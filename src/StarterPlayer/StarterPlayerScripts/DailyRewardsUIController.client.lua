--[[
	DailyRewardsUIController.client.lua

	The Daily Rewards building's interior interaction: a genuine daily-
	login streak panel, entirely separate from RewardsUIController.client.
	lua's win-based Rewards track. Opened by walking into the Daily
	Rewards building and interacting with its terminal, or via the bottom-
	bar Daily button - backed by DailyRewardsSystem (GetDailyRewardSnapshot
	/ ClaimDailyReward).

	Sized and positioned to always stay fully within the screen and
	properly centered (previously reached below the screen once the
	Lifetime Rewards section was stacked underneath the streak track) - a
	DAILY / LIFETIME tab toggle switches between the two sections instead
	of showing both at once, so the panel only ever needs to be as tall as
	whichever single section is showing, and each section gets the FULL
	content area rather than a cramped fraction of it.

	The 7-day track is a ROLLING window starting at today (not a fixed
	Day1..Day7 layout) - if you're on day 4, you see day 4 first (marked
	TODAY), then the next 6 days after it, with days already collected
	this pass marked DONE - and a separate History panel (opened from
	within the Daily tab) lets you scroll back through actual past
	calendar claims beyond the current 7-day ring, capped short at about a
	week (DailyRewardsSystem.MAX_HISTORY_ENTRIES).

	Lifetime Rewards: once a milestone is claimed, its row shows a
	permanent "COMPLETE" stamp rather than disappearing.

	Purely presentational: claiming always goes through the server, which
	re-validates the day boundary - this script only shows whatever the
	server confirms.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
local LifetimeRewardsConfig = require(ReplicatedStorage.Modules.LifetimeRewardsConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local OverlayManager = require(script.Parent.OverlayManager)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")

local getDailyRewardSnapshotFunction = RemoteFunctions.Get("GetDailyRewardSnapshot")
local claimDailyRewardFunction = RemoteFunctions.Get("ClaimDailyReward")
local getLifetimeRewardsSnapshotFunction = RemoteFunctions.Get("GetLifetimeRewardsSnapshot")
local claimLifetimeMilestoneFunction = RemoteFunctions.Get("ClaimLifetimeMilestone")

-- Forward-declared: referenced by the lifetime milestone rows' Claim
-- button handlers below, defined further down alongside the rest of the
-- lifetime-rewards state/refresh logic.
local requestLifetimeSnapshot: () -> ()
local requestSnapshot: () -> ()

-- Forward-declared: the History overlay is built further down, but the
-- Close button (built near the top) needs to hide it too.
local historyOverlay: Frame

-- ===== Overlay / panel shell =====
-- Sized to fully fit within the screen and stay centered - only ONE of
-- the Daily/Lifetime sections is ever visible at a time (see the tab
-- toggle below), so this no longer needs to be tall enough for both
-- stacked on top of each other.

local dailyOverlay = Instance.new("Frame")
dailyOverlay.Name = "DailyRewardsOverlay"
dailyOverlay.Size = UDim2.fromScale(1, 1)
dailyOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
dailyOverlay.BackgroundTransparency = 0.5
dailyOverlay.Visible = false
dailyOverlay.ZIndex = 20
dailyOverlay.Parent = mainUI

OverlayManager.Register(dailyOverlay)

local PANEL_WIDTH = 560
local PANEL_HEIGHT = 580

local dailyPanel = Instance.new("Frame")
dailyPanel.Name = "DailyRewardsPanel"
dailyPanel.Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT)
dailyPanel.Position = UDim2.new(0.5, -PANEL_WIDTH / 2, 0.5, -PANEL_HEIGHT / 2)
dailyPanel.ZIndex = 21
UITheme.StylePremiumPanel(dailyPanel, 0.05)
dailyPanel.Parent = dailyOverlay

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.fromOffset(260, 32)
titleLabel.Position = UDim2.fromOffset(16, 12)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextScaled = true
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextColor3 = UITheme.COLORS.Accent
titleLabel.Text = "Rewards"
titleLabel.ZIndex = 22
titleLabel.Parent = dailyPanel

local closeButton = Instance.new("TextButton")
closeButton.Name = "DailyRewardsCloseButton"
closeButton.Size = UDim2.fromOffset(90, 32)
closeButton.Position = UDim2.new(1, -106, 0, 12)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextScaled = true
closeButton.Text = "Close"
closeButton.TextColor3 = UITheme.COLORS.Text
closeButton.BackgroundColor3 = UITheme.COLORS.Error
closeButton.ZIndex = 22
UITheme.ApplyCorner(closeButton)
UITheme.ApplyButtonHoverEffect(closeButton)
closeButton.Parent = dailyPanel
closeButton.MouseButton1Click:Connect(function()
	dailyOverlay.Visible = false
	historyOverlay.Visible = false
end)

-- ===== DAILY / LIFETIME tab toggle =====

local TAB_ROW_Y = 52
local TAB_HEIGHT = 36
local TAB_GAP = 8
local TAB_WIDTH = (PANEL_WIDTH - 32 - TAB_GAP) / 2

local dailyTabButton = Instance.new("TextButton")
dailyTabButton.Name = "DailyTabButton"
dailyTabButton.Size = UDim2.fromOffset(TAB_WIDTH, TAB_HEIGHT)
dailyTabButton.Position = UDim2.fromOffset(16, TAB_ROW_Y)
dailyTabButton.Font = Enum.Font.GothamBlack
dailyTabButton.TextScaled = true
dailyTabButton.Text = "DAILY REWARDS"
dailyTabButton.TextColor3 = UITheme.COLORS.Text
dailyTabButton.BackgroundColor3 = UITheme.COLORS.Accent
dailyTabButton.ZIndex = 22
UITheme.ApplyCorner(dailyTabButton)
UITheme.ApplyButtonHoverEffect(dailyTabButton)
dailyTabButton.Parent = dailyPanel

local lifetimeTabButton = Instance.new("TextButton")
lifetimeTabButton.Name = "LifetimeTabButton"
lifetimeTabButton.Size = UDim2.fromOffset(TAB_WIDTH, TAB_HEIGHT)
lifetimeTabButton.Position = UDim2.fromOffset(16 + TAB_WIDTH + TAB_GAP, TAB_ROW_Y)
lifetimeTabButton.Font = Enum.Font.GothamBlack
lifetimeTabButton.TextScaled = true
lifetimeTabButton.Text = "LIFETIME REWARDS"
lifetimeTabButton.TextColor3 = UITheme.COLORS.Text
lifetimeTabButton.BackgroundColor3 = UITheme.COLORS.Panel
lifetimeTabButton.ZIndex = 22
UITheme.ApplyCorner(lifetimeTabButton)
UITheme.ApplyButtonHoverEffect(lifetimeTabButton)
lifetimeTabButton.Parent = dailyPanel

-- ===== Shared content area (one of these two views visible at a time) =====

local CONTENT_Y = 100
local CONTENT_WIDTH = PANEL_WIDTH - 32
local CONTENT_HEIGHT = PANEL_HEIGHT - CONTENT_Y - 16

local dailyView = Instance.new("Frame")
dailyView.Name = "DailyView"
dailyView.Size = UDim2.fromOffset(CONTENT_WIDTH, CONTENT_HEIGHT)
dailyView.Position = UDim2.fromOffset(16, CONTENT_Y)
dailyView.BackgroundTransparency = 1
dailyView.ZIndex = 22
dailyView.Parent = dailyPanel

local lifetimeView = Instance.new("Frame")
lifetimeView.Name = "LifetimeView"
lifetimeView.Size = UDim2.fromOffset(CONTENT_WIDTH, CONTENT_HEIGHT)
lifetimeView.Position = UDim2.fromOffset(16, CONTENT_Y)
lifetimeView.BackgroundTransparency = 1
lifetimeView.Visible = false
lifetimeView.ZIndex = 22
lifetimeView.Parent = dailyPanel

local function setActiveTab(tab: "Daily" | "Lifetime")
	dailyView.Visible = tab == "Daily"
	lifetimeView.Visible = tab == "Lifetime"
	dailyTabButton.BackgroundColor3 = if tab == "Daily" then UITheme.COLORS.Accent else UITheme.COLORS.Panel
	lifetimeTabButton.BackgroundColor3 = if tab == "Lifetime" then UITheme.COLORS.Accent else UITheme.COLORS.Panel
	if tab == "Daily" then
		requestSnapshot()
	else
		requestLifetimeSnapshot()
	end
end

dailyTabButton.MouseButton1Click:Connect(function()
	setActiveTab("Daily")
end)
lifetimeTabButton.MouseButton1Click:Connect(function()
	setActiveTab("Lifetime")
end)

-- ===== Daily view content =====

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Size = UDim2.new(1, -120, 0, 26)
statusLabel.Position = UDim2.fromOffset(0, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 15
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextColor3 = UITheme.COLORS.SubText
statusLabel.Text = ""
statusLabel.ZIndex = 22
statusLabel.Parent = dailyView

-- "Scroll back to further days that you've had" - opens a separate small
-- overlay listing the real claim history log, capped short at about a
-- week.
local historyButton = Instance.new("TextButton")
historyButton.Name = "HistoryButton"
historyButton.Size = UDim2.fromOffset(110, 26)
historyButton.Position = UDim2.new(1, -110, 0, 0)
historyButton.Font = Enum.Font.GothamBold
historyButton.TextScaled = true
historyButton.Text = "History"
historyButton.TextColor3 = UITheme.COLORS.Text
historyButton.BackgroundColor3 = UITheme.COLORS.Panel
historyButton.ZIndex = 22
UITheme.ApplyCorner(historyButton)
UITheme.ApplyButtonHoverEffect(historyButton)
historyButton.Parent = dailyView

-- 7-day track (a simple row of 7 day cards, not a scrolling list - the
-- whole cycle always fits on screen at once).
local trackRow = Instance.new("Frame")
trackRow.Name = "TrackRow"
trackRow.Size = UDim2.new(1, 0, 0, 150)
trackRow.Position = UDim2.fromOffset(0, 34)
trackRow.BackgroundTransparency = 1
trackRow.ZIndex = 22
trackRow.Parent = dailyView

local trackLayout = Instance.new("UIListLayout")
trackLayout.SortOrder = Enum.SortOrder.LayoutOrder
trackLayout.FillDirection = Enum.FillDirection.Horizontal
trackLayout.Padding = UDim.new(0, 8)
trackLayout.Parent = trackRow

-- Indexed by POSITION in the rolling window (1 = today/next claim, 2 =
-- the day after, ... 7 = six days out) rather than by a fixed day
-- number, since the whole point is the window rolls with today.
local DAY_CARD_WIDTH = 66
local dayCards: { [number]: { card: Frame, dayLabel: TextLabel, rewardLabel: TextLabel, stateLabel: TextLabel } } = {}

for position = 1, 7 do
	local card = Instance.new("Frame")
	card.Name = "Position" .. position
	card.LayoutOrder = position
	card.Size = UDim2.fromOffset(DAY_CARD_WIDTH, 150)
	card.BackgroundColor3 = UITheme.COLORS.Panel
	card.ZIndex = 22
	UITheme.ApplyCorner(card)
	card.Parent = trackRow

	local dayLabel = Instance.new("TextLabel")
	dayLabel.Name = "DayLabel"
	dayLabel.Size = UDim2.new(1, 0, 0, 22)
	dayLabel.Position = UDim2.fromOffset(0, 8)
	dayLabel.BackgroundTransparency = 1
	dayLabel.Font = Enum.Font.GothamBold
	dayLabel.TextScaled = true
	dayLabel.TextColor3 = UITheme.COLORS.SubText
	dayLabel.Text = ""
	dayLabel.ZIndex = 23
	dayLabel.Parent = card

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "RewardLabel"
	rewardLabel.Size = UDim2.new(1, -6, 0, 80)
	rewardLabel.Position = UDim2.fromOffset(3, 34)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Font = Enum.Font.Gotham
	rewardLabel.TextSize = 12
	rewardLabel.TextWrapped = true
	rewardLabel.TextColor3 = UITheme.COLORS.Gold
	rewardLabel.Text = ""
	rewardLabel.ZIndex = 23
	rewardLabel.Parent = card

	local stateLabel = Instance.new("TextLabel")
	stateLabel.Name = "StateLabel"
	stateLabel.Size = UDim2.new(1, 0, 0, 20)
	stateLabel.Position = UDim2.new(0, 0, 1, -24)
	stateLabel.BackgroundTransparency = 1
	stateLabel.Font = Enum.Font.GothamBold
	stateLabel.TextScaled = true
	stateLabel.TextColor3 = UITheme.COLORS.SubText
	stateLabel.Text = ""
	stateLabel.ZIndex = 23
	stateLabel.Parent = card

	dayCards[position] = { card = card, dayLabel = dayLabel, rewardLabel = rewardLabel, stateLabel = stateLabel }
end

local claimButton = Instance.new("TextButton")
claimButton.Name = "ClaimTodayButton"
claimButton.Size = UDim2.new(1, 0, 0, 48)
claimButton.Position = UDim2.fromOffset(0, 192)
claimButton.Font = Enum.Font.GothamBlack
claimButton.TextScaled = true
claimButton.TextColor3 = UITheme.COLORS.Text
claimButton.BackgroundColor3 = UITheme.COLORS.Success
claimButton.Text = "CLAIM TODAY'S REWARD"
claimButton.ZIndex = 22
UITheme.ApplyCorner(claimButton)
UITheme.ApplyButtonHoverEffect(claimButton)
claimButton.Parent = dailyView

-- ===== Lifetime view content - a scrolling, categorized milestone list.
-- Gets the FULL content area now that it's not sharing space with the
-- streak track (previously cramped into a fixed-height stub below it). =====

local lifetimeList = Instance.new("ScrollingFrame")
lifetimeList.Name = "LifetimeList"
lifetimeList.Size = UDim2.new(1, 0, 1, 0)
lifetimeList.Position = UDim2.fromOffset(0, 0)
lifetimeList.BackgroundTransparency = 1
lifetimeList.BorderSizePixel = 0
lifetimeList.ScrollBarThickness = 6
lifetimeList.CanvasSize = UDim2.fromOffset(0, 0)
lifetimeList.AutomaticCanvasSize = Enum.AutomaticSize.Y
lifetimeList.ZIndex = 22
lifetimeList.Parent = lifetimeView

local lifetimeListLayout = Instance.new("UIListLayout")
lifetimeListLayout.SortOrder = Enum.SortOrder.LayoutOrder
lifetimeListLayout.Padding = UDim.new(0, 8)
lifetimeListLayout.Parent = lifetimeList

local lifetimeRows: { [string]: { row: Frame, label: TextLabel, barFill: Frame, claimButton: TextButton, completeBadge: TextLabel } } = {}

-- Grouped by category - a small header label per category, then that
-- category's rows, rather than one flat list.
local layoutOrder = 0
local lastCategory: string? = nil
for _, milestone in ipairs(LifetimeRewardsConfig.GetSorted()) do
	if milestone.category ~= lastCategory then
		lastCategory = milestone.category
		layoutOrder += 1
		local header = Instance.new("TextLabel")
		header.Name = "Category_" .. milestone.category
		header.LayoutOrder = layoutOrder
		header.Size = UDim2.new(1, 0, 0, 20)
		header.BackgroundTransparency = 1
		header.Font = Enum.Font.GothamBold
		header.TextSize = 13
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.TextColor3 = UITheme.COLORS.SubText
		header.Text = milestone.category:upper()
		header.ZIndex = 22
		header.Parent = lifetimeList
	end

	layoutOrder += 1
	local row = Instance.new("Frame")
	row.Name = "Milestone_" .. milestone.id
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundColor3 = UITheme.COLORS.Panel
	row.ZIndex = 22
	UITheme.ApplyCorner(row)
	row.Parent = lifetimeList

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -140, 1, 0)
	label.Position = UDim2.fromOffset(10, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = UITheme.COLORS.Text
	label.Text = milestone.label
	label.ZIndex = 23
	label.Parent = row

	local barBackground = Instance.new("Frame")
	barBackground.Name = "BarBackground"
	barBackground.Size = UDim2.new(1, -150, 0, 6)
	barBackground.Position = UDim2.new(0, 10, 1, -12)
	barBackground.BackgroundColor3 = Color3.fromRGB(40, 42, 54)
	barBackground.ZIndex = 23
	UITheme.ApplyCorner(barBackground)
	barBackground.Parent = row

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = UITheme.COLORS.Accent
	barFill.ZIndex = 24
	UITheme.ApplyCorner(barFill)
	barFill.Parent = barBackground

	local claimBtn = Instance.new("TextButton")
	claimBtn.Name = "ClaimButton"
	claimBtn.Size = UDim2.fromOffset(110, 30)
	claimBtn.Position = UDim2.new(1, -120, 0, 5)
	claimBtn.Font = Enum.Font.GothamBold
	claimBtn.TextScaled = true
	claimBtn.TextColor3 = UITheme.COLORS.Text
	claimBtn.BackgroundColor3 = UITheme.COLORS.Success
	claimBtn.Text = "CLAIM"
	claimBtn.Visible = false
	claimBtn.ZIndex = 23
	UITheme.ApplyCorner(claimBtn)
	UITheme.ApplyButtonHoverEffect(claimBtn)
	claimBtn.Parent = row

	claimBtn.MouseButton1Click:Connect(function()
		claimBtn.Active = false
		local result = claimLifetimeMilestoneFunction:InvokeServer(milestone.id)
		claimBtn.Active = true
		if result and result.success then
			requestLifetimeSnapshot()
		end
	end)

	-- A permanent stamp shown in place of the Claim button once claimed -
	-- the row itself is NEVER destroyed/hidden, it only ever flips which
	-- of these two widgets is visible.
	local completeBadge = Instance.new("TextLabel")
	completeBadge.Name = "CompleteBadge"
	completeBadge.Size = UDim2.fromOffset(110, 30)
	completeBadge.Position = UDim2.new(1, -120, 0, 5)
	completeBadge.Rotation = -6
	completeBadge.Font = Enum.Font.GothamBlack
	completeBadge.TextScaled = true
	completeBadge.TextColor3 = UITheme.COLORS.Success
	completeBadge.BackgroundTransparency = 1
	completeBadge.Text = "\u{2713} COMPLETE"
	completeBadge.Visible = false
	completeBadge.ZIndex = 24
	completeBadge.Parent = row

	local completeBadgeStroke = Instance.new("UIStroke")
	completeBadgeStroke.Color = UITheme.COLORS.Success
	completeBadgeStroke.Thickness = 1.5
	completeBadgeStroke.Parent = completeBadge

	lifetimeRows[milestone.id] = { row = row, label = label, barFill = barFill, claimButton = claimBtn, completeBadge = completeBadge }
end

-- ===== History overlay ("scroll back to further days that you've had") =====

historyOverlay = Instance.new("Frame")
historyOverlay.Name = "DailyHistoryOverlay"
historyOverlay.Size = UDim2.fromScale(1, 1)
historyOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
historyOverlay.BackgroundTransparency = 0.5
historyOverlay.Visible = false
historyOverlay.ZIndex = 25
historyOverlay.Parent = mainUI

-- Deliberately NOT registered with OverlayManager - this is a nested
-- sub-panel over the Daily Rewards panel (opened from within it), not a
-- sibling top-level panel, so opening it must NOT hide the Daily Rewards
-- panel behind it the way OverlayManager.Show would.

local historyPanel = Instance.new("Frame")
historyPanel.Name = "DailyHistoryPanel"
historyPanel.Size = UDim2.fromOffset(420, 480)
historyPanel.Position = UDim2.new(0.5, -210, 0.5, -240)
historyPanel.ZIndex = 26
UITheme.StylePremiumPanel(historyPanel, 0.05)
historyPanel.Parent = historyOverlay

local historyTitleLabel = Instance.new("TextLabel")
historyTitleLabel.Name = "TitleLabel"
historyTitleLabel.Size = UDim2.new(1, -120, 0, 32)
historyTitleLabel.Position = UDim2.fromOffset(16, 12)
historyTitleLabel.BackgroundTransparency = 1
historyTitleLabel.Font = Enum.Font.GothamBlack
historyTitleLabel.TextScaled = true
historyTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
historyTitleLabel.TextColor3 = UITheme.COLORS.Accent
historyTitleLabel.Text = "Claim History"
historyTitleLabel.ZIndex = 27
historyTitleLabel.Parent = historyPanel

local historyCloseButton = Instance.new("TextButton")
historyCloseButton.Name = "HistoryCloseButton"
historyCloseButton.Size = UDim2.fromOffset(90, 32)
historyCloseButton.Position = UDim2.new(1, -106, 0, 12)
historyCloseButton.Font = Enum.Font.GothamBold
historyCloseButton.TextScaled = true
historyCloseButton.Text = "Close"
historyCloseButton.TextColor3 = UITheme.COLORS.Text
historyCloseButton.BackgroundColor3 = UITheme.COLORS.Error
historyCloseButton.ZIndex = 27
UITheme.ApplyCorner(historyCloseButton)
UITheme.ApplyButtonHoverEffect(historyCloseButton)
historyCloseButton.Parent = historyPanel
historyCloseButton.MouseButton1Click:Connect(function()
	historyOverlay.Visible = false
end)

local historyScroll = Instance.new("ScrollingFrame")
historyScroll.Name = "HistoryScroll"
historyScroll.Size = UDim2.new(1, -32, 1, -64)
historyScroll.Position = UDim2.fromOffset(16, 56)
historyScroll.BackgroundTransparency = 1
historyScroll.BorderSizePixel = 0
historyScroll.ScrollBarThickness = 6
historyScroll.CanvasSize = UDim2.fromOffset(0, 0)
historyScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
historyScroll.ZIndex = 27
historyScroll.Parent = historyPanel

local historyScrollLayout = Instance.new("UIListLayout")
historyScrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
historyScrollLayout.Padding = UDim.new(0, 6)
historyScrollLayout.Parent = historyScroll

local historyEmptyLabel = Instance.new("TextLabel")
historyEmptyLabel.Name = "EmptyLabel"
historyEmptyLabel.Size = UDim2.new(1, 0, 0, 40)
historyEmptyLabel.BackgroundTransparency = 1
historyEmptyLabel.Font = Enum.Font.Gotham
historyEmptyLabel.TextSize = 14
historyEmptyLabel.TextColor3 = UITheme.COLORS.SubText
historyEmptyLabel.Text = "No claims yet - come back daily to start your streak!"
historyEmptyLabel.Visible = false
historyEmptyLabel.ZIndex = 27
historyEmptyLabel.Parent = historyScroll

--[[
	Rebuilds the history list from `historyEntries` (most-recent-first, as
	returned by DailyRewardsSystem.BuildSnapshot). Rebuilt fresh each time
	the panel opens rather than kept in sync incrementally, since it's
	opened rarely and the list is short (capped at 7 entries - about a
	week back).
]]
local function refreshHistoryList(historyEntries)
	for _, child in ipairs(historyScroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	historyEmptyLabel.Visible = #historyEntries == 0

	for i, entry in ipairs(historyEntries) do
		local row = Instance.new("Frame")
		row.Name = "Claim" .. i
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 36)
		row.BackgroundColor3 = UITheme.COLORS.Panel
		row.ZIndex = 27
		UITheme.ApplyCorner(row)
		row.Parent = historyScroll

		local dateLabel = Instance.new("TextLabel")
		dateLabel.Name = "DateLabel"
		dateLabel.Size = UDim2.new(0, 140, 1, 0)
		dateLabel.Position = UDim2.fromOffset(10, 0)
		dateLabel.BackgroundTransparency = 1
		dateLabel.Font = Enum.Font.Gotham
		dateLabel.TextSize = 13
		dateLabel.TextXAlignment = Enum.TextXAlignment.Left
		dateLabel.TextColor3 = UITheme.COLORS.SubText
		dateLabel.Text = os.date("!%Y-%m-%d", entry.unixTime)
		dateLabel.ZIndex = 28
		dateLabel.Parent = row

		local rewardLabel = Instance.new("TextLabel")
		rewardLabel.Name = "RewardLabel"
		rewardLabel.Size = UDim2.new(1, -160, 1, 0)
		rewardLabel.Position = UDim2.fromOffset(150, 0)
		rewardLabel.BackgroundTransparency = 1
		rewardLabel.Font = Enum.Font.GothamBold
		rewardLabel.TextSize = 13
		rewardLabel.TextXAlignment = Enum.TextXAlignment.Left
		rewardLabel.TextColor3 = UITheme.COLORS.Gold
		rewardLabel.Text = ("Day %d: %s"):format(entry.day, entry.label)
		rewardLabel.ZIndex = 28
		rewardLabel.Parent = row
	end
end

historyButton.MouseButton1Click:Connect(function()
	historyOverlay.Visible = true
	UITheme.PlayOpenTween(historyPanel)
	local ok, snapshot = pcall(function()
		return getDailyRewardSnapshotFunction:InvokeServer()
	end)
	if ok and snapshot then
		refreshHistoryList(snapshot.history)
	end
end)

-- ===== State =====

local function formatCountdown(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	return ("%dh %dm"):format(hours, minutes)
end

local function refreshFromSnapshot(snapshot)
	if not snapshot then
		return
	end

	-- snapshot.track is already ordered starting at today (offsetFromToday
	-- 0..6), so array position IS window position - no day-number lookup
	-- needed here anymore.
	for position, entry in ipairs(snapshot.track) do
		local widgets = dayCards[position]
		if widgets then
			widgets.rewardLabel.Text = entry.label
			widgets.dayLabel.Text = if entry.offsetFromToday == 0 then "TODAY"
				elseif entry.offsetFromToday == 1 then "+1 DAY"
				else ("+%d DAYS"):format(entry.offsetFromToday)

			if entry.isToday then
				widgets.card.BackgroundColor3 = UITheme.COLORS.Accent
				widgets.stateLabel.Text = "TODAY"
				widgets.stateLabel.TextColor3 = UITheme.COLORS.Text
			elseif entry.isCollected then
				widgets.card.BackgroundColor3 = UITheme.COLORS.Panel
				widgets.stateLabel.Text = "\u{2713} DONE"
				widgets.stateLabel.TextColor3 = UITheme.COLORS.Success
			elseif entry.offsetFromToday == 0 and not entry.isToday then
				-- Today's slot but already claimed for real today.
				widgets.card.BackgroundColor3 = UITheme.COLORS.Panel
				widgets.stateLabel.Text = "\u{2713} CLAIMED"
				widgets.stateLabel.TextColor3 = UITheme.COLORS.Success
			else
				widgets.card.BackgroundColor3 = UITheme.COLORS.Panel
				widgets.stateLabel.Text = ""
			end
		end
	end

	if snapshot.canClaimToday then
		claimButton.Visible = true
		claimButton.Text = "CLAIM TODAY'S REWARD"
		claimButton.BackgroundColor3 = UITheme.COLORS.Success
		statusLabel.Text = ("Streak: Day %d/7  \u{2022}  %d total claims"):format(
			snapshot.currentStreakDay,
			snapshot.totalClaims
		)
	else
		claimButton.Visible = true
		claimButton.Text = ("ALREADY CLAIMED \u{2022} back in %s"):format(formatCountdown(snapshot.secondsUntilNextDay))
		claimButton.BackgroundColor3 = UITheme.COLORS.Panel
		statusLabel.Text = ("Streak: Day %d/7  \u{2022}  %d total claims"):format(
			snapshot.currentStreakDay,
			snapshot.totalClaims
		)
	end
end

local latestSnapshot = nil

requestSnapshot = function()
	local ok, snapshot = pcall(function()
		return getDailyRewardSnapshotFunction:InvokeServer()
	end)
	if ok and snapshot then
		latestSnapshot = snapshot
		refreshFromSnapshot(snapshot)
	end
end

-- ===== Lifetime Rewards state/refresh =====

requestLifetimeSnapshot = function()
	local ok, snapshot = pcall(function()
		return getLifetimeRewardsSnapshotFunction:InvokeServer()
	end)
	if not (ok and snapshot) then
		return
	end

	for _, milestone in ipairs(snapshot.milestones) do
		local widgets = lifetimeRows[milestone.id]
		if widgets then
			local progressFraction = math.clamp(milestone.progress / milestone.target, 0, 1)
			widgets.barFill.Size = UDim2.new(progressFraction, 0, 1, 0)
			if milestone.status == "Claimed" then
				widgets.row.BackgroundColor3 = UITheme.COLORS.Panel
				widgets.label.Text = milestone.label
				widgets.claimButton.Visible = false
				widgets.completeBadge.Visible = true
				widgets.barFill.BackgroundColor3 = UITheme.COLORS.Success
			elseif milestone.status == "Available" then
				widgets.label.Text = milestone.label
				widgets.claimButton.Visible = true
				widgets.completeBadge.Visible = false
				widgets.barFill.BackgroundColor3 = UITheme.COLORS.Success
			else
				local displayProgress = milestone.progress
				-- Time Played milestones track fractional hours - show one
				-- decimal place there instead of a misleadingly-truncated int.
				local progressText = if milestone.category == "Time Played"
					then ("%.1f / %d"):format(displayProgress, milestone.target)
					else ("%d / %d"):format(math.floor(displayProgress), milestone.target)
				widgets.label.Text = ("%s  (%s)"):format(milestone.label, progressText)
				widgets.claimButton.Visible = false
				widgets.completeBadge.Visible = false
				widgets.barFill.BackgroundColor3 = UITheme.COLORS.Accent
			end
		end
	end
end

claimButton.MouseButton1Click:Connect(function()
	if not (latestSnapshot and latestSnapshot.canClaimToday) then
		return
	end
	claimButton.Active = false
	local result = claimDailyRewardFunction:InvokeServer()
	claimButton.Active = true
	if result and result.success then
		requestSnapshot()
	end
end)

-- ===== Open/close =====

local function openDailyRewardsPanel()
	OverlayManager.Show(dailyOverlay)
	UITheme.PlayOpenTween(dailyPanel)
	setActiveTab("Daily")
end

-- ===== Bottom-bar "Daily" button =====
-- LobbyUIController.client.lua builds this button and leaves a no-op
-- connection - same handoff pattern ShopUIController/RewardsUIController
-- already use for their own bottom-bar buttons.
do
	local lobbyButtonBar = mainUI:WaitForChild("LobbyButtonBar")
	local dailyButton = lobbyButtonBar:WaitForChild("DailyButton") :: TextButton
	dailyButton.MouseButton1Click:Connect(openDailyRewardsPanel)
end

-- ===== Daily Rewards Terminal (in-world interaction) =====

task.spawn(function()
	local lobby = Workspace:WaitForChild("Lobby", 10)
	local rewardsBuilding = lobby and lobby:WaitForChild("Buildings", 10):WaitForChild("DailyRewards", 10)
	local stand = rewardsBuilding and rewardsBuilding:FindFirstChild("DailyRewardsTerminalStand")
	local prompt = stand and stand:FindFirstChild("DailyRewardsTerminalPrompt")
	if prompt then
		(prompt :: ProximityPrompt).Triggered:Connect(function(triggeringPlayer: Player)
			if triggeringPlayer == player then
				openDailyRewardsPanel()
			end
		end)
	end
end)
