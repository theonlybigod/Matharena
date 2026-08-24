--[[
	StreetLampConfig.lua

	Centralized configuration for the lobby's futuristic street lamps
	(Message 2 addition/refinement, replacing the old plain 12-stud pole +
	floating neon ball). All tunable values - height, spacing, light
	range/brightness, materials, and placement jitter - live here so
	StreetLamps.lua (construction) and Decorations.lua (placement) never
	hardcode a lamp dimension or light value directly.

	Lives beside LobbyConfig.lua in ServerScriptService/LobbyBuilder
	rather than ReplicatedStorage - nothing here is needed client-side
	(the lamps have no client-driven animation; see StreetLamps.lua for
	why), matching the existing precedent that pure server-side
	world-building data stays out of ReplicatedStorage.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)
local LobbyTheme = require(script.Parent.LobbyTheme)

local StreetLampConfig = {}

-- Stable type identifier for this lamp design, set as a Model Attribute
-- by StreetLamps.lua. Only one visual variant exists right now - see the
-- module doc in StreetLamps.lua for why a second wasn't invented just to
-- have one - but the identifier is stable so a StreetLampTypeB could be
-- added later without touching any call site.
StreetLampConfig.TYPE_ID = "StreetLampTypeA"

-- Overall proportions. Notably taller than the old generic 12-stud pole
-- so it reads as properly scaled to the 220x220 stud lobby.
StreetLampConfig.POST_HEIGHT = 18
StreetLampConfig.POST_DIAMETER = 0.9

-- The "neck": a single angled arm from the top of the post out to the
-- lamp head - reads as a curved/hooked street-lamp silhouette from a
-- distance (Roblox has no native curved-part primitive, so a single
-- straight angled segment is the practical way to suggest a curve).
StreetLampConfig.NECK_LENGTH = 4.5
StreetLampConfig.NECK_ANGLE_DEGREES = 55 -- tilt from vertical

StreetLampConfig.HEAD_SIZE = Vector3.new(2.2, 1.1, 1.4)
StreetLampConfig.BULB_SIZE = 0.9

local defaultTheme = LobbyTheme.Get()
StreetLampConfig.METAL_COLOR = defaultTheme.lampMetalColor
StreetLampConfig.METAL_MATERIAL = defaultTheme.lampMetalMaterial
StreetLampConfig.ACCENT_COLOR = defaultTheme.lampAccentColor -- small trim/ring accents only
-- Soft, slightly cool white-blue - a believable "modern LED streetlamp"
-- glow, deliberately distinct from the saturated brand-blue neon trims
-- so the light itself doesn't read as a decorative neon sphere. Under the
-- Lava theme this becomes a genuine warm brazier-flame glow instead.
StreetLampConfig.GLOW_COLOR = defaultTheme.lampGlowColor

--[[
	Latches `theme`'s metal/accent/glow colors (and metal material) for
	every subsequent StreetLamps.Build call.
]]
function StreetLampConfig.SetTheme(theme: LobbyTheme.Theme)
	StreetLampConfig.METAL_COLOR = theme.lampMetalColor
	StreetLampConfig.METAL_MATERIAL = theme.lampMetalMaterial
	StreetLampConfig.ACCENT_COLOR = theme.lampAccentColor
	StreetLampConfig.GLOW_COLOR = theme.lampGlowColor
end

-- Kept modest on purpose - "soft illumination", not an oversized glow
-- that would wash out or compete with the floating sign/leaderboards.
-- Calmer-lighting pass: dimmer than the shared ACCENT_LIGHT reference
-- (not just equal to it) since a lamp's glow is meant to be the softest
-- light source in the lobby, not on par with building/landmark beacons.
StreetLampConfig.LIGHT_RANGE = LightingConfig.ACCENT_LIGHT_RANGE
StreetLampConfig.LIGHT_BRIGHTNESS = LightingConfig.ACCENT_LIGHT_BRIGHTNESS * 0.85

-- Placement. Reuses the same radial ring-based layout as trees (see
-- Decorations.lua) at its own radius/spacing, with a small jitter and
-- orientation variation so lamps don't read as a rigid grid, while
-- staying close enough to the walkway ring to read as "along the paths".
StreetLampConfig.RING_SPACING_MULTIPLIER = 2 -- multiplies LobbyConfig.TREE_SPACING
StreetLampConfig.PLACEMENT_JITTER = 4.5 -- studs; smaller than trees' jitter so lamps stay near the path (scaled up from 3 for the larger map)
StreetLampConfig.ORIENTATION_JITTER_DEGREES = 20 -- random yaw variation per lamp
-- Map-scale refinement: scaled up from 10 ("give street lamps appropriate
-- spacing" on the larger map).
StreetLampConfig.AVOID_RADIUS = 15 -- studs kept clear around spawns/buildings/portal/seating/sign

return StreetLampConfig
