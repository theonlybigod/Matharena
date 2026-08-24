--[[
	MapsConfig.lua

	Stable registry of every Play Mode map/environment this game builds -
	the "prep for per-difficulty maps" groundwork: a single source of
	truth for which maps exist, their stable ids, which Workspace folder
	each one builds into, which visual theme it uses (see LobbyBuilder/
	LobbyTheme.lua), and where in the world it sits (so multiple maps can
	coexist in one Workspace without overlapping).

	IMPORTANT - what this module deliberately does NOT do yet:
		- It does NOT route matchmaking, spin up separate servers, or
		  assign a difficulty to a map. `difficultyId` below is present
		  and always nil for now - reserved so a future system can assign
		  GameplayConfig.QUEUE_TIERS ids to specific maps without a schema
		  change, but nothing currently reads it.
		- It does NOT change how Practice Mode selects a map. Practice
		  Mode still only ever uses the default map.
		- Only one map (`DEFAULT_MAP_ID`) is actually wired up as "the"
		  active lobby every other system references (spawns, the queue
		  portal, teleport systems, GameStateChanged visibility, etc.).
		  Every other listed map is currently a coexisting, fully-dressed
		  but otherwise-inert environment, in the same server, for
		  players to walk into and explore - see LobbyBuilder.BuildAllMaps.

	Lives in ReplicatedStorage since map ids/display names are plain data
	a future Practice Mode map-picker (client-facing) and matchmaking
	system (server-facing) will both eventually need to read, same
	reasoning GameplayConfig.QUEUE_TIERS already follows.

	Adding a future map/difficulty means adding one more entry to MAPS
	below (plus a matching Workspace folder in default.project.json and a
	theme in LobbyTheme.lua) - no existing map's entry, nor any
	construction module, needs to change.
]]

local MapsConfig = {}

export type MapDef = {
	id: string, -- stable identifier - never rename once shipped, other systems may reference it by id
	displayName: string,
	workspaceFolderName: string, -- the Workspace child Folder this map builds into (see default.project.json)
	themeId: string, -- LobbyTheme.THEMES key
	origin: Vector3, -- world-space offset this entire map is translated by after being built at local-origin coordinates
	difficultyId: number?, -- reserved for a future GameplayConfig.QUEUE_TIERS id - always nil today, not yet assigned/read anywhere
	isDefault: boolean?, -- true for exactly one map - the one every other current system (spawns, queue portal, teleports, GameStateChanged visibility) actually treats as "the" lobby
}

-- One-map-length spacing (Message: "put the size as one map in between
-- both maps, just so it's easy to navigate through both of them"): each
-- map's own footprint is a regular 30-gon roughly
-- 2*MapConfig.CIRCUMRADIUS wide (~350 studs across at the current scale).
-- Offsetting the Lava map by a full extra map-width along +X leaves
-- exactly one more map-length of open, walkable space between the two
-- maps' nearest edges - close enough to walk between without a loading
-- screen/teleport, far enough that neither map's geometry, invisible
-- boundary walls, or decorations can ever intersect the other's.
local MAP_SPACING_STUDS = 1050 -- ~3 map-widths center-to-center: one map-width each side plus one full map-width of clear space between them

MapsConfig.MAPS = {
	{
		id = "Futuristic",
		displayName = "Futuristic Arena",
		workspaceFolderName = "Lobby",
		themeId = "Futuristic",
		origin = Vector3.new(0, 0, 0),
		difficultyId = nil,
		isDefault = true,
	},
	{
		id = "Lava",
		displayName = "Lava Arena",
		workspaceFolderName = "LobbyLava",
		themeId = "Lava",
		origin = Vector3.new(MAP_SPACING_STUDS, 0, 0),
		difficultyId = nil,
		isDefault = false,
	},
} :: { MapDef }

--[[
	Returns the MapDef for `id`, or nil if unknown - callers decide their
	own fallback (usually GetDefaultMap below), since "unknown map id"
	means different things in different contexts.
]]
function MapsConfig.GetMap(id: string): MapDef?
	for _, def in ipairs(MapsConfig.MAPS) do
		if def.id == id then
			return def
		end
	end
	return nil
end

--[[
	Returns the single map flagged isDefault = true - the one every
	current system that doesn't yet know about multiple maps (spawns, the
	queue portal, teleport-to-building, GameStateChanged visibility,
	LeaderboardDisplay's primary refresh target, etc.) should keep
	treating as "the" lobby. Errors loudly if none/more than one map is
	flagged default, since that would silently break every one of those
	systems in a way that'd be confusing to debug later.
]]
function MapsConfig.GetDefaultMap(): MapDef
	local found: MapDef? = nil
	for _, def in ipairs(MapsConfig.MAPS) do
		if def.isDefault then
			assert(not found, "MapsConfig: more than one map is flagged isDefault")
			found = def
		end
	end
	assert(found, "MapsConfig: no map is flagged isDefault")
	return found :: MapDef
end

return MapsConfig
