--[[
	TutorialUIController.client.lua

	The Tutorial Building's interior interaction (Message 15). No tutorial
	system existed before this, so this is new - but it deliberately reuses
	the exact same modal-building pattern already established by
	LobbyUIController/ShopUIController/RewardsUIController (UITheme panel
	styling, overlay+panel+close-button shape) rather than inventing a
	different UI framework, per the spec's "use the existing UI
	architecture" instruction.

	Purely presentational, static content - there is nothing here for a
	server to validate (no player data is read or written), so there are
	no RemoteEvents/RemoteFunctions for this feature.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local UITheme = require(ReplicatedStorage.Modules.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")

local TOPICS = {
	{
		title = "How to Play",
		body = "MathArena is a competitive math game show. Join a match, answer questions faster and more "
			.. "accurately than your opponents, and be the last one standing to win Coins, XP, and Gems.",
	},
	{
		title = "How Matchmaking Works",
		body = "Click PLAY to queue up. A match needs at least 2 players and holds up to 12 - once enough "
			.. "players are queued, a countdown begins and you're teleported to the arena. If you're ever "
			.. "alone in the server, you'll automatically be offered Practice Mode after a short wait.",
	},
	{
		title = "How Questions Work",
		body = "Questions get progressively harder as a match goes on, from basic arithmetic to fractions, "
			.. "percentages, and beyond. Each question has a time limit based on its difficulty - answer "
			.. "correctly before time runs out, or you're eliminated.",
	},
	{
		title = "Practice Mode",
		body = "Practice Mode lets you answer the same kinds of questions with no elimination and no time "
			.. "pressure to lose over. Click the PRACTICE button in the lobby any time - it doesn't count "
			.. "as a competitive match and won't affect your Wins or leaderboard standing.",
	},
	{
		title = "Rewards & XP",
		body = "Winning and playing matches earns Coins, XP, and Gems. Spend Coins and Gems in the Shop on "
			.. "cosmetics, and check the Rewards track to see what you unlock as your competitive Wins add up.",
	},
}

-- ===== Overlay / panel =====

local tutorialOverlay = Instance.new("Frame")
tutorialOverlay.Name = "TutorialOverlay"
tutorialOverlay.Size = UDim2.fromScale(1, 1)
tutorialOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
tutorialOverlay.BackgroundTransparency = 0.5
tutorialOverlay.Visible = false
tutorialOverlay.ZIndex = 20
tutorialOverlay.Parent = mainUI

local tutorialPanel = Instance.new("Frame")
tutorialPanel.Name = "TutorialPanel"
tutorialPanel.Size = UDim2.fromOffset(560, 420)
tutorialPanel.Position = UDim2.new(0.5, -280, 0.5, -210)
tutorialPanel.ZIndex = 21
UITheme.StylePanel(tutorialPanel, 0.05)
tutorialPanel.Parent = tutorialOverlay

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.fromOffset(300, 32)
titleLabel.Position = UDim2.fromOffset(16, 12)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextScaled = true
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextColor3 = UITheme.COLORS.Accent
titleLabel.Text = "Tutorial"
titleLabel.ZIndex = 22
titleLabel.Parent = tutorialPanel

local closeButton = Instance.new("TextButton")
closeButton.Name = "TutorialCloseButton"
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
closeButton.Parent = tutorialPanel

-- Topic list (left column)
local topicList = Instance.new("Frame")
topicList.Name = "TopicList"
topicList.Size = UDim2.fromOffset(160, 340)
topicList.Position = UDim2.fromOffset(16, 56)
topicList.BackgroundTransparency = 1
topicList.ZIndex = 22
topicList.Parent = tutorialPanel

local topicLayout = Instance.new("UIListLayout")
topicLayout.SortOrder = Enum.SortOrder.LayoutOrder
topicLayout.Padding = UDim.new(0, 6)
topicLayout.Parent = topicList

-- Body panel (right side)
local bodyFrame = Instance.new("Frame")
bodyFrame.Name = "BodyFrame"
bodyFrame.Size = UDim2.fromOffset(360, 340)
bodyFrame.Position = UDim2.fromOffset(184, 56)
UITheme.StylePanel(bodyFrame, 0.15)
bodyFrame.ZIndex = 22
bodyFrame.Parent = tutorialPanel

local bodyTitle = Instance.new("TextLabel")
bodyTitle.Name = "BodyTitle"
bodyTitle.Size = UDim2.new(1, -16, 0, 28)
bodyTitle.Position = UDim2.fromOffset(8, 8)
bodyTitle.BackgroundTransparency = 1
bodyTitle.Font = Enum.Font.GothamBold
bodyTitle.TextScaled = true
bodyTitle.TextXAlignment = Enum.TextXAlignment.Left
bodyTitle.TextColor3 = UITheme.COLORS.Text
bodyTitle.Text = ""
bodyTitle.ZIndex = 23
bodyTitle.Parent = bodyFrame

local bodyText = Instance.new("TextLabel")
bodyText.Name = "BodyText"
bodyText.Size = UDim2.new(1, -16, 1, -48)
bodyText.Position = UDim2.fromOffset(8, 40)
bodyText.BackgroundTransparency = 1
bodyText.Font = Enum.Font.Gotham
bodyText.TextSize = 16
bodyText.TextWrapped = true
bodyText.TextXAlignment = Enum.TextXAlignment.Left
bodyText.TextYAlignment = Enum.TextYAlignment.Top
bodyText.TextColor3 = UITheme.COLORS.SubText
bodyText.Text = ""
bodyText.ZIndex = 23
bodyText.Parent = bodyFrame

local function selectTopic(index: number)
	local topic = TOPICS[index]
	bodyTitle.Text = topic.title
	bodyText.Text = topic.body

	for _, sibling in ipairs(topicList:GetChildren()) do
		if sibling:IsA("TextButton") then
			sibling.BackgroundColor3 = if sibling.LayoutOrder == index then UITheme.COLORS.Accent
				else UITheme.COLORS.Panel
		end
	end
end

for index, topic in ipairs(TOPICS) do
	local topicButton = Instance.new("TextButton")
	topicButton.Name = "Topic" .. index
	topicButton.LayoutOrder = index
	topicButton.Size = UDim2.new(1, 0, 0, 56)
	topicButton.Font = Enum.Font.GothamBold
	topicButton.TextSize = 14
	topicButton.TextWrapped = true
	topicButton.TextColor3 = UITheme.COLORS.Text
	topicButton.BackgroundColor3 = UITheme.COLORS.Panel
	topicButton.Text = topic.title
	topicButton.ZIndex = 22
	UITheme.ApplyCorner(topicButton)
	UITheme.ApplyButtonHoverEffect(topicButton)
	topicButton.Parent = topicList

	topicButton.MouseButton1Click:Connect(function()
		selectTopic(index)
	end)
end

closeButton.MouseButton1Click:Connect(function()
	tutorialOverlay.Visible = false
end)

local function openTutorialPanel()
	tutorialOverlay.Visible = true
	UITheme.PlayOpenTween(tutorialPanel)
	selectTopic(1)
end

-- ===== Tutorial Terminal (in-world interaction) =====

task.spawn(function()
	local lobby = Workspace:WaitForChild("Lobby", 10)
	local tutorialBuilding = lobby and lobby:WaitForChild("Buildings", 10):WaitForChild("TutorialBuilding", 10)
	local stand = tutorialBuilding and tutorialBuilding:FindFirstChild("TutorialTerminalStand")
	local prompt = stand and stand:FindFirstChild("TutorialTerminalPrompt")
	if prompt then
		(prompt :: ProximityPrompt).Triggered:Connect(function(triggeringPlayer: Player)
			if triggeringPlayer == player then
				openTutorialPanel()
			end
		end)
	end
end)
