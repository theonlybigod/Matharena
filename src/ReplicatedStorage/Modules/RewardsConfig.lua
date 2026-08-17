--[[
	RewardsConfig.lua

	Centralized reward values (XP/Coins/Gems) for every reward-granting
	event in MathArena, so future balance changes only require editing
	this one file. Pure data - no reward-granting logic lives here. See
	ProgressionSystem for the mutation functions (AwardXP/AwardCoins/
	AwardGems), and MatchSystem/CompetitionGameplay for where each reward
	is actually triggered.
]]

local RewardsConfig = {}

-- Correct answer (per question, awarded by CompetitionGameplay)
RewardsConfig.CORRECT_ANSWER_XP = 10
RewardsConfig.CORRECT_ANSWER_COINS = 5

-- Match win (awarded by MatchSystem.EndMatch to the winner, all end paths)
RewardsConfig.WIN_XP = 100
RewardsConfig.WIN_COINS = 50
RewardsConfig.WIN_GEMS = 10

-- Participation (awarded by MatchSystem.EndMatch to every finished
-- participant who did NOT win - the winner gets WIN_* instead, not both)
RewardsConfig.PARTICIPATION_XP = 25
RewardsConfig.PARTICIPATION_COINS = 5

-- Perfect game bonus: on top of the win reward, specifically when the
-- winner reached victory without ever answering a question incorrectly.
-- Awarded by CompetitionGameplay at the moment it determines a winner via
-- the normal elimination path (see that module for why every such winner
-- provably qualifies).
RewardsConfig.PERFECT_GAME_BONUS_XP = 50

-- Fast answer bonus: on top of the correct-answer reward, when a question
-- is answered within this fraction of its turn's allotted time. A
-- fraction (not a fixed second count) because the timer varies by
-- difficulty - see GameplayConfig.TIMER_SECONDS (5-10s).
RewardsConfig.FAST_ANSWER_BONUS_COINS = 10
RewardsConfig.FAST_ANSWER_TIME_FRACTION = 0.4

return RewardsConfig
