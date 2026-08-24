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

local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
local DataSystem = require(ServerScriptService.DataSystem)

local TutorialSystem = {}

local getTutorialStateFunction = RemoteFunctions.Get("GetTutorialState")
local markTutorialCompletedFunction = RemoteFunctions.Get("MarkTutorialCompleted")

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

	-- Trusted client -> server signal, same as TutorialUIController's own
	-- doc comment on the static topic panel: purely cosmetic, nothing for
	-- the server to validate (there's no way to "cheat" finishing a guided
	-- walkthrough that has no gameplay consequence), so this just records
	-- the flag the client reports.
	markTutorialCompletedFunction.OnServerInvoke = function(player: Player)
		local profile = DataSystem.GetProfile(player)
		if profile then
			profile.tutorialCompleted = true
		end
		return { success = true }
	end

	print("[TutorialSystem] Initialized")
end

return TutorialSystem
