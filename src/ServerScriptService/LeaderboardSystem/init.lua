--[[
	LeaderboardSystem

	Server-authoritative global leaderboards (Message 11), backed by
	OrderedDataStores so standings reflect ALL players/sessions, not just
	who's currently online: Wins, XP, Questions Solved (correct answers),
	Accuracy, and Fastest Answer.

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

	DataStore limitation this module works around: OrderedDataStore
	values must be non-negative integers.
		- Accuracy (0-100 with one decimal place) is stored as
		  round(accuracy * 10) (e.g. 87.3% -> 873) and divided back by 10
		  for display.
		- Fastest Answer (fractional seconds) is stored as whole
		  milliseconds and divided back by 1000 for display. Lower is
		  better, so only this leaderboard is fetched ascending; the
		  other four are fetched descending. Players with no recorded
		  fastest answer yet (the -1 sentinel, see DataSystem) are
		  skipped entirely rather than written as an artificial "fastest
		  of all".

	ASSUMPTION (documented, not stopped for): "Questions solved" is read
	as questions answered CORRECTLY (profile.statistics.correctAnswers),
	not merely attempted.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
local PersistenceRetry = require(ServerScriptService.PersistenceRetry)

local LeaderboardSystem = {}

export type LeaderboardEntry = {
	name: string,
	value: number,
}

local STORE_PREFIX = "MathArena_Leaderboard_"
local STORE_VERSION = "v1"
local TOP_N = 10

type CategoryInfo = {
	store: OrderedDataStore,
	ascending: boolean, -- true = lower raw value is better (only FastestAnswer)
	toRawValue: (profile: any) -> number?, -- nil = skip writing this category for this profile
	toDisplayValue: (raw: number) -> number,
}

local CATEGORIES: { [string]: CategoryInfo } = {}
local categoriesBuilt = false

local function buildCategories()
	if categoriesBuilt then
		return
	end
	categoriesBuilt = true

	CATEGORIES.Wins = {
		store = DataStoreService:GetOrderedDataStore(STORE_PREFIX .. "Wins_" .. STORE_VERSION),
		ascending = false,
		toRawValue = function(profile)
			return profile.wins
		end,
		toDisplayValue = function(raw)
			return raw
		end,
	}
	CATEGORIES.XP = {
		store = DataStoreService:GetOrderedDataStore(STORE_PREFIX .. "XP_" .. STORE_VERSION),
		ascending = false,
		toRawValue = function(profile)
			return profile.xp
		end,
		toDisplayValue = function(raw)
			return raw
		end,
	}
	CATEGORIES.QuestionsSolved = {
		store = DataStoreService:GetOrderedDataStore(STORE_PREFIX .. "QuestionsSolved_" .. STORE_VERSION),
		ascending = false,
		toRawValue = function(profile)
			return profile.statistics.correctAnswers
		end,
		toDisplayValue = function(raw)
			return raw
		end,
	}
	CATEGORIES.Accuracy = {
		store = DataStoreService:GetOrderedDataStore(STORE_PREFIX .. "Accuracy_" .. STORE_VERSION),
		ascending = false,
		toRawValue = function(profile)
			return math.floor(profile.statistics.accuracy * 10 + 0.5)
		end,
		toDisplayValue = function(raw)
			return raw / 10
		end,
	}
	CATEGORIES.FastestAnswer = {
		store = DataStoreService:GetOrderedDataStore(STORE_PREFIX .. "FastestAnswer_" .. STORE_VERSION),
		ascending = true,
		toRawValue = function(profile)
			local seconds = profile.statistics.fastestAnswerSeconds
			if seconds < 0 then
				return nil -- no recorded fastest answer yet - skip, don't write a fake "0"
			end
			return math.floor(seconds * 1000 + 0.5)
		end,
		toDisplayValue = function(raw)
			return raw / 1000
		end,
	}
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
	Fetches the top TOP_N entries for `category`, resolving each entry's
	current username. Returns an empty list (never errors out to the
	caller) if the category is unknown or the DataStore call fails after
	retries - the client-facing surface always gets a well-formed
	(possibly empty) list.
]]
function LeaderboardSystem.GetTopEntries(category: string): { LeaderboardEntry }
	local info = CATEGORIES[category]
	if not info then
		return {}
	end

	local ok, pagesOrError = PersistenceRetry.Attempt(function()
		return info.store:GetSortedAsync(info.ascending, TOP_N)
	end)

	if not ok then
		warn(("[LeaderboardSystem] Failed to fetch %s leaderboard: %s"):format(category, tostring(pagesOrError)))
		return {}
	end

	local page = (pagesOrError :: any):GetCurrentPage()
	local entries: { LeaderboardEntry } = {}

	for _, entry in ipairs(page) do
		local userId = tonumber(entry.key)
		local nameOk, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId :: number)
		end)

		table.insert(entries, {
			name = if nameOk then name else ("Player_%d"):format(userId :: number),
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
