--[[
	LavaEnvironment.lua

	Builds the Lava map's signature backdrop: a large enclosing ring of
	dark volcanic-rock wall panels (with glowing fissure cracks running
	through them) plus a matching ash-haze ceiling and floor cap, a
	scattering of rising ember particles, distant volcano silhouettes
	near the boundary, and a scattering of ground-level lava fissures
	within the playable area itself - glowing cracks with lava visibly
	flowing through them, not just a recolored floor.

	LAVA-MAP-ONLY: only ever called by LobbyBuilder for the Lava map
	(def.themeId == "Lava" - see LobbyBuilder/init.lua). Every other map
	is completely untouched by this module.

	Architecture mirrors SpaceEnvironment.lua exactly (same enclosing-ring
	technique, same local-space-then-bulk-translate convention, same
	ENCLOSURE_RADIUS/fog-distance reasoning) - see that module's doc
	comment for the full explanation of why a single giant Part doesn't
	work here and why the shared global Lighting fog caps how large this
	can usefully be.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local MapConfig = require(script.Parent.MapConfig)

local LavaEnvironment = {}

local ENCLOSURE_RADIUS = 300
local WALL_SEGMENTS = 28
local WALL_HEIGHT = 700
local WALL_BOTTOM_Y = -200
local WALL_THICKNESS = 4
local ROCK_COLOR = Color3.fromRGB(24, 18, 16) -- dark, ash-choked volcanic rock
local GLOW_COLOR = Color3.fromRGB(255, 110, 30)

--[[
	Builds the enclosing dark-rock ring + ceiling/floor caps - see
	SpaceEnvironment.lua's buildWallSegments doc comment for the full
	explanation of why this is a ring of thin panels (each one the camera
	stands beside, never inside) rather than one giant part. A handful of
	glowing fissure cracks (thin Neon strips) are embedded directly in a
	few wall segments so the horizon itself reads as smoldering rock, not
	just a flat dark backdrop.
]]
local function buildWallSegments(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "RockWalls"
	folder.Parent = parent

	local wallCenterY = WALL_BOTTOM_Y + WALL_HEIGHT / 2
	local rng = Random.new(772140)
	for i = 0, WALL_SEGMENTS - 1 do
		local angle1 = (2 * math.pi / WALL_SEGMENTS) * i
		local angle2 = (2 * math.pi / WALL_SEGMENTS) * (i + 1)
		local v1 = Vector3.new(ENCLOSURE_RADIUS * math.sin(angle1), 0, ENCLOSURE_RADIUS * math.cos(angle1))
		local v2 = Vector3.new(ENCLOSURE_RADIUS * math.sin(angle2), 0, ENCLOSURE_RADIUS * math.cos(angle2))
		local midpoint = (v1 + v2) / 2
		local direction = v2 - v1
		local length = direction.Magnitude + 3
		local yaw = math.atan2(direction.X, direction.Z)

		PartUtils.CreatePart({
			name = "RockWall" .. i,
			size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, length),
			cframe = CFrame.new(midpoint + Vector3.new(0, wallCenterY, 0)) * CFrame.Angles(0, yaw, 0),
			material = Enum.Material.Basalt,
			color = ROCK_COLOR,
			canCollide = false,
			parent = folder,
		})

		-- Roughly every third segment gets a glowing fissure crack, so
		-- the horizon reads as smoldering rather than uniformly dark.
		if i % 3 == 0 then
			PartUtils.CreatePart({
				name = "WallFissure" .. i,
				size = Vector3.new(WALL_THICKNESS + 0.6, rng:NextNumber(120, 260), 1.2),
				cframe = CFrame.new(midpoint + Vector3.new(0, wallCenterY + rng:NextNumber(-100, 150), 0))
					* CFrame.Angles(0, yaw, math.rad(rng:NextNumber(-8, 8))),
				material = Enum.Material.CrackedLava,
				color = GLOW_COLOR,
				canCollide = false,
				parent = folder,
			})
		end
	end
end

local function buildCeiling(parent: Instance)
	local ceilingY = WALL_BOTTOM_Y + WALL_HEIGHT + 6
	PartUtils.CreatePart({
		name = "AshCeiling",
		size = Vector3.new(ENCLOSURE_RADIUS * 2 + 40, 8, ENCLOSURE_RADIUS * 2 + 40),
		position = Vector3.new(0, ceilingY, 0),
		material = Enum.Material.Slate,
		color = Color3.fromRGB(30, 24, 22),
		canCollide = false,
		parent = parent,
	})
end

-- Caps the bottom of the enclosure - see SpaceEnvironment.lua's buildFloor
-- doc comment for why this matters ("the bottom of the outline" gap).
local function buildFloor(parent: Instance)
	PartUtils.CreatePart({
		name = "RockFloor",
		size = Vector3.new(ENCLOSURE_RADIUS * 2 + 40, 8, ENCLOSURE_RADIUS * 2 + 40),
		position = Vector3.new(0, WALL_BOTTOM_Y - 6, 0),
		material = Enum.Material.Basalt,
		color = ROCK_COLOR,
		canCollide = false,
		parent = parent,
	})
end

--[[
	Rising ember particles scattered around the map - each an invisible
	anchor part with a ParticleEmitter tuned to drift upward and fade,
	purely decorative (no PointLights, matching the performance guidance
	already established by SpaceEnvironment.lua).
]]
local function buildEmbers(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Embers"
	folder.Parent = parent

	local rng = Random.new(552391)
	local count = 16
	for i = 1, count do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(20, MapConfig.USABLE_RADIUS * 0.98)
		local position = Vector3.new(math.sin(angle) * radius, 1, math.cos(angle) * radius)

		local anchor = PartUtils.CreatePart({
			name = "EmberAnchor" .. i,
			size = Vector3.new(1, 1, 1),
			position = position,
			transparency = 1,
			canCollide = false,
			parent = folder,
		}) :: BasePart

		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(GLOW_COLOR)
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Size = NumberSequence.new(0.3)
		emitter.Lifetime = NumberRange.new(4, 7)
		emitter.Speed = NumberRange.new(3, 6)
		emitter.Rate = 3
		emitter.SpreadAngle = Vector2.new(10, 10)
		emitter.Acceleration = Vector3.new(0, 4, 0)
		emitter.Parent = anchor
	end
end

--[[
	One volcano landmark near the boundary - REBUILT as a genuinely
	CONNECTED landform instead of a pile of overlapping boulder/sphere
	chunks: a continuous tapered slope built from large, heavily-
	overlapping angled rock "shingles" (flattened slabs tilted to match
	the cone's own slope angle at each tier, like Roblox's classic
	mountain-building technique), plus a wide, very-shallow-sloped SKIRT
	blending the volcano's foot into the surrounding ground so it reads as
	one continuous terrain feature rather than a mound floating on flat
	ground. Lava channels are laid FLUSH ON the slope (same tilt as the
	shingles beneath them) so they read as molten rock running down/through
	the terrain, not detached glowing boxes hovering near it. A crater-like
	glowing opening still caps the peak, and a handful of heated vents and
	jagged ridge outcrops break up the surface for visual irregularity.
]]
local function slopeCFrame(position: Vector3, angle: number, pitch: number): CFrame
	return CFrame.new(position) * CFrame.Angles(0, angle, 0) * CFrame.Angles(pitch, 0, 0)
end

local function buildDistantVolcano(position: Vector3, rng: Random, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local baseRadius = rng:NextNumber(45, 65)
	local peakHeight = rng:NextNumber(90, 150)
	local craterRadius = 4 + rng:NextNumber(0, 2)
	-- Slope angle of the cone's face measured from horizontal - used to
	-- tilt every shingle so its flat top face lies FLUSH against the
	-- theoretical cone surface instead of sitting at a fixed flat angle
	-- that would gap open against its neighbors above/below.
	local slopeAngle = math.atan2(peakHeight, baseRadius - craterRadius)
	local shinglePitch = (math.pi / 2) - slopeAngle

	-- Continuous tapered slope: many tiers from the ground up to the
	-- crater rim, each a ring of large overlapping shingles. Consecutive
	-- tiers overlap in BOTH radius and height (shingleLength/shingleHeight
	-- deliberately oversized relative to the tier spacing) so there is
	-- never a seam or gap between one tier and the next - this is what
	-- makes the mountain read as one continuous rock surface instead of
	-- discrete floating rings.
	local tierCount = 9
	for tier = 0, tierCount do
		local t = tier / tierCount
		local ringRadius = math.max(craterRadius, baseRadius * (1 - t) ^ 0.9)
		local ringY = peakHeight * t ^ 1.05
		local shingleLength = (baseRadius / tierCount) * 2.6 -- deep radial overlap tier-to-tier
		local shingleWidth = math.max(9, ringRadius * 0.6)
		local shingleCount = math.max(8, math.floor((2 * math.pi * ringRadius) / (shingleWidth * 0.55)))
		for c = 1, shingleCount do
			local angle = (2 * math.pi / shingleCount) * c + rng:NextNumber(-0.12, 0.12)
			local jitterRadius = ringRadius + rng:NextNumber(-1.5, 1.5)
			local jitterY = ringY + rng:NextNumber(-2, 2)
			local shinglePos = position + Vector3.new(math.sin(angle) * jitterRadius, jitterY, math.cos(angle) * jitterRadius)
			PartUtils.CreatePart({
				name = ("ShingleT%dC%d"):format(tier, c),
				size = Vector3.new(shingleWidth * rng:NextNumber(0.9, 1.15), rng:NextNumber(2.5, 4.5), shingleLength),
				cframe = slopeCFrame(shinglePos, angle, shinglePitch + math.rad(rng:NextNumber(-4, 4))),
				material = if rng:NextNumber() < 0.35 then Enum.Material.Rock else Enum.Material.Basalt,
				color = Color3.fromRGB(26 + rng:NextInteger(-4, 6), 20 + rng:NextInteger(-3, 5), 18 + rng:NextInteger(-3, 4)),
				canCollide = false,
				parent = model,
			})
		end

		-- Occasional jagged ridge outcrop breaking above the slope surface,
		-- so it doesn't read as a perfectly smooth cone.
		if tier > 0 and tier < tierCount and rng:NextNumber() < 0.5 then
			local ridgeAngle = rng:NextNumber(0, 2 * math.pi)
			local ridgePos = position + Vector3.new(math.sin(ridgeAngle) * ringRadius, ringY + rng:NextNumber(2, 6), math.cos(ridgeAngle) * ringRadius)
			PartUtils.CreatePart({
				name = "RidgeOutcrop" .. tier,
				size = Vector3.new(rng:NextNumber(6, 12), rng:NextNumber(6, 14), rng:NextNumber(6, 12)),
				cframe = slopeCFrame(ridgePos, ridgeAngle, shinglePitch * 0.6) * CFrame.Angles(0, 0, rng:NextNumber(-0.3, 0.3)),
				material = Enum.Material.Rock,
				color = Color3.fromRGB(30 + rng:NextInteger(-4, 6), 23 + rng:NextInteger(-3, 5), 19 + rng:NextInteger(-3, 4)),
				canCollide = false,
				parent = model,
			})
		end
	end

	-- Wide, very-shallow skirt blending the volcano's foot into the
	-- surrounding ground - without this the whole mountain still reads as
	-- a mound dropped onto flat terrain no matter how solid its own slope
	-- is. A handful of big, nearly-flat overlapping slabs fanning out to
	-- ~2.2x the base radius, tapering down to ground level.
	local skirtOuterRadius = baseRadius * 2.2
	local skirtRingCount = 3
	for ring = 1, skirtRingCount do
		local ringFraction = ring / skirtRingCount
		local ringRadius = baseRadius + (skirtOuterRadius - baseRadius) * ringFraction
		local ringY = math.max(0, (peakHeight * 0.06) * (1 - ringFraction))
		local skirtPitch = shinglePitch * (1 - ringFraction) * 0.35
		local slabWidth = 22
		local slabCount = math.max(10, math.floor((2 * math.pi * ringRadius) / (slabWidth * 0.55)))
		for c = 1, slabCount do
			local angle = (2 * math.pi / slabCount) * c + rng:NextNumber(-0.15, 0.15)
			local slabPos = position + Vector3.new(math.sin(angle) * ringRadius, ringY, math.cos(angle) * ringRadius)
			PartUtils.CreatePart({
				name = ("SkirtSlabR%dC%d"):format(ring, c),
				size = Vector3.new(slabWidth * rng:NextNumber(0.9, 1.2), rng:NextNumber(1.5, 3), (skirtOuterRadius - baseRadius) / skirtRingCount * 2.4),
				cframe = slopeCFrame(slabPos, angle, skirtPitch),
				material = Enum.Material.Basalt,
				color = Color3.fromRGB(24 + rng:NextInteger(-4, 6), 19 + rng:NextInteger(-3, 5), 16 + rng:NextInteger(-3, 4)),
				canCollide = false,
				parent = model,
			})
		end
	end

	PartUtils.CreateDisc({
		name = "Crater",
		diameter = craterRadius * 2,
		thickness = 1.5,
		position = position + Vector3.new(0, peakHeight, 0),
		material = Enum.Material.CrackedLava,
		color = GLOW_COLOR,
		canCollide = false,
		parent = model,
	})

	-- Lava channels laid FLUSH ON the slope (same tilt as the shingles
	-- beneath them) so molten rock reads as running down/through the
	-- terrain, not as detached glowing boxes hovering near it.
	local channelCount = rng:NextInteger(4, 6)
	for i = 1, channelCount do
		local channelAngle = rng:NextNumber(0, 2 * math.pi)
		local channelStartT = rng:NextNumber(0, 0.15) -- start near the crater rim
		local channelEndT = rng:NextNumber(0.55, 0.95) -- end partway or all the way down the slope
		local startRadius = math.max(craterRadius, baseRadius * (1 - channelStartT) ^ 0.9)
		local endRadius = math.max(craterRadius, baseRadius * (1 - channelEndT) ^ 0.9)
		local startY = peakHeight * channelStartT ^ 1.05
		local endY = peakHeight * channelEndT ^ 1.05
		local midRadius = (startRadius + endRadius) / 2
		local midY = (startY + endY) / 2
		local channelLength = math.sqrt((startRadius - endRadius) ^ 2 + (startY - endY) ^ 2) + 4
		local channelPos = position + Vector3.new(math.sin(channelAngle) * midRadius, midY + 0.4, math.cos(channelAngle) * midRadius)
		PartUtils.CreatePart({
			name = "LavaChannel" .. i,
			size = Vector3.new(rng:NextNumber(2, 4.5), 0.35, channelLength),
			cframe = slopeCFrame(channelPos, channelAngle, shinglePitch),
			material = Enum.Material.CrackedLava,
			color = GLOW_COLOR,
			canCollide = false,
			parent = model,
		})
	end

	-- Small heated glowing vents scattered across the surface.
	for i = 1, rng:NextInteger(4, 7) do
		local t = rng:NextNumber(0.1, 0.85)
		local angle = rng:NextNumber(0, 2 * math.pi)
		local ventRadius = math.max(craterRadius, baseRadius * (1 - t) ^ 0.9)
		local ventY = peakHeight * t ^ 1.05 + 0.3
		PartUtils.CreatePart({
			name = "HeatVent" .. i,
			size = Vector3.new(rng:NextNumber(1.5, 3), 0.3, rng:NextNumber(1.5, 3)),
			cframe = slopeCFrame(position + Vector3.new(math.sin(angle) * ventRadius, ventY, math.cos(angle) * ventRadius), angle, shinglePitch),
			material = Enum.Material.CrackedLava,
			color = GLOW_COLOR,
			canCollide = false,
			parent = model,
		})
	end
end

local function buildDistantVolcanoes(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "DistantVolcanoes"
	folder.Parent = parent

	local rng = Random.new(884211)
	local count = 6
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local radius = rng:NextNumber(ENCLOSURE_RADIUS * 0.7, ENCLOSURE_RADIUS * 0.92)
		local position = Vector3.new(math.sin(angle) * radius, -30, math.cos(angle) * radius)
		buildDistantVolcano(position, rng, folder, "DistantVolcano" .. i)
	end
end

--[[
	Ground-level lava fissures within the playable area itself - a genuine
	irregular fracture pattern, NOT the old evenly-chained straight-line
	segments: each "system" is a random-walk crack of varying width/length
	with occasional forks (a shorter child crack splitting off at a
	different angle), so some cracks branch and intersect themselves while
	others simply terminate. Systems themselves vary too - most are lone
	isolated fractures, some are small clusters of 2-3 cracks sharing
	roughly the same origin point. Only some points along each crack get
	an actual glowing lava pool, and a faint wider translucent glow strip
	rides along each main crack for "subtle heat glow around the
	fissures" - not every fissure looks alike or evenly distributed.
]]
local function buildFissureBranch(
	cursor: Vector3,
	direction: number,
	totalSegments: number,
	rng: Random,
	parent: Instance,
	namePrefix: string,
	depth: number
)
	local branchWidth = rng:NextNumber(0.5, 1.5) * (1 - depth * 0.3)
	if branchWidth <= 0.15 or totalSegments <= 0 then
		return
	end

	for s = 1, totalSegments do
		local segLength = rng:NextNumber(2, 6) * (1 - depth * 0.15)
		direction += rng:NextNumber(-0.65, 0.65)
		local nextCursor = cursor + Vector3.new(math.sin(direction) * segLength, 0, math.cos(direction) * segLength)
		local midpoint = (cursor + nextCursor) / 2
		local yaw = math.atan2(nextCursor.X - cursor.X, nextCursor.Z - cursor.Z)
		local segWidth = branchWidth * rng:NextNumber(0.65, 1.2)

		PartUtils.CreatePart({
			name = namePrefix .. "Seg" .. s,
			size = Vector3.new(segWidth, 0.12, segLength + 0.4),
			cframe = CFrame.new(midpoint + Vector3.new(0, 0.16, 0)) * CFrame.Angles(0, yaw, 0),
			material = Enum.Material.CrackedLava,
			color = GLOW_COLOR,
			canCollide = false,
			parent = parent,
		})

		-- Faint wider heat-glow halo beneath the crack (depth 0 only, so
		-- forks stay cheap) - "subtle heat glow around the fissures".
		if depth == 0 then
			PartUtils.CreatePart({
				name = namePrefix .. "Glow" .. s,
				size = Vector3.new(segWidth * 3.2, 0.05, segLength + 0.4),
				cframe = CFrame.new(midpoint + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, yaw, 0),
				material = Enum.Material.Neon,
				color = GLOW_COLOR,
				transparency = 0.75,
				canCollide = false,
				parent = parent,
			})
		end

		-- Occasional lava pool along the crack (not at every segment) -
		-- "molten lava visibly beneath/within the broken ground".
		if rng:NextNumber() < 0.3 then
			PartUtils.CreateDisc({
				name = namePrefix .. "Pool" .. s,
				diameter = rng:NextNumber(1.5, 4),
				thickness = 0.1,
				position = nextCursor + Vector3.new(0, 0.14, 0),
				material = Enum.Material.CrackedLava,
				color = GLOW_COLOR,
				canCollide = false,
				parent = parent,
			})
		end

		-- Occasional fork - a shorter child crack splitting off at a
		-- different angle, so some fissures genuinely branch/intersect
		-- rather than every one being a single unbroken line.
		if depth < 2 and s > 1 and rng:NextNumber() < 0.28 then
			local forkDirection = direction + rng:NextNumber(0.7, 2.0) * (if rng:NextNumber() < 0.5 then 1 else -1)
			buildFissureBranch(nextCursor, forkDirection, rng:NextInteger(1, 3), rng, parent, namePrefix .. "Fork" .. s, depth + 1)
		end

		cursor = nextCursor
	end
end

local function buildGroundFissures(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "GroundFissures"
	folder.Parent = parent

	local rng = Random.new(129384)
	-- A mix of lone isolated fractures and small clusters of 2-3 cracks
	-- sharing roughly the same origin, so crack DENSITY itself varies
	-- across the map instead of one evenly-spaced crack per slot.
	local systemCount = 10
	for i = 1, systemCount do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(MapConfig.USABLE_RADIUS * 0.22, MapConfig.USABLE_RADIUS * 0.8)
		local center = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)

		local cracksHere = if rng:NextNumber() < 0.35 then rng:NextInteger(2, 3) else 1
		for c = 1, cracksHere do
			local originOffset = if cracksHere > 1 then Vector3.new(rng:NextNumber(-5, 5), 0, rng:NextNumber(-5, 5)) else Vector3.zero
			local startDirection = rng:NextNumber(0, 2 * math.pi)
			local totalSegments = rng:NextInteger(3, 7)
			buildFissureBranch(center + originOffset, startDirection, totalSegments, rng, folder, ("System%dCrack%d"):format(i, c), 0)
		end
	end
end

--[[
	Lava-specific ground TERRAIN pattern - replaces the generic shared
	ring/spoke/medallion ground design (see Floor.lua's
	THEMES_WITH_OWN_GROUND_PATTERN) with something that actually looks like
	cracked, broken volcanic earth: scattered low rock outcroppings
	breaking through the ground, small ash-drift mounds, and loose scree
	clusters - genuine surface relief and breakup, not another recolored
	copy of the futuristic map's rings-and-spokes medallion. Kept low/flat
	enough everywhere that walking across the map is never obstructed.
]]
local function buildGroundPattern(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "LavaGroundPattern"
	folder.Parent = parent

	local rng = Random.new(447213)

	-- Low rock outcroppings breaking through the ground - small clusters
	-- of irregular half-buried boulders, never taller than a curb, so
	-- they read as texture/terrain rather than obstacles.
	for i = 1, 14 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(MapConfig.USABLE_RADIUS * 0.15, MapConfig.USABLE_RADIUS * 0.92)
		local center = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		local chunkCount = rng:NextInteger(2, 4)
		for c = 1, chunkCount do
			local offset = Vector3.new(rng:NextNumber(-2.5, 2.5), 0, rng:NextNumber(-2.5, 2.5))
			local chunkSize = rng:NextNumber(1.2, 3)
			PartUtils.CreatePart({
				name = ("Outcrop%d_%d"):format(i, c),
				size = Vector3.new(chunkSize, chunkSize * rng:NextNumber(0.4, 0.7), chunkSize * rng:NextNumber(0.8, 1.2)),
				cframe = CFrame.new(center + offset + Vector3.new(0, chunkSize * 0.15, 0))
					* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
				material = Enum.Material.Basalt,
				color = Color3.fromRGB(30 + rng:NextInteger(-5, 8), 24 + rng:NextInteger(-4, 6), 20 + rng:NextInteger(-3, 5)),
				canCollide = false,
				parent = folder,
			})
		end
	end

	-- Ash-drift mounds - low, flat, wide patches of pale ash color
	-- breaking up the dark basalt floor's uniformity.
	for i = 1, 9 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(MapConfig.USABLE_RADIUS * 0.1, MapConfig.USABLE_RADIUS * 0.95)
		local center = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		PartUtils.CreateDisc({
			name = "AshDrift" .. i,
			diameter = rng:NextNumber(6, 13),
			thickness = 0.08,
			position = center + Vector3.new(0, 0.1, 0),
			material = Enum.Material.Slate,
			color = Color3.fromRGB(58, 50, 46),
			canCollide = false,
			parent = folder,
		})
	end
end

--[[
	Builds the full volcanic backdrop under `parent` (the map's root
	Workspace folder), in a single "LavaEnvironment" folder - see
	LobbyBuilder/init.lua for the (Lava map-only) call site.
]]
function LavaEnvironment.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "LavaEnvironment"
	folder.Parent = parent

	buildWallSegments(folder)
	buildCeiling(folder)
	buildFloor(folder)
	buildEmbers(folder)
	buildDistantVolcanoes(folder)
	buildGroundFissures(folder)
	buildGroundPattern(folder)

	return folder
end

return LavaEnvironment
