--[[
	ProgressionSystem

	Server-authoritative progression logic: awarding XP/coins/wins,
	recording match/question statistics, and keeping each player's
	replicated "leaderstats" and "Statistics" folders in sync with their
	DataSystem profile.

	Only server code should ever call the Award*/Record* functions here.
	Client code must never be trusted to grant XP, coins, wins, ranks, or
	statistics — the only RemoteEvent this module owns is "RewardGranted",
	which is one-way server -> client (a notification for the floating
	reward popup, Message 12) and carries no client input whatsoever.
	Gameplay systems (MatchSystem, CompetitionGameplay, ShopSystem) call
	the Award*/Spend* functions directly from server code.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProgressionConfig = require(ReplicatedStorage.Modules.ProgressionConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local DataSystem = require(script.Parent.DataSystem)

local ProgressionSystem = {}

-- Message 12: notifies the client of an individual XP/Coins/Gems grant so
-- it can show a floating "+10 XP"-style popup. Deliberately NOT fired for
-- AwardWin - the Winner announcement/audio/confetti already give that
-- moment strong feedback on its own, and stacking a redundant "+1 Win"
-- popup on top would be visual noise rather than useful information.
local rewardGrantedEvent = RemoteEvents.Get("RewardGranted")

local function createIntValue(name: string, parent: Instance): IntValue
	local value = Instance.new("IntValue")
	value.Name = name
	value.Value = 0
	value.Parent = parent
	return value
end

local function createNumberValue(name: string, parent: Instance): NumberValue
	local value = Instance.new("NumberValue")
	value.Name = name
	value.Value = 0
	value.Parent = parent
	return value
end

local function buildLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	createIntValue("Wins", leaderstats)
	createIntValue("Coins", leaderstats)
	createIntValue("Gems", leaderstats)
	createIntValue("XP", leaderstats)
	createIntValue("Level", leaderstats)

	local rank = Instance.new("StringValue")
	rank.Name = "Rank"
	rank.Value = ProgressionConfig.RANKS[1]
	rank.Parent = leaderstats

	leaderstats.Parent = player
end

local function buildStatistics(player: Player)
	local statistics = Instance.new("Folder")
	statistics.Name = "Statistics"

	createIntValue("GamesPlayed", statistics)
	createIntValue("GamesWon", statistics)
	createIntValue("QuestionsAnswered", statistics)
	createIntValue("CorrectAnswers", statistics)
	createIntValue("IncorrectAnswers", statistics)
	createNumberValue("Accuracy", statistics)

	local fastest = createNumberValue("FastestAnswer", statistics)
	fastest.Value = -1 -- sentinel: no answer recorded yet

	createIntValue("LongestStreak", statistics)

	statistics.Parent = player
end

--[[
	Pushes the current profile values onto the player's replicated
	"leaderstats" folder. Safe to call any time after SetupPlayer.
]]
function ProgressionSystem.RefreshLeaderstats(player: Player)
	local profile = DataSystem.GetProfile(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not profile or not leaderstats then
		return
	end

	local wins = leaderstats:FindFirstChild("Wins") :: IntValue
	local coins = leaderstats:FindFirstChild("Coins") :: IntValue
	local gems = leaderstats:FindFirstChild("Gems") :: IntValue
	local xp = leaderstats:FindFirstChild("XP") :: IntValue
	local level = leaderstats:FindFirstChild("Level") :: IntValue
	local rank = leaderstats:FindFirstChild("Rank") :: StringValue

	wins.Value = profile.wins
	coins.Value = profile.coins
	gems.Value = profile.gems
	xp.Value = profile.xp
	level.Value = profile.level
	rank.Value = profile.rank
end

--[[
	Pushes the current profile statistics onto the player's replicated
	"Statistics" folder. Safe to call any time after SetupPlayer.
]]
function ProgressionSystem.RefreshStatistics(player: Player)
	local profile = DataSystem.GetProfile(player)
	local statistics = player:FindFirstChild("Statistics")
	if not profile or not statistics then
		return
	end

	local s = profile.statistics

	local gamesPlayed = statistics:FindFirstChild("GamesPlayed") :: IntValue
	local gamesWon = statistics:FindFirstChild("GamesWon") :: IntValue
	local questionsAnswered = statistics:FindFirstChild("QuestionsAnswered") :: IntValue
	local correctAnswers = statistics:FindFirstChild("CorrectAnswers") :: IntValue
	local incorrectAnswers = statistics:FindFirstChild("IncorrectAnswers") :: IntValue
	local accuracy = statistics:FindFirstChild("Accuracy") :: NumberValue
	local fastestAnswer = statistics:FindFirstChild("FastestAnswer") :: NumberValue
	local longestStreak = statistics:FindFirstChild("LongestStreak") :: IntValue

	gamesPlayed.Value = s.gamesPlayed
	gamesWon.Value = s.gamesWon
	questionsAnswered.Value = s.questionsAnswered
	correctAnswers.Value = s.correctAnswers
	incorrectAnswers.Value = s.incorrectAnswers
	accuracy.Value = s.accuracy
	fastestAnswer.Value = s.fastestAnswerSeconds
	longestStreak.Value = s.longestStreak
end

--[[
	Sets up a freshly-joined player: loads their profile and builds their
	replicated leaderstats/Statistics folders from it. Call from
	Players.PlayerAdded (currently wired in GameManager).
]]
function ProgressionSystem.SetupPlayer(player: Player)
	local profile = DataSystem.LoadProfile(player)

	buildLeaderstats(player)
	buildStatistics(player)

	profile.rank = ProgressionConfig.GetRankForLevel(profile.level)

	ProgressionSystem.RefreshLeaderstats(player)
	ProgressionSystem.RefreshStatistics(player)
end

--[[
	Releases a leaving player's profile. The leaderstats/Statistics
	Instances are destroyed automatically along with the Player instance;
	there's nothing to clean up on that side here. Call from
	Players.PlayerRemoving (currently wired in GameManager).
]]
function ProgressionSystem.TeardownPlayer(player: Player)
	DataSystem.ReleaseProfile(player)
end

--[[
	Awards lifetime XP and recomputes level/rank from the new total. XP is
	cumulative and never decreases; a level-up (and possible rank-up) is a
	side effect of crossing a threshold, not a separate action callers need
	to trigger themselves.
]]
function ProgressionSystem.AwardXP(player: Player, amount: number)
	if amount <= 0 then
		return
	end

	local profile = DataSystem.GetProfile(player)
	if not profile then
		warn(("[ProgressionSystem] AwardXP called for %s with no loaded profile."):format(player.Name))
		return
	end

	profile.xp += amount
	profile.level = ProgressionConfig.GetLevelFromTotalXP(profile.xp)
	profile.rank = ProgressionConfig.GetRankForLevel(profile.level)

	ProgressionSystem.RefreshLeaderstats(player)
	rewardGrantedEvent:FireClient(player, { type = "XP", amount = amount })
end

function ProgressionSystem.AwardCoins(player: Player, amount: number)
	if amount <= 0 then
		return
	end

	local profile = DataSystem.GetProfile(player)
	if not profile then
		warn(("[ProgressionSystem] AwardCoins called for %s with no loaded profile."):format(player.Name))
		return
	end

	profile.coins += amount
	ProgressionSystem.RefreshLeaderstats(player)
	rewardGrantedEvent:FireClient(player, { type = "Coins", amount = amount })
end

function ProgressionSystem.AwardGems(player: Player, amount: number)
	if amount <= 0 then
		return
	end

	local profile = DataSystem.GetProfile(player)
	if not profile then
		warn(("[ProgressionSystem] AwardGems called for %s with no loaded profile."):format(player.Name))
		return
	end

	profile.gems += amount
	ProgressionSystem.RefreshLeaderstats(player)
	rewardGrantedEvent:FireClient(player, { type = "Gems", amount = amount })
end

--[[
	Spends coins if the player has enough. Returns true and deducts on
	success; returns false (no mutation) if there's no loaded profile or
	insufficient funds. Used by the shop (Message 10) so ShopSystem never
	needs to touch profile.coins directly - purchases go through this
	same trusted, server-only mutation surface as every other Award*
	function here.
]]
function ProgressionSystem.SpendCoins(player: Player, amount: number): boolean
	if amount <= 0 then
		return true
	end

	local profile = DataSystem.GetProfile(player)
	if not profile then
		warn(("[ProgressionSystem] SpendCoins called for %s with no loaded profile."):format(player.Name))
		return false
	end

	if profile.coins < amount then
		return false
	end

	profile.coins -= amount
	ProgressionSystem.RefreshLeaderstats(player)
	return true
end

--[[
	Spends gems if the player has enough. See SpendCoins - same contract.
]]
function ProgressionSystem.SpendGems(player: Player, amount: number): boolean
	if amount <= 0 then
		return true
	end

	local profile = DataSystem.GetProfile(player)
	if not profile then
		warn(("[ProgressionSystem] SpendGems called for %s with no loaded profile."):format(player.Name))
		return false
	end

	if profile.gems < amount then
		return false
	end

	profile.gems -= amount
	ProgressionSystem.RefreshLeaderstats(player)
	return true
end

function ProgressionSystem.AwardWin(player: Player)
	local profile = DataSystem.GetProfile(player)
	if not profile then
		warn(("[ProgressionSystem] AwardWin called for %s with no loaded profile."):format(player.Name))
		return
	end

	profile.wins += 1
	ProgressionSystem.RefreshLeaderstats(player)
end

--[[
	Records the outcome of a single answered question. `timeTakenSeconds`
	is optional; pass nil if timing isn't tracked for that answer.
	Recomputes accuracy and (on a correct answer) streak/fastest-answer.
]]
function ProgressionSystem.RecordQuestionAnswer(player: Player, isCorrect: boolean, timeTakenSeconds: number?)
	local profile = DataSystem.GetProfile(player)
	if not profile then
		warn(("[ProgressionSystem] RecordQuestionAnswer called for %s with no loaded profile."):format(player.Name))
		return
	end

	local stats = profile.statistics
	stats.questionsAnswered += 1

	if isCorrect then
		stats.correctAnswers += 1
		profile.currentStreak += 1
		stats.longestStreak = math.max(stats.longestStreak, profile.currentStreak)

		if timeTakenSeconds and (stats.fastestAnswerSeconds < 0 or timeTakenSeconds < stats.fastestAnswerSeconds) then
			stats.fastestAnswerSeconds = timeTakenSeconds
		end
	else
		stats.incorrectAnswers += 1
		profile.currentStreak = 0
	end

	stats.accuracy = if stats.questionsAnswered > 0
		then math.round((stats.correctAnswers / stats.questionsAnswered) * 1000) / 10
		else 0

	ProgressionSystem.RefreshStatistics(player)
end

--[[
	Records that a game finished for this player (games played + won).
	Awarding an actual leaderstat "win" is separate (see AwardWin) so
	callers can decide whether a completed game should also count as a
	leaderstat win (e.g. only the tournament winner gets one).
]]
function ProgressionSystem.RecordGameCompleted(player: Player, didWin: boolean)
	local profile = DataSystem.GetProfile(player)
	if not profile then
		warn(("[ProgressionSystem] RecordGameCompleted called for %s with no loaded profile."):format(player.Name))
		return
	end

	profile.statistics.gamesPlayed += 1
	if didWin then
		profile.statistics.gamesWon += 1
	end

	ProgressionSystem.RefreshStatistics(player)
end

function ProgressionSystem.Init()
	print("[ProgressionSystem] Initialized")
end

return ProgressionSystem
