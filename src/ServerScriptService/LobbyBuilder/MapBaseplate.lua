--[[
	MapBaseplate.lua

	A wide, flat slab of ground sitting just under a map's walkable plate,
	so looking out over the edge shows solid terrain running away to the
	horizon instead of the plate ending in mid-air.

	WHY THIS EXISTS

	Every themed map already had a floor - SkyFloor, RockFloor, WaterFloor,
	DomeFloor - but all of them sit at Y = -202, which is 205 studs below
	the plate at Y = 3. At that distance, and through the map's own
	atmosphere, the floor is not readable as ground at all: the plate just
	stops, and beyond its rim there is pale empty space. The map reads as a
	disc floating in a void.

	This slab is deliberately placed only a few studs under the plate's own
	underside, so its surface is continuous with the plate to the eye. It
	does not replace those deep floors - they still close the map off from
	below - it fills the specific gap between the plate rim and the
	horizon.

	NOT APPLIED TO THE FUTURISTIC MAP. That map is the default lobby at the
	world origin and is intentionally presented as a platform in open sky;
	it also has no deep floor of its own. Only the four themed maps get a
	baseplate.

	PERFORMANCE: exactly one part per map. Anchored, non-collidable (the
	plate above already carries the player), and not a shadow caster - a
	single slab this large would otherwise throw a shadow across the whole
	map for no visual gain.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)

local MapBaseplate = {}

--[[
	Thickness of the slab. Deep enough that its own side face reads as a
	solid edge rather than a sheet of paper when seen from a low angle.
]]
local THICKNESS = 24

--[[
	How far the slab's TOP sits below the walkable plate's top surface.

	Tuned by eye across three passes: 8 sat almost flush with the plate and
	read as one continuous sheet with no rim at all; 50 gave a clear drop
	but started to read as a terrace the map was perched on. 29 is the
	midpoint and the settled value - enough of a step that the plate reads
	as raised ground, not so much that it looks like a mesa.

	Room to move either way if needed: the deep floors sit at Y = -202, so
	anything up to roughly 150 still clears them, but past about 80 the
	terrain starts reading as a distant valley floor rather than ground the
	map sits on.
]]
local DROP_BELOW_PLATE = 29

--[[
	Builds the baseplate for one map.

	`extent` is the half-width of the square slab. It should comfortably
	exceed the map's enclosure radius so the ground reaches past the
	boundary walls and there is never a visible outer edge from inside.

	`color`/`material` come from the caller so each map's ground matches
	its own theme rather than every map sharing one generic slab.
]]
function MapBaseplate.Build(parent: Instance, opts: {
	plateTopY: number,
	extent: number,
	color: Color3,
	material: Enum.Material,
})
	local topY = opts.plateTopY - DROP_BELOW_PLATE

	return PartUtils.CreatePart({
		name = "MapBaseplate",
		size = Vector3.new(opts.extent * 2, THICKNESS, opts.extent * 2),
		-- Positioned by its CENTRE, so half the thickness is subtracted to
		-- put the requested surface where the caller asked for it.
		position = Vector3.new(0, topY - THICKNESS / 2, 0),
		material = opts.material,
		color = opts.color,
		canCollide = false,
		castShadow = false,
		parent = parent,
	})
end

return MapBaseplate
