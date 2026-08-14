--[[
	LobbyBuilder

	Procedurally constructs the entire lobby (floor, buildings, spawns,
	queue portal, decorations, lighting) under Workspace.Lobby, from
	source-controlled data in LobbyConfig.

	Rerun policy (decided by design, see project history):
		- Build() is safe to call every server start. If Workspace.Lobby
		  is already marked built (via the "MathArenaBuilt" attribute),
		  it does nothing.
		- Rebuild() forces a full rebuild, destroying and regenerating
		  everything currently under Workspace.Lobby. It prints a warning
		  stating exactly what will be destroyed before doing so.

	To (re)build the lobby by hand from Roblox Studio (Edit mode or Play
	mode command bar):
		require(game.ServerScriptService.LobbyBuilder).Build()   -- build if not already built
		require(game.ServerScriptService.LobbyBuilder).Rebuild() -- force full rebuild
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyConfig = require(script.LobbyConfig)
local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local Buildings = require(script.Buildings)
local Decorations = require(script.Decorations)
local SpawnsAndPortal = require(script.SpawnsAndPortal)

local LobbyBuilder = {}

local function buildFloor(lobby: Instance)
	PartUtils.CreatePart({
		name = "Floor",
		size = Vector3.new(LobbyConfig.LOBBY_SIZE, LobbyConfig.FLOOR_THICKNESS, LobbyConfig.LOBBY_SIZE),
		position = Vector3.new(0, -LobbyConfig.FLOOR_THICKNESS / 2, 0),
		material = Enum.Material.Concrete,
		color = LobbyConfig.FLOOR_COLOR,
		parent = lobby,
	})

	local trimFolder = Instance.new("Folder")
	trimFolder.Name = "FloorTrim"
	trimFolder.Parent = lobby

	local half = LobbyConfig.LOBBY_SIZE / 2
	local trimThickness = 1

	local edges = {
		{ size = Vector3.new(LobbyConfig.LOBBY_SIZE, 0.2, trimThickness), position = Vector3.new(0, 0.1, half - trimThickness / 2) },
		{ size = Vector3.new(LobbyConfig.LOBBY_SIZE, 0.2, trimThickness), position = Vector3.new(0, 0.1, -half + trimThickness / 2) },
		{ size = Vector3.new(trimThickness, 0.2, LobbyConfig.LOBBY_SIZE), position = Vector3.new(half - trimThickness / 2, 0.1, 0) },
		{ size = Vector3.new(trimThickness, 0.2, LobbyConfig.LOBBY_SIZE), position = Vector3.new(-half + trimThickness / 2, 0.1, 0) },
	}

	for i, edge in ipairs(edges) do
		PartUtils.CreatePart({
			name = "TrimEdge" .. i,
			size = edge.size,
			position = edge.position,
			material = Enum.Material.Neon,
			color = LobbyConfig.NEON_COLOR,
			canCollide = false,
			parent = trimFolder,
		})
	end
end

-- NOTE: Lighting is a single global service shared by the whole place, not
-- something scoped to Workspace.Lobby. These settings will also apply to
-- the Arena until a later prompt gives the Arena its own atmosphere.
local function applyLighting()
	Lighting.Ambient = Color3.fromRGB(40, 45, 60)
	Lighting.OutdoorAmbient = Color3.fromRGB(40, 45, 60)
	Lighting.Brightness = 2
	Lighting.ClockTime = 21
	Lighting.FogColor = Color3.fromRGB(20, 20, 30)
	Lighting.FogEnd = 500
end

function LobbyBuilder.Build(force: boolean?)
	local lobby = Workspace:WaitForChild("Lobby")

	local alreadyBuilt = lobby:GetAttribute("MathArenaBuilt") == true
	if alreadyBuilt and not force then
		print("[LobbyBuilder] Lobby already built; skipping. Call LobbyBuilder.Rebuild() to force a full rebuild.")
		return
	end

	if alreadyBuilt and force then
		warn(
			("[LobbyBuilder] Rebuilding lobby: destroying %d existing top-level instance(s) under Workspace.Lobby (and everything inside them)."):format(
				#lobby:GetChildren()
			)
		)
	end

	for _, child in ipairs(lobby:GetChildren()) do
		child:Destroy()
	end

	applyLighting()
	buildFloor(lobby)
	Buildings.BuildAll(lobby)
	SpawnsAndPortal.BuildSpawns(lobby)
	SpawnsAndPortal.BuildQueuePortal(lobby)
	Decorations.BuildAll(lobby)

	lobby:SetAttribute("MathArenaBuilt", true)
	lobby:SetAttribute("MathArenaBuiltAt", DateTime.now().UnixTimestamp)

	print("[LobbyBuilder] Lobby build complete.")
end

--[[
	Forces a full rebuild, destroying and regenerating everything currently
	under Workspace.Lobby. Intended to be run manually, e.g. from the
	Studio command bar:
		require(game.ServerScriptService.LobbyBuilder).Rebuild()
]]
function LobbyBuilder.Rebuild()
	return LobbyBuilder.Build(true)
end

return LobbyBuilder
