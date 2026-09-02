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

--[[
	Computes the yaw (degrees) that makes a SpawnLocation's default
	-Z-facing orientation (zero rotation) point exactly from `fromPos`
	toward `toPos`, ignoring height. Computed directly here (rather than
	hand-derived decimal literals) so it can never drift out of sync with
	wherever the leaderboard anchor happens to move to. Matches the exact
	convention Message 23 already validated (yaw = atan2(-dirX, -dirZ)) for
	a CFrame.Angles(0, yaw, 0) rotation.
]]
local function yawTowards(fromPos: Vector3, toPos: Vector3): number
	local dir = toPos - fromPos
	return math.deg(math.atan2(-dir.X, -dir.Z))
end

-- Spawn-side fix ("spawn IN FRONT of the leaderboards, not behind
-- them"): every leaderboard board's actual DISPLAY face (the SurfaceGui
-- is on Enum.NormalId.Back - see LeaderboardBoards.lua) was verified
-- directly against the live boards' CFrame.LookVector to face toward
-- DECREASING Z (each board's Front/LookVector points toward INCREASING
-- Z, so the opposite Back face - where the screen actually renders -
-- points the other way, toward the map center/portal). The boards
-- themselves sit around Z=122-138 (scaled). The OLD spawn Z (90 unscaled
-- = 153 scaled) put players just beyond that range on the FURTHER side -
-- i.e. behind the boards' blank Front face, the wrong side entirely,
-- matching the bug report exactly (Message 23's per-spawn rotation only
-- pointed the camera AT the boards' position - it never fixed which SIDE
-- of them the player was standing on).
--
-- Fix: moved to unscaled Z=55 (scaled ~93.5), comfortably between the
-- queue portal (Z=0) and the nearest board (~Z=122) - genuinely on the
-- viewable/Back-face side now, with real walking room on both sides.
-- facingYawDegrees is recomputed via yawTowards() above (now pointing in
-- the opposite general direction from before, since the spawn is on the
-- opposite side of the arc now) so each spawn still looks exactly at the
-- leaderboard anchor - this time correctly aimed at the screens rather
-- than their blank back.
LobbyConfig.SPAWN_POSITIONS = {
	{ position = scaled(-30, 55), facingYawDegrees = yawTowards(scaled(-30, 55), scaled(0, 72)) },
	{ position = scaled(-10, 55), facingYawDegrees = yawTowards(scaled(-10, 55), scaled(0, 72)) },
	{ position = scaled(10, 55), facingYawDegrees = yawTowards(scaled(10, 55), scaled(0, 72)) },
	{ position = scaled(30, 55), facingYawDegrees = yawTowards(scaled(30, 55), scaled(0, 72)) },
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
	--[[
		CEILING HEIGHTS RAISED so the full feature screen clears the ceiling.

		Measured on the Space map before this change (floor surface Y=4.5):

		  Shop                screen top 24.0, ceiling 29.5 -> 5.0 clear
		  DailyRewards        screen top 22.5, ceiling 24.5 -> 2.0 clear
		  TutorialBuilding    screen top 22.5, ceiling 24.5 -> 2.0 clear
		  StatisticsBuilding  screen top 20.5, ceiling 22.5 -> 2.0 clear

		Two studs is nothing. The frame top sat essentially against the ceiling
		slab, so from a standing eye height the ceiling's near edge cut across
		the top of the panel - the screen was not clipped in geometry, but it
		was not fully VISIBLE either, which is what matters.

		Interior height is (height - 1), so +8 studs here buys 8 studs of
		headroom. Combined with the reworked screen sizing in
		BuildingInteriors.buildFeatureScreen, every building now clears by ~10.

		StatisticsBuilding gets +8 like the rest rather than being levelled to
		the others: its 36x19 footprint is the shallowest, and matching the
		taller rooms' absolute height would have made a narrow room feel like a
		lift shaft.

		SHARED BY ALL FIVE MAPS - the other four need a rebuild to pick this up.
	]]
	{
		name = "Shop",
		displayName = "Shop",
		size = Vector2.new(36, 30),
		position = scaled(-68, -20),
		height = 34,
	},
	{
		name = "DailyRewards",
		displayName = "Daily Rewards",
		size = Vector2.new(26, 26),
		position = scaled(-26, -68),
		height = 29,
	},
	{
		name = "TutorialBuilding",
		displayName = "Tutorial Building",
		size = Vector2.new(26, 26),
		position = scaled(26, -68),
		height = 29,
	},
	{
		name = "StatisticsBuilding",
		displayName = "Statistics Building",
		size = Vector2.new(36, 19),
		position = scaled(68, -20),
		height = 27,
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
