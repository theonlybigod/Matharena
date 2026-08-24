--[[
	LifetimeRewardsConfig.lua

	Genuine LIFETIME progress ACHIEVEMENTS - entirely distinct from
	RewardTrackSystem's win-based track (lobby "RewardsButton") and from
	DailyRewardsSystem's calendar-day streak. Only ever viewable/claimable
	from inside the Daily Rewards building's panel ("the open rewards
	section in the daily rewards shop to have some lifetime rewards open
	up, their progress on them") - a slower-building, bigger-payoff set of
	tracks that lives alongside (not instead of) that building's daily
	streak.

	Deliberately spans several DIFFERENT categories rather than being
	solely correct-answer-count-based: games played, win streaks, practice
	reps, real playtime, and daily-login participation, each with its own
	`metric` reading an EXISTING profile counter (same pattern as
	QuestsConfig) - no duplicate/parallel stat tracking. Each milestone has
	a globally-unique `id` (used as the claim key in
	profile.claimedLifetimeMilestones) rather than reusing a numeric
	threshold, since two different categories can otherwise land on the
	same number.

	See LifetimeRewardsSystem.lua for the claim logic and
	DailyRewardsUIController.client.lua for the UI (which shows a
	permanent "COMPLETE" badge in place of a claimed milestone's Claim
	button, rather than removing/hiding the row).
]]

export type LifetimeMilestone = {
	id: string,
	category: string, -- display group heading, e.g. "Correct Answers", "Time Played"
	target: number,
	metric: (profile: any) -> number,
	label: string,
	coins: number?,
	gems: number?,
}

local LifetimeRewardsConfig = {}

local function correctAnswersMetric(profile)
	return profile.statistics.correctAnswers
end

local function gamesPlayedMetric(profile)
	return profile.statistics.gamesPlayed
end

local function longestStreakMetric(profile)
	return profile.statistics.longestStreak
end

local function practiceRepsMetric(profile)
	return profile.practiceStatistics.correctAnswers
end

local function playTimeHoursMetric(profile)
	return (profile.totalPlayTimeSeconds or 0) / 3600
end

local function dailyLoginsMetric(profile)
	return profile.dailyRewards.totalClaims
end

local MILESTONES: { LifetimeMilestone } = {
	-- Correct Answers - kept, but now just ONE category among several.
	{ id = "CorrectAnswers25", category = "Correct Answers", target = 25, metric = correctAnswersMetric, label = "25 Lifetime Correct Answers", coins = 50 },
	{ id = "CorrectAnswers100", category = "Correct Answers", target = 100, metric = correctAnswersMetric, label = "100 Lifetime Correct Answers", coins = 120 },
	{ id = "CorrectAnswers250", category = "Correct Answers", target = 250, metric = correctAnswersMetric, label = "250 Lifetime Correct Answers", coins = 250, gems = 10 },
	{ id = "CorrectAnswers500", category = "Correct Answers", target = 500, metric = correctAnswersMetric, label = "500 Lifetime Correct Answers", coins = 400, gems = 25 },
	{ id = "CorrectAnswers1000", category = "Correct Answers", target = 1000, metric = correctAnswersMetric, label = "1000 Lifetime Correct Answers", coins = 750, gems = 60 },

	-- Games Played - participation, regardless of outcome.
	{ id = "GamesPlayed10", category = "Games Played", target = 10, metric = gamesPlayedMetric, label = "Play 10 Matches", coins = 60 },
	{ id = "GamesPlayed50", category = "Games Played", target = 50, metric = gamesPlayedMetric, label = "Play 50 Matches", coins = 200, gems = 15 },
	{ id = "GamesPlayed200", category = "Games Played", target = 200, metric = gamesPlayedMetric, label = "Play 200 Matches", coins = 600, gems = 50 },

	-- Win Streak - skill/consistency, not just raw totals.
	{ id = "Streak5", category = "Win Streaks", target = 5, metric = longestStreakMetric, label = "Reach a 5-Match Win Streak", coins = 100, gems = 15 },
	{ id = "Streak10", category = "Win Streaks", target = 10, metric = longestStreakMetric, label = "Reach a 10-Match Win Streak", coins = 300, gems = 40 },

	-- Practice Mode reps - rewards players who use Practice to improve.
	{ id = "PracticeReps50", category = "Practice", target = 50, metric = practiceRepsMetric, label = "Answer 50 Practice Questions Correctly", coins = 80 },
	{ id = "PracticeReps250", category = "Practice", target = 250, metric = practiceRepsMetric, label = "Answer 250 Practice Questions Correctly", coins = 300, gems = 20 },

	-- Time Played - a genuinely different kind of progression that
	-- rewards sticking around, not performance.
	{ id = "PlayTime1h", category = "Time Played", target = 1, metric = playTimeHoursMetric, label = "Play for 1 Hour Total", coins = 60 },
	{ id = "PlayTime5h", category = "Time Played", target = 5, metric = playTimeHoursMetric, label = "Play for 5 Hours Total", coins = 250, gems = 20 },
	{ id = "PlayTime20h", category = "Time Played", target = 20, metric = playTimeHoursMetric, label = "Play for 20 Hours Total", coins = 700, gems = 60 },

	-- Daily Login participation - rewards returning day after day, on top
	-- of (not instead of) the Daily Rewards streak track itself.
	{ id = "DailyLogins7", category = "Daily Logins", target = 7, metric = dailyLoginsMetric, label = "Claim 7 Daily Rewards", coins = 90 },
	{ id = "DailyLogins30", category = "Daily Logins", target = 30, metric = dailyLoginsMetric, label = "Claim 30 Daily Rewards", coins = 350, gems = 30 },
}

LifetimeRewardsConfig.MILESTONES = MILESTONES

-- Display order for category groups in the UI - anything not listed here
-- (shouldn't happen) sorts after these, alphabetically.
LifetimeRewardsConfig.CATEGORY_ORDER = {
	"Correct Answers",
	"Games Played",
	"Win Streaks",
	"Practice",
	"Time Played",
	"Daily Logins",
}

--[[
	Returns every milestone sorted by category (in CATEGORY_ORDER), then by
	target within each category - what the UI iterates to render grouped
	sections rather than one long flat list.
]]
function LifetimeRewardsConfig.GetSorted(): { LifetimeMilestone }
	local sorted = table.clone(MILESTONES)
	local function categoryIndex(category: string): number
		for i, c in ipairs(LifetimeRewardsConfig.CATEGORY_ORDER) do
			if c == category then
				return i
			end
		end
		return #LifetimeRewardsConfig.CATEGORY_ORDER + 1
	end
	table.sort(sorted, function(a, b)
		local ai, bi = categoryIndex(a.category), categoryIndex(b.category)
		if ai ~= bi then
			return ai < bi
		end
		return a.target < b.target
	end)
	return sorted
end

return LifetimeRewardsConfig
