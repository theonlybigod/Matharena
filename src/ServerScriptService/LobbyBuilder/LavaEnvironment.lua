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

--[[
	MOLTEN LAVA APPEARANCE - one definition used by every lava surface on
	this map (volcano flows, ground fissures, pools, vents, crater).

	Previously each site picked its own colour and used
	Enum.Material.CrackedLava, which renders as a dark crusted rock with
	dull embers - it read as scorched stone rather than as molten lava, and
	against the near-black basalt floor it barely registered. Lava is now a
	bright orange NEON so it self-illuminates and reads as genuinely molten.

	LAVA_CORE is the hot centre of a flow; LAVA_EDGE is the slightly deeper
	orange used at the cooling rim so a stream still has some internal
	shading rather than being one flat block of colour. The neon is kept a
	touch below pure white-hot so it stays legible instead of blooming out
	(LobbyBloom's threshold is 1.6 - see LobbyLighting).
]]
local LAVA_MATERIAL = Enum.Material.Neon
-- Neon renders considerably brighter than its raw colour, and LobbyBloom
-- picks up anything past threshold 1.6 - so these are deliberately pitched
-- BELOW the orange we actually want on screen. Set any higher (the first
-- pass used 255,138,26) and the bloom washes the flows out to flat yellow,
-- losing both the colour and the internal shading.
local LAVA_CORE = Color3.fromRGB(214, 88, 12)
local LAVA_EDGE = Color3.fromRGB(168, 48, 8)
local GLOW_COLOR = LAVA_CORE

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
				material = LAVA_MATERIAL,
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

--[[
	Finds the volcano's REAL, as-built surface at a given angle and height
	by raycasting inward toward its axis, instead of trusting the idealised
	cone formula.

	Why this exists: the flank is tiled from slabs that carry deliberate
	positional jitter, so the mathematical cone is only approximately where
	the rock actually ended up. Surface decorations (vents, lava channels)
	positioned from the formula could therefore land a stud or two off the
	real rock face and hang in mid-air - which is precisely the floating-
	geometry defect this pass is eliminating. Snapping them to an actual
	raycast hit against the already-built shell guarantees they sit on the
	geometry that exists rather than the geometry that was intended.

	Returns nil if the ray misses entirely (caller simply skips that piece).
]]
local function surfaceHit(model: Instance, origin: Vector3, angle: number, y: number, searchRadius: number): RaycastResult?
	local from = origin + Vector3.new(math.sin(angle) * searchRadius, y, math.cos(angle) * searchRadius)
	local toward = origin + Vector3.new(0, y, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	return workspace:Raycast(from, toward - from, params)
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
	--[[
		Tier count raised, and every dimension is now DERIVED from the
		tier's own spacing instead of being chosen independently of it.
		Previously the +/-1.5 stud radial and +/-2 stud vertical jitter was
		applied to shingles only 2.5-4.5 studs thick, so individual slabs
		popped clear of the surface and opened seams at close range. Jitter
		is now expressed as a fraction of the guaranteed overlap margin, so
		it can still roughen the surface but can never break it.
	]]
	local tierCount = 14
	local SHINGLE_OVERLAP = 1.9
	for tier = 0, tierCount do
		local t = tier / tierCount
		local ringRadius = math.max(craterRadius, baseRadius * (1 - t) ^ 0.9)
		local ringY = peakHeight * t ^ 1.05
		-- Slant distance to the next tier, so consecutive tiers overlap
		-- along the slope no matter how fast the radius is shrinking.
		local nextT = math.min((tier + 1) / tierCount, 1)
		local nextRadius = math.max(craterRadius, baseRadius * (1 - nextT) ^ 0.9)
		local nextY = peakHeight * nextT ^ 1.05
		local slant = math.max(
			math.sqrt((ringRadius - nextRadius) ^ 2 + (ringY - nextY) ^ 2),
			baseRadius / tierCount
		)
		local shingleLength = slant * SHINGLE_OVERLAP

		local circumference = 2 * math.pi * ringRadius
		local shingleCount = math.max(10, math.ceil(circumference / math.max(ringRadius * 0.45, 7)))
		local arcSpacing = circumference / shingleCount
		local shingleWidth = arcSpacing * SHINGLE_OVERLAP
		local overlapMargin = (shingleWidth - arcSpacing) / 2

		for c = 1, shingleCount do
			local angle = (2 * math.pi / shingleCount) * c
			local jitterRadius = ringRadius + rng:NextNumber(-overlapMargin * 0.4, overlapMargin * 0.4)
			local jitterY = ringY + rng:NextNumber(-slant * 0.15, slant * 0.15)
			local shinglePos = position + Vector3.new(math.sin(angle) * jitterRadius, jitterY, math.cos(angle) * jitterRadius)
			PartUtils.CreatePart({
				name = ("ShingleT%dC%d"):format(tier, c),
				size = Vector3.new(shingleWidth, rng:NextNumber(3.5, 5.5), shingleLength),
				cframe = slopeCFrame(shinglePos, angle, shinglePitch + math.rad(rng:NextNumber(-3, 3))),
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
		material = LAVA_MATERIAL,
		color = GLOW_COLOR,
		canCollide = false,
		parent = model,
	})

	--[[
		Lava channels running down the REAL rock face. Each channel is a
		chain of short segments, and every segment is snapped onto the
		as-built surface by raycast (see surfaceHit above) and then sunk
		slightly along that surface's own normal - so the molten rock is
		cut INTO the flank rather than laid over an idealised cone the
		jittered slabs never exactly matched.
	]]
	local searchRadius = baseRadius * 1.8
	local channelCount = rng:NextInteger(4, 6)
	for i = 1, channelCount do
		local channelAngle = rng:NextNumber(0, 2 * math.pi)
		-- t = 1 is the crater rim, t = 0 the base (matching the shingle
		-- loop's own parameterisation), so a flow walks from high t to low.
		local tTop = rng:NextNumber(0.86, 0.97)
		local tBottom = rng:NextNumber(0.02, 0.16)
		local channelWidth = rng:NextNumber(2.8, 4.8)
		local segments = 16

		--[[
			DIRECTED FLOW. Sample the real rock face straight down one
			bearing, then connect CONSECUTIVE samples end to end.

			The previous version placed each segment independently and
			oriented it with CFrame.lookAt(pos, pos + normal) - which pins
			the part's -Z to the surface normal but leaves its long axis
			pointing wherever the derived up-vector happened to land. That
			is why the flows read as rectangles scattered at every angle
			instead of a stream: nothing in that maths ever referenced the
			downhill direction. Building each segment BETWEEN two points on
			the slope makes the flow direction explicit, and passing the
			surface normal as the up-vector lays the ribbon flat against the
			rock.
		]]
		--[[
			The ribbon's roll is set by ONE constant normal for the whole
			flow, computed analytically from the cone's own slope angle:
			for a surface at bearing `channelAngle` inclined `slopeAngle`
			from horizontal, the outward normal is
			(sin(bearing)*sin(slope), cos(slope), cos(bearing)*sin(slope)).

			Using each raycast's OWN hit normal here (as this first did) is
			what made the stream look like a chain of loose plates: the
			shingles carry deliberate tilt jitter, so every segment picked up
			a slightly different up-vector and twisted relative to its
			neighbours. A single shared normal keeps every segment coplanar,
			so they read as one continuous ribbon.
		]]
		local flowNormal = Vector3.new(
			math.sin(channelAngle) * math.sin(slopeAngle),
			math.cos(slopeAngle),
			math.cos(channelAngle) * math.sin(slopeAngle)
		).Unit

		--[[
			Points come from the cone's OWN analytic surface - the same
			formula the shingles were laid against - offset outward along the
			shared normal so the ribbon rides just clear of the rock.

			Raycasting for these (as the previous pass did) is subtly wrong
			here: the shingles carry positional jitter, so a ray occasionally
			lands on a recessed slab and the flow dips inward, disappearing
			behind the tier lip below it and breaking the stream into
			visible gaps. The analytic surface has no such jitter, and a
			clearance comfortably greater than the slab half-thickness plus
			jitter guarantees the ribbon stays on top of the rock the whole
			way down. (Vents still raycast - they WANT to be embedded.)
		]]
		-- Clearance must beat HALF a shingle's thickness (slabs are 3.5-5.5
		-- thick, centred on the analytic surface) PLUS the radial jitter,
		-- PLUS the downhill overhang of the tier above - which together are
		-- a good deal more than the slab thickness alone. At 3.2 the ribbon
		-- was still being occluded by the rock it was supposed to run over.
		local FLOW_CLEARANCE = 7
		local points = {}
		for s = 0, segments do
			local t = tTop + (tBottom - tTop) * (s / segments)
			local segY = peakHeight * t ^ 1.05
			local segR = math.max(craterRadius, baseRadius * (1 - t) ^ 0.9)
			local onCone = position
				+ Vector3.new(math.sin(channelAngle) * segR, segY, math.cos(channelAngle) * segR)
			table.insert(points, onCone + flowNormal * FLOW_CLEARANCE)
		end

		for s = 1, #points - 1 do
			local a, b = points[s], points[s + 1]
			local delta = b - a
			local span = delta.Magnitude
			if span > 0.05 then
				local mid = a + delta * 0.5
				-- Generous overlap along the flow so consecutive segments
				-- always intersect, and a slight widening downhill the way a
				-- real flow spreads as the slope eases near the base.
				local widen = 1 + (s / math.max(#points - 1, 1)) * 0.45
				PartUtils.CreatePart({
					name = ("LavaFlow%dS%d"):format(i, s),
					-- Given real depth so the channel reads as a molten stream
				-- carved into the flank rather than a decal stuck on it.
				size = Vector3.new(channelWidth * widen, 3.4, span * 1.6),
					cframe = CFrame.lookAt(mid, b, flowNormal),
					material = LAVA_MATERIAL,
					color = if s % 4 == 0 then LAVA_EDGE else LAVA_CORE,
					canCollide = false,
					parent = model,
				})
			end
		end
	end

	-- Heated glowing vents cut INTO the surface. Like the flows above,
	-- each vent is snapped to a real raycast hit against the finished rock
	-- and sunk along that hit's normal, rather than positioned from the
	-- idealised cone formula (which the jittered slabs only approximate,
	-- and which therefore used to leave vents hanging off the face).
	for i = 1, rng:NextInteger(4, 7) do
		local t = rng:NextNumber(0.1, 0.85)
		local angle = rng:NextNumber(0, 2 * math.pi)
		local ventY = peakHeight * t ^ 1.05
		local hit = surfaceHit(model, position, angle, ventY, searchRadius)
		if hit then
			local pos = hit.Position - hit.Normal * 0.9
			PartUtils.CreatePart({
				name = "HeatVent" .. i,
				size = Vector3.new(rng:NextNumber(1.5, 3), rng:NextNumber(1.5, 3), 2.6),
				cframe = CFrame.lookAt(pos, pos + hit.Normal),
				material = LAVA_MATERIAL,
				color = LAVA_EDGE,
				canCollide = false,
				parent = model,
			})
		end
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
			material = LAVA_MATERIAL,
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
				material = LAVA_MATERIAL,
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

	--[[
		BLOWN-OUT CRATER PITS - the "exploded potholes" ground treatment.

		Deliberately NOT clean circles: each pit's rim is walked around as a
		ragged loop whose radius wanders per step, and the rim blocks are
		tilted outward at varying angles as though the ground was thrown up
		from underneath. A darker sunken floor sits inside, and about half
		the pits have molten lava still pooled at the bottom.

		Everything is kept curb-height or lower and non-collidable, so the
		relief reads underfoot without ever obstructing walking.
	]]
	for i = 1, 11 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(MapConfig.USABLE_RADIUS * 0.18, MapConfig.USABLE_RADIUS * 0.9)
		local center = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		local pitRadius = rng:NextNumber(5, 11)
		local molten = rng:NextNumber() < 0.5

		-- Sunken floor: a couple of stacked discs, the lower one darker, so
		-- the pit reads as depth rather than a flat decal.
		PartUtils.CreateDisc({
			name = ("PitFloor%d"):format(i),
			diameter = pitRadius * 1.9,
			thickness = 0.3,
			position = center + Vector3.new(0, 0.06, 0),
			material = Enum.Material.Basalt,
			color = Color3.fromRGB(14, 11, 10),
			canCollide = false,
			parent = folder,
		})
		if molten then
			PartUtils.CreateDisc({
				name = ("PitLava%d"):format(i),
				diameter = pitRadius * rng:NextNumber(0.9, 1.4),
				thickness = 0.24,
				position = center + Vector3.new(rng:NextNumber(-1, 1), 0.14, rng:NextNumber(-1, 1)),
				material = LAVA_MATERIAL,
				color = LAVA_EDGE,
				canCollide = false,
				parent = folder,
			})
		end

		-- Ragged, thrown-up rim.
		local rimSteps = rng:NextInteger(9, 14)
		for r = 1, rimSteps do
			local rimAngle = (2 * math.pi / rimSteps) * r + rng:NextNumber(-0.14, 0.14)
			-- Radius wanders per block, so the outline is irregular rather
			-- than a perfect circle.
			local rimRadius = pitRadius * rng:NextNumber(0.82, 1.22)
			local blockSize = rng:NextNumber(2, 4.2)
			local pos = center
				+ Vector3.new(math.sin(rimAngle) * rimRadius, rng:NextNumber(0.1, 0.5), math.cos(rimAngle) * rimRadius)
			PartUtils.CreatePart({
				name = ("PitRim%d_%d"):format(i, r),
				size = Vector3.new(blockSize, rng:NextNumber(0.5, 1.3), blockSize * rng:NextNumber(0.6, 1.1)),
				cframe = CFrame.new(pos)
					* CFrame.Angles(0, rimAngle, 0)
					-- Tipped outward, as debris ejected from the centre.
					* CFrame.Angles(math.rad(rng:NextNumber(-26, -6)), 0, math.rad(rng:NextNumber(-14, 14))),
				material = if rng:NextNumber() < 0.4 then Enum.Material.Rock else Enum.Material.Basalt,
				color = Color3.fromRGB(28 + rng:NextInteger(-6, 8), 22 + rng:NextInteger(-4, 6), 19 + rng:NextInteger(-3, 5)),
				canCollide = false,
				parent = folder,
			})
		end
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
