--[[
	TutorialUIController.client.lua

	The Tutorial Building's interior interaction, plus a genuine GUIDED,
	physically-walked first-time Play Tutorial: a step-by-step sequence
	that highlights each key map location in turn (the queue portal, the
	Quest Log, Shop, Daily Rewards, Tutorial Building, Statistics
	Building) and requires the player to actually walk to it (or, for the
	Quest Log step, just observe it) before advancing, rather than just
	reading static topic text.

	Runs AUTOMATICALLY, exactly ONCE EVER per player, the first time their
	character spawns and their profile says they've never completed it
	(TutorialSystem.lua persists that one flag) - with no way to skip or
	close out of it on that first run. It does NOT run again on later
	server joins once completed. It can always be replayed afterward via
	the "Replay Guided Walkthrough" button inside the static topic panel
	(opened from the Tutorial Building), which reruns the exact same steps
	for that session regardless of the persisted flag.

	The static topic panel below is purely presentational (nothing for a
	server to validate). The guided walkthrough only ever tells the server
	one trusted, low-stakes bit - "I finished it" - via TutorialSystem's
	GetTutorialState/MarkTutorialCompleted remotes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
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
			.. "Nothing is ever accepted for you automatically.",
	},
	{
		title = "Rewards & XP",
		body = "Winning and playing matches earns Coins, XP, and Gems. Spend Coins and Gems in the Shop on "
			.. "cosmetics, and check the Rewards track and Daily Rewards building to see what you unlock over time.",
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
	topicButton.Size = UDim2.new(1, 0, 0, 50)
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

-- "Replay Guided Walkthrough" - reruns the exact same physically-walked
-- steps as the automatic first-time tutorial, for THIS session, no
-- matter what the persisted completed flag says.
local replayButton = Instance.new("TextButton")
replayButton.Name = "ReplayGuidedTutorialButton"
replayButton.Size = UDim2.new(1, -16, 0, 36)
replayButton.Position = UDim2.new(0, 8, 1, -44)
replayButton.Font = Enum.Font.GothamBlack
replayButton.TextScaled = true
replayButton.Text = "REPLAY GUIDED WALKTHROUGH"
replayButton.TextColor3 = UITheme.COLORS.Text
replayButton.BackgroundColor3 = UITheme.COLORS.Accent
replayButton.ZIndex = 22
UITheme.ApplyCorner(replayButton)
UITheme.ApplyButtonHoverEffect(replayButton)
replayButton.Parent = tutorialPanel

local function openTutorialPanel()
	OverlayManager.Show(tutorialOverlay)
	UITheme.PlayOpenTween(tutorialPanel)
	selectTopic(1)
end

OverlayManager.Register(tutorialOverlay)

-- ===== Guided, physically-walked first-time Play Tutorial =====

-- Two kinds of step:
--   "walk" - highlight a world Instance + floating marker, wait until the
--            player's character gets within ARRIVAL_RADIUS.
--   "ui"   - highlight an on-screen GUI element (currently only the Quest
--            Log, which has no world location to walk to) and just wait
--            out a fixed short duration while explaining it.
local WAYPOINTS = {
	{
		type = "walk",
		buildingPath = { "QueuePortal" }, -- directly under Workspace.Lobby, not under Buildings
		title = "Find a Match",
		instruction = "Walk to the glowing queue portal - this is a landmark only now. Use the PLAY button to actually queue up for a match.",
	},
	{
		type = "ui",
		title = "Your Quest Log",
		instruction = "This is your Quest Log. Open it any time to Accept a quest, Refresh a standard quest for a different one (up to 3x a day), Cancel one you've accepted, or Claim a finished one - it's always manual, nothing is ever accepted for you.",
	},
	{
		type = "walk",
		buildingPath = { "Buildings", "Shop" },
		title = "Visit the Shop",
		instruction = "Walk to the Shop to browse cosmetics you can buy with Coins and Gems.",
	},
	{
		type = "walk",
		buildingPath = { "Buildings", "DailyRewards" },
		title = "Daily Rewards",
		instruction = "Walk to the Daily Rewards building - claim a reward here every day, and check your Lifetime Rewards progress.",
	},
	{
		type = "walk",
		buildingPath = { "Buildings", "TutorialBuilding" },
		title = "Tutorial Building",
		instruction = "This is the Tutorial Building - come back here any time and press Replay Guided Walkthrough to do this again.",
	},
	{
		type = "walk",
		buildingPath = { "Buildings", "StatisticsBuilding" },
		title = "Statistics & Leaderboards",
		instruction = "Walk to the Statistics Building to see your stats and check out the leaderboards.",
	},
}

local ARRIVAL_RADIUS = 16 -- studs; close enough to a "walk" waypoint to count as "arrived"
local WAYPOINT_HEIGHT_OFFSET = 14
local UI_STEP_HOLD_SECONDS = 6 -- how long a "ui" step stays highlighted before auto-advancing

-- Top-of-screen guidance banner (step counter + instruction + live
-- distance), separate from the static topic panel above - shown only
-- while a guided walkthrough is actively running.
local guideBanner = Instance.new("Frame")
guideBanner.Name = "TutorialGuideBanner"
guideBanner.Size = UDim2.fromOffset(460, 84)
guideBanner.Position = UDim2.new(0.5, -230, 0, 16)
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
guideInstructionLabel.Size = UDim2.new(1, -16, 0, 36)
guideInstructionLabel.Position = UDim2.fromOffset(12, 28)
guideInstructionLabel.BackgroundTransparency = 1
guideInstructionLabel.Font = Enum.Font.Gotham
guideInstructionLabel.TextSize = 14
guideInstructionLabel.TextWrapped = true
guideInstructionLabel.TextXAlignment = Enum.TextXAlignment.Left
guideInstructionLabel.TextColor3 = UITheme.COLORS.Text
guideInstructionLabel.Text = ""
guideInstructionLabel.ZIndex = 31
guideInstructionLabel.Parent = guideBanner

local guideDistanceLabel = Instance.new("TextLabel")
guideDistanceLabel.Name = "DistanceLabel"
guideDistanceLabel.Size = UDim2.new(1, -16, 0, 16)
guideDistanceLabel.Position = UDim2.fromOffset(12, 64)
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
	Resolves a waypoint's target Instance by walking `buildingPath` under
	Workspace.Lobby (e.g. {"Buildings","Shop"} -> Workspace.Lobby.Buildings.
	Shop), and returns its world position (Model:GetPivot().Position). Real
	live instance positions, not hand-copied coordinates, so this can never
	drift out of sync with wherever LobbyBuilder actually placed things.
]]
local function resolveWaypointPosition(buildingPath: { string }): (Instance?, Vector3?)
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		return nil, nil
	end
	local current: Instance = lobby
	for _, name in ipairs(buildingPath) do
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
	Runs the "ui" step: highlights the Quest Log frame (forced open/visible
	via QuestsUIController's exposed bridge, see that script) with a
	pulsing bright UIStroke for UI_STEP_HOLD_SECONDS, then removes it.
	Falls back to just holding the instruction on screen (no highlight) if
	the quest box hasn't finished building yet for some reason - never
	gets the player stuck.
]]
local function runUIStep(waypoint)
	guideStepLabel.Text = ("STEP - %s"):format(waypoint.title)
	guideInstructionLabel.Text = waypoint.instruction
	guideDistanceLabel.Text = ""

	local bridge = _G.MathArenaQuestBoxBridge
	local frame: Frame? = nil
	if bridge then
		pcall(bridge.ForceExpanded)
		local ok, result = pcall(bridge.GetFrame)
		if ok then
			frame = result
		end
	end

	local stroke: UIStroke? = nil
	local wasVisible: boolean? = nil
	if frame then
		wasVisible = frame.Visible
		frame.Visible = true
		stroke = Instance.new("UIStroke")
		stroke.Name = "TutorialQuestHighlight"
		stroke.Color = UITheme.COLORS.Gold
		stroke.Thickness = 3
		stroke.Transparency = 0
		stroke.Parent = frame

		local pulseTween = TweenService:Create(
			stroke,
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.6 }
		)
		pulseTween:Play()

		task.wait(UI_STEP_HOLD_SECONDS)
		pulseTween:Cancel()
		stroke:Destroy()
		if wasVisible == false then
			frame.Visible = wasVisible
		end
	else
		-- Quest box script hasn't registered its bridge yet (very unlikely,
		-- but never worth stalling the whole tutorial over) - just hold the
		-- instruction on screen for the same duration.
		task.wait(UI_STEP_HOLD_SECONDS)
	end
end

--[[
	Runs the "walk" step: highlights the target building/portal (visible
	through walls) plus a floating marker, and waits until the player's
	character gets within ARRIVAL_RADIUS.
]]
local function runWalkStep(waypoint, index: number, humanoidRootPart: BasePart?)
	local targetInstance, targetPosition = resolveWaypointPosition(waypoint.buildingPath)
	if not targetPosition then
		return -- skip a waypoint that can't be resolved rather than getting the player stuck forever
	end

	guideStepLabel.Text = ("STEP %d - %s"):format(index, waypoint.title)
	guideInstructionLabel.Text = waypoint.instruction

	local highlight = Instance.new("Highlight")
	highlight.Name = "TutorialHighlight"
	highlight.FillColor = UITheme.COLORS.Accent
	highlight.OutlineColor = UITheme.COLORS.Gold
	highlight.FillTransparency = 0.6
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = targetInstance

	local marker = Instance.new("Part")
	marker.Name = "TutorialWaypointMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.Transparency = 1
	marker.Size = Vector3.new(1, 1, 1)
	marker.Position = targetPosition + Vector3.new(0, WAYPOINT_HEIGHT_OFFSET, 0)
	marker.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TutorialWaypointBillboard"
	billboard.Size = UDim2.fromOffset(160, 48)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 500
	billboard.Parent = marker

	local markerLabel = Instance.new("TextLabel")
	markerLabel.Size = UDim2.fromScale(1, 1)
	markerLabel.BackgroundTransparency = 1
	markerLabel.Font = Enum.Font.GothamBlack
	markerLabel.TextScaled = true
	markerLabel.TextColor3 = UITheme.COLORS.Gold
	markerLabel.TextStrokeTransparency = 0
	markerLabel.Text = "\u{2193} " .. waypoint.title
	markerLabel.Parent = billboard

	while humanoidRootPart and humanoidRootPart.Parent do
		local distance = (humanoidRootPart.Position - targetPosition).Magnitude
		guideDistanceLabel.Text = ("Distance: %d studs"):format(math.floor(distance))
		if distance <= ARRIVAL_RADIUS then
			break
		end
		task.wait(0.5)
	end

	highlight:Destroy()
	marker:Destroy()
end

--[[
	Runs the full guided walkthrough for this session: shows the banner,
	then runs every WAYPOINTS entry in order (walk-to or UI-highlight, per
	its `type`). Marks the tutorial completed on the server when the whole
	sequence finishes. Safe to call more than once (e.g. Replay button) -
	guarded by tutorialRunning so two overlapping runs can never fight
	over the same banner/highlights.
]]
local function runGuidedTutorial()
	if tutorialRunning then
		return
	end
	tutorialRunning = true
	tutorialOverlay.Visible = false -- don't leave the static panel covering the screen during the walkthrough

	local character = player.Character or player.CharacterAdded:Wait()
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?

	guideBanner.Visible = true

	for index, waypoint in ipairs(WAYPOINTS) do
		if waypoint.type == "ui" then
			runUIStep(waypoint)
		else
			runWalkStep(waypoint, index, humanoidRootPart)
		end
	end

	guideBanner.Visible = false
	tutorialRunning = false

	pcall(function()
		markTutorialCompletedFunction:InvokeServer()
	end)

	-- A one-time toast at the end, reusing the same premium-panel toast
	-- look as elsewhere in the project.
	local completionToast = Instance.new("Frame")
	completionToast.Name = "TutorialCompletionToast"
	completionToast.Size = UDim2.fromOffset(420, 70)
	completionToast.Position = UDim2.new(0.5, -210, 0, -90)
	completionToast.ZIndex = 30
	UITheme.StylePremiumPanel(completionToast, 0.05)
	completionToast.Parent = mainUI

	local completionLabel = Instance.new("TextLabel")
	completionLabel.Size = UDim2.new(1, -16, 1, -16)
	completionLabel.Position = UDim2.fromOffset(8, 8)
	completionLabel.BackgroundTransparency = 1
	completionLabel.Font = Enum.Font.GothamBold
	completionLabel.TextScaled = true
	completionLabel.TextWrapped = true
	completionLabel.TextColor3 = UITheme.COLORS.Text
	completionLabel.Text = "Tutorial complete! Need it again? Just visit the Tutorial Building any time."
	completionLabel.ZIndex = 31
	completionLabel.Parent = completionToast

	local showTween = TweenService:Create(
		completionToast,
		TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, -210, 0, 24) }
	)
	showTween:Play()
	task.delay(6, function()
		local hideTween = TweenService:Create(
			completionToast,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, -210, 0, -90) }
		)
		hideTween:Play()
		hideTween.Completed:Connect(function(playbackState: Enum.PlaybackState)
			if playbackState == Enum.PlaybackState.Completed then
				completionToast:Destroy()
			end
		end)
	end)
end

replayButton.MouseButton1Click:Connect(function()
	tutorialOverlay.Visible = false
	runGuidedTutorial()
end)

-- First-time auto-start: check the server's persisted flag once, after
-- the character has actually spawned and the player's had a moment to
-- get their bearings, rather than firing the instant the script loads.
-- Automatic and NOT choosable/skippable on this very first run - there is
-- no button anywhere in this sequence that dismisses it early.
task.spawn(function()
	if not player.Character then
		player.CharacterAdded:Wait()
	end
	task.wait(3)

	local ok, state = pcall(function()
		return getTutorialStateFunction:InvokeServer()
	end)
	if ok and state and not state.completed then
		runGuidedTutorial()
	end
end)

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
