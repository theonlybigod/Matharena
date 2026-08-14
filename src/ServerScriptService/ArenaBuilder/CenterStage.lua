--[[
	CenterStage.lua

	Builds the center stage: the raised stage disc, the host podium, the
	question screen floating above, and the winner area marking. Tags key
	pieces via CollectionService so MatchSystem / CompetitionGameplay can
	find them later without hardcoded paths:
		"HostPodium"    -> the podium Model
		"QuestionScreen" -> the screen Part (has a "SetText"-friendly
		                     TextLabel named "ScreenText" on both faces)
		"WinnerArea"    -> the winner area marker Part
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

local function addScreenFace(screen: BasePart, face: Enum.NormalId)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.Parent = screen

	local label = Instance.new("TextLabel")
	label.Name = "ScreenText"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(5, 5, 8)
	label.BackgroundTransparency = 0
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = "MATHARENA"
	label.Parent = gui
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

local function buildWinnerArea(parent: Instance, stageTopY: number): BasePart
	local marker = PartUtils.CreateDisc({
		name = "WinnerArea",
		diameter = ArenaConfig.WINNER_AREA_DIAMETER,
		thickness = 0.3,
		position = Vector3.new(0, stageTopY + 0.15, 0),
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
