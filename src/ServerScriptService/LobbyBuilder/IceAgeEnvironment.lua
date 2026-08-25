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

--[[
	One "pillar" landmark near the boundary: NOT a clean two-wedge peak
	anymore - a genuinely irregular ice/rock formation assembled from many
	overlapping chunks (mixed Ice/Rock materials, varied size/rotation/
	offset, stacked into rings that narrow and rise - same technique
	LavaEnvironment's pillars use, reinterpreted in frost tones), with a
	snow-accumulation cap at the top and a handful of hanging icicles
	along its own edges.
]]
local function buildFrozenPeak(position: Vector3, rng: Random, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local baseRadius = rng:NextNumber(16, 26)
	local peakHeight = rng:NextNumber(55, 100)

	local ringCount = 5
	for ring = 1, ringCount do
		local ringFraction = (ring - 1) / (ringCount - 1)
		local ringRadius = baseRadius * (1 - ringFraction * 0.8)
		local ringY = peakHeight * ringFraction * 0.9
		local chunkCount = math.floor(8 - ringFraction * 4)
		for c = 1, chunkCount do
			local angle = (2 * math.pi / chunkCount) * c + rng:NextNumber(-0.3, 0.3)
			local chunkRadius = ringRadius * rng:NextNumber(0.8, 1.1)
			local chunkSize = rng:NextNumber(7, 13) * (1 - ringFraction * 0.3)
			local chunkPos = position
				+ Vector3.new(math.sin(angle) * chunkRadius, ringY + rng:NextNumber(-2, 2), math.cos(angle) * chunkRadius)
			local useRock = rng:NextNumber() < 0.35
			PartUtils.CreatePart({
				name = ("PeakChunkR%dC%d"):format(ring, c),
				size = Vector3.new(chunkSize, chunkSize * rng:NextNumber(0.75, 1.2), chunkSize * rng:NextNumber(0.75, 1.2)),
				cframe = CFrame.new(chunkPos) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3)),
				material = if useRock then Enum.Material.Rock else Enum.Material.Ice,
				color = if useRock
					then Color3.fromRGB(88, 94, 100)
					else Color3.fromRGB(200 + rng:NextInteger(-8, 10), 216 + rng:NextInteger(-6, 8), 232 + rng:NextInteger(-4, 6)),
				canCollide = false,
				parent = model,
			})
		end
	end

	-- Snow-accumulation cap at the very top.
	PartUtils.CreatePart({
		name = "SnowCap",
		size = Vector3.new(baseRadius * 0.5, baseRadius * 0.28, baseRadius * 0.5),
		position = position + Vector3.new(0, peakHeight * 0.92, 0),
		material = Enum.Material.Snow,
		color = Color3.fromRGB(240, 246, 251),
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})

	-- A handful of hanging icicles along the formation's own edges (this
	-- is the "pillars" icicle treatment - not the removed map-wide
	-- floating clusters).
	for i = 1, rng:NextInteger(3, 5) do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local icicleRadius = baseRadius * rng:NextNumber(0.5, 0.95)
		local icicleHeight = peakHeight * rng:NextNumber(0.2, 0.6)
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
	local count = 20
	local windAngle = rng:NextNumber(0, 2 * math.pi)
	local windDirection = Vector3.new(math.sin(windAngle), 0, math.cos(windAngle))

	for i = 1, count do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(10, MapConfig.USABLE_RADIUS)
		local height = rng:NextNumber(8, 90)
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
		emitter.Size = NumberSequence.new(0.15)
		emitter.Lifetime = NumberRange.new(8, 14)
		emitter.Speed = NumberRange.new(4, 9)
		emitter.Rate = 14
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

	-- Uneven snowbank mounds - low wide drifts breaking up the flat ice
	-- sheet.
	for i = 1, 12 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(MapConfig.USABLE_RADIUS * 0.1, MapConfig.USABLE_RADIUS * 0.95)
		local center = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		PartUtils.CreatePart({
			name = "SnowbankMound" .. i,
			size = Vector3.new(rng:NextNumber(4, 9), rng:NextNumber(0.6, 1.4), rng:NextNumber(4, 9)),
			position = center + Vector3.new(0, 0.3, 0),
			material = Enum.Material.Snow,
			color = Color3.fromRGB(232, 240, 248),
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = folder,
		})
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
