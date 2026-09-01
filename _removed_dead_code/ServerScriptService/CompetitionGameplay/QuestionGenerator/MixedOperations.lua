--[[
	MixedOperations.lua

	Round 3 category: combines two different basic operations in a single
	question. Always explicitly parenthesized ("(a op1 b) op2 c") so the
	intended evaluation order is unambiguous to the player - this is what
	distinguishes it from OrderOfOperations, which deliberately omits
	parentheses to test precedence knowledge.
]]

export type RawQuestion = {
	text: string,
	answer: number,
	tolerance: number?,
	debugOperands: { [string]: any }?,
}

local MixedOperations = {}

local OPS = { "+", "-", "*" }

local function randomInt(min: number, max: number): number
	return math.random(min, max)
end

local function apply(op: string, x: number, y: number): number
	if op == "+" then
		return x + y
	elseif op == "-" then
		return x - y
	else
		return x * y
	end
end

local function symbol(op: string): string
	return (op == "*") and "\u{00D7}" or op
end

function MixedOperations.Generate(): RawQuestion
	local a = randomInt(2, 20)
	local b = randomInt(2, 20)
	local c = randomInt(2, 20)

	local op1 = OPS[math.random(1, 3)]
	local op2 = OPS[math.random(1, 3)]

	if op1 == "-" and a < b then
		a, b = b, a
	end
	local intermediate = apply(op1, a, b)

	if op2 == "-" and intermediate < c then
		c = randomInt(1, math.max(1, intermediate))
	end
	local answer = apply(op2, intermediate, c)

	return {
		text = ("(%d %s %d) %s %d"):format(a, symbol(op1), b, symbol(op2), c),
		answer = answer,
		debugOperands = { a = a, b = b, c = c, op1 = op1, op2 = op2 },
	}
end

return MixedOperations
