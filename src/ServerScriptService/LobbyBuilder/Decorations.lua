--[[
	Decorations.lua

	Builds the lobby's decorative dressing: a perimeter ring of trees
	(every LobbyConfig.TREE_SPACING studs), streetlights and benches on
	concentric rings further inset, flower beds near each building
	entrance, and a floating, particle-emitting Matharena logo above the
	plaza.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local LobbyConfig = require(script.Parent.LobbyConfig)

local Decorations = {}

local half = LobbyConfig.LOBBY_SIZE / 2

-- Generates positions around a square ring, `inset` studs in from the
-- lobby edge, spaced `spacing` studs apart along each side.
local function ringPositions(inset: number, spacing: number): { Vector3 }
	local r = half - inset
	local positions = {}

	for x = -r, r, spacing do
		table.insert(positions, Vector3.new(x, 0, r))
		table.insert(positions, Vector3.new(x, 0, -r))
	end

	local z = -r + spacing
	while z < r - spacing / 2 do
		table.insert(positions, Vector3.new(r, 0, z))
		table.insert(positions, Vector3.new(-r, 0, z))
		z += spacing
	end

	return positions
end

local function createTree(position: Vector3, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Tree"
	model.Parent = parent

	PartUtils.CreatePart({
		name = "Trunk",
		size = Vector3.new(1.5, 6, 1.5),
		position = position + Vector3.new(0, 3, 0),
		material = Enum.Material.Wood,
		color = Color3.fromRGB(90, 60, 40),
		parent = model,
	})

	PartUtils.CreatePart({
		name = "Foliage",
		size = Vector3.new(6, 6, 6),
		position = position + Vector3.new(0, 7, 0),
		material = Enum.Material.Grass,
		color = Color3.fromRGB(45, 120, 60),
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})
end

local function createStreetlight(position: Vector3, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Streetlight"
	model.Parent = parent

	PartUtils.CreatePart({
		name = "Pole",
		size = Vector3.new(0.8, 12, 0.8),
		position = position + Vector3.new(0, 6, 0),
		material = Enum.Material.Metal,
		color = Color3.fromRGB(50, 50, 55),
		parent = model,
	})

	local lamp = PartUtils.CreatePart({
		name = "Lamp",
		size = Vector3.new(1.6, 1.6, 1.6),
		position = position + Vector3.new(0, 12, 0),
		material = Enum.Material.Neon,
		color = LobbyConfig.NEON_COLOR,
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})

	local light = Instance.new("PointLight")
	light.Color = LobbyConfig.NEON_COLOR
	light.Range = 16
	light.Brightness = 2
	light.Parent = lamp
end

local function createBench(position: Vector3, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Bench"
	model.Parent = parent

	PartUtils.CreatePart({
		name = "Seat",
		size = Vector3.new(4, 0.4, 1.5),
		position = position + Vector3.new(0, 1.2, 0),
		material = Enum.Material.WoodPlanks,
		color = Color3.fromRGB(110, 80, 55),
		parent = model,
	})

	PartUtils.CreatePart({
		name = "Back",
		size = Vector3.new(4, 1.2, 0.3),
		position = position + Vector3.new(0, 1.9, -0.6),
		material = Enum.Material.WoodPlanks,
		color = Color3.fromRGB(110, 80, 55),
		parent = model,
	})
end

local FLOWER_COLORS = {
	Color3.fromRGB(230, 60, 90),
	Color3.fromRGB(250, 200, 40),
	Color3.fromRGB(140, 90, 230),
}

local function createFlowerBed(position: Vector3, parent: Instance)
	for i, color in ipairs(FLOWER_COLORS) do
		PartUtils.CreatePart({
			name = "Flower" .. i,
			size = Vector3.new(0.8, 0.8, 0.8),
			position = position + Vector3.new((i - 2) * 1.2, 0.4, 0),
			material = Enum.Material.Neon,
			color = color,
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = parent,
		})
	end
end

local function createFloatingLogo(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "MatharenaLogo"
	model.Parent = parent

	local panel = PartUtils.CreatePart({
		name = "LogoPanel",
		size = Vector3.new(20, 6, 1),
		position = Vector3.new(0, LobbyConfig.LOGO_HEIGHT, 0),
		material = Enum.Material.Neon,
		color = LobbyConfig.NEON_COLOR,
		canCollide = false,
		parent = model,
	})

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- faces the plaza/spawns (+Z)
	gui.Parent = panel

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = "MATHARENA"
	label.Parent = gui

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(LobbyConfig.NEON_COLOR)
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Rate = 8
	emitter.Speed = NumberRange.new(1, 2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = panel

	-- Gentle floating bob, driven by TweenService rather than a per-frame
	-- loop script, so the position replicates efficiently on its own.
	local tween = TweenService:Create(
		panel,
		TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = panel.Position + Vector3.new(0, 3, 0) }
	)
	tween:Play()

	return model
end

function Decorations.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Decorations"
	folder.Parent = parent

	local treesFolder = Instance.new("Folder")
	treesFolder.Name = "Trees"
	treesFolder.Parent = folder
	for _, position in ipairs(ringPositions(LobbyConfig.PERIMETER_INSET, LobbyConfig.TREE_SPACING)) do
		createTree(position, treesFolder)
	end

	local lightsFolder = Instance.new("Folder")
	lightsFolder.Name = "Streetlights"
	lightsFolder.Parent = folder
	for _, position in ipairs(ringPositions(LobbyConfig.PERIMETER_INSET + 10, LobbyConfig.TREE_SPACING * 2)) do
		createStreetlight(position, lightsFolder)
	end

	local benchesFolder = Instance.new("Folder")
	benchesFolder.Name = "Benches"
	benchesFolder.Parent = folder
	for _, position in ipairs(ringPositions(LobbyConfig.PERIMETER_INSET + 20, LobbyConfig.TREE_SPACING * 2)) do
		createBench(position, benchesFolder)
	end

	local flowersFolder = Instance.new("Folder")
	flowersFolder.Name = "FlowerBeds"
	flowersFolder.Parent = folder
	for _, def in ipairs(LobbyConfig.BUILDINGS) do
		createFlowerBed(def.position + Vector3.new(0, 0, def.size.Y / 2 + 2), flowersFolder)
	end

	createFloatingLogo(folder)

	return folder
end

return Decorations
