--[[
	BuildingTeleportSystem

	Backs the new clickable overhead building signs (LobbyBuilder/
	BuildingSigns.lua): a player clicking the floating sign above a
	building fires "RequestTeleportToBuilding" with that building's
	LobbyConfig name (e.g. "Shop"), and this module teleports them to a
	position directly in front of that building's ACTUAL doorway opening -
	not the sign, and not the building's center - facing the entrance.

	Message 32 ("teleport right in front of it... right in front of the
	door opening... not towards the actual word/building that would
	highlight the building"): computed directly from LobbyConfig.BUILDINGS'
	static geometry rather than by reading a live Part, since every
	building's doorway is always centered on its own local (0, doorHeight,
	+halfZ) - the exact geometry BuildingInteriors.BuildShell always uses
	when cutting the doorway gap into the plaza-facing wall (see that
	module's FrontWallLeft/FrontWallRight/DoorwayTrim placement). Adding
	MapConfig.GROUND_ELEVATION (the single bulk vertical shift LobbyBuilder
	applies to every built part) keeps this in agreement with where the
	building's parts actually end up standing, without this module needing
	to depend on the building already being built/found in the workspace
	tree.

	Self-contained: owns its own RemoteEvent connection (same pattern as
	RemoteThrottle/PracticeSystem) rather than requiring GameManager to
	know about it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LobbyConfig = require(ServerScriptService.LobbyBuilder.LobbyConfig)
local MapConfig = require(ServerScriptService.LobbyBuilder.MapConfig)
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
	The CFrame directly in front of `def`'s doorway, facing the doorway.
	Every building is built axis-aligned (no rotation - see Buildings.lua/
	BuildingInteriors.lua, which never apply a yaw to a building's parts),
	with its doorway always cut into the +Z ("plaza-facing") wall at local
	X=0. A point further out along +Z from the doorway, with NO yaw
	rotation applied, faces back toward -Z (Roblox's default "Front"/
	-Z-facing orientation) - i.e. directly at the door - matching the same
	yaw=0-faces-toward-the-building convention already used by every
	lobby spawn (see LobbyConfig.yawTowards's doc comment).
]]
local function getEntranceCFrame(def): CFrame
	local halfZ = def.size.Y / 2
	local position = Vector3.new(
		def.position.X,
		MapConfig.GROUND_ELEVATION + STAND_HEIGHT_ABOVE_GROUND,
		def.position.Z + halfZ + DOOR_APPROACH_DISTANCE
	)
	return CFrame.new(position) -- no rotation needed; default -Z facing already looks at the door
end

local function onRequestTeleportToBuilding(player: Player, rawName: unknown)
	if typeof(rawName) ~= "string" then
		return
	end

	local def = findBuildingDef(rawName)
	if not def then
		warn(("[BuildingTeleportSystem] Unknown building name %q requested by %s."):format(rawName, player.Name))
		return
	end

	local character = player.Character
	if not character then
		return
	end

	character:PivotTo(getEntranceCFrame(def))
end

function BuildingTeleportSystem.Init()
	RemoteEvents.Get("RequestTeleportToBuilding").OnServerEvent:Connect(onRequestTeleportToBuilding)
	print("[BuildingTeleportSystem] Initialized")
end

return BuildingTeleportSystem
