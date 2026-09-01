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
	button (RequestManualPractice) - never automatically.

	Practice TYPE ("what type of practice you want", chosen from the
	popup shown when pressing Practice - see PracticeUIController.client.lua):
		"Regular"   - normal timer, taken straight from the same round+
		              category formula a competitive match uses
		              (GameplayConfig.GetTimerSeconds).
		"ExtraTime" - the SAME base timer, multiplied by a player-chosen
		              factor of 2x-5x (practiceTimeMultiplier), OR
		              Infinite Time (practiceInfiniteTime = true), which
		              removes the per-question countdown/timeout entirely
		              without touching the normal answer/result flow - a
		              player can still submit at any time, they just never
		              get auto-resolved by a timeout.
	Server-authoritative: the client only ever REQUESTS one of these two
	exact strings plus (for "ExtraTime") a multiplier number 2-5 or the
	literal string "Infinite" - the server clamps/validates and applies
	the actual timer math below, exactly as it already owned every other
	timing value.

	The popup flow is Type (Regular/ExtraTime) -> [ExtraTime only: pick a
	multiplier or Infinite] -> Difficulty (the same five GameplayConfig.
	QUEUE_TIERS the Play button's tier-select popup uses) -> practice
	actually starts. The chosen tier's `startingRound` feeds
	`practiceQuestionNumber`'s starting point exactly the same way
	MatchSystem seeds a competitive match's starting round from a queue
	tier.

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
local DifficultyCurriculum = require(ReplicatedStorage.Modules.DifficultyCurriculum)
local RewardsConfig = require(ReplicatedStorage.Modules.RewardsConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)

local DataSystem = require(ServerScriptService.DataSystem)
local ProgressionSystem = require(ServerScriptService.ProgressionSystem)
local MatchSystem = require(ServerScriptService.MatchSystem)
local RemoteThrottle = require(ServerScriptService.RemoteThrottle)
local QuestsSystem = require(ServerScriptService.QuestsSystem)

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

-- Sent to the client in place of a real timerSeconds value whenever
-- Infinite Time is active - negative, so any naive client code that just
-- checks `timerSeconds and timerSeconds > 0` before starting a countdown
-- safely treats it as "no timer" without needing to know this sentinel by
-- name (ArenaScreenController.client.lua does exactly that).
local INFINITE_TIME_SENTINEL = -1

-- ===== Active practice state (at most one practice session at a time is
-- typical, since practice is opt-in per player, but nothing here assumes
-- exactly one player is online) =====

local practicePlayer: Player? = nil
local practicePlatform: Model? = nil
local practiceQuestionNumber = 0
local practiceTierId: number? = nil -- the difficulty tier picked from the Practice popup - caps how far practiceQuestionNumber is ever allowed to climb, see GameplayConfig.AdvanceRoundForTier
local currentQuestion: QuestionGenerator.Question? = nil
local turnStartClock: number? = nil
local turnTimerSeconds: number? = nil
local turnGeneration = 0
local endPracticeAfterCurrentQuestion = false

local VALID_PRACTICE_MODES = { Regular = true, ExtraTime = true }
local practiceMode: string = "Regular"
local practiceTimeMultiplier: number = 1 -- ExtraTime only: 2-5
local practiceInfiniteTime: boolean = false -- ExtraTime only: Infinite Time selected

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

	-- Capped by the chosen practice tier (an Easy Mode practice session
	-- stays genuinely Easy for however long the player keeps going - it
	-- can get harder WITHIN its own band, but a long session must never
	-- drift into a harder tier's categories, e.g. Exponents, just because
	-- the player answered enough questions in a row).
	--[[
		Practice climbs its own difficulty's rounds 1-10 and then stays there,
		the same clamp competitive matches use. Each difficulty owns its own
		ladder now, so an Easy practice session replays Easy round 10 forever
		rather than drifting into a harder tier's number ranges - the guarantee
		the old per-tier maxRound ceiling used to provide.
	]]
	practiceQuestionNumber = math.min(practiceQuestionNumber + 1, DifficultyCurriculum.ROUNDS_PER_DIFFICULTY)
	turnGeneration += 1
	local myTurnGeneration = turnGeneration

	--[[
		Same curriculum a competitive match uses, with the practice question
		counter acting as the round within the CHOSEN difficulty's own ladder.

		Practice deliberately does NOT apply the correct-streak timer decay -
		that is a competitive pressure mechanic, and Practice exists to be the
		no-stakes surface. The base time is the flat curriculum baseline (or a
		form's own override), then Extra Time Mode's 2x-5x multiplier on top,
		or Infinite Time which drops the countdown entirely.
	]]
	local difficultyDef = DifficultyCurriculum.DIFFICULTIES[practiceTierId or 1] or DifficultyCurriculum.DIFFICULTIES[1]
	local question = QuestionGenerator.Generate(difficultyDef.id, practiceQuestionNumber)
	local difficulty = difficultyDef.name

	local baseTimerSeconds = question.seconds or DifficultyCurriculum.BASE_SECONDS
	local timerSeconds = if practiceInfiniteTime then nil else baseTimerSeconds * practiceTimeMultiplier

	currentQuestion = question
	turnStartClock = os.clock()
	turnTimerSeconds = timerSeconds -- nil while Infinite Time is active

	practiceQuestionStartedEvent:FireClient(practicePlayer, {
		questionNumber = practiceQuestionNumber,
		questionText = question.text,
		difficulty = difficulty,
		timerSeconds = if timerSeconds then timerSeconds else INFINITE_TIME_SENTINEL,
	})

	if timerSeconds then
		local watchedPlayer = practicePlayer
		task.delay(timerSeconds, function()
			if turnGeneration ~= myTurnGeneration then
				return -- already resolved (answered) or practice ended
			end
			PracticeSystem.ResolveTurn(watchedPlayer, false, true)
		end)
	end
	-- Infinite Time: deliberately no task.delay scheduled at all - the
	-- ONLY way this question resolves is a real submitted answer, via
	-- onPracticeSubmitAnswer below. The normal answer/result flow
	-- (ResolveTurn, stats, XP, the resolve pause) is completely unchanged.
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
		-- Quest progress ("Practice Makes Perfect" - practice correct
		-- answers) moves via RecordPracticeQuestionAnswer above - check
		-- right after, same reasoning as CompetitionGameplay's own check.
		QuestsSystem.CheckForNewlyCompleted(player)
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
	Starts Practice Mode for `player`, via the lobby's Practice Mode button
	(RequestManualPractice) - the only way Practice Mode ever starts.
	Valid any time this player isn't currently an active competitive match
	participant (never pull them out of a real match). Removes them from
	the queue first if they were in it.

	`requestedMode` is one of VALID_PRACTICE_MODES's keys ("Regular",
	"ExtraTime") - anything else (a stale/malicious client) silently falls
	back to "Regular" rather than erroring, same defensive pattern as
	every other client-supplied value in this project.

	`requestedTierId` is one of GameplayConfig.QUEUE_TIERS' ids (1-5, Easy
	Mode through Master Mode) - anything else falls back to tier 1.
	Determines which round practiceQuestionNumber starts counting from.

	`requestedExtraTime` only matters when requestedMode == "ExtraTime":
	either a number (clamped to 2-5, the per-question time multiplier) or
	the literal string "Infinite" (removes the per-question timer
	entirely). Anything else falls back to a 2x multiplier - never
	silently drops back to "Regular" behavior just because this one extra
	argument was malformed.
]]
function PracticeSystem.StartPractice(player: Player, requestedMode: string?, requestedTierId: number?, requestedExtraTime: (number | string)?)
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

	local tier = GameplayConfig.GetQueueTier(requestedTierId or 1)

	practicePlayer = player
	practiceTierId = tier.id
	-- beginNextPracticeQuestion advances BEFORE generating, so seeding one
	-- below the tier's starting round makes the very first question land
	-- exactly on tier.startingRound.
	-- Every difficulty now owns its own rounds 1-10, so practice always
	-- begins at round 1 of the CHOSEN difficulty rather than at an offset
	-- into a shared ladder. Seeded at 0 because beginNextPracticeQuestion
	-- increments before generating.
	practiceQuestionNumber = 0
	endPracticeAfterCurrentQuestion = false
	practiceMode = if requestedMode and VALID_PRACTICE_MODES[requestedMode] then requestedMode else "Regular"

	if practiceMode == "ExtraTime" then
		if requestedExtraTime == "Infinite" then
			practiceInfiniteTime = true
			practiceTimeMultiplier = 1
		elseif typeof(requestedExtraTime) == "number" then
			practiceInfiniteTime = false
			practiceTimeMultiplier = math.clamp(math.floor(requestedExtraTime), 2, 5)
		else
			practiceInfiniteTime = false
			practiceTimeMultiplier = 2
		end
	else
		practiceInfiniteTime = false
		practiceTimeMultiplier = 1
	end

	local assignments = Teleporter.AssignPlatforms({ player })
	practicePlatform = assignments[player]

	practiceStateChangedEvent:FireClient(player, {
		active = true,
		platformIndex = practicePlatform and practicePlatform:GetAttribute("PlatformIndex"),
		mode = practiceMode,
		timeMultiplier = practiceTimeMultiplier,
		infiniteTime = practiceInfiniteTime,
	})

	print(
		("[PracticeSystem] Practice started for %s (mode: %s%s)"):format(
			player.Name,
			practiceMode,
			if practiceMode == "ExtraTime"
				then (if practiceInfiniteTime then ", Infinite Time" else (", " .. tostring(practiceTimeMultiplier) .. "x"))
				else ""
		)
	)
	beginNextPracticeQuestion()
end

local function onRequestManualPractice(player: Player, requestedMode: unknown, requestedTierId: unknown, requestedExtraTime: unknown)
	if not RemoteThrottle.Check(player, "RequestManualPractice", 1) then
		return
	end
	PracticeSystem.StartPractice(
		player,
		if typeof(requestedMode) == "string" then requestedMode else nil,
		if typeof(requestedTierId) == "number" then requestedTierId else nil,
		if typeof(requestedExtraTime) == "number" or typeof(requestedExtraTime) == "string" then requestedExtraTime else nil
	)
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
