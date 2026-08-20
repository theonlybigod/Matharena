--[[
	SettingsUIController.client.lua

	Real settings panel (Message 12): music volume, SFX volume, graphics
	quality, UI scale, colorblind mode. Replaces the "coming soon"
	placeholder LobbyUIController originally showed for the Settings
	button - same handoff pattern Message 10 used for the Shop button
	(LobbyUIController's SettingsButton click handler is now a no-op).

	Uses stepper controls (-/+ buttons) rather than drag-sliders: simpler
	to get right, and inherently touch-friendly for mobile without needing
	fine drag precision.

	All changes go through ClientSettingsState, which persists them via
	SettingsSystem (server) and notifies AudioController/
	ResponsiveUIController so the change takes effect immediately.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsConfig = require(ReplicatedStorage.Modules.SettingsConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local ClientSettingsState = require(script.Parent.ClientSettingsState)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")

-- ===== Panel shell =====
-- Message 26 ("make each opened panel 100x better"): premium panel style
-- (gradient + glowing accent border), larger, with a title divider -
-- same upgrade pattern applied to every panel this message touches.

local overlay = Instance.new("Frame")
overlay.Name = "SettingsOverlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 0.45
overlay.Visible = false
overlay.ZIndex = 10
overlay.Parent = mainUI

local panel = Instance.new("Frame")
panel.Name = "SettingsPanel"
panel.Size = UDim2.fromOffset(500, 440)
panel.Position = UDim2.new(0.5, -250, 0.5, -220)
panel.ZIndex = 11
UITheme.StylePremiumPanel(panel, 0.05)
panel.Parent = overlay

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -28, 0, 44)
title.Position = UDim2.fromOffset(14, 14)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = UITheme.COLORS.Accent
title.Text = "Settings"
title.ZIndex = 12
title.Parent = panel

local titleDivider = Instance.new("Frame")
titleDivider.Name = "Divider"
titleDivider.Size = UDim2.new(1, -28, 0, 2)
titleDivider.Position = UDim2.fromOffset(14, 60)
titleDivider.BackgroundColor3 = UITheme.COLORS.Accent
titleDivider.BackgroundTransparency = 0.7
titleDivider.BorderSizePixel = 0
titleDivider.ZIndex = 12
titleDivider.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.fromOffset(110, 40)
closeButton.Position = UDim2.new(1, -124, 1, -54)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextScaled = true
closeButton.Text = "Close"
closeButton.TextColor3 = UITheme.COLORS.Text
closeButton.BackgroundColor3 = UITheme.COLORS.Error
closeButton.ZIndex = 12
UITheme.ApplyCorner(closeButton)
UITheme.ApplyButtonHoverEffect(closeButton)
closeButton.Parent = panel
closeButton.MouseButton1Click:Connect(function()
	overlay.Visible = false
end)

local rowsContainer = Instance.new("Frame")
rowsContainer.Name = "Rows"
rowsContainer.Size = UDim2.new(1, -28, 1, -130)
rowsContainer.Position = UDim2.fromOffset(14, 76)
rowsContainer.BackgroundTransparency = 1
rowsContainer.ZIndex = 12
rowsContainer.Parent = panel

local rowsLayout = Instance.new("UIListLayout")
rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowsLayout.Padding = UDim.new(0, 12)
rowsLayout.Parent = rowsContainer

-- ===== Generic stepper row builder =====

local function createRow(labelText: string, order: number): Frame
	local row = Instance.new("Frame")
	row.Name = labelText:gsub("%s", "") .. "Row"
	row.Size = UDim2.new(1, 0, 0, 50)
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.ZIndex = 12
	row.Parent = rowsContainer

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromOffset(140, 50)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = UITheme.COLORS.SubText
	label.Text = labelText
	label.ZIndex = 12
	label.Parent = row

	return row
end

local function createStepperButton(name: string, text: string, xOffset: number, parent: Instance): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(36, 36)
	button.Position = UDim2.new(0, xOffset, 0.5, -18)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = text
	button.TextColor3 = UITheme.COLORS.Text
	button.BackgroundColor3 = UITheme.COLORS.Panel
	button.ZIndex = 12
	UITheme.ApplyCorner(button)
	UITheme.ApplyButtonHoverEffect(button)
	button.Parent = parent
	return button
end

--[[
	A -/value/+ stepper for a numeric setting in [min, max], stepping by
	`step` each click.
]]
local function createNumberStepper(labelText: string, order: number, key: string, step: number)
	local row = createRow(labelText, order)

	local minusButton = createStepperButton(key .. "Minus", "-", 150, row)
	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "Value"
	valueLabel.Size = UDim2.fromOffset(70, 36)
	valueLabel.Position = UDim2.new(0, 192, 0.5, -18)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextScaled = true
	valueLabel.TextColor3 = UITheme.COLORS.Text
	valueLabel.ZIndex = 12
	valueLabel.Parent = row
	local plusButton = createStepperButton(key .. "Plus", "+", 268, row)

	local function refresh()
		local value = ClientSettingsState.Get(key)
		valueLabel.Text = ("%d%%"):format(math.round(value * 100))
	end

	minusButton.MouseButton1Click:Connect(function()
		ClientSettingsState.Set(key, ClientSettingsState.Get(key) - step)
		refresh()
	end)
	plusButton.MouseButton1Click:Connect(function()
		ClientSettingsState.Set(key, ClientSettingsState.Get(key) + step)
		refresh()
	end)

	ClientSettingsState.OnLoaded(refresh)
	return refresh
end

createNumberStepper("Music Volume", 1, "musicVolume", 0.1)
createNumberStepper("SFX Volume", 2, "sfxVolume", 0.1)

-- UI Scale stepper (displayed as a plain multiplier, not a percent-of-100 volume)
do
	local row = createRow("UI Scale", 3)
	local minusButton = createStepperButton("uiScaleMinus", "-", 150, row)
	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "Value"
	valueLabel.Size = UDim2.fromOffset(70, 36)
	valueLabel.Position = UDim2.new(0, 192, 0.5, -18)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextScaled = true
	valueLabel.TextColor3 = UITheme.COLORS.Text
	valueLabel.ZIndex = 12
	valueLabel.Parent = row
	local plusButton = createStepperButton("uiScalePlus", "+", 268, row)

	local function refresh()
		valueLabel.Text = ("%.2fx"):format(ClientSettingsState.Get("uiScale"))
	end

	minusButton.MouseButton1Click:Connect(function()
		ClientSettingsState.Set("uiScale", ClientSettingsState.Get("uiScale") - 0.05)
		refresh()
	end)
	plusButton.MouseButton1Click:Connect(function()
		ClientSettingsState.Set("uiScale", ClientSettingsState.Get("uiScale") + 0.05)
		refresh()
	end)

	ClientSettingsState.OnLoaded(refresh)
end

-- Graphics quality: 3 discrete buttons (Low/Medium/High)
do
	local row = createRow("Graphics", 4)
	local buttons: { [string]: TextButton } = {}

	local function refreshHighlight()
		local current = ClientSettingsState.Get("graphicsQuality")
		for optionName, button in pairs(buttons) do
			button.BackgroundColor3 = (optionName == current) and UITheme.COLORS.Accent or UITheme.COLORS.Panel
		end
	end

	for i, option in ipairs(SettingsConfig.GRAPHICS_QUALITY_OPTIONS) do
		local button = createStepperButton("graphics" .. option, option, 150 + (i - 1) * 76, row)
		button.Size = UDim2.fromOffset(70, 36)
		button.TextScaled = true
		buttons[option] = button
		button.MouseButton1Click:Connect(function()
			ClientSettingsState.Set("graphicsQuality", option)
			refreshHighlight()
		end)
	end

	ClientSettingsState.OnLoaded(refreshHighlight)
end

-- Colorblind mode: single toggle button
do
	local row = createRow("Colorblind Mode", 5)
	local toggleButton = createStepperButton("colorblindToggle", "", 150, row)
	toggleButton.Size = UDim2.fromOffset(120, 36)

	local function refresh()
		local enabled = ClientSettingsState.Get("colorblindMode")
		toggleButton.Text = enabled and "On" or "Off"
		toggleButton.BackgroundColor3 = enabled and UITheme.COLORS.Success or UITheme.COLORS.Panel
	end

	toggleButton.MouseButton1Click:Connect(function()
		ClientSettingsState.Set("colorblindMode", not ClientSettingsState.Get("colorblindMode"))
		refresh()
	end)

	ClientSettingsState.OnLoaded(refresh)
end

-- ===== Wire up from LobbyUIController's Settings button =====

local function openSettings()
	overlay.Visible = true
	UITheme.PlayOpenTween(panel)
end

-- LobbyUIController creates the SettingsButton; find it and hook into it
-- directly rather than duplicating the button (mirrors how ShopUIController
-- hooks into LobbyUIController's ShopButton in Message 10).
task.spawn(function()
	local buttonBar = mainUI:WaitForChild("LobbyButtonBar", 10)
	local settingsButton = buttonBar and buttonBar:WaitForChild("SettingsButton", 10)
	if settingsButton then
		settingsButton.MouseButton1Click:Connect(openSettings)
	end
end)
