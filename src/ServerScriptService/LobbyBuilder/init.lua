--[[
	LobbyBuilder

	Procedurally constructs a lobby map (floor, buildings, spawns, queue
	portal, decorations) under its own Workspace folder, from source-
	controlled data in LobbyConfig/MapConfig plus a visual theme
	(LobbyTheme.lua) - see MapsConfig.lua (ReplicatedStorage/Modules) for
	the registry of every map this builds.

	Multi-map support: every construction module (Floor/Buildings/
	BuildingInteriors/BuildingSigns/Decorations/Trees/StreetLamps/Seating/
	SpawnsAndPortal/LeaderboardBoards/Sign) still builds everything
	assuming it's working in its own LOCAL space, exactly as before a
	second map ever existed - none of them know or care where in the
	world their finished map ends up. A map's THEME (color/material
	palette) is latched via each themed module's SetTheme(theme) call,
	made once per map right before that module builds anything, so every
	one of its (otherwise completely unchanged) construction functions
	picks up the right palette without needing a theme parameter threaded
	through every call. A map's WORLD POSITION is handled the exact same
	way GROUND_ELEVATION always was (see applyMapTransform below) - a
	single bulk translation applied to every already-built BasePart at
	the very end, rather than threading a world-offset through every
	position calculation in every module. This is what lets two (or more)
	maps coexist in the same Workspace, at different world locations,
	using the exact same source files, with zero risk of one map's
	geometry drifting into another's.

	Rerun policy (decided by design, see project history) - per MAP:
		- Build(mapDef) is safe to call every server start. If that map's
		  root Workspace folder is already marked built (via the
		  "MathArenaBuilt" attribute), it does nothing.
		- Rebuild(mapDef) forces a full rebuild of that one map, destroying
		  and regenerating everything currently under its root folder. It
		  prints a warning stating exactly what will be destroyed before
		  doing so.
		- BuildAllMaps()/RebuildAllMaps() do the above for every map in
		  MapsConfig.MAPS - this is what Main.server.lua actually calls at
		  server start.

	Backward-compatible no-arg calls: `Build()`/`Rebuild()` with no
	argument default to MapsConfig.GetDefaultMap() (the existing
	futuristic map) - the exact same map/behavior as before multi-map
	support existed, for any manual Studio command-bar usage:
		require(game.ServerScriptService.LobbyBuilder).Build()   -- default map, build if not already built
		require(game.ServerScriptService.LobbyBuilder).Rebuild() -- default map, force full rebuild
		require(game.ServerScriptService.LobbyBuilder).Build(require(game.ReplicatedStorage.Modules.MapsConfig).GetMap("Lava"))
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapsConfig = require(ReplicatedStorage.Modules.MapsConfig)
local BuildVersion = require(ReplicatedStorage.Modules.BuildVersion)
local LobbyTheme = require(script.LobbyTheme)
local MapConfig = require(script.MapConfig)
local Buildings = require(script.Buildings)
local Decorations = require(script.Decorations)
local SpawnsAndPortal = require(script.SpawnsAndPortal)
local Floor = require(script.Floor)
local LobbyLighting = require(script.LobbyLighting)
local Sign = require(script.Sign)
local LeaderboardBoards = require(script.LeaderboardBoards)
local SpaceEnvironment = require(script.SpaceEnvironment)
local UnderTheSeaEnvironment = require(script.UnderTheSeaEnvironment)
local IceAgeEnvironment = require(script.IceAgeEnvironment)
local LavaEnvironment = require(script.LavaEnvironment)
local MapBaseplate = require(script.MapBaseplate)

local LobbyBuilder = {}

--[[
	Applies MapConfig.GROUND_ELEVATION (vertical) AND mapDef.origin
	(horizontal, world-space) as a single bulk translation to every
	BasePart already built under `root`, run once at the end of
	Build(mapDef). Every construction module still builds everything
	assuming it's working at its own local origin (0, 0, 0) - this is
	what actually places the finished map at its real world position
	afterward, rather than threading a world-offset through every
	module's internal position math. Shifting .Position (not re-deriving
	each CFrame) leaves every part's existing rotation untouched - a pure
	translation.
]]
local function applyMapTransform(root: Instance, mapDef: MapsConfig.MapDef)
	local offset = mapDef.origin + Vector3.new(0, MapConfig.GROUND_ELEVATION, 0)
	if offset.Magnitude == 0 then
		return
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Position += offset
		end
	end
end

function LobbyBuilder.Build(mapDef: MapsConfig.MapDef?, force: boolean?, enableSpawns: boolean?)
	local def = mapDef or MapsConfig.GetDefaultMap()
	local root = Workspace:FindFirstChild(def.workspaceFolderName)
	if not root then
		-- Every map's root folder is declared in default.project.json (so
		-- Rojo owns creating it, same as the original "Lobby"/"Arena"
		-- folders) - this fallback only matters if that sync hasn't
		-- happened yet for some reason; it never creates a competing,
		-- Studio-only instance that Rojo doesn't know about.
		root = Instance.new("Folder")
		root.Name = def.workspaceFolderName
		root.Parent = Workspace
	end

	local alreadyBuilt = root:GetAttribute("MathArenaBuilt") == true

	-- Stale-geometry check (see BuildVersion.lua's doc comment for the full
	-- reasoning): geometry built by an older version of the builder code is
	-- regenerated automatically, even without `force`. Without this, the
	-- MathArenaBuilt attribute saved into a published place file froze that
	-- Place's world at whatever the code produced the day it was first
	-- built - which is exactly why edits reached some Places and not others.
	-- A folder built before this system existed has no stored version at
	-- all (nil ~= CURRENT), so it counts as stale and rebuilds once.
	local storedVersion = root:GetAttribute("MathArenaBuildVersion")
	local versionStale = storedVersion ~= BuildVersion.CURRENT

	-- Also rebuild if this folder currently holds a DIFFERENT map than the
	-- one being requested (e.g. a Place reassigned to another difficulty).
	-- Cheap to check, and prevents silently keeping the wrong map forever.
	local storedMapId = root:GetAttribute("MathArenaMapId")
	local mapChanged = storedMapId ~= nil and storedMapId ~= def.id

	if alreadyBuilt and not force and not versionStale and not mapChanged then
		print(("[LobbyBuilder] %s already built and current; skipping. Call LobbyBuilder.Rebuild() to force a full rebuild."):format(def.id))
		return
	end

	if alreadyBuilt then
		local reason = if force
			then "forced"
			elseif mapChanged then ("folder previously held map '%s'"):format(tostring(storedMapId))
			else ("built by an older build version (%s -> %d)"):format(tostring(storedVersion), BuildVersion.CURRENT)
		warn(
			("[LobbyBuilder] Rebuilding %s (%s): destroying %d existing top-level instance(s) under Workspace.%s (and everything inside them)."):format(
				def.id,
				reason,
				#root:GetChildren(),
				def.workspaceFolderName
			)
		)
	end

	for _, child in ipairs(root:GetChildren()) do
		child:Destroy()
	end

	local theme = LobbyTheme.Get(def.themeId)
	Floor.SetTheme(theme)
	Buildings.SetTheme(theme)
	Decorations.SetTheme(theme)
	SpawnsAndPortal.SetTheme(theme)
	LeaderboardBoards.SetTheme(theme)
	Sign.SetTheme(theme)

	if def.isDefault then
		-- Only the default map re-applies the GLOBAL Lighting service
		-- post-effects. Lighting/Atmosphere/Bloom/ColorCorrection are
		-- children of the single shared Lighting service, not of any
		-- individual map's Workspace folder - they can't meaningfully
		-- differ per-map while multiple maps coexist in one server, so
		-- only the default map's build path touches them (matches
		-- Main.server.lua's own unconditional LobbyLighting.Apply() call
		-- immediately after this, which is what actually keeps it
		-- self-healing on every server start regardless of build state).
		LobbyLighting.Apply()
	end

	-- Which map's spawns get Enabled = true: normally the map flagged
	-- isDefault in MapsConfig (the Hub's own "home" map, Futuristic) - but
	-- a caller building the ONE map assigned to a dedicated difficulty
	-- Place (see Main.server.lua) passes enableSpawns = true explicitly,
	-- since that map is the only one that will ever exist there and must
	-- have working spawns regardless of its global isDefault flag. Only
	-- Main.server.lua's difficulty-Place branch does this; BuildAllMaps()/
	-- RebuildAllMaps() (the Hub's path) never pass a third argument, so
	-- the Hub's spawn-enable behavior is completely unchanged.
	local shouldEnableSpawns = if enableSpawns ~= nil then enableSpawns else def.isDefault == true
	Floor.Build(root)
	Buildings.BuildAll(root, def.id)
	SpawnsAndPortal.BuildSpawns(root, shouldEnableSpawns)
	SpawnsAndPortal.BuildQueuePortal(root)
	Decorations.BuildAll(root)
	Sign.Build(root)

	-- Per-theme surrounding backdrop (starfield dome for Space, water
	-- volume for Under the Sea, whiteout sky for Ice Age, etc.) - see each
	-- module's own doc comment for why this is genuinely new geometry
	-- rather than something every theme can express through LobbyTheme
	-- alone, and why it's safe to build unconditionally in local space
	-- here (applyMapTransform below carries it to the right world position
	-- along with everything else). Every map WITHOUT a matching branch
	-- below is completely untouched by this dispatch.
	if def.themeId == "Space" then
		SpaceEnvironment.BuildAll(root)
	elseif def.themeId == "UnderTheSea" then
		UnderTheSeaEnvironment.BuildAll(root)
	elseif def.themeId == "IceAge" then
		IceAgeEnvironment.BuildAll(root)
	elseif def.themeId == "Lava" then
		LavaEnvironment.BuildAll(root)
	end

	--[[
		Ground slab just under the walkable plate, so looking out over the
		rim shows terrain running to the horizon instead of the plate ending
		in mid-air.

		The themed maps each already have a deep floor (SkyFloor, RockFloor,
		WaterFloor, DomeFloor) but those sit at Y = -202, some 205 studs
		below the plate - far enough, and hazed enough by each map's own
		atmosphere, that they do not read as ground at all. From the rim the
		map looks like a disc floating in empty space. This fills that gap;
		the deep floors still close the map off from below.

		DELIBERATELY NOT APPLIED TO FUTURISTIC. That map is the default lobby
		at the world origin, is presented as a platform in open sky, and has
		no deep floor of its own - a slab under it would change its
		established look rather than complete it. Guarded by themeId so any
		future theme opts in explicitly.

		Built in LOCAL space like everything else above, so applyMapTransform
		below carries it to the map's world position.
	]]
	if def.themeId ~= "Futuristic" then
		MapBaseplate.Build(root, {
			-- LobbyConfig's plate sits with its top surface at this height.
			plateTopY = 3,
			-- Comfortably past the widest enclosure (Lava's, at 440) so the
			-- slab always reaches beyond the boundary walls and no outer edge
			-- is ever visible from inside the map.
			extent = 620,
			-- Uses the map's own floor palette, so each baseplate reads as that
			-- map's terrain rather than a generic grey slab.
			color = theme.floorColor,
			material = theme.floorMaterial,
		})
	end
	-- CentralBoard was manually deleted directly in Studio - no longer
	-- built here so a future Rebuild() reproduces that deletion instead of
	-- silently re-creating it. CentralBoard.lua/CentralBoardConfig.lua
	-- still physically exist on disk (unused dead code) - I don't have a
	-- file-delete capability, so removing them from disk entirely needs a
	-- manual step outside this pipeline if you want them gone for good.

	applyMapTransform(root, def)

	--[[
		Ice Age mountain range, built AFTER applyMapTransform and only for that
		map. It is Terrain, not BaseParts, so the transform above cannot move
		it - it has to be written at the final world position directly. That is
		why this sits here rather than in the themed-environment dispatch with
		every other backdrop.
	]]
	if def.themeId == "IceAge" then
		local worldOrigin = def.origin + Vector3.new(0, MapConfig.GROUND_ELEVATION, 0)
		local ok, tiles = pcall(IceAgeEnvironment.BuildTerrainMountains, worldOrigin)
		if ok then
			print(("[LobbyBuilder] IceAge terrain range written (%s tiles)."):format(tostring(tiles)))
		else
			-- Terrain writes can fail on region/limit errors; the map is still
			-- perfectly playable without the backdrop, so warn rather than
			-- aborting the whole build.
			warn("[LobbyBuilder] IceAge terrain range failed: " .. tostring(tiles))
		end
	end

	root:SetAttribute("MathArenaBuilt", true)
	root:SetAttribute("MathArenaBuiltAt", DateTime.now().UnixTimestamp)
	root:SetAttribute("MathArenaMapId", def.id)
	root:SetAttribute("MathArenaBuildVersion", BuildVersion.CURRENT)

	print(("[LobbyBuilder] %s build complete."):format(def.id))
end

--[[
	Forces a full rebuild of `mapDef` (default map if omitted), destroying
	and regenerating everything currently under its root Workspace folder.
	Intended to be run manually, e.g. from the Studio command bar:
		require(game.ServerScriptService.LobbyBuilder).Rebuild()
]]
function LobbyBuilder.Rebuild(mapDef: MapsConfig.MapDef?)
	return LobbyBuilder.Build(mapDef, true)
end

--[[
	Self-healing spawn-enable pass for `mapDef`'s ALREADY-BUILT Workspace
	folder. Build()'s own `enableSpawns` argument only takes effect the
	moment a map is actually (re)built - it does nothing on a Place where
	that map was already marked MathArenaBuilt under the OLD isDefault-only
	spawn logic (every difficulty Place tested before this fix existed, at
	minimum Under the Sea). Those Places would otherwise keep disabled
	spawns forever, since Build() skips re-running once already built.

	This walks `mapDef`'s existing Spawns folder (a no-op if the map or its
	Spawns folder doesn't exist yet) and force-enables every SpawnLocation
	under it - cheap, non-destructive (nothing is rebuilt/destroyed, unlike
	Rebuild()), and safe to call unconditionally on every server start, same
	reasoning as Main.server.lua's own unconditional LobbyLighting.Apply()
	call right after this runs.
]]
function LobbyBuilder.EnsureSpawnsEnabled(mapDef: MapsConfig.MapDef)
	local root = Workspace:FindFirstChild(mapDef.workspaceFolderName)
	if not root then
		return
	end
	local spawnsFolder = root:FindFirstChild("Spawns")
	if not spawnsFolder then
		return
	end
	for _, child in ipairs(spawnsFolder:GetChildren()) do
		if child:IsA("SpawnLocation") then
			child.Enabled = true
		end
	end
end

--[[
	Builds every map registered in MapsConfig.MAPS - this is what
	Main.server.lua actually calls at server start. Each map is
	independently safe-to-rerun (see Build's own rerun policy above), so
	calling this on every server start is exactly as cheap as the
	original single-map Build() always was once every map is already
	built.
]]
function LobbyBuilder.BuildAllMaps()
	for _, def in ipairs(MapsConfig.MAPS) do
		LobbyBuilder.Build(def)
	end
end

--[[
	Forces a full rebuild of every map registered in MapsConfig.MAPS.
]]
function LobbyBuilder.RebuildAllMaps()
	for _, def in ipairs(MapsConfig.MAPS) do
		LobbyBuilder.Rebuild(def)
	end
end

return LobbyBuilder
