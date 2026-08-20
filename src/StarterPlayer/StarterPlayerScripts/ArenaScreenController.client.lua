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

local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)

local player = Players.LocalPlayer

-- The screen is built once, at server start, before any player could
-- possibly need it - a short wait here is just startup-order safety, not
-- a retry loop.
local screen = (CollectionService:GetTagged("QuestionScreen")[1] :: BasePart?)
	or Workspace:WaitForChild("Arena"):WaitForChild("CenterStage"):WaitForChild("QuestionScreen")

local faces = {}
for _, gui in ipairs(screen:GetChildren()) do
	if gui:IsA("SurfaceGui") and gui.Name == "ScreenGui" then
		local background = gui:WaitForChild("Background")
		table.insert(faces, {
			idle = background:WaitForChild("IdleLabel"),
			contestant = background:WaitForChild("ContestantLabel"),
			question = background:WaitForChild("QuestionLabel"),
			timer = background:WaitForChild("TimerLabel"),
			round = background:WaitForChild("RoundLabel"),
			answerBox = background:WaitForChild("AnswerBox") :: TextBox,
			submitButton = background:WaitForChild("SubmitButton") :: TextButton,
			leavePracticeButton = background:WaitForChild("LeavePracticeButton") :: TextButton,
		})
	end
end

-- "Session" here means whichever of competitive/practice currently owns
-- the shared screen - see the KNOWN LIMITATION note above. Competitive
-- always wins if both are simultaneously trying to render.
local activeSession: "Competitive" | "Practice" | nil = nil

local function setVisible(turnActive: boolean, showLeavePractice: boolean, canAnswer: boolean)
	for _, face in ipairs(faces) do
		face.idle.Visible = not turnActive
		face.contestant.Visible = turnActive
		face.question.Visible = turnActive
		face.timer.Visible = turnActive
		face.round.Visible = turnActive
		-- Only the currently-active contestant/practicer (this client, for
		-- itself) ever sees the input row - see the module doc comment on
		-- why this is safe and doesn't leak to other clients.
		face.answerBox.Visible = turnActive and canAnswer
		face.submitButton.Visible = turnActive and canAnswer
		face.leavePracticeButton.Visible = turnActive and showLeavePractice and canAnswer
		if not (turnActive and canAnswer) then
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

for _, face in ipairs(faces) do
	face.submitButton.MouseButton1Click:Connect(submitAnswer)
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
	setVisible(true, false, isMyTurn)
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
	if payload.correct then
		setTimerText("Correct!", Color3.fromRGB(80, 220, 130))
	else
		local reason = payload.timedOut and "Time's up!" or "Wrong!"
		setTimerText(("%s Answer: %s"):format(reason, tostring(payload.correctAnswer)), Color3.fromRGB(230, 80, 80))
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
	startCountdown(payload.timerSeconds)
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
	if payload.correct then
		setTimerText("Correct!", Color3.fromRGB(80, 220, 130))
	elseif payload.timedOut then
		setTimerText(("Time's up! Answer: %s"):format(tostring(payload.correctAnswer)), TIMER_GOLD)
	else
		setTimerText(("Wrong! Answer: %s"):format(tostring(payload.correctAnswer)), Color3.fromRGB(230, 80, 80))
	end
end)
