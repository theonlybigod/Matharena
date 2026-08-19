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

LobbyConfig.BUILDINGS = {
	{
		name = "Shop",
		displayName = "Shop",
		size = Vector2.new(30, 25),
		position = scaled(-70, -40),
		height = 20,
	},
	{
		name = "DailyRewards",
		displayName = "Daily Rewards",
		size = Vector2.new(20, 20),
		position = scaled(-40, -70),
		height = 16,
	},
	{
		name = "LeaderboardHall",
		displayName = "Leaderboard Hall",
		size = Vector2.new(40, 18),
		position = scaled(0, -80),
		height = 18,
	},
	{
		name = "TutorialBuilding",
		displayName = "Tutorial Building",
		size = Vector2.new(20, 20),
		position = scaled(40, -70),
		height = 16,
	},
	{
		name = "StatisticsBuilding",
		displayName = "Statistics Building",
		size = Vector2.new(30, 15),
		position = scaled(70, -40),
		height = 14,
	},
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
