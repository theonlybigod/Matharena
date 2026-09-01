--[[
	Decimals.lua

	Round 8+ pool category. Decimal addition/subtraction to 2 places.
	Uses a small tolerance (0.01) in CheckAnswer to absorb floating-point
	representation error rather than requiring exact float equality.
]]

export type RawQuestion = {
	text: string,
	answer: number,
	tolerance: number?,
	debugOperands: { [string]: any }?,
}

local Decimals = {}

local function randomCents(min: number, max: number): number
	return math.random(min * 100, max * 100) / 100
end

local function round2(value: number): number
	return math.floor(value * 100 + 0.5) / 100
end

function Decimals.Generate(): RawQuestion
	local a = randomCents(1, 50)
	local b = randomCents(1, 50)

	if math.random() < 0.5 then
		return {
			text = ("%.2f + %.2f"):format(a, b),
			answer = round2(a + b),
			tolerance = 0.01,
			debugOperands = { a = a, b = b, op = "+" },
		}
	end

	if a < b then
		a, b = b, a
	end
	return {
		text = ("%.2f - %.2f"):format(a, b),
		answer = round2(a - b),
		tolerance = 0.01,
		debugOperands = { a = a, b = b, op = "-" },
	}
end

return Decimals
