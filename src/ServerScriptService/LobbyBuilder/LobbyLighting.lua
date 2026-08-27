--[[
	LobbyLighting.lua

	Applies the lobby's atmosphere settings to the (single, global) Lighting
	service. Split out from LobbyBuilder/init.lua (previously a local
	`applyLighting` function) so it can be called unconditionally on every
	server start - independent of whether Workspace.Lobby's geometry was
	just generated or already existed as a source-controlled bake - and so
	its exact values are documented in one place instead of being buried
	inside the build-skip control flow.

	NOTE: Lighting is a single global service shared by the whole place,
	not something scoped to Workspace.Lobby. These settings also apply to
	the Arena until a later prompt gives the Arena its own atmosphere.

	Global dusk environment (Message 2 refinement, on top of the earlier
	calmer-neon pass): every tunable value here comes from LightingConfig.lua
	instead of being hardcoded, and this module also creates (once - see the
	FindFirstChild guards) a restrained BloomEffect + ColorCorrectionEffect.
	The goal is "early evening / soft dusk / futuristic nighttime - calm,
	atmospheric, clearly playable": a dusk ClockTime for the sky, plus fixed
	Ambient/OutdoorAmbient/Brightness/Exposure that guarantee baseline
	visibility EVERYWHERE on their own - independent of every local lamp and
	building light, which only add supplemental atmosphere on top (see
	LightingConfig.lua's three-level hierarchy comment).

	These same values (except the two PostEffects, which are runtime-only
	- see below) are mirrored as $properties on the Lighting node in
	default.project.json, so the lobby's atmosphere is also visible in
	Studio Edit mode immediately after a Rojo sync, without needing Play
	mode to run this module. If you change the values here, update
	default.project.json's Lighting node to match.

	UNITS - IMPORTANT WHEN EDITING default.project.json:
	Rojo parses a Color3 $property as THREE 0-1 FLOATS, not 0-255 bytes.
	Confirmed empirically: the Atmosphere node's Color of [1, 1, 1] arrives
	as 1.0000, not as 1/255.

	The Lighting node used to write its colours in 0-255 (Ambient
	[140,140,140], FogColor [180,180,185], TintColor [255,255,255]). Every
	one of those clamps to PURE WHITE when parsed as 0-1. That never showed
	up in practice only because Apply() below overwrites Ambient/
	OutdoorAmbient/FogColor at runtime from LightingConfig, masking it -
	but it made the "visible in Edit mode straight after a sync" promise
	above false, and a sync into a clean place would have produced a
	blown-out white Lighting setup with no module run yet to correct it.
	Those entries are now written as 0-1 floats (0.549 = 140/255,
	0.7059/0.7255 = 180/185 over 255).

	So: when mirroring a colour from LightingConfig into
	default.project.json, divide each channel by 255.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)

local LobbyLighting = {}

--[[
	Bloom/ColorCorrection are children INSTANCES of Lighting, not simple
	$properties, so (unlike Ambient/Brightness/Fog above) they can't be
	mirrored into default.project.json's static Lighting node - they only
	exist after this function has actually run at least once (Play mode,
	or any Rebuild).

	This actively deduplicates rather than just checking "does one exist":
	if MORE THAN ONE BloomEffect (or ColorCorrectionEffect) is ever present
	under Lighting - e.g. a stray manual Studio edit, or a leftover from an
	older version of this code under a different name - every ENABLED one
	stacks in the renderer simultaneously (this is exactly how the lobby
	once went white/blown-out: two BloomEffects, "Bloom" and
	"MatharenaBloom", coexisting). So this keeps exactly one of each
	(renamed to the canonical "LobbyBloom"/"LobbyColorCorrection") and
	destroys any others, every time it runs - safe to call on every server
	start/Rebuild regardless of what Lighting already contains.
]]
--[[
	Keeps exactly ONE instance of `className` under Lighting, named
	`name`, destroying any duplicates, and returns it (creating it if
	absent).

	This generalises the dedup that previously existed only for Bloom and
	ColorCorrection. It matters for the same reason: these are all children
	INSTANCES of the single global Lighting service, so if two ever coexist
	- a stray manual Studio edit, a leftover under an older name, or two
	builders both creating one - every ENABLED copy stacks in the renderer
	simultaneously. That is exactly how the lobby once went white/blown-out
	(two BloomEffects, "Bloom" and "MatharenaBloom", at the same time).
]]
local function ensureSingleton(className: string, name: string): Instance
	local found: Instance? = nil
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA(className) then
			if found then
				warn(("[LobbyLighting] Removing duplicate %s %q - keeping %q."):format(className, child.Name, found.Name))
				child:Destroy()
			else
				found = child
			end
		end
	end
	if not found then
		found = Instance.new(className)
		found.Parent = Lighting
	end
	found.Name = name
	return found
end

local function applyPostEffects()
	local bloom = ensureSingleton("BloomEffect", "LobbyBloom") :: BloomEffect
	bloom.Enabled = true
	bloom.Intensity = LightingConfig.BLOOM_INTENSITY
	bloom.Threshold = LightingConfig.BLOOM_THRESHOLD
	bloom.Size = LightingConfig.BLOOM_SIZE

	local colorCorrection = ensureSingleton("ColorCorrectionEffect", "LobbyColorCorrection") :: ColorCorrectionEffect
	colorCorrection.Enabled = true
	colorCorrection.Contrast = LightingConfig.COLOR_CORRECTION_CONTRAST
	colorCorrection.Saturation = LightingConfig.COLOR_CORRECTION_SATURATION
	colorCorrection.Brightness = LightingConfig.COLOR_CORRECTION_BRIGHTNESS
	colorCorrection.TintColor = LightingConfig.COLOR_CORRECTION_TINT_COLOR

	-- Atmosphere/DOF/SunRays: see LightingConfig's own section for why these
	-- moved from default.project.json into this module.
	local atmosphere = ensureSingleton("Atmosphere", "Atmosphere") :: Atmosphere
	atmosphere.Density = LightingConfig.ATMOSPHERE_DENSITY
	atmosphere.Offset = LightingConfig.ATMOSPHERE_OFFSET
	atmosphere.Color = LightingConfig.ATMOSPHERE_COLOR
	atmosphere.Decay = LightingConfig.ATMOSPHERE_DECAY
	atmosphere.Glare = LightingConfig.ATMOSPHERE_GLARE
	atmosphere.Haze = LightingConfig.ATMOSPHERE_HAZE

	local dof = ensureSingleton("DepthOfFieldEffect", "DepthOfField") :: DepthOfFieldEffect
	dof.Enabled = true
	dof.FocusDistance = LightingConfig.DOF_FOCUS_DISTANCE
	dof.InFocusRadius = LightingConfig.DOF_IN_FOCUS_RADIUS
	dof.FarIntensity = LightingConfig.DOF_FAR_INTENSITY
	dof.NearIntensity = LightingConfig.DOF_NEAR_INTENSITY

	local sunRays = ensureSingleton("SunRaysEffect", "SunRays") :: SunRaysEffect
	sunRays.Enabled = true
	sunRays.Intensity = LightingConfig.SUN_RAYS_INTENSITY
	sunRays.Spread = LightingConfig.SUN_RAYS_SPREAD
end

function LobbyLighting.Apply()
	Lighting.Ambient = LightingConfig.AMBIENT_COLOR
	Lighting.OutdoorAmbient = LightingConfig.OUTDOOR_AMBIENT_COLOR
	Lighting.Brightness = LightingConfig.DUSK_BRIGHTNESS
	Lighting.ClockTime = LightingConfig.DUSK_CLOCK_TIME
	Lighting.ExposureCompensation = LightingConfig.EXPOSURE_COMPENSATION
	Lighting.FogColor = LightingConfig.FOG_COLOR
	Lighting.FogStart = LightingConfig.FOG_START
	Lighting.FogEnd = LightingConfig.FOG_END

	applyPostEffects()
end

return LobbyLighting
