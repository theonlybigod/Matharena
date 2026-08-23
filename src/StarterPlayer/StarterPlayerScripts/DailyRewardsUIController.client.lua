--[[
	DailyRewardsUIController.client.lua

	The Daily Rewards building's interior interaction: a genuine daily-
	login streak panel, entirely separate from RewardsUIController.client.
	lua's win-based Rewards track (that one is opened via the lobby's
	"RewardsButton", quick-claim only, hidden unless something's currently
	claimable - see that script's own doc comment). This one is opened
	ONLY by walking into the Daily Rewards building and interacting with
	its terminal (DailyRewardsTerminalPrompt, built in BuildingInteriors.
	FurnishRewards) - "go to the daily reward building, see your progress
	in bigger things and how close you are to them" - so the WHOLE 7-day
	track is always shown here, not just today's single reward, backed by
	DailyRewardsSystem (GetDailyRewardSnapshot / ClaimDailyReward).

	Purely presentational: claiming always goes through the server, which
	re-validates the day boundary - this script only shows whatever the
	server confirms.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local OverlayManager = require(script.Parent.OverlayManager)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")

local getDailyRewardSnapshotFunction = RemoteFunctions.Get("GetDailyRewardSnapshot")
local claimDailyRewardFunction = RemoteFunctions.Get("ClaimDailyReward")

-- ===== Overlay / panel shell =====

local dailyOverlay = Instance.new("Frame")
dailyOverlay.Name = "DailyRewardsOverlay"
dailyOverlay.Size = UDim2.fromScale(1, 1)
dailyOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
dailyOverlay.BackgroundTransparency = 0.5
dailyOverlay.Visible = false
dailyOverlay.ZIndex = 20
dailyOverlay.Parent = mainUI

OverlayManager.Register(dailyOverlay)

local dailyPanel = Instance.new("Frame")
dailyPanel.Name = "DailyRewardsPanel"
dailyPanel.Size = UDim2.fromOffset(560, 440)
dailyPanel.Position = UDim2.new(0.5, -280, 0.5, -220)
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
titleLabel.Text = "Daily Rewards"
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
end)

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Size = UDim2.new(1, -32, 0, 26)
statusLabel.Position = UDim2.fromOffset(16, 52)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 16
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextColor3 = UITheme.COLORS.SubText
statusLabel.Text = ""
statusLabel.ZIndex = 22
statusLabel.Parent = dailyPanel

-- ===== 7-day track (a simple row of 7 day cards, not a scrolling list -
-- the whole cycle always fits on screen at once, matching "see your
-- progress in bigger things") =====

local trackRow = Instance.new("Frame")
trackRow.Name = "TrackRow"
trackRow.Size = UDim2.new(1, -32, 0, 150)
trackRow.Position = UDim2.fromOffset(16, 88)
trackRow.BackgroundTransparency = 1
trackRow.ZIndex = 22
trackRow.Parent = dailyPanel

local trackLayout = Instance.new("UIListLayout")
trackLayout.SortOrder = Enum.SortOrder.LayoutOrder
trackLayout.FillDirection = Enum.FillDirection.Horizontal
trackLayout.Padding = UDim.new(0, 8)
trackLayout.Parent = trackRow

local dayCards: { [number]: { card: Frame, dayLabel: TextLabel, rewardLabel: TextLabel, stateLabel: TextLabel } } = {}

for day = 1, 7 do
	local card = Instance.new("Frame")
	card.Name = "Day" .. day
	card.LayoutOrder = day
	card.Size = UDim2.fromOffset(70, 150)
	card.BackgroundColor3 = UITheme.COLORS.Panel
	card.ZIndex = 22
	UITheme.ApplyCorner(card)
	card.Parent = trackRow

	local dayLabel = Instance.new("TextLabel")
	dayLabel.Name = "DayLabel"
	dayLabel.Size = UDim2.new(1, 0, 0, 24)
	dayLabel.Position = UDim2.fromOffset(0, 8)
	dayLabel.BackgroundTransparency = 1
	dayLabel.Font = Enum.Font.GothamBold
	dayLabel.TextScaled = true
	dayLabel.TextColor3 = UITheme.COLORS.SubText
	dayLabel.Text = "DAY " .. day
	dayLabel.ZIndex = 23
	dayLabel.Parent = card

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "RewardLabel"
	rewardLabel.Size = UDim2.new(1, -8, 0, 80)
	rewardLabel.Position = UDim2.fromOffset(4, 36)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Font = Enum.Font.Gotham
	rewardLabel.TextSize = 13
	rewardLabel.TextWrapped = true
	rewardLabel.TextColor3 = UITheme.COLORS.Gold
	rewardLabel.Text = ""
	rewardLabel.ZIndex = 23
	rewardLabel.Parent = card

	local stateLabel = Instance.new("TextLabel")
	stateLabel.Name = "StateLabel"
	stateLabel.Size = UDim2.new(1, 0, 0, 20)
	stateLabel.Position = UDim2.new(0, 0, 1, -26)
	stateLabel.BackgroundTransparency = 1
	stateLabel.Font = Enum.Font.GothamBold
	stateLabel.TextScaled = true
	stateLabel.TextColor3 = UITheme.COLORS.SubText
	stateLabel.Text = ""
	stateLabel.ZIndex = 23
	stateLabel.Parent = card

	dayCards[day] = { card = card, dayLabel = dayLabel, rewardLabel = rewardLabel, stateLabel = stateLabel }
end

-- ===== Claim button + countdown =====

local claimButton = Instance.new("TextButton")
claimButton.Name = "ClaimTodayButton"
claimButton.Size = UDim2.new(1, -32, 0, 48)
claimButton.Position = UDim2.new(0, 16, 1, -68)
claimButton.Font = Enum.Font.GothamBlack
claimButton.TextScaled = true
claimButton.TextColor3 = UITheme.COLORS.Text
claimButton.BackgroundColor3 = UITheme.COLORS.Success
claimButton.Text = "CLAIM TODAY'S REWARD"
claimButton.ZIndex = 22
UITheme.ApplyCorner(claimButton)
UITheme.ApplyButtonHoverEffect(claimButton)
claimButton.Parent = dailyPanel

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

	for day, entry in ipairs(snapshot.track) do
		local widgets = dayCards[day]
		if widgets then
			widgets.rewardLabel.Text = entry.label
			if entry.isToday then
				widgets.card.BackgroundColor3 = UITheme.COLORS.Accent
				widgets.stateLabel.Text = "TODAY"
				widgets.stateLabel.TextColor3 = UITheme.COLORS.Text
			elseif entry.isPastCurrentStreak then
				widgets.card.BackgroundColor3 = UITheme.COLORS.Panel
				widgets.stateLabel.Text = "DONE"
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
		statusLabel.Text = ("Current streak: Day %d of 7  \u{2022}  %d total claims"):format(
			snapshot.currentStreakDay,
			snapshot.totalClaims
		)
	else
		claimButton.Visible = true
		claimButton.Text = ("ALREADY CLAIMED \u{2022} back in %s"):format(formatCountdown(snapshot.secondsUntilNextDay))
		claimButton.BackgroundColor3 = UITheme.COLORS.Panel
		statusLabel.Text = ("Current streak: Day %d of 7  \u{2022}  %d total claims"):format(
			snapshot.currentStreakDay,
			snapshot.totalClaims
		)
	end
end

local latestSnapshot = nil

local function requestSnapshot()
	local ok, snapshot = pcall(function()
		return getDailyRewardSnapshotFunction:InvokeServer()
	end)
	if ok and snapshot then
		latestSnapshot = snapshot
		refreshFromSnapshot(snapshot)
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
	requestSnapshot()
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
