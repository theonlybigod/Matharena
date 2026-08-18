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
local Config = require(ReplicatedStorage.Modules.Config)

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

StreetLampConfig.METAL_COLOR = Color3.fromRGB(55, 58, 66)
StreetLampConfig.ACCENT_COLOR = Config.BRAND_NEON_COLOR -- brand blue, used only for small trim accents
-- Soft, slightly cool white-blue - a believable "modern LED streetlamp"
-- glow, deliberately distinct from the saturated brand-blue neon trims
-- so the light itself doesn't read as a decorative neon sphere.
StreetLampConfig.GLOW_COLOR = Color3.fromRGB(210, 225, 255)

-- Kept modest on purpose - "soft illumination", not an oversized glow
-- that would wash out or compete with the floating sign/leaderboards.
StreetLampConfig.LIGHT_RANGE = 16
StreetLampConfig.LIGHT_BRIGHTNESS = 1.3

-- Placement. Reuses the same ring-based layout as trees/benches (see
-- Decorations.lua) at its own inset/spacing, with a small jitter and
-- orientation variation so lamps don't read as a rigid grid, while
-- staying close enough to the walkway ring to read as "along the paths".
StreetLampConfig.RING_INSET_EXTRA = 10 -- added to LobbyConfig.PERIMETER_INSET
StreetLampConfig.RING_SPACING_MULTIPLIER = 2 -- multiplies LobbyConfig.TREE_SPACING
StreetLampConfig.PLACEMENT_JITTER = 3 -- studs; smaller than trees' jitter so lamps stay near the path
StreetLampConfig.ORIENTATION_JITTER_DEGREES = 20 -- random yaw variation per lamp
StreetLampConfig.AVOID_RADIUS = 10 -- studs kept clear around spawns/buildings/portal/benches/sign

return StreetLampConfig
