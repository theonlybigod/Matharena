--[[
	Buildings.lua

	Constructs the five named lobby buildings from LobbyConfig.BUILDINGS.
	Each building is a Model containing a base volume, a neon roofline trim
	band, and a sign facing the plaza (+Z direction, where spawns are).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local LobbyConfig = require(script.Parent.LobbyConfig)

local Buildings = {}

local function addSign(basePart: BasePart, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- Back = +Z face, which faces the plaza/spawns
	gui.Parent = basePart

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	label.Parent = gui
end

local function buildOne(def, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = def.name
	model.Parent = parent

	local base = PartUtils.CreatePart({
		name = "Base",
		size = Vector3.new(def.size.X, def.height, def.size.Y),
		position = def.position + Vector3.new(0, def.height / 2, 0),
		material = Enum.Material.Metal,
		color = Color3.fromRGB(60, 65, 75),
		parent = model,
	})

	PartUtils.CreatePart({
		name = "TrimBand",
		size = Vector3.new(def.size.X + 0.4, 0.6, def.size.Y + 0.4),
		position = def.position + Vector3.new(0, def.height - 1, 0),
		material = Enum.Material.Neon,
		color = LobbyConfig.NEON_COLOR,
		canCollide = false,
		parent = model,
	})

	addSign(base, def.displayName)

	model.PrimaryPart = base
	return model
end

function Buildings.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Buildings"
	folder.Parent = parent

	for _, def in ipairs(LobbyConfig.BUILDINGS) do
		buildOne(def, folder)
	end

	return folder
end

return Buildings
