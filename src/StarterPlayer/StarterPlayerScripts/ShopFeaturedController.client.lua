--[[
	ShopFeaturedController.client.lua

	Drives the "Featured Item of the Day" stand inside the Shop: a wall board
	describing one cosmetic, and a tall preview column beside it tinted to
	that item's colour.

	WHY IT EXISTS. The Shop building was redundant with the bottom-bar Shop
	button - everything inside was reachable in one click, so walking there
	was strictly slower. This is the one thing the building has that the
	button does not: a single item presented properly, at size, with its
	colour shown on a full-height column rather than a small swatch.

	DELIBERATELY A SPOTLIGHT, NOT A DISCOUNT. Nothing here changes a price or
	performs a purchase. Buying still goes through the existing Shop terminal
	and ShopSystem, untouched. A discounted daily deal would mean editing
	ShopSystem's purchase validation - live economy code where a mistake lets
	players buy at the wrong price - and that is not worth the risk for a
	display feature.

	NO SERVER, ON PURPOSE. The featured item is derived from the UTC date, so
	every client independently computes the same answer on the same day
	without a remote, without stored state, and without a scheduled job. And
	because nothing is granted or charged here, there is nothing for a
	tampered client to gain by lying about the date to itself - the worst it
	can do is show itself the wrong item.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local CosmeticsConfig = require(ReplicatedStorage.Modules.CosmeticsConfig)

local CANVAS = Vector2.new(700, 430)
local BG = Color3.fromRGB(16, 18, 26)
local TEXT_DIM = Color3.fromRGB(150, 158, 178)
local TEXT_BRIGHT = Color3.fromRGB(238, 242, 250)
local GOLD = Color3.fromRGB(255, 200, 62)

--[[
	Picks today's featured cosmetic.

	PURCHASABLE ITEMS ONLY (fix alongside the rarity/rewards-split rebuild):
	CosmeticsConfig.ITEMS now also contains 30 reward-only items (5 per
	category, granted by the win-based Rewards track, never buyable). Before
	this filter, pickFeatured() could land on one of those and this board
	would show "Buy it at the Shop terminal" under something with a 0 price
	that cannot actually be bought - confusing at best. rewardOnly items are
	excluded from the candidate pool entirely; only real purchasable items
	are ever featured.

	CosmeticsConfig.ITEMS is keyed by id, and pairs() order is NOT stable
	across runs in Luau - so the ids are collected and SORTED before
	indexing. Without the sort, two clients could compute different "today's
	item" from identical data, which is exactly the sort of bug that only
	shows up between two players standing in the same room.
]]
local function pickFeatured()
	local ids = {}
	for id, item in pairs(CosmeticsConfig.ITEMS) do
		if not item.rewardOnly then
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		return nil
	end
	table.sort(ids)

	-- Whole days since the epoch, UTC. os.time() is UTC-based in Roblox, so
	-- every client rolls over to the next item at the same instant.
	local dayNumber = math.floor(os.time() / 86400)
	local index = (dayNumber % #ids) + 1
	return CosmeticsConfig.ITEMS[ids[index]]
end

local function makeLabel(parent: Instance, size: UDim2, pos: UDim2, text: string, color: Color3, weight: Enum.FontWeight, textSize: number, xAlignment: Enum.TextXAlignment?, fontEnum: Enum.Font?)
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = pos
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextXAlignment = xAlignment or Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextSize = textSize
	label.TextWrapped = true
	label.FontFace = Font.fromEnum(fontEnum or Enum.Font.GothamMedium)
	label.FontFace.Weight = weight
	label.Parent = parent
	return label
end

local boards: { [BasePart]: any } = {}

local function buildBoard(part: BasePart)
	if boards[part] then
		return
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "FeaturedItemGui"
	gui.Adornee = part
	-- Back = +Z, facing into the room. A Part's Front is its local -Z, which
	-- here points into the wall behind the board.
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = CANVAS
	gui.LightInfluence = 0
	gui.Parent = part

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = BG
	bg.BorderSizePixel = 0
	bg.Parent = gui

	--[[
		"FEATURED TODAY" kicker redesign: centered across the top of the board
		(was left-aligned), ~1.5x the old 24pt size (now 36pt), and set in
		Bangers - a bold, rounded display font that reads as "artsy" at a
		glance while staying completely legible at distance, unlike a script/
		handwriting font. Every other line shifts down to make room and a new
		Rarity line is inserted between Category and Description.
	]]
	local kicker = makeLabel(
		bg,
		UDim2.new(1, 0, 0, 46),
		UDim2.new(0, 0, 0, 12),
		"FEATURED TODAY",
		GOLD,
		Enum.FontWeight.Bold,
		36,
		Enum.TextXAlignment.Center,
		Enum.Font.Bangers
	)
	local name = makeLabel(bg, UDim2.new(1, -50, 0, 52), UDim2.new(0, 25, 0, 70), "", TEXT_BRIGHT, Enum.FontWeight.Bold, 44)
	local category = makeLabel(bg, UDim2.new(1, -50, 0, 26), UDim2.new(0, 25, 0, 126), "", TEXT_DIM, Enum.FontWeight.Medium, 22)
	local rarity = makeLabel(bg, UDim2.new(1, -50, 0, 22), UDim2.new(0, 25, 0, 154), "", GOLD, Enum.FontWeight.Bold, 18)
	local desc = makeLabel(bg, UDim2.new(1, -50, 0, 110), UDim2.new(0, 25, 0, 184), "", TEXT_DIM, Enum.FontWeight.Regular, 24)
	local price = makeLabel(bg, UDim2.new(1, -50, 0, 46), UDim2.new(0, 25, 0, 306), "", GOLD, Enum.FontWeight.Bold, 38)
	local hint = makeLabel(bg, UDim2.new(1, -50, 0, 26), UDim2.new(0, 25, 0, 364), "Buy it at the Shop terminal", TEXT_DIM, Enum.FontWeight.Regular, 20)

	boards[part] = { kicker = kicker, name = name, category = category, rarity = rarity, desc = desc, price = price, hint = hint }
end

local function render()
	local item = pickFeatured()

	for _, board in pairs(boards) do
		if not item then
			board.name.Text = "No items available"
			board.category.Text = ""
			board.rarity.Text = ""
			board.desc.Text = ""
			board.price.Text = ""
		else
			board.name.Text = item.displayName or item.id
			board.category.Text = (CosmeticsConfig.CATEGORY_DISPLAY_NAMES and CosmeticsConfig.CATEGORY_DISPLAY_NAMES[item.category])
				or item.category
				or ""
			board.rarity.Text = (item.rarity or "Common"):upper()
			board.rarity.TextColor3 = CosmeticsConfig.RARITY_COLORS[item.rarity] or GOLD
			board.desc.Text = item.description or ""
			board.price.Text = ("%d %s"):format(item.price or 0, item.currency or "Coins")
		end
	end
end

local function bindTag(tag: string, handler: (BasePart) -> ())
	for _, part in ipairs(CollectionService:GetTagged(tag)) do
		if part:IsA("BasePart") then
			handler(part)
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(part)
		if part:IsA("BasePart") then
			handler(part)
		end
	end)
end

bindTag("FeaturedItemBoard", function(part)
	buildBoard(part)
	render()
end)
CollectionService:GetInstanceRemovedSignal("FeaturedItemBoard"):Connect(function(part)
	boards[part] = nil
end)

render()

--[[
	Re-check periodically so a client left running across UTC midnight rolls
	over to the next day's item instead of showing yesterday's until rejoin.
	Ten minutes is far more often than needed for a daily rotation and costs
	nothing - there is no network call involved.
]]
task.spawn(function()
	while true do
		task.wait(600)
		render()
	end
end)
