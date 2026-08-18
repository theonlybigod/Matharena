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
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)

local LobbyConfig = {}

LobbyConfig.LOBBY_SIZE = 220
LobbyConfig.FLOOR_THICKNESS = 2

LobbyConfig.FLOOR_COLOR = Color3.fromRGB(180, 180, 185) -- smooth concrete
LobbyConfig.NEON_COLOR = Config.BRAND_NEON_COLOR -- blue neon trim (shared brand color)

LobbyConfig.SPAWN_SIZE = Vector2.new(8, 8)
LobbyConfig.SPAWN_POSITIONS = {
	Vector3.new(-30, 0, 90),
	Vector3.new(-10, 0, 90),
	Vector3.new(10, 0, 90),
	Vector3.new(30, 0, 90),
}

LobbyConfig.BUILDINGS = {
	{
		name = "Shop",
		displayName = "Shop",
		size = Vector2.new(30, 25),
		position = Vector3.new(-70, 0, -40),
		height = 20,
	},
	{
		name = "DailyRewards",
		displayName = "Daily Rewards",
		size = Vector2.new(20, 20),
		position = Vector3.new(-40, 0, -70),
		height = 16,
	},
	{
		name = "LeaderboardHall",
		displayName = "Leaderboard Hall",
		size = Vector2.new(40, 18),
		position = Vector3.new(0, 0, -80),
		height = 18,
	},
	{
		name = "TutorialBuilding",
		displayName = "Tutorial Building",
		size = Vector2.new(20, 20),
		position = Vector3.new(40, 0, -70),
		height = 16,
	},
	{
		name = "StatisticsBuilding",
		displayName = "Statistics Building",
		size = Vector2.new(30, 15),
		position = Vector3.new(70, 0, -40),
		height = 14,
	},
}

LobbyConfig.QUEUE_PORTAL_SIZE = Vector2.new(12, 12)
LobbyConfig.QUEUE_PORTAL_POSITION = Vector3.new(0, 0, 0)

LobbyConfig.TREE_SPACING = 25
LobbyConfig.PERIMETER_INSET = 12 -- distance from the lobby edge for the decoration ring

-- Note: the old small floating logo that used LOGO_HEIGHT was removed
-- during the sign cleanup pass (it duplicated LobbyBuilder/Sign.lua's
-- landmark sign). That sign's own position/size now live in
-- ReplicatedStorage/Modules/SignConfig.lua instead, since it's shared
-- with the client-side bob animation, which LobbyConfig isn't.

return LobbyConfig
