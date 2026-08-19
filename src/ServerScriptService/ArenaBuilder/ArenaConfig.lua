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

-- Message 21: expanded ~30% ("noticeably more space... major
-- centerpiece") - every other arena dimension below that's expressed as
-- an offset/fraction of ARENA_RADIUS scales automatically with it
-- (RimLights/MovingBeams in ArenaDecorations.lua derive their radius
-- directly from this constant); PLATFORM_SPACING/FLOOR_RING_RADII/
-- SPECTATOR_RING_OFFSETS below are scaled by the same ~1.3x factor
-- explicitly so the whole composition grows together rather than
-- leaving platforms/rings clustered near the center of a much bigger
-- floor.
ArenaConfig.ARENA_RADIUS = 130
ArenaConfig.FLOOR_THICKNESS = 2
ArenaConfig.FLOOR_COLOR = Color3.fromRGB(12, 12, 14) -- black marble
ArenaConfig.NEON_COLOR = Config.BRAND_NEON_COLOR -- blue neon (shared brand color)

-- Concentric decorative neon circles on the arena floor.
ArenaConfig.FLOOR_RING_RADII = { 39, 78, 117 }
ArenaConfig.FLOOR_RING_SEGMENTS = 64
-- Message 21 fix (section 6): these ring segments previously sat with
-- their bottom face at EXACTLY the same Y as the floor's top face (both
-- at Y=0) - a textbook z-fighting setup, the same class of bug already
-- fixed once before in LobbyGround/FloorTrim. This is a genuine,
-- deliberate nonzero gap so the neon rings read as clean trim sitting
-- just above the floor rather than glitching against it - the floor
-- itself (one Marble-material disc, unchanged) remains the single
-- consistent surface underneath.
ArenaConfig.FLOOR_RING_HEIGHT_ABOVE_FLOOR = 0.08

ArenaConfig.PLATFORM_COUNT = 12
ArenaConfig.PLATFORM_DIAMETER = 10
ArenaConfig.PLATFORM_HEIGHT = 3
ArenaConfig.PLATFORM_SPACING = 36 -- center-to-center arc spacing between adjacent platforms
ArenaConfig.PLATFORM_ALIVE_COLOR = Color3.fromRGB(50, 55, 65) -- Base color while a contestant is still in the round

ArenaConfig.CENTER_STAGE_DIAMETER = 26
ArenaConfig.CENTER_STAGE_HEIGHT = 1.5

-- Message 21: "huge game-show-style question display" - up from 40x20.
ArenaConfig.QUESTION_SCREEN_SIZE = Vector2.new(64, 32) -- width x height
ArenaConfig.QUESTION_SCREEN_HEIGHT_ABOVE_STAGE = 19 -- studs above the stage surface

ArenaConfig.WINNER_AREA_DIAMETER = 10

ArenaConfig.HOST_PODIUM_OFFSET = Vector3.new(0, 0, -6) -- offset from stage center

-- Spectator seating: concentric rings beyond the platform ring.
ArenaConfig.SPECTATOR_RING_OFFSETS = { 20, 36 } -- studs beyond the platform ring radius
ArenaConfig.SPECTATOR_SEAT_SPACING = 10

-- Rim light rigs (spotlights + moving beams) mounted above the arena.
ArenaConfig.RIM_LIGHT_COUNT = 8
ArenaConfig.RIM_LIGHT_HEIGHT = 40
ArenaConfig.MOVING_BEAM_COUNT = 4
ArenaConfig.MOVING_BEAM_HEIGHT = 45

return ArenaConfig
