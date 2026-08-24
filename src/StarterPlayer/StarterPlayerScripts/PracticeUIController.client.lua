--[[
	PracticeUIController.client.lua

	Practice Mode entry point + camera - the Practice button/type-select/
	extra-time-select/difficulty-select/confirm-modal flow in the lobby,
	and the camera focus onto the practicer's platform. Purely
	presentational - the server (PracticeSystem) decides everything
	(question correctness, timing, which practice type/extra-time setting
	actually applies); this script only forwards the local player's
	practice-entry/leave requests and moves the camera.

	Practice Mode is manual-only: it starts ONLY when the player presses
	the Practice button - there is no automatic countdown/entry of any
	kind, and no "Practice Mode starts in..." banner.

	Flow: press Practice -> choose a TYPE (Regular Practice / Extra Time
	Mode) -> [Extra Time Mode only: choose a multiplier 2x-5x, or Infinite
	Time] -> choose a DIFFICULTY (same five tiers the Play button uses) ->
	(confirm leaving the queue, if applicable) -> practice starts. The
	difficulty screen's "GO BACK" button returns to the TYPE screen (not a
	dead-end Cancel) so a wrong pick is never more than one click to redo.

	The three server-facing values this ever sends are: a mode string
	("Regular"/"ExtraTime"), a tier id (1-5), and - only when mode is
	"ExtraTime" - either a number 2-5 or the literal string "Infinite".
	The server clamps/validates all of them independently; this script
	never invents timing values itself.

	The actual question/timer/answer-input/exit UI all live on the arena's
	giant central screen (ArenaScreenController.client.lua), the exact
	same surface competitive matches use.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local GameplayConfig = require(ReplicatedStorage.Modules.GameplayConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local GameplayCameraController = require(script.Parent.GameplayCameraController)
local OverlayManager = require(script.Parent.OverlayManager)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")

local practiceStateChangedEvent = RemoteEvents.Get("PracticeStateChanged")
local requestManualPracticeEvent = RemoteEvents.Get("RequestManualPractice")
local queueUpdatedEvent = RemoteEvents.Get("QueueUpdated")

local lobbyButtonBar = mainUI:WaitForChild("LobbyButtonBar")
local practiceButton = lobbyButtonBar:WaitForChild("PracticeButton") :: TextButton

-- Which type, difficulty tier, and (if ExtraTime) extra-time value were
-- picked, remembered across the (optional) queued-confirm step so the
-- eventual FireServer call sends what the player actually chose, not
-- always the defaults. Declared once here, before anything below
-- references them, so every closure in this file shares these exact same
-- variables rather than accidentally creating separate globals.
local pendingPracticeMode = "Regular"
local pendingPracticeTierId = GameplayConfig.QUEUE_TIERS[1].id
local pendingExtraTimeValue: (number | string)? = nil -- number 2-5, or "Infinite" - only meaningful when pendingPracticeMode == "ExtraTime"

-- Tracked purely so clicking Practice while queued can show a confirm
-- step instead of silently pulling the player out - updated from the
-- same QueueUpdated broadcast MatchSystem already sends.
local amIQueued = false
queueUpdatedEvent.OnClientEvent:Connect(function(payload)
	amIQueued = payload and payload.waitingNames and table.find(payload.waitingNames, player.Name) ~= nil
end)

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

OverlayManager.Register(confirmOverlay)

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
	requestManualPracticeEvent:FireServer(pendingPracticeMode, pendingPracticeTierId, pendingExtraTimeValue)
end)

-- ===== Practice difficulty selection - shown AFTER type (and, for Extra
-- Time Mode, extra-time) selection, BEFORE practice actually starts.
-- Reuses the exact same five GameplayConfig.QUEUE_TIERS the Play button's
-- tier-select popup uses - not a second, separate difficulty list - so
-- Easy/Medium/Hard/Expert/Master Mode mean exactly the same thing in
-- Practice as they do in a real match. =====

local difficultyOverlay = Instance.new("Frame")
difficultyOverlay.Name = "PracticeDifficultyOverlay"
difficultyOverlay.Size = UDim2.fromScale(1, 1)
difficultyOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
difficultyOverlay.BackgroundTransparency = 0.5
difficultyOverlay.Visible = false
difficultyOverlay.ZIndex = 25
difficultyOverlay.Parent = mainUI

OverlayManager.Register(difficultyOverlay)

local difficultyPanel = Instance.new("Frame")
difficultyPanel.Name = "PracticeDifficultyPanel"
-- Same sizing convention as the Play button's 5-tier popup
-- (LobbyUIController.client.lua's PlayTierPanel) for visual consistency
-- between the two tier-select flows.
difficultyPanel.Size = UDim2.fromOffset(420, 400)
difficultyPanel.Position = UDim2.new(0.5, -210, 0.5, -200)
difficultyPanel.ZIndex = 26
UITheme.StylePanel(difficultyPanel, 0.05)
difficultyPanel.Parent = difficultyOverlay

local difficultyTitle = Instance.new("TextLabel")
difficultyTitle.Name = "Title"
difficultyTitle.Size = UDim2.new(1, -16, 0, 36)
difficultyTitle.Position = UDim2.fromOffset(8, 10)
difficultyTitle.BackgroundTransparency = 1
difficultyTitle.Font = Enum.Font.GothamBlack
difficultyTitle.TextScaled = true
difficultyTitle.TextColor3 = UITheme.COLORS.Text
difficultyTitle.Text = "CHOOSE A DIFFICULTY"
difficultyTitle.ZIndex = 27
difficultyTitle.Parent = difficultyPanel

-- Forward-declared: the mode-select overlay (the "type of practice" screen
-- this button returns to) is built further down, after this one.
local modeOverlay: Frame
local modePanel: Frame

-- "GO BACK" - returns to the TYPE (Regular/Extra Time Mode) screen,
-- replacing the old dead-end CANCEL button here.
local difficultyBackButton = Instance.new("TextButton")
difficultyBackButton.Name = "BackButton"
difficultyBackButton.Size = UDim2.new(1, -16, 0, 34)
difficultyBackButton.Position = UDim2.fromOffset(8, 354)
difficultyBackButton.Font = Enum.Font.GothamBold
difficultyBackButton.TextScaled = true
difficultyBackButton.Text = "\u{2190} GO BACK"
difficultyBackButton.TextColor3 = UITheme.COLORS.Text
difficultyBackButton.BackgroundColor3 = UITheme.COLORS.Panel
difficultyBackButton.ZIndex = 27
UITheme.ApplyCorner(difficultyBackButton)
UITheme.ApplyButtonHoverEffect(difficultyBackButton)
difficultyBackButton.Parent = difficultyPanel

difficultyBackButton.MouseButton1Click:Connect(function()
	difficultyOverlay.Visible = false
	OverlayManager.Show(modeOverlay)
	UITheme.PlayOpenTween(modePanel)
end)

local function finalizePracticeStart()
	if amIQueued then
		OverlayManager.Show(confirmOverlay)
		UITheme.PlayOpenTween(confirmPanel)
	else
		requestManualPracticeEvent:FireServer(pendingPracticeMode, pendingPracticeTierId, pendingExtraTimeValue)
	end
end

for i, tier in ipairs(GameplayConfig.QUEUE_TIERS) do
	local tierButton = Instance.new("TextButton")
	tierButton.Name = "Tier" .. tier.id .. "Button"
	tierButton.Size = UDim2.new(1, -16, 0, 56)
	tierButton.Position = UDim2.fromOffset(8, 50 + (i - 1) * 62)
	tierButton.Font = Enum.Font.GothamBold
	tierButton.TextColor3 = UITheme.COLORS.Text
	tierButton.BackgroundColor3 = UITheme.COLORS.Panel
	tierButton.AutoButtonColor = false
	tierButton.Text = ""
	tierButton.ZIndex = 27
	UITheme.ApplyCorner(tierButton)
	UITheme.ApplyButtonHoverEffect(tierButton)
	tierButton.Parent = difficultyPanel

	local labelText = Instance.new("TextLabel")
	labelText.Name = "Label"
	labelText.Size = UDim2.new(1, -16, 0, 26)
	labelText.Position = UDim2.fromOffset(8, 4)
	labelText.BackgroundTransparency = 1
	labelText.Font = Enum.Font.GothamBold
	labelText.TextScaled = true
	labelText.TextXAlignment = Enum.TextXAlignment.Left
	labelText.TextColor3 = UITheme.COLORS.Accent
	labelText.Text = tier.name
	labelText.ZIndex = 28
	labelText.Parent = tierButton

	local descriptionText = Instance.new("TextLabel")
	descriptionText.Name = "Description"
	descriptionText.Size = UDim2.new(1, -16, 0, 22)
	descriptionText.Position = UDim2.fromOffset(8, 30)
	descriptionText.BackgroundTransparency = 1
	descriptionText.Font = Enum.Font.Gotham
	descriptionText.TextSize = 14
	descriptionText.TextXAlignment = Enum.TextXAlignment.Left
	descriptionText.TextColor3 = UITheme.COLORS.SubText
	descriptionText.Text = tier.description
	descriptionText.ZIndex = 28
	descriptionText.Parent = tierButton

	tierButton.MouseButton1Click:Connect(function()
		pendingPracticeTierId = tier.id
		difficultyOverlay.Visible = false
		finalizePracticeStart()
	end)
end

local function openDifficultyOverlay()
	OverlayManager.Show(difficultyOverlay)
	UITheme.PlayOpenTween(difficultyPanel)
end

-- ===== Extra Time Mode selection - a per-question time multiplier
-- (2x-5x) or Infinite Time, shown only when "Extra Time Mode" is chosen
-- on the type screen. Replaces the old separate "Double Time"/"No
-- Cooldown" modes with one unified picker. =====

local extraTimeOverlay = Instance.new("Frame")
extraTimeOverlay.Name = "PracticeExtraTimeOverlay"
extraTimeOverlay.Size = UDim2.fromScale(1, 1)
extraTimeOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
extraTimeOverlay.BackgroundTransparency = 0.5
extraTimeOverlay.Visible = false
extraTimeOverlay.ZIndex = 25
extraTimeOverlay.Parent = mainUI

OverlayManager.Register(extraTimeOverlay)

local extraTimePanel = Instance.new("Frame")
extraTimePanel.Name = "PracticeExtraTimePanel"
extraTimePanel.Size = UDim2.fromOffset(380, 360)
extraTimePanel.Position = UDim2.new(0.5, -190, 0.5, -180)
extraTimePanel.ZIndex = 26
UITheme.StylePanel(extraTimePanel, 0.05)
extraTimePanel.Parent = extraTimeOverlay

local extraTimeTitle = Instance.new("TextLabel")
extraTimeTitle.Name = "Title"
extraTimeTitle.Size = UDim2.new(1, -16, 0, 36)
extraTimeTitle.Position = UDim2.fromOffset(8, 10)
extraTimeTitle.BackgroundTransparency = 1
extraTimeTitle.Font = Enum.Font.GothamBlack
extraTimeTitle.TextScaled = true
extraTimeTitle.TextColor3 = UITheme.COLORS.Text
extraTimeTitle.Text = "CHOOSE YOUR TIME"
extraTimeTitle.ZIndex = 27
extraTimeTitle.Parent = extraTimePanel

local extraTimeBackButton = Instance.new("TextButton")
extraTimeBackButton.Name = "BackButton"
extraTimeBackButton.Size = UDim2.new(1, -16, 0, 34)
extraTimeBackButton.Position = UDim2.fromOffset(8, 316)
extraTimeBackButton.Font = Enum.Font.GothamBold
extraTimeBackButton.TextScaled = true
extraTimeBackButton.Text = "\u{2190} GO BACK"
extraTimeBackButton.TextColor3 = UITheme.COLORS.Text
extraTimeBackButton.BackgroundColor3 = UITheme.COLORS.Panel
extraTimeBackButton.ZIndex = 27
UITheme.ApplyCorner(extraTimeBackButton)
UITheme.ApplyButtonHoverEffect(extraTimeBackButton)
extraTimeBackButton.Parent = extraTimePanel

extraTimeBackButton.MouseButton1Click:Connect(function()
	extraTimeOverlay.Visible = false
	OverlayManager.Show(modeOverlay)
	UITheme.PlayOpenTween(modePanel)
end)

local EXTRA_TIME_OPTIONS = {
	{ value = 2, label = "2\u{00D7} Time", description = "Double the usual time per question." },
	{ value = 3, label = "3\u{00D7} Time", description = "Triple the usual time per question." },
	{ value = 4, label = "4\u{00D7} Time", description = "Quadruple the usual time per question." },
	{ value = 5, label = "5\u{00D7} Time", description = "5x the usual time per question." },
	{ value = "Infinite", label = "Infinite Time", description = "No per-question timer at all - answer whenever you're ready." },
}

local function startPracticeWithExtraTime(value: number | string)
	pendingExtraTimeValue = value
	extraTimeOverlay.Visible = false
	openDifficultyOverlay()
end

for i, option in ipairs(EXTRA_TIME_OPTIONS) do
	local optionButton = Instance.new("TextButton")
	optionButton.Name = "ExtraTime" .. tostring(option.value) .. "Button"
	optionButton.Size = UDim2.new(1, -16, 0, 50)
	optionButton.Position = UDim2.fromOffset(8, 50 + (i - 1) * 54)
	optionButton.Font = Enum.Font.GothamBold
	optionButton.TextColor3 = UITheme.COLORS.Text
	optionButton.BackgroundColor3 = UITheme.COLORS.Panel
	optionButton.AutoButtonColor = false
	optionButton.Text = ""
	optionButton.ZIndex = 27
	UITheme.ApplyCorner(optionButton)
	UITheme.ApplyButtonHoverEffect(optionButton)
	optionButton.Parent = extraTimePanel

	local labelText = Instance.new("TextLabel")
	labelText.Name = "Label"
	labelText.Size = UDim2.new(1, -16, 0, 24)
	labelText.Position = UDim2.fromOffset(8, 3)
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
	descriptionText.Size = UDim2.new(1, -16, 0, 20)
	descriptionText.Position = UDim2.fromOffset(8, 27)
	descriptionText.BackgroundTransparency = 1
	descriptionText.Font = Enum.Font.Gotham
	descriptionText.TextSize = 13
	descriptionText.TextXAlignment = Enum.TextXAlignment.Left
	descriptionText.TextColor3 = UITheme.COLORS.SubText
	descriptionText.Text = option.description
	descriptionText.ZIndex = 28
	descriptionText.Parent = optionButton

	optionButton.MouseButton1Click:Connect(function()
		startPracticeWithExtraTime(option.value)
	end)
end

-- ===== Practice type selection ("what type of practice you want") - now
-- just two entries: Regular, and Extra Time Mode (which branches into the
-- extra-time picker above before reaching the difficulty screen). =====

modeOverlay = Instance.new("Frame")
modeOverlay.Name = "PracticeModeOverlay"
modeOverlay.Size = UDim2.fromScale(1, 1)
modeOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
modeOverlay.BackgroundTransparency = 0.5
modeOverlay.Visible = false
modeOverlay.ZIndex = 25
modeOverlay.Parent = mainUI

OverlayManager.Register(modeOverlay)

modePanel = Instance.new("Frame")
modePanel.Name = "PracticeModePanel"
modePanel.Size = UDim2.fromOffset(380, 220)
modePanel.Position = UDim2.new(0.5, -190, 0.5, -110)
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

-- Cancel button: dismisses the type-select popup without starting
-- Practice at all (this is the very first screen in the flow, so there's
-- nowhere "back" to go - Cancel here just closes the whole flow, unlike
-- the difficulty/extra-time screens further in, which use GO BACK).
local modeCancelButton = Instance.new("TextButton")
modeCancelButton.Name = "CancelButton"
modeCancelButton.Size = UDim2.new(1, -16, 0, 34)
modeCancelButton.Position = UDim2.fromOffset(8, 176)
modeCancelButton.Font = Enum.Font.GothamBold
modeCancelButton.TextScaled = true
modeCancelButton.Text = "CANCEL"
modeCancelButton.TextColor3 = UITheme.COLORS.Text
modeCancelButton.BackgroundColor3 = UITheme.COLORS.Error
modeCancelButton.ZIndex = 27
UITheme.ApplyCorner(modeCancelButton)
UITheme.ApplyButtonHoverEffect(modeCancelButton)
modeCancelButton.Parent = modePanel

modeCancelButton.MouseButton1Click:Connect(function()
	modeOverlay.Visible = false
end)

local MODE_OPTIONS = {
	{ mode = "Regular", label = "Regular Practice", description = "Normal timer, normal pace." },
	{ mode = "ExtraTime", label = "Extra Time Mode", description = "Choose 2x-5x time per question, or Infinite Time." },
}

for i, option in ipairs(MODE_OPTIONS) do
	local optionButton = Instance.new("TextButton")
	optionButton.Name = option.mode .. "Button"
	optionButton.Size = UDim2.new(1, -16, 0, 62)
	optionButton.Position = UDim2.fromOffset(8, 50 + (i - 1) * 68)
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
	descriptionText.Size = UDim2.new(1, -16, 0, 26)
	descriptionText.Position = UDim2.fromOffset(8, 32)
	descriptionText.BackgroundTransparency = 1
	descriptionText.Font = Enum.Font.Gotham
	descriptionText.TextSize = 14
	descriptionText.TextWrapped = true
	descriptionText.TextXAlignment = Enum.TextXAlignment.Left
	descriptionText.TextColor3 = UITheme.COLORS.SubText
	descriptionText.Text = option.description
	descriptionText.ZIndex = 28
	descriptionText.Parent = optionButton

	optionButton.MouseButton1Click:Connect(function()
		pendingPracticeMode = option.mode
		modeOverlay.Visible = false
		if option.mode == "ExtraTime" then
			pendingExtraTimeValue = nil -- must be chosen on the next screen
			OverlayManager.Show(extraTimeOverlay)
			UITheme.PlayOpenTween(extraTimePanel)
		else
			pendingExtraTimeValue = nil
			openDifficultyOverlay()
		end
	end)
end

practiceButton.MouseButton1Click:Connect(function()
	OverlayManager.Show(modeOverlay)
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
