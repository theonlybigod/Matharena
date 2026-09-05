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
	after skipping one or more days resets the streak back to day 1.

	Persistence: profile.dailyRewards (DataSystem.lua) - lastClaimUnix,
	streakDay, totalClaims, and a capped claim `history` log - saves/loads
	through the existing autosave/on-leave/DataStore path, no separate
	store.

	Claim history is deliberately kept SHORT ("keep the claim history
	pretty short... maybe one week back at most, nothing more than that")
	- MAX_HISTORY_ENTRIES caps it at 7, since there's at most one real
	claim per day.

	Duplicate-claim safety: same pattern as RewardTrackSystem.ClaimMilestone
	- the profile is mutated (lastClaimUnix/streakDay/totalClaims all set)
	BEFORE any further non-yielding work, so a rapid double-click or a
	replayed request sees AlreadyClaimedToday on every attempt after the
	first.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local DailyRewardsConfig = require(ReplicatedStorage.Modules.DailyRewardsConfig)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)

local DataSystem = require(ServerScriptService.DataSystem)
local ProgressionSystem = require(ServerScriptService.ProgressionSystem)
local RemoteThrottle = require(ServerScriptService.RemoteThrottle)

local DailyRewardsSystem = {}

local SECONDS_PER_DAY = 86400
local MAX_HISTORY_ENTRIES = 7 -- keep history "pretty short" - about a week back, since there's at most one claim per real day

local getDailyRewardSnapshotFunction = RemoteFunctions.Get("GetDailyRewardSnapshot")
local claimDailyRewardFunction = RemoteFunctions.Get("ClaimDailyReward")

local function dayNumber(unixTime: number): number
	return math.floor(unixTime / SECONDS_PER_DAY)
end

--[[
	Builds the full snapshot for the Daily Rewards UI: whether today's
	reward is still claimable, the current streak day, seconds until the
	next UTC day boundary (for a "come back in..." countdown), the whole
	7-day track (a rolling window starting at today, not a fixed
	Day1..Day7 layout - "see your progress in bigger things"), lifetime
	total claims, and the capped claim history (most-recent-first, for
	"scroll back to further days you've had").
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

	-- "Collected" days THIS pass through the 7-day ring: if the player has
	-- already claimed today, every day up to and including streakDay is
	-- done. If they haven't claimed yet today but the streak is continuing
	-- from a previous day, every day BEFORE nextClaimDay is already
	-- collected. A fresh/reset streak (nextClaimDay==1 with nothing
	-- claimed yet) correctly shows nothing as collected.
	local collectedThreshold = if not canClaimToday then state.streakDay
		elseif streakContinues then nextClaimDay - 1
		else 0

	-- The "next seven days" view the client renders, REORDERED to start at
	-- today/nextClaimDay rather than always showing the fixed Day1..Day7
	-- layout regardless of where the player actually is in the cycle.
	local track = {}
	for offset = 0, DailyRewardsConfig.CYCLE_LENGTH - 1 do
		local day = ((nextClaimDay - 1 + offset) % DailyRewardsConfig.CYCLE_LENGTH) + 1
		local entry = DailyRewardsConfig.GetDay(day)
		if entry then
			table.insert(track, {
				day = entry.day,
				label = entry.label,
				offsetFromToday = offset, -- 0 = today/next claim, 1 = tomorrow, etc.
				isToday = canClaimToday and offset == 0,
				-- "Collected" this pass: either today's slot but already claimed,
				-- or an earlier day in the ring while the streak is continuing.
				isCollected = (offset == 0 and not canClaimToday)
					or (offset > 0 and day <= collectedThreshold and streakContinues),
			})
		end
	end

	local secondsUntilNextDay = ((todayNumber + 1) * SECONDS_PER_DAY) - now

	return {
		canClaimToday = canClaimToday,
		currentStreakDay = state.streakDay,
		nextClaimDay = nextClaimDay,
		secondsUntilNextDay = secondsUntilNextDay,
		totalClaims = state.totalClaims,
		track = track,
		-- Most-recent-first, for the "scroll back to further days you've
		-- had" history view - capped at MAX_HISTORY_ENTRIES (about a week).
		history = (function()
			local reversed = {}
			for i = #state.history, 1, -1 do
				table.insert(reversed, state.history[i])
			end
			return reversed
		end)(),
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
		-- Append to the scroll-back history log, capped so a very long-
		-- lived profile doesn't grow this unboundedly in DataStore and so
		-- the history view stays "pretty short" (about a week back).
		table.insert(state.history, { unixTime = now, day = claimDay, label = entry.label })
		if #state.history > MAX_HISTORY_ENTRIES then
			table.remove(state.history, 1)
		end

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

	--[[
		FLOOR TOUCH-TO-CLAIM (BuildVersion 24): "run over the day to collect
		the reward" - BuildingInteriors.FurnishRewards lays seven
		"StreakDayFloorPad" parts directly in the walking path, each carrying
		a StreakDay attribute (1-7, the day's FIXED position in the 7-day
		cycle - not an "offset from today", since the pads are static world
		geometry laid out once, while each player's own current day rolls
		independently). Touching one only claims if that pad's day is THIS
		player's actual next claimable day - two players in the same room can
		be on different days of their own streaks, so touching pad #5 must not
		claim day 5 for a player who is actually only on day 3 of their own
		cycle. ClaimDaily/BuildSnapshot above already contain the real
		day-boundary logic; this only decides WHETHER to call them, never
		reimplements the streak math itself.

		A short per-player debounce guards against a Touched storm (multiple
		body parts crossing the same thin pad within one footstep can fire
		Touched more than once) - harmless either way since ClaimDaily is
		already idempotent (a second call the same day just returns
		"AlreadyClaimedToday"), but there is no reason to re-run the snapshot
		build and profile lookup for every redundant touch.
	]]
	local lastTouchAttempt: { [Player]: number } = {}
	local TOUCH_DEBOUNCE_SECONDS = 1.5

	local function tryClaimFromPad(player: Player, day: number)
		local now = os.clock()
		if lastTouchAttempt[player] and now - lastTouchAttempt[player] < TOUCH_DEBOUNCE_SECONDS then
			return
		end
		lastTouchAttempt[player] = now

		local snapshot = DailyRewardsSystem.BuildSnapshot(player)
		if not snapshot or not snapshot.canClaimToday or snapshot.nextClaimDay ~= day then
			return
		end
		DailyRewardsSystem.ClaimDaily(player)
	end

	local function wirePad(part: BasePart)
		local day = part:GetAttribute("StreakDay")
		if typeof(day) ~= "number" then
			return
		end
		part.Touched:Connect(function(hit: BasePart)
			local character = hit.Parent
			local player = character and Players:GetPlayerFromCharacter(character)
			if player then
				tryClaimFromPad(player, day)
			end
		end)
	end

	for _, part in ipairs(CollectionService:GetTagged("StreakDayFloorPad")) do
		if part:IsA("BasePart") then
			wirePad(part)
		end
	end
	CollectionService:GetInstanceAddedSignal("StreakDayFloorPad"):Connect(function(part)
		if part:IsA("BasePart") then
			wirePad(part)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastTouchAttempt[player] = nil
	end)

	print("[DailyRewardsSystem] Initialized")
end

return DailyRewardsSystem
