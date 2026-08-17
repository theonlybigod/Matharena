--[[
	CompetitionUIController.client.lua

	Match UI: Top bar (Round / Players Remaining / Difficulty), Center
	(question), Bottom (answer box + submit), Side (live roster/
	"leaderboard" + player info HUD). Also owns the camera focus on
	whoever's currently answering.

	All correctness/timing decisions are made by the server
	(CompetitionGameplay) - this script only displays what it's told and
	forwards the local player's answer. The visual countdown here is
	purely local prediction; the server enforces the real timeout
	independently.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local MatchConfig = require(ReplicatedStorage.Modules.MatchConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local UITheme = require(ReplicatedStorage.Modules.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")
local camera = Workspace.CurrentCamera

-- ===== Top bar: Round / Players Remaining / Difficulty =====

local topBar = Instance.new("Frame")
topBar.Name = "MatchTopBar"
topBar.Size = UDim2.fromOffset(560, 44)
topBar.Position = UDim2.new(0.5, -280, 0, 16)
topBar.Visible = false
UITheme.StylePanel(topBar, 0.2)
topBar.Parent = mainUI

local topBarLayout = Instance.new("UIListLayout")
topBarLayout.FillDirection = Enum.FillDirection.Horizontal
topBarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
topBarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
topBarLayout.Padding = UDim.new(0, 24)
topBarLayout.Parent = topBar

local function createTopBarLabel(name: string, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.Size = UDim2.fromOffset(160, 40)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = UITheme.COLORS.Text
	label.Text = ""
	label.Parent = topBar
	return label
end

local roundLabel = createTopBarLabel("RoundLabel", 1)
local playersRemainingLabel = createTopBarLabel("PlayersRemainingLabel", 2)
local difficultyLabel = createTopBarLabel("DifficultyLabel", 3)

-- ===== Center: question panel =====

local questionFrame = Instance.new("Frame")
questionFrame.Name = "QuestionPanel"
questionFrame.Size = UDim2.fromOffset(560, 170)
questionFrame.Position = UDim2.new(0.5, -280, 0.5, -170)
questionFrame.Visible = false
UITheme.StylePanel(questionFrame, 0.1)
questionFrame.Parent = mainUI

local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "ActivePlayerLabel"
nameLabel.Size = UDim2.new(1, -20, 0, 28)
nameLabel.Position = UDim2.fromOffset(10, 8)
nameLabel.BackgroundTransparency = 1
nameLabel.TextColor3 = UITheme.COLORS.Accent
nameLabel.Font = Enum.Font.GothamBold
nameLabel.TextScaled = true
nameLabel.Text = ""
nameLabel.Parent = questionFrame

local questionLabel = Instance.new("TextLabel")
questionLabel.Name = "QuestionLabel"
questionLabel.Size = UDim2.new(1, -20, 0, 70)
questionLabel.Position = UDim2.fromOffset(10, 40)
questionLabel.BackgroundTransparency = 1
questionLabel.TextColor3 = UITheme.COLORS.Text
questionLabel.Font = Enum.Font.GothamBlack
questionLabel.TextScaled = true
questionLabel.Text = ""
questionLabel.Parent = questionFrame

local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "TimerLabel"
timerLabel.Size = UDim2.new(1, -20, 0, 34)
timerLabel.Position = UDim2.fromOffset(10, 116)
timerLabel.BackgroundTransparency = 1
timerLabel.TextColor3 = UITheme.COLORS.Gold
timerLabel.Font = Enum.Font.GothamBold
timerLabel.TextScaled = true
timerLabel.Text = ""
timerLabel.Parent = questionFrame

-- ===== Bottom: answer box + submit (active player only) =====

local answerBox = Instance.new("TextBox")
answerBox.Name = "AnswerBox"
answerBox.Size = UDim2.fromOffset(180, 44)
answerBox.Position = UDim2.new(0.5, -190, 1, -60)
answerBox.Font = Enum.Font.Gotham
answerBox.TextScaled = true
answerBox.PlaceholderText = "Your answer"
answerBox.TextColor3 = Color3.fromRGB(20, 20, 25)
answerBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
answerBox.ClearTextOnFocus = false
answerBox.Visible = false
UITheme.ApplyCorner(answerBox)
answerBox.Parent = mainUI

local submitButton = Instance.new("TextButton")
submitButton.Name = "SubmitButton"
submitButton.Size = UDim2.fromOffset(150, 44)
submitButton.Position = UDim2.new(0.5, 20, 1, -60)
submitButton.BackgroundColor3 = UITheme.COLORS.Accent
submitButton.TextColor3 = UITheme.COLORS.Text
submitButton.Font = Enum.Font.GothamBold
submitButton.TextScaled = true
submitButton.Text = "Submit"
submitButton.Visible = false
UITheme.ApplyCorner(submitButton)
UITheme.ApplyButtonHoverEffect(submitButton)
submitButton.Parent = mainUI

local function submitAnswer()
	if answerBox.Text == "" then
		return
	end
	RemoteEvents.Get("SubmitAnswer"):FireServer(answerBox.Text)
	answerBox.Text = ""
end

submitButton.MouseButton1Click:Connect(submitAnswer)
answerBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		submitAnswer()
	end
end)

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
		row.TextColor3 = entry.alive and UITheme.COLORS.Success or UITheme.COLORS.SubText
		row.Text = ("%s%s  (%s)"):format(entry.alive and "" or "\u{2715} ", entry.name, entry.rank)
		row.Parent = rosterList
	end
end

RemoteEvents.Get("RosterUpdated").OnClientEvent:Connect(rebuildRoster)

-- ===== Camera =====

local cameraActive = false

local function focusCameraOnPlatform(platformIndex: number?)
	if not platformIndex then
		return
	end

	local arena = Workspace:FindFirstChild("Arena")
	local platforms = arena and arena:FindFirstChild("Platforms")
	local platform = platforms and platforms:FindFirstChild("Platform" .. platformIndex)
	local base = platform and platform:FindFirstChild("Base")
	if not (base and base:IsA("BasePart")) then
		return
	end

	local center = Vector3.new(0, base.Position.Y, 0)
	local outward = base.Position - center
	if outward.Magnitude < 1 then
		outward = Vector3.new(0, 0, 1)
	end
	outward = outward.Unit

	local camPos = base.Position + outward * 22 + Vector3.new(0, 10, 0)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(camPos, base.Position + Vector3.new(0, 3, 0))
	cameraActive = true
end

local function releaseCameraControl()
	if cameraActive then
		camera.CameraType = Enum.CameraType.Custom
		cameraActive = false
	end
end

-- ===== Local countdown display (visual only; server enforces the real timeout) =====

local countdownConnection: RBXScriptConnection? = nil
local countdownDeadlineClock: number? = nil

local function stopCountdown()
	if countdownConnection then
		countdownConnection:Disconnect()
		countdownConnection = nil
	end
	countdownDeadlineClock = nil
end

local function startCountdown(seconds: number)
	stopCountdown()
	countdownDeadlineClock = os.clock() + seconds
	timerLabel.TextColor3 = UITheme.COLORS.Gold

	countdownConnection = RunService.RenderStepped:Connect(function()
		if not countdownDeadlineClock then
			return
		end
		local remaining = math.max(0, countdownDeadlineClock - os.clock())
		timerLabel.Text = ("%.1fs"):format(remaining)
		if remaining <= 0 then
			stopCountdown()
		end
	end)
end

-- ===== Remote handlers =====

RemoteEvents.Get("TurnStarted").OnClientEvent:Connect(function(payload)
	if not payload then
		questionFrame.Visible = false
		topBar.Visible = false
		answerBox.Visible = false
		submitButton.Visible = false
		stopCountdown()
		releaseCameraControl()
		return
	end

	topBar.Visible = true
	roundLabel.Text = "Round " .. tostring(payload.round)
	playersRemainingLabel.Text = ("Players: %d"):format(payload.playersRemaining)
	difficultyLabel.Text = payload.difficulty

	questionFrame.Visible = true
	UITheme.PlayOpenTween(questionFrame)
	nameLabel.Text = ("%s \u{2014} %s"):format(payload.playerName, payload.category)
	questionLabel.Text = payload.questionText
	startCountdown(payload.timerSeconds)
	focusCameraOnPlatform(payload.platformIndex)

	local isMyTurn = payload.playerUserId == player.UserId
	answerBox.Visible = isMyTurn
	submitButton.Visible = isMyTurn
end)

RemoteEvents.Get("TurnResolved").OnClientEvent:Connect(function(payload)
	stopCountdown()
	answerBox.Visible = false
	submitButton.Visible = false

	if payload.correct then
		timerLabel.TextColor3 = UITheme.COLORS.Success
		timerLabel.Text = "Correct!"
	else
		timerLabel.TextColor3 = UITheme.COLORS.Error
		local reason = payload.timedOut and "Time's up!" or "Wrong!"
		timerLabel.Text = ("%s Answer: %s"):format(reason, tostring(payload.correctAnswer))
	end
end)

RemoteEvents.Get("GameStateChanged").OnClientEvent:Connect(function(state: string)
	local showSide = (state == MatchConfig.GameState.Playing) or (state == MatchConfig.GameState.Winner)
	sidePanel.Visible = showSide
	if showSide then
		UITheme.PlayOpenTween(sidePanel)
	end
end)
