--[[
	UnderTheSeaEnvironment.lua

	Builds the Under the Sea map's signature backdrop: a large enclosing
	ring of dark teal "water volume" wall panels plus a matching ceiling
	cap (reads as murky open water surrounding the playable area - see
	SpaceEnvironment.lua's buildWallSegments doc comment for why this is a
	ring of panels rather than one giant enclosing part), scattered rising
	bubble streams, a scattering of coral reef formations, and small
	drifting schools of fish silhouettes well above head height near the
	map's edge.

	UNDER-THE-SEA-MAP-ONLY: only ever called by LobbyBuilder for the Under
	the Sea map (def.themeId == "UnderTheSea" - see LobbyBuilder/init.lua).
	Every other map (Futuristic, Lava, Space, Ice Age, and any future map)
	is completely untouched by this module.

	Architecture mirrors SpaceEnvironment.lua exactly (same enclosing-ring
	technique, same local-space-then-bulk-translate convention, same
	DOME_RADIUS/fog-distance reasoning) - see that module's doc comment
	for the full explanation of why a single giant Part doesn't work here
	and why the shared global Lighting fog caps how large this can
	usefully be. The only meaningful difference is the color palette and
	the decorative content (bubbles/coral/fish instead of
	stars/planets/asteroids).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local MapConfig = require(script.Parent.MapConfig)

local UnderTheSeaEnvironment = {}

local ENCLOSURE_RADIUS = 300
local WALL_SEGMENTS = 28
local WALL_HEIGHT = 700
local WALL_BOTTOM_Y = -200
local WALL_THICKNESS = 4
local WATER_COLOR = Color3.fromRGB(10, 45, 58) -- deep, murky open water

--[[
	Builds the enclosing "open water" ring + ceiling cap - see
	SpaceEnvironment.lua's buildWallSegments doc comment for the full
	explanation of why this is a ring of thin panels (each one the camera
	stands beside, never inside) rather than one giant part.
]]
local function buildWallSegments(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "WaterWalls"
	folder.Parent = parent

	local wallCenterY = WALL_BOTTOM_Y + WALL_HEIGHT / 2
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
			name = "WaterWall" .. i,
			size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, length),
			cframe = CFrame.new(midpoint + Vector3.new(0, wallCenterY, 0)) * CFrame.Angles(0, yaw, 0),
			material = Enum.Material.SmoothPlastic,
			color = WATER_COLOR,
			canCollide = false,
			parent = folder,
		})
	end
end

local function buildCeiling(parent: Instance)
	local ceilingY = WALL_BOTTOM_Y + WALL_HEIGHT + 6
	PartUtils.CreatePart({
		name = "WaterCeiling",
		size = Vector3.new(ENCLOSURE_RADIUS * 2 + 40, 8, ENCLOSURE_RADIUS * 2 + 40),
		position = Vector3.new(0, ceilingY, 0),
		material = Enum.Material.SmoothPlastic,
		color = WATER_COLOR,
		canCollide = false,
		parent = parent,
	})
end

-- Caps the bottom of the enclosure - see SpaceEnvironment.lua's buildFloor
-- doc comment for why this matters ("the bottom of the outline" gap).
local function buildFloor(parent: Instance)
	PartUtils.CreatePart({
		name = "WaterFloor",
		size = Vector3.new(ENCLOSURE_RADIUS * 2 + 40, 8, ENCLOSURE_RADIUS * 2 + 40),
		position = Vector3.new(0, WALL_BOTTOM_Y - 6, 0),
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(4, 20, 26),
		canCollide = false,
		parent = parent,
	})
end

--[[
	Scatters small rising bubble streams around the map - each an
	invisible anchor part with a ParticleEmitter tuned to slowly rise and
	fade, purely decorative (no PointLights, matching the performance
	guidance already established by SpaceEnvironment.lua). Deterministic
	seed so placement looks identical across rebuilds.
]]
local function buildBubbleStreams(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "BubbleStreams"
	folder.Parent = parent

	local rng = Random.new(552310)
	local count = 14
	for i = 1, count do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(40, MapConfig.USABLE_RADIUS * 0.98)
		local position = Vector3.new(math.sin(angle) * radius, 1, math.cos(angle) * radius)

		local anchor = PartUtils.CreatePart({
			name = "BubbleAnchor" .. i,
			size = Vector3.new(1, 1, 1),
			position = position,
			transparency = 1,
			canCollide = false,
			parent = folder,
		}) :: BasePart

		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(Color3.fromRGB(210, 240, 245))
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Size = NumberSequence.new(0.25)
		emitter.Lifetime = NumberRange.new(3, 5)
		emitter.Speed = NumberRange.new(3, 5)
		emitter.Rate = 4
		emitter.SpreadAngle = Vector2.new(6, 6)
		emitter.Acceleration = Vector3.new(0, 6, 0) -- bubbles accelerate upward
		emitter.Parent = anchor
	end
end

--[[
	Builds one coral reef formation: an irregular cluster of rounded rock/
	coral blocks in varied warm reef colors, with a couple of small
	glowing bioluminescent accent tips. Sits ON the seafloor (unlike the
	floating asteroid debris in SpaceEnvironment.lua) since coral reefs
	are a grounded feature, not a background object.
]]
local function buildCoralReef(position: Vector3, rng: Random, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local reefColors = {
		Color3.fromRGB(230, 120, 130),
		Color3.fromRGB(240, 170, 90),
		Color3.fromRGB(150, 110, 170),
	}

	local baseSize = rng:NextNumber(4, 7)
	local clusterCount = rng:NextInteger(4, 6)
	for i = 1, clusterCount do
		local offset = Vector3.new(rng:NextNumber(-3.5, 3.5), 0, rng:NextNumber(-3.5, 3.5))
		local height = baseSize * rng:NextNumber(0.6, 1.3)
		local width = baseSize * rng:NextNumber(0.5, 0.9)

		PartUtils.CreatePart({
			name = "ReefBlock" .. i,
			size = Vector3.new(width, height, width),
			position = position + offset + Vector3.new(0, height / 2, 0),
			material = Enum.Material.Rock,
			color = reefColors[rng:NextInteger(1, #reefColors)],
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = model,
		})
	end

	-- Bioluminescent accent tip on top of the tallest block.
	PartUtils.CreatePart({
		name = "ReefGlow",
		size = Vector3.new(baseSize * 0.3, baseSize * 0.3, baseSize * 0.3),
		position = position + Vector3.new(0, baseSize * 1.3 + baseSize * 0.15, 0),
		material = Enum.Material.Neon,
		color = Color3.fromRGB(90, 235, 220),
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})
end

local function buildCoralReefs(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "CoralReefs"
	folder.Parent = parent

	local rng = Random.new(773241)
	local count = 10
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local radius = rng:NextNumber(MapConfig.USABLE_RADIUS * 0.9, MapConfig.USABLE_RADIUS * 1.05)
		local position = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		buildCoralReef(position, rng, folder, "CoralReef" .. i)
	end
end

--[[
	Three distinct fish silhouette builders, inspired by different real-
	world fish body plans, so schools read as varied species rather than
	identical copies:
		"Reef" - small, deep-bodied, rounded (angelfish/clownfish-like):
			a flattened wide body plus a small triangular tail fin.
		"Ray" - flat, wide, diamond-shaped (manta/stingray-like): a broad
			flattened wedge with "wingtips" swept back, no separate tail.
		"Predator" - long, streamlined body with a dorsal fin and a
			forked tail (shark/tuna-like): the largest, fastest-reading
			silhouette of the three.
	Each takes a `cframe` (already oriented/positioned for this fish) and
	builds 2-4 parts under a small per-fish Model, so every fish is a
	genuine little assembly rather than one flat wedge.
]]
local function buildReefFish(cframe: CFrame, size: number, color: Color3, parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local body = PartUtils.CreatePart({
		name = "Body",
		size = Vector3.new(size * 0.9, size * 1.1, size * 0.35),
		cframe = cframe,
		material = Enum.Material.SmoothPlastic,
		color = color,
		canCollide = false,
		parent = model,
	})
	PartUtils.CreatePart({
		className = "WedgePart",
		name = "TailFin",
		size = Vector3.new(size * 0.5, size * 0.7, size * 0.1),
		cframe = cframe * CFrame.new(-size * 0.65, 0, 0) * CFrame.Angles(0, math.rad(90), 0),
		material = Enum.Material.SmoothPlastic,
		color = color,
		canCollide = false,
		parent = model,
	})
	model.PrimaryPart = body
	return model
end

local function buildRayFish(cframe: CFrame, size: number, color: Color3, parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local body = PartUtils.CreatePart({
		className = "WedgePart",
		name = "Body",
		size = Vector3.new(size * 1.6, size * 0.25, size * 1.3),
		cframe = cframe,
		material = Enum.Material.SmoothPlastic,
		color = color,
		canCollide = false,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "TailWhip",
		size = Vector3.new(size * 0.9, size * 0.08, size * 0.08),
		cframe = cframe * CFrame.new(-size * 1.1, 0, 0),
		material = Enum.Material.SmoothPlastic,
		color = color,
		canCollide = false,
		parent = model,
	})
	model.PrimaryPart = body
	return model
end

local function buildPredatorFish(cframe: CFrame, size: number, color: Color3, parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local body = PartUtils.CreatePart({
		name = "Body",
		size = Vector3.new(size * 1.8, size * 0.55, size * 0.4),
		cframe = cframe,
		material = Enum.Material.SmoothPlastic,
		color = color,
		canCollide = false,
		parent = model,
	})
	PartUtils.CreatePart({
		className = "WedgePart",
		name = "DorsalFin",
		size = Vector3.new(size * 0.5, size * 0.5, size * 0.08),
		cframe = cframe * CFrame.new(0.1, size * 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		material = Enum.Material.SmoothPlastic,
		color = color,
		canCollide = false,
		parent = model,
	})
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			className = "WedgePart",
			name = "TailLobe",
			size = Vector3.new(size * 0.45, size * 0.35, size * 0.06),
			cframe = cframe * CFrame.new(-size * 0.95, side * size * 0.15, 0) * CFrame.Angles(0, math.rad(90), 0),
			material = Enum.Material.SmoothPlastic,
			color = color,
			canCollide = false,
			parent = model,
		})
	end
	model.PrimaryPart = body
	return model
end

local FISH_BUILDERS = { buildReefFish, buildRayFish, buildPredatorFish }

--[[
	Small drifting schools of fish, well above head height so they never
	obstruct walking/paths - each school rolls ONE species (so it reads as
	a real school of the same fish, not a random mixed bag) from
	FISH_BUILDERS above, grouped into schools of 3-4, gently varied per fish.
]]
local function buildFishSchools(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "FishSchools"
	folder.Parent = parent

	local speciesPalettes = {
		{ Color3.fromRGB(235, 150, 60), Color3.fromRGB(255, 190, 90) }, -- clownfish-orange reef fish
		{ Color3.fromRGB(120, 140, 170), Color3.fromRGB(150, 165, 190) }, -- grey ray
		{ Color3.fromRGB(90, 110, 130), Color3.fromRGB(70, 90, 110) }, -- steel-blue predator
	}

	local rng = Random.new(918820)
	local schoolCount = 8
	for s = 1, schoolCount do
		local angle = (s - 1) / schoolCount * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local radius = rng:NextNumber(MapConfig.USABLE_RADIUS * 0.5, MapConfig.USABLE_RADIUS * 0.9)
		local height = rng:NextNumber(30, 65)
		local center = Vector3.new(math.sin(angle) * radius, height, math.cos(angle) * radius)
		local schoolYaw = rng:NextNumber(0, 2 * math.pi)

		local speciesIndex = ((s - 1) % #FISH_BUILDERS) + 1
		local builder = FISH_BUILDERS[speciesIndex]
		local palette = speciesPalettes[speciesIndex]
		-- Predator schools (species 3) read better as smaller, sparser groups
		-- - a "school" of large sharks/tuna should be a handful, not a dozen.
		local fishCount = if speciesIndex == 3 then rng:NextInteger(2, 3) else rng:NextInteger(3, 5)
		local baseSize = if speciesIndex == 3 then rng:NextNumber(3, 4.5) else rng:NextNumber(1.4, 2.2)

		for f = 1, fishCount do
			local offset = Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(-1.5, 1.5), rng:NextNumber(-4, 4))
			local size = baseSize * rng:NextNumber(0.85, 1.15)
			local cframe = CFrame.new(center + offset) * CFrame.Angles(0, schoolYaw + rng:NextNumber(-0.3, 0.3), 0)
			local color = palette[rng:NextInteger(1, #palette)]
			builder(cframe, size, color, folder, ("School%dFish%d"):format(s, f))
		end
	end
end

--[[
	Builds the full underwater backdrop under `parent` (the map's root
	Workspace folder), in a single "UnderTheSeaEnvironment" folder - see
	LobbyBuilder/init.lua for the (Under the Sea map-only) call site.
]]
--[[
	Soft pale-cyan "sunbeam" shafts angling down from the ceiling - large,
	highly transparent tilted panels, the classic "light penetrating open
	water" look. Purely atmospheric, kept to a handful for performance.
]]
local function buildLightShafts(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "LightShafts"
	folder.Parent = parent

	local ceilingY = WALL_BOTTOM_Y + WALL_HEIGHT
	local rng = Random.new(60219)
	for i = 1, 6 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(20, MapConfig.USABLE_RADIUS * 0.8)
		local position = Vector3.new(math.sin(angle) * radius, ceilingY * 0.4, math.cos(angle) * radius)
		local tilt = rng:NextNumber(-12, 12)

		PartUtils.CreatePart({
			name = "LightShaft" .. i,
			size = Vector3.new(rng:NextNumber(10, 18), ceilingY * 0.8, 1),
			cframe = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi), math.rad(tilt)),
			material = Enum.Material.Neon,
			color = Color3.fromRGB(190, 230, 235),
			transparency = 0.93,
			canCollide = false,
			parent = folder,
		})
	end
end

function UnderTheSeaEnvironment.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "UnderTheSeaEnvironment"
	folder.Parent = parent

	buildWallSegments(folder)
	buildCeiling(folder)
	buildFloor(folder)
	buildLightShafts(folder)
	buildBubbleStreams(folder)
	buildCoralReefs(folder)
	buildFishSchools(folder)

	return folder
end

return UnderTheSeaEnvironment
