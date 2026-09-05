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

	--[[
		Cosmetic reward ladder (rarity rebuild): every CosmeticsConfig category
		now has exactly 5 reward-only items, one per rarity (Common ->
		Boundless), each granted at its own win-count milestone below. Every
		winsRequired value in this entire table (including the Coins-only ones
		above) MUST be globally unique - findMilestone()/getStatus() above key
		purely by winsRequired, so two milestones sharing a number would
		collide: only the first would ever be found or claimable, and claiming
		it would incorrectly flag the other as claimed too (same
		claimedRewardMilestones[tostring(winsRequired)] key). The values below
		were chosen specifically to avoid any such collision, including with
		the 8 Coins-only entries above. Three of these (Trail@75, Accessory@100,
		Title@50) existed before this rebuild and are UNCHANGED here on purpose
		- only their backing CosmeticsConfig item definitions were restyled.

		Trail
	]]
	{ winsRequired = 8, rewardType = "Cosmetic", itemId = "trail_rookie_spark", label = "Rookie Spark Trail" },
	{ winsRequired = 22, rewardType = "Cosmetic", itemId = "trail_rising_star", label = "Rising Star Trail" },
	{ winsRequired = 45, rewardType = "Cosmetic", itemId = "trail_comet_tail", label = "Comet Tail Trail" },
	{ winsRequired = 75, rewardType = "Cosmetic", itemId = "trail_champion", label = "Exclusive Cosmetic" },
	{ winsRequired = 150, rewardType = "Cosmetic", itemId = "trail_celestial_aurora", label = "Celestial Aurora Trail" },

	-- Accessory
	{ winsRequired = 9, rewardType = "Cosmetic", itemId = "accessory_trainee_badge", label = "Trainee Badge" },
	{ winsRequired = 24, rewardType = "Cosmetic", itemId = "accessory_bronze_medal_charm", label = "Bronze Medal Charm" },
	{ winsRequired = 47, rewardType = "Cosmetic", itemId = "accessory_silver_medal_charm", label = "Silver Medal Charm" },
	{ winsRequired = 80, rewardType = "Cosmetic", itemId = "accessory_platinum_medal_charm", label = "Platinum Medal Charm" },
	{
		winsRequired = 100,
		rewardType = "CoinsAndCosmetic",
		coins = 1000,
		itemId = "accessory_champion_crown",
		label = "1,000 Coins + Exclusive Cosmetic",
	},

	-- NameColor
	{ winsRequired = 11, rewardType = "Cosmetic", itemId = "namecolor_bronze_name", label = "Bronze Name" },
	{ winsRequired = 26, rewardType = "Cosmetic", itemId = "namecolor_silver_name", label = "Silver Name" },
	{ winsRequired = 49, rewardType = "Cosmetic", itemId = "namecolor_sapphire_name", label = "Sapphire Name" },
	{ winsRequired = 85, rewardType = "Cosmetic", itemId = "namecolor_diamond_name", label = "Diamond Name" },
	{ winsRequired = 155, rewardType = "Cosmetic", itemId = "namecolor_champion_name", label = "Champion's Name" },

	-- VictoryAnimation
	{ winsRequired = 12, rewardType = "Cosmetic", itemId = "victory_rookie_bow", label = "Rookie's Bow" },
	{ winsRequired = 27, rewardType = "Cosmetic", itemId = "victory_rising_applause", label = "Rising Applause" },
	{ winsRequired = 51, rewardType = "Cosmetic", itemId = "victory_champions_roar", label = "Champion's Roar" },
	{ winsRequired = 90, rewardType = "Cosmetic", itemId = "victory_aura_burst", label = "Victory Aura Burst" },
	{ winsRequired = 165, rewardType = "Cosmetic", itemId = "victory_legends_never_fade", label = "Legends Never Fade" },

	-- QuestionTheme
	{ winsRequired = 13, rewardType = "Cosmetic", itemId = "theme_scholars", label = "Scholar's Theme" },
	{ winsRequired = 28, rewardType = "Cosmetic", itemId = "theme_mathlete", label = "Mathlete's Theme" },
	{ winsRequired = 53, rewardType = "Cosmetic", itemId = "theme_grandmaster", label = "Grandmaster's Theme" },
	{ winsRequired = 95, rewardType = "Cosmetic", itemId = "theme_champions", label = "Champion's Theme" },
	{ winsRequired = 170, rewardType = "Cosmetic", itemId = "theme_legends", label = "Legend's Theme" },

	-- Title
	{ winsRequired = 14, rewardType = "Cosmetic", itemId = "title_rookie_champion", label = "Exclusive Title" },
	{ winsRequired = 29, rewardType = "Cosmetic", itemId = "title_rising_star", label = "Exclusive Title" },
	{ winsRequired = 42, rewardType = "Cosmetic", itemId = "title_tournament_veteran", label = "Exclusive Title" },
	{ winsRequired = 50, rewardType = "Cosmetic", itemId = "title_math_champion", label = "Exclusive Title" },
	{ winsRequired = 175, rewardType = "Cosmetic", itemId = "title_math_legend", label = "Exclusive Title" },
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
