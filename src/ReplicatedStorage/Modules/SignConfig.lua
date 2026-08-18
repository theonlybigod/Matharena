--[[
	SignConfig.lua

	Shared configuration for the floating "MATHARENA" landmark sign above
	the lobby (Message 2 addition). Both the server-side builder
	(ServerScriptService/LobbyBuilder/Sign.lua) and the client-side
	floating-motion controller (StarterPlayerScripts/MatharenaSignController
	.client.lua) read from here, so the sign's size, position, colors, and
	bob motion can all be retuned from a single place without touching
	either script.

	Supersedes the small "MatharenaLogo" that used to be built in
	Decorations.lua - see the note in Decorations.lua for why.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)

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

-- Panel size, in studs. Notably larger than a normal decorative building
-- sign (compare Buildings.lua's addSign, which sizes its label to the
-- building's own face) so this reads as the lobby's major landmark.
SignConfig.PANEL_SIZE = Vector3.new(56, 16, 3)

SignConfig.PANEL_COLOR = Config.BRAND_NEON_COLOR
SignConfig.TRIM_COLOR = Color3.fromRGB(235, 235, 245) -- bright metal, for the shiny trim bars

SignConfig.TEXT = "MATHARENA"
SignConfig.TEXT_COLOR = Color3.fromRGB(255, 255, 255)
SignConfig.TEXT_FONT = Enum.Font.GothamBlack
SignConfig.TEXT_STROKE_TRANSPARENCY = 0.5 -- subtle outline so the bold text pops against the neon panel

-- Glow. Kept to a single light + a low-rate emitter per side so the sign
-- stays readable rather than busy.
SignConfig.GLOW_BRIGHTNESS = 3
SignConfig.GLOW_RANGE = 60
SignConfig.PARTICLE_RATE = 4

-- Floating/bobbing motion. Purely visual, so it's driven client-side (see
-- MatharenaSignController.client.lua) rather than tweening the real
-- instance on the server every frame for every client.
SignConfig.BOB_HEIGHT = 4 -- studs of vertical travel above/below the base position
SignConfig.BOB_PERIOD_SECONDS = 6 -- full up-down-up cycle length

return SignConfig
