--[[
	Buildings.lua

	Constructs the four named lobby buildings from LobbyConfig.BUILDINGS.
	Each building is a genuinely walkable shell (BuildingInteriors) with a
	neon roofline trim band, a doorway, interior furnishings/terminals,
	and a sign facing the plaza (+Z direction, where spawns are).

	LEADERBOARD REDESIGN + RELOCATION (Message 18): the leaderboard is no
	longer a LobbyConfig.BUILDINGS entry at all - it has its own dedicated
	region, LobbyConfig.LEADERBOARD_ANCHOR, on the map's west side (moved
	out of the back building row to "the currently empty side of the
	map"). LeaderboardBoards.BuildAll builds five separate, independently-
	named boards (WinsLeaderboard, XPLeaderboard, QuestionsSolvedLeaderboard,
	AccuracyLeaderboard, FastestAnswerLeaderboard) fanned across an arc
	there, facing back toward the plaza. This file never touches a
	DataStore itself; LeaderboardDisplay (ServerScriptService) finds the
	five boards by their stable names and fills in live values.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local LobbyConfig = require(script.Parent.LobbyConfig)
local BuildingInteriors = require(script.Parent.BuildingInteriors)
local BuildingSigns = require(script.Parent.BuildingSigns)
local LeaderboardBoards = require(script.Parent.LeaderboardBoards)

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

	local base = BuildingInteriors.BuildShell(def, model)

	PartUtils.CreatePart({
		name = "TrimBand",
		size = Vector3.new(def.size.X + 0.4, 0.6, def.size.Y + 0.4),
		position = def.position + Vector3.new(0, def.height - 1, 0),
		material = Enum.Material.Neon,
		color = LobbyConfig.NEON_COLOR,
		canCollide = false,
		parent = model,
	})

	if def.name == "Shop" then
		addSign(base, def.displayName)
		BuildingInteriors.FurnishShop(def, model)
	elseif def.name == "DailyRewards" then
		addSign(base, def.displayName)
		BuildingInteriors.FurnishRewards(def, model)
	elseif def.name == "StatisticsBuilding" then
		addSign(base, def.displayName)
		BuildingInteriors.FurnishStatistics(def, model)
	elseif def.name == "TutorialBuilding" then
		addSign(base, def.displayName)
		BuildingInteriors.FurnishTutorial(def, model)
	else
		addSign(base, def.displayName)
	end

	-- Message 32: floating overhead sign above every building (distinct
	-- from the door-side plaque `addSign` above builds), clickable to
	-- teleport right to the building's entrance - see BuildingSigns.lua.
	BuildingSigns.BuildOne(def, model)

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

	-- Message 18: leaderboard region relocated out of the building row
	-- entirely - built from its own dedicated anchor/config, not a
	-- LobbyConfig.BUILDINGS entry.
	LeaderboardBoards.BuildAll(LobbyConfig.LEADERBOARD_ANCHOR, folder)

	return folder
end

return Buildings
