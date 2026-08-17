--[[
	Exponents.lua

	Round 8+ pool category. Small base/exponent so results stay reasonable.
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
