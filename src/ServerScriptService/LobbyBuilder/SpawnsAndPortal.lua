--[[
	SpawnsAndPortal.lua

	Builds the 4 player spawn locations and the queue portal structure.

	The queue portal is visual/structural only - its invisible trigger
	volume (tagged "QueuePortal" via CollectionService) is a purely
	decorative landmark now, not a queue-entry trigger. MatchSystem used to
	wire a Touched handler to this tag that silently queued any player who
	walked across the map's dead center for a match with zero confirmation
	- that auto-join behavior has been removed entirely (see MatchSystem's
	module doc comment) because it bypassed the game's actual, deliberate
	entry point (the Play button's tier-select-then-confirm popup). The
	tag is left in place in case a future system wants to find this part by
	name, but nothing currently listens for it being touched.

	Pillar removal pass: the four decorative corner pillars around the
	portal have been removed entirely, per explicit direction ("pillars 1
	to 4 of the queue portal section gone"). The portal's floor disc and
	the invisible trigger volume (used by MatchSystem) are untouched.
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
