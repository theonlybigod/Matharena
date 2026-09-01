--[[
	Exponents.lua

	Round 8+ pool category ("Master Mode" pool) - now genuinely only ever
	reachable by a session that actually picked Master Mode, since every
	other tier is capped well below round 8 (GameplayConfig.QUEUE_TIERS'
	maxRound / GameplayConfig.AdvanceRoundForTier) and can never drift in
	here. Base/exponent range trimmed back down from an earlier, much
	wider range (base up to 16, exponent up to 4, e.g. 13^4 = 28561) -
	still clearly the hardest arithmetic in the game, but bounded so even
	Master Mode's biggest result stays reasonably computable by hand
	(12^3 = 1728 at the very top end) rather than requiring a calculator.
]]

export type RawQuestion = {
	text: string,
	answer: number,
	tolerance: number?,
	debugOperands: { [string]: any }?,
}

local Exponents = {}

local function randomInt(min: number, max: number): number
	return math.random(min, max)
end

function Exponents.Generate(): RawQuestion
	local base = randomInt(2, 12)
	local exponent = randomInt(2, 3)

	return {
		text = ("%d^%d"):format(base, exponent),
		answer = base ^ exponent,
		debugOperands = { base = base, exponent = exponent },
	}
end

return Exponents
