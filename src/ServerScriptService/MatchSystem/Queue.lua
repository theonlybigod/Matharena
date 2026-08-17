--[[
	Queue.lua

	Pure roster bookkeeping for players waiting to enter a match. Countdown
	timing and state transitions live in MatchSystem's init.lua, which uses
	this module purely as an ordered membership list.
]]

local Queue = {}

local players: { Player } = {}
local memberSet: { [Player]: boolean } = {}

function Queue.Add(player: Player): boolean
	if memberSet[player] then
		return false
	end

	table.insert(players, player)
	memberSet[player] = true
	return true
end

function Queue.Remove(player: Player): boolean
	if not memberSet[player] then
		return false
	end

	memberSet[player] = nil
	for i, queuedPlayer in ipairs(players) do
		if queuedPlayer == player then
			table.remove(players, i)
			break
		end
	end

	return true
end

function Queue.Contains(player: Player): boolean
	return memberSet[player] == true
end

function Queue.Count(): number
	return #players
end

function Queue.GetPlayers(): { Player }
	return table.clone(players)
end

function Queue.Clear()
	table.clear(players)
	table.clear(memberSet)
end

return Queue
