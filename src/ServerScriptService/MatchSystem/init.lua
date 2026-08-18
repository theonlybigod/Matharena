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

	Only this module mutates match state. All RemoteEvents here are
	one-way server -> client (QueueUpdated, MatchCountdownTick,
	GameStateChanged, MatchWinner) except "RequestJoinQueue" (client ->
	server, fire-and-forget - the lobby Play button, Message 8; it carries
	no payload, so there is nothing for a client to falsify beyond their
	own identity, which Roblox itself guarantees). The one RemoteFunction
	(GetMatchSnapshot) is a read-only query with no side effects, so
	there's nothing for a client to abuse by calling it.

	No elimination/question gameplay exists yet (later prompts). EndMatch()
	and RemoveParticipant() are the public hooks that gameplay will call;
	this module never fabricates a winner on its own.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MatchConfig = require(ReplicatedStorage.Modules.MatchConfig)
local RewardsConfig = require(ReplicatedStorage.Modules.RewardsConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)

local ProgressionSystem = require(ServerScriptService.ProgressionSystem)
local RemoteThrottle = require(ServerScriptService.RemoteThrottle)

local Queue = require(script.Queue)
local Teleporter = require(script.Teleporter)

local MatchSystem = {}

local GameState = MatchConfig.GameState

local state: string = GameState.Lobby
local acceptingQueue = true
local countdownGeneration = 0
local currentCountdownSeconds: number? = nil

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

local function getWaitingNames(): { string }
	local names = {}
	for _, player in ipairs(Queue.GetPlayers()) do
		table.insert(names, player.Name)
	end
	return names
end

local function broadcastQueueUpdated()
	queueUpdatedEvent:FireAllClients({
		waitingCount = Queue.Count(),
		waitingNames = getWaitingNames(),
		countdownSeconds = currentCountdownSeconds,
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
		waitingCount = Queue.Count(),
		waitingNames = getWaitingNames(),
		countdownSeconds = currentCountdownSeconds,
	}
end

-- ===== Queue countdown (the pre-teleport half of "Starting") =====

local function cancelCountdown()
	countdownGeneration += 1
	currentCountdownSeconds = nil
end

local function beginTeleportAndIntro()
	-- Freeze the roster the instant we commit to launching.
	acceptingQueue = false
	local myGeneration = countdownGeneration

	local launchingPlayers = Queue.GetPlayers()
	Queue.Clear()
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

	for remaining = MatchConfig.QUEUE_COUNTDOWN_SECONDS, 0, -1 do
		if countdownGeneration ~= myGeneration then
			return -- cancelled (queue dropped below MIN_PLAYERS)
		end

		currentCountdownSeconds = remaining
		broadcastQueueUpdated()

		if Queue.Count() >= MatchConfig.MAX_PLAYERS then
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
	setState(if Queue.Count() > 0 then GameState.Waiting else GameState.Lobby)
end

-- ===== Portal / queue membership =====

--[[
	Shared queue-join validation, used by both the physical portal Touched
	handler and the "RequestJoinQueue" RemoteEvent (the lobby Play button,
	Message 8). Same rules either way - a button click gets no special
	treatment over walking into the portal.
]]
local function tryJoinQueue(player: Player)
	if not acceptingQueue then
		return
	end

	if state == GameState.Playing or state == GameState.Winner or state == GameState.Returning then
		return -- roster locked for the current match
	end

	if Queue.Count() >= MatchConfig.MAX_PLAYERS then
		return
	end

	if not Queue.Add(player) then
		return -- already queued
	end

	if state == GameState.Lobby then
		setState(GameState.Waiting)
	end

	broadcastQueueUpdated()

	if state == GameState.Waiting and Queue.Count() >= MatchConfig.MIN_PLAYERS then
		beginCountdown()
	end
	-- If already Starting and MAX_PLAYERS was just reached, runCountdown's
	-- own loop notices on its next iteration (at most ~1 second later).
end

local function onPortalTouched(hit: BasePart)
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	tryJoinQueue(player)
end

local function onRequestJoinQueue(player: Player)
	if not RemoteThrottle.Check(player, "RequestJoinQueue", 1) then
		return
	end
	tryJoinQueue(player)
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
		else
			ProgressionSystem.AwardXP(player, RewardsConfig.PARTICIPATION_XP)
			ProgressionSystem.AwardCoins(player, RewardsConfig.PARTICIPATION_COINS)
		end
	end

	task.wait(MatchConfig.WINNER_DISPLAY_SECONDS)

	setState(GameState.Returning)
	Teleporter.ReturnToLobby(finishedParticipants)

	task.wait(MatchConfig.RETURNING_SECONDS)

	acceptingQueue = true
	setState(GameState.Lobby)
	broadcastQueueUpdated()
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
	disconnecting whether they were queued or already in an active match.
]]
function MatchSystem.HandlePlayerLeaving(player: Player)
	if Queue.Contains(player) then
		Queue.Remove(player)
		if state == GameState.Starting and Queue.Count() < MatchConfig.MIN_PLAYERS then
			revertToWaitingOrLobby()
		else
			broadcastQueueUpdated()
			if state == GameState.Waiting and Queue.Count() == 0 then
				setState(GameState.Lobby)
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

function MatchSystem.GetPlatformForPlayer(player: Player): Model?
	return platformAssignments[player]
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
	print("[MatchSystem] Initialized")
end

return MatchSystem
