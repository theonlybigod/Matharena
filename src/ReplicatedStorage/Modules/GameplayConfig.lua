--[[
	GameplayConfig.lua

	Centralized constants for the question-answering gameplay, and the
	documented network contract for its RemoteEvents.
]]

export type Difficulty = "Easy" | "Medium" | "Hard" | "Expert"

local GameplayConfig = {}

-- Difficulty LABEL escalates as the round number increases (spelling-bee
-- style): round 1 = first time through all contestants, round 2 = second
-- pass, etc. This is purely a display/metadata label sent alongside a
-- turn now (used to be what picked the timer too) - see GetTimerSeconds
-- below for the actual timer math, which progresses smoothly round-by-
-- round instead of jumping at these tier boundaries.
GameplayConfig.DIFFICULTY_BY_ROUND = {
	{ upTo = 2, difficulty = "Easy" },
	{ upTo = 4, difficulty = "Medium" },
	{ upTo = 6, difficulty = "Hard" },
	{ upTo = math.huge, difficulty = "Expert" },
}

function GameplayConfig.GetDifficultyForRound(round: number): Difficulty
	for _, tier in ipairs(GameplayConfig.DIFFICULTY_BY_ROUND) do
		if round <= tier.upTo then
			return tier.difficulty :: Difficulty
		end
	end
	return "Expert"
end

--[[
	Timer math ("difficulty should directly determine both question
	complexity AND an appropriate amount of time - Easy should be a LOT
	easier/shorter than Master, and every tier in between should feel
	meaningfully different"):

	TIMER_ANCHORS pins a base time to each of the five QUEUE_TIERS'
	startingRound (1/3/5/7/8 - Easy/Medium/Hard/Expert/Master), with the
	gap between anchors deliberately large (18s -> 6.5s end to end) so the
	TIER is always the dominant factor. Rounds BETWEEN two anchors (e.g. a
	match that started at round 1 and has since progressed to round 2)
	interpolate linearly between them. Rounds past the last anchor (8+,
	the "Master" rotating pool) decay only very slightly further per round
	(POST_MASTER_DECAY_PER_ROUND) - a very long Master session gets
	slightly tighter over time, but never craters.

	CATEGORY_TIME_BONUS_SECONDS is a SECONDARY, intentionally SMALL
	adjustment on top (max +1.5s) reflecting how much longer a given
	category takes to read/solve - small enough that it can never flip two
	different tiers' relative ordering (previously, before this fix, a
	flat 0.35s/round decay combined with up to +4s category bonuses meant
	an easy-to-mid Medium-Mode question could receive the SAME time as, or
	even MORE time than, a Master-Mode question - exactly the bug this
	redesign fixes).
]]
GameplayConfig.TIMER_ANCHORS = {
	{ round = 1, seconds = 18 }, -- Easy Mode start: very simple, very generous time
	{ round = 3, seconds = 13 }, -- Medium Mode start
	{ round = 5, seconds = 10 }, -- Hard Mode start
	{ round = 7, seconds = 8 }, -- Expert Mode start
	{ round = 8, seconds = 6.5 }, -- Master Mode start (round 8+ rotating pool)
}
GameplayConfig.MIN_TIMER_SECONDS = 5
GameplayConfig.POST_MASTER_DECAY_PER_ROUND = 0.05 -- very slow additional tightening for a long-running Master session

GameplayConfig.CATEGORY_TIME_BONUS_SECONDS = {
	BasicArithmetic = 0,
	MixedOperations = 0.5,
	OrderOfOperations = 0.5,
	Percentages = 0.5,
	Fractions = 0.5,
	SquareRoots = 0.5,
	Decimals = 0.5,
	Exponents = 1,
	Algebra = 1,
	Geometry = 1.5, -- longest to read/solve (shape + two measurements + a formula, sometimes two-step)
}

--[[
	Linearly interpolates the base (pre-category-bonus) time for `round`
	across GameplayConfig.TIMER_ANCHORS. See the doc comment above.
]]
function GameplayConfig.GetBaseTimerSeconds(round: number): number
	local anchors = GameplayConfig.TIMER_ANCHORS

	if round <= anchors[1].round then
		return anchors[1].seconds
	end

	for i = 1, #anchors - 1 do
		local a, b = anchors[i], anchors[i + 1]
		if round >= a.round and round <= b.round then
			local t = (round - a.round) / (b.round - a.round)
			return a.seconds + (b.seconds - a.seconds) * t
		end
	end

	-- Past the last anchor (round 8+): a very slow additional decay, floored.
	local last = anchors[#anchors]
	local extraRounds = round - last.round
	return math.max(GameplayConfig.MIN_TIMER_SECONDS, last.seconds - extraRounds * GameplayConfig.POST_MASTER_DECAY_PER_ROUND)
end

function GameplayConfig.GetTimerSeconds(round: number, category: string): number
	local base = GameplayConfig.GetBaseTimerSeconds(round)
	local bonus = GameplayConfig.CATEGORY_TIME_BONUS_SECONDS[category] or 0
	return math.max(GameplayConfig.MIN_TIMER_SECONDS, base + bonus)
end

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

--[[
	Round -> question-category plan (Message 7). Rounds 1-7 each have one
	fixed category (rounds 1-2 share "BasicArithmetic" but at different
	number-size tiers). Round 8 and beyond draw randomly from a rotating
	pool of the remaining advanced categories every turn.

	This table only describes WHICH CATEGORY to use - it carries no answer
	data, so it's safe to keep shared/replicated. The actual question text
	and answer generation lives server-only in CompetitionGameplay's
	QuestionGenerator.
]]
export type RoundPlan = {
	category: string,
	tier: string?,
}

GameplayConfig.ROUND_PLAN = {
	[1] = { category = "BasicArithmetic", tier = "single" },
	[2] = { category = "BasicArithmetic", tier = "two" },
	[3] = { category = "MixedOperations" },
	[4] = { category = "Percentages" },
	[5] = { category = "Fractions" },
	[6] = { category = "OrderOfOperations" },
	[7] = { category = "SquareRoots" },
} :: { [number]: RoundPlan }

-- Round 8+ rotating pool (decided: Decimals/Exponents/Geometry fold in
-- alongside Algebra here rather than getting their own dedicated rounds).
GameplayConfig.ROUND_8_PLUS_CATEGORIES = { "Algebra", "Decimals", "Exponents", "Geometry" }

function GameplayConfig.GetRoundPlan(round: number): RoundPlan
	local plan = GameplayConfig.ROUND_PLAN[round]
	if plan then
		return plan
	end

	local pool = GameplayConfig.ROUND_8_PLUS_CATEGORIES
	return { category = pool[math.random(1, #pool)] }
end

GameplayConfig.RESOLVE_DISPLAY_SECONDS = 2.5 -- pause after an answer before the next turn begins

--[[
	Queue difficulty tiers ("what type of match you want", chosen from the
	Play button's tier-select popup - see LobbyUIController.client.lua).
	Each tier maps to a STARTING round in the EXISTING round-based
	category/difficulty progression above (ROUND_PLAN / DIFFICULTY_BY_ROUND)
	- picking a tier doesn't create a second difficulty system, it just
	picks where in the current one a match begins. The match still
	progresses harder from there exactly as it always has (a match still
	gets harder every round; it just starts at round 1 instead of, say,
	round 6).

	Message 32 ("scrap that - five difficulties, plain measurement-style
	names like easy/medium/hard, with a LITTLE novelty"): replaces the
	previous six flavor-first names (Addition Academy, Arithmetic
	Apprentice, Mixed Operations Mayhem, Percentage Pursuit, Order of
	Operations Odyssey, Expert Equation Gauntlet) with five
	<StraightforwardDifficultyWord> + "Mode" names - immediately readable
	as a plain difficulty ladder (Easy -> Medium -> Hard -> Expert ->
	Master), with "Mode" as the one consistent touch of novelty rather
	than each tier inventing its own unrelated theme. `description` still
	names the actual math content each tier starts at, same as before.

	Each tier is also its own separate matchmaking queue (see
	MatchSystem.lua) - players choosing different tiers wait in different
	pools rather than being grouped together, though only one match runs on
	the arena at a time (whichever tier fills up first launches next).
]]
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
-- startingRound/maxRound are retained only for MatchSystem's existing tier
-- bookkeeping; they no longer drive question selection. Each difficulty now
-- runs its own rounds 1-10 via DifficultyCurriculum.
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
	return GameplayConfig.QUEUE_TIERS[1] -- fall back to the easiest tier for any invalid/stale id
end

function GameplayConfig.GetRoundCeilingForTier(tierId: number?): number?
	if tierId == nil then
		return GameplayConfig.QUEUE_TIERS[1].maxRound
	end
	return GameplayConfig.GetQueueTier(tierId).maxRound
end

function GameplayConfig.AdvanceRoundForTier(round: number, tierId: number?): number
	local ceiling = GameplayConfig.GetRoundCeilingForTier(tierId)
	if ceiling and round >= ceiling then
		return ceiling
	end
	return round + 1
end

--[[
	Network contract. RemoteEvents are created on demand via the shared
	RemoteEvents factory (ReplicatedStorage.Remotes.RemoteEvents), same
	pattern as MatchSystem's remotes.

	"TurnStarted" (server -> all clients)
		payload: {
			playerUserId: number,
			playerName: string,
			platformIndex: number?,
			questionText: string,
			category: string,
			difficulty: Difficulty,
			timerSeconds: number,
			round: number,
			playersRemaining: number,
		} | nil
		-- nil means "no active turn" (round ended/hasn't started): clients
		-- should hide question/timer UI and release any camera lock.

	"TurnResolved" (server -> all clients)
		payload: {
			playerUserId: number,
			correct: boolean,
			timedOut: boolean,
			correctAnswer: number,
		}

	"RosterUpdated" (server -> all clients, Message 8)
		payload: {
			{ userId: number, name: string, rank: string, platformIndex: number?, alive: boolean },
			...
		}
		-- The full list of this match's contestants (including already-
		-- eliminated ones, marked alive=false) for the Match UI's live
		-- leaderboard/roster panel. Fires at round start and after every
		-- elimination. An empty list means no active round.

	"SubmitAnswer" (client -> server, fire-and-forget via FireServer)
		payload: number | string
		-- The player's answer; server parses with tonumber() and ignores
		-- anything that doesn't parse. The server only ever accepts a
		-- submission from whichever player it currently considers active,
		-- and only once per turn (first valid submission or timeout wins,
		-- whichever the server processes first). There is no direct
		-- response to the sender - the result arrives via "TurnResolved"
		-- to all clients.
]]

return GameplayConfig
