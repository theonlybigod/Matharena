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

-- Invisible frame the text/light/particles attach to, in studs. Sized
-- larger and with a less-wide aspect ratio than the original (was
-- 56x16, a 3.5:1 wide-and-flat box) specifically so TextScaled has more
-- vertical room to work with - the same word reads noticeably taller
-- without getting any wider or distorted.
SignConfig.PANEL_SIZE = Vector3.new(68, 28, 2)

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

-- The glow lives in the text's own outline plus a soft light/particle
-- accent - not in a background panel, so there's no border/frame reading
-- as a "box" around the word. Uses the palette's CENTRAL_FEATURE shade -
-- the sign is one of the two "hero" landmarks (with the queue portal)
-- meant to read as the map's focal point, per the calmer-lighting pass.
SignConfig.GLOW_COLOR = LightingConfig.CENTRAL_FEATURE
SignConfig.TEXT_STROKE_TRANSPARENCY = 0.15 -- stronger than a plain outline - this IS the sign's glow
SignConfig.GLOW_BRIGHTNESS = 3 -- calmer-lighting pass: was 4 - still the brightest single light in the lobby (it's the map's focal landmark), but pulled back from an excessive hotspot
SignConfig.GLOW_RANGE = 60
SignConfig.PARTICLE_RATE = 4 -- restrained; a soft accent, not a distraction from the text

-- Floating/bobbing motion. Purely visual, so it's driven client-side (see
-- MatharenaSignController.client.lua) rather than tweening the real
-- instance on the server every frame for every client.
SignConfig.BOB_HEIGHT = 4 -- studs of vertical travel above/below the base position
SignConfig.BOB_PERIOD_SECONDS = 6 -- full up-down-up cycle length

return SignConfig
