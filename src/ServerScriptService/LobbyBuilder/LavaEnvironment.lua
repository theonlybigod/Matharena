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

--[[
	Radius of the map's rock-wall enclosure.

	Raised from the original 300 to 440, driven entirely by the volcanoes:
	they must stand fully clear of the 193-stud walkable plate AND remain
	INSIDE this wall, because anything outside it is hidden behind 700
	studs of rock.

	The binding number is a volcano's REACH - its outermost geometry
	measured from its own centre, including each slab's half-width, which
	runs to ~175 studs at the current size. That forces centres out to
	193 + 10 margin + 175 = ~378, so the wall has to sit comfortably beyond
	that. 440 leaves the volcanoes ~60 studs inside the enclosure.

	There is a hard ceiling on this: the same constant sizes the ground
	plane below (ENCLOSURE_RADIUS * 2 + 40), and MapsConfig spaces the five
	maps 1050 studs apart. At 440 the plane is 920 wide, so two adjacent
	maps total 920 against 1050 of spacing and still clear. Much past 500
	they would overlap, and at that point the volcanoes would have to get
	smaller instead.
]]
local ENCLOSURE_RADIUS = 440
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
	Attaches a warm PointLight to a lava feature so molten rock actually
	ILLUMINATES what is around it.

	Defined HERE, above every caller, rather than beside the other build
	helpers further down: buildBoundaryWalls is the first user and sits
	near the top of this file, and a `local function` declared after that
	point resolves to nil at the call site.

	Why this exists: the Lava map's mean surface luminance measured 0.168 -
	against 0.442 for Futuristic and 0.817 for IceAge, so nearly five times
	darker than the brightest map and comfortably the least readable of the
	five. The cause was not the global lighting (which is shared by every
	map and cannot be tuned per-map, since all five coexist in one
	Workspace) but the fact that this map's dominant feature emitted no
	light at all: 480 LavaFlow segments totalling ~81,500 studs³ of glowing
	neon, 10 WallFissures and 6 Craters, every one Neon-material and every
	one contributing exactly zero illumination. Neon in Roblox is emissive
	in APPEARANCE only.

	So this is a look fix as much as a readability fix - it is what makes
	the lava read as genuinely molten rather than as bright orange plastic.

	PERFORMANCE: lights are added SPARSELY and deliberately, not to every
	glowing part. Lighting one flow segment in eight is enough to carry the
	glow along a channel because the ranges overlap generously, and it
	keeps the map's light count in the same order of magnitude it already
	had (51). Attaching 480 would be indefensible.
]]
local function addLavaGlow(part: BasePart, brightness: number, range: number)
	local light = Instance.new("PointLight")
	light.Color = GLOW_COLOR
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false -- shadow-casting lights are the expensive kind; this is fill, not a key light
	light.Parent = part
end

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
			local fissure = PartUtils.CreatePart({
				name = "WallFissure" .. i,
				size = Vector3.new(WALL_THICKNESS + 0.6, rng:NextNumber(120, 260), 1.2),
				cframe = CFrame.new(midpoint + Vector3.new(0, wallCenterY + rng:NextNumber(-100, 150), 0))
					* CFrame.Angles(0, yaw, math.rad(rng:NextNumber(-8, 8))),
				material = LAVA_MATERIAL,
				color = GLOW_COLOR,
				canCollide = false,
				parent = folder,
			})
			-- Tall wall cracks: the map's only light source at the horizon, so
			-- a long range to wash the surrounding rock rather than spot it.
			addLavaGlow(fissure, 1.6, 90)
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
	purely decorative (no PointLights of their own; the lava features
	themselves now carry the map's emissive lighting - see addLavaGlow).
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

--[[
	PER-VOLCANO SHAPE FIELD.

	This replaces the old "radius is a function of height alone" model,
	which is what made every volcano read as a stack of concentric rings:
	if radius depends only on t, then every tier IS a perfect circle, and
	no amount of surface decoration hides that.

	Here the radius is a function of BOTH height and bearing. A handful of
	low-frequency sinusoidal lobes at random phases deform the cone into
	ridges and gullies that run continuously from foot to rim, so a
	horizontal slice is an irregular blob rather than a circle, and the
	left, right, front and back of the mountain genuinely differ.

	The deformation is enveloped to zero at the very bottom and the very
	top (sin(pi*t)) so the foot still meets the ground cleanly and the rim
	stays readable, with the strongest character mid-slope where the eye
	spends most of its time.

	Crucially the SAME field drives the rock, the crater rim and the lava.
	The lava finds its own path by walking downhill through this field
	(see descendGully), so flows end up in the gullies the rock actually
	has - rather than being assigned arbitrary bearings and then having
	the rock bent out of their way.

	Three lobes at frequencies 2-5 is deliberately few: enough for
	believable large-scale geology, far too few to read as noise.
]]
local FLANK_EXPONENT = 1.55

type FlankShape = {
	radiusAt: (t: number, bearing: number) -> number,
	heightAt: (t: number) -> number,
	rimLiftAt: (bearing: number) -> number,
}

local function makeFlankShape(rng: Random, baseRadius: number, craterRadius: number, peakHeight: number): FlankShape
	local lobes = {}
	for _ = 1, 3 do
		table.insert(lobes, {
			freq = rng:NextInteger(2, 4),
			phase = rng:NextNumber(0, 2 * math.pi),
			-- Amplitude halved from 0.06-0.15. That range gave the broad,
			-- believable ridges we wanted but at a depth that made the
			-- surface visibly lumpy; at this scale the geology still reads
			-- clearly while the flank stays smooth to the eye.
			amp = rng:NextNumber(0.035, 0.075),
		})
	end
	-- An independent, higher-frequency pair shapes the crater rim only, so
	-- the rim's ups and downs are not just an echo of the flank's ridges.
	local rimLobes = {}
	for _ = 1, 2 do
		table.insert(rimLobes, {
			freq = rng:NextInteger(3, 7),
			phase = rng:NextNumber(0, 2 * math.pi),
			amp = rng:NextNumber(0.04, 0.10),
		})
	end

	local function deform(bearing: number, t: number): number
		local n = 0
		for _, l in ipairs(lobes) do
			n += math.sin(bearing * l.freq + l.phase) * l.amp
		end
		local envelope = math.sin(math.pi * math.clamp(t, 0, 1)) ^ 0.7
		return n * envelope
	end

	local shape = {}

	function shape.radiusAt(t: number, bearing: number): number
		local base = craterRadius + (baseRadius - craterRadius) * (1 - t) ^ FLANK_EXPONENT
		return base * (1 + deform(bearing, t))
	end

	function shape.heightAt(t: number): number
		return peakHeight * t
	end

	-- How much the crater rim rises (or dips) at a given bearing, as a
	-- fraction of peak height. This is what stops the summit reading as a
	-- perfect circular collar dropped onto the cone.
	function shape.rimLiftAt(bearing: number): number
		local n = 0
		for _, l in ipairs(rimLobes) do
			n += math.sin(bearing * l.freq + l.phase) * l.amp
		end
		return n
	end

	return shape
end

--[[
	Walks downhill from a starting bearing, letting the shape field decide
	where the lava goes.

	At each step it samples the flank slightly left and slightly right of
	the current bearing and drifts toward whichever is RECESSED - i.e. it
	follows the gully. That is the whole trick: real lava collects in low
	ground, and because the gullies come from the same field that built the
	rock, a flow physically cannot end up running along a ridge or cutting
	across the grain of the mountain.

	Returns a list of {t, bearing} samples from `tTop` down to `tBottom`.
]]
local function descendGully(shape: FlankShape, startBearing: number, tTop: number, tBottom: number, steps: number, rng: Random)
	local path = {}
	local bearing = startBearing
	local probe = math.rad(6)
	for s = 0, steps do
		local t = tTop + (tBottom - tTop) * (s / steps)
		table.insert(path, { t = t, bearing = bearing })

		local here = shape.radiusAt(t, bearing)
		local left = shape.radiusAt(t, bearing - probe)
		local right = shape.radiusAt(t, bearing + probe)
		-- Move toward the smaller radius (the recess). Step size is modest so
		-- the path curves smoothly instead of snapping to the minimum.
		local pull = 0
		if left < here or right < here then
			pull = if left < right then -probe * 0.45 else probe * 0.45
		end
		-- A little wander keeps two flows in similar gullies from tracing
		-- identical curves.
		bearing += pull + rng:NextNumber(-0.012, 0.012)
	end
	return path
end

local function buildDistantVolcano(position: Vector3, rng: Random, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	--[[
		HEIGHT: ~4x TALLER, AT A FOOTPRINT THE MAP CAN ACTUALLY AFFORD.

		Measured baseline before this change: heights 25-36 studs (mean ~30),
		footprints 109-140. Target is a mean near 120.

		The hard constraint is horizontal, not vertical. The volcanoes sit
		230-268 studs from the map centre, with the walkable ground disc at
		radius 193 and the boundary RockWalls at 298 - so there is very
		little room to grow outward, and an earlier attempt at widening the
		base pushed 583 rock parts into the plaza.

		So the cone is widened WITHOUT widening the footprint: the skirt
		multiplier drops from 2.2x to 1.5x (see skirtOuterRadius below) and
		that reclaimed width goes into baseRadius instead. Footprint stays
		about where it was; the mountain itself gets substantially broader,
		which is what keeps a 4x taller cone from turning into a spike.

		Even so, 4x height on a near-fixed base necessarily steepens the
		flank - roughly 30 degrees before, roughly 55 now. Slab thinness,
		low jitter and the raised tier count below are what keep that
		steeper surface reading as smooth rock rather than the spiky,
		chunky look this pass is specifically avoiding.

		`spread` gives each volcano a slightly different overall size, and
		the height multiplier varies independently, so heights and widths
		both differ noticeably but subtly.
	]]
	local spread = rng:NextNumber(0.92, 1.08)
	local baseRadius = rng:NextNumber(100, 122) * spread
	local peakHeight = baseRadius * rng:NextNumber(1.35, 1.60)
	-- Crater scaled to the mountain instead of a fixed 4-6 studs, so the
	-- summit opening is actually large enough to read as a lava-filled
	-- caldera from a distance rather than a pinprick lost in the peak.
	local craterRadius = baseRadius * rng:NextNumber(0.18, 0.28)
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
	local tierCount = 30

	--[[
		The shape field (see makeFlankShape) is the single source of truth
		for this mountain's geometry. Rock, crater rim and lava all read from
		it, so they cannot disagree.
	]]
	local shape = makeFlankShape(rng, baseRadius, craterRadius, peakHeight)

	local SHINGLE_OVERLAP = 1.9
	for tier = 0, tierCount do
		local t = tier / tierCount
		local nextT = math.min((tier + 1) / tierCount, 1)
		local ringY = shape.heightAt(t)
		local nextY = shape.heightAt(nextT)

		--[[
			PER-TIER ANGULAR PHASE.

			Every tier used to start its shingles at the same angle, so the
			seams between neighbouring slabs stacked into continuous vertical
			columns all the way down the mountain - a strong visual cue that
			the thing is built from rings. Offsetting each tier by an
			arbitrary fraction of its own spacing staggers those seams like
			brickwork, so no column of joins ever forms.
		]]
		local phase = rng:NextNumber(0, 2 * math.pi)

		-- Sized from the widest point of this tier so slabs still overlap
		-- where the deformed radius is largest.
		--
		-- MINIMUM COUNT RAISED 12 -> 28. A floor of 12 means each slab spans
		-- 30 degrees of arc, which is harmless on the wide lower tiers but
		-- catastrophic near the summit where the radius is small: a chord
		-- across 30 degrees, widened by the 1.9x overlap, comes out WIDER
		-- THAN THE CONE'S RADIUS. Measured on the previous build, upper-tier
		-- slabs were 12-15 studs wide where the local radius was only 5-13,
		-- so they overshot the surface in every direction and engulfed the
		-- lava - the direct cause of 100% of flow segments intersecting rock.
		local nominalRadius = shape.radiusAt(t, phase)
		local circumference = 2 * math.pi * nominalRadius
		local shingleCount = math.max(28, math.ceil(circumference / math.max(nominalRadius * 0.38, 6)))

		for c = 1, shingleCount do
			local angle = phase + (2 * math.pi / shingleCount) * c
			local ringRadius = shape.radiusAt(t, angle)
			local nextRadius = shape.radiusAt(nextT, angle)

			-- Slope is evaluated along THIS bearing, so a slab sitting in a
			-- gully tilts differently from one on a ridge - which is what
			-- makes the deformed surface read as continuous rock rather than
			-- a circular tier that has been pushed in and out.
			local slant = math.max(
				math.sqrt((ringRadius - nextRadius) ^ 2 + (nextY - ringY) ^ 2),
				baseRadius / tierCount
			)
			local tierSlope = math.atan2(math.max(nextY - ringY, 0.001), math.max(ringRadius - nextRadius, 0.001))
			local tierPitch = (math.pi / 2) - tierSlope

			local arcSpacing = (2 * math.pi * ringRadius) / shingleCount
			-- Hard cap relative to the LOCAL radius. Even with the raised
			-- count above, the deformation can leave a bearing whose radius is
			-- much smaller than the tier's nominal one; without this cap such
			-- a slab still bulges past the surface it is meant to tile.
			local shingleWidth = math.min(arcSpacing * SHINGLE_OVERLAP, ringRadius * 0.55)
			-- Length is capped the same way and for the same reason: an 8-stud
			-- plate laid along a near-vertical upper flank sweeps well outboard
			-- of a 6-stud radius.
			local shingleLength = math.min(slant * SHINGLE_OVERLAP, math.max(ringRadius * 0.85, 3))
			local overlapMargin = math.max((shingleWidth - arcSpacing) / 2, 0)

			local jitterRadius = ringRadius + rng:NextNumber(-overlapMargin * 0.18, overlapMargin * 0.18)
			local jitterY = ringY + rng:NextNumber(-slant * 0.05, slant * 0.05)
			local shinglePos = position + Vector3.new(math.sin(angle) * jitterRadius, jitterY, math.cos(angle) * jitterRadius)
			PartUtils.CreatePart({
				name = ("ShingleT%dC%d"):format(tier, c),
				--[[
					THIN slabs. These averaged 5.3 studs thick, which is what
					produced the chunky, blocky surface AND the lava clipping:
					the ribbon runs 5 studs off the analytic surface, so slabs
					half that thick (2.65 outboard) came within a fraction of
					the lava and any jitter pushed them through it - the lava
					appearing to pass in and out of the rock.

					At 1.6-2.4 studs only ~1.2 sits outboard of the surface, so
					the rock reads as a smooth shell and the lava clears it with
					room to spare. Length/width are unchanged, so coverage and
					overlap are unaffected - the slabs get thinner, not sparser.
				]]
				size = Vector3.new(shingleWidth, rng:NextNumber(1.6, 2.4), shingleLength),
				-- Tilt jitter cut from +/-2.5 to +/-1 degree: at 5 studs thick a
				-- couple of degrees was invisible, but on a thin plate it lifts
				-- a corner clear of its neighbour and reads as a chipped edge.
				cframe = slopeCFrame(shinglePos, angle, tierPitch + math.rad(rng:NextNumber(-1, 1))),
				material = if rng:NextNumber() < 0.35 then Enum.Material.Rock else Enum.Material.Basalt,
				color = Color3.fromRGB(26 + rng:NextInteger(-4, 6), 20 + rng:NextInteger(-3, 5), 18 + rng:NextInteger(-3, 4)),
				canCollide = false,
				parent = model,
			})
		end

		--[[
			Rock shelves: BROAD, LOW swells that widen the mountain's shoulder.

			These used to be 5-10 stud tall balls sitting proud of the flank -
			a major contributor to the chunky, lumpy read. They are now wide
			and deliberately shallow (1.5-3 studs of rise), and sunk INTO the
			surface rather than perched on it, so they broaden the silhouette
			the way a real buttress does instead of studding it with boulders.

			Still placed only on ridges, never in a gully, so they stay out of
			the lava's path.
		]]
		if tier > 1 and tier < tierCount - 1 and rng:NextNumber() < 0.35 then
			local shelfAngle = rng:NextNumber(0, 2 * math.pi)
			local r = shape.radiusAt(t, shelfAngle)
			-- Ridge test widened from +/-9 to +/-20 degrees. A shelf can be tens
			-- of studs across, which at this radius spans ~25 degrees of arc - so
			-- a 9-degree test could confirm a ridge at the shelf's centre while
			-- its edges still overhung the neighbouring gully, which is exactly
			-- where the lava runs. Measured: 11 flow segments were being clipped
			-- by RockShelf parts, all of them mid-flank.
			local onRidge = r > shape.radiusAt(t, shelfAngle - math.rad(20))
				and r > shape.radiusAt(t, shelfAngle + math.rad(20))
			if onRidge then
				local shelfPos = position
					+ Vector3.new(math.sin(shelfAngle) * (r - 4), ringY, math.cos(shelfAngle) * (r - 4))
				-- Also capped relative to the local radius, so a shelf can never
				-- span more arc than the ridge it is sitting on.
				local shelfSpan = math.min(rng:NextNumber(26, 44), r * 0.30)
				PartUtils.CreatePart({
					name = "RockShelf" .. tier,
					size = Vector3.new(shelfSpan, rng:NextNumber(1.5, 3), shelfSpan * rng:NextNumber(0.7, 0.9)),
					cframe = slopeCFrame(shelfPos, shelfAngle, math.rad(rng:NextNumber(-3, 3))),
					material = Enum.Material.Basalt,
					color = Color3.fromRGB(29 + rng:NextInteger(-4, 6), 22 + rng:NextInteger(-3, 5), 19 + rng:NextInteger(-3, 4)),
					canCollide = false,
					parent = model,
				})
			end
		end
	end

	-- Wide, very-shallow skirt blending the volcano's foot into the
	-- surrounding ground - without this the whole mountain still reads as
	-- a mound dropped onto flat terrain no matter how solid its own slope
	-- is. A handful of big, nearly-flat overlapping slabs fanning out to
	-- ~2.2x the base radius, tapering down to ground level.
	--[[
		Skirt cut from 1.5x to 1.15x of base radius.

		This is what lets the volcanoes be BIGGER and CLOSER at the same
		time, which otherwise pull against each other: a volcano must sit at
		193 (plate) + margin + its own REACH, so growing it normally pushes
		it further away and it gains nothing on screen.

		The skirt is the cheapest reach to give up. It is a nearly-flat
		apron 1.5-3 studs tall that only exists to blend the foot into the
		ground - it contributes almost nothing to the silhouette while
		accounting for roughly a third of the total reach. Trading it back
		buys the cone real size and a closer standoff for the same footprint.

		1.15 still leaves a blend band of 0.15 x baseRadius (~15-20 studs),
		which is enough to keep the mountain from reading as a mound dropped
		onto flat terrain. Going much below this would reintroduce that.
	]]
	local skirtOuterRadius = baseRadius * 1.15
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

	--[[
		CRATER: an irregular rim of rock blocks, not a disc.

		The summit used to be a single flat CreateDisc laid on top of the
		cone, which is exactly the "circular structure placed on top" read.
		Now the rim is built from individual blocks whose height, width and
		outward lean all vary by bearing (via shape.rimLiftAt), so one side
		of the crater stands tall and another is breached low - and the lava
		pool sits recessed INSIDE that rim rather than capping it.
	]]
	local rimBlocks = 26
	-- Crater floor sits only shallowly below the rim now. Recessing it 4
	-- studs under a tall rim hid the lava pool inside the summit; the point
	-- is a visible molten caldera, so the rim is low and the pool broad.
	local craterFloorY = peakHeight - 1.5
	for c = 1, rimBlocks do
		local angle = (2 * math.pi / rimBlocks) * c
		local lift = shape.rimLiftAt(angle)
		local rimR = craterRadius * (1.04 + lift * 1.2)
		-- Rim height scaled right down (was 6 + 12% of peak). A low, uneven
		-- collar frames the lava instead of walling it off from view.
		local rimH = 2.2 + lift * peakHeight * 0.05 + rng:NextNumber(-0.4, 0.8)
		local rimY = peakHeight + rimH * 0.5 - 1.5
		PartUtils.CreatePart({
			name = "CraterRim" .. c,
			size = Vector3.new((2 * math.pi * rimR / rimBlocks) * 1.8, math.max(rimH, 1.2), rng:NextNumber(5, 9)),
			cframe = slopeCFrame(
				position + Vector3.new(math.sin(angle) * rimR, rimY, math.cos(angle) * rimR),
				angle,
				math.rad(rng:NextNumber(-10, -3))
			),
			material = Enum.Material.Basalt,
			color = Color3.fromRGB(24 + rng:NextInteger(-3, 5), 18 + rng:NextInteger(-2, 4), 16 + rng:NextInteger(-2, 3)),
			canCollide = false,
			parent = model,
		})
	end

	local crater = PartUtils.CreateDisc({
		name = "Crater",
		-- Fills the rim rather than sitting inside it, and thicker so the
		-- pool reads as a body of molten rock instead of a glowing sheet.
		diameter = craterRadius * 2.1,
		thickness = 3.5,
		position = position + Vector3.new(0, craterFloorY, 0),
		material = LAVA_MATERIAL,
		color = GLOW_COLOR,
		canCollide = false,
		parent = model,
	})
	addLavaGlow(crater, 2.2, 70)

	--[[
		Lava channels running down the REAL rock face. Each channel is a
		chain of short segments, and every segment is snapped onto the
		as-built surface by raycast (see surfaceHit above) and then sunk
		slightly along that surface's own normal - so the molten rock is
		cut INTO the flank rather than laid over an idealised cone the
		jittered slabs never exactly matched.
	]]
	--[[
		Lava channels running down the flank's reserved corridors.

		Each channel follows a bearing chosen BEFORE the rock was built, down
		a lane where outcrops were suppressed and jitter damped - so there is
		nothing left on the flank for the lava to cut through.

		The centreline comes from flankRadius/flankHeight, the very same
		functions that placed the shingles, so the stream traces the real
		profile of the mountain instead of a straight line drawn past it. On
		a concave flank that difference is large: a straight chord from rim
		to base cuts metres into the rock at mid-height, which is exactly the
		"goes through the volcano" defect.

		CLEARANCE has to beat HALF a shingle's thickness, since slabs are
		3.5-5.5 studs thick and centred ON the analytic surface (so up to
		2.75 studs of rock sits outboard of it), plus the downhill overhang
		of the tier above. Measured against the built mountain: at 3.2 studs
		65% of flow segments were still buried behind rock. 5.0 clears the
		thickest slab with margin while staying far below the old value of 7,
		which was set to dodge the jagged outcrops the corridor now prevents
		and which left the ribbon visibly hovering off the flank.
	]]
	--[[
		LAVA FLOWS THAT FIND THEIR OWN PATH.

		Each flow starts at a breach in the crater rim and walks downhill
		through the shape field (descendGully), drifting into whichever
		gully is lower at each step. Because the gullies come from the same
		field that placed the rock, a flow physically cannot run along a
		ridge or cut across the mountain's grain - it ends up in the
		recesses, which is where real lava collects.

		This replaces fixed bearings walked in a straight line. Every flow
		now has its own curvature, and no two trace the same arc, because
		the field differs by bearing and each volcano's lobes are randomised.

		WIDTH varies along the path rather than being one constant strip: a
		flow narrows where it is steep and swells where the slope eases, and
		each flow gets its own overall scale so some read as wide sluggish
		sheets and others as narrow concentrated streams.
	]]
	--[[
		CLEARANCE IS MEASURED TO THE LAVA'S INNER FACE, NOT ITS CENTRE.

		This is where the previous value went wrong. The ribbon is offset
		along the surface normal by its CENTRE, so a 3.6-stud-thick segment
		at clearance 3.0 puts its inner face only 3.0 - 1.8 = 1.2 studs off
		the surface - exactly where the shingles' outer faces already sit
		(half of a 2.4-stud slab). Margin was effectively zero and a
		measured 100% of segments had rock inside them.

		Budget now: lava half-thickness 1.4, plus slab half-thickness up to
		1.2, plus radial jitter and the downhill overhang of the tier above
		on a ~43 degree flank. 4.6 leaves roughly 2 studs of clear air under
		the ribbon - enough that nothing pokes through, while still close
		enough to read as lava running over the rock rather than hovering.
	]]
	local FLOW_CLEARANCE = 4.6
	local channelCount = rng:NextInteger(3, 5)

	local function surfaceNormalAt(t: number, bearing: number): Vector3
		local dt = 0.01
		local t0, t1 = math.max(t - dt, 0), math.min(t + dt, 1)
		local dr = shape.radiusAt(t1, bearing) - shape.radiusAt(t0, bearing)
		local dy = shape.heightAt(t1) - shape.heightAt(t0)
		local localSlope = math.atan2(dy, -dr)
		return Vector3.new(
			math.sin(bearing) * math.sin(localSlope),
			math.cos(localSlope),
			math.cos(bearing) * math.sin(localSlope)
		).Unit
	end

	--[[
		Lays one ribbon of lava along a descended path.
		`scale` lets a secondary branch be built by the same code as a trunk,
		just narrower - so branches are never a separate look.
	]]
	local function layFlow(path, flowIndex: number, scale: number, label: string)
		local baseWidth = rng:NextNumber(3.2, 6.0) * scale
		for s = 1, #path - 1 do
			local p0, p1 = path[s], path[s + 1]
			local n0 = surfaceNormalAt(p0.t, p0.bearing)
			local a = position
				+ Vector3.new(math.sin(p0.bearing) * shape.radiusAt(p0.t, p0.bearing), shape.heightAt(p0.t), math.cos(p0.bearing) * shape.radiusAt(p0.t, p0.bearing))
				+ n0 * FLOW_CLEARANCE
			local b = position
				+ Vector3.new(math.sin(p1.bearing) * shape.radiusAt(p1.t, p1.bearing), shape.heightAt(p1.t), math.cos(p1.bearing) * shape.radiusAt(p1.t, p1.bearing))
				+ surfaceNormalAt(p1.t, p1.bearing) * FLOW_CLEARANCE
			local delta = b - a
			local span = delta.Magnitude
			if span > 0.05 then
				local frac = s / math.max(#path - 1, 1)
				-- Two out-of-phase swells so the width pulses irregularly along
				-- the path instead of tapering uniformly.
				local swell = 1
					+ 0.35 * math.sin(frac * math.pi * 2.3 + flowIndex)
					+ 0.22 * math.sin(frac * math.pi * 5.1 + flowIndex * 2)
					+ frac * 0.45 -- spreads out as the slope eases near the foot
				local seg = PartUtils.CreatePart({
					name = ("LavaFlow%s%dS%d"):format(label, flowIndex, s),
					-- 2.8 studs: enough body to read as viscous molten rock, but
					-- deliberately not thicker - every extra stud of thickness has
					-- to be paid for twice in clearance (half of it pushes the
					-- inner face toward the rock), and thick slabs are exactly the
					-- chunky look being avoided. Overlap 2.1 keeps consecutive
					-- joins buried inside each other so the ribbon reads continuous.
					size = Vector3.new(math.max(baseWidth * swell, 1.4), 2.8, span * 2.1),
					cframe = CFrame.lookAt(a + delta * 0.5, b, n0),
					material = LAVA_MATERIAL,
					-- Cooler crust appears irregularly rather than on a fixed
					-- cycle, so no repeating stripe pattern forms.
					color = if rng:NextNumber() < 0.18 then LAVA_EDGE else LAVA_CORE,
					canCollide = false,
					parent = model,
				})
				if s % 8 == 0 then
					addLavaGlow(seg, 1.3, 34)
				end
			end
		end
	end

	for i = 1, channelCount do
		-- Start at a LOW point of the rim: lava overtops where the rim is
		-- breached, not at an arbitrary compass bearing.
		local startBearing, lowest = 0, math.huge
		for probe = 1, 24 do
			local candidate = rng:NextNumber(0, 2 * math.pi)
			local lift = shape.rimLiftAt(candidate)
			if lift < lowest then
				lowest, startBearing = lift, candidate
			end
		end

		-- Flows begin just BELOW the rim crest rather than level with it.
		-- Starting at t = 0.94-0.99 put the first few segments inside the
		-- CraterRim blocks themselves - the only remaining rock/lava
		-- intersection once the shingle sizing was fixed (10 of 1660
		-- segments, every one of them a rim block at the summit). Dropping
		-- the start below the crest lets the lava emerge from under the rim
		-- instead of through it.
		local path = descendGully(shape, startBearing, rng:NextNumber(0.86, 0.91), rng:NextNumber(0.0, 0.05), 46, rng)
		layFlow(path, i, 1.0, "")

		-- Secondary branch: splits off partway down and descends
		-- independently, so it diverges naturally instead of mirroring.
		if rng:NextNumber() < 0.6 then
			local splitAt = math.floor(#path * rng:NextNumber(0.3, 0.6))
			local node = path[math.max(splitAt, 2)]
			local branch = descendGully(
				shape,
				node.bearing + rng:NextNumber(-0.30, 0.30),
				node.t,
				rng:NextNumber(0.0, 0.08),
				22,
				rng
			)
			layFlow(branch, i, 0.62, "B")
		end
	end

	-- Heated glowing vents cut INTO the surface. Like the flows above,
	-- each vent is snapped to a real raycast hit against the finished rock
	-- and sunk along that hit's normal, rather than positioned from the
	-- idealised cone formula (which the jittered slabs only approximate,
	-- and which therefore used to leave vents hanging off the face).
	for i = 1, rng:NextInteger(4, 7) do
		local searchRadius = baseRadius * 1.8
		local t = rng:NextNumber(0.1, 0.85)
		local angle = rng:NextNumber(0, 2 * math.pi)
		local ventY = shape.heightAt(t)
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

	-- Returned so the caller can measure the finished footprint and nudge
	-- the volcano clear of the plate (see nudgeClearOfPlate).
	return model
end

--[[
	Radius of the walkable LobbyGround plate that volcanoes must not cut
	into, plus a small margin so a skirt slab never quite touches its edge.
]]
local PLATE_RADIUS = 193
-- Trimmed from 10 to 5: with the nudge measuring true reach (including
-- each slab's half-width) rather than part centres, a smaller margin is
-- still safe, and every stud here is a stud further from the player.
local PLATE_MARGIN = 5

--[[
	Nudges a finished volcano straight outward along its own bearing, by
	exactly enough that its widest point stops short of the plate.

	Done by MEASUREMENT rather than by picking a placement band, because a
	band has to be sized for the worst-case volcano and therefore pushes
	every other one further out than it needs to go - which is what made
	them all read as smaller and more distant. Each volcano now moves the
	minimum its own footprint requires, and one that already clears the
	plate does not move at all.

	Returns the distance moved, for verification.
]]
local function nudgeClearOfPlate(model: Model, centre: Vector3): number
	local flat = Vector3.new(centre.X, 0, centre.Z)
	local distance = flat.Magnitude
	if distance < 0.001 then
		return 0
	end

	local footprint = 0
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local radial = (Vector3.new(part.Position.X, 0, part.Position.Z) - flat).Magnitude
			-- Half the part's largest horizontal dimension, so the measurement
			-- accounts for the slab's own width rather than just its centre.
			local reach = math.max(part.Size.X, part.Size.Z) * 0.5
			footprint = math.max(footprint, radial + reach)
		end
	end

	local required = PLATE_RADIUS + PLATE_MARGIN + footprint
	if distance >= required then
		return 0
	end

	local shift = (flat.Unit) * (required - distance)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Position += shift
		end
	end
	return shift.Magnitude
end

local function buildDistantVolcanoes(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "DistantVolcanoes"
	folder.Parent = parent

	local rng = Random.new(884211)
	local count = 6
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		-- Placed close in, then nudged outward by exactly the amount its own
		-- measured footprint needs (see nudgeClearOfPlate). Keeping the
		-- nominal band tight means volcanoes stay as near the plate - and so
		-- as large on screen - as clearing it allows.
		local radius = rng:NextNumber(ENCLOSURE_RADIUS * 0.72, ENCLOSURE_RADIUS * 0.80)
		local position = Vector3.new(math.sin(angle) * radius, -30, math.cos(angle) * radius)
		local volcano = buildDistantVolcano(position, rng, folder, "DistantVolcano" .. i)
		if volcano then
			nudgeClearOfPlate(volcano, position)
		end
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
