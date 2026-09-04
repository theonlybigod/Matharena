--[[
	MatchConfig.lua

	Centralized matchmaking/game-flow constants. Shared because the client
	UI needs the same numbers (e.g. displaying "X/12") without them being
	hardcoded twice.
]]

local MatchConfig = {}

--[[
	Schedule-driven, not accumulation-driven, but with a floor (design
	decision, confirmed): a match's countdown starts the moment MIN_PLAYERS
	is reached rather than waiting for a full roster to slowly accumulate,
	but MIN_PLAYERS stays at 2 deliberately - a solo match was tried at 1
	and found to be a real exploit: CompetitionGameplay's
	advanceAndBeginNextTurn checks "#alivePlayers == 1" as its WIN
	condition, which fires on the very first call for a match that STARTED
	at 1 player, before a single question is ever asked - an instant,
	zero-risk win (plus the Perfect Game bonus) with no gameplay at all,
	repeatable forever via Ready Up + Auto Ready. That code assumes a
	match only ever REACHES 1 remaining player via elimination from a
	larger field, never starts there, and reworking that assumption was
	ruled out in favour of simply never allowing a 1-player launch.
	MIN_PLAYERS=2 makes that unreachable at the source - the moment a
	second player queues, evaluateQueueForLaunch's
	`Queue.Count(...) >= MatchConfig.MIN_PLAYERS` check is satisfied and
	the countdown begins immediately, same "don't wait around" spirit as
	the original ask, just with a floor of 2 instead of 1.
]]
MatchConfig.MIN_PLAYERS = 2
MatchConfig.MAX_PLAYERS = 12

-- "Auto start up within 1 minute... more of a server thing": once
-- MIN_PLAYERS is reached, the match launches within this window
-- regardless of how many more players join in the meantime (still
-- launches EARLY if MAX_PLAYERS is reached first - unchanged).
MatchConfig.QUEUE_COUNTDOWN_SECONDS = 60

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
