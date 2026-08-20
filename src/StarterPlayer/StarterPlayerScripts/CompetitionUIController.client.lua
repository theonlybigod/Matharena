--[[
	CompetitionUIController.client.lua

	Match UI: a Side panel (live roster/"leaderboard" + player info HUD),
	plus camera focus on whoever's currently answering.

	The arena's giant central screen is now the PRIMARY gameplay surface for
	BOTH display AND input (see ArenaScreenController.client.lua) - round
	number, players remaining, difficulty, the question, the timer, AND the
	answer box/submit button all live there now, visible from both sides,
	for competitive matches and Practice Mode alike. This script previously
	still built its own small answer-input popup here too, which meant a
	player briefly saw two separate places to type an answer during a
	competitive turn - that duplicate popup has been removed entirely, not
	just hidden, so there is exactly one input surface.

	All correctness/timing decisions are made by the server
	(CompetitionGameplay) - this script only displays the side panel/roster
	and handles the camera; it never touches question/answer state at all
	anymore.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MatchConfig = require(ReplicatedStorage.Modules.MatchConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local GameplayCameraController = require(script.Parent.GameplayCameraController)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")

-- ===== Side: leaderboard (live roster) + player info =====

local sidePanel = Instance.new("Frame")
sidePanel.Name = "MatchSidePanel"
sidePanel.Size = UDim2.fromOffset(230, 420)
sidePanel.Position = UDim2.new(1, -250, 0.5, -210)
sidePanel.BackgroundTransparency = 1
sidePanel.Visible = false
sidePanel.Parent = mainUI

local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0, 12)
sideLayout.Parent = sidePanel

-- Leaderboard (live roster)
local leaderboardFrame = Instance.new("Frame")
leaderboardFrame.Name = "Leaderboard"
leaderboardFrame.Size = UDim2.fromOffset(230, 260)
leaderboardFrame.LayoutOrder = 1
UITheme.StylePanel(leaderboardFrame, 0.1)
leaderboardFrame.Parent = sidePanel

local leaderboardTitle = Instance.new("TextLabel")
leaderboardTitle.Name = "Title"
leaderboardTitle.Size = UDim2.new(1, -16, 0, 28)
leaderboardTitle.Position = UDim2.fromOffset(8, 6)
leaderboardTitle.BackgroundTransparency = 1
leaderboardTitle.Font = Enum.Font.GothamBold
leaderboardTitle.TextScaled = true
leaderboardTitle.TextXAlignment = Enum.TextXAlignment.Left
leaderboardTitle.TextColor3 = UITheme.COLORS.Accent
leaderboardTitle.Text = "Leaderboard"
leaderboardTitle.Parent = leaderboardFrame

local rosterList = Instance.new("Frame")
rosterList.Name = "RosterList"
rosterList.Size = UDim2.new(1, -16, 1, -42)
rosterList.Position = UDim2.fromOffset(8, 36)
rosterList.BackgroundTransparency = 1
rosterList.Parent = leaderboardFrame

local rosterListLayout = Instance.new("UIListLayout")
rosterListLayout.Padding = UDim.new(0, 2)
rosterListLayout.Parent = rosterList

-- Player info HUD
local playerInfoFrame = Instance.new("Frame")
playerInfoFrame.Name = "PlayerInfo"
playerInfoFrame.Size = UDim2.fromOffset(230, 148)
playerInfoFrame.LayoutOrder = 2
UITheme.StylePanel(playerInfoFrame, 0.1)
playerInfoFrame.Parent = sidePanel

local playerInfoTitle = Instance.new("TextLabel")
playerInfoTitle.Name = "Title"
playerInfoTitle.Size = UDim2.new(1, -16, 0, 28)
playerInfoTitle.Position = UDim2.fromOffset(8, 6)
playerInfoTitle.BackgroundTransparency = 1
playerInfoTitle.Font = Enum.Font.GothamBold
playerInfoTitle.TextScaled = true
playerInfoTitle.TextXAlignment = Enum.TextXAlignment.Left
playerInfoTitle.TextColor3 = UITheme.COLORS.Accent
playerInfoTitle.Text = "Player Info"
playerInfoTitle.Parent = playerInfoFrame

local function createStatRow(labelText: string, order: number): TextLabel
	local row = Instance.new("TextLabel")
	row.Name = labelText:gsub("%s", "") .. "Row"
	row.Size = UDim2.new(1, -16, 0, 26)
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.Font = Enum.Font.Gotham
	row.TextScaled = true
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextColor3 = UITheme.COLORS.SubText
	row.Text = labelText .. ": -"
	row.Parent = playerInfoFrame
	return row
end

local statsLayout = Instance.new("UIListLayout")
statsLayout.Padding = UDim.new(0, 2)
statsLayout.Parent = playerInfoFrame

playerInfoTitle.LayoutOrder = 0
local coinsRow = createStatRow("Coins", 1)
local xpRow = createStatRow("XP", 2)
local rankRow = createStatRow("Rank", 3)
local winsRow = createStatRow("Wins", 4)

local function refreshPlayerInfo()
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	coinsRow.Text = ("Coins: %d"):format(leaderstats.Coins.Value)
	xpRow.Text = ("XP: %d"):format(leaderstats.XP.Value)
	rankRow.Text = ("Rank: %s"):format(leaderstats.Rank.Value)
	winsRow.Text = ("Wins: %d"):format(leaderstats.Wins.Value)
end

task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats", 10)
	if not leaderstats then
		return
	end
	for _, valueName in ipairs({ "Coins", "XP", "Rank", "Wins" }) do
		local valueObject = leaderstats:FindFirstChild(valueName)
		if valueObject then
			valueObject:GetPropertyChangedSignal("Value"):Connect(refreshPlayerInfo)
		end
	end
	refreshPlayerInfo()
end)

local function rebuildRoster(roster: { any })
	for _, child in ipairs(rosterList:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	for i, entry in ipairs(roster) do
		local row = Instance.new("TextLabel")
		row.Name = "Entry" .. i
		row.Size = UDim2.new(1, 0, 0, 22)
		row.LayoutOrder = entry.platformIndex or i
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.Gotham
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = entry.alive and UITheme.GetSuccessColor() or UITheme.COLORS.SubText
		row.Text = ("%s%s  (%s)"):format(entry.alive and "" or "\u{2715} ", entry.name, entry.rank)
		row.Parent = rosterList
	end
end

RemoteEvents.Get("RosterUpdated").OnClientEvent:Connect(rebuildRoster)

-- ===== Camera =====
-- Message 28: now zooms toward the central MATHARENA screen (shared
-- GameplayCameraController.lua), not just the player's own platform - see
-- that module for the framing details. Consolidated out of this file
-- since PracticeUIController needed the identical behavior; duplicating
-- it a third time wasn't worth it.

-- ===== Remote handlers =====
-- Question/answer/timer state is entirely the arena screen's job now
-- (ArenaScreenController.client.lua) - this script only still cares
-- about TurnStarted for the camera focus, and GameStateChanged for the
-- side panel's visibility.

RemoteEvents.Get("TurnStarted").OnClientEvent:Connect(function(payload)
	if not payload then
		GameplayCameraController.Release()
		return
	end
	GameplayCameraController.FocusOnScreen(payload.platformIndex, 1)
end)

RemoteEvents.Get("GameStateChanged").OnClientEvent:Connect(function(state: string)
	local showSide = (state == MatchConfig.GameState.Playing) or (state == MatchConfig.GameState.Winner)
	sidePanel.Visible = showSide
	if showSide then
		UITheme.PlayOpenTween(sidePanel)
	end
end)
