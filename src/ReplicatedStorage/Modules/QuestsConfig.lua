--[[
	QuestsConfig.lua

	Slot-based repeatable quest system - "quest offerings that pop up...
	for simple rewards if accepted". Distinct from every other reward
	system in this project: not win-based (RewardTrackSystem), not
	calendar-day-based totals (DailyRewardsSystem/LifetimeRewardsConfig) -
	a quest must be explicitly ACCEPTED before its progress counts (see
	QuestsSystem.lua). Each quest's `metric` function reads an EXISTING
	profile counter - no duplicate/parallel stat tracking.

	There are three fixed SLOTS the quest box always shows:
		- Standard1 / Standard2: draw from POOLS.standard, refresh 2-5
		  minutes after being claimed (see QuestsSystem.ClaimQuest), and
		  can be manually REJECTED/refreshed for a different quest up to
		  REFRESHES_PER_DAY times per real day (see QuestsSystem.RefreshQuest).
		- Daily: draws from POOLS.daily (deliberately harder/bigger-reward
		  quests), refreshes once per real UTC day. No manual refresh.
	Each standard slot also has a small chance (challengeChance) that its
	NEXT quest, instead of coming from POOLS.standard, comes from
	POOLS.challenge - "every now and then a challenge quest come[s] and
	[is] an option" - a harder, bigger-reward quest that occasionally
	takes over a standard slot until it's claimed.
]]

export type QuestKind = "standard" | "daily" | "challenge"

export type QuestDef = {
	id: string,
	title: string,
	description: string,
	target: number,
	metric: (profile: any) -> number,
	coins: number?,
	gems: number?,
	rewardLabel: string,
}

export type SlotDef = {
	slotId: string,
	kind: QuestKind, -- the slot's BASE kind (a standard slot can still occasionally roll a challenge quest into it)
	pool: "standard" | "daily" | "challenge",
	challengeChance: number, -- 0-1, chance a reroll pulls from POOLS.challenge instead of the slot's own pool
}

local QuestsConfig = {}

local POOLS: { [string]: { QuestDef } } = {
	standard = {
		{
			id = "QuickThinker15",
			title = "Quick Thinker",
			description = "Answer 15 questions correctly (competitive or practice).",
			target = 15,
			metric = function(profile)
				return profile.statistics.correctAnswers + profile.practiceStatistics.correctAnswers
			end,
			coins = 30,
			rewardLabel = "30 Coins",
		},
		{
			id = "PracticeReps10",
			title = "Practice Makes Perfect",
			description = "Answer 10 practice questions correctly.",
			target = 10,
			metric = function(profile)
				return profile.practiceStatistics.correctAnswers
			end,
			coins = 25,
			rewardLabel = "25 Coins",
		},
		{
			id = "WinAMatch",
			title = "Champion",
			description = "Win 1 competitive match.",
			target = 1,
			metric = function(profile)
				return profile.wins
			end,
			gems = 15,
			rewardLabel = "15 Gems",
		},
	},

	-- Deliberately harder than anything in the standard pool - "the daily
	-- quest to be significantly harder" - with a correspondingly bigger
	-- payout, since it only refreshes once per day.
	daily = {
		{
			id = "DailyTripleWin",
			title = "Daily Champion",
			description = "Win 3 competitive matches today.",
			target = 3,
			metric = function(profile)
				return profile.wins
			end,
			coins = 120,
			gems = 25,
			rewardLabel = "120 Coins + 25 Gems",
		},
		{
			id = "DailyQuestionMarathon",
			title = "Daily Marathon",
			description = "Answer 40 questions correctly today (competitive or practice).",
			target = 40,
			metric = function(profile)
				return profile.statistics.correctAnswers + profile.practiceStatistics.correctAnswers
			end,
			coins = 100,
			gems = 20,
			rewardLabel = "100 Coins + 20 Gems",
		},
	},

	-- Occasional, optional, bigger swings than even the daily quest -
	-- these only ever appear by randomly taking over a standard slot on
	-- reroll (see SLOTS[].challengeChance), never guaranteed.
	challenge = {
		{
			id = "ChallengeFiveWins",
			title = "CHALLENGE: High Roller",
			description = "Win 5 competitive matches.",
			target = 5,
			metric = function(profile)
				return profile.wins
			end,
			coins = 300,
			gems = 75,
			rewardLabel = "300 Coins + 75 Gems",
		},
		{
			id = "ChallengeSeventyCorrect",
			title = "CHALLENGE: Marathon Solver",
			description = "Answer 70 questions correctly (competitive or practice).",
			target = 70,
			metric = function(profile)
				return profile.statistics.correctAnswers + profile.practiceStatistics.correctAnswers
			end,
			coins = 250,
			gems = 60,
			rewardLabel = "250 Coins + 60 Gems",
		},
	},
}

QuestsConfig.POOLS = POOLS

-- Standard slots refresh 2-5 minutes after being claimed ("refresh once
-- completed every 2-5 minutes randomly").
QuestsConfig.STANDARD_REFRESH_MIN_SECONDS = 120
QuestsConfig.STANDARD_REFRESH_MAX_SECONDS = 300

-- Chance that a standard slot's reroll pulls a challenge quest instead of
-- a normal one from POOLS.standard.
QuestsConfig.CHALLENGE_CHANCE = 0.2

local SLOTS: { SlotDef } = {
	{ slotId = "Standard1", kind = "standard", pool = "standard", challengeChance = QuestsConfig.CHALLENGE_CHANCE },
	{ slotId = "Standard2", kind = "standard", pool = "standard", challengeChance = QuestsConfig.CHALLENGE_CHANCE },
	{ slotId = "Daily", kind = "daily", pool = "daily", challengeChance = 0 },
}

QuestsConfig.SLOTS = SLOTS

function QuestsConfig.GetSlot(slotId: string): SlotDef?
	for _, slot in ipairs(SLOTS) do
		if slot.slotId == slotId then
			return slot
		end
	end
	return nil
end

--[[
	Searches every pool for a quest by id - a slot's currently-assigned
	quest can come from any pool (a standard slot may be holding a
	challenge quest right now), so this doesn't take a pool hint.
]]
function QuestsConfig.GetQuestById(id: string): QuestDef?
	for _, pool in pairs(POOLS) do
		for _, quest in ipairs(pool) do
			if quest.id == id then
				return quest
			end
		end
	end
	return nil
end

--[[
	Picks a new quest for `slotDef` - normally from the slot's own pool,
	but with `slotDef.challengeChance` probability, from POOLS.challenge
	instead. Returns the chosen QuestDef plus the EFFECTIVE kind it should
	display as (which can differ from slotDef.kind when a challenge quest
	takes over a standard slot).
]]
function QuestsConfig.RollQuestForSlot(slotDef: SlotDef): (QuestDef, QuestKind)
	if slotDef.challengeChance > 0 and math.random() < slotDef.challengeChance and #POOLS.challenge > 0 then
		local pool = POOLS.challenge
		return pool[math.random(1, #pool)], "challenge"
	end

	local pool = POOLS[slotDef.pool]
	return pool[math.random(1, #pool)], slotDef.kind
end

return QuestsConfig
