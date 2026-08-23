--[[
	DailyRewardsConfig.lua

	A genuine daily-login streak reward catalog - entirely separate from
	RewardTrackConfig.lua's win-based milestone track (that one triggers
	off lifetime Wins and is claimed via the lobby's "RewardsButton"; this
	one triggers off real calendar days and is claimed by walking into the
	Daily Rewards building - see DailyRewardsSystem.lua for the claim
	logic and DailyRewardsUIController.client.lua for the UI).

	7-day cycle: claiming on consecutive real days advances through
	DAY_TRACK in order, looping back to day 1 after day 7. Missing a day
	resets the streak back to day 1 on the next claim (see
	DailyRewardsSystem.lua for the exact day-boundary math) - "see your
	progress in bigger things and how close you are to them" means the
	whole 7-day track is always visible, not just today's single reward,
	with day 7 landing a noticeably bigger bonus (both coins AND gems) as
	the "worth coming back all week for" payoff.
]]

export type DailyRewardEntry = {
	day: number, -- 1-7, position in the cycle
	coins: number?,
	gems: number?,
	label: string, -- short display text, e.g. "50 Coins" or "200 Coins + 10 Gems"
}

local DailyRewardsConfig = {}

DailyRewardsConfig.CYCLE_LENGTH = 7

local DAY_TRACK: { DailyRewardEntry } = {
	{ day = 1, coins = 25, label = "25 Coins" },
	{ day = 2, coins = 40, label = "40 Coins" },
	{ day = 3, coins = 60, label = "60 Coins" },
	{ day = 4, coins = 80, label = "80 Coins" },
	{ day = 5, coins = 100, label = "100 Coins" },
	{ day = 6, coins = 130, label = "130 Coins" },
	{ day = 7, coins = 200, gems = 10, label = "200 Coins + 10 Gems" },
}

DailyRewardsConfig.DAY_TRACK = DAY_TRACK

function DailyRewardsConfig.GetDay(day: number): DailyRewardEntry?
	for _, entry in ipairs(DAY_TRACK) do
		if entry.day == day then
			return entry
		end
	end
	return nil
end

return DailyRewardsConfig
