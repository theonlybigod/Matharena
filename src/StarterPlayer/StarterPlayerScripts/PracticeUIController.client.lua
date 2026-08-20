--[[
	PracticeUIController.client.lua

	Practice Mode entry point + camera - the Practice button/mode-select/
	confirm-modal flow in the lobby, and the camera focus onto the
	practicer's platform. Purely presentational - the server
	(PracticeSystem) decides everything (question correctness, timing,
	which practice mode variant actually applies); this script only
	forwards the local player's practice-entry/leave requests and moves
	the camera.

	Practice Mode is manual-only: it starts ONLY when the player presses
	the Practice button - there is no automatic countdown/entry of any
	kind, and no "Practice Mode starts in..." banner.

	Practice mode selection ("what type of practice you want"): pressing
	Practice now always shows a mode-select popup first (Regular/Double
	Time/No Cooldown), before anything else - including before the
	queued-confirm modal, so the flow is always: press Practice -> choose
	a mode -> (confirm leaving the queue, if applicable) -> practice
	starts in that mode. The three modes themselves (what "double time"/
	"no cooldown" actually change about timing) are entirely a server-side
	concern (see PracticeSystem.lua) - this script only ever sends one of
	three fixed strings ("Regular"/"DoubleTime"/"NoCooldown"), never
	invents timing values itself.

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
local GameplayCameraController = require(script.Parent.GameplayCameraController)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")

local practiceStateChangedEvent = RemoteEvents.Get("PracticeStateChanged")
local requestManualPracticeEvent = RemoteEvents.Get("RequestManualPractice")
local queueUpdatedEvent = RemoteEvents.Get("QueueUpdated")

local lobbyButtonBar = mainUI:WaitForChild("LobbyButtonBar")
local practiceButton = lobbyButtonBar:WaitForChild("PracticeButton") :: TextButton

-- Which mode was picked in the mode-select popup, remembered across the
-- (optional) queued-confirm step so the eventual FireServer call sends
-- the mode the player actually chose, not always "Regular". Declared once
-- here, before anything below references it, so every closure in this
-- file shares this exact same variable rather than accidentally creating
-- separate globals.
local pendingPracticeMode = "Regular"

-- Tracked purely so clicking Practice while queued can show a confirm
-- step instead of silently pulling the player out - updated from the
-- same QueueUpdated broadcast MatchSystem already sends.
local amIQueued = false
queueUpdatedEvent.OnClientEvent:Connect(function(payload)
	amIQueued = payload and payload.waitingNames and table.find(payload.waitingNames, player.Name) ~= nil
end)

-- ===== Camera (Message 28: now shared with CompetitionUIController via
-- GameplayCameraController.lua, and zooms toward the central MATHARENA
-- screen rather than just the player's own platform) =====

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
	requestManualPracticeEvent:FireServer(pendingPracticeMode)
end)

-- ===== Practice mode selection ("what type of practice you want") =====

local modeOverlay = Instance.new("Frame")
modeOverlay.Name = "PracticeModeOverlay"
modeOverlay.Size = UDim2.fromScale(1, 1)
modeOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
modeOverlay.BackgroundTransparency = 0.5
modeOverlay.Visible = false
modeOverlay.ZIndex = 25
modeOverlay.Parent = mainUI

local modePanel = Instance.new("Frame")
modePanel.Name = "PracticeModePanel"
modePanel.Size = UDim2.fromOffset(380, 260)
modePanel.Position = UDim2.new(0.5, -190, 0.5, -130)
modePanel.ZIndex = 26
UITheme.StylePanel(modePanel, 0.05)
modePanel.Parent = modeOverlay

local modeTitle = Instance.new("TextLabel")
modeTitle.Name = "Title"
modeTitle.Size = UDim2.new(1, -16, 0, 36)
modeTitle.Position = UDim2.fromOffset(8, 10)
modeTitle.BackgroundTransparency = 1
modeTitle.Font = Enum.Font.GothamBlack
modeTitle.TextScaled = true
modeTitle.TextColor3 = UITheme.COLORS.Text
modeTitle.Text = "WHAT TYPE OF PRACTICE?"
modeTitle.ZIndex = 27
modeTitle.Parent = modePanel

local MODE_OPTIONS = {
	{ mode = "Regular", label = "Regular Practice", description = "Normal timer, normal pace." },
	{ mode = "DoubleTime", label = "Double Time Practice", description = "2x the usual time per question." },
	{ mode = "NoCooldown", label = "No Cooldown Practice", description = "No pause between questions." },
}

local function startPracticeWithMode(mode: string)
	pendingPracticeMode = mode
	modeOverlay.Visible = false
	if amIQueued then
		confirmOverlay.Visible = true
		UITheme.PlayOpenTween(confirmPanel)
	else
		requestManualPracticeEvent:FireServer(pendingPracticeMode)
	end
end

for i, option in ipairs(MODE_OPTIONS) do
	local optionButton = Instance.new("TextButton")
	optionButton.Name = option.mode .. "Button"
	optionButton.Size = UDim2.new(1, -16, 0, 56)
	optionButton.Position = UDim2.fromOffset(8, 50 + (i - 1) * 62)
	optionButton.Font = Enum.Font.GothamBold
	optionButton.TextColor3 = UITheme.COLORS.Text
	optionButton.BackgroundColor3 = UITheme.COLORS.Panel
	optionButton.AutoButtonColor = false
	optionButton.Text = ""
	optionButton.ZIndex = 27
	UITheme.ApplyCorner(optionButton)
	UITheme.ApplyButtonHoverEffect(optionButton)
	optionButton.Parent = modePanel

	local labelText = Instance.new("TextLabel")
	labelText.Name = "Label"
	labelText.Size = UDim2.new(1, -16, 0, 26)
	labelText.Position = UDim2.fromOffset(8, 4)
	labelText.BackgroundTransparency = 1
	labelText.Font = Enum.Font.GothamBold
	labelText.TextScaled = true
	labelText.TextXAlignment = Enum.TextXAlignment.Left
	labelText.TextColor3 = UITheme.COLORS.Accent
	labelText.Text = option.label
	labelText.ZIndex = 28
	labelText.Parent = optionButton

	local descriptionText = Instance.new("TextLabel")
	descriptionText.Name = "Description"
	descriptionText.Size = UDim2.new(1, -16, 0, 22)
	descriptionText.Position = UDim2.fromOffset(8, 30)
	descriptionText.BackgroundTransparency = 1
	descriptionText.Font = Enum.Font.Gotham
	descriptionText.TextSize = 14
	descriptionText.TextXAlignment = Enum.TextXAlignment.Left
	descriptionText.TextColor3 = UITheme.COLORS.SubText
	descriptionText.Text = option.description
	descriptionText.ZIndex = 28
	descriptionText.Parent = optionButton

	optionButton.MouseButton1Click:Connect(function()
		startPracticeWithMode(option.mode)
	end)
end

practiceButton.MouseButton1Click:Connect(function()
	modeOverlay.Visible = true
	UITheme.PlayOpenTween(modePanel)
end)

-- ===== Remote handlers =====

practiceStateChangedEvent.OnClientEvent:Connect(function(data)
	if not data or not data.active then
		GameplayCameraController.Release()
		setLobbyMenuVisible(true)
		return
	end

	setLobbyMenuVisible(false)
	GameplayCameraController.FocusOnScreen(data.platformIndex, 1)
end)
