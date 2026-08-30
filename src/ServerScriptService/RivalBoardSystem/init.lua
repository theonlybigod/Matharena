--[[
	RivalBoardSystem.lua

	Backs the RIVAL BOARD - a physical display standing inside the
	Statistics building on every map, showing the player's own value in each
	of the five leaderboard categories side by side with the current global
	#1, plus the gap left to close.

	WHY IT EXISTS, AND WHY IT IS IN-BUILDING ONLY. The lobby buildings were
	redundant: everything they offered (Shop, Stats, Daily) was already one
	click away on the bottom bar, so walking inside was strictly slower than
	pressing a button and there was no reason to go in. This is the
	Statistics building's answer - a comparison available nowhere else.

	It renders onto a SurfaceGui on a real part in the room rather than into
	a ScreenGui overlay, which is a deliberate design constraint rather than
	an implementation detail: a world surface cannot be surfaced on the
	bottom bar, so standing in the room is the only way to read it.

	SERVER AUTHORITATIVE. The client never computes standings and never sees
	another player's raw data. It invokes "GetRivalComparison" and receives
	finished, already-formatted strings. The player's own values come from
	their DataSystem profile on the server; leader values come from
	LeaderboardSystem.GetTopEntries - the same OrderedDataStore-backed source
	the five physical leaderboards use. Nothing here writes anything, so the
	worst a malicious client can do is read its own standing repeatedly,
	which RATE_LIMIT_SECONDS caps anyway.

	Reuses LeaderboardConfig for the category list, display names, accent
	colours and value formatting, so the Rival Board can never disagree with
	the physical leaderboards about what a category is called or how a value
	reads.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
local LeaderboardConfig = require(ServerScriptService.LeaderboardConfig)
local LeaderboardSystem = require(ServerScriptService.LeaderboardSystem)
local DataSystem = require(ServerScriptService.DataSystem)

local RivalBoardSystem = {}

-- The board refreshes when a player walks up to it, so a handful of
-- invocations per visit is normal; anything faster is a client spinning the
-- remote. Cached results are returned instead of re-reading the profile and
-- the OrderedDataStore caches on every call.
local RATE_LIMIT_SECONDS = 3

local lastCall: { [Player]: number } = {}
local lastResult: { [Player]: any } = {}

--[[
	Pulls the player's own RAW value for `category` out of their profile.

	"Raw" means the same units LeaderboardSystem stores in the
	OrderedDataStore for that category - otherwise the comparison would be
	between two different units (a fastest-answer time in seconds against the
	same time stored as milliseconds) and the gap would be nonsense.

	Category ids are the stable contract - LeaderboardConfig warns explicitly
	that renaming one would orphan existing standings - so this switches on
	ids rather than guessing profile field names.
]]
local function ownRawValue(profile: any, category: any): number?
	if not profile then
		return nil
	end

	local stats = profile.Statistics or profile.Stats or profile.stats or profile
	local value: any = nil

	if category.id == "Wins" then
		value = stats.Wins or stats.wins
	elseif category.id == "XP" then
		value = profile.XP or profile.xp or stats.XP or stats.xp
	elseif category.id == "QuestionsSolved" then
		value = stats.QuestionsSolved or stats.questionsSolved
	elseif category.id == "Accuracy" then
		value = stats.Accuracy or stats.accuracy
	elseif category.id == "FastestAnswer" then
		value = stats.FastestAnswer or stats.fastestAnswer
	end

	if typeof(value) ~= "number" then
		return nil
	end

	-- Match what the leaderboard actually stores, where the category defines
	-- a conversion (e.g. seconds -> milliseconds).
	if category.toRawValue then
		local ok, converted = pcall(category.toRawValue, value)
		if ok and typeof(converted) == "number" then
			return converted
		end
	end
	return value
end

-- Formats a raw value the same way the physical boards do.
local function formatValue(category: any, raw: number?): string
	if raw == nil then
		return "--"
	end
	local shown: any = raw
	if category.toDisplayValue then
		local ok, converted = pcall(category.toDisplayValue, raw)
		if ok then
			shown = converted
		end
	end
	if category.format then
		local ok, text = pcall(category.format, shown)
		if ok then
			return tostring(text)
		end
	end
	return tostring(shown)
end

--[[
	Builds the comparison payload: one row per leaderboard category.

	Every field handed to the client is display-ready. `hasStandings` is
	included because GetTopEntries legitimately returns an empty table on a
	fresh server or an empty OrderedDataStore (verified: it returns 0 entries
	in a clean Studio session), and the board must show an honest "no
	standings yet" state rather than a blank panel.
]]
local function buildComparison(player: Player)
	local profile = DataSystem.GetProfile(player)
	local rows = {}
	local anyStandings = false

	for _, category in ipairs(LeaderboardConfig.CATEGORIES) do
		local top = LeaderboardSystem.GetTopEntries(category.id)
		local leader = top and top[1]
		if leader then
			anyStandings = true
		end

		local own = ownRawValue(profile, category)

		local youLead = false
		local gapText = "--"

		if leader and own ~= nil then
			youLead = leader.userId == player.UserId
			if youLead then
				gapText = "You hold #1"
			else
				-- `ascending` marks categories where a LOWER raw value is
				-- better (fastest answer). Without this the board would tell a
				-- leading player they are behind.
				local diff = if category.ascending then (own - leader.value) else (leader.value - own)
				if diff <= 0 then
					gapText = "Level with #1"
				else
					gapText = ("%s to go"):format(formatValue(category, diff))
				end
			end
		elseif leader then
			gapText = "Unranked"
		elseif own ~= nil then
			gapText = "No standings yet"
		end

		table.insert(rows, {
			id = category.id,
			title = category.displayName or category.id,
			accent = category.accentColor,
			yourValue = formatValue(category, own),
			leaderName = leader and leader.name or "--",
			leaderValue = leader and formatValue(category, leader.value) or "--",
			youLead = youLead,
			gapText = gapText,
		})
	end

	return {
		hasStandings = anyStandings,
		rows = rows,
	}
end

function RivalBoardSystem.Init()
	local remote = RemoteFunctions.Get("GetRivalComparison")

	remote.OnServerInvoke = function(player: Player)
		local now = os.clock()
		local previous = lastCall[player]
		if previous and (now - previous) < RATE_LIMIT_SECONDS and lastResult[player] then
			return lastResult[player]
		end
		lastCall[player] = now

		--[[
			Wrapped deliberately. GetTopEntries reaches an OrderedDataStore and
			can throw on a service hiccup; an error raised inside
			OnServerInvoke propagates back across the RemoteFunction and would
			surface as a hard error at the client's call site, leaving the
			board permanently blank. Returning nil lets the client show its
			"unavailable" state and retry on the next approach.
		]]
		local ok, result = pcall(buildComparison, player)
		if not ok then
			warn("[RivalBoardSystem] comparison failed for " .. player.Name .. ": " .. tostring(result))
			return nil
		end

		lastResult[player] = result
		return result
	end

	-- Don't leak per-player cache entries for players who have left.
	Players.PlayerRemoving:Connect(function(player)
		lastCall[player] = nil
		lastResult[player] = nil
	end)

	print("[RivalBoardSystem] Initialized")
end

return RivalBoardSystem
