--[[
	ArenaDecorations.lua

	Builds the arena's floor ring decals, spectator seating (tagged
	"SpectatorSeat"), rim spotlights, and rotating "moving beam" fixtures.
]]

local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local ArenaConfig = require(script.Parent.ArenaConfig)
local Platforms = require(script.Parent.Platforms)

local ArenaDecorations = {}

-- Approximates a glowing ring outline using many short neon segments
-- placed and rotated around a circle (no true annulus primitive exists
-- without a mesh asset).
local function buildRingSegments(radius: number, segments: number, parent: Instance)
	for i = 1, segments do
		local angle = (i - 1) / segments * math.pi * 2
		local position = Vector3.new(math.sin(angle) * radius, 0.05, math.cos(angle) * radius)
		local segmentLength = (2 * math.pi * radius / segments) * 0.7

		PartUtils.CreatePart({
			name = "RingSegment" .. i,
			size = Vector3.new(0.6, 0.1, segmentLength),
			cframe = CFrame.new(position) * CFrame.Angles(0, angle, 0),
			material = Enum.Material.Neon,
			color = ArenaConfig.NEON_COLOR,
			canCollide = false,
			parent = parent,
		})
	end
end

local function buildFloorRings(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "FloorRings"
	folder.Parent = parent

	for _, radius in ipairs(ArenaConfig.FLOOR_RING_RADII) do
		buildRingSegments(radius, ArenaConfig.FLOOR_RING_SEGMENTS, folder)
	end
end

local function buildSeatRing(radius: number, parent: Instance)
	local circumference = 2 * math.pi * radius
	local count = math.floor(circumference / ArenaConfig.SPECTATOR_SEAT_SPACING)

	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2
		local position = Vector3.new(math.sin(angle) * radius, 1, math.cos(angle) * radius)

		local seat = PartUtils.CreatePart({
			className = "Seat",
			name = "Seat" .. i,
			size = Vector3.new(2, 1, 2),
			cframe = CFrame.new(position) * CFrame.Angles(0, angle + math.pi, 0),
			material = Enum.Material.Fabric,
			color = Color3.fromRGB(40, 45, 60),
			parent = parent,
		})

		CollectionService:AddTag(seat, "SpectatorSeat")
	end
end

local function buildSpectatorSeating(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "SpectatorSeating"
	folder.Parent = parent

	local platformRingRadius = Platforms.ComputeRingRadius()

	for _, offset in ipairs(ArenaConfig.SPECTATOR_RING_OFFSETS) do
		buildSeatRing(platformRingRadius + offset, folder)
	end
end

local function buildRimLights(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "RimLights"
	folder.Parent = parent

	local count = ArenaConfig.RIM_LIGHT_COUNT
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2
		local radius = ArenaConfig.ARENA_RADIUS - 5
		local position = Vector3.new(math.sin(angle) * radius, ArenaConfig.RIM_LIGHT_HEIGHT, math.cos(angle) * radius)

		local fixture = PartUtils.CreatePart({
			name = "RimLight" .. i,
			size = Vector3.new(2, 2, 2),
			position = position,
			material = Enum.Material.Metal,
			color = Color3.fromRGB(30, 30, 35),
			canCollide = false,
			parent = folder,
		})

		local spotlight = Instance.new("SpotLight")
		spotlight.Name = "Spotlight"
		spotlight.Face = Enum.NormalId.Bottom
		spotlight.Range = 80
		spotlight.Angle = 35
		spotlight.Brightness = 4
		spotlight.Color = ArenaConfig.NEON_COLOR
		spotlight.Parent = fixture
	end
end

local function buildMovingBeams(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "MovingBeams"
	folder.Parent = parent

	local count = ArenaConfig.MOVING_BEAM_COUNT
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2
		local radius = ArenaConfig.ARENA_RADIUS * 0.5
		local position = Vector3.new(math.sin(angle) * radius, ArenaConfig.MOVING_BEAM_HEIGHT, math.cos(angle) * radius)

		local fixture = PartUtils.CreatePart({
			name = "MovingBeam" .. i,
			size = Vector3.new(1.5, 1.5, 1.5),
			position = position,
			material = Enum.Material.Neon,
			color = ArenaConfig.NEON_COLOR,
			canCollide = false,
			parent = folder,
		})

		local spotlight = Instance.new("SpotLight")
		spotlight.Name = "Spotlight"
		spotlight.Face = Enum.NormalId.Bottom
		spotlight.Range = 100
		spotlight.Angle = 20
		spotlight.Brightness = 5
		spotlight.Color = ArenaConfig.NEON_COLOR
		spotlight.Parent = fixture

		-- Continuous sweeping rotation to simulate a moving concert beam.
		local tween = TweenService:Create(
			fixture,
			TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false),
			{ Orientation = Vector3.new(0, 360, 0) }
		)
		tween:Play()
	end
end

function ArenaDecorations.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Decorations"
	folder.Parent = parent

	buildFloorRings(parent)
	buildSpectatorSeating(folder)
	buildRimLights(folder)
	buildMovingBeams(folder)

	return folder
end

return ArenaDecorations
