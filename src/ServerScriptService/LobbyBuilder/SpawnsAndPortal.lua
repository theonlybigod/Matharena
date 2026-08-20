--[[
	SpawnsAndPortal.lua

	Builds the 4 player spawn locations and the queue portal structure.

	The queue portal is visual/structural only in this pass — it is not
	wired to any queueing or match logic yet (that belongs to MatchSystem
	in a later prompt). It exposes an invisible trigger volume tagged
	"QueuePortal" via CollectionService so future systems can find it with
	CollectionService:GetTagged("QueuePortal") without this module needing
	to know anything about match/queue logic.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local LobbyConfig = require(script.Parent.LobbyConfig)
local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)

local SpawnsAndPortal = {}

function SpawnsAndPortal.BuildSpawns(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Spawns"
	folder.Parent = parent

	-- Message 23: each spawn is individually rotated to face the
	-- leaderboard arc (LobbyConfig.SPAWN_POSITIONS carries a per-spawn
	-- facingYawDegrees now, not just a bare position) - see that field's
	-- comment in LobbyConfig.lua for why a single shared rotation isn't
	-- enough (the four spawns are at different angles from the arc).
	for i, spawn in ipairs(LobbyConfig.SPAWN_POSITIONS) do
		PartUtils.CreatePart({
			className = "SpawnLocation",
			name = "Spawn" .. i,
			size = Vector3.new(LobbyConfig.SPAWN_SIZE.X, 1, LobbyConfig.SPAWN_SIZE.Y),
			cframe = CFrame.new(spawn.position) * CFrame.Angles(0, math.rad(spawn.facingYawDegrees), 0),
			material = Enum.Material.Concrete,
			color = LobbyConfig.FLOOR_COLOR,
			parent = folder,
		})
	end

	return folder
end

function SpawnsAndPortal.BuildQueuePortal(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "QueuePortal"
	model.Parent = parent

	PartUtils.CreatePart({
		name = "PortalBase",
		size = Vector3.new(LobbyConfig.QUEUE_PORTAL_SIZE.X, 0.4, LobbyConfig.QUEUE_PORTAL_SIZE.Y),
		position = LobbyConfig.QUEUE_PORTAL_POSITION + Vector3.new(0, 0.2, 0),
		material = Enum.Material.Neon,
		color = LightingConfig.CENTRAL_FEATURE,
		canCollide = false,
		parent = model,
	})

	local half = LobbyConfig.QUEUE_PORTAL_SIZE.X / 2
	local corners = {
		Vector3.new(half, 0, half),
		Vector3.new(half, 0, -half),
		Vector3.new(-half, 0, half),
		Vector3.new(-half, 0, -half),
	}

	for i, offset in ipairs(corners) do
		PartUtils.CreatePart({
			name = "Pillar" .. i,
			size = Vector3.new(1, 10, 1),
			position = LobbyConfig.QUEUE_PORTAL_POSITION + offset + Vector3.new(0, 5, 0),
			material = Enum.Material.Metal,
			color = Color3.fromRGB(50, 50, 55),
			parent = model,
		})
	end

	local trigger = PartUtils.CreatePart({
		name = "Trigger",
		size = Vector3.new(LobbyConfig.QUEUE_PORTAL_SIZE.X, 6, LobbyConfig.QUEUE_PORTAL_SIZE.Y),
		position = LobbyConfig.QUEUE_PORTAL_POSITION + Vector3.new(0, 3, 0),
		transparency = 1,
		canCollide = false,
		parent = model,
	})
	CollectionService:AddTag(trigger, "QueuePortal")

	return model
end

return SpawnsAndPortal
