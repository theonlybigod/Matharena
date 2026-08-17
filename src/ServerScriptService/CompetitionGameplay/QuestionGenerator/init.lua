--[[
	QuestionGenerator

	SERVER-ONLY - must never be moved to ReplicatedStorage. Generates both
	the question text AND the correct answer for every category; if this
	logic were replicated, any client could inspect the ModuleScript's
	source and compute (or predict) answers ahead of time. Only question
	text ever leaves the server, via CompetitionGameplay's "TurnStarted"
	RemoteEvent.

	API:
		Generate(round) -> Question         -- request a question for a round
		CheckAnswer(question, submitted)    -- server-authoritative correctness check
		ResetUsedQuestions()                -- call at the start of each match
		RunSelfTest(sampleCount?)           -- internal validation/regression helper

	"No repeats": generated question TEXT is tracked per-match (reset via
	ResetUsedQuestions) and regenerated on collision, up to a retry cap -
	after which a repeat is allowed rather than risking an infinite loop in
	a category/tier with a small possibility space (e.g. single-digit
	arithmetic only has 100 possible digit pairs).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameplayConfig = require(ReplicatedStorage.Modules.GameplayConfig)

local BasicArithmetic = require(script.BasicArithmetic)
local MixedOperations = require(script.MixedOperations)
local OrderOfOperations = require(script.OrderOfOperations)
local Percentages = require(script.Percentages)
local Fractions = require(script.Fractions)
local Roots = require(script.Roots)
local Algebra = require(script.Algebra)
local Decimals = require(script.Decimals)
local Exponents = require(script.Exponents)
local Geometry = require(script.Geometry)

export type Question = {
	category: string,
	round: number,
	text: string,
	answer: number,
	tolerance: number,
	debugOperands: { [string]: any }?,
}

local QuestionGenerator = {}

local MAX_RETRIES = 25
local usedQuestionTexts: { [string]: boolean } = {}

local generatorsByCategory: { [string]: (tier: string?) -> any } = {
	BasicArithmetic = function(tier: string?)
		return BasicArithmetic.Generate(tier or "single")
	end,
	MixedOperations = function()
		return MixedOperations.Generate()
	end,
	OrderOfOperations = function()
		return OrderOfOperations.Generate()
	end,
	Percentages = function()
		return Percentages.Generate()
	end,
	Fractions = function()
		return Fractions.Generate()
	end,
	SquareRoots = function()
		return Roots.Generate()
	end,
	Algebra = function()
		return Algebra.Generate()
	end,
	Decimals = function()
		return Decimals.Generate()
	end,
	Exponents = function()
		return Exponents.Generate()
	end,
	Geometry = function()
		return Geometry.Generate()
	end,
}

--[[
	Clears the per-match "no repeats" tracking. Call once at the start of
	each match (CompetitionGameplay does this in startRound()).
]]
function QuestionGenerator.ResetUsedQuestions()
	table.clear(usedQuestionTexts)
end

--[[
	Requests a question for the given round. The category (and, for
	BasicArithmetic, the number-size tier) is resolved from
	GameplayConfig.GetRoundPlan(round). Retries on a duplicate question
	text up to MAX_RETRIES before giving up and allowing the repeat.
]]
function QuestionGenerator.Generate(round: number): Question
	local plan = GameplayConfig.GetRoundPlan(round)
	local generator = generatorsByCategory[plan.category]
	assert(generator, ("[QuestionGenerator] Unknown category %q for round %d"):format(plan.category, round))

	local raw
	for _ = 1, MAX_RETRIES do
		raw = generator(plan.tier)
		if not usedQuestionTexts[raw.text] then
			break
		end
	end

	usedQuestionTexts[raw.text] = true

	return {
		category = plan.category,
		round = round,
		text = raw.text,
		answer = raw.answer,
		tolerance = raw.tolerance or 0,
		debugOperands = raw.debugOperands,
	}
end

--[[
	Server-authoritative correctness check. Uses the question's tolerance
	(0 for exact-match categories, a small epsilon for Decimals) rather
	than strict equality, so floating-point representation error doesn't
	cause a correct decimal answer to be rejected.
]]
function QuestionGenerator.CheckAnswer(question: Question, submitted: number): boolean
	return math.abs(submitted - question.answer) <= question.tolerance
end

-- Independently recomputes the expected answer from a question's
-- debugOperands, without reusing the generator's own formula verbatim -
-- used only by RunSelfTest as a cross-check.
local function recomputeExpected(question: Question): number?
	local d = question.debugOperands
	if not d then
		return nil
	end

	local category = question.category
	if category == "BasicArithmetic" then
		if d.op == "+" then
			return d.a + d.b
		elseif d.op == "-" then
			return d.a - d.b
		elseif d.op == "*" then
			return d.a * d.b
		else
			return d.a / d.b
		end
	elseif category == "MixedOperations" then
		local function apply(op, x, y)
			if op == "+" then
				return x + y
			elseif op == "-" then
				return x - y
			else
				return x * y
			end
		end
		return apply(d.op2, apply(d.op1, d.a, d.b), d.c)
	elseif category == "OrderOfOperations" then
		local product = d.b * d.c
		return (d.op == "+") and (d.a + product) or (d.a - product)
	elseif category == "Percentages" then
		return (d.percent * d.y) / 100
	elseif category == "Fractions" then
		return (d.n * d.y) / d.d
	elseif category == "SquareRoots" then
		return d.root
	elseif category == "Algebra" then
		if d.form == "add" then
			return d.b - d.a
		elseif d.form == "sub" then
			return d.b + d.a
		elseif d.form == "mul" then
			return d.b / d.m
		else
			return d.m * d.q
		end
	elseif category == "Decimals" then
		return (d.op == "+") and (d.a + d.b) or (d.a - d.b)
	elseif category == "Exponents" then
		return d.base ^ d.exponent
	elseif category == "Geometry" then
		if d.shape == "rectangleArea" then
			return d.length * d.width
		elseif d.shape == "rectanglePerimeter" then
			return 2 * (d.length + d.width)
		else
			return (d.base * d.height) / 2
		end
	end

	return nil
end

--[[
	Internal validation/regression helper (not called automatically at
	runtime). Generates sample questions across every round, checking:
		- question text is non-empty
		- the stored answer is a valid, finite number
		- CheckAnswer accepts the question's own correct answer
		- where debugOperands are available, an independently-recomputed
		  expected answer matches the stored one
	Returns (true, {}) on success, or (false, errorMessages) otherwise.
]]
function QuestionGenerator.RunSelfTest(sampleCount: number?): (boolean, { string })
	local samples = sampleCount or 300
	local errors: { string } = {}
	local roundsToTest = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }

	QuestionGenerator.ResetUsedQuestions()

	for _, round in ipairs(roundsToTest) do
		for _ = 1, math.ceil(samples / #roundsToTest) do
			local question = QuestionGenerator.Generate(round)

			if question.text == "" then
				table.insert(errors, ("Round %d (%s): empty question text"):format(round, question.category))
			end

			if type(question.answer) ~= "number" or question.answer ~= question.answer then
				table.insert(
					errors,
					("Round %d (%s): answer is not a valid number (%s)"):format(
						round,
						question.category,
						tostring(question.answer)
					)
				)
			end

			if not QuestionGenerator.CheckAnswer(question, question.answer) then
				table.insert(
					errors,
					("Round %d (%s): text=%q - CheckAnswer rejected the question's own correct answer"):format(
						round,
						question.category,
						question.text
					)
				)
			end

			local expected = recomputeExpected(question)
			if expected and math.abs(expected - question.answer) > (question.tolerance + 0.001) then
				table.insert(
					errors,
					("Round %d (%s): text=%q answer=%s but independently recomputed=%s"):format(
						round,
						question.category,
						question.text,
						tostring(question.answer),
						tostring(expected)
					)
				)
			end
		end
	end

	return (#errors == 0), errors
end

return QuestionGenerator
