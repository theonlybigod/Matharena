--[[
	SettingsConfig.lua

	Centralized settings schema, defaults, and validation ranges (Message
	12). Both SettingsSystem (server, authoritative validation) and
	SettingsUIController (client, builds the panel/ranges) read from this
	same table so the two never drift out of sync.

	Every setting here is a client-experience preference (audio volume,
	graphics quality, UI scale, colorblind mode) - none of it is a
	security-sensitive value like currency, so the server's job is just to
	validate/clamp and persist it, not guard it from the player who owns it.
]]

export type GraphicsQuality = "Low" | "Medium" | "High"

local SettingsConfig = {}

SettingsConfig.DEFAULTS = {
	musicVolume = 0.5,
	sfxVolume = 0.7,
	graphicsQuality = "High" :: GraphicsQuality,
	uiScale = 1.0,
	colorblindMode = false,
}

SettingsConfig.MUSIC_VOLUME_RANGE = { min = 0, max = 1 }
SettingsConfig.SFX_VOLUME_RANGE = { min = 0, max = 1 }
SettingsConfig.UI_SCALE_RANGE = { min = 0.75, max = 1.25 }
SettingsConfig.GRAPHICS_QUALITY_OPTIONS = { "Low", "Medium", "High" }

--[[
	Validates and clamps a single (key, value) pair against the ranges/
	enums above. Returns (true, clampedValue) if the key is recognized and
	the value is a usable type, or (false) if the key is unknown or the
	value's type doesn't match what that setting expects at all (e.g. a
	string where a number was expected) - the caller should reject the
	update entirely in that case rather than guess at a fallback.
]]
function SettingsConfig.ValidateAndClamp(key: string, value: any): (boolean, any)
	if key == "musicVolume" or key == "sfxVolume" then
		if typeof(value) ~= "number" then
			return false, nil
		end
		local range = if key == "musicVolume" then SettingsConfig.MUSIC_VOLUME_RANGE else SettingsConfig.SFX_VOLUME_RANGE
		return true, math.clamp(value, range.min, range.max)
	elseif key == "uiScale" then
		if typeof(value) ~= "number" then
			return false, nil
		end
		return true, math.clamp(value, SettingsConfig.UI_SCALE_RANGE.min, SettingsConfig.UI_SCALE_RANGE.max)
	elseif key == "graphicsQuality" then
		if typeof(value) ~= "string" then
			return false, nil
		end
		for _, option in ipairs(SettingsConfig.GRAPHICS_QUALITY_OPTIONS) do
			if option == value then
				return true, value
			end
		end
		return false, nil
	elseif key == "colorblindMode" then
		if typeof(value) ~= "boolean" then
			return false, nil
		end
		return true, value
	end

	return false, nil -- unknown key
end

return SettingsConfig
