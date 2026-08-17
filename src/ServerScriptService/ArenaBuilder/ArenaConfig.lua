--[[
	ArenaConfig.lua

	Centralized dimensions/positions for the procedurally generated
	competition arena. Coordinate convention:
		Arena is centered on the origin. Center stage sits at (0, y, 0).
		Contestant platforms ring the stage. Spectator seating rings the
		platforms, out toward the arena's outer edge.

	"28 studs spacing" for platforms is interpreted as center-to-center arc
	spacing between adjacent platforms (consistent with how LobbyConfig
	treats tree spacing) — the platform ring radius is derived from this in
	ArenaBuilder, not hardcoded, so changing PLATFORM_COUNT or
	PLATFORM_SPACING here automatically produces a correct new radius.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)

local ArenaConfig = {}

ArenaConfig.ARENA_RADIUS = 100
ArenaConfig.FLOOR_THICKNESS = 2
ArenaConfig.FLOOR_COLOR = Color3.fromRGB(12, 12, 14) -- black marble
ArenaConfig.NEON_COLOR = Config.BRAND_NEON_COLOR -- blue neon (shared brand color)

-- Concentric decorative neon circles on the arena floor.
ArenaConfig.FLOOR_RING_RADII = { 30, 60, 90 }
ArenaConfig.FLOOR_RING_SEGMENTS = 64

ArenaConfig.PLATFORM_COUNT = 12
ArenaConfig.PLATFORM_DIAMETER = 10
ArenaConfig.PLATFORM_HEIGHT = 3
ArenaConfig.PLATFORM_SPACING = 28 -- center-to-center arc spacing between adjacent platforms
ArenaConfig.PLATFORM_ALIVE_COLOR = Color3.fromRGB(50, 55, 65) -- Base color while a contestant is still in the round

ArenaConfig.CENTER_STAGE_DIAMETER = 20
ArenaConfig.CENTER_STAGE_HEIGHT = 1.5

ArenaConfig.QUESTION_SCREEN_SIZE = Vector2.new(40, 20) -- width x height
ArenaConfig.QUESTION_SCREEN_HEIGHT_ABOVE_STAGE = 15 -- studs above the stage surface

ArenaConfig.WINNER_AREA_DIAMETER = 8

ArenaConfig.HOST_PODIUM_OFFSET = Vector3.new(0, 0, -6) -- offset from stage center

-- Spectator seating: concentric rings beyond the platform ring.
ArenaConfig.SPECTATOR_RING_OFFSETS = { 15, 28 } -- studs beyond the platform ring radius
ArenaConfig.SPECTATOR_SEAT_SPACING = 10

-- Rim light rigs (spotlights + moving beams) mounted above the arena.
ArenaConfig.RIM_LIGHT_COUNT = 8
ArenaConfig.RIM_LIGHT_HEIGHT = 40
ArenaConfig.MOVING_BEAM_COUNT = 4
ArenaConfig.MOVING_BEAM_HEIGHT = 45

return ArenaConfig
