--[[
	LobbyUIController.client.lua

	Builds the lobby menu: Play, Practice, Shop, Stats, Settings, Rewards
	buttons, plus a Stats panel (backed by real ProgressionSystem/
	DataSystem data from Message 4) and a placeholder panel for Settings.

	Settings has no backing system in THIS file yet - clicking it opens a
	"coming soon" panel (note SettingsSystem/SettingsUIController exist
	elsewhere and may already own this button - check before assuming
	it's unwired). The Shop, Rewards, and Practice buttons' click handling
	belongs to ShopUIController.client.lua, RewardsUIController.client.lua,
	and PracticeUIController.client.lua respectively - this file only
	creates the buttons and leaves a no-op connection, same handoff pattern
	for all three. Button names are stable (ShopButton, SettingsButton,
	RewardsButton, PracticeButton, ModalOverlay/ModalPanel) so future
	messages can wire real functionality into this same UI without
	replacing it.

	RewardsButton was previously "DailyRewardsButton" showing a "Daily
	Rewards" placeholder - replaced with a win-based Rewards track (NOT a
	daily-login system); the old placeholder click handler is gone.

	Visible while not committed to an active match (Lobby/Waiting); hidden
	once the match locks in (Starting onward).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MatchConfig = require(ReplicatedStorage.Modules.MatchConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
local UITheme = require(ReplicatedStorage.Modules.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")

-- ===== Button bar =====

local buttonBar = Instance.new("Frame")
buttonBar.Name = "LobbyButtonBar"
buttonBar.Size = UDim2.fromOffset(700, 64)
buttonBar.Position = UDim2.new(0.5, -350, 1, -84)
buttonBar.BackgroundTransparency = 1
buttonBar.Parent = mainUI

local barLayout = Instance.new("UIListLayout")
barLayout.SortOrder = Enum.SortOrder.LayoutOrder
barLayout.FillDirection = Enum.FillDirection.Horizontal
barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
barLayout.Padding = UDim.new(0, 12)
barLayout.Parent = buttonBar

local function createButton(name: string, text: string, order: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(104, 56)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = text
	button.TextColor3 = UITheme.COLORS.Text
	UITheme.StylePanel(button, 0)
	UITheme.ApplyButtonHoverEffect(button)
	button.Parent = buttonBar
	return button
end

local playButton = createButton("PlayButton", "Play", 1)
playButton.BackgroundColor3 = UITheme.COLORS.Accent

local practiceButton = createButton("PracticeButton", "Practice", 2)
local shopButton = createButton("ShopButton", "Shop", 3)
local statsButton = createButton("StatsButton", "Stats", 4)
local settingsButton = createButton("SettingsButton", "Settings", 5)
local dailyRewardsButton = createButton("RewardsButton", "Rewards", 6)

-- ===== Generic modal (reused by Shop/Settings/Daily Rewards/Stats) =====

local modalOverlay = Instance.new("Frame")
modalOverlay.Name = "ModalOverlay"
modalOverlay.Size = UDim2.fromScale(1, 1)
modalOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
modalOverlay.BackgroundTransparency = 0.5
modalOverlay.Visible = false
modalOverlay.ZIndex = 10
modalOverlay.Parent = mainUI

local modalPanel = Instance.new("Frame")
modalPanel.Name = "ModalPanel"
modalPanel.Size = UDim2.fromOffset(440, 340)
modalPanel.Position = UDim2.new(0.5, -220, 0.5, -170)
modalPanel.ZIndex = 11
UITheme.StylePanel(modalPanel, 0.05)
modalPanel.Parent = modalOverlay

local modalTitle = Instance.new("TextLabel")
modalTitle.Name = "ModalTitle"
modalTitle.Size = UDim2.new(1, -20, 0, 40)
modalTitle.Position = UDim2.fromOffset(10, 10)
modalTitle.BackgroundTransparency = 1
modalTitle.Font = Enum.Font.GothamBlack
modalTitle.TextScaled = true
modalTitle.TextXAlignment = Enum.TextXAlignment.Left
modalTitle.TextColor3 = UITheme.COLORS.Accent
modalTitle.ZIndex = 12
modalTitle.Parent = modalPanel

local modalBody = Instance.new("TextLabel")
modalBody.Name = "ModalBody"
modalBody.Size = UDim2.new(1, -20, 1, -100)
modalBody.Position = UDim2.fromOffset(10, 56)
modalBody.BackgroundTransparency = 1
modalBody.Font = Enum.Font.Gotham
modalBody.TextSize = 18
modalBody.TextWrapped = true
modalBody.TextYAlignment = Enum.TextYAlignment.Top
modalBody.TextXAlignment = Enum.TextXAlignment.Left
modalBody.TextColor3 = UITheme.COLORS.SubText
modalBody.ZIndex = 12
modalBody.Parent = modalPanel

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.fromOffset(100, 36)
closeButton.Position = UDim2.new(1, -110, 1, -46)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextScaled = true
closeButton.Text = "Close"
closeButton.TextColor3 = UITheme.COLORS.Text
closeButton.BackgroundColor3 = UITheme.COLORS.Error
closeButton.ZIndex = 12
UITheme.ApplyCorner(closeButton)
UITheme.ApplyButtonHoverEffect(closeButton)
closeButton.Parent = modalPanel

closeButton.MouseButton1Click:Connect(function()
	modalOverlay.Visible = false
end)

local function openModal(title: string, body: string)
	modalTitle.Text = title
	modalBody.Text = body
	modalOverlay.Visible = true
	UITheme.PlayOpenTween(modalPanel)
end

shopButton.MouseButton1Click:Connect(function()
	-- Intentionally not handled here - ShopUIController.client.lua
	-- (Message 10) owns this button's click handling and opens the real
	-- shop panel. This connection is a no-op so anyone reading this file
	-- doesn't mistake ShopButton for being unwired.
end)

practiceButton.MouseButton1Click:Connect(function()
	-- Intentionally not handled here - PracticeUIController.client.lua owns
	-- this button's click handling (immediate manual Practice entry, with
	-- a confirm step if the player is currently queued), same handoff
	-- pattern as ShopButton above.
end)

settingsButton.MouseButton1Click:Connect(function()
	-- Intentionally not handled here - SettingsUIController.client.lua
	-- (Message 12) owns this button's click handling and opens the real
	-- settings panel, same handoff pattern as ShopButton above.
end)

dailyRewardsButton.MouseButton1Click:Connect(function()
	-- Intentionally not handled here - RewardsUIController.client.lua owns
	-- this button's click handling and opens the real win-based Rewards
	-- track panel, same handoff pattern as ShopButton above.
end)

-- ===== Stats panel (real data, Message 4) =====

local function formatFastest(value: number): string
	if value < 0 then
		return "-"
	end
	return ("%.1fs"):format(value)
end

local function openStatsModal()
	local leaderstats = player:FindFirstChild("leaderstats")
	local statistics = player:FindFirstChild("Statistics")
	local lines = {}

	if leaderstats then
		table.insert(lines, ("Rank: %s  (Level %d)"):format(leaderstats.Rank.Value, leaderstats.Level.Value))
		table.insert(
			lines,
			("Wins: %d    Coins: %d    XP: %d"):format(
				leaderstats.Wins.Value,
				leaderstats.Coins.Value,
				leaderstats.XP.Value
			)
		)
	end

	if statistics then
		table.insert(lines, "")
		table.insert(
			lines,
			("Games Played: %d    Games Won: %d"):format(statistics.GamesPlayed.Value, statistics.GamesWon.Value)
		)
		table.insert(lines, ("Questions Answered: %d"):format(statistics.QuestionsAnswered.Value))
		table.insert(
			lines,
			("Correct: %d    Incorrect: %d"):format(statistics.CorrectAnswers.Value, statistics.IncorrectAnswers.Value)
		)
		table.insert(lines, ("Accuracy: %.1f%%"):format(statistics.Accuracy.Value))
		table.insert(lines, ("Fastest Answer: %s"):format(formatFastest(statistics.FastestAnswer.Value)))
		table.insert(lines, ("Longest Streak: %d"):format(statistics.LongestStreak.Value))
	end

	openModal("Stats", table.concat(lines, "\n"))
end

statsButton.MouseButton1Click:Connect(openStatsModal)

-- ===== Statistics Terminal (in-world interaction, Message 15) =====
-- Same open logic as the lobby StatsButton above.
task.spawn(function()
	local lobby = Workspace:WaitForChild("Lobby", 10)
	local statsBuilding = lobby and lobby:WaitForChild("Buildings", 10):WaitForChild("StatisticsBuilding", 10)
	local stand = statsBuilding and statsBuilding:FindFirstChild("StatisticsTerminalStand")
	local prompt = stand and stand:FindFirstChild("StatisticsTerminalPrompt")
	if prompt then
		(prompt :: ProximityPrompt).Triggered:Connect(function(triggeringPlayer: Player)
			if triggeringPlayer == player then
				openStatsModal()
			end
		end)
	end
end)

-- ===== Play button =====

playButton.MouseButton1Click:Connect(function()
	RemoteEvents.Get("RequestJoinQueue"):FireServer()
end)

-- ===== Visibility driven by match state =====

local function updateVisibility(state: string)
	buttonBar.Visible = (state == MatchConfig.GameState.Lobby) or (state == MatchConfig.GameState.Waiting)
end

RemoteEvents.Get("GameStateChanged").OnClientEvent:Connect(updateVisibility)

task.spawn(function()
	local ok, snapshot = pcall(function()
		return RemoteFunctions.Get("GetMatchSnapshot"):InvokeServer()
	end)
	if ok and snapshot then
		updateVisibility(snapshot.gameState)
	end
end)
