--[[
	PracticeUIController.client.lua

	Solo-wait countdown + Practice Mode UI/camera. Purely presentational -
	the server (PracticeSystem) decides everything (when practice starts,
	question correctness, timing); this script only displays what it's
	told and forwards the local player's answer/leave request.

	Reuses the existing Match/Competition visual language (UITheme) rather
	than inventing a new style, and the existing competition camera-focus
	pattern (see CompetitionUIController) for "smoothly move the camera to
	the active platform".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local UITheme = require(ReplicatedStorage.Modules.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")
local camera = Workspace.CurrentCamera

local soloWaitUpdateEvent = RemoteEvents.Get("SoloWaitUpdate")
local practiceStateChangedEvent = RemoteEvents.Get("PracticeStateChanged")
local practiceQuestionStartedEvent = RemoteEvents.Get("PracticeQuestionStarted")
local practiceQuestionResolvedEvent = RemoteEvents.Get("PracticeQuestionResolved")
local leavePracticeModeEvent = RemoteEvents.Get("LeavePracticeMode")
local practiceSubmitAnswerEvent = RemoteEvents.Get("PracticeSubmitAnswer")
local requestManualPracticeEvent = RemoteEvents.Get("RequestManualPractice")
local queueUpdatedEvent = RemoteEvents.Get("QueueUpdated")

local lobbyButtonBar = mainUI:WaitForChild("LobbyButtonBar")
local practiceButton = lobbyButtonBar:WaitForChild("PracticeButton") :: TextButton

-- Tracked purely so clicking Practice while queued can show a confirm
-- step instead of silently pulling the player out (section 9) - updated
-- from the same QueueUpdated broadcast MatchSystem already sends.
local amIQueued = false
queueUpdatedEvent.OnClientEvent:Connect(function(payload)
	amIQueued = payload and payload.waitingNames and table.find(payload.waitingNames, player.Name) ~= nil
end)

-- ===== Solo-wait banner =====

local soloWaitFrame = Instance.new("Frame")
soloWaitFrame.Name = "SoloWaitBanner"
soloWaitFrame.Size = UDim2.fromOffset(360, 110)
soloWaitFrame.Position = UDim2.new(0.5, -180, 0, 24)
soloWaitFrame.Visible = false
UITheme.StylePanel(soloWaitFrame, 0.1)
soloWaitFrame.Parent = mainUI

local soloWaitTitle = Instance.new("TextLabel")
soloWaitTitle.Name = "Title"
soloWaitTitle.Size = UDim2.new(1, -16, 0, 26)
soloWaitTitle.Position = UDim2.fromOffset(8, 8)
soloWaitTitle.BackgroundTransparency = 1
soloWaitTitle.Font = Enum.Font.GothamBold
soloWaitTitle.TextScaled = true
soloWaitTitle.TextColor3 = UITheme.COLORS.Accent
soloWaitTitle.Text = "WAITING FOR PLAYERS"
soloWaitTitle.Parent = soloWaitFrame

local soloWaitCount = Instance.new("TextLabel")
soloWaitCount.Name = "Count"
soloWaitCount.Size = UDim2.new(1, -16, 0, 22)
soloWaitCount.Position = UDim2.fromOffset(8, 36)
soloWaitCount.BackgroundTransparency = 1
soloWaitCount.Font = Enum.Font.Gotham
soloWaitCount.TextScaled = true
soloWaitCount.TextColor3 = UITheme.COLORS.SubText
soloWaitCount.Text = "1 / 2 PLAYERS"
soloWaitCount.Parent = soloWaitFrame

local soloWaitCountdown = Instance.new("TextLabel")
soloWaitCountdown.Name = "Countdown"
soloWaitCountdown.Size = UDim2.new(1, -16, 0, 34)
soloWaitCountdown.Position = UDim2.fromOffset(8, 64)
soloWaitCountdown.BackgroundTransparency = 1
soloWaitCountdown.Font = Enum.Font.GothamBlack
soloWaitCountdown.TextScaled = true
soloWaitCountdown.TextColor3 = UITheme.COLORS.Gold
soloWaitCountdown.Text = ""
soloWaitCountdown.Parent = soloWaitFrame

soloWaitUpdateEvent.OnClientEvent:Connect(function(secondsRemaining: number?)
	if secondsRemaining == nil then
		soloWaitFrame.Visible = false
		return
	end
	soloWaitFrame.Visible = true
	soloWaitCountdown.Text = ("Practice Mode starts in: %d"):format(secondsRemaining)
end)

-- ===== Practice HUD =====

local practiceFrame = Instance.new("Frame")
practiceFrame.Name = "PracticeHUD"
practiceFrame.Size = UDim2.fromOffset(420, 260)
practiceFrame.Position = UDim2.new(0.5, -210, 0, 16)
practiceFrame.Visible = false
UITheme.StylePanel(practiceFrame, 0.1)
practiceFrame.Parent = mainUI

local practiceTitle = Instance.new("TextLabel")
practiceTitle.Name = "Title"
practiceTitle.Size = UDim2.new(1, -16, 0, 28)
practiceTitle.Position = UDim2.fromOffset(8, 8)
practiceTitle.BackgroundTransparency = 1
practiceTitle.Font = Enum.Font.GothamBlack
practiceTitle.TextScaled = true
practiceTitle.TextColor3 = UITheme.COLORS.Accent
practiceTitle.Text = "PRACTICE MODE"
practiceTitle.Parent = practiceFrame

local questionNumberLabel = Instance.new("TextLabel")
questionNumberLabel.Name = "QuestionNumber"
questionNumberLabel.Size = UDim2.new(1, -16, 0, 20)
questionNumberLabel.Position = UDim2.fromOffset(8, 38)
questionNumberLabel.BackgroundTransparency = 1
questionNumberLabel.Font = Enum.Font.Gotham
questionNumberLabel.TextScaled = true
questionNumberLabel.TextColor3 = UITheme.COLORS.SubText
questionNumberLabel.Text = ""
questionNumberLabel.Parent = practiceFrame

local questionTextLabel = Instance.new("TextLabel")
questionTextLabel.Name = "QuestionText"
questionTextLabel.Size = UDim2.new(1, -16, 0, 50)
questionTextLabel.Position = UDim2.fromOffset(8, 60)
questionTextLabel.BackgroundTransparency = 1
questionTextLabel.Font = Enum.Font.GothamBlack
questionTextLabel.TextScaled = true
questionTextLabel.TextColor3 = UITheme.COLORS.Text
questionTextLabel.Text = ""
questionTextLabel.Parent = practiceFrame

local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "Timer"
timerLabel.Size = UDim2.new(1, -16, 0, 30)
timerLabel.Position = UDim2.fromOffset(8, 112)
timerLabel.BackgroundTransparency = 1
timerLabel.Font = Enum.Font.GothamBold
timerLabel.TextScaled = true
timerLabel.TextColor3 = UITheme.COLORS.Gold
timerLabel.Text = ""
timerLabel.Parent = practiceFrame

local statsLabel = Instance.new("TextLabel")
statsLabel.Name = "Stats"
statsLabel.Size = UDim2.new(1, -16, 0, 44)
statsLabel.Position = UDim2.fromOffset(8, 146)
statsLabel.BackgroundTransparency = 1
statsLabel.Font = Enum.Font.Gotham
statsLabel.TextSize = 15
statsLabel.TextXAlignment = Enum.TextXAlignment.Left
statsLabel.TextWrapped = true
statsLabel.TextColor3 = UITheme.COLORS.SubText
statsLabel.Text = ""
statsLabel.Parent = practiceFrame

local practiceAnswerBox = Instance.new("TextBox")
practiceAnswerBox.Name = "AnswerBox"
practiceAnswerBox.Size = UDim2.fromOffset(160, 36)
practiceAnswerBox.Position = UDim2.fromOffset(8, 196)
practiceAnswerBox.Font = Enum.Font.Gotham
practiceAnswerBox.TextScaled = true
practiceAnswerBox.PlaceholderText = "Your answer"
practiceAnswerBox.TextColor3 = Color3.fromRGB(20, 20, 25)
practiceAnswerBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
practiceAnswerBox.ClearTextOnFocus = false
UITheme.ApplyCorner(practiceAnswerBox)
practiceAnswerBox.Parent = practiceFrame

local practiceSubmitButton = Instance.new("TextButton")
practiceSubmitButton.Name = "SubmitButton"
practiceSubmitButton.Size = UDim2.fromOffset(110, 36)
practiceSubmitButton.Position = UDim2.fromOffset(176, 196)
practiceSubmitButton.Font = Enum.Font.GothamBold
practiceSubmitButton.TextScaled = true
practiceSubmitButton.Text = "Submit"
practiceSubmitButton.TextColor3 = UITheme.COLORS.Text
practiceSubmitButton.BackgroundColor3 = UITheme.COLORS.Accent
UITheme.ApplyCorner(practiceSubmitButton)
UITheme.ApplyButtonHoverEffect(practiceSubmitButton)
practiceSubmitButton.Parent = practiceFrame

local leavePracticeButton = Instance.new("TextButton")
leavePracticeButton.Name = "LeavePracticeButton"
leavePracticeButton.Size = UDim2.fromOffset(180, 36)
leavePracticeButton.Position = UDim2.fromOffset(8, 216)
leavePracticeButton.Font = Enum.Font.GothamBold
leavePracticeButton.TextScaled = true
leavePracticeButton.Text = "LEAVE PRACTICE"
leavePracticeButton.TextColor3 = UITheme.COLORS.Text
leavePracticeButton.BackgroundColor3 = UITheme.COLORS.Error
leavePracticeButton.ZIndex = 2
UITheme.ApplyCorner(leavePracticeButton)
UITheme.ApplyButtonHoverEffect(leavePracticeButton)
leavePracticeButton.Parent = practiceFrame

-- Position the answer row above the Leave button once both exist.
leavePracticeButton.Position = UDim2.fromOffset(8, 216)
practiceAnswerBox.Position = UDim2.fromOffset(8, 176)
practiceSubmitButton.Position = UDim2.fromOffset(176, 176)
leavePracticeButton.Size = UDim2.fromOffset(160, 32)

local function submitPracticeAnswer()
	if practiceAnswerBox.Text == "" then
		return
	end
	practiceSubmitAnswerEvent:FireServer(practiceAnswerBox.Text)
	practiceAnswerBox.Text = ""
end

practiceSubmitButton.MouseButton1Click:Connect(submitPracticeAnswer)
practiceAnswerBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		submitPracticeAnswer()
	end
end)

leavePracticeButton.MouseButton1Click:Connect(function()
	leavePracticeModeEvent:FireServer()
end)

local function formatStats(stats): string
	if not stats then
		return ""
	end
	return ("Correct: %d   Incorrect: %d   Accuracy: %d%%   Streak: %d"):format(
		stats.correctAnswers,
		stats.incorrectAnswers,
		math.floor(stats.accuracy + 0.5),
		stats.currentStreak
	)
end

-- ===== Local countdown (visual only; server enforces the real timeout) =====

local countdownConnection: RBXScriptConnection? = nil
local countdownDeadlineClock: number? = nil

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

	countdownConnection = RunService.RenderStepped:Connect(function()
		if not countdownDeadlineClock then
			return
		end
		local remaining = math.max(0, countdownDeadlineClock - os.clock())
		timerLabel.Text = ("TIME: %.1f"):format(remaining)
		-- Visually urgent in the final 3 seconds.
		timerLabel.TextColor3 = if remaining <= 3 then UITheme.COLORS.Error else UITheme.COLORS.Gold
		if remaining <= 0 then
			stopCountdown()
		end
	end)
end

-- ===== Camera (reuses the same focus-on-platform approach as competitive) =====

local cameraActive = false

local function focusCameraOnPlatform(platformIndex: number?)
	if not platformIndex then
		return
	end

	local arena = Workspace:FindFirstChild("Arena")
	local platforms = arena and arena:FindFirstChild("Platforms")
	local platform = platforms and platforms:FindFirstChild("Platform" .. platformIndex)
	local base = platform and platform:FindFirstChild("Base")
	if not (base and base:IsA("BasePart")) then
		return
	end

	local center = Vector3.new(0, base.Position.Y, 0)
	local outward = base.Position - center
	if outward.Magnitude < 1 then
		outward = Vector3.new(0, 0, 1)
	end
	outward = outward.Unit
	local camPos = base.Position + outward * 22 + Vector3.new(0, 10, 0)

	camera.CameraType = Enum.CameraType.Scriptable
	local fromCFrame = camera.CFrame
	local toCFrame = CFrame.new(camPos, base.Position + Vector3.new(0, 3, 0))

	-- ~1 second smooth transition, per spec.
	local tweenTarget = Instance.new("CFrameValue")
	tweenTarget.Value = fromCFrame
	local tween = TweenService:Create(tweenTarget, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Value = toCFrame,
	})
	local connection: RBXScriptConnection
	connection = tweenTarget:GetPropertyChangedSignal("Value"):Connect(function()
		if cameraActive then
			camera.CFrame = tweenTarget.Value
		end
	end)
	tween.Completed:Connect(function()
		connection:Disconnect()
		tweenTarget:Destroy()
	end)
	cameraActive = true
	tween:Play()
end

local function releaseCameraControl()
	if cameraActive then
		camera.CameraType = Enum.CameraType.Custom
		cameraActive = false
	end
end

-- ===== Lobby UI coordination (hide/show the normal lobby menu) =====

local function setLobbyMenuVisible(visible: boolean)
	local lobbyButtonBar = mainUI:FindFirstChild("LobbyButtonBar")
	if lobbyButtonBar then
		lobbyButtonBar.Visible = visible
	end
end

-- ===== Confirm modal (only shown if clicking Practice while queued) =====

local confirmOverlay = Instance.new("Frame")
confirmOverlay.Name = "PracticeConfirmOverlay"
confirmOverlay.Size = UDim2.fromScale(1, 1)
confirmOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
confirmOverlay.BackgroundTransparency = 0.5
confirmOverlay.Visible = false
confirmOverlay.ZIndex = 25
confirmOverlay.Parent = mainUI

local confirmPanel = Instance.new("Frame")
confirmPanel.Name = "PracticeConfirmPanel"
confirmPanel.Size = UDim2.fromOffset(360, 160)
confirmPanel.Position = UDim2.new(0.5, -180, 0.5, -80)
confirmPanel.ZIndex = 26
UITheme.StylePanel(confirmPanel, 0.05)
confirmPanel.Parent = confirmOverlay

local confirmLabel = Instance.new("TextLabel")
confirmLabel.Name = "Label"
confirmLabel.Size = UDim2.new(1, -16, 0, 70)
confirmLabel.Position = UDim2.fromOffset(8, 12)
confirmLabel.BackgroundTransparency = 1
confirmLabel.Font = Enum.Font.GothamBold
confirmLabel.TextScaled = true
confirmLabel.TextWrapped = true
confirmLabel.TextColor3 = UITheme.COLORS.Text
confirmLabel.Text = "LEAVE QUEUE AND ENTER PRACTICE?"
confirmLabel.ZIndex = 27
confirmLabel.Parent = confirmPanel

local confirmCancelButton = Instance.new("TextButton")
confirmCancelButton.Name = "CancelButton"
confirmCancelButton.Size = UDim2.fromOffset(160, 40)
confirmCancelButton.Position = UDim2.fromOffset(8, 108)
confirmCancelButton.Font = Enum.Font.GothamBold
confirmCancelButton.TextScaled = true
confirmCancelButton.Text = "CANCEL"
confirmCancelButton.TextColor3 = UITheme.COLORS.Text
confirmCancelButton.BackgroundColor3 = UITheme.COLORS.Panel
confirmCancelButton.ZIndex = 27
UITheme.ApplyCorner(confirmCancelButton)
UITheme.ApplyButtonHoverEffect(confirmCancelButton)
confirmCancelButton.Parent = confirmPanel

local confirmPracticeButton = Instance.new("TextButton")
confirmPracticeButton.Name = "ConfirmButton"
confirmPracticeButton.Size = UDim2.fromOffset(160, 40)
confirmPracticeButton.Position = UDim2.fromOffset(176, 108)
confirmPracticeButton.Font = Enum.Font.GothamBold
confirmPracticeButton.TextScaled = true
confirmPracticeButton.Text = "PRACTICE"
confirmPracticeButton.TextColor3 = UITheme.COLORS.Text
confirmPracticeButton.BackgroundColor3 = UITheme.COLORS.Accent
confirmPracticeButton.ZIndex = 27
UITheme.ApplyCorner(confirmPracticeButton)
UITheme.ApplyButtonHoverEffect(confirmPracticeButton)
confirmPracticeButton.Parent = confirmPanel

confirmCancelButton.MouseButton1Click:Connect(function()
	confirmOverlay.Visible = false
end)

confirmPracticeButton.MouseButton1Click:Connect(function()
	confirmOverlay.Visible = false
	requestManualPracticeEvent:FireServer()
end)

practiceButton.MouseButton1Click:Connect(function()
	if amIQueued then
		confirmOverlay.Visible = true
		UITheme.PlayOpenTween(confirmPanel)
	else
		requestManualPracticeEvent:FireServer()
	end
end)

-- ===== Remote handlers =====

practiceStateChangedEvent.OnClientEvent:Connect(function(data)
	if not data or not data.active then
		practiceFrame.Visible = false
		stopCountdown()
		releaseCameraControl()
		setLobbyMenuVisible(true)
		return
	end

	setLobbyMenuVisible(false)
	practiceFrame.Visible = true
	UITheme.PlayOpenTween(practiceFrame)
	statsLabel.Text = ""
	focusCameraOnPlatform(data.platformIndex)
end)

practiceQuestionStartedEvent.OnClientEvent:Connect(function(payload)
	if not payload then
		return
	end
	questionNumberLabel.Text = "Question " .. tostring(payload.questionNumber)
	questionTextLabel.Text = payload.questionText
	practiceAnswerBox.Text = ""
	startCountdown(payload.timerSeconds)
end)

practiceQuestionResolvedEvent.OnClientEvent:Connect(function(payload)
	if not payload then
		return
	end
	stopCountdown()

	if payload.correct then
		timerLabel.TextColor3 = UITheme.GetSuccessColor()
		timerLabel.Text = "Correct!"
	elseif payload.timedOut then
		timerLabel.TextColor3 = UITheme.COLORS.Gold
		timerLabel.Text = ("Time's up! Answer: %s"):format(tostring(payload.correctAnswer))
	else
		timerLabel.TextColor3 = UITheme.GetErrorColor()
		timerLabel.Text = ("Wrong! Answer: %s"):format(tostring(payload.correctAnswer))
	end

	statsLabel.Text = formatStats(payload.stats)
end)
