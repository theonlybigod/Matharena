--[[
	SpaceEnvironment.lua

	Builds the Space map's signature "deep outer space" backdrop: a large
	enclosing ring of dark wall panels plus a matching ceiling cap (reads
	as a dark surrounding void from inside the playable area - see
	buildWallSegments' doc comment for why this is a ring of panels rather
	than one giant dome part), a scattering of small glowing star points,
	a few distant celestial objects (a ringed planet, two moons, soft
	nebula haze), and a light scattering of floating asteroid debris well
	above head height near the map's edge.

	SPACE-MAP-ONLY: only ever called by LobbyBuilder for the Space map
	(def.themeId == "Space" - see LobbyBuilder/init.lua). Every other map
	(Futuristic, Lava, and any future map) is completely untouched by this
	module - it is never required by, or wired into, anything those maps'
	build paths call.

	Why this can't just be the global Lighting.Sky: Lighting is a single
	shared service, not scoped per map - multiple maps already coexist in
	one Workspace/one server (see MapsConfig.lua), and only the DEFAULT
	map's build path is even allowed to touch Lighting/Bloom/
	ColorCorrection (see LobbyBuilder/init.lua's own comment on exactly
	this point - it's what the recurring "whole map goes white" bug was
	rooted in). A large, local, non-collidable dome of ordinary geometry
	gets a map-specific "surrounding void" without touching any shared
	service at all.

	Builds entirely in the map's own LOCAL space (same convention as every
	other construction module here - Floor/Buildings/Decorations/etc. all
	build at local-origin coordinates and let LobbyBuilder's
	applyMapTransform bulk-translate the result afterward). This module is
	no different: every part below is positioned relative to (0, 0, 0),
	and LobbyBuilder.Build's existing applyMapTransform step carries this
	whole backdrop along with the rest of the map to its real world
	position with zero special-casing.

	Overlap check (why DOME_RADIUS is 300, not bigger): MapsConfig places
	the Space map MAP_SPACING_STUDS (1050 studs) from the origin (shared by
	the default Futuristic map AND Workspace.Arena, both centered at world
	(0,0,0)) and from the Lava map's center. The closest any neighboring
	map's own territory can be to the Space map's center is
	1050 - ~166 (MapConfig.CIRCUMRADIUS, the largest map footprint radius
	any current map uses) = ~884 studs, so DOME_RADIUS has a lot of room to
	spare there.

	The tighter constraint, in practice, is the shared global Lighting fog
	(LightingConfig.FOG_END = 650) and Atmosphere haze, which apply to
	EVERY map identically (see LobbyLighting.lua) - verified directly in
	Studio that a radius-550 ring faded into the light grey fog color badly
	enough to be nearly indistinguishable from the default sky, since a lot
	of its geometry sat close to or beyond FogEnd. 300 keeps the entire
	ring comfortably inside FogEnd from anywhere a player can stand on the
	map (worst case: standing at MapConfig.USABLE_RADIUS from center,
	looking at the far wall, is only ~450 studs away), so it reads as a
	crisp dark backdrop rather than fading to grey - while still being
	comfortably bigger than the map's own footprint (MapConfig.CIRCUMRADIUS
	~166) for a real sense of open surrounding space.

	Performance: WALL_SEGMENTS thin wall panels plus one ceiling panel, a
	bounded number of small star parts, a handful of celestial bodies, and
	a handful of floating asteroids - no PointLights added anywhere in this
	module (a light with a range large enough to matter at this scale
	would be expensive and would bleed into the shared Lighting model for
	no real visual benefit over Neon's own self-illumination, which every
	glowing element here already uses).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local MapConfig = require(script.Parent.MapConfig)

local SpaceEnvironment = {}

-- See the module doc comment above for why 300 is the sweet spot (well
-- clear of neighboring maps, but well inside the shared Lighting fog
-- distance so it reads as dark rather than fading to grey).
local DOME_RADIUS = 300
local WALL_SEGMENTS = 28
local WALL_HEIGHT = 700
-- Extends well below ground level so no grazing viewing angle from
-- anywhere on the map can see a gap under the wall's bottom edge out to
-- the default sky beyond it (verified directly in Studio).
local WALL_BOTTOM_Y = -200
local WALL_THICKNESS = 4

local STAR_COUNT = 220
local STAR_MIN_RADIUS = 150
local STAR_MAX_RADIUS = DOME_RADIUS - 30
local STAR_MIN_HEIGHT = 20
local STAR_MAX_HEIGHT = WALL_BOTTOM_Y + WALL_HEIGHT - 80

--[[
	Builds the enclosing backdrop as a ring of thin wall panels plus a flat
	ceiling cap - NOT one giant single Part.

	A single Part large enough to fully contain the camera inside its own
	bounding volume does not render in Roblox (verified directly in Studio,
	with both a Ball AND a Box shape at this scale: the default sky showed
	straight through in both cases, from every camera position tested
	inside the part). A ring of individually thin panels sidesteps this
	entirely, because it's the exact same geometric situation as every
	other enclosure already proven to work elsewhere in this codebase - a
	player standing in a room (BuildingInteriors.lua's walls) or walking
	the lobby floor (Floor.lua's boundary curb / invisible boundary wall
	ring) is always INSIDE the overall enclosed AREA, but never inside any
	one individual thin wall PART's own bounding volume - each wall is a
	thin plate the camera stands to one side of. This dome reuses that same
	proven pattern at a much larger radius: WALL_SEGMENTS thin vertical
	panels arranged in a circle (same per-segment vertex/midpoint/yaw math
	as Floor.lua's buildBoundarySegment, just at DOME_RADIUS instead of
	MapConfig.CIRCUMRADIUS), plus one large flat horizontal panel capping
	the top - a thin ceiling the camera is always below, matching
	BuildingInteriors.lua's own Ceiling Part.
]]
local function buildWallSegments(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "DomeWalls"
	folder.Parent = parent

	local wallCenterY = WALL_BOTTOM_Y + WALL_HEIGHT / 2
	for i = 0, WALL_SEGMENTS - 1 do
		local angle1 = (2 * math.pi / WALL_SEGMENTS) * i
		local angle2 = (2 * math.pi / WALL_SEGMENTS) * (i + 1)
		local v1 = Vector3.new(DOME_RADIUS * math.sin(angle1), 0, DOME_RADIUS * math.cos(angle1))
		local v2 = Vector3.new(DOME_RADIUS * math.sin(angle2), 0, DOME_RADIUS * math.cos(angle2))
		local midpoint = (v1 + v2) / 2
		local direction = v2 - v1
		-- Slight over-length so adjacent segments overlap a little at the
		-- seam (same reasoning as Floor.lua's buildInvisibleBoundarySegment).
		local length = direction.Magnitude + 3
		-- Same convention as Floor.lua's buildBoundarySegment: local X =
		-- thickness (radial), local Z = length (tangential), yaw =
		-- atan2(direction.X, direction.Z).
		local yaw = math.atan2(direction.X, direction.Z)

		PartUtils.CreatePart({
			name = "DomeWall" .. i,
			size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, length),
			cframe = CFrame.new(midpoint + Vector3.new(0, wallCenterY, 0)) * CFrame.Angles(0, yaw, 0),
			material = Enum.Material.SmoothPlastic,
			color = Color3.fromRGB(5, 6, 14),
			canCollide = false,
			parent = folder,
		})
	end
end

local function buildCeiling(parent: Instance)
	local ceilingY = WALL_BOTTOM_Y + WALL_HEIGHT + 6
	PartUtils.CreatePart({
		name = "DomeCeiling",
		size = Vector3.new(DOME_RADIUS * 2 + 40, 8, DOME_RADIUS * 2 + 40),
		position = Vector3.new(0, ceilingY, 0),
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(5, 6, 14),
		canCollide = false,
		parent = parent,
	})
end

--[[
	Caps the BOTTOM of the enclosure - without this, a player near the
	boundary who looks down at a steep angle would see straight through to
	the default baseplate/void below WALL_BOTTOM_Y, an obviously unfinished-
	looking gap. Sits comfortably below WALL_BOTTOM_Y (never visible from
	above the real ground, since the map's own opaque ground disc already
	covers everything a standing player can see downward) and is only ever
	reachable by looking through/under the wall ring from an extreme angle.
]]
local function buildFloor(parent: Instance)
	PartUtils.CreatePart({
		name = "DomeFloor",
		size = Vector3.new(DOME_RADIUS * 2 + 40, 8, DOME_RADIUS * 2 + 40),
		position = Vector3.new(0, WALL_BOTTOM_Y - 6, 0),
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(5, 6, 14),
		canCollide = false,
		parent = parent,
	})
end

--[[
	Scatters small glowing Neon "star" points around the map, at random
	horizontal radius/angle and random height - all well inside the
	DomeWalls ring and below DomeCeiling (viewed from OUTSIDE each tiny
	star's own volume, so unlike the big enclosure these are fine as small
	Balls - see buildCelestialBody below for the same reasoning). 
	Deterministic seed (same convention as Decorations.lua's seededRandom)
	so the starfield looks identical across rebuilds rather than
	re-rolling on every server start.
]]
local function buildStars(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Starfield"
	folder.Parent = parent

	local rng = Random.new(778912)
	local starColors = {
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(200, 220, 255),
		Color3.fromRGB(180, 200, 255),
		Color3.fromRGB(255, 235, 210),
	}

	for i = 1, STAR_COUNT do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(STAR_MIN_RADIUS, STAR_MAX_RADIUS)
		local height = rng:NextNumber(STAR_MIN_HEIGHT, STAR_MAX_HEIGHT)
		local position = Vector3.new(math.sin(angle) * radius, height, math.cos(angle) * radius)

		local isBrightStar = rng:NextNumber() > 0.85
		local size = if isBrightStar then rng:NextNumber(1.3, 2.2) else rng:NextNumber(0.5, 1)

		PartUtils.CreatePart({
			name = "Star" .. i,
			size = Vector3.new(size, size, size),
			position = position,
			material = Enum.Material.Neon,
			color = starColors[rng:NextInteger(1, #starColors)],
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = folder,
		})
	end
end

--[[
	Builds one distant "planet" or "moon": a solid glowing sphere, plus an
	optional tilted ring disc (reusing PartUtils.CreateDisc - the same
	flattened-cylinder trick every other ring/halo in this codebase
	already uses, e.g. StreetLamps' BaseTrim).
]]
local function buildCelestialBody(
	position: Vector3,
	diameter: number,
	color: Color3,
	ringColor: Color3?,
	parent: Instance,
	name: string
)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local body = PartUtils.CreatePart({
		name = "Body",
		size = Vector3.new(diameter, diameter, diameter),
		position = position,
		material = Enum.Material.SmoothPlastic,
		color = color,
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})

	if ringColor then
		local ring = PartUtils.CreateDisc({
			name = "Ring",
			diameter = diameter * 1.9,
			thickness = math.max(0.6, diameter * 0.04),
			position = position,
			material = Enum.Material.Neon,
			color = ringColor,
			canCollide = false,
			parent = model,
		})
		-- Tilt the ring off-axis so it reads as a genuine Saturn-like ring
		-- rather than a flat halo sitting exactly on the planet's equator.
		ring.CFrame = ring.CFrame * CFrame.Angles(math.rad(20), 0, math.rad(12))
	end

	model.PrimaryPart = body
end

--[[
	A handful of fixed distant celestial bodies plus soft nebula haze -
	all placed well inside DOME_RADIUS (see the module doc comment for the
	overall clearance math), never collidable, never looked at up close.
]]
local function buildCelestialBodies(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "CelestialBodies"
	folder.Parent = parent

	buildCelestialBody(
		Vector3.new(-160, 120, -150),
		70,
		Color3.fromRGB(210, 140, 90),
		Color3.fromRGB(230, 200, 160),
		folder,
		"RingedPlanet"
	)
	buildCelestialBody(Vector3.new(150, 100, 140), 42, Color3.fromRGB(90, 140, 220), nil, folder, "BlueMoon")
	buildCelestialBody(Vector3.new(-120, 140, 160), 26, Color3.fromRGB(180, 90, 200), nil, folder, "VioletMoon")

	--[[
		Additional worlds, added to fill out the skybox now that the buildings
		are rockets and the sky is a bigger part of the map's identity.

		Placement rules kept consistent with the three above: all are well
		above head height and out past the walkable plate, none share a bearing
		with an existing body or a SkySaucer, and sizes descend with distance so
		the sky reads as having depth rather than as a flat collage. Two get
		rings (the second argument pair to buildCelestialBody) for variety.
	]]
	buildCelestialBody(
		Vector3.new(210, 165, -40),
		58,
		Color3.fromRGB(120, 200, 165),
		Color3.fromRGB(200, 235, 220),
		folder,
		"RingedTealGiant"
	)
	buildCelestialBody(Vector3.new(-215, 90, -110), 48, Color3.fromRGB(206, 118, 74), nil, folder, "RustPlanet")
	buildCelestialBody(Vector3.new(40, 200, 210), 34, Color3.fromRGB(235, 214, 130), nil, folder, "SandMoon")
	buildCelestialBody(Vector3.new(-70, 210, -200), 30, Color3.fromRGB(96, 112, 190), nil, folder, "DeepBlueMoon")
	buildCelestialBody(Vector3.new(190, 125, 195), 22, Color3.fromRGB(170, 175, 185), nil, folder, "GreyMoonlet")
	buildCelestialBody(
		Vector3.new(-180, 175, 55),
		40,
		Color3.fromRGB(150, 95, 205),
		Color3.fromRGB(215, 190, 240),
		folder,
		"RingedVioletWorld"
	)

	-- Soft nebula haze: large, mostly-transparent tinted spheres far away
	-- - cheap atmospheric color variation, not meant to be inspected up
	-- close. Kept to two spots so the sky reads as "accented", not busy.
	local nebulaSpots = {
		{ position = Vector3.new(150, 130, -160), color = Color3.fromRGB(150, 80, 200), size = 120 },
		{ position = Vector3.new(-160, 100, 130), color = Color3.fromRGB(70, 160, 220), size = 110 },
	}
	for i, spot in ipairs(nebulaSpots) do
		PartUtils.CreatePart({
			name = "NebulaHaze" .. i,
			size = Vector3.new(spot.size, spot.size, spot.size),
			position = spot.position,
			material = Enum.Material.Neon,
			color = spot.color,
			transparency = 0.88,
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = folder,
		})
	end
end

--[[
	Floating asteroid debris - small irregular rock clusters well above
	head height (35-70 studs up) so they never obstruct walking/paths
	regardless of their XZ placement, kept within the map's own usable
	radius (same buffer convention every other decoration in this codebase
	uses - see MapConfig.USABLE_RADIUS) rather than out near the dome.
	Deterministic seed, modest count, for performance.
]]
local function buildFloatingAsteroids(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "FloatingAsteroids"
	folder.Parent = parent

	local rng = Random.new(41177)
	local count = 9
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local radius = rng:NextNumber(MapConfig.USABLE_RADIUS * 0.55, MapConfig.USABLE_RADIUS * 0.95)
		local height = rng:NextNumber(35, 70)
		local center = Vector3.new(math.sin(angle) * radius, height, math.cos(angle) * radius)

		local model = Instance.new("Model")
		model.Name = "Asteroid" .. i
		model.Parent = folder

		local coreSize = rng:NextNumber(3, 6)
		local core = PartUtils.CreatePart({
			name = "Core",
			size = Vector3.new(coreSize, coreSize * 0.8, coreSize * 0.9),
			position = center,
			material = Enum.Material.Rock,
			color = Color3.fromRGB(58, 58, 66),
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = model,
		})

		for j = 1, rng:NextInteger(2, 3) do
			local offset = Vector3.new(rng:NextNumber(-2.5, 2.5), rng:NextNumber(-1.5, 1.5), rng:NextNumber(-2.5, 2.5))
			local chunkSize = coreSize * rng:NextNumber(0.35, 0.6)
			PartUtils.CreatePart({
				name = "Chunk" .. j,
				size = Vector3.new(chunkSize, chunkSize * 0.8, chunkSize * 0.9),
				position = center + offset,
				material = Enum.Material.Rock,
				color = Color3.fromRGB(50, 50, 58),
				shape = Enum.PartType.Ball,
				canCollide = false,
				parent = model,
			})
		end

		-- Small glowing mineral-vein accent, ties the asteroids into the
		-- map's cyan/violet accent palette rather than reading as plain
		-- grey rock disconnected from the rest of the theme.
		PartUtils.CreatePart({
			name = "OreVein",
			size = Vector3.new(coreSize * 0.35, coreSize * 0.15, coreSize * 0.35),
			position = center + Vector3.new(0, coreSize * 0.3, 0),
			material = Enum.Material.Neon,
			color = if i % 2 == 0 then Color3.fromRGB(80, 220, 255) else Color3.fromRGB(170, 90, 255),
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = model,
		})

		model.PrimaryPart = core
	end
end

--[[
	Builds the full space backdrop under `parent` (the map's root
	Workspace folder), in a single "SpaceEnvironment" folder - see
	LobbyBuilder/init.lua for the (Space-map-only) call site.
]]
--[[
	FLYING SAUCERS IN THE SKY.

	The same half-hull/half-saucer silhouette the buildings now use (see
	BuildingInteriors.addSpaceCraftBody), but small, decorative, and hung up
	among the planets - so the craft parked on the ground read as part of a
	fleet rather than as one-off scenery.

	Built from simple primitives rather than the continuous-shell builder:
	at this distance the silhouette and the glowing underside ring are the
	only things that register, and a full plated shell per saucer would cost
	hundreds of parts for detail nobody can resolve.

	Everything is non-collidable and sits far above head height, so none of
	it affects walking or the map's playable space. Each saucer is tilted a
	little so the group doesn't read as a row of identical discs.
]]
local function buildSkySaucers(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "SkySaucers"
	folder.Parent = parent

	local HULL_LIGHT = Color3.fromRGB(150, 158, 178)
	local HULL_DARK = Color3.fromRGB(74, 80, 96)

	-- Hand-placed so they sit in clear sky between the existing planets and
	-- nebula spots rather than intersecting them.
	local saucers = {
		{ position = Vector3.new(60, 145, -95), scale = 1.0, tilt = 12, yaw = 20 },
		{ position = Vector3.new(-95, 118, 40), scale = 0.7, tilt = -9, yaw = 130 },
		{ position = Vector3.new(120, 160, 55), scale = 0.5, tilt = 16, yaw = 260 },
		{ position = Vector3.new(-40, 175, -140), scale = 0.62, tilt = -14, yaw = 75 },
		{ position = Vector3.new(10, 132, 150), scale = 0.45, tilt = 8, yaw = 310 },
	}

	for i, s in ipairs(saucers) do
		local discWidth = 34 * s.scale
		local orientation = CFrame.new(s.position)
			* CFrame.Angles(0, math.rad(s.yaw), 0)
			* CFrame.Angles(math.rad(s.tilt), 0, math.rad(s.tilt * 0.5))

		-- Saucer disc (the wide flange).
		--[[
			CreateDisc builds a Cylinder already rotated to lie flat. Assigning
			`orientation` straight onto .CFrame would throw that rotation away
			and stand the disc on its edge, so the craft's own tilt is applied
			ON TOP of whatever rotation the disc was created with. Subtracting
			a CFrame's Position leaves the rotation-only component.
		]]
		local disc = PartUtils.CreateDisc({
			name = ("SkySaucer%dDisc"):format(i),
			diameter = discWidth,
			thickness = 3.2 * s.scale,
			position = s.position,
			material = Enum.Material.Metal,
			color = HULL_LIGHT,
			canCollide = false,
			parent = folder,
		})
		local discRotation = disc.CFrame - disc.CFrame.Position
		disc.CFrame = orientation * discRotation

		-- Lower hull, tapering under the disc - the "half hull" half.
		PartUtils.CreatePart({
			name = ("SkySaucer%dHull"):format(i),
			size = Vector3.new(discWidth * 0.52, 5 * s.scale, discWidth * 0.52),
			cframe = orientation * CFrame.new(0, -3.4 * s.scale, 0),
			material = Enum.Material.Metal,
			color = HULL_DARK,
			canCollide = false,
			parent = folder,
		})

		-- Cockpit dome on top.
		PartUtils.CreatePart({
			name = ("SkySaucer%dCockpit"):format(i),
			shape = Enum.PartType.Ball,
			size = Vector3.new(discWidth * 0.4, discWidth * 0.3, discWidth * 0.4),
			cframe = orientation * CFrame.new(0, 2.6 * s.scale, 0),
			material = Enum.Material.Glass,
			color = Color3.fromRGB(150, 220, 255),
			transparency = 0.35,
			canCollide = false,
			parent = folder,
		})

		-- Glowing underside ring - the part that actually reads as a UFO from
		-- across the map, especially against a dark sky.
		local glow = PartUtils.CreateDisc({
			name = ("SkySaucer%dUnderGlow"):format(i),
			diameter = discWidth * 0.66,
			thickness = 0.9,
			position = s.position,
			material = Enum.Material.Neon,
			color = Color3.fromRGB(120, 235, 255),
			canCollide = false,
			parent = folder,
		})
		glow.CFrame = orientation * CFrame.new(0, -6.2 * s.scale, 0) * (glow.CFrame - glow.CFrame.Position)

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(120, 235, 255)
		light.Range = 34 * s.scale
		light.Brightness = 2
		light.Parent = glow
	end
end

function SpaceEnvironment.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "SpaceEnvironment"
	folder.Parent = parent

	buildWallSegments(folder)
	buildCeiling(folder)
	buildFloor(folder)
	buildStars(folder)
	buildCelestialBodies(folder)
	buildFloatingAsteroids(folder)
	buildSkySaucers(folder)

	return folder
end

return SpaceEnvironment
