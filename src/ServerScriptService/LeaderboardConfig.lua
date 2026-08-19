--[[
	LeaderboardConfig.lua

	Single shared source of truth for the five MathArena leaderboard
	categories (Wins, XP, Questions Solved, Accuracy, Fastest Answer):
	their stable board names, display names, per-category accent colors,
	value formatting, and the DataStore-facing raw/display value mapping.

	Every leaderboard-touching system requires THIS module instead of
	keeping its own copy of the category list, so the five categories are
	defined in exactly one place:
		- LeaderboardSystem (ServerScriptService) - OrderedDataStore reads/
		  writes, using each category's ascending/toRawValue/toDisplayValue.
		- LeaderboardDisplay (ServerScriptService) - refreshes the physical
		  boards' row text using each category's displayName/format.
		- LobbyBuilder/LeaderboardBoards.lua - builds the five physical
		  board instances, named/tagged from boardName/accentColor here.

	Lives in ServerScriptService (not ReplicatedStorage) because every
	consumer is a server-side system - matches the existing precedent of
	LobbyBuilder/LobbyConfig.lua, which is also server-only world-building
	data kept out of ReplicatedStorage.

	IMPORTANT (do not break existing data): `id` values below (Wins, XP,
	QuestionsSolved, Accuracy, FastestAnswer) are also the OrderedDataStore
	key suffixes LeaderboardSystem has always used. Renaming any `id` here
	would silently start writing to different DataStores and orphan all
	existing standings - don't do that.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Modules.Config)
local MapConfig = require(ServerScriptService.LobbyBuilder.MapConfig)

local LeaderboardConfig = {}

-- Roblox's OrderedDataStore:GetSortedAsync caps a single page at 100
-- entries, which is also exactly our "Top 100" requirement - one page,
-- no pagination needed.
LeaderboardConfig.TOP_LIMIT = 100

-- How many rows are visible in a board's scroll viewport at once (the
-- "~10 players" requirement). This plus ROW_HEIGHT_PIXELS below is what
-- actually determines the physical viewport height - see
-- LobbyBuilder/LeaderboardBoards.lua.
LeaderboardConfig.VISIBLE_ROWS = 10
LeaderboardConfig.ROW_HEIGHT_PIXELS = 60

-- Fixed-pixel SurfaceGui canvas, the same on all five boards. Using a
-- fixed canvas (rather than trusting SurfaceGui's default PixelsPerStud
-- behavior) makes "approximately 10 rows visible" an explicit, verifiable
-- number instead of something that depends on undocumented engine
-- defaults.
LeaderboardConfig.GUI_CANVAS_SIZE = Vector2.new(500, 700)
LeaderboardConfig.TITLE_HEIGHT_PIXELS = 80

-- Circular/surrounding arc layout (Message 19 revision - previously a
-- shallow, mostly-flat bow). ARC_SPREAD_RADIUS fans the boards out
-- sideways; ARC_DEPTH is now a substantial fraction of that spread
-- (0.55x, not the old ~0.22x) so the five boards genuinely curve around
-- an implied viewing point in front of them rather than reading as five
-- flat screens in a line - "partially surrounding the viewing area" per
-- the design brief. Both scaled by MapConfig's map-scale factor. All
-- three numbers (plus ARC_TOTAL_DEGREES and LobbyConfig.LEADERBOARD_ANCHOR)
-- were verified together via a Python position/clearance check before
-- being applied - see LobbyConfig.lua's LEADERBOARD_ANCHOR comment for
-- the actual resulting margins against the map boundary and
-- StatisticsBuilding.
LeaderboardConfig.ARC_TOTAL_DEGREES = 130
LeaderboardConfig.ARC_SPREAD_RADIUS = 34 * MapConfig.SCALE_FACTOR
LeaderboardConfig.ARC_DEPTH_FACTOR = 0.55
LeaderboardConfig.ARC_DEPTH = LeaderboardConfig.ARC_SPREAD_RADIUS * LeaderboardConfig.ARC_DEPTH_FACTOR

-- Message 19: "increase the physical size... major landmarks" - up from
-- 13x15. Re-verified (see above) that this larger size still leaves
-- ~16 studs of clearance between adjacent boards along the arc.
LeaderboardConfig.BOARD_WIDTH = 17
LeaderboardConfig.BOARD_HEIGHT = 19

-- Podium colors, shared by both the physical board (rank badge fill) and
-- the client-side glow accent script.
LeaderboardConfig.PODIUM_COLORS = {
	[1] = Color3.fromRGB(255, 215, 0), -- gold
	[2] = Color3.fromRGB(200, 205, 214), -- silver
	[3] = Color3.fromRGB(205, 127, 50), -- bronze
}

export type CategoryConfig = {
	id: string,
	displayName: string,
	boardName: string,
	accentColor: Color3,
	ascending: boolean, -- true = lower raw value is better (only FastestAnswer)
	toRawValue: (profile: any) -> number?, -- nil = skip writing this category for this profile
	toDisplayValue: (raw: number) -> number,
	format: (value: number) -> string,
}

-- ASSUMPTION (documented, not stopped for): the design doc doesn't specify
-- per-category accent colors beyond "subtle differences appropriate to
-- each category" - Wins keeps the shared brand color (it's the flagship
-- stat); the other four get distinct, complementary futuristic hues.
LeaderboardConfig.CATEGORIES = {
	{
		id = "Wins",
		displayName = "Wins",
		boardName = "WinsLeaderboard",
		accentColor = Config.BRAND_NEON_COLOR,
		ascending = false,
		toRawValue = function(profile)
			return profile.wins
		end,
		toDisplayValue = function(raw)
			return raw
		end,
		format = function(value)
			return tostring(value)
		end,
	},
	{
		id = "XP",
		displayName = "XP",
		boardName = "XPLeaderboard",
		accentColor = Color3.fromRGB(155, 90, 230),
		ascending = false,
		toRawValue = function(profile)
			return profile.xp
		end,
		toDisplayValue = function(raw)
			return raw
		end,
		format = function(value)
			return tostring(value)
		end,
	},
	{
		id = "QuestionsSolved",
		displayName = "Questions Solved",
		boardName = "QuestionsSolvedLeaderboard",
		accentColor = Color3.fromRGB(60, 220, 130),
		ascending = false,
		toRawValue = function(profile)
			return profile.statistics.correctAnswers
		end,
		toDisplayValue = function(raw)
			return raw
		end,
		format = function(value)
			return tostring(value)
		end,
	},
	{
		id = "Accuracy",
		displayName = "Accuracy",
		boardName = "AccuracyLeaderboard",
		accentColor = Color3.fromRGB(60, 220, 210),
		ascending = false,
		-- OrderedDataStore values must be non-negative integers - accuracy
		-- (0-100, one decimal place) is stored as round(accuracy * 10)
		-- (e.g. 87.3% -> 873) and divided back by 10 for display.
		toRawValue = function(profile)
			return math.floor(profile.statistics.accuracy * 10 + 0.5)
		end,
		toDisplayValue = function(raw)
			return raw / 10
		end,
		format = function(value)
			return ("%.1f%%"):format(value)
		end,
	},
	{
		id = "FastestAnswer",
		displayName = "Fastest Answer",
		boardName = "FastestAnswerLeaderboard",
		accentColor = Color3.fromRGB(255, 140, 60),
		ascending = true, -- lower is better - only this leaderboard sorts ascending
		-- Stored as whole milliseconds (fractional seconds aren't valid
		-- OrderedDataStore values), divided back by 1000 for display.
		-- Players with no recorded fastest answer yet (the -1 sentinel,
		-- see DataSystem) are skipped entirely rather than written as an
		-- artificial "fastest of all".
		toRawValue = function(profile)
			local seconds = profile.statistics.fastestAnswerSeconds
			if seconds < 0 then
				return nil
			end
			return math.floor(seconds * 1000 + 0.5)
		end,
		toDisplayValue = function(raw)
			return raw / 1000
		end,
		format = function(value)
			return ("%.2fs"):format(value)
		end,
	},
}

return LeaderboardConfig
