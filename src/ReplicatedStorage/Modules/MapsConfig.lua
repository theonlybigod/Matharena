--[[
	MapsConfig.lua

	Stable registry of every Play Mode map/environment this game builds -
	the "prep for per-difficulty maps" groundwork: a single source of
	truth for which maps exist, their stable ids, which Workspace folder
	each one builds into, which visual theme it uses (see LobbyBuilder/
	LobbyTheme.lua), and where in the world it sits (so multiple maps can
	coexist in one Workspace without overlapping).

	Play Mode Architecture (README.md): `difficultyId` below is now used -
	DifficultyPlacesConfig.lua (also ReplicatedStorage/Modules) is the
	actual difficulty -> Place routing table PlaceTeleportSystem reads;
	this field just keeps each map's own entry self-describing and in
	sync with that table (kept as plain data here rather than only living
	in DifficultyPlacesConfig, since a map's difficulty is as much a
	property of the MAP as of the Place it's routed to).

	IMPORTANT - what this module still deliberately does NOT do:
		- It does NOT change how Practice Mode selects a map. Practice
		  Mode still only ever uses the default map, and never teleports
		  cross-server for any difficulty - see PracticeSystem.lua.
		- On the Hub (this repo's main Place), every map still builds and
		  coexists in one Workspace exactly as before Play Mode routing
		  existed - only one map (`DEFAULT_MAP_ID`) is wired up as "the"
		  active lobby every other Hub-only system references (spawns,
		  the queue portal, GameStateChanged visibility, etc.). On a
		  dedicated difficulty Place, Main.server.lua builds ONLY that
		  Place's one assigned map - see DifficultyPlacesConfig.lua.

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
	difficultyId: number?, -- matches a GameplayConfig.QUEUE_TIERS id; see DifficultyPlacesConfig.lua for the actual routing table
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
		difficultyId = 1, -- GameplayConfig.QUEUE_TIERS id 1, Easy Mode - see DifficultyPlacesConfig.lua
		isDefault = true,
	},
	{
		id = "Lava",
		displayName = "Lava Arena",
		workspaceFolderName = "LobbyLava",
		themeId = "Lava",
		origin = Vector3.new(MAP_SPACING_STUDS, 0, 0),
		difficultyId = 4, -- GameplayConfig.QUEUE_TIERS id 4, Expert Mode ("Volcano") - see DifficultyPlacesConfig.lua
		isDefault = false,
	},
	{
		id = "Space",
		displayName = "Space Arena",
		workspaceFolderName = "LobbySpace",
		themeId = "Space",
		-- Offset along -Z (not +X like Lava) so the two non-default maps
		-- never sit collinear with each other or with the default map -
		-- same MAP_SPACING_STUDS distance-from-origin convention as Lava,
		-- just along a different axis, giving every map its own clear
		-- quadrant to expand into later. The Space map also builds a large
		-- (but bounded) surrounding starfield dome (see SpaceEnvironment.lua)
		-- - this spacing keeps that dome's radius comfortably clear of both
		-- the origin map (Futuristic/Arena) and the Lava map's own footprint;
		-- see SpaceEnvironment.lua's module doc for the exact radius check.
		origin = Vector3.new(0, 0, -MAP_SPACING_STUDS),
		difficultyId = 5, -- GameplayConfig.QUEUE_TIERS id 5, Master Mode - see DifficultyPlacesConfig.lua
		isDefault = false,
	},
	{
		id = "UnderTheSea",
		displayName = "Under the Sea Arena",
		workspaceFolderName = "LobbyUnderTheSea",
		themeId = "UnderTheSea",
		-- Mirrors Lava's own axis (-X instead of +X) so all four non-origin
		-- maps sit on their own cardinal direction from the shared
		-- Futuristic/Arena origin, none of them collinear with each other:
		-- Lava (+X), UnderTheSea (-X), Space (-Z), IceAge (+Z).
		origin = Vector3.new(-MAP_SPACING_STUDS, 0, 0),
		difficultyId = 2, -- GameplayConfig.QUEUE_TIERS id 2, Medium Mode ("Under the Sea") - see DifficultyPlacesConfig.lua
		isDefault = false,
	},
	{
		id = "IceAge",
		displayName = "Ice Age Arena",
		workspaceFolderName = "LobbyIceAge",
		themeId = "IceAge",
		-- Mirrors Space's own axis (+Z instead of -Z) - see the UnderTheSea
		-- entry's comment above for the full four-cardinal-direction layout.
		origin = Vector3.new(0, 0, MAP_SPACING_STUDS),
		difficultyId = 3, -- GameplayConfig.QUEUE_TIERS id 3, Hard Mode ("Tundra") - see DifficultyPlacesConfig.lua
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
