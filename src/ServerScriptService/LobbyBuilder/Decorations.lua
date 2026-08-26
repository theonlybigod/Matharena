--[[
	Decorations.lua

	Builds the lobby's decorative dressing: futuristic street lamps and
	enhanced futuristic trees on their own concentric RADIAL rings (not
	square rings - see radialRingPositions below), seating (see
	LobbyBuilder/Seating.lua), flower beds near each building entrance,
	and perimeter fill lights along the 30-sided boundary.

	Map-scale refinement (Message 2): the old ringPositions() walked the
	perimeter of a SQUARE (min/max X and Z loops). The lobby is now a
	regular 30-gon (see MapConfig.lua), so ring placement is now genuinely
	radial: pick an angle, walk outward along MapConfig's polar
	coordinate system. This is a straightforward reuse of MapConfig's own
	math (the same trig LobbyBuilder/Floor.lua uses for the boundary
	itself), not a parallel/competing placement system.

	The floating "MATHARENA" plaza logo that used to be built here
	(createFloatingLogo) has been removed (sign cleanup pass) - it was a
	duplicate of the larger, borderless landmark sign now built by
	LobbyBuilder/Sign.lua. Sign.lua is the only floating-sign construction
	path.

	Street lamps (redesigned): LobbyBuilder/StreetLamps.lua builds one
	lamp at a given position/orientation; this file owns PLACEMENT (ring
	radius/spacing, jitter, avoidance).

	Seating (redesigned): LobbyBuilder/Seating.lua - four distinct seat
	types placed into five hand-designed zones. This file calls
	Seating.BuildAll and reuses the seat positions it returns for street
	lamp/tree avoidance.

	Trees (enhanced): LobbyBuilder/Trees.lua - four angular geometric
	variants. Placed LAST (after seating and lamps) so their avoidance
	list can include both.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local LobbyConfig = require(script.Parent.LobbyConfig)
local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)
local MapConfig = require(script.Parent.MapConfig)
local StreetLamps = require(script.Parent.StreetLamps)
local StreetLampConfig = require(script.Parent.StreetLampConfig)
local Seating = require(script.Parent.Seating)
local Trees = require(script.Parent.Trees)
local TreeConfig = require(script.Parent.TreeConfig)
local LobbyTheme = require(script.Parent.LobbyTheme)

local Decorations = {}

local defaultTheme = LobbyTheme.Get()
local GROUND_CLUSTER_COLORS = defaultTheme.groundClusterColors
local PERIMETER_FILL_LIGHT_COLOR = defaultTheme.perimeterFillLightColor

--[[
	Latches `theme` for this module's own flower-bed/perimeter-light colors
	AND cascades to every other themed decoration-construction module
	(Trees, StreetLamps, Seating) - Decorations.lua already requires all
	three, so this is the single call site LobbyBuilder needs for the whole
	"decorations" family.
]]
function Decorations.SetTheme(theme: LobbyTheme.Theme)
	GROUND_CLUSTER_COLORS = theme.groundClusterColors
	PERIMETER_FILL_LIGHT_COLOR = theme.perimeterFillLightColor
	Trees.SetTheme(theme)
	StreetLamps.SetTheme(theme)
	Seating.SetTheme(theme)
end

--[[
	Deterministic per-position Random - the same world position always
	produces the same tree/lamp shape/lean/rotation across rebuilds
	(variation "controlled enough that Rojo/Studio produces a stable
	intended environment", not fresh dice every server start).
]]
local function seededRandom(position: Vector3): Random
	local seed = math.floor(position.X * 92821 + position.Z * 68917)
	return Random.new(seed)
end

--[[
	True if `position` is within `radius` studs (XZ only) of anything in
	`points` - used to keep jittered placement away from spawns, building
	entrances, the queue portal, seating, and other lamps/trees.
]]
local function isNear(position: Vector3, points: { Vector3 }, radius: number): boolean
	for _, point in ipairs(points) do
		if (Vector2.new(position.X, position.Z) - Vector2.new(point.X, point.Z)).Magnitude < radius then
			return true
		end
	end
	return false
end

--[[
	Generates positions evenly spaced (by arc length) around a circle of
	`radius`, with a small deterministic jitter and occasional skip/cluster
	so the placement doesn't read as "object -> exactly N studs -> object"
	- the radial equivalent of the old square ringPositions(). `avoidPoints`
	/`avoidRadius` keep placement clear of spawns/buildings/portal/seating/
	other rings, exactly as before.
]]
local function radialRingPositions(
	radius: number,
	arcSpacing: number,
	jitter: number?,
	avoidPoints: { Vector3 }?,
	avoidRadius: number?,
	skipChance: number?,
	clusterChance: number?
): { Vector3 }
	local circumference = 2 * math.pi * radius
	local slotCount = math.max(6, math.floor(circumference / arcSpacing + 0.5))

	local rawPositions = {}
	for i = 0, slotCount - 1 do
		local angle = (2 * math.pi / slotCount) * i
		table.insert(rawPositions, Vector3.new(radius * math.sin(angle), 0, radius * math.cos(angle)))
	end

	if not jitter then
		return rawPositions
	end

	local skip = skipChance or 0.15
	local cluster = clusterChance or 0.25
	local positions = {}
	for _, rawPosition in ipairs(rawPositions) do
		local rng = seededRandom(rawPosition)

		if rng:NextNumber() > skip then
			local jittered = rawPosition + Vector3.new(rng:NextNumber(-jitter, jitter), 0, rng:NextNumber(-jitter, jitter))

			if not (avoidPoints and isNear(jittered, avoidPoints, avoidRadius or 0)) then
				table.insert(positions, jittered)

				if rng:NextNumber() < cluster then
					local clusterOffset = Vector3.new(rng:NextNumber(-7, 7), 0, rng:NextNumber(-7, 7))
					local clusterPosition = jittered + clusterOffset
					if not (avoidPoints and isNear(clusterPosition, avoidPoints, avoidRadius or 0)) then
						table.insert(positions, clusterPosition)
					end
				end
			end
		end
	end

	return positions
end

--[[
	A flower bed as an actual connected planting, not three loose spheres.

	This used to place three 0.8-stud balls at 1.2-stud spacing with nothing
	underneath them: the spacing exceeded their diameter so they did not
	even touch each other, and there was no soil or stem for them to grow
	from - so every bed was three orbs hovering over bare ground.

	It now builds a soil mound that all three blooms share, and a stem from
	that mound up into each bloom, so the bed is one connected object.
]]
local function createFlowerBed(position: Vector3, parent: Instance)
	local spread = 1.2

	PartUtils.CreateDisc({
		name = "FlowerBedSoil",
		diameter = spread * (#GROUND_CLUSTER_COLORS - 1) + 2.4,
		thickness = 0.5,
		position = position + Vector3.new(0, 0.18, 0),
		material = Enum.Material.Ground,
		color = Color3.fromRGB(74, 62, 50),
		canCollide = false,
		parent = parent,
	})

	for i, color in ipairs(GROUND_CLUSTER_COLORS) do
		local offsetX = (i - 2) * spread
		-- Stem: overlaps the soil below it and the bloom above it.
		PartUtils.CreatePart({
			name = "FlowerStem" .. i,
			size = Vector3.new(0.18, 0.7, 0.18),
			position = position + Vector3.new(offsetX, 0.42, 0),
			material = Enum.Material.Grass,
			color = Color3.fromRGB(72, 108, 62),
			canCollide = false,
			parent = parent,
		})
		PartUtils.CreatePart({
			name = "Flower" .. i,
			size = Vector3.new(0.8, 0.8, 0.8),
			position = position + Vector3.new(offsetX, 0.85, 0),
			material = Enum.Material.Neon,
			color = color,
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = parent,
		})
	end
end

local function createPerimeterFillLight(position: Vector3, parent: Instance)
	local anchor = PartUtils.CreatePart({
		name = "PerimeterFillAnchor",
		size = Vector3.new(1, 1, 1),
		position = position,
		transparency = 1,
		canCollide = false,
		parent = parent,
	}) :: BasePart

	local light = Instance.new("PointLight")
	light.Color = PERIMETER_FILL_LIGHT_COLOR
	light.Range = LightingConfig.CORNER_FILL_RANGE
	light.Brightness = LightingConfig.CORNER_FILL_BRIGHTNESS
	light.Parent = anchor
end

--[[
	Picks a tree variant for `position`, with a mild positional bias so
	different areas of the lobby favor different silhouettes rather than a
	purely uniform roll everywhere - "use different tree variants in
	different areas". Thresholds are expressed as fractions of
	MapConfig.USABLE_RADIUS so they stay correct regardless of the map's
	absolute scale.
]]
local function pickTreeVariant(position: Vector3, rng: Random): string
	local weights = { Spire = 1, CanopyBurst = 1, TwinBough = 1, CrystalCluster = 1 }
	local radialDistance = Vector2.new(position.X, position.Z).Magnitude

	-- Building side (-Z): favor CrystalCluster/TwinBough, denser/more
	-- irregular, complementing the architecture. Spawn side (+Z): favor
	-- Spire, tall sentinels framing the entrance.
	if position.Z < -0.2 * MapConfig.USABLE_RADIUS then
		weights.CrystalCluster += 1.5
		weights.TwinBough += 1
	elseif position.Z > 0.2 * MapConfig.USABLE_RADIUS then
		weights.Spire += 1.5
	end

	-- Near the boundary generally (replaces the old square's "corners" -
	-- a 30-gon doesn't have corners in that sense): favor CanopyBurst,
	-- the widest silhouette, reading well against the open boundary space.
	if radialDistance > 0.8 * MapConfig.USABLE_RADIUS then
		weights.CanopyBurst += 1.5
	end

	local total = 0
	for _, weight in pairs(weights) do
		total += weight
	end

	local roll = rng:NextNumber() * total
	local cumulative = 0
	for _, variantId in ipairs(TreeConfig.VARIANT_IDS) do
		cumulative += weights[variantId]
		if roll <= cumulative then
			return variantId
		end
	end
	return TreeConfig.VARIANT_IDS[1]
end

function Decorations.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Decorations"
	folder.Parent = parent

	-- Keep everything's placement clear of spawns, building
	-- entrances/footprints, and the queue portal.
	local avoidPoints = { LobbyConfig.QUEUE_PORTAL_POSITION }
	for _, spawn in ipairs(LobbyConfig.SPAWN_POSITIONS) do
		table.insert(avoidPoints, spawn.position)
	end
	for _, def in ipairs(LobbyConfig.BUILDINGS) do
		table.insert(avoidPoints, def.position)
		-- Also avoid the plaza-facing entrance apron in front of each building.
		table.insert(avoidPoints, def.position + Vector3.new(0, 0, def.size.Y / 2 + 6))
	end

	-- Seating is computed first (it's hand-placed, not ring-generated) so
	-- both street lamps and trees below can avoid it.
	local _seatingFolder, seatPositions = Seating.BuildAll(folder)

	-- Street lamps: their own radial ring, avoiding spawns/buildings/
	-- portal/seating. The floating Matharena sign sits directly above the
	-- queue portal position (X=0, Z=0), which is already in avoidPoints,
	-- so no separate entry is needed for it.
	local lampAvoidPoints = table.clone(avoidPoints)
	for _, seatPosition in ipairs(seatPositions) do
		table.insert(lampAvoidPoints, seatPosition)
	end

	local lightsFolder = Instance.new("Folder")
	lightsFolder.Name = "Streetlights"
	lightsFolder.Parent = folder
	local lampRadius = MapConfig.USABLE_RADIUS * 0.85
	local lampPositions = radialRingPositions(
		lampRadius,
		LobbyConfig.TREE_SPACING * StreetLampConfig.RING_SPACING_MULTIPLIER,
		StreetLampConfig.PLACEMENT_JITTER,
		lampAvoidPoints,
		StreetLampConfig.AVOID_RADIUS
	)
	for _, position in ipairs(lampPositions) do
		-- Deterministic per-position yaw jitter (same seeding convention as
		-- the trees) so lamps get "slight variation in orientation" without
		-- rerolling differently on every rebuild.
		local rng = seededRandom(position)
		local yaw = rng:NextNumber(-StreetLampConfig.ORIENTATION_JITTER_DEGREES, StreetLampConfig.ORIENTATION_JITTER_DEGREES)
		StreetLamps.Build(position, yaw, lightsFolder)
	end

	-- Trees are placed LAST specifically so their avoidance list can
	-- include both seating and street lamps, in addition to the general
	-- spawns/buildings/portal points. Their ring sits further out than
	-- the lamps' (closer to the boundary), same relative arrangement as
	-- the original square layout.
	local treeAvoidPoints = table.clone(lampAvoidPoints)
	for _, lampPosition in ipairs(lampPositions) do
		table.insert(treeAvoidPoints, lampPosition)
	end

	local treesFolder = Instance.new("Folder")
	treesFolder.Name = "Trees"
	treesFolder:SetAttribute(TreeConfig.ROOT_ATTRIBUTE, true)
	treesFolder.Parent = folder
	-- Pulled in from USABLE_RADIUS by the jitter amount: USABLE_RADIUS is
	-- already the "safe from the boundary" radius, but jitter can push a
	-- tree OUTWARD from its ring by up to TreeConfig.RING_JITTER studs -
	-- placing the ring exactly at USABLE_RADIUS let the worst-case jittered
	-- tree land right at the boundary buffer's edge (measured in Studio: as
	-- close as 4.6 studs from the boundary, well under the intended 15-stud
	-- buffer). Pulling the ring in by the jitter amount keeps even the
	-- worst-case tree safely within the buffer.
	local treeRadius = MapConfig.USABLE_RADIUS - TreeConfig.RING_JITTER
	local treePositions = radialRingPositions(
		treeRadius,
		TreeConfig.RING_SPACING,
		TreeConfig.RING_JITTER,
		treeAvoidPoints,
		TreeConfig.AVOID_RADIUS,
		TreeConfig.SKIP_CHANCE,
		TreeConfig.CLUSTER_CHANCE
	)
	for _, position in ipairs(treePositions) do
		local rng = seededRandom(position)
		local variantId = pickTreeVariant(position, rng)
		Trees.Build(position, variantId, treesFolder)
	end

	local flowersFolder = Instance.new("Folder")
	flowersFolder.Name = "FlowerBeds"
	flowersFolder.Parent = folder
	for _, def in ipairs(LobbyConfig.BUILDINGS) do
		createFlowerBed(def.position + Vector3.new(0, 0, def.size.Y / 2 + 2), flowersFolder)
	end

	-- Perimeter fill lights (replaces the old square's "4 corner lights" -
	-- a 30-gon doesn't have corners in that sense): every 5th boundary
	-- vertex (30 / 5 = 6 lights), evenly covering the full 30-sided
	-- boundary rather than just 4 points - "full-map lighting coverage...
	-- outer edges" via better distribution, not brighter individual lights.
	local perimeterLightsFolder = Instance.new("Folder")
	perimeterLightsFolder.Name = "PerimeterFillLights"
	perimeterLightsFolder.Parent = folder
	for i = 0, MapConfig.SIDES - 1, 5 do
		local vertex = MapConfig.GetVertex(i)
		createPerimeterFillLight(Vector3.new(vertex.X, 8, vertex.Z), perimeterLightsFolder)
	end

	return folder
end

return Decorations
