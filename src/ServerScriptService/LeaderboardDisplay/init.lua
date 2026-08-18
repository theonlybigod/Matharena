--[[
	LeaderboardDisplay

	Refreshes the five separate physical leaderboard boards built by
	LobbyBuilder/LeaderboardBoards.lua (Workspace.Lobby.Buildings.
	<Category>Leaderboard - e.g. WinsLeaderboard) with live standings from
	LeaderboardSystem.

	Single centralized refresh loop - one timer, one pass per cycle that
	iterates all five categories - rather than five independent polling
	loops. This also matches DataStore request budgeting: GetSortedAsync
	calls count against read request budgets, so there's no reason to
	poll faster than the underlying data actually changes (still the same
	60s cadence as the DataStore autosave/leaderboard write cycle).

	Only row TEXT is touched here (rank/name/score). Podium styling (the
	gold/silver/bronze rank-badge colors for the top 3) is baked in once
	at build time in LeaderboardBoards.lua, since Row1 is always "rank 1"
	regardless of which player currently holds it - no need to recompute
	styling on every refresh.
]]

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local LeaderboardSystem = require(ServerScriptService.LeaderboardSystem)
local LeaderboardConfig = require(ServerScriptService.LeaderboardConfig)

local LeaderboardDisplay = {}

local REFRESH_INTERVAL_SECONDS = 60

local refreshLoopStarted = false

local function findBoardScroll(boardName: string): ScrollingFrame?
	local lobby = Workspace:FindFirstChild("Lobby")
	local buildings = lobby and lobby:FindFirstChild("Buildings")
	local board = buildings and buildings:FindFirstChild(boardName)
	local base = board and board:FindFirstChild("Base")
	local gui = base and base:FindFirstChild("BoardDisplay")
	local root = gui and gui:FindFirstChild("Root")
	local scroll = root and root:FindFirstChild("EntriesScroll")
	return scroll :: ScrollingFrame?
end

local function refreshCategory(category)
	local scroll = findBoardScroll(category.boardName)
	if not scroll then
		warn(("[LeaderboardDisplay] Could not find %s - skipping this refresh."):format(category.boardName))
		return
	end

	local entries = LeaderboardSystem.GetTopEntries(category.id)

	for rank = 1, LeaderboardConfig.TOP_LIMIT do
		local row = scroll:FindFirstChild("Row" .. rank)
		local nameLabel = row and row:FindFirstChild("NameLabel") :: TextLabel?
		local valueLabel = row and row:FindFirstChild("ValueLabel") :: TextLabel?
		if nameLabel and valueLabel then
			local entry = entries[rank]
			if entry then
				nameLabel.Text = entry.name
				valueLabel.Text = category.format(entry.value)
			else
				nameLabel.Text = "-"
				valueLabel.Text = "-"
			end
		end
	end
end

local function refreshAll()
	for _, category in ipairs(LeaderboardConfig.CATEGORIES) do
		task.spawn(refreshCategory, category)
	end
end

function LeaderboardDisplay.Init()
	if refreshLoopStarted then
		warn("[LeaderboardDisplay] Init() called more than once; ignoring.")
		return
	end
	refreshLoopStarted = true

	refreshAll() -- populate immediately on server start rather than waiting a full interval

	task.spawn(function()
		while true do
			task.wait(REFRESH_INTERVAL_SECONDS)
			refreshAll()
		end
	end)

	print("[LeaderboardDisplay] Initialized")
end

return LeaderboardDisplay
