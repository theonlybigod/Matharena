--[[
	PracticeUIController.client.lua

	Practice Mode entry point + camera - the Practice button/confirm-modal
	flow in the lobby, and the camera focus onto the practicer's platform.
	Purely presentational - the server (PracticeSystem) decides everything
	(question correctness, timing); this script only forwards the local
	player's practice-entry/leave requests and moves the camera.

	Practice Mode is manual-only: it starts ONLY when the player presses
	the Practice button - there is no automatic countdown/entry of any
	kind, and no "Practice Mode starts in..." banner.

	The actual question/timer/answer-input/exit UI all live on the arena's
	giant central screen now (ArenaScreenController.client.lua), the exact
	same surface competitive matches use - this script previously ALSO
	built its own separate popup with the question/timer/answer box/exit
	button, which meant a practicing player saw two competing places to
	read the question and type an answer at once. That popup has been
	removed entirely, not just hidden, so there's exactly one gameplay
	surface during Practice Mode too.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local UITheme = require(ReplicatedStorage.Modules.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")
local camera = Workspace.CurrentCamera

local practiceStateChangedEvent = RemoteEvents.Get("PracticeStateChanged")
local requestManualPracticeEvent = RemoteEvents.Get("RequestManualPractice")
local queueUpdatedEvent = RemoteEvents.Get("QueueUpdated")

local lobbyButtonBar = mainUI:WaitForChild("LobbyButtonBar")
local practiceButton = lobbyButtonBar:WaitForChild("PracticeButton") :: TextButton

-- Tracked purely so clicking Practice while queued can show a confirm
-- step instead of silently pulling the player out - updated from the
-- same QueueUpdated broadcast MatchSystem already sends.
local amIQueued = false
queueUpdatedEvent.OnClientEvent:Connect(function(payload)
	amIQueued = payload and payload.waitingNames and table.find(payload.waitingNames, player.Name) ~= nil
end)

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
		releaseCameraControl()
		setLobbyMenuVisible(true)
		return
	end

	setLobbyMenuVisible(false)
	focusCameraOnPlatform(data.platformIndex)
end)
