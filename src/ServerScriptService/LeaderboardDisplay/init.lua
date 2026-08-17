--[[
	LeaderboardDisplay

	Refreshes the physical leaderboard board built into the Leaderboard
	Hall building (Workspace.Lobby.Buildings.LeaderboardHall - see
	LobbyBuilder/Buildings.lua) with live standings from LeaderboardSystem.

	This is Message 11's answer to "display leaderboards in lobby": an
	in-world SurfaceGui rather than a menu/UI panel, since Message 2 built
	this specific building back then in clear anticipation of exactly this
	feature.

	Refreshes on the same cadence as the DataStore autosave/leaderboard
	write cycle (60s), since GetSortedAsync calls also count against
	DataStore read request budgets - no reason to poll faster than the
	underlying data actually changes.
]]

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local LeaderboardSystem = require(ServerScriptService.LeaderboardSystem)

local LeaderboardDisplay = {}

local REFRESH_INTERVAL_SECONDS = 60
local DISPLAY_ROWS = 5 -- how many entries fit on the physical board (see Buildings.lua)

type CategoryDisplayInfo = {
	id: string,
	format: (value: number) -> string,
}

local CATEGORIES: { CategoryDisplayInfo } = {
	{ id = "Wins", format = function(value) return tostring(value) end },
	{ id = "XP", format = function(value) return tostring(value) end },
	{ id = "QuestionsSolved", format = function(value) return tostring(value) end },
	{ id = "Accuracy", format = function(value) return ("%.1f%%"):format(value) end },
	{ id = "FastestAnswer", format = function(value) return ("%.2fs"):format(value) end },
}

local refreshLoopStarted = false

local function findBoardRoot(): Frame?
	local lobby = Workspace:FindFirstChild("Lobby")
	local buildings = lobby and lobby:FindFirstChild("Buildings")
	local hall = buildings and buildings:FindFirstChild("LeaderboardHall")
	local base = hall and hall:FindFirstChild("Base")
	local gui = base and base:FindFirstChild("LeaderboardDisplay")
	local root = gui and gui:FindFirstChild("Root")
	return root :: Frame?
end

local function refreshCategory(root: Frame, category: CategoryDisplayInfo)
	local categoriesRow = root:FindFirstChild("CategoriesRow")
	local column = categoriesRow and categoriesRow:FindFirstChild(category.id .. "Column")
	if not column then
		return
	end

	local entries = LeaderboardSystem.GetTopEntries(category.id)

	for row = 1, DISPLAY_ROWS do
		local rowLabel = column:FindFirstChild("Row" .. row) :: TextLabel?
		if rowLabel then
			local entry = entries[row]
			if entry then
				rowLabel.Text = ("%d. %s - %s"):format(row, entry.name, category.format(entry.value))
			else
				rowLabel.Text = ("%d. -"):format(row)
			end
		end
	end
end

local function refreshAll()
	local root = findBoardRoot()
	if not root then
		warn("[LeaderboardDisplay] Could not find the LeaderboardHall display board - skipping this refresh.")
		return
	end

	for _, category in ipairs(CATEGORIES) do
		task.spawn(refreshCategory, root, category)
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
