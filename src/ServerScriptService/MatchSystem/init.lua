--[[
	MatchSystem

	Server-authoritative matchmaking + match flow:
		- Queue formation via the lobby's queue portal (CollectionService
		  tag "QueuePortal", set up in LobbyBuilder, Message 2)
		- 15-second countdown once MIN_PLAYERS is reached (or an early
		  launch once MAX_PLAYERS is reached)
		- Teleport to arena contestant platforms (CollectionService tag
		  "ContestantPlatform", set up in ArenaBuilder, Message 3), then a
		  3-2-1-GO intro
		- Winner declaration + return-to-lobby teleport, integrating with
		  ProgressionSystem (Message 4) to award the win and record stats
		- Player-leaving-mid-game handling (auto-win by forfeit)

	SERVER vs MATCH: MAX_PLAYERS (12) caps a single MATCH's contestant
	count - it is NOT a server player cap. The Roblox server can hold as
	many players as normal; the Queue can hold any number of waiting
	players too. A match launch only ever TAKES the first MAX_PLAYERS
	queued players (FIFO, see Queue.TakeUpTo) - anyone beyond that stays
	queued for the next match rather than being dropped or rejected.

	Players CAN queue while a competitive match is already Playing/Winner/
	Returning - they simply wait; the state machine only transitions to
	Waiting/Starting once it's actually back in Lobby/Waiting (see
	evaluateQueueForLaunch). EndMatch re-runs that same evaluation once it
	returns to Lobby, so any overflow/leftover queued players immediately
	start their own countdown without needing a fresh join event.

	Only this module mutates match state. All RemoteEvents here are
	one-way server -> client (QueueUpdated, MatchCountdownTick,
	GameStateChanged, MatchWinner) except "RequestJoinQueue" (client ->
	server, fire-and-forget - the lobby Play button, Message 8; now also
	carries the chosen difficulty tier id, see below) and
	"RequestLeaveQueue" (also fire-and-forget). The one RemoteFunction
	(GetMatchSnapshot) is a read-only query with no side effects, so
	there's nothing for a client to abuse by calling it.

	Difficulty tiers (Play redesign): the queue is now SIX separate
	per-tier queues (GameplayConfig.QUEUE_TIERS), one Queue instance each
	(see Queue.lua's instantiable pass), rather than one flat list. Only
	ONE match still ever runs on the arena at a time - this doesn't add
	concurrent matches, it only changes WHICH players get grouped
	together. `currentTier` tracks which tier the currently-forming/active
	match belongs to; evaluateQueueForLaunch picks a tier to "claim" (the
	lowest-numbered tier with anyone waiting) once the arena is free, and
	no other tier can begin a countdown until that match fully returns to
	Lobby. A player choosing a HARDER tier just means "start the match's
	round-progression further along" (see GameplayConfig.GetQueueTier) -
	the actual per-turn difficulty/category logic in CompetitionGameplay
	is completely unchanged, unaware anything but the round number moved.

	EndMatch()/RemoveParticipant() are the public hooks CompetitionGameplay
	calls; this module never fabricates a winner on its own.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MatchConfig = require(ReplicatedStorage.Modules.MatchConfig)
local GameplayConfig = require(ReplicatedStorage.Modules.GameplayConfig)
local RewardsConfig = require(ReplicatedStorage.Modules.RewardsConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)

local ProgressionSystem = require(ServerScriptService.ProgressionSystem)
local RewardTrackSystem = require(ServerScriptService.RewardTrackSystem)
local RemoteThrottle = require(ServerScriptService.RemoteThrottle)

local Queue = require(script.Queue)
local Teleporter = require(script.Teleporter)

local MatchSystem = {}

local GameState = MatchConfig.GameState

local state: string = GameState.Lobby
local countdownGeneration = 0
local currentCountdownSeconds: number? = nil

-- One independent Queue instance per difficulty tier (GameplayConfig.
-- QUEUE_TIERS), keyed by tier id.
local tierQueues: { [number]: Queue.QueueInstance } = {}
for _, tier in ipairs(GameplayConfig.QUEUE_TIERS) do
	tierQueues[tier.id] = Queue.new()
end

-- Which tier the currently-forming/active match belongs to. nil means the
-- arena is free and no tier has been "claimed" yet.
local currentTier: number? = nil

local participants: { Player } = {}
local platformAssignments: { [Player]: Model } = {}

local stateChangedCallbacks: { (string) -> () } = {}
local participantRemovedCallbacks: { (Player) -> () } = {}

-- Remotes, created on demand via the shared factory modules (Message 1).
local queueUpdatedEvent = RemoteEvents.Get("QueueUpdated")
local matchCountdownTickEvent = RemoteEvents.Get("MatchCountdownTick")
local gameStateChangedEvent = RemoteEvents.Get("GameStateChanged")
local matchWinnerEvent = RemoteEvents.Get("MatchWinner")
local getMatchSnapshotFunction = RemoteFunctions.Get("GetMatchSnapshot")
local requestJoinQueueEvent = RemoteEvents.Get("RequestJoinQueue")
local requestLeaveQueueEvent = RemoteEvents.Get("RequestLeaveQueue")

--[[
	Total players waiting across every tier's queue - used anywhere the
	old single-queue "how many people are waiting" count was used (the
	queue banner shows a per-tier breakdown too - see QueueUpdated's
	payload below).
]]
local function totalWaitingCount(): number
	local total = 0
	for _, queue in pairs(tierQueues) do
		total += Queue.Count(queue)
	end
	return total
end

--[[
	Finds which tier's queue (if any) `player` is currently in. Players can
	only ever be in one tier's queue at a time (tryJoinQueue below removes
	them from any other tier first).
]]
local function findPlayerTier(player: Player): number?
	for tierId, queue in pairs(tierQueues) do
		if Queue.Contains(queue, player) then
			return tierId
		end
	end
	return nil
end

local function getWaitingNames(): { string }
	local names = {}
	for _, queue in pairs(tierQueues) do
		for _, player in ipairs(Queue.GetPlayers(queue)) do
			table.insert(names, player.Name)
		end
	end
	return names
end

--[[
	Per-tier waiting counts, in tier order, for the queue banner to show
	"Tier X: N waiting" style breakdowns rather than just one opaque total.
]]
local function getTierCounts(): { [number]: number }
	local counts = {}
	for tierId, queue in pairs(tierQueues) do
		counts[tierId] = Queue.Count(queue)
	end
	return counts
end

local function broadcastQueueUpdated()
	queueUpdatedEvent:FireAllClients({
		waitingCount = totalWaitingCount(),
		waitingNames = getWaitingNames(),
		countdownSeconds = currentCountdownSeconds,
		currentTier = currentTier,
		tierCounts = getTierCounts(),
	})
end

local function setState(newState: string)
	state = newState
	gameStateChangedEvent:FireAllClients(state)
	for _, callback in ipairs(stateChangedCallbacks) do
		task.spawn(callback, newState)
	end
end

getMatchSnapshotFunction.OnServerInvoke = function(_player: Player)
	return {
		gameState = state,
		waitingCount = totalWaitingCount(),
		waitingNames = getWaitingNames(),
		countdownSeconds = currentCountdownSeconds,
		currentTier = currentTier,
		tierCounts = getTierCounts(),
	}
end

-- ===== Queue countdown (the pre-teleport half of "Starting") =====

local function cancelCountdown()
	countdownGeneration += 1
	currentCountdownSeconds = nil
end

local function beginTeleportAndIntro()
	local myGeneration = countdownGeneration
	local activeQueue = tierQueues[currentTier :: number]

	-- FIFO-capped: only ever takes the first MAX_PLAYERS queued players
	-- from the claimed tier's queue, no matter how many are actually
	-- waiting. Anyone beyond that stays in that tier's queue for the next
	-- match - never dropped, never force-included.
	local launchingPlayers = Queue.TakeUpTo(activeQueue, MatchConfig.MAX_PLAYERS)
	currentCountdownSeconds = nil
	broadcastQueueUpdated()

	participants = launchingPlayers
	platformAssignments = Teleporter.AssignPlatforms(launchingPlayers)

	task.wait(1) -- let characters land on their platforms before the intro

	if countdownGeneration ~= myGeneration then
		return -- match already ended underneath us (e.g. everyone but one left)
	end

	for _, step in ipairs(MatchConfig.INTRO_STEPS) do
		if countdownGeneration ~= myGeneration then
			return
		end
		matchCountdownTickEvent:FireAllClients(step)
		task.wait(MatchConfig.INTRO_STEP_SECONDS)
	end

	if countdownGeneration ~= myGeneration then
		return
	end

	matchCountdownTickEvent:FireAllClients(nil)
	setState(GameState.Playing)
end

local function runCountdown()
	local myGeneration = countdownGeneration
	local activeQueue = tierQueues[currentTier :: number]

	for remaining = MatchConfig.QUEUE_COUNTDOWN_SECONDS, 0, -1 do
		if countdownGeneration ~= myGeneration then
			return -- cancelled (queue dropped below MIN_PLAYERS)
		end

		currentCountdownSeconds = remaining
		broadcastQueueUpdated()

		if Queue.Count(activeQueue) >= MatchConfig.MAX_PLAYERS then
			break -- full roster reached early; launch without waiting out the rest
		end

		if remaining > 0 then
			task.wait(1)
		end
	end

	if countdownGeneration ~= myGeneration then
		return
	end

	beginTeleportAndIntro()
end

local function beginCountdown()
	countdownGeneration += 1
	setState(GameState.Starting)
	task.spawn(runCountdown)
end

local function revertToWaitingOrLobby()
	cancelCountdown()
	broadcastQueueUpdated()
	local activeQueue = currentTier and tierQueues[currentTier]
	setState(if activeQueue and Queue.Count(activeQueue) > 0 then GameState.Waiting else GameState.Lobby)
end

--[[
	Re-checks whether the queue should now transition state and/or begin a
	countdown. Only actually does anything while state is Lobby or Waiting -
	it's always safe to call this after ANY queue change (a join, a
	removal, or a match just ending) since it's a no-op whenever a
	competitive match is currently forming/active. This is what lets
	overflow players (beyond MAX_PLAYERS) and players who joined mid-match
	automatically start their own countdown the moment it becomes possible,
	without needing a fresh join event to trigger it.

	Difficulty tiers: if no tier is currently claimed (currentTier == nil,
	i.e. the arena is genuinely free), this claims the lowest-numbered
	tier with anyone waiting in it - deterministic and simple, rather than
	trying to race multiple tiers against each other. Once a tier is
	claimed, only THAT tier's queue is checked for the MIN_PLAYERS
	threshold; other tiers' players simply wait their turn.
]]
local function evaluateQueueForLaunch()
	if state ~= GameState.Lobby and state ~= GameState.Waiting then
		return
	end

	if not currentTier then
		for _, tier in ipairs(GameplayConfig.QUEUE_TIERS) do
			if Queue.Count(tierQueues[tier.id]) > 0 then
				currentTier = tier.id
				break
			end
		end
	end

	if not currentTier then
		return -- nothing waiting in any tier
	end

	if state == GameState.Lobby then
		setState(GameState.Waiting)
	end

	if Queue.Count(tierQueues[currentTier]) >= MatchConfig.MIN_PLAYERS then
		beginCountdown()
	end
end

-- ===== Portal / queue membership =====

--[[
	Shared queue-join validation, used by both the physical portal Touched
	handler (always joins the default/easiest tier, since walking into the
	portal has no tier-selection UI of its own) and the "RequestJoinQueue"
	RemoteEvent (the lobby Play button's tier-select popup). Same rules
	either way - a button click gets no special treatment over walking in.
	Joining is allowed regardless of current match state (SERVER vs MATCH:
	queueing during an active match just means "waiting for the next one"
	- see module doc comment); evaluateQueueForLaunch decides whether that
	actually starts anything right now.
]]
local function tryJoinQueue(player: Player, tierId: number)
	local tier = GameplayConfig.GetQueueTier(tierId) -- clamps/validates, falls back to tier 1
	local existingTier = findPlayerTier(player)
	if existingTier == tier.id then
		return -- already queued for this exact tier
	end
	if existingTier then
		Queue.Remove(tierQueues[existingTier], player) -- switching tiers - only ever in one queue at a time
	end

	Queue.Add(tierQueues[tier.id], player)

	broadcastQueueUpdated()
	evaluateQueueForLaunch()
end

local function onPortalTouched(hit: BasePart)
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	tryJoinQueue(player, GameplayConfig.QUEUE_TIERS[1].id)
end

local function onRequestJoinQueue(player: Player, rawTierId: unknown)
	if not RemoteThrottle.Check(player, "RequestJoinQueue", 1) then
		return
	end
	local tierId = if typeof(rawTierId) == "number" then rawTierId else GameplayConfig.QUEUE_TIERS[1].id
	tryJoinQueue(player, tierId)
end

local function onRequestLeaveQueue(player: Player)
	if not RemoteThrottle.Check(player, "RequestLeaveQueue", 1) then
		return
	end
	MatchSystem.LeaveQueue(player)
end

local function connectPortals()
	local tagged = CollectionService:GetTagged("QueuePortal")
	for _, part in ipairs(tagged) do
		if part:IsA("BasePart") then
			part.Touched:Connect(onPortalTouched)
		end
	end

	if #tagged == 0 then
		warn('[MatchSystem] No instance tagged "QueuePortal" found - queue entry will not work.')
	end
end

-- ===== Match end / participant removal =====

--[[
	Ends the current match. `winner` may be nil (e.g. everyone left).
	Awards progression, shows the Winner state, then teleports everyone
	back to the lobby and returns to the Lobby state.
]]
function MatchSystem.EndMatch(winner: Player?)
	if state ~= GameState.Playing and state ~= GameState.Starting then
		return
	end

	cancelCountdown()

	local finishedParticipants = participants
	participants = {}
	platformAssignments = {}
	Teleporter.ClearAllPlatforms()

	setState(GameState.Winner)
	matchWinnerEvent:FireAllClients(winner and winner.Name or nil)

	-- Win/participation economy (Message 9). This is the single place ALL
	-- match endings funnel through - both a CompetitionGameplay-driven
	-- elimination win and a MatchSystem-driven forfeit win (via
	-- RemoveParticipant, opponents disconnecting) - so granting the reward
	-- here covers every end path uniformly. The winner gets the Win reward
	-- only, not Participation too; everyone else gets Participation only.
	-- (The separate Perfect Game bonus, when it applies, is granted by
	-- CompetitionGameplay itself at the moment it identifies the winner,
	-- since only that module knows whether the win came via elimination.)
	for _, player in ipairs(finishedParticipants) do
		local didWin = player == winner
		ProgressionSystem.RecordGameCompleted(player, didWin)
		if didWin then
			ProgressionSystem.AwardWin(player)
			ProgressionSystem.AwardXP(player, RewardsConfig.WIN_XP)
			ProgressionSystem.AwardCoins(player, RewardsConfig.WIN_COINS)
			ProgressionSystem.AwardGems(player, RewardsConfig.WIN_GEMS)
			RewardTrackSystem.CheckForNewlyUnlocked(player)
		else
			ProgressionSystem.AwardXP(player, RewardsConfig.PARTICIPATION_XP)
			ProgressionSystem.AwardCoins(player, RewardsConfig.PARTICIPATION_COINS)
		end
	end

	task.wait(MatchConfig.WINNER_DISPLAY_SECONDS)

	setState(GameState.Returning)
	Teleporter.ReturnToLobby(finishedParticipants)

	task.wait(MatchConfig.RETURNING_SECONDS)

	setState(GameState.Lobby)
	-- Free the arena for any tier to claim next - if this tier still has
	-- overflow players left over, evaluateQueueForLaunch below will just
	-- re-claim the SAME tier immediately (identical to the pre-tiers
	-- overflow behavior); otherwise a different tier's waiting players get
	-- their turn.
	currentTier = nil
	broadcastQueueUpdated()
	-- Pick up any leftover/overflow players who were already queued during
	-- this match (beyond MAX_PLAYERS, or who joined mid-match) - starts
	-- their countdown immediately rather than waiting for a fresh join.
	evaluateQueueForLaunch()
end

--[[
	Removes a single player from the active match (e.g. they disconnected,
	or - in later prompts - were eliminated). If only one participant
	remains afterward, they automatically win by forfeit. If none remain,
	the match ends with no winner.
]]
function MatchSystem.RemoveParticipant(player: Player, _reason: string?)
	local index
	for i, p in ipairs(participants) do
		if p == player then
			index = i
			break
		end
	end
	if not index then
		return
	end

	table.remove(participants, index)

	for _, callback in ipairs(participantRemovedCallbacks) do
		task.spawn(callback, player)
	end

	local platform = platformAssignments[player]
	if platform then
		Teleporter.ClearPlatform(platform)
		platformAssignments[player] = nil
	end

	if #participants == 1 then
		MatchSystem.EndMatch(participants[1])
	elseif #participants == 0 then
		MatchSystem.EndMatch(nil)
	end
end

--[[
	Called from GameManager's Players.PlayerRemoving. Handles a player
	disconnecting whether they were queued (in any tier) or already in an
	active match.
]]
function MatchSystem.HandlePlayerLeaving(player: Player)
	local tierId = findPlayerTier(player)
	if tierId then
		Queue.Remove(tierQueues[tierId], player)
		if state == GameState.Starting and tierId == currentTier and Queue.Count(tierQueues[tierId]) < MatchConfig.MIN_PLAYERS then
			revertToWaitingOrLobby()
		else
			broadcastQueueUpdated()
			if state == GameState.Waiting and tierId == currentTier and Queue.Count(tierQueues[tierId]) == 0 then
				currentTier = nil
				setState(GameState.Lobby)
				evaluateQueueForLaunch() -- another tier's players may be waiting
			end
		end
		return
	end

	MatchSystem.RemoveParticipant(player, "left")
end

function MatchSystem.GetState(): string
	return state
end

function MatchSystem.GetParticipants(): { Player }
	return table.clone(participants)
end

function MatchSystem.IsParticipant(player: Player): boolean
	return table.find(participants, player) ~= nil
end

function MatchSystem.GetPlatformForPlayer(player: Player): Model?
	return platformAssignments[player]
end

--[[
	Which difficulty tier the CURRENTLY forming/active match belongs to
	(nil if the arena is free). CompetitionGameplay reads this at round
	start to pick the correct starting round via
	GameplayConfig.GetQueueTier(tierId).startingRound.
]]
function MatchSystem.GetCurrentTier(): number?
	return currentTier
end

--[[
	Public wrapper around the same queue-join validation the Play button
	and portal use (Practice Mode, solo-wait system). No special treatment
	over any other entry point - same checks. Defaults to the easiest tier
	if not specified.
]]
function MatchSystem.TryJoinQueue(player: Player, tierId: number?)
	tryJoinQueue(player, tierId or GameplayConfig.QUEUE_TIERS[1].id)
end

--[[
	Removes `player` from whichever tier's queue they're currently in (if
	any) - used by both manual Practice Mode entry (a queued player
	chooses to leave the queue and practice instead, section 9) and the
	plain "Cancel Queue" button (section 26). Mirrors HandlePlayerLeaving's
	queue-side logic but without the "they disconnected" framing - the
	player is still in the server, just no longer queued. Returns true if
	they were actually removed from a queue.
]]
function MatchSystem.LeaveQueue(player: Player): boolean
	local tierId = findPlayerTier(player)
	if not tierId then
		return false
	end

	Queue.Remove(tierQueues[tierId], player)
	if state == GameState.Starting and tierId == currentTier and Queue.Count(tierQueues[tierId]) < MatchConfig.MIN_PLAYERS then
		revertToWaitingOrLobby()
	else
		broadcastQueueUpdated()
		if state == GameState.Waiting and tierId == currentTier and Queue.Count(tierQueues[tierId]) == 0 then
			currentTier = nil
			setState(GameState.Lobby)
			evaluateQueueForLaunch() -- another tier's players may be waiting
		end
	end

	return true
end

--[[
	Subscribes to match-state transitions. Used by CompetitionGameplay
	(Message 6) to start a question round when state becomes "Playing" and
	to clean up if the match ends any other way (e.g. a disconnect cascaded
	to a forfeit while a round was active). Callbacks are invoked via
	task.spawn so a misbehaving subscriber can't block MatchSystem's own flow.
]]
function MatchSystem.OnStateChanged(callback: (string) -> ())
	table.insert(stateChangedCallbacks, callback)
end

--[[
	Subscribes to participant removals (disconnects only - see
	RemoveParticipant). Used by CompetitionGameplay so a departing
	contestant's turn doesn't stall waiting for a timeout that will never
	resolve.
]]
function MatchSystem.OnParticipantRemoved(callback: (Player) -> ())
	table.insert(participantRemovedCallbacks, callback)
end

function MatchSystem.Init()
	connectPortals()
	requestJoinQueueEvent.OnServerEvent:Connect(onRequestJoinQueue)
	requestLeaveQueueEvent.OnServerEvent:Connect(onRequestLeaveQueue)
	print("[MatchSystem] Initialized")
end

return MatchSystem
