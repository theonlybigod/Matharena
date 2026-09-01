--[[
	GameplayConfig.lua

	Constants for the question-answering gameplay, and the queue-tier table
	the Play and Practice menus read.

	WHAT THIS MODULE NO LONGER OWNS. It used to also decide WHICH question
	appeared and HOW LONG it was worth, through a single shared round ladder
	(ROUND_PLAN rounds 1-7, plus a round-8+ pool) and a per-round timer
	anchor curve. Both were built for a model where all five difficulty
	tiers were slices of one curve, selected by `startingRound`.

	That model is gone. Each difficulty now owns its own rounds 1-10 in
	DifficultyCurriculum, which is the single source of truth for question
	shape, number ranges, and per-question base time. The retired members
	(ROUND_PLAN, ROUND_8_PLUS_CATEGORIES, TIMER_ANCHORS,
	CATEGORY_TIME_BONUS_SECONDS, DIFFICULTY_BY_ROUND, GetRoundPlan,
	GetTimerSeconds, GetBaseTimerSeconds, GetDifficultyForRound,
	AdvanceRoundForTier, GetRoundCeilingForTier) were verified to have zero
	remaining callers before removal.

	What stays here is the part that is genuinely about gameplay pacing
	rather than question content: the per-turn timer decay, the pause
	between turns, and the queue tiers.
]]

local GameplayConfig = {}

--[[
	PER-TURN TIMER DECAY.

	From TIMER_DECAY_START_ROUND onward, every CORRECT answer shortens the
	clock for the NEXT player by DECAY_PER_CORRECT, compounding: three
	correct answers in a row leave the fourth player on
	0.9 * 0.9 * 0.9 = 72.9% of the base time, not 70%.

	A WRONG answer resets the multiplier all the way back to 1 - not part of
	the way, and not to whatever it was when the round began. The next
	player gets the full base time again.

	The streak is deliberately NOT reset at a round boundary. It is a
	property of the run of correct answers, and a round ends on a wrong
	answer anyway - which resets it through the normal path.

	Before TIMER_DECAY_START_ROUND the multiplier is always 1, so rounds 1-4
	of every difficulty play at the flat base time.
]]
GameplayConfig.TIMER_DECAY_START_ROUND = 5
GameplayConfig.TIMER_DECAY_PER_CORRECT = 0.10

-- Floor, so a very long correct streak can never drive the clock to
-- something unanswerable. At 10% compounding this is reached after about
-- 16 consecutive correct answers on an 8-second base.
GameplayConfig.MIN_TURN_SECONDS = 1.5

--[[
	The time this turn gets.

	`baseSeconds` is the question's own base - DifficultyCurriculum.BASE_SECONDS
	for most forms, or a form's `seconds` override where reading is part of
	the cost (ratios, exponent operations, Master word problems).

	`correctStreak` is how many correct answers have been given in a row
	since the last wrong one, across the whole match.
]]
function GameplayConfig.GetTurnSeconds(baseSeconds: number, correctStreak: number, round: number): number
	if round < GameplayConfig.TIMER_DECAY_START_ROUND or correctStreak <= 0 then
		return baseSeconds
	end
	local multiplier = (1 - GameplayConfig.TIMER_DECAY_PER_CORRECT) ^ correctStreak
	return math.max(GameplayConfig.MIN_TURN_SECONDS, baseSeconds * multiplier)
end

GameplayConfig.RESOLVE_DISPLAY_SECONDS = 2.5 -- pause after an answer before the next turn begins

export type QueueTier = {
	id: number,
	name: string,
	description: string,
	startingRound: number,
	maxRound: number?,
}

-- Descriptions are deliberately vague and two-to-four words: they convey
-- the FEEL of the step up, not the maths involved, so the question types
-- stay a surprise and players discover the change themselves. Kept in sync
-- with DifficultyCurriculum, which is the source of truth for what each
-- difficulty actually contains.
--
-- startingRound/maxRound are retained only because MatchSystem and
-- PlaceTeleportSystem still read the tier records; they no longer drive
-- question selection. Each difficulty runs its own rounds 1-10 via
-- DifficultyCurriculum.
GameplayConfig.QUEUE_TIERS = {
	{ id = 1, name = "Easy Mode", description = "Gentle warm-up.", startingRound = 1, maxRound = 2 },
	{ id = 2, name = "Medium Mode", description = "Steady climb.", startingRound = 3, maxRound = 4 },
	{ id = 3, name = "Hard Mode", description = "Real pressure.", startingRound = 5, maxRound = 6 },
	{ id = 4, name = "Expert Mode", description = "Serious work.", startingRound = 7, maxRound = 7 },
	{ id = 5, name = "Master Mode", description = "Brutal.", startingRound = 8, maxRound = nil },
} :: { QueueTier }

function GameplayConfig.GetQueueTier(tierId: number): QueueTier
	for _, tier in ipairs(GameplayConfig.QUEUE_TIERS) do
		if tier.id == tierId then
			return tier
		end
	end
	return GameplayConfig.QUEUE_TIERS[1]
end

return GameplayConfig
