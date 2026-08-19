--[[
	MapConfig.lua

	Central source of truth for the lobby's overall shape and scale
	(Message 2 refinement: +50% footprint, square -> regular 30-gon
	boundary). Every other placement module (LobbyConfig's building/spawn
	positions, Decorations' tree/lamp rings, SeatingConfig's zones,
	LeaderboardConfig's arc) derives its numbers from here rather than
	hardcoding its own footprint assumptions, so the map's scale/shape can
	be changed from one place.

	Math: a regular 30-gon is fully described by its apothem (center to
	the middle of an edge - the "flat to flat" half-width) and its
	circumradius (center to a vertex - the "point to point" half-width).
	BOUNDARY_APOTHEM is the number that maps onto the old LOBBY_SIZE's
	"half" semantics (both describe the flat-to-flat extent), scaled by
	SCALE_FACTOR for the +50% footprint increase. CIRCUMRADIUS is derived
	from it via basic trigonometry - apothem = circumradius * cos(pi/n) -
	so the two can never drift out of mathematical agreement with each
	other.
]]

local MapConfig = {}

MapConfig.SIDES = 30

-- The old lobby was a 220x220 square (half = 110, both dimensions equal).
-- +50% in both length and width -> a 330x330 flat-to-flat footprint.
MapConfig.OLD_LOBBY_SIZE = 220
MapConfig.SCALE_FACTOR = 1.5
MapConfig.BOUNDARY_APOTHEM = (MapConfig.OLD_LOBBY_SIZE * MapConfig.SCALE_FACTOR) / 2 -- 165

-- circumradius = apothem / cos(pi / sides) - the exact relationship for a
-- regular polygon, computed rather than hand-picked so the boundary's
-- vertices and edges are always mathematically consistent with each other.
MapConfig.CIRCUMRADIUS = MapConfig.BOUNDARY_APOTHEM / math.cos(math.pi / MapConfig.SIDES)

-- Minimum clearance every object must keep from the boundary edge -
-- "no important building, seating area, street lamp, spawn point, or
-- decorative object should sit directly against the outer edge". Measured
-- against the apothem (the CLOSEST the boundary ever gets to the center,
-- since a polygon's edges are always closer than its vertices), so
-- anything placed within USABLE_RADIUS of the center is guaranteed clear
-- of the boundary from every angle, without needing a per-angle polygon
-- containment check.
MapConfig.BUFFER_ZONE = 15
MapConfig.USABLE_RADIUS = MapConfig.BOUNDARY_APOTHEM - MapConfig.BUFFER_ZONE

-- Stable attributes for the primary map components (design brief's own
-- suggested names).
MapConfig.GROUND_ATTRIBUTE = "LobbyGround"
MapConfig.BOUNDARY_ATTRIBUTE = "LobbyBoundary"
MapConfig.GROUND_DESIGN_ATTRIBUTE = "GroundDesign"
MapConfig.CENTER_ATTRIBUTE = "MapCenter"

--[[
	Returns the world position of polygon vertex `index` (0-based,
	0..SIDES-1) at the given `radius` (defaults to CIRCUMRADIUS for the
	actual boundary; callers building smaller concentric rings - ground
	design accents, perimeter fill lights, etc. - can pass a smaller
	radius and reuse the exact same angular spacing).

	The whole polygon is rotated by half a side-step (SIDES is even, so
	this centers flat EDGES on the four cardinal directions instead of
	vertices) - buildings sit on the -Z side and spawns on the +Z side of
	the existing layout, so a flat edge facing each of them (rather than a
	single point) reads as more deliberate/architectural.
]]
function MapConfig.GetVertex(index: number, radius: number?): Vector3
	local r = radius or MapConfig.CIRCUMRADIUS
	local angle = (2 * math.pi / MapConfig.SIDES) * index + (math.pi / MapConfig.SIDES)
	return Vector3.new(r * math.sin(angle), 0, r * math.cos(angle))
end

return MapConfig
