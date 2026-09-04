--[[
	IceAgeEnvironment.lua

	Builds the Ice Age map's signature backdrop: a large enclosing ring of
	pale "whiteout sky" wall panels plus a matching ceiling cap (reads as
	an overcast frozen horizon surrounding the playable area - see
	SpaceEnvironment.lua's buildWallSegments doc comment for why this is a
	ring of panels rather than one giant enclosing part), scattered
	falling-snow streams, distant frozen mountain silhouettes near the
	boundary, a few hanging icicle clusters, and soft translucent aurora
	streaks arcing overhead.

	ICE-AGE-MAP-ONLY: only ever called by LobbyBuilder for the Ice Age map
	(def.themeId == "IceAge" - see LobbyBuilder/init.lua). Every other map
	(Futuristic, Lava, Space, Under the Sea, and any future map) is
	completely untouched by this module.

	Architecture mirrors SpaceEnvironment.lua exactly (same enclosing-ring
	technique, same local-space-then-bulk-translate convention, same
	ENCLOSURE_RADIUS/fog-distance reasoning) - see that module's doc
	comment for the full explanation of why a single giant Part doesn't
	work here and why the shared global Lighting fog caps how large this
	can usefully be. Here the pale wall color is chosen to blend smoothly
	into the shared fog (a flat, pale, overcast "whiteout" sky is exactly
	the right look for a frozen horizon, unlike Space's dark void which
	had to actively fight the fog to read as dark).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local MapConfig = require(script.Parent.MapConfig)
-- Used by buildIceSheets to keep frozen patches clear of building entrances.
local LobbyConfig = require(script.Parent.LobbyConfig)

local IceAgeEnvironment = {}

--[[
	ENLARGED FOR THE MOUNTAIN RANGE.

	Was 300. The enclosure is a sealed opaque box - SkyWalls form a cylinder
	at this radius and SkyCeiling/SkyFloor are sized from it - so nothing
	outside it is visible from inside, and it therefore sets the hard ceiling
	on how much surrounding landscape the map can show.

	At 300 there was only ~130 studs of ground between the walkable plaza
	(USABLE_RADIUS 172) and the wall. Realistically-proportioned mountains
	are far WIDER than they are tall - Everest rises about 3.7km over a base
	roughly 10km across - so a believable peak needs a base radius in the
	hundreds. There was simply nowhere to put one, which is why the first
	attempt ended up as narrow 450-stud spikes.

	1000 gives ~800 studs of clear ground beyond the plaza: enough for a ring
	of genuinely broad mountains with room between them and the wall. Walls,
	ceiling and floor all derive from this constant, so they scale with it
	automatically and nothing else needs changing.
]]
local ENCLOSURE_RADIUS = 1000
-- Scaled with ENCLOSURE_RADIUS. At the old radius of 300, 28 segments gave
-- a chord of ~67 studs, short enough that the ring read as smooth. At 1000
-- the same 28 segments give a 224-stud chord, and the flat facets plus the
-- gaps at each joint show as vertical seams across the sky. 96 restores a
-- ~65-stud chord, i.e. the same smoothness as before the map was enlarged.
local WALL_SEGMENTS = 96
local WALL_HEIGHT = 700
local WALL_BOTTOM_Y = -200
local WALL_THICKNESS = 4
local SKY_COLOR = Color3.fromRGB(198, 210, 222) -- pale overcast whiteout, blends into the shared fog

--[[
	Builds the enclosing "whiteout sky" ring + ceiling cap - see
	SpaceEnvironment.lua's buildWallSegments doc comment for the full
	explanation of why this is a ring of thin panels (each one the camera
	stands beside, never inside) rather than one giant part.
]]
local function buildWallSegments(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "SkyWalls"
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
			name = "SkyWall" .. i,
			size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, length),
			cframe = CFrame.new(midpoint + Vector3.new(0, wallCenterY, 0)) * CFrame.Angles(0, yaw, 0),
			material = Enum.Material.SmoothPlastic,
			color = SKY_COLOR,
			canCollide = false,
			parent = folder,
		})
	end
end

local function buildCeiling(parent: Instance)
	local ceilingY = WALL_BOTTOM_Y + WALL_HEIGHT + 6
	PartUtils.CreatePart({
		name = "SkyCeiling",
		size = Vector3.new(ENCLOSURE_RADIUS * 2 + 40, 8, ENCLOSURE_RADIUS * 2 + 40),
		position = Vector3.new(0, ceilingY, 0),
		material = Enum.Material.SmoothPlastic,
		color = SKY_COLOR,
		canCollide = false,
		parent = parent,
	})
end

-- Caps the bottom of the enclosure - see SpaceEnvironment.lua's buildFloor
-- doc comment for why this matters ("the bottom of the outline" gap).
local function buildFloor(parent: Instance)
	PartUtils.CreatePart({
		name = "SkyFloor",
		size = Vector3.new(ENCLOSURE_RADIUS * 2 + 40, 8, ENCLOSURE_RADIUS * 2 + 40),
		position = Vector3.new(0, WALL_BOTTOM_Y - 6, 0),
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(150, 165, 178),
		canCollide = false,
		parent = parent,
	})
end

--[[
	Scatters slow falling-snow streams around the map - each an invisible
	anchor part with a ParticleEmitter tuned to drift gently downward and
	fade, purely decorative (no PointLights, matching the performance
	guidance already established by SpaceEnvironment.lua). Deterministic
	seed so placement looks identical across rebuilds.
]]
local function buildSnowfall(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Snowfall"
	folder.Parent = parent

	local rng = Random.new(410772)
	--[[
		SNOWFALL DENSITY.

		Was 16 anchors on a single plane at WALL_HEIGHT * 0.35, Rate 6 - a
		thin scatter all at one altitude, which reads as barely-there from the
		ground and disappears entirely if the camera rises above that plane.

		Now 3 height layers x 14 anchors = 42 emitters at Rate 16, so there is
		snow in the air at every viewing height and enough of it to actually
		read as weather. Lifetime is stretched to 9-14s so flakes fall the full
		visible distance instead of vanishing mid-air.

		Still particle emitters on real anchored Parts, so this renders in the
		Edit viewport as well as in Play.
	]]
	local PER_LAYER = 14
	local LAYERS = { 0.22, 0.55, 0.9 } -- fractions of WALL_HEIGHT

	local index = 0
	for _, heightFraction in ipairs(LAYERS) do
		for _ = 1, PER_LAYER do
			index += 1
			local angle = rng:NextNumber(0, 2 * math.pi)
			local radius = rng:NextNumber(20, MapConfig.USABLE_RADIUS * 0.98)
			local position =
				Vector3.new(math.sin(angle) * radius, WALL_HEIGHT * heightFraction, math.cos(angle) * radius)

			local anchor = PartUtils.CreatePart({
				name = "SnowAnchor" .. index,
				-- A wide flat emitter box spreads flakes over an area instead of
				-- streaming them from a single point.
				size = Vector3.new(70, 1, 70),
				position = position,
				transparency = 1,
				canCollide = false,
				castShadow = false,
				parent = folder,
			}) :: BasePart

			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "Snow"
			emitter.Shape = Enum.ParticleEmitterShape.Box
			emitter.EmissionDirection = Enum.NormalId.Bottom
			emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
			emitter.LightInfluence = 0
			emitter.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.6),
				NumberSequenceKeypoint.new(0.15, 0.15),
				NumberSequenceKeypoint.new(0.85, 0.25),
				NumberSequenceKeypoint.new(1, 1),
			})
			emitter.Size = NumberSequence.new(0.35)
			emitter.Lifetime = NumberRange.new(9, 14)
			emitter.Speed = NumberRange.new(2, 4)
			emitter.Rate = 16
			emitter.SpreadAngle = Vector2.new(25, 25)
			-- Sideways component so snow drifts on a wind rather than dropping
			-- vertically like rain.
			emitter.Acceleration = Vector3.new(-1.8, -6, 1.2)
			emitter.Rotation = NumberRange.new(0, 360)
			emitter.RotSpeed = NumberRange.new(-30, 30)
			emitter.Parent = anchor
		end
	end
end

local function slopeCFrame(position: Vector3, angle: number, pitch: number): CFrame
	return CFrame.new(position) * CFrame.Angles(0, angle, 0) * CFrame.Angles(pitch, 0, 0)
end

--[[
	Forward-declared. buildFrozenPeak/buildFrozenPeaks (immediately below) need
	to sample the actual apron/range height so the foothills sit flush on the
	terrain instead of at a hardcoded Y - but that logic (mountainHeight and
	the RANGE_*/APRON_* constants it depends on) is defined much further down,
	next to BuildTerrainMountains, which is where it conceptually belongs.
	Declaring the local here and assigning the real function later (that
	definition drops its own `local` keyword accordingly) lets both call sites
	share one implementation without moving ~90 lines of terrain code above
	the part-based builders it has nothing else to do with. Safe because nothing
	calls buildFrozenPeaks until IceAgeEnvironment.BuildAll runs, by which point
	the whole module has finished loading and the assignment below has happened.
]]
local mountainHeight: (number, number) -> number

--[[
	One "pillar" landmark near the boundary: a continuous frozen-mountain
	cone, NOT scattered floating chunks. Uses the exact same tiered-shingle
	technique as LavaEnvironment's buildDistantVolcano - many tiers of
	large overlapping slabs, each tilted (via slopeCFrame) so its flat face
	lies FLUSH against the theoretical cone surface, with radius/height
	overlap between consecutive tiers so there is never a seam or gap.
	Reinterpreted in frost tones (mixed Ice/Rock/Snow materials), with a
	snow-accumulation cap at the peak, a shallow ground-blending skirt at
	the base, and a handful of hanging icicles along the slope's edges.
]]
local function buildFrozenPeak(position: Vector3, rng: Random, parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local baseRadius = rng:NextNumber(20, 30)
	local peakHeight = rng:NextNumber(55, 100)
	local tipRadius = 2 + rng:NextNumber(0, 1.5)

	local slopeAngle = math.atan2(peakHeight, baseRadius - tipRadius)
	local shinglePitch = (math.pi / 2) - slopeAngle

	-- Same tightening as LavaEnvironment's buildDistantVolcano: more tiers,
	-- slab length derived from the true slant distance to the next tier,
	-- width derived from the ring's own arc spacing, and jitter expressed
	-- as a fraction of the resulting overlap margin so it can never open a
	-- seam between neighbouring slabs.
	local tierCount = 12
	local SHINGLE_OVERLAP = 1.9
	for tier = 0, tierCount do
		local t = tier / tierCount
		local ringRadius = math.max(tipRadius, baseRadius * (1 - t) ^ 0.9)
		local ringY = peakHeight * t ^ 1.05
		local nextT = math.min((tier + 1) / tierCount, 1)
		local nextRadius = math.max(tipRadius, baseRadius * (1 - nextT) ^ 0.9)
		local nextY = peakHeight * nextT ^ 1.05
		local slant = math.max(
			math.sqrt((ringRadius - nextRadius) ^ 2 + (ringY - nextY) ^ 2),
			baseRadius / tierCount
		)
		local shingleLength = slant * SHINGLE_OVERLAP

		local circumference = 2 * math.pi * ringRadius
		local shingleCount = math.max(8, math.ceil(circumference / math.max(ringRadius * 0.45, 5.5)))
		local arcSpacing = circumference / shingleCount
		local shingleWidth = arcSpacing * SHINGLE_OVERLAP
		local overlapMargin = (shingleWidth - arcSpacing) / 2

		for c = 1, shingleCount do
			local angle = (2 * math.pi / shingleCount) * c
			local jitterRadius = ringRadius + rng:NextNumber(-overlapMargin * 0.4, overlapMargin * 0.4)
			local jitterY = ringY + rng:NextNumber(-slant * 0.15, slant * 0.15)
			local shinglePos = position + Vector3.new(math.sin(angle) * jitterRadius, jitterY, math.cos(angle) * jitterRadius)
			local useRock = rng:NextNumber() < 0.3
			PartUtils.CreatePart({
				name = ("PeakShingleT%dC%d"):format(tier, c),
				size = Vector3.new(shingleWidth, rng:NextNumber(3, 4.5), shingleLength),
				cframe = slopeCFrame(shinglePos, angle, shinglePitch + math.rad(rng:NextNumber(-3, 3))),
				material = if useRock then Enum.Material.Rock else Enum.Material.Ice,
				color = if useRock
					then Color3.fromRGB(90 + rng:NextInteger(-4, 6), 96 + rng:NextInteger(-4, 6), 102 + rng:NextInteger(-4, 6))
					else Color3.fromRGB(200 + rng:NextInteger(-8, 10), 216 + rng:NextInteger(-6, 8), 232 + rng:NextInteger(-4, 6)),
				canCollide = false,
				parent = model,
			})
		end
	end

	-- Shallow skirt blending the peak's foot into the surrounding ground.
	local skirtOuterRadius = baseRadius * 2
	local skirtRingCount = 2
	for ring = 1, skirtRingCount do
		local ringFraction = ring / skirtRingCount
		local ringRadius = baseRadius + (skirtOuterRadius - baseRadius) * ringFraction
		local ringY = math.max(0, (peakHeight * 0.05) * (1 - ringFraction))
		local skirtPitch = shinglePitch * (1 - ringFraction) * 0.35
		local slabWidth = 18
		local slabCount = math.max(8, math.floor((2 * math.pi * ringRadius) / (slabWidth * 0.55)))
		for c = 1, slabCount do
			local angle = (2 * math.pi / slabCount) * c + rng:NextNumber(-0.15, 0.15)
			local slabPos = position + Vector3.new(math.sin(angle) * ringRadius, ringY, math.cos(angle) * ringRadius)
			PartUtils.CreatePart({
				name = ("PeakSkirtR%dC%d"):format(ring, c),
				size = Vector3.new(slabWidth * rng:NextNumber(0.9, 1.2), rng:NextNumber(1.2, 2.5), (skirtOuterRadius - baseRadius) / skirtRingCount * 2.2),
				cframe = slopeCFrame(slabPos, angle, skirtPitch),
				material = Enum.Material.Snow,
				color = Color3.fromRGB(225 + rng:NextInteger(-6, 8), 234 + rng:NextInteger(-4, 6), 242 + rng:NextInteger(-4, 4)),
				canCollide = false,
				parent = model,
			})
		end
	end

	-- Snow-accumulation cap at the very top.
	PartUtils.CreatePart({
		name = "SnowCap",
		size = Vector3.new(tipRadius * 3, tipRadius * 1.8, tipRadius * 3),
		position = position + Vector3.new(0, peakHeight + tipRadius * 0.4, 0),
		material = Enum.Material.Snow,
		color = Color3.fromRGB(240, 246, 251),
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})

	-- A handful of hanging icicles along the formation's own slope edges.
	for i = 1, rng:NextInteger(3, 5) do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local t = rng:NextNumber(0.15, 0.7)
		local icicleRadius = math.max(tipRadius, baseRadius * (1 - t) ^ 0.9)
		local icicleHeight = peakHeight * t ^ 1.05
		PartUtils.CreatePart({
			className = "WedgePart",
			name = "PeakIcicle" .. i,
			size = Vector3.new(0.8, rng:NextNumber(2, 4), 0.8),
			cframe = CFrame.new(
				position + Vector3.new(math.sin(angle) * icicleRadius, icicleHeight, math.cos(angle) * icicleRadius)
			) * CFrame.Angles(math.pi, 0, 0),
			material = Enum.Material.Ice,
			color = Color3.fromRGB(210, 232, 245),
			canCollide = false,
			parent = model,
		})
	end

	return model
end

local function buildFrozenPeaks(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "FrozenPeaks"
	folder.Parent = parent

	--[[
		HARDCODED, HAND-PLACED POSITIONS.

		These 8 peaks were originally placed procedurally (mountainHeight-based
		apron placement, ground-truth-snapped by SnapFrozenPeaksToTerrain), then
		manually repositioned by hand in Studio to their approved final spots.
		Read directly off the live, hand-placed Tundra place via Model:GetPivot()
		- which reports LOCAL, pre-applyMapTransform coordinates, confirmed by
		cross-checking against each peak's world-space bounding box, which
		differs by exactly the known origin+GROUND_ELEVATION offset - and
		hardcoded here so no future procedural rebuild moves them again.

		The angle/radius RNG draws below are DELIBERATELY KEPT (their results
		are discarded) rather than removed outright, so buildFrozenPeak's own
		internal shape rolls (baseRadius, peakHeight, shingle jitter, tier
		counts, etc., all drawn from this same `rng` right afterward) consume
		the exact same sequence of random numbers as before - every peak's
		actual shape/size stays byte-identical to what was already built and
		approved; only its position is now fixed.
	]]
	local rng = Random.new(619204)
	local count = 8
	local APRON_BAND_INNER = 210 -- unused for placement now, kept only so the discarded RNG draw below matches the original sequence
	local APRON_BAND_OUTER = 300 -- unused for placement now, kept only so the discarded RNG draw below matches the original sequence

	local HAND_PLACED_POSITIONS = {
		Vector3.new(-9.796, 51.215, 270.892), -- FrozenPeak1
		Vector3.new(155.496, 37.168, 224.646), -- FrozenPeak2
		Vector3.new(285.977, 35.299, 13.087), -- FrozenPeak3
		Vector3.new(181.235, 42.365, -197.170), -- FrozenPeak4
		Vector3.new(-2.875, 44.963, -257.762), -- FrozenPeak5
		Vector3.new(-191.208, 34.791, -193.649), -- FrozenPeak6
		Vector3.new(-281.680, 50.968, 2.653), -- FrozenPeak7
		Vector3.new(-211.477, 55.263, 157.722), -- FrozenPeak8
	}

	for i = 1, count do
		-- Discarded on purpose - see comment above; preserves RNG state so
		-- each peak's shape generation is unaffected by the switch to fixed
		-- positions.
		local _angle = (i - 1) / count * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local _radius = rng:NextNumber(APRON_BAND_INNER, APRON_BAND_OUTER)

		local position = HAND_PLACED_POSITIONS[i]
		buildFrozenPeak(position, rng, folder, "FrozenPeak" .. i)
	end
end

--[[
	Chilly, windy atmosphere - replaces the old floating IcicleClusters
	decoration ENTIRELY (per explicit direction: remove the prominent
	map-wide icicle treatment and replace it with many small snowflakes/
	wind-blown particles instead - icicles now only ever appear on the
	igloo buildings' own edges/entrance arch, see BuildingInteriors.lua).
	Many small snowflake particles drift with a strong horizontal "wind"
	bias (not gentle vertical fall like buildSnowfall's existing streams
	elsewhere in this file) from a single consistent prevailing direction,
	so the whole map reads as one continuous windy gust rather than
	random directionless drift.
]]
local function buildSnowflakeWind(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "SnowflakeWind"
	folder.Parent = parent

	local rng = Random.new(551029)
	-- Denser and lower than before: emitters now start close to head height
	-- so the snow is visibly IN THE AIR AROUND the player rather than only
	-- drifting somewhere overhead. More emitters at a higher rate is what
	-- actually sells "it feels snowy" when standing in the plaza.
	local count = 34
	local windAngle = rng:NextNumber(0, 2 * math.pi)
	local windDirection = Vector3.new(math.sin(windAngle), 0, math.cos(windAngle))

	for i = 1, count do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(6, MapConfig.USABLE_RADIUS)
		local height = rng:NextNumber(4, 70)
		local position = Vector3.new(math.sin(angle) * radius, height, math.cos(angle) * radius)

		local anchor = PartUtils.CreatePart({
			name = "SnowflakeAnchor" .. i,
			size = Vector3.new(1, 1, 1),
			position = position,
			transparency = 1,
			canCollide = false,
			parent = folder,
		}) :: BasePart

		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.8, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		-- Mixed flake sizes read as real snow; a single uniform size reads as
		-- dust. Rate raised alongside the higher emitter count so the air
		-- genuinely fills rather than showing occasional stray specks.
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, rng:NextNumber(0.16, 0.34)),
			NumberSequenceKeypoint.new(1, rng:NextNumber(0.12, 0.26)),
		})
		emitter.Lifetime = NumberRange.new(8, 14)
		emitter.Speed = NumberRange.new(4, 9)
		emitter.Rate = 26
		emitter.SpreadAngle = Vector2.new(35, 15)
		-- Wind bias: strong horizontal acceleration along the prevailing
		-- direction, only mild downward pull - reads as snow blowing
		-- SIDEWAYS across the map, not just falling.
		emitter.Acceleration = windDirection * rng:NextNumber(6, 10) + Vector3.new(0, -2, 0)
		emitter.RotSpeed = NumberRange.new(-90, 90)
		emitter.Parent = anchor
	end
end

--[[
	Tundra-specific ground TERRAIN pattern - replaces the generic shared
	ring/spoke/medallion ground design (see Floor.lua's
	THEMES_WITH_OWN_GROUND_PATTERN) with genuine frozen-ground surface
	variation: uneven low snowbank mounds, scattered ice-chunk debris, and
	thin pale frost-crack seams in the ice sheet - not another recolored
	copy of the futuristic map's rings-and-spokes medallion. Kept low/flat
	enough everywhere that walking across the map is never obstructed.
]]
local function buildGroundPattern(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "IceAgeGroundPattern"
	folder.Parent = parent

	local rng = Random.new(881221)

	--[[
		SNOW-COVERED GROUND. A wide, very shallow sheet of overlapping snow
		patches laid across the whole walkable area, so the ground reads as
		SNOW rather than as a flat ice plate with a few mounds sitting on it.
		Each patch is a hair above the floor and only a few tenths thick, so
		it changes the surface's look without changing its height.
	]]
	local snowPatchRng = Random.new(305118)
	for i = 1, 90 do
		local angle = snowPatchRng:NextNumber(0, 2 * math.pi)
		-- sqrt keeps the scatter area-uniform instead of bunching at the middle
		local radius = math.sqrt(snowPatchRng:NextNumber(0, 1)) * MapConfig.USABLE_RADIUS * 0.99
		local center = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		PartUtils.CreateDisc({
			name = "SnowPatch" .. i,
			diameter = snowPatchRng:NextNumber(14, 32),
			thickness = snowPatchRng:NextNumber(0.15, 0.4),
			position = center + Vector3.new(0, 0.12, 0),
			material = Enum.Material.Snow,
			color = Color3.fromRGB(
				236 + snowPatchRng:NextInteger(-6, 6),
				243 + snowPatchRng:NextInteger(-4, 5),
				250 + snowPatchRng:NextInteger(-3, 3)
			),
			canCollide = false,
			parent = folder,
		})
	end

	--[[
		Irregular SNOW PILES - drifts with genuine (if slight) elevation.
		Each pile is a cluster of overlapping rounded lumps of varying size
		rather than one ball, so it reads as wind-heaped snow instead of a
		sphere half-sunk in the floor. Deliberately capped at ~2.5 studs so
		a player walks over them without the terrain fighting navigation.
	]]
	for i = 1, 16 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(MapConfig.USABLE_RADIUS * 0.12, MapConfig.USABLE_RADIUS * 0.95)
		local center = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		local pileSpread = rng:NextNumber(4, 9)
		local lumps = rng:NextInteger(3, 6)
		for l = 1, lumps do
			-- Lumps sit within the pile's own spread so they always overlap
			-- into one connected drift.
			local lumpAngle = rng:NextNumber(0, 2 * math.pi)
			local lumpDist = rng:NextNumber(0, pileSpread * 0.5)
			local lumpSize = rng:NextNumber(4, 10) * (1 - lumpDist / (pileSpread * 1.4))
			local height = math.min(2.5, lumpSize * rng:NextNumber(0.18, 0.3))
			PartUtils.CreatePart({
				name = ("SnowPile%d_%d"):format(i, l),
				size = Vector3.new(lumpSize, height, lumpSize * rng:NextNumber(0.85, 1.15)),
				position = center
					+ Vector3.new(math.sin(lumpAngle) * lumpDist, height * 0.22, math.cos(lumpAngle) * lumpDist),
				material = Enum.Material.Snow,
				color = Color3.fromRGB(234 + rng:NextInteger(-5, 6), 241 + rng:NextInteger(-4, 5), 249 + rng:NextInteger(-3, 3)),
				shape = Enum.PartType.Ball,
				canCollide = false,
				parent = folder,
			})
		end
	end

	-- Ice-chunk debris scattered across the ground.
	for i = 1, 16 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(MapConfig.USABLE_RADIUS * 0.1, MapConfig.USABLE_RADIUS * 0.95)
		local center = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		local chunkSize = rng:NextNumber(0.8, 1.8)
		PartUtils.CreatePart({
			name = "IceChunk" .. i,
			size = Vector3.new(chunkSize, chunkSize * 0.7, chunkSize),
			cframe = CFrame.new(center + Vector3.new(0, chunkSize * 0.25, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			material = Enum.Material.Ice,
			color = Color3.fromRGB(198, 220, 235),
			canCollide = false,
			parent = folder,
		})
	end

	-- Thin pale frost-crack seams in the ice sheet - distinct from Lava's
	-- glowing fissures, just subtle white surface cracking.
	for i = 1, 6 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(MapConfig.USABLE_RADIUS * 0.15, MapConfig.USABLE_RADIUS * 0.85)
		local center = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		local direction = rng:NextNumber(0, 2 * math.pi)
		local segCount = rng:NextInteger(2, 4)
		local cursor = center
		for s = 1, segCount do
			local segLength = rng:NextNumber(3, 7)
			direction += rng:NextNumber(-0.5, 0.5)
			local nextCursor = cursor + Vector3.new(math.sin(direction) * segLength, 0, math.cos(direction) * segLength)
			local midpoint = (cursor + nextCursor) / 2
			local yaw = math.atan2(nextCursor.X - cursor.X, nextCursor.Z - cursor.Z)
			PartUtils.CreatePart({
				name = ("FrostCrack%d_%d"):format(i, s),
				size = Vector3.new(0.3, 0.05, segLength),
				cframe = CFrame.new(midpoint + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, yaw, 0),
				material = Enum.Material.Ice,
				color = Color3.fromRGB(225, 238, 248),
				canCollide = false,
				parent = folder,
			})
			cursor = nextCursor
		end
	end
end

--[[
	Soft translucent aurora streaks arcing overhead, just below the
	ceiling cap - a handful of large, thin, gently curved Neon strips in
	green/violet, high transparency so they read as a magical glow rather
	than solid geometry.
]]
local function buildAuroraStreaks(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "AuroraStreaks"
	folder.Parent = parent

	local streakY = WALL_BOTTOM_Y + WALL_HEIGHT - 60
	local streaks = {
		{ color = Color3.fromRGB(120, 255, 190), yaw = 20, radius = 220 },
		{ color = Color3.fromRGB(170, 140, 255), yaw = 100, radius = 200 },
		{ color = Color3.fromRGB(120, 220, 255), yaw = 200, radius = 230 },
	}

	for i, streak in ipairs(streaks) do
		-- Approximate a gentle arc with several short segments (same
		-- "many short segments around a circle" technique Floor.lua's ring
		-- decorations already use), spanning a limited angular range
		-- rather than a full circle so it reads as a streak, not a halo.
		local segmentCount = 10
		local arcSpan = math.rad(70)
		local startAngle = math.rad(streak.yaw)
		for s = 0, segmentCount - 1 do
			local a1 = startAngle + (arcSpan / segmentCount) * s
			local a2 = startAngle + (arcSpan / segmentCount) * (s + 1)
			local p1 = Vector3.new(streak.radius * math.sin(a1), streakY, streak.radius * math.cos(a1))
			local p2 = Vector3.new(streak.radius * math.sin(a2), streakY + 8, streak.radius * math.cos(a2))
			local midpoint = (p1 + p2) / 2
			local direction = p2 - p1
			local segYaw = math.atan2(direction.X, direction.Z)

			PartUtils.CreatePart({
				name = ("AuroraStreak%dSegment%d"):format(i, s),
				size = Vector3.new(14, 0.4, direction.Magnitude),
				cframe = CFrame.new(midpoint) * CFrame.Angles(0, segYaw, 0),
				material = Enum.Material.Neon,
				color = streak.color,
				transparency = 0.65,
				canCollide = false,
				parent = folder,
			})
		end
	end
end

--[[
	Builds the full frozen backdrop under `parent` (the map's root
	Workspace folder), in a single "IceAgeEnvironment" folder - see
	LobbyBuilder/init.lua for the (Ice Age map-only) call site.
]]
--[[
	DISTANT MOUNTAIN RANGE.

	Huge snow-capped peaks ringing the map far outside the playable area -
	the Ice Age equivalent of the Lava map's DistantVolcanoes and the Space
	map's planets: pure backdrop that gives the horizon scale and tells you
	what world you are standing in.

	DELIBERATELY SEPARATE FROM buildFrozenPeaks. Those are the nearby
	foothills - ~99 studs tall, squat and rounded. These are 260-450 studs
	tall: the same ring of ground, but towering rather than rolling, so the
	horizon reads as a mountain range enclosing the arena.

	PLACED INSIDE THE ENCLOSURE, and this is not optional. The Ice Age map is
	a sealed opaque room - SkyWalls form a cylinder at radius 298 spanning
	Y -196..504 with Transparency 0, capped by SkyCeiling at Y 510. Anything
	beyond that radius is simply not visible from inside, however large. A
	first attempt put these at radius 520-900 like a real distant range and
	they were completely hidden behind the wall.

	So they sit at radius 258-292: outside MapConfig.USABLE_RADIUS (172) so
	they never intrude on the playable plaza, inside 298 so they are actually
	visible, and under the 504 wall top so they never clip through the sky.
	Base radius is capped at 72, which puts the nearest possible flank at
	258 - 72 = 186, comfortably clear of the 172 usable radius. An earlier
	235-290 / base-78 pass left 18 slabs poking into the plaza at player
	height - harmless, since they are non-collidable, but you could walk
	through a mountain, which looks broken.

	Built from stacked rings of slabs rather than one cone, so the silhouette
	has the broken, ridged look of real rock instead of a smooth pyramid.
	Each peak gets three bands - dark exposed rock at the base, blue glacial
	ice through the middle, and a bright snow cap on top, which is the
	single strongest "this is a big mountain" cue.

	Everything is CanCollide = false and CastShadow = false: it is beyond
	anywhere a player can stand, so collision would only cost physics memory,
	and shadows from geometry this large would fall across the whole map.
]]
--[==[ DEAD CODE - the part-based mountain builders, replaced by
	IceAgeEnvironment.BuildTerrainMountains further down.

	Removed rather than retuned because the TECHNIQUE was the problem: rings
	of slabs terrace vertically and facet horizontally however they are
	parameterised, so these could never stop reading as stacked geometry.
	They produced 12,594 parts for a result that still looked wrong.

	A leveled long-bracket is used because the block below contains its own
	long comments, and Lua long comments do not nest.

local function buildDistantMountain(position: Vector3, rng: Random, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	--[[
		REALISTIC PROPORTIONS.

		The previous pass made 260-450 stud peaks on a 45-72 stud base - a
		height:base-radius ratio of roughly 5:1. Nothing on Earth looks like
		that; it reads as a spike or a witch's hat, not a mountain.

		Real massifs are far wider than they are tall. Everest rises about
		3.7km from its base over a footprint roughly 10km across - a ratio
		nearer 0.7:1. These are built to that: a 150-260 stud base carrying a
		110-195 stud summit, so every peak is between two and three times wider
		than it is high.

		That single change is most of what makes them read as real. The rest is
		the profile exponent and the snow line below.
	]]
	local baseRadius = rng:NextNumber(150, 260)
	local peakHeight = baseRadius * rng:NextNumber(0.62, 0.82)
	local tipRadius = baseRadius * rng:NextNumber(0.05, 0.11)

	-- Rock, not ice, for the bulk: a mountain this size is exposed stone with
	-- snow only on its upper slopes. Solid ice flanks were part of why the
	-- last version read as fantasy rather than landscape.
	local ROCK_LOW = Color3.fromRGB(88, 92, 102) -- dark exposed stone at the foot
	local ROCK_HIGH = Color3.fromRGB(122, 126, 138) -- paler weathered rock higher up
	local SNOW_CAP = Color3.fromRGB(242, 248, 254)

	-- More tiers than before: the flanks are much wider now, so the same tier
	-- count would leave visibly stepped terraces.
	local tierCount = 30
	local OVERLAP = 1.9

	-- Per-mountain ridge pattern. Two offset sine waves around the compass
	-- give each peak its own set of spurs and gullies, so fourteen mountains
	-- built from one function don't look like fourteen copies.
	local ridgeCount = rng:NextInteger(3, 6)
	local ridgePhase = rng:NextNumber(0, math.pi * 2)
	local ridgeDepth = rng:NextNumber(0.06, 0.13)

	for tier = 0, tierCount do
		local t = tier / tierCount
		--[[
			^1.35 (was ^0.78) is the other half of the realism fix. An exponent
			below 1 gives a CONVEX flank that bulges outward and tapers late -
			a cone. Above 1 gives a CONCAVE flank: the radius falls away fast
			near the base and slowly near the summit, which is the swept, skirt
			like profile real mountains have where scree has piled at the foot.
		]]
		local ringRadius = math.max(tipRadius, baseRadius * (1 - t) ^ 1.35)
		-- ^0.85 lifts the lower tiers slightly, so height climbs quickly at
		-- first then eases toward the summit rather than rising linearly.
		local ringY = peakHeight * t ^ 0.85

		local nextT = math.min((tier + 1) / tierCount, 1)
		local nextRadius = math.max(tipRadius, baseRadius * (1 - nextT) ^ 1.35)
		local nextY = peakHeight * nextT ^ 0.85
		local slant = math.sqrt((ringRadius - nextRadius) ^ 2 + (nextY - ringY) ^ 2)

		local circumference = 2 * math.pi * ringRadius
		local segments = math.max(12, math.floor(circumference / 22))
		local arcSpacing = circumference / segments

		--[[
			Snow line, and it is a LINE rather than a fraction of each mountain.
			Snow settles above an altitude, not above a percentage - so on a
			range of mixed heights the shorter peaks should be bare or barely
			dusted while the tall ones carry a deep cap. Using absolute Y here
			is what produces that, and it is a strong cue that the peaks are
			different sizes rather than one shape scaled.
		]]
		local SNOW_LINE_Y = 96
		local isSnow = ringY > SNOW_LINE_Y

		for s = 1, segments do
			local angle = (2 * math.pi / segments) * s
			-- Ridges: pull the radius in and out around the compass, more
			-- strongly low down where spurs are widest.
			local ridge = math.sin(angle * ridgeCount + ridgePhase) * ridgeDepth * (1 - t)
			local jitter = rng:NextNumber(-arcSpacing * 0.12, arcSpacing * 0.12)
			local r = ringRadius * (1 + ridge) + jitter
			local shade = rng:NextNumber(-0.035, 0.035)

			local colour
			if isSnow then
				colour = SNOW_CAP
			else
				-- Blend the two rock tones by height so the flank lightens
				-- gradually instead of banding.
				colour = ROCK_LOW:Lerp(ROCK_HIGH, math.clamp(ringY / SNOW_LINE_Y, 0, 1))
			end

			PartUtils.CreatePart({
				name = ("%sSlab%d_%d"):format(name, tier, s),
				size = Vector3.new(arcSpacing * OVERLAP, math.max(slant * OVERLAP, 6), 12),
				cframe = CFrame.new(position + Vector3.new(math.sin(angle) * r, ringY, math.cos(angle) * r))
					* CFrame.Angles(0, angle, 0)
					* CFrame.Angles(math.atan2(ringRadius - nextRadius, math.max(nextY - ringY, 0.001)), 0, 0),
				material = if isSnow then Enum.Material.Snow else Enum.Material.Slate,
				color = Color3.new(
					math.clamp(colour.R + shade, 0, 1),
					math.clamp(colour.G + shade, 0, 1),
					math.clamp(colour.B + shade, 0, 1)
				),
				canCollide = false,
				castShadow = false,
				parent = model,
			})
		end
	end

	-- Summit cap. Snow only if this peak actually breaks the snow line -
	-- a short mountain gets a bare rock top, which is the payoff for using
	-- an absolute snow line above.
	PartUtils.CreatePart({
		name = name .. "Summit",
		shape = Enum.PartType.Ball,
		size = Vector3.new(tipRadius * 2.6, tipRadius * 2.2, tipRadius * 2.6),
		position = position + Vector3.new(0, peakHeight, 0),
		material = if peakHeight > 96 then Enum.Material.Snow else Enum.Material.Slate,
		color = if peakHeight > 96 then SNOW_CAP else ROCK_HIGH,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
end

local function buildDistantMountains(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "DistantMountains"
	folder.Parent = parent

	local rng = Random.new(881423)
	local count = 16
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2 + rng:NextNumber(-0.22, 0.22)
		-- Room for a 150-260 stud base: 470 - 260 = 210, clear of the plaza
		-- (USABLE_RADIUS 172), while 680 + 260 = 940 stays inside the 1000
		-- stud enclosure wall.
		local radius = rng:NextNumber(470, 680)
		-- Sunk so the base is buried and the peak rises from the horizon
		-- rather than sitting on the floor like a prop.
		local position = Vector3.new(math.sin(angle) * radius, -30, math.cos(angle) * radius)
		buildDistantMountain(position, rng, folder, "Everest" .. i)
	end
end
]==]

--[[
	SHEET ICE.

	Flat frozen patches scattered across the plaza floor - slightly raised,
	translucent slabs with a paler cracked rim, as though meltwater has
	pooled and refrozen.

	Purely decorative: CanCollide = false and only ~0.3 studs proud of the
	floor, so they never trip a player or change where anyone can walk.

	Placement avoids the two things that would make them a nuisance: the map
	centre (the queue portal plaza, kept clear so the portal stays readable)
	and a radius around each building entrance, so no sheet lies across a
	doorway approach. Sizes vary widely so the map does not look stamped with
	identical discs.
]]
local function buildIceSheets(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "IceSheets"
	folder.Parent = parent

	local rng = Random.new(553019)

	local INNER = 34 -- keep the portal plaza clear
	local OUTER = MapConfig.USABLE_RADIUS * 0.95
	local BUILDING_CLEARANCE = 34

	local SHEET_COLOR = Color3.fromRGB(196, 226, 242)
	local RIM_COLOR = Color3.fromRGB(224, 240, 250)

	local placed = 0
	local attempts = 0
	while placed < 22 and attempts < 400 do
		attempts += 1
		local angle = rng:NextNumber(0, 2 * math.pi)
		-- sqrt keeps the scatter even by AREA rather than clumping at the centre
		local radius = INNER + (OUTER - INNER) * math.sqrt(rng:NextNumber())
		local pos = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)

		-- Reject anything landing near a building.
		local tooClose = false
		for _, def in ipairs(LobbyConfig.BUILDINGS) do
			if (Vector3.new(def.position.X, 0, def.position.Z) - pos).Magnitude < BUILDING_CLEARANCE then
				tooClose = true
				break
			end
		end
		if not tooClose then
			placed += 1
			local diameter = rng:NextNumber(14, 42)

			-- Main sheet: a thin translucent disc lying flush on the floor.
			PartUtils.CreateDisc({
				name = ("IceSheet%d"):format(placed),
				diameter = diameter,
				thickness = 0.3,
				position = pos + Vector3.new(0, 0.15, 0),
				material = Enum.Material.Ice,
				color = SHEET_COLOR,
				transparency = 0.35,
				canCollide = false,
				castShadow = false,
				parent = folder,
			})

			-- Broken rim: a few small slabs around the edge so the sheet has a
			-- cracked border rather than a machined circular edge.
			local shards = math.max(5, math.floor(diameter / 3))
			for s = 1, shards do
				local a = (2 * math.pi / shards) * s + rng:NextNumber(-0.15, 0.15)
				local rr = diameter / 2 * rng:NextNumber(0.9, 1.05)
				PartUtils.CreatePart({
					name = ("IceSheet%dShard%d"):format(placed, s),
					size = Vector3.new(rng:NextNumber(2.5, 5.5), 0.45, rng:NextNumber(1.6, 3.2)),
					cframe = CFrame.new(pos + Vector3.new(math.sin(a) * rr, 0.22, math.cos(a) * rr))
						* CFrame.Angles(0, a, 0)
						* CFrame.Angles(math.rad(rng:NextNumber(-4, 4)), 0, 0),
					material = Enum.Material.Ice,
					color = RIM_COLOR,
					transparency = 0.2,
					canCollide = false,
					castShadow = false,
					parent = folder,
				})
			end
		end
	end
end

--[[
	TERRAIN MOUNTAIN RANGE (Rockies / Himalaya).

	WHY TERRAIN AND NOT PARTS. Every previous attempt built these from rings
	of slabs - a stack of tiers, each a ring of overlapping boxes. That
	technique cannot look like a mountain, for two structural reasons:

	  1. TERRACING. Each tier is a constant height, so the flank climbs in
	     visible steps. Adding tiers shrinks the steps but never removes them.
	  2. FACETING. Each tier is a polygon, not a circle, so the silhouette is
	     a ring of flat panels catching light at different angles.

	Roblox Terrain has neither problem: it is a smoothed voxel field, so the
	surface is continuous in every direction and the engine shades it as one
	mass. It also gets proper Rock and Snow material treatment for free.

	SHAPE COMES FROM RIDGE NOISE, not from a profile curve. A radial profile
	- any f(distance-from-centre) - can only ever make a cone, however it is
	tuned. Real ranges are ridges and valleys: long spurs running down from a
	crest, with gullies between them. That is what ridged fractal noise
	produces (see ridgedNoise below), and it is the single biggest reason
	this reads as landscape rather than as a pile of geometry.

	WORLD SPACE, ON PURPOSE. Terrain is not a BasePart, so LobbyBuilder's
	applyMapTransform - which shifts each BasePart's .Position after the
	build - cannot move it. This function therefore takes the FINAL world
	origin and is called after that transform, rather than building at the
	local origin like everything else in this module.
]]

-- Voxel resolution. 4 is Terrain's native grid; anything else is silently
-- rounded, so writing at 4 avoids resampling artefacts.
local TERRAIN_RES = 4

-- The annulus the range occupies, measured from the map centre.
--[[
	TUNED AFTER LOOKING AT IT. The first pass used 250 / 600 / 985 with a
	snow line at 118, and two things were wrong:

	  - The inner edge at 250 is only ~80 studs beyond the plaza, so the near
	    flank rose steeply right at the map edge and filled the lower half of
	    the view as a grey wall. Pushing it to 330 puts the rise far enough
	    back that you see the RANGE rather than the slope in front of it.
	  - A snow line of 118 against peaks averaging ~230 left most of the
	    visible surface bare grey rock, which reads as a quarry. Real high
	    ranges are snow-dominant well down their flanks; 68 puts the snow
	    line low enough that ridges read white with rock showing through on
	    the steepest faces, which is the Himalaya/Rockies look.
]]
--[[
	SNOW APRON.

	Fixes a visible hole in the map: LobbyGround is a cylinder of radius 193
	with its top at Y=4, and the mountain range does not begin until
	RANGE_INNER (330). Between the two there was NO surface at all, so from
	the plaza edge you looked 26 studs down onto raw MapBaseplate - a grey
	slab, obviously not part of the world.

	Filled with terrain rather than a part disc for two reasons: it joins the
	existing mountain terrain as one continuous smoothed surface with no seam,
	and it takes the same Snow material, so apron and lower slopes are visibly
	the same ground.

	APRON_INNER STARTS OUTSIDE THE PLAZA. This was first set to 178 - inside
	LobbyGround's 193 radius - on the theory that tucking the terrain under
	the plaza rim would avoid a hairline crack. It did, but it also pushed
	snow up onto the MathArena circle itself, which is far worse than a crack:
	the arena floor is meant to be clean. 196 keeps every voxel outside the
	plaza, and PLAZA_CLEAR_RADIUS below guarantees it.
]]
local APRON_INNER = 196
local PLAZA_CLEAR_RADIUS = 190 -- inside LobbyGround's 193 so the clear cannot eat the apron's inner edge
--[[
	APRON_HEIGHT = 3, not 0.

	Terrain heights here are measured RELATIVE TO worldOrigin.Y, and
	worldOrigin is MapCenter, already at world Y=4 - the same height as
	LobbyGround's top. So 0 means "exactly level with the plaza floor".

	That sounds right and is wrong in practice: at height 0 the surface voxel
	gets occupancy 0, and wherever the drift noise bottomed out the column
	produced no solid voxel at all - measured as a patchy snowfield with only
	3 to 8 of 12 bearings covered, baseplate showing through the gaps.

	3 lifts the whole apron clear of that boundary so every column is solidly
	filled. It also reads correctly: snow banks UP outside a cleared arena,
	so a few studs of lip at the rim is what you would actually see.
]]
local APRON_HEIGHT = 3

local RANGE_INNER = 330 -- clear of the plaza (USABLE_RADIUS 172) with breathing room
local RANGE_CREST = 700 -- where peaks are tallest
local RANGE_OUTER = 985 -- just inside the 1000-stud enclosure wall

local PEAK_HEIGHT = 340 -- tallest summit above ground level
local SNOW_LINE = 68 -- absolute height above ground where snow begins

--[[
	Ridged fractal noise in 0..1.

	`1 - |noise|` folds the noise field at zero, turning smooth hills into
	sharp CRESTS - the fold line becomes a ridge. Squaring sharpens them
	further and pushes the valleys flatter, which is what gives a range its
	characteristic knife-edge spurs with broad basins between.

	Octaves are summed at halving amplitude and doubling frequency, so each
	adds finer detail without changing the overall silhouette.
]]
local function ridgedNoise(x: number, z: number, frequency: number, octaves: number): number
	local sum, amplitude, norm = 0, 1, 0
	local f = frequency
	for _ = 1, octaves do
		local n = math.noise(x * f, z * f, 0)
		n = 1 - math.abs(n)
		n = n * n
		sum += n * amplitude
		norm += amplitude
		amplitude *= 0.5
		f *= 2
	end
	return sum / norm
end

-- Smooth 0..1 ramp; cheaper than a full smoothstep and enough here.
local function smoothRamp(edge0: number, edge1: number, value: number): number
	local t = math.clamp((value - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

--[[
	Height of the range at a point, in studs above ground level.
	Returns 0 inside the plaza and outside the wall, so terrain only ever
	exists in the annulus.
]]
function mountainHeight(localX: number, localZ: number): number
	local dist = math.sqrt(localX * localX + localZ * localZ)
	if dist < APRON_INNER or dist > RANGE_OUTER then
		return 0
	end

	--[[
		APRON ZONE: the flat snowfield between the plaza and the foothills.

		Held at APRON_HEIGHT so it sits level with the plaza floor, with a
		couple of studs of drift so it is not a machined plane, easing upward
		over the last 30 studs so it rises INTO the foothills rather than
		meeting them at a step.
	]]
	if dist < RANGE_INNER then
		--[[
			Drift is faded in over the first 40 studs of the apron, so the snow
			leaves the plaza edge FLUSH and only banks up further out. Without
			this the noise put up to 3 studs of snow hard against the arena rim,
			which read as a lip around the circle.
		]]
		local edgeFade = smoothRamp(APRON_INNER, APRON_INNER + 40, dist)
		local drift = (math.noise(localX * 0.012, localZ * 0.012, 29) * 0.5 + 0.5) * 3 * edgeFade
		local blend = smoothRamp(RANGE_INNER - 30, RANGE_INNER, dist)
		return APRON_HEIGHT + drift + blend * 6
	end

	-- Envelope: rises from nothing at the inner edge, peaks at the crest,
	-- falls back to nothing at the outer edge. Without this the range would
	-- either spill onto the plaza or clip through the sky wall.
	local envelope
	if dist < RANGE_CREST then
		envelope = smoothRamp(RANGE_INNER, RANGE_CREST, dist)
	else
		envelope = 1 - smoothRamp(RANGE_CREST, RANGE_OUTER, dist)
	end

	-- Ridged detail: the actual mountain shape.
	local ridges = ridgedNoise(localX, localZ, 0.0016, 5)

	-- Very low-frequency mass variation, so the range has genuinely big
	-- massifs and genuinely low saddles rather than uniform peaks. Without
	-- this every summit tops out at the same height and it reads as a wall.
	local massif = 0.45 + 0.75 * ((math.noise(localX * 0.0006, localZ * 0.0006, 7) + 1) * 0.5)

	return PEAK_HEIGHT * envelope * ridges * massif
end

--[[
	Writes the range into Terrain around `worldOrigin`.

	Written in TILES rather than one call: Terrain:WriteVoxels is capped at a
	few million voxels per call, and the full 2000x2000x420 stud region is far
	beyond that. Tiles whose entire footprint lies outside the annulus are
	skipped, which removes roughly half the work.
]]
function IceAgeEnvironment.BuildTerrainMountains(worldOrigin: Vector3)
	local Terrain = workspace.Terrain

	local TILE = 128 -- studs per tile edge (32 voxels at res 4)
	local FLOOR_Y = -120 -- terrain base, buried below the map floor
	local TOP_Y = PEAK_HEIGHT + 40

	-- Clear any previous range so this is safe to re-run.
	local clearRegion = Region3.new(
		worldOrigin + Vector3.new(-RANGE_OUTER - TILE, FLOOR_Y - TILE, -RANGE_OUTER - TILE),
		worldOrigin + Vector3.new(RANGE_OUTER + TILE, TOP_Y + TILE, RANGE_OUTER + TILE)
	):ExpandToGrid(TERRAIN_RES)
	Terrain:FillRegion(clearRegion, TERRAIN_RES, Enum.Material.Air)

	local voxelsY = math.floor((TOP_Y - FLOOR_Y) / TERRAIN_RES)
	local tilesWritten, voxelsWritten = 0, 0

	for tileX = -RANGE_OUTER, RANGE_OUTER - 1, TILE do
		for tileZ = -RANGE_OUTER, RANGE_OUTER - 1, TILE do
			-- Skip tiles entirely inside the plaza or entirely beyond the wall.
			-- Corner distances bound the tile, so this is exact, not a guess.
			local cx, cz = tileX + TILE / 2, tileZ + TILE / 2
			local centreDist = math.sqrt(cx * cx + cz * cz)
			local halfDiag = TILE * 0.7072
			-- APRON_INNER, not RANGE_INNER: the tile scan has to reach inward to
			-- the plaza edge now that the apron fills that ring too.
			if centreDist + halfDiag >= APRON_INNER and centreDist - halfDiag <= RANGE_OUTER then
				--[[
					Build the region FIRST and derive the array dimensions from it,
					rather than assuming TILE/RES.

					Region3:ExpandToGrid snaps outward to the 4-stud voxel grid, and
					the map origin is not grid-aligned (Z = 1050 is 262.5 voxels), so
					the snapped region is one voxel larger on each unaligned axis than
					the nominal tile. Assuming 32x32 produced a
					"33x116x33 array expected" error from WriteVoxels.

					Reading the size back off the expanded region makes this correct
					for any origin, aligned or not.
				]]
				local region = Region3.new(
					worldOrigin + Vector3.new(tileX, FLOOR_Y, tileZ),
					worldOrigin + Vector3.new(tileX + TILE, FLOOR_Y + voxelsY * TERRAIN_RES, tileZ + TILE)
				):ExpandToGrid(TERRAIN_RES)

				local regionSize = region.Size
				local sizeX = math.floor(regionSize.X / TERRAIN_RES + 0.5)
				local sizeY = math.floor(regionSize.Y / TERRAIN_RES + 0.5)
				local sizeZ = math.floor(regionSize.Z / TERRAIN_RES + 0.5)
				-- Bottom-left-front corner of the region, in world space.
				local corner = region.CFrame.Position - regionSize / 2

				local materials = {}
				local occupancies = {}

				--[[
					Precompute the height and SLOPE of each column before filling
					voxels. Two reasons:

					1. SPEED. mountainHeight runs 5 octaves of noise; calling it
					   inside the Y loop evaluated it ~115 times per column for an
					   answer that does not depend on Y at all.
					2. SLOPE-BASED MATERIALS. Snow lies where it can settle and
					   slides off where it cannot, so on a real mountain the rock
					   shows through on the STEEP faces while gentle ground stays
					   white - regardless of altitude. Choosing material by height
					   alone gave a wide grey band low down and a white cap above,
					   which reads as a quarry with a hat on.

					Slope is the gradient magnitude from the four neighbouring
					samples, one voxel out in each direction.
				]]
				local colHeight, colSlope = {}, {}
				for ix = 1, sizeX do
					colHeight[ix], colSlope[ix] = {}, {}
					local lx = corner.X + (ix - 0.5) * TERRAIN_RES - worldOrigin.X
					for iz = 1, sizeZ do
						local lz = corner.Z + (iz - 0.5) * TERRAIN_RES - worldOrigin.Z
						local h = mountainHeight(lx, lz)
						colHeight[ix][iz] = h

						local dx = mountainHeight(lx + TERRAIN_RES, lz) - mountainHeight(lx - TERRAIN_RES, lz)
						local dz = mountainHeight(lx, lz + TERRAIN_RES) - mountainHeight(lx, lz - TERRAIN_RES)
						-- Rise over the 2-voxel run the differences span.
						colSlope[ix][iz] = math.sqrt(dx * dx + dz * dz) / (2 * TERRAIN_RES)
					end
				end

				for ix = 1, sizeX do
					materials[ix] = {}
					occupancies[ix] = {}
					local lx = corner.X + (ix - 0.5) * TERRAIN_RES - worldOrigin.X

					for iy = 1, sizeY do
						materials[ix][iy] = {}
						occupancies[ix][iy] = {}
						local voxelBottom = corner.Y + (iy - 1) * TERRAIN_RES - worldOrigin.Y

						for iz = 1, sizeZ do
							local lz = corner.Z + (iz - 0.5) * TERRAIN_RES - worldOrigin.Z
							local height = colHeight[ix][iz]

							-- Partial occupancy on the surface voxel is what makes
							-- Terrain render a smooth slope instead of a staircase.
							local fill = math.clamp((height - voxelBottom) / TERRAIN_RES, 0, 1)

							local material = Enum.Material.Air
							if fill > 0 then
								local slope = colSlope[ix][iz]
								-- Ragged edges rather than clean contour rings.
								local jitter = math.noise(lx * 0.012, lz * 0.012, 3) * 0.16

								-- Deep buried rock: never seen, but keeps the core
								-- from being a solid block of Snow.
								if voxelBottom < -20 then
									material = Enum.Material.Slate
								elseif slope + jitter > 0.92 then
									-- Cliff face: too steep to hold snow.
									material = Enum.Material.Slate
								elseif slope + jitter > 0.62 then
									-- Broken rock and scree on the steeper flanks.
									material = Enum.Material.Rock
								else
									-- Everything gentle enough to hold snow does.
									material = Enum.Material.Snow
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

	--[[
		KEEP THE ARENA CIRCLE CLEAR.

		Run AFTER the write loop, deliberately. Placed before it, the tiles
		would simply fill the plaza back in and this would guarantee nothing.

		APRON_INNER (196) already puts every apron voxel outside LobbyGround's
		193-stud radius, but voxel writes snap outward to the 4-stud grid, so a
		boundary voxel can still bleed a stud or two inside. This carves the
		plaza cylinder back out as a guarantee rather than a hope.

		It also removes snow left over from an earlier build that used a smaller
		APRON_INNER, so re-running this function is enough to clean up a map
		that already has snow on the arena floor.

		FillCylinder (not FillRegion) because the plaza is round - a box clear
		would bite square corners out of the surrounding snowfield.

		NO ROTATION ON THE CFRAME. FillCylinder extends the cylinder along its
		CFrame's UP axis, so an unrotated CFrame already gives a vertical
		column. An earlier version passed CFrame.Angles(0, 0, rad(90)) - copied
		from the pattern used for cylinder PARTS, which do lie along X - and
		that laid the clear on its side, carving a horizontal tube straight
		through the snowfield. The symptom was gaps in the snow on some
		bearings and leftover snow inside the arena on others.
	]]
	Terrain:FillCylinder(
		CFrame.new(worldOrigin),
		(TOP_Y - FLOOR_Y) + 200, -- height: well clear above and below
		PLAZA_CLEAR_RADIUS,
		Enum.Material.Air
	)

	return tilesWritten, voxelsWritten
end

function IceAgeEnvironment.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "IceAgeEnvironment"
	folder.Parent = parent

	buildWallSegments(folder)
	buildCeiling(folder)
	buildFloor(folder)
	buildSnowfall(folder)
	buildFrozenPeaks(folder)
	-- NOTE: the mountain range is NOT built here. It is Terrain, which cannot
	-- be translated by applyMapTransform, so LobbyBuilder calls
	-- IceAgeEnvironment.BuildTerrainMountains(worldOrigin) after the
	-- transform instead.
	buildIceSheets(folder)
	buildSnowflakeWind(folder)
	buildGroundPattern(folder)
	buildAuroraStreaks(folder)

	return folder
end

--[[
	GROUND-TRUTH FINAL PASS for FrozenPeaks, called by LobbyBuilder AFTER
	BuildTerrainMountains has actually written the range/apron into Terrain.

	buildFrozenPeaks already places each peak using mountainHeight(x, z) plus
	a measure-then-correct pass against its OWN built geometry (see that
	function's doc comment) - that gets every peak within roughly a stud or
	two of the real surface, but not exactly onto it: Terrain's rendered
	surface does not sit exactly at the analytic height sampled during the
	build - it bulges upward by roughly half a voxel (TERRAIN_RES is 4, so up
	to ~2 studs) depending on neighbouring voxel occupancy, and that bulge is
	not practically predictable from mountainHeight() alone.

	Raycasting the ACTUAL Terrain (which does not exist yet when
	buildFrozenPeaks runs, only after this later call) removes that
	uncertainty entirely: whatever the true rendered surface turns out to be,
	each peak is shifted to sit CLEARANCE studs above it, guaranteeing no
	part of any peak overlaps the snow, regardless of any analytic
	approximation error upstream.
]]
function IceAgeEnvironment.SnapFrozenPeaksToTerrain(frozenPeaksFolder: Instance)
	local CLEARANCE = 1.5
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { workspace.Terrain }

	for _, model in ipairs(frozenPeaksFolder:GetChildren()) do
		if model:IsA("Model") then
			local cf, size = model:GetBoundingBox()
			local actualBottom = cf.Position.Y - size.Y / 2

			--[[
				Sample terrain across the model's WHOLE footprint, not just its
				centre point. A peak's base spans up to ~60 studs (baseRadius
				20-30 doubled by the skirt), and apron height genuinely varies
				across that span (radial blend plus per-point noise drift) - a
				single centre raycast can miss a locally higher patch of terrain
				under an outlying shingle, leaving that one part dipping into the
				snow even though the model's centre clears it fine. Sampling a
				ring plus the centre and taking the HIGHEST point found is what
				actually guarantees the whole footprint clears, not just one spot
				in it.
			]]
			local footprintRadius = math.sqrt((size.X / 2) ^ 2 + (size.Z / 2) ^ 2) -- circumscribes the rectangular bbox, not just its shorter half-width
			local highestTerrainY = -math.huge
			local sampleOffsets = { Vector3.new(0, 0, 0) }
			-- Three concentric rings (not one) at 12 angles each: a single ring
			-- missed a dip on FrozenPeak7 during testing - the footprint is an
			-- irregular jittered blob, not a clean disc, so bumps can sit at any
			-- radius fraction, not just the outer edge.
			for _, radiusFraction in ipairs({ 0.35, 0.7, 1.0 }) do
				for a = 0, 330, 30 do
					local rad = math.rad(a)
					local r = footprintRadius * radiusFraction
					table.insert(sampleOffsets, Vector3.new(math.sin(rad) * r, 0, math.cos(rad) * r))
				end
			end

			for _, offset in ipairs(sampleOffsets) do
				local sampleX, sampleZ = cf.Position.X + offset.X, cf.Position.Z + offset.Z
				local hit = workspace:Raycast(
					Vector3.new(sampleX, cf.Position.Y + 400, sampleZ),
					Vector3.new(0, -800, 0),
					rayParams
				)
				if hit and hit.Position.Y > highestTerrainY then
					highestTerrainY = hit.Position.Y
				end
			end

			if highestTerrainY > -math.huge then
				local correction = (highestTerrainY + CLEARANCE) - actualBottom
				model:PivotTo(model:GetPivot() + Vector3.new(0, correction, 0))
			end
		end
	end
end

return IceAgeEnvironment
