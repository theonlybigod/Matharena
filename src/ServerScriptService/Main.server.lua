--[[
	Main.server.lua

	Server entry point. Requires and initializes foundational server
	systems in a deliberate order:
		1. LobbyBuilder        - ensures the lobby exists (no-op if already built;
		                          see LobbyBuilder for the full rerun policy)
		2. ArenaBuilder         - ensures the arena exists (same rerun policy)
		3. DataSystem           - profile storage (DataStore-backed, Message 11)
		4. LeaderboardSystem    - global OrderedDataStore leaderboards (Message 11)
		5. LeaderboardDisplay   - refreshes the in-world Leaderboard Hall board (Message 11)
		6. ProgressionSystem    - XP/coins/gems/wins/rank/statistics logic
		7. ShopSystem           - cosmetics ownership/purchase/equip (Message 10)
		8. MatchSystem          - matchmaking/game-flow state machine
		9. CompetitionGameplay  - question rotation, subscribes to MatchSystem
		10. GameManager         - player lifecycle, coordinates the above

	LeaderboardSystem.Init() must run before GameManager.Init() (which is
	what starts letting players join and eventually get saved) so its
	OrderedDataStore references exist before DataSystem's first save ever
	tries to push a leaderboard update. LeaderboardDisplay.Init() must run
	after LobbyBuilder.Build() (the board it looks for doesn't exist until
	then) and after LeaderboardSystem.Init() (same OrderedDataStore
	readiness reason).

	Note: the pre-existing "Systems" folder is left untouched. GameManager,
	MatchSystem, DataSystem, LobbyBuilder, ArenaBuilder, ProgressionSystem,
	ShopSystem, LeaderboardSystem, LeaderboardDisplay, and CompetitionGameplay
	are direct siblings of this script under ServerScriptService, per the
	current architecture decision.
]]

local LobbyBuilder = require(script.Parent.LobbyBuilder)
local ArenaBuilder = require(script.Parent.ArenaBuilder)
local GameManager = require(script.Parent.GameManager)
local MatchSystem = require(script.Parent.MatchSystem)
local DataSystem = require(script.Parent.DataSystem)
local LeaderboardSystem = require(script.Parent.LeaderboardSystem)
local LeaderboardDisplay = require(script.Parent.LeaderboardDisplay)
local ProgressionSystem = require(script.Parent.ProgressionSystem)
local ShopSystem = require(script.Parent.ShopSystem)
local CompetitionGameplay = require(script.Parent.CompetitionGameplay)

LobbyBuilder.Build()
ArenaBuilder.Build()
DataSystem.Init()
LeaderboardSystem.Init()
LeaderboardDisplay.Init()
ProgressionSystem.Init()
ShopSystem.Init()
MatchSystem.Init()
CompetitionGameplay.Init()
GameManager.Init()

print("MathArena server started!")
