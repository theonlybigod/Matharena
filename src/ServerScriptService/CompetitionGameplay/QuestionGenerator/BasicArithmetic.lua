--[[
	BasicArithmetic.lua

	Addition, Subtraction, Multiplication, Division - the four Round 1/2
	categories, parameterized by number-size tier ("single" digit for
	Round 1, "two" digit for Round 2). One of the four operations is
	picked at random each call.
]]

export type RawQuestion = {
	text: string,
	answer: number,
	tolerance: number?,
	debugOperands: { [string]: any }?,
}

local BasicArithmetic = {}

local function randomInt(min: number, max: number): number
	return math.random(min, max)
end

function BasicArithmetic.Generate(tier: string): RawQuestion
	local low, high = 1, 9
	if tier == "two" then
		low, high = 10, 99
	end

	local op = ({ "+", "-", "*", "/" })[math.random(1, 4)]
	local a, b, answer

	if op == "+" then
		a, b = randomInt(low, high), randomInt(low, high)
		answer = a + b
	elseif op == "-" then
		a, b = randomInt(low, high), randomInt(low, high)
		if a < b then
			a, b = b, a
		end
		answer = a - b
	elseif op == "*" then
		a, b = randomInt(low, high), randomInt(low, high)
		answer = a * b
	else -- "/"
		local divisor = randomInt(math.max(low, 2), high)
		local quotient = randomInt(low, high)
		a = divisor * quotient
		b = divisor
		answer = quotient
	end

	local symbol = (op == "*") and "\u{00D7}" or (op == "/") and "\u{00F7}" or op

	return {
		text = ("%d %s %d"):format(a, symbol, b),
		answer = answer,
		debugOperands = { a = a, b = b, op = op },
	}
end

return BasicArithmetic
