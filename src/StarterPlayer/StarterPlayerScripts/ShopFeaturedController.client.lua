--[[
	ShopFeaturedController.client.lua

	Drives the "Featured Item of the Day" stand inside the Shop: a wall board
	describing one cosmetic on the left half, and a live character preview
	(or the exact title/name-color text, for those two categories) on the
	right half, in the same section as the name.

	FEATURED ITEM PICKING now lives in CosmeticsConfig.GetFeaturedItem() -
	shared with ShopSystem server-side, which is what makes the 10% daily
	discount below safe: the item shown here and the price actually charged
	at the terminal are always the exact same deterministic answer, never
	two copies of the same logic that could drift.

	REAL DISCOUNT NOW (previously deliberately display-only): the featured
	item is always 10% off (CosmeticsConfig.FEATURED_DISCOUNT_PERCENT),
	verified server-side in ShopSystem.PurchaseItem via
	CosmeticsConfig.IsFeaturedToday - this board never invents a price the
	terminal wouldn't also charge.

	NEVER BOUNDLESS: CosmeticsConfig.GetFeaturedItem() excludes Boundless-
	rarity items entirely, so the single most exclusive tier in the game is
	never featured (or discounted).

	CHARACTER PREVIEW: uses the shared CharacterPreviewBuilder (also used by
	ShopUIController's and InventoryUIController's detail panels) - same
	honesty boundary as those: Title/NameColor items show their exact real
	effect (the actual title text / the player's actual name in that exact
	color) because both are pure text with nothing to attach; every other
	category still has no in-world cosmetic-effects system to render, so it
	shows the character plus a color swatch rather than faking an effect
	that isn't real.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local CosmeticsConfig = require(ReplicatedStorage.Modules.CosmeticsConfig)
local CharacterPreviewBuilder = require(ReplicatedStorage.Modules.CharacterPreviewBuilder)

local CANVAS = Vector2.new(700, 430)
local BG = Color3.fromRGB(16, 18, 26)
local TEXT_DIM = Color3.fromRGB(150, 158, 178)
local TEXT_BRIGHT = Color3.fromRGB(238, 242, 250)
local GOLD = Color3.fromRGB(255, 200, 62)

-- Left column (text) width; the right column (preview) picks up the rest.
local LEFT_WIDTH = 330
local RIGHT_X = 360
local RIGHT_WIDTH = CANVAS.X - RIGHT_X - 20

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
		"FEATURED TODAY" kicker: centered across the FULL width (spans both
		columns, sits above the split) in Bangers, matching the same
		flourish-title treatment used on the Shop's Rewards board and the
		Daily Rewards vault.
	]]
	makeLabel(
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

	-- ===== Left column: name/category/rarity/description/price =====
	local name = makeLabel(bg, UDim2.new(0, LEFT_WIDTH, 0, 52), UDim2.new(0, 25, 0, 70), "", TEXT_BRIGHT, Enum.FontWeight.Bold, 40)
	local category = makeLabel(bg, UDim2.new(0, LEFT_WIDTH, 0, 26), UDim2.new(0, 25, 0, 126), "", TEXT_DIM, Enum.FontWeight.Medium, 20)
	local rarity = makeLabel(bg, UDim2.new(0, LEFT_WIDTH, 0, 22), UDim2.new(0, 25, 0, 154), "", GOLD, Enum.FontWeight.Bold, 18)
	local desc = makeLabel(bg, UDim2.new(0, LEFT_WIDTH, 0, 100), UDim2.new(0, 25, 0, 184), "", TEXT_DIM, Enum.FontWeight.Regular, 20)
	local price = makeLabel(bg, UDim2.new(0, LEFT_WIDTH, 0, 30), UDim2.new(0, 25, 0, 292), "", GOLD, Enum.FontWeight.Bold, 26)
	local discountBadge = makeLabel(bg, UDim2.new(0, LEFT_WIDTH, 0, 24), UDim2.new(0, 25, 0, 324), "", Color3.fromRGB(120, 220, 150), Enum.FontWeight.Bold, 18)
	local hint = makeLabel(bg, UDim2.new(0, LEFT_WIDTH, 0, 26), UDim2.new(0, 25, 0, 364), "Buy it at the Shop terminal", TEXT_DIM, Enum.FontWeight.Regular, 18)

	-- ===== Right column: item preview =====
	--[[
		NOT a live character ViewportFrame here, on purpose - tried it, and
		found (with a direct side-by-side comparison) that a ViewportFrame
		embedded in a SurfaceGui renders completely blank in this engine/
		version, even with a verified-correct model and camera - the exact
		SAME CharacterPreviewBuilder output renders perfectly in the Shop
		panel's ScreenGui-based details panel. That's a SurfaceGui+ViewportFrame
		nesting limitation, not something fixable by adjusting the model/camera
		further, so this wall board shows the same honest preview the item
		grid cards use - a large color swatch, plus the real Title/NameColor
		text for the two categories where that IS the exact real effect - and
		leaves the live rotating character render for the ScreenGui panels
		(Shop details / Inventory details) where it demonstrably works.
	]]
	local previewFrame = Instance.new("Frame")
	previewFrame.Size = UDim2.fromOffset(RIGHT_WIDTH, 300)
	previewFrame.Position = UDim2.fromOffset(RIGHT_X, 70)
	previewFrame.BackgroundColor3 = Color3.fromRGB(10, 11, 16)
	previewFrame.Parent = bg

	local previewSwatch = Instance.new("Frame")
	previewSwatch.Size = UDim2.fromOffset(140, 140)
	previewSwatch.Position = UDim2.new(0.5, -70, 0.5, -70)
	previewSwatch.BackgroundColor3 = Color3.new(1, 1, 1)
	previewSwatch.BorderSizePixel = 0
	previewSwatch.Parent = previewFrame
	local swatchCorner = Instance.new("UICorner")
	swatchCorner.CornerRadius = UDim.new(0, 16)
	swatchCorner.Parent = previewSwatch

	local previewTitleLabel = Instance.new("TextLabel")
	previewTitleLabel.Size = UDim2.new(1, -20, 0, 60)
	previewTitleLabel.Position = UDim2.new(0.5, -((RIGHT_WIDTH - 20) / 2), 0.5, -30)
	previewTitleLabel.BackgroundTransparency = 1
	previewTitleLabel.Font = Enum.Font.GothamBold
	previewTitleLabel.TextScaled = true
	previewTitleLabel.TextColor3 = TEXT_BRIGHT
	previewTitleLabel.TextStrokeTransparency = 0.3
	previewTitleLabel.Text = ""
	previewTitleLabel.Visible = false
	previewTitleLabel.Parent = previewFrame

	local previewNameLabel = Instance.new("TextLabel")
	previewNameLabel.Size = UDim2.new(1, -20, 0, 60)
	previewNameLabel.Position = UDim2.new(0.5, -((RIGHT_WIDTH - 20) / 2), 0.5, -30)
	previewNameLabel.BackgroundTransparency = 1
	previewNameLabel.Font = Enum.Font.GothamBold
	previewNameLabel.TextScaled = true
	previewNameLabel.TextStrokeTransparency = 0.3
	previewNameLabel.Text = ""
	previewNameLabel.Visible = false
	previewNameLabel.Parent = previewFrame

	boards[part] = {
		name = name,
		category = category,
		rarity = rarity,
		desc = desc,
		price = price,
		discountBadge = discountBadge,
		hint = hint,
		previewTitleLabel = previewTitleLabel,
		previewNameLabel = previewNameLabel,
		previewSwatch = previewSwatch,
	}
end

local function render()
	local item = CosmeticsConfig.GetFeaturedItem()

	for _, board in pairs(boards) do
		if not item then
			board.name.Text = "No items available"
			board.category.Text = ""
			board.rarity.Text = ""
			board.desc.Text = ""
			board.price.Text = ""
			board.discountBadge.Text = ""
			board.previewTitleLabel.Visible = false
			board.previewNameLabel.Visible = false
		else
			board.name.Text = item.displayName or item.id
			board.category.Text = (CosmeticsConfig.CATEGORY_DISPLAY_NAMES and CosmeticsConfig.CATEGORY_DISPLAY_NAMES[item.category])
				or item.category
				or ""
			board.rarity.Text = (item.rarity or "Common"):upper()
			board.rarity.TextColor3 = CosmeticsConfig.RARITY_COLORS[item.rarity] or GOLD
			board.desc.Text = item.description or ""

			local discountedPrice = CosmeticsConfig.GetDiscountedPrice(item)
			board.price.Text = ("%d %s"):format(discountedPrice, item.currency or "Coins")
			board.discountBadge.Text = ("%d%% OFF TODAY (was %d %s)"):format(
				CosmeticsConfig.FEATURED_DISCOUNT_PERCENT,
				item.price or 0,
				item.currency or "Coins"
			)

			board.previewSwatch.BackgroundColor3 = item.previewColor

			if item.category == "Title" then
				board.previewTitleLabel.Visible = true
				board.previewTitleLabel.Text = item.displayName
				board.previewNameLabel.Visible = false
			elseif item.category == "NameColor" then
				board.previewNameLabel.Visible = true
				board.previewNameLabel.Text = Players.LocalPlayer and Players.LocalPlayer.Name or ""
				board.previewNameLabel.TextColor3 = item.previewColor
				board.previewTitleLabel.Visible = false
			else
				board.previewTitleLabel.Visible = false
				board.previewNameLabel.Visible = false
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
