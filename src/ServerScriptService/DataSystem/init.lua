--[[
	DataSystem

	Owns player data persistence. For this pass (Message 4), profiles live
	in memory only — DataStore persistence is intentionally deferred to
	Message 11. The public interface (LoadProfile/GetProfile/ReleaseProfile/
	SaveProfile) is already shaped the way it will be once DataStore-backed,
	so callers (ProgressionSystem, GameManager) won't need to change when
	real persistence is added.
]]

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
	xp: number,
	level: number,
	rank: string,
	currentStreak: number, -- not replicated directly; used to derive longestStreak
	statistics: Statistics,
}

local profiles: { [number]: Profile } = {}

local function createDefaultProfile(): Profile
	return {
		wins = 0,
		coins = 0,
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
	}
end

--[[
	Loads (or creates, if none exists) the profile for a player.

	TODO (Message 11): replace the in-memory default with an actual
	DataStore fetch, falling back to createDefaultProfile() only when no
	saved data exists for this player.
]]
function DataSystem.LoadProfile(player: Player): Profile
	local existing = profiles[player.UserId]
	if existing then
		return existing
	end

	local profile = createDefaultProfile()
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
	TODO (Message 11): actually write `profile` to the player's DataStore
	entry, with retries/error handling. Currently a no-op placeholder so
	the call site already exists and won't need to move later.
]]
function DataSystem.SaveProfile(player: Player)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end

	print(
		("[DataSystem] SaveProfile(%s) called - no-op until Message 11 (DataStore persistence)."):format(player.Name)
	)
end

--[[
	Releases a player's profile from memory. Called when a player leaves.
	Saves first (currently a no-op) so that save call site is already wired.
]]
function DataSystem.ReleaseProfile(player: Player)
	DataSystem.SaveProfile(player)
	profiles[player.UserId] = nil
end

function DataSystem.Init()
	print("[DataSystem] Initialized (in-memory profiles only; DataStore persistence arrives in Message 11)")
end

return DataSystem
