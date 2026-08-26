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

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LobbyConfig = require(ServerScriptService.LobbyBuilder.LobbyConfig)
local MapConfig = require(ServerScriptService.LobbyBuilder.MapConfig)
local BuildingInteriors = require(ServerScriptService.LobbyBuilder.BuildingInteriors)
local BuildingSigns = require(ServerScriptService.LobbyBuilder.BuildingSigns)
local MapsConfig = require(ReplicatedStorage.Modules.MapsConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)

local BuildingTeleportSystem = {}
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
	--[[
		The standoff is THEME-AWARE. A flat halfZ+6 was correct while every
		building was a bare box, but the Lava/IceAge/UnderTheSea themes wrap
		each building in a body whose radius and entrance tunnel reach well
		past halfZ - so that offset dropped the player inside the volcano
		mound / igloo dome rather than in front of it.
		BuildingInteriors.GetEntranceStandoff reports the distance that
		actually clears whatever this map's theme built.
	]]
	local standoff = BuildingInteriors.GetEntranceStandoff(def, mapDef.themeId)
	local localPosition = Vector3.new(
		def.position.X,
		STAND_HEIGHT_ABOVE_GROUND,
		def.position.Z + standoff
	)
	local worldPosition = localPosition + mapDef.origin + Vector3.new(0, MapConfig.GROUND_ELEVATION, 0)
	return CFrame.new(worldPosition) -- no rotation needed; default -Z facing already looks at the door
end

local function resolveDestination(rawName: unknown, rawMapId: unknown, who: string): (CFrame?, string?)
	if typeof(rawName) ~= "string" then
		return nil, "building name was not a string"
	end

	local def = findBuildingDef(rawName)
	if not def then
		return nil, ("unknown building %q"):format(rawName)
	end

	local mapDef = (typeof(rawMapId) == "string" and MapsConfig.GetMap(rawMapId)) or MapsConfig.GetDefaultMap()
	if not mapDef then
		return nil, ("no map definition for %q and no default map"):format(tostring(rawMapId))
	end

	local cframe = getEntranceCFrame(def, mapDef)
	-- Guard against a destination that is somehow not a finite position -
	-- PivotTo with a NaN would put the character somewhere unrecoverable.
	local p = cframe.Position
	if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z then
		return nil, ("computed a non-finite destination for %s on %s"):format(rawName, mapDef.id or "?")
	end

	return cframe, nil
end

--[[
	Shared teleport entry point for BOTH click paths. Validates on the
	server every time - neither path is trusted to have done it - and warns
	on failure rather than silently doing nothing, which is what made the
	original breakage so hard to see.
]]
local function teleportPlayerToBuilding(player: Player, rawName: unknown, rawMapId: unknown, source: string)
	local cframe, failure = resolveDestination(rawName, rawMapId, player.Name)
	if not cframe then
		warn(("[BuildingTeleportSystem] %s teleport request from %s rejected: %s"):format(source, player.Name, failure))
		return
	end

	local character = player.Character
	if not character or not character.PrimaryPart then
		warn(("[BuildingTeleportSystem] %s teleport for %s skipped: no loaded character."):format(source, player.Name))
		return
	end

	character:PivotTo(cframe)
end

local function onRequestTeleportToBuilding(player: Player, rawName: unknown, rawMapId: unknown)
	teleportPlayerToBuilding(player, rawName, rawMapId, "Remote")
end

--[[
	Wires every ClickDetector-based teleport target (LobbyBuilder/
	BuildingSigns.lua tags them BuildingSigns.TELEPORT_TARGET_TAG). This is
	the PRIMARY path: MouseClick fires on the server with the clicking
	Player, so the click never depends on client GUI input working, and the
	server is authoritative by construction.

	The part carries its own BuildingName/MapId attributes, so a click
	resolves the correct map's copy of a building without the client
	supplying anything at all.
]]
local function wireClickTarget(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local detector = part:FindFirstChildOfClass("ClickDetector")
	if not detector then
		warn(("[BuildingTeleportSystem] %s is tagged as a teleport target but has no ClickDetector."):format(part:GetFullName()))
		return
	end

	detector.MouseClick:Connect(function(player)
		teleportPlayerToBuilding(player, part:GetAttribute("BuildingName"), part:GetAttribute("MapId"), "Click")
	end)
end

function BuildingTeleportSystem.Init()
	RemoteEvents.Get("RequestTeleportToBuilding").OnServerEvent:Connect(onRequestTeleportToBuilding)

	local wiredCount = 0
	for _, part in ipairs(CollectionService:GetTagged(BuildingSigns.TELEPORT_TARGET_TAG)) do
		wireClickTarget(part)
		wiredCount += 1
	end
	CollectionService:GetInstanceAddedSignal(BuildingSigns.TELEPORT_TARGET_TAG):Connect(wireClickTarget)

	print(("[BuildingTeleportSystem] Initialized (%d click targets wired)"):format(wiredCount))
end

return BuildingTeleportSystem
