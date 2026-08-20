--[[
	CenterStage.lua

	Builds the center stage: the raised stage disc, the host podium, the
	question screen floating above, and the winner area marking. Tags key
	pieces via CollectionService so MatchSystem / CompetitionGameplay can
	find them later without hardcoded paths:
		"HostPodium"    -> the podium Model
		"QuestionScreen" -> the screen Part - each face has a "ScreenGui"
		                     SurfaceGui with IdleLabel/ContestantLabel/
		                     QuestionLabel/TimerLabel/RoundLabel, plus
		                     AnswerBox/SubmitButton/LeavePracticeButton (see
		                     addScreenFace below); driven live by
		                     ArenaScreenController.client.lua
		"WinnerArea"    -> the winner area marker Part

	The answer-input controls (AnswerBox/SubmitButton/LeavePracticeButton)
	are built here as real, static, server-created Instances - same
	principle as the text labels - so every client sees the identical
	geometry/layout. Only their Visible state and Text differ PER CLIENT,
	set locally by ArenaScreenController.client.lua depending on whether
	that specific client is the currently-active contestant/practicer -
	client-side Instance property writes are never replicated to other
	clients or the server, so one player seeing their own answer box does
	not make it appear (or become editable) for anyone else. Submitting
	still goes through the exact same SubmitAnswer/PracticeSubmitAnswer
	RemoteEvents as before, validated server-side exactly as before - this
	is purely a relocation of the input widgets, not a new input pathway.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local ArenaConfig = require(script.Parent.ArenaConfig)

local CenterStage = {}

local function buildStageDisc(parent: Instance): BasePart
	return PartUtils.CreateDisc({
		name = "StageBase",
		diameter = ArenaConfig.CENTER_STAGE_DIAMETER,
		thickness = ArenaConfig.CENTER_STAGE_HEIGHT,
		position = Vector3.new(0, ArenaConfig.CENTER_STAGE_HEIGHT / 2, 0),
		material = Enum.Material.Marble,
		color = Color3.fromRGB(20, 20, 24),
		parent = parent,
	})
end

local function buildPodium(parent: Instance, stageTopY: number): Model
	local model = Instance.new("Model")
	model.Name = "HostPodium"
	model.Parent = parent

	local base = PartUtils.CreatePart({
		name = "Base",
		size = Vector3.new(4, 3.5, 2.5),
		position = ArenaConfig.HOST_PODIUM_OFFSET + Vector3.new(0, stageTopY + 1.75, 0),
		material = Enum.Material.Metal,
		color = Color3.fromRGB(45, 50, 60),
		parent = model,
	})

	PartUtils.CreatePart({
		name = "Trim",
		size = Vector3.new(4.2, 0.3, 2.7),
		position = ArenaConfig.HOST_PODIUM_OFFSET + Vector3.new(0, stageTopY + 3.5, 0),
		material = Enum.Material.Neon,
		color = ArenaConfig.NEON_COLOR,
		canCollide = false,
		parent = model,
	})

	model.PrimaryPart = base
	CollectionService:AddTag(model, "HostPodium")

	return model
end

--[[
	Builds one face of the arena's central question screen (Message 22,
	sections 6-8: the giant screen becomes the PRIMARY question display,
	on both faces, driven by the same authoritative server events every
	client already receives).

	Stable child names (read by ArenaScreenController.client.lua):
		"IdleLabel"      - shown when no turn is active ("MATHARENA")
		"ContestantLabel" - active contestant's name + category
		"QuestionLabel"   - the math question itself, the largest element
		"TimerLabel"      - remaining time
		"RoundLabel"      - round number / players remaining
	All hidden except IdleLabel by default; the client shows/hides them
	together when a turn starts/ends. Building this once here (rather than
	in the client script) keeps the actual screen layout part of the
	world's static geometry - the client only ever sets .Text/.Visible on
	instances that already exist, never constructs UI at runtime.
]]
local function addScreenFace(screen: BasePart, face: Enum.NormalId)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ScreenGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.Parent = screen

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(5, 5, 8)
	background.BorderSizePixel = 0
	background.Parent = gui

	local idleLabel = Instance.new("TextLabel")
	idleLabel.Name = "IdleLabel"
	idleLabel.Size = UDim2.fromScale(1, 1)
	idleLabel.BackgroundTransparency = 1
	idleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	idleLabel.Font = Enum.Font.GothamBold
	idleLabel.TextScaled = true
	idleLabel.Text = "MATHARENA"
	idleLabel.Visible = true
	idleLabel.Parent = background

	local contestantLabel = Instance.new("TextLabel")
	contestantLabel.Name = "ContestantLabel"
	contestantLabel.Size = UDim2.new(1, -40, 0.16, 0)
	contestantLabel.Position = UDim2.fromScale(0, 0.04)
	contestantLabel.BackgroundTransparency = 1
	contestantLabel.TextColor3 = ArenaConfig.NEON_COLOR
	contestantLabel.Font = Enum.Font.GothamBold
	contestantLabel.TextScaled = true
	contestantLabel.Text = ""
	contestantLabel.Visible = false
	contestantLabel.Parent = background

	local questionLabel = Instance.new("TextLabel")
	questionLabel.Name = "QuestionLabel"
	questionLabel.Size = UDim2.new(1, -60, 0.38, 0)
	questionLabel.Position = UDim2.fromScale(0, 0.22)
	questionLabel.BackgroundTransparency = 1
	questionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	questionLabel.Font = Enum.Font.GothamBlack
	questionLabel.TextScaled = true
	questionLabel.TextWrapped = true
	questionLabel.Text = ""
	questionLabel.Visible = false
	questionLabel.Parent = background

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = UDim2.new(0.4, 0, 0.13, 0)
	timerLabel.Position = UDim2.fromScale(0.05, 0.62)
	timerLabel.BackgroundTransparency = 1
	timerLabel.TextColor3 = Color3.fromRGB(255, 205, 60)
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.TextScaled = true
	timerLabel.Text = ""
	timerLabel.Visible = false
	timerLabel.Parent = background

	local roundLabel = Instance.new("TextLabel")
	roundLabel.Name = "RoundLabel"
	roundLabel.Size = UDim2.new(0.4, 0, 0.13, 0)
	roundLabel.Position = UDim2.fromScale(0.55, 0.62)
	roundLabel.BackgroundTransparency = 1
	roundLabel.TextColor3 = Color3.fromRGB(200, 205, 215)
	roundLabel.Font = Enum.Font.Gotham
	roundLabel.TextScaled = true
	roundLabel.Text = ""
	roundLabel.Visible = false
	roundLabel.Parent = background

	-- ===== Answer input row (Message 25: moved off the player's personal
	-- popup entirely - this IS the input now, for both competitive turns
	-- and Practice Mode). Hidden/disabled by default; a client only shows
	-- and enables these for itself when it is the active contestant/
	-- practicer (see ArenaScreenController.client.lua). Given its own clear
	-- band (0.78-0.96) below the timer/round row, with margin to the
	-- screen's bottom edge so nothing clips or overflows. =====
	local answerBox = Instance.new("TextBox")
	answerBox.Name = "AnswerBox"
	answerBox.Size = UDim2.new(0.42, 0, 0.16, 0)
	answerBox.Position = UDim2.fromScale(0.04, 0.79)
	answerBox.Font = Enum.Font.GothamBold
	answerBox.TextScaled = true
	answerBox.PlaceholderText = "Your answer"
	answerBox.TextColor3 = Color3.fromRGB(20, 20, 25)
	answerBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	answerBox.ClearTextOnFocus = false
	answerBox.Visible = false
	answerBox.Parent = background

	local answerBoxCorner = Instance.new("UICorner")
	answerBoxCorner.CornerRadius = UDim.new(0, 10)
	answerBoxCorner.Parent = answerBox

	local submitButton = Instance.new("TextButton")
	submitButton.Name = "SubmitButton"
	submitButton.Size = UDim2.new(0.22, 0, 0.16, 0)
	submitButton.Position = UDim2.fromScale(0.48, 0.79)
	submitButton.BackgroundColor3 = ArenaConfig.NEON_COLOR
	submitButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	submitButton.Font = Enum.Font.GothamBold
	submitButton.TextScaled = true
	submitButton.Text = "SUBMIT"
	submitButton.Visible = false
	submitButton.Parent = background

	local submitButtonCorner = Instance.new("UICorner")
	submitButtonCorner.CornerRadius = UDim.new(0, 10)
	submitButtonCorner.Parent = submitButton

	local leavePracticeButton = Instance.new("TextButton")
	leavePracticeButton.Name = "LeavePracticeButton"
	leavePracticeButton.Size = UDim2.new(0.22, 0, 0.16, 0)
	leavePracticeButton.Position = UDim2.fromScale(0.74, 0.79)
	leavePracticeButton.BackgroundColor3 = Color3.fromRGB(190, 60, 60)
	leavePracticeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	leavePracticeButton.Font = Enum.Font.GothamBold
	leavePracticeButton.TextScaled = true
	leavePracticeButton.Text = "EXIT PRACTICE"
	leavePracticeButton.Visible = false
	leavePracticeButton.Parent = background

	local leaveButtonCorner = Instance.new("UICorner")
	leaveButtonCorner.CornerRadius = UDim.new(0, 10)
	leaveButtonCorner.Parent = leavePracticeButton
end

local function buildQuestionScreen(parent: Instance, stageTopY: number): BasePart
	local screen = PartUtils.CreatePart({
		name = "QuestionScreen",
		size = Vector3.new(ArenaConfig.QUESTION_SCREEN_SIZE.X, ArenaConfig.QUESTION_SCREEN_SIZE.Y, 1),
		position = Vector3.new(0, stageTopY + ArenaConfig.QUESTION_SCREEN_HEIGHT_ABOVE_STAGE, 0),
		material = Enum.Material.Metal,
		color = Color3.fromRGB(15, 15, 18),
		canCollide = false,
		parent = parent,
	})

	-- Two faces so the screen reads from either side of the arena.
	addScreenFace(screen, Enum.NormalId.Front)
	addScreenFace(screen, Enum.NormalId.Back)

	CollectionService:AddTag(screen, "QuestionScreen")

	return screen
end

--[[
	Message 21 fix (section 6): same z-fighting pattern as the arena
	floor's ring segments (see ArenaDecorations.lua) - this marker
	previously sat with its bottom face at EXACTLY stageTopY, coincident
	with the stage disc's top face. Uses the same deliberate gap constant
	so both fixes stay consistent.
]]
local function buildWinnerArea(parent: Instance, stageTopY: number): BasePart
	local thickness = 0.3
	local marker = PartUtils.CreateDisc({
		name = "WinnerArea",
		diameter = ArenaConfig.WINNER_AREA_DIAMETER,
		thickness = thickness,
		position = Vector3.new(0, stageTopY + ArenaConfig.FLOOR_RING_HEIGHT_ABOVE_FLOOR + thickness / 2, 0),
		material = Enum.Material.Neon,
		color = ArenaConfig.NEON_COLOR,
		canCollide = false,
		parent = parent,
	})

	CollectionService:AddTag(marker, "WinnerArea")

	return marker
end

function CenterStage.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "CenterStage"
	folder.Parent = parent

	buildStageDisc(folder)
	local stageTopY = ArenaConfig.CENTER_STAGE_HEIGHT

	buildWinnerArea(folder, stageTopY)
	buildPodium(folder, stageTopY)
	buildQuestionScreen(folder, stageTopY)

	return folder
end

return CenterStage
