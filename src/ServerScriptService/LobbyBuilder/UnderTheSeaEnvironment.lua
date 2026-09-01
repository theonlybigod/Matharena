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
-- Used by buildKelpForest to keep strands clear of building entrances.
local LobbyConfig = require(script.Parent.LobbyConfig)

local UnderTheSeaEnvironment = {}

--[[
	ENLARGED FOR THE REEF WALL.

	Was 300. The enclosure is a sealed opaque box - WaterWalls form a cylinder
	at this radius and WaterCeiling/WaterFloor are sized from it - so nothing
	outside it is visible from inside. It therefore sets the hard limit on how
	much surrounding seascape the map can show.

	At 300 there was only ~130 studs between the walkable plaza
	(USABLE_RADIUS 172) and the wall: nowhere to put a reef of any real mass
	without it crowding the plaza. 1000 gives ~800 studs of open water beyond
	the plaza for the reef ring to occupy.

	Walls, ceiling and floor all derive from this constant, so they scale
	automatically.
]]
local ENCLOSURE_RADIUS = 1000
-- Scaled with ENCLOSURE_RADIUS. At radius 300, 28 segments gave a ~67 stud
-- chord; at 1000 the same count gives 224 studs and the flat facets show as
-- vertical seams across the water. 96 restores a ~65 stud chord.
local WALL_SEGMENTS = 96
local WALL_HEIGHT = 700
local WALL_BOTTOM_Y = -200
local WALL_THICKNESS = 4
local WATER_COLOR = Color3.fromRGB(10, 45, 58) -- deep, murky open water

--[[
	REEF SHAPE MATHS.

	Rebuilt to follow a REAL reef profile rather than a generic noise ridge.
	The previous version was a smooth bell curve of ridged noise, which is why
	it read as sand dunes: reefs do not look like hills.

	A barrier reef has four distinct zones, working outward from the lagoon:

	  LAGOON      flat, sandy, deep-ish. Nothing grows tall here.
	  REEF FLAT   a shallow PLATEAU, almost level, near the surface. This is
	              the single most characteristic feature and the previous
	              version had none of it - a reef has a flat top, not a peak.
	  CREST       the highest line, where surf breaks.
	  FORE-REEF   a STEEP drop into deep water, far steeper than the inner
	              face, cut by spur-and-groove channels running down it.

	SPUR AND GROOVE. Real fore-reefs are ribbed with radial ridges (spurs)
	separated by sand channels (grooves) running perpendicular to the crest,
	carved by wave energy. This is the texture that most says "reef" at a
	distance, and it is purely radial - noise alone cannot produce it.

	BOMMIES. Isolated coral heads rising off the reef flat, from a separate
	high-frequency band, so the plateau is knobbly rather than a table.
]]
local TERRAIN_RES = 4

-- Zone boundaries, measured from the map centre.
local REEF_INNER = 330 -- lagoon edge; inside this is open sand
local REEF_FLAT_START = 470 -- where the reef flat plateau begins
local REEF_CREST = 700 -- highest line, where the fore-reef drop starts
local REEF_OUTER = 985 -- foot of the fore-reef, just inside the wall

local REEF_FLAT_HEIGHT = 150 -- height of the plateau
local CREST_HEIGHT = 205 -- height at the crest line

local function smoothRamp(edge0: number, edge1: number, value: number): number
	local t = math.clamp((value - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Plain fractal noise (not ridged). Ridged noise gives knife-edge crests,
-- which suited the Ice Age mountains; coral is lumpy and rounded.
local function fbm(x: number, z: number, frequency: number, octaves: number, seed: number): number
	local sum, amplitude, norm = 0, 1, 0
	local f = frequency
	for i = 1, octaves do
		sum += math.noise(x * f, z * f, seed + i) * amplitude
		norm += amplitude
		amplitude *= 0.5
		f *= 2
	end
	return sum / norm -- roughly -1..1
end

local function reefHeight(localX: number, localZ: number): number
	local dist = math.sqrt(localX * localX + localZ * localZ)
	if dist < REEF_INNER or dist > REEF_OUTER then
		return 0
	end

	local angle = math.atan2(localX, localZ)

	--[[
		BASE PROFILE by zone. Note the asymmetry: the inner face ramps up over
		140 studs while the fore-reef drops over 285 but from a greater height
		and with a steeper curve. That asymmetry is what makes it read as a
		reef rather than as a symmetrical ridge.
	]]
	local base
	if dist < REEF_FLAT_START then
		-- Inner face: rises out of the lagoon onto the flat.
		base = REEF_FLAT_HEIGHT * smoothRamp(REEF_INNER, REEF_FLAT_START, dist)
	elseif dist < REEF_CREST then
		-- REEF FLAT: near-level plateau, easing up to the crest.
		local t = smoothRamp(REEF_FLAT_START, REEF_CREST, dist)
		base = REEF_FLAT_HEIGHT + (CREST_HEIGHT - REEF_FLAT_HEIGHT) * t
	else
		-- FORE-REEF: steep drop. ^1.7 makes it fall away fast near the crest
		-- and flatten out at the toe, which is the real slope shape.
		local t = math.clamp((dist - REEF_CREST) / (REEF_OUTER - REEF_CREST), 0, 1)
		base = CREST_HEIGHT * (1 - t) ^ 1.7
	end

	--[[
		SPUR AND GROOVE, on the fore-reef only. ~34 radial ribs; the grooves
		cut down to 55% of the local height, so they are real channels rather
		than surface ripples. Faded in past the crest so the flat stays flat.
	]]
	local spurStrength = smoothRamp(REEF_CREST - 40, REEF_CREST + 120, dist)
	local spur = math.sin(angle * 34 + fbm(localX, localZ, 0.004, 2, 3) * 2.5)
	-- Map -1..1 to 0.55..1 so grooves cut down and spurs stay at full height.
	local spurMask = 1 - spurStrength * 0.45 * (1 - (spur * 0.5 + 0.5))

	--[[
		PASSES. A few full-depth breaks all the way through the ring, so the
		lagoon connects to open water. Low frequency, sharply masked.
	]]
	local passNoise = fbm(localX, localZ, 0.0009, 2, 41)
	local passMask = smoothRamp(-0.42, -0.16, passNoise)

	-- Large-scale variation so some sections of reef are taller than others.
	local massif = 0.72 + 0.4 * (fbm(localX, localZ, 0.0011, 2, 17) * 0.5 + 0.5)

	-- BOMMIES: coral heads standing off the reef flat. Only where the base is
	-- already high, so they never appear out in the lagoon.
	local bommieField = fbm(localX, localZ, 0.011, 3, 61)
	local bommie = math.max(0, bommieField) ^ 2 * 46 * smoothRamp(60, 130, base)

	-- Fine rubble detail, so no surface is ever perfectly smooth.
	local rubble = fbm(localX, localZ, 0.05, 3, 83) * 5

	local h = (base * massif + bommie + rubble) * spurMask * passMask
	return math.max(0, h)
end

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
	-- (Kept subdued: this is the old small-clump coral used only in the lagoon
	-- dressing, not on the main reef.)
	PartUtils.CreatePart({
		name = "ReefGlow",
		size = Vector3.new(baseSize * 0.3, baseSize * 0.3, baseSize * 0.3),
		position = position + Vector3.new(0, baseSize * 1.3 + baseSize * 0.15, 0),
		material = Enum.Material.Sandstone,
		color = Color3.fromRGB(150, 140, 118),
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
--[[
	Shared fish detailing, so every species gets the same recognisable
	anatomy without duplicating the maths three times.

	`cframe` convention for all fish: local +X is FORWARD (the nose), local
	+Y is up, local +Z is the flank the stripes sit on.
]]
local FISH_DARK = Color3.fromRGB(28, 32, 40)

-- A pair of eyes set into the head, one per flank.
local function addFishEyes(model: Model, cframe: CFrame, size: number, forward: number, halfWidth: number)
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "Eye",
			size = Vector3.new(size * 0.14, size * 0.14, size * 0.14),
			cframe = cframe * CFrame.new(forward, size * 0.08, side * halfWidth),
			material = Enum.Material.SmoothPlastic,
			color = FISH_DARK,
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = model,
		})
	end
end

-- Vertical banding across the flanks - the single clearest "this is a
-- fish" cue after the silhouette itself.
local function addFishStripes(
	model: Model,
	cframe: CFrame,
	size: number,
	stripeColor: Color3,
	count: number,
	spacing: number,
	height: number,
	width: number
)
	for i = 1, count do
		local offset = (i - (count + 1) / 2) * spacing
		PartUtils.CreatePart({
			name = "Stripe" .. i,
			size = Vector3.new(size * 0.1, height, width),
			cframe = cframe * CFrame.new(offset, 0, 0),
			material = Enum.Material.SmoothPlastic,
			color = stripeColor,
			canCollide = false,
			parent = model,
		})
	end
end

local function buildReefFish(cframe: CFrame, size: number, color: Color3, parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local bodyLen = size * 1.15
	local bodyHeight = size * 1.2
	local bodyWidth = size * 0.45

	local body = PartUtils.CreatePart({
		name = "Body",
		size = Vector3.new(bodyLen, bodyHeight, bodyWidth),
		cframe = cframe,
		material = Enum.Material.SmoothPlastic,
		color = color,
		canCollide = false,
		parent = model,
	})
	-- Tapered snout, so the head end is obviously the front.
	PartUtils.CreatePart({
		name = "Head",
		size = Vector3.new(size * 0.42, bodyHeight * 0.62, bodyWidth * 0.78),
		cframe = cframe * CFrame.new(bodyLen * 0.52, -size * 0.04, 0),
		material = Enum.Material.SmoothPlastic,
		color = color,
		canCollide = false,
		parent = model,
	})
	-- Forked tail: two lobes rather than one flat wedge.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			className = "WedgePart",
			name = "TailLobe",
			size = Vector3.new(size * 0.14, size * 0.5, size * 0.5),
			cframe = cframe
				* CFrame.new(-bodyLen * 0.62, side * size * 0.24, 0)
				* CFrame.Angles(0, math.rad(-90), 0),
			material = Enum.Material.SmoothPlastic,
			color = color,
			canCollide = false,
			parent = model,
		})
	end
	-- Dorsal + pelvic fins.
	PartUtils.CreatePart({
		className = "WedgePart",
		name = "DorsalFin",
		size = Vector3.new(size * 0.1, size * 0.42, size * 0.6),
		cframe = cframe * CFrame.new(-size * 0.05, bodyHeight * 0.52, 0) * CFrame.Angles(0, math.rad(-90), 0),
		material = Enum.Material.SmoothPlastic,
		color = color,
		canCollide = false,
		parent = model,
	})
	PartUtils.CreatePart({
		className = "WedgePart",
		name = "PelvicFin",
		size = Vector3.new(size * 0.09, size * 0.3, size * 0.42),
		cframe = cframe
			* CFrame.new(-size * 0.02, -bodyHeight * 0.5, 0)
			* CFrame.Angles(math.pi, math.rad(-90), 0),
		material = Enum.Material.SmoothPlastic,
		color = color,
		canCollide = false,
		parent = model,
	})

	addFishStripes(model, cframe, size, FISH_DARK, 3, size * 0.34, bodyHeight * 0.94, bodyWidth * 1.04)
	addFishEyes(model, cframe, size, bodyLen * 0.52, bodyWidth * 0.42)

	model.PrimaryPart = body
	return model
end

local function buildRayFish(cframe: CFrame, size: number, color: Color3, parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local body = PartUtils.CreatePart({
		name = "Body",
		size = Vector3.new(size * 1.5, size * 0.3, size * 1.0),
		cframe = cframe,
		material = Enum.Material.SmoothPlastic,
		color = color,
		canCollide = false,
		parent = model,
	})
	-- Swept wings, tapering to a point outboard - the manta silhouette.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			className = "WedgePart",
			name = "Wing",
			size = Vector3.new(size * 1.3, size * 0.16, size * 0.95),
			cframe = cframe
				* CFrame.new(-size * 0.1, 0, side * size * 0.92)
				* CFrame.Angles(0, if side > 0 then 0 else math.pi, 0),
			material = Enum.Material.SmoothPlastic,
			color = color,
			canCollide = false,
			parent = model,
		})
	end
	-- Blunt cephalic head lobe.
	PartUtils.CreatePart({
		name = "Head",
		size = Vector3.new(size * 0.4, size * 0.26, size * 0.7),
		cframe = cframe * CFrame.new(size * 0.8, 0, 0),
		material = Enum.Material.SmoothPlastic,
		color = color,
		canCollide = false,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "TailWhip",
		size = Vector3.new(size * 1.3, size * 0.1, size * 0.1),
		cframe = cframe * CFrame.new(-size * 1.25, 0, 0),
		material = Enum.Material.SmoothPlastic,
		color = color,
		canCollide = false,
		parent = model,
	})

	-- Rays are patterned with spots along the back rather than bands.
	for i = 1, 4 do
		local along = (i - 2.5) * size * 0.3
		for _, side in ipairs({ -1, 1 }) do
			PartUtils.CreatePart({
				name = "Spot" .. i,
				size = Vector3.new(size * 0.2, size * 0.34, size * 0.2),
				cframe = cframe * CFrame.new(along, size * 0.05, side * size * 0.42),
				material = Enum.Material.SmoothPlastic,
				color = FISH_DARK,
				shape = Enum.PartType.Ball,
				canCollide = false,
				parent = model,
			})
		end
	end
	addFishEyes(model, cframe, size, size * 0.82, size * 0.26)

	model.PrimaryPart = body
	return model
end

local function buildPredatorFish(cframe: CFrame, size: number, color: Color3, parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local bodyLen = size * 1.9
	local bodyHeight = size * 0.62
	local bodyWidth = size * 0.46

	local body = PartUtils.CreatePart({
		name = "Body",
		size = Vector3.new(bodyLen, bodyHeight, bodyWidth),
		cframe = cframe,
		material = Enum.Material.SmoothPlastic,
		color = color,
		canCollide = false,
		parent = model,
	})
	-- Pointed snout.
	PartUtils.CreatePart({
		className = "WedgePart",
		name = "Snout",
		size = Vector3.new(bodyWidth * 0.9, bodyHeight * 0.8, size * 0.55),
		cframe = cframe * CFrame.new(bodyLen * 0.5, 0, 0) * CFrame.Angles(0, math.rad(90), math.rad(90)),
		material = Enum.Material.SmoothPlastic,
		color = color,
		canCollide = false,
		parent = model,
	})
	-- Tall dorsal fin - the shark read.
	PartUtils.CreatePart({
		className = "WedgePart",
		name = "DorsalFin",
		size = Vector3.new(size * 0.12, size * 0.62, size * 0.8),
		cframe = cframe * CFrame.new(size * 0.05, bodyHeight * 0.6, 0) * CFrame.Angles(0, math.rad(-90), 0),
		material = Enum.Material.SmoothPlastic,
		color = color,
		canCollide = false,
		parent = model,
	})
	-- Pectoral fins swept out from the flanks.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			className = "WedgePart",
			name = "PectoralFin",
			size = Vector3.new(size * 0.1, size * 0.42, size * 0.5),
			cframe = cframe
				* CFrame.new(size * 0.15, -bodyHeight * 0.22, side * bodyWidth * 0.55)
				* CFrame.Angles(math.rad(side * 60), math.rad(-90), 0),
			material = Enum.Material.SmoothPlastic,
			color = color,
			canCollide = false,
			parent = model,
		})
	end
	-- Forked caudal tail.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			className = "WedgePart",
			name = "TailLobe",
			size = Vector3.new(size * 0.12, size * 0.6, size * 0.55),
			cframe = cframe
				* CFrame.new(-bodyLen * 0.56, side * size * 0.26, 0)
				* CFrame.Angles(0, math.rad(-90), 0),
			material = Enum.Material.SmoothPlastic,
			color = color,
			canCollide = false,
			parent = model,
		})
	end

	-- Predators get a pale counter-shaded belly instead of bands.
	PartUtils.CreatePart({
		name = "Belly",
		size = Vector3.new(bodyLen * 0.86, bodyHeight * 0.34, bodyWidth * 1.02),
		cframe = cframe * CFrame.new(0, -bodyHeight * 0.34, 0),
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(198, 208, 218),
		canCollide = false,
		parent = model,
	})
	addFishEyes(model, cframe, size, bodyLen * 0.42, bodyWidth * 0.48)

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
	--[[
		RELOCATED TO THE REEF, AND OFF THE VIEW.

		Schools used to sit at radius 0.28-0.98 of USABLE_RADIUS and heights
		14-120 - i.e. directly over the plaza, at eye level, between the player
		and the central board. Dense schools there are clutter, not atmosphere.

		They now live in the reef band (REEF_INNER..REEF_OUTER) and sit ON the
		reef surface, which is where reef fish actually are. A small number are
		kept over the plaza but pushed HIGH - see buildOverheadLife - so there
		is life above you without anything crossing the sightline to the board.
	]]
	local schoolCount = 46
	for s = 1, schoolCount do
		--[[
			Search for a spot with real reef under it, rather than taking the
			first random point in the band. Roughly a third of the annulus is
			sand channel where reefHeight is ~0; a school landing there hangs in
			open water with nothing beneath it, which is exactly the "floating
			decoration" look this pass is meant to remove.

			Falls back to the last sample after 24 tries so a school is never
			silently dropped.
		]]
		local angle, radius, surface = 0, 0, 0
		for attempt = 1, 24 do
			angle = (s - 1) / schoolCount * math.pi * 2 + rng:NextNumber(-0.28, 0.28)
			radius = rng:NextNumber(REEF_INNER + 30, REEF_OUTER - 40)
			surface = reefHeight(math.sin(angle) * radius, math.cos(angle) * radius)
			if surface > 14 then
				break
			end
		end
		-- Hug the reef surface: close in for the small reef species, further
		-- off the bottom for the bigger ones.
		local height = surface + rng:NextNumber(6, 48)
		local center = Vector3.new(math.sin(angle) * radius, height, math.cos(angle) * radius)
		local schoolYaw = rng:NextNumber(0, 2 * math.pi)

		local speciesIndex = ((s - 1) % #FISH_BUILDERS) + 1
		local builder = FISH_BUILDERS[speciesIndex]
		local palette = speciesPalettes[speciesIndex]
		-- Predator schools (species 3) read better as smaller, sparser groups
		-- - a "school" of large sharks/tuna should be a handful, not a dozen.
		local fishCount = if speciesIndex == 3 then rng:NextInteger(3, 5) else rng:NextInteger(7, 13)
		-- Moderately larger so the new anatomy (fins, stripes, eyes) is
		-- actually legible from the ground rather than resolving to specks.
		local baseSize = if speciesIndex == 3 then rng:NextNumber(5, 7) else rng:NextNumber(2.8, 4.2)

		for f = 1, fishCount do
			-- Spread scales with the bigger fish so a school stays a school
			-- instead of the members overlapping into one mass.
			local spread = baseSize * 2.2
			local offset = Vector3.new(
				rng:NextNumber(-spread, spread),
				rng:NextNumber(-2.5, 2.5),
				rng:NextNumber(-spread, spread)
			)
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
--[[
	JELLYFISH.

	Added because the existing life was all FISH - three species that all
	read as the same silhouette from any distance. Jellyfish give the water
	column a second, completely different shape: a translucent glowing bell
	with trailing tentacles, drifting rather than swimming.

	They are also the only self-lit thing down here besides the light shafts,
	so they double as soft point lights in a very dark map.
]]
local function buildJellyfish(position: Vector3, size: number, tint: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	-- Bell: a translucent dome. Deliberately NOT Neon and with no PointLight:
	-- the emissive version glowed like a lantern, which is why the whole map
	-- read as cartoonish. Real jellyfish are near-transparent and catch
	-- ambient light rather than emitting it.
	local bell = PartUtils.CreatePart({
		name = name .. "Bell",
		shape = Enum.PartType.Ball,
		size = Vector3.new(size, size * 0.72, size),
		position = position,
		material = Enum.Material.Glass,
		color = tint,
		transparency = 0.65,
		canCollide = false,
		castShadow = false,
		parent = model,
	})

	-- Tentacles: thin tapering strands hanging from the bell rim.
	local strands = 6
	for t = 1, strands do
		local a = (2 * math.pi / strands) * t
		local rimX = math.sin(a) * size * 0.3
		local rimZ = math.cos(a) * size * 0.3
		local segments = 3
		for seg = 1, segments do
			local drop = size * 0.45 * seg
			PartUtils.CreatePart({
				name = ("%sTentacle%d_%d"):format(name, t, seg),
				size = Vector3.new(size * 0.09, size * 0.5, size * 0.09),
				-- Splay outward as they descend so they trail rather than hang
				-- straight like wires.
				position = position + Vector3.new(rimX * (1 + seg * 0.22), -drop, rimZ * (1 + seg * 0.22)),
				material = Enum.Material.Glass,
				color = tint,
				transparency = 0.72 + seg * 0.05,
				canCollide = false,
				castShadow = false,
				parent = model,
			})
		end
	end
end

local function buildJellyfishBloom(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Jellyfish"
	folder.Parent = parent

	local rng = Random.new(731904)
	local TINTS = {
		-- Pale, near-colourless: what jellyfish actually look like underwater.
		Color3.fromRGB(198, 206, 224),
		Color3.fromRGB(212, 200, 214),
		Color3.fromRGB(190, 208, 214),
	}

	-- Moved out to the reef band with the fish, and lifted well above the
	-- reef surface - jellyfish drift in open water above the structure.
	for i = 1, 60 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(REEF_INNER, REEF_OUTER - 20)
		local surface = reefHeight(math.sin(angle) * radius, math.cos(angle) * radius)
		local height = surface + rng:NextNumber(30, 140)
		buildJellyfish(
			Vector3.new(math.sin(angle) * radius, height, math.cos(angle) * radius),
			rng:NextNumber(3.5, 9),
			TINTS[rng:NextInteger(1, #TINTS)],
			folder,
			"Jelly" .. i
		)
	end
end

--[[
	KELP FOREST.

	Tall strands rising from the seabed, leaning slightly and tapering as they
	rise. These matter for a reason the fish do not: they are ROOTED. A map
	where everything floats has no sense of a floor, and kelp visually ties
	the water column to the seabed.

	Placed clear of the plaza and of every building entrance, using the same
	clearance rule the Ice Age sheet ice uses.
]]
local function buildKelpForest(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "KelpForest"
	folder.Parent = parent

	local rng = Random.new(264188)
	local KELP_DARK = Color3.fromRGB(38, 82, 52)
	local KELP_LIGHT = Color3.fromRGB(64, 122, 70)

	local placed, attempts = 0, 0
	while placed < 46 and attempts < 500 do
		attempts += 1
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(46, MapConfig.USABLE_RADIUS * 0.96)
		local base = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)

		local tooClose = false
		for _, def in ipairs(LobbyConfig.BUILDINGS) do
			if (Vector3.new(def.position.X, 0, def.position.Z) - base).Magnitude < 36 then
				tooClose = true
				break
			end
		end

		if not tooClose then
			placed += 1
			local height = rng:NextNumber(22, 52)
			local segments = math.max(5, math.floor(height / 6))
			-- A consistent lean per strand, so a stand of kelp all sways the
			-- same way as though one current runs through it.
			local leanDir = rng:NextNumber(0, 2 * math.pi)
			local lean = rng:NextNumber(0.05, 0.16)
			local tint = KELP_DARK:Lerp(KELP_LIGHT, rng:NextNumber())

			for seg = 1, segments do
				local t = seg / segments
				local segHeight = height / segments
				-- Lean grows with height, so the strand curves instead of tilting
				-- as a rigid pole.
				local drift = lean * height * t * t
				PartUtils.CreatePart({
					name = ("Kelp%dSeg%d"):format(placed, seg),
					size = Vector3.new(1.5 * (1.15 - t * 0.55), segHeight * 1.1, 0.5),
					cframe = CFrame.new(
						base
							+ Vector3.new(
								math.sin(leanDir) * drift,
								segHeight * (seg - 0.5),
								math.cos(leanDir) * drift
							)
					) * CFrame.Angles(0, leanDir, 0) * CFrame.Angles(lean * t * 2, 0, 0),
					material = Enum.Material.Grass,
					color = tint,
					transparency = 0.15,
					canCollide = false,
					castShadow = false,
					parent = folder,
				})
			end
		end
	end
end

--[[
	AMBIENT BUBBLES.

	Distinct from buildBubbleStreams, which makes columns of bubbles rising
	from fixed seabed vents. This fills the whole water column with a fine
	drift of bubbles so that the AIR ITSELF reads as water from anywhere on
	the map, which is what makes the place feel submerged rather than like a
	dark room with fish in it.

	Three height layers for the same reason the Lava ashfall uses them: a
	single emitter plane vanishes the moment the camera rises above it.

	ParticleEmitters on real anchored Parts, so this renders in the Edit
	viewport as well as in Play.
]]
local function buildAmbientBubbles(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "AmbientBubbles"
	folder.Parent = parent

	local rng = Random.new(486201)
	local span = MapConfig.USABLE_RADIUS * 0.7
	local spots = {
		Vector3.new(0, 0, 0),
		Vector3.new(-span, 0, -span),
		Vector3.new(span, 0, span),
		Vector3.new(-span, 0, span),
		Vector3.new(span, 0, -span),
	}

	local index = 0
	for _, height in ipairs({ 20, 70, 130 }) do
		for _, spot in ipairs(spots) do
			index += 1
			local anchor = PartUtils.CreatePart({
				name = ("AmbientBubbleEmitter%d"):format(index),
				size = Vector3.new(span * 1.6, 1, span * 1.6),
				position = spot + Vector3.new(0, height, 0),
				transparency = 1,
				canCollide = false,
				castShadow = false,
				parent = folder,
			})

			local bubbles = Instance.new("ParticleEmitter")
			bubbles.Name = "Bubbles"
			bubbles.Shape = Enum.ParticleEmitterShape.Box
			bubbles.EmissionDirection = Enum.NormalId.Top
			bubbles.Color = ColorSequence.new(Color3.fromRGB(210, 240, 255))
			bubbles.LightEmission = 0.65
			bubbles.LightInfluence = 0
			bubbles.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.18),
				NumberSequenceKeypoint.new(1, 0.45),
			})
			bubbles.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.45),
				NumberSequenceKeypoint.new(0.85, 0.55),
				NumberSequenceKeypoint.new(1, 1),
			})
			bubbles.Lifetime = NumberRange.new(7, 13)
			bubbles.Rate = 20
			bubbles.Speed = NumberRange.new(2, 5)
			bubbles.SpreadAngle = Vector2.new(22, 22)
			-- Positive Y: bubbles rise. Slight lateral drift so they wander in
			-- the current rather than tracking straight up.
			bubbles.Acceleration = Vector3.new(0.8, 3.2, -0.6)
			bubbles.Parent = anchor
		end
	end
end

--[[
	TERRAIN REEF WALL.

	A huge coral massif ringing the map - the underwater counterpart to the
	Ice Age range, and built the same way and for the same reason.

	WHY TERRAIN AND NOT PARTS. The existing buildCoralReefs makes 10 small
	part-built coral clumps, which is right for detail dressing but cannot
	scale to a reef WALL: rings of slabs terrace vertically and facet
	horizontally, so a large one always reads as stacked geometry. Terrain is
	a smoothed voxel field, so the surface is continuous in every direction.

	REEF, NOT MOUNTAIN. The shape maths differ from the Ice Age range in two
	deliberate ways:
	  - A LOWER ridge exponent, so the mass is lumpier and more rounded -
	    reefs are accreted coral heads and bommies, not eroded rock with
	    knife-edge aretes.
	  - A NOTCHED crest: a second noise band cuts channels through the ring,
	    so it reads as a reef with swim-throughs and lagoons rather than a
	    solid dam.

	Materials are sand at the foot, then limestone and sandstone for the reef
	body - the actual carbonate rock a reef is built from. Live coral colour
	comes from the part-built coral gardens scattered on top (see
	buildCoralForest), because Terrain has no coral material and a flat
	tinted mass would look like painted rock.

	WORLD SPACE, ON PURPOSE. Terrain is not a BasePart, so LobbyBuilder's
	applyMapTransform cannot move it. This takes the FINAL world origin and is
	called after that transform.

	The shape maths (REEF_* constants, reefNoise, reefHeight) live near the top
	of this file - they have to be declared above the builders that use them.
]]

--[[
	Writes the reef into Terrain around `worldOrigin`.

	Tiled because Terrain:WriteVoxels is capped well below the full region.
	Height and slope are computed once per column rather than per voxel - the
	noise does not vary with Y, and slope is needed for material choice.
]]
function UnderTheSeaEnvironment.BuildTerrainReef(worldOrigin: Vector3)
	local Terrain = workspace.Terrain

	local TILE = 128
	local FLOOR_Y = -120
	-- CREST_HEIGHT plus headroom for bommies (up to ~46) and rubble.
	local TOP_Y = CREST_HEIGHT + 110

	local clearRegion = Region3.new(
		worldOrigin + Vector3.new(-REEF_OUTER - TILE, FLOOR_Y - TILE, -REEF_OUTER - TILE),
		worldOrigin + Vector3.new(REEF_OUTER + TILE, TOP_Y + TILE, REEF_OUTER + TILE)
	):ExpandToGrid(TERRAIN_RES)
	Terrain:FillRegion(clearRegion, TERRAIN_RES, Enum.Material.Air)

	local voxelsY = math.floor((TOP_Y - FLOOR_Y) / TERRAIN_RES)
	local tilesWritten, voxelsWritten = 0, 0

	for tileX = -REEF_OUTER, REEF_OUTER - 1, TILE do
		for tileZ = -REEF_OUTER, REEF_OUTER - 1, TILE do
			local cx, cz = tileX + TILE / 2, tileZ + TILE / 2
			local centreDist = math.sqrt(cx * cx + cz * cz)
			local halfDiag = TILE * 0.7072
			if centreDist + halfDiag >= REEF_INNER and centreDist - halfDiag <= REEF_OUTER then
				-- Build the region first; ExpandToGrid snaps outward and the map
				-- origin is not grid-aligned, so array sizes must come from the
				-- expanded region rather than from TILE/RES.
				local region = Region3.new(
					worldOrigin + Vector3.new(tileX, FLOOR_Y, tileZ),
					worldOrigin + Vector3.new(tileX + TILE, FLOOR_Y + voxelsY * TERRAIN_RES, tileZ + TILE)
				):ExpandToGrid(TERRAIN_RES)

				local regionSize = region.Size
				local sizeX = math.floor(regionSize.X / TERRAIN_RES + 0.5)
				local sizeY = math.floor(regionSize.Y / TERRAIN_RES + 0.5)
				local sizeZ = math.floor(regionSize.Z / TERRAIN_RES + 0.5)
				local corner = region.CFrame.Position - regionSize / 2

				-- Per-column height and slope, computed once.
				local colHeight, colSlope = {}, {}
				for ix = 1, sizeX do
					colHeight[ix], colSlope[ix] = {}, {}
					local lx = corner.X + (ix - 0.5) * TERRAIN_RES - worldOrigin.X
					for iz = 1, sizeZ do
						local lz = corner.Z + (iz - 0.5) * TERRAIN_RES - worldOrigin.Z
						colHeight[ix][iz] = reefHeight(lx, lz)
						local dx = reefHeight(lx + TERRAIN_RES, lz) - reefHeight(lx - TERRAIN_RES, lz)
						local dz = reefHeight(lx, lz + TERRAIN_RES) - reefHeight(lx, lz - TERRAIN_RES)
						colSlope[ix][iz] = math.sqrt(dx * dx + dz * dz) / (2 * TERRAIN_RES)
					end
				end

				local materials, occupancies = {}, {}
				for ix = 1, sizeX do
					materials[ix], occupancies[ix] = {}, {}
					local lx = corner.X + (ix - 0.5) * TERRAIN_RES - worldOrigin.X
					for iy = 1, sizeY do
						materials[ix][iy], occupancies[ix][iy] = {}, {}
						local voxelBottom = corner.Y + (iy - 1) * TERRAIN_RES - worldOrigin.Y
						for iz = 1, sizeZ do
							local lz = corner.Z + (iz - 0.5) * TERRAIN_RES - worldOrigin.Z
							local height = colHeight[ix][iz]
							local fill = math.clamp((height - voxelBottom) / TERRAIN_RES, 0, 1)

							local material = Enum.Material.Air
							if fill > 0 then
								local slope = colSlope[ix][iz]
								--[[
									MATERIALS BY POSITION AND SLOPE.

									The previous pass was Sand at the bottom and
									Sandstone almost everywhere else, which is why the
									whole structure came out pale beige and read as
									dunes. Real reef rock is DARK - grey-brown
									limestone stained by algae - with clean carbonate
									sand only in the grooves and at the toe.

									Rock and Slate now carry the reef body. Sand is
									restricted to genuinely flat low ground, which is
									exactly where it collects.
								]]
								local grain = math.noise(lx * 0.03, lz * 0.03, 7)
								if voxelBottom < 8 and slope < 0.25 then
									-- Sand: flat, low ground only - grooves and toe.
									material = Enum.Material.Sand
								elseif slope > 0.75 then
									-- Near-vertical reef wall: bare dark rock.
									material = Enum.Material.Slate
								elseif grain > 0.18 then
									-- Patches of paler dead carbonate.
									material = Enum.Material.Limestone
								else
									-- The bulk: algae-stained reef rock.
									material = Enum.Material.Rock
								end
								voxelsWritten += 1
							end

							materials[ix][iy][iz] = material
							occupancies[ix][iy][iz] = fill
						end
					end
				end

				Terrain:WriteVoxels(region, TERRAIN_RES, materials, occupancies)
				tilesWritten += 1
			end
		end
	end

	return tilesWritten, voxelsWritten
end

-- Exposed so the decoration and marine-life passes can sit ON the reef
-- rather than guessing where its surface is.
function UnderTheSeaEnvironment.GetReefHeight(localX: number, localZ: number): number
	return reefHeight(localX, localZ)
end

function UnderTheSeaEnvironment.GetReefBand(): (number, number, number)
	return REEF_INNER, REEF_CREST, REEF_OUTER
end

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

--[[
	SEABED GROUND TREATMENT - the soft, lumpy sand floor of the ocean.

	Kept in this map's own environment module (like Lava's potholes and Ice
	Age's snow piles) so each map's terrain can be tuned independently.

	Two layers: a broad wash of very flat sand patches that recolours the
	floor as seabed, then rounded sand BLOBS - overlapping low domes in
	clusters, the way sand actually heaps on an ocean floor rather than
	forming crisp geometric shapes. Everything is well under knee height
	and non-collidable, so it never interferes with walking.
]]
local function buildSeabedPattern(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "SeabedPattern"
	folder.Parent = parent

	local rng = Random.new(624489)
	local SAND = Color3.fromRGB(222, 208, 170)

	-- Flat sand wash across the walkable area.
	for i = 1, 80 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = math.sqrt(rng:NextNumber(0, 1)) * MapConfig.USABLE_RADIUS * 0.99
		local center = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		PartUtils.CreateDisc({
			name = "SandWash" .. i,
			diameter = rng:NextNumber(16, 34),
			thickness = rng:NextNumber(0.14, 0.34),
			position = center + Vector3.new(0, 0.12, 0),
			material = Enum.Material.Sand,
			color = Color3.new(
				math.clamp(SAND.R + rng:NextInteger(-10, 8) / 255, 0, 1),
				math.clamp(SAND.G + rng:NextInteger(-8, 8) / 255, 0, 1),
				math.clamp(SAND.B + rng:NextInteger(-8, 10) / 255, 0, 1)
			),
			canCollide = false,
			parent = folder,
		})
	end

	-- Rounded sand blobs, in overlapping clusters.
	for i = 1, 22 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(MapConfig.USABLE_RADIUS * 0.12, MapConfig.USABLE_RADIUS * 0.95)
		local center = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		local spread = rng:NextNumber(4, 10)
		for b = 1, rng:NextInteger(3, 6) do
			local blobAngle = rng:NextNumber(0, 2 * math.pi)
			local blobDist = rng:NextNumber(0, spread * 0.55)
			local blobSize = rng:NextNumber(5, 12) * (1 - blobDist / (spread * 1.5))
			-- Flattened spheres: wide and shallow, like settled sand.
			local height = math.min(2.2, blobSize * rng:NextNumber(0.15, 0.26))
			PartUtils.CreatePart({
				name = ("SandBlob%d_%d"):format(i, b),
				size = Vector3.new(blobSize, height, blobSize * rng:NextNumber(0.8, 1.2)),
				position = center
					+ Vector3.new(math.sin(blobAngle) * blobDist, height * 0.2, math.cos(blobAngle) * blobDist),
				material = Enum.Material.Sand,
				color = Color3.new(
					math.clamp(SAND.R + rng:NextInteger(-8, 10) / 255, 0, 1),
					math.clamp(SAND.G + rng:NextInteger(-8, 8) / 255, 0, 1),
					math.clamp(SAND.B + rng:NextInteger(-6, 10) / 255, 0, 1)
				),
				shape = Enum.PartType.Ball,
				canCollide = false,
				parent = folder,
			})
		end
	end

	-- Scattered shell/pebble grit for close-up texture.
	for i = 1, 26 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(MapConfig.USABLE_RADIUS * 0.1, MapConfig.USABLE_RADIUS * 0.95)
		local center = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		local grit = rng:NextNumber(0.6, 1.5)
		PartUtils.CreatePart({
			name = "SeabedPebble" .. i,
			size = Vector3.new(grit, grit * 0.45, grit * rng:NextNumber(0.8, 1.2)),
			cframe = CFrame.new(center + Vector3.new(0, grit * 0.2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			material = Enum.Material.Slate,
			color = Color3.fromRGB(186, 178, 158),
			canCollide = false,
			parent = folder,
		})
	end
end

--[[
	OVERHEAD LIFE.

	A deliberately SMALL number of large animals high above the plaza.

	The point is to have something alive overhead without putting anything in
	the way: everything here sits at least 150 studs up, far above the central
	board and the building signs, so it is visible when you look up and never
	crosses the sightline when you look ahead. That is the whole reason the
	dense schools moved out to the reef.
]]
local function buildOverheadLife(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "OverheadLife"
	folder.Parent = parent

	local rng = Random.new(447120)

	-- A few big rays cruising over the plaza - the classic "look up" moment.
	for i = 1, 7 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(0, MapConfig.USABLE_RADIUS * 0.8)
		local height = rng:NextNumber(165, 235)
		buildRayFish(
			CFrame.new(Vector3.new(math.sin(angle) * radius, height, math.cos(angle) * radius))
				* CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0),
			rng:NextNumber(9, 15),
			Color3.fromRGB(120, 140, 170),
			folder,
			"OverheadRay" .. i
		)
	end

	-- And a couple of large predators higher still, as silhouettes.
	for i = 1, 4 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(0, MapConfig.USABLE_RADIUS * 0.9)
		local height = rng:NextNumber(215, 275)
		buildPredatorFish(
			CFrame.new(Vector3.new(math.sin(angle) * radius, height, math.cos(angle) * radius))
				* CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0),
			rng:NextNumber(10, 16),
			Color3.fromRGB(80, 98, 118),
			folder,
			"OverheadPredator" .. i
		)
	end
end

--[[
	CORAL SPECIES.

	The reef previously had one coral shape - a clump of 4-6 spheres - which
	at any distance reads as a pile of bubbles. A real reef's character comes
	from the VARIETY of growth forms sharing one surface: domes, branches,
	plates, fans and columns all competing for light.

	Six builders below, each a genuinely different silhouette. They all take
	the same (position, size, colour, parent, name) signature so the scatter
	pass can pick between them at random.

	Every piece is CanCollide = false and CastShadow = false. There are
	thousands of them out on the reef where no player can stand, so collision
	would only cost physics memory and shadows would cost frames.
]]

--[[
	CORAL PALETTE - NATURAL, NOT NEON.

	The previous palette was seven fully-saturated primaries (255,118,136 /
	92,214,198 / 255,210,92 ...) which is why the reef looked like plastic
	toys. Live coral is far more muted than photographs suggest: mostly
	olive-browns, dusty ochres, muted mauves and pale creams, with only
	occasional genuinely bright colonies.

	Everything below is desaturated and darkened accordingly. The two brighter
	entries are last and are drawn rarely (see ACCENT_CHANCE in
	buildCoralForest) so they read as highlights rather than as the norm.
]]
local CORAL_PALETTE = {
	Color3.fromRGB(150, 116, 86), -- olive-brown, the commonest reef tone
	Color3.fromRGB(122, 108, 78), -- dull khaki
	Color3.fromRGB(168, 138, 108), -- pale sandy ochre
	Color3.fromRGB(134, 112, 122), -- dusty mauve
	Color3.fromRGB(108, 124, 106), -- grey-green
	Color3.fromRGB(176, 152, 124), -- bleached cream
	Color3.fromRGB(96, 104, 116), -- slate blue-grey
}

-- Drawn rarely, as highlights only.
local CORAL_ACCENTS = {
	Color3.fromRGB(186, 118, 108), -- muted coral red
	Color3.fromRGB(150, 126, 168), -- soft violet
	Color3.fromRGB(196, 172, 112), -- mustard
}

-- Reef skeleton is limestone. Sandstone/Rock read as porous stone; nothing
-- here is ever Neon, which was the single biggest cause of the plastic look.
local CORAL_MATERIALS = { Enum.Material.Sandstone, Enum.Material.Rock, Enum.Material.Limestone }

-- BRAIN CORAL: a low ridged dome. Built from stacked discs of shrinking
-- diameter with a wobble, so the surface is furrowed rather than smooth.
local function buildBrainCoral(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local rng = Random.new(math.floor(position.X * 71 + position.Z * 131))

	local tiers = 5
	for t = 0, tiers do
		local f = t / tiers
		local diameter = size * (1 - f * f * 0.85)
		PartUtils.CreateDisc({
			name = ("%sDome%d"):format(name, t),
			diameter = diameter,
			thickness = size * 0.17,
			position = position + Vector3.new(
				rng:NextNumber(-size * 0.03, size * 0.03),
				size * 0.15 * t,
				rng:NextNumber(-size * 0.03, size * 0.03)
			),
			material = Enum.Material.Sandstone,
			color = colour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
end

-- STAGHORN CORAL: antler-like branching. The recursive fork is what makes it
-- read as coral rather than as a bush.
local function buildStaghornCoral(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local rng = Random.new(math.floor(position.X * 53 + position.Z * 97))
	local counter = 0

	local function branch(from: Vector3, direction: Vector3, length: number, thickness: number, depth: number)
		if depth > 3 or length < size * 0.12 then
			return
		end
		counter += 1
		local to = from + direction * length
		local mid = (from + to) / 2
		PartUtils.CreatePart({
			name = ("%sBranch%d"):format(name, counter),
			size = Vector3.new(thickness, thickness, length),
			cframe = CFrame.lookAt(mid, to),
			material = Enum.Material.Sandstone,
			color = colour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
		-- Two to three forks, each tilted off the parent and biased upward so
		-- the colony grows toward the light the way real coral does.
		for _ = 1, rng:NextInteger(2, 3) do
			local spread = Vector3.new(rng:NextNumber(-0.7, 0.7), rng:NextNumber(0.25, 0.9), rng:NextNumber(-0.7, 0.7))
			branch(to, (direction + spread).Unit, length * rng:NextNumber(0.55, 0.75), thickness * 0.7, depth + 1)
		end
	end

	branch(position, Vector3.new(0, 1, 0), size * 0.5, size * 0.16, 0)
end

-- TABLE CORAL: a broad flat plate on a short stalk - the strongest
-- horizontal shape on the reef, and the best contrast to the branching forms.
local function buildTableCoral(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	PartUtils.CreatePart({
		name = name .. "Stalk",
		size = Vector3.new(size * 0.16, size * 0.45, size * 0.16),
		position = position + Vector3.new(0, size * 0.22, 0),
		material = Enum.Material.Sandstone,
		color = colour,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	-- Two offset plates give the tabletop a layered, uneven edge.
	for i = 0, 1 do
		PartUtils.CreateDisc({
			name = ("%sPlate%d"):format(name, i),
			diameter = size * (1 - i * 0.28),
			thickness = size * 0.07,
			position = position + Vector3.new(size * 0.04 * i, size * (0.45 + i * 0.09), 0),
			material = Enum.Material.Sandstone,
			color = colour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
end

-- SEA FAN: a thin upright frond. Flat, so it catches light very differently
-- from the solid forms and gives the reef its lacy look.
local function buildSeaFan(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local rng = Random.new(math.floor(position.X * 41 + position.Z * 173))
	local facing = rng:NextNumber(0, math.pi * 2)

	for i = 1, 4 do
		local f = i / 4
		PartUtils.CreatePart({
			name = ("%sFrond%d"):format(name, i),
			-- Widening as it rises, like a fan opening.
			size = Vector3.new(size * (0.35 + f * 0.7), size * 0.34, size * 0.06),
			cframe = CFrame.new(position + Vector3.new(0, size * 0.3 * i, 0))
				* CFrame.Angles(0, facing, 0)
				* CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.12, 0.12)),
			material = Enum.Material.Fabric,
			color = colour,
			transparency = 0.18,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
end

-- PILLAR CORAL: vertical columns of differing height, like organ pipes.
local function buildPillarCoral(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local rng = Random.new(math.floor(position.X * 89 + position.Z * 59))

	for i = 1, rng:NextInteger(3, 6) do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0, size * 0.3)
		local h = size * rng:NextNumber(0.6, 1.5)
		PartUtils.CreatePart({
			name = ("%sPillar%d"):format(name, i),
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(h, size * 0.22, size * 0.22),
			cframe = CFrame.new(position + Vector3.new(math.sin(a) * r, h / 2, math.cos(a) * r))
				* CFrame.Angles(0, 0, math.rad(90))
				* CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), 0),
			material = Enum.Material.Sandstone,
			color = colour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
end

-- BARREL SPONGE: a hollow open-topped drum. The dark inner mouth is the
-- detail that sells it.
local function buildBarrelSponge(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	PartUtils.CreatePart({
		name = name .. "Body",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(size, size * 0.8, size * 0.8),
		cframe = CFrame.new(position + Vector3.new(0, size * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		material = Enum.Material.Sandstone,
		color = colour,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	PartUtils.CreateDisc({
		name = name .. "Mouth",
		diameter = size * 0.55,
		thickness = size * 0.12,
		position = position + Vector3.new(0, size * 0.96, 0),
		material = Enum.Material.Slate,
		color = Color3.fromRGB(26, 34, 40),
		canCollide = false,
		castShadow = false,
		parent = model,
	})
end

-- ANEMONE: a soft-bodied column with waving tentacles. No longer emissive -
-- the glowing neon version was the most obviously fake thing on the reef.
local function buildAnemone(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local rng = Random.new(math.floor(position.X * 149 + position.Z * 31))

	-- Squat column base.
	PartUtils.CreatePart({
		name = name .. "Column",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(size * 0.4, size * 0.5, size * 0.5),
		cframe = CFrame.new(position + Vector3.new(0, size * 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		material = Enum.Material.Sandstone,
		color = colour,
		canCollide = false,
		castShadow = false,
		parent = model,
	})

	-- Tentacle crown: many short soft strands, splayed outward.
	for i = 1, 14 do
		local a = (2 * math.pi / 14) * i + rng:NextNumber(-0.15, 0.15)
		local lean = rng:NextNumber(0.5, 0.95)
		PartUtils.CreatePart({
			name = ("%sTentacle%d"):format(name, i),
			size = Vector3.new(size * 0.07, size * 0.42, size * 0.07),
			cframe = CFrame.new(position + Vector3.new(math.sin(a) * size * 0.22, size * 0.5, math.cos(a) * size * 0.22))
				* CFrame.Angles(math.sin(a) * lean, 0, math.cos(a) * lean),
			material = Enum.Material.Sandstone,
			color = colour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
end

local CORAL_BUILDERS = {
	buildBrainCoral,
	buildStaghornCoral,
	buildTableCoral,
	buildSeaFan,
	buildPillarCoral,
	buildBarrelSponge,
	buildAnemone,
}

--[[
	CORAL FOREST.

	Covers the terrain reef in dense, varied, colourful coral. This is what
	turns the substrate from "beige underwater dunes" into a reef.

	The terrain underneath is deliberately plain carbonate rock - sand,
	limestone, sandstone - because that is what a reef actually grows ON.
	All the colour and nearly all the detail lives here, in parts.

	Placement samples reefHeight, so every colony sits on the surface wherever
	the terrain happens to be, and anything landing in a sand channel is
	skipped so the passes stay open. Colonies cluster: a seed point spawns a
	handful of neighbours, because coral grows in stands rather than scattered
	evenly like a lawn.
]]
local function buildCoralForest(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "CoralForest"
	folder.Parent = parent

	local rng = Random.new(605512)
	local colonies, attempts = 0, 0

	--[[
		DENSITY. 900 colonies looked sparse: the reef annulus is ~650 studs
		wide and 4,000+ studs around at the crest, so 900 scattered colonies
		average one every few thousand square studs - visible as isolated
		clumps rather than as reef cover.

		2,600 at a larger size range is what makes the surface read as
		continuous coral. Every piece is non-collidable and shadowless, and it
		sits out where no player stands, so the cost is draw calls only.
	]]
	local TARGET = 2600

	while colonies < TARGET and attempts < 40000 do
		attempts += 1
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(REEF_INNER + 10, REEF_OUTER - 20)
		local lx, lz = math.sin(angle) * radius, math.cos(angle) * radius
		local surface = reefHeight(lx, lz)

		if surface > 10 then
			-- A stand of 3-7 colonies around this seed point.
			local standSize = rng:NextInteger(4, 9)
			local standColour = CORAL_PALETTE[rng:NextInteger(1, #CORAL_PALETTE)]
			for _ = 1, standSize do
				if colonies >= TARGET then
					break
				end
				local ox = lx + rng:NextNumber(-26, 26)
				local oz = lz + rng:NextNumber(-26, 26)
				local oSurface = reefHeight(ox, oz)
				if oSurface > 8 then
					colonies += 1
					local builder = CORAL_BUILDERS[rng:NextInteger(1, #CORAL_BUILDERS)]
					-- Most of a stand shares a colour; a small minority are drawn
					-- from the bright accents so they read as highlights on a
					-- mostly muted reef rather than as the default.
					local ACCENT_CHANCE = 0.08
					local colour
					if rng:NextNumber() < ACCENT_CHANCE then
						colour = CORAL_ACCENTS[rng:NextInteger(1, #CORAL_ACCENTS)]
					elseif rng:NextNumber() < 0.75 then
						colour = standColour
					else
						colour = CORAL_PALETTE[rng:NextInteger(1, #CORAL_PALETTE)]
					end
					-- Per-colony tonal drift, so even same-coloured neighbours are
					-- not literally identical.
					local drift = rng:NextNumber(-0.05, 0.05)
					colour = Color3.new(
						math.clamp(colour.R + drift, 0, 1),
						math.clamp(colour.G + drift * 0.9, 0, 1),
						math.clamp(colour.B + drift * 0.8, 0, 1)
					)
					builder(
						Vector3.new(ox, oSurface - 1, oz),
						rng:NextNumber(9, 30),
						colour,
						folder,
						"Coral" .. colonies
					)
				end
			end
		end
	end
end

--[[
	SUNKEN SUBMARINE.

	A wreck half-buried in the reef: hull, conning tower, dive planes, screw,
	and a torn-open break amidships. Listing to one side and pitched down at
	the bow, because a wreck sitting perfectly level reads as a parked vehicle
	rather than as something that sank.

	Coral is grown over the hull afterwards - the detail that makes it look
	like it has been down here for decades rather than dropped in yesterday.

	Placed by searching the reef for a spot with enough mass to sit on, so it
	never ends up floating over a sand channel.
]]
local function buildSunkenSubmarine(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "SunkenSubmarine"
	folder.Parent = parent

	local rng = Random.new(880413)

	-- Find a solid perch on the reef.
	local bestX, bestZ, bestSurface = 0, 0, -1
	for _ = 1, 400 do
		local a = rng:NextNumber(0, 2 * math.pi)
		local r = rng:NextNumber(REEF_INNER + 60, REEF_CREST + 80)
		local x, z = math.sin(a) * r, math.cos(a) * r
		local s = reefHeight(x, z)
		if s > bestSurface then
			bestX, bestZ, bestSurface = x, z, s
		end
	end

	local HULL_GREY = Color3.fromRGB(78, 88, 92)
	local RUST = Color3.fromRGB(112, 74, 52)
	local DARK = Color3.fromRGB(34, 40, 44)

	local origin = Vector3.new(bestX, bestSurface + 11 * 0.75, bestZ)
	-- Lifted by 0.75 of the hull radius (11). This was bestSurface + 3, which
	-- buried the wreck: with an 11-stud radius, a 3-stud lift left almost the
	-- whole boat inside the terrain and only the torn plates showing. At 0.75r
	-- the lower quarter stays sunk - half-buried, as a wreck should be - with
	-- the conning tower, dive planes and screw all proud of the reef.
	local heading = rng:NextNumber(0, math.pi * 2)
	-- Listing to port and nose-down: the pose of something that sank.
	local pose = CFrame.new(origin) * CFrame.Angles(0, heading, 0) * CFrame.Angles(math.rad(-12), 0, math.rad(19))

	local LENGTH = 110
	local RADIUS = 11

	-- Hull, in two sections with a gap where it has broken its back.
	local sections = {
		{ offset = -LENGTH * 0.28, length = LENGTH * 0.42 },
		{ offset = LENGTH * 0.30, length = LENGTH * 0.38 },
	}
	for i, sec in ipairs(sections) do
		PartUtils.CreatePart({
			name = ("SubHull%d"):format(i),
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(sec.length, RADIUS * 2, RADIUS * 2),
			cframe = pose * CFrame.new(0, 0, sec.offset) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(90)),
			material = Enum.Material.CorrodedMetal,
			color = if i == 1 then HULL_GREY else RUST,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
	end

	-- Torn plating around the break.
	for i = 1, 9 do
		local a = rng:NextNumber(0, math.pi * 2)
		PartUtils.CreatePart({
			name = ("SubTornPlate%d"):format(i),
			size = Vector3.new(rng:NextNumber(3, 8), rng:NextNumber(3, 9), 0.7),
			cframe = pose
				* CFrame.new(math.sin(a) * RADIUS * 0.9, math.cos(a) * RADIUS * 0.9, rng:NextNumber(-6, 8))
				* CFrame.Angles(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)),
			material = Enum.Material.CorrodedMetal,
			color = RUST,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
	end

	-- Nose cone.
	PartUtils.CreatePart({
		name = "SubBow",
		shape = Enum.PartType.Ball,
		size = Vector3.new(RADIUS * 1.9, RADIUS * 1.9, RADIUS * 2.6),
		cframe = pose * CFrame.new(0, 0, -LENGTH * 0.5),
		material = Enum.Material.CorrodedMetal,
		color = HULL_GREY,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})

	-- Conning tower with a periscope.
	PartUtils.CreatePart({
		name = "SubConningTower",
		size = Vector3.new(9, 15, 22),
		cframe = pose * CFrame.new(0, RADIUS * 0.85, -LENGTH * 0.05),
		material = Enum.Material.CorrodedMetal,
		color = HULL_GREY,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})
	PartUtils.CreatePart({
		name = "SubPeriscope",
		size = Vector3.new(1.2, 12, 1.2),
		cframe = pose * CFrame.new(0, RADIUS * 0.85 + 13, -LENGTH * 0.02),
		material = Enum.Material.CorrodedMetal,
		color = DARK,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})

	-- Dive planes either side of the tower.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "SubDivePlane",
			size = Vector3.new(16, 1.1, 6),
			cframe = pose * CFrame.new(side * 12, RADIUS * 0.4, -LENGTH * 0.05) * CFrame.Angles(0, 0, math.rad(side * 6)),
			material = Enum.Material.CorrodedMetal,
			color = HULL_GREY,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
	end

	-- Stern fins and screw.
	for i = 1, 4 do
		local a = (math.pi / 2) * i
		PartUtils.CreatePart({
			name = ("SubSternFin%d"):format(i),
			size = Vector3.new(1.1, 15, 8),
			cframe = pose * CFrame.new(0, 0, LENGTH * 0.5) * CFrame.Angles(0, 0, a),
			material = Enum.Material.CorrodedMetal,
			color = RUST,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
	end
	for i = 1, 5 do
		local a = (2 * math.pi / 5) * i
		PartUtils.CreatePart({
			name = ("SubBlade%d"):format(i),
			size = Vector3.new(1.6, 9, 3.2),
			cframe = pose * CFrame.new(0, 0, LENGTH * 0.56) * CFrame.Angles(0, 0, a) * CFrame.new(0, 5, 0) * CFrame.Angles(0.5, 0, 0),
			material = Enum.Material.CorrodedMetal,
			color = DARK,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
	end

	-- Portholes: dark glass, not lit. Emissive portholes made the wreck look
	-- powered and occupied; a sunken hull's glass is black.
	for i = 1, 12 do
		local along = -LENGTH * 0.42 + (LENGTH * 0.84) * (i / 13)
		for _, side in ipairs({ -1, 1 }) do
			PartUtils.CreatePart({
				name = ("SubPorthole%d"):format(i),
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(0.6, 2.6, 2.6),
				cframe = pose * CFrame.new(side * RADIUS * 0.95, 1, along) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, math.rad(90), 0),
				material = Enum.Material.Glass,
				color = Color3.fromRGB(18, 26, 30),
				canCollide = false,
				castShadow = false,
				parent = folder,
			})
		end
	end

	--[[
		Coral growing over the wreck. This is the detail that dates it: bare
		metal reads as recently sunk, encrusted metal reads as part of the reef.
	]]
	for i = 1, 40 do
		local a = rng:NextNumber(0, math.pi * 2)
		local along = rng:NextNumber(-LENGTH * 0.5, LENGTH * 0.5)
		local builder = CORAL_BUILDERS[rng:NextInteger(1, #CORAL_BUILDERS)]
		local spot = pose * CFrame.new(math.sin(a) * RADIUS * 0.8, math.cos(a) * RADIUS * 0.8, along)
		builder(
			spot.Position,
			rng:NextNumber(3, 8),
			CORAL_PALETTE[rng:NextInteger(1, #CORAL_PALETTE)],
			folder,
			"SubCoral" .. i
		)
	end

	return origin
end

--[[
	SHIPWRECK.

	A broken cargo freighter, deliberately a completely different silhouette
	from the submarine: where the sub is a smooth sealed tube, this is an
	angular hull with a flat deck, an upright superstructure, a funnel, cargo
	hatches, a mast, and exposed frame ribs where the plating has gone.

	Snapped in two amidships with the stern half lying at a different angle -
	the most recognisable thing about a real wreck is that the two halves do
	not line up.

	Like the submarine it is encrusted with coral, and it sits half-buried:
	the keel is sunk into the reef rather than resting on top of it.
]]
local function buildShipwreck(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Shipwreck"
	folder.Parent = parent

	local rng = Random.new(190244)

	-- Find a broad, reasonably level shelf, well away from the submarine's
	-- own search band so the two wrecks never land on top of each other.
	local bestX, bestZ, bestSurface, bestScore = 0, 0, 0, -1e9
	for _ = 1, 700 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(REEF_FLAT_START, REEF_CREST)
		local x, z = math.sin(a) * r, math.cos(a) * r
		local s = reefHeight(x, z)
		if s > 60 then
			local spread = 0
			for _, o in ipairs({ Vector2.new(70, 0), Vector2.new(-70, 0), Vector2.new(0, 70), Vector2.new(0, -70) }) do
				spread += math.abs(reefHeight(x + o.X, z + o.Y) - s)
			end
			local score = s - spread * 0.8
			if score > bestScore then
				bestX, bestZ, bestSurface, bestScore = x, z, s, score
			end
		end
	end

	local HULL = Color3.fromRGB(64, 68, 72)
	local RUST = Color3.fromRGB(104, 66, 44)
	local DECK = Color3.fromRGB(78, 74, 66)
	local RED_LEAD = Color3.fromRGB(96, 48, 40) -- anti-fouling paint below the waterline

	local LENGTH = 200
	local BEAM = 34
	local DEPTH = 26

	local heading = rng:NextNumber(0, math.pi * 2)
	-- Keel sunk about a third into the reef, listing hard to starboard.
	local origin = Vector3.new(bestX, bestSurface + DEPTH * 0.2, bestZ)
	local bowPose = CFrame.new(origin) * CFrame.Angles(0, heading, 0) * CFrame.Angles(math.rad(6), 0, math.rad(-27))
	-- Stern half: broken away, twisted off-axis and settled deeper.
	local sternPose = CFrame.new(origin + Vector3.new(0, -6, 0))
		* CFrame.Angles(0, heading + math.rad(23), 0)
		* CFrame.Angles(math.rad(-9), 0, math.rad(14))

	-- BOW SECTION hull.
	for i = 0, 5 do
		local t = i / 5
		local taper = 1 - t * 0.75 -- narrows toward the bow
		PartUtils.CreatePart({
			name = ("WreckBowHull%d"):format(i),
			size = Vector3.new(BEAM * taper, DEPTH, LENGTH * 0.09),
			cframe = bowPose * CFrame.new(0, 0, -LENGTH * (0.08 + t * 0.4)),
			material = Enum.Material.CorrodedMetal,
			color = if i > 3 then RED_LEAD else HULL,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
	end
	-- Raked stem.
	PartUtils.CreatePart({
		className = "WedgePart",
		name = "WreckStem",
		size = Vector3.new(BEAM * 0.25, DEPTH, LENGTH * 0.1),
		cframe = bowPose * CFrame.new(0, 0, -LENGTH * 0.53) * CFrame.Angles(0, math.rad(180), 0),
		material = Enum.Material.CorrodedMetal,
		color = RED_LEAD,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})
	-- Foredeck.
	PartUtils.CreatePart({
		name = "WreckForedeck",
		size = Vector3.new(BEAM * 0.92, 1.6, LENGTH * 0.42),
		cframe = bowPose * CFrame.new(0, DEPTH * 0.5, -LENGTH * 0.27),
		material = Enum.Material.CorrodedMetal,
		color = DECK,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})
	-- Cargo hatches, one collapsed inward.
	for i = 1, 3 do
		PartUtils.CreatePart({
			name = ("WreckHatch%d"):format(i),
			size = Vector3.new(BEAM * 0.55, 2.4, LENGTH * 0.075),
			cframe = bowPose
				* CFrame.new(0, DEPTH * 0.53, -LENGTH * (0.12 + i * 0.11))
				* CFrame.Angles(0, 0, if i == 2 then math.rad(24) else 0),
			material = Enum.Material.CorrodedMetal,
			color = RUST,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
	end
	-- Foremast, snapped and leaning.
	PartUtils.CreatePart({
		name = "WreckMast",
		size = Vector3.new(2.2, 46, 2.2),
		cframe = bowPose * CFrame.new(0, DEPTH * 0.5 + 20, -LENGTH * 0.2) * CFrame.Angles(math.rad(17), 0, math.rad(9)),
		material = Enum.Material.CorrodedMetal,
		color = RUST,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})

	-- STERN SECTION hull.
	for i = 0, 4 do
		local t = i / 4
		PartUtils.CreatePart({
			name = ("WreckSternHull%d"):format(i),
			size = Vector3.new(BEAM * (1 - t * 0.3), DEPTH, LENGTH * 0.09),
			cframe = sternPose * CFrame.new(0, 0, LENGTH * (0.12 + t * 0.36)),
			material = Enum.Material.CorrodedMetal,
			color = if i > 2 then RED_LEAD else HULL,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
	end
	-- Superstructure: the block of accommodation decks aft.
	for deck = 0, 2 do
		PartUtils.CreatePart({
			name = ("WreckSuperstructure%d"):format(deck),
			size = Vector3.new(BEAM * (0.78 - deck * 0.12), 9, LENGTH * (0.13 - deck * 0.02)),
			cframe = sternPose * CFrame.new(0, DEPTH * 0.5 + 4.5 + deck * 9, LENGTH * 0.26),
			material = Enum.Material.CorrodedMetal,
			color = if deck == 0 then HULL else DECK,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
	end
	-- Funnel.
	PartUtils.CreatePart({
		name = "WreckFunnel",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(20, 13, 13),
		cframe = sternPose * CFrame.new(0, DEPTH * 0.5 + 38, LENGTH * 0.3) * CFrame.Angles(0, 0, math.rad(90)),
		material = Enum.Material.CorrodedMetal,
		color = RUST,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})
	-- Rudder and screw.
	PartUtils.CreatePart({
		name = "WreckRudder",
		size = Vector3.new(1.8, 16, 12),
		cframe = sternPose * CFrame.new(0, -DEPTH * 0.35, LENGTH * 0.52),
		material = Enum.Material.CorrodedMetal,
		color = RED_LEAD,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})
	for i = 1, 4 do
		local a = (math.pi / 2) * i
		PartUtils.CreatePart({
			name = ("WreckBlade%d"):format(i),
			size = Vector3.new(2, 11, 4),
			cframe = sternPose
				* CFrame.new(0, -DEPTH * 0.3, LENGTH * 0.47)
				* CFrame.Angles(0, 0, a)
				* CFrame.new(0, 6, 0)
				* CFrame.Angles(0.4, 0, 0),
			material = Enum.Material.CorrodedMetal,
			color = Color3.fromRGB(88, 76, 52),
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
	end

	--[[
		THE BREAK. Exposed frame ribs at both torn ends, with debris scattered
		between the halves. This is the detail that reads as "snapped" rather
		than "two ships parked nose to tail".
	]]
	for i = 1, 9 do
		local f = (i - 5) / 5
		PartUtils.CreatePart({
			name = ("WreckRibBow%d"):format(i),
			size = Vector3.new(1.4, DEPTH * rng:NextNumber(0.55, 0.95), 1.4),
			cframe = bowPose * CFrame.new(f * BEAM * 0.45, 0, -LENGTH * 0.06) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, f * 0.5),
			material = Enum.Material.CorrodedMetal,
			color = RUST,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
		PartUtils.CreatePart({
			name = ("WreckRibStern%d"):format(i),
			size = Vector3.new(1.4, DEPTH * rng:NextNumber(0.5, 0.9), 1.4),
			cframe = sternPose * CFrame.new(f * BEAM * 0.45, 0, LENGTH * 0.1) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, f * 0.5),
			material = Enum.Material.CorrodedMetal,
			color = RUST,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
	end
	-- Spilled debris in the gap.
	for i = 1, 22 do
		PartUtils.CreatePart({
			name = ("WreckDebris%d"):format(i),
			size = Vector3.new(rng:NextNumber(2, 9), rng:NextNumber(1, 5), rng:NextNumber(2, 10)),
			cframe = CFrame.new(
				origin
					+ Vector3.new(rng:NextNumber(-45, 45), rng:NextNumber(-8, 4), rng:NextNumber(-45, 45))
			) * CFrame.Angles(rng:NextNumber(-1, 1), rng:NextNumber(-3, 3), rng:NextNumber(-1, 1)),
			material = Enum.Material.CorrodedMetal,
			color = if rng:NextNumber() < 0.5 then RUST else HULL,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
	end

	-- Coral encrusting the hull, as on the submarine.
	for i = 1, 70 do
		local onBow = rng:NextNumber() < 0.55
		local pose = if onBow then bowPose else sternPose
		local along = if onBow then rng:NextNumber(-LENGTH * 0.5, -LENGTH * 0.05) else rng:NextNumber(LENGTH * 0.1, LENGTH * 0.5)
		local spot = pose * CFrame.new(rng:NextNumber(-BEAM * 0.5, BEAM * 0.5), rng:NextNumber(-DEPTH * 0.3, DEPTH * 0.55), along)
		local builder = CORAL_BUILDERS[rng:NextInteger(1, #CORAL_BUILDERS)]
		builder(spot.Position, rng:NextNumber(4, 12), CORAL_PALETTE[rng:NextInteger(1, #CORAL_PALETTE)], folder, "WreckCoral" .. i)
	end
end

--[[
	MEGAFAUNA.

	The map had nothing bigger than a 16-stud predator, so there was no sense
	of scale: a reef reads as huge only when something huge swims past it.

	All three below share a construction approach - a tapering body built from
	stacked segments, plus flukes/fins - and all three use COUNTERSHADING:
	dark on top, pale underneath. That is how every large marine animal is
	coloured, and it is what makes them read as animals rather than as grey
	blocks. Nothing here is emissive.

	Sizes are in studs, nose to tail:
	  Shark  40-60
	  Orca   70-90
	  Whale  180-260
]]

-- Tapered body: a chain of blocks whose cross-section follows `profile`.
local function buildTaperedBody(
	model: Model,
	pose: CFrame,
	length: number,
	profile: (number) -> (number, number),
	topColour: Color3,
	bellyColour: Color3,
	name: string
)
	local SEGMENTS = 16
	for i = 0, SEGMENTS - 1 do
		local t = i / SEGMENTS
		local nextT = (i + 1) / SEGMENTS
		local w, h = profile(t + 0.5 / SEGMENTS)
		local segLen = (nextT - t) * length * 1.08 -- slight overlap, no seams
		local along = (t + 0.5 / SEGMENTS - 0.5) * length

		-- Upper body.
		PartUtils.CreatePart({
			name = ("%sBody%d"):format(name, i),
			size = Vector3.new(w, h, segLen),
			cframe = pose * CFrame.new(0, 0, along),
			material = Enum.Material.SmoothPlastic,
			color = topColour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
		-- Pale belly panel, inset so it reads as the underside rather than as
		-- a stripe stuck on the flank.
		PartUtils.CreatePart({
			name = ("%sBelly%d"):format(name, i),
			size = Vector3.new(w * 0.72, h * 0.34, segLen),
			cframe = pose * CFrame.new(0, -h * 0.36, along),
			material = Enum.Material.SmoothPlastic,
			color = bellyColour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
end

-- Horizontal tail flukes (whales, orcas) or a vertical caudal fin (sharks).
local function buildFlukes(model: Model, pose: CFrame, length: number, span: number, colour: Color3, name: string)
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = name .. "Fluke",
			size = Vector3.new(span * 0.52, length * 0.018, length * 0.1),
			cframe = pose
				* CFrame.new(side * span * 0.3, 0, length * 0.52)
				* CFrame.Angles(0, side * 0.35, side * 0.12),
			material = Enum.Material.SmoothPlastic,
			color = colour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
end

local function buildPectorals(model: Model, pose: CFrame, length: number, span: number, sweep: number, colour: Color3, name: string)
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = name .. "Pectoral",
			size = Vector3.new(span, length * 0.016, length * 0.11),
			cframe = pose
				* CFrame.new(side * span * 0.55, -length * 0.02, -length * 0.14)
				* CFrame.Angles(0, side * sweep, side * 0.3),
			material = Enum.Material.SmoothPlastic,
			color = colour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
end

-- GREAT WHITE SHARK: torpedo body, tall triangular dorsal, vertical tail.
local function buildShark(pose: CFrame, length: number, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local TOP = Color3.fromRGB(86, 94, 102)
	local BELLY = Color3.fromRGB(206, 206, 198)

	-- Widest a third back from the nose, tapering to a narrow tail stock.
	local function profile(t: number): (number, number)
		local girth = math.sin(math.clamp(t, 0, 1) ^ 0.7 * math.pi) ^ 0.8
		return length * 0.15 * girth + length * 0.012, length * 0.19 * girth + length * 0.012
	end
	buildTaperedBody(model, pose, length, profile, TOP, BELLY, name)

	-- Pointed snout.
	PartUtils.CreatePart({
		name = name .. "Snout",
		size = Vector3.new(length * 0.07, length * 0.07, length * 0.11),
		cframe = pose * CFrame.new(0, 0, -length * 0.54),
		material = Enum.Material.SmoothPlastic,
		color = TOP,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	-- Tall dorsal - the shark read.
	PartUtils.CreatePart({
		className = "WedgePart",
		name = name .. "Dorsal",
		size = Vector3.new(length * 0.02, length * 0.16, length * 0.2),
		cframe = pose * CFrame.new(0, length * 0.11, -length * 0.02) * CFrame.Angles(0, math.rad(180), 0),
		material = Enum.Material.SmoothPlastic,
		color = TOP,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	buildPectorals(model, pose, length, length * 0.17, 0.25, TOP, name)
	-- Vertical caudal fin with a longer upper lobe.
	for _, lobe in ipairs({ { 1, 0.22 }, { -1, 0.13 } }) do
		PartUtils.CreatePart({
			className = "WedgePart",
			name = name .. "Caudal",
			size = Vector3.new(length * 0.02, length * lobe[2], length * 0.14),
			cframe = pose
				* CFrame.new(0, lobe[1] * length * lobe[2] * 0.5, length * 0.52)
				* CFrame.Angles(if lobe[1] > 0 then 0 else math.pi, 0, 0),
			material = Enum.Material.SmoothPlastic,
			color = TOP,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
	return model
end

-- ORCA: blunt rounded head, huge dorsal, and the distinctive white eye patch
-- and saddle - without those markings it is just a black whale.
local function buildOrca(pose: CFrame, length: number, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local BLACK = Color3.fromRGB(24, 26, 30)
	local WHITE = Color3.fromRGB(238, 238, 232)

	local function profile(t: number): (number, number)
		local girth = math.sin(math.clamp(t, 0, 1) ^ 0.62 * math.pi) ^ 0.62
		return length * 0.17 * girth + length * 0.014, length * 0.2 * girth + length * 0.014
	end
	buildTaperedBody(model, pose, length, profile, BLACK, WHITE, name)

	-- Rounded melon head.
	PartUtils.CreatePart({
		name = name .. "Melon",
		shape = Enum.PartType.Ball,
		size = Vector3.new(length * 0.15, length * 0.16, length * 0.18),
		cframe = pose * CFrame.new(0, 0, -length * 0.48),
		material = Enum.Material.SmoothPlastic,
		color = BLACK,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	-- Eye patches.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = name .. "EyePatch",
			size = Vector3.new(length * 0.03, length * 0.045, length * 0.09),
			cframe = pose * CFrame.new(side * length * 0.075, length * 0.03, -length * 0.36),
			material = Enum.Material.SmoothPlastic,
			color = WHITE,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
	-- Grey saddle behind the dorsal.
	PartUtils.CreatePart({
		name = name .. "Saddle",
		size = Vector3.new(length * 0.13, length * 0.03, length * 0.13),
		cframe = pose * CFrame.new(0, length * 0.09, length * 0.08),
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(96, 100, 108),
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	-- The unmistakable tall dorsal.
	PartUtils.CreatePart({
		className = "WedgePart",
		name = name .. "Dorsal",
		size = Vector3.new(length * 0.025, length * 0.24, length * 0.17),
		cframe = pose * CFrame.new(0, length * 0.19, -length * 0.03) * CFrame.Angles(0, math.rad(180), 0),
		material = Enum.Material.SmoothPlastic,
		color = BLACK,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	buildPectorals(model, pose, length, length * 0.2, 0.3, BLACK, name)
	buildFlukes(model, pose, length, length * 0.34, BLACK, name)
	return model
end

-- HUMPBACK WHALE: vast, deep-bodied, with the enormous pectoral flippers and
-- pleated throat that distinguish it. The biggest thing in the map.
local function buildWhale(pose: CFrame, length: number, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local TOP = Color3.fromRGB(52, 58, 68)
	local BELLY = Color3.fromRGB(178, 180, 176)

	local function profile(t: number): (number, number)
		-- Bulk carried well forward, tapering to a narrow peduncle.
		local girth = math.sin(math.clamp(t, 0, 1) ^ 0.5 * math.pi) ^ 0.55
		return length * 0.15 * girth + length * 0.01, length * 0.18 * girth + length * 0.01
	end
	buildTaperedBody(model, pose, length, profile, TOP, BELLY, name)

	-- Broad head.
	PartUtils.CreatePart({
		name = name .. "Head",
		shape = Enum.PartType.Ball,
		size = Vector3.new(length * 0.14, length * 0.12, length * 0.22),
		cframe = pose * CFrame.new(0, 0, -length * 0.5),
		material = Enum.Material.SmoothPlastic,
		color = TOP,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	-- Throat pleats: long shallow ridges along the underside.
	for i = 1, 7 do
		PartUtils.CreatePart({
			name = name .. "Pleat",
			size = Vector3.new(length * 0.012, length * 0.02, length * 0.3),
			cframe = pose * CFrame.new((i - 4) * length * 0.018, -length * 0.075, -length * 0.28),
			material = Enum.Material.SmoothPlastic,
			color = Color3.fromRGB(150, 152, 148),
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
	-- Small dorsal hump, far back.
	PartUtils.CreatePart({
		className = "WedgePart",
		name = name .. "Dorsal",
		size = Vector3.new(length * 0.02, length * 0.05, length * 0.1),
		cframe = pose * CFrame.new(0, length * 0.09, length * 0.18) * CFrame.Angles(0, math.rad(180), 0),
		material = Enum.Material.SmoothPlastic,
		color = TOP,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	-- Huge white-undersided flippers, ~1/3 of body length.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = name .. "Flipper",
			size = Vector3.new(length * 0.3, length * 0.015, length * 0.08),
			cframe = pose
				* CFrame.new(side * length * 0.19, -length * 0.03, -length * 0.16)
				* CFrame.Angles(0, side * 0.5, side * 0.35),
			material = Enum.Material.SmoothPlastic,
			color = BELLY,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
	buildFlukes(model, pose, length, length * 0.32, TOP, name)
	return model
end

--[[
	MEGAFAUNA PLACEMENT.

	Kept OUT over the reef and open water, never over the plaza, and high
	enough that nothing crosses the sightline to the central board. Whales
	cruise highest and furthest out; sharks patrol closest to the reef.
]]
local function buildMegafauna(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Megafauna"
	folder.Parent = parent

	local rng = Random.new(313377)

	local function poseAt(radiusMin: number, radiusMax: number, heightMin: number, heightMax: number): CFrame
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(radiusMin, radiusMax)
		local y = rng:NextNumber(heightMin, heightMax)
		-- Face along the ring, so animals cruise around the reef rather than
		-- pointing at random.
		return CFrame.new(Vector3.new(math.sin(a) * r, y, math.cos(a) * r))
			* CFrame.Angles(0, a + math.pi / 2 + rng:NextNumber(-0.4, 0.4), 0)
			* CFrame.Angles(rng:NextNumber(-0.08, 0.08), 0, rng:NextNumber(-0.12, 0.12))
	end

	-- Sharks: closest to the reef, patrolling the drop-off.
	for i = 1, 9 do
		buildShark(poseAt(REEF_INNER + 40, REEF_OUTER - 60, 170, 300), rng:NextNumber(40, 60), folder, "Shark" .. i)
	end

	-- Orcas: a family pod, travelling together as they actually do.
	local podAngle = rng:NextNumber(0, math.pi * 2)
	local podRadius = rng:NextNumber(REEF_CREST - 60, REEF_OUTER - 80)
	local podY = rng:NextNumber(280, 360)
	for i = 1, 5 do
		local spread = 70
		local centre = Vector3.new(math.sin(podAngle) * podRadius, podY, math.cos(podAngle) * podRadius)
			+ Vector3.new(rng:NextNumber(-spread, spread), rng:NextNumber(-25, 25), rng:NextNumber(-spread, spread))
		local pose = CFrame.new(centre) * CFrame.Angles(0, podAngle + math.pi / 2, 0) * CFrame.Angles(rng:NextNumber(-0.06, 0.06), 0, 0)
		-- One large bull, the rest smaller cows and calves.
		buildOrca(pose, if i == 1 then 90 else rng:NextNumber(55, 78), folder, "Orca" .. i)
	end

	-- Whales: two, very high and far out, as distant silhouettes.
	for i = 1, 2 do
		buildWhale(poseAt(REEF_CREST, REEF_OUTER - 40, 380, 470), rng:NextNumber(180, 260), folder, "Whale" .. i)
	end
end

function UnderTheSeaEnvironment.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "UnderTheSeaEnvironment"
	folder.Parent = parent

	buildWallSegments(folder)
	buildCeiling(folder)
	buildFloor(folder)
	buildSeabedPattern(folder)
	buildLightShafts(folder)
	buildBubbleStreams(folder)
	buildCoralReefs(folder)
	buildFishSchools(folder)
	-- Added life and atmosphere: a second creature silhouette (jellyfish),
	-- something rooted to the seabed (kelp), and bubbles filling the whole
	-- water column so the map reads as submerged from any height.
	buildJellyfishBloom(folder)
	buildKelpForest(folder)
	buildAmbientBubbles(folder)
	-- Colour and close-up detail on the terrain reef, plus the handful of
	-- large animals kept high over the plaza.
	buildCoralForest(folder)
	buildSunkenSubmarine(folder)
	buildShipwreck(folder)
	buildMegafauna(folder)
	buildOverheadLife(folder)

	return folder
end

return UnderTheSeaEnvironment
