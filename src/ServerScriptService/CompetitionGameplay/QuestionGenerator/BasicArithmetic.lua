--[[
	BasicArithmetic.lua

	The Round 1/2 categories - deliberately the SIMPLEST questions in the
	game ("Easy Mode" - "very simple questions"), parameterized by number-
	size tier ("single" digit for Round 1, "two" digit for Round 2).

	Round 1 ("single") is ADDITION ONLY - genuinely the simplest possible
	question, matching Easy Mode's own advertised description ("Simple
	single-digit addition"). Round 2 ("two") adds subtraction into the mix
	but still never multiplication/division - those are deliberately held
	back for Round 3 (MixedOperations) onward, so Easy Mode stays clearly,
	meaningfully easier than everything after it rather than immediately
	handing out the same four operations as later rounds.
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
	local availableOps = { "+" } -- Round 1 ("single"): addition only
	if tier == "two" then
		low, high = 10, 99
		availableOps = { "+", "-" } -- Round 2 ("two"): addition + subtraction
	end

	local op = availableOps[math.random(1, #availableOps)]
	local a, b, answer

	if op == "+" then
		a, b = randomInt(low, high), randomInt(low, high)
		answer = a + b
	else -- "-"
		a, b = randomInt(low, high), randomInt(low, high)
		if a < b then
			a, b = b, a
		end
		answer = a - b
	end

	return {
		text = ("%d %s %d"):format(a, op, b),
		answer = answer,
		debugOperands = { a = a, b = b, op = op },
	}
end

return BasicArithmetic
