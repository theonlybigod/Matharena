--[[
	SignConfig.lua

	Shared configuration for the floating "MATHARENA" landmark sign above
	the lobby. Both the server-side builder (ServerScriptService/
	LobbyBuilder/Sign.lua) and the client-side floating-motion controller
	(StarterPlayerScripts/MatharenaSignController.client.lua) read from
	here, so the sign's size, position, colors, typography, and bob motion
	can all be retuned from a single place without touching either script.

	Redesigned (sign cleanup pass): the sign is no longer a solid colored
	panel framed by metal trim bars. It's now borderless - just glowing
	typography and a soft light/particle accent, floating above the lobby.
	This is the single, primary MATHARENA sign; do not add a second one
	(see Sign.lua's header for why one previously had to be removed).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)

local SignConfig = {}

-- Stable name used to locate the sign later (client controller, and any
-- future system that needs to find/modify it). Also set as a bool
-- Attribute on the model itself for lookup by attribute instead of name.
SignConfig.SIGN_NAME = "MatharenaSign"

-- World position: centered over the lobby's visual midpoint. The building
-- row sits on the -Z side (roughly Z -40 to -80) and the spawn/entrance
-- row sits on the +Z side (Z 90), with the queue portal plaza at the
-- origin in between - so X=0, Z=0 is the lobby's true visual center.
-- Y is well above the tallest building (20 studs) plus its roofline trim,
-- so no lobby structure can obscure the sign from anywhere in the plaza.
SignConfig.POSITION = Vector3.new(0, 85, 0)

-- Invisible frame the text/light/particles attach to, in studs. Message
-- 23: grown further (68x28 -> 100x42, roughly 1.5x) per explicit "make
-- the text bigger significantly" direction - since TitleLabel below uses
-- TextScaled (always fills the panel), growing the panel IS how the
-- lettering itself gets bigger. Verified the sign's bottom edge (POSITION.Y
-- - PANEL_SIZE.Y/2 = 64, or 68 once the +4 ground-elevation bulk
-- translation is applied) still clears the tallest building (Shop, ~32
-- studs including roofline trim and the ground raise) with a comfortable
-- margin.
SignConfig.PANEL_SIZE = Vector3.new(100, 42, 2)

SignConfig.TEXT = "MATHARENA"
SignConfig.TEXT_COLOR = Color3.fromRGB(255, 255, 255)
-- Oswald: a tall, condensed, clean sans-serif - increases the lettering's
-- vertical presence (the actual ask) without widening it, and reads as
-- modern/futuristic rather than "boxy handwritten neon".
SignConfig.TEXT_FONT = Enum.Font.Oswald
-- A light top-to-bottom sheen on the lettering itself (a "shiny" pass
-- without a physical border/panel around it).
SignConfig.TEXT_SHIMMER_COLORS = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(210, 235, 255),
}

-- Small subtitle beneath the main word, in a lighter/smaller weight -
-- "significantly more impressive/polished" without adding visual clutter
-- to the main title or making it harder to recognize at a glance.
SignConfig.SUBTITLE_TEXT = "COMPETITIVE MATH ARENA"
SignConfig.SUBTITLE_HEIGHT_FRACTION = 0.16 -- fraction of PANEL_SIZE.Y reserved for the subtitle strip

-- Holographic ring (a flattened, mostly-transparent Cylinder disc)
-- floating just behind the text, slowly rotating (client-side, see
-- MatharenaSignController.client.lua) - the single biggest "10x cooler"
-- lever for cheap: one extra part, no per-frame server cost, reads
-- immediately as "futuristic hologram" rather than "floating word".
SignConfig.RING_DIAMETER = 56
SignConfig.RING_THICKNESS = 0.6
SignConfig.RING_ROTATION_PERIOD_SECONDS = 14

-- Upward energy beams connecting the sign down toward the ground/portal
-- area below it - reinforces "this is a deliberate floating installation",
-- not just text that happens to hover. Kept at a radius clear of the
-- queue portal's own footprint (QueuePortal is a 12x12 structure at the
-- same X/Z origin) so the beams read as surrounding it, not clipping
-- through its pillars.
SignConfig.BEAM_COUNT = 4
SignConfig.BEAM_RADIUS = 15
SignConfig.BEAM_THICKNESS = 0.5

-- The glow lives in the text's own outline plus a soft light/particle
-- accent - not in a background panel, so there's no border/frame reading
-- as a "box" around the word. Uses the palette's CENTRAL_FEATURE shade -
-- the sign is one of the two "hero" landmarks (with the queue portal)
-- meant to read as the map's focal point, per the calmer-lighting pass.
SignConfig.GLOW_COLOR = LightingConfig.CENTRAL_FEATURE
SignConfig.TEXT_STROKE_TRANSPARENCY = 0.15 -- stronger than a plain outline - this IS the sign's glow
-- "10x cooler" pass: brightness/range/particle rate all nudged up from
-- the calmer-lighting pass's values, since the sign is now a genuinely
-- bigger, more elaborate installation (ring + beams + subtitle) that can
-- carry a slightly stronger glow without looking like a hotspot - still
-- restrained relative to a full-brightness neon sign, and still just one
-- PointLight + one ParticleEmitter, so the performance cost is unchanged.
SignConfig.GLOW_BRIGHTNESS = 4
SignConfig.GLOW_RANGE = 70
SignConfig.PARTICLE_RATE = 6

-- Floating/bobbing motion. Purely visual, so it's driven client-side (see
-- MatharenaSignController.client.lua) rather than tweening the real
-- instance on the server every frame for every client.
SignConfig.BOB_HEIGHT = 4 -- studs of vertical travel above/below the base position
SignConfig.BOB_PERIOD_SECONDS = 6 -- full up-down-up cycle length

return SignConfig
