--[[
	Config.lua

	Centralized, shared configuration for MathArena.
	Both server and client code may require this module.

	Add new configuration values here instead of hardcoding constants
	inside individual systems. Gameplay-specific values (match timers,
	scoring, difficulty curves, etc.) will be added here as those
	systems are built in later prompts.
]]

local Config = {}

Config.GAME_NAME = "MathArena"
Config.VERSION = "0.1.0"

-- Shared brand color used across world-building modules (lobby, arena, etc.)
-- so it isn't hardcoded/duplicated in multiple places.
Config.BRAND_NEON_COLOR = Color3.fromRGB(30, 140, 255)

-- Server-authoritative gameplay values will be added below as systems
-- (MatchSystem, DataSystem, etc.) are implemented. Intentionally left
-- minimal for the foundation/architecture pass.

return Config
