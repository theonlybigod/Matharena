--[[
	Fractions.lua

	Round 5 category: "What is N/D of Y?" - a fraction-of-a-number problem.
	Y is always chosen as a multiple of D, guaranteeing a whole-number
	answer (keeps the existing numeric-only answer contract from Message 6
	intact rather than introducing fraction-formatted input).
]]

export type RawQuestion = {
	text: string,
	answer: number,
	tolerance: number?,
	debugOperands: { [string]: any }?,
}

local Fractions = {}

local DENOMINATORS = { 2, 3, 4, 5, 6, 8 }

local function randomInt(min: number, max: number): number
	return math.random(min, max)
end

function Fractions.Generate(): RawQuestion
	local d = DENOMINATORS[math.random(1, #DENOMINATORS)]
	local n = randomInt(1, d - 1)
	local y = d * randomInt(1, 10)
	local answer = (n * y) / d

	return {
		text = ("What is %d/%d of %d?"):format(n, d, y),
		answer = answer,
		debugOperands = { n = n, d = d, y = y },
	}
end

return Fractions
