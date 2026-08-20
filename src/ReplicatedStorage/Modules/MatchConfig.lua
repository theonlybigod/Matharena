--[[
	MatchConfig.lua

	Centralized matchmaking/game-flow constants. Shared because the client
	UI needs the same numbers (e.g. displaying "X/12") without them being
	hardcoded twice.
]]

local MatchConfig = {}

MatchConfig.MIN_PLAYERS = 2
MatchConfig.MAX_PLAYERS = 12

MatchConfig.QUEUE_COUNTDOWN_SECONDS = 15

MatchConfig.INTRO_STEPS = { "3", "2", "1", "GO" }
MatchConfig.INTRO_STEP_SECONDS = 1

MatchConfig.WINNER_DISPLAY_SECONDS = 8
MatchConfig.RETURNING_SECONDS = 3

-- "Starting" covers both the pre-teleport queue countdown and the
-- post-teleport 3-2-1-GO intro; "Playing" begins the moment GO fires.
MatchConfig.GameState = {
	Lobby = "Lobby",
	Waiting = "Waiting",
	Starting = "Starting",
	Playing = "Playing",
	Winner = "Winner",
	Returning = "Returning",
}

return MatchConfig
