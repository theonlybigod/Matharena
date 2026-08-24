--[[
	ArenaScreenController.client.lua

	The arena's giant central "MATHARENA" screen is the PRIMARY public
	gameplay display AND the primary input surface, for both competitive
	turns and Practice Mode - visible from both sides. Message 25 extends
	this (previously question/timer/round display only) to also carry the
	answer input (AnswerBox/SubmitButton) and, for Practice Mode, the exit
	button - everything that used to live in a popup on the player's own
	screen now lives here instead.

	This is still purely a presentation change - it listens to the exact
	same authoritative RemoteEvents CompetitionUIController/
	PracticeUIController already used (TurnStarted/TurnResolved for
	competitive, PracticeQuestionStarted/PracticeQuestionResolved/
	PracticeStateChanged for practice), and writes to the SAME screen
	instance's two faces (CenterStage.lua's QuestionScreen, tagged
	"QuestionScreen"). No new remotes, no new server logic, no duplicate
	question/answer system - CompetitionGameplay/PracticeSystem (server)
	remain the only authority on what the question/timer/active-contestant
	actually are; this script only ever displays what it's told and
	forwards the local player's answer through the exact same
	SubmitAnswer/PracticeSubmitAnswer/LeavePracticeMode RemoteEvents as
	before.

	INPUT PRIVACY (kept intact from the old popup design): the AnswerBox/
	SubmitButton/LeavePracticeButton instances are real, shared, server-
	built Instances - every client sees the same physical screen. But
	their Visible state and Text are only ever set LOCALLY, by each
	client's own copy of this script, and Roblox never replicates a
	client-side Instance property write to the server or to other
	clients. So this client only ever shows/enables the input row for
	ITSELF, and only when IT is the active contestant/practicer - no
	other player's screen is affected, and nothing here lets a client
	claim to be someone it isn't (the server still separately validates
	who's allowed to submit, exactly as before).

	KNOWN LIMITATION (documented, not silently ignored): the screen is one
	shared physical object. If a competitive match is actively running
	(TurnStarted firing) at the same moment a completely different player
	starts a solo Practice session on a spare platform, only ONE of the
	two can occupy the screen's text at a time. This script gives the
	competitive match priority (a real match with spectators/leaderboard
	stakes) - a concurrent practicer's OWN answer input still works via
	this same screen once the competitive match isn't actively mid-turn,
	but during an actively-running competitive turn, a simultaneous
	practicer will not see their own question rendered on the shared
	screen. This is a genuine architectural tradeoff for a single shared
	public screen, not a bug being papered over.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)

local player = Players.LocalPlayer

local ACCENT_COLOR = Color3.fromRGB(70, 150, 230)
local SUCCESS_COLOR = Color3.fromRGB(80, 220, 130)
local ERROR_COLOR = Color3.fromRGB(230, 80, 80)

-- The screen is built once, at server start, before any player could
-- possibly need it - a short wait here is just startup-order safety, not
-- a retry loop.
local screen = (CollectionService:GetTagged("QuestionScreen")[1] :: BasePart?)
	or Workspace:WaitForChild("Arena"):WaitForChild("CenterStage"):WaitForChild("QuestionScreen")

local faces = {}
for _, gui in ipairs(screen:GetChildren()) do
	if gui:IsA("SurfaceGui") and gui.Name == "ScreenGui" then
		local background = gui:WaitForChild("Background")
		-- Message 28 visual overhaul restructured these into nested
		-- containers (HeaderBar/QuestionCard/FooterBar) for a proper framed
		-- layout - WaitForChild only searches DIRECT children, so labels
		-- that moved into a nested container have to be looked up through
		-- that container now, not straight off Background.
		local headerBar = background:WaitForChild("HeaderBar")
		local questionCard = background:WaitForChild("QuestionCard")
		local footerBar = background:WaitForChild("FooterBar")
		local answerBox = background:WaitForChild("AnswerBox") :: TextBox
		local submitButton = background:WaitForChild("SubmitButton") :: TextButton
		table.insert(faces, {
			idle = background:WaitForChild("IdleLabel"),
			contestant = headerBar:WaitForChild("ContestantLabel"),
			question = questionCard:WaitForChild("QuestionLabel"),
			questionCard = questionCard,
			timer = footerBar:WaitForChild("TimerLabel"),
			round = footerBar:WaitForChild("RoundLabel"),
			answerBox = answerBox,
			answerBoxStroke = answerBox:WaitForChild("AnswerBoxStroke") :: UIStroke,
			submitButton = submitButton,
			submitButtonStroke = submitButton:WaitForChild("SubmitButtonStroke") :: UIStroke,
			leavePracticeButton = background:WaitForChild("LeavePracticeButton") :: TextButton,
		})
	end
end

-- "Session" here means whichever of competitive/practice currently owns
-- the shared screen - see the KNOWN LIMITATION note above. Competitive
-- always wins if both are simultaneously trying to render.
local activeSession: "Competitive" | "Practice" | nil = nil

local function setVisible(turnActive: boolean, showLeavePractice: boolean, canAnswer: boolean, isSpectatingCompetitive: boolean?)
	for _, face in ipairs(faces) do
		face.idle.Visible = not turnActive
		face.contestant.Visible = turnActive
		face.question.Visible = turnActive
		face.timer.Visible = turnActive
		face.round.Visible = turnActive
		-- The currently-active contestant/practicer sees a normal, editable
		-- answer box (this client, for itself - see module doc comment on
		-- why that's safe). Message 34 ("show the rest of the players what
		-- they see on their working area"): a competitive SPECTATOR now also
		-- sees the answer box, but read-only (TextEditable=false) - its Text
		-- is mirrored from the active player's own typing via the
		-- AnswerTypingUpdate relay below, never locally editable for anyone
		-- but the active player.
		face.answerBox.Visible = turnActive and (canAnswer or (isSpectatingCompetitive == true))
		face.answerBox.TextEditable = canAnswer
		face.submitButton.Visible = turnActive and canAnswer
		face.leavePracticeButton.Visible = turnActive and showLeavePractice and canAnswer
		if not turnActive then
			face.answerBox.Text = ""
		end
	end
end

local function setText(contestantText: string, questionText: string, roundText: string)
	for _, face in ipairs(faces) do
		face.contestant.Text = contestantText
		face.question.Text = questionText
		face.round.Text = roundText
	end
end

local function setTimerText(text: string, color: Color3)
	for _, face in ipairs(faces) do
		face.timer.Text = text
		face.timer.TextColor3 = color
	end
end

-- ===== Answer submission (fires whichever remote matches the current
-- session - SubmitAnswer for a real match, PracticeSubmitAnswer for
-- practice - the exact same RemoteEvents/server validation as before) =====

local function submitAnswer()
	for _, face in ipairs(faces) do
		if face.answerBox.Visible and face.answerBox.Text ~= "" then
			local remoteName = if activeSession == "Practice" then "PracticeSubmitAnswer" else "SubmitAnswer"
			RemoteEvents.Get(remoteName):FireServer(face.answerBox.Text)
			for _, f in ipairs(faces) do
				f.answerBox.Text = ""
			end
			return
		end
	end
end

-- ===== Message 29: engaging answer-input feedback ("make the way you
-- type your answer more engaging... visually react when typing...
-- animate when focused... satisfying submit interaction") =====

for _, face in ipairs(faces) do
	-- Glowing focus feedback: the answer box's border brightens and
	-- thickens while the player is actively typing, and eases back when
	-- they click away - makes typing feel like an active part of the
	-- presentation rather than a plain text field.
	face.answerBox.Focused:Connect(function()
		TweenService:Create(face.answerBoxStroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			Transparency = 0.1,
			Thickness = 3,
		}):Play()
	end)
	-- Message 34: throttled relay of this client's own typed text to
	-- spectators (via AnswerTypingUpdate), ONLY while this client is the
	-- genuinely active competitive contestant (face.answerBox.TextEditable
	-- is only ever true for the active player - see setVisible above).
	-- Client-side min-interval check here is just to cut down on needless
	-- network chatter on fast typing; the server independently throttles
	-- and re-validates the sender regardless (CompetitionGameplay.lua).
	local lastTypingRelayClock = 0
	face.answerBox:GetPropertyChangedSignal("Text"):Connect(function()
		-- A quick, subtle scale "tick" on every keystroke - immediate visual
		-- confirmation that input is registering, without being distracting.
		if not face.answerBox:IsFocused() then
			return
		end
		local originalSize = face.answerBox.Size
		TweenService:Create(face.answerBox, TweenInfo.new(0.06, Enum.EasingStyle.Quad), {
			Size = originalSize + UDim2.fromOffset(0, 3),
		}):Play()
		task.delay(0.06, function()
			TweenService:Create(face.answerBox, TweenInfo.new(0.08, Enum.EasingStyle.Quad), {
				Size = originalSize,
			}):Play()
		end)

		if activeSession == "Competitive" and face.answerBox.TextEditable then
			local now = os.clock()
			if now - lastTypingRelayClock >= 0.12 then
				lastTypingRelayClock = now
				RemoteEvents.Get("AnswerTypingUpdate"):FireServer(face.answerBox.Text)
			end
		end
	end)
	face.answerBox.FocusLost:Connect(function()
		TweenService:Create(face.answerBoxStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
			Transparency = 0.7,
			Thickness = 2,
		}):Play()
	end)

	-- Submit button: a real hover/press scale animation (this screen's
	-- buttons never had one before - every other panel in the project
	-- does, via UITheme.ApplyButtonHoverEffect) plus a bright flash-pulse
	-- on click, so submitting reads as a deliberate, satisfying action.
	local submitOriginalSize = face.submitButton.Size
	face.submitButton.MouseEnter:Connect(function()
		TweenService:Create(face.submitButton, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
			Size = submitOriginalSize + UDim2.fromOffset(6, 4),
		}):Play()
	end)
	face.submitButton.MouseLeave:Connect(function()
		TweenService:Create(face.submitButton, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
			Size = submitOriginalSize,
		}):Play()
	end)

	-- ===== Actual submit wiring (click, Enter-to-submit, exit practice) =====
	face.submitButton.MouseButton1Click:Connect(function()
		-- A quick, bright flash-pulse on the button itself the instant it's
		-- pressed - immediate, satisfying confirmation the submission
		-- registered, independent of whatever the server eventually decides.
		TweenService:Create(face.submitButton, TweenInfo.new(0.08, Enum.EasingStyle.Quad), {
			Size = submitOriginalSize - UDim2.fromOffset(4, 3),
		}):Play()
		face.submitButtonStroke.Thickness = 4
		face.submitButtonStroke.Transparency = 0.2
		TweenService:Create(face.submitButtonStroke, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
			Transparency = 1,
		}):Play()
		task.delay(0.08, function()
			TweenService:Create(face.submitButton, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {
				Size = submitOriginalSize,
			}):Play()
		end)
		submitAnswer()
	end)
	face.answerBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitAnswer()
		end
	end)
	face.leavePracticeButton.MouseButton1Click:Connect(function()
		RemoteEvents.Get("LeavePracticeMode"):FireServer()
	end)
end

-- ===== Local countdown display (visual only; the server enforces the
-- real timeout independently) =====

local countdownConnection: RBXScriptConnection? = nil
local countdownDeadlineClock: number? = nil
local TIMER_GOLD = Color3.fromRGB(255, 205, 60)

local function stopCountdown()
	if countdownConnection then
		countdownConnection:Disconnect()
		countdownConnection = nil
	end
	countdownDeadlineClock = nil
end

local function startCountdown(seconds: number)
	stopCountdown()
	countdownDeadlineClock = os.clock() + seconds
	setTimerText(("%.1fs"):format(seconds), TIMER_GOLD)

	countdownConnection = RunService.RenderStepped:Connect(function()
		if not countdownDeadlineClock then
			return
		end
		local remaining = math.max(0, countdownDeadlineClock - os.clock())
		setTimerText(("%.1fs"):format(remaining), TIMER_GOLD)
		if remaining <= 0 then
			stopCountdown()
		end
	end)
end

-- ===== Message 29: correct/incorrect feedback flash - a brief colored
-- pulse on the question card's own border, on top of the existing timer-
-- text feedback, so the result reads as a genuine game-show "ding/buzz"
-- moment rather than just a text color change. =====
local function flashResultBorder(isCorrect: boolean)
	local color = if isCorrect then SUCCESS_COLOR else ERROR_COLOR
	for _, face in ipairs(faces) do
		local stroke = face.questionCard:FindFirstChildOfClass("UIStroke")
		if not stroke then
			continue
		end
		local originalColor = stroke.Color
		stroke.Color = color
		stroke.Thickness = 5
		stroke.Transparency = 0
		local tween = TweenService:Create(stroke, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 0.6,
			Thickness = 2,
		})
		tween:Play()
		tween.Completed:Connect(function()
			stroke.Color = originalColor
		end)
	end
end

-- ===== Message 34: mirrors the active contestant's live-typed answer to
-- every OTHER client (spectators only - the active player already sees
-- their own typing locally, and the server never relays a message for
-- anyone but the genuinely active contestant, see CompetitionGameplay.lua) =====
RemoteEvents.Get("AnswerTypingUpdate").OnClientEvent:Connect(function(activePlayerUserId: number, text: string)
	if activeSession ~= "Competitive" or activePlayerUserId == player.UserId then
		return
	end
	for _, face in ipairs(faces) do
		if face.answerBox.Visible and not face.answerBox.TextEditable then
			face.answerBox.Text = text
		end
	end
end)

-- ===== Competitive match remote handlers =====

RemoteEvents.Get("TurnStarted").OnClientEvent:Connect(function(payload)
	if not payload then
		if activeSession == "Competitive" then
			activeSession = nil
			setVisible(false, false, false)
			stopCountdown()
		end
		return
	end

	-- Competitive always takes ownership of the shared screen - see the
	-- module doc comment's KNOWN LIMITATION.
	activeSession = "Competitive"
	setText(
		("%s \u{2014} %s"):format(payload.playerName, payload.category),
		payload.questionText,
		("Round %d \u{2022} %d Left"):format(payload.round, payload.playersRemaining)
	)
	local isMyTurn = payload.playerUserId == player.UserId
	setVisible(true, false, isMyTurn, not isMyTurn)
	startCountdown(payload.timerSeconds)
end)

RemoteEvents.Get("TurnResolved").OnClientEvent:Connect(function(payload)
	if activeSession ~= "Competitive" then
		return
	end
	stopCountdown()
	for _, face in ipairs(faces) do
		face.answerBox.Visible = false
		face.submitButton.Visible = false
	end
	flashResultBorder(payload.correct)
	if payload.correct then
		setTimerText("Correct!", SUCCESS_COLOR)
	else
		local reason = payload.timedOut and "Time's up!" or "Wrong!"
		setTimerText(("%s Answer: %s"):format(reason, tostring(payload.correctAnswer)), ERROR_COLOR)
	end
end)

-- ===== Practice Mode remote handlers =====
-- Practice is always a solo session for whichever client is running it -
-- there is no "is this my turn" check needed the way competitive has one,
-- since PracticeStateChanged/PracticeQuestionStarted only ever fire for
-- the practicing player's own client in the first place.

RemoteEvents.Get("PracticeStateChanged").OnClientEvent:Connect(function(data)
	if not data or not data.active then
		if activeSession == "Practice" then
			activeSession = nil
			setVisible(false, false, false)
			stopCountdown()
		end
		return
	end

	if activeSession == "Competitive" then
		return -- a real match currently owns the shared screen - see KNOWN LIMITATION
	end
	activeSession = "Practice"
end)

RemoteEvents.Get("PracticeQuestionStarted").OnClientEvent:Connect(function(payload)
	if not payload or activeSession ~= "Practice" then
		return
	end
	setText("PRACTICE", payload.questionText, "Question " .. tostring(payload.questionNumber))
	setVisible(true, true, true)
	-- Infinite Time practice: the server sends a negative sentinel instead
	-- of a real duration (see PracticeSystem.INFINITE_TIME_SENTINEL) - show
	-- an infinity symbol and never start a local countdown, rather than
	-- trying to tick down from a negative number. The answer/submit flow
	-- below is completely unaffected either way.
	if payload.timerSeconds and payload.timerSeconds > 0 then
		startCountdown(payload.timerSeconds)
	else
		stopCountdown()
		setTimerText("\u{221E}", TIMER_GOLD)
	end
end)

RemoteEvents.Get("PracticeQuestionResolved").OnClientEvent:Connect(function(payload)
	if not payload or activeSession ~= "Practice" then
		return
	end
	stopCountdown()
	for _, face in ipairs(faces) do
		face.answerBox.Visible = false
		face.submitButton.Visible = false
	end
	flashResultBorder(payload.correct)
	if payload.correct then
		setTimerText("Correct!", SUCCESS_COLOR)
	elseif payload.timedOut then
		setTimerText(("Time's up! Answer: %s"):format(tostring(payload.correctAnswer)), TIMER_GOLD)
	else
		setTimerText(("Wrong! Answer: %s"):format(tostring(payload.correctAnswer)), ERROR_COLOR)
	end
end)
