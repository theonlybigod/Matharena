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

-- ===== Global dusk/sunset environment (LobbyLighting.lua) =====
-- "The background lighting/sky not daytime, but more of a dusk/sunset
-- colour... nice sunset atmosphere, but do not make it dark... map should
-- remain easy to see". Replaces the previous sunrise theme (ClockTime
-- 6.5, cool golden-morning tones) with a genuine dusk/sunset - a later
-- ClockTime for a warm orange/pink horizon, while keeping every actual
-- brightness/fill lever at least as strong as the brightest prior pass so
-- "dusk" reads as warm-colored, not dim. This is the ONLY tier
-- responsible for baseline visibility - a player standing far from every
-- lamp, building, and landmark must still clearly read the ground/paths/
-- other players by these values alone. The blue neon accent palette above
-- is intentionally left untouched - "neon elements still looking good" -
-- only the GLOBAL environment tier changes; local/architectural/
-- decorative accents keep their own colors.

-- Daytime sky (14.0 = early afternoon) - "I just want it to be like
-- normal" - reverted from the dusk/sunset ClockTime experiments back to
-- a standard bright daytime hour.
LightingConfig.DUSK_CLOCK_TIME = 14.0

-- Ambient/Outdoor ambient: NEUTRAL white/grey, not color-tinted at all.
-- Two prior passes tried to convey "dusk/sunset" through a tinted Ambient
-- color (first too saturated/red, then overcorrected into a flat washed-
-- out grey) - since Ambient colors literally everything in the scene at
-- once, any tint strong enough to read as "a mood" ends up reading as
-- "the whole map is that color" instead. Reverting to genuine neutral so
-- every building/ground/object shows its own real color correctly -
-- "I just want it to be like normal". ClockTime below still keeps things
-- at a later hour for a slightly warmer sun angle, but the FILL light
-- itself is neutral now, not tinted.
LightingConfig.AMBIENT_COLOR = Color3.fromRGB(140, 140, 140)
LightingConfig.OUTDOOR_AMBIENT_COLOR = Color3.fromRGB(140, 140, 140)
LightingConfig.DUSK_BRIGHTNESS = 1.8

-- Exposure: a small positive compensation so midtones/shadows lift
-- slightly without raising Brightness (which affects direct light) or
-- Ambient (which affects fill color) - a third, independent lever for
-- "clearly playable".
--
-- Glow/overexposure fix: Brightness and ExposureCompensation were both
-- tuned specifically for the earlier low-angle SUNRISE theme (ClockTime
-- 6.5), where the sun sits near the horizon and needs real compensation
-- to stay readable. Once ClockTime moved to 14.0 (midday - the sun is
-- already close to overhead and naturally bright on its own), that same
-- boost became redundant on top of already-strong natural light,
-- overexposing the whole scene into a washed-out/"glowing" look. Both
-- values eased back down to levels appropriate for a bright midday sun
-- rather than a dim sunrise - still clearly bright/"not dark", just not
-- double-compensated for a sun angle that no longer applies.
LightingConfig.EXPOSURE_COMPENSATION = 0.15

-- Fog: DISABLED.
--
-- History worth keeping, because this setting has been through three
-- states and each one was wrong in a different way:
--
--   1. FogStart/FogEnd 0/650, neutral grey. Grey blending began at ZERO
--      distance, washing wide shots out and flattening contrast; and
--      anything past FogEnd became a solid grey silhouette, so the
--      neighbouring maps showed up as flat grey slabs against a blue sky.
--   2. Sky-matched blue at 550/1200. Much better - the local map stayed
--      crisp and the neighbours softened - but at EYE LEVEL they still
--      read as pale vertical shapes rather than dissolving, because
--      ground-level sightlines are far longer than the aerial view that
--      the values were judged from.
--   3. Disabled (current). Chosen deliberately for maximum clarity: no
--      distance wash of any kind, so the map reads at full contrast and
--      full colour from every camera height.
--
-- KNOWN TRADE-OFF: with no fog, distant geometry renders in its true
-- colour, so the neighbouring maps (Lava's rock walls ~560 studs out,
-- Space's dome ~1100) are visible on the horizon as dark shapes rather
-- than being hidden. That is accepted - clarity of the playable map was
-- judged more important than concealing the neighbours. Atmosphere below
-- still provides near/mid-range depth.
--
-- If the neighbours ever need hiding again, do NOT reach for grey fog -
-- match FogColor to the horizon sky instead (state 2 above), which is the
-- only version that blended rather than silhouetted.
LightingConfig.FOG_COLOR = Color3.fromRGB(150, 190, 220) -- sky-matched, retained for whenever fog is re-enabled
LightingConfig.FOG_START = 100000
LightingConfig.FOG_END = 100000 -- fog off

-- Bloom: restrained on purpose - enough to make neon read as "glowing"
-- rather than "flat colored plastic", without blowing out into glare.
LightingConfig.BLOOM_INTENSITY = 0.35
LightingConfig.BLOOM_THRESHOLD = 1.6 -- higher threshold = only genuinely bright/neon surfaces bloom, not general geometry
LightingConfig.BLOOM_SIZE = 20

-- ColorCorrection: a restrained grade, no longer fully neutral.
--
-- Measured surface luminance in the Futuristic lobby: ground 0.707,
-- building walls 0.219, roof caps 0.188, interior floors 0.126. That is a
-- very wide spread, and with a completely neutral grade (Contrast,
-- Saturation and Brightness all 0) the buildings read as flat near-black
-- silhouettes against a bright ground, losing their trim and panel
-- detail entirely at normal viewing distance.
--
-- The fix is deliberately NOT more contrast - that would crush the dark
-- end further and make the buildings worse. Instead:
--   Brightness  a small positive lift, which raises the dark end much
--               more perceptually than the already-bright ground, so
--               building detail becomes readable ("areas are not
--               excessively dark") without blowing out the plaza. Eased
--               from an initial 0.03 after review - the plaza ground is
--               already luminance 0.707 and was dominating the frame -
--               but deliberately kept above 0, since the fully neutral
--               original was too dark on the buildings.
--   Saturation  a modest bump so the blue neon palette and the green
--               foliage read as colour rather than tinted grey. This is
--               the single biggest "looks" win available at zero
--               structural cost.
--   Contrast    left at 0. The scene's dynamic range is already wide;
--               adding contrast only deepens the silhouette problem.
--
-- All three are intentionally small. Anything stronger starts to look
-- like a filter rather than a grade.
LightingConfig.COLOR_CORRECTION_CONTRAST = 0
LightingConfig.COLOR_CORRECTION_SATURATION = 0.12
LightingConfig.COLOR_CORRECTION_BRIGHTNESS = 0.02
LightingConfig.COLOR_CORRECTION_TINT_COLOR = Color3.fromRGB(255, 255, 255) -- neutral - no color tint at all

-- ===== Atmosphere / DepthOfField / SunRays =====
--
-- These three were previously configured ONLY as $properties nodes in
-- default.project.json, with no runtime owner. That made them the most
-- fragile settings in the project: Rojo re-reads default.project.json
-- only when the `rojo serve` PROCESS restarts (reconnecting the Studio
-- plugin is NOT enough), so edits to them could sit on disk looking
-- applied while the live place kept the old values indefinitely.
--
-- They are now owned by LobbyLighting.Apply() exactly like Bloom and
-- ColorCorrection above, so they are re-asserted on every single server
-- start and are editable from one place with normal hot-sync behaviour.

-- Atmospheric depth. Density gives distance falloff; a slightly blue-grey
-- Color/Decay keeps far geometry reading as "receding into air" rather
-- than "fading to flat grey". Haze and Glare are deliberately SMALL: they
-- add depth cues without the milky wash that heavier values produce,
-- which would directly work against map readability.
-- Density is kept modest because legacy fog (above) handles long-range
-- blending; Atmosphere here is only providing near/mid-range depth, and
-- raising it further just hazes the local map without helping distance.
LightingConfig.ATMOSPHERE_DENSITY = 0.28
LightingConfig.ATMOSPHERE_OFFSET = 0.25
LightingConfig.ATMOSPHERE_COLOR = Color3.new(0.78, 0.80, 0.85)
LightingConfig.ATMOSPHERE_DECAY = Color3.new(0.55, 0.60, 0.70)
LightingConfig.ATMOSPHERE_GLARE = 0.05
LightingConfig.ATMOSPHERE_HAZE = 0.15

-- Depth of field, retuned for READABILITY rather than cinematics.
--
-- The previous values were FocusDistance 0.05, InFocusRadius 30,
-- NearIntensity 0.75, FarIntensity 0.1. Working the arithmetic through:
-- the in-focus band ended at 30.05 studs, so EVERYTHING past 30 studs -
-- i.e. essentially the whole map from any normal camera - was being
-- blurred, while NearIntensity 0.75 applied only closer than 0 studs and
-- so never fired at all.
--
-- Now the in-focus band reaches 90 studs (buildings, signs and other
-- players stay crisp at normal gameplay distance), far blur is halved to
-- a hint of aerial perspective, and the dead near-blur is set to 0.
LightingConfig.DOF_FOCUS_DISTANCE = 0.05
LightingConfig.DOF_IN_FOCUS_RADIUS = 90
LightingConfig.DOF_FAR_INTENSITY = 0.05
LightingConfig.DOF_NEAR_INTENSITY = 0

-- Sun rays: barely-there. Enough to catch the sun angle, far too weak to
-- bloom out the sky or compete with the neon palette.
LightingConfig.SUN_RAYS_INTENSITY = 0.01
LightingConfig.SUN_RAYS_SPREAD = 0.1

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
