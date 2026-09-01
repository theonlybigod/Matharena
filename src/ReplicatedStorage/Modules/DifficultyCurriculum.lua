--[[
	DifficultyCurriculum.lua

	The per-difficulty question curriculum: what shape of maths appears, at
	what number sizes, in each of the ten rounds of each of the five
	difficulties.

	WHY THIS REPLACES THE OLD MODEL. GameplayConfig previously ran ONE
	shared round ladder (ROUND_PLAN rounds 1-7 plus a round-8+ pool) and
	each queue tier simply picked a `startingRound` and `maxRound` into it -
	so "Easy Mode" was literally rounds 1-2 of the same sequence Master Mode
	finished. That made the five tiers slices of one curve rather than five
	curricula, which is exactly why the spread of maths did not line up with
	the difficulty names.

	Each difficulty now owns its own rounds 1-10. Round 1 of Hard is Hard's
	own round 1, not round 5 of a global ladder.

	TOTAL AND PEAK DIFFICULTY ARE NOT RAISED. Master's round 10 remains the
	ceiling of the whole game; what changes is the DISTRIBUTION beneath it,
	so each tier occupies a distinct band instead of four of them crowding
	the easy end.

	HOW A ROUND IS DESCRIBED. Every round resolves to a list of FORMS. A
	form is one shape of question (two-number addition, three-term
	subtraction, a percentage, a square root) plus the numeric ranges it
	draws from and a relative `weight` deciding how often it is picked.

	Ranges and weights are written as ANCHORS at particular rounds and
	interpolated in between, because most of the spec is of the shape
	"slowly increase from X to Y across rounds 6-10", or "raise the chance
	from 25% to 60% by round 10". Writing the anchors rather than ten
	literal tables per difficulty keeps the intent legible and puts the
	tuning in one place.

	SERVER/CLIENT. This module carries no answers, only the SHAPE and
	RANGES of questions, so it is safe in ReplicatedStorage next to
	GameplayConfig - the client needs difficulty names and descriptions for
	the Play menu. Question text and answer generation stay server-only in
	CompetitionGameplay.QuestionGenerator, which reads this to know what to
	build.
]]

local DifficultyCurriculum = {}

DifficultyCurriculum.ROUNDS_PER_DIFFICULTY = 10

-- Flat baseline seconds per question. Difficulty comes from the maths and
-- from the per-correct-answer decay, not from starting some tiers on a
-- shorter clock. Individual forms may override with `seconds` where a
-- question genuinely takes longer to READ than to solve (word problems).
DifficultyCurriculum.BASE_SECONDS = 8

export type Range = { min: number, max: number }

export type ResolvedForm = {
	form: string,
	weight: number,
	range: Range?,
	secondRange: Range?,
	terms: number?,
	allowNegativeAnswer: boolean?,
	sameDenominator: boolean?,
	maxDenominator: number?,
	powers: { number }?,
	seconds: number?,
}

--[[
	Linear interpolation between anchored values, clamped outside the anchor
	range. `anchors` is { { round = n, value = v }, ... } ascending by round.

	This is what implements every "slowly increase from X to Y" line in the
	spec exactly and reproducibly, instead of ten hand-written numbers that
	drift apart the moment a range is retuned.
]]
local function lerpAnchors(anchors: { { round: number, value: number } }, round: number): number
	if round <= anchors[1].round then
		return anchors[1].value
	end
	for i = 1, #anchors - 1 do
		local a, b = anchors[i], anchors[i + 1]
		if round >= a.round and round <= b.round then
			local t = (round - a.round) / (b.round - a.round)
			return a.value + (b.value - a.value) * t
		end
	end
	return anchors[#anchors].value
end

-- Every range in this game is an integer range.
local function lerpInt(anchors, round: number): number
	return math.floor(lerpAnchors(anchors, round) + 0.5)
end

-- Shorthand: a single anchor pair from round `fromRound` to `toRound`.
local function ramp(fromRound: number, fromValue: number, toRound: number, toValue: number)
	return { { round = fromRound, value = fromValue }, { round = toRound, value = toValue } }
end

local function flat(value: number)
	return { { round = 1, value = value } }
end

--[[
	A range whose min and max each follow their own anchor list.
	`resolveRange(spec, round)` turns it into a concrete { min, max }.
]]
local function range(minAnchors, maxAnchors)
	return { minAnchors = minAnchors, maxAnchors = maxAnchors }
end

local function resolveRange(spec, round: number): Range?
	if not spec then
		return nil
	end
	local min = lerpInt(spec.minAnchors, round)
	local max = lerpInt(spec.maxAnchors, round)
	if max < min then
		max = min
	end
	return { min = min, max = max }
end

--[[
	EASY MODE.

	Addition only to begin with, subtraction introduced at round 3, never a
	negative answer anywhere in this difficulty, and never more than two
	terms. `firstRound`/`lastRound` gate a form to part of the ladder - a
	form is simply absent outside its window rather than present at weight
	zero, so "subtraction is added at round 3" is literally what the table
	says.
]]
local EASY = {
	id = "Easy",
	name = "Easy Mode",
	-- Two-to-four words, describing the FEEL rather than the content, so the
	-- question types stay a surprise (spec).
	description = "Gentle warm-up.",
	forms = {
		{
			form = "addSub2",
			ops = { "+" },
			weight = flat(1),
			allowNegativeAnswer = false,
			-- R1: 0-10. R2: still 0-10 but skewed high ("closer to 10").
			-- R4: 7-15. R5: 10-16. R6-10: drift up to 30.
			range = range(
				{ { round = 1, value = 0 }, { round = 2, value = 3 }, { round = 4, value = 7 }, { round = 5, value = 10 }, { round = 10, value = 10 } },
				{ { round = 1, value = 10 }, { round = 2, value = 10 }, { round = 4, value = 15 }, { round = 5, value = 16 }, { round = 10, value = 30 } }
			),
		},
		{
			form = "addSub2",
			ops = { "-" },
			firstRound = 3,
			weight = flat(1),
			allowNegativeAnswer = false,
			-- R3: below 10. R5: 10-16. R6-10: up to 30.
			range = range(
				{ { round = 3, value = 1 }, { round = 5, value = 10 }, { round = 10, value = 10 } },
				{ { round = 3, value = 9 }, { round = 5, value = 16 }, { round = 10, value = 30 } }
			),
		},
	},
}

--[[
	MEDIUM MODE.

	Negative answers become possible from round 1 and stay possible for
	every addition/subtraction question from here on, in every harder
	difficulty. Three-term questions arrive at round 3 at a 25% share and
	climb to 60% by round 10 - the weights below are literal percentages,
	which is why the two-term forms fall as the three-term form rises.

	A three-term question is never a MIX of + and -, per spec; the
	generator picks one operator for the whole question.
]]
local MEDIUM = {
	id = "Medium",
	name = "Medium Mode",
	description = "Steady climb.",
	forms = {
		{
			form = "addSub2",
			ops = { "+", "-" },
			allowNegativeAnswer = true,
			-- R1: 10-30. R2: 10-40. R5-10: up to 10-60.
			range = range(
				flat(10),
				{ { round = 1, value = 30 }, { round = 2, value = 40 }, { round = 5, value = 45 }, { round = 10, value = 60 } }
			),
			-- 100% until three-term appears, then 75% -> 40%.
			weight = { { round = 1, value = 100 }, { round = 2, value = 100 }, { round = 3, value = 75 }, { round = 10, value = 40 } },
		},
		{
			form = "addSub3",
			terms = 3,
			ops = { "+", "-" },
			firstRound = 3,
			allowNegativeAnswer = true,
			-- R3: 10-20. R5-10: up to 10-35.
			range = range(
				flat(10),
				{ { round = 3, value = 20 }, { round = 5, value = 24 }, { round = 10, value = 35 } }
			),
			weight = { { round = 3, value = 25 }, { round = 10, value = 60 } },
		},
	},
}

--[[
	HARD MODE.

	Everything Medium ended on arrives immediately at round 1, plus
	four-term questions, multiplication and integer-only division. Round 2
	introduces percentages, fractions and ratios.

	Constraints held throughout, all from the spec:
		- division always divides evenly; no negative results
		- multiplication is non-negative
		- percentages move in steps of five, applied to a number capped at
		  200, and always land on a whole number
		- fraction addition/subtraction shares a denominator until round 4,
		  after which unlike denominators become possible and fraction
		  multiplication joins in
		- fraction numerators and denominators never exceed 10

	Rounds 3-10 scale everything toward roughly a 2x increase, which is
	what the ranges below reach by round 10.
]]
local HARD = {
	id = "Hard",
	name = "Hard Mode",
	description = "Real pressure.",
	forms = {
		{
			form = "addSub2",
			ops = { "+", "-" },
			allowNegativeAnswer = true,
			range = range(flat(10), ramp(1, 60, 10, 120)),
			weight = ramp(1, 30, 10, 20),
		},
		{
			form = "addSub3",
			terms = 3,
			ops = { "+", "-" },
			allowNegativeAnswer = true,
			range = range(flat(10), ramp(1, 40, 10, 80)),
			weight = flat(18),
		},
		{
			form = "addSub4",
			terms = 4,
			ops = { "+", "-" },
			allowNegativeAnswer = true,
			range = range(flat(10), ramp(1, 30, 10, 60)),
			weight = flat(14),
		},
		{
			form = "mulDiv",
			-- Multiplication operands 4-10 at round 1, doubling by round 10.
			range = range(ramp(1, 4, 10, 4), ramp(1, 10, 10, 20)),
			-- Divisor range; the dividend is built from divisor * quotient so
			-- the answer is always a whole number.
			secondRange = range(flat(2), ramp(1, 10, 10, 20)),
			weight = flat(18),
		},
		{
			form = "percent",
			firstRound = 2,
			-- Percentage itself, in steps of five: 5%-50% early, up to 95%.
			range = range(flat(5), ramp(2, 50, 10, 95)),
			-- The number the percentage is applied to, hard-capped at 200.
			secondRange = range(flat(20), ramp(2, 100, 10, 200)),
			weight = flat(12),
		},
		{
			form = "fractionAddSub",
			firstRound = 2,
			-- Same denominator until round 4, then unlike denominators allowed.
			sameDenominator = true,
			sameDenominatorUntilRound = 4,
			maxDenominator = 10,
			terms = 2,
			weight = flat(10),
		},
		{
			form = "fractionMul",
			firstRound = 4,
			maxDenominator = 10,
			weight = flat(4),
		},
		{
			form = "ratio",
			firstRound = 2,
			range = range(flat(2), ramp(2, 12, 10, 24)),
			weight = flat(4),
			seconds = 9, -- a ratio question is longer to read than to solve
		},
	},
}

--[[
	EXPERT MODE.

	Carries Hard's whole cycle forward at roughly 20% harder and 100%
	larger numbers, and adds exponents and roots.

	Round 1 is deliberately narrow: squares only, bases 0-10, and square
	roots of perfect squares up to 100. From round 2 the powers open up to
	cubes and fourth powers, with per-power ceilings the spec fixes at
	round 10 - fourth powers never past base 6, cubes never past 8, squares
	up to 20. Square roots climb to 2000, still perfect squares only.

	Everything stays a whole number. No decimals anywhere.
]]
local EXPERT = {
	id = "Expert",
	name = "Expert Mode",
	description = "Serious work.",
	forms = {
		{
			form = "addSub2",
			ops = { "+", "-" },
			allowNegativeAnswer = true,
			range = range(ramp(1, 100, 10, 100), ramp(1, 250, 10, 400)),
			weight = flat(16),
		},
		{
			form = "addSub3",
			terms = 3,
			ops = { "+", "-" },
			allowNegativeAnswer = true,
			range = range(flat(100), ramp(1, 200, 10, 300)),
			weight = flat(12),
		},
		{
			form = "addSub4",
			terms = 4,
			ops = { "+", "-" },
			allowNegativeAnswer = true,
			range = range(flat(100), ramp(1, 175, 10, 250)),
			weight = flat(10),
		},
		{
			form = "mulDiv",
			range = range(flat(4), ramp(1, 20, 10, 40)),
			secondRange = range(flat(2), ramp(1, 20, 10, 40)),
			weight = flat(14),
		},
		{
			form = "percent",
			range = range(flat(5), flat(95)),
			secondRange = range(flat(20), flat(200)),
			weight = flat(8),
		},
		{
			form = "fractionAddSub",
			sameDenominator = false,
			maxDenominator = 10,
			terms = 2,
			weight = flat(8),
		},
		{
			form = "fractionMul",
			maxDenominator = 10,
			weight = flat(6),
		},
		{
			-- Round 1: squares only, base 0-10.
			form = "power",
			powers = { 2 },
			powersByRound = {
				[1] = { 2 },
				-- From round 2, cubes and fourth powers join.
				[2] = { 2, 3, 4 },
			},
			-- Per-power base ceilings at round 10, ramped from round 2.
			baseCeilings = {
				[2] = ramp(1, 10, 10, 20),
				[3] = ramp(2, 5, 10, 8),
				[4] = ramp(2, 3, 10, 6),
			},
			weight = flat(12),
		},
		{
			form = "root",
			-- Perfect squares only. Root value 0-10 at round 1 (so squares up
			-- to 100), climbing so the radicand reaches 2000 by round 10
			-- (44^2 = 1936, the largest perfect square under 2000).
			range = range(flat(2), ramp(1, 10, 10, 44)),
			weight = flat(10),
		},
		{
			form = "higherRoot",
			firstRound = 3,
			-- Cube roots and fourth roots, kept small so they stay exact.
			range = range(flat(2), ramp(3, 6, 10, 10)),
			powers = { 3, 4 },
			weight = flat(6),
		},
		{
			form = "powerOps",
			firstRound = 2,
			-- Operations BETWEEN exponents: multiplying powers, powers of
			-- fractions, and similar combined forms.
			range = range(flat(2), ramp(2, 6, 10, 12)),
			powers = { 2, 3 },
			weight = flat(8),
			seconds = 9,
		},
	},
}

--[[
	MASTER MODE.

	The same jump above Expert that every other step makes. No new SHAPES of
	question - everything here already exists in Expert - but the numbers,
	the combining, and the time pressure are all turned up so that a
	competent grade-12 student finds it genuinely hard inside the clock.

	Two things carry the difficulty rather than new maths:

		1. COMBINING. Weights shift decisively toward the multi-term and
		   exponent-operation forms, so a typical Master question is several
		   operations deep rather than one.
		2. WORD PROBLEMS. Master is the only difficulty that uses them. They
		   are the same underlying arithmetic, wrapped so the player has to
		   extract the operation before solving - which is where the
		   multitasking pressure the spec asks for actually comes from. They
		   carry a longer `seconds` because reading is part of the cost, and
		   they start rare and become common.

	Round 1 sits deliberately just above Expert's round 10; the ramp then
	moves quickly rather than gently.
]]
local MASTER = {
	id = "Master",
	name = "Master Mode",
	description = "Brutal.",
	forms = {
		{
			form = "addSub2",
			ops = { "+", "-" },
			allowNegativeAnswer = true,
			range = range(flat(100), ramp(1, 450, 10, 900)),
			weight = flat(8),
		},
		{
			form = "addSub3",
			terms = 3,
			ops = { "+", "-" },
			allowNegativeAnswer = true,
			range = range(flat(100), ramp(1, 320, 10, 650)),
			weight = flat(10),
		},
		{
			form = "addSub4",
			terms = 4,
			ops = { "+", "-" },
			allowNegativeAnswer = true,
			range = range(flat(100), ramp(1, 260, 10, 500)),
			weight = flat(12),
		},
		{
			form = "mulDiv",
			range = range(flat(6), ramp(1, 45, 10, 90)),
			secondRange = range(flat(3), ramp(1, 45, 10, 90)),
			weight = flat(12),
		},
		{
			form = "percent",
			range = range(flat(5), flat(95)),
			secondRange = range(flat(40), flat(200)),
			weight = flat(8),
		},
		{
			form = "fractionAddSub",
			sameDenominator = false,
			maxDenominator = 10,
			terms = 3,
			weight = flat(8),
		},
		{
			form = "fractionMul",
			maxDenominator = 10,
			weight = flat(8),
		},
		{
			form = "power",
			powers = { 2, 3, 4 },
			baseCeilings = {
				[2] = ramp(1, 20, 10, 30),
				[3] = ramp(1, 8, 10, 12),
				[4] = ramp(1, 6, 10, 8),
			},
			weight = flat(10),
		},
		{
			form = "root",
			range = range(flat(4), ramp(1, 44, 10, 70)),
			weight = flat(8),
		},
		{
			form = "higherRoot",
			range = range(flat(2), ramp(1, 10, 10, 14)),
			powers = { 3, 4 },
			weight = flat(6),
		},
		{
			form = "powerOps",
			range = range(flat(2), ramp(1, 12, 10, 20)),
			powers = { 2, 3, 4 },
			weight = ramp(1, 10, 10, 16),
			seconds = 10,
		},
		{
			form = "wordProblem",
			firstRound = 2,
			-- Starts rare, becomes a defining feature of late Master.
			weight = ramp(2, 6, 10, 22),
			-- Reading is part of the cost; the spec fixes this at 10 seconds.
			seconds = 10,
		},
	},
}

DifficultyCurriculum.DIFFICULTIES = { EASY, MEDIUM, HARD, EXPERT, MASTER }

DifficultyCurriculum.BY_ID = {}
for _, def in ipairs(DifficultyCurriculum.DIFFICULTIES) do
	DifficultyCurriculum.BY_ID[def.id] = def
end

--[[
	Returns the difficulty definition for `id`, falling back to Easy for an
	unknown/stale id - the same defensive convention every other GetX-by-id
	in this project uses.
]]
function DifficultyCurriculum.Get(id: string?)
	return (id and DifficultyCurriculum.BY_ID[id]) or EASY
end

--[[
	Resolves `difficultyId` + `round` into the concrete list of forms in
	play, with every range, weight and ceiling already interpolated.

	This is the single function the question generator calls. Rounds past
	ROUNDS_PER_DIFFICULTY clamp to the last round rather than continuing to
	scale - a long elimination on Easy Mode must never drift into Hard Mode
	numbers, which is the same guarantee the old AdvanceRoundForTier
	ceiling provided.

	MEMOISED. The result is a pure function of (difficulty, round) - every
	input is an anchor table interpolated at a fixed point, with no
	randomness - so there are only 50 possible answers in the whole game.
	Resolving all twelve of Master's forms took ~0.007ms and allocated a
	dozen tables on EVERY question; caching makes repeat lookups a single
	table index and removes that allocation churn from the match loop
	entirely.

	The cached tables are treated as READ-ONLY by callers. PickForm returns
	one of them directly, and Forms.lua only ever reads from it.
]]
local roundFormsCache: { [string]: { ResolvedForm } } = {}

function DifficultyCurriculum.GetRoundForms(difficultyId: string?, round: number): { ResolvedForm }
	local def = DifficultyCurriculum.Get(difficultyId)
	local r = math.clamp(round, 1, DifficultyCurriculum.ROUNDS_PER_DIFFICULTY)

	local cacheKey = def.id .. ":" .. r
	local cached = roundFormsCache[cacheKey]
	if cached then
		return cached
	end

	local resolved: { ResolvedForm } = {}
	for _, spec in ipairs(def.forms) do
		local firstRound = spec.firstRound or 1
		local lastRound = spec.lastRound or DifficultyCurriculum.ROUNDS_PER_DIFFICULTY
		if r >= firstRound and r <= lastRound then
			local weight = lerpAnchors(spec.weight, r)
			if weight > 0 then
				-- Powers available this round, and their per-power base ceiling.
				local powers = spec.powers
				if spec.powersByRound then
					for anchorRound = r, 1, -1 do
						if spec.powersByRound[anchorRound] then
							powers = spec.powersByRound[anchorRound]
							break
						end
					end
				end

				local baseCeilings = nil
				if spec.baseCeilings then
					baseCeilings = {}
					for power, anchors in pairs(spec.baseCeilings) do
						baseCeilings[power] = lerpInt(anchors, r)
					end
				end

				table.insert(resolved, {
					form = spec.form,
					weight = weight,
					ops = spec.ops,
					terms = spec.terms,
					range = resolveRange(spec.range, r),
					secondRange = resolveRange(spec.secondRange, r),
					allowNegativeAnswer = spec.allowNegativeAnswer,
					-- "same denominator until round N" collapses to a plain
					-- boolean once the round is known.
					sameDenominator = if spec.sameDenominatorUntilRound
						then r < spec.sameDenominatorUntilRound
						else spec.sameDenominator,
					maxDenominator = spec.maxDenominator,
					powers = powers,
					baseCeilings = baseCeilings,
					seconds = spec.seconds,
				})
			end
		end
	end

	roundFormsCache[cacheKey] = resolved
	return resolved
end

--[[
	Total weight per resolved round, cached alongside the forms so PickForm
	does not re-sum the list on every question.
]]
local roundWeightCache: { [string]: number } = {}

--[[
	Picks one form for this round, weighted. Returns nil only if a round
	somehow resolved to no forms at all, which would be a curriculum bug -
	callers should treat nil as "fall back to the simplest form" rather
	than erroring a live match.
]]
function DifficultyCurriculum.PickForm(difficultyId: string?, round: number): ResolvedForm?
	local forms = DifficultyCurriculum.GetRoundForms(difficultyId, round)
	if #forms == 0 then
		return nil
	end

	local def = DifficultyCurriculum.Get(difficultyId)
	local cacheKey = def.id .. ":" .. math.clamp(round, 1, DifficultyCurriculum.ROUNDS_PER_DIFFICULTY)

	local total = roundWeightCache[cacheKey]
	if not total then
		total = 0
		for _, form in ipairs(forms) do
			total += form.weight
		end
		roundWeightCache[cacheKey] = total
	end

	local roll = math.random() * total
	local running = 0
	for _, form in ipairs(forms) do
		running += form.weight
		if roll <= running then
			return form
		end
	end
	return forms[#forms]
end

return DifficultyCurriculum
