--[[
	LobbyConfig.lua

	Centralized dimensions/positions for the procedurally generated lobby.
	Coordinate convention used throughout LobbyBuilder:
		+X = east, +Z = "front" (toward spawns), -Z = "back" (toward buildings)
		Buildings sit on the -Z side, spawns + entrance on the +Z side,
		the queue portal plaza sits at the origin in between.

	Building "size" fields are Vector2(width, depth) — .X maps to world X,
	.Y maps to world Z (Vector2 has no Z component, this is just a compact
	way to store a footprint).

	Map-scale refinement (Message 2): every position below is the ORIGINAL
	layout's coordinates multiplied by MapConfig.SCALE_FACTOR (1.5) - this
	is "recalculating object placement for the larger map" rather than
	just stretching the ground underneath everything, since every
	building/spawn actually moves outward and gains proportionally more
	space around it and its neighbors. Building/spawn/portal SIZES are
	intentionally left unscaled ("preserve the existing major buildings"
	- give them more room, don't resize them). PERIMETER_INSET (a
	square-specific "distance from the edge" concept) is gone entirely -
	Decorations.lua now places rings by radius, relative to
	MapConfig.USABLE_RADIUS, which works for the new 30-gon boundary.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)
local MapConfig = require(script.Parent.MapConfig)

local LobbyConfig = {}

local SCALE = MapConfig.SCALE_FACTOR

local function scaled(x: number, z: number): Vector3
	return Vector3.new(x * SCALE, 0, z * SCALE)
end

-- Kept for reference/backward compatibility - the ground itself is no
-- longer this square; see MapConfig.lua (BOUNDARY_APOTHEM/CIRCUMRADIUS)
-- for the actual current footprint.
LobbyConfig.LOBBY_SIZE = MapConfig.OLD_LOBBY_SIZE
LobbyConfig.FLOOR_THICKNESS = 2

LobbyConfig.FLOOR_COLOR = Color3.fromRGB(180, 180, 185) -- smooth concrete
-- Building trim/accent color across Buildings.lua + BuildingInteriors.lua.
-- Was a flat Config.BRAND_NEON_COLOR; now pulls the dedicated
-- "building trim" shade from the calmer-neon-lighting palette (Message 2
-- refinement) so buildings read as a distinct, slightly cooler accent
-- from the ground/path and central-feature shades used elsewhere.
LobbyConfig.NEON_COLOR = LightingConfig.BUILDING_TRIM

LobbyConfig.SPAWN_SIZE = Vector2.new(8, 8)
LobbyConfig.SPAWN_POSITIONS = {
	scaled(-30, 90),
	scaled(-10, 90),
	scaled(10, 90),
	scaled(30, 90),
}

-- Message 20 major expansion: buildings grew substantially (roughly
-- 1.2-1.3x each footprint dimension, +5-6 studs of height) - "the
-- interiors should have enough space to feel like actual locations", not
-- a small decoration pass. Repositioned (not just resized in place) to
-- keep genuine clearance between the now-bigger buildings: Shop/
-- StatisticsBuilding sit further out and shallower (closer to the
-- portal), DailyRewards/TutorialBuilding sit further back and more
-- inward, forming a gentle fan rather than a straight row - verified via
-- Python before applying: ~44 studs of clearance between adjacent
-- buildings (was down to single digits when simply scaled up in place),
-- and every building's furthest corner stays within ~165 studs of the
-- map center (safely inside the ~172-stud usable radius).
LobbyConfig.BUILDINGS = {
	{
		name = "Shop",
		displayName = "Shop",
		size = Vector2.new(36, 30),
		position = scaled(-68, -20),
		height = 26,
	},
	{
		name = "DailyRewards",
		displayName = "Daily Rewards",
		size = Vector2.new(26, 26),
		position = scaled(-26, -68),
		height = 21,
	},
	{
		name = "TutorialBuilding",
		displayName = "Tutorial Building",
		size = Vector2.new(26, 26),
		position = scaled(26, -68),
		height = 21,
	},
	{
		name = "StatisticsBuilding",
		displayName = "Statistics Building",
		size = Vector2.new(36, 19),
		position = scaled(68, -20),
		height = 19,
	},
}

-- Message 18: dedicated leaderboard region, relocated from the middle of
-- the back building row to its own dedicated region. Not a
-- LobbyConfig.BUILDINGS entry anymore (nothing here builds a walk-in
-- structure or occupies the building row); LeaderboardBoards.BuildAll
-- reads this directly.
--
-- Message 20: moved to the NORTH side (+Z, the spawn/entrance side) per
-- explicit direction, facing back toward the map center.
--
-- Message 21: pushed much closer to the boundary (per explicit "~5-stud
-- buffer from the map edge" direction, measured from each board's actual
-- physical corner, not its center) and re-tuned for the bigger boards
-- (LeaderboardConfig.BOARD_WIDTH/HEIGHT). facingYawDegrees = 180 still
-- only drives the POSITION math (fanning the boards' centers into the
-- arc shape) - each board's actual ORIENTATION is now computed
-- separately in LeaderboardBoards.lua as a direct look-at toward
-- LeaderboardConfig.VIEW_FOCAL_POINT, which is what actually fixes the
-- two end boards being hard to see (see that module's comment).
-- Verified via Python before applying: every board corner stays within
-- 174.5 studs of center (boundary sits at 187, so a genuine ~7.5-stud
-- buffer - "approximately 5 studs"), every adjacent pair keeps 5+ studs
-- of clearance (no overlap), and the whole arc keeps ~7.9 studs of
-- clearance from the nearest spawn point.
LobbyConfig.LEADERBOARD_ANCHOR = {
	position = scaled(0, 93),
	facingYawDegrees = 180,
}

LobbyConfig.QUEUE_PORTAL_SIZE = Vector2.new(12, 12)
LobbyConfig.QUEUE_PORTAL_POSITION = Vector3.new(0, 0, 0) -- stays at the map's true center regardless of scale

LobbyConfig.TREE_SPACING = 25 * SCALE -- still referenced by the street-lamp ring spacing multiplier (see StreetLampConfig.lua)

-- Note: the old small floating logo that used LOGO_HEIGHT was removed
-- during the sign cleanup pass (it duplicated LobbyBuilder/Sign.lua's
-- landmark sign). That sign's own position/size now live in
-- ReplicatedStorage/Modules/SignConfig.lua instead, since it's shared
-- with the client-side bob animation, which LobbyConfig isn't.

return LobbyConfig
