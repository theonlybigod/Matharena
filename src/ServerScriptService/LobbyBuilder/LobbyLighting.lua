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
	or any Rebuild). FindFirstChild guards make this idempotent so calling
	Apply() again (e.g. on a Rebuild) never creates duplicates.
]]
local function applyPostEffects()
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") :: BloomEffect?
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Name = "LobbyBloom"
		bloom.Parent = Lighting
	end
	bloom.Intensity = LightingConfig.BLOOM_INTENSITY
	bloom.Threshold = LightingConfig.BLOOM_THRESHOLD
	bloom.Size = LightingConfig.BLOOM_SIZE

	local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") :: ColorCorrectionEffect?
	if not colorCorrection then
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Name = "LobbyColorCorrection"
		colorCorrection.Parent = Lighting
	end
	colorCorrection.Contrast = LightingConfig.COLOR_CORRECTION_CONTRAST
	colorCorrection.Saturation = LightingConfig.COLOR_CORRECTION_SATURATION
	colorCorrection.TintColor = LightingConfig.COLOR_CORRECTION_TINT_COLOR
end

function LobbyLighting.Apply()
	Lighting.Ambient = LightingConfig.AMBIENT_COLOR
	Lighting.OutdoorAmbient = LightingConfig.OUTDOOR_AMBIENT_COLOR
	Lighting.Brightness = LightingConfig.DUSK_BRIGHTNESS
	Lighting.ClockTime = LightingConfig.DUSK_CLOCK_TIME
	Lighting.ExposureCompensation = LightingConfig.EXPOSURE_COMPENSATION
	Lighting.FogColor = LightingConfig.FOG_COLOR
	Lighting.FogEnd = LightingConfig.FOG_END

	applyPostEffects()
end

return LobbyLighting
