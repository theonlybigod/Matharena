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

LobbyTheme.THEMES = {
	Futuristic = FUTURISTIC,
	Lava = LAVA,
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
