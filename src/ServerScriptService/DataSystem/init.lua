--[[
	DataSystem

	Owns player data persistence. As of Message 11 this is real
	DataStore-backed storage (previously in-memory only, per the original
	design note that this interface was already shaped for the swap).
	Every other system (ProgressionSystem, ShopSystem, ...) reads/writes
	profile fields through the SAME Profile table returned by GetProfile -
	nothing else talks to DataStoreService directly, per this message's
	"single schema" instruction.

	What's saved: the entire Profile table - wins, coins, gems, xp, level,
	rank, statistics, ownedCosmetics, equippedCosmetics, and settings (see
	the Profile type below). This covers everything the message asks for
	(Coins/XP/Wins/Rank directly; Inventory+Cosmetics via owned/equipped
	cosmetics, since cosmetics are the only inventory concept that exists
	in this project; Statistics via the statistics table) plus gems,
	which obviously needs to persist alongside coins even though it
	wasn't named explicitly.

	Settings note: no Settings system exists yet (Message 8 left the
	Settings button as a "coming soon" placeholder with no backing data).
	`settings` is a generic, empty, extensible table here so persistence
	is ready for whatever a future Settings message stores in it, without
	this message inventing specific settings values that weren't asked
	for.

	Save safety (the race-condition/duplicate-loop hazard this message
	calls out):
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
		  a save loop for the same player.
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

export type Profile = {
	wins: number,
	coins: number,
	gems: number,
	xp: number,
	level: number,
	rank: string,
	currentStreak: number, -- not replicated directly; used to derive longestStreak
	statistics: Statistics,
	ownedCosmetics: { [string]: boolean }, -- set of owned CosmeticsConfig item ids (Message 10)
	equippedCosmetics: { [string]: string }, -- CosmeticsConfig category -> equipped item id
	settings: { [string]: any }, -- generic/extensible; no Settings system exists yet to populate this
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
	}
end

--[[
	Merges a freshly-loaded saved table onto a brand-new default profile,
	so a save written before a field existed (e.g. before Message 9 added
	gems, or Message 10 added cosmetics) safely fills in defaults for
	whatever's missing instead of erroring or leaving nil fields.
]]
local function reconcileWithDefaults(saved: { [string]: any }): Profile
	local profile = createDefaultProfile()

	for key, value in pairs(saved) do
		if key == "statistics" and typeof(value) == "table" then
			for statKey, statValue in pairs(value) do
				(profile.statistics :: any)[statKey] = statValue
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
	for userId in pairs(profiles) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
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
