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

	CosmeticsConfig.ITEMS is keyed by id, and pairs() order is NOT stable
	across runs in Luau - so the ids are collected and SORTED before
	indexing. Without the sort, two clients could compute different "today's
	item" from identical data, which is exactly the sort of bug that only
	shows up between two players standing in the same room.
]]
local function pickFeatured()
	local ids = {}
	for id in pairs(CosmeticsConfig.ITEMS) do
		table.insert(ids, id)
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

local function makeLabel(parent: Instance, size: UDim2, pos: UDim2, text: string, color: Color3, weight: Enum.FontWeight, textSize: number)
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = pos
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextSize = textSize
	label.TextWrapped = true
	label.FontFace = Font.fromEnum(Enum.Font.GothamMedium)
	label.FontFace.Weight = weight
	label.Parent = parent
	return label
end

local boards: { [BasePart]: any } = {}
local shafts: { [BasePart]: boolean } = {}

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

	local kicker = makeLabel(bg, UDim2.new(1, -50, 0, 26), UDim2.new(0, 25, 0, 20), "FEATURED TODAY", GOLD, Enum.FontWeight.Bold, 24)
	local name = makeLabel(bg, UDim2.new(1, -50, 0, 52), UDim2.new(0, 25, 0, 52), "", TEXT_BRIGHT, Enum.FontWeight.Bold, 44)
	local category = makeLabel(bg, UDim2.new(1, -50, 0, 26), UDim2.new(0, 25, 0, 112), "", TEXT_DIM, Enum.FontWeight.Medium, 22)
	local desc = makeLabel(bg, UDim2.new(1, -50, 0, 130), UDim2.new(0, 25, 0, 150), "", TEXT_DIM, Enum.FontWeight.Regular, 24)
	local price = makeLabel(bg, UDim2.new(1, -50, 0, 46), UDim2.new(0, 25, 0, 300), "", GOLD, Enum.FontWeight.Bold, 38)
	local hint = makeLabel(bg, UDim2.new(1, -50, 0, 26), UDim2.new(0, 25, 0, 366), "Buy it at the Shop terminal", TEXT_DIM, Enum.FontWeight.Regular, 20)

	boards[part] = { kicker = kicker, name = name, category = category, desc = desc, price = price, hint = hint }
end

local function render()
	local item = pickFeatured()

	for _, board in pairs(boards) do
		if not item then
			board.name.Text = "No items available"
			board.category.Text = ""
			board.desc.Text = ""
			board.price.Text = ""
		else
			board.name.Text = item.displayName or item.id
			board.category.Text = (CosmeticsConfig.CATEGORY_DISPLAY_NAMES and CosmeticsConfig.CATEGORY_DISPLAY_NAMES[item.category])
				or item.category
				or ""
			board.desc.Text = item.description or ""
			board.price.Text = ("%d %s"):format(item.price or 0, item.currency or "Coins")
		end
	end

	-- Tint the preview column to the item's colour, which is the whole point
	-- of showing it at this size.
	if item and item.previewColor then
		for shaft in pairs(shafts) do
			if shaft.Parent then
				shaft.Color = item.previewColor
			end
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

bindTag("FeaturedPreviewShaft", function(part)
	shafts[part] = true
	render()
end)
CollectionService:GetInstanceRemovedSignal("FeaturedPreviewShaft"):Connect(function(part)
	shafts[part] = nil
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
