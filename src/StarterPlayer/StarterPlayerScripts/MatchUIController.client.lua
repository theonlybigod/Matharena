--[[
	MatchUIController.client.lua

	Builds and updates the queue-status banner and the 3-2-1-GO intro
	countdown under StarterGui.MainUI. Purely presentational — it only
	displays what the server reports via RemoteEvents/GetMatchSnapshot; it
	never decides game state itself.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchConfig = require(ReplicatedStorage.Modules.MatchConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
local UITheme = require(ReplicatedStorage.Modules.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")

-- Queue status banner (top-center)
local queueFrame = Instance.new("Frame")
queueFrame.Name = "QueueStatus"
queueFrame.Size = UDim2.fromOffset(340, 92)
queueFrame.Position = UDim2.new(0.5, -170, 0, 20)
queueFrame.Visible = false
UITheme.StylePanel(queueFrame, 0.25)
queueFrame.Parent = mainUI

local queueLabel = Instance.new("TextLabel")
queueLabel.Name = "QueueLabel"
queueLabel.Size = UDim2.new(1, 0, 0, 56)
queueLabel.BackgroundTransparency = 1
queueLabel.TextColor3 = UITheme.COLORS.Text
queueLabel.Font = Enum.Font.GothamBold
queueLabel.TextScaled = true
queueLabel.Text = ""
queueLabel.Parent = queueFrame

local cancelQueueButton = Instance.new("TextButton")
cancelQueueButton.Name = "CancelQueueButton"
cancelQueueButton.Size = UDim2.new(1, -16, 0, 28)
cancelQueueButton.Position = UDim2.fromOffset(8, 58)
cancelQueueButton.Font = Enum.Font.GothamBold
cancelQueueButton.TextScaled = true
cancelQueueButton.Text = "CANCEL"
cancelQueueButton.TextColor3 = UITheme.COLORS.Text
cancelQueueButton.BackgroundColor3 = UITheme.COLORS.Error
UITheme.ApplyCorner(cancelQueueButton)
UITheme.ApplyButtonHoverEffect(cancelQueueButton)
cancelQueueButton.Parent = queueFrame

cancelQueueButton.MouseButton1Click:Connect(function()
	RemoteEvents.Get("RequestLeaveQueue"):FireServer()
end)

-- Intro countdown (big centered text, 3-2-1-GO / winner announcement)
local introLabel = Instance.new("TextLabel")
introLabel.Name = "IntroCountdown"
introLabel.Size = UDim2.fromOffset(360, 200)
introLabel.Position = UDim2.new(0.5, -180, 0.5, -100)
introLabel.BackgroundTransparency = 1
introLabel.TextColor3 = UITheme.COLORS.Accent
introLabel.Font = Enum.Font.GothamBlack
introLabel.TextScaled = true
introLabel.Visible = false
introLabel.Text = ""
introLabel.Parent = mainUI

local function updateQueueDisplay(waitingCount: number, countdownSeconds: number?)
	if waitingCount <= 0 then
		queueFrame.Visible = false
		return
	end

	queueFrame.Visible = true
	if countdownSeconds then
		queueLabel.Text = ("Match starting in %d... (%d/%d players)"):format(
			countdownSeconds,
			waitingCount,
			MatchConfig.MAX_PLAYERS
		)
	else
		queueLabel.Text = ("Waiting for players... (%d/%d)"):format(waitingCount, MatchConfig.MAX_PLAYERS)
	end
end

RemoteEvents.Get("QueueUpdated").OnClientEvent:Connect(function(payload)
	updateQueueDisplay(payload.waitingCount, payload.countdownSeconds)
end)

RemoteEvents.Get("MatchCountdownTick").OnClientEvent:Connect(function(step: string?)
	if not step or step == "" then
		introLabel.Visible = false
		return
	end

	introLabel.Visible = true
	introLabel.TextColor3 = UITheme.COLORS.Accent
	introLabel.Text = step
	queueFrame.Visible = false
end)

RemoteEvents.Get("MatchWinner").OnClientEvent:Connect(function(winnerName: string?)
	introLabel.Visible = true
	introLabel.TextColor3 = UITheme.COLORS.Gold
	introLabel.Text = if winnerName and winnerName ~= "" then (winnerName .. " wins!") else "No winner"
end)

RemoteEvents.Get("GameStateChanged").OnClientEvent:Connect(function(state: string)
	if state == MatchConfig.GameState.Lobby then
		introLabel.Visible = false
		introLabel.TextColor3 = UITheme.COLORS.Accent
		queueFrame.Visible = false
	elseif state == MatchConfig.GameState.Waiting or state == MatchConfig.GameState.Starting then
		introLabel.Visible = false
	elseif state == MatchConfig.GameState.Playing then
		introLabel.Visible = false
		queueFrame.Visible = false
	elseif state == MatchConfig.GameState.Winner then
		queueFrame.Visible = false
	elseif state == MatchConfig.GameState.Returning then
		introLabel.Visible = false
		introLabel.TextColor3 = UITheme.COLORS.Accent
		queueFrame.Visible = false
	end
end)

-- Initialize immediately in case we joined mid-flow (avoids a blank UI
-- until the next server-pushed update).
task.spawn(function()
	local ok, snapshot = pcall(function()
		return RemoteFunctions.Get("GetMatchSnapshot"):InvokeServer()
	end)

	if ok and snapshot then
		updateQueueDisplay(snapshot.waitingCount, snapshot.countdownSeconds)
	end
end)
