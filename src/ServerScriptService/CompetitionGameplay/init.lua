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
local DifficultyCurriculum = require(ReplicatedStorage.Modules.DifficultyCurriculum)
local MatchConfig = require(ReplicatedStorage.Modules.MatchConfig)
local RewardsConfig = require(ReplicatedStorage.Modules.RewardsConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)

local MatchSystem = require(ServerScriptService.MatchSystem)
local ProgressionSystem = require(ServerScriptService.ProgressionSystem)
local RemoteThrottle = require(ServerScriptService.RemoteThrottle)
local QuestsSystem = require(ServerScriptService.QuestsSystem)

local QuestionGenerator = require(script.QuestionGenerator)
local Elimination = require(script.Elimination)

local CompetitionGameplay = {}

local turnStartedEvent = RemoteEvents.Get("TurnStarted")
local turnResolvedEvent = RemoteEvents.Get("TurnResolved")
local submitAnswerEvent = RemoteEvents.Get("SubmitAnswer")
local rosterUpdatedEvent = RemoteEvents.Get("RosterUpdated")
local answerTypingUpdateEvent = RemoteEvents.Get("AnswerTypingUpdate")

local roundActive = false
local alivePlayers: { Player } = {}
local currentTurnIndex = 0
local roundNumber = 1
local currentTierId: number? = nil -- the queue tier this match was launched from - caps how far roundNumber is ever allowed to climb, see GameplayConfig.AdvanceRoundForTier
local turnGeneration = 0

local activePlayer: Player? = nil
local currentQuestion: QuestionGenerator.Question? = nil
local turnStartClock: number? = nil
local turnTimerSeconds: number? = nil

--[[
	ROUND = ONE FULL ROTATION, OR A WRONG ANSWER.

	`turnsThisRound` counts turns taken since the round began; once it
	reaches the number of contestants still alive, everyone has answered
	once and the round is over.

	A wrong answer ALSO ends the round, via `pendingRoundAdvance`. Crucially
	it does not restart the rotation - `currentTurnIndex` keeps moving from
	wherever it was, so the next player after the eliminated one takes the
	first turn of the new round rather than play snapping back to contestant
	one.

	`correctStreak` drives the per-turn timer decay from round 5 onward (see
	GameplayConfig.GetTurnSeconds). It counts consecutive correct answers
	across the whole match and is reset to zero by any wrong answer, which
	is what puts the next player back on the full base time.
]]
local turnsThisRound = 0
local pendingRoundAdvance = false
local correctStreak = 0
local currentDifficultyId: string? = nil

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
	turnsThisRound = 0
	pendingRoundAdvance = false
	correctStreak = 0
	table.clear(rosterStatus)
	broadcastRoster()
	clearTurnUI()
end

local function beginTurnAt(index: number)
	turnGeneration += 1
	local myGeneration = turnGeneration

	activePlayer = alivePlayers[index]
	local player = activePlayer :: Player

	local question = QuestionGenerator.Generate(currentDifficultyId, roundNumber)
	currentQuestion = question
	turnStartClock = os.clock()

	--[[
		Display label. This must come from the MATCH's difficulty, not from the
		round number - each difficulty now owns rounds 1-10, so the old
		GetDifficultyForRound(roundNumber) would have labelled round 1 of a
		Master match "Easy", since it read a round number against a ladder that
		no longer exists.
	]]
	local difficulty = (DifficultyCurriculum.Get(currentDifficultyId)).name

	--[[
		Timer. One flat base for every difficulty (DifficultyCurriculum.BASE_SECONDS),
		overridden per question only where reading is genuinely part of the
		cost - ratios, exponent operations, Master word problems all carry
		their own `seconds`.

		From round 5 the base is then scaled down by the running correct
		streak, compounding 10% per correct answer. This replaced the old
		GetTimerSeconds(round, category), which interpolated a per-tier anchor
		table - that made sense when all five tiers shared one round ladder,
		but each difficulty now owns its own rounds 1-10, so a per-round anchor
		curve would be measuring the wrong thing.
	]]
	local baseSeconds = question.seconds or DifficultyCurriculum.BASE_SECONDS
	local timerSeconds = GameplayConfig.GetTurnSeconds(baseSeconds, correctStreak, roundNumber)
	turnTimerSeconds = timerSeconds
	turnsThisRound += 1
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
	end

	--[[
		Advance the round on either ending condition: a completed rotation, or
		a wrong answer (flagged in resolveTurn). Note this deliberately does
		NOT reset currentTurnIndex - the rotation carries on from where it
		was, so an elimination mid-rotation does not send play back to the
		first contestant.

		Clamped to the difficulty's own last round: a long elimination on Easy
		Mode keeps replaying Easy round 10 rather than drifting into number
		ranges that belong to a harder tier. This is the same guarantee the
		old per-tier maxRound ceiling gave, expressed against the new
		per-difficulty ladder.
	]]
	if pendingRoundAdvance or turnsThisRound >= #alivePlayers then
		roundNumber = math.min(roundNumber + 1, DifficultyCurriculum.ROUNDS_PER_DIFFICULTY)
		turnsThisRound = 0
		pendingRoundAdvance = false
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

	-- Timer decay bookkeeping. A correct answer lengthens the streak, so the
	-- next player gets 10% less time (from round 5); a wrong answer clears
	-- it outright, putting the next player back on the full base time, and
	-- ends the round.
	if isCorrect then
		correctStreak += 1
	else
		correctStreak = 0
		pendingRoundAdvance = true
	end

	ProgressionSystem.RecordQuestionAnswer(player, isCorrect, if isCorrect then elapsed else nil)

	-- Message 34: quest progress ("Quick Thinker" - combined correct
	-- answers) moves via the exact same RecordQuestionAnswer call above -
	-- check right after, so an accepted quest that just became claimable
	-- notifies the player immediately rather than waiting for their next
	-- quest-box poll.
	QuestsSystem.CheckForNewlyCompleted(player)

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
	-- Difficulty tiers (Play redesign): a match starts at whichever round
	-- the queued tier maps to (GameplayConfig.QUEUE_TIERS), not always
	-- round 1 - a harder tier just means "begin further along the SAME
	-- round-based progression", not a separate difficulty system. Falls
	-- back to round 1 if, for any reason, no tier was recorded (shouldn't
	-- normally happen - MatchSystem always claims a tier before a match can
	-- ever reach Playing).
	--[[
		Every difficulty now starts at ITS OWN round 1, rather than at an
		offset into one shared ladder. Queue tier ids 1-5 line up with
		DifficultyCurriculum.DIFFICULTIES in order (Easy, Medium, Hard, Expert,
		Master), so the tier chooses WHICH curriculum runs, not where in a
		common curve the match begins.
	]]
	local tierId = MatchSystem.GetCurrentTier()
	currentTierId = tierId
	local difficultyDef = DifficultyCurriculum.DIFFICULTIES[tierId or 1] or DifficultyCurriculum.DIFFICULTIES[1]
	currentDifficultyId = difficultyDef.id
	roundNumber = 1
	turnsThisRound = 0
	pendingRoundAdvance = false
	correctStreak = 0
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

	-- Defense-in-depth: reject absurdly long input before even attempting
	-- tonumber() (which is itself safe on any string, but there's no
	-- legitimate reason an answer needs to be longer than this).
	if typeof(rawAnswer) == "string" and #rawAnswer > 32 then
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

--[[
	Message 34 ("show the rest of the players what they see on their
	working area"): relays the ACTIVE contestant's live-typed answer text
	(not yet submitted) to every other client, so spectators watching the
	shared arena screen see the same digits appear in real time, matching
	what the active player is actually typing - without ever exposing
	correctness/validation info (this only ever carries the raw typed
	text, nothing about whether it's right, and CheckAnswer/the correct
	answer are never part of this payload).

	Server-validated, not just relayed blindly: only ever relays a message
	from whoever this server ALREADY considers the genuinely active
	contestant (player == activePlayer) - a non-active client's attempt to
	spoof typing text for someone else is silently ignored, same defensive
	posture as onSubmitAnswer above. Same length cap and throttle pattern
	as everywhere else client input is trusted.
]]
local function onAnswerTypingUpdate(player: Player, rawText: unknown)
	if not roundActive or player ~= activePlayer then
		return
	end
	if typeof(rawText) ~= "string" or #rawText > 32 then
		return
	end
	if not RemoteThrottle.Check(player, "AnswerTypingUpdate", 0.1) then
		return
	end
	answerTypingUpdateEvent:FireAllClients(player.UserId, rawText)
end

function CompetitionGameplay.Init()
	submitAnswerEvent.OnServerEvent:Connect(onSubmitAnswer)
	answerTypingUpdateEvent.OnServerEvent:Connect(onAnswerTypingUpdate)

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
