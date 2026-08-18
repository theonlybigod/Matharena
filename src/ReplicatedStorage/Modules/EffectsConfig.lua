--[[
	EffectsConfig.lua

	Tuning constants for the client-side visual effects (Message 12):
	confetti/fireworks bursts, screen flashes, and floating reward text.
	Pure data - EffectsController.client.lua owns creating and animating
	the actual instances.
]]

local EffectsConfig = {}

EffectsConfig.CONFETTI_COLORS = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 210, 60),
	Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(130, 255, 130),
	Color3.fromRGB(255, 130, 230),
}
EffectsConfig.CONFETTI_PARTICLE_COUNT = 80
EffectsConfig.CONFETTI_DURATION_SECONDS = 3

EffectsConfig.FIREWORK_BURST_COUNT = 5
EffectsConfig.FIREWORK_COLORS = {
	Color3.fromRGB(255, 100, 60),
	Color3.fromRGB(120, 180, 255),
	Color3.fromRGB(255, 240, 120),
}

EffectsConfig.FLASH_DURATION_SECONDS = 0.35
-- Correct/Wrong flashes route through UITheme.GetSuccessColor()/
-- GetErrorColor() instead (so they respect colorblind mode); only Winner
-- is a fixed color here since it isn't a semantic correct/incorrect signal.
EffectsConfig.FLASH_COLORS = {
	Winner = Color3.fromRGB(255, 215, 0),
}

EffectsConfig.FLOATING_REWARD_RISE_PIXELS = 60
EffectsConfig.FLOATING_REWARD_DURATION_SECONDS = 1.2

return EffectsConfig
