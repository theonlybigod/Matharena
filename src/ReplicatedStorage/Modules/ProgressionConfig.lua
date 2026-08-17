--[[
	ProgressionConfig.lua

	Centralized progression constants: rank tiers and the XP curve.

	Pure, deterministic functions only — safe to require from both server
	and client (e.g. a future client-side "XP to next level" UI). Only
	ProgressionSystem (server) is trusted to actually mutate a player's
	XP/level/rank; this module never touches player data itself.
]]

local ProgressionConfig = {}

-- Ordered lowest to highest. Each rank spans LEVELS_PER_RANK levels.
ProgressionConfig.RANKS = {
	"Beginner",
	"Student",
	"Scholar",
	"Mathlete",
	"Prodigy",
	"Expert",
	"Master",
	"Grandmaster",
	"Legend",
	"Champion",
}

ProgressionConfig.LEVELS_PER_RANK = 10
ProgressionConfig.MAX_LEVEL = #ProgressionConfig.RANKS * ProgressionConfig.LEVELS_PER_RANK -- 100

-- XP curve: XP required to advance FROM `level` to `level + 1`. Formula-
-- based (rather than a hardcoded per-level table) so the whole curve is
-- easy to tune from one place.
ProgressionConfig.BASE_XP = 100
ProgressionConfig.XP_GROWTH_EXPONENT = 1.35

function ProgressionConfig.GetXPRequiredForLevel(level: number): number
	return math.floor(ProgressionConfig.BASE_XP * level ^ ProgressionConfig.XP_GROWTH_EXPONENT)
end

--[[
	Given a player's total (lifetime, cumulative) XP, returns the level that
	amount of XP corresponds to, capped at MAX_LEVEL.
]]
function ProgressionConfig.GetLevelFromTotalXP(totalXP: number): number
	local level = 1
	local remaining = totalXP

	while level < ProgressionConfig.MAX_LEVEL do
		local needed = ProgressionConfig.GetXPRequiredForLevel(level)
		if remaining < needed then
			break
		end
		remaining -= needed
		level += 1
	end

	return level
end

--[[
	Given a player's total XP, returns (level, xpIntoCurrentLevel,
	xpRequiredForCurrentLevel) — intended for a future "XP progress bar" UI.
]]
function ProgressionConfig.GetXPProgress(totalXP: number): (number, number, number)
	local level = 1
	local remaining = totalXP

	while level < ProgressionConfig.MAX_LEVEL do
		local needed = ProgressionConfig.GetXPRequiredForLevel(level)
		if remaining < needed then
			return level, remaining, needed
		end
		remaining -= needed
		level += 1
	end

	return level, remaining, ProgressionConfig.GetXPRequiredForLevel(level)
end

--[[
	Maps a level to its rank name. Levels 1-10 are Beginner, 11-20 Student,
	... 91-100 Champion (10 ranks x 10 levels = MAX_LEVEL).
]]
function ProgressionConfig.GetRankForLevel(level: number): string
	local index = math.clamp(math.ceil(level / ProgressionConfig.LEVELS_PER_RANK), 1, #ProgressionConfig.RANKS)
	return ProgressionConfig.RANKS[index]
end

return ProgressionConfig
