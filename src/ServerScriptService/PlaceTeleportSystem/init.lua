--[[
	PlaceTeleportSystem

	Server-authoritative Play Mode difficulty routing across MathArena's
	five dedicated difficulty Places (see README.md's Play Mode
	Architecture section and DifficultyPlacesConfig.lua).

	Play Mode's tier-select popup (LobbyUIController.client.lua) no longer
	fires MatchSystem's "RequestJoinQueue" remote directly - it fires
	"RequestPlayDifficulty" (owned by this module) with the chosen tier
	id. This module is the ONLY thing that decides what happens next:

		1. Validate the tier id server-side (GameplayConfig.GetQueueTier
		   clamps/falls back to tier 1 for anything malformed - the same
		   defensive pattern already used everywhere else in this project;
		   the client can never pick an arbitrary destination string or
		   Place id, only ever a tier NUMBER that this module resolves).
		2. Look up that tier's destination Place (DifficultyPlacesConfig).
		   If it isn't configured yet (placeId == 0 - the five Places
		   haven't been created in Studio yet), fail closed: tell the
		   client via "PlayTeleportFailed" and do nothing else. Never
		   teleport to Place 0.
		3. If the destination Place IS the Place this server is already
		   running as (game.PlaceId matches), no teleport is needed at
		   all - just join that tier's queue locally via
		   MatchSystem.TryJoinQueue, exactly like the old direct-fire
		   behavior. This is what makes "pick the difficulty you're
		   already on" a no-op cross-server hop.
		4. Otherwise, actually teleport the player there with
		   TeleportService, carrying the chosen tierId as TeleportData so
		   the destination server knows to queue this player the instant
		   they arrive (see the PlayerAdded handler below) - no need to
		   press Play a second time after landing.

	Failure handling: TeleportAsync is wrapped in pcall. A failure (rate
	limit, the destination Place being invalid/unpublished, a Roblox
	outage, etc.) fires "PlayTeleportFailed" to the player with a reason
	string and otherwise changes nothing - the player stays exactly where
	they were, not queued anywhere, free to press Play again. This is the
	"recoverable state" the project's Play Mode teleport requirement
	calls for: a failed teleport is never a soft-lock.

	Practice Mode never touches this module at all - PracticeSystem calls
	MatchSystem.TryJoinQueue/LeaveQueue directly as plain Lua function
	calls, and never fires "RequestPlayDifficulty". That is what makes
	Practice Mode's difficulty changes stay on the player's current
	server/map with zero risk of ever invoking this teleport path -
	there's no shared code path between the two to accidentally cross.

	Arrival auto-join: if this server IS one of the five difficulty
	Places (DifficultyPlacesConfig.GetPlaceForPlaceId(game.PlaceId)
	returns a def), every joining player is checked for TeleportData
	carrying a matching tierId (set in step 4 above). If present, they're
	queued immediately via MatchSystem.TryJoinQueue - this is what makes
	"change difficulty -> land already queued for it" work without an
	extra button press. A player who arrives at a difficulty Place any
	other way (e.g. a direct game link, or Roblox's own follow-friend
	join) simply lands in that Place's lobby unqueued, same as arriviing
	at the Hub - they can still press Play there like normal.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local GameplayConfig = require(ReplicatedStorage.Modules.GameplayConfig)
local DifficultyPlacesConfig = require(ReplicatedStorage.Modules.DifficultyPlacesConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)

local MatchSystem = require(ServerScriptService.MatchSystem)
local RemoteThrottle = require(ServerScriptService.RemoteThrottle)

local PlaceTeleportSystem = {}

local requestPlayDifficultyEvent = RemoteEvents.Get("RequestPlayDifficulty")
local playTeleportFailedEvent = RemoteEvents.Get("PlayTeleportFailed")

-- Which difficulty (if any) THIS server is dedicated to. nil on the Hub
-- (and on a difficulty Place whose placeId hasn't been filled in yet -
-- see DifficultyPlacesConfig's doc comment on why that fails closed
-- rather than guessing).
local myPlace: DifficultyPlacesConfig.DifficultyPlaceDef? = DifficultyPlacesConfig.GetPlaceForPlaceId(game.PlaceId)

--[[
	Actually performs the cross-server hop for `player` to `destination`,
	carrying `destination.tierId` as TeleportData so the receiving
	server's PlayerAdded handler (below) can auto-join the right queue.
	Never called for a destination that's already this server (callers
	check that first) or for an unconfigured (placeId == 0) destination.
]]
local function teleportToDifficulty(player: Player, destination: DifficultyPlacesConfig.DifficultyPlaceDef)
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(destination.placeId, { player }, TeleportOptions.new())
	end)

	if not ok then
		warn(
			("[PlaceTeleportSystem] Teleport failed for %s -> tier %d (%s): %s"):format(
				player.Name,
				destination.tierId,
				destination.displayName,
				tostring(err)
			)
		)
		playTeleportFailedEvent:FireClient(player, {
			tierId = destination.tierId,
			reason = "TeleportFailed",
		})
	end
end

--[[
	Handles a validated "RequestPlayDifficulty" request. `rawTierId` is
	untrusted client input - GameplayConfig.GetQueueTier clamps/falls back
	to tier 1 for anything that isn't a real tier id, so this can never be
	used to reference an arbitrary destination.
]]
local function onRequestPlayDifficulty(player: Player, rawTierId: unknown)
	if not RemoteThrottle.Check(player, "RequestPlayDifficulty", 1) then
		return
	end

	local tierId = if typeof(rawTierId) == "number" then rawTierId else GameplayConfig.QUEUE_TIERS[1].id
	local tier = GameplayConfig.GetQueueTier(tierId) -- clamps/validates, falls back to tier 1
	local destination = DifficultyPlacesConfig.GetPlaceForTier(tier.id)

	if not destination or destination.placeId == 0 then
		warn(
			("[PlaceTeleportSystem] %s requested tier %d, but that difficulty's Place isn't configured yet."):format(
				player.Name,
				tier.id
			)
		)
		playTeleportFailedEvent:FireClient(player, {
			tierId = tier.id,
			reason = "NotConfigured",
		})
		return
	end

	if destination.placeId == game.PlaceId then
		-- Already on the right server for this difficulty - no teleport,
		-- just join its queue exactly like the old direct-fire behavior.
		MatchSystem.TryJoinQueue(player, tier.id)
		return
	end

	teleportToDifficulty(player, destination)
end

--[[
	Auto-joins a newly-arrived player's queue if they teleported in
	specifically for THIS Place's assigned difficulty. Only ever does
	anything on one of the five difficulty Places (myPlace ~= nil); the
	Hub never auto-joins anyone into anything.
]]
local function onPlayerAdded(player: Player)
	if not myPlace then
		return
	end

	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData
	if typeof(teleportData) == "table" and teleportData.tierId == myPlace.tierId then
		MatchSystem.TryJoinQueue(player, myPlace.tierId)
	end
end

function PlaceTeleportSystem.Init()
	if myPlace then
		print(
			("[PlaceTeleportSystem] This server is the tier %d (%s) destination."):format(
				myPlace.tierId,
				myPlace.displayName
			)
		)
	else
		print("[PlaceTeleportSystem] This server is the Hub (not one of the five difficulty destinations).")
		if not DifficultyPlacesConfig.IsFullyConfigured() then
			warn(
				"[PlaceTeleportSystem] One or more difficulty Places still have placeId = 0 in DifficultyPlacesConfig.lua - Play Mode teleports to those tiers will fail closed until they're filled in."
			)
		end
	end

	requestPlayDifficultyEvent.OnServerEvent:Connect(onRequestPlayDifficulty)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return PlaceTeleportSystem
