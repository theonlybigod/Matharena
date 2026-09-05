--[[
	ShopUIController.client.lua

	Cosmetics shop: category tabs, a Shop/Rewards view toggle, an item
	grid, and a details panel with Preview / Purchase / Equip / Unequip
	actions. Opened from the Lobby's stably-named "ShopButton" (built by
	LobbyUIController) - this script claims that button's click handling
	itself; LobbyUIController's own placeholder handler for it was
	replaced with a no-op.

	RARITY + REWARDS-SPLIT REBUILD:
	CosmeticsConfig now carries a `rarity` field (Common/Uncommon/Rare/
	Legendary/Boundless) on every item, and each category has both
	purchasable items and reward-only items (rewardOnly = true, granted by
	the win-based Rewards track, never buyable with currency). Mixing
	those into one flat list read as "why is this un-buyable thing sitting
	in my shop next to things I can actually buy" - so this screen now has
	a genuine Shop/Rewards toggle per category:
		Shop view    - only purchasable items, sorted rarest-first so the
		               most exclusive/expensive items are the first thing
		               you see, cheapest Common items at the bottom.
		Rewards view - only reward-only items for that category, same
		               rarest-first order, each card showing the win
		               count that unlocks it instead of a price.
	Both views share the same grid/details-panel code - only the item list
	feeding them differs - so this isn't two parallel UIs to maintain.

	Purely presentational: every purchase/equip/unequip request goes to
	the server (ShopSystem) via RemoteFunctions and this script only
	displays whatever the server confirms - it never marks something as
	owned/equipped on its own, and prices/currency/rarity always come from
	the shared CosmeticsConfig catalog, never invented client-side.

	SCOPE NOTE: this implements the shop/ownership/equip system end-to-end.
	It intentionally does NOT render the equipped cosmetics' actual
	in-world effect (a real trail, halo, victory animation, recolored
	nameplate, themed question panel, or a title next to your name) - see
	CosmeticsConfig for why. "Preview" here means the details panel's
	description + color swatch, not a live in-world preview.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local CosmeticsConfig = require(ReplicatedStorage.Modules.CosmeticsConfig)
local RewardTrackConfig = require(ReplicatedStorage.Modules.RewardTrackConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local OverlayManager = require(script.Parent.OverlayManager)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")
local lobbyButtonBar = mainUI:WaitForChild("LobbyButtonBar")
local shopButton = lobbyButtonBar:WaitForChild("ShopButton") :: TextButton

local getInventorySnapshotFunction = RemoteFunctions.Get("GetInventorySnapshot")
local purchaseCosmeticItemFunction = RemoteFunctions.Get("PurchaseCosmeticItem")
local equipCosmeticItemFunction = RemoteFunctions.Get("EquipCosmeticItem")
local unequipCosmeticCategoryFunction = RemoteFunctions.Get("UnequipCosmeticCategory")
local inventoryUpdatedEvent = RemoteEvents.Get("InventoryUpdated")

-- Reverse lookup (itemId -> winsRequired) built once from
-- RewardTrackConfig, purely for display ("Earn at N wins" on a reward
-- card/detail panel) - never used to grant anything; claiming still goes
-- through RewardTrackSystem server-side exactly as before.
local winsRequiredByItemId: { [string]: number } = {}
for _, milestone in ipairs(RewardTrackConfig.MILESTONES) do
	if milestone.itemId then
		winsRequiredByItemId[milestone.itemId] = milestone.winsRequired
	end
end

-- ===== State =====

local owned: { [string]: boolean } = {}
local equipped: { [string]: string } = {}
local selectedCategory: string = CosmeticsConfig.CATEGORIES[1]
local viewingRewards = false -- false = Shop (purchasable) view, true = Rewards (reward-only) view
local selectedItemId: string? = nil

-- ===== Overlay / panel shell =====

local shopOverlay = Instance.new("Frame")
shopOverlay.Name = "ShopOverlay"
shopOverlay.Size = UDim2.fromScale(1, 1)
shopOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
shopOverlay.BackgroundTransparency = 0.5
shopOverlay.Visible = false
shopOverlay.ZIndex = 20
shopOverlay.Parent = mainUI

local shopPanel = Instance.new("Frame")
shopPanel.Name = "ShopPanel"
shopPanel.Size = UDim2.fromOffset(720, 480)
-- Nudged up from dead-center per explicit "the shop was too low, I want
-- it a little higher" direction.
shopPanel.Position = UDim2.new(0.5, -360, 0.5, -260)
shopPanel.ZIndex = 21
UITheme.StylePremiumPanel(shopPanel, 0.05)
shopPanel.Parent = shopOverlay

-- Title bar
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.fromOffset(160, 32)
titleLabel.Position = UDim2.fromOffset(16, 12)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextScaled = true
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextColor3 = UITheme.COLORS.Accent
titleLabel.Text = "Shop"
titleLabel.ZIndex = 22
titleLabel.Parent = shopPanel

local currencyLabel = Instance.new("TextLabel")
currencyLabel.Name = "CurrencyLabel"
currencyLabel.Size = UDim2.fromOffset(260, 32)
currencyLabel.Position = UDim2.new(1, -460, 0, 12)
currencyLabel.BackgroundTransparency = 1
currencyLabel.Font = Enum.Font.GothamBold
currencyLabel.TextScaled = true
currencyLabel.TextXAlignment = Enum.TextXAlignment.Right
currencyLabel.TextColor3 = UITheme.COLORS.Text
currencyLabel.Text = ""
currencyLabel.ZIndex = 22
currencyLabel.Parent = shopPanel

local closeButton = Instance.new("TextButton")
closeButton.Name = "ShopCloseButton"
closeButton.Size = UDim2.fromOffset(90, 32)
closeButton.Position = UDim2.new(1, -106, 0, 12)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextScaled = true
closeButton.Text = "Close"
closeButton.TextColor3 = UITheme.COLORS.Text
closeButton.BackgroundColor3 = UITheme.COLORS.Error
closeButton.ZIndex = 22
UITheme.ApplyCorner(closeButton)
UITheme.ApplyButtonHoverEffect(closeButton)
closeButton.Parent = shopPanel

-- Category tabs
-- Bug fix ("Show All Items/My Items overlaps the shop items sections"):
-- this row used to share space with a toggle beside it. With 6 categories
-- (CosmeticsConfig.CATEGORIES), the tabs' combined width already exceeds
-- that allotted space on a full-size desktop panel - fixed by giving the
-- Shop/Rewards toggle its own row entirely below the tabs, so there's no
-- shared horizontal space to overlap no matter how many categories exist.
local tabBar = Instance.new("Frame")
tabBar.Name = "CategoryTabs"
tabBar.Size = UDim2.new(1, -32, 0, 32)
tabBar.Position = UDim2.fromOffset(16, 52)
tabBar.BackgroundTransparency = 1
tabBar.ZIndex = 22
tabBar.Parent = shopPanel

local tabLayout = Instance.new("UIListLayout")
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.Parent = tabBar

-- Shop / Rewards view toggle - its own row below the category tabs (see
-- comment above). This is the primary split requested: reward-only items
-- must never appear mixed in with purchasable ones.
local shopViewTab = Instance.new("TextButton")
shopViewTab.Name = "ShopViewTab"
shopViewTab.Size = UDim2.fromOffset(100, 26)
shopViewTab.Position = UDim2.new(1, -216, 0, 90)
shopViewTab.Font = Enum.Font.GothamBlack
shopViewTab.TextScaled = true
shopViewTab.Text = "SHOP"
shopViewTab.TextColor3 = UITheme.COLORS.Text
shopViewTab.BackgroundColor3 = UITheme.COLORS.Accent
shopViewTab.ZIndex = 22
UITheme.ApplyCorner(shopViewTab)
UITheme.ApplyButtonHoverEffect(shopViewTab)
shopViewTab.Parent = shopPanel

local rewardsViewTab = Instance.new("TextButton")
rewardsViewTab.Name = "RewardsViewTab"
rewardsViewTab.Size = UDim2.fromOffset(100, 26)
rewardsViewTab.Position = UDim2.new(1, -110, 0, 90)
rewardsViewTab.Font = Enum.Font.GothamBlack
rewardsViewTab.TextScaled = true
rewardsViewTab.Text = "REWARDS"
rewardsViewTab.TextColor3 = UITheme.COLORS.Text
rewardsViewTab.BackgroundColor3 = UITheme.COLORS.Panel
rewardsViewTab.ZIndex = 22
UITheme.ApplyCorner(rewardsViewTab)
UITheme.ApplyButtonHoverEffect(rewardsViewTab)
rewardsViewTab.Parent = shopPanel

-- Item grid (scrolling) - shifted down to make room for the view-toggle
-- row above, height trimmed to match so the bottom edge stays where it
-- was. Cell height bumped from the original 90 to 102 to fit the new
-- rarity label under each item's price/status line.
local gridScroll = Instance.new("ScrollingFrame")
gridScroll.Name = "ItemGrid"
gridScroll.Size = UDim2.fromOffset(440, 332)
gridScroll.Position = UDim2.fromOffset(16, 124)
gridScroll.BackgroundTransparency = 1
gridScroll.BorderSizePixel = 0
gridScroll.ScrollBarThickness = 8
gridScroll.ScrollBarImageColor3 = UITheme.COLORS.Accent
gridScroll.CanvasSize = UDim2.fromOffset(0, 0)
gridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
gridScroll.ZIndex = 22
gridScroll.Parent = shopPanel

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(140, 102)
gridLayout.CellPadding = UDim2.fromOffset(8, 8)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = gridScroll

-- Details panel (right side)
local detailsPanel = Instance.new("Frame")
detailsPanel.Name = "DetailsPanel"
detailsPanel.Size = UDim2.fromOffset(220, 332)
detailsPanel.Position = UDim2.fromOffset(472, 124)
UITheme.StylePremiumPanel(detailsPanel, 0.1)
detailsPanel.ZIndex = 22
detailsPanel.Parent = shopPanel

--[[
	Character preview (rebuild replacing the flat color swatch): a live,
	slowly-rotating ViewportFrame render of the player's OWN character,
	built once from their real HumanoidDescription and reused for the rest
	of the session - not a generic mannequin.

	HONEST ABOUT WHAT THIS DOES AND DOESN'T SHOW (see the SCOPE NOTE at the
	top of this file): this game has no system that actually attaches a
	trail/halo/victory-animation effect to a character or reskins the
	question panel - only ownership/equip STATE is tracked. Building that
	rendering system is a much larger, separate undertaking, so this preview
	does not fake it with a placeholder effect that isn't the real thing.
	What IS genuinely shown here, because both are pure text/color with
	nothing to attach:
		- Title items: the exact title text, overlaid above the character,
		  precisely as it would appear next to their name.
		- NameColor items: the player's own name, rendered in that exact
		  color, overlaid below the character.
	Every item still shows its previewColor as a small swatch badge in the
	viewport's corner (unchanged in spirit from the old flat swatch) since
	for Trail/Accessory/VictoryAnimation/QuestionTheme items that color is
	still the most concrete preview available without the effects system.
]]
local previewViewport = Instance.new("ViewportFrame")
previewViewport.Name = "PreviewViewport"
previewViewport.Size = UDim2.new(1, -16, 0, 140)
previewViewport.Position = UDim2.fromOffset(8, 8)
previewViewport.BackgroundColor3 = Color3.fromRGB(10, 11, 16)
previewViewport.ZIndex = 23
UITheme.ApplyCorner(previewViewport)
previewViewport.Parent = detailsPanel

local previewCamera = Instance.new("Camera")
previewCamera.Parent = previewViewport
previewViewport.CurrentCamera = previewCamera

local previewTitleLabel = Instance.new("TextLabel")
previewTitleLabel.Name = "PreviewTitleLabel"
previewTitleLabel.Size = UDim2.new(1, -12, 0, 22)
previewTitleLabel.Position = UDim2.fromOffset(6, 4)
previewTitleLabel.BackgroundTransparency = 1
previewTitleLabel.Font = Enum.Font.GothamBold
previewTitleLabel.TextScaled = true
previewTitleLabel.TextColor3 = UITheme.COLORS.Text
previewTitleLabel.TextStrokeTransparency = 0.4
previewTitleLabel.Text = ""
previewTitleLabel.Visible = false
previewTitleLabel.ZIndex = 24
previewTitleLabel.Parent = previewViewport

local previewNameLabel = Instance.new("TextLabel")
previewNameLabel.Name = "PreviewNameLabel"
previewNameLabel.Size = UDim2.new(1, -12, 0, 22)
previewNameLabel.Position = UDim2.new(0, 6, 1, -26)
previewNameLabel.BackgroundTransparency = 1
previewNameLabel.Font = Enum.Font.GothamBold
previewNameLabel.TextScaled = true
previewNameLabel.TextStrokeTransparency = 0.4
previewNameLabel.Text = ""
previewNameLabel.Visible = false
previewNameLabel.ZIndex = 24
previewNameLabel.Parent = previewViewport

local previewSwatch = Instance.new("Frame")
previewSwatch.Name = "PreviewSwatch"
previewSwatch.Size = UDim2.fromOffset(26, 26)
previewSwatch.Position = UDim2.new(1, -34, 1, -34)
previewSwatch.BackgroundColor3 = Color3.new(1, 1, 1)
previewSwatch.BorderSizePixel = 0
previewSwatch.ZIndex = 24
UITheme.ApplyCorner(previewSwatch, UDim.new(1, 0))
local previewSwatchStroke = Instance.new("UIStroke")
previewSwatchStroke.Color = Color3.new(0, 0, 0)
previewSwatchStroke.Transparency = 0.5
previewSwatchStroke.Thickness = 1.5
previewSwatchStroke.Parent = previewSwatch
previewSwatch.Parent = previewViewport

--[[
	Builds the character model ONCE per session (not per item click) from
	the player's real HumanoidDescription, parents it into the viewport, and
	frames the camera to fit it. GetHumanoidDescriptionFromUserId is a
	network call, so this runs in its own coroutine and the viewport just
	stays on its dark background until it resolves - a session-once cost,
	not a per-open one.
]]
local previewModel: Model? = nil
local previewOrbitAngle = 0

task.spawn(function()
	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if not ok or not description then
		warn("[ShopUIController] Could not load HumanoidDescription for character preview:", description)
		return
	end

	local ok2, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok2 or not model then
		warn("[ShopUIController] Could not build character preview model:", model)
		return
	end

	-- Strip worn accessories (hats/hair/etc) entirely rather than trying to
	-- render them. Their Handle parts are positioned via a Weld computed at
	-- attach time, and that weld does not always finish settling by the time
	-- CreateHumanoidModelFromDescription returns - measured on this exact
	-- model, one Handle sat at (55, 4.5, 7.3), studs away from the body,
	-- which blew the bounding box out to 57 studs wide and made the camera
	-- framing math below meaningless. The body itself (skin tone, build) is
	-- what this preview is actually for, so removing accessories trades a
	-- cosmetic detail for a guaranteed-correct, guaranteed-centered render.
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Accessory") then
			child:Destroy()
		end
	end

	-- Anchor every part: a ViewportFrame's contents don't get the real
	-- world's physics step, so an unanchored rig would just sit there inert
	-- anyway, but anchoring makes that explicit and guarantees PivotTo below
	-- moves the whole model as one rigid piece rather than parts drifting
	-- apart from stale joint state.
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		humanoid.PlatformStand = true
	end

	-- PrimaryPart must be set explicitly - CreateHumanoidModelFromDescription
	-- does not always return a model with one already assigned, and without
	-- it PivotTo has no reliable anchor to move the whole rig as a single
	-- rigid unit, which is what left the very first version of this preview
	-- with parts scattered across a 57-stud bounding box instead of a
	-- normal ~2-stud-wide standing character.
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		model.PrimaryPart = rootPart
	end

	model.Parent = previewViewport

	-- Accessories/mesh parts on a HumanoidDescription-built model can still
	-- be streaming in for a moment after the Model itself is returned; a
	-- brief wait here so the bounding box measured below reflects the fully
	-- assembled character rather than a partial rig mid-load.
	task.wait(0.3)

	if model.PrimaryPart then
		model:PivotTo(CFrame.new(0, 0, 0))
	end

	local center, size = model:GetBoundingBox()
	local modelHeight = size.Y
	local focusPoint = center.Position
	-- Distance derived from the model's own measured height (roughly 5-6
	-- studs for a typical R15 rig) rather than a fixed guess, so unusually
	-- tall/short avatars still frame correctly without clipping.
	local distance = modelHeight * 1.7
	previewCamera.FieldOfView = 30

	previewOrbitAngle = 0
	RunService.RenderStepped:Connect(function(dt)
		if not shopOverlay.Visible then
			return
		end
		-- Slow orbit around the character - a static render reads as a flat
		-- cutout; a turning one reads as an actual 3D preview.
		previewOrbitAngle += dt * 0.5
		local camPos = focusPoint
			+ Vector3.new(math.sin(previewOrbitAngle) * distance, modelHeight * 0.15, math.cos(previewOrbitAngle) * distance)
		previewCamera.CFrame = CFrame.new(camPos, focusPoint + Vector3.new(0, modelHeight * 0.05, 0))
	end)

	previewModel = model
end)

local detailsName = Instance.new("TextLabel")
detailsName.Name = "DetailsName"
detailsName.Size = UDim2.new(1, -16, 0, 22)
detailsName.Position = UDim2.fromOffset(8, 156)
detailsName.BackgroundTransparency = 1
detailsName.Font = Enum.Font.GothamBold
detailsName.TextScaled = true
detailsName.TextColor3 = UITheme.COLORS.Text
detailsName.Text = "Select an item"
detailsName.ZIndex = 23
detailsName.Parent = detailsPanel

-- Rarity pill - a small colored label under the name, using
-- CosmeticsConfig.RARITY_COLORS so Common/Uncommon/Rare/Legendary/
-- Boundless are visually distinguishable at a glance, not just text.
local detailsRarity = Instance.new("TextLabel")
detailsRarity.Name = "DetailsRarity"
detailsRarity.Size = UDim2.new(1, -16, 0, 16)
detailsRarity.Position = UDim2.fromOffset(8, 180)
detailsRarity.BackgroundTransparency = 1
detailsRarity.Font = Enum.Font.GothamBlack
detailsRarity.TextSize = 13
detailsRarity.TextXAlignment = Enum.TextXAlignment.Left
detailsRarity.Text = ""
detailsRarity.ZIndex = 23
detailsRarity.Parent = detailsPanel

local detailsDescription = Instance.new("TextLabel")
detailsDescription.Name = "DetailsDescription"
detailsDescription.Size = UDim2.new(1, -16, 0, 42)
detailsDescription.Position = UDim2.fromOffset(8, 198)
detailsDescription.BackgroundTransparency = 1
detailsDescription.Font = Enum.Font.Gotham
detailsDescription.TextSize = 14
detailsDescription.TextWrapped = true
detailsDescription.TextYAlignment = Enum.TextYAlignment.Top
detailsDescription.TextColor3 = UITheme.COLORS.SubText
detailsDescription.Text = ""
detailsDescription.ZIndex = 23
detailsDescription.Parent = detailsPanel

local detailsPrice = Instance.new("TextLabel")
detailsPrice.Name = "DetailsPrice"
detailsPrice.Size = UDim2.new(1, -16, 0, 22)
detailsPrice.Position = UDim2.fromOffset(8, 242)
detailsPrice.BackgroundTransparency = 1
detailsPrice.Font = Enum.Font.GothamBold
detailsPrice.TextScaled = true
detailsPrice.TextColor3 = UITheme.COLORS.Gold
detailsPrice.Text = ""
detailsPrice.ZIndex = 23
detailsPrice.Parent = detailsPanel

local detailsStatus = Instance.new("TextLabel")
detailsStatus.Name = "DetailsStatus"
detailsStatus.Size = UDim2.new(1, -16, 0, 14)
detailsStatus.Position = UDim2.fromOffset(8, 266)
detailsStatus.BackgroundTransparency = 1
detailsStatus.Font = Enum.Font.Gotham
detailsStatus.TextSize = 14
detailsStatus.TextColor3 = UITheme.COLORS.SubText
detailsStatus.Text = ""
detailsStatus.ZIndex = 23
detailsStatus.Parent = detailsPanel

local actionButton = Instance.new("TextButton")
actionButton.Name = "ActionButton"
actionButton.Size = UDim2.new(1, -16, 0, 40)
actionButton.Position = UDim2.new(0, 8, 1, -56)
actionButton.Font = Enum.Font.GothamBold
actionButton.TextScaled = true
actionButton.TextColor3 = UITheme.COLORS.Text
actionButton.BackgroundColor3 = UITheme.COLORS.Accent
actionButton.Text = ""
actionButton.Visible = false
actionButton.ZIndex = 23
UITheme.ApplyCorner(actionButton)
UITheme.ApplyButtonHoverEffect(actionButton)
actionButton.Parent = detailsPanel

local secondaryActionButton = Instance.new("TextButton")
secondaryActionButton.Name = "SecondaryActionButton"
secondaryActionButton.Size = UDim2.new(1, -16, 0, 30)
secondaryActionButton.Position = UDim2.new(0, 8, 1, -12)
secondaryActionButton.Font = Enum.Font.GothamBold
secondaryActionButton.TextScaled = true
secondaryActionButton.TextColor3 = UITheme.COLORS.Text
secondaryActionButton.BackgroundColor3 = UITheme.COLORS.Panel
secondaryActionButton.Text = "Unequip"
secondaryActionButton.Visible = false
secondaryActionButton.ZIndex = 23
UITheme.ApplyCorner(secondaryActionButton)
UITheme.ApplyButtonHoverEffect(secondaryActionButton)
secondaryActionButton.Parent = detailsPanel

-- ===== Currency display =====

local function refreshCurrencyDisplay()
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	currencyLabel.Text = ("%d Coins   %d Gems"):format(leaderstats.Coins.Value, leaderstats.Gems.Value)
end

task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats", 10)
	if not leaderstats then
		return
	end
	leaderstats.Coins:GetPropertyChangedSignal("Value"):Connect(refreshCurrencyDisplay)
	leaderstats.Gems:GetPropertyChangedSignal("Value"):Connect(refreshCurrencyDisplay)
	refreshCurrencyDisplay()
end)

-- ===== Details panel =====

local function updateDetailsPanel()
	local item = selectedItemId and CosmeticsConfig.GetItem(selectedItemId)
	if not item then
		previewSwatch.BackgroundColor3 = Color3.new(1, 1, 1)
		previewTitleLabel.Visible = false
		previewNameLabel.Visible = false
		detailsName.Text = "Select an item"
		detailsRarity.Text = ""
		detailsDescription.Text = ""
		detailsPrice.Text = ""
		detailsStatus.Text = ""
		actionButton.Visible = false
		secondaryActionButton.Visible = false
		return
	end

	previewSwatch.BackgroundColor3 = item.previewColor

	-- Title/NameColor overlays: the two categories where the actual
	-- equipped effect is pure text/color and can be shown for real (see the
	-- character-preview comment above for why every other category can't
	-- be, yet).
	if item.category == "Title" then
		previewTitleLabel.Visible = true
		previewTitleLabel.Text = item.displayName
		previewNameLabel.Visible = false
	elseif item.category == "NameColor" then
		previewNameLabel.Visible = true
		previewNameLabel.Text = player.Name
		previewNameLabel.TextColor3 = item.previewColor
		previewTitleLabel.Visible = false
	else
		previewTitleLabel.Visible = false
		previewNameLabel.Visible = false
	end

	detailsName.Text = item.displayName
	detailsRarity.Text = (item.rarity or "Common"):upper()
	detailsRarity.TextColor3 = CosmeticsConfig.RARITY_COLORS[item.rarity] or UITheme.COLORS.SubText
	detailsDescription.Text = item.description

	local isOwned = owned[item.id] == true
	local isEquipped = equipped[item.category] == item.id

	if item.rewardOnly then
		local winsRequired = winsRequiredByItemId[item.id]
		detailsPrice.Text = if winsRequired then ("Earn at %d Wins"):format(winsRequired) else "Reward Only"
		detailsPrice.TextColor3 = UITheme.COLORS.Gem
	else
		detailsPrice.Text = ("%d %s"):format(item.price, item.currency)
		detailsPrice.TextColor3 = if item.currency == "Gems" then UITheme.COLORS.Gem else UITheme.COLORS.Gold
	end

	if isEquipped then
		detailsStatus.Text = "Equipped"
		actionButton.Visible = false
		secondaryActionButton.Visible = true
		secondaryActionButton.Text = "Unequip"
	elseif isOwned then
		detailsStatus.Text = "Owned"
		actionButton.Visible = true
		actionButton.Text = "Equip"
		actionButton.BackgroundColor3 = UITheme.COLORS.Accent
		secondaryActionButton.Visible = false
	elseif item.rewardOnly then
		-- Not purchasable - only earned via the Rewards track. Once granted
		-- it hits the isOwned branch above and behaves like any other item.
		local winsRequired = winsRequiredByItemId[item.id]
		detailsStatus.Text = if winsRequired
			then ("Win %d competitive matches to unlock"):format(winsRequired)
			else "Earn this from the Rewards track"
		actionButton.Visible = false
		secondaryActionButton.Visible = false
	else
		detailsStatus.Text = ""
		actionButton.Visible = true
		actionButton.Text = ("Purchase (%d %s)"):format(item.price, item.currency)
		actionButton.BackgroundColor3 = UITheme.COLORS.Success
		secondaryActionButton.Visible = false
	end
end

-- ===== Item grid =====

local function createItemCard(item: CosmeticsConfig.CosmeticItem, order: number): TextButton
	local card = Instance.new("TextButton")
	card.Name = item.id
	card.LayoutOrder = order
	card.AutoButtonColor = false
	card.Text = ""
	card.BackgroundColor3 = UITheme.COLORS.Panel
	card.ZIndex = 22
	UITheme.ApplyCorner(card)

	-- Rarity accent stripe down the left edge - readable at a glance even
	-- before looking at the text label below it.
	local rarityStripe = Instance.new("Frame")
	rarityStripe.Name = "RarityStripe"
	rarityStripe.Size = UDim2.new(0, 4, 1, 0)
	rarityStripe.BackgroundColor3 = CosmeticsConfig.RARITY_COLORS[item.rarity] or UITheme.COLORS.SubText
	rarityStripe.BorderSizePixel = 0
	rarityStripe.ZIndex = 23
	rarityStripe.Parent = card

	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.Size = UDim2.fromOffset(28, 28)
	swatch.Position = UDim2.fromOffset(14, 8)
	swatch.BackgroundColor3 = item.previewColor
	swatch.ZIndex = 23
	UITheme.ApplyCorner(swatch, UDim.new(1, 0))
	swatch.Parent = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, -50, 0, 20)
	nameLabel.Position = UDim2.fromOffset(46, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = UITheme.COLORS.Text
	nameLabel.Text = item.displayName
	nameLabel.ZIndex = 23
	nameLabel.Parent = card

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "Price"
	priceLabel.Size = UDim2.new(1, -22, 0, 18)
	priceLabel.Position = UDim2.fromOffset(14, 40)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Font = Enum.Font.Gotham
	priceLabel.TextScaled = true
	priceLabel.TextXAlignment = Enum.TextXAlignment.Left
	priceLabel.ZIndex = 23
	priceLabel.Parent = card

	if item.rewardOnly then
		local winsRequired = winsRequiredByItemId[item.id]
		priceLabel.Text = if winsRequired then ("Earn @ %d Wins"):format(winsRequired) else "Reward Only"
		priceLabel.TextColor3 = UITheme.COLORS.Gem
	else
		priceLabel.Text = ("%d %s"):format(item.price, item.currency)
		priceLabel.TextColor3 = if item.currency == "Gems" then UITheme.COLORS.Gem else UITheme.COLORS.Gold
	end

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, -22, 0, 15)
	statusLabel.Position = UDim2.fromOffset(14, 60)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextScaled = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.ZIndex = 23
	statusLabel.Parent = card

	if equipped[item.category] == item.id then
		statusLabel.Text = "Equipped"
		statusLabel.TextColor3 = UITheme.COLORS.Success
	elseif owned[item.id] then
		statusLabel.Text = "Owned"
		statusLabel.TextColor3 = UITheme.COLORS.SubText
	else
		statusLabel.Text = ""
	end

	-- Rarity label - always shown, distinct from the Owned/Equipped status
	-- line above it (Message: "below an item you would see its Rarity").
	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Name = "Rarity"
	rarityLabel.Size = UDim2.new(1, -22, 0, 14)
	rarityLabel.Position = UDim2.fromOffset(14, 78)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Font = Enum.Font.GothamBlack
	rarityLabel.TextScaled = true
	rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
	rarityLabel.TextColor3 = CosmeticsConfig.RARITY_COLORS[item.rarity] or UITheme.COLORS.SubText
	rarityLabel.Text = (item.rarity or "Common"):upper()
	rarityLabel.ZIndex = 23
	rarityLabel.Parent = card

	card.MouseButton1Click:Connect(function()
		selectedItemId = item.id
		updateDetailsPanel()
	end)

	return card
end

local function refreshGrid()
	for _, child in ipairs(gridScroll:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	-- Rarest-first (Boundless -> Common), so the shop's most exclusive/
	-- expensive items are the first thing a player sees per category, and
	-- the affordable Common items sit at the bottom of the scroll.
	local items = CosmeticsConfig.GetItemsByCategorySortedByRarity(selectedCategory)
	local order = 0
	for _, item in ipairs(items) do
		if (item.rewardOnly == true) == viewingRewards then
			order += 1
			createItemCard(item, order).Parent = gridScroll
		end
	end
end

-- ===== Category tabs =====

for index, category in ipairs(CosmeticsConfig.CATEGORIES) do
	local tabButton = Instance.new("TextButton")
	tabButton.Name = category .. "Tab"
	tabButton.LayoutOrder = index
	tabButton.Size = UDim2.fromOffset(90, 28)
	tabButton.Font = Enum.Font.GothamBold
	tabButton.TextScaled = true
	tabButton.TextColor3 = UITheme.COLORS.Text
	tabButton.BackgroundColor3 = if category == selectedCategory then UITheme.COLORS.Accent else UITheme.COLORS.Panel
	tabButton.Text = CosmeticsConfig.CATEGORY_DISPLAY_NAMES[category] or category
	tabButton.ZIndex = 22
	UITheme.ApplyCorner(tabButton)
	tabButton.Parent = tabBar

	tabButton.MouseButton1Click:Connect(function()
		selectedCategory = category
		for _, sibling in ipairs(tabBar:GetChildren()) do
			if sibling:IsA("TextButton") then
				sibling.BackgroundColor3 = if sibling.Name == category .. "Tab"
					then UITheme.COLORS.Accent
					else UITheme.COLORS.Panel
			end
		end
		selectedItemId = nil
		updateDetailsPanel()
		refreshGrid()
	end)
end

-- ===== Shop / Rewards view toggle =====

local function setViewingRewards(newValue: boolean)
	viewingRewards = newValue
	shopViewTab.BackgroundColor3 = if not viewingRewards then UITheme.COLORS.Accent else UITheme.COLORS.Panel
	rewardsViewTab.BackgroundColor3 = if viewingRewards then UITheme.COLORS.Accent else UITheme.COLORS.Panel
	selectedItemId = nil
	updateDetailsPanel()
	refreshGrid()
end

shopViewTab.MouseButton1Click:Connect(function()
	setViewingRewards(false)
end)
rewardsViewTab.MouseButton1Click:Connect(function()
	setViewingRewards(true)
end)

-- ===== Actions =====

actionButton.MouseButton1Click:Connect(function()
	local item = selectedItemId and CosmeticsConfig.GetItem(selectedItemId)
	if not item then
		return
	end

	if owned[item.id] then
		-- Equip
		local result = equipCosmeticItemFunction:InvokeServer(item.id)
		if result and result.success then
			equipped[item.category] = item.id
			updateDetailsPanel()
			refreshGrid()
		else
			detailsStatus.Text = (result and result.reason) or "Equip failed"
		end
	else
		-- Purchase
		local result = purchaseCosmeticItemFunction:InvokeServer(item.id)
		if result and result.success then
			owned[item.id] = true
			updateDetailsPanel()
			refreshGrid()
		else
			detailsStatus.Text = (result and result.reason) or "Purchase failed"
		end
	end
end)

secondaryActionButton.MouseButton1Click:Connect(function()
	local item = selectedItemId and CosmeticsConfig.GetItem(selectedItemId)
	if not item then
		return
	end

	local result = unequipCosmeticCategoryFunction:InvokeServer(item.category)
	if result and result.success then
		equipped[item.category] = nil
		updateDetailsPanel()
		refreshGrid()
	end
end)

-- ===== Open/close =====

local function requestSnapshot()
	local ok, snapshot = pcall(function()
		return getInventorySnapshotFunction:InvokeServer()
	end)
	if ok and snapshot then
		owned = snapshot.owned or {}
		equipped = snapshot.equipped or {}
	end
	refreshGrid()
	updateDetailsPanel()
end

local function openShopPanel()
	OverlayManager.Show(shopOverlay)
	UITheme.PlayOpenTween(shopPanel)
	refreshCurrencyDisplay()
	requestSnapshot()
end

OverlayManager.Register(shopOverlay)

shopButton.MouseButton1Click:Connect(function()
	if shopOverlay.Visible then
		shopOverlay.Visible = false
	else
		openShopPanel()
	end
end)

closeButton.MouseButton1Click:Connect(function()
	shopOverlay.Visible = false
end)

-- ===== Shop Terminal (in-world interaction) =====
-- Same open logic as the lobby ShopButton above - reuses this exact
-- function rather than duplicating the shop system or building a second
-- UI path. The terminal Part lives in Workspace.Lobby.Buildings.Shop
-- (BuildingInteriors.lua); this just connects to its ProximityPrompt.
task.spawn(function()
	-- StreamingEnabled is on for this game (Workspace.StreamingEnabled = true),
	-- so the Shop building Model can exist on the client before its
	-- CHILDREN (ShopTerminalStand/ShopTerminalPrompt) have streamed in -
	-- especially right at spawn, when the player is nowhere near the Shop
	-- building yet. FindFirstChild here used to return nil immediately in
	-- that gap and give up for good (no retry), permanently leaving this
	-- listener unconnected for the rest of the session even after the
	-- player walked over and the parts had long since streamed in.
	-- WaitForChild actually waits for streaming to deliver them.
	local lobby = Workspace:WaitForChild("Lobby", 10)
	local shopBuilding = lobby and lobby:WaitForChild("Buildings", 10):WaitForChild("Shop", 10)
	local stand = shopBuilding and shopBuilding:WaitForChild("ShopTerminalStand", 30)
	local prompt = stand and stand:WaitForChild("ShopTerminalPrompt", 30)
	if prompt then
		(prompt :: ProximityPrompt).Triggered:Connect(function(triggeringPlayer: Player)
			if triggeringPlayer == player then
				openShopPanel()
			end
		end)
	else
		warn("[ShopUIController] Shop terminal prompt never streamed in - in-world Shop terminal will not open the shop this session")
	end
end)

-- ===== Rewards Terminal (in-world interaction, mirrored side of the room) =====
-- Same open logic as the Shop terminal above, but forces the panel straight
-- into its Rewards view (setViewingRewards(true)) instead of leaving
-- whichever view was last selected - walking up to a wall that says "OPEN
-- REWARDS" and getting the Shop's purchasable grid instead would be a
-- confusing mismatch between the world and the UI it opens.
task.spawn(function()
	local lobby = Workspace:WaitForChild("Lobby", 10)
	local shopBuilding = lobby and lobby:WaitForChild("Buildings", 10):WaitForChild("Shop", 10)
	local stand = shopBuilding and shopBuilding:WaitForChild("RewardsTerminalStand", 30)
	local prompt = stand and stand:WaitForChild("RewardsTerminalPrompt", 30)
	if prompt then
		(prompt :: ProximityPrompt).Triggered:Connect(function(triggeringPlayer: Player)
			if triggeringPlayer == player then
				openShopPanel()
				setViewingRewards(true)
			end
		end)
	else
		warn("[ShopUIController] Rewards terminal prompt never streamed in - in-world Rewards terminal will not open the rewards view this session")
	end
end)

inventoryUpdatedEvent.OnClientEvent:Connect(function(snapshot)
	if snapshot then
		owned = snapshot.owned or {}
		equipped = snapshot.equipped or {}
		refreshGrid()
		updateDetailsPanel()
	end
end)
