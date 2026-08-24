--[[
	BuildingTeleportSystem

	Backs the new clickable overhead building signs (LobbyBuilder/
	BuildingSigns.lua): a player clicking the floating sign above a
	building fires "RequestTeleportToBuilding" with that building's
	LobbyConfig name (e.g. "Shop") AND which map's copy of it was clicked
	(the sign's own "MapId" attribute - see BuildingSigns.lua), and this
	module teleports them to a position directly in front of that
	building's ACTUAL doorway opening in THAT map - not the sign, not the
	building's center, and not another map's copy of the same-named
	building.

	Message 32 ("teleport right in front of it... right in front of the
	door opening... not towards the actual word/building that would
	highlight the building"): computed directly from LobbyConfig.BUILDINGS'
	static geometry rather than by reading a live Part, since every
	building's doorway is always centered on its own local (0, doorHeight,
	+halfZ) - the exact geometry BuildingInteriors.BuildShell always uses
	when cutting the doorway gap into the plaza-facing wall (see that
	module's FrontWallLeft/FrontWallRight/DoorwayTrim placement).

	Multi-map support: LobbyConfig.BUILDINGS describes every map's
	building layout in LOCAL (map-relative) coordinates - every map reuses
	the exact same layout, just translated afterward (see LobbyBuilder/
	init.lua's applyMapTransform) - so this module has to add the
	REQUESTING map's own MapsConfig.origin (plus MapConfig.GROUND_ELEVATION,
	the same single bulk vertical shift LobbyBuilder applies) on top of
	that local geometry to land in the right map's copy of the building,
	without needing to depend on the building already being built/found in
	the workspace tree.

	Self-contained: owns its own RemoteEvent connection (same pattern as
	RemoteThrottle/PracticeSystem) rather than requiring GameManager to
	know about it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LobbyConfig = require(ServerScriptService.LobbyBuilder.LobbyConfig)
local MapConfig = require(ServerScriptService.LobbyBuilder.MapConfig)
local MapsConfig = require(ReplicatedStorage.Modules.MapsConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)

local BuildingTeleportSystem = {}

-- How far out from the doorway (past the building's own front wall) the
-- player lands - far enough to stand clear of the door swing/canopy
-- overhang, close enough to obviously read as "right in front of it".
local DOOR_APPROACH_DISTANCE = 6
-- Matches Teleporter.lua's own convention for standing a character just
-- above the ground (its lobby-return teleport uses the same +3 offset).
local STAND_HEIGHT_ABOVE_GROUND = 3

local function findBuildingDef(name: string)
	for _, def in ipairs(LobbyConfig.BUILDINGS) do
		if def.name == name then
			return def
		end
	end
	return nil
end

--[[
	The CFrame directly in front of `def`'s doorway, facing the doorway,
	in `mapDef`'s WORLD space. Every building is built axis-aligned (no
	rotation - see Buildings.lua/BuildingInteriors.lua, which never apply
	a yaw to a building's parts), with its doorway always cut into the +Z
	("plaza-facing") wall at local X=0. A point further out along +Z from
	the doorway, with NO yaw rotation applied, faces back toward -Z
	(Roblox's default "Front"/-Z-facing orientation) - i.e. directly at
	the door - matching the same yaw=0-faces-toward-the-building
	convention already used by every lobby spawn (see LobbyConfig.
	yawTowards's doc comment).

	`mapDef.origin` is added on top of LobbyConfig.BUILDINGS' LOCAL (map-
	relative) position - LobbyConfig itself has no concept of which map a
	building belongs to (every map reuses the exact same building layout
	at local-origin coordinates), so resolving the CORRECT world position
	for a specific map's copy of a building is this function's job, not
	LobbyConfig's.
]]
local function getEntranceCFrame(def, mapDef: MapsConfig.MapDef): CFrame
	local halfZ = def.size.Y / 2
	local localPosition = Vector3.new(
		def.position.X,
		STAND_HEIGHT_ABOVE_GROUND,
		def.position.Z + halfZ + DOOR_APPROACH_DISTANCE
	)
	local worldPosition = localPosition + mapDef.origin + Vector3.new(0, MapConfig.GROUND_ELEVATION, 0)
	return CFrame.new(worldPosition) -- no rotation needed; default -Z facing already looks at the door
end

local function onRequestTeleportToBuilding(player: Player, rawName: unknown, rawMapId: unknown)
	if typeof(rawName) ~= "string" then
		return
	end

	local def = findBuildingDef(rawName)
	if not def then
		warn(("[BuildingTeleportSystem] Unknown building name %q requested by %s."):format(rawName, player.Name))
		return
	end

	-- `rawMapId` comes from the clicked sign's own "MapId" attribute
	-- (BuildingSigns.lua) - falls back to the default map for any
	-- stale/pre-multi-map client or malformed value, same defensive
	-- fallback convention every other client-supplied id uses elsewhere in
	-- this project.
	local mapDef = (typeof(rawMapId) == "string" and MapsConfig.GetMap(rawMapId)) or MapsConfig.GetDefaultMap()

	local character = player.Character
	if not character then
		return
	end

	character:PivotTo(getEntranceCFrame(def, mapDef))
end

function BuildingTeleportSystem.Init()
	RemoteEvents.Get("RequestTeleportToBuilding").OnServerEvent:Connect(onRequestTeleportToBuilding)
	print("[BuildingTeleportSystem] Initialized")
end

return BuildingTeleportSystem
