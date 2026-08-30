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
		13. PlaceTeleportSystem - Play Mode cross-server difficulty routing (see README.md's
		                          Play Mode Architecture section)
		14. GameManager         - player lifecycle, coordinates the above

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
	RewardTrackSystem, PracticeSystem, PlaceTeleportSystem, and
	CompetitionGameplay are direct siblings of this script under
	ServerScriptService, per the current architecture decision.

	Multi-Place map build (Play Mode Architecture, README.md): this exact
	script/src tree is synced into SIX separate Roblox Places - the Hub
	(this repo's main default.project.json) plus five dedicated
	difficulty Places (place.<name>.project.json). DifficultyPlacesConfig
	maps game.PlaceId to at most one assigned MapsConfig map id. On the
	Hub, that lookup returns nil and every map still builds
	(BuildAllMaps(), unchanged multi-map exploration lobby). On a
	difficulty Place, only that ONE assigned map is built - the other
	four are never created there at all, satisfying "only that one map
	allocated on each server".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyBuilder = require(script.Parent.LobbyBuilder)
local ArenaBuilder = require(script.Parent.ArenaBuilder)
local LobbyLighting = require(script.Parent.LobbyBuilder.LobbyLighting)
local GameManager = require(script.Parent.GameManager)
local MatchSystem = require(script.Parent.MatchSystem)
local PracticeSystem = require(script.Parent.PracticeSystem)
local DataSystem = require(script.Parent.DataSystem)
local LeaderboardSystem = require(script.Parent.LeaderboardSystem)
local LeaderboardDisplay = require(script.Parent.LeaderboardDisplay)
local RivalBoardSystem = require(script.Parent.RivalBoardSystem)
local ProgressionSystem = require(script.Parent.ProgressionSystem)
local ShopSystem = require(script.Parent.ShopSystem)
local RewardTrackSystem = require(script.Parent.RewardTrackSystem)
local SettingsSystem = require(script.Parent.SettingsSystem)
local CompetitionGameplay = require(script.Parent.CompetitionGameplay)
local BuildingTeleportSystem = require(script.Parent.BuildingTeleportSystem)
local DailyRewardsSystem = require(script.Parent.DailyRewardsSystem)
local LifetimeRewardsSystem = require(script.Parent.LifetimeRewardsSystem)
local QuestsSystem = require(script.Parent.QuestsSystem)
local TutorialSystem = require(script.Parent.TutorialSystem)
local PlaceTeleportSystem = require(script.Parent.PlaceTeleportSystem)

local MapsConfig = require(ReplicatedStorage.Modules.MapsConfig)
local DifficultyPlacesConfig = require(ReplicatedStorage.Modules.DifficultyPlacesConfig)

local assignedPlace = DifficultyPlacesConfig.GetPlaceForPlaceId(game.PlaceId)
if assignedPlace then
	-- One of the five difficulty Places: build ONLY the one map this
	-- Place is dedicated to. Deliberately does NOT call BuildAllMaps() -
	-- the other four maps must never exist here. enableSpawns = true is
	-- passed explicitly (LobbyBuilder.Build's 3rd arg) because this map's
	-- own MapsConfig.isDefault flag is almost always false (only
	-- Futuristic is flagged isDefault, for the Hub's sake) - but since
	-- this Place only ever builds this one map, its spawns must be the
	-- ones enabled here regardless of that flag. See LobbyBuilder.Build's
	-- doc comment for why the Hub's BuildAllMaps() path below is
	-- unaffected by this.
	local assignedMap = MapsConfig.GetMap(assignedPlace.mapId)
	LobbyBuilder.Build(assignedMap, nil, true)

	-- Self-healing pass, unconditional every server start (see
	-- LobbyBuilder.EnsureSpawnsEnabled's own doc comment): fixes any
	-- difficulty Place whose map was already built and marked
	-- MathArenaBuilt under the OLD isDefault-only spawn logic (e.g. Under
	-- the Sea, tested before this fix existed) without needing a
	-- destructive manual Rebuild(). A no-op on a Place where Build() just
	-- (re)built the map above, since its spawns are already enabled.
	LobbyBuilder.EnsureSpawnsEnabled(assignedMap)

	-- The competition Arena, embedded IN this Place's one map (re-themed
	-- to match it, positioned at its world location) rather than a
	-- separate structure at the Hub's shared origin - see
	-- ArenaBuilder.BuildForMap's own doc comment.
	ArenaBuilder.BuildForMap(assignedMap)
else
	-- The Hub (or a difficulty Place whose placeId hasn't been filled in
	-- yet - see DifficultyPlacesConfig's doc comment): unchanged
	-- multi-map exploration lobby plus the single shared central Arena,
	-- exactly as before this system existed.
	LobbyBuilder.BuildAllMaps()
	ArenaBuilder.Build()
end

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
-- Rival Board (Statistics building interior - the in-person-only standing
-- comparison). After LeaderboardSystem.Init() for the same
-- OrderedDataStore-readiness reason LeaderboardDisplay has, and before
-- GameManager.Init() so its RemoteFunction exists before any player can
-- join and walk up to the board.
RivalBoardSystem.Init()
ProgressionSystem.Init()
ShopSystem.Init()
RewardTrackSystem.Init()
SettingsSystem.Init()
MatchSystem.Init()
PracticeSystem.Init()
CompetitionGameplay.Init()
BuildingTeleportSystem.Init()
DailyRewardsSystem.Init()
LifetimeRewardsSystem.Init()
QuestsSystem.Init()
TutorialSystem.Init()
PlaceTeleportSystem.Init()
GameManager.Init()

print("MathArena server started!")
