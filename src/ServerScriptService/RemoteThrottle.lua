--[[
	RemoteThrottle.lua

	Small shared per-player, per-action cooldown tracker (Message 12
	security pass). Used to rate-limit RemoteEvents/RemoteFunctions that
	a client could otherwise spam-fire faster than is ever legitimately
	useful (e.g. rapid-fire shop purchases, settings updates, queue-join
	requests) - not because any single call is dangerous on its own, but
	spamming still costs unnecessary server work and DataStore budget.

	Self-contained: cleans up its own tracking on PlayerRemoving rather
	than requiring every caller to remember to do so.
]]

local Players = game:GetService("Players")

local RemoteThrottle = {}

local lastCallClock: { [Player]: { [string]: number } } = {}

--[[
	Returns true if `player` is allowed to perform `key` right now (and
	records that they just did), or false if they're still within
	`cooldownSeconds` of their last call for that same key. Call this
	FIRST, before doing any other work for the request.
]]
function RemoteThrottle.Check(player: Player, key: string, cooldownSeconds: number): boolean
	local playerTable = lastCallClock[player]
	if not playerTable then
		playerTable = {}
		lastCallClock[player] = playerTable
	end

	local now = os.clock()
	local last = playerTable[key]
	if last and (now - last) < cooldownSeconds then
		return false
	end

	playerTable[key] = now
	return true
end

Players.PlayerRemoving:Connect(function(player: Player)
	lastCallClock[player] = nil
end)

return RemoteThrottle
