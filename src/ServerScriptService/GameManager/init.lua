--[[
	GameManager

	Top-level orchestrator for MathArena's server-side systems.

	Responsibilities (foundation pass):
		- Player join/leave lifecycle
		- Bootstrapping other server systems (MatchSystem, DataSystem)

	GameManager itself should stay thin. Actual gameplay logic (matches,
	scoring, elimination, data persistence, etc.) belongs in the relevant
	system, not here. This module coordinates, it doesn't implement.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.Config)
local ProgressionSystem = require(script.Parent.ProgressionSystem)
local MatchSystem = require(script.Parent.MatchSystem)
local CompetitionGameplay = require(script.Parent.CompetitionGameplay)

local GameManager = {}

local initialized = false

local function onPlayerAdded(player: Player)
	print(("[GameManager] %s joined %s"):format(player.Name, Config.GAME_NAME))
	ProgressionSystem.SetupPlayer(player)

	-- Someone arriving mid-match cannot join the round in progress, so offer
	-- them the Spectate button straight away. No-ops when no match is
	-- running, so GameManager stays out of match-state bookkeeping.
	CompetitionGameplay.OfferSpectateIfMatchRunning(player)
end

local function onPlayerRemoving(player: Player)
	print(("[GameManager] %s left %s"):format(player.Name, Config.GAME_NAME))
	MatchSystem.HandlePlayerLeaving(player)
	ProgressionSystem.TeardownPlayer(player)
end

--[[
	Initializes GameManager. Must be called once from the server entry point
	after other foundational systems have been required.
]]
function GameManager.Init()
	if initialized then
		warn("[GameManager] Init() called more than once; ignoring.")
		return
	end
	initialized = true

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Handle any players already present (e.g. during live-sync testing).
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	print(("[GameManager] Initialized (%s v%s)"):format(Config.GAME_NAME, Config.VERSION))
end

return GameManager
