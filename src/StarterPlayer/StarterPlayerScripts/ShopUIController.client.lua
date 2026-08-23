--[[
	ShopUIController.client.lua

	Cosmetics shop: category tabs, an item grid (all items or owned-only),
	and a details panel with Preview / Purchase / Equip / Unequip actions.
	Opened from the Lobby's stably-named "ShopButton" (built by
	LobbyUIController, Message 8) - this script claims that button's click
	handling itself; LobbyUIController's own placeholder handler for it
	was replaced with a no-op as part of this message.

	Purely presentational: every purchase/equip/unequip request goes to
	the server (ShopSystem) via RemoteFunctions and this script only
	displays whatever the server confirms - it never marks something as
	owned/equipped on its own, and prices/currency always come from the
	shared CosmeticsConfig catalog, never invented client-side.

	SCOPE NOTE (Message 10): this implements the shop/ownership/equip
	system end-to-end. It intentionally does NOT render the equipped
	cosmetics' actual in-world effect (a real trail, halo, victory
	animation, recolored nameplate, themed question panel, or a title
	next to your name) - see CosmeticsConfig for why. "Preview" here
	means the details panel's description + color swatch, not a live
	in-world preview.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CosmeticsConfig = require(ReplicatedStorage.Modules.CosmeticsConfig)
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

-- ===== State =====

local owned: { [string]: boolean } = {}
local equipped: { [string]: string } = {}
local selectedCategory: string = CosmeticsConfig.CATEGORIES[1]
local showOnlyOwned = false
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
-- this row used to share space with FilterToggle beside it (tabBar width
-- = panel width - 172, leaving a gap for the toggle to its right). With
-- 6 categories (CosmeticsConfig.CATEGORIES), the tabs' combined width
-- (6 * 90 + 5 * 6 padding = 570) already EXCEEDS that allotted space
-- (548) on a full-size desktop panel, before any responsive scaling - the
-- last tab overflows rightward into the toggle regardless of screen size.
-- Fixed by giving the toggle its own row entirely below the tabs, so
-- there's no shared horizontal space to overlap no matter how many
-- categories exist or how wide their labels are.
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

-- Owned-only filter toggle - its own row below the tabs (see comment above).
local filterToggle = Instance.new("TextButton")
filterToggle.Name = "FilterToggle"
filterToggle.Size = UDim2.fromOffset(140, 26)
filterToggle.Position = UDim2.new(1, -156, 0, 90)
filterToggle.Font = Enum.Font.GothamBold
filterToggle.TextScaled = true
filterToggle.TextColor3 = UITheme.COLORS.Text
filterToggle.BackgroundColor3 = UITheme.COLORS.Panel
filterToggle.Text = "Show: All Items"
filterToggle.ZIndex = 22
UITheme.ApplyCorner(filterToggle)
UITheme.ApplyButtonHoverEffect(filterToggle)
filterToggle.Parent = shopPanel

-- Item grid (scrolling) - shifted down to make room for the filter
-- toggle's own row above, height trimmed to match so the bottom edge
-- stays where it was.
local gridScroll = Instance.new("ScrollingFrame")
gridScroll.Name = "ItemGrid"
gridScroll.Size = UDim2.fromOffset(440, 332)
gridScroll.Position = UDim2.fromOffset(16, 124)
gridScroll.BackgroundTransparency = 1
gridScroll.BorderSizePixel = 0
gridScroll.ScrollBarThickness = 6
gridScroll.CanvasSize = UDim2.fromOffset(0, 0)
gridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
gridScroll.ZIndex = 22
gridScroll.Parent = shopPanel

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(140, 90)
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

local previewSwatch = Instance.new("Frame")
previewSwatch.Name = "PreviewSwatch"
previewSwatch.Size = UDim2.fromOffset(60, 60)
previewSwatch.Position = UDim2.new(0.5, -30, 0, 16)
previewSwatch.BackgroundColor3 = Color3.new(1, 1, 1)
previewSwatch.ZIndex = 23
UITheme.ApplyCorner(previewSwatch, UDim.new(1, 0))
previewSwatch.Parent = detailsPanel

local detailsName = Instance.new("TextLabel")
detailsName.Name = "DetailsName"
detailsName.Size = UDim2.new(1, -16, 0, 28)
detailsName.Position = UDim2.fromOffset(8, 84)
detailsName.BackgroundTransparency = 1
detailsName.Font = Enum.Font.GothamBold
detailsName.TextScaled = true
detailsName.TextColor3 = UITheme.COLORS.Text
detailsName.Text = "Select an item"
detailsName.ZIndex = 23
detailsName.Parent = detailsPanel

local detailsDescription = Instance.new("TextLabel")
detailsDescription.Name = "DetailsDescription"
detailsDescription.Size = UDim2.new(1, -16, 0, 100)
detailsDescription.Position = UDim2.fromOffset(8, 116)
detailsDescription.BackgroundTransparency = 1
detailsDescription.Font = Enum.Font.Gotham
detailsDescription.TextSize = 15
detailsDescription.TextWrapped = true
detailsDescription.TextYAlignment = Enum.TextYAlignment.Top
detailsDescription.TextColor3 = UITheme.COLORS.SubText
detailsDescription.Text = ""
detailsDescription.ZIndex = 23
detailsDescription.Parent = detailsPanel

local detailsPrice = Instance.new("TextLabel")
detailsPrice.Name = "DetailsPrice"
detailsPrice.Size = UDim2.new(1, -16, 0, 24)
detailsPrice.Position = UDim2.fromOffset(8, 220)
detailsPrice.BackgroundTransparency = 1
detailsPrice.Font = Enum.Font.GothamBold
detailsPrice.TextScaled = true
detailsPrice.TextColor3 = UITheme.COLORS.Gold
detailsPrice.Text = ""
detailsPrice.ZIndex = 23
detailsPrice.Parent = detailsPanel

local detailsStatus = Instance.new("TextLabel")
detailsStatus.Name = "DetailsStatus"
detailsStatus.Size = UDim2.new(1, -16, 0, 20)
detailsStatus.Position = UDim2.fromOffset(8, 248)
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
		detailsName.Text = "Select an item"
		detailsDescription.Text = ""
		detailsPrice.Text = ""
		detailsStatus.Text = ""
		actionButton.Visible = false
		secondaryActionButton.Visible = false
		return
	end

	previewSwatch.BackgroundColor3 = item.previewColor
	detailsName.Text = item.displayName
	detailsDescription.Text = item.description
	detailsPrice.Text = ("%d %s"):format(item.price, item.currency)
	detailsPrice.TextColor3 = if item.currency == "Gems" then UITheme.COLORS.Gem else UITheme.COLORS.Gold

	local isOwned = owned[item.id] == true
	local isEquipped = equipped[item.category] == item.id

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
		detailsStatus.Text = "Earn this from the Rewards track"
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

	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.Size = UDim2.fromOffset(28, 28)
	swatch.Position = UDim2.fromOffset(8, 8)
	swatch.BackgroundColor3 = item.previewColor
	swatch.ZIndex = 23
	UITheme.ApplyCorner(swatch, UDim.new(1, 0))
	swatch.Parent = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, -44, 0, 20)
	nameLabel.Position = UDim2.fromOffset(40, 8)
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
	priceLabel.Size = UDim2.new(1, -16, 0, 18)
	priceLabel.Position = UDim2.fromOffset(8, 40)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Font = Enum.Font.Gotham
	priceLabel.TextScaled = true
	priceLabel.TextXAlignment = Enum.TextXAlignment.Left
	priceLabel.TextColor3 = if item.currency == "Gems" then UITheme.COLORS.Gem else UITheme.COLORS.Gold
	priceLabel.Text = ("%d %s"):format(item.price, item.currency)
	priceLabel.ZIndex = 23
	priceLabel.Parent = card

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, -16, 0, 16)
	statusLabel.Position = UDim2.fromOffset(8, 62)
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
	elseif item.rewardOnly then
		statusLabel.Text = "Reward Only"
		statusLabel.TextColor3 = UITheme.COLORS.Gem
	else
		statusLabel.Text = ""
	end

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

	local items = CosmeticsConfig.GetItemsByCategory(selectedCategory)
	local order = 0
	for _, item in ipairs(items) do
		if not showOnlyOwned or owned[item.id] then
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

-- ===== Filter toggle =====

filterToggle.MouseButton1Click:Connect(function()
	showOnlyOwned = not showOnlyOwned
	filterToggle.Text = if showOnlyOwned then "Show: My Items" else "Show: All Items"
	refreshGrid()
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

-- ===== Shop Terminal (in-world interaction, Message 15) =====
-- Same open logic as the lobby ShopButton above - reuses this exact
-- function rather than duplicating the shop system or building a second
-- UI path. The terminal Part lives in Workspace.Lobby.Buildings.Shop
-- (BuildingInteriors.lua); this just connects to its ProximityPrompt.
task.spawn(function()
	local lobby = Workspace:WaitForChild("Lobby", 10)
	local shopBuilding = lobby and lobby:WaitForChild("Buildings", 10):WaitForChild("Shop", 10)
	local stand = shopBuilding and shopBuilding:FindFirstChild("ShopTerminalStand")
	local prompt = stand and stand:FindFirstChild("ShopTerminalPrompt")
	if prompt then
		(prompt :: ProximityPrompt).Triggered:Connect(function(triggeringPlayer: Player)
			if triggeringPlayer == player then
				openShopPanel()
			end
		end)
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
