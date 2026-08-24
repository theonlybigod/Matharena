--[[
	DataSystem

	Owns player data persistence. Real DataStore-backed storage. Every
	other system (ProgressionSystem, ShopSystem, QuestsSystem, ...) reads/
	writes profile fields through the SAME Profile table returned by
	GetProfile - nothing else talks to DataStoreService directly, per the
	"single schema" rule.

	What's saved: the entire Profile table - wins, coins, gems, xp, level,
	rank, statistics, ownedCosmetics, equippedCosmetics, settings,
	dailyRewards (streak + capped claim history), claimedLifetimeMilestones,
	quests (slot-based quest state), tutorialCompleted, totalPlayTimeSeconds.

	Save safety (race-condition/duplicate-loop hazards):
		- LoadProfile retries GetAsync (see PersistenceRetry). If every
		  attempt fails, the player gets an in-memory-only default
		  profile for this session and is NEVER auto/leave-saved (see
		  loadSucceeded below) - this prevents a transient read failure
		  from silently overwriting a player's real saved data with a
		  blank profile the next time this session saves.
		- Saves (autosave + on-leave) are serialized per player: a save
		  waits out any save already in flight for that SAME player
		  before starting its own, so the periodic autosave loop and a
		  leave-triggered save can never race each other for one player.
		  Different players save fully independently/in parallel.
		- A single shared autosave loop (task.spawn'd once from Init)
		  iterates every currently-loaded profile every 60s - there is
		  deliberately no per-player timer, so nothing can double-schedule
		  a save loop for the same player. This same loop is also where
		  totalPlayTimeSeconds accumulates (once per tick, for every
		  profile currently loaded - i.e. the player is actually online).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local PersistenceRetry = require(script.Parent.PersistenceRetry)
local LeaderboardSystem = require(script.Parent.LeaderboardSystem)

local DataSystem = {}

export type Statistics = {
	gamesPlayed: number,
	gamesWon: number,
	questionsAnswered: number,
	correctAnswers: number,
	incorrectAnswers: number,
	accuracy: number, -- percentage, 0-100
	fastestAnswerSeconds: number, -- -1 means "no answer recorded yet"
	longestStreak: number,
}

-- Practice Mode's own statistics, tracked entirely separately from the
-- competitive Statistics above - answering practice questions must never
-- move gamesPlayed/gamesWon/questionsAnswered/etc. on the competitive side.
export type PracticeStatistics = {
	questionsAnswered: number,
	correctAnswers: number,
	incorrectAnswers: number,
	accuracy: number, -- percentage, 0-100
	fastestAnswerSeconds: number, -- -1 means "no answer recorded yet"
	averageAnswerTimeSeconds: number,
	currentStreak: number,
	bestStreak: number,
}

-- One real calendar-day claim, kept in a short capped log so the Daily
-- Rewards UI can show "further days you've had" beyond the current 7-day
-- ring - see DailyRewardsSystem.MAX_HISTORY_ENTRIES ("keep history
-- pretty short... maybe one week back at most, nothing more than that").
export type DailyClaimRecord = {
	unixTime: number,
	day: number, -- which DAY_TRACK entry (1-7) was claimed
	label: string, -- the reward label at the time of claim, so re-labeling DAY_TRACK later doesn't rewrite history
}

export type DailyRewardsState = {
	lastClaimUnix: number,
	streakDay: number,
	totalClaims: number,
	history: { DailyClaimRecord }, -- most-recent-last log of real claims, capped
}

-- Per-SLOT state for the repeatable quest loop (QuestsConfig/QuestsSystem)
-- - keyed by SlotDef.slotId ("Standard1"/"Standard2"/"Daily"), NOT by
-- quest id, since a slot's assigned quest changes every claim/refresh.
export type QuestState = {
	questId: string, -- which QuestsConfig quest is CURRENTLY assigned to this slot
	effectiveKind: string, -- "standard" | "daily" | "challenge" - what's actually rolled in right now
	accepted: boolean,
	snapshotValue: number, -- the quest's metric value AT THE MOMENT it was accepted
	nextAvailableAt: number, -- unix time this slot's quest becomes offerable (0 = immediately)
	notifiedReady: boolean, -- whether the "New Quest Available" banner has already fired for the current cooldown expiry
	lastDayNumber: number?, -- daily slot only: which UTC day number was last rolled
	refreshesUsed: number, -- standard slots only: how many of today's REFRESHES_PER_DAY have been used
	refreshDayNumber: number, -- which UTC day refreshesUsed is counted against (resets to 0 on a new day)
}

export type Profile = {
	wins: number,
	coins: number,
	gems: number,
	xp: number,
	level: number,
	rank: string,
	currentStreak: number, -- not replicated directly; used to derive longestStreak
	totalPlayTimeSeconds: number, -- accumulated in DataSystem's autosave loop while a profile is loaded; backs the Lifetime Rewards "time played" category
	statistics: Statistics,
	ownedCosmetics: { [string]: boolean }, -- set of owned CosmeticsConfig item ids
	equippedCosmetics: { [string]: string }, -- CosmeticsConfig category -> equipped item id
	settings: { [string]: any }, -- generic/extensible
	claimedRewardMilestones: { [string]: boolean }, -- win-based Rewards track: set of claimed winsRequired milestones, KEYED BY STRING since DataStore round-trips numeric table keys into strings anyway
	practiceStatistics: PracticeStatistics,
	dailyRewards: DailyRewardsState,
	claimedLifetimeMilestones: { [string]: boolean }, -- LifetimeRewardsConfig: set of claimed milestone ids
	quests: { [string]: QuestState }, -- QuestsConfig SlotDef.slotId -> state
	tutorialCompleted: boolean, -- whether the player has ever finished the guided first-time Play Tutorial - gates whether it auto-starts again; replaying from the Tutorial Building always works regardless of this flag
}

local PROFILE_STORE_NAME = "MathArena_PlayerProfiles_v1"
local profileStore = DataStoreService:GetDataStore(PROFILE_STORE_NAME)

local AUTOSAVE_INTERVAL_SECONDS = 60
local SAVE_WAIT_TIMEOUT_SECONDS = 10 -- cap on waiting out an in-flight save for the same player

local profiles: { [number]: Profile } = {}
-- true only if this session's profile came from a real DataStore read (or
-- is a brand-new player) - gates whether it's safe to save (see doc comment).
local loadSucceeded: { [number]: boolean } = {}
local savingInProgress: { [number]: boolean } = {}
local autosaveLoopStarted = false

local function profileKey(userId: number): string
	return ("Player_%d"):format(userId)
end

local function createDefaultProfile(): Profile
	return {
		wins = 0,
		coins = 0,
		gems = 0,
		xp = 0,
		level = 1,
		rank = "Beginner",
		currentStreak = 0,
		statistics = {
			gamesPlayed = 0,
			gamesWon = 0,
			questionsAnswered = 0,
			correctAnswers = 0,
			incorrectAnswers = 0,
			accuracy = 0,
			fastestAnswerSeconds = -1,
			longestStreak = 0,
		},
		ownedCosmetics = {},
		equippedCosmetics = {},
		settings = {},
		claimedRewardMilestones = {},
		practiceStatistics = {
			questionsAnswered = 0,
			correctAnswers = 0,
			incorrectAnswers = 0,
			accuracy = 0,
			fastestAnswerSeconds = -1,
			averageAnswerTimeSeconds = 0,
			currentStreak = 0,
			bestStreak = 0,
		},
		dailyRewards = {
			lastClaimUnix = 0,
			streakDay = 0,
			totalClaims = 0,
			history = {},
		},
		claimedLifetimeMilestones = {},
		quests = {},
		totalPlayTimeSeconds = 0,
		tutorialCompleted = false,
	}
end

--[[
	Merges a freshly-loaded saved table onto a brand-new default profile,
	so a save written before a field existed safely fills in defaults for
	whatever's missing instead of erroring or leaving nil fields.
]]
local function reconcileWithDefaults(saved: { [string]: any }): Profile
	local profile = createDefaultProfile()

	for key, value in pairs(saved) do
		if (key == "statistics" or key == "practiceStatistics" or key == "dailyRewards") and typeof(value) == "table" then
			local target = if key == "statistics"
				then profile.statistics
				elseif key == "practiceStatistics" then profile.practiceStatistics
				else profile.dailyRewards
			for statKey, statValue in pairs(value) do
				(target :: any)[statKey] = statValue
			end
		elseif key == "claimedLifetimeMilestones" and typeof(value) == "table" then
			for claimKey, claimValue in pairs(value) do
				profile.claimedLifetimeMilestones[claimKey] = claimValue
			end
		elseif key == "quests" and typeof(value) == "table" then
			for slotId, questState in pairs(value) do
				profile.quests[slotId] = questState
			end
		else
			(profile :: any)[key] = value
		end
	end

	return profile
end

--[[
	Loads (or creates, if none exists) the profile for a player. Retries
	the DataStore read; on repeated failure, falls back to an in-memory-
	only default profile for this session and marks loadSucceeded=false
	so this session is never saved (see module doc comment above).
]]
function DataSystem.LoadProfile(player: Player): Profile
	local existing = profiles[player.UserId]
	if existing then
		return existing
	end

	local ok, result = PersistenceRetry.Attempt(function()
		return profileStore:GetAsync(profileKey(player.UserId))
	end)

	local profile: Profile
	if ok then
		profile = if result then reconcileWithDefaults(result :: any) else createDefaultProfile()
		loadSucceeded[player.UserId] = true
	else
		warn(
			("[DataSystem] LoadProfile FAILED for %s after retries (%s) - using a TEMPORARY, UNSAVED default profile for this session."):format(
				player.Name,
				tostring(result)
			)
		)
		profile = createDefaultProfile()
		loadSucceeded[player.UserId] = false
	end

	profiles[player.UserId] = profile
	return profile
end

--[[
	Returns the already-loaded profile for a player, or nil if LoadProfile
	hasn't been called for them yet (or their data was already released).
]]
function DataSystem.GetProfile(player: Player): Profile?
	return profiles[player.UserId]
end

--[[
	Saves `player`'s current profile to DataStore right now, waiting out
	any save already in flight for this SAME player first (never two
	concurrent SetAsync calls for one player). Safe to call from both the
	autosave loop and on-leave. Does nothing (and returns false) if this
	session's initial load never actually succeeded, to avoid overwriting
	real saved data with a blank/partial profile (see module doc comment).
	On a successful profile save, also pushes this player's updated
	standing to LeaderboardSystem.
]]
function DataSystem.SaveProfile(player: Player, context: string?): boolean
	local userId = player.UserId
	local profile = profiles[userId]
	if not profile then
		return false
	end

	if not loadSucceeded[userId] then
		warn(
			("[DataSystem] Skipping save (%s) for %s - this session's initial load never succeeded."):format(
				context or "save",
				player.Name
			)
		)
		return false
	end

	local waited = 0
	while savingInProgress[userId] and waited < SAVE_WAIT_TIMEOUT_SECONDS do
		task.wait(0.1)
		waited += 0.1
	end

	savingInProgress[userId] = true
	local ok = PersistenceRetry.Attempt(function()
		profileStore:SetAsync(profileKey(userId), profile)
	end)
	savingInProgress[userId] = false

	if ok then
		LeaderboardSystem.UpdateEntries(player, profile)
	else
		warn(("[DataSystem] Save (%s) FAILED for %s after retries."):format(context or "save", player.Name))
	end

	return ok
end

--[[
	Releases a player's profile from memory. Called when a player leaves.
	Saves first (the final save-on-leave) so the last in-session changes
	are captured before the profile is dropped.
]]
function DataSystem.ReleaseProfile(player: Player)
	DataSystem.SaveProfile(player, "leave")
	profiles[player.UserId] = nil
	loadSucceeded[player.UserId] = nil
	savingInProgress[player.UserId] = nil
end

--[[
	Iterates every currently-loaded profile and saves it. Runs once every
	AUTOSAVE_INTERVAL_SECONDS via the loop started in Init() - a single
	shared loop, not a per-player timer, so nothing can double-schedule an
	autosave for the same player. Each player's save runs concurrently
	(task.spawn) so one slow DataStore call can't delay everyone else's.
]]
local function autosaveAll()
	for userId, profile in pairs(profiles) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			-- Playtime accumulates here (once per AUTOSAVE_INTERVAL_SECONDS
			-- tick, for every profile currently loaded - i.e. the player is
			-- actually online right now) rather than a separate timer, so
			-- there is exactly one place that advances it.
			profile.totalPlayTimeSeconds = (profile.totalPlayTimeSeconds or 0) + AUTOSAVE_INTERVAL_SECONDS
			task.spawn(DataSystem.SaveProfile, player, "autosave")
		end
	end
end

local function startAutosaveLoop()
	if autosaveLoopStarted then
		warn("[DataSystem] startAutosaveLoop() called more than once; ignoring.")
		return
	end
	autosaveLoopStarted = true

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL_SECONDS)
			autosaveAll()
		end
	end)
end

function DataSystem.Init()
	startAutosaveLoop()
	print(
		("[DataSystem] Initialized (DataStore-backed profiles, autosave every %ds)"):format(AUTOSAVE_INTERVAL_SECONDS)
	)
end

return DataSystem
