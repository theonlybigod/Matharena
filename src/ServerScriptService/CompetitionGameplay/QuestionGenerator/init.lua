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
local DifficultyCurriculum = require(ReplicatedStorage.Modules.DifficultyCurriculum)

local Forms = require(script.Forms)

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
	seconds: number?,
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
	Requests a question for `difficultyId` at `round`.

	The curriculum (DifficultyCurriculum) decides which FORM is drawn and at
	what number ranges; Forms.lua turns that into text and an answer. This
	replaced the old GameplayConfig.GetRoundPlan lookup, which mapped a round
	to a single fixed CATEGORY on one shared ladder - that model could not
	express "three-term questions appear 25% of the time at round 3, rising
	to 60% by round 10", which is most of what the difficulty spec asks for.

	Retries on a duplicate question text up to MAX_RETRIES before allowing
	the repeat, exactly as before - a small possibility space (Easy round 1
	is only 121 distinct sums) must not spin forever.

	`category` on the returned question is the form id, which is what the
	client displays and what the self-test groups by.
]]
function QuestionGenerator.Generate(difficultyId: string?, round: number): Question
	local raw, form

	for _ = 1, MAX_RETRIES do
		form = DifficultyCurriculum.PickForm(difficultyId, round)
		if not form then
			break
		end
		raw = Forms.Build(form)
		if raw and not usedQuestionTexts[raw.text] then
			break
		end
	end

	-- Curriculum bug or an unknown form id: fall back to the simplest
	-- possible question rather than erroring out a live match.
	if not raw then
		form = { form = "addSub2", terms = 2, ops = { "+" }, range = { min = 1, max = 9 } }
		raw = Forms.Build(form)
	end

	usedQuestionTexts[raw.text] = true

	return {
		category = form.form,
		round = round,
		text = raw.text,
		answer = raw.answer,
		tolerance = raw.tolerance or 0,
		-- Per-form time override (ratios, exponent operations, word problems);
		-- nil means the flat DifficultyCurriculum.BASE_SECONDS applies.
		seconds = form.seconds,
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
		elseif d.shape == "compoundRectangleArea" then
			return (d.lengthA * d.widthA) + (d.lengthB * d.widthB)
		else
			return (d.base * d.height) / 2
		end
	end

	return nil
end

--[[
	Internal validation/regression helper (not called automatically at
	runtime). Walks EVERY difficulty across all ten of its rounds, checking:
		- question text is non-empty
		- the answer is a valid, finite WHOLE number (nothing in the redesign
		  may return a fraction or decimal)
		- CheckAnswer accepts the question's own correct answer
		- Easy never produces a negative answer
	Returns (true, {}) on success, or (false, errorMessages) otherwise.
]]
function QuestionGenerator.RunSelfTest(samplesPerRound: number?): (boolean, { string })
	local samples = samplesPerRound or 100
	local errors: { string } = {}

	for _, def in ipairs(DifficultyCurriculum.DIFFICULTIES) do
		for round = 1, DifficultyCurriculum.ROUNDS_PER_DIFFICULTY do
			QuestionGenerator.ResetUsedQuestions()
			for _ = 1, samples do
				local ok, question = pcall(QuestionGenerator.Generate, def.id, round)
				if not ok then
					table.insert(errors, ("%s round %d: generator threw - %s"):format(def.id, round, tostring(question)))
					break
				end

				if question.text == "" then
					table.insert(errors, ("%s round %d (%s): empty question text"):format(def.id, round, question.category))
				end

				if type(question.answer) ~= "number" or question.answer ~= question.answer then
					table.insert(errors, ("%s round %d (%s): answer is not a valid number"):format(def.id, round, question.category))
				elseif question.answer % 1 ~= 0 then
					table.insert(
						errors,
						("%s round %d (%s): non-integer answer %s from %q"):format(
							def.id,
							round,
							question.category,
							tostring(question.answer),
							question.text
						)
					)
				end

				if not QuestionGenerator.CheckAnswer(question, question.answer) then
					table.insert(
						errors,
						("%s round %d (%s): CheckAnswer rejected its own correct answer"):format(def.id, round, question.category)
					)
				end

				if def.id == "Easy" and question.answer < 0 then
					table.insert(errors, ("Easy round %d: negative answer %q = %d"):format(round, question.text, question.answer))
				end
			end
		end
	end

	return (#errors == 0), errors
end

return QuestionGenerator
