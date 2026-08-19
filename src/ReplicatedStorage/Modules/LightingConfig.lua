--[[
	LightingConfig.lua

	Single shared source of truth for the lobby's lighting: both the
	varied blue accent palette used across every construction module, and
	the tunable GLOBAL environment values LobbyLighting.Apply() uses.

	Three-level lighting hierarchy (Message 2's dusk-environment
	refinement, layered on top of the earlier "calmer neon" pass):
		1. GLOBAL ENVIRONMENT (this module's "Global dusk environment"
		   section + LobbyLighting.lua) - Ambient/OutdoorAmbient/
		   Brightness/Exposure/Fog/Bloom/ColorCorrection on the Lighting
		   service. Provides baseline visibility EVERYWHERE, independent
		   of any map object - a player standing far from every lamp and
		   every building still sees by this alone.
		2. AREA/ARCHITECTURAL (BuildingInteriors.lua's ceiling lights/
		   beacons, LeaderboardBoards.lua's board glow) - supplemental
		   illumination around buildings/leaderboards/queue area, using
		   this module's shared ACCENT_LIGHT_* reference so no single
		   fixture has to compensate for weak global lighting.
		3. LOCAL STREET/DECORATIVE (StreetLamps.lua, seating accents,
		   corner fill lights) - localized pools of light and atmosphere,
		   again referencing ACCENT_LIGHT_*/CORNER_FILL_* rather than
		   picking their own numbers.
	No level should have to overcompensate for another: baseline
	visibility is level 1's job alone, so levels 2-3 stay restrained.

	Lives in ReplicatedStorage/Modules (not beside LobbyConfig.lua in
	ServerScriptService/LobbyBuilder, where most other lobby-only config
	lives) specifically because SignConfig.lua - itself in ReplicatedStorage
	since it's required by both server (Sign.lua) and client
	(MatharenaSignController.client.lua) code - needs the CENTRAL_FEATURE
	shade below. A ReplicatedStorage module can never require anything
	from ServerScriptService (the client half of that require would fail
	outright, since clients can't see ServerScriptService at all), so this
	module has to live wherever its most restrictive consumer can reach it.

	Why a palette instead of one flat brand color: every construction
	module used to reach for the exact same Config.BRAND_NEON_COLOR for
	everything (buildings, ground trim, lamps, decorations, the sign) -
	functional, but flat. The named shades below are all still clearly
	"the same blue family" (cohesive identity, no unrelated hues), just
	varied enough in lightness/saturation to give the environment real
	depth and to let the CENTRAL_FEATURE shade read as a genuine focal
	point rather than every neon surface competing at the same intensity.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)

local LightingConfig = {}

-- ===== Blue accent palette (all one cohesive family, varied by purpose) =====

-- Primary architectural accents (used as the general-purpose brand blue
-- wherever nothing more specific applies).
LightingConfig.PRIMARY_ARCHITECTURAL = Color3.fromRGB(70, 150, 230)

-- Building trim: roofline bands, canopy/doorway trim, window frames,
-- interior accent panels - a hair cooler/dimmer than PRIMARY so building
-- surfaces read as "accented", not "glowing as bright as the sign".
LightingConfig.BUILDING_TRIM = Color3.fromRGB(80, 160, 225)

-- Ground/path accents: floor perimeter trim - lighter and slightly more
-- cyan so paths read as "lit ground", distinct from vertical surfaces.
LightingConfig.GROUND_PATH = Color3.fromRGB(110, 195, 245)

-- Street lamp decorative trim (the accent ring/cap, NOT the actual light
-- bulb color below) - close to BUILDING_TRIM but kept as its own named
-- value so lamps can be retuned independently of buildings.
LightingConfig.STREET_LAMP_ACCENT = Color3.fromRGB(85, 165, 230)

-- Street lamp functional glow (the actual PointLight + bulb color) - a
-- soft, near-white, slightly cool blue. Deliberately the lightest/most
-- desaturated shade in the palette: this is meant to read as believable
-- illumination, not a saturated neon decoration.
LightingConfig.STREET_LAMP_GLOW = Color3.fromRGB(210, 225, 250)

-- Decorative elements: seating accents, small trim details - a touch
-- warmer/more saturated than BUILDING_TRIM so decor doesn't disappear
-- against the buildings behind it.
LightingConfig.DECORATIVE = Color3.fromRGB(95, 175, 240)

-- Central map features: the queue portal and the floating Matharena sign
-- - the most saturated/brightest shade in the family, used sparingly so
-- these two landmarks read as the map's focal point ("a subtle brighter
-- focal area around the center") without anything else competing with them.
LightingConfig.CENTRAL_FEATURE = Config.BRAND_NEON_COLOR

-- ===== Global dusk environment (LobbyLighting.lua) =====
-- "Early evening / soft dusk / futuristic nighttime - calm, atmospheric,
-- clearly playable" (Message 2 dusk-environment refinement). This is the
-- ONLY tier responsible for baseline visibility - a player standing far
-- from every lamp, building, and landmark must still clearly read the
-- ground/paths/other players by these values alone.

-- A dusk sky (not full night) - late-sunset sky tones/sun angle rather
-- than the near-black sky ClockTime=21 (9pm) would give. Ambient/
-- OutdoorAmbient below are fixed overrides, so this mainly shapes the
-- visual sky/sun, not the actual fill brightness.
LightingConfig.DUSK_CLOCK_TIME = 19.25

-- Ambient/Outdoor ambient: a restrained blue dusk tint, bright enough on
-- its own (independent of any lamp) that ground/buildings/players stay
-- clearly readable in open areas between fixtures - "do not compensate
-- for poor global visibility by making every street lamp excessively
-- bright" means this has to carry that weight itself.
--
-- Message 22, section 2 ("make the entire map lighter... bright, welcoming,
-- easy to see"): pushed meaningfully brighter across all three
-- independent levers (Ambient color, Brightness, Exposure) rather than
-- just one, since each affects a different part of the render (fill
-- color, direct light, midtone lift respectively) - a real, noticeable
-- jump without any single value doing all the work alone (which would
-- risk washing out the color identity). Saturation/contrast in
-- ColorCorrection below are eased further too, for the same reason.
LightingConfig.AMBIENT_COLOR = Color3.fromRGB(110, 118, 145)
LightingConfig.OUTDOOR_AMBIENT_COLOR = Color3.fromRGB(110, 118, 145)
LightingConfig.DUSK_BRIGHTNESS = 2.6 -- was 1.75

-- Exposure: a small positive compensation so midtones/shadows lift
-- slightly without raising Brightness (which affects direct light) or
-- Ambient (which affects fill color) - a third, independent lever for
-- "clearly playable" without changing the dusk color mood.
LightingConfig.EXPOSURE_COMPENSATION = 0.4 -- was 0.15

LightingConfig.FOG_COLOR = Color3.fromRGB(34, 38, 52) -- close to Ambient, so fog reads as atmospheric haze, not a mismatched color
LightingConfig.FOG_END = 650 -- generous falloff distance - "subtle atmospheric depth without heavy fog obscuring distant objects"

-- Bloom: restrained on purpose - enough to make neon read as "glowing"
-- rather than "flat colored plastic", without blowing out into glare.
LightingConfig.BLOOM_INTENSITY = 0.35
LightingConfig.BLOOM_THRESHOLD = 1.6 -- higher threshold = only genuinely bright/neon surfaces bloom, not general geometry
LightingConfig.BLOOM_SIZE = 20

-- ColorCorrection: a small contrast/saturation ease so the scene reads as
-- "calm/polished" rather than punchy - subtle enough to not flatten the
-- palette above. Message 22: eased slightly further to complement the
-- brighter Ambient/Brightness/Exposure above without looking washed out.
LightingConfig.COLOR_CORRECTION_CONTRAST = -0.08
LightingConfig.COLOR_CORRECTION_SATURATION = -0.03
LightingConfig.COLOR_CORRECTION_TINT_COLOR = Color3.fromRGB(245, 248, 255) -- a hair cool, reinforcing the blue identity

-- Reference brightness/range for the smaller decorative PointLights
-- scattered around the lobby (building beacons, ceiling lights, etc.) -
-- "avoid strong lighting hotspots directly around individual neon
-- objects" means these stay modest; local fixtures should lean on this
-- shared reference rather than each picking its own number. Message 22:
-- nudged up alongside the global boost so building interiors specifically
-- (which rely heavily on these fixtures, having no windows to the dusk
-- sky) don't feel comparatively darker than the now-brighter outdoors.
LightingConfig.ACCENT_LIGHT_BRIGHTNESS = 1.6
LightingConfig.ACCENT_LIGHT_RANGE = 20

-- Corner fill lights (see Decorations.lua): small supplemental
-- PointLights at the four corners of the square lobby floor, specifically
-- to cover the corners a perimeter ring of street lamps naturally leaves
-- dimmer than the mid-edge points - "full-map lighting coverage" without
-- just cranking every existing light brighter.
LightingConfig.CORNER_FILL_BRIGHTNESS = 1
LightingConfig.CORNER_FILL_RANGE = 45

return LightingConfig
