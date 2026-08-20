--[[
	RewardsUIController.client.lua

	Win-based Rewards track UI (replaces the old "Daily Rewards"
	placeholder - NOT a daily-login system). Shows current wins, the next
	unclaimed reward, a progress bar, and the full milestone track with
	Locked/Available/Claimed states, each backed by real server data via
	RewardTrackSystem (GetRewardTrackSnapshot / ClaimRewardMilestone).

	Opened from the Lobby's "RewardsButton" (built by LobbyUIController,
	which leaves this button's click handling to this script - same
	handoff pattern Message 10 used for the Shop button).

	Purely presentational: claiming always goes through the server, which
	re-validates wins and already-claimed state - this script only shows
	whatever the server confirms, and never marks anything Claimed on its
	own. Also listens for "RewardMilestoneUnlocked" (fired by the server
	the instant a win crosses a new milestone) to show a toast, even if
	the Rewards panel isn't currently open.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local RewardTrackConfig = require(ReplicatedStorage.Modules.RewardTrackConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
local UITheme = require(ReplicatedStorage.Modules.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")
local lobbyButtonBar = mainUI:WaitForChild("LobbyButtonBar")
local rewardsButton = lobbyButtonBar:WaitForChild("RewardsButton") :: TextButton

local getRewardTrackSnapshotFunction = RemoteFunctions.Get("GetRewardTrackSnapshot")
local claimRewardMilestoneFunction = RemoteFunctions.Get("ClaimRewardMilestone")
local rewardMilestoneUnlockedEvent = RemoteEvents.Get("RewardMilestoneUnlocked")

local STATE_COLORS = {
	Locked = Color3.fromRGB(90, 92, 100),
	Available = UITheme.COLORS.Accent,
	Claimed = UITheme.COLORS.Success,
}

-- ===== Overlay / panel shell =====

local rewardsOverlay = Instance.new("Frame")
rewardsOverlay.Name = "RewardsOverlay"
rewardsOverlay.Size = UDim2.fromScale(1, 1)
rewardsOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
rewardsOverlay.BackgroundTransparency = 0.5
rewardsOverlay.Visible = false
rewardsOverlay.ZIndex = 20
rewardsOverlay.Parent = mainUI

local rewardsPanel = Instance.new("Frame")
rewardsPanel.Name = "RewardsPanel"
rewardsPanel.Size = UDim2.fromOffset(520, 520)
rewardsPanel.Position = UDim2.new(0.5, -260, 0.5, -260)
rewardsPanel.ZIndex = 21
UITheme.StylePremiumPanel(rewardsPanel, 0.05)
rewardsPanel.Parent = rewardsOverlay

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.fromOffset(200, 32)
titleLabel.Position = UDim2.fromOffset(16, 12)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextScaled = true
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextColor3 = UITheme.COLORS.Accent
titleLabel.Text = "Rewards"
titleLabel.ZIndex = 22
titleLabel.Parent = rewardsPanel

local closeButton = Instance.new("TextButton")
closeButton.Name = "RewardsCloseButton"
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
closeButton.Parent = rewardsPanel

-- ===== Header: current wins / next reward / progress bar =====

local winsLabel = Instance.new("TextLabel")
winsLabel.Name = "WinsLabel"
winsLabel.Size = UDim2.new(1, -32, 0, 30)
winsLabel.Position = UDim2.fromOffset(16, 52)
winsLabel.BackgroundTransparency = 1
winsLabel.Font = Enum.Font.GothamBold
winsLabel.TextScaled = true
winsLabel.TextXAlignment = Enum.TextXAlignment.Left
winsLabel.TextColor3 = UITheme.COLORS.Gold
winsLabel.Text = "0 Wins"
winsLabel.ZIndex = 22
winsLabel.Parent = rewardsPanel

local nextRewardLabel = Instance.new("TextLabel")
nextRewardLabel.Name = "NextRewardLabel"
nextRewardLabel.Size = UDim2.new(1, -32, 0, 22)
nextRewardLabel.Position = UDim2.fromOffset(16, 84)
nextRewardLabel.BackgroundTransparency = 1
nextRewardLabel.Font = Enum.Font.Gotham
nextRewardLabel.TextSize = 16
nextRewardLabel.TextXAlignment = Enum.TextXAlignment.Left
nextRewardLabel.TextColor3 = UITheme.COLORS.SubText
nextRewardLabel.Text = "All rewards claimed!"
nextRewardLabel.ZIndex = 22
nextRewardLabel.Parent = rewardsPanel

local progressTrack = Instance.new("Frame")
progressTrack.Name = "ProgressTrack"
progressTrack.Size = UDim2.new(1, -32, 0, 16)
progressTrack.Position = UDim2.fromOffset(16, 112)
progressTrack.BackgroundColor3 = UITheme.COLORS.Panel
progressTrack.ZIndex = 22
UITheme.ApplyCorner(progressTrack)
progressTrack.Parent = rewardsPanel

local progressFill = Instance.new("Frame")
progressFill.Name = "ProgressFill"
progressFill.Size = UDim2.fromScale(0, 1)
progressFill.BackgroundColor3 = UITheme.COLORS.Accent
progressFill.ZIndex = 23
UITheme.ApplyCorner(progressFill)
progressFill.Parent = progressTrack

-- ===== Milestone track (scrolling) =====

local trackScroll = Instance.new("ScrollingFrame")
trackScroll.Name = "MilestoneTrack"
trackScroll.Size = UDim2.new(1, -32, 1, -160)
trackScroll.Position = UDim2.fromOffset(16, 140)
trackScroll.BackgroundTransparency = 1
trackScroll.BorderSizePixel = 0
trackScroll.ScrollBarThickness = 6
trackScroll.CanvasSize = UDim2.fromOffset(0, 0)
trackScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
trackScroll.ZIndex = 22
trackScroll.Parent = rewardsPanel

local trackLayout = Instance.new("UIListLayout")
trackLayout.SortOrder = Enum.SortOrder.LayoutOrder
trackLayout.Padding = UDim.new(0, 6)
trackLayout.Parent = trackScroll

-- ===== Toast notification (independent of the panel being open) =====

local toastFrame = Instance.new("Frame")
toastFrame.Name = "RewardToast"
toastFrame.Size = UDim2.fromOffset(320, 110)
toastFrame.Position = UDim2.new(0.5, -160, 0, -130)
toastFrame.ZIndex = 30
UITheme.StylePremiumPanel(toastFrame, 0.05)
toastFrame.Parent = mainUI

local toastTitle = Instance.new("TextLabel")
toastTitle.Name = "ToastTitle"
toastTitle.Size = UDim2.new(1, -16, 0, 24)
toastTitle.Position = UDim2.fromOffset(8, 8)
toastTitle.BackgroundTransparency = 1
toastTitle.Font = Enum.Font.GothamBlack
toastTitle.TextScaled = true
toastTitle.TextColor3 = UITheme.COLORS.Gold
toastTitle.Text = "NEW REWARD UNLOCKED!"
toastTitle.ZIndex = 31
toastTitle.Parent = toastFrame

local toastBody = Instance.new("TextLabel")
toastBody.Name = "ToastBody"
toastBody.Size = UDim2.new(1, -16, 0, 40)
toastBody.Position = UDim2.fromOffset(8, 36)
toastBody.BackgroundTransparency = 1
toastBody.Font = Enum.Font.GothamBold
toastBody.TextScaled = true
toastBody.TextColor3 = UITheme.COLORS.Text
toastBody.Text = ""
toastBody.ZIndex = 31
toastBody.Parent = toastFrame

local toastClaimButton = Instance.new("TextButton")
toastClaimButton.Name = "ToastClaimButton"
toastClaimButton.Size = UDim2.new(1, -16, 0, 28)
toastClaimButton.Position = UDim2.new(0, 8, 1, -36)
toastClaimButton.Font = Enum.Font.GothamBold
toastClaimButton.TextScaled = true
toastClaimButton.Text = "CLAIM NOW"
toastClaimButton.TextColor3 = UITheme.COLORS.Text
toastClaimButton.BackgroundColor3 = UITheme.COLORS.Success
toastClaimButton.ZIndex = 31
UITheme.ApplyCorner(toastClaimButton)
UITheme.ApplyButtonHoverEffect(toastClaimButton)
toastClaimButton.Parent = toastFrame

-- Hidden by default (Message 8 addition: "Claim Now" must not appear
-- until the server confirms something is actually claimable). Hidden by
-- BOTH Visible=false and off-screen position, so it takes up no UI space
-- and can't intercept input while hidden.
toastFrame.Visible = false

local currentToastWinsRequired: number? = nil

local function showClaimToast(entry)
	currentToastWinsRequired = entry.winsRequired
	toastBody.Text = ("%d WINS\n%s"):format(entry.winsRequired, tostring(entry.label))
	toastFrame.Visible = true

	local showTween = TweenService:Create(
		toastFrame,
		TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, -160, 0, 24) }
	)
	showTween:Play()
end

-- Hides the button completely - not a timer-based auto-dismiss. Per the
-- Message 8 addition, this only ever gets called when the server confirms
-- either the milestone was claimed or nothing is available anymore, never
-- "N seconds elapsed" - a still-unclaimed reward must keep showing the
-- button.
local function hideClaimToastCompletely()
	currentToastWinsRequired = nil
	local tween = TweenService:Create(
		toastFrame,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0.5, -160, 0, -130) }
	)
	tween:Play()
	tween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		if playbackState == Enum.PlaybackState.Completed then
			toastFrame.Visible = false
		end
	end)
end

-- ===== State =====

local latestSnapshot: { wins: number, milestones: { any } }? = nil

-- Finds the earliest still-unclaimed Available milestone in a snapshot,
-- if any - this is what decides whether the "Claim Now" button should be
-- showing at all (Message 8 addition).
local function findAvailableMilestone(snapshot)
	if not snapshot then
		return nil
	end
	for _, entry in ipairs(snapshot.milestones) do
		if entry.status == "Available" then
			return entry
		end
	end
	return nil
end

-- Server-authoritative claim-button visibility: shows/hides the toast's
-- "Claim Now" button purely based on what the server's own snapshot says
-- is currently Available - never based on the client guessing, and never
-- based on a timer. Called every time a snapshot is fetched (on load, on
-- panel open, and after every claim attempt), so the button's visibility
-- always reflects the player's actual current claimable state.
local function refreshClaimButtonFromSnapshot(snapshot)
	local available = findAvailableMilestone(snapshot)
	if available then
		if currentToastWinsRequired ~= available.winsRequired then
			showClaimToast(available)
		end
	elseif currentToastWinsRequired ~= nil then
		hideClaimToastCompletely()
	end
end

-- Forward-declared so refreshRewardsPanel's inline claim handler (defined
-- below) and requestSnapshot (defined further below) can reference each
-- other regardless of definition order.
local refreshRewardsPanel
local requestSnapshot

function refreshRewardsPanel()
	local snapshot = latestSnapshot
	if not snapshot then
		return
	end

	winsLabel.Text = ("%d Wins"):format(snapshot.wins)

	for _, child in ipairs(trackScroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local nextMilestone = nil
	local order = 0

	for _, entry in ipairs(snapshot.milestones) do
		if not nextMilestone and entry.status ~= "Claimed" then
			nextMilestone = entry
		end

		order += 1
		local row = Instance.new("Frame")
		row.Name = "Milestone" .. entry.winsRequired
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, 56)
		row.BackgroundColor3 = UITheme.COLORS.Panel
		row.BackgroundTransparency = if entry.status == "Locked" then 0.5 else 0.15
		row.ZIndex = 22
		UITheme.ApplyCorner(row)
		row.Parent = trackScroll

		local stateBar = Instance.new("Frame")
		stateBar.Name = "StateBar"
		stateBar.Size = UDim2.new(0, 6, 1, 0)
		stateBar.BackgroundColor3 = STATE_COLORS[entry.status]
		stateBar.ZIndex = 23
		UITheme.ApplyCorner(stateBar)
		stateBar.Parent = row

		local winsText = Instance.new("TextLabel")
		winsText.Name = "WinsText"
		winsText.Size = UDim2.fromOffset(100, 56)
		winsText.Position = UDim2.fromOffset(16, 0)
		winsText.BackgroundTransparency = 1
		winsText.Font = Enum.Font.GothamBold
		winsText.TextScaled = true
		winsText.TextXAlignment = Enum.TextXAlignment.Left
		winsText.TextColor3 = if entry.status == "Locked" then UITheme.COLORS.SubText else UITheme.COLORS.Text
		winsText.Text = entry.winsRequired .. " WINS"
		winsText.ZIndex = 23
		winsText.Parent = row

		local rewardText = Instance.new("TextLabel")
		rewardText.Name = "RewardText"
		rewardText.Size = UDim2.new(1, -280, 0, 56)
		rewardText.Position = UDim2.fromOffset(120, 0)
		rewardText.BackgroundTransparency = 1
		rewardText.Font = Enum.Font.Gotham
		rewardText.TextScaled = true
		rewardText.TextXAlignment = Enum.TextXAlignment.Left
		rewardText.TextColor3 = if entry.status == "Locked" then UITheme.COLORS.SubText else UITheme.COLORS.Gold
		rewardText.Text = entry.label
		rewardText.ZIndex = 23
		rewardText.Parent = row

		if entry.status == "Claimed" then
			local checkLabel = Instance.new("TextLabel")
			checkLabel.Name = "CheckLabel"
			checkLabel.Size = UDim2.fromOffset(140, 40)
			checkLabel.Position = UDim2.new(1, -156, 0.5, -20)
			checkLabel.BackgroundTransparency = 1
			checkLabel.Font = Enum.Font.GothamBold
			checkLabel.TextScaled = true
			checkLabel.TextColor3 = UITheme.COLORS.Success
			checkLabel.Text = "CLAIMED"
			checkLabel.ZIndex = 23
			checkLabel.Parent = row
		elseif entry.status == "Available" then
			local claimButton = Instance.new("TextButton")
			claimButton.Name = "ClaimButton"
			claimButton.Size = UDim2.fromOffset(120, 40)
			claimButton.Position = UDim2.new(1, -136, 0.5, -20)
			claimButton.Font = Enum.Font.GothamBold
			claimButton.TextScaled = true
			claimButton.Text = "CLAIM"
			claimButton.TextColor3 = UITheme.COLORS.Text
			claimButton.BackgroundColor3 = UITheme.COLORS.Success
			claimButton.ZIndex = 23
			UITheme.ApplyCorner(claimButton)
			UITheme.ApplyButtonHoverEffect(claimButton)
			claimButton.Parent = row

			claimButton.MouseButton1Click:Connect(function()
				claimButton.Active = false
				local result = claimRewardMilestoneFunction:InvokeServer(entry.winsRequired)
				claimButton.Active = true
				if result and result.success then
					-- Refetch so claimed state + progress bar + the "Claim Now"
					-- button all reflect the server's authoritative result rather
					-- than assuming success locally.
					requestSnapshot()
				end
			end)
		else
			local lockLabel = Instance.new("TextLabel")
			lockLabel.Name = "LockLabel"
			lockLabel.Size = UDim2.fromOffset(140, 40)
			lockLabel.Position = UDim2.new(1, -156, 0.5, -20)
			lockLabel.BackgroundTransparency = 1
			lockLabel.Font = Enum.Font.GothamBold
			lockLabel.TextScaled = true
			lockLabel.TextColor3 = UITheme.COLORS.SubText
			lockLabel.Text = "LOCKED"
			lockLabel.ZIndex = 23
			lockLabel.Parent = row
		end
	end

	if nextMilestone then
		local winsRemaining = math.max(0, nextMilestone.winsRequired - snapshot.wins)
		if nextMilestone.status == "Available" then
			nextRewardLabel.Text = ("Ready to claim: %s"):format(nextMilestone.label)
		else
			nextRewardLabel.Text = ("Next reward: %s (%d more win%s)"):format(
				nextMilestone.label,
				winsRemaining,
				if winsRemaining == 1 then "" else "s"
			)
		end

		-- Progress toward the next milestone from the previous one (or 0).
		local previousThreshold = 0
		for _, milestone in ipairs(RewardTrackConfig.GetSorted()) do
			if milestone.winsRequired < nextMilestone.winsRequired then
				previousThreshold = milestone.winsRequired
			end
		end
		local span = math.max(1, nextMilestone.winsRequired - previousThreshold)
		local progress = math.clamp((snapshot.wins - previousThreshold) / span, 0, 1)
		progressFill.Size = UDim2.fromScale(progress, 1)
	else
		nextRewardLabel.Text = "All rewards claimed!"
		progressFill.Size = UDim2.fromScale(1, 1)
	end
end

function requestSnapshot()
	local ok, snapshot = pcall(function()
		return getRewardTrackSnapshotFunction:InvokeServer()
	end)
	if ok and snapshot then
		latestSnapshot = snapshot
		refreshRewardsPanel()
		refreshClaimButtonFromSnapshot(snapshot)
	end
end

-- Establish the "Claim Now" button's correct initial state as soon as this
-- script loads (on join, or on a UI reload) - not just in reaction to a
-- live unlock event. Without this, a player with an already-available (but
-- not freshly-unlocked-this-session) reward would never see the button.
requestSnapshot()

-- ===== Open/close =====

local function openRewardsPanel()
	rewardsOverlay.Visible = true
	UITheme.PlayOpenTween(rewardsPanel)
	requestSnapshot()
end

rewardsButton.MouseButton1Click:Connect(function()
	if rewardsOverlay.Visible then
		rewardsOverlay.Visible = false
	else
		openRewardsPanel()
	end
end)

closeButton.MouseButton1Click:Connect(function()
	rewardsOverlay.Visible = false
end)

-- ===== Rewards Terminal (in-world interaction, Message 15) =====
-- Same open logic as the lobby RewardsButton above.
task.spawn(function()
	local lobby = Workspace:WaitForChild("Lobby", 10)
	local rewardsBuilding = lobby and lobby:WaitForChild("Buildings", 10):WaitForChild("DailyRewards", 10)
	local stand = rewardsBuilding and rewardsBuilding:FindFirstChild("RewardsTerminalStand")
	local prompt = stand and stand:FindFirstChild("RewardsTerminalPrompt")
	if prompt then
		(prompt :: ProximityPrompt).Triggered:Connect(function(triggeringPlayer: Player)
			if triggeringPlayer == player then
				openRewardsPanel()
			end
		end)
	end
end)

-- ===== Unlock toast (works whether or not the panel is open) =====

rewardMilestoneUnlockedEvent.OnClientEvent:Connect(function(data)
	if not data or typeof(data) ~= "table" then
		return
	end

	-- The push event tells us a milestone just unlocked - show it
	-- immediately rather than waiting for the next snapshot poll. This
	-- still goes through the same showClaimToast used by the state-driven
	-- refresh, so there's only one code path that actually shows the button.
	showClaimToast({ winsRequired = data.winsRequired, label = data.label })

	-- If the Rewards panel happens to be open, refresh it so the newly
	-- Available milestone shows up without needing to reopen the panel.
	if rewardsOverlay.Visible then
		requestSnapshot()
	end
end)

toastClaimButton.MouseButton1Click:Connect(function()
	if not currentToastWinsRequired then
		return
	end

	local winsRequired = currentToastWinsRequired
	toastClaimButton.Active = false
	local result = claimRewardMilestoneFunction:InvokeServer(winsRequired)
	toastClaimButton.Active = true
	if result and result.success then
		-- Refetch rather than assume: this both hides the button if nothing
		-- else is available, and correctly shows the NEXT available
		-- milestone's toast instead if one exists.
		requestSnapshot()
		if rewardsOverlay.Visible then
			refreshRewardsPanel()
		end
	end
end)
