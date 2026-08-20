--[[
	Queue.lua

	Pure roster bookkeeping for players waiting to enter a match. Countdown
	timing and state transitions live in MatchSystem's init.lua, which uses
	this module purely as an ordered membership list.

	Instantiable pass (difficulty-tier queues): this used to be a single
	module-level singleton (one flat player list shared by the whole
	game). Now a constructor (Queue.new()) returning an independent
	instance, so MatchSystem can create one per difficulty tier - each
	tier gets its own genuinely separate FIFO roster using the exact same,
	already-tested logic, rather than a second reimplementation of queue
	bookkeeping. Every method below is unchanged in behavior; they're just
	bound to one instance's own `players`/`memberSet` tables now instead of
	shared module-level ones.
]]

local Queue = {}
Queue.__index = Queue

export type QueueInstance = typeof(setmetatable(
	{} :: {
		players: { Player },
		memberSet: { [Player]: boolean },
	},
	Queue
))

function Queue.new(): QueueInstance
	local self = setmetatable({
		players = {},
		memberSet = {},
	}, Queue)
	return self
end

function Queue.Add(self: QueueInstance, player: Player): boolean
	if self.memberSet[player] then
		return false
	end

	table.insert(self.players, player)
	self.memberSet[player] = true
	return true
end

function Queue.Remove(self: QueueInstance, player: Player): boolean
	if not self.memberSet[player] then
		return false
	end

	self.memberSet[player] = nil
	for i, queuedPlayer in ipairs(self.players) do
		if queuedPlayer == player then
			table.remove(self.players, i)
			break
		end
	end

	return true
end

function Queue.Contains(self: QueueInstance, player: Player): boolean
	return self.memberSet[player] == true
end

function Queue.Count(self: QueueInstance): number
	return #self.players
end

function Queue.GetPlayers(self: QueueInstance): { Player }
	return table.clone(self.players)
end

function Queue.Clear(self: QueueInstance)
	table.clear(self.players)
	table.clear(self.memberSet)
end

--[[
	Removes and returns up to `count` players from the FRONT of the queue
	(FIFO - first queued, first served), leaving any remainder still
	queued. Used by MatchSystem to cap a single match at MAX_PLAYERS
	without silently dropping/losing overflow players - they simply stay
	queued for the next match.
]]
function Queue.TakeUpTo(self: QueueInstance, count: number): { Player }
	local taken = {}
	for _ = 1, math.min(count, #self.players) do
		local player = table.remove(self.players, 1) :: Player
		self.memberSet[player] = nil
		table.insert(taken, player)
	end
	return taken
end

return Queue
