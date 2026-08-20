--[[
	ArenaDecorations.lua

	Builds the arena's floor ring decals and spectator seating (tagged
	"SpectatorSeat").

	Spotlight removal pass: rim spotlights and rotating "moving beam"
	fixtures have been removed entirely, per explicit direction ("I know
	they add light to the map, I don't want those features anymore") -
	their sole purpose was to be spotlights, so removing just the SpotLight
	and leaving a pointless decorative fixture behind wouldn't match what
	was actually asked for.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local ArenaConfig = require(script.Parent.ArenaConfig)
local Platforms = require(script.Parent.Platforms)

local ArenaDecorations = {}

-- Approximates a glowing ring outline using many short neon segments
-- placed and rotated around a circle (no true annulus primitive exists
-- without a mesh asset).
--
-- Message 21 fix (section 6): positioned with a genuine, deliberate gap
-- above the arena floor (ArenaConfig.FLOOR_RING_HEIGHT_ABOVE_FLOOR) -
-- previously these sat at Y=0.05 with a 0.1-stud thickness, putting their
-- BOTTOM face at exactly Y=0, precisely coincident with the floor's top
-- face. That's a textbook z-fighting setup (the same bug class already
-- found and fixed once before in the lobby's ground/trim), which is what
-- caused the "visual inconsistency/glitching" on the arena floor. The
-- floor itself was always a single Marble-material disc - the fix here
-- is purely the gap, not a material change.
local function buildRingSegments(radius: number, segments: number, parent: Instance)
	local segmentThickness = 0.1
	local centerY = ArenaConfig.FLOOR_RING_HEIGHT_ABOVE_FLOOR + segmentThickness / 2
	for i = 1, segments do
		local angle = (i - 1) / segments * math.pi * 2
		local position = Vector3.new(math.sin(angle) * radius, centerY, math.cos(angle) * radius)
		local segmentLength = (2 * math.pi * radius / segments) * 0.7

		PartUtils.CreatePart({
			name = "RingSegment" .. i,
			size = Vector3.new(0.6, segmentThickness, segmentLength),
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

function ArenaDecorations.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Decorations"
	folder.Parent = parent

	buildFloorRings(parent)
	buildSpectatorSeating(folder)

	return folder
end

return ArenaDecorations
