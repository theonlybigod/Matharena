--[[
	PracticeSystem

	Solo-player Practice Mode: if exactly one player is online for
	MatchConfig.SOLO_PRACTICE_WAIT_SECONDS, they're auto-placed into an
	infinite, non-competitive practice loop on a real arena contestant
	platform, using the SAME QuestionGenerator/GameplayConfig/Teleporter
	that competitive matches use - no duplicate question system, timer
	system, or arena. Practice never touches MatchSystem's Queue/GameState
	machinery, competitive Wins/Statistics, or Reward milestones; it has
	its own practiceStatistics bucket on the profile and a small,
	deliberately-capped XP trickle (RewardsConfig.PRACTICE_CORRECT_ANSWER_XP)
	instead of coins.

	Self-contained: owns its own Players.PlayerAdded/PlayerRemoving
	connections (same pattern as RemoteThrottle) rather than requiring
	GameManager to know about it.

	Transition rules (never interrupt mid-question):
		- A 2nd player joining during the 10s solo countdown cancels it
		  immediately - no practice starts, normal matchmaking proceeds.
		- A 2nd player joining WHILE a SOLO (automatic) practice session is
		  active does not end it right away; a flag is set and checked right
		  after the current question resolves, so the player always finishes
		  what they're looking at. Only then are both players handed to
		  MatchSystem.TryJoinQueue (no button needed, mirroring how solo
		  practice itself starts without a button).
		- MANUAL practice (started via the lobby's Practice Mode button) does
		  NOT auto-end when other players join/queue - a player who chooses
		  to practice while others are around isn't blocking anyone else's
		  matchmaking (they already left the queue to practice, if they were
		  in it), so there's nothing to "free up" by ending it. It only ends
		  via Exit Practice or a disconnect. `isSoloSession` tracks which
		  kind the active session is.
		- Manually clicking "Leave/Exit Practice" ends it immediately (no
		  question to protect against interrupting there - it's the
		  player's own explicit choice).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MatchConfig = require(ReplicatedStorage.Modules.MatchConfig)
local GameplayConfig = require(ReplicatedStorage.Modules.GameplayConfig)
local RewardsConfig = require(ReplicatedStorage.Modules.RewardsConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)

local DataSystem = require(ServerScriptService.DataSystem)
local ProgressionSystem = require(ServerScriptService.ProgressionSystem)
local MatchSystem = require(ServerScriptService.MatchSystem)
local RemoteThrottle = require(ServerScriptService.RemoteThrottle)

local QuestionGenerator = require(ServerScriptService.CompetitionGameplay.QuestionGenerator)
local Teleporter = require(ServerScriptService.MatchSystem.Teleporter)

local PracticeSystem = {}

local GameState = MatchConfig.GameState

local soloWaitUpdateEvent = RemoteEvents.Get("SoloWaitUpdate")
local practiceStateChangedEvent = RemoteEvents.Get("PracticeStateChanged")
local practiceQuestionStartedEvent = RemoteEvents.Get("PracticeQuestionStarted")
local practiceQuestionResolvedEvent = RemoteEvents.Get("PracticeQuestionResolved")
local leavePracticeModeEvent = RemoteEvents.Get("LeavePracticeMode")
local practiceSubmitAnswerEvent = RemoteEvents.Get("PracticeSubmitAnswer")
local requestManualPracticeEvent = RemoteEvents.Get("RequestManualPractice")

-- ===== Solo-wait state =====

local soloWaitGeneration = 0
local soloWaitPlayer: Player? = nil

-- ===== Active practice state (at most one practice session at a time,
-- since practice only ever starts when the whole server has exactly 1
-- player) =====

local practicePlayer: Player? = nil
local practicePlatform: Model? = nil
local practiceQuestionNumber = 0
local currentQuestion: QuestionGenerator.Question? = nil
local turnStartClock: number? = nil
local turnTimerSeconds: number? = nil
local turnGeneration = 0
local endPracticeAfterCurrentQuestion = false
-- true only for the AUTOMATIC solo-wait-triggered session; false for a
-- manually-started one (see the module doc comment's transition rules).
local isSoloSession = false

local function cancelSoloWait()
	if soloWaitPlayer then
		soloWaitUpdateEvent:FireClient(soloWaitPlayer, nil)
	end
	soloWaitGeneration += 1
	soloWaitPlayer = nil
end

local function startSoloWait(player: Player)
	soloWaitGeneration += 1
	local myGeneration = soloWaitGeneration
	soloWaitPlayer = player

	task.spawn(function()
		for remaining = MatchConfig.SOLO_PRACTICE_WAIT_SECONDS, 0, -1 do
			if soloWaitGeneration ~= myGeneration then
				return -- cancelled (someone joined/left, or state changed)
			end
			soloWaitUpdateEvent:FireClient(player, remaining)
			if remaining > 0 then
				task.wait(1)
			end
		end

		if soloWaitGeneration ~= myGeneration then
			return
		end

		soloWaitPlayer = nil
		PracticeSystem.StartPractice(player)
	end)
end

-- ===== Practice question loop =====

local function clearPracticeStatDisplayPayload(player: Player)
	local profile = DataSystem.GetProfile(player)
	if not profile then
		return nil
	end
	return table.clone(profile.practiceStatistics)
end

local function endPractice(reason: string)
	local endedPlayer = practicePlayer
	local endedPlatform = practicePlatform

	turnGeneration += 1 -- invalidate any in-flight timeout watcher
	currentQuestion = nil
	turnStartClock = nil
	turnTimerSeconds = nil
	practicePlayer = nil
	practicePlatform = nil
	endPracticeAfterCurrentQuestion = false

	if endedPlatform then
		Teleporter.ClearPlatform(endedPlatform)
	end

	if endedPlayer and endedPlayer.Parent then
		Teleporter.ReturnToLobby({ endedPlayer })
		practiceStateChangedEvent:FireClient(endedPlayer, { active = false })
	end

	print(("[PracticeSystem] Practice ended for %s (%s)"):format(endedPlayer and endedPlayer.Name or "?", reason))
end

local function beginNextPracticeQuestion()
	if not practicePlayer or not practicePlayer.Parent then
		endPractice("PlayerGone")
		return
	end

	if endPracticeAfterCurrentQuestion then
		local endedPlayer = practicePlayer
		endPractice("SecondPlayerJoined")
		-- Hand both the ex-practice player and whoever's now online back to
		-- normal matchmaking, no button needed - mirrors how solo practice
		-- itself starts without one. (Only reachable for a solo session -
		-- see onPopulationChanged, which never sets this flag for a manual one.)
		if endedPlayer and endedPlayer.Parent then
			MatchSystem.TryJoinQueue(endedPlayer)
		end
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer ~= endedPlayer then
				MatchSystem.TryJoinQueue(otherPlayer)
			end
		end
		return
	end

	practiceQuestionNumber += 1
	turnGeneration += 1
	local myTurnGeneration = turnGeneration

	-- Reuses the EXACT same round-based difficulty/category progression
	-- competitive matches use (GameplayConfig), feeding the practice
	-- question counter in as the "round" - rounds 1-7 already ramp
	-- Easy -> Medium -> Hard -> Expert and arithmetic -> mixed ->
	-- percentages/fractions -> harder categories, matching the requested
	-- progression without a second, incompatible difficulty table.
	local question = QuestionGenerator.Generate(practiceQuestionNumber)
	local difficulty = GameplayConfig.GetDifficultyForRound(practiceQuestionNumber)
	local timerSeconds = GameplayConfig.TIMER_SECONDS[difficulty]

	currentQuestion = question
	turnStartClock = os.clock()
	turnTimerSeconds = timerSeconds

	practiceQuestionStartedEvent:FireClient(practicePlayer, {
		questionNumber = practiceQuestionNumber,
		questionText = question.text,
		difficulty = difficulty,
		timerSeconds = timerSeconds,
	})

	local watchedPlayer = practicePlayer
	task.delay(timerSeconds, function()
		if turnGeneration ~= myTurnGeneration then
			return -- already resolved (answered) or practice ended
		end
		PracticeSystem.ResolveTurn(watchedPlayer, false, true)
	end)
end

--[[
	Resolves the current practice question. `isCorrect`/`timedOut` are
	server-determined (isCorrect via QuestionGenerator.CheckAnswer, never
	trusted from the client). Safe to call redundantly - the turnGeneration
	guard means only the FIRST caller (an on-time answer or the timeout,
	whichever the server processes first) actually resolves anything.
]]
function PracticeSystem.ResolveTurn(player: Player, isCorrect: boolean, timedOut: boolean)
	if player ~= practicePlayer or not currentQuestion then
		return
	end

	local question = currentQuestion
	local elapsed = turnStartClock and (os.clock() - turnStartClock) or nil
	local correctAnswer = question.answer

	turnGeneration += 1 -- invalidates the timeout watcher / a late duplicate answer
	currentQuestion = nil
	turnStartClock = nil
	turnTimerSeconds = nil

	ProgressionSystem.RecordPracticeQuestionAnswer(player, isCorrect, if isCorrect then elapsed else nil)
	if isCorrect then
		ProgressionSystem.AwardXP(player, RewardsConfig.PRACTICE_CORRECT_ANSWER_XP)
	end

	practiceQuestionResolvedEvent:FireClient(player, {
		correct = isCorrect,
		timedOut = timedOut,
		correctAnswer = correctAnswer,
		stats = clearPracticeStatDisplayPayload(player),
	})

	task.wait(GameplayConfig.RESOLVE_DISPLAY_SECONDS)

	if player == practicePlayer then
		beginNextPracticeQuestion()
	end
end

local function onPracticeSubmitAnswer(player: Player, rawAnswer: unknown)
	if player ~= practicePlayer or not currentQuestion then
		return
	end
	if not RemoteThrottle.Check(player, "PracticeSubmitAnswer", 0.2) then
		return
	end

	local submitted = tonumber(rawAnswer)
	if submitted == nil then
		return
	end

	local isCorrect = QuestionGenerator.CheckAnswer(currentQuestion, submitted)
	PracticeSystem.ResolveTurn(player, isCorrect, false)
end

--[[
	Starts Practice Mode for `player`.

	AUTOMATIC (isManual=false/nil, from the solo-wait timer): only valid
	while the whole server has exactly this one player and no competitive
	match is forming (state Lobby/Waiting).

	MANUAL (isManual=true, from the lobby's Practice Mode button): valid
	any time this player isn't currently an active match participant and no
	match is forming FOR THEM specifically - the population check is
	skipped since other players being online doesn't prevent this player
	from practicing (section 10: "players waiting may enter Practice
	Mode"). Removes them from the queue first if they were in it.
]]
function PracticeSystem.StartPractice(player: Player, isManual: boolean?)
	if not player.Parent then
		return
	end
	if practicePlayer then
		return -- already practicing (shouldn't happen, but don't double-start)
	end
	if MatchSystem.IsParticipant(player) then
		return -- currently in an active competitive match - never pull them out
	end

	if isManual then
		MatchSystem.LeaveQueue(player)
	else
		if #Players:GetPlayers() ~= 1 then
			return
		end
		local state = MatchSystem.GetState()
		if state ~= GameState.Lobby and state ~= GameState.Waiting then
			return
		end
	end

	practicePlayer = player
	practiceQuestionNumber = 0
	endPracticeAfterCurrentQuestion = false
	isSoloSession = not isManual

	local assignments = Teleporter.AssignPlatforms({ player })
	practicePlatform = assignments[player]

	practiceStateChangedEvent:FireClient(player, {
		active = true,
		platformIndex = practicePlatform and practicePlatform:GetAttribute("PlatformIndex"),
	})

	print(("[PracticeSystem] Practice started for %s (%s)"):format(player.Name, if isManual then "manual" else "solo"))
	beginNextPracticeQuestion()
end

local function onRequestManualPractice(player: Player)
	if not RemoteThrottle.Check(player, "RequestManualPractice", 1) then
		return
	end
	if player == soloWaitPlayer then
		cancelSoloWait()
	end
	PracticeSystem.StartPractice(player, true)
end

local function onLeavePracticeRequest(player: Player)
	if player ~= practicePlayer then
		return
	end
	if not RemoteThrottle.Check(player, "LeavePracticeMode", 1) then
		return
	end
	endPractice("ManualLeave")
end

-- ===== Population tracking (drives both solo-wait and the "end practice
-- after this question" handoff) =====

--[[
	`count` is passed explicitly rather than read fresh from
	Players:GetPlayers() here, since PlayerRemoving fires WHILE the
	leaving player is still counted there - callers compute the correct
	post-event population themselves (see call sites below).
]]
local function onPopulationChanged(count: number)
	if count ~= 1 then
		cancelSoloWait()
	end

	if practicePlayer then
		-- Only a SOLO session needs to end when someone else becomes
		-- available - a manual session isn't blocking anyone (see module
		-- doc comment).
		if isSoloSession and count >= 2 then
			endPracticeAfterCurrentQuestion = true
		end
		return
	end

	-- Waiting counts too, not just Lobby - a lone player who's still
	-- technically queued (e.g. after a countdown got cancelled when their
	-- opponent left) should still get the automatic solo-practice fallback.
	local matchState = MatchSystem.GetState()
	if count == 1 and (matchState == GameState.Lobby or matchState == GameState.Waiting) and not soloWaitPlayer then
		local onlyPlayer = Players:GetPlayers()[1]
		if onlyPlayer then
			startSoloWait(onlyPlayer)
		end
	end
end

local function onPlayerRemoving(player: Player)
	if player == practicePlayer then
		endPractice("Disconnected")
	end
	if player == soloWaitPlayer then
		cancelSoloWait()
	end
	-- PlayerRemoving fires before the player is actually removed from the
	-- Players service, so the population AFTER this departure is one less
	-- than what GetPlayers() reports right now.
	onPopulationChanged(#Players:GetPlayers() - 1)
end

function PracticeSystem.Init()
	Players.PlayerAdded:Connect(function()
		onPopulationChanged(#Players:GetPlayers())
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	leavePracticeModeEvent.OnServerEvent:Connect(onLeavePracticeRequest)
	practiceSubmitAnswerEvent.OnServerEvent:Connect(onPracticeSubmitAnswer)
	requestManualPracticeEvent.OnServerEvent:Connect(onRequestManualPractice)

	task.defer(function()
		onPopulationChanged(#Players:GetPlayers())
	end) -- handles a solo player already online when the server starts

	print("[PracticeSystem] Initialized")
end

return PracticeSystem
