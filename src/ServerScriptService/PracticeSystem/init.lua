--[[
	PracticeSystem

	Practice Mode: a manually-chosen (via the lobby's Practice Mode button),
	infinite, non-competitive practice loop on a real arena contestant
	platform, using the SAME QuestionGenerator/GameplayConfig/Teleporter
	that competitive matches use - no duplicate question system, timer
	system, or arena. Practice never touches MatchSystem's Queue/GameState
	machinery, competitive Wins/Statistics, or Reward milestones; it has
	its own practiceStatistics bucket on the profile and a small,
	deliberately-capped XP trickle (RewardsConfig.PRACTICE_CORRECT_ANSWER_XP)
	instead of coins.

	Practice Mode is manual-only: it starts ONLY via the lobby's Practice
	button (RequestManualPractice) - "just make players choose by pressing
	the Practice button when they want to play" - never automatically. An
	earlier version of this system auto-started practice for a lone player
	after a 10-second countdown, with a "Practice Mode starts in..." banner
	on their screen; that entire mechanic (both the server-side timer and
	the client countdown UI) has been removed rather than just hidden, so a
	solo player is never pulled into practice without explicitly choosing
	to.

	Self-contained: owns its own Players.PlayerAdded/PlayerRemoving
	connections (same pattern as RemoteThrottle) rather than requiring
	GameManager to know about it.

	Transition rules (never interrupt mid-question):
		- A 2nd player joining WHILE a practice session is active does not end
		  it right away; a flag is set and checked right after the current
		  question resolves, so the player always finishes what they're
		  looking at. Only then are both players handed to
		  MatchSystem.TryJoinQueue (no button needed on their end).
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

local practiceStateChangedEvent = RemoteEvents.Get("PracticeStateChanged")
local practiceQuestionStartedEvent = RemoteEvents.Get("PracticeQuestionStarted")
local practiceQuestionResolvedEvent = RemoteEvents.Get("PracticeQuestionResolved")
local leavePracticeModeEvent = RemoteEvents.Get("LeavePracticeMode")
local practiceSubmitAnswerEvent = RemoteEvents.Get("PracticeSubmitAnswer")
local requestManualPracticeEvent = RemoteEvents.Get("RequestManualPractice")

-- ===== Active practice state (at most one practice session at a time is
-- typical, since practice is opt-in per player, but nothing here assumes
-- exactly one player is online) =====

local practicePlayer: Player? = nil
local practicePlatform: Model? = nil
local practiceQuestionNumber = 0
local currentQuestion: QuestionGenerator.Question? = nil
local turnStartClock: number? = nil
local turnTimerSeconds: number? = nil
local turnGeneration = 0
local endPracticeAfterCurrentQuestion = false

-- Practice mode variants ("what type of practice you want", chosen from
-- the popup shown when pressing Practice - see PracticeUIController.client.lua):
--   "Regular"    - normal timer, normal between-question pause.
--   "DoubleTime" - each question's timer is doubled - more breathing
--                  room to work through harder questions while training.
--   "NoCooldown" - the between-question result-display pause
--                  (GameplayConfig.RESOLVE_DISPLAY_SECONDS) is skipped
--                  entirely, so the next question starts immediately -
--                  rapid-fire reps with no downtime.
-- Server-authoritative: the client only ever REQUESTS one of these three
-- exact strings; the server clamps/validates and applies the actual
-- timer/pause math below, exactly as it already owned every other timing
-- value.
local VALID_PRACTICE_MODES = { Regular = true, DoubleTime = true, NoCooldown = true }
local practiceMode: string = "Regular"

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
		-- normal matchmaking, no button needed on their end.
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
	-- "DoubleTime" mode: exactly what it says - double the usual per-
	-- question timer, the only difference from Regular mode's timing.
	local timerSeconds = GameplayConfig.TIMER_SECONDS[difficulty] * (if practiceMode == "DoubleTime" then 2 else 1)

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

	task.wait(if practiceMode == "NoCooldown" then 0 else GameplayConfig.RESOLVE_DISPLAY_SECONDS)

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
	Starts Practice Mode for `player`, via the lobby's Practice Mode button
	(RequestManualPractice) - the only way Practice Mode ever starts.
	Valid any time this player isn't currently an active competitive match
	participant (never pull them out of a real match) - other players being
	online doesn't prevent this player from practicing (section 10 from an
	earlier prompt: "players waiting may enter Practice Mode"). Removes
	them from the queue first if they were in it.

	`requestedMode` is one of VALID_PRACTICE_MODES's keys ("Regular",
	"DoubleTime", "NoCooldown") - anything else (a stale/malicious client)
	silently falls back to "Regular" rather than erroring, same defensive
	pattern as every other client-supplied value in this project.
]]
function PracticeSystem.StartPractice(player: Player, requestedMode: string?)
	if not player.Parent then
		return
	end
	if practicePlayer then
		return -- already practicing (shouldn't happen, but don't double-start)
	end
	if MatchSystem.IsParticipant(player) then
		return -- currently in an active competitive match - never pull them out
	end

	MatchSystem.LeaveQueue(player)

	practicePlayer = player
	practiceQuestionNumber = 0
	endPracticeAfterCurrentQuestion = false
	practiceMode = if requestedMode and VALID_PRACTICE_MODES[requestedMode] then requestedMode else "Regular"

	local assignments = Teleporter.AssignPlatforms({ player })
	practicePlatform = assignments[player]

	practiceStateChangedEvent:FireClient(player, {
		active = true,
		platformIndex = practicePlatform and practicePlatform:GetAttribute("PlatformIndex"),
		mode = practiceMode,
	})

	print(("[PracticeSystem] Practice started for %s (mode: %s)"):format(player.Name, practiceMode))
	beginNextPracticeQuestion()
end

local function onRequestManualPractice(player: Player, requestedMode: unknown)
	if not RemoteThrottle.Check(player, "RequestManualPractice", 1) then
		return
	end
	PracticeSystem.StartPractice(player, if typeof(requestedMode) == "string" then requestedMode else nil)
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

-- ===== Population tracking (drives the "end practice after this
-- question" handoff when a second player becomes available) =====

--[[
	`count` is passed explicitly rather than read fresh from
	Players:GetPlayers() here, since PlayerRemoving fires WHILE the
	leaving player is still counted there - callers compute the correct
	post-event population themselves (see call sites below).
]]
local function onPopulationChanged(count: number)
	if practicePlayer and count >= 2 then
		endPracticeAfterCurrentQuestion = true
	end
end

local function onPlayerRemoving(player: Player)
	if player == practicePlayer then
		endPractice("Disconnected")
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

	print("[PracticeSystem] Initialized")
end

return PracticeSystem
