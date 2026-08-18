--[[
	LeaderboardSystem

	Server-authoritative global leaderboards (Message 11), backed by
	OrderedDataStores so standings reflect ALL players/sessions, not just
	who's currently online: Wins, XP, Questions Solved (correct answers),
	Accuracy, and Fastest Answer.

	Category definitions (id, ascending/descending, raw<->display value
	mapping) now live in ServerScriptService/LeaderboardConfig.lua - the
	single shared source of truth also used by LeaderboardDisplay and
	LobbyBuilder/LeaderboardBoards.lua, so the five categories are only
	defined once. This module just wraps each one with its actual
	OrderedDataStore instance.

	Write side: UpdateEntries(player, profile) is called by DataSystem at
	the exact same sync points as the main profile save (autosave every
	60s + on-leave) - piggybacking on that already-rate-limited cadence
	rather than writing on every single game event, to stay well within
	DataStore request budgets.

	Read side: the "GetLeaderboardData" RemoteFunction fetches the top N
	entries for a category via GetSortedAsync and resolves each entry's
	CURRENT display name via Players:GetNameFromUserIdAsync (works for
	offline players too, and always reflects their latest username).
	Nothing else is exposed through this path beyond { name, value } pairs
	per entry - no other profile data leaks through the leaderboard.

	DataStore limitation this module works around (see LeaderboardConfig
	for the actual per-category raw<->display conversions):
		- Accuracy and Fastest Answer both need fractional values, but
		  OrderedDataStore values must be non-negative integers, so both
		  are stored scaled up (x10 and milliseconds respectively) and
		  scaled back down for display.
		- Fastest Answer is the only category fetched ascending (lower is
		  better). Players with no recorded fastest answer yet are
		  skipped entirely rather than written as an artificial "fastest
		  of all" - see LeaderboardConfig.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
local PersistenceRetry = require(ServerScriptService.PersistenceRetry)
local LeaderboardConfig = require(ServerScriptService.LeaderboardConfig)

local LeaderboardSystem = {}

export type LeaderboardEntry = {
	name: string,
	value: number,
}

local STORE_PREFIX = "MathArena_Leaderboard_"
local STORE_VERSION = "v1"

type CategoryInfo = {
	store: OrderedDataStore,
	ascending: boolean,
	toRawValue: (profile: any) -> number?,
	toDisplayValue: (raw: number) -> number,
}

local CATEGORIES: { [string]: CategoryInfo } = {}
local categoriesBuilt = false

local function buildCategories()
	if categoriesBuilt then
		return
	end
	categoriesBuilt = true

	for _, category in ipairs(LeaderboardConfig.CATEGORIES) do
		CATEGORIES[category.id] = {
			store = DataStoreService:GetOrderedDataStore(STORE_PREFIX .. category.id .. "_" .. STORE_VERSION),
			ascending = category.ascending,
			toRawValue = category.toRawValue,
			toDisplayValue = category.toDisplayValue,
		}
	end
end

--[[
	Writes this player's current standing into every leaderboard category.
	Called by DataSystem right after a successful profile save (autosave
	or on-leave) - never on every single in-match event, to stay within
	DataStore request budgets. Best-effort per category: a failure is
	retried a few times and then just warned about, since a missed update
	self-heals at the next save cycle rather than blocking anything.
]]
function LeaderboardSystem.UpdateEntries(player: Player, profile: any)
	local key = tostring(player.UserId)

	for categoryName, info in pairs(CATEGORIES) do
		local rawValue = info.toRawValue(profile)
		if rawValue ~= nil then
			local ok = PersistenceRetry.Attempt(function()
				info.store:SetAsync(key, rawValue)
			end)
			if not ok then
				warn(("[LeaderboardSystem] Failed to update %s leaderboard for %s."):format(categoryName, player.Name))
			end
		end
	end
end

--[[
	Fetches the top LeaderboardConfig.TOP_LIMIT (100) entries for
	`category`, resolving each entry's current username. Returns an empty
	list (never errors out to the caller) if the category is unknown or
	the DataStore call fails after retries - the client-facing surface
	always gets a well-formed (possibly empty) list.
]]
function LeaderboardSystem.GetTopEntries(category: string): { LeaderboardEntry }
	local info = CATEGORIES[category]
	if not info then
		return {}
	end

	local ok, pagesOrError = PersistenceRetry.Attempt(function()
		return info.store:GetSortedAsync(info.ascending, LeaderboardConfig.TOP_LIMIT)
	end)

	if not ok then
		warn(("[LeaderboardSystem] Failed to fetch %s leaderboard: %s"):format(category, tostring(pagesOrError)))
		return {}
	end

	local page = (pagesOrError :: any):GetCurrentPage()
	local entries: { LeaderboardEntry } = {}

	for _, entry in ipairs(page) do
		local userId = tonumber(entry.key)
		local displayName: string

		if userId then
			local nameOk, name = pcall(function()
				return Players:GetNameFromUserIdAsync(userId :: number)
			end)
			displayName = if nameOk then name else ("Player_%d"):format(userId :: number)
		else
			-- A non-numeric or missing key (e.g. stray test data) - don't
			-- crash the whole leaderboard fetch over one bad entry.
			displayName = "Unknown"
		end

		table.insert(entries, {
			name = displayName,
			value = info.toDisplayValue(entry.value),
		})
	end

	return entries
end

function LeaderboardSystem.Init()
	buildCategories()

	local getLeaderboardDataFunction = RemoteFunctions.Get("GetLeaderboardData")
	getLeaderboardDataFunction.OnServerInvoke = function(_player: Player, category: unknown)
		if typeof(category) ~= "string" then
			return {}
		end
		return LeaderboardSystem.GetTopEntries(category)
	end

	print("[LeaderboardSystem] Initialized")
end

return LeaderboardSystem
