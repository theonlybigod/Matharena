--[[
	Main.server.lua

	Server entry point. Requires and initializes foundational server
	systems in a deliberate order:
		1. LobbyBuilder        - ensures the lobby exists (no-op if already built;
		                          see LobbyBuilder for the full rerun policy)
		2. ArenaBuilder         - ensures the arena exists (same rerun policy)
		3. DataSystem           - profile storage (in-memory; DataStore in Message 11)
		4. ProgressionSystem    - XP/coins/wins/rank/statistics logic
		5. MatchSystem          - matchmaking/game-flow state machine
		6. CompetitionGameplay  - question rotation, subscribes to MatchSystem
		7. GameManager          - player lifecycle, coordinates the above

	Note: the pre-existing "Systems" folder is left untouched. GameManager,
	MatchSystem, DataSystem, LobbyBuilder, ArenaBuilder, ProgressionSystem,
	and CompetitionGameplay are direct siblings of this script under
	ServerScriptService, per the current architecture decision.
]]

local LobbyBuilder = require(script.Parent.LobbyBuilder)
local ArenaBuilder = require(script.Parent.ArenaBuilder)
local GameManager = require(script.Parent.GameManager)
local MatchSystem = require(script.Parent.MatchSystem)
local DataSystem = require(script.Parent.DataSystem)
local ProgressionSystem = require(script.Parent.ProgressionSystem)
local CompetitionGameplay = require(script.Parent.CompetitionGameplay)

LobbyBuilder.Build()
ArenaBuilder.Build()
DataSystem.Init()
ProgressionSystem.Init()
MatchSystem.Init()
CompetitionGameplay.Init()
GameManager.Init()

print("MathArena server started!")
