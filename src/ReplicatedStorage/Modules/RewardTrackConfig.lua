--[[
	RewardTrackConfig.lua

	Centralized win-based reward milestone catalog (replaces the old
	"Daily Rewards" placeholder - this is NOT a daily-login system; every
	milestone here unlocks purely from the player's lifetime competitive
	Wins total). Pure data - no claim/grant logic lives here, see
	RewardTrackSystem for that.

	Coins-only rewards are granted via ProgressionSystem.AwardCoins - the
	existing currency, nothing new. Cosmetic/title rewards reference a
	CosmeticsConfig item id and are granted via ShopSystem.GrantRewardItem,
	so a reward-track item behaves EXACTLY like a purchased one afterward
	(inventory, equip/unequip, persistence) with no separate code path.

	ASSUMPTION (documented, not stopped for): the design doc's section 13
	lists "Math Champion / Math Legend / Matharena Master" as illustrative
	title examples, but section 2's actual milestone table only assigns a
	Title to 50 wins (75 and 100 are Cosmetic and Coins+Cosmetic
	respectively) - the milestone table below follows section 2 literally,
	using section 13 only for the 50-win title's exact name.
]]

export type RewardType = "Coins" | "Cosmetic" | "CoinsAndCosmetic"

export type RewardMilestone = {
	winsRequired: number,
	rewardType: RewardType,
	coins: number?,
	itemId: string?, -- CosmeticsConfig id, present for Cosmetic/CoinsAndCosmetic
	label: string, -- short display text, e.g. "150 Coins" or "Exclusive Title"
}

local RewardTrackConfig = {}

local MILESTONES: { RewardMilestone } = {
	{ winsRequired = 1, rewardType = "Coins", coins = 50, label = "50 Coins" },
	{ winsRequired = 3, rewardType = "Coins", coins = 75, label = "75 Coins" },
	{ winsRequired = 5, rewardType = "Coins", coins = 100, label = "100 Coins" },
	{ winsRequired = 10, rewardType = "Coins", coins = 150, label = "150 Coins" },
	{ winsRequired = 15, rewardType = "Coins", coins = 200, label = "200 Coins" },
	{ winsRequired = 20, rewardType = "Coins", coins = 250, label = "250 Coins" },
	{ winsRequired = 30, rewardType = "Coins", coins = 350, label = "350 Coins" },
	{ winsRequired = 40, rewardType = "Coins", coins = 500, label = "500 Coins" },
	{ winsRequired = 50, rewardType = "Cosmetic", itemId = "title_math_champion", label = "Exclusive Title" },
	{ winsRequired = 75, rewardType = "Cosmetic", itemId = "trail_champion", label = "Exclusive Cosmetic" },
	{
		winsRequired = 100,
		rewardType = "CoinsAndCosmetic",
		coins = 1000,
		itemId = "accessory_champion_crown",
		label = "1,000 Coins + Exclusive Cosmetic",
	},
}

RewardTrackConfig.MILESTONES = MILESTONES

-- Sorted ascending by winsRequired - MILESTONES above is already in that
-- order, but callers that care about order (the UI, snapshot building)
-- should go through this rather than assume the literal table above.
function RewardTrackConfig.GetSorted(): { RewardMilestone }
	local sorted = table.clone(RewardTrackConfig.MILESTONES)
	table.sort(sorted, function(a, b)
		return a.winsRequired < b.winsRequired
	end)
	return sorted
end

return RewardTrackConfig
