--[[
	ShopSystem

	Server-authoritative cosmetics shop: ownership, purchasing, and
	equipping. Clients only request actions (Purchase/Equip/Unequip) and
	read back the result / a full inventory snapshot - they can never
	grant themselves ownership, equip something they don't own, or spend
	currency the server didn't actually deduct. Price/currency for every
	item are looked up server-side from CosmeticsConfig; nothing about a
	purchase is taken from the client except "which item id".

	Persistence note: like the rest of the economy (Message 9), ownership/
	equip state lives on the same in-memory DataSystem profile and will
	get real persistence in Message 11 alongside coins/XP/gems - nothing
	here needs to change when that arrives.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CosmeticsConfig = require(ReplicatedStorage.Modules.CosmeticsConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)

local DataSystem = require(ServerScriptService.DataSystem)
local ProgressionSystem = require(ServerScriptService.ProgressionSystem)

local ShopSystem = {}

export type InventorySnapshot = {
	owned: { [string]: boolean },
	equipped: { [string]: string },
}

local inventoryUpdatedEvent = RemoteEvents.Get("InventoryUpdated")
local getInventorySnapshotFunction = RemoteFunctions.Get("GetInventorySnapshot")
local purchaseCosmeticItemFunction = RemoteFunctions.Get("PurchaseCosmeticItem")
local equipCosmeticItemFunction = RemoteFunctions.Get("EquipCosmeticItem")
local unequipCosmeticCategoryFunction = RemoteFunctions.Get("UnequipCosmeticCategory")

local function buildSnapshot(player: Player): InventorySnapshot?
	local profile = DataSystem.GetProfile(player)
	if not profile then
		return nil
	end
	return {
		owned = table.clone(profile.ownedCosmetics),
		equipped = table.clone(profile.equippedCosmetics),
	}
end

local function pushInventoryUpdated(player: Player)
	local snapshot = buildSnapshot(player)
	if snapshot then
		inventoryUpdatedEvent:FireClient(player, snapshot)
	end
end

--[[
	Attempts to purchase a cosmetic for `player`. Returns true on success,
	or (false, reason) on failure - reason is one of "UnknownItem",
	"NoProfile", "AlreadyOwned", or "InsufficientFunds".
]]
function ShopSystem.PurchaseItem(player: Player, itemId: string): (boolean, string?)
	local item = CosmeticsConfig.GetItem(itemId)
	if not item then
		return false, "UnknownItem"
	end

	local profile = DataSystem.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end

	if profile.ownedCosmetics[itemId] then
		return false, "AlreadyOwned"
	end

	local spent: boolean
	if item.currency == "Coins" then
		spent = ProgressionSystem.SpendCoins(player, item.price)
	else
		spent = ProgressionSystem.SpendGems(player, item.price)
	end

	if not spent then
		return false, "InsufficientFunds"
	end

	profile.ownedCosmetics[itemId] = true
	pushInventoryUpdated(player)
	return true
end

--[[
	Equips an owned cosmetic. Equipping a new item in a category replaces
	whatever was equipped there before - at most one item per category.
	Fails with "NotOwned" if the player hasn't purchased it.
]]
function ShopSystem.EquipItem(player: Player, itemId: string): (boolean, string?)
	local item = CosmeticsConfig.GetItem(itemId)
	if not item then
		return false, "UnknownItem"
	end

	local profile = DataSystem.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end

	if not profile.ownedCosmetics[itemId] then
		return false, "NotOwned"
	end

	profile.equippedCosmetics[item.category] = itemId
	pushInventoryUpdated(player)
	return true
end

--[[
	Clears whatever is equipped in `category`, if anything. Not an error
	to call with nothing equipped there.
]]
function ShopSystem.UnequipCategory(player: Player, category: string): (boolean, string?)
	local profile = DataSystem.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end

	profile.equippedCosmetics[category] = nil
	pushInventoryUpdated(player)
	return true
end

function ShopSystem.Init()
	getInventorySnapshotFunction.OnServerInvoke = function(player: Player)
		return buildSnapshot(player) or { owned = {}, equipped = {} }
	end

	purchaseCosmeticItemFunction.OnServerInvoke = function(player: Player, itemId: unknown)
		if typeof(itemId) ~= "string" then
			return { success = false, reason = "InvalidRequest" }
		end
		local ok, reason = ShopSystem.PurchaseItem(player, itemId)
		return { success = ok, reason = reason }
	end

	equipCosmeticItemFunction.OnServerInvoke = function(player: Player, itemId: unknown)
		if typeof(itemId) ~= "string" then
			return { success = false, reason = "InvalidRequest" }
		end
		local ok, reason = ShopSystem.EquipItem(player, itemId)
		return { success = ok, reason = reason }
	end

	unequipCosmeticCategoryFunction.OnServerInvoke = function(player: Player, category: unknown)
		if typeof(category) ~= "string" then
			return { success = false, reason = "InvalidRequest" }
		end
		local ok, reason = ShopSystem.UnequipCategory(player, category)
		return { success = ok, reason = reason }
	end

	print("[ShopSystem] Initialized")
end

return ShopSystem
