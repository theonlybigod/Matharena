--[[
	Forms.lua

	SERVER-ONLY, same as everything else under QuestionGenerator - these
	functions compute answers, so replicating them would let a client read
	the source and solve ahead of time.

	One builder per FORM id in DifficultyCurriculum. Each takes the resolved
	form (ranges, weights, ceilings already interpolated for this round) and
	returns { text, answer, debugOperands }.

	TWO RULES HOLD ACROSS EVERY BUILDER.

	1. ANSWERS ARE ALWAYS WHOLE NUMBERS. The spec repeats this for
	   percentages, division, roots and exponents, and it is simplest to
	   make it universal: nothing here can return a fraction or a decimal.
	   Where a form's natural answer WOULD be a fraction, the question
	   states the common denominator and asks for the numerator instead
	   ("3/8 + 2/8 = ?/8"), which keeps the maths honest and the answer an
	   integer that tonumber() can validate.

	2. NEGATIVE ANSWERS ONLY WHERE ALLOWED. `allowNegativeAnswer` comes
	   from the curriculum - false for the whole of Easy, true from Medium
	   onward for addition and subtraction. Multiplication and division
	   never produce negatives at any difficulty, per spec.
]]

local Forms = {}

local function randomInt(min: number, max: number): number
	if max < min then
		max = min
	end
	return math.random(math.floor(min), math.floor(max))
end

local function pick<T>(list: { T }): T
	return list[math.random(1, #list)]
end

local function gcd(a: number, b: number): number
	while b ~= 0 do
		a, b = b, a % b
	end
	return math.abs(a)
end

--[[
	ADDITION / SUBTRACTION, 2 to 4 terms.

	A single question never MIXES + and - when it has three or four terms
	(spec) - one operator is chosen and used throughout. Two-term questions
	pick their operator from the form's `ops` list, which is how Easy runs
	addition-only until round 3.

	When negatives are disallowed, the terms are reordered so the running
	total never dips below zero, rather than regenerating until it happens
	to work - that would bias the number distribution toward large first
	operands.
]]
local function buildAddSub(form)
	local terms = form.terms or 2
	local range = form.range or { min = 1, max = 10 }
	local op = pick(form.ops or { "+", "-" })
	local allowNegative = form.allowNegativeAnswer == true

	local values = {}
	for i = 1, terms do
		values[i] = randomInt(range.min, range.max)
	end

	if op == "-" and not allowNegative then
		-- Largest first, then descending, so every partial result stays >= 0.
		table.sort(values, function(a, b)
			return a > b
		end)
	end

	local answer = values[1]
	for i = 2, terms do
		if op == "+" then
			answer += values[i]
		else
			answer -= values[i]
		end
	end

	local parts = { tostring(values[1]) }
	for i = 2, terms do
		table.insert(parts, op)
		table.insert(parts, tostring(values[i]))
	end

	return {
		text = table.concat(parts, " "),
		answer = answer,
		debugOperands = { values = values, op = op, terms = terms },
	}
end

--[[
	MULTIPLICATION AND INTEGER DIVISION.

	Division is built BACKWARD from divisor x quotient, which is the only
	way to guarantee an exact integer answer without rejection-sampling.

	The spec asks that a higher and a lower number be more likely to appear
	together on division questions; drawing the quotient from the lower part
	of the range while the divisor spans the whole of it produces exactly
	that, and keeps the dividend from exploding.
]]
local function buildMulDiv(form)
	local range = form.range or { min = 2, max = 10 }
	local second = form.secondRange or range

	if math.random() < 0.5 then
		local a = randomInt(range.min, range.max)
		local b = randomInt(range.min, range.max)
		return {
			text = ("%d x %d"):format(a, b),
			answer = a * b,
			debugOperands = { a = a, b = b, op = "*" },
		}
	end

	local divisor = randomInt(math.max(2, second.min), math.max(2, second.max))
	local quotient = randomInt(2, math.max(2, math.floor(range.min + (range.max - range.min) * 0.5)))
	local dividend = divisor * quotient

	return {
		text = ("%d / %d"):format(dividend, divisor),
		answer = quotient,
		debugOperands = { a = dividend, b = divisor, op = "/" },
	}
end

--[[
	PERCENTAGES.

	The percentage always moves in steps of five, the number it applies to
	is capped at 200, and the answer is always whole - so the base number is
	drawn from the multiples that divide cleanly.

	For a percentage p, p*N must be divisible by 100, so N has to be a
	multiple of 100/gcd(p,100). Computing that step and picking a multiple
	of it inside the range is exact; there is no retry loop and no
	possibility of a fractional answer slipping through.

	No variables appear in these questions, per spec - always a literal
	number.
]]
local function buildPercent(form)
	local pRange = form.range or { min = 5, max = 50 }
	local nRange = form.secondRange or { min = 20, max = 200 }

	-- Percentage in steps of five.
	local lowStep = math.max(1, math.ceil(pRange.min / 5))
	local highStep = math.max(lowStep, math.floor(pRange.max / 5))
	local percent = randomInt(lowStep, highStep) * 5

	-- Smallest N that makes the answer whole.
	local step = 100 // gcd(percent, 100)
	local cap = math.min(nRange.max, 200) -- hard cap from the spec
	local lowMultiple = math.max(1, math.ceil(nRange.min / step))
	local highMultiple = math.max(lowMultiple, math.floor(cap / step))
	local n = randomInt(lowMultiple, highMultiple) * step

	return {
		text = ("%d%% of %d"):format(percent, n),
		answer = (percent * n) // 100,
		debugOperands = { percent = percent, y = n },
	}
end

--[[
	FRACTION ADDITION AND SUBTRACTION.

	The answer would naturally be a fraction, so the question states the
	denominator of the result and asks for the NUMERATOR - "3/8 + 2/8 = ?/8".
	That keeps the answer an integer while still testing the actual skill.

	`sameDenominator` is true for Hard rounds 2-3 and false from round 4,
	which is where unlike denominators are introduced. With unlike
	denominators the common denominator is the product (or the LCM where
	smaller), and it is shown in the question so there is exactly one
	correct numerator.

	Numerators and denominators never exceed maxDenominator (10 everywhere
	it is used), per spec.
]]
local function buildFractionAddSub(form)
	local maxD = form.maxDenominator or 10
	local terms = form.terms or 2
	local same = form.sameDenominator ~= false
	local op = pick({ "+", "-" })

	if same then
		local d = randomInt(2, maxD)
		local nums = {}
		for i = 1, terms do
			nums[i] = randomInt(1, math.max(1, d - 1))
		end
		if op == "-" then
			table.sort(nums, function(a, b)
				return a > b
			end)
		end

		local answer = nums[1]
		local parts = { ("%d/%d"):format(nums[1], d) }
		for i = 2, terms do
			answer = if op == "+" then answer + nums[i] else answer - nums[i]
			table.insert(parts, op)
			table.insert(parts, ("%d/%d"):format(nums[i], d))
		end

		return {
			text = ("%s = ?/%d"):format(table.concat(parts, " "), d),
			answer = answer,
			debugOperands = { nums = nums, d = d, op = op, same = true },
		}
	end

	-- Unlike denominators, two terms only - three unlike denominators inside
	-- an 8-second turn is past the point of being solvable rather than hard.
	local d1 = randomInt(2, maxD)
	local d2 = randomInt(2, maxD)
	while d2 == d1 do
		d2 = randomInt(2, maxD)
	end
	local n1 = randomInt(1, d1 - 1)
	local n2 = randomInt(1, d2 - 1)

	local common = (d1 * d2) // gcd(d1, d2)
	local a = n1 * (common // d1)
	local b = n2 * (common // d2)
	if op == "-" and a < b then
		a, b = b, a
		n1, n2, d1, d2 = n2, n1, d2, d1
	end

	return {
		text = ("%d/%d %s %d/%d = ?/%d"):format(n1, d1, op, n2, d2, common),
		answer = if op == "+" then a + b else a - b,
		debugOperands = { n1 = n1, d1 = d1, n2 = n2, d2 = d2, op = op, common = common },
	}
end

--[[
	FRACTION MULTIPLICATION.

	Deliberately the easiest of the fraction forms, per spec - numerators
	and denominators both capped at 10, and the answer asked for as the
	numerator over the product denominator, unsimplified.
]]
local function buildFractionMul(form)
	local maxD = form.maxDenominator or 10
	local d1 = randomInt(2, maxD)
	local d2 = randomInt(2, maxD)
	local n1 = randomInt(1, d1 - 1)
	local n2 = randomInt(1, d2 - 1)

	return {
		text = ("%d/%d x %d/%d = ?/%d"):format(n1, d1, n2, d2, d1 * d2),
		answer = n1 * n2,
		debugOperands = { n1 = n1, d1 = d1, n2 = n2, d2 = d2, op = "*" },
	}
end

--[[
	RATIOS.

	Share-of-a-total questions: a total is split in a given ratio and the
	player returns one part. The total is built as (a+b) x multiplier so
	every part is a whole number.
]]
local function buildRatio(form)
	local range = form.range or { min = 2, max = 12 }
	local a = randomInt(math.max(1, range.min), math.max(2, range.max))
	local b = randomInt(math.max(1, range.min), math.max(2, range.max))
	local multiplier = randomInt(2, 12)
	local total = (a + b) * multiplier
	local wantFirst = math.random() < 0.5

	return {
		text = ("%d is split in the ratio %d:%d. What is the %s share?"):format(
			total,
			a,
			b,
			if wantFirst then "first" else "second"
		),
		answer = (if wantFirst then a else b) * multiplier,
		debugOperands = { a = a, b = b, multiplier = multiplier, wantFirst = wantFirst },
	}
end

--[[
	POWERS.

	`powers` lists which exponents are live this round (squares only on
	Expert round 1; squares, cubes and fourth powers from round 2), and
	`baseCeilings` caps the base PER EXPONENT - the spec fixes these at
	round 10: fourth powers never past base 6, cubes never past 8, squares
	up to 20.
]]
local function buildPower(form)
	local powers = form.powers or { 2 }
	local exponent = pick(powers)
	local ceiling = (form.baseCeilings and form.baseCeilings[exponent]) or 10
	local base = randomInt(0, math.max(1, ceiling))

	return {
		text = ("%d^%d"):format(base, exponent),
		answer = base ^ exponent,
		debugOperands = { base = base, exponent = exponent },
	}
end

--[[
	SQUARE ROOTS.

	Built from the root outward, so the radicand is always a perfect square
	and the answer always exact. `range` is the ROOT's range, which is why
	Expert round 10's max of 44 gives a radicand of 1936 - the largest
	perfect square under the spec's 2000 ceiling.
]]
local function buildRoot(form)
	local range = form.range or { min = 2, max = 10 }
	local root = randomInt(range.min, range.max)

	return {
		text = ("sqrt(%d)"):format(root * root),
		answer = root,
		debugOperands = { root = root, power = 2 },
	}
end

--[[
	CUBE ROOTS AND FOURTH ROOTS. Same construction as buildRoot - from the
	root outward, so the value under the radical is always a perfect power.
]]
local function buildHigherRoot(form)
	local range = form.range or { min = 2, max = 6 }
	local power = pick(form.powers or { 3 })
	local root = randomInt(math.max(2, range.min), math.max(2, range.max))

	return {
		text = ("root%d(%d)"):format(power, root ^ power),
		answer = root,
		debugOperands = { root = root, power = power },
	}
end

--[[
	OPERATIONS BETWEEN EXPONENTS.

	Multiplying and dividing powers of a shared base, and raising a power to
	a power - the "different functions of exponents together" the spec asks
	for. Division is arranged so the exponent difference is never negative,
	keeping the answer a whole number.
]]
local function buildPowerOps(form)
	local range = form.range or { min = 2, max = 6 }
	local powers = form.powers or { 2, 3 }
	local base = randomInt(2, math.max(2, math.min(range.max, 6)))
	local e1 = pick(powers)
	local e2 = pick(powers)
	local mode = math.random(1, 3)

	if mode == 1 then
		return {
			text = ("%d^%d x %d^%d"):format(base, e1, base, e2),
			answer = base ^ (e1 + e2),
			debugOperands = { base = base, e1 = e1, e2 = e2, mode = "mul" },
		}
	elseif mode == 2 then
		local high, low = math.max(e1, e2), math.min(e1, e2)
		-- Guarantee a positive exponent so the answer stays a whole number.
		if high == low then
			high += 1
		end
		return {
			text = ("%d^%d / %d^%d"):format(base, high, base, low),
			answer = base ^ (high - low),
			debugOperands = { base = base, e1 = high, e2 = low, mode = "div" },
		}
	end

	return {
		text = ("(%d^%d)^%d"):format(base, e1, e2),
		answer = base ^ (e1 * e2),
		debugOperands = { base = base, e1 = e1, e2 = e2, mode = "pow" },
	}
end

--[[
	WORD PROBLEMS - Master only.

	No new maths: the arithmetic underneath is the same as elsewhere. What
	makes them hard is that the operation has to be EXTRACTED before it can
	be solved, under a clock - which is the multitasking pressure the spec
	asks Master to carry. They get a longer `seconds` from the curriculum
	because reading is part of the cost.

	Every template is built from chosen operands rather than parsed from
	text, so the answer is exact by construction.
]]
local WORD_TEMPLATES = {
	function()
		local perBox = randomInt(12, 40)
		local boxes = randomInt(6, 25)
		return ("A crate holds %d items. How many items are in %d crates?"):format(perBox, boxes), perBox * boxes
	end,
	function()
		local total = randomInt(20, 60) * randomInt(4, 12)
		local groups = randomInt(4, 12)
		while total % groups ~= 0 do
			groups -= 1
			if groups < 2 then
				groups = 2
				total = total - (total % groups)
			end
		end
		return ("%d players are split evenly into %d teams. How many per team?"):format(total, groups), total // groups
	end,
	function()
		local start = randomInt(200, 800)
		local spent = randomInt(50, 199)
		local earned = randomInt(50, 199)
		return ("You start with %d coins, spend %d, then earn %d. How many coins now?"):format(start, spent, earned),
			start - spent + earned
	end,
	function()
		local percent = randomInt(1, 19) * 5
		local step = 100 // gcd(percent, 100)
		local n = randomInt(math.max(1, 40 // step), 200 // step) * step
		return ("%d%% of a %d-point score is bonus. How many bonus points?"):format(percent, n), (percent * n) // 100
	end,
	function()
		local rate = randomInt(15, 45)
		local hours = randomInt(3, 12)
		local extra = randomInt(20, 120)
		return ("A machine makes %d parts an hour for %d hours, then %d more. How many parts?"):format(rate, hours, extra),
			rate * hours + extra
	end,
}

local function buildWordProblem()
	local template = pick(WORD_TEMPLATES)
	local text, answer = template()
	return {
		text = text,
		answer = answer,
		debugOperands = { word = true },
	}
end

Forms.BUILDERS = {
	addSub2 = buildAddSub,
	addSub3 = buildAddSub,
	addSub4 = buildAddSub,
	mulDiv = buildMulDiv,
	percent = buildPercent,
	fractionAddSub = buildFractionAddSub,
	fractionMul = buildFractionMul,
	ratio = buildRatio,
	power = buildPower,
	root = buildRoot,
	higherRoot = buildHigherRoot,
	powerOps = buildPowerOps,
	wordProblem = buildWordProblem,
}

--[[
	Builds one question from a resolved curriculum form. Returns nil for an
	unknown form id rather than erroring, so a curriculum typo degrades to
	"pick something else" instead of killing a live match.
]]
function Forms.Build(form)
	local builder = Forms.BUILDERS[form.form]
	if not builder then
		return nil
	end
	return builder(form)
end

return Forms
