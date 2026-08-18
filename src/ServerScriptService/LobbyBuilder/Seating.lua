--[[
	Seating.lua

	Builds the lobby's seating: four visually distinct seat types
	(SeatTypeA-D, see SeatingConfig.lua for their parameters), placed into
	five hand-designed seating zones. Replaces the old single repeated
	"Bench" design in Decorations.lua.

	One builder function per seat type - reused across every zone/
	placement that uses that type, rather than duplicated per-instance.
	Each built seat is a Model with:
		- Attribute SeatingConfig.DECORATIVE_ATTRIBUTE = true
		- Attribute "SeatType" = the type id (e.g. "SeatTypeA")
		- Attribute "SeatingZone" = the zone id (e.g. "WalkwayZone")
	so later systems (or just manual inspection) can reliably identify
	seating without depending on tree position/naming.

	Static, source-generated geometry - no runtime randomness in the
	seats themselves; only their (hand-placed, source-controlled)
	position/yaw vary per SeatingConfig.ZONES.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local SeatingConfig = require(script.Parent.SeatingConfig)

local Seating = {}

-- ===== SeatTypeA: "Classic Bench" - two leg supports, modest backrest,
-- no armrests, thin neon underglow strip. =====
local function buildSeatTypeA(cframe: CFrame, model: Model, def)
	local legHeight = 1.2
	local seatY = legHeight + def.seatSize.Y / 2

	PartUtils.CreatePart({
		name = "Seat",
		size = def.seatSize,
		cframe = cframe * CFrame.new(0, seatY, 0),
		material = def.seatMaterial,
		color = def.seatColor,
		parent = model,
	})

	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "Leg",
			size = Vector3.new(0.35, legHeight, def.seatSize.Z - 0.2),
			cframe = cframe * CFrame.new(side * (def.seatSize.X / 2 - 0.5), legHeight / 2, 0),
			material = Enum.Material.Metal,
			color = Color3.fromRGB(60, 63, 70),
			parent = model,
		})
	end

	PartUtils.CreatePart({
		name = "Backrest",
		size = Vector3.new(def.seatSize.X, def.backrestHeight, 0.25),
		cframe = cframe * CFrame.new(0, seatY + def.backrestHeight / 2, -def.seatSize.Z / 2),
		material = def.seatMaterial,
		color = def.seatColor,
		canCollide = false,
		parent = model,
	})

	PartUtils.CreatePart({
		name = "UnderglowStrip",
		size = Vector3.new(def.seatSize.X - 0.6, 0.1, 0.15),
		cframe = cframe * CFrame.new(0, legHeight - 0.15, def.seatSize.Z / 2 - 0.1),
		material = Enum.Material.Neon,
		color = def.accentColor,
		canCollide = false,
		parent = model,
	})
end

-- ===== SeatTypeB: "Lounge Chair" - armrests, single pedestal block,
-- slightly reclined backrest. =====
local function buildSeatTypeB(cframe: CFrame, model: Model, def)
	local pedestalHeight = 1.1
	local seatY = pedestalHeight + def.seatSize.Y / 2

	PartUtils.CreatePart({
		name = "Seat",
		size = def.seatSize,
		cframe = cframe * CFrame.new(0, seatY, 0),
		material = def.seatMaterial,
		color = def.seatColor,
		parent = model,
	})

	PartUtils.CreatePart({
		name = "PedestalBlock",
		size = Vector3.new(def.seatSize.X - 0.8, pedestalHeight, def.seatSize.Z - 0.8),
		cframe = cframe * CFrame.new(0, pedestalHeight / 2, 0),
		material = Enum.Material.Metal,
		color = Color3.fromRGB(50, 53, 60),
		parent = model,
	})

	-- Slightly reclined backrest (a small forward tilt away from
	-- vertical) for a "lounge" feel rather than an upright bench back.
	local backrestCFrame = cframe
		* CFrame.new(0, seatY, -def.seatSize.Z / 2 + 0.15)
		* CFrame.Angles(math.rad(-12), 0, 0)
		* CFrame.new(0, def.backrestHeight / 2, 0)
	PartUtils.CreatePart({
		name = "Backrest",
		size = Vector3.new(def.seatSize.X - 0.3, def.backrestHeight, 0.25),
		cframe = backrestCFrame,
		material = def.seatMaterial,
		color = def.seatColor,
		canCollide = false,
		parent = model,
	})

	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "Armrest",
			size = Vector3.new(0.3, 0.6, def.seatSize.Z - 0.4),
			cframe = cframe * CFrame.new(side * (def.seatSize.X / 2 - 0.15), seatY + 0.5, 0),
			material = def.seatMaterial,
			color = def.seatColor,
			canCollide = false,
			parent = model,
		})
		PartUtils.CreatePart({
			name = "ArmrestTrim",
			size = Vector3.new(0.32, 0.08, def.seatSize.Z - 0.5),
			cframe = cframe * CFrame.new(side * (def.seatSize.X / 2 - 0.15), seatY + 0.8, 0),
			material = Enum.Material.Neon,
			color = def.accentColor,
			canCollide = false,
			parent = model,
		})
	end
end

-- ===== SeatTypeC: "Booth Seat" - tall backrest with angled side wings,
-- solid block base, neon edge trim. =====
local function buildSeatTypeC(cframe: CFrame, model: Model, def)
	local blockHeight = 1.1
	local seatY = blockHeight + def.seatSize.Y / 2

	PartUtils.CreatePart({
		name = "BaseBlock",
		size = Vector3.new(def.seatSize.X + 0.4, blockHeight, def.seatSize.Z + 0.4),
		cframe = cframe * CFrame.new(0, blockHeight / 2, 0),
		material = def.seatMaterial,
		color = def.seatColor,
		parent = model,
	})

	PartUtils.CreatePart({
		name = "Seat",
		size = def.seatSize,
		cframe = cframe * CFrame.new(0, seatY, 0),
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(225, 225, 230),
		parent = model,
	})

	PartUtils.CreatePart({
		name = "Backrest",
		size = Vector3.new(def.seatSize.X, def.backrestHeight, 0.3),
		cframe = cframe * CFrame.new(0, seatY + def.backrestHeight / 2, -def.seatSize.Z / 2),
		material = def.seatMaterial,
		color = def.seatColor,
		canCollide = false,
		parent = model,
	})

	-- Angled side wings, flaring outward from the backrest - the
	-- "enclosed booth" identity element that sets this type apart from
	-- SeatTypeA's flat backrest.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			className = "WedgePart",
			name = "BoothWing",
			size = Vector3.new(def.seatSize.Z, def.backrestHeight, 0.3),
			cframe = cframe
				* CFrame.new(side * (def.seatSize.X / 2 + 0.02), seatY + def.backrestHeight / 2, def.seatSize.Z / 4)
				* CFrame.Angles(0, math.rad(side == -1 and -90 or 90), 0),
			material = def.seatMaterial,
			color = def.seatColor,
			canCollide = false,
			parent = model,
		})
	end

	PartUtils.CreatePart({
		name = "BackrestTrim",
		size = Vector3.new(def.seatSize.X + 0.1, 0.12, 0.32),
		cframe = cframe * CFrame.new(0, seatY + def.backrestHeight + 0.06, -def.seatSize.Z / 2),
		material = Enum.Material.Neon,
		color = def.accentColor,
		canCollide = false,
		parent = model,
	})
end

-- ===== SeatTypeD: "Portal Stool" - low, round, backless, single
-- pedestal post - deliberately unobtrusive near the portal/sign. =====
local function buildSeatTypeD(cframe: CFrame, model: Model, def)
	local postHeight = 1.0
	local seatDiameter = def.seatSize.X

	PartUtils.CreateDisc({
		name = "PedestalPost",
		diameter = 0.6,
		thickness = postHeight,
		position = (cframe * CFrame.new(0, postHeight / 2, 0)).Position,
		material = Enum.Material.Metal,
		color = Color3.fromRGB(55, 58, 66),
		parent = model,
	})

	PartUtils.CreateDisc({
		name = "BaseRingAccent",
		diameter = 0.8,
		thickness = 0.1,
		position = (cframe * CFrame.new(0, 0.1, 0)).Position,
		material = Enum.Material.Neon,
		color = def.accentColor,
		canCollide = false,
		parent = model,
	})

	PartUtils.CreatePart({
		name = "Seat",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(def.seatSize.Y, seatDiameter, seatDiameter),
		cframe = cframe * CFrame.new(0, postHeight + def.seatSize.Y / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		material = def.seatMaterial,
		color = def.seatColor,
		parent = model,
	})
end

local SEAT_BUILDERS = {
	SeatTypeA = buildSeatTypeA,
	SeatTypeB = buildSeatTypeB,
	SeatTypeC = buildSeatTypeC,
	SeatTypeD = buildSeatTypeD,
}

--[[
	Builds every seat in every zone from SeatingConfig.ZONES, parented
	into a single "LobbySeating" folder under `parent` (the lobby folder).
	Returns the folder, plus a flat list of every seat's world position -
	Decorations.lua feeds that list into street lamp / tree placement
	avoidance so nothing gets built on top of a seating zone.
]]
function Seating.BuildAll(parent: Instance): (Folder, { Vector3 })
	local folder = Instance.new("Folder")
	folder.Name = "LobbySeating"
	folder:SetAttribute(SeatingConfig.ROOT_ATTRIBUTE, true)
	folder.Parent = parent

	local allPositions = {}

	for _, zone in ipairs(SeatingConfig.ZONES) do
		local seatDef = SeatingConfig.SEAT_TYPES[zone.seatType]
		local builder = SEAT_BUILDERS[zone.seatType]

		local zoneFolder = Instance.new("Folder")
		zoneFolder.Name = zone.id
		zoneFolder:SetAttribute("SeatingZone", zone.id)
		zoneFolder.Parent = folder

		for i, placement in ipairs(zone.placements) do
			local model = Instance.new("Model")
			model.Name = seatDef.id .. i
			model:SetAttribute(SeatingConfig.DECORATIVE_ATTRIBUTE, true)
			model:SetAttribute("SeatType", seatDef.id)
			model:SetAttribute("SeatingZone", zone.id)

			local cframe = CFrame.new(placement.position) * CFrame.Angles(0, math.rad(placement.yawDegrees), 0)
			builder(cframe, model, seatDef)

			model.Parent = zoneFolder
			table.insert(allPositions, placement.position)
		end
	end

	return folder, allPositions
end

return Seating
