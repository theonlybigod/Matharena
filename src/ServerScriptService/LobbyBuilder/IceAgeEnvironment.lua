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

local IceAgeEnvironment = {}

local ENCLOSURE_RADIUS = 300
local WALL_SEGMENTS = 28
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
	local count = 16
	for i = 1, count do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(20, MapConfig.USABLE_RADIUS * 0.98)
		local position = Vector3.new(math.sin(angle) * radius, WALL_HEIGHT * 0.35, math.cos(angle) * radius)

		local anchor = PartUtils.CreatePart({
			name = "SnowAnchor" .. i,
			size = Vector3.new(1, 1, 1),
			position = position,
			transparency = 1,
			canCollide = false,
			parent = folder,
		}) :: BasePart

		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 0.6),
		})
		emitter.Size = NumberSequence.new(0.3)
		emitter.Lifetime = NumberRange.new(6, 9)
		emitter.Speed = NumberRange.new(2, 4)
		emitter.Rate = 6
		emitter.SpreadAngle = Vector2.new(25, 25)
		emitter.Acceleration = Vector3.new(0, -6, 0) -- snow drifts gently down
		emitter.Parent = anchor
	end
end

local function slopeCFrame(position: Vector3, angle: number, pitch: number): CFrame
	return CFrame.new(position) * CFrame.Angles(0, angle, 0) * CFrame.Angles(pitch, 0, 0)
end

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
local function buildFrozenPeak(position: Vector3, rng: Random, parent: Instance, name: string)
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
end

local function buildFrozenPeaks(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "FrozenPeaks"
	folder.Parent = parent

	local rng = Random.new(619204)
	local count = 8
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local radius = rng:NextNumber(ENCLOSURE_RADIUS * 0.7, ENCLOSURE_RADIUS * 0.92)
		local position = Vector3.new(math.sin(angle) * radius, -20, math.cos(angle) * radius)
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
function IceAgeEnvironment.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "IceAgeEnvironment"
	folder.Parent = parent

	buildWallSegments(folder)
	buildCeiling(folder)
	buildFloor(folder)
	buildSnowfall(folder)
	buildFrozenPeaks(folder)
	buildSnowflakeWind(folder)
	buildGroundPattern(folder)
	buildAuroraStreaks(folder)

	return folder
end

return IceAgeEnvironment
