--[[
	RewardTrackSystem

	Server-authoritative win-based reward track. Replaces the old "Daily
	Rewards" placeholder - this is NOT a daily-login system; milestones
	unlock purely from the player's lifetime competitive Wins total
	(profile.wins, the exact same value leaderstats.Wins already shows -
	no duplicate counter). Milestones are defined in RewardTrackConfig;
	every claim is fully re-validated here, never trusted from the client.

	Persistence: claimed milestones live on the same DataSystem profile as
	everything else (profile.claimedRewardMilestones, keyed by
	tostring(winsRequired)) and save/load through the existing autosave/
	on-leave/DataStore path - no separate store, no duplicate Wins/Coins.

	Cosmetic/title rewards are granted via ShopSystem.GrantRewardItem,
	which marks the item owned exactly like a purchase would (no
	currency involved) - the item then behaves identically to a purchased
	one (inventory, equip/unequip, persistence) with no separate code path.

	Duplicate-claim safety: ClaimMilestone re-checks the player's ACTUAL
	profile.wins (never the client's say-so) and sets the claimed flag
	BEFORE doing any further (non-yielding) work, so a rapid double-click,
	a second concurrent claim attempt, or a client replaying an old
	request all see "AlreadyClaimed" on every attempt after the first.
	Because DataSystem saves the whole profile together, a player who
	disconnects mid-claim either has the flag set (and got their reward)
	or doesn't (and can claim normally next time) - there is no
	"claimed but reward not granted" gap, since both happen in the same
	synchronous call before any yielding.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RewardTrackConfig = require(ReplicatedStorage.Modules.RewardTrackConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)

local DataSystem = require(ServerScriptService.DataSystem)
local ProgressionSystem = require(ServerScriptService.ProgressionSystem)
local ShopSystem = require(ServerScriptService.ShopSystem)
local RemoteThrottle = require(ServerScriptService.RemoteThrottle)

local RewardTrackSystem = {}

export type MilestoneStatus = "Locked" | "Available" | "Claimed"

export type MilestoneSnapshotEntry = {
	winsRequired: number,
	label: string,
	status: MilestoneStatus,
}

export type TrackSnapshot = {
	wins: number,
	milestones: { MilestoneSnapshotEntry },
}

local rewardMilestoneUnlockedEvent = RemoteEvents.Get("RewardMilestoneUnlocked")
local getRewardTrackSnapshotFunction = RemoteFunctions.Get("GetRewardTrackSnapshot")
local claimRewardMilestoneFunction = RemoteFunctions.Get("ClaimRewardMilestone")

local function findMilestone(winsRequired: number)
	for _, milestone in ipairs(RewardTrackConfig.MILESTONES) do
		if milestone.winsRequired == winsRequired then
			return milestone
		end
	end
	return nil
end

local function getStatus(profile: any, milestone): MilestoneStatus
	if profile.claimedRewardMilestones[tostring(milestone.winsRequired)] then
		return "Claimed"
	elseif profile.wins >= milestone.winsRequired then
		return "Available"
	else
		return "Locked"
	end
end

--[[
	Builds the full track snapshot for the Rewards UI: current wins, and
	every milestone's status. Returns nil only if the player has no
	loaded profile (shouldn't normally happen for a connected player).
]]
function RewardTrackSystem.BuildSnapshot(player: Player): TrackSnapshot?
	local profile = DataSystem.GetProfile(player)
	if not profile then
		return nil
	end

	local milestones = {}
	for _, milestone in ipairs(RewardTrackConfig.GetSorted()) do
		table.insert(milestones, {
			winsRequired = milestone.winsRequired,
			label = milestone.label,
			status = getStatus(profile, milestone),
		})
	end

	return { wins = profile.wins, milestones = milestones }
end

--[[
	Checks whether the player's CURRENT wins total has reached any
	milestone(s) that aren't claimed yet, and fires a client notification
	for each so the UI can show a "NEW REWARD UNLOCKED!" popup. Does NOT
	grant anything automatically - claiming is always an explicit player
	action (ClaimMilestone). Call this right after a win is awarded.
]]
function RewardTrackSystem.CheckForNewlyUnlocked(player: Player)
	local profile = DataSystem.GetProfile(player)
	if not profile then
		return
	end

	for _, milestone in ipairs(RewardTrackConfig.MILESTONES) do
		if profile.wins == milestone.winsRequired and not profile.claimedRewardMilestones[tostring(milestone.winsRequired)] then
			rewardMilestoneUnlockedEvent:FireClient(player, {
				winsRequired = milestone.winsRequired,
				label = milestone.label,
			})
		end
	end
end

--[[
	Claims a milestone's reward for `player`. Returns true on success, or
	(false, reason) - reason is one of "UnknownMilestone", "NoProfile",
	"AlreadyClaimed", or "NotEnoughWins". See the module doc comment for
	why this can't be double-claimed.
]]
function RewardTrackSystem.ClaimMilestone(player: Player, winsRequired: number): (boolean, string?)
	local milestone = findMilestone(winsRequired)
	if not milestone then
		return false, "UnknownMilestone"
	end

	local profile = DataSystem.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end

	local claimKey = tostring(winsRequired)
	if profile.claimedRewardMilestones[claimKey] then
		return false, "AlreadyClaimed"
	end

	if profile.wins < winsRequired then
		return false, "NotEnoughWins"
	end

	-- Mark claimed FIRST, before any further (non-yielding) work below, so
	-- a second concurrent claim attempt for this exact milestone sees
	-- AlreadyClaimed immediately rather than racing the grant.
	profile.claimedRewardMilestones[claimKey] = true

	if milestone.coins then
		ProgressionSystem.AwardCoins(player, milestone.coins)
	end
	if milestone.itemId then
		ShopSystem.GrantRewardItem(player, milestone.itemId)
	end

	return true
end

function RewardTrackSystem.Init()
	getRewardTrackSnapshotFunction.OnServerInvoke = function(player: Player)
		return RewardTrackSystem.BuildSnapshot(player) or { wins = 0, milestones = {} }
	end

	claimRewardMilestoneFunction.OnServerInvoke = function(player: Player, winsRequired: unknown)
		if typeof(winsRequired) ~= "number" then
			return { success = false, reason = "InvalidRequest" }
		end
		if not RemoteThrottle.Check(player, "ClaimRewardMilestone", 0.5) then
			return { success = false, reason = "TooManyRequests" }
		end
		local ok, reason = RewardTrackSystem.ClaimMilestone(player, winsRequired)
		return { success = ok, reason = reason }
	end

	print("[RewardTrackSystem] Initialized")
end

return RewardTrackSystem
