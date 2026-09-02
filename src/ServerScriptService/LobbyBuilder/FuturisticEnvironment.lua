--[[
	FuturisticEnvironment.lua

	The metropolis backdrop for the Futuristic (Difficulty 1) map: a city
	skyline ringing the plaza, a sun in the sky, and volumetric sun beams
	raking down into the map.

	WHY THIS MODULE EXISTS AT ALL. Every other map has a themed environment
	(SpaceEnvironment, LavaEnvironment, IceAgeEnvironment,
	UnderTheSeaEnvironment) that supplies its surroundings. Futuristic had
	none, so the plaza simply ended at a boundary wall with nothing beyond -
	which is why it read as a platform rather than as a place.

	DESIGN: "STANDING IN THE HEART OF THE CITY". The towers are deliberately
	TALLER THAN YOU CAN SEE. They start close to the plaza and rise past the
	top of the view, so the horizon is a canyon wall rather than a distant
	silhouette. That is the difference between looking AT a skyline and being
	IN one.

	VARIETY IS THE WHOLE POINT. A ring of identical boxes reads as a fence.
	Six tower archetypes below, drawn from real Manhattan building types:

	  SETBACK      1920s-30s ziggurat - stepped shoulders, the classic
	               pre-war New York profile (think 20 Exchange Place).
	  ARTDECO      Setback plus a crowned spire (Chrysler / Empire State).
	  GLASSBOX     Post-war international style - a plain curtain-wall slab
	               (Seagram Building).
	  TAPERED      Modern supertall, narrowing continuously (432 Park, One
	               World Trade).
	  TWISTED      Contemporary rotated-floorplate tower.
	  BRICK        Low-rise pre-war infill block, filling the gaps between
	               the towers so the skyline has a floor rather than
	               free-standing spikes.

	Built in the map's LOCAL space like every other environment module;
	LobbyBuilder.applyMapTransform carries it to the map's world position.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local MapConfig = require(script.Parent.MapConfig)

local FuturisticEnvironment = {}

--[[
	The city occupies a wide band starting just beyond the plaza. INNER is
	close deliberately - a distant skyline reads as scenery, a close one reads
	as being downtown.
]]
local CITY_INNER = 260 -- first row of buildings, just past the plaza
local CITY_OUTER = 980 -- last row, inside the enclosure
local ENCLOSURE_RADIUS = 1000
local SKY_HEIGHT = 1400 -- enclosure height; towers reach ~1000

local ROWS = 7 -- concentric rows of buildings

-- Muted daytime city palette. Real cities are grey, buff and glass-green;
-- saturated colour here would read as a toy town.
local FACADE_COLOURS = {
	Color3.fromRGB(122, 128, 138), -- grey concrete
	Color3.fromRGB(148, 142, 130), -- buff limestone
	Color3.fromRGB(96, 104, 116), -- dark steel
	Color3.fromRGB(134, 140, 146), -- pale grey
	Color3.fromRGB(112, 96, 86), -- weathered brick-brown
	Color3.fromRGB(104, 116, 118), -- glass green-grey
}
local BRICK_COLOURS = {
	Color3.fromRGB(126, 82, 66),
	Color3.fromRGB(146, 100, 78),
	Color3.fromRGB(108, 74, 62),
}
local GLASS_COLOUR = Color3.fromRGB(140, 168, 178)
local TRIM_DARK = Color3.fromRGB(58, 62, 70)

--[[
	Window banding.

	Rather than model individual windows (which at this scale would be tens of
	thousands of parts), each tower gets horizontal glass bands every few
	studs. At any distance a real facade reads as horizontal striping, not as
	a grid of squares, so this is both cheaper and more convincing.
]]
local function addWindowBands(
	model: Model,
	base: Vector3,
	width: number,
	depth: number,
	fromY: number,
	toY: number,
	rng: Random,
	name: string
)
	local spacing = rng:NextNumber(7, 11)
	local y = fromY + spacing * 0.6
	local index = 0
	while y < toY - 2 do
		index += 1
		-- Lit floors are emissive so the distant skyline has occupancy too,
		-- which is most of what makes a far-off tower look inhabited.
		local lit = rng:NextNumber() < 0.3
		PartUtils.CreatePart({
			name = ("%sBand%d"):format(name, index),
			-- Slightly proud of the facade so the band catches its own light.
			size = Vector3.new(width * 1.01, spacing * 0.42, depth * 1.01),
			position = base + Vector3.new(0, y, 0),
			material = if lit then Enum.Material.Neon else Enum.Material.Glass,
			color = if lit then Color3.fromRGB(226, 236, 244) else GLASS_COLOUR,
			transparency = if lit then 0.2 else 0.25,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
		y += spacing
	end
end

-- Flat roof furniture: parapet, water tank, rooftop plant, and the cluster
-- of mechanical kit every real roof carries. A bare slab top is one of the
-- clearest tells that a building is a prop.
local function addRoofDetail(model: Model, base: Vector3, width: number, depth: number, topY: number, rng: Random, name: string)
	PartUtils.CreatePart({
		name = name .. "Parapet",
		size = Vector3.new(width * 1.06, 2.4, depth * 1.06),
		position = base + Vector3.new(0, topY + 1.2, 0),
		material = Enum.Material.Concrete,
		color = TRIM_DARK,
		canCollide = false,
		castShadow = false,
		parent = model,
	})

	-- Recessed roof deck, so the parapet reads as a wall around a surface
	-- rather than a lip on a solid block.
	PartUtils.CreatePart({
		name = name .. "RoofDeck",
		size = Vector3.new(width * 0.98, 0.8, depth * 0.98),
		position = base + Vector3.new(0, topY + 0.4, 0),
		material = Enum.Material.Concrete,
		color = Color3.fromRGB(74, 76, 80),
		canCollide = false,
		castShadow = false,
		parent = model,
	})

	-- Bulkhead: the stair/lift overrun. Every tall building has one and it is
	-- always the tallest thing on an otherwise flat roof.
	PartUtils.CreatePart({
		name = name .. "Bulkhead",
		size = Vector3.new(width * 0.3, 9, depth * 0.3),
		position = base + Vector3.new(width * 0.16, topY + 4.5, -depth * 0.14),
		material = Enum.Material.Concrete,
		color = Color3.fromRGB(88, 90, 94),
		canCollide = false,
		castShadow = false,
		parent = model,
	})

	-- HVAC units, scattered.
	for u = 1, rng:NextInteger(2, 4) do
		PartUtils.CreatePart({
			name = name .. "HVAC",
			size = Vector3.new(rng:NextNumber(5, 9), rng:NextNumber(2.5, 4.5), rng:NextNumber(4, 8)),
			position = base
				+ Vector3.new(
					rng:NextNumber(-width * 0.32, width * 0.32),
					topY + 2.4,
					rng:NextNumber(-depth * 0.32, depth * 0.32)
				),
			material = Enum.Material.CorrodedMetal,
			color = Color3.fromRGB(126, 128, 130),
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end

	if rng:NextNumber() < 0.6 then
		local tankW = math.min(width, depth) * 0.28
		-- The classic New York rooftop water tank, on its timber legs.
		for leg = 1, 4 do
			local a = (math.pi / 2) * leg + math.pi / 4
			PartUtils.CreatePart({
				name = name .. "TankLeg",
				size = Vector3.new(0.7, 6, 0.7),
				position = base
					+ Vector3.new(-width * 0.2 + math.sin(a) * tankW * 0.35, topY + 3, depth * 0.16 + math.cos(a) * tankW * 0.35),
				material = Enum.Material.WoodPlanks,
				color = Color3.fromRGB(82, 60, 48),
				canCollide = false,
				castShadow = false,
				parent = model,
			})
		end
		PartUtils.CreatePart({
			name = name .. "WaterTank",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(tankW * 1.5, tankW, tankW),
			cframe = CFrame.new(base + Vector3.new(-width * 0.2, topY + 6 + tankW * 0.75, depth * 0.16))
				* CFrame.Angles(0, 0, math.rad(90)),
			material = Enum.Material.WoodPlanks,
			color = Color3.fromRGB(92, 68, 54),
			canCollide = false,
			castShadow = false,
			parent = model,
		})
		-- Conical lid.
		PartUtils.CreatePart({
			name = name .. "TankLid",
			size = Vector3.new(tankW * 0.9, 1.6, tankW * 0.9),
			position = base + Vector3.new(-width * 0.2, topY + 6 + tankW * 1.5, depth * 0.16),
			material = Enum.Material.Metal,
			color = Color3.fromRGB(70, 72, 76),
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
end

--[[
	One tower. `archetype` selects the profile; everything else is derived.

	All city geometry is CanCollide = false and CastShadow = false: it sits
	beyond the boundary wall where no player can reach, so collision would
	only cost physics memory, and shadows from a thousand towers would cost
	frames for no visible gain.
]]
--[[
	FACADE DETAIL.

	A flat slab with horizontal glass stripes is readable at a distance but
	falls apart close up, because real facades have DEPTH: the wall plane sits
	behind a grid of structure, and it is the shadow in those recesses that
	makes a building look built rather than printed.

	Three layers below, applied per facade section:

	  SPANDRELS   the solid band between windows, set slightly proud of the
	              glass so each floor line casts a shadow.
	  MULLIONS    vertical structural fins running the full height, which is
	              what gives a tower its verticality - the single strongest
	              cue that something is tall.
	  CORNERS     darker quoin strips at the four vertical edges, so the
	              silhouette has a defined edge instead of dissolving into
	              the sky.
]]
local function addFacadeDetail(
	model: Model,
	base: Vector3,
	width: number,
	depth: number,
	fromY: number,
	toY: number,
	facade: Color3,
	rng: Random,
	name: string
)
	local height = toY - fromY
	if height < 6 then
		return
	end

	local floorHeight = rng:NextNumber(8, 11)
	local floors = math.max(1, math.floor(height / floorHeight))
	floorHeight = height / floors

	-- Darker tone for the recessed glazing, lighter for the spandrel, so the
	-- two read as different materials rather than the same wall striped.
	local glassTone = Color3.new(facade.R * 0.42, facade.G * 0.48, facade.B * 0.58)
	local spandrel = Color3.new(
		math.clamp(facade.R * 1.06, 0, 1),
		math.clamp(facade.G * 1.06, 0, 1),
		math.clamp(facade.B * 1.04, 0, 1)
	)

	--[[
		OCCUPANCY. A fraction of floors are LIT from inside.

		This is the single strongest "this building has people in it" cue there
		is, and its absence is why the city read as a model: every window being
		uniformly dark is something that never happens in a real skyline.

		The fraction varies per tower rather than per floor, so a building is
		mostly busy or mostly empty instead of every tower averaging the same -
		which is what makes the skyline read as many separate buildings.
	]]
	local litFraction = rng:NextNumber(0.12, 0.55)
	local WARM = Color3.fromRGB(255, 232, 176)
	local COOL = Color3.fromRGB(214, 232, 246) -- fluorescent office lighting

	for f = 0, floors - 1 do
		local y = fromY + f * floorHeight

		--[[
			WEATHERING. Facades darken toward street level, where decades of soot
			and road spray collect. A perfectly even tone from pavement to roof
			is one of the clearest signs a building was generated.
		]]
		local grimeT = 1 - math.clamp(y / math.max(height, 1), 0, 1)
		local grime = 1 - grimeT * 0.16

		local lit = rng:NextNumber() < litFraction
		local paneColour = if lit
			then (if rng:NextNumber() < 0.7 then COOL else WARM)
			else Color3.new(glassTone.R * grime, glassTone.G * grime, glassTone.B * grime)

		-- Recessed window band: INSET, so the structure around it stands proud
		-- and catches light. Inset is the whole point - a band that sticks out
		-- looks like a stripe painted on.
		PartUtils.CreatePart({
			name = ("%sGlass%d"):format(name, f),
			size = Vector3.new(width * 0.965, floorHeight * 0.6, depth * 0.965),
			position = base + Vector3.new(0, y + floorHeight * 0.42, 0),
			-- Lit floors are emissive; dark ones stay glass so they still
			-- reflect the sky rather than reading as painted panels.
			material = if lit then Enum.Material.Neon else Enum.Material.Glass,
			color = paneColour,
			transparency = if lit then 0.12 else 0.22,
			canCollide = false,
			castShadow = false,
			parent = model,
		})

		-- Spandrel band at each floor line, proud of the glass, grimed toward
		-- the base along with everything else.
		PartUtils.CreatePart({
			name = ("%sSpandrel%d"):format(name, f),
			size = Vector3.new(width * 1.012, floorHeight * 0.34, depth * 1.012),
			position = base + Vector3.new(0, y + floorHeight * 0.06, 0),
			material = Enum.Material.Concrete,
			color = Color3.new(spandrel.R * grime, spandrel.G * grime, spandrel.B * grime),
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end

	--[[
		VERTICAL MULLIONS on all four faces. Spaced by width so a wide tower
		gets more fins than a narrow one - the rhythm stays constant rather
		than the count.
	]]
	local spacingX = math.max(7, width / math.max(3, math.floor(width / 9)))
	local countX = math.max(2, math.floor(width / spacingX))
	for m = 0, countX do
		local x = -width / 2 + (width / countX) * m
		for _, side in ipairs({ -1, 1 }) do
			PartUtils.CreatePart({
				name = ("%sMullion"):format(name),
				size = Vector3.new(0.9, height, 0.9),
				position = base + Vector3.new(x, fromY + height / 2, side * depth / 2),
				material = Enum.Material.Metal,
				color = spandrel,
				canCollide = false,
				castShadow = false,
				parent = model,
			})
		end
	end
	local spacingZ = math.max(7, depth / math.max(3, math.floor(depth / 9)))
	local countZ = math.max(2, math.floor(depth / spacingZ))
	for m = 0, countZ do
		local z = -depth / 2 + (depth / countZ) * m
		for _, side in ipairs({ -1, 1 }) do
			PartUtils.CreatePart({
				name = ("%sMullion"):format(name),
				size = Vector3.new(0.9, height, 0.9),
				position = base + Vector3.new(side * width / 2, fromY + height / 2, z),
				material = Enum.Material.Metal,
				color = spandrel,
				canCollide = false,
				castShadow = false,
				parent = model,
			})
		end
	end

	-- CORNER QUOINS: a darker vertical strip at each of the four edges.
	local cornerTone = Color3.new(facade.R * 0.78, facade.G * 0.78, facade.B * 0.8)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			PartUtils.CreatePart({
				name = name .. "Corner",
				size = Vector3.new(2.4, height, 2.4),
				position = base + Vector3.new(sx * width / 2, fromY + height / 2, sz * depth / 2),
				material = Enum.Material.Concrete,
				color = cornerTone,
				canCollide = false,
				castShadow = false,
				parent = model,
			})
		end
	end
end

--[[
	GROUND-FLOOR STOREFRONT.

	The single most important detail for making a tower meet the street
	convincingly. Real buildings do not continue their facade to the pavement:
	they have a taller, glassier retail floor with a canopy and a sign band.
	Without it a tower looks like it was pushed into the ground.
]]
local function addStorefront(model: Model, base: Vector3, width: number, depth: number, rng: Random, name: string)
	local shopHeight = 16

	-- Dark recessed glazing, inset so the floor above visibly overhangs it.
	PartUtils.CreatePart({
		name = name .. "Storefront",
		size = Vector3.new(width * 0.94, shopHeight, depth * 0.94),
		position = base + Vector3.new(0, shopHeight / 2, 0),
		material = Enum.Material.Glass,
		color = Color3.fromRGB(48, 56, 64),
		transparency = 0.15,
		canCollide = false,
		castShadow = false,
		parent = model,
	})

	-- Canopy over the pavement on all four sides.
	PartUtils.CreatePart({
		name = name .. "Canopy",
		size = Vector3.new(width * 1.14, 1.1, depth * 1.14),
		position = base + Vector3.new(0, shopHeight, 0),
		material = Enum.Material.Metal,
		color = TRIM_DARK,
		canCollide = false,
		castShadow = false,
		parent = model,
	})

	-- Lit sign band above the canopy - the row of shopfront signage that
	-- makes a street feel occupied rather than abandoned.
	local signColour = ({
		Color3.fromRGB(214, 78, 66),
		Color3.fromRGB(70, 132, 196),
		Color3.fromRGB(224, 176, 62),
		Color3.fromRGB(88, 168, 124),
	})[rng:NextInteger(1, 4)]
	PartUtils.CreatePart({
		name = name .. "SignBand",
		size = Vector3.new(width * 1.02, 2.6, depth * 1.02),
		position = base + Vector3.new(0, shopHeight + 2, 0),
		material = Enum.Material.Neon,
		color = signColour,
		transparency = 0.35,
		canCollide = false,
		castShadow = false,
		parent = model,
	})

	return shopHeight + 3
end

-- Projecting ledge. Real facades break up with cornices; a continuous
-- unbroken wall is what makes a box read as a box.
local function addCornice(model: Model, base: Vector3, width: number, depth: number, y: number, name: string)
	PartUtils.CreatePart({
		name = name .. "Cornice",
		size = Vector3.new(width * 1.07, 1.8, depth * 1.07),
		position = base + Vector3.new(0, y, 0),
		material = Enum.Material.Concrete,
		color = TRIM_DARK,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
end

-- Roof mast/antenna. Gives the far towers a broken, spiky skyline edge
-- instead of a row of flat tops.
local function addAntenna(model: Model, base: Vector3, topY: number, height: number, rng: Random, name: string)
	PartUtils.CreatePart({
		name = name .. "Mast",
		size = Vector3.new(1.4, height, 1.4),
		position = base + Vector3.new(rng:NextNumber(-4, 4), topY + height / 2, rng:NextNumber(-4, 4)),
		material = Enum.Material.Metal,
		color = Color3.fromRGB(70, 74, 82),
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	-- Aircraft warning light.
	PartUtils.CreatePart({
		name = name .. "AviationLight",
		shape = Enum.PartType.Ball,
		size = Vector3.new(2.2, 2.2, 2.2),
		position = base + Vector3.new(0, topY + height, 0),
		material = Enum.Material.Neon,
		color = Color3.fromRGB(226, 62, 52),
		canCollide = false,
		castShadow = false,
		parent = model,
	})
end

local function buildTower(
	position: Vector3,
	width: number,
	depth: number,
	height: number,
	archetype: string,
	rng: Random,
	parent: Instance,
	name: string
)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local facade = FACADE_COLOURS[rng:NextInteger(1, #FACADE_COLOURS)]

	-- Every tower meets the street with a retail floor. `groundY` is where the
	-- facade proper starts, so window banding never runs down over the shops.
	local groundY = addStorefront(model, position, width, depth, rng, name)

	--[[
		LEVEL OF DETAIL.

		Full facade detail (per-floor glazing, spandrels, mullions, corner
		quoins) is roughly 40 parts per storey-stage. Applied to all 250 towers
		that would be ~85,000 parts for detail nobody can resolve on a building
		half a kilometre away.

		So the near city - everything inside 620 studs, which is what you
		actually walk up to and look at - gets the full treatment, and the
		distant rows keep the cheap horizontal banding that already reads
		correctly at that range. The visual difference at the LOD boundary is
		invisible; the part-count difference is about 4x.
	]]
	local DETAIL_RADIUS = 620
	local isNear = math.sqrt(position.X * position.X + position.Z * position.Z) < DETAIL_RADIUS

	local function facadeOf(w: number, d: number, fromY: number, toY: number, colour: Color3, suffix: string)
		if isNear then
			addFacadeDetail(model, position, w, d, fromY, toY, colour, rng, name .. suffix)
		else
			addWindowBands(model, position, w, d, fromY, toY, rng, name .. suffix)
		end
	end

	local function slab(w: number, d: number, fromY: number, toY: number, colour: Color3, suffix: string)
		PartUtils.CreatePart({
			name = name .. suffix,
			size = Vector3.new(w, toY - fromY, d),
			position = position + Vector3.new(0, (fromY + toY) / 2, 0),
			material = Enum.Material.Concrete,
			color = colour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end

	if archetype == "SETBACK" or archetype == "ARTDECO" then
		--[[
			Stepped ziggurat. Each stage is shorter and narrower than the one
			below, which is the profile the 1916 New York zoning law produced
			and the single most recognisable pre-war Manhattan silhouette.
		]]
		local stages = rng:NextInteger(3, 5)
		local y = groundY
		local w, d = width, depth
		for s = 1, stages do
			local stageHeight = height * (0.42 / stages + (stages - s) * 0.16 / stages) + height * 0.1
			slab(w, d, y, y + stageHeight, facade, "Stage" .. s)
			facadeOf(w, d, y, y + stageHeight, facade, "S" .. s)
			-- Cornice at every setback, which is what gives the pre-war profile
			-- its stacked, layered look rather than a smooth taper.
			addCornice(model, position, w, d, y + stageHeight, name .. "S" .. s)
			y += stageHeight
			w *= rng:NextNumber(0.7, 0.84)
			d *= rng:NextNumber(0.7, 0.84)
		end
		addRoofDetail(model, position, w, d, y, rng, name)

		if archetype == "ARTDECO" then
			-- Crown: a short stack of shrinking discs and a mast, the
			-- Chrysler/Empire State finish.
			local crownW = w
			for c = 1, 5 do
				local ch = height * 0.028
				PartUtils.CreatePart({
					name = ("%sCrown%d"):format(name, c),
					size = Vector3.new(crownW, ch, crownW),
					position = position + Vector3.new(0, y + ch * (c - 0.5), 0),
					material = Enum.Material.Metal,
					color = Color3.fromRGB(168, 172, 178),
					canCollide = false,
					castShadow = false,
					parent = model,
				})
				crownW *= 0.72
			end
			PartUtils.CreatePart({
				name = name .. "Spire",
				size = Vector3.new(2.2, height * 0.16, 2.2),
				position = position + Vector3.new(0, y + height * 0.08 + height * 0.028 * 5, 0),
				material = Enum.Material.Metal,
				color = Color3.fromRGB(186, 190, 196),
				canCollide = false,
				castShadow = false,
				parent = model,
			})
		end
	elseif archetype == "TAPERED" then
		-- Modern supertall: continuous narrowing over many thin stages.
		local stages = 9
		local y = groundY
		for s = 1, stages do
			local f = (s - 1) / stages
			local w = width * (1 - f * 0.4)
			local d = depth * (1 - f * 0.4)
			local stageHeight = (height - groundY) / stages
			slab(w, d, y, y + stageHeight, facade, "Taper" .. s)
			facadeOf(w, d, y, y + stageHeight, facade, "T" .. s)
			y += stageHeight
		end
		addRoofDetail(model, position, width * 0.6, depth * 0.6, y, rng, name)
		-- Supertalls carry masts; this is what breaks the far skyline.
		addAntenna(model, position, y, height * 0.14, rng, name)
	elseif archetype == "TWISTED" then
		-- Contemporary rotated-floorplate tower: each stage yawed a few
		-- degrees off the one below.
		local stages = 12
		local stageHeight = (height - groundY) / stages
		for s = 1, stages do
			local f = (s - 1) / stages
			local w = width * (1 - f * 0.22)
			local d = depth * (1 - f * 0.22)
			PartUtils.CreatePart({
				name = ("%sTwist%d"):format(name, s),
				size = Vector3.new(w, stageHeight * 1.02, d),
				cframe = CFrame.new(position + Vector3.new(0, groundY + stageHeight * (s - 0.5), 0))
					* CFrame.Angles(0, math.rad(f * 42), 0),
				material = Enum.Material.Glass,
				color = GLASS_COLOUR,
				transparency = 0.12,
				canCollide = false,
				castShadow = false,
				parent = model,
			})
		end
		addRoofDetail(model, position, width * 0.78, depth * 0.78, height, rng, name)
	elseif archetype == "BRICK" then
		-- Low pre-war infill. Fills the gaps so the skyline has a base.
		local brick = BRICK_COLOURS[rng:NextInteger(1, #BRICK_COLOURS)]
		slab(width, depth, groundY, height, brick, "Block")
		-- Same brick tone for the detail, so the facade reads as one material.
		facadeOf(width, depth, groundY, height, brick, "B")
		addCornice(model, position, width, depth, height, name)
		addRoofDetail(model, position, width, depth, height, rng, name)

		--[[
			FIRE ESCAPE. The definitive New York low-rise detail - a zigzag of
			landings down one face. Nothing else says "pre-war Manhattan block"
			as immediately.
		]]
		if rng:NextNumber() < 0.7 then
			local landings = math.floor((height - groundY) / 18)
			for l = 1, landings do
				local y = groundY + l * 18
				PartUtils.CreatePart({
					name = name .. "FireEscape",
					size = Vector3.new(width * 0.42, 0.5, 4),
					position = position + Vector3.new(0, y, depth / 2 + 2),
					material = Enum.Material.DiamondPlate,
					color = Color3.fromRGB(44, 46, 50),
					canCollide = false,
					castShadow = false,
					parent = model,
				})
				-- Rail, so the landing is not a bare shelf.
				PartUtils.CreatePart({
					name = name .. "FireEscapeRail",
					size = Vector3.new(width * 0.42, 3, 0.3),
					position = position + Vector3.new(0, y + 1.7, depth / 2 + 3.8),
					material = Enum.Material.DiamondPlate,
					color = Color3.fromRGB(44, 46, 50),
					canCollide = false,
					castShadow = false,
					parent = model,
				})
			end
		end
	else -- GLASSBOX
		-- International style: a plain curtain-wall slab on a darker podium.
		local podium = groundY + height * 0.05
		slab(width * 1.12, depth * 1.12, groundY, podium, TRIM_DARK, "Podium")
		PartUtils.CreatePart({
			name = name .. "Tower",
			size = Vector3.new(width, height - podium, depth),
			position = position + Vector3.new(0, (podium + height) / 2, 0),
			material = Enum.Material.Glass,
			color = GLASS_COLOUR,
			transparency = 0.15,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
		-- Vertical mullions, the defining detail of a Seagram-type facade.
		facadeOf(width, depth, podium, height, GLASS_COLOUR, "G")
		addRoofDetail(model, position, width, depth, height, rng, name)
	end
end

--[[
	THE CITY.

	Concentric rows of towers. Height rises with distance so the near rows
	never hide the far ones, and every row is angularly offset from the last
	so you are always looking down a street rather than at a wall.
]]
--[[
	CITY GROUND: streets, sidewalks and traffic.

	Without this the towers appear to FLOAT - they rise out of nothing,
	because the plaza's own ground ends at the boundary and there is no
	surface underneath the city at all. Everything here exists to give them
	something to stand on and a street grid to stand along.

	Built in layers, cheapest first:
	  1. One large sidewalk-coloured plate under the whole city.
	  2. Radial AVENUES running out from the plaza, and concentric CROSS
	     STREETS, in darker asphalt on top of it.
	  3. Lane markings, crosswalks at the intersections.
	  4. Street furniture and traffic - lamps, and cars along the avenues.

	The grid is radial rather than square because the city is a ring: streets
	that run outward from the centre naturally line up with the gaps between
	tower rows, so you end up looking down a street from the plaza rather than
	at the side of a building.

	All of it is CanCollide = false and CastShadow = false - it sits beyond
	the boundary wall where no player can reach.
]]

local ASPHALT = Color3.fromRGB(58, 60, 64)
local SIDEWALK = Color3.fromRGB(146, 146, 142)
local LANE_PAINT = Color3.fromRGB(214, 196, 120)
local CROSSWALK = Color3.fromRGB(206, 206, 200)

local AVENUES = 16 -- radial streets
local AVENUE_WIDTH = 30

local CAR_COLOURS = {
	Color3.fromRGB(198, 62, 54),
	Color3.fromRGB(232, 226, 218),
	Color3.fromRGB(38, 42, 52),
	Color3.fromRGB(52, 88, 148),
	Color3.fromRGB(216, 168, 48), -- the obligatory yellow cab
	Color3.fromRGB(216, 168, 48),
}

local function buildCityGround(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "CityGround"
	folder.Parent = parent

	local rng = Random.new(661204)

	--[[
		1. BASE PLATE. One disc under everything, top just below y=0 so it sits
		flush with the plaza floor without z-fighting against LobbyGround
		(which shares that exact height). The plaza covers the middle of it, so
		only the ring beyond the boundary is ever seen.
	]]
	PartUtils.CreateDisc({
		name = "CityBasePlate",
		diameter = ENCLOSURE_RADIUS * 2,
		thickness = 6,
		position = Vector3.new(0, -3.2, 0),
		material = Enum.Material.Concrete,
		color = SIDEWALK,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})

	-- 2a. RADIAL AVENUES.
	local roadStart = 150 -- starts under the plaza edge so streets run out of it
	local roadEnd = ENCLOSURE_RADIUS - 10
	for a = 1, AVENUES do
		local angle = (a - 1) / AVENUES * math.pi * 2
		local length = roadEnd - roadStart
		local mid = (roadStart + roadEnd) / 2
		local centre = Vector3.new(math.sin(angle) * mid, -0.05, math.cos(angle) * mid)

		PartUtils.CreatePart({
			name = ("Avenue%d"):format(a),
			size = Vector3.new(AVENUE_WIDTH, 0.4, length),
			cframe = CFrame.new(centre) * CFrame.Angles(0, angle, 0),
			material = Enum.Material.Asphalt,
			color = ASPHALT,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})

		-- Dashed centre line.
		local dashes = math.floor(length / 26)
		for d = 1, dashes do
			local along = roadStart + (length / dashes) * (d - 0.5)
			PartUtils.CreatePart({
				name = "LaneDash",
				size = Vector3.new(0.9, 0.1, 9),
				cframe = CFrame.new(Vector3.new(math.sin(angle) * along, 0.18, math.cos(angle) * along))
					* CFrame.Angles(0, angle, 0),
				material = Enum.Material.SmoothPlastic,
				color = LANE_PAINT,
				canCollide = false,
				castShadow = false,
				parent = folder,
			})
		end

		-- 4a. STREET LAMPS down both kerbs.
		for s = 1, math.floor(length / 90) do
			local along = roadStart + (length / math.floor(length / 90)) * (s - 0.5)
			for _, side in ipairs({ -1, 1 }) do
				local off = CFrame.new(Vector3.new(math.sin(angle) * along, 0, math.cos(angle) * along))
					* CFrame.Angles(0, angle, 0)
					* CFrame.new(side * (AVENUE_WIDTH / 2 + 3), 0, 0)
				PartUtils.CreatePart({
					name = "StreetLampPost",
					size = Vector3.new(0.8, 22, 0.8),
					cframe = off * CFrame.new(0, 11, 0),
					material = Enum.Material.Metal,
					color = Color3.fromRGB(46, 48, 54),
					canCollide = false,
					castShadow = false,
					parent = folder,
				})
				PartUtils.CreatePart({
					name = "StreetLampHead",
					size = Vector3.new(5, 0.8, 1.6),
					-- Arm reaches out over the roadway, as a real cobra-head does.
					cframe = off * CFrame.new(-side * 2.2, 21.6, 0),
					material = Enum.Material.Metal,
					color = Color3.fromRGB(46, 48, 54),
					canCollide = false,
					castShadow = false,
					parent = folder,
				})
			end
		end

		--[[
			4c. SIDEWALK LIFE.

			The details that separate "a road with buildings beside it" from a
			street people use. Placed along both kerbs, spaced out so they read
			as incidental rather than as a repeating pattern.
		]]
		local furnitureSpacing = 120
		for s = 1, math.floor(length / furnitureSpacing) do
			local along = roadStart + furnitureSpacing * (s - 0.5)
			for _, side in ipairs({ -1, 1 }) do
				local kerb = CFrame.new(Vector3.new(math.sin(angle) * along, 0, math.cos(angle) * along))
					* CFrame.Angles(0, angle, 0)
					* CFrame.new(side * (AVENUE_WIDTH / 2 + 6), 0, 0)

				local pick = rng:NextInteger(1, 4)
				if pick == 1 then
					-- Street tree in a planter: the most common thing on any
					-- Manhattan sidewalk.
					PartUtils.CreatePart({
						name = "TreePlanter",
						size = Vector3.new(6, 1.6, 6),
						cframe = kerb * CFrame.new(0, 0.8, 0),
						material = Enum.Material.Concrete,
						color = Color3.fromRGB(96, 96, 92),
						canCollide = false,
						castShadow = false,
						parent = folder,
					})
					PartUtils.CreatePart({
						name = "TreeTrunk",
						size = Vector3.new(1.2, 12, 1.2),
						cframe = kerb * CFrame.new(0, 7, 0),
						material = Enum.Material.Wood,
						color = Color3.fromRGB(84, 62, 46),
						canCollide = false,
						castShadow = false,
						parent = folder,
					})
					for c = 1, 3 do
						PartUtils.CreatePart({
							name = "TreeCanopy",
							size = Vector3.new(rng:NextNumber(8, 12), rng:NextNumber(5, 8), rng:NextNumber(8, 12)),
							cframe = kerb
								* CFrame.new(rng:NextNumber(-2, 2), 13 + c * 2.5, rng:NextNumber(-2, 2)),
							material = Enum.Material.Grass,
							color = Color3.fromRGB(66, 96, 58),
							canCollide = false,
							castShadow = false,
							parent = folder,
						})
					end
				elseif pick == 2 then
					-- Traffic signal on a mast arm over the roadway.
					PartUtils.CreatePart({
						name = "SignalPost",
						size = Vector3.new(0.9, 26, 0.9),
						cframe = kerb * CFrame.new(0, 13, 0),
						material = Enum.Material.Metal,
						color = Color3.fromRGB(52, 60, 52),
						canCollide = false,
						castShadow = false,
						parent = folder,
					})
					PartUtils.CreatePart({
						name = "SignalArm",
						size = Vector3.new(14, 0.7, 0.7),
						cframe = kerb * CFrame.new(-side * 7, 25, 0),
						material = Enum.Material.Metal,
						color = Color3.fromRGB(52, 60, 52),
						canCollide = false,
						castShadow = false,
						parent = folder,
					})
					-- Head with one lamp lit, chosen per signal.
					local state = rng:NextInteger(1, 3)
					local lampColours = {
						Color3.fromRGB(220, 52, 44),
						Color3.fromRGB(228, 172, 44),
						Color3.fromRGB(60, 200, 96),
					}
					PartUtils.CreatePart({
						name = "SignalHead",
						size = Vector3.new(2.2, 6, 1.8),
						cframe = kerb * CFrame.new(-side * 13, 22, 0),
						material = Enum.Material.Metal,
						color = Color3.fromRGB(38, 44, 38),
						canCollide = false,
						castShadow = false,
						parent = folder,
					})
					PartUtils.CreatePart({
						name = "SignalLamp",
						shape = Enum.PartType.Ball,
						size = Vector3.new(1.5, 1.5, 1.5),
						cframe = kerb * CFrame.new(-side * 13, 24 - state * 2, -0.9),
						material = Enum.Material.Neon,
						color = lampColours[state],
						canCollide = false,
						castShadow = false,
						parent = folder,
					})
				elseif pick == 3 then
					-- Bus shelter.
					PartUtils.CreatePart({
						name = "ShelterRoof",
						size = Vector3.new(5, 0.5, 16),
						cframe = kerb * CFrame.new(0, 10, 0),
						material = Enum.Material.Metal,
						color = Color3.fromRGB(48, 52, 58),
						canCollide = false,
						castShadow = false,
						parent = folder,
					})
					PartUtils.CreatePart({
						name = "ShelterGlass",
						size = Vector3.new(0.3, 9, 16),
						cframe = kerb * CFrame.new(side * 2.3, 5, 0),
						material = Enum.Material.Glass,
						color = Color3.fromRGB(180, 200, 210),
						transparency = 0.5,
						canCollide = false,
						castShadow = false,
						parent = folder,
					})
					-- Lit ad panel at one end - the glow that makes a shelter
					-- read at night and from a distance.
					PartUtils.CreatePart({
						name = "ShelterAd",
						size = Vector3.new(0.4, 7, 4),
						cframe = kerb * CFrame.new(side * 2.3, 5, 7),
						material = Enum.Material.Neon,
						color = Color3.fromRGB(240, 236, 210),
						transparency = 0.25,
						canCollide = false,
						castShadow = false,
						parent = folder,
					})
				else
					-- Hydrant and a couple of bins: small, but they scale the
					-- street. Without something person-sized on the pavement the
					-- towers have nothing to be tall against.
					PartUtils.CreatePart({
						name = "Hydrant",
						size = Vector3.new(1.2, 3.2, 1.2),
						cframe = kerb * CFrame.new(0, 1.6, 0),
						material = Enum.Material.Metal,
						color = Color3.fromRGB(198, 66, 52),
						canCollide = false,
						castShadow = false,
						parent = folder,
					})
					for bin = 1, 2 do
						PartUtils.CreatePart({
							name = "TrashBin",
							shape = Enum.PartType.Cylinder,
							size = Vector3.new(4.5, 3.4, 3.4),
							cframe = kerb
								* CFrame.new(rng:NextNumber(-2, 2), 2.25, 8 + bin * 5)
								* CFrame.Angles(0, 0, math.rad(90)),
							material = Enum.Material.DiamondPlate,
							color = Color3.fromRGB(58, 64, 58),
							canCollide = false,
							castShadow = false,
							parent = folder,
						})
					end
				end
			end
		end

		-- 4d. TRAFFIC. Cars parked and stopped along the avenue.
		for v = 1, rng:NextInteger(5, 10) do
			local along = rng:NextNumber(roadStart + 40, roadEnd - 40)
			local lane = if rng:NextNumber() < 0.5 then -1 else 1
			local base = CFrame.new(Vector3.new(math.sin(angle) * along, 0, math.cos(angle) * along))
				* CFrame.Angles(0, angle, 0)
				* CFrame.new(lane * rng:NextNumber(5, 11), 0, 0)
			local colour = CAR_COLOURS[rng:NextInteger(1, #CAR_COLOURS)]
			local carLength = rng:NextNumber(11, 15)

			PartUtils.CreatePart({
				name = "CarBody",
				size = Vector3.new(5.2, 3.2, carLength),
				cframe = base * CFrame.new(0, 1.8, 0),
				material = Enum.Material.SmoothPlastic,
				color = colour,
				canCollide = false,
				castShadow = false,
				parent = folder,
			})
			-- Cabin, set back so the silhouette reads as a car not a brick.
			PartUtils.CreatePart({
				name = "CarCabin",
				size = Vector3.new(4.8, 2.4, carLength * 0.45),
				cframe = base * CFrame.new(0, 4.4, -carLength * 0.05),
				material = Enum.Material.Glass,
				color = Color3.fromRGB(70, 84, 96),
				transparency = 0.25,
				canCollide = false,
				castShadow = false,
				parent = folder,
			})
		end
	end

	-- 2b. CONCENTRIC CROSS STREETS, one between each tower row.
	for row = 1, ROWS do
		local f = (row - 1) / (ROWS - 1)
		local radius = CITY_INNER + (CITY_OUTER - CITY_INNER) * f - 46
		if radius > roadStart then
			local segments = math.max(28, math.floor(2 * math.pi * radius / 46))
			for s = 1, segments do
				local a1 = (s - 1) / segments * math.pi * 2
				local a2 = s / segments * math.pi * 2
				local v1 = Vector3.new(math.sin(a1) * radius, 0, math.cos(a1) * radius)
				local v2 = Vector3.new(math.sin(a2) * radius, 0, math.cos(a2) * radius)
				local mid = (v1 + v2) / 2
				local part = PartUtils.CreatePart({
					name = ("CrossStreet%d"):format(row),
					-- 1.05 overlap so the ring has no gaps at the joints.
					size = Vector3.new(24, 0.4, (v2 - v1).Magnitude * 1.05),
					material = Enum.Material.Asphalt,
					color = ASPHALT,
					canCollide = false,
					castShadow = false,
					parent = folder,
				})
				part.CFrame = CFrame.lookAt(mid + Vector3.new(0, -0.05, 0), v2) * CFrame.Angles(0, 0, 0)
			end

			-- 3. CROSSWALKS where each avenue meets this cross street: a ladder
			-- of white bars, which is the most recognisable street marking there
			-- is and instantly reads as "intersection".
			for a = 1, AVENUES do
				local angle = (a - 1) / AVENUES * math.pi * 2
				for bar = -3, 3 do
					PartUtils.CreatePart({
						name = "Crosswalk",
						size = Vector3.new(2.2, 0.1, 16),
						cframe = CFrame.new(Vector3.new(math.sin(angle) * (radius + 20), 0.2, math.cos(angle) * (radius + 20)))
							* CFrame.Angles(0, angle, 0)
							* CFrame.new(bar * 3.6, 0, 0),
						material = Enum.Material.SmoothPlastic,
						color = CROSSWALK,
						canCollide = false,
						castShadow = false,
						parent = folder,
					})
				end
			end
		end
	end
end

local function buildCity(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "CitySkyline"
	folder.Parent = parent

	local rng = Random.new(770211)

	local ARCHETYPES = { "SETBACK", "ARTDECO", "GLASSBOX", "TAPERED", "TWISTED", "BRICK" }

	for row = 1, ROWS do
		local f = (row - 1) / (ROWS - 1)
		local radius = CITY_INNER + (CITY_OUTER - CITY_INNER) * f

		-- More buildings per row further out, so density stays even as the
		-- circumference grows.
		local count = math.floor(16 + f * 40)
		-- Offset each row so towers are never radially aligned - that is what
		-- creates the impression of streets between them.
		local rowOffset = rng:NextNumber(0, math.pi * 2)

		for i = 1, count do
			local angle = (i - 1) / count * math.pi * 2 + rowOffset + rng:NextNumber(-0.03, 0.03)
			local r = radius + rng:NextNumber(-42, 42)
			local pos = Vector3.new(math.sin(angle) * r, 0, math.cos(angle) * r)

			--[[
				HEIGHT. Rises steeply with distance. The near rows are 180-320
				studs; the far rows reach 1000, which is well past the top of
				the view from the plaza - so the city closes over you instead
				of sitting on the horizon.
			]]
			local base = 170 + f * 620
			local height = base * rng:NextNumber(0.75, 1.5)

			-- Archetype by distance: low brick close in, supertalls behind.
			local archetype
			if f < 0.25 then
				archetype = if rng:NextNumber() < 0.55 then "BRICK" else "SETBACK"
			elseif f < 0.6 then
				archetype = ARCHETYPES[rng:NextInteger(1, 4)]
			else
				-- Far rows: the dramatic profiles, since these are the ones
				-- breaking the skyline.
				archetype = ({ "ARTDECO", "TAPERED", "TWISTED", "SETBACK" })[rng:NextInteger(1, 4)]
			end
			if archetype == "BRICK" then
				height = math.min(height, 220)
			end

			local width = rng:NextNumber(34, 68) * (0.7 + f * 0.6)
			local depth = width * rng:NextNumber(0.7, 1.3)

			buildTower(pos, width, depth, height, archetype, rng, folder, ("Tower%d_%d"):format(row, i))
		end
	end
end

--[[
	SUN AND SUN BEAMS.

	A bright disc high in the sky with god-rays raking down across the plaza.

	The beams are long translucent slabs angled from the sun's direction, all
	parallel - which is the point. Sunlight arrives in parallel rays; beams
	that fan out from a point read as a spotlight, not as the sun.
]]
local function buildSun(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "SunAndBeams"
	folder.Parent = parent

	--[[
		The sun disc lives in a PERSISTENT Model, and that is not optional.

		This place has StreamingEnabled, so parts far from the player are simply
		not replicated. At 2,100 studs out the sun sat well beyond the streaming
		radius: it existed on the server and was completely absent on every
		client. The beams still appeared, because they reach down into the plaza
		and so fall inside the radius - which made the bug easy to miss, since
		the god-rays looked fine while their source was invisible.

		ModelStreamingMode.Persistent exempts a model from streaming entirely.
		It is the right tool here precisely because this is two small parts that
		must ALWAYS be visible; it would be the wrong tool for the 20,000-part
		city, which is close enough to stream normally.
	]]
	local sunModel = Instance.new("Model")
	sunModel.Name = "SunModel"
	sunModel.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	sunModel.Parent = folder

	--[[
		SUN POSITION.

		The DIRECTION is deliberately unchanged - the beams below are built
		along this vector, and the raking low-angle look is what makes the city
		read as a city. Only the distance changed, from 900 to 2100, which
		lifts the disc from ~770 studs up to ~1630 without altering the beam
		angle at all.

		The extra +260 on Y raises it a little further still, so the disc sits
		well above even the 1,742-stud towers rather than appearing to hang
		between them.
	]]
	local sunDirection = Vector3.new(0.45, -0.72, 0.53).Unit
	local sunPosition = -sunDirection * 2100 + Vector3.new(0, 260, 0)

	local disc = PartUtils.CreatePart({
		name = "Sun",
		shape = Enum.PartType.Ball,
		-- Scaled up with the distance so its apparent size is unchanged.
		size = Vector3.new(330, 330, 330),
		position = sunPosition,
		material = Enum.Material.Neon,
		color = Color3.fromRGB(255, 248, 224),
		canCollide = false,
		castShadow = false,
		parent = sunModel,
	})

	-- Halo: a larger, fainter shell so the disc has a soft edge instead of
	-- ending abruptly.
	PartUtils.CreatePart({
		name = "SunHalo",
		shape = Enum.PartType.Ball,
		size = Vector3.new(660, 660, 660),
		position = sunPosition,
		material = Enum.Material.Neon,
		color = Color3.fromRGB(255, 236, 190),
		transparency = 0.82,
		canCollide = false,
		castShadow = false,
		parent = sunModel,
	})

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 244, 214)
	glow.Range = 60
	glow.Brightness = 3
	glow.Shadows = false
	glow.Parent = disc

	--[[
		GOD RAYS. Long thin slabs running along the sun direction, scattered
		across the plaza and city. Very transparent and additive-looking, so
		they read as light in dusty air rather than as solid geometry.
	]]
	local rng = Random.new(504911)
	for i = 1, 26 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(0, CITY_INNER * 1.5)
		-- Where the beam crosses ground level.
		local groundPoint = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		local beamLength = rng:NextNumber(700, 1100)
		-- Centre the slab along the ray so it spans from high in the sky down
		-- through the plaza.
		local centre = groundPoint - sunDirection * (beamLength * 0.42)

		PartUtils.CreatePart({
			name = ("SunBeam%d"):format(i),
			size = Vector3.new(rng:NextNumber(18, 46), rng:NextNumber(18, 46), beamLength),
			-- lookAt along the sun direction orientates the slab's long axis
			-- with the light.
			cframe = CFrame.lookAt(centre, centre + sunDirection),
			material = Enum.Material.Neon,
			color = Color3.fromRGB(255, 246, 214),
			transparency = rng:NextNumber(0.88, 0.95),
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
	end
end

--[[
	Enclosure. Same sealed-box approach the other maps use, but sized to hold
	the city and tall enough that the towers never poke through the ceiling.
]]
local function buildEnclosure(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "SkyEnclosure"
	folder.Parent = parent

	local SKY = Color3.fromRGB(150, 186, 224) -- daytime haze
	local SEGMENTS = 96 -- ~65 stud chord at this radius; fewer shows as seams
	local wallY = SKY_HEIGHT / 2 - 200

	for i = 1, SEGMENTS do
		local a1 = (i - 1) / SEGMENTS * math.pi * 2
		local a2 = i / SEGMENTS * math.pi * 2
		local v1 = Vector3.new(ENCLOSURE_RADIUS * math.sin(a1), 0, ENCLOSURE_RADIUS * math.cos(a1))
		local v2 = Vector3.new(ENCLOSURE_RADIUS * math.sin(a2), 0, ENCLOSURE_RADIUS * math.cos(a2))
		local mid = (v1 + v2) / 2
		local part = PartUtils.CreatePart({
			name = "SkyWall" .. i,
			-- 1.06 overlap so neighbouring panels can never open a seam.
			size = Vector3.new(4, SKY_HEIGHT, (v2 - v1).Magnitude * 1.06),
			material = Enum.Material.SmoothPlastic,
			color = SKY,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
		part.CFrame = CFrame.lookAt(mid + Vector3.new(0, wallY, 0), v2 + Vector3.new(0, wallY, 0))
			* CFrame.Angles(0, math.pi / 2, 0)
	end

	PartUtils.CreatePart({
		name = "SkyCeiling",
		size = Vector3.new(ENCLOSURE_RADIUS * 2 + 40, 8, ENCLOSURE_RADIUS * 2 + 40),
		position = Vector3.new(0, wallY + SKY_HEIGHT / 2 + 4, 0),
		material = Enum.Material.SmoothPlastic,
		color = SKY,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})
end

function FuturisticEnvironment.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "FuturisticEnvironment"
	folder.Parent = parent

	buildEnclosure(folder)
	buildCityGround(folder)
	buildCity(folder)
	buildSun(folder)

	return folder
end

return FuturisticEnvironment
