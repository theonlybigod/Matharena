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

-- World position: centered over the lobby's visual midpoint (X=0, Z=0,
-- the same true center the queue portal sits at). Y = 161: manually
-- lowered directly in Studio from the previous 460 (built anchor Y=464)
-- down to a built anchor Y of 165 - reconciled here to the equivalent
-- pre-ground-elevation config value (161 + 4 ground elevation = 165)
-- rather than the source silently disagreeing with the manual move.
SignConfig.POSITION = Vector3.new(0, 161, 0)

-- BillboardGui rewrite (final size pass): the sign used to be a
-- SurfaceGui glued to a giant anchor Part's face, which hit a hard
-- Roblox engine ceiling - 2048 studs is the absolute maximum size for
-- ANY single Part along any axis - silently capping the sign at ~2.05x
-- instead of the requested 3x, no matter what the config said. A
-- BillboardGui's Size is in studs directly, completely independent of
-- any Part's physical size limit, so there's no engine ceiling to hit
-- here at all.
--
-- Text-size pass: since TitleLabel uses TextScaled and fills the entire
-- BillboardGui (see Sign.lua), the ONLY way to make the rendered glyphs
-- themselves bigger is to grow the BillboardGui itself by the same
-- factor - there's no separate "text size" knob independent of the
-- container. Per explicit "3x taller and wider" direction, this is 3x
-- the previous BillboardGui size (was 4000x900) on both axes.
SignConfig.BILLBOARD_SIZE = Vector2.new(12000, 2700)

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
-- Brightness kept restrained even though the sign itself is now much
-- bigger - "ensure the larger sign does not become excessively bright or
-- visually harsh". Range increased again to feel proportional to the
-- much larger physical footprint, without raising brightness to match.
SignConfig.GLOW_BRIGHTNESS = 3.2
SignConfig.GLOW_RANGE = 120
SignConfig.PARTICLE_RATE = 6

-- Floating/bobbing motion. Purely visual, so it's driven client-side (see
-- MatharenaSignController.client.lua) rather than tweening the real
-- instance on the server every frame for every client.
SignConfig.BOB_HEIGHT = 4 -- studs of vertical travel above/below the base position
SignConfig.BOB_PERIOD_SECONDS = 6 -- full up-down-up cycle length

return SignConfig
