--[[
	CompetitionGameplay

	Server-authoritative spelling-bee-style question rotation: selects one
	contestant at a time, sends everyone (contestant + spectators) the
	question, enforces a difficulty-based timer, validates the submitted
	answer, and eliminates on a wrong answer or timeout. When only one
	contestant remains, declares them the winner via MatchSystem.EndMatch.

	Starts a round automatically when MatchSystem transitions to "Playing"
	(via MatchSystem.OnStateChanged) and cleans up if the match ends any
	other way. Reacts to disconnects via MatchSystem.OnParticipantRemoved
	so a departing contestant's turn doesn't stall waiting for a timeout
	that will never resolve.

	Camera focus, question/timer display, and sending SubmitAnswer are all
	client-side (StarterPlayer). This module never trusts the client for
	anything except "here is my answer" - and only accepts that from
	whoever it currently considers the active player, once per turn.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameplayConfig = require(ReplicatedStorage.Modules.GameplayConfig)
local MatchConfig = require(ReplicatedStorage.Modules.MatchConfig)
local RewardsConfig = require(ReplicatedStorage.Modules.RewardsConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)

local MatchSystem = require(ServerScriptService.MatchSystem)
local ProgressionSystem = require(ServerScriptService.ProgressionSystem)

local QuestionGenerator = require(script.QuestionGenerator)
local Elimination = require(script.Elimination)

local CompetitionGameplay = {}

local turnStartedEvent = RemoteEvents.Get("TurnStarted")
local turnResolvedEvent = RemoteEvents.Get("TurnResolved")
local submitAnswerEvent = RemoteEvents.Get("SubmitAnswer")
local rosterUpdatedEvent = RemoteEvents.Get("RosterUpdated")

local roundActive = false
local alivePlayers: { Player } = {}
local currentTurnIndex = 0
local roundNumber = 1
local turnGeneration = 0

local activePlayer: Player? = nil
local currentQuestion: QuestionGenerator.Question? = nil
local turnStartClock: number? = nil
local turnTimerSeconds: number? = nil

type RosterEntry = {
	userId: number,
	name: string,
	rank: string,
	platformIndex: number?,
	alive: boolean,
}
local rosterStatus: { [Player]: RosterEntry } = {}

local resolveTurn: (isCorrect: boolean, timedOut: boolean, myGeneration: number) -> ()

local function buildRosterList(): { RosterEntry }
	local list = {}
	for _, entry in pairs(rosterStatus) do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b)
		return (a.platformIndex or 0) < (b.platformIndex or 0)
	end)
	return list
end

local function broadcastRoster()
	rosterUpdatedEvent:FireAllClients(buildRosterList())
end

local function markEliminatedInRoster(player: Player)
	local entry = rosterStatus[player]
	if entry then
		entry.alive = false
	end
end

local function removeFromAliveList(player: Player): number?
	for i, p in ipairs(alivePlayers) do
		if p == player then
			table.remove(alivePlayers, i)
			return i
		end
	end
	return nil
end

local function clearTurnUI()
	turnStartedEvent:FireAllClients(nil)
end

local function cleanupRound()
	turnGeneration += 1 -- invalidate any pending timeout watcher
	roundActive = false
	activePlayer = nil
	currentQuestion = nil
	turnStartClock = nil
	alivePlayers = {}
	currentTurnIndex = 0
	table.clear(rosterStatus)
	broadcastRoster()
	clearTurnUI()
end

local function beginTurnAt(index: number)
	turnGeneration += 1
	local myGeneration = turnGeneration

	activePlayer = alivePlayers[index]
	local player = activePlayer :: Player

	local question = QuestionGenerator.Generate(roundNumber)
	currentQuestion = question
	turnStartClock = os.clock()

	local difficulty = GameplayConfig.GetDifficultyForRound(roundNumber)
	local timerSeconds = GameplayConfig.TIMER_SECONDS[difficulty]
	turnTimerSeconds = timerSeconds
	local platform = MatchSystem.GetPlatformForPlayer(player)

	turnStartedEvent:FireAllClients({
		playerUserId = player.UserId,
		playerName = player.Name,
		platformIndex = platform and platform:GetAttribute("PlatformIndex"),
		questionText = question.text,
		category = question.category,
		difficulty = difficulty,
		timerSeconds = timerSeconds,
		round = roundNumber,
		playersRemaining = #alivePlayers,
	})

	task.spawn(function()
		task.wait(timerSeconds)
		if turnGeneration == myGeneration then
			resolveTurn(false, true, myGeneration)
		end
	end)
end

local function advanceAndBeginNextTurn(currentAlreadyRemoved: boolean)
	if #alivePlayers == 0 then
		cleanupRound()
		MatchSystem.EndMatch(nil)
		return
	end

	if #alivePlayers == 1 then
		local winner = alivePlayers[1]

		-- Perfect Game bonus (Message 9): reaching this branch means every
		-- OTHER contestant was removed from alivePlayers by answering
		-- incorrectly or timing out (see resolveTurn's `not isCorrect`
		-- branch) - the only way to leave this list. `winner` was never
		-- removed, so they provably never answered a question incorrectly
		-- in this match; on top of the Win reward (granted separately by
		-- MatchSystem.EndMatch, which covers every match-ending path
		-- uniformly), they additionally earn the Perfect Game bonus here,
		-- since only this module has the information needed to know that.
		ProgressionSystem.AwardXP(winner, RewardsConfig.PERFECT_GAME_BONUS_XP)

		cleanupRound()
		MatchSystem.EndMatch(winner)
		return
	end

	if not currentAlreadyRemoved then
		currentTurnIndex += 1
	end
	if currentTurnIndex > #alivePlayers then
		currentTurnIndex = 1
		roundNumber += 1
	end

	beginTurnAt(currentTurnIndex)
end

resolveTurn = function(isCorrect: boolean, timedOut: boolean, myGeneration: number)
	if myGeneration ~= turnGeneration then
		return -- superseded by the other resolution path (answer vs. timeout race)
	end
	turnGeneration += 1

	local player = activePlayer :: Player
	local correctAnswer = currentQuestion.answer
	local elapsed = turnStartClock and (os.clock() - turnStartClock) or nil
	local timerSecondsForThisTurn = turnTimerSeconds

	activePlayer = nil
	currentQuestion = nil
	turnStartClock = nil
	turnTimerSeconds = nil

	turnResolvedEvent:FireAllClients({
		playerUserId = player.UserId,
		correct = isCorrect,
		timedOut = timedOut,
		correctAnswer = correctAnswer,
	})

	ProgressionSystem.RecordQuestionAnswer(player, isCorrect, if isCorrect then elapsed else nil)

	-- Correct-answer economy (Message 9): base reward every time, plus a
	-- fast-answer bonus if it came in under a fraction of the turn's
	-- allotted time (proportional, since the timer varies by difficulty).
	if isCorrect then
		ProgressionSystem.AwardXP(player, RewardsConfig.CORRECT_ANSWER_XP)
		ProgressionSystem.AwardCoins(player, RewardsConfig.CORRECT_ANSWER_COINS)

		if elapsed and timerSecondsForThisTurn and elapsed <= timerSecondsForThisTurn * RewardsConfig.FAST_ANSWER_TIME_FRACTION then
			ProgressionSystem.AwardCoins(player, RewardsConfig.FAST_ANSWER_BONUS_COINS)
		end
	end

	local removedNow = false
	if not isCorrect then
		local platform = MatchSystem.GetPlatformForPlayer(player)
		if platform then
			Elimination.SetPlatformGray(platform)
		end
		Elimination.MoveToSpectatorSeat(player)
		removeFromAliveList(player)
		markEliminatedInRoster(player)
		broadcastRoster()
		removedNow = true
	end

	task.wait(GameplayConfig.RESOLVE_DISPLAY_SECONDS)

	if not roundActive then
		return -- match ended some other way (e.g. a disconnect forfeit) while we were paused
	end

	advanceAndBeginNextTurn(removedNow)
end

local function startRound()
	roundActive = true
	alivePlayers = MatchSystem.GetParticipants()
	currentTurnIndex = 0
	roundNumber = 1
	Elimination.RestoreAllPlatformColors()
	QuestionGenerator.ResetUsedQuestions()
	table.clear(rosterStatus)

	for _, player in ipairs(alivePlayers) do
		local platform = MatchSystem.GetPlatformForPlayer(player)
		local leaderstats = player:FindFirstChild("leaderstats")
		local rank = leaderstats and (leaderstats:FindFirstChild("Rank") :: StringValue?)
		rosterStatus[player] = {
			userId = player.UserId,
			name = player.Name,
			rank = rank and rank.Value or "Unranked",
			platformIndex = platform and platform:GetAttribute("PlatformIndex"),
			alive = true,
		}
	end
	broadcastRoster()

	if #alivePlayers < MatchConfig.MIN_PLAYERS then
		-- Shouldn't normally happen (MatchSystem already enforces the
		-- minimum before launching), but stay safe rather than looping.
		cleanupRound()
		return
	end

	advanceAndBeginNextTurn(false)
end

--[[
	Handles a quiz-alive contestant disconnecting mid-round. Subscribed to
	MatchSystem.OnParticipantRemoved at Init, so this fires automatically -
	nothing else needs to call it directly.
]]
function CompetitionGameplay.HandlePlayerLeaving(player: Player)
	if not roundActive then
		return
	end

	if player == activePlayer then
		turnGeneration += 1 -- cancel the pending timeout watcher for this turn
		activePlayer = nil
		currentQuestion = nil
		turnStartClock = nil
		removeFromAliveList(player)
		markEliminatedInRoster(player)
		broadcastRoster()
		advanceAndBeginNextTurn(true)
		return
	end

	local removedIndex = removeFromAliveList(player)
	if removedIndex then
		markEliminatedInRoster(player)
		broadcastRoster()
		if removedIndex < currentTurnIndex then
			currentTurnIndex -= 1
		end
	end
end

local function onSubmitAnswer(player: Player, rawAnswer: unknown)
	if not roundActive or player ~= activePlayer or not currentQuestion then
		return
	end

	local answer = tonumber(rawAnswer)
	if not answer then
		return -- ignore non-numeric input rather than penalizing malformed submissions
	end

	local myGeneration = turnGeneration
	local isCorrect = QuestionGenerator.CheckAnswer(currentQuestion, answer)
	resolveTurn(isCorrect, false, myGeneration)
end

function CompetitionGameplay.Init()
	submitAnswerEvent.OnServerEvent:Connect(onSubmitAnswer)

	MatchSystem.OnStateChanged(function(newState: string)
		if newState == MatchConfig.GameState.Playing then
			startRound()
		elseif roundActive then
			cleanupRound()
		end
	end)

	MatchSystem.OnParticipantRemoved(function(player: Player)
		CompetitionGameplay.HandlePlayerLeaving(player)
	end)

	print("[CompetitionGameplay] Initialized")
end

return CompetitionGameplay
