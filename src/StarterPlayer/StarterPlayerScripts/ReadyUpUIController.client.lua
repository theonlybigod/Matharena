--[[
	ReadyUpUIController.client.lua

	A quick "Ready Up" bar so returning players don't have to re-open the
	Play tier-picker every round: one click joins THIS server's own
	difficulty queue directly (see myTierId below), with an "Auto Ready"
	checkbox beside it that re-queues automatically the moment this player
	is back at Lobby after a match, with no further clicks needed.

	WHY THIS BYPASSES RequestPlayDifficulty/PlaceTeleportSystem. That flow
	exists to route a CHOSEN difficulty to whichever Place is dedicated to
	it, including a cross-server teleport if this isn't already that
	Place (see PlaceTeleportSystem.lua). Ready Up's whole point is "queue
	right here, for whatever this server already is" - firing
	RequestJoinQueue directly (the same remote PlaceTeleportSystem itself
	calls into locally once it's confirmed you're already on the right
	Place) skips that resolution entirely. That also means it works
	correctly from the Hub for Easy Mode even though the Hub isn't
	registered in DifficultyPlacesConfig (see that module's own doc
	comment on why that lookup returns nil there) - Ready Up never needs
	to answer "which Place is this", it just queues locally, always.

	POSITION. A separate bar ABOVE LobbyButtonBar, with a gap - not one
	more button crammed into that row - so future bottom-bar buttons never
	collide with it.

	"Waiting..." vs a player count while a game is ongoing is handled by
	MatchUIController's own queue banner, not here - this bar only cares
	about GETTING a player into the queue, not about displaying its state
	once they are.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchConfig = require(ReplicatedStorage.Modules.MatchConfig)
local DifficultyPlacesConfig = require(ReplicatedStorage.Modules.DifficultyPlacesConfig)
local GameplayConfig = require(ReplicatedStorage.Modules.GameplayConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
local UITheme = require(ReplicatedStorage.Modules.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")

-- Which tier THIS server represents. nil on the Hub (not registered in
-- DifficultyPlacesConfig) defaults to tier 1 (Easy/Futuristic), matching
-- Main.server.lua's own MapsConfig.GetDefaultMap() fallback for the
-- Hub's build branch - Ready Up always matches whatever map is actually
-- built here.
local assignedPlace = DifficultyPlacesConfig.GetPlaceForPlaceId(game.PlaceId)
local myTierId = assignedPlace and assignedPlace.tierId or 1
local myTier = GameplayConfig.GetQueueTier(myTierId)

local autoReadyEnabled = false
local isQueued = false

-- ===== Bar, positioned above LobbyButtonBar =====
-- LobbyButtonBar sits at Position Y = {1, -112}, height 92, so its top
-- edge is 112px above the screen bottom. This bar's bottom edge sits 8px
-- above that: {1, -(112 + 8 + 56)} = {1, -176} for a 56-tall bar.

local readyBar = Instance.new("Frame")
readyBar.Name = "ReadyUpBar"
readyBar.Size = UDim2.fromOffset(370, 56)
readyBar.Position = UDim2.new(0.5, -185, 1, -176)
readyBar.BackgroundTransparency = 1
readyBar.Parent = mainUI

local barLayout = Instance.new("UIListLayout")
barLayout.FillDirection = Enum.FillDirection.Horizontal
barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
barLayout.Padding = UDim.new(0, 12)
barLayout.Parent = readyBar

local readyButton = Instance.new("TextButton")
readyButton.Name = "ReadyUpButton"
readyButton.Size = UDim2.fromOffset(210, 48)
readyButton.LayoutOrder = 1
readyButton.Font = Enum.Font.GothamBlack
readyButton.TextScaled = true
readyButton.TextColor3 = UITheme.COLORS.Text
readyButton.BackgroundColor3 = UITheme.COLORS.Accent
readyButton.AutoButtonColor = false
UITheme.ApplyCorner(readyButton)
UITheme.ApplyButtonHoverEffect(readyButton)
readyButton.Parent = readyBar

-- Auto Ready checkbox + label, beside the Ready Up button.
local autoReadyFrame = Instance.new("Frame")
autoReadyFrame.Name = "AutoReadyFrame"
autoReadyFrame.Size = UDim2.fromOffset(140, 48)
autoReadyFrame.LayoutOrder = 2
autoReadyFrame.BackgroundTransparency = 1
autoReadyFrame.Parent = readyBar

local autoReadyLayout = Instance.new("UIListLayout")
autoReadyLayout.FillDirection = Enum.FillDirection.Horizontal
autoReadyLayout.VerticalAlignment = Enum.VerticalAlignment.Center
autoReadyLayout.Padding = UDim.new(0, 6)
autoReadyLayout.Parent = autoReadyFrame

local checkbox = Instance.new("TextButton")
checkbox.Name = "AutoReadyCheckbox"
checkbox.Size = UDim2.fromOffset(28, 28)
checkbox.LayoutOrder = 1
checkbox.Text = ""
checkbox.BackgroundColor3 = UITheme.COLORS.Panel
checkbox.AutoButtonColor = false
UITheme.ApplyCorner(checkbox)
checkbox.Parent = autoReadyFrame

local checkMark = Instance.new("TextLabel")
checkMark.Name = "CheckMark"
checkMark.Size = UDim2.fromScale(1, 1)
checkMark.BackgroundTransparency = 1
checkMark.Font = Enum.Font.GothamBlack
checkMark.TextScaled = true
checkMark.TextColor3 = UITheme.COLORS.Accent
checkMark.Text = ""
checkMark.Parent = checkbox

local autoReadyLabel = Instance.new("TextLabel")
autoReadyLabel.Name = "Label"
autoReadyLabel.Size = UDim2.fromOffset(102, 28)
autoReadyLabel.LayoutOrder = 2
autoReadyLabel.BackgroundTransparency = 1
autoReadyLabel.Font = Enum.Font.GothamBold
autoReadyLabel.TextScaled = true
autoReadyLabel.TextXAlignment = Enum.TextXAlignment.Left
autoReadyLabel.TextColor3 = UITheme.COLORS.SubText
autoReadyLabel.Text = "Auto Ready"
autoReadyLabel.Parent = autoReadyFrame

local function updateReadyButtonVisual()
	if isQueued then
		readyButton.Text = ("QUEUED: %s (tap to cancel)"):format(myTier.name)
		readyButton.BackgroundColor3 = UITheme.COLORS.Panel
	else
		readyButton.Text = ("READY UP: %s"):format(myTier.name)
		readyButton.BackgroundColor3 = UITheme.COLORS.Accent
	end
end
updateReadyButtonVisual()

local function updateCheckboxVisual()
	checkMark.Text = if autoReadyEnabled then "\u{2713}" else ""
	checkbox.BackgroundColor3 = if autoReadyEnabled then UITheme.COLORS.Accent else UITheme.COLORS.Panel
end
updateCheckboxVisual()

readyButton.MouseButton1Click:Connect(function()
	if isQueued then
		RemoteEvents.Get("RequestLeaveQueue"):FireServer()
	else
		RemoteEvents.Get("RequestJoinQueue"):FireServer(myTierId)
	end
end)

checkbox.MouseButton1Click:Connect(function()
	autoReadyEnabled = not autoReadyEnabled
	updateCheckboxVisual()
end)

-- ===== Track whether I'm queued, from the same broadcast every other
-- queue-aware UI already listens to =====

RemoteEvents.Get("QueueUpdated").OnClientEvent:Connect(function(payload)
	isQueued = table.find(payload.waitingNames, player.Name) ~= nil
	updateReadyButtonVisual()
end)

-- ===== Visibility + Auto Ready, driven by match state =====
-- Same visibility rule as LobbyButtonBar (Lobby or Waiting) - hidden once
-- a match locks in (Starting onward), same as every other lobby-only UI
-- element.

RemoteEvents.Get("GameStateChanged").OnClientEvent:Connect(function(state: string)
	readyBar.Visible = (state == MatchConfig.GameState.Lobby) or (state == MatchConfig.GameState.Waiting)

	if state == MatchConfig.GameState.Lobby and autoReadyEnabled and not isQueued then
		RemoteEvents.Get("RequestJoinQueue"):FireServer(myTierId)
	end
end)

-- Initialize immediately in case we joined mid-flow (avoids a blank/wrong
-- state until the next server-pushed update).
task.spawn(function()
	local ok, snapshot = pcall(function()
		return RemoteFunctions.Get("GetMatchSnapshot"):InvokeServer()
	end)
	if ok and snapshot then
		isQueued = table.find(snapshot.waitingNames, player.Name) ~= nil
		updateReadyButtonVisual()
		readyBar.Visible = (snapshot.gameState == MatchConfig.GameState.Lobby)
			or (snapshot.gameState == MatchConfig.GameState.Waiting)
	end
end)
