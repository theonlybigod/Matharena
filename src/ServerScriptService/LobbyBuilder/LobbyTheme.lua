--[[
	LobbyTheme.lua

	Named visual-theme presets for the lobby's procedural construction
	code (Floor/Buildings/BuildingInteriors/BuildingSigns/Decorations/
	Trees/StreetLamps/Seating/SpawnsAndPortal/LeaderboardBoards/Sign).

	This module owns ONLY colors/materials - never positions, sizes, or
	counts. Every construction module's actual GEOMETRY (building
	footprints, tree/lamp ring placement, the leaderboard arc, spawn
	positions, the 30-gon boundary shape) stays driven entirely by
	MapConfig/LobbyConfig/TreeConfig/StreetLampConfig/SeatingConfig exactly
	as before, completely unchanged and shared by every map - a new theme
	is a genuinely different look for the exact same layout, not a
	different map shape.

	"Futuristic" reproduces every color/material the lobby already used
	before multi-theme support existed (LobbyConfig.NEON_COLOR,
	LightingConfig's blue accent palette, etc.) byte-for-byte, so building
	the existing map with this theme is visually IDENTICAL to before this
	module existed - the default/current map is never altered by adding
	this system.

	"Lava" is a genuinely different material/color treatment (dark
	basalt/rock instead of smooth metal, glowing CrackedLava instead of
	Neon accents, charred trunks instead of wood, warm orange/red glow
	instead of cool blue) - not the same geometry simply recolored, per
	real Roblox materials (Basalt, Rock, CrackedLava, Ground) rather than
	hand-approximated colors on the same Metal/Neon/Glass materials the
	futuristic theme uses.

	Adding a further theme later means adding one more entry to THEMES
	below - no construction module needs to change.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)

local LobbyTheme = {}

export type Theme = {
	id: string,

	-- Ground / boundary / ground-design (Floor.lua)
	floorMaterial: Enum.Material,
	floorColor: Color3,
	curbMaterial: Enum.Material,
	curbColor: Color3,
	curbTrimMaterial: Enum.Material,
	curbTrimColor: Color3,
	groundDesignCenterColor: Color3,
	groundDesignMidColor: Color3,
	groundDesignSpokeColor: Color3,

	-- Buildings exterior/interior (Buildings.lua, BuildingInteriors.lua)
	buildingWallMaterial: Enum.Material,
	buildingExteriorWallColor: Color3,
	buildingInteriorWallColor: Color3,
	buildingInteriorFloorColor: Color3,
	buildingCeilingColor: Color3,
	buildingRoofCapColor: Color3,
	buildingAccentMaterial: Enum.Material,
	buildingAccentColor: Color3,
	buildingGlassMaterial: Enum.Material,
	buildingGlassColor: Color3,
	buildingGlassTransparency: number,
	buildingHeaderColor: Color3,
	buildingCanopyColor: Color3,
	buildingFurnitureMaterial: Enum.Material,
	buildingFurnitureColor: Color3,

	-- Building overhead signs (BuildingSigns.lua)
	buildingSignAccentColor: Color3,

	-- Trees (Trees.lua)
	treeTrunkMaterial: Enum.Material,
	treeTrunkColor: Color3, -- base color; a small deterministic per-tree shift is still applied on top
	treeFoliageMaterial: Enum.Material,
	treeFoliageColor: Color3, -- base color; a small deterministic per-tree shift is still applied on top

	-- Street lamps (StreetLamps.lua / StreetLampConfig.lua)
	lampMetalMaterial: Enum.Material,
	lampMetalColor: Color3,
	lampAccentColor: Color3,
	lampGlowColor: Color3,

	-- Seating (Seating.lua / SeatingConfig.lua)
	seatMaterial: Enum.Material,
	seatColor: Color3,
	seatAccentColor: Color3,
	seatFrameMaterial: Enum.Material,
	seatFrameColor: Color3,

	-- Spawns + queue portal (SpawnsAndPortal.lua)
	spawnPadMaterial: Enum.Material,
	spawnPadColor: Color3,
	portalAccentColor: Color3,

	-- Leaderboard board structure only - NOT each category's own accent
	-- color, which stays consistent branding across every map/theme
	-- (LeaderboardBoards.lua reads this for the plinth/support posts only).
	leaderboardStructureMaterial: Enum.Material,
	leaderboardStructureColor: Color3,

	-- Decorative ground clusters (Decorations.lua's flower beds) + the
	-- perimeter fill-light color.
	groundClusterColors: { Color3 },
	perimeterFillLightColor: Color3,

	-- The floating landmark sign's glow only (Sign.lua) - text/position/
	-- size are unaffected by theme.
	signGlowColor: Color3,

	-- Optional themed "backing panel" behind the floating landmark sign's
	-- text (Sign.lua) - a large, soft-edged translucent sheet reading as
	-- "a panel of water" or "a block of ice" the MATHARENA title floats in
	-- front of. nil (the default, Futuristic/Lava/Space) means no panel at
	-- all - preserves the existing borderless-glowing-text look exactly as
	-- it already was before this field existed for every theme that
	-- doesn't set it.
	signBackingColor: Color3?,
	signBackingTransparency: number?,
}

local FUTURISTIC: Theme = {
	id = "Futuristic",

	floorMaterial = Enum.Material.Concrete,
	floorColor = Color3.fromRGB(180, 180, 185),
	curbMaterial = Enum.Material.Metal,
	curbColor = Color3.fromRGB(48, 51, 60),
	curbTrimMaterial = Enum.Material.Neon,
	curbTrimColor = LightingConfig.GROUND_PATH,
	groundDesignCenterColor = LightingConfig.CENTRAL_FEATURE,
	groundDesignMidColor = LightingConfig.DECORATIVE,
	groundDesignSpokeColor = LightingConfig.DECORATIVE,

	buildingWallMaterial = Enum.Material.Metal,
	buildingExteriorWallColor = Color3.fromRGB(52, 56, 66),
	buildingInteriorWallColor = Color3.fromRGB(40, 43, 50),
	buildingInteriorFloorColor = Color3.fromRGB(30, 32, 38),
	buildingCeilingColor = Color3.fromRGB(50, 53, 60),
	buildingRoofCapColor = Color3.fromRGB(45, 48, 56),
	buildingAccentMaterial = Enum.Material.Neon,
	buildingAccentColor = LightingConfig.BUILDING_TRIM,
	buildingGlassMaterial = Enum.Material.Glass,
	buildingGlassColor = Color3.fromRGB(120, 200, 255),
	buildingGlassTransparency = 0.45,
	buildingHeaderColor = Color3.fromRGB(60, 65, 75),
	buildingCanopyColor = Color3.fromRGB(60, 65, 75),
	buildingFurnitureMaterial = Enum.Material.Metal,
	buildingFurnitureColor = Color3.fromRGB(45, 48, 56),

	buildingSignAccentColor = LightingConfig.BUILDING_TRIM,

	treeTrunkMaterial = Enum.Material.Wood,
	treeTrunkColor = Color3.fromRGB(90, 60, 40),
	treeFoliageMaterial = Enum.Material.Grass,
	treeFoliageColor = Color3.fromRGB(45, 118, 60),

	lampMetalMaterial = Enum.Material.Metal,
	lampMetalColor = Color3.fromRGB(55, 58, 66),
	lampAccentColor = LightingConfig.STREET_LAMP_ACCENT,
	lampGlowColor = LightingConfig.STREET_LAMP_GLOW,

	seatMaterial = Enum.Material.SmoothPlastic,
	seatColor = Color3.fromRGB(235, 235, 240),
	seatAccentColor = LightingConfig.DECORATIVE,
	seatFrameMaterial = Enum.Material.Metal,
	seatFrameColor = Color3.fromRGB(60, 63, 70),

	spawnPadMaterial = Enum.Material.Concrete,
	spawnPadColor = Color3.fromRGB(180, 180, 185),
	portalAccentColor = LightingConfig.CENTRAL_FEATURE,

	leaderboardStructureMaterial = Enum.Material.Metal,
	leaderboardStructureColor = Color3.fromRGB(45, 48, 56),

	groundClusterColors = {
		Color3.fromRGB(230, 60, 90),
		Color3.fromRGB(250, 200, 40),
		Color3.fromRGB(140, 90, 230),
	},
	perimeterFillLightColor = LightingConfig.OUTDOOR_AMBIENT_COLOR,

	signGlowColor = LightingConfig.CENTRAL_FEATURE,
}

-- Hot, dry, volcanic: dark basalt/charcoal rock instead of smooth painted
-- metal, real glowing CrackedLava instead of Neon standing in for a glow,
-- charred/ashen trunks instead of wood, molten-orange foliage instead of
-- grass-green. Every structural material below is a genuine Roblox rock/
-- lava material (Basalt, Rock, Ground, CrackedLava) rather than a Metal/
-- Neon/Glass part merely recolored, so the volcanic look reads as an
-- actual different material world, not a color swap of the futuristic one.
local LAVA: Theme = {
	id = "Lava",

	-- Basalt (not Ground) for the floor: Roblox's "Ground" material carries
	-- a strong baked-in light-grey/sandy texture that mutes a dark Color
	-- tint into a washed-out grey (verified directly in Studio - the same
	-- dark-brown Color renders as flat grey on Ground but as a genuinely
	-- dark charcoal-brown on Basalt, matching the buildings). Basalt is
	-- also literally volcanic rock, so it's a better thematic fit anyway.
	floorMaterial = Enum.Material.Basalt,
	floorColor = Color3.fromRGB(64, 46, 36), -- dry, cracked dark-brown earth
	curbMaterial = Enum.Material.Basalt,
	curbColor = Color3.fromRGB(36, 28, 26),
	curbTrimMaterial = Enum.Material.CrackedLava,
	curbTrimColor = Color3.fromRGB(255, 110, 30),
	groundDesignCenterColor = Color3.fromRGB(255, 130, 30),
	groundDesignMidColor = Color3.fromRGB(230, 90, 25),
	groundDesignSpokeColor = Color3.fromRGB(230, 90, 25),

	buildingWallMaterial = Enum.Material.Basalt,
	buildingExteriorWallColor = Color3.fromRGB(44, 36, 33),
	buildingInteriorWallColor = Color3.fromRGB(32, 26, 24),
	buildingInteriorFloorColor = Color3.fromRGB(26, 21, 19),
	buildingCeilingColor = Color3.fromRGB(38, 31, 28),
	buildingRoofCapColor = Color3.fromRGB(34, 27, 25),
	buildingAccentMaterial = Enum.Material.CrackedLava,
	buildingAccentColor = Color3.fromRGB(255, 100, 25),
	-- "Windows" become glowing lava vents rather than glass panes -
	-- CrackedLava is a real emissive-reading material in Roblox, so this
	-- is a genuine material swap, not a tinted pane of Glass.
	buildingGlassMaterial = Enum.Material.CrackedLava,
	buildingGlassColor = Color3.fromRGB(255, 120, 30),
	buildingGlassTransparency = 0,
	buildingHeaderColor = Color3.fromRGB(50, 40, 37),
	buildingCanopyColor = Color3.fromRGB(50, 40, 37),
	buildingFurnitureMaterial = Enum.Material.Rock,
	buildingFurnitureColor = Color3.fromRGB(40, 33, 30),

	buildingSignAccentColor = Color3.fromRGB(255, 100, 25),

	treeTrunkMaterial = Enum.Material.Basalt,
	treeTrunkColor = Color3.fromRGB(30, 24, 22), -- charred/ashen, near-black
	treeFoliageMaterial = Enum.Material.CrackedLava,
	treeFoliageColor = Color3.fromRGB(255, 90, 20), -- molten glowing "canopy"

	lampMetalMaterial = Enum.Material.Basalt,
	lampMetalColor = Color3.fromRGB(40, 33, 30),
	lampAccentColor = Color3.fromRGB(255, 110, 30),
	lampGlowColor = Color3.fromRGB(255, 100, 25), -- a genuine warm brazier-flame glow, not a cool LED white

	seatMaterial = Enum.Material.Rock,
	seatColor = Color3.fromRGB(48, 40, 36),
	seatAccentColor = Color3.fromRGB(255, 100, 25),
	seatFrameMaterial = Enum.Material.Basalt,
	seatFrameColor = Color3.fromRGB(38, 31, 28),

	spawnPadMaterial = Enum.Material.Basalt,
	spawnPadColor = Color3.fromRGB(64, 46, 36),
	portalAccentColor = Color3.fromRGB(255, 110, 30),

	leaderboardStructureMaterial = Enum.Material.Basalt,
	leaderboardStructureColor = Color3.fromRGB(40, 33, 30),

	-- "Ember clusters" instead of flower beds - same construction code
	-- (createFlowerBed), a warm ember-toned palette instead of bright
	-- florals, fitting the volcanic setting.
	groundClusterColors = {
		Color3.fromRGB(255, 80, 20),
		Color3.fromRGB(255, 160, 30),
		Color3.fromRGB(200, 50, 20),
	},
	perimeterFillLightColor = Color3.fromRGB(200, 110, 70),

	signGlowColor = Color3.fromRGB(255, 100, 25),
}

-- Deep-space station: dark metal hull plating instead of smooth painted
-- concrete/basalt, electric cyan + violet Neon accents instead of a single
-- blue family, tinted viewport Glass (reading as "looking out into the
-- void") instead of clear/lava-vent glass, and Neon-lit
-- crystal/energy-formation "foliage" instead of grass or molten rock -
-- every structural material below is a genuine different material
-- combination (Metal/DiamondPlate/Neon/Glass) from BOTH other themes, not
-- a recolor of either. Trees keep their exact existing angular silhouettes
-- (Spire/CanopyBurst/TwinBough/CrystalCluster - see Trees.lua) but read as
-- glowing crystalline energy spires here, the same "material swap, not a
-- new shape" technique the Lava theme already established for its molten
-- canopies. The map's own surrounding deep-space backdrop (starfield dome,
-- distant planets, floating asteroids) is NOT part of this theme table -
-- it's built by SpaceEnvironment.lua, called directly by LobbyBuilder for
-- the Space map only, since it's genuinely new geometry (not a color/
-- material swap of something every map already builds).
local SPACE: Theme = {
	id = "Space",

	floorMaterial = Enum.Material.Metal,
	floorColor = Color3.fromRGB(20, 22, 30), -- dark station deck plating
	curbMaterial = Enum.Material.Metal,
	curbColor = Color3.fromRGB(14, 15, 21),
	curbTrimMaterial = Enum.Material.Neon,
	curbTrimColor = Color3.fromRGB(80, 220, 255), -- electric cyan
	groundDesignCenterColor = Color3.fromRGB(190, 110, 255), -- violet focal accent
	groundDesignMidColor = Color3.fromRGB(80, 220, 255),
	groundDesignSpokeColor = Color3.fromRGB(80, 220, 255),

	buildingWallMaterial = Enum.Material.Metal,
	buildingExteriorWallColor = Color3.fromRGB(32, 35, 46), -- dark hull plating
	buildingInteriorWallColor = Color3.fromRGB(24, 26, 34),
	buildingInteriorFloorColor = Color3.fromRGB(18, 19, 25),
	buildingCeilingColor = Color3.fromRGB(30, 32, 42),
	buildingRoofCapColor = Color3.fromRGB(26, 28, 37),
	buildingAccentMaterial = Enum.Material.Neon,
	buildingAccentColor = Color3.fromRGB(80, 220, 255),
	-- Windows become dark observation viewports looking out into the void -
	-- a genuinely different tint/transparency treatment from the
	-- futuristic theme's bright sky-blue glass, not the same pane recolored.
	buildingGlassMaterial = Enum.Material.Glass,
	buildingGlassColor = Color3.fromRGB(30, 45, 80),
	buildingGlassTransparency = 0.2,
	buildingHeaderColor = Color3.fromRGB(28, 30, 39),
	buildingCanopyColor = Color3.fromRGB(28, 30, 39),
	buildingFurnitureMaterial = Enum.Material.Metal,
	buildingFurnitureColor = Color3.fromRGB(36, 39, 50),

	buildingSignAccentColor = Color3.fromRGB(190, 110, 255),

	-- Trees: same angular silhouettes, reinterpreted as glowing crystalline
	-- energy spires - a dark metal "mast" instead of a wood trunk, Neon
	-- "canopy" instead of grass/lava foliage.
	treeTrunkMaterial = Enum.Material.Metal,
	treeTrunkColor = Color3.fromRGB(40, 42, 52),
	treeFoliageMaterial = Enum.Material.Neon,
	treeFoliageColor = Color3.fromRGB(120, 90, 255), -- violet-blue energy glow

	lampMetalMaterial = Enum.Material.Metal,
	lampMetalColor = Color3.fromRGB(30, 32, 42),
	lampAccentColor = Color3.fromRGB(80, 220, 255),
	lampGlowColor = Color3.fromRGB(190, 220, 255), -- cool starlight-white glow

	seatMaterial = Enum.Material.Metal,
	seatColor = Color3.fromRGB(34, 37, 48),
	seatAccentColor = Color3.fromRGB(80, 220, 255),
	seatFrameMaterial = Enum.Material.Metal,
	seatFrameColor = Color3.fromRGB(24, 26, 34),

	spawnPadMaterial = Enum.Material.Metal,
	spawnPadColor = Color3.fromRGB(22, 24, 32),
	portalAccentColor = Color3.fromRGB(190, 110, 255),

	leaderboardStructureMaterial = Enum.Material.Metal,
	leaderboardStructureColor = Color3.fromRGB(28, 30, 39),

	-- "Energy/crystal clusters" instead of flower beds - same construction
	-- code (createFlowerBed), a cyan/violet/starlight palette instead of
	-- bright florals or warm embers, fitting the space-station setting.
	groundClusterColors = {
		Color3.fromRGB(80, 220, 255),
		Color3.fromRGB(170, 90, 255),
		Color3.fromRGB(230, 235, 255),
	},
	perimeterFillLightColor = Color3.fromRGB(120, 150, 255),

	signGlowColor = Color3.fromRGB(190, 110, 255),
}

-- Underwater world: rock/coral instead of smooth metal or basalt,
-- vivid bioluminescent coral-pink/teal Neon accents instead of a single
-- blue family, tinted aqua "porthole" glass instead of clear/lava-vent/
-- viewport glass, and glowing coral/anemone "foliage" instead of grass,
-- lava-canopy, or crystal energy. Every structural material below is a
-- genuine different material combination (Slate/Rock/Wood/Neon/Glass)
-- from every other theme, not a recolor of any of them. Trees keep their
-- exact existing angular silhouettes (Spire/CanopyBurst/TwinBough/
-- CrystalCluster - see Trees.lua) but read as coral formations/anemone
-- clusters/kelp fronds here, the same "material swap, not a new shape"
-- technique the Lava and Space themes already established. The map's own
-- surrounding underwater backdrop (enclosing water-volume walls, bubble
-- streams, coral reef clusters, drifting fish) is NOT part of this theme
-- table - it's built by UnderTheSeaEnvironment.lua, called directly by
-- LobbyBuilder for the Under the Sea map only, mirroring exactly how
-- SpaceEnvironment.lua is wired in for the Space map (see that module's
-- doc comment for why this kind of backdrop can't be a shared
-- Lighting.Sky change).
local UNDER_THE_SEA: Theme = {
	id = "UnderTheSea",

	floorMaterial = Enum.Material.Sand,
	floorColor = Color3.fromRGB(168, 150, 108), -- sandy seabed, muted by deep water
	curbMaterial = Enum.Material.Slate,
	curbColor = Color3.fromRGB(22, 40, 50),
	curbTrimMaterial = Enum.Material.Neon,
	curbTrimColor = Color3.fromRGB(80, 230, 210), -- bioluminescent teal
	groundDesignCenterColor = Color3.fromRGB(255, 130, 140), -- coral-pink focal accent
	groundDesignMidColor = Color3.fromRGB(80, 230, 210),
	groundDesignSpokeColor = Color3.fromRGB(80, 230, 210),

	buildingWallMaterial = Enum.Material.Slate,
	buildingExteriorWallColor = Color3.fromRGB(70, 90, 100), -- weathered shell/coral-rock
	buildingInteriorWallColor = Color3.fromRGB(48, 64, 72),
	buildingInteriorFloorColor = Color3.fromRGB(38, 52, 58),
	buildingCeilingColor = Color3.fromRGB(55, 72, 80),
	buildingRoofCapColor = Color3.fromRGB(50, 66, 74),
	buildingAccentMaterial = Enum.Material.Neon,
	buildingAccentColor = Color3.fromRGB(80, 230, 210),
	-- Windows become aqua-tinted "portholes" looking out into the water -
	-- a genuinely different tint/transparency treatment from every other
	-- theme's glass, not the same pane recolored.
	buildingGlassMaterial = Enum.Material.Glass,
	buildingGlassColor = Color3.fromRGB(100, 200, 210),
	buildingGlassTransparency = 0.35,
	buildingHeaderColor = Color3.fromRGB(46, 62, 70),
	buildingCanopyColor = Color3.fromRGB(46, 62, 70),
	-- Weathered driftwood furniture, not metal/rock - a genuine material
	-- difference from every other theme's interior fixtures.
	buildingFurnitureMaterial = Enum.Material.Wood,
	buildingFurnitureColor = Color3.fromRGB(72, 60, 52),

	buildingSignAccentColor = Color3.fromRGB(80, 230, 210),

	-- Trees: same angular silhouettes, reinterpreted as coral formations/
	-- anemone clusters/kelp fronds - a rock "base" instead of a wood trunk,
	-- Neon coral-pink "canopy" instead of grass/lava/crystal foliage.
	treeTrunkMaterial = Enum.Material.Rock,
	treeTrunkColor = Color3.fromRGB(110, 85, 90),
	treeFoliageMaterial = Enum.Material.Neon,
	treeFoliageColor = Color3.fromRGB(255, 120, 130), -- vivid bioluminescent coral-pink

	lampMetalMaterial = Enum.Material.Slate,
	lampMetalColor = Color3.fromRGB(38, 55, 64),
	lampAccentColor = Color3.fromRGB(80, 230, 210),
	lampGlowColor = Color3.fromRGB(150, 220, 255), -- soft bioluminescent blue-white

	seatMaterial = Enum.Material.Rock,
	seatColor = Color3.fromRGB(80, 62, 70),
	seatAccentColor = Color3.fromRGB(80, 230, 210),
	seatFrameMaterial = Enum.Material.Slate,
	seatFrameColor = Color3.fromRGB(34, 50, 58),

	spawnPadMaterial = Enum.Material.Slate,
	spawnPadColor = Color3.fromRGB(40, 60, 70),
	portalAccentColor = Color3.fromRGB(90, 240, 220),

	leaderboardStructureMaterial = Enum.Material.Slate,
	leaderboardStructureColor = Color3.fromRGB(38, 55, 64),

	-- "Coral/anemone clusters" instead of flower beds - same construction
	-- code (createFlowerBed), a coral-reef palette instead of bright
	-- florals, embers, or crystal shards.
	groundClusterColors = {
		Color3.fromRGB(255, 130, 150),
		Color3.fromRGB(255, 200, 90),
		Color3.fromRGB(120, 230, 255),
	},
	perimeterFillLightColor = Color3.fromRGB(100, 190, 230),

	signGlowColor = Color3.fromRGB(90, 220, 230),
	-- "A large panel of water" behind the MATHARENA title - a soft, deep
	-- teal translucent sheet (see Sign.lua's createBillboard).
	signBackingColor = Color3.fromRGB(20, 90, 110),
	signBackingTransparency = 0.35,
}

-- Frozen world: packed ice/glacier instead of smooth metal, basalt, rock,
-- or hull-plating, pale icy-cyan Neon accents instead of any other
-- theme's accent family, frosted ice "windows" instead of glass/lava-
-- vent/viewport panes, and glowing frost-blue "foliage" instead of
-- grass, lava-canopy, crystal energy, or coral. Every structural material
-- below is a genuine different material combination (Ice/Glacier/Metal/
-- Neon) from every other theme, not a recolor of any of them. Trees keep
-- their exact existing angular silhouettes but read as frozen ice-
-- crystal formations here. Lamps deliberately keep a WARM glow
-- (lampGlowColor) rather than an icy one - a cozy lantern glow against
-- the cold surroundings reads as more intentional than everything being
-- uniformly cold. The map's own surrounding frozen backdrop (enclosing
-- whiteout-sky walls, falling snow, distant frozen peaks, icicle
-- clusters, aurora streaks) is NOT part of this theme table - it's built
-- by IceAgeEnvironment.lua, called directly by LobbyBuilder for the Ice
-- Age map only, mirroring exactly how SpaceEnvironment.lua is wired in
-- for the Space map.
local ICE_AGE: Theme = {
	id = "IceAge",

	floorMaterial = Enum.Material.Glacier,
	floorColor = Color3.fromRGB(205, 222, 235), -- packed snow/ice sheet
	curbMaterial = Enum.Material.Ice,
	curbColor = Color3.fromRGB(180, 208, 225),
	curbTrimMaterial = Enum.Material.Neon,
	curbTrimColor = Color3.fromRGB(160, 225, 255),
	groundDesignCenterColor = Color3.fromRGB(190, 205, 255), -- pale aurora-violet focal accent
	groundDesignMidColor = Color3.fromRGB(160, 225, 255),
	groundDesignSpokeColor = Color3.fromRGB(160, 225, 255),

	--[[
		ICE, NOT SNOW.

		The building surfaces were Glacier in near-white packed-snow tones
		(225,235,242 walls, 210-215 roof/ceiling), which read as igloos - snow
		piled up rather than ice. Everything below is retuned toward glacial
		ice: the Ice material instead of Glacier for the walls, and colours
		pulled well down in brightness and hard toward cyan-blue.

		The brightness drop matters as much as the hue. Near-white surfaces read
		as snow whatever their material, because snow is what white-and-matte
		looks like; ice reads as ice because it is DARKER and more saturated
		than the snow lying on it, with the light coming through rather than
		off it.

		Glacier is kept for the floor - underfoot is genuinely a packed sheet
		with snow over it, and a fully transparent-looking floor would read as
		standing on nothing.
	]]
	buildingWallMaterial = Enum.Material.Ice,
	buildingExteriorWallColor = Color3.fromRGB(150, 198, 224), -- glacial ice, not packed snow
	buildingInteriorWallColor = Color3.fromRGB(132, 178, 205),
	buildingInteriorFloorColor = Color3.fromRGB(146, 186, 208),
	buildingCeilingColor = Color3.fromRGB(138, 186, 214),
	buildingRoofCapColor = Color3.fromRGB(126, 176, 208),
	buildingAccentMaterial = Enum.Material.Neon,
	buildingAccentColor = Color3.fromRGB(140, 210, 255),
	-- Frosted ice panes instead of glass - a genuine different material
	-- (Ice, not Glass) from every other theme's windows.
	-- Deeper, more saturated ice for the panes now that the walls themselves
	-- are ice - at the old near-white the windows were lighter than the wall
	-- around them, which is backwards for a translucent pane.
	buildingGlassMaterial = Enum.Material.Ice,
	buildingGlassColor = Color3.fromRGB(168, 216, 240),
	buildingGlassTransparency = 0.35,
	buildingHeaderColor = Color3.fromRGB(120, 168, 200),
	buildingCanopyColor = Color3.fromRGB(120, 168, 200),
	-- Frost-covered metal fixtures - a genuine material difference from
	-- every other theme's interior furniture.
	buildingFurnitureMaterial = Enum.Material.Metal,
	buildingFurnitureColor = Color3.fromRGB(150, 165, 178),

	buildingSignAccentColor = Color3.fromRGB(140, 210, 255),

	-- Trees: same angular silhouettes, reinterpreted as glowing frozen
	-- ice-crystal formations - a frost-pale "trunk" instead of wood/metal/
	-- rock, glowing icy-cyan Neon "canopy" instead of every other theme's
	-- foliage material.
	treeTrunkMaterial = Enum.Material.Wood,
	treeTrunkColor = Color3.fromRGB(95, 105, 115), -- bare frost-greyed bark
	treeFoliageMaterial = Enum.Material.Neon,
	treeFoliageColor = Color3.fromRGB(170, 220, 255), -- glowing frost-blue ice crystal

	lampMetalMaterial = Enum.Material.Metal,
	lampMetalColor = Color3.fromRGB(75, 85, 98),
	lampAccentColor = Color3.fromRGB(150, 215, 255),
	-- Deliberately warm (not icy) - a cozy lantern-flame glow contrasting
	-- against the cold surroundings, see the theme's own doc comment above.
	lampGlowColor = Color3.fromRGB(255, 200, 140),

	seatMaterial = Enum.Material.Ice,
	seatColor = Color3.fromRGB(210, 226, 238),
	seatAccentColor = Color3.fromRGB(150, 215, 255),
	seatFrameMaterial = Enum.Material.Metal,
	seatFrameColor = Color3.fromRGB(80, 90, 102),

	spawnPadMaterial = Enum.Material.Glacier,
	spawnPadColor = Color3.fromRGB(210, 224, 236),
	portalAccentColor = Color3.fromRGB(170, 205, 255),

	leaderboardStructureMaterial = Enum.Material.Ice,
	leaderboardStructureColor = Color3.fromRGB(195, 215, 230),

	-- "Ice crystal clusters" instead of flower beds - same construction
	-- code (createFlowerBed), a pale icy-blue/white palette instead of
	-- bright florals, embers, or coral tones.
	groundClusterColors = {
		Color3.fromRGB(170, 220, 255),
		Color3.fromRGB(220, 240, 255),
		Color3.fromRGB(140, 180, 255),
	},
	perimeterFillLightColor = Color3.fromRGB(170, 200, 230),

	signGlowColor = Color3.fromRGB(150, 210, 255),
	-- "A block of ice" behind the MATHARENA title - a pale, frosted
	-- translucent sheet (see Sign.lua's createBillboard).
	signBackingColor = Color3.fromRGB(190, 220, 240),
	signBackingTransparency = 0.4,
}

LobbyTheme.THEMES = {
	Futuristic = FUTURISTIC,
	Lava = LAVA,
	Space = SPACE,
	UnderTheSea = UNDER_THE_SEA,
	IceAge = ICE_AGE,
}

LobbyTheme.DEFAULT_THEME_ID = "Futuristic"

--[[
	Returns the Theme table for `themeId`, falling back to the Futuristic
	default for a nil/unknown id (same defensive fallback convention every
	other *.GetX-by-id function in this project already uses).
]]
function LobbyTheme.Get(themeId: string?): Theme
	if themeId and LobbyTheme.THEMES[themeId] then
		return LobbyTheme.THEMES[themeId]
	end
	return LobbyTheme.THEMES[LobbyTheme.DEFAULT_THEME_ID]
end

return LobbyTheme
