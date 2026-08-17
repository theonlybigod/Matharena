--[[
	Floor.lua

	Builds the lobby floor slab and its neon perimeter trim, from
	source-controlled dimensions in LobbyConfig.

	Split out from LobbyBuilder/init.lua (previously a local `buildFloor`
	function) so the exact same code path can be reused by:
		1. LobbyBuilder itself at runtime (Play mode / fresh servers), and
		2. build/BakeLobby.luau, the offline script (run via Lune) that
		   bakes a source-controlled Workspace/Lobby.rbxmx model file so
		   the lobby is visible in Studio Edit mode through plain Rojo
		   sync, with no code execution required.
	This guarantees the baked model and the runtime-generated lobby can
	never drift apart for the floor geometry.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local LobbyConfig = require(script.Parent.LobbyConfig)

local Floor = {}

function Floor.Build(lobby: Instance)
	PartUtils.CreatePart({
		name = "Floor",
		size = Vector3.new(LobbyConfig.LOBBY_SIZE, LobbyConfig.FLOOR_THICKNESS, LobbyConfig.LOBBY_SIZE),
		position = Vector3.new(0, -LobbyConfig.FLOOR_THICKNESS / 2, 0),
		material = Enum.Material.Concrete,
		color = LobbyConfig.FLOOR_COLOR,
		parent = lobby,
	})

	local trimFolder = Instance.new("Folder")
	trimFolder.Name = "FloorTrim"
	trimFolder.Parent = lobby

	local half = LobbyConfig.LOBBY_SIZE / 2
	local trimThickness = 1

	local edges = {
		{ size = Vector3.new(LobbyConfig.LOBBY_SIZE, 0.2, trimThickness), position = Vector3.new(0, 0.1, half - trimThickness / 2) },
		{ size = Vector3.new(LobbyConfig.LOBBY_SIZE, 0.2, trimThickness), position = Vector3.new(0, 0.1, -half + trimThickness / 2) },
		{ size = Vector3.new(trimThickness, 0.2, LobbyConfig.LOBBY_SIZE), position = Vector3.new(half - trimThickness / 2, 0.1, 0) },
		{ size = Vector3.new(trimThickness, 0.2, LobbyConfig.LOBBY_SIZE), position = Vector3.new(-half + trimThickness / 2, 0.1, 0) },
	}

	for i, edge in ipairs(edges) do
		PartUtils.CreatePart({
			name = "TrimEdge" .. i,
			size = edge.size,
			position = edge.position,
			material = Enum.Material.Neon,
			color = LobbyConfig.NEON_COLOR,
			canCollide = false,
			parent = trimFolder,
		})
	end

	return trimFolder
end

return Floor
