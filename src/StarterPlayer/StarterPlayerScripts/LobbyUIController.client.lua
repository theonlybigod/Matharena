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
local GameplayConfig = require(ReplicatedStorage.Modules.GameplayConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local OverlayManager = require(script.Parent.OverlayManager)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")

-- ===== Button bar =====
-- Message 26 ("make the whole interface 100x better"): bigger, icon-
-- driven premium nav buttons (UITheme.CreateNavButton) instead of plain
-- flat text buttons - each one gets a glyph, a label, and a glowing
-- underline accent that brightens on hover.

local buttonBar = Instance.new("Frame")
buttonBar.Name = "LobbyButtonBar"
-- Inventory button added: widened from 880 to 1000 (and re-centered to
-- match) to fit the new 8th button without crowding - 8 buttons * 112
-- wide + 7 gaps * 14 padding = 994, so 1000 leaves a little breathing
-- room, same margin the 7-button version kept.
buttonBar.Size = UDim2.fromOffset(1000, 92)
buttonBar.Position = UDim2.new(0.5, -500, 1, -112)
buttonBar.BackgroundTransparency = 1
buttonBar.Parent = mainUI

local barLayout = Instance.new("UIListLayout")
barLayout.SortOrder = Enum.SortOrder.LayoutOrder
barLayout.FillDirection = Enum.FillDirection.Horizontal
barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
barLayout.Padding = UDim.new(0, 14)
barLayout.Parent = buttonBar

local function createButton(name: string, icon: string, text: string, order: number): TextButton
	local button = UITheme.CreateNavButton(name, icon, text)
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(112, 84)
	button.Parent = buttonBar
	return button
end

local playButton = createButton("PlayButton", "\u{25B6}", "Play", 1)
local playButtonStroke = playButton:FindFirstChildOfClass("UIStroke")
if playButtonStroke then
	playButtonStroke.Color = UITheme.COLORS.Accent
	playButtonStroke.Transparency = 0.1
end

local practiceButton = createButton("PracticeButton", "\u{1F4DD}", "Practice", 2)
local shopButton = createButton("ShopButton", "\u{1F6D2}", "Shop", 3)
local statsButton = createButton("StatsButton", "\u{1F4CA}", "Stats", 4)
local settingsButton = createButton("SettingsButton", "\u{2699}", "Settings", 5)
local dailyRewardsButton = createButton("RewardsButton", "\u{1F3C6}", "Rewards", 6)
-- Message 33 ("a daily reward section in the bottom tab that shows
-- you today's daily reward and lets you claim it, as well as the next
-- 6 days"): a SEVENTH bottom-bar button, distinct from RewardsButton
-- above (that one is the win-based track's quick-claim button, hidden
-- unless something's currently claimable - see RewardsUIController's
-- own doc comment). This one always shows, and opens the SAME 7-day
-- streak panel the Daily Rewards building's terminal opens - see
-- DailyRewardsUIController.client.lua, which owns this button's click
-- handling (same handoff pattern as ShopButton/PracticeButton below).
local dailyButton = createButton("DailyButton", "\u{1F4C5}", "Daily", 7)
-- Inventory: reward-only cosmetics and purchased cosmetics alike land
-- here once owned, organized by category (Trails/Accessories/Name
-- Colors/Victory Animations/Question Themes/Titles) - separate from the
-- Shop's purchasable/Rewards-to-earn grids, this is just "what do I
-- already have and what's equipped". See InventoryUIController.client.lua,
-- which owns this button's click handling (same handoff pattern as
-- ShopButton/PracticeButton above).
local inventoryButton = createButton("InventoryButton", "\u{1F392}", "Items", 8)

-- ===== Generic modal (reused by Settings/Stats) =====
-- Message 26: upgraded to the premium panel style (gradient + glowing
-- border), larger, with a proper title bar/divider instead of a plain
-- flat rectangle.

local modalOverlay = Instance.new("Frame")
modalOverlay.Name = "ModalOverlay"
modalOverlay.Size = UDim2.fromScale(1, 1)
modalOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
modalOverlay.BackgroundTransparency = 0.45
modalOverlay.Visible = false
modalOverlay.ZIndex = 10
modalOverlay.Parent = mainUI

local modalPanel = Instance.new("Frame")
modalPanel.Name = "ModalPanel"
modalPanel.Size = UDim2.fromOffset(480, 380)
modalPanel.Position = UDim2.new(0.5, -240, 0.5, -190)
modalPanel.ZIndex = 11
UITheme.StylePremiumPanel(modalPanel, 0.05)
modalPanel.Parent = modalOverlay

local modalTitle = Instance.new("TextLabel")
modalTitle.Name = "ModalTitle"
modalTitle.Size = UDim2.new(1, -28, 0, 44)
modalTitle.Position = UDim2.fromOffset(14, 14)
modalTitle.BackgroundTransparency = 1
modalTitle.Font = Enum.Font.GothamBlack
modalTitle.TextScaled = true
modalTitle.TextXAlignment = Enum.TextXAlignment.Left
modalTitle.TextColor3 = UITheme.COLORS.Accent
modalTitle.ZIndex = 12
modalTitle.Parent = modalPanel

local modalDivider = Instance.new("Frame")
modalDivider.Name = "Divider"
modalDivider.Size = UDim2.new(1, -28, 0, 2)
modalDivider.Position = UDim2.fromOffset(14, 60)
modalDivider.BackgroundColor3 = UITheme.COLORS.Accent
modalDivider.BackgroundTransparency = 0.7
modalDivider.BorderSizePixel = 0
modalDivider.ZIndex = 12
modalDivider.Parent = modalPanel

local modalBody = Instance.new("TextLabel")
modalBody.Name = "ModalBody"
modalBody.Size = UDim2.new(1, -28, 1, -130)
modalBody.Position = UDim2.fromOffset(14, 76)
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
closeButton.Parent = modalPanel

closeButton.MouseButton1Click:Connect(function()
	modalOverlay.Visible = false
end)

OverlayManager.Register(modalOverlay)

local function openModal(title: string, body: string)
	modalTitle.Text = title
	modalBody.Text = body
	OverlayManager.Show(modalOverlay)
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

dailyButton.MouseButton1Click:Connect(function()
	-- Intentionally not handled here - DailyRewardsUIController.client.lua
	-- owns this button's click handling and opens the real 7-day daily
	-- streak panel, same handoff pattern as ShopButton above.
end)

inventoryButton.MouseButton1Click:Connect(function()
	-- Intentionally not handled here - InventoryUIController.client.lua owns
	-- this button's click handling and opens the real owned-items panel,
	-- same handoff pattern as ShopButton above.
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

-- ===== Play button (Play redesign: difficulty tier selection) =====
-- Pressing Play used to instantly fire RequestJoinQueue with no choice
-- involved. Now shows a tier-select popup first (5 named difficulty
-- tiers, GameplayConfig.QUEUE_TIERS - Easy Mode's simple addition up
-- through Master Mode's everything-mixed-together), which the
-- player can cancel out of at any point before committing to a queue -
-- same "press the button -> pick an option -> confirm" shape as the
-- Practice mode popup (PracticeUIController.client.lua), reused rather
-- than inventing a different pattern for a very similar choice.
--
-- Multi-Place Play Mode (README.md's Play Mode Architecture section):
-- picking a tier here now fires "RequestPlayDifficulty", not
-- "RequestJoinQueue" directly. PlaceTeleportSystem (server) decides
-- whether that means joining the local queue (already on the right
-- difficulty's Place) or a cross-server TeleportService hop to the
-- Place dedicated to that tier - the client never picks a destination
-- itself, only ever a tier NUMBER. A failed teleport fires
-- "PlayTeleportFailed" back, shown here as a recoverable modal rather
-- than silently doing nothing.

local tierOverlay = Instance.new("Frame")
tierOverlay.Name = "PlayTierOverlay"
tierOverlay.Size = UDim2.fromScale(1, 1)
tierOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
tierOverlay.BackgroundTransparency = 0.5
tierOverlay.Visible = false
tierOverlay.ZIndex = 25
tierOverlay.Parent = mainUI

local tierPanel = Instance.new("Frame")
tierPanel.Name = "PlayTierPanel"
-- Message 32: shrunk from 460 to 400 tall (and re-centered to match) now
-- that there are 5 tiers instead of 6 - keeps the Cancel button close
-- under the last option instead of leaving a large empty gap.
tierPanel.Size = UDim2.fromOffset(420, 400)
tierPanel.Position = UDim2.new(0.5, -210, 0.5, -200)
tierPanel.ZIndex = 26
UITheme.StylePanel(tierPanel, 0.05)
tierPanel.Parent = tierOverlay

local tierTitle = Instance.new("TextLabel")
tierTitle.Name = "Title"
tierTitle.Size = UDim2.new(1, -16, 0, 36)
tierTitle.Position = UDim2.fromOffset(8, 10)
tierTitle.BackgroundTransparency = 1
tierTitle.Font = Enum.Font.GothamBlack
tierTitle.TextScaled = true
tierTitle.TextColor3 = UITheme.COLORS.Text
tierTitle.Text = "CHOOSE YOUR DIFFICULTY"
tierTitle.ZIndex = 27
tierTitle.Parent = tierPanel

local tierCancelButton = Instance.new("TextButton")
tierCancelButton.Name = "CancelButton"
tierCancelButton.Size = UDim2.new(1, -16, 0, 34)
tierCancelButton.Position = UDim2.fromOffset(8, 354)
tierCancelButton.Font = Enum.Font.GothamBold
tierCancelButton.TextScaled = true
tierCancelButton.Text = "CANCEL"
tierCancelButton.TextColor3 = UITheme.COLORS.Text
tierCancelButton.BackgroundColor3 = UITheme.COLORS.Error
tierCancelButton.ZIndex = 27
UITheme.ApplyCorner(tierCancelButton)
UITheme.ApplyButtonHoverEffect(tierCancelButton)
tierCancelButton.Parent = tierPanel

tierCancelButton.MouseButton1Click:Connect(function()
	tierOverlay.Visible = false
end)

OverlayManager.Register(tierOverlay)

for i, tier in ipairs(GameplayConfig.QUEUE_TIERS) do
	local tierButton = Instance.new("TextButton")
	tierButton.Name = "Tier" .. tier.id .. "Button"
	tierButton.Size = UDim2.new(1, -16, 0, 56)
	tierButton.Position = UDim2.fromOffset(8, 50 + (i - 1) * 60)
	tierButton.Font = Enum.Font.GothamBold
	tierButton.TextColor3 = UITheme.COLORS.Text
	tierButton.BackgroundColor3 = UITheme.COLORS.Panel
	tierButton.AutoButtonColor = false
	tierButton.Text = ""
	tierButton.ZIndex = 27
	UITheme.ApplyCorner(tierButton)
	UITheme.ApplyButtonHoverEffect(tierButton)
	tierButton.Parent = tierPanel

	local tierLabel = Instance.new("TextLabel")
	tierLabel.Name = "Label"
	tierLabel.Size = UDim2.new(1, -16, 0, 24)
	tierLabel.Position = UDim2.fromOffset(8, 4)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Font = Enum.Font.GothamBold
	tierLabel.TextScaled = true
	tierLabel.TextXAlignment = Enum.TextXAlignment.Left
	tierLabel.TextColor3 = UITheme.COLORS.Accent
	tierLabel.Text = ("%d. %s"):format(tier.id, tier.name)
	tierLabel.ZIndex = 28
	tierLabel.Parent = tierButton

	local tierDescription = Instance.new("TextLabel")
	tierDescription.Name = "Description"
	tierDescription.Size = UDim2.new(1, -16, 0, 22)
	tierDescription.Position = UDim2.fromOffset(8, 28)
	tierDescription.BackgroundTransparency = 1
	tierDescription.Font = Enum.Font.Gotham
	tierDescription.TextSize = 14
	tierDescription.TextXAlignment = Enum.TextXAlignment.Left
	tierDescription.TextColor3 = UITheme.COLORS.SubText
	tierDescription.Text = tier.description
	tierDescription.ZIndex = 28
	tierDescription.Parent = tierButton

	tierButton.MouseButton1Click:Connect(function()
		tierOverlay.Visible = false
		RemoteEvents.Get("RequestPlayDifficulty"):FireServer(tier.id)
	end)
end

playButton.MouseButton1Click:Connect(function()
	OverlayManager.Show(tierOverlay)
	UITheme.PlayOpenTween(tierPanel)
end)

-- A failed cross-server Play Mode teleport (rate limit, destination
-- Place not configured/published yet, a Roblox outage, etc.) leaves the
-- player exactly where they were - never queued, never stuck - so this
-- is purely informational: explain what happened and let them press
-- Play again whenever they're ready.
RemoteEvents.Get("PlayTeleportFailed").OnClientEvent:Connect(function(payload)
	local tier = payload and typeof(payload) == "table" and GameplayConfig.GetQueueTier(payload.tierId)
	local tierName = tier and tier.name or "that difficulty"
	local reason = payload and typeof(payload) == "table" and payload.reason

	local body = if reason == "NotConfigured"
		then ("%s isn't set up yet - its server hasn't been published. Try again later or pick a different difficulty."):format(
			tierName
		)
		else ("Couldn't move you to %s right now. You're still right here - try Play again in a moment."):format(
			tierName
		)

	openModal("Couldn't Start", body)
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
