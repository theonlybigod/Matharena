--[[
	TutorialSystem

	Tiny server-side counterpart to the guided first-time Play Tutorial
	(TutorialUIController.client.lua owns all the actual walk-to-this-spot
	guidance logic - purely cosmetic client-side movement/highlight stuff,
	nothing here needs to validate WHERE a player walked). This module
	only persists the one bit of state that has to survive a rejoin:
	whether the player has ever completed the guided tutorial before, so
	it only auto-starts ONCE per player, ever - not on every server join
	(replaying from the Tutorial Building always works regardless of this
	flag - see TutorialUIController's replay button).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
local DataSystem = require(ServerScriptService.DataSystem)

local TutorialSystem = {}

local getTutorialStateFunction = RemoteFunctions.Get("GetTutorialState")
local markTutorialCompletedFunction = RemoteFunctions.Get("MarkTutorialCompleted")
-- server -> client, fired once at the moment a player finishes the
-- first-time tutorial, so the quest UI can unlock without polling.
local tutorialCompletedEvent = RemoteEvents.Get("TutorialCompleted")

--[[
	Whether `player` has ever finished the first-time tutorial.

	This is the single gate the quest system uses to decide whether quests
	exist for a player yet (see QuestsSystem) - "quests should only pop up
	after they complete the tutorial for the first time". Returns false for
	a profile that hasn't loaded, which is the SAFE direction here: a
	player briefly sees no quests rather than the quest system running for
	someone who never did the tutorial.
]]
function TutorialSystem.IsCompleted(player: Player): boolean
	local profile = DataSystem.GetProfile(player)
	return profile ~= nil and profile.tutorialCompleted == true
end


function TutorialSystem.Init()
	getTutorialStateFunction.OnServerInvoke = function(player: Player)
		-- The profile can genuinely still be mid-load (DataStore GetAsync +
		-- PersistenceRetry retries) when the client asks this shortly after
		-- joining. Answering immediately based on a not-yet-loaded profile
		-- would always say "not completed" (since GetProfile returns nil),
		-- which is exactly the bug this fixes - the guided tutorial firing
		-- for a RETURNING player every single join, not just their first
		-- ever one. So: wait (bounded) for the real profile instead of
		-- guessing from an absent one.
		local profile = DataSystem.GetProfile(player)
		local waited = 0
		while not profile and waited < 15 and player.Parent do
			task.wait(0.5)
			waited += 0.5
			profile = DataSystem.GetProfile(player)
		end

		if not profile then
			-- Profile still never loaded (extremely rare - DataSystem's own
			-- retry/fallback logic should have produced at least a temporary
			-- profile well before 15s). Default to "completed" rather than
			-- "not completed" here - firing the guided tutorial on a broken
			-- load is a worse experience than just skipping it once.
			return { completed = true }
		end

		return { completed = profile.tutorialCompleted == true }
	end

	--[[
		Records first-time completion. Purely cosmetic to "cheat" (there is
		no gameplay consequence to finishing a walkthrough), so the client is
		trusted to report it - but this is now the QUEST UNLOCK gate too, so
		it does two things carefully:

		  1. It is IDEMPOTENT. Replaying from the Tutorial Building never
		     reaches here at all (the client only calls this on a genuine
		     first run - see TutorialUIController's `isReplay`), but even if
		     it did, a second call cannot re-fire the unlock event or
		     otherwise disturb an already-completed player.
		  2. It fires TutorialCompleted exactly ONCE, on the transition, so
		     the client's quest UI unlocks the moment the tutorial ends
		     rather than on the next poll.
	]]
	markTutorialCompletedFunction.OnServerInvoke = function(player: Player)
		local profile = DataSystem.GetProfile(player)
		if not profile then
			warn(("[TutorialSystem] %s finished the tutorial but has no loaded profile - completion NOT persisted."):format(player.Name))
			return { success = false }
		end

		if profile.tutorialCompleted == true then
			return { success = true, alreadyCompleted = true }
		end

		profile.tutorialCompleted = true
		tutorialCompletedEvent:FireClient(player)
		print(("[TutorialSystem] %s completed the first-time tutorial - quests unlocked."):format(player.Name))
		return { success = true }
	end

	print("[TutorialSystem] Initialized")
end

return TutorialSystem
