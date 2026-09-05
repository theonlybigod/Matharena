--[[
	InventoryUIController.client.lua

	"My Items": everything the player OWNS (purchased from the Shop or
	earned from the Rewards track alike), organized by category, with
	Equip/Unequip - and nothing else. This is the section the original
	ask wanted separate from the Shop entirely: "I don't want items like
	[reward-earned] ones in the shop or featured, I want them to be their
	own section... have it be the character's items for the player...
	organized by Trails, Accessories, Name Colors, Victory Animations,
	Question Themes, and Titles."

	Deliberately NOT a third copy of the Shop's purchase flow: there is no
	price anywhere on this screen, no currency display, no Buy button -
	only items already in `owned` (from GetInventorySnapshot/
	InventoryUpdated, the same server-confirmed source ShopUIController
	uses) ever appear here at all. An item a player doesn't own yet simply
	isn't listed in the relevant category - "browse what's for sale" stays
	the Shop's job, this screen only ever shows what already belongs to
	the player.

	Shares the same character-preview approach as ShopUIController.client.lua
	(a live ViewportFrame render of the player's own HumanoidDescription,
	with genuine Title/NameColor overlays and a color-swatch badge for
	every other category) - see that file's own comment for why the other
	categories can't show their real equipped effect yet (no in-world
	cosmetic-rendering system exists), which applies identically here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CosmeticsConfig = require(ReplicatedStorage.Modules.CosmeticsConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local OverlayManager = require(script.Parent.OverlayManager)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")
local lobbyButtonBar = mainUI:WaitForChild("LobbyButtonBar")
local inventoryButton = lobbyButtonBar:WaitForChild("InventoryButton") :: TextButton

local getInventorySnapshotFunction = RemoteFunctions.Get("GetInventorySnapshot")
local equipCosmeticItemFunction = RemoteFunctions.Get("EquipCosmeticItem")
local unequipCosmeticCategoryFunction = RemoteFunctions.Get("UnequipCosmeticCategory")
local inventoryUpdatedEvent = RemoteEvents.Get("InventoryUpdated")

-- ===== State =====

local owned: { [string]: boolean } = {}
local equipped: { [string]: string } = {}
local selectedCategory: string = CosmeticsConfig.CATEGORIES[1]
local selectedItemId: string? = nil

-- ===== Overlay / panel shell =====

local inventoryOverlay = Instance.new("Frame")
inventoryOverlay.Name = "InventoryOverlay"
inventoryOverlay.Size = UDim2.fromScale(1, 1)
inventoryOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
inventoryOverlay.BackgroundTransparency = 0.5
inventoryOverlay.Visible = false
inventoryOverlay.ZIndex = 20
inventoryOverlay.Parent = mainUI

local inventoryPanel = Instance.new("Frame")
inventoryPanel.Name = "InventoryPanel"
inventoryPanel.Size = UDim2.fromOffset(720, 480)
inventoryPanel.Position = UDim2.new(0.5, -360, 0.5, -260)
inventoryPanel.ZIndex = 21
UITheme.StylePremiumPanel(inventoryPanel, 0.05)
inventoryPanel.Parent = inventoryOverlay

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.fromOffset(260, 32)
titleLabel.Position = UDim2.fromOffset(16, 12)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextScaled = true
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextColor3 = UITheme.COLORS.Accent
titleLabel.Text = "My Items"
titleLabel.ZIndex = 22
titleLabel.Parent = inventoryPanel

local closeButton = Instance.new("TextButton")
closeButton.Name = "InventoryCloseButton"
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
closeButton.Parent = inventoryPanel

-- Category tabs
local tabBar = Instance.new("Frame")
tabBar.Name = "CategoryTabs"
tabBar.Size = UDim2.new(1, -32, 0, 32)
tabBar.Position = UDim2.fromOffset(16, 52)
tabBar.BackgroundTransparency = 1
tabBar.ZIndex = 22
tabBar.Parent = inventoryPanel

local tabLayout = Instance.new("UIListLayout")
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.Parent = tabBar

-- Item grid (scrolling) - no view toggle needed here (unlike the Shop),
-- so it starts right under the category tabs with more vertical room.
local gridScroll = Instance.new("ScrollingFrame")
gridScroll.Name = "ItemGrid"
gridScroll.Size = UDim2.fromOffset(440, 396)
gridScroll.Position = UDim2.fromOffset(16, 92)
gridScroll.BackgroundTransparency = 1
gridScroll.BorderSizePixel = 0
gridScroll.ScrollBarThickness = 8
gridScroll.ScrollBarImageColor3 = UITheme.COLORS.Accent
gridScroll.CanvasSize = UDim2.fromOffset(0, 0)
gridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
gridScroll.ZIndex = 22
gridScroll.Parent = inventoryPanel

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(140, 102)
gridLayout.CellPadding = UDim2.fromOffset(8, 8)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = gridScroll

-- Empty-category placeholder, shown INSTEAD of the grid when the
-- selected category has no owned items yet - an empty grid with nothing
-- in it reads as broken; this reads as "nothing here yet, go earn or buy
-- some".
local emptyLabel = Instance.new("TextLabel")
emptyLabel.Name = "EmptyLabel"
emptyLabel.Size = UDim2.fromOffset(440, 396)
emptyLabel.Position = UDim2.fromOffset(16, 92)
emptyLabel.BackgroundTransparency = 1
emptyLabel.Font = Enum.Font.Gotham
emptyLabel.TextSize = 16
emptyLabel.TextWrapped = true
emptyLabel.TextColor3 = UITheme.COLORS.SubText
emptyLabel.Text = "No items owned in this category yet.\nVisit the Shop or earn one from the Rewards track."
emptyLabel.Visible = false
emptyLabel.ZIndex = 22
emptyLabel.Parent = inventoryPanel

-- Details panel (right side)
local detailsPanel = Instance.new("Frame")
detailsPanel.Name = "DetailsPanel"
detailsPanel.Size = UDim2.fromOffset(220, 396)
detailsPanel.Position = UDim2.fromOffset(472, 92)
UITheme.StylePremiumPanel(detailsPanel, 0.1)
detailsPanel.ZIndex = 22
detailsPanel.Parent = inventoryPanel

--[[
	Character preview - same approach as ShopUIController.client.lua's (see
	that file for the full reasoning and the two real bugs worked through
	building it: PrimaryPart-less PivotTo scattering the rig across a
	57-stud bounding box, and an unsettled accessory Weld placing a Handle
	studs away from the body). Duplicated here rather than shared because
	each screen owns its own self-contained UI, matching how every other
	panel in this codebase is built.
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

local previewOrbitAngle = 0

task.spawn(function()
	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if not ok or not description then
		warn("[InventoryUIController] Could not load HumanoidDescription for character preview:", description)
		return
	end

	local ok2, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok2 or not model then
		warn("[InventoryUIController] Could not build character preview model:", model)
		return
	end

	-- Strip worn accessories - see ShopUIController.client.lua's identical
	-- fix for why: an unsettled accessory Weld can leave a Handle studs
	-- away from the body, blowing out the bounding box the framing math
	-- below depends on.
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Accessory") then
			child:Destroy()
		end
	end

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

	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		model.PrimaryPart = rootPart
	end

	model.Parent = previewViewport
	task.wait(0.3)
	if model.PrimaryPart then
		model:PivotTo(CFrame.new(0, 0, 0))
	end

	local center, size = model:GetBoundingBox()
	local modelHeight = size.Y
	local focusPoint = center.Position
	local distance = modelHeight * 1.7
	previewCamera.FieldOfView = 30

	previewOrbitAngle = 0
	RunService.RenderStepped:Connect(function(dt)
		if not inventoryOverlay.Visible then
			return
		end
		previewOrbitAngle += dt * 0.5
		local camPos = focusPoint
			+ Vector3.new(math.sin(previewOrbitAngle) * distance, modelHeight * 0.15, math.cos(previewOrbitAngle) * distance)
		previewCamera.CFrame = CFrame.new(camPos, focusPoint + Vector3.new(0, modelHeight * 0.05, 0))
	end)
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
detailsDescription.Size = UDim2.new(1, -16, 0, 60)
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

local detailsStatus = Instance.new("TextLabel")
detailsStatus.Name = "DetailsStatus"
detailsStatus.Size = UDim2.new(1, -16, 0, 20)
detailsStatus.Position = UDim2.fromOffset(8, 262)
detailsStatus.BackgroundTransparency = 1
detailsStatus.Font = Enum.Font.GothamBold
detailsStatus.TextScaled = true
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
actionButton.Text = "Equip"
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
		detailsStatus.Text = ""
		actionButton.Visible = false
		secondaryActionButton.Visible = false
		return
	end

	previewSwatch.BackgroundColor3 = item.previewColor

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

	local isEquipped = equipped[item.category] == item.id
	if isEquipped then
		detailsStatus.Text = "Equipped"
		detailsStatus.TextColor3 = UITheme.COLORS.Success
		actionButton.Visible = false
		secondaryActionButton.Visible = true
	else
		detailsStatus.Text = "Owned"
		detailsStatus.TextColor3 = UITheme.COLORS.SubText
		actionButton.Visible = true
		actionButton.Text = "Equip"
		actionButton.BackgroundColor3 = UITheme.COLORS.Accent
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

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, -22, 0, 18)
	statusLabel.Position = UDim2.fromOffset(14, 40)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextScaled = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.ZIndex = 23
	statusLabel.Parent = card

	if equipped[item.category] == item.id then
		statusLabel.Text = "Equipped"
		statusLabel.TextColor3 = UITheme.COLORS.Success
	else
		statusLabel.Text = "Owned"
		statusLabel.TextColor3 = UITheme.COLORS.SubText
	end

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

	local items = CosmeticsConfig.GetItemsByCategorySortedByRarity(selectedCategory)
	local order = 0
	for _, item in ipairs(items) do
		if owned[item.id] then
			order += 1
			createItemCard(item, order).Parent = gridScroll
		end
	end

	local hasAny = order > 0
	gridScroll.Visible = hasAny
	emptyLabel.Visible = not hasAny
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

-- ===== Actions =====

actionButton.MouseButton1Click:Connect(function()
	local item = selectedItemId and CosmeticsConfig.GetItem(selectedItemId)
	if not item then
		return
	end

	local result = equipCosmeticItemFunction:InvokeServer(item.id)
	if result and result.success then
		equipped[item.category] = item.id
		updateDetailsPanel()
		refreshGrid()
	else
		detailsStatus.Text = (result and result.reason) or "Equip failed"
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

local function openInventoryPanel()
	OverlayManager.Show(inventoryOverlay)
	UITheme.PlayOpenTween(inventoryPanel)
	requestSnapshot()
end

OverlayManager.Register(inventoryOverlay)

inventoryButton.MouseButton1Click:Connect(function()
	if inventoryOverlay.Visible then
		inventoryOverlay.Visible = false
	else
		openInventoryPanel()
	end
end)

closeButton.MouseButton1Click:Connect(function()
	inventoryOverlay.Visible = false
end)

inventoryUpdatedEvent.OnClientEvent:Connect(function(snapshot)
	if snapshot then
		owned = snapshot.owned or {}
		equipped = snapshot.equipped or {}
		refreshGrid()
		updateDetailsPanel()
	end
end)
