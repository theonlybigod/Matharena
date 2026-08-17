--[[
	CosmeticsConfig.lua

	Centralized, stable-ID catalog of every purchasable cosmetic in
	MathArena's shop (Message 10). Pure data - no purchase/ownership/equip
	logic lives here (see ServerScriptService/ShopSystem for that). New
	cosmetics are added here only; nothing else needs to change to add one
	- the shop UI and ShopSystem both iterate this table generically by
	category rather than referencing individual items by name.

	Categories are "equip slots" - a player may have at most one item
	equipped per category at a time (see ShopSystem.EquipItem).

	ASSUMPTION (documented, not stopped for - a low-risk content choice):
	the design doc's flat item list is read as categories with variants:
	"Trails" -> Classic/Fire/Lightning/Rainbow, "Victory animations" ->
	Confetti/Fireworks/Dance. "Name colors"/"Question themes"/"Titles"
	didn't specify which colors/themes/titles, so a small starting set is
	defined below - easy to extend later since this table is the only
	place that needs to change.

	SCOPE NOTE (Message 10): this module and ShopSystem implement full
	ownership/purchase/equip tracking, server-authoritative and ready for
	a future message to build on. Actually RENDERING the equipped
	cosmetic's effect in the world (a real trail/halo particle, playing a
	victory dance animation, recoloring a nameplate, reskinning the
	question panel, showing a title next to a player's name) is
	intentionally NOT implemented here - that's a separate "presentation"
	layer that can read a player's equipped cosmetics (already tracked,
	see ShopSystem) without any changes to this config or the shop system
	itself. This keeps Message 10 scoped to the shop/economy system itself,
	per its own instructions ("do not build unrelated features"). The
	shop UI's "Preview" is this file's description + previewColor swatch,
	not a live in-world preview.
]]

export type CurrencyType = "Coins" | "Gems"

export type CosmeticItem = {
	id: string,
	category: string,
	displayName: string,
	description: string,
	currency: CurrencyType,
	price: number,
	previewColor: Color3, -- swatch shown in the shop UI in place of a real world effect (see SCOPE NOTE above)
}

local CosmeticsConfig = {}

-- Ordered list of equip-slot categories, in the order shown as shop tabs.
CosmeticsConfig.CATEGORIES = {
	"Trail",
	"Accessory",
	"NameColor",
	"VictoryAnimation",
	"QuestionTheme",
	"Title",
}

CosmeticsConfig.CATEGORY_DISPLAY_NAMES = {
	Trail = "Trails",
	Accessory = "Accessories",
	NameColor = "Name Colors",
	VictoryAnimation = "Victory Animations",
	QuestionTheme = "Question Themes",
	Title = "Titles",
}

-- Keyed by stable id. GetItemsByCategory below sorts by id for a
-- deterministic display order - insertion order here doesn't matter.
local ITEMS: { [string]: CosmeticItem } = {
	-- ===== Trail =====
	trail_classic = {
		id = "trail_classic",
		category = "Trail",
		displayName = "Classic Trail",
		description = "A clean, simple trail in MathArena's brand color.",
		currency = "Coins",
		price = 100,
		previewColor = Color3.fromRGB(30, 140, 255),
	},
	trail_fire = {
		id = "trail_fire",
		category = "Trail",
		displayName = "Fire Trail",
		description = "A blazing orange-red trail that follows every step.",
		currency = "Coins",
		price = 250,
		previewColor = Color3.fromRGB(255, 90, 20),
	},
	trail_lightning = {
		id = "trail_lightning",
		category = "Trail",
		displayName = "Lightning Trail",
		description = "A crackling electric-blue trail with a sharp glow.",
		currency = "Coins",
		price = 250,
		previewColor = Color3.fromRGB(140, 210, 255),
	},
	trail_rainbow = {
		id = "trail_rainbow",
		category = "Trail",
		displayName = "Rainbow Trail",
		description = "A shifting, full-spectrum trail - the flashiest option.",
		currency = "Gems",
		price = 8,
		previewColor = Color3.fromRGB(255, 120, 255),
	},

	-- ===== Accessory =====
	accessory_halo = {
		id = "accessory_halo",
		category = "Accessory",
		displayName = "Halo",
		description = "A softly glowing ring that hovers above your head.",
		currency = "Gems",
		price = 12,
		previewColor = Color3.fromRGB(255, 245, 190),
	},

	-- ===== NameColor =====
	namecolor_crimson = {
		id = "namecolor_crimson",
		category = "NameColor",
		displayName = "Crimson Name",
		description = "Recolors your displayed name a deep crimson red.",
		currency = "Coins",
		price = 75,
		previewColor = Color3.fromRGB(200, 40, 40),
	},
	namecolor_azure = {
		id = "namecolor_azure",
		category = "NameColor",
		displayName = "Azure Name",
		description = "Recolors your displayed name a bright azure blue.",
		currency = "Coins",
		price = 75,
		previewColor = Color3.fromRGB(50, 130, 220),
	},
	namecolor_emerald = {
		id = "namecolor_emerald",
		category = "NameColor",
		displayName = "Emerald Name",
		description = "Recolors your displayed name a rich emerald green.",
		currency = "Coins",
		price = 75,
		previewColor = Color3.fromRGB(40, 170, 100),
	},
	namecolor_amethyst = {
		id = "namecolor_amethyst",
		category = "NameColor",
		displayName = "Amethyst Name",
		description = "Recolors your displayed name a royal purple.",
		currency = "Coins",
		price = 75,
		previewColor = Color3.fromRGB(150, 80, 210),
	},
	namecolor_gold = {
		id = "namecolor_gold",
		category = "NameColor",
		displayName = "Gold Name",
		description = "Recolors your displayed name a shining gold.",
		currency = "Gems",
		price = 5,
		previewColor = Color3.fromRGB(255, 215, 0),
	},

	-- ===== VictoryAnimation =====
	victory_confetti = {
		id = "victory_confetti",
		category = "VictoryAnimation",
		displayName = "Confetti Burst",
		description = "A burst of colorful confetti when you win a match.",
		currency = "Coins",
		price = 150,
		previewColor = Color3.fromRGB(255, 190, 60),
	},
	victory_fireworks = {
		id = "victory_fireworks",
		category = "VictoryAnimation",
		displayName = "Fireworks Finale",
		description = "A short fireworks show over the arena on your win.",
		currency = "Coins",
		price = 200,
		previewColor = Color3.fromRGB(255, 100, 130),
	},
	victory_dance = {
		id = "victory_dance",
		category = "VictoryAnimation",
		displayName = "Victory Dance",
		description = "Your character performs a custom dance on your win.",
		currency = "Gems",
		price = 6,
		previewColor = Color3.fromRGB(255, 150, 220),
	},

	-- ===== QuestionTheme =====
	theme_classic = {
		id = "theme_classic",
		category = "QuestionTheme",
		displayName = "Classic Theme",
		description = "The default MathArena question panel styling.",
		currency = "Coins",
		price = 50,
		previewColor = Color3.fromRGB(22, 22, 30),
	},
	theme_neon = {
		id = "theme_neon",
		category = "QuestionTheme",
		displayName = "Neon Theme",
		description = "A high-contrast neon look for the question panel.",
		currency = "Coins",
		price = 200,
		previewColor = Color3.fromRGB(60, 255, 210),
	},
	theme_chalkboard = {
		id = "theme_chalkboard",
		category = "QuestionTheme",
		displayName = "Chalkboard Theme",
		description = "A classroom chalkboard look for the question panel.",
		currency = "Coins",
		price = 200,
		previewColor = Color3.fromRGB(35, 55, 45),
	},

	-- ===== Title =====
	title_rookie = {
		id = "title_rookie",
		category = "Title",
		displayName = '"Rookie"',
		description = 'Shows the title "Rookie" alongside your name.',
		currency = "Coins",
		price = 100,
		previewColor = Color3.fromRGB(180, 180, 190),
	},
	title_challenger = {
		id = "title_challenger",
		category = "Title",
		displayName = '"Challenger"',
		description = 'Shows the title "Challenger" alongside your name.',
		currency = "Coins",
		price = 150,
		previewColor = Color3.fromRGB(90, 170, 255),
	},
	title_mathlete_supreme = {
		id = "title_mathlete_supreme",
		category = "Title",
		displayName = '"Mathlete Supreme"',
		description = 'Shows the title "Mathlete Supreme" alongside your name.',
		currency = "Gems",
		price = 6,
		previewColor = Color3.fromRGB(255, 215, 0),
	},
	title_perfectionist = {
		id = "title_perfectionist",
		category = "Title",
		displayName = '"Perfectionist"',
		description = 'Shows the title "Perfectionist" alongside your name.',
		currency = "Gems",
		price = 6,
		previewColor = Color3.fromRGB(120, 255, 170),
	},
}

CosmeticsConfig.ITEMS = ITEMS

function CosmeticsConfig.GetItem(id: string): CosmeticItem?
	return ITEMS[id]
end

function CosmeticsConfig.GetItemsByCategory(category: string): { CosmeticItem }
	local list = {}
	for _, item in pairs(ITEMS) do
		if item.category == category then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

return CosmeticsConfig
