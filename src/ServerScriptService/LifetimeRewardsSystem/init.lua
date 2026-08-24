--[[
	LifetimeRewardsSystem

	Server-authoritative lifetime-progress reward track spanning several
	achievement categories (LifetimeRewardsConfig) - entirely separate
	from RewardTrackSystem (win-based, claimed via the lobby's quick-access
	RewardsButton) and DailyRewardsSystem (calendar-day streak). Only ever
	viewed/claimed from inside the Daily Rewards building's panel
	(DailyRewardsUIController.client.lua).

	Same duplicate-claim safety pattern as RewardTrackSystem.ClaimMilestone
	- the claimed flag is set BEFORE any further (non-yielding) work, so a
	rapid double-click or a replayed request sees AlreadyClaimed on every
	attempt after the first.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LifetimeRewardsConfig = require(ReplicatedStorage.Modules.LifetimeRewardsConfig)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)

local DataSystem = require(ServerScriptService.DataSystem)
local ProgressionSystem = require(ServerScriptService.ProgressionSystem)
local RemoteThrottle = require(ServerScriptService.RemoteThrottle)

local LifetimeRewardsSystem = {}

export type MilestoneStatus = "Locked" | "Available" | "Claimed"

local getLifetimeRewardsSnapshotFunction = RemoteFunctions.Get("GetLifetimeRewardsSnapshot")
local claimLifetimeMilestoneFunction = RemoteFunctions.Get("ClaimLifetimeMilestone")

local function findMilestone(id: string)
	for _, milestone in ipairs(LifetimeRewardsConfig.MILESTONES) do
		if milestone.id == id then
			return milestone
		end
	end
	return nil
end

local function getStatus(profile: any, milestone): MilestoneStatus
	if profile.claimedLifetimeMilestones[milestone.id] then
		return "Claimed"
	elseif milestone.metric(profile) >= milestone.target then
		return "Available"
	else
		return "Locked"
	end
end

--[[
	Builds the full snapshot for the Daily Rewards building's "Lifetime
	Rewards" section: every milestone's category/status/current progress
	toward its own target (correct answers, games played, win streak,
	practice reps, time played, or daily logins). Returns nil only if the
	player has no loaded profile.
]]
function LifetimeRewardsSystem.BuildSnapshot(player: Player)
	local profile = DataSystem.GetProfile(player)
	if not profile then
		return nil
	end

	local milestones = {}
	for _, milestone in ipairs(LifetimeRewardsConfig.GetSorted()) do
		table.insert(milestones, {
			id = milestone.id,
			category = milestone.category,
			target = milestone.target,
			progress = milestone.metric(profile),
			label = milestone.label,
			status = getStatus(profile, milestone),
		})
	end

	return { milestones = milestones }
end

--[[
	Claims a lifetime milestone's reward (by id) for `player`. Returns true
	on success, or (false, reason) - reason is one of "UnknownMilestone",
	"NoProfile", "AlreadyClaimed", or "NotEnoughProgress".
]]
function LifetimeRewardsSystem.ClaimMilestone(player: Player, id: string): (boolean, string?)
	local milestone = findMilestone(id)
	if not milestone then
		return false, "UnknownMilestone"
	end

	local profile = DataSystem.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end

	if profile.claimedLifetimeMilestones[id] then
		return false, "AlreadyClaimed"
	end

	if milestone.metric(profile) < milestone.target then
		return false, "NotEnoughProgress"
	end

	-- Mark claimed FIRST, before any further (non-yielding) work below -
	-- same duplicate-claim safety pattern as RewardTrackSystem.
	profile.claimedLifetimeMilestones[id] = true

	if milestone.coins then
		ProgressionSystem.AwardCoins(player, milestone.coins)
	end
	if milestone.gems then
		ProgressionSystem.AwardGems(player, milestone.gems)
	end

	return true
end

function LifetimeRewardsSystem.Init()
	getLifetimeRewardsSnapshotFunction.OnServerInvoke = function(player: Player)
		return LifetimeRewardsSystem.BuildSnapshot(player) or { milestones = {} }
	end

	claimLifetimeMilestoneFunction.OnServerInvoke = function(player: Player, id: unknown)
		if typeof(id) ~= "string" then
			return { success = false, reason = "InvalidRequest" }
		end
		if not RemoteThrottle.Check(player, "ClaimLifetimeMilestone", 0.5) then
			return { success = false, reason = "TooManyRequests" }
		end
		local ok, reason = LifetimeRewardsSystem.ClaimMilestone(player, id)
		return { success = ok, reason = reason }
	end

	print("[LifetimeRewardsSystem] Initialized")
end

return LifetimeRewardsSystem
