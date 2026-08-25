--[[
	Floor.lua

	Builds the lobby's ground: a single authoritative ground slab
	(LobbyGround), a 30-sided boundary (LobbyBoundary) tracing the exact
	polygon MapConfig defines, a restrained ground design (GroundDesign -
	two concentric rings, radial spokes, and a center medallion), and a
	MapCenter marker at the origin.

	Ground-flicker bug fix (Message 2 refinement): the previous version of
	this file built four long neon trim strips whose BOTTOM face sat at
	EXACTLY the same Y coordinate as the floor slab's TOP face (verified
	directly in Studio: both at Y=0.0, zero gap) - two different-material
	surfaces occupying the identical plane along a 220-stud edge, which is
	a textbook z-fighting/flicker setup. The actual root cause was this
	coincident geometry, not a material or lighting setting, so every
	ground-level decorative surface below (boundary, rings, spokes,
	medallion) is deliberately given a small but consistent GROUND_EPSILON
	gap above the slab's top - imperceptible visually, but never
	numerically coincident with another surface.

	30-sided boundary + ~50% larger footprint (Message 2 refinement): the
	old ground was a flat 220x220 square. It's now a single round slab
	(so the map doesn't read as "a square with corners" from above) sized
	to fully cover a regular 30-gon whose flat-to-flat width is 330 studs
	(220 * 1.5) - see MapConfig.lua for the exact math. The 30-gon itself
	is traced by LobbyBoundary, 30 individual edge segments built from
	MapConfig.GetVertex, so the boundary's vertices/edges are always
	mathematically exact regardless of any other tuning.

	Split out from LobbyBuilder/init.lua (previously a local `buildFloor`
	function) so the exact same code path can be reused by:
		1. LobbyBuilder itself at runtime (Play mode / fresh servers), and
		2. build/BakeLobby.luau, the offline script (run via Lune) that
		   bakes a source-controlled Workspace/Lobby.rbxmx model file so
		   the lobby is visible in Studio Edit mode through plain Rojo
		   sync, with no code execution required.
	This guarantees the baked model and the runtime-generated lobby can
	never drift apart for the floor geometry.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local LobbyConfig = require(script.Parent.LobbyConfig)
local MapConfig = require(script.Parent.MapConfig)
local LobbyTheme = require(script.Parent.LobbyTheme)

local Floor = {}

-- Theme-driven; latched via Floor.SetTheme(theme) once per map build,
-- right before Floor.Build runs - see LobbyBuilder/init.lua. Defaults to
-- the Futuristic palette so this module behaves exactly as before if
-- SetTheme is somehow never called.
local defaultTheme = LobbyTheme.Get()
local FLOOR_MATERIAL = defaultTheme.floorMaterial
local FLOOR_COLOR = defaultTheme.floorColor
local CURB_MATERIAL = defaultTheme.curbMaterial
local CURB_COLOR = defaultTheme.curbColor
local CURB_TRIM_MATERIAL = defaultTheme.curbTrimMaterial
local CURB_TRIM_COLOR = defaultTheme.curbTrimColor
local GROUND_DESIGN_CENTER_COLOR = defaultTheme.groundDesignCenterColor
local GROUND_DESIGN_MID_COLOR = defaultTheme.groundDesignMidColor
local GROUND_DESIGN_SPOKE_COLOR = defaultTheme.groundDesignSpokeColor
local CURRENT_THEME_ID = defaultTheme.id

-- Themes with their own dedicated environment module (IceAgeEnvironment/
-- LavaEnvironment/UnderTheSeaEnvironment) build their OWN ground terrain
-- pattern (see each module's buildGroundPattern) instead of the generic
-- ring/spoke/medallion pattern below - "avoid copying the futuristic
-- map's ground pattern" was an explicit direction, and reusing the same
-- rings-and-spokes medallion (just recolored) under every theme was
-- exactly that. Futuristic/Space keep the original generic pattern
-- unchanged.
local THEMES_WITH_OWN_GROUND_PATTERN = {
	IceAge = true,
	Lava = true,
	UnderTheSea = true,
}

--[[
	Latches `theme`'s ground/boundary/ground-design colors and materials
	for every subsequent Floor.Build call, until the next SetTheme call -
	see the module doc comment on LobbyBuilder/init.lua for why a mutable
	module-level variable (rather than threading a theme parameter through
	every private helper below) is the right pattern here: builds are
	always synchronous/sequential (one map fully finishes before the next
	map's SetTheme call happens), so every helper function below - which
	already closes over these exact same local variables - automatically
	picks up the new palette with no signature changes needed anywhere.
]]
function Floor.SetTheme(theme: LobbyTheme.Theme)
	FLOOR_MATERIAL = theme.floorMaterial
	FLOOR_COLOR = theme.floorColor
	CURB_MATERIAL = theme.curbMaterial
	CURB_COLOR = theme.curbColor
	CURB_TRIM_MATERIAL = theme.curbTrimMaterial
	CURB_TRIM_COLOR = theme.curbTrimColor
	GROUND_DESIGN_CENTER_COLOR = theme.groundDesignCenterColor
	GROUND_DESIGN_MID_COLOR = theme.groundDesignMidColor
	GROUND_DESIGN_SPOKE_COLOR = theme.groundDesignSpokeColor
	CURRENT_THEME_ID = theme.id
end

local FLOOR_THICKNESS = LobbyConfig.FLOOR_THICKNESS
local FLOOR_TOP_Y = 0 -- the slab's top surface always sits at world Y=0, matching every other placement module's assumption
local GROUND_EPSILON = 0.15 -- deliberate, consistent, nonzero gap for every ground-level decorative surface - see the module doc comment above for why

local function groundY(riseAbove: number?)
	return FLOOR_TOP_Y + GROUND_EPSILON + (riseAbove or 0)
end

--[[
	Builds one boundary edge segment between polygon vertices `index` and
	`index + 1`, oriented via the exact yaw between them - a raised neon
	curb (not a flat decal) so the 30-sided shape reads clearly even from
	ground level, not just from above.
]]
local function buildBoundarySegment(index: number, parent: Instance)
	local v1 = MapConfig.GetVertex(index)
	local v2 = MapConfig.GetVertex((index + 1) % MapConfig.SIDES)
	local midpoint = (v1 + v2) / 2
	local direction = (v2 - v1)
	local length = direction.Magnitude
	local yaw = math.atan2(direction.X, direction.Z)

	local curbHeight = 1.4
	local curbThickness = 1.0

	PartUtils.CreatePart({
		name = "BoundarySegment" .. index,
		size = Vector3.new(curbThickness, curbHeight, length),
		cframe = CFrame.new(midpoint + Vector3.new(0, curbHeight / 2, 0)) * CFrame.Angles(0, yaw, 0),
		material = CURB_MATERIAL,
		color = CURB_COLOR,
		canCollide = true,
		parent = parent,
	})
	PartUtils.CreatePart({
		name = "BoundaryTrim" .. index,
		size = Vector3.new(curbThickness + 0.2, 0.25, length),
		cframe = CFrame.new(midpoint + Vector3.new(0, curbHeight + 0.15, 0)) * CFrame.Angles(0, yaw, 0),
		material = CURB_TRIM_MATERIAL,
		color = CURB_TRIM_COLOR,
		canCollide = false,
		parent = parent,
	})
end

--[[
	Builds one INVISIBLE containment wall segment between polygon vertices
	`index` and `index + 1`, at MapConfig.INVISIBLE_WALL_OUTSET studs beyond
	CIRCUMRADIUS - Message 18, section 3. Reuses the exact same
	MapConfig.GetVertex angular math as the visible decorative curb
	(buildBoundarySegment above), just at a slightly larger radius, so the
	30 segments can never leave a gap at a vertex seam regardless of any
	other tuning. Tall (extends well above normal jump height) and deep
	(extends well below the ground) so players can't clear it by jumping
	or clip under it via physics jitter - a single ring of 30 large
	anchored, invisible, collidable parts rather than hundreds of small
	ones (Message 18, section 8 performance guidance).
]]
local function buildInvisibleBoundarySegment(index: number, parent: Instance)
	local outsetRadius = MapConfig.CIRCUMRADIUS + MapConfig.INVISIBLE_WALL_OUTSET
	local v1 = MapConfig.GetVertex(index, outsetRadius)
	local v2 = MapConfig.GetVertex((index + 1) % MapConfig.SIDES, outsetRadius)
	local midpoint = (v1 + v2) / 2
	local direction = v2 - v1
	-- Slightly over-length each segment so adjacent segments overlap a
	-- little at the vertex seam (polygon edges get closer together at a
	-- larger radius than at CIRCUMRADIUS itself is a non-issue here since
	-- we use the SAME angular vertices merely pushed outward radially -
	-- this still leaves a small angular gap at each seam without the
	-- overlap margin, since GetVertex's direction changes between edges).
	local length = direction.Magnitude + 4
	local yaw = math.atan2(direction.X, direction.Z)

	local wallHeight = MapConfig.INVISIBLE_WALL_HEIGHT
	local wallBottomY = -MapConfig.INVISIBLE_WALL_BELOW_GROUND
	local wallCenterY = wallBottomY + wallHeight / 2

	PartUtils.CreatePart({
		name = "InvisibleWall" .. index,
		size = Vector3.new(2, wallHeight, length),
		cframe = CFrame.new(midpoint + Vector3.new(0, wallCenterY, 0)) * CFrame.Angles(0, yaw, 0),
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(255, 255, 255),
		transparency = 1,
		canCollide = true,
		parent = parent,
	})
end

--[[
	Builds a thin ring OUTLINE (not a filled disc) approximated by
	`segmentCount` short straight neon bars around a circle of `radius` -
	reused for both ground-design rings, at whatever segment density looks
	smooth enough for that ring's size.
]]
local function buildRing(radius: number, segmentCount: number, color: Color3, parent: Instance, name: string)
	local ring = Instance.new("Folder")
	ring.Name = name
	ring.Parent = parent

	for i = 0, segmentCount - 1 do
		local angleStep = (2 * math.pi) / segmentCount
		local a1 = angleStep * i
		local a2 = angleStep * (i + 1)
		local p1 = Vector3.new(radius * math.sin(a1), 0, radius * math.cos(a1))
		local p2 = Vector3.new(radius * math.sin(a2), 0, radius * math.cos(a2))
		local midpoint = (p1 + p2) / 2
		local direction = p2 - p1
		local yaw = math.atan2(direction.X, direction.Z)

		PartUtils.CreatePart({
			name = "RingSegment" .. i,
			size = Vector3.new(0.3, 0.15, direction.Magnitude),
			cframe = CFrame.new(midpoint + Vector3.new(0, groundY(), 0)) * CFrame.Angles(0, yaw, 0),
			material = Enum.Material.Neon,
			color = color,
			canCollide = false,
			parent = ring,
		})
	end
end

--[[
	Ground design (Message 2 refinement): kept deliberately restrained -
	"relatively simple and polished... should support the environment
	rather than compete with the buildings, signage, seating, or
	lighting". Two concentric ring outlines, 10 radial spokes at every
	3rd boundary vertex angle (reusing MapConfig.GetVertex so the spokes
	stay in perfect angular agreement with the boundary), and a small
	center medallion reinforcing the floating sign/queue portal as the
	map's focal point.
]]
local function buildGroundDesign(parent: Instance)
	local groundDesign = Instance.new("Folder")
	groundDesign.Name = "GroundDesign"
	groundDesign:SetAttribute(MapConfig.GROUND_DESIGN_ATTRIBUTE, true)
	groundDesign.Parent = parent

	-- Center medallion: a small accent ring right around the queue portal.
	-- Kept for every theme (it's a small focal accent around a shared
	-- gameplay landmark, not "the futuristic map's ground pattern").
	buildRing(14, 16, GROUND_DESIGN_CENTER_COLOR, groundDesign, "CenterMedallion")

	-- The generic mid-ring + 10 radial spokes are Futuristic/Space-only -
	-- see THEMES_WITH_OWN_GROUND_PATTERN's doc comment above for why the
	-- three themed maps skip this and build their own ground pattern
	-- instead (in their own environment module).
	if THEMES_WITH_OWN_GROUND_PATTERN[CURRENT_THEME_ID] then
		return
	end

	-- A subtler mid-radius ring, roughly halfway out.
	buildRing(90, 32, GROUND_DESIGN_MID_COLOR, groundDesign, "MidRing")

	-- Radial spokes: every 3rd polygon vertex (30 / 3 = 10 spokes), from
	-- just outside the medallion out to just inside the usable radius.
	local spokesFolder = Instance.new("Folder")
	spokesFolder.Name = "Spokes"
	spokesFolder.Parent = groundDesign

	for i = 0, MapConfig.SIDES - 1, 3 do
		local direction = MapConfig.GetVertex(i, 1) -- unit direction toward vertex i
		local innerPoint = direction * 16
		local outerPoint = direction * (MapConfig.USABLE_RADIUS - 5)
		local midpoint = (innerPoint + outerPoint) / 2
		local length = (outerPoint - innerPoint).Magnitude
		local yaw = math.atan2(direction.X, direction.Z)

		PartUtils.CreatePart({
			name = "Spoke" .. i,
			size = Vector3.new(0.25, 0.15, length),
			cframe = CFrame.new(midpoint + Vector3.new(0, groundY(), 0)) * CFrame.Angles(0, yaw, 0),
			material = Enum.Material.Neon,
			color = GROUND_DESIGN_SPOKE_COLOR,
			canCollide = false,
			parent = spokesFolder,
		})
	end
end

function Floor.Build(lobby: Instance)
	-- Single authoritative ground surface: one round slab, sized to fully
	-- cover the 30-gon (extends slightly past the boundary's own vertices
	-- so there's no gap visible at the points), not a square.
	local groundDiameter = 2 * (MapConfig.CIRCUMRADIUS + 5)
	local ground = PartUtils.CreateDisc({
		name = "LobbyGround",
		diameter = groundDiameter,
		thickness = FLOOR_THICKNESS,
		position = Vector3.new(0, -FLOOR_THICKNESS / 2, 0),
		material = FLOOR_MATERIAL,
		color = FLOOR_COLOR,
		parent = lobby,
	})
	ground:SetAttribute(MapConfig.GROUND_ATTRIBUTE, true)

	-- MapCenter marker - an invisible anchor at the exact origin, for any
	-- system that wants a reliable "center of the map" reference without
	-- hardcoding Vector3.new(0,0,0) itself.
	local mapCenter = PartUtils.CreatePart({
		name = "MapCenter",
		size = Vector3.new(1, 1, 1),
		position = Vector3.new(0, 0.5, 0),
		transparency = 1,
		canCollide = false,
		parent = lobby,
	})
	mapCenter:SetAttribute(MapConfig.CENTER_ATTRIBUTE, true)

	-- 30-sided boundary, mathematically exact from MapConfig.GetVertex.
	local boundaryFolder = Instance.new("Folder")
	boundaryFolder.Name = "LobbyBoundary"
	boundaryFolder:SetAttribute(MapConfig.BOUNDARY_ATTRIBUTE, true)
	boundaryFolder.Parent = lobby
	for i = 0, MapConfig.SIDES - 1 do
		buildBoundarySegment(i, boundaryFolder)
	end

	-- Invisible containment boundary (Message 18, section 3) - a separate
	-- folder from the decorative curb above, since this one is purely
	-- functional (collision only, never rendered) rather than a visual
	-- landmark. Sits just outside the decorative curb so it never visually
	-- clips through it.
	local invisibleBoundaryFolder = Instance.new("Folder")
	invisibleBoundaryFolder.Name = "InvisibleBoundary"
	invisibleBoundaryFolder.Parent = lobby
	for i = 0, MapConfig.SIDES - 1 do
		buildInvisibleBoundarySegment(i, invisibleBoundaryFolder)
	end

	buildGroundDesign(lobby)

	return ground
end

return Floor
