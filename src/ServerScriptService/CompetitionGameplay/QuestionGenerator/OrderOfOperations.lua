--[[
	OrderOfOperations.lua

	Round 6 category: an unparenthesized expression that requires knowing
	multiplication happens before addition/subtraction (PEMDAS). Always of
	the form "a + b × c" or "a - b × c".
]]

export type RawQuestion = {
	text: string,
	answer: number,
	tolerance: number?,
	debugOperands: { [string]: any }?,
}

local OrderOfOperations = {}

local function randomInt(min: number, max: number): number
	return math.random(min, max)
end

function OrderOfOperations.Generate(): RawQuestion
	local b = randomInt(2, 9)
	local c = randomInt(2, 9)
	local product = b * c

	if math.random() < 0.5 then
		local a = randomInt(1, 20)
		return {
			text = ("%d + %d \u{00D7} %d"):format(a, b, c),
			answer = a + product,
			debugOperands = { a = a, b = b, c = c, op = "+" },
		}
	end

	local a = randomInt(product + 1, product + 20) -- keep a - product non-negative
	return {
		text = ("%d - %d \u{00D7} %d"):format(a, b, c),
		answer = a - product,
		debugOperands = { a = a, b = b, c = c, op = "-" },
	}
end

return OrderOfOperations
