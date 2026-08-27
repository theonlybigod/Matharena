--[[
	ArenaConfig.lua

	Centralized dimensions/positions for the procedurally generated
	competition arena. Coordinate convention:
		Every construction module builds the arena around its own LOCAL
		origin: center stage at (0, y, 0), contestant platforms ringing the
		stage, spectator seating ringing the platforms out toward the outer
		edge. ArenaBuilder.Build() then translates the whole finished result
		to ORIGIN below, exactly the way LobbyBuilder translates each map to
		its MapsConfig origin.

	"28 studs spacing" for platforms is interpreted as center-to-center arc
	spacing between adjacent platforms (consistent with how LobbyConfig
	treats tree spacing) — the platform ring radius is derived from this in
	ArenaBuilder, not hardcoded, so changing PLATFORM_COUNT or
	PLATFORM_SPACING here automatically produces a correct new radius.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)

local ArenaConfig = {}

--[[
	World-space position of the finished arena.

	CURRENTLY (0, 0, 0) - the same origin as the Futuristic lobby, so the
	arena sits inside the lobby and is visible and walkable there outside a
	match. That is deliberate: the arena's centre stage is the lobby's
	centrepiece. In particular CenterStage's QuestionScreen - an 80 x 40
	board reading "MATHARENA" on both faces while idle, and showing live
	questions during a match - stands at the middle of the plaza and is
	meant to be seen from the lobby.

	The known cost of sharing an origin: the arena's 234 x 23.5 x 234
	volume encloses ~419 Lobby parts, and ~160 collidable arena parts
	(seats, podium tiers, stage bases) sit at walking height around the
	plaza. That is accepted, not overlooked.

	The transform mechanism below is kept even at zero offset so the arena
	CAN be relocated later by changing this one constant - nothing reads
	arena coordinates literally. MatchSystem places contestants via
	Teleporter, which finds platforms by the "ContestantPlatform"
	CollectionService tag and pivots to each platform's live Position, and
	returns players via Workspace.Lobby.Spawns. Both follow the arena
	wherever it is. If it is ever moved, prefer the free diagonal quadrant
	(1050, 0, 1050): MapsConfig already spends the four cardinals on the
	non-default maps (Lava +X, UnderTheSea -X, Space -Z, IceAge +Z) at 1050
	studs each, and that corner is clear of all of them.
]]
ArenaConfig.ORIGIN = Vector3.new(0, 0, 0)

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
ArenaConfig.FLOOR_MATERIAL = Enum.Material.Marble -- default (Hub) floor material; ArenaBuilder.BuildForMap overrides per-theme
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
-- Podium tier colors (Platforms.lua's PodiumTier1/PodiumTier2 discs). Both
-- default to the Hub's original fixed values; ArenaBuilder.BuildForMap
-- overrides these per-theme, same mechanism as FLOOR_COLOR/NEON_COLOR above.
ArenaConfig.PODIUM_TIER1_COLOR = Color3.fromRGB(42, 45, 52)
ArenaConfig.PODIUM_TIER2_COLOR = Color3.fromRGB(18, 18, 22)

ArenaConfig.CENTER_STAGE_DIAMETER = 26
ArenaConfig.CENTER_STAGE_HEIGHT = 1.5

-- Message 22, section 5: "much bigger" again - up from 64x32 (verified
-- via Python that 80 studs wide still leaves a comfortable ~30-stud gap
-- to the nearest contestant platform, given PLATFORM_SPACING/
-- PLATFORM_COUNT below put the platform ring at radius ~69.5).
ArenaConfig.QUESTION_SCREEN_SIZE = Vector2.new(80, 40) -- width x height
ArenaConfig.QUESTION_SCREEN_HEIGHT_ABOVE_STAGE = 21 -- studs above the stage surface

ArenaConfig.WINNER_AREA_DIAMETER = 10

-- Spectator seating: concentric rings beyond the platform ring.
ArenaConfig.SPECTATOR_RING_OFFSETS = { 20, 36 } -- studs beyond the platform ring radius
ArenaConfig.SPECTATOR_SEAT_SPACING = 10

-- Rim light rigs (spotlights + moving beams) mounted above the arena.
ArenaConfig.RIM_LIGHT_COUNT = 8
ArenaConfig.RIM_LIGHT_HEIGHT = 40
ArenaConfig.MOVING_BEAM_COUNT = 4
ArenaConfig.MOVING_BEAM_HEIGHT = 45

return ArenaConfig
