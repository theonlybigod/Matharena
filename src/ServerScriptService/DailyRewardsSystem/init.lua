--[[
	DailyRewardsSystem

	A genuine daily-login streak reward system - entirely separate from
	RewardTrackSystem (that one is win-based/lifetime-milestone; this one
	is real-calendar-day-based, the actual "Daily Rewards" the building's
	name promises). Claimed exclusively via the Daily Rewards building's
	in-world terminal (DailyRewardsUIController.client.lua) - it has no
	lobby bottom-bar button of its own; the lobby's "RewardsButton" belongs
	entirely to RewardTrackSystem now (see that system's own doc comment).

	Day-boundary math: `dayNumber(unixTime)` buckets a Unix timestamp into
	a UTC calendar day (math.floor(unixTime / 86400)). Claiming on the
	SAME UTC day as the last claim is rejected (AlreadyClaimedToday).
	Claiming on the very NEXT UTC day continues the streak (advances to
	the next DailyRewardsConfig.DAY_TRACK entry, wrapping 7 -> 1). Claiming
	after skipping one or more days resets the streak back to day 1 -
	consistent with a normal daily-login-streak design, and simple to
	reason about without timezone-of-day edge cases (a UTC-day boundary,
	not "24 hours since last claim", so the exact reset moment is the same
	for every player regardless of when in the day they usually play).

	Persistence: profile.dailyRewards (DataSystem.lua) - lastClaimUnix,
	streakDay, totalClaims - saves/loads through the existing autosave/
	on-leave/DataStore path, no separate store.

	Duplicate-claim safety: same pattern as RewardTrackSystem.ClaimMilestone
	- the profile is mutated (lastClaimUnix/streakDay/totalClaims all set)
	BEFORE any further non-yielding work, so a rapid double-click or a
	replayed request sees AlreadyClaimedToday on every attempt after the
	first.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DailyRewardsConfig = require(ReplicatedStorage.Modules.DailyRewardsConfig)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)

local DataSystem = require(ServerScriptService.DataSystem)
local ProgressionSystem = require(ServerScriptService.ProgressionSystem)
local RemoteThrottle = require(ServerScriptService.RemoteThrottle)

local DailyRewardsSystem = {}

local SECONDS_PER_DAY = 86400

local getDailyRewardSnapshotFunction = RemoteFunctions.Get("GetDailyRewardSnapshot")
local claimDailyRewardFunction = RemoteFunctions.Get("ClaimDailyReward")

local function dayNumber(unixTime: number): number
	return math.floor(unixTime / SECONDS_PER_DAY)
end

--[[
	Builds the full snapshot for the Daily Rewards UI: whether today's
	reward is still claimable, the current streak day, seconds until the
	next UTC day boundary (for a "come back in..." countdown), the whole
	7-day track (so "see your progress in bigger things" is always
	visible, not just today's single reward), and lifetime total claims.
]]
function DailyRewardsSystem.BuildSnapshot(player: Player)
	local profile = DataSystem.GetProfile(player)
	if not profile then
		return nil
	end

	local state = profile.dailyRewards
	local now = os.time()
	local todayNumber = dayNumber(now)
	local lastClaimDayNumber = if state.lastClaimUnix > 0 then dayNumber(state.lastClaimUnix) else nil

	local canClaimToday = lastClaimDayNumber ~= todayNumber
	-- Streak continues (rather than resetting to day 1) only if the last
	-- claim was yesterday, UTC - anything older (or never claimed) resets.
	local streakContinues = lastClaimDayNumber == todayNumber - 1
	local nextClaimDay = if not canClaimToday then state.streakDay
		elseif streakContinues then (state.streakDay % DailyRewardsConfig.CYCLE_LENGTH) + 1
		else 1

	local track = {}
	for _, entry in ipairs(DailyRewardsConfig.DAY_TRACK) do
		table.insert(track, {
			day = entry.day,
			label = entry.label,
			isToday = canClaimToday and entry.day == nextClaimDay,
			isPastCurrentStreak = not canClaimToday and entry.day <= state.streakDay,
		})
	end

	local secondsUntilNextDay = ((todayNumber + 1) * SECONDS_PER_DAY) - now

	return {
		canClaimToday = canClaimToday,
		currentStreakDay = state.streakDay,
		nextClaimDay = nextClaimDay,
		secondsUntilNextDay = secondsUntilNextDay,
		totalClaims = state.totalClaims,
		track = track,
	}
end

--[[
	Claims today's daily reward for `player`. Returns true on success, or
	(false, reason) - reason is one of "NoProfile" or "AlreadyClaimedToday".
]]
function DailyRewardsSystem.ClaimDaily(player: Player): (boolean, string?)
	local profile = DataSystem.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end

	local state = profile.dailyRewards
	local now = os.time()
	local todayNumber = dayNumber(now)
	local lastClaimDayNumber = if state.lastClaimUnix > 0 then dayNumber(state.lastClaimUnix) else nil

	if lastClaimDayNumber == todayNumber then
		return false, "AlreadyClaimedToday"
	end

	local streakContinues = lastClaimDayNumber == todayNumber - 1
	local claimDay = if streakContinues then (state.streakDay % DailyRewardsConfig.CYCLE_LENGTH) + 1 else 1

	-- Mutate FIRST (see module doc comment on duplicate-claim safety),
	-- before the (non-yielding) Award* calls below.
	state.lastClaimUnix = now
	state.streakDay = claimDay
	state.totalClaims += 1

	local entry = DailyRewardsConfig.GetDay(claimDay)
	if entry then
		if entry.coins then
			ProgressionSystem.AwardCoins(player, entry.coins)
		end
		if entry.gems then
			ProgressionSystem.AwardGems(player, entry.gems)
		end
	end

	return true
end

function DailyRewardsSystem.Init()
	getDailyRewardSnapshotFunction.OnServerInvoke = function(player: Player)
		return DailyRewardsSystem.BuildSnapshot(player)
	end

	claimDailyRewardFunction.OnServerInvoke = function(player: Player)
		if not RemoteThrottle.Check(player, "ClaimDailyReward", 1) then
			return { success = false, reason = "TooManyRequests" }
		end
		local ok, reason = DailyRewardsSystem.ClaimDaily(player)
		return { success = ok, reason = reason }
	end

	print("[DailyRewardsSystem] Initialized")
end

return DailyRewardsSystem
