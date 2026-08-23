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
		8. RewardTrackSystem    - win-based Rewards track (replaces Daily Rewards)
		9. SettingsSystem       - music/SFX/graphics/UI-scale/colorblind persistence (Message 12)
		10. MatchSystem          - matchmaking/game-flow state machine
		11. PracticeSystem      - solo-player Practice Mode (10s solo wait -> infinite practice)
		12. CompetitionGameplay - question rotation, subscribes to MatchSystem
		13. GameManager         - player lifecycle, coordinates the above

	LeaderboardSystem.Init() must run before GameManager.Init() (which is
	what starts letting players join and eventually get saved) so its
	OrderedDataStore references exist before DataSystem's first save ever
	tries to push a leaderboard update. LeaderboardDisplay.Init() must run
	after LobbyBuilder.Build() (the board it looks for doesn't exist until
	then) and after LeaderboardSystem.Init() (same OrderedDataStore
	readiness reason). SettingsSystem.Init() just needs to run before
	GameManager.Init() so its remotes exist before any player can request
	their settings snapshot. PracticeSystem.Init() runs after MatchSystem.Init()
	since it calls into MatchSystem (GetState/TryJoinQueue) - it also owns its
	own Players.PlayerAdded/PlayerRemoving connections, independent of
	GameManager, so it can react to a solo player the instant they join.

	Note: the pre-existing "Systems" folder is left untouched. GameManager,
	MatchSystem, DataSystem, LobbyBuilder, ArenaBuilder, ProgressionSystem,
	ShopSystem, SettingsSystem, LeaderboardSystem, LeaderboardDisplay,
	RewardTrackSystem, PracticeSystem, and CompetitionGameplay are direct
	siblings of this script under ServerScriptService, per the current
	architecture decision.
]]

local LobbyBuilder = require(script.Parent.LobbyBuilder)
local ArenaBuilder = require(script.Parent.ArenaBuilder)
local LobbyLighting = require(script.Parent.LobbyBuilder.LobbyLighting)
local GameManager = require(script.Parent.GameManager)
local MatchSystem = require(script.Parent.MatchSystem)
local PracticeSystem = require(script.Parent.PracticeSystem)
local DataSystem = require(script.Parent.DataSystem)
local LeaderboardSystem = require(script.Parent.LeaderboardSystem)
local LeaderboardDisplay = require(script.Parent.LeaderboardDisplay)
local ProgressionSystem = require(script.Parent.ProgressionSystem)
local ShopSystem = require(script.Parent.ShopSystem)
local RewardTrackSystem = require(script.Parent.RewardTrackSystem)
local SettingsSystem = require(script.Parent.SettingsSystem)
local CompetitionGameplay = require(script.Parent.CompetitionGameplay)
local BuildingTeleportSystem = require(script.Parent.BuildingTeleportSystem)
local DailyRewardsSystem = require(script.Parent.DailyRewardsSystem)

LobbyBuilder.Build()
ArenaBuilder.Build()

-- Always re-run the Lighting post-effect dedup, even when both builders
-- skip their full build (Lobby/Arena already marked built). Bloom and
-- ColorCorrectionEffect are children of the single global Lighting
-- service, not Workspace.Lobby/Workspace.Arena, so they are NOT reset by
-- a fresh Rojo sync or a normal server start - only Build()'s own
-- (skippable) code path used to clean them up. If two builders (or a
-- stray manual edit) ever leave duplicate BloomEffect/ColorCorrection
-- instances sitting in the saved place file, every previous server start
-- would silently keep stacking them forever, since Build() never re-runs
-- once already built. Calling this unconditionally, every single server
-- start, makes the dedup self-healing regardless of build state - this
-- is what actually prevents the "whole map glowing white" bug from ever
-- silently persisting across a restart again.
LobbyLighting.Apply()

DataSystem.Init()
LeaderboardSystem.Init()
LeaderboardDisplay.Init()
ProgressionSystem.Init()
ShopSystem.Init()
RewardTrackSystem.Init()
SettingsSystem.Init()
MatchSystem.Init()
PracticeSystem.Init()
CompetitionGameplay.Init()
BuildingTeleportSystem.Init()
DailyRewardsSystem.Init()
GameManager.Init()

print("MathArena server started!")
