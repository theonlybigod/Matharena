--[[
	TutorialUIController.client.lua

	The Tutorial Building's static topic panel, plus a genuine GUIDED,
	physically-walked walkthrough that introduces every major system in
	the game: lobby navigation, Play, Practice, questions, Quests,
	Statistics, Settings, Rewards, Daily Rewards, and building teleports.

	TWO ENTRY POINTS, ONE FLOW:

	  1. FIRST-TIME (automatic). Runs once ever, when the player's profile
	     says they have never completed it (TutorialSystem persists that
	     flag). Not skippable. On completion it calls MarkTutorialCompleted,
	     which is what UNLOCKS THE QUEST SYSTEM (see QuestsSystem's
	     questsUnlocked gate) - so finishing this is a real prerequisite,
	     not just a cosmetic milestone.

	  2. REDO (manual). The "Replay Guided Walkthrough" button in the
	     Tutorial Building panel. Runs the exact same steps but passes
	     isReplay = true, so it NEVER calls MarkTutorialCompleted and can
	     therefore never disturb quest-unlock state or any other
	     progression. Always available, regardless of the persisted flag.

	=== THREE BUGS THIS REWRITE FIXES ===

	MAP-LOCKED WAYPOINTS. Waypoint resolution was hardcoded to
	Workspace.Lobby - written before the game had five coexisting maps
	(MapsConfig). Running the walkthrough while standing on Lava, IceAge,
	Space or UnderTheSea targeted the Futuristic buildings ~1050 studs
	away, so the distance counter sat around 1000 and the tutorial could
	never advance - with no skip button to escape it. Waypoints now
	resolve against whichever map the player is actually standing in
	(resolveCurrentMap), so the walkthrough works from any of them.

	INTERRUPTION COUNTED AS SUCCESS. The walk loop ran
	`while humanoidRootPart and humanoidRootPart.Parent do`, so if the
	player died or reset mid-step, the root part was reparented away, the
	loop exited, and the step was treated as ARRIVED. Enough of those and
	an abandoned tutorial marked itself completed - silently unlocking
	quests for someone who never finished. Steps now re-acquire the
	character across respawns and only ever finish by genuinely satisfying
	their own condition, and the run only reports completion if every step
	did.

	REDO WROTE COMPLETION STATE. Both entry points shared one code path
	that unconditionally called MarkTutorialCompleted. Now gated on
	isReplay.

	Server owns state (the completed flag, and the quest unlock it gates).
	This script owns presentation - camera-free highlights, banner text,
	and waiting for the player to do the thing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
local MapsConfig = require(ReplicatedStorage.Modules.MapsConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local OverlayManager = require(script.Parent.OverlayManager)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")

local getTutorialStateFunction = RemoteFunctions.Get("GetTutorialState")
local markTutorialCompletedFunction = RemoteFunctions.Get("MarkTutorialCompleted")

local TOPICS = {
	{
		title = "How to Play",
		body = "MathArena is a competitive math game show. Join a match, answer questions faster and more "
			.. "accurately than your opponents, and be the last one standing to win Coins, XP, and Gems.",
	},
	{
		title = "How Matchmaking Works",
		body = "Click PLAY to pick a difficulty and queue up directly - no need to walk anywhere first. A match "
			.. "needs at least 2 players and holds up to 12 - once enough players are queued, a countdown begins "
			.. "and you're teleported to the arena.",
	},
	{
		title = "How Questions Work",
		body = "Questions get progressively harder as a match goes on, from basic arithmetic to fractions, "
			.. "percentages, and beyond. Each question has a time limit based on its difficulty - answer "
			.. "correctly before time runs out, or you're eliminated.",
	},
	{
		title = "Practice Mode",
		body = "Practice Mode lets you answer the same kinds of questions with no elimination to lose over. "
			.. "Click the PRACTICE button in the lobby any time and choose Regular Practice or Extra Time Mode "
			.. "(2x-5x time per question, or Infinite Time) - it doesn't count as a competitive match and won't "
			.. "affect your Wins or leaderboard standing.",
	},
	{
		title = "Quests",
		body = "Your Quest Log sits on the left edge of the screen - open it any time to see your current quests. "
			.. "Quests are entirely manual: you choose when to Accept one, Refresh a standard quest for a "
			.. "different one (up to 3 times a day), Cancel one you've accepted, or Claim a completed one. "
			.. "Nothing is ever accepted for you automatically. Quests unlock once you finish this tutorial.",
	},
	{
		title = "Rewards & XP",
		body = "Winning and playing matches earns Coins, XP, and Gems. Spend Coins and Gems in the Shop on "
			.. "cosmetics, and check the Rewards track and Daily Rewards building to see what you unlock over time.",
	},
	{
		title = "Getting Around",
		body = "Every major building has a floating sign above it and its name on the front. Click either one to "
			.. "teleport straight to that building's entrance instead of walking - handy when you're across the map.",
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
tutorialPanel.Size = UDim2.fromOffset(560, 460)
tutorialPanel.Position = UDim2.new(0.5, -280, 0.5, -230)
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
	topicButton.Size = UDim2.new(1, 0, 0, 44)
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

local replayButton = Instance.new("TextButton")
replayButton.Name = "ReplayGuidedTutorialButton"
replayButton.Size = UDim2.new(1, -32, 0, 40)
replayButton.Position = UDim2.new(0, 16, 1, -52)
replayButton.Font = Enum.Font.GothamBlack
replayButton.TextScaled = true
replayButton.Text = "REPLAY GUIDED WALKTHROUGH"
replayButton.TextColor3 = UITheme.COLORS.Text
replayButton.BackgroundColor3 = UITheme.COLORS.Accent
replayButton.ZIndex = 24
UITheme.ApplyCorner(replayButton)
UITheme.ApplyButtonHoverEffect(replayButton)
replayButton.Parent = tutorialPanel

local function openTutorialPanel()
	OverlayManager.Show(tutorialOverlay)
	UITheme.PlayOpenTween(tutorialPanel)
	selectTopic(1)
end

OverlayManager.Register(tutorialOverlay)

-- ===== Guided walkthrough =====

--[[
	STEP TYPES

	  walk     - highlight a world Model in the player's CURRENT map and
	             wait until they physically arrive.
	  ui       - highlight an on-screen element and hold, explaining it.
	  ui_open  - highlight a bottom-bar button and wait until the panel it
	             opens actually becomes visible. This is what makes the
	             tutorial a demonstration rather than a description: the
	             player really opens the difficulty picker, the practice
	             menu, Settings, Rewards, and so on.
	  teleport - highlight a building's overhead sign and wait until the
	             player is standing at that building's entrance, i.e. they
	             actually used the teleport control.

	Every step also carries a `hold` so nothing advances so fast the text
	can't be read, and every waiting step has a TIMEOUT - an unreachable
	condition must never trap a player in an unskippable tutorial again.
]]
local STEPS = {
	{
		type = "ui",
		title = "Welcome to MathArena",
		instruction = "MathArena is a competitive math game show. This walkthrough takes a couple of minutes and shows you every part of the lobby. Follow along!",
		hold = 7,
	},
	{
		type = "walk",
		path = { "QueuePortal" },
		title = "The Lobby",
		instruction = "This is the lobby plaza, with the queue portal at its centre. The buildings around the edge each hold a different game system. Walk to the portal to begin.",
	},
	{
		type = "ui_open",
		buttonName = "PlayButton",
		opens = "PlayTierOverlay",
		title = "Play Mode",
		instruction = "PLAY queues you for a real match against other players. Click PLAY now to open the difficulty picker.",
	},
	{
		type = "ui",
		title = "The Five Difficulties",
		instruction = "There are five difficulty tiers, from the easiest arithmetic up to the hardest mixed problems. Harder tiers ask harder questions and give less time - but pay out more. A match needs 2 players and holds up to 12; once enough queue up, a countdown starts and everyone is teleported to the arena. Close this picker when you're ready.",
		hold = 10,
	},
	{
		type = "ui_open",
		buttonName = "PracticeButton",
		opens = "PracticeModeOverlay",
		title = "Practice Mode",
		instruction = "Practice is completely separate from competitive matches - no elimination, and it never affects your Wins or leaderboard place. Click PRACTICE to see the options.",
	},
	{
		type = "ui",
		title = "Practice Options",
		instruction = "Choose Regular Practice, or Extra Time Mode for 2x-5x time per question or Infinite Time. You pick the difficulty too. Try a practice question after this walkthrough - it's the best way to learn the question format safely.",
		hold = 10,
	},
	{
		type = "ui",
		title = "Answering Questions",
		instruction = "In a match or in practice, the question appears on screen with an answer box below it and a countdown timer. Type your answer, submit it, and you'll immediately see whether it was correct. In a match, a wrong answer or running out of time eliminates you.",
		hold = 11,
	},
	{
		type = "ui",
		title = "Quests",
		instruction = "Quests are optional goals that pay Coins and XP. They're always manual - you choose when to Accept one, Refresh it for a different one, Cancel it, or Claim a finished one. Nothing is ever accepted for you. Your Quest Log unlocks as soon as you finish this tutorial.",
		hold = 11,
		highlightQuestBox = true,
	},
	{
		type = "teleport",
		building = "StatisticsBuilding",
		title = "Building Teleports",
		instruction = "Every building has a floating sign above it and its name on the front - click either to teleport straight there. Try it now: click the Statistics Building's sign to jump to its entrance.",
	},
	{
		type = "ui_open",
		buttonName = "StatsButton",
		opens = { "StatsOverlay", "MatchSidePanel" },
		title = "Statistics",
		instruction = "Your statistics track wins, questions answered, accuracy and fastest answer - the same values the lobby leaderboards rank you by. Click STATS to take a look.",
		optional = true,
	},
	{
		type = "ui_open",
		buttonName = "SettingsButton",
		opens = "SettingsOverlay",
		title = "Settings",
		instruction = "Settings let you adjust music and sound volume and other preferences - worth turning music down if you want to concentrate. Click SETTINGS to open it.",
	},
	{
		type = "ui_open",
		buttonName = "RewardsButton",
		opens = "RewardsOverlay",
		title = "Rewards",
		instruction = "The Rewards track unlocks prizes as you play more matches. Rewards are claimed MANUALLY - nothing is granted automatically, so check back and claim what you've earned. Click REWARDS.",
	},
	{
		type = "walk",
		path = { "Buildings", "DailyRewards" },
		title = "Daily Rewards",
		instruction = "Daily Rewards are a separate system from the Rewards track: one claim per day, and the streak grows the longer you keep coming back. Walk to the Daily Rewards building.",
	},
	{
		type = "ui_open",
		buttonName = "DailyButton",
		opens = "DailyRewardsOverlay",
		title = "Claiming a Daily Reward",
		instruction = "Click DAILY to open it - claim today's reward here, and check your Lifetime Rewards for the long-term milestones.",
	},
	{
		type = "walk",
		path = { "Buildings", "Shop" },
		title = "The Shop",
		instruction = "Spend the Coins and Gems you earn on cosmetics here. Walk to the Shop.",
	},
	{
		type = "walk",
		path = { "Buildings", "TutorialBuilding" },
		title = "Tutorial Building",
		instruction = "Last stop - the Tutorial Building. Come back here and press REPLAY GUIDED WALKTHROUGH any time you want to run through all of this again.",
	},
}

local ARRIVAL_RADIUS = 16
local WAYPOINT_HEIGHT_OFFSET = 14
local DEFAULT_HOLD_SECONDS = 6
local WALK_TIMEOUT_SECONDS = 150
local UI_OPEN_TIMEOUT_SECONDS = 45
local TELEPORT_TIMEOUT_SECONDS = 90

local guideBanner = Instance.new("Frame")
guideBanner.Name = "TutorialGuideBanner"
guideBanner.Size = UDim2.fromOffset(500, 104)
guideBanner.Position = UDim2.new(0.5, -250, 0, 16)
guideBanner.Visible = false
guideBanner.ZIndex = 30
UITheme.StylePremiumPanel(guideBanner, 0.05)
guideBanner.Parent = mainUI

local guideStepLabel = Instance.new("TextLabel")
guideStepLabel.Name = "StepLabel"
guideStepLabel.Size = UDim2.new(1, -16, 0, 20)
guideStepLabel.Position = UDim2.fromOffset(12, 8)
guideStepLabel.BackgroundTransparency = 1
guideStepLabel.Font = Enum.Font.GothamBold
guideStepLabel.TextSize = 13
guideStepLabel.TextXAlignment = Enum.TextXAlignment.Left
guideStepLabel.TextColor3 = UITheme.COLORS.Gold
guideStepLabel.Text = ""
guideStepLabel.ZIndex = 31
guideStepLabel.Parent = guideBanner

local guideInstructionLabel = Instance.new("TextLabel")
guideInstructionLabel.Name = "InstructionLabel"
guideInstructionLabel.Size = UDim2.new(1, -16, 0, 54)
guideInstructionLabel.Position = UDim2.fromOffset(12, 28)
guideInstructionLabel.BackgroundTransparency = 1
guideInstructionLabel.Font = Enum.Font.Gotham
guideInstructionLabel.TextSize = 14
guideInstructionLabel.TextWrapped = true
guideInstructionLabel.TextXAlignment = Enum.TextXAlignment.Left
guideInstructionLabel.TextYAlignment = Enum.TextYAlignment.Top
guideInstructionLabel.TextColor3 = UITheme.COLORS.Text
guideInstructionLabel.Text = ""
guideInstructionLabel.ZIndex = 31
guideInstructionLabel.Parent = guideBanner

local guideDistanceLabel = Instance.new("TextLabel")
guideDistanceLabel.Name = "DistanceLabel"
guideDistanceLabel.Size = UDim2.new(1, -16, 0, 16)
guideDistanceLabel.Position = UDim2.fromOffset(12, 84)
guideDistanceLabel.BackgroundTransparency = 1
guideDistanceLabel.Font = Enum.Font.GothamBold
guideDistanceLabel.TextSize = 12
guideDistanceLabel.TextXAlignment = Enum.TextXAlignment.Left
guideDistanceLabel.TextColor3 = UITheme.COLORS.SubText
guideDistanceLabel.Text = ""
guideDistanceLabel.ZIndex = 31
guideDistanceLabel.Parent = guideBanner

local tutorialRunning = false

--[[
	Returns the Workspace folder for the map the player is CURRENTLY
	standing in, by picking the MapsConfig entry whose origin is nearest
	to the character.

	This is the fix for the map-locked waypoints described at the top of
	this file. Every map builds the same building layout translated by its
	own origin, so "nearest origin" is an exact answer, not a guess.
	Falls back to the default map when there's no character yet.
]]
local function resolveCurrentMap(): Instance?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	local chosen = MapsConfig.GetDefaultMap()
	if root then
		local best = math.huge
		for _, def in ipairs(MapsConfig.MAPS) do
			local distance = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(def.origin.X, 0, def.origin.Z)).Magnitude
			if distance < best then
				best, chosen = distance, def
			end
		end
	end
	return Workspace:FindFirstChild(chosen.workspaceFolderName)
end

local function resolveWaypoint(path: { string }): (Instance?, Vector3?)
	local mapFolder = resolveCurrentMap()
	if not mapFolder then
		return nil, nil
	end
	local current: Instance = mapFolder
	for _, name in ipairs(path) do
		current = current:FindFirstChild(name)
		if not current then
			return nil, nil
		end
	end
	if current:IsA("Model") then
		return current, current:GetPivot().Position
	elseif current:IsA("BasePart") then
		return current, current.Position
	end
	return current, nil
end

--[[
	Re-acquires the player's HumanoidRootPart, waiting through a respawn if
	necessary. Steps call this every poll instead of capturing the root
	part once - that capture is precisely what let a mid-tutorial death
	count as "arrived" (see the header).
]]
local function currentRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function setBannerText(stepIndex: number, total: number, title: string, instruction: string)
	guideStepLabel.Text = ("STEP %d OF %d  -  %s"):format(stepIndex, total, title:upper())
	guideInstructionLabel.Text = instruction
	guideDistanceLabel.Text = ""
end

local function makeHighlight(target: Instance): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "TutorialHighlight"
	highlight.FillColor = UITheme.COLORS.Accent
	highlight.OutlineColor = UITheme.COLORS.Gold
	highlight.FillTransparency = 0.6
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = target
	return highlight
end

local function makeWorldMarker(position: Vector3, text: string): Part
	local marker = Instance.new("Part")
	marker.Name = "TutorialWaypointMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false -- must never intercept a teleport-sign click
	marker.Transparency = 1
	marker.Size = Vector3.new(1, 1, 1)
	marker.Position = position + Vector3.new(0, WAYPOINT_HEIGHT_OFFSET, 0)
	marker.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TutorialWaypointBillboard"
	billboard.Size = UDim2.fromOffset(190, 52)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 1200
	billboard.Parent = marker

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = UITheme.COLORS.Gold
	label.TextStrokeTransparency = 0
	label.Text = "\u{2193} " .. text
	label.Parent = billboard

	return marker
end

--[[
	Pulsing outline on an on-screen GUI element, so "click PLAY" points at
	the actual PLAY button rather than just naming it.
]]
local function highlightGui(guiObject: GuiObject): () -> ()
	local stroke = Instance.new("UIStroke")
	stroke.Name = "TutorialGuiHighlight"
	stroke.Color = UITheme.COLORS.Gold
	stroke.Thickness = 3
	stroke.Parent = guiObject

	local pulse = TweenService:Create(
		stroke,
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.65 }
	)
	pulse:Play()

	return function()
		pulse:Cancel()
		stroke:Destroy()
	end
end

local function findLobbyButton(name: string): GuiObject?
	local bar = mainUI:FindFirstChild("LobbyButtonBar")
	local button = bar and bar:FindFirstChild(name)
	return button and button:IsA("GuiObject") and button or nil
end

--[[
	Returns true once ANY of `names` is a visible frame under mainUI.
	A list rather than a single name because a couple of the bottom-bar
	buttons can legitimately surface one of several panels.
]]
local function anyOverlayVisible(names): boolean
	local list = if typeof(names) == "table" then names else { names }
	for _, name in ipairs(list) do
		local frame = mainUI:FindFirstChild(name)
		if frame and frame:IsA("GuiObject") and frame.Visible then
			return true
		end
	end
	return false
end

-- ===== Step runners. Each returns true only if it genuinely finished. =====

local function runHoldStep(step, index: number, total: number): boolean
	setBannerText(index, total, step.title, step.instruction)

	local cleanup: (() -> ())? = nil
	if step.highlightQuestBox then
		local bridge = _G.MathArenaQuestBoxBridge
		local frame: Frame? = nil
		if bridge then
			pcall(bridge.ForceExpanded)
			local ok, result = pcall(bridge.GetFrame)
			if ok then
				frame = result
			end
		end
		-- The quest box is intentionally HIDDEN for a player who hasn't
		-- finished the tutorial (that's the whole point of the unlock), so
		-- show it just for this step to explain it, then restore.
		if frame then
			local wasVisible = frame.Visible
			frame.Visible = true
			local removeStroke = highlightGui(frame)
			cleanup = function()
				removeStroke()
				frame.Visible = wasVisible
			end
		end
	end

	task.wait(step.hold or DEFAULT_HOLD_SECONDS)
	if cleanup then
		cleanup()
	end
	return true
end

local function runWalkStep(step, index: number, total: number): boolean
	local target, position = resolveWaypoint(step.path)
	if not position then
		-- Unresolvable waypoint: skip rather than strand the player, but
		-- report failure so the run cannot claim completion.
		return false
	end

	setBannerText(index, total, step.title, step.instruction)
	local highlight = makeHighlight(target)
	local marker = makeWorldMarker(position, step.title)

	local arrived = false
	local elapsed = 0
	while elapsed < WALK_TIMEOUT_SECONDS do
		local root = currentRoot()
		if root then
			local distance = (root.Position - position).Magnitude
			guideDistanceLabel.Text = ("Distance: %d studs"):format(math.floor(distance))
			if distance <= ARRIVAL_RADIUS then
				arrived = true
				break
			end
		else
			-- Respawning. Explicitly NOT treated as arrival.
			guideDistanceLabel.Text = "Waiting for you to respawn..."
		end
		task.wait(0.4)
		elapsed += 0.4
	end

	highlight:Destroy()
	marker:Destroy()
	return arrived
end

local function runUIOpenStep(step, index: number, total: number): boolean
	setBannerText(index, total, step.title, step.instruction)

	local button = findLobbyButton(step.buttonName)
	local removeHighlight = if button then highlightGui(button) else nil

	local opened = false
	local elapsed = 0
	while elapsed < UI_OPEN_TIMEOUT_SECONDS do
		if anyOverlayVisible(step.opens) then
			opened = true
			break
		end
		guideDistanceLabel.Text = ("Click %s to continue (%ds)"):format(
			step.buttonName:gsub("Button$", ""):upper(),
			math.max(0, math.ceil(UI_OPEN_TIMEOUT_SECONDS - elapsed))
		)
		task.wait(0.3)
		elapsed += 0.3
	end

	if removeHighlight then
		removeHighlight()
	end

	if opened then
		-- Let them actually look at what they just opened.
		guideDistanceLabel.Text = "Nice - have a look, then close it when you're done."
		task.wait(3)
		return true
	end

	-- `optional` steps describe a panel that may not exist in this build;
	-- they must not fail the whole run.
	return step.optional == true
end

local function runTeleportStep(step, index: number, total: number): boolean
	local building, buildingPosition = resolveWaypoint({ "Buildings", step.building })
	if not buildingPosition then
		return false
	end

	setBannerText(index, total, step.title, step.instruction)

	-- Highlight the sign anchor, which is the clickable teleport target
	-- (BuildingSigns.MakeTeleportTarget), so the instruction points at the
	-- exact thing the player has to click.
	local anchor = building:FindFirstChild(step.building .. "SignAnchor")
	local highlight = makeHighlight(anchor or building)

	local teleported = false
	local elapsed = 0
	while elapsed < TELEPORT_TIMEOUT_SECONDS do
		local root = currentRoot()
		if root then
			local distance = (root.Position - buildingPosition).Magnitude
			guideDistanceLabel.Text = ("Distance: %d studs - click the sign to teleport"):format(math.floor(distance))
			if distance <= ARRIVAL_RADIUS * 2.5 then
				teleported = true
				break
			end
		else
			guideDistanceLabel.Text = "Waiting for you to respawn..."
		end
		task.wait(0.4)
		elapsed += 0.4
	end

	highlight:Destroy()
	return teleported
end

local function showCompletionToast(message: string)
	local toast = Instance.new("Frame")
	toast.Name = "TutorialCompletionToast"
	toast.Size = UDim2.fromOffset(460, 80)
	toast.Position = UDim2.new(0.5, -230, 0, -100)
	toast.ZIndex = 30
	UITheme.StylePremiumPanel(toast, 0.05)
	toast.Parent = mainUI

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -16, 1, -16)
	label.Position = UDim2.fromOffset(8, 8)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = UITheme.COLORS.Text
	label.Text = message
	label.ZIndex = 31
	label.Parent = toast

	TweenService:Create(
		toast,
		TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, -230, 0, 24) }
	):Play()

	task.delay(8, function()
		local hide = TweenService:Create(
			toast,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, -230, 0, -100) }
		)
		hide:Play()
		hide.Completed:Connect(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed then
				toast:Destroy()
			end
		end)
	end)
end

--[[
	Runs the whole walkthrough.

	`isReplay` is the Redo path: it changes exactly one thing - completion
	is never reported to the server - so replaying can never touch the
	quest unlock or any other progression state.

	Completion is reported ONLY if every step genuinely succeeded. A step
	that times out or can't resolve its target ends the run honestly
	rather than quietly banking a completion the player didn't earn.
]]
local function runGuidedTutorial(isReplay: boolean)
	if tutorialRunning then
		return
	end
	tutorialRunning = true
	tutorialOverlay.Visible = false

	if not player.Character then
		player.CharacterAdded:Wait()
	end
	player.Character:WaitForChild("HumanoidRootPart", 10)

	guideBanner.Visible = true

	local total = #STEPS
	local allSucceeded = true
	for index, step in ipairs(STEPS) do
		local ok: boolean
		if step.type == "walk" then
			ok = runWalkStep(step, index, total)
		elseif step.type == "ui_open" then
			ok = runUIOpenStep(step, index, total)
		elseif step.type == "teleport" then
			ok = runTeleportStep(step, index, total)
		else
			ok = runHoldStep(step, index, total)
		end
		if not ok then
			allSucceeded = false
		end
	end

	guideBanner.Visible = false
	tutorialRunning = false

	if isReplay then
		showCompletionToast("Walkthrough finished! Your progress and quests were not affected.")
		return
	end

	if not allSucceeded then
		showCompletionToast("Tutorial ended early. Visit the Tutorial Building to run it again and unlock quests.")
		return
	end

	local ok = pcall(function()
		return markTutorialCompletedFunction:InvokeServer()
	end)
	if ok then
		showCompletionToast("Tutorial complete - quests are now unlocked! Replay it any time from the Tutorial Building.")
	else
		showCompletionToast("Tutorial complete! (Your progress couldn't be saved just now - try again from the Tutorial Building.)")
	end
end

replayButton.MouseButton1Click:Connect(function()
	tutorialOverlay.Visible = false
	runGuidedTutorial(true)
end)

-- First-time auto-start, once ever, only for a player whose persisted
-- profile says they have never completed it.
task.spawn(function()
	if not player.Character then
		player.CharacterAdded:Wait()
	end
	task.wait(3)

	local ok, state = pcall(function()
		return getTutorialStateFunction:InvokeServer()
	end)
	if ok and state and not state.completed then
		runGuidedTutorial(false)
	end
end)

-- ===== Tutorial Terminal (in-world interaction) =====

--[[
	Wires the Tutorial Building terminal in EVERY map, not just the
	default one - the prompt exists in all five copies of the building,
	and a player standing in the Lava lobby should be able to open the
	tutorial from the terminal in front of them.
]]
task.spawn(function()
	for _, def in ipairs(MapsConfig.MAPS) do
		task.spawn(function()
			local mapFolder = Workspace:WaitForChild(def.workspaceFolderName, 30)
			local buildings = mapFolder and mapFolder:WaitForChild("Buildings", 30)
			local tutorialBuilding = buildings and buildings:WaitForChild("TutorialBuilding", 30)
			local stand = tutorialBuilding and tutorialBuilding:WaitForChild("TutorialTerminalStand", 30)
			local prompt = stand and stand:WaitForChild("TutorialTerminalPrompt", 30)
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.Triggered:Connect(function(triggeringPlayer: Player)
					if triggeringPlayer == player then
						openTutorialPanel()
					end
				end)
			end
		end)
	end
end)
