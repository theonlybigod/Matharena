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
-- Message 23: each spawn now faces the leaderboard arc directly, not
-- just "generally toward the plaza" (the previous default/unrotated
-- facing left the two OUTER spawns pointing ~59 degrees off from the
-- leaderboard anchor - close enough to see them peripherally, but not
-- genuinely "in front of" the player as this message requires). Each
-- entry now carries its own yaw, computed as an exact look-at from that
-- spawn's position toward LobbyConfig.LEADERBOARD_ANCHOR.position -
-- verified via Python (yaw = atan2(-dirX, -dirZ), matching a
-- SpawnLocation's default -Z-facing orientation with zero rotation) so
-- each spawn's resulting LookVector exactly matches the direction toward
-- the leaderboard arc, not approximated.
LobbyConfig.SPAWN_POSITIONS = {
	{ position = scaled(-30, 90), facingYawDegrees = -59.04 },
	{ position = scaled(-10, 90), facingYawDegrees = -29.05 },
	{ position = scaled(10, 90), facingYawDegrees = 29.05 },
	{ position = scaled(30, 90), facingYawDegrees = 59.04 },
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
--
-- Message 22: pulled back in from the boundary again (anchor_z 93 -> 72)
-- specifically to make room for the now much-wider arc (bigger boards +
-- wider spread, see LeaderboardConfig.lua's ARC_SPREAD_RADIUS comment for
-- the exact numbers) without pushing the two end boards past the
-- boundary or too close to the spawn row. Verified via Python before
-- applying: every board corner stays a comfortable ~32 studs inside the
-- boundary and ~12 studs clear of the nearest spawn point, with the two
-- end boards genuinely more separated from the middle ones (~17.9-stud
-- end gap vs ~9.1-stud inner gap) rather than one uniform spacing.
LobbyConfig.LEADERBOARD_ANCHOR = {
	position = scaled(0, 72),
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
