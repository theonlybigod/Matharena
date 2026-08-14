--[[
	Main.server.lua

	Server entry point. Requires and initializes foundational server
	systems in a deliberate order:
		1. LobbyBuilder - ensures the lobby exists (no-op if already built;
		                   see LobbyBuilder for the full rerun policy)
		2. ArenaBuilder  - ensures the arena exists (same rerun policy)
		3. DataSystem    - persistence (no dependents yet)
		4. MatchSystem   - gameplay/match orchestration (no dependents yet)
		5. GameManager   - player lifecycle, coordinates the above

	Note: the pre-existing "Systems" folder is left untouched. GameManager,
	MatchSystem, DataSystem, LobbyBuilder, and ArenaBuilder are direct
	siblings of this script under ServerScriptService, per the current
	architecture decision.
]]

local LobbyBuilder = require(script.Parent.LobbyBuilder)
local ArenaBuilder = require(script.Parent.ArenaBuilder)
local GameManager = require(script.Parent.GameManager)
local MatchSystem = require(script.Parent.MatchSystem)
local DataSystem = require(script.Parent.DataSystem)

LobbyBuilder.Build()
ArenaBuilder.Build()
DataSystem.Init()
MatchSystem.Init()
GameManager.Init()

print("MathArena server started!")
