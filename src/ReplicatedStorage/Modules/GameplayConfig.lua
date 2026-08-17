--[[
	GameplayConfig.lua

	Centralized constants for the question-answering gameplay, and the
	documented network contract for its RemoteEvents.
]]

export type Difficulty = "Easy" | "Medium" | "Hard" | "Expert"

local GameplayConfig = {}

GameplayConfig.TIMER_SECONDS = {
	Easy = 10,
	Medium = 8,
	Hard = 6,
	Expert = 5,
}

-- Difficulty escalates as the round number increases (spelling-bee style):
-- round 1 = first time through all contestants, round 2 = second pass, etc.
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
