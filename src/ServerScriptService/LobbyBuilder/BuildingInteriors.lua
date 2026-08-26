--[[
	BuildingInteriors.lua

	Message 15 gave every building a genuinely walkable shell. Message 16
	is a major visual overhaul on top of that shell: a shared architectural
	language (entrance canopy, window strips, a layered roof cap with neon
	trim) applied to every building, PLUS one distinct "identity" massing
	element per building so Shop/DailyRewards/Tutorial/StatisticsBuilding
	read as different structures from across the lobby, not the same box
	with a different sign:
		- Shop: angled glass storefront bays flanking the entrance
		- DailyRewards: a stepped, trophy-like tower rising off the roof
		- Tutorial: a rounded corner turret with a beacon light
		- StatisticsBuilding: a tall vertical "data spire" with neon rings

	LEADERBOARD: Leaderboard Hall no longer gets any geometry from this
	file. It isn't a walk-in building (Message 15/16), and it isn't a
	single freestanding screen either anymore - that design (the old
	BuildLeaderboardScreen below) has been replaced by five separate
	boards fanned across an arc; see LobbyBuilder/LeaderboardBoards.lua,
	which Buildings.lua calls directly for the "LeaderboardHall" entry
	instead of anything in this file.

	Terminals (Shop/Rewards/Statistics/Tutorial): unchanged from Message 15
	- each terminal Part gets a ProximityPrompt with a stable Name, and the
	CLIENT controller that already owns the corresponding panel connects
	directly to that prompt's Triggered signal. No new remotes, no
	duplicate UI/shop/rewards/statistics logic.

	Multi-theme support: every color/material below that isn't purely
	functional (ProximityPrompt config, doorway sizing math, etc.) is
	driven by a small set of mutable module-level variables, latched via
	BuildingInteriors.SetTheme(theme) once per map build (see
	LobbyBuilder/init.lua and Buildings.lua, which cascades its own
	SetTheme call into this module) - every function below already closes
	over these same variables, so a theme swap needs no other changes
	anywhere in this file:
		WALL_MATERIAL / EXTERIOR_WALL_COLOR - structural exterior walls,
			ceiling, roof cap, entrance canopy, doorway header.
		INTERIOR_WALL_COLOR / INTERIOR_FLOOR_COLOR - the (currently mostly
			unused, kept for future interior-specific surfaces) interior
			shell tones.
		FURNITURE_MATERIAL / FURNITURE_COLOR - every freestanding interior
			fixture (shelves, terminal stands, counters, pedestals,
			monitors, benches) and every roof-mounted "identity" massing
			structure's solid body (the reward tower, data spire, turret).
		ACCENT_MATERIAL / ACCENT_COLOR - every glowing trim/accent surface
			that used to be a flat Enum.Material.Neon - roofline/canopy/
			doorway trim, terminal screens, identity-structure trim rings,
			shop marquee, milestone panels, monitor screens, and so on.
		GLASS_MATERIAL / GLASS_COLOR / GLASS_TRANSPARENCY - the side-wall
			window strips and the Shop's storefront bays. For the Lava
			theme this becomes a genuinely different MATERIAL (CrackedLava
			"lava vents" glowing through the wall) rather than a tinted
			pane of Glass, not just a recolor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)
local LobbyTheme = require(script.Parent.LobbyTheme)

local BuildingInteriors = {}

-- Distance from a building's nominal footprint edge to the INNER face of
-- its wall. Every interior fixture is laid out relative to this, so it
-- must not change - see SOLID_WALL_THICKNESS below for the separate knob
-- that controls how thick the wall actually is.
local WALL_THICKNESS = 1

--[[
	LIGHT-LEAK FIX: how thick the structural shell surfaces really are.

	Roblox's voxel lighting grid is 4 studs. Any occluder thinner than one
	voxel cannot block a light at all, so the 1-stud walls and - much worse
	- the 0.5-stud floor and ceiling used to let every interior PointLight
	(Range 20, Shadows left at its `false` default) pour straight out
	through the roof and walls. That is the light "peeking from" the
	buildings.

	The surfaces are now genuinely thicker than a voxel, and critically
	they grow OUTWARD ONLY: every inner face stays exactly where it was, so
	no interior furniture, terminal, doorway or collision surface moves by
	a single stud. For the three custom-exterior themes the extra thickness
	is completely hidden inside the dome/volcano/hull anyway.
]]
local SOLID_WALL_THICKNESS = 4.5
local SOLID_SLAB_THICKNESS = 4.5

local MIN_DOOR_WIDTH = 8
local MAX_DOOR_WIDTH = 14

--[[
	Applied to every light built INSIDE a building. Shadows=true makes
	Roblox actually occlude the light with geometry rather than lighting
	everything in radius regardless of walls, and the reduced range keeps
	the falloff inside the room even where voxel resolution is coarse.
	Together with the thickened surfaces above this is what actually seals
	the interiors.
]]
local function sealInteriorLight(light: Light, range: number): Light
	light.Shadows = true
	light.Range = range
	return light
end

local defaultTheme = LobbyTheme.Get()
local WALL_MATERIAL = defaultTheme.buildingWallMaterial
local EXTERIOR_WALL_COLOR = defaultTheme.buildingExteriorWallColor
local INTERIOR_WALL_COLOR = defaultTheme.buildingInteriorWallColor
local INTERIOR_FLOOR_COLOR = defaultTheme.buildingInteriorFloorColor
local CEILING_COLOR = defaultTheme.buildingCeilingColor
local ROOFCAP_COLOR = defaultTheme.buildingRoofCapColor
local HEADER_COLOR = defaultTheme.buildingHeaderColor
local CANOPY_COLOR = defaultTheme.buildingCanopyColor
local ACCENT_MATERIAL = defaultTheme.buildingAccentMaterial
local ACCENT_COLOR = defaultTheme.buildingAccentColor
local GLASS_MATERIAL = defaultTheme.buildingGlassMaterial
local GLASS_COLOR = defaultTheme.buildingGlassColor
local GLASS_TRANSPARENCY = defaultTheme.buildingGlassTransparency
local FURNITURE_MATERIAL = defaultTheme.buildingFurnitureMaterial
local FURNITURE_COLOR = defaultTheme.buildingFurnitureColor
local CURRENT_THEME_ID = defaultTheme.id

-- Themes that get a fully custom hand-assembled exterior BODY (igloo
-- brick dome / volcanic boulder mound / coral reef, see the FULL-BODY
-- EXTERIOR builders below) instead of the shared box shell's own
-- decorative surfaces (windows, entrance canopy, doorway trim, roof
-- cap). Explicit direction: "do not leave the old prism shells
-- underneath the new designs if they remain visually identifiable" -
-- so for these three themes, BuildShell skips every decorative surface
-- that would otherwise read as "a box" (see the CUSTOM_EXTERIOR_THEMES
-- checks throughout BuildShell below), leaving only the plain
-- structural walls/floor/ceiling needed for collision and interior
-- furniture layout - completely covered from outside by the custom
-- exterior body.
local CUSTOM_EXTERIOR_THEMES = {
	IceAge = true,
	Lava = true,
	UnderTheSea = true,
}

--[[
	Exposed so OTHER construction modules (Buildings.lua's TrimBand, in
	particular) can skip their own exterior box dressing for these three
	themes too, without duplicating this table - anything that decorates
	the box's outside needs to know the same thing BuildShell already
	does: is this building about to be fully wrapped in a custom dome/
	volcano/hull body?
]]
function BuildingInteriors.HasCustomExterior(themeId: string): boolean
	return CUSTOM_EXTERIOR_THEMES[themeId] == true
end

--[[
	Latches `theme` for every building-interior/exterior color and
	material in this file - see the module doc comment above for exactly
	which surfaces each field drives.
]]
function BuildingInteriors.SetTheme(theme: LobbyTheme.Theme)
	WALL_MATERIAL = theme.buildingWallMaterial
	EXTERIOR_WALL_COLOR = theme.buildingExteriorWallColor
	INTERIOR_WALL_COLOR = theme.buildingInteriorWallColor
	INTERIOR_FLOOR_COLOR = theme.buildingInteriorFloorColor
	CEILING_COLOR = theme.buildingCeilingColor
	ROOFCAP_COLOR = theme.buildingRoofCapColor
	HEADER_COLOR = theme.buildingHeaderColor
	CANOPY_COLOR = theme.buildingCanopyColor
	ACCENT_MATERIAL = theme.buildingAccentMaterial
	ACCENT_COLOR = theme.buildingAccentColor
	GLASS_MATERIAL = theme.buildingGlassMaterial
	GLASS_COLOR = theme.buildingGlassColor
	GLASS_TRANSPARENCY = theme.buildingGlassTransparency
	FURNITURE_MATERIAL = theme.buildingFurnitureMaterial
	FURNITURE_COLOR = theme.buildingFurnitureColor
	CURRENT_THEME_ID = theme.id
end

--[[
	Per-theme interior "flourish" - one signature decorative prop per
	theme, added to every building's interior (see the BuildShell call site
	below) so each map's buildings read as intentionally designed for that
	world rather than the same shell recolored. Each builder reuses the
	ALREADY-latched ACCENT_MATERIAL/ACCENT_COLOR/FURNITURE_MATERIAL/
	FURNITURE_COLOR module variables above (set once per map by SetTheme)
	rather than hardcoding a second copy of any theme's palette here - the
	SHAPE differs per theme (holographic panel / lava vent / cosmic orrery
	/ coral cluster / ice crystal), but the COLOR driving it always comes
	from LobbyTheme, so a future theme edit there is picked up here
	automatically with no changes needed in this file.
]]
local function buildFuturisticFlourish(model: Model, position: Vector3)
	local panel = PartUtils.CreatePart({
		name = "HoloPanel",
		size = Vector3.new(2.2, 2.2, 0.1),
		position = position,
		material = Enum.Material.Neon,
		color = ACCENT_COLOR,
		transparency = 0.5,
		canCollide = false,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "HoloPanelFrame",
		size = Vector3.new(2.4, 2.4, 0.05),
		position = position - Vector3.new(0, 0, 0.08),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		transparency = 0.2,
		canCollide = false,
		parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = ACCENT_COLOR
	light.Range = LightingConfig.ACCENT_LIGHT_RANGE * 0.6
	light.Brightness = LightingConfig.ACCENT_LIGHT_BRIGHTNESS * 0.7
	light.Parent = panel
end

local function buildLavaFlourish(model: Model, position: Vector3)
	local vent = PartUtils.CreateDisc({
		name = "LavaVent",
		diameter = 2.2,
		thickness = 0.15,
		position = position - Vector3.new(0, 1.7, 0),
		material = Enum.Material.CrackedLava,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})
	for i, offset in ipairs({ Vector3.new(-0.9, -1.5, -0.6), Vector3.new(1.0, -1.4, 0.5) }) do
		PartUtils.CreatePart({
			name = "VentRock" .. i,
			size = Vector3.new(0.9, 0.9, 0.9),
			position = position + offset,
			material = FURNITURE_MATERIAL,
			color = FURNITURE_COLOR,
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = model,
		})
	end
	local light = Instance.new("PointLight")
	light.Color = ACCENT_COLOR
	light.Range = LightingConfig.ACCENT_LIGHT_RANGE * 0.6
	light.Brightness = LightingConfig.ACCENT_LIGHT_BRIGHTNESS
	light.Parent = vent
end

local function buildSpaceFlourish(model: Model, position: Vector3)
	local ring = PartUtils.CreateDisc({
		name = "OrreryRing",
		diameter = 2.6,
		thickness = 0.12,
		position = position,
		material = Enum.Material.Neon,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})
	ring.CFrame = ring.CFrame * CFrame.Angles(math.rad(25), 0, 0)
	local planet = PartUtils.CreatePart({
		name = "OrreryPlanet",
		size = Vector3.new(0.9, 0.9, 0.9),
		position = position,
		material = Enum.Material.Neon,
		color = FURNITURE_COLOR,
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = ACCENT_COLOR
	light.Range = LightingConfig.ACCENT_LIGHT_RANGE * 0.6
	light.Brightness = LightingConfig.ACCENT_LIGHT_BRIGHTNESS * 0.7
	light.Parent = planet
end

local function buildUnderTheSeaFlourish(model: Model, position: Vector3)
	for i, offset in ipairs({ Vector3.new(-0.6, -0.8, -0.4), Vector3.new(0.5, -1.0, 0.3), Vector3.new(0, -0.4, 0.5) }) do
		PartUtils.CreatePart({
			name = "CoralBit" .. i,
			size = Vector3.new(1.1, 1.1, 1.1),
			position = position + offset,
			material = Enum.Material.Rock,
			color = FURNITURE_COLOR,
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = model,
		})
	end
	local tip = PartUtils.CreatePart({
		name = "CoralGlow",
		size = Vector3.new(0.55, 0.55, 0.55),
		position = position + Vector3.new(0, 0.35, 0),
		material = Enum.Material.Neon,
		color = ACCENT_COLOR,
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = ACCENT_COLOR
	light.Range = LightingConfig.ACCENT_LIGHT_RANGE * 0.5
	light.Brightness = LightingConfig.ACCENT_LIGHT_BRIGHTNESS * 0.6
	light.Parent = tip
end

local function buildIceAgeFlourish(model: Model, position: Vector3)
	for i, offset in ipairs({ Vector3.new(-0.5, 0, -0.3), Vector3.new(0.4, 0.3, 0.2), Vector3.new(0, 0.6, 0) }) do
		PartUtils.CreatePart({
			className = "WedgePart",
			name = "Icicle" .. i,
			size = Vector3.new(0.7, 1.6, 0.7),
			cframe = CFrame.new(position + offset) * CFrame.Angles(math.pi, 0, 0),
			material = Enum.Material.Ice,
			color = FURNITURE_COLOR,
			canCollide = false,
			parent = model,
		})
	end
	local glow = PartUtils.CreatePart({
		name = "FrostGlow",
		size = Vector3.new(0.45, 0.45, 0.45),
		position = position,
		material = Enum.Material.Neon,
		color = ACCENT_COLOR,
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = ACCENT_COLOR
	light.Range = LightingConfig.ACCENT_LIGHT_RANGE * 0.5
	light.Brightness = LightingConfig.ACCENT_LIGHT_BRIGHTNESS * 0.6
	light.Parent = glow
end

local FLOURISH_BUILDERS = {
	Futuristic = buildFuturisticFlourish,
	Lava = buildLavaFlourish,
	Space = buildSpaceFlourish,
	UnderTheSea = buildUnderTheSeaFlourish,
	IceAge = buildIceAgeFlourish,
}

--[[
	Adds this map's signature interior flourish to `model`, in a back
	corner near the ceiling (a spot every building's furniture layout
	leaves clear, regardless of which building this is) - see the
	FLOURISH_BUILDERS table above. Falls back to doing nothing for an
	unrecognized theme id rather than erroring, so a future theme can be
	added to LobbyTheme without this file needing an update first.
]]
local function addThemedFlourish(def, model: Model)
	local builder = FLOURISH_BUILDERS[CURRENT_THEME_ID]
	if not builder then
		return
	end
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2
	local position = def.position + Vector3.new(halfX - 2, def.height - 4, -(halfZ - 2))
	builder(model, position)
end

--[[
	Theme-signature FULL-BODY EXTERIOR - replaces the old "flat RoofCap
	plus a small accent stuck on top of an otherwise plain box" approach.
	Each of these now builds a genuinely different BODY shape (a dome, a
	volcanic mound, an ellipsoid hull) that starts at GROUND level and
	fully encloses the existing box shell beneath it, so the building's
	overall silhouette actually reads as an igloo / mini-volcano / sunken
	hull from across the map - not a rectangular building with a small
	ornament on its roof. The box shell itself (walls/doorway/collision/
	interiors) is untouched and still does all the structural and
	gameplay work; every shape below is a non-collidable decorative wrap
	around it, sized to fully contain its footprint. A short decorative
	entrance tunnel (themedEntranceTunnel) bridges the real doorway out
	past each wrap's own curvature, so the entrance still reads as an
	obvious walk-up-to feature instead of appearing sealed behind solid
	snow/rock/hull.
		IceAge: a rounded ice dome (full igloo silhouette) with stacked
			ring seams and irregular snowdrift mounds at its base.
		Lava: a tapering volcanic mound (full mini-volcano silhouette,
			ground to crater) with lava falls running its full height and
			scattered boulder formations at its base.
		UnderTheSea: a rounded ellipsoid hull (submarine/sunken-ship
			silhouette) with paneled seams, a conning tower + periscope,
			and portholes down both sides.
	Futuristic/Space keep only the existing flat RoofCap (no entry in
	ROOF_SILHOUETTE_BUILDERS below), unchanged from before this feature
	existed.

	NOTE ON ORDERING: this whole block is declared HERE - before
	BuildShell - specifically because BuildShell calls
	addThemedRoofSilhouette below, and Luau (like standard Lua) resolves
	a `local function` name lexically from its declaration point onward,
	not by hoisting - a call to a same-named local declared LATER in the
	same chunk silently resolves to a global (nil) instead, which is
	exactly the bug this ordering avoids.
]]
--[[
	Angular half-width (radians) of the OPEN NOTCH that must be carved out
	of a collar ring at the given `ringRadius` so the real doorway (width
	`doorWidth`, centered on angle 0 = the +Z/plaza-facing direction the
	entrance always opens toward) stays physically uncovered by that
	ring's chunks/bricks/plates. A fixed literal STUD margin (not a fixed
	ANGLE) is converted to whatever angle that margin subtends at this
	specific ring's radius, so the notch is the same real-world width at
	every tier instead of flaring open wider on inner rings and pinching
	shut on outer ones.

	Used by every custom-exterior collar-ring loop below (dome bricks/
	volcano chunks/hull plates) - this is the fix for "you removed the
	feature to enter the buildings": those rings used to close a complete
	360-degree loop with no gap at all, so the entrance tunnel dead-ended
	into solid-looking (if non-collide) wrap geometry instead of opening
	through an actual carved archway.
]]
local function entranceNotchHalfAngle(ringRadius: number, doorWidth: number): number
	local halfGap = doorWidth / 2 + 3 -- stud margin so framing rock/ice/plates don't crowd the opening
	return math.atan2(halfGap, math.max(ringRadius, 1))
end

--[[
	True if `angle` (radians, same convention as the ring-placement loops:
	0 = +Z/plaza-facing) falls inside the entrance notch and this piece
	should be skipped entirely.
]]
local function isInEntranceNotch(angle: number, ringRadius: number, doorWidth: number): boolean
	local normalized = ((angle + math.pi) % (2 * math.pi)) - math.pi
	return math.abs(normalized) < entranceNotchHalfAngle(ringRadius, doorWidth)
end

--[[
	=====================================================================
	CONTINUOUS SHELL BUILDER
	=====================================================================

	This is the single, shared fix for "the structures look like a
	collection of separate primitives with gaps between them".

	THE BUG IT REPLACES. Every custom exterior below (igloo dome, volcano
	mound, submarine hull) used to place its surface pieces at an angular
	spacing derived from the piece's own width - e.g.
	`count = floor(circumference / pieceWidth)` - and then build each
	piece at `pieceWidth * rng(0.85, 1.05)`. Two pieces spaced exactly
	their own width apart only ever ABUT along a single edge in the very
	best case, and the 0.85 lower bound guaranteed a literal 15% gap much
	of the time. On top of that, each piece got radial jitter (up to
	+/-13% of the ring radius) and vertical jitter of a couple of studs -
	both LARGER than the pieces' own thickness - which pulled neighbours
	apart into a loose scatter. Vertically it was worse still: rings were
	stepped by (height / 7) while the pieces themselves were only ~3 studs
	tall, leaving multi-stud horizontal bands of open air between rings.
	That is why the buildings read as piles of blocks with daylight
	through them rather than as one built object.

	HOW THIS FIXES THE GEOMETRY (not the appearance - the geometry):

	  1. OVERLAP IS DERIVED, NOT CONFIGURED. A ring's piece width is
	     computed FROM that ring's own arc spacing and multiplied by
	     SHELL_OVERLAP, so neighbours always intersect by ~45% of their
	     width. There is no parameter combination a caller can pass that
	     produces abutting-but-not-overlapping pieces.

	  2. THE SHELL FOLLOWS THE PROFILE'S SLOPE. Each piece is tilted to
	     lie along the local surface tangent (computed by sampling the
	     profile either side of the ring) and is built as long as the
	     SLANT distance to the next ring, times the same overlap factor.
	     A shrinking radius therefore can no longer open a radial gap
	     between one ring and the next - which is what made domes and
	     cone caps come apart near the top.

	  3. TWO STAGGERED LAYERS. The shell is built twice: an inner layer
	     inset radially and rotated by half an arc spacing, so its pieces
	     sit directly behind the outer layer's seams. This is real
	     geometry, not a texture or lighting trick - it also gives the
	     walls genuine thickness, so they read as a solid built mass
	     rather than the old 1.4-stud paper shell.

	Irregularity is still applied for a hand-built look, but every jitter
	is CLAMPED to a fraction of the overlap margin, so no amount of
	randomness can re-open a gap.
]]
local SHELL_OVERLAP = 1.9

--[[
	Builds one continuous shell of revolution around `basePos`.

	opts.profile(y) -> radius is the shape's silhouette; it is sampled
	either side of every ring to derive the local slope, so callers only
	ever have to describe the shape, never the tiling.
]]
local function buildContinuousShell(opts)
	local model = opts.model
	local basePos = opts.basePos
	local rng = opts.rng
	local baseY = opts.baseY or 0
	local topY = opts.topY
	local profile = opts.profile
	local thickness = opts.thickness or 3
	local doorWidth = opts.doorWidth
	local notchTopY = opts.notchTopY or -1
	local layers = opts.layers or 2

	local span = topY - baseY
	if span <= 0 then
		return
	end

	-- Ring spacing is capped so that even on a tall building the shell is
	-- stepped finely enough for consecutive rings to overlap generously.
	local ringCount = math.max(3, math.ceil(span / math.max(opts.stepY or 2.8, 0.8)))
	local step = span / ringCount

	for i = 0, ringCount do
		local y = baseY + step * i
		local radius = profile(y)
		if radius < 0.8 then
			continue
		end

		-- Local surface tangent, from the profile either side of this ring.
		-- dr < 0 means the surface is drawing inward as it rises (a dome or
		-- cone flank); tiltX rotates each piece to lie flat along it.
		local dr = profile(math.min(y + step * 0.5, topY)) - profile(math.max(y - step * 0.5, baseY))
		local slant = math.sqrt(dr * dr + step * step)
		local tiltX = math.atan2(dr, step)

		local circumference = 2 * math.pi * radius
		local count = math.max(8, math.ceil(circumference / math.max(opts.pieceTarget or 6, 1)))
		local arcSpacing = circumference / count
		local pieceWidth = arcSpacing * SHELL_OVERLAP
		local pieceLength = slant * SHELL_OVERLAP

		-- Jitter budget: half the overlap margin, so two neighbours still
		-- intersect even when both jitter toward each other's far side.
		local overlapMargin = (pieceWidth - arcSpacing) / 2
		local radialJitter = math.min(opts.radialJitter or 0, overlapMargin * 0.5)
		local tiltJitter = opts.tiltJitter or 0

		for layer = 0, layers - 1 do
			-- Inner layers are rotated half a spacing so their pieces sit
			-- behind the outer layer's seams, and inset so they never poke
			-- back out through the surface.
			local angleOffset = (arcSpacing / math.max(radius, 0.001)) * 0.5 * layer
			local layerInset = thickness * 0.55 * layer

			for p = 1, count do
				local angle = (2 * math.pi / count) * p + angleOffset
				if doorWidth and y <= notchTopY and isInEntranceNotch(angle, radius, doorWidth) then
					continue
				end

				local r = radius - layerInset
				if radialJitter > 0 then
					r += rng:NextNumber(-radialJitter, radialJitter)
				end

				local piecePos = basePos + Vector3.new(math.sin(angle) * r, y, math.cos(angle) * r)
				local cf = CFrame.new(piecePos) * CFrame.Angles(0, angle, 0) * CFrame.Angles(tiltX, 0, 0)
				if tiltJitter > 0 then
					cf = cf * CFrame.Angles(rng:NextNumber(-tiltJitter, tiltJitter), 0, rng:NextNumber(-tiltJitter, tiltJitter))
				end

				PartUtils.CreatePart({
					name = ("%sL%dT%dP%d"):format(opts.namePrefix, layer, i, p),
					size = Vector3.new(pieceWidth, pieceLength, thickness),
					cframe = cf,
					material = if opts.materialPicker then opts.materialPicker(rng) else opts.material,
					color = if opts.colorPicker then opts.colorPicker(rng) else opts.color,
					canCollide = false,
					parent = model,
				})
			end
		end
	end
end

--[[
	A wide, very shallow apron fanning outward from the foot of a shell so
	the structure grows OUT OF the ground instead of being a mound dropped
	onto flat terrain. Same overlap guarantees as buildContinuousShell.
	Kept clear of the entrance notch so it never steps up into the doorway.
]]
local function buildGroundSkirt(opts)
	local model = opts.model
	local basePos = opts.basePos
	local rng = opts.rng
	local innerRadius = opts.innerRadius
	local outerRadius = opts.outerRadius
	local startHeight = opts.startHeight or 2.5
	local ringCount = math.max(2, opts.ringCount or 3)

	for ring = 1, ringCount do
		local t = ring / ringCount
		local radius = innerRadius + (outerRadius - innerRadius) * t
		local y = startHeight * (1 - t) * 0.6
		local bandDepth = ((outerRadius - innerRadius) / ringCount) * SHELL_OVERLAP

		local circumference = 2 * math.pi * radius
		local count = math.max(10, math.ceil(circumference / math.max(opts.pieceTarget or 9, 1)))
		local arcSpacing = circumference / count
		local pieceWidth = arcSpacing * SHELL_OVERLAP

		for p = 1, count do
			local angle = (2 * math.pi / count) * p
			if opts.doorWidth and isInEntranceNotch(angle, radius, opts.doorWidth) then
				continue
			end
			local pos = basePos + Vector3.new(math.sin(angle) * radius, y, math.cos(angle) * radius)
			PartUtils.CreatePart({
				name = ("%sR%dP%d"):format(opts.namePrefix, ring, p),
				size = Vector3.new(pieceWidth, opts.thickness or 2.2, bandDepth),
				cframe = CFrame.new(pos)
					* CFrame.Angles(0, angle, 0)
					* CFrame.Angles(math.rad(rng:NextNumber(-4, 4)), 0, 0),
				material = if opts.materialPicker then opts.materialPicker(rng) else opts.material,
				color = if opts.colorPicker then opts.colorPicker(rng) else opts.color,
				canCollide = false,
				parent = model,
			})
		end
	end
end

--[[
	A genuine curved archway around the entrance mouth: voussoir blocks
	stepped around a half-circle, each overlapping its neighbour, so the
	doorway reads as cut THROUGH the shell rather than as a rectangular
	hole with loose blocks beside it. Returns nothing; purely decorative
	framing around the (already-built) tunnel.
]]
local function buildEntranceArch(opts)
	local model = opts.model
	local basePos = opts.basePos
	local doorWidth = opts.doorWidth
	local doorHeight = opts.doorHeight
	local z = opts.z
	local archRadius = doorWidth / 2 + 1.6
	local springLine = doorHeight - archRadius + 1.2

	local segCount = opts.segments or 13
	for s = 0, segCount do
		local t = s / segCount
		local angle = math.pi * t -- 0 = right springing, pi = left springing
		local x = math.cos(angle) * archRadius
		local y = springLine + math.sin(angle) * archRadius
		-- Segment length is the arc step times the shared overlap factor, so
		-- consecutive voussoirs always intersect.
		local segLength = (math.pi * archRadius / segCount) * SHELL_OVERLAP
		PartUtils.CreatePart({
			name = "EntranceArchBlock" .. s,
			size = Vector3.new(opts.blockDepth or 2.2, segLength, opts.thickness or 2.6),
			cframe = CFrame.new(basePos + Vector3.new(x, y, z)) * CFrame.Angles(0, 0, angle - math.pi / 2),
			material = opts.material,
			color = opts.color,
			canCollide = false,
			parent = model,
		})
	end

	-- Solid jambs from the springing line down to the ground, so the arch
	-- lands on real geometry instead of ending in mid-air.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "EntranceJamb",
			size = Vector3.new(opts.blockDepth or 2.2, springLine + 1, opts.thickness or 2.6),
			position = basePos + Vector3.new(side * archRadius, (springLine + 1) / 2, z),
			material = opts.material,
			color = opts.color,
			canCollide = false,
			parent = model,
		})
	end
end

local function themedEntranceTunnel(def, model: Model, tunnelLength: number, tunnelMaterial: Enum.Material, tunnelColor: Color3)
	local basePos = def.position
	local halfZ = def.size.Y / 2
	local doorWidth = math.clamp(def.size.X * 0.22, MIN_DOOR_WIDTH, MAX_DOOR_WIDTH)
	local doorHeight = math.min(10, def.height - 4)

	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "EntranceTunnelWall",
			size = Vector3.new(0.8, doorHeight, tunnelLength),
			position = basePos + Vector3.new(side * (doorWidth / 2 + 0.4), doorHeight / 2, halfZ + tunnelLength / 2),
			material = tunnelMaterial,
			color = tunnelColor,
			canCollide = false,
			parent = model,
		})
	end
	PartUtils.CreatePart({
		name = "EntranceTunnelRoof",
		size = Vector3.new(doorWidth + 1.6, 0.8, tunnelLength),
		position = basePos + Vector3.new(0, doorHeight + 0.4, halfZ + tunnelLength / 2),
		material = tunnelMaterial,
		color = tunnelColor,
		canCollide = false,
		parent = model,
	})

	--[[
		Large, unmissable name plate mounted on the OUTER facade, right at
		the tunnel mouth facing the plaza - fixes "no name on the face of
		its new design". The old addSign() plaque still exists on the
		inner "Base" header part (Buildings.lua still calls it, unchanged),
		but that part now sits buried deep inside the dome/volcano/hull
		wrap at the BACK of the entrance tunnel, invisible from outside.
		This plate sits at the FRONT of the tunnel instead, exactly where a
		player walking up actually looks.
	]]
	--[[
		Mounted CLEAR OF THE ARCHWAY. The themed builders now frame this
		tunnel with a real vaulted arch whose crown rises to roughly
		doorHeight + 2.5 at the tunnel mouth. The plate used to sit at
		doorHeight + 1.9 at that same depth, which put it bodily inside the
		crown blocks - readable from nowhere. It now sits above the crown
		and slightly proud of the outermost arch ring, on the flat facade
		above the opening, which is where a player walking up actually
		looks.
	]]
	--[[
		Deep enough to reach BACK INTO the shell it is mounted on. A 0.4-stud
		plate parked just outside the wrap's outer face is a floating sign;
		giving it real depth means the plate physically intersects the
		facade behind it, so it reads (and audits) as mounted rather than
		hovering.
	]]
	--[[
		Sized for legibility from normal walking distance. The plate used to
		be 3.2 studs tall and only doorWidth+6 wide, so TextScaled shrank the
		name into a thin band readable only from directly underneath. Height
		is what actually drives glyph size for a single line of TextScaled
		text, so it is now more than doubled, and the width is derived from
		the building's own frontage - giving a long name like "Daily Rewards"
		proportionally more room while never exceeding the facade, so it
		cannot clip past the shell's edge.
	]]
	local plateWidth = math.clamp(def.size.X * 0.9, doorWidth + 10, doorWidth + 26)
	-- Tall enough for the TWO-LINE layout FormatSignText now produces (see
	-- that function for why two lines is what actually drives glyph size).
	-- At 8.5 a two-line name was height-bound again, undoing the gain.
	local plateHeight = 12
	local plateY = doorHeight + 8.6
	local plateDepth = 2.2
	local plateZ = halfZ + tunnelLength - 0.4
	local platePart = PartUtils.CreatePart({
		name = "EntranceNamePlate",
		size = Vector3.new(plateWidth, plateHeight, plateDepth),
		position = basePos + Vector3.new(0, plateY, plateZ),
		material = tunnelMaterial,
		color = tunnelColor,
		canCollide = false,
		parent = model,
	})
	local nameGui = Instance.new("SurfaceGui")
	nameGui.Face = Enum.NormalId.Back -- Back = +Z face, which faces the plaza/spawns (see addSign)
	nameGui.LightInfluence = 0
	nameGui.PixelsPerStud = 48
	nameGui.Parent = platePart

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 1)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextScaled = true
	nameLabel.Text = BuildingInteriors.FormatSignText(def.displayName or def.name or "")
	nameLabel.Parent = nameGui

	-- A pair of small accent lamps flanking the plate so it reads as lit
	-- signage rather than a plain placard, matching whichever theme this is.
	-- Seated ON the plate's own ends (not floating a stud clear of them), so
	-- each lamp intersects the signage it lights.
	for _, side in ipairs({ -1, 1 }) do
		local lamp = PartUtils.CreatePart({
			name = "EntranceLamp",
			size = Vector3.new(1.4, 1.4, 1.4),
			position = basePos + Vector3.new(side * (plateWidth / 2 - 0.2), plateY, plateZ),
			material = Enum.Material.Neon,
			color = ACCENT_COLOR,
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = model,
		})
		local light = Instance.new("PointLight")
		light.Color = ACCENT_COLOR
		light.Range = LightingConfig.ACCENT_LIGHT_RANGE * 0.5
		light.Brightness = LightingConfig.ACCENT_LIGHT_BRIGHTNESS
		light.Parent = lamp
	end
end

--[[
	Shared enclosing-envelope math for the three custom exterior body
	builders below (dome/volcano/hull).

	CONTAINMENT BUG FIX: every one of these used to derive its radius
	purely from the box's footprint (halfDiag * ~1.1) and then taper that
	radius continuously from ground level all the way to the peak (a pure
	hemisphere/cone/ellipsoid profile). Since the actual box shell stays
	at its FULL footprint all the way up to its FULL height (it has
	vertical walls, not a taper), a profile that starts shrinking at
	y = 0 is mathematically guaranteed to fall inside the box's own
	corners well before reaching the roofline - the box's upper walls/
	roof cap end up sticking out through the "custom" shape, which is
	exactly why buildings still read as boxes with rocks/ice/hull plates
	glued to their roof instead of genuinely different silhouettes.

	Fix: split the body into two zones instead of one continuous taper -
		1. COLLAR (y = 0..def.height): radius held at a CONSTANT
		   collarRadius comfortably larger than the box's own worst-case
		   corner distance (halfDiag) for the building's entire height, so
		   nothing the box shell builds can ever poke through it.
		2. CAP (y = def.height..peak): only ABOVE the roofline - where
		   there is no more box geometry left to contain - does the shape
		   actually taper into a dome/cone/rounded point. This is the only
		   zone that needs to look "curved"; the collar below it is what
		   guarantees full coverage.
]]
--[[
	Per-theme envelope proportions, in ONE place.

	These used to be magic numbers passed inline at each of the three
	builder call sites, which meant nothing outside this file could know
	how tall or how wide a finished building actually is. That caused two
	real bugs: the overhead teleport sign was anchored off `def.height` and
	ended up buried INSIDE the Lava volcano (whose cap rises ~1.6x halfDiag
	above the roofline), and the teleport landed a player at halfZ+6, which
	is inside the shell rather than in front of it.

	`skirt` is how far the ground apron fans out past the body radius - the
	outermost geometry a player can be standing next to.
]]
local EXTERIOR_ENVELOPE = {
	IceAge = { radius = 1.35, capHeight = 0.62, skirt = 1.5 },
	Lava = { radius = 1.18, capHeight = 1.35, skirt = 1.75 },
	UnderTheSea = { radius = 1.2, capHeight = 0.55, skirt = 1.45 },
}

local function halfDiagonalOf(def): number
	return math.sqrt((def.size.X / 2) ^ 2 + (def.size.Y / 2) ^ 2)
end

--[[
	Lays a building's display name out for a WIDE, SHORT sign face.

	Why this exists: every facade name in the project is drawn with
	TextScaled on a plate far wider than it is tall. TextScaled preserves
	the text's aspect ratio, so for a SINGLE line the glyph height is
	capped by the plate's WIDTH divided by the character count - the
	plate's own HEIGHT is never the binding constraint for a long name.
	Measured on the as-built plates: "Statistics Building" (19 chars) on a
	32.4-wide plate renders glyphs only ~3.4 studs tall inside an 8.5-stud
	face, using barely 40% of the height available to it. That is exactly
	the "very thin" appearance this pass fixes, and no amount of extra
	plate height alone can fix it.

	Breaking the name across two lines roughly halves the per-line
	character count, which roughly DOUBLES the glyph height for the same
	plate width - the actual lever. Single-word names ("Shop") are left
	alone: they already fill the face, and splitting them would only
	shrink them.

	Splits at the gap leaving the two lines most even in length, so
	"Statistics Building" breaks 10/8 rather than lopsidedly.
]]
function BuildingInteriors.FormatSignText(displayName: string): string
	local words = {}
	for word in displayName:gmatch("%S+") do
		table.insert(words, word)
	end
	if #words < 2 then
		return displayName
	end

	local bestSplit, bestDelta = 1, math.huge
	for split = 1, #words - 1 do
		local left, right = 0, 0
		for i = 1, split do
			left += #words[i] + 1
		end
		for i = split + 1, #words do
			right += #words[i] + 1
		end
		local delta = math.abs(left - right)
		if delta < bestDelta then
			bestDelta, bestSplit = delta, split
		end
	end

	return table.concat(words, " ", 1, bestSplit)
		.. "\n"
		.. table.concat(words, " ", bestSplit + 1, #words)
end

--[[
	The Y of the highest solid geometry this building will actually have,
	for the given theme - what anything mounted ABOVE the building (the
	overhead teleport sign) must clear. Pure: takes themeId explicitly
	rather than reading the latched CURRENT_THEME_ID, so callers outside
	the build pass (e.g. BuildingTeleportSystem) get correct answers.
]]
function BuildingInteriors.GetExteriorTopY(def, themeId: string): number
	local env = EXTERIOR_ENVELOPE[themeId]
	if not env then
		-- Box themes: the tallest roof topper is the Statistics data spire
		-- at +16 above the roofline (see addStatisticsIdentity).
		return def.position.Y + def.height + 16
	end
	local bodyRadius = halfDiagonalOf(def) * env.radius
	local top = def.position.Y + def.height + bodyRadius * env.capHeight
	if themeId == "UnderTheSea" then
		top += 10 -- conning tower + periscope stand above the deck
	end
	return top
end

--[[
	How far out along +Z from the building's centre a player should stand
	to be genuinely IN FRONT OF the entrance rather than inside the shell
	wrapped around it. For box themes that is just past the front wall; for
	the custom exteriors the body and its entrance tunnel reach out to
	roughly bodyRadius + 2, so the standoff has to clear that.
]]
function BuildingInteriors.GetEntranceStandoff(def, themeId: string): number
	local halfZ = def.size.Y / 2
	local env = EXTERIOR_ENVELOPE[themeId]
	if not env then
		return halfZ + 6
	end
	local bodyRadius = halfDiagonalOf(def) * env.radius
	return math.max(halfZ + 6, bodyRadius + 8)
end

local function computeEnclosingEnvelope(def, radiusMultiplier: number, capHeightMultiplier: number)
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2
	local halfDiag = math.sqrt(halfX ^ 2 + halfZ ^ 2)
	local collarRadius = halfDiag * radiusMultiplier
	local collarTop = def.height
	local capHeight = collarRadius * capHeightMultiplier
	return halfDiag, collarRadius, collarTop, collarTop + capHeight
end

local function addIceAgeDome(def, model: Model)
	local basePos = def.position
	local halfZ = def.size.Y / 2
	-- Wider, lower dome than the hull's proportions (1.35 radius vs 1.2,
	-- 0.62 cap-height vs 0.55-0.85) so this genuinely reads as a squat
	-- igloo mound - a real igloo bulges out close to the ground and then
	-- curves over in a shallow dome, not a tall rounded tower - instead of
	-- looking like a taller, narrower version of the UnderTheSea hull.
	local halfDiag, domeRadius, collarTop, peakY = computeEnclosingEnvelope(def, EXTERIOR_ENVELOPE.IceAge.radius, EXTERIOR_ENVELOPE.IceAge.capHeight)
	local capHeight = peakY - collarTop
	local rng = Random.new(math.floor(basePos.X * 733 + basePos.Z * 271))
	local doorWidth = math.clamp(def.size.X * 0.22, MIN_DOOR_WIDTH, MAX_DOOR_WIDTH)
	local doorHeight = math.min(10, def.height - 4)

	--[[
		ONE-PIECE IGLOO SHELL.

		Previously this stacked discrete "ice bricks" at an angular spacing
		equal to each brick's own width (and then shrank a random 15% off
		many of them), on tiers spaced far further apart than the bricks
		were tall - so the dome came apart into a scatter of floating
		blocks. It is now a single continuous shell of revolution built by
		buildContinuousShell, which derives every piece's size FROM its
		spacing and tilts each one along the dome's local slope, so the
		wall, the shoulder and the roof are one unbroken curved surface.

		The blocky ice-brick READING is preserved (the shell is still tiled
		from individual tangent blocks with slight tilt variation, and the
		staggered inner layer shows through the joints as recessed mortar)
		- what changed is that neighbouring blocks now genuinely intersect
		instead of merely being placed near one another.

		The profile itself is a true igloo silhouette: a wall that leans
		very slightly outward at the ground, flowing without a corner into
		a shallow spherical cap. Both zones are described by one continuous
		function, so there is no seam where the wall meets the roof.
	]]
	local wallRadius = domeRadius * 0.94
	local function iglooProfile(y: number): number
		if y <= collarTop then
			-- Gentle outward lean at the foot, easing to the wall radius by
			-- the time it reaches the shoulder - matches how a real igloo
			-- bulges near the ground.
			local t = y / math.max(collarTop, 0.001)
			return domeRadius * (1 - 0.06 * t * t)
		end
		local t = math.clamp((y - collarTop) / math.max(capHeight, 0.001), 0, 1)
		return wallRadius * math.sqrt(math.max(0, 1 - t * t))
	end

	buildContinuousShell({
		model = model,
		basePos = basePos,
		rng = rng,
		profile = iglooProfile,
		topY = peakY,
		stepY = 2.4,
		pieceTarget = 5.5,
		thickness = 2.8,
		layers = 2,
		radialJitter = 0.35,
		tiltJitter = 0.045,
		namePrefix = "IceBlock",
		material = WALL_MATERIAL,
		color = ROOFCAP_COLOR,
		doorWidth = doorWidth,
		notchTopY = doorHeight + 2.5,
	})

	-- Closing keystone block at the crown, so the dome finishes as a
	-- capped mound rather than converging on an open pinhole.
	PartUtils.CreatePart({
		name = "DomeKeystone",
		size = Vector3.new(5.5, 3.4, 5.5),
		position = basePos + Vector3.new(0, peakY - 1, 0),
		material = Enum.Material.Snow,
		color = Color3.fromRGB(240, 246, 251),
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})

	-- Layered snow accumulation: continuous bands lying ON the dome's own
	-- surface, following the same profile the shell was built from, so the
	-- snow reads as settled on the igloo rather than as separate rings
	-- hovering around it. Each band is inset a hair inside the shell's
	-- outer face and skipped across the doorway.
	for _, bandFraction in ipairs({ 0.42, 0.66, 0.86 }) do
		local bandY = collarTop + capHeight * bandFraction
		local bandRadius = iglooProfile(bandY)
		if bandRadius < 2 then
			continue
		end
		local circumference = 2 * math.pi * bandRadius
		local count = math.max(10, math.ceil(circumference / 4))
		local arcSpacing = circumference / count
		local dr = iglooProfile(bandY + 1) - iglooProfile(bandY - 1)
		local tiltX = math.atan2(dr, 2)
		for p = 1, count do
			local angle = (2 * math.pi / count) * p
			local pos = basePos
				+ Vector3.new(math.sin(angle) * (bandRadius + 0.5), bandY, math.cos(angle) * (bandRadius + 0.5))
			PartUtils.CreatePart({
				name = "SnowLayer",
				size = Vector3.new(arcSpacing * SHELL_OVERLAP, 1.5, 1.1),
				cframe = CFrame.new(pos) * CFrame.Angles(0, angle, 0) * CFrame.Angles(tiltX, 0, 0),
				material = Enum.Material.Snow,
				color = Color3.fromRGB(242, 247, 252),
				canCollide = false,
				parent = model,
			})
		end
	end

	-- Packed snow apron so the igloo grows out of the ground instead of
	-- sitting on it, replacing the old scatter of detached snowball mounds.
	buildGroundSkirt({
		model = model,
		basePos = basePos,
		rng = rng,
		innerRadius = domeRadius * 0.97,
		outerRadius = domeRadius * EXTERIOR_ENVELOPE.IceAge.skirt,
		startHeight = 3,
		ringCount = 3,
		pieceTarget = 7,
		thickness = 2,
		namePrefix = "SnowApron",
		material = Enum.Material.Snow,
		color = Color3.fromRGB(238, 244, 250),
		doorWidth = doorWidth,
	})

	-- Entrance: a proper rounded ice-tunnel archway (rib segments + arch
	-- lintel) instead of a plain box tunnel, with icicles hanging along
	-- ITS rim only - this is where "icicles on the edges of the igloo"
	-- now lives, replacing the old map-wide floating icicle clusters
	-- (see IceAgeEnvironment.lua's buildSnowflakeWind for what replaced
	-- those).
	-- Length reaches all the way past the dome's own outer radius (plus a
	-- couple studs clear) so the tunnel mouth - and the name plate it
	-- carries - ends up flush with the dome's real outer surface instead
	-- of buried partway inside the notch.
	local tunnelLength = math.max(7, domeRadius - halfZ + 2)
	themedEntranceTunnel(def, model, tunnelLength, WALL_MATERIAL, ROOFCAP_COLOR)

	-- The entrance tunnel is now a continuous vaulted throat rather than
	-- two flat side ribs with a slab across the top: rings of blocks
	-- stepped along its length, each ring a half-arch, so the passage
	-- reads as carved through solid ice all the way in.
	-- Arch rings stop short of the tunnel mouth so the crown never closes
	-- over the name plate mounted on the facade there.
	local throatSpan = math.max(2, tunnelLength - 2.5)
	local throatRings = math.max(3, math.ceil(throatSpan / 2.2))
	for ringIndex = 0, throatRings do
		local z = halfZ + (throatSpan / throatRings) * ringIndex
		buildEntranceArch({
			model = model,
			basePos = basePos,
			doorWidth = doorWidth,
			doorHeight = doorHeight,
			z = z,
			segments = 11,
			blockDepth = 2,
			thickness = (throatSpan / throatRings) * SHELL_OVERLAP,
			material = WALL_MATERIAL,
			color = ROOFCAP_COLOR,
		})
	end

	-- Icicles hanging from the arch's own leading edge, spaced around the
	-- curve itself so each one is attached to the arch above it.
	for i = 1, 7 do
		local t = (i - 1) / 6
		local archAngle = math.pi * (0.12 + t * 0.76)
		local archRadius = doorWidth / 2 + 1.6
		local springLine = doorHeight - archRadius + 1.2
		PartUtils.CreatePart({
			className = "WedgePart",
			name = "RimIcicle" .. i,
			size = Vector3.new(0.5, rng:NextNumber(1.4, 2.6), 0.5),
			cframe = CFrame.new(
				basePos
					+ Vector3.new(
						math.cos(archAngle) * archRadius,
						springLine + math.sin(archAngle) * archRadius - 0.6,
						halfZ + throatSpan + 0.4
					)
			) * CFrame.Angles(math.pi, 0, 0),
			material = Enum.Material.Ice,
			color = Color3.fromRGB(210, 232, 245),
			canCollide = false,
			parent = model,
		})
	end
end

local function addLavaVolcanoRoof(def, model: Model)
	local basePos = def.position
	local halfZ = def.size.Y / 2
	local halfDiag, baseRadius, collarTop, peakHeight = computeEnclosingEnvelope(def, EXTERIOR_ENVELOPE.Lava.radius, EXTERIOR_ENVELOPE.Lava.capHeight)
	local craterY = collarTop + (peakHeight - collarTop) * 0.9
	local rng = Random.new(math.floor(basePos.X * 511 + basePos.Z * 907))
	local doorWidth = math.clamp(def.size.X * 0.22, MIN_DOOR_WIDTH, MAX_DOOR_WIDTH)
	local doorHeight = math.min(10, def.height - 4)

	--[[
		CONTINUOUS VOLCANIC ROCK MASS.

		This is where the "separated sphere/cubic-prism appearance" was
		worst. Chunks were scattered at +/-13% of the ring radius and
		+/-1.5 studs vertically while being only ~3 studs thick, across
		just 7 rings spanning the entire building height - so both the
		jitter AND the ring spacing exceeded the chunks' own dimensions in
		every direction at once. The result was a literal pile of loose
		boulders with the plain box showing through between them.

		It is now one continuous rock flank built by buildContinuousShell:
		a wide foot, a concave slope, and a crater rim, all described by a
		single profile function and tiled with slabs that are guaranteed to
		intersect their neighbours and are tilted to lie flat along the
		slope. The rugged, broken-rock READING is kept through per-slab
		tilt variation, mixed Rock/Basalt materials and per-slab colour
		variation - but the mass itself is now unbroken.
	]]
	local craterRadius = math.max(2.5, baseRadius * 0.22)
	local flankRadius = baseRadius * 0.95
	local function volcanoProfile(y: number): number
		if y <= collarTop then
			local t = y / math.max(collarTop, 0.001)
			return baseRadius * (1 - 0.05 * t)
		end
		local t = math.clamp((y - collarTop) / math.max(peakHeight - collarTop, 0.001), 0, 1)
		-- Concave flank (exponent > 1) - a real volcano's slope steepens as
		-- it rises rather than running straight like a party hat.
		return craterRadius + (flankRadius - craterRadius) * (1 - t) ^ 1.3
	end

	local function rockMaterial(r: Random): Enum.Material
		local roll = r:NextNumber()
		if roll < 0.34 then
			return Enum.Material.Rock
		elseif roll < 0.62 then
			return Enum.Material.Basalt
		end
		return WALL_MATERIAL
	end
	local function rockColor(r: Random): Color3
		local shade = r:NextInteger(-7, 9) / 255
		return Color3.new(
			math.clamp(ROOFCAP_COLOR.R + shade, 0, 1),
			math.clamp(ROOFCAP_COLOR.G + shade * 0.8, 0, 1),
			math.clamp(ROOFCAP_COLOR.B + shade * 0.7, 0, 1)
		)
	end

	buildContinuousShell({
		model = model,
		basePos = basePos,
		rng = rng,
		profile = volcanoProfile,
		topY = craterY,
		stepY = 2.6,
		pieceTarget = 6,
		thickness = 3.4,
		layers = 2,
		radialJitter = 0.6,
		tiltJitter = 0.11,
		namePrefix = "VolcanoRock",
		materialPicker = rockMaterial,
		colorPicker = rockColor,
		doorWidth = doorWidth,
		notchTopY = doorHeight + 2.5,
	})

	-- Rock apron fanning out to the plaza floor: this is what makes the
	-- volcanic terrain transition naturally INTO the building instead of
	-- the mound sitting on the ground as a separate object.
	buildGroundSkirt({
		model = model,
		basePos = basePos,
		rng = rng,
		innerRadius = baseRadius * 0.98,
		outerRadius = baseRadius * EXTERIOR_ENVELOPE.Lava.skirt,
		startHeight = 4,
		ringCount = 3,
		pieceTarget = 8,
		thickness = 2.4,
		namePrefix = "VolcanoApron",
		materialPicker = rockMaterial,
		colorPicker = rockColor,
		doorWidth = doorWidth,
	})

	-- Crater rim + molten floor, sized to the profile's own top radius so
	-- the rim sits exactly on the flank rather than floating above it.
	local rimRadius = volcanoProfile(craterY)
	local rimCount = math.max(10, math.ceil((2 * math.pi * rimRadius) / 3.5))
	local rimSpacing = (2 * math.pi * rimRadius) / rimCount
	for c = 1, rimCount do
		local angle = (2 * math.pi / rimCount) * c
		PartUtils.CreatePart({
			name = "CraterRim" .. c,
			size = Vector3.new(rimSpacing * SHELL_OVERLAP, rng:NextNumber(1.8, 3.2), 3),
			cframe = CFrame.new(basePos + Vector3.new(math.sin(angle) * rimRadius, craterY, math.cos(angle) * rimRadius))
				* CFrame.Angles(0, angle, 0)
				* CFrame.Angles(rng:NextNumber(-0.14, 0.14), 0, rng:NextNumber(-0.1, 0.1)),
			material = rockMaterial(rng),
			color = rockColor(rng),
			canCollide = false,
			parent = model,
		})
	end
	PartUtils.CreateDisc({
		name = "VolcanoCrater",
		diameter = math.max(3, rimRadius * 1.7),
		thickness = 1.2,
		position = basePos + Vector3.new(0, craterY - 0.4, 0),
		material = Enum.Material.CrackedLava,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	--[[
		Lava channels laid FLUSH ON the flank, following the same profile
		the rock was built from. Previously these were vertical boxes
		planted at an arbitrary radius, so they hovered off the slope
		(more detached geometry). Each channel is now a chain of short
		segments walking down the real surface, each segment tilted to the
		local slope and overlapping the next.
	]]
	local channelCount = rng:NextInteger(3, 5)
	for i = 1, channelCount do
		local channelAngle = rng:NextNumber(0, 2 * math.pi)
		local startT = rng:NextNumber(0.05, 0.2)
		local endT = rng:NextNumber(0.7, 1.0)
		local segments = 7
		local channelWidth = rng:NextNumber(1.6, 3.2)
		for s = 0, segments do
			local t = startT + (endT - startT) * (s / segments)
			local y = craterY - (craterY - collarTop * 0.2) * t
			local r = volcanoProfile(y) + 0.5
			local dr = volcanoProfile(y + 1.2) - volcanoProfile(y - 1.2)
			local segStep = ((craterY - collarTop * 0.2) * (endT - startT)) / segments
			local slant = math.sqrt(dr * dr + segStep * segStep)
			PartUtils.CreatePart({
				name = ("LavaChannel%dS%d"):format(i, s),
				size = Vector3.new(channelWidth, math.max(slant * SHELL_OVERLAP, 1.5), 0.6),
				cframe = CFrame.new(
					basePos + Vector3.new(math.sin(channelAngle) * r, y, math.cos(channelAngle) * r)
				) * CFrame.Angles(0, channelAngle, 0) * CFrame.Angles(math.atan2(dr, segStep), 0, 0),
				material = Enum.Material.CrackedLava,
				color = ACCENT_COLOR,
				canCollide = false,
				parent = model,
			})
		end
	end

	-- Glowing vents sitting ON the flank surface (radius taken from the
	-- profile, not a random fraction of it, so none of them float).
	for i = 1, rng:NextInteger(3, 5) do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local ventHeight = rng:NextNumber(collarTop * 0.3, craterY * 0.8)
		local ventRadius = volcanoProfile(ventHeight) + 0.4
		PartUtils.CreatePart({
			name = "HeatVent" .. i,
			size = Vector3.new(rng:NextNumber(1.4, 2.6), 0.5, rng:NextNumber(1.4, 2.6)),
			position = basePos
				+ Vector3.new(math.sin(angle) * ventRadius, ventHeight, math.cos(angle) * ventRadius),
			material = Enum.Material.CrackedLava,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
	end

	-- Cave-mouth entrance: rough overlapping boulder chunks framing an
	-- archway (not a plain rectangular tunnel), plus the functional
	-- tunnel bridge to the real doorway. Length reaches past the mound's
	-- own outer radius so the tunnel mouth (and its name plate) sits
	-- flush with the mound's real outer surface, not buried inside it.
	local lavaTunnelLength = math.max(6, baseRadius - halfZ + 2)
	themedEntranceTunnel(def, model, lavaTunnelLength, WALL_MATERIAL, ROOFCAP_COLOR)

	-- Cave throat: rings of arch blocks stepped along the tunnel, so the
	-- mouth reads as bored through solid rock. Replaces the two loose
	-- boulders and floating lintel that used to frame a rectangular hole.
	-- Arch rings stop short of the mouth so the crown never closes over the
	-- name plate mounted on the facade there.
	local caveSpan = math.max(2, lavaTunnelLength - 2.5)
	local caveRings = math.max(3, math.ceil(caveSpan / 2.2))
	for ringIndex = 0, caveRings do
		local z = halfZ + (caveSpan / caveRings) * ringIndex
		buildEntranceArch({
			model = model,
			basePos = basePos,
			doorWidth = doorWidth,
			doorHeight = doorHeight,
			z = z,
			segments = 11,
			blockDepth = 2.6,
			thickness = (caveSpan / caveRings) * SHELL_OVERLAP,
			material = rockMaterial(rng),
			color = rockColor(rng),
		})
	end
end

local function addUnderTheSeaHull(def, model: Model)
	local basePos = def.position
	local halfZ = def.size.Y / 2

	-- Full-body hull: paneled rings of curved plates (not one smooth
	-- ellipsoid blob) so it reads as a genuinely built submarine/sunken-
	-- hull, hand-riveted section by section.
	--
	-- Two zones (see computeEnclosingEnvelope above): a COLLAR of
	-- constant-radius hull-plate rings from the ground up to the
	-- building's own roofline (so the box shell can never poke through
	-- the hull), then a shallow rounded CAP - the classic curved
	-- submarine deck/sail base - only above that.
	local halfDiag, hullRadius, collarTop, peakY = computeEnclosingEnvelope(def, EXTERIOR_ENVELOPE.UnderTheSea.radius, EXTERIOR_ENVELOPE.UnderTheSea.capHeight)
	local capHeight = peakY - collarTop
	local rng = Random.new(math.floor(basePos.X * 349 + basePos.Z * 617))
	local doorWidth = math.clamp(def.size.X * 0.22, MIN_DOOR_WIDTH, MAX_DOOR_WIDTH)
	local doorHeight = math.min(10, def.height - 4)

	--[[
		ONE-PIECE RIVETED HULL.

		The hull had the same two defects as the dome and the volcano: 6
		studs of plate spacing against 6-stud plates (times 0.85 in places),
		on rings stepped further apart than the plates were tall, over a
		1.4-stud-thin shell. It now builds as a single continuous hull of
		revolution - wall and curved deck described by one profile function
		so there is no seam at the shoulder - tiled with overlapping plates
		that follow the local slope.

		The panelled submarine reading is kept and in fact strengthened:
		plates are still individually visible, and the staggered inner
		layer shows through the joints as recessed hull seams, which is
		exactly what riveted plating looks like.
	]]
	local deckRadius = hullRadius * 0.96
	local function hullProfile(y: number): number
		if y <= collarTop then
			local t = y / math.max(collarTop, 0.001)
			return hullRadius * (1 - 0.04 * t * t)
		end
		local t = math.clamp((y - collarTop) / math.max(capHeight, 0.001), 0, 1)
		return deckRadius * math.sqrt(math.max(0, 1 - t * t))
	end

	buildContinuousShell({
		model = model,
		basePos = basePos,
		rng = rng,
		profile = hullProfile,
		topY = peakY,
		stepY = 2.6,
		pieceTarget = 6,
		thickness = 2.6,
		layers = 2,
		radialJitter = 0.2,
		tiltJitter = 0.02,
		namePrefix = "HullPlate",
		material = WALL_MATERIAL,
		color = ROOFCAP_COLOR,
		doorWidth = doorWidth,
		notchTopY = doorHeight + 2.5,
	})

	--[[
		FILLED DECK CROWN.

		buildContinuousShell stops laying rings once the profile narrows
		past ~0.8 studs, and a hemispherical profile spends its last several
		studs of height sweeping from a few studs of radius down to nothing.
		That left the very top of the hull as an open ring with a single
		small ball perched over it - the unfinished, odd-looking crown.

		This fills that zone properly: a short stack of discs following the
		same hullProfile, each thick enough to overlap the next, so the deck
		closes into a solid capped surface continuous with the plating below.
	]]
	local crownStart = collarTop + capHeight * 0.55
	local crownSteps = 7
	for i = 0, crownSteps do
		local y = crownStart + (peakY - crownStart) * (i / crownSteps)
		local r = math.max(hullProfile(y), 1.1)
		PartUtils.CreateDisc({
			name = "HullDeckCrown" .. i,
			-- Slightly proud of the plating radius so the crown reads as one
			-- surface with it rather than a separate inner cone.
			diameter = (r + 0.9) * 2,
			thickness = ((peakY - crownStart) / crownSteps) * 1.9,
			position = basePos + Vector3.new(0, y, 0),
			material = WALL_MATERIAL,
			color = ROOFCAP_COLOR,
			canCollide = false,
			parent = model,
		})
	end

	-- Closing deck plate at the crown of the hull.
	PartUtils.CreatePart({
		name = "HullCapTip",
		size = Vector3.new(5, 2.6, 5),
		position = basePos + Vector3.new(0, peakY - 0.8, 0),
		material = WALL_MATERIAL,
		color = ROOFCAP_COLOR,
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})

	-- Structural seam bands lying ON the hull surface, following the same
	-- profile, so they wrap the hull instead of hovering as flat discs
	-- around it. Broken across the doorway so no band crosses the opening.
	for _, seamY in ipairs({ collarTop * 0.45, collarTop * 0.85, collarTop + capHeight * 0.45 }) do
		local seamRadius = hullProfile(seamY)
		if seamRadius < 2 then
			continue
		end
		local circumference = 2 * math.pi * seamRadius
		local count = math.max(12, math.ceil(circumference / 4))
		local arcSpacing = circumference / count
		local dr = hullProfile(seamY + 1) - hullProfile(seamY - 1)
		local tiltX = math.atan2(dr, 2)
		for p = 1, count do
			local angle = (2 * math.pi / count) * p
			if seamY <= doorHeight + 2.5 and isInEntranceNotch(angle, seamRadius, doorWidth) then
				continue
			end
			PartUtils.CreatePart({
				name = "HullSeam",
				size = Vector3.new(arcSpacing * SHELL_OVERLAP, 0.7, 0.9),
				cframe = CFrame.new(
					basePos + Vector3.new(math.sin(angle) * (seamRadius + 0.6), seamY, math.cos(angle) * (seamRadius + 0.6))
				) * CFrame.Angles(0, angle, 0) * CFrame.Angles(tiltX, 0, 0),
				material = ACCENT_MATERIAL,
				color = ACCENT_COLOR,
				canCollide = false,
				parent = model,
			})
		end
	end

	-- Coral and sediment growing up the hull's foot, tying the structure
	-- into the seabed rather than leaving it perched on it.
	buildGroundSkirt({
		model = model,
		basePos = basePos,
		rng = rng,
		innerRadius = hullRadius * 0.98,
		outerRadius = hullRadius * EXTERIOR_ENVELOPE.UnderTheSea.skirt,
		startHeight = 3,
		ringCount = 3,
		pieceTarget = 8,
		thickness = 2,
		namePrefix = "HullSediment",
		material = Enum.Material.Sand,
		colorPicker = function(r: Random): Color3
			local shade = r:NextInteger(-8, 8) / 255
			return Color3.new(
				math.clamp(0.82 + shade, 0, 1),
				math.clamp(0.78 + shade, 0, 1),
				math.clamp(0.62 + shade, 0, 1)
			)
		end,
		doorWidth = doorWidth,
	})

	--[[
		Conning tower + periscope, seated ON the curved deck. This used to
		be pinned to `def.height` (the inner box's roofline) while the hull
		cap rises well above that, so the tower was partly swallowed by the
		deck at some building sizes and left floating over it at others.
		Its base height is now solved from the hull profile at the tower's
		own offset, and the tower is sunk a couple of studs into the deck so
		the two genuinely intersect.
	]]
	local towerOffsetZ = halfZ * 0.3
	local towerFootprint = 5
	-- Height at which the hull surface has narrowed to the tower's own
	-- outer corner distance - i.e. where a tower of this width can sit
	-- flush on the deck.
	local towerCornerDist = math.sqrt((towerFootprint / 2) ^ 2 + (towerOffsetZ + towerFootprint / 2) ^ 2)
	local deckT = math.sqrt(math.max(0, 1 - (math.min(towerCornerDist, deckRadius) / deckRadius) ^ 2))
	local deckY = collarTop + capHeight * deckT
	local towerHeight = 5
	PartUtils.CreatePart({
		name = "ConningTower",
		size = Vector3.new(towerFootprint, towerHeight, towerFootprint),
		position = basePos + Vector3.new(0, deckY + towerHeight / 2 - 2, towerOffsetZ),
		material = WALL_MATERIAL,
		color = ROOFCAP_COLOR,
		canCollide = false,
		parent = model,
	})
	-- Sunk into the conning tower's top rather than balanced above it: the
	-- tower's real top face is at deckY + towerHeight - 2, so a periscope
	-- centred at +0.5 above deckY + towerHeight left a half-stud of air
	-- under it.
	PartUtils.CreatePart({
		name = "Periscope",
		size = Vector3.new(0.8, 5, 0.8),
		position = basePos + Vector3.new(0, deckY + towerHeight - 0.5, towerOffsetZ),
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		canCollide = false,
		parent = model,
	})

	--[[
		Portholes set INTO the hull's real surface. These used to be pinned
		at a flat `hullRadius * 0.92` on the X axis regardless of their Z
		offset, which on a round hull left them hanging off the side in
		open water. The horizontal offset is now solved from the hull's own
		profile at that height, so each porthole lands exactly on the
		curved plating and is rotated to face along its true surface
		normal.
	]]
	local portholeY = def.height * 0.55
	local portholeSurfaceRadius = hullProfile(portholeY)
	for _, side in ipairs({ -1, 1 }) do
		for _, offsetZ in ipairs({ -halfZ * 0.4, halfZ * 0.4 }) do
			local offsetX = math.sqrt(math.max(portholeSurfaceRadius ^ 2 - offsetZ ^ 2, 1))
			local surfaceAngle = math.atan2(side * offsetX, offsetZ)
			local center = basePos + Vector3.new(side * offsetX, portholeY, offsetZ)
			-- CreateDisc builds a disc lying flat (caps up/down); rotating by
			-- 90 degrees about X stands it upright, then the yaw aims it
			-- outward along the hull normal.
			local function faceOutward(part: BasePart)
				part.CFrame = CFrame.new(center)
					* CFrame.Angles(0, surfaceAngle, 0)
					* CFrame.Angles(math.rad(90), 0, 0)
					* CFrame.Angles(0, 0, math.rad(90))
			end
			local frame = PartUtils.CreateDisc({
				name = "PortholeFrame",
				diameter = 3.2,
				thickness = 1.2,
				position = center,
				material = ACCENT_MATERIAL,
				color = ACCENT_COLOR,
				canCollide = false,
				parent = model,
			})
			faceOutward(frame)
			local porthole = PartUtils.CreateDisc({
				name = "Porthole",
				diameter = 2.4,
				thickness = 1.4,
				position = center,
				material = GLASS_MATERIAL,
				color = GLASS_COLOR,
				canCollide = false,
				parent = model,
			})
			faceOutward(porthole)
		end
	end

	-- Airlock hatch entrance tunnel - bridges the real doorway out past
	-- the hull's own curvature. Length reaches past the hull's own outer
	-- radius so the tunnel mouth (and its name plate) sits flush with the
	-- hull's real outer surface, not buried inside it.
	local hullTunnelLength = math.max(6, hullRadius - halfZ + 2)
	themedEntranceTunnel(def, model, hullTunnelLength, WALL_MATERIAL, ROOFCAP_COLOR)

	-- Airlock throat: rings of arch plating stepped along the tunnel so the
	-- opening is a moulded hatchway through the hull rather than a
	-- rectangular gap with a loose rim bar over it.
	-- Arch rings stop short of the mouth so the crown never closes over the
	-- name plate mounted on the facade there.
	local airlockSpan = math.max(2, hullTunnelLength - 2.5)
	local airlockRings = math.max(3, math.ceil(airlockSpan / 2.2))
	for ringIndex = 0, airlockRings do
		local z = halfZ + (airlockSpan / airlockRings) * ringIndex
		buildEntranceArch({
			model = model,
			basePos = basePos,
			doorWidth = doorWidth,
			doorHeight = doorHeight,
			z = z,
			segments = 11,
			blockDepth = 1.8,
			thickness = (airlockSpan / airlockRings) * SHELL_OVERLAP,
			material = WALL_MATERIAL,
			color = ROOFCAP_COLOR,
		})
	end

	-- Accent hatch ring around the outermost arch, following its curve.
	local hatchRadius = doorWidth / 2 + 1.6
	local hatchSpring = doorHeight - hatchRadius + 1.2
	for s = 0, 11 do
		local a = math.pi * (s / 11)
		local segLength = (math.pi * hatchRadius / 11) * SHELL_OVERLAP
		PartUtils.CreatePart({
			name = "HatchRim",
			size = Vector3.new(0.5, segLength, 0.5),
			cframe = CFrame.new(
				basePos
					+ Vector3.new(
						math.cos(a) * hatchRadius,
						hatchSpring + math.sin(a) * hatchRadius,
						halfZ + airlockSpan + 0.6
					)
			) * CFrame.Angles(0, 0, a - math.pi / 2),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
	end
end

local ROOF_SILHOUETTE_BUILDERS = {
	IceAge = addIceAgeDome,
	Lava = addLavaVolcanoRoof,
	UnderTheSea = addUnderTheSeaHull,
}

local function addThemedRoofSilhouette(def, model: Model)
	local builder = ROOF_SILHOUETTE_BUILDERS[CURRENT_THEME_ID]
	if builder then
		builder(def, model)
	end
end

--[[
	Builds the hollow shell for one building: floor, ceiling, left/right/back
	solid walls, and a plaza-facing (Back/+Z) wall split around a doorway
	gap. Returns the "Base" header part (same role addSign/
	addLeaderboardDisplay already expect - a part whose Back face they can
	put a SurfaceGui on) so Buildings.lua's existing calls don't change.
]]
function BuildingInteriors.BuildShell(def, model: Model): BasePart
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2
	-- Message 20: doorway scales with the building's own width (was a flat
	-- 8 studs regardless of size) - an 8-stud door reads as tiny against a
	-- 61-stud-wide exterior now that buildings are much bigger.
	local DOOR_WIDTH = math.clamp(def.size.X * 0.22, MIN_DOOR_WIDTH, MAX_DOOR_WIDTH)
	local doorHeight = math.min(10, def.height - 4)
	local headerHeight = def.height - doorHeight
	local doorHalfWidth = DOOR_WIDTH / 2
	local basePos = def.position

	-- "do not leave the old prism shells underneath the new designs if
	-- they remain visually identifiable" - for the three custom-exterior
	-- themes (see CUSTOM_EXTERIOR_THEMES above), every purely decorative
	-- BOX surface below (window strips, entrance canopy, doorway trim,
	-- layered roof cap) is skipped entirely: the full-body dome/volcano/
	-- hull built by addThemedRoofSilhouette already encloses the building
	-- completely and supplies its own entrance/trim, so keeping the box's
	-- own exterior dressing would just poke back out through it. The
	-- structural walls/floor/ceiling/doorway gap themselves are NOT
	-- skipped - they're what actually holds the interior/collision/
	-- furniture layout, just with nothing decorative exposed outside them.
	local isCustomExterior = CUSTOM_EXTERIOR_THEMES[CURRENT_THEME_ID] == true

	--[[
		Floor and ceiling are built thicker than one lighting voxel and grown
		AWAY from the room (floor downward, ceiling upward), so the walkable
		surface stays at y=0.5 and the ceiling soffit stays at
		def.height-0.5 exactly as before - only the hidden outer faces move.
		At 0.5 studs thick these were the single worst light leak in the
		project: an interior light 0.25 studs under the ceiling lit the sky
		straight through it.
	]]
	local floorTopY = 0.5
	PartUtils.CreatePart({
		name = "Floor",
		size = Vector3.new(def.size.X, SOLID_SLAB_THICKNESS, def.size.Y),
		position = basePos + Vector3.new(0, floorTopY - SOLID_SLAB_THICKNESS / 2, 0),
		material = Enum.Material.SmoothPlastic,
		color = INTERIOR_FLOOR_COLOR,
		parent = model,
	})

	local ceilingUnderside = def.height - 0.5
	PartUtils.CreatePart({
		name = "Ceiling",
		size = Vector3.new(def.size.X, SOLID_SLAB_THICKNESS, def.size.Y),
		position = basePos + Vector3.new(0, ceilingUnderside + SOLID_SLAB_THICKNESS / 2, 0),
		material = WALL_MATERIAL,
		color = CEILING_COLOR,
		parent = model,
	})

	-- Walls likewise keep their inner face at exactly (edge - WALL_THICKNESS)
	-- and thicken outward only.
	PartUtils.CreatePart({
		name = "BackWall",
		size = Vector3.new(def.size.X, def.height, SOLID_WALL_THICKNESS),
		position = basePos
			+ Vector3.new(0, def.height / 2, -halfZ + WALL_THICKNESS - SOLID_WALL_THICKNESS / 2),
		material = WALL_MATERIAL,
		color = EXTERIOR_WALL_COLOR,
		parent = model,
	})

	-- Left/Right walls, each with two window strips (glass + neon frame)
	-- instead of a single flat surface - the "layered walls / large
	-- windows" the visual overhaul calls for.
	for _, side in ipairs({ -1, 1 }) do
		-- Inner face stays at side*(halfX - WALL_THICKNESS); the wall grows
		-- outward from there so shelving and fixtures keep their positions.
		local wallX = side * (halfX - WALL_THICKNESS + SOLID_WALL_THICKNESS / 2)
		PartUtils.CreatePart({
			name = if side == -1 then "LeftWall" else "RightWall",
			size = Vector3.new(SOLID_WALL_THICKNESS, def.height, def.size.Y),
			position = basePos + Vector3.new(wallX, def.height / 2, 0),
			material = WALL_MATERIAL,
			color = EXTERIOR_WALL_COLOR,
			parent = model,
		})

		-- Window strips are exterior box dressing - skipped for custom-
		-- exterior themes (see isCustomExterior above), since the dome/
		-- volcano/hull fully encloses these walls anyway.
		if not isCustomExterior then
			local windowHeight = math.min(5, def.height - 6)
			local windowWidth = math.min(6, def.size.Y * 0.22)
			-- Message 20: a third window pair for the now much-deeper side
			-- walls - two windows looked sparse spread across 30+ studs of depth.
			local windowOffsets = if def.size.Y > 24
				then { -def.size.Y / 3, 0, def.size.Y / 3 }
				else { -def.size.Y / 4, def.size.Y / 4 }
			for _, offsetZ in ipairs(windowOffsets) do
				PartUtils.CreatePart({
					name = "WindowFrame",
					size = Vector3.new(0.3, windowHeight + 0.6, windowWidth + 0.6),
					position = basePos + Vector3.new(side * (halfX - 0.15), def.height * 0.55, offsetZ),
					material = ACCENT_MATERIAL,
					color = ACCENT_COLOR,
					canCollide = false,
					parent = model,
				})
				PartUtils.CreatePart({
					name = "Window",
					size = Vector3.new(0.15, windowHeight, windowWidth),
					position = basePos + Vector3.new(side * (halfX - 0.15), def.height * 0.55, offsetZ),
					material = GLASS_MATERIAL,
					color = GLASS_COLOR,
					transparency = GLASS_TRANSPARENCY,
					canCollide = false,
					parent = model,
				})
			end
		end
	end

	-- Plaza-facing wall, split around the doorway gap.
	local sideSegWidth = halfX - doorHalfWidth
	if sideSegWidth > 0.5 then
		-- Front wall segments also keep their inner face at halfZ -
		-- WALL_THICKNESS and thicken outward, so the doorway reveal is
		-- unchanged from inside while the wall becomes a real occluder.
		local frontWallZ = halfZ - WALL_THICKNESS + SOLID_WALL_THICKNESS / 2
		PartUtils.CreatePart({
		name = "FrontWallLeft",
		size = Vector3.new(sideSegWidth, doorHeight, SOLID_WALL_THICKNESS),
		position = basePos + Vector3.new(-halfX + sideSegWidth / 2, doorHeight / 2, frontWallZ),
		material = WALL_MATERIAL,
		color = EXTERIOR_WALL_COLOR,
		parent = model,
		})
		PartUtils.CreatePart({
		name = "FrontWallRight",
		size = Vector3.new(sideSegWidth, doorHeight, SOLID_WALL_THICKNESS),
		position = basePos + Vector3.new(halfX - sideSegWidth / 2, doorHeight / 2, frontWallZ),
		material = WALL_MATERIAL,
		color = EXTERIOR_WALL_COLOR,
		parent = model,
		})
		end

	-- "Base": the header above the doorway - full building width, carries
	-- the exterior sign/display exactly as Buildings.lua already expects.
	-- Its Back (+Z) face must stay exactly at halfZ so the SurfaceGui
	-- Buildings.lua mounts on it keeps facing the plaza from the same
	-- plane; it therefore thickens INWARD rather than outward.
	local base = PartUtils.CreatePart({
		name = "Base",
		size = Vector3.new(def.size.X, headerHeight, SOLID_WALL_THICKNESS),
		position = basePos
			+ Vector3.new(0, doorHeight + headerHeight / 2, halfZ - SOLID_WALL_THICKNESS / 2),
		material = WALL_MATERIAL,
		color = HEADER_COLOR,
		parent = model,
	})

	-- Entrance canopy / doorway trim / layered roof cap are all purely
	-- decorative BOX exterior dressing - skipped entirely for custom-
	-- exterior themes (see isCustomExterior above). Those three themes
	-- get their own entrance framing from themedEntranceTunnel (called by
	-- addThemedRoofSilhouette below - ice-tunnel arch / cave mouth rocks /
	-- airlock hatch rim) and their own roofline from the dome/volcano/
	-- hull body itself, so building these would just be extra geometry
	-- sitting invisibly inside (or worse, poking through) that body.
	if not isCustomExterior then
		-- Entrance canopy: an angled overhang projecting out from above the
		-- doorway, the single biggest "this looks designed, not extruded"
		-- upgrade an entrance can get cheaply.
		PartUtils.CreatePart({
			className = "WedgePart",
			name = "EntranceCanopy",
			size = Vector3.new(DOOR_WIDTH + 4, 2.5, 5),
			cframe = CFrame.new(basePos + Vector3.new(0, doorHeight + 0.5, halfZ + 2))
				* CFrame.Angles(0, math.rad(180), 0),
			material = WALL_MATERIAL,
			color = CANOPY_COLOR,
			canCollide = false,
			parent = model,
		})
		PartUtils.CreatePart({
			name = "CanopyTrim",
			size = Vector3.new(DOOR_WIDTH + 4.2, 0.25, 0.25),
			position = basePos + Vector3.new(0, doorHeight - 0.6, halfZ + 4.4),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})

		-- Doorway accent trim (neon strip framing the entrance).
		PartUtils.CreatePart({
			name = "DoorwayTrim",
			size = Vector3.new(DOOR_WIDTH + 1, 0.4, WALL_THICKNESS + 0.2),
			position = basePos + Vector3.new(0, doorHeight, halfZ - WALL_THICKNESS / 2),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})

		--[[
			FACADE NAME PLATE for the BOX themes (Futuristic / Space).

			The three custom-exterior themes already get a large mounted name
			plate at their tunnel mouth (see themedEntranceTunnel's
			EntranceNamePlate). The box themes had NO plate at all - their name
			was painted straight onto the "Base" header via Buildings.lua's
			addSign, stretched across the header's full width. Because
			TextScaled is width-bound for a long single-line name (see
			FormatSignText), "Statistics Building" rendered ~3.1-stud glyphs
			inside a 9-stud header - the "very thin" name this pass fixes.

			This is a real plate standing proud of the facade, so it also reads
			as mounted signage rather than paint, matching the themed maps.

			GEOMETRY: the bottom is held at doorHeight + 3 so the plate always
			clears the EntranceCanopy above the door (whose top reaches about
			doorHeight + 1.75). The height then runs up to 6 studs past the
			roofline, capped at 12. On all four buildings that resolves to the
			SAME 12-stud plate topping out at the SAME Y - so the whole
			building row's signage lines up, which reads as deliberate rather
			than each building having a differently-sized sign. It sits at
			halfZ + 1.1, outside the wall but well inside the canopy's own
			reach, so it never floats detached.
		]]
		local plateBottomY = doorHeight + 3
		local platePassHeight = math.clamp(def.height + 6 - plateBottomY, 7, 12)
		local platePassWidth = math.clamp(def.size.X * 0.9, DOOR_WIDTH + 10, DOOR_WIDTH + 26)
		local platePassY = plateBottomY + platePassHeight / 2
		local platePassZ = halfZ + 1.1
		local facadePlate = PartUtils.CreatePart({
			name = "EntranceNamePlate",
			size = Vector3.new(platePassWidth, platePassHeight, 2.2),
			position = basePos + Vector3.new(0, platePassY, platePassZ),
			material = WALL_MATERIAL,
			color = HEADER_COLOR,
			canCollide = false,
			parent = model,
		})

		local facadeGui = Instance.new("SurfaceGui")
		facadeGui.Face = Enum.NormalId.Back -- Back = +Z, facing the plaza (see addSign)
		facadeGui.LightInfluence = 0
		facadeGui.PixelsPerStud = 48
		facadeGui.Parent = facadePlate

		local facadeLabel = Instance.new("TextLabel")
		facadeLabel.Size = UDim2.fromScale(1, 1)
		facadeLabel.BackgroundTransparency = 1
		facadeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		facadeLabel.TextStrokeTransparency = 0.3
		facadeLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		facadeLabel.Font = Enum.Font.GothamBlack
		facadeLabel.TextScaled = true
		facadeLabel.Text = BuildingInteriors.FormatSignText(def.displayName or def.name or "")
		facadeLabel.Parent = facadeGui

		-- Flanking accent lamps, seated ON the plate's own ends so they
		-- intersect the signage they light - same treatment the themed maps'
		-- plate already uses, so signage reads identically across all maps.
		for _, side in ipairs({ -1, 1 }) do
			local facadeLamp = PartUtils.CreatePart({
				name = "EntranceLamp",
				size = Vector3.new(1.4, 1.4, 1.4),
				position = basePos + Vector3.new(side * (platePassWidth / 2 - 0.2), platePassY, platePassZ),
				material = Enum.Material.Neon,
				color = ACCENT_COLOR,
				shape = Enum.PartType.Ball,
				canCollide = false,
				parent = model,
			})
			local facadeLight = Instance.new("PointLight")
			facadeLight.Color = ACCENT_COLOR
			facadeLight.Range = LightingConfig.ACCENT_LIGHT_RANGE * 0.5
			facadeLight.Brightness = LightingConfig.ACCENT_LIGHT_BRIGHTNESS
			facadeLight.Parent = facadeLamp
		end

		-- Layered roof cap: a smaller, inset volume sitting on the ceiling
		-- with a glowing edge, so the silhouette reads as two stacked masses
		-- rather than one flat-topped box.
		local capInset = 3
		PartUtils.CreatePart({
			name = "RoofCap",
			size = Vector3.new(def.size.X - capInset * 2, 1.5, def.size.Y - capInset * 2),
			position = basePos + Vector3.new(0, def.height + 0.75, 0),
			material = WALL_MATERIAL,
			color = ROOFCAP_COLOR,
			parent = model,
		})
		PartUtils.CreatePart({
			name = "RoofCapTrim",
			size = Vector3.new(def.size.X - capInset * 2 + 0.3, 0.3, def.size.Y - capInset * 2 + 0.3),
			position = basePos + Vector3.new(0, def.height + 1.5, 0),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
	end

	--[[
		A couple of ceiling-mounted interior lights (kept minimal per the
		performance guidance - no more than needed to keep the room
		readable). Raised flush INTO the ceiling slab: at def.height - 0.7
		with a 0.2-stud panel these hung a few tenths of a stud below the
		ceiling with clear air behind them, reading as floating strips. They
		now intersect the ceiling they are supposed to be mounted on.
	]]
	for _, offsetZ in ipairs({ -halfZ / 2, halfZ / 2 }) do
		local light = PartUtils.CreatePart({
			name = "CeilingLight",
			size = Vector3.new(4, 0.6, 1.5),
			position = basePos + Vector3.new(0, def.height - 0.1, offsetZ),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
		local pointLight = Instance.new("PointLight")
		pointLight.Color = ACCENT_COLOR
		pointLight.Brightness = LightingConfig.ACCENT_LIGHT_BRIGHTNESS
		-- Sealed: shadows on, and range clamped so the falloff dies inside
		-- the room instead of washing out through the roof (see
		-- sealInteriorLight). This pair of ceiling lamps was the main source
		-- of light visibly peeking out of the buildings.
		sealInteriorLight(pointLight, math.min(LightingConfig.ACCENT_LIGHT_RANGE, def.height + 4))
		pointLight.Parent = light
	end

	-- Floor tile seam pattern (Message 18, section 4 "flooring patterns") -
	-- a handful of thin recessed-look strips running the depth of the room,
	-- shared by every building automatically since it lives in the shell
	-- rather than each Furnish* function repeating it.
	local tileSpacing = def.size.X / 4
	for i = 1, 3 do
		PartUtils.CreatePart({
			name = "FloorSeam" .. i,
			size = Vector3.new(0.15, 0.02, def.size.Y - 2),
			position = basePos + Vector3.new(-halfX + tileSpacing * i, 0.51, 0),
			material = WALL_MATERIAL,
			color = Color3.fromRGB(20, 22, 27),
			canCollide = false,
			parent = model,
		})
	end

	-- Ceiling structural support beams (Message 18, section 4 "ceiling
	-- details / structural supports") - simple recessed-look beams, again
	-- shared automatically by every building via the shell.
	for _, offsetZ in ipairs({ -halfZ * 0.6, 0, halfZ * 0.6 }) do
		PartUtils.CreatePart({
			name = "CeilingBeam",
			size = Vector3.new(def.size.X - 1, 0.4, 0.6),
			position = basePos + Vector3.new(0, def.height - 0.7, offsetZ),
			material = WALL_MATERIAL,
			color = Color3.fromRGB(38, 41, 48),
			canCollide = false,
			parent = model,
		})
	end

	-- Per-map themed interior flourish (holographic panel/lava vent/
	-- cosmic orrery/coral cluster/ice crystal - see FLOURISH_BUILDERS
	-- above) - added here in the shared shell so every building on every
	-- map gets one automatically, rather than needing a call added to each
	-- of the four separate Furnish* functions below.
	addThemedFlourish(def, model)

	-- Per-map themed EXTERIOR silhouette (igloo dome/volcano cone with
	-- lava falls/ship hull with portholes - see ROOF_SILHOUETTE_BUILDERS
	-- above), added on top of the shared flat RoofCap for real
	-- architectural differentiation between maps, not just a recolor.
	addThemedRoofSilhouette(def, model)

	return base
end

--[[
	Builds the shared "obvious interactive feature" terminal used by
	every building (Shop/DailyRewards/Statistics/Tutorial) - a raised
	dais, an archway frame, a floating header label naming exactly what
	it does, and a focused overhead spotlight, all pointing at the same
	real ProximityPrompt this always had. This is the ACTUAL functional
	focal point players are meant to notice and interact with -
	triggering it fires the exact same Prompt.Triggered flow the
	corresponding client controller already listens for
	(ShopUIController.client.lua etc.), so nothing about the underlying
	system changes - only how obviously this spot reads as "the thing to
	interact with", replacing what used to just be "a stand and a
	screen" sitting among otherwise-unexplained furniture.
]]
local function terminal(model: Model, position: Vector3, promptName: string, promptText: string, objectText: string)
	-- Raised circular dais at floor level - a real platform reading as
	-- "this spot matters", not just a stand plunked on bare floor.
	PartUtils.CreateDisc({
		name = "TerminalDais",
		diameter = 5,
		thickness = 0.3,
		position = position + Vector3.new(0, 0.05, 0),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	-- Archway frame: two side pillars + a top bar, so the terminal sits
	-- inside an actual architectural frame instead of floating in open
	-- room space.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "TerminalArchPost",
			size = Vector3.new(0.6, 5, 0.6),
			position = position + Vector3.new(side * 2.4, 1, 0),
			material = FURNITURE_MATERIAL,
			color = FURNITURE_COLOR,
			canCollide = false,
			parent = model,
		})
	end
	PartUtils.CreatePart({
		name = "TerminalArchTop",
		size = Vector3.new(5.4, 0.5, 0.6),
		position = position + Vector3.new(0, 3.5, 0),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	-- Header naming exactly what this terminal does - "an obvious
	-- attention-grabbing feature", not a mystery box. Seated ON the arch
	-- top rather than hovering 0.15 studs above and 0.1 studs in front of
	-- it, so the sign is genuinely part of the frame carrying it.
	local header = PartUtils.CreatePart({
		name = "TerminalHeader",
		size = Vector3.new(4.6, 1, 0.3),
		position = position + Vector3.new(0, 4.05, 0.25),
		material = Enum.Material.Neon,
		color = ACCENT_COLOR,
		transparency = 0.15,
		canCollide = false,
		parent = model,
	})
	local headerGui = Instance.new("SurfaceGui")
	headerGui.Face = Enum.NormalId.Front
	headerGui.Parent = header
	local headerLabel = Instance.new("TextLabel")
	headerLabel.Size = UDim2.fromScale(1, 1)
	headerLabel.BackgroundTransparency = 1
	headerLabel.Font = Enum.Font.GothamBlack
	headerLabel.TextScaled = true
	headerLabel.TextColor3 = Color3.fromRGB(10, 10, 12)
	headerLabel.Text = objectText:upper()
	headerLabel.Parent = headerGui

	local stand = PartUtils.CreatePart({
		name = promptName:gsub("Prompt$", "Stand"),
		size = Vector3.new(3, 3.5, 1.5),
		position = position,
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		parent = model,
	})

	PartUtils.CreatePart({
		name = "Screen",
		size = Vector3.new(2.4, 1.6, 0.15),
		position = position + Vector3.new(0, 0.8, 0.85),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	-- Focused overhead spotlight - a genuine attention-grabbing beacon
	-- over the interaction point, on top of (not replacing) the shell's
	-- own general ceiling lights.
	local spotAnchor = PartUtils.CreatePart({
		name = "TerminalSpotAnchor",
		size = Vector3.new(0.3, 0.3, 0.3),
		position = position + Vector3.new(0, 4.3, 0),
		transparency = 1,
		canCollide = false,
		parent = model,
	})
	local spotlight = Instance.new("SpotLight")
	spotlight.Color = ACCENT_COLOR
	spotlight.Range = 16
	spotlight.Brightness = LightingConfig.ACCENT_LIGHT_BRIGHTNESS * 1.6
	spotlight.Angle = 70
	spotlight.Face = Enum.NormalId.Bottom
	spotlight.Shadows = true -- occlude against the room rather than bleeding through it
	spotlight.Parent = spotAnchor

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = promptName
	prompt.ActionText = objectText
	prompt.ObjectText = promptText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = stand

	return stand
end

--[[
	Shop identity: angled glass storefront bays flanking the entrance, plus
	an illuminated marquee sign above the canopy - makes the Shop read as
	"browse from outside" the moment you approach, distinct from every
	other building's flat facade.

	Message 29 ("make each shop 10x better"): added the marquee (a genuine
	lit sign distinct from the plain name plate on Base) and a warm accent
	spotlight over each storefront bay, so the exterior itself reads as
	"an actual store" even before anyone walks in.
]]
local function addShopIdentity(def, model: Model)
	local basePos = def.position
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2

	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			className = "WedgePart",
			name = "StorefrontBay",
			size = Vector3.new(4, 6, 3),
			cframe = CFrame.new(basePos + Vector3.new(side * (halfX - 2), 4, halfZ + 1))
				* CFrame.Angles(0, math.rad(side == -1 and 90 or -90), 0),
			material = GLASS_MATERIAL,
			color = GLASS_COLOR,
			transparency = GLASS_TRANSPARENCY,
			canCollide = false,
			parent = model,
		})
	end

	-- Illuminated marquee above the entrance canopy - a genuine "this is a
	-- store" beacon, distinct from the plain name plate already on Base.
	local marquee = PartUtils.CreatePart({
		name = "ShopMarquee",
		size = Vector3.new(def.size.X * 0.5, 2, 0.3),
		position = basePos + Vector3.new(0, def.height + 3, halfZ + 4.6),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})
	local marqueeGui = Instance.new("SurfaceGui")
	marqueeGui.Face = Enum.NormalId.Front
	marqueeGui.Parent = marquee
	local marqueeLabel = Instance.new("TextLabel")
	marqueeLabel.Size = UDim2.fromScale(1, 1)
	marqueeLabel.BackgroundTransparency = 1
	marqueeLabel.Font = Enum.Font.GothamBlack
	marqueeLabel.TextScaled = true
	marqueeLabel.TextColor3 = Color3.fromRGB(10, 12, 16)
	marqueeLabel.Text = "OPEN"
	marqueeLabel.Parent = marqueeGui
end

--[[
	Shop: a clear front-to-back store layout using the building's full,
	now much larger floor (Message 20 - "the biggest interior treatment"):
		entrance foyer -> two freestanding aisle islands (with wall shelving
		flanking both sides) -> a cosmetic showcase row -> the counter and
		terminal against the back wall.
	Every row/aisle leaves a clear walkway - the center aisle (|x|<4) runs
	straight from the door to the terminal, and the side walkways (between
	the wall shelves and the freestanding islands) stay clear too.
]]
function BuildingInteriors.FurnishShop(def, model: Model)
	local basePos = def.position
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2

	-- Roof-mounted "identity massing" (storefront bays/marquee here; reward
	-- tower/data spire/turret for the other three buildings below) is
	-- exterior BOX dressing exactly like the shell's own canopy/roof cap -
	-- skipped for custom-exterior themes (see CUSTOM_EXTERIOR_THEMES/
	-- BuildShell's isCustomExterior above) so it can't poke through the
	-- dome/volcano/hull that now fully encloses the building instead.
	if not CUSTOM_EXTERIOR_THEMES[CURRENT_THEME_ID] then
		addShopIdentity(def, model)
	end

	-- Two tiers of wall shelving along both side walls, spanning the full
	-- depth of the room now that there's much more of it to use.
	local wallShelfOffsets = { -halfZ + 4, -halfZ / 3, halfZ / 3 - 2, halfZ - 5 }
	for _, side in ipairs({ -1, 1 }) do
		for _, shelfY in ipairs({ 3.2, 5.6 }) do
			for _, offsetZ in ipairs(wallShelfOffsets) do
				PartUtils.CreatePart({
					name = "WallShelf",
					size = Vector3.new(3.2, 0.25, 1.4),
					position = basePos + Vector3.new(side * (halfX - 2.1), shelfY, offsetZ),
					material = FURNITURE_MATERIAL,
					color = FURNITURE_COLOR,
					parent = model,
				})
				-- Resting ON the shelf. At +0.55 above a 0.25-thick shelf an
				-- 0.8-cube's underside sat 0.025 studs clear of the shelf top -
				-- a hairline float, but a float, and it read as merchandise
				-- hovering. Lowered so the item genuinely sits on the board.
				PartUtils.CreatePart({
					name = "ShelfItem",
					size = Vector3.new(0.8, 0.8, 0.8),
					position = basePos + Vector3.new(side * (halfX - 2.1), shelfY + 0.45, offsetZ),
					material = ACCENT_MATERIAL,
					color = ACCENT_COLOR,
					canCollide = false,
					parent = model,
				})
			end
		end
	end

	-- Two freestanding, double-sided aisle islands in the middle third of
	-- the room - the actual "browse between rows" store experience the
	-- wall shelving alone can't provide. Positioned well clear of both the
	-- center walkway (|x|<4) and the side walkways (between the island and
	-- the wall shelves).
	for _, aisleX in ipairs({ -halfX * 0.4, halfX * 0.4 }) do
		PartUtils.CreatePart({
			name = "AisleIsland",
			size = Vector3.new(2.2, 4, halfZ * 0.7),
			position = basePos + Vector3.new(aisleX, 2, halfZ * 0.05),
			material = FURNITURE_MATERIAL,
			color = FURNITURE_COLOR,
			parent = model,
		})
		for _, itemOffsetZ in ipairs({ -halfZ * 0.25, 0, halfZ * 0.25 }) do
			for _, faceX in ipairs({ -1, 1 }) do
				PartUtils.CreatePart({
					name = "AisleItem",
					size = Vector3.new(0.9, 0.9, 0.9),
					position = basePos
						+ Vector3.new(aisleX + faceX * 1.5, 4.2, itemOffsetZ + halfZ * 0.05),
					material = ACCENT_MATERIAL,
					color = ACCENT_COLOR,
					canCollide = false,
					parent = model,
				})
			end
		end
	end

	-- Floor accent stripe leading from the doorway straight down the
	-- center aisle to the counter.
	PartUtils.CreatePart({
		name = "FloorAccent",
		size = Vector3.new(2, 0.05, def.size.Y - 8),
		position = basePos + Vector3.new(0, 0.53, 1),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		transparency = 0.5,
		canCollide = false,
		parent = model,
	})

	-- Cosmetic showcase row, just in front of the counter - the "look but
	-- don't buy yet" zone between the aisles and checkout.
	for _, x in ipairs({ -halfX * 0.35, 0, halfX * 0.35 }) do
		PartUtils.CreatePart({
			name = "DisplayPlinth",
			size = Vector3.new(2, 3, 2),
			position = basePos + Vector3.new(x, 1.5, -halfZ * 0.35),
			material = FURNITURE_MATERIAL,
			color = FURNITURE_COLOR,
			parent = model,
		})
		PartUtils.CreatePart({
			name = "DisplayItem",
			size = Vector3.new(1.2, 1.2, 1.2),
			position = basePos + Vector3.new(x, 3.6, -halfZ * 0.35),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
	end

	-- Counter + register + terminal against the back wall - the store's
	-- clear "end point", now with a proper checkout register (a small
	-- raised monitor + neon accent) and its own overhead spotlight, rather
	-- than a bare counter slab.
	PartUtils.CreatePart({
		name = "Counter",
		size = Vector3.new(math.min(14, def.size.X - 8), 3.5, 2.5),
		position = basePos + Vector3.new(0, 1.75, -halfZ + 4),
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "CounterRegister",
		size = Vector3.new(1.6, 1.2, 1.2),
		position = basePos + Vector3.new(0, 4.1, -halfZ + 3.6),
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "CounterRegisterScreen",
		size = Vector3.new(1, 0.7, 0.1),
		position = basePos + Vector3.new(0, 4.3, -halfZ + 3.05),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	terminal(model, basePos + Vector3.new(0, 0, -halfZ + 7.5), "ShopTerminalPrompt", "Open Shop", "Shop")
end

--[[
	DailyRewards identity: a stepped, trophy-like tower rising off the
	roof - three shrinking tiers with neon seams, reading as "progression/
	achievement" from across the lobby.
]]
local function addRewardsIdentity(def, model: Model)
	local basePos = def.position
	local tiers = { { size = 10, height = 3 }, { size = 7, height = 3 }, { size = 4, height = 4 } }
	local y = def.height + 1.5

	for i, tier in ipairs(tiers) do
		PartUtils.CreatePart({
			name = "RewardTower" .. i,
			size = Vector3.new(tier.size, tier.height, tier.size),
			position = basePos + Vector3.new(0, y + tier.height / 2, 0),
			material = FURNITURE_MATERIAL,
			color = FURNITURE_COLOR,
			parent = model,
		})
		PartUtils.CreatePart({
			name = "RewardTowerTrim" .. i,
			size = Vector3.new(tier.size + 0.3, 0.25, tier.size + 0.3),
			position = basePos + Vector3.new(0, y + tier.height, 0),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
		y += tier.height
	end

	PartUtils.CreatePart({
		name = "RewardBeacon",
		size = Vector3.new(1.2, 1.2, 1.2),
		position = basePos + Vector3.new(0, y + 1, 0),
		material = Enum.Material.Neon,
		color = Color3.fromRGB(255, 215, 0),
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})
end

--[[
	Daily Rewards: the stepped trophy tower outside, and inside - a clear
	"hall of milestones" using the building's larger floor (Message 20):
	entrance -> a center row of milestone pedestals players walk past ->
	the progression wall + Rewards Terminal against the back wall. Side-
	wall milestone screens flank the whole walk.
]]
function BuildingInteriors.FurnishRewards(def, model: Model)
	local basePos = def.position
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2

	if not CUSTOM_EXTERIOR_THEMES[CURRENT_THEME_ID] then
		addRewardsIdentity(def, model)
	end

	-- Side-wall milestone screens - small floating panels suggesting
	-- individual reward tiers, flanking the walk from door to terminal.
	for _, side in ipairs({ -1, 1 }) do
		for i, offsetZ in ipairs({ halfZ - 6, 0, -halfZ + 8 }) do
			PartUtils.CreatePart({
				name = "MilestonePanel" .. i,
				size = Vector3.new(0.2, 2.4, 2.4),
				position = basePos + Vector3.new(side * (halfX - 0.3), 5, offsetZ),
				material = ACCENT_MATERIAL,
				color = ACCENT_COLOR,
				transparency = 0.2,
				canCollide = false,
				parent = model,
			})
		end
	end

	-- Center row of milestone pedestals - the actual "hall" walk-through,
	-- filling the room's middle rather than leaving it empty between the
	-- door and the back wall. Spaced to leave clear side walkways.
	for i, offsetZ in ipairs({ halfZ * 0.45, 0, -halfZ * 0.45 }) do
		PartUtils.CreatePart({
			name = "MilestonePedestal" .. i,
			size = Vector3.new(3, 2.5, 3),
			position = basePos + Vector3.new(0, 1.25, offsetZ),
			material = FURNITURE_MATERIAL,
			color = FURNITURE_COLOR,
			parent = model,
		})
		PartUtils.CreatePart({
			name = "MilestoneTrophy" .. i,
			size = Vector3.new(1.4, 1.4, 1.4),
			position = basePos + Vector3.new(0, 3.2, offsetZ),
			material = Enum.Material.Neon,
			color = if i == 2 then Color3.fromRGB(255, 215, 0) else ACCENT_COLOR,
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = model,
		})
	end

	PartUtils.CreatePart({
		name = "ProgressionWall",
		size = Vector3.new(def.size.X - 6, def.height - 8, 0.3),
		position = basePos + Vector3.new(0, def.height / 2, -halfZ + 1),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	terminal(model, basePos + Vector3.new(0, 0, -halfZ + 5), "DailyRewardsTerminalPrompt", "Claim Daily Reward", "Daily Rewards")
end

--[[
	Statistics identity: a tall vertical "data spire" rising well above
	the roofline with stacked neon rings - reads as "data/analytics" from
	a distance, and gives the shortest building real verticality/presence.
]]
local function addStatisticsIdentity(def, model: Model)
	local basePos = def.position
	local spireHeight = 16
	local spireTop = def.height + spireHeight

	PartUtils.CreatePart({
		name = "DataSpire",
		size = Vector3.new(1.6, spireHeight, 1.6),
		position = basePos + Vector3.new(0, def.height + spireHeight / 2, 0),
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		canCollide = false,
		parent = model,
	})

	for i = 1, 3 do
		local ringY = def.height + (spireHeight / 4) * i
		PartUtils.CreateDisc({
			name = "SpireRing" .. i,
			diameter = 3 + i * 0.6,
			thickness = 0.3,
			position = basePos + Vector3.new(0, ringY, 0),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
	end

	local beacon = PartUtils.CreatePart({
		name = "SpireBeacon",
		size = Vector3.new(1.4, 1.4, 1.4),
		position = basePos + Vector3.new(0, spireTop + 0.7, 0),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = ACCENT_COLOR
	light.Range = LightingConfig.ACCENT_LIGHT_RANGE
	light.Brightness = LightingConfig.ACCENT_LIGHT_BRIGHTNESS
	light.Parent = beacon
end

--[[
	Statistics Building: the data spire outside, and inside - a data
	"reading room" (Message 20): entrance -> a center row of player-
	statistics terminal stations with simple bench seating -> the big
	stat-screen wall + Statistics Terminal against the back wall. Side
	monitor screens flank the room.
]]
function BuildingInteriors.FurnishStatistics(def, model: Model)
	local basePos = def.position
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2

	if not CUSTOM_EXTERIOR_THEMES[CURRENT_THEME_ID] then
		addStatisticsIdentity(def, model)
	end

	-- Side monitor screens along both walls, spanning the room's depth.
	for _, side in ipairs({ -1, 1 }) do
		for _, offsetZ in ipairs({ halfZ - 4, 0, -halfZ + 5 }) do
			PartUtils.CreatePart({
				name = "MonitorStand",
				size = Vector3.new(0.4, 2.5, 1.6),
				position = basePos + Vector3.new(side * (halfX - 1.5), 2.5, offsetZ),
				material = FURNITURE_MATERIAL,
				color = FURNITURE_COLOR,
				parent = model,
			})
			PartUtils.CreatePart({
				name = "MonitorScreen",
				size = Vector3.new(0.15, 1.6, 1.2),
				position = basePos + Vector3.new(side * (halfX - 1.25), 2.9, offsetZ),
				material = ACCENT_MATERIAL,
				color = ACCENT_COLOR,
				canCollide = false,
				parent = model,
			})
		end
	end

	-- Center row of player-data terminal stations with a bench each, so
	-- the room's middle reads as a place to actually sit and review your
	-- own stats, not empty floor between the door and the back wall.
	for _, offsetZ in ipairs({ halfZ * 0.4, -halfZ * 0.15 }) do
		PartUtils.CreatePart({
			name = "DataStation",
			size = Vector3.new(3, 2.8, 1.4),
			position = basePos + Vector3.new(0, 1.4, offsetZ),
			material = FURNITURE_MATERIAL,
			color = FURNITURE_COLOR,
			parent = model,
		})
		PartUtils.CreatePart({
			name = "DataStationScreen",
			size = Vector3.new(2.2, 1.3, 0.15),
			position = basePos + Vector3.new(0, 2.9, offsetZ - 0.6),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
		PartUtils.CreatePart({
			name = "DataStationBench",
			size = Vector3.new(2.6, 1, 1.2),
			position = basePos + Vector3.new(0, 0.6, offsetZ + 1.6),
			material = FURNITURE_MATERIAL,
			color = FURNITURE_COLOR,
			parent = model,
		})
	end

	PartUtils.CreatePart({
		name = "StatScreen",
		size = Vector3.new(def.size.X - 8, def.height - 6, 0.3),
		position = basePos + Vector3.new(0, def.height / 2, -halfZ + 1),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	terminal(model, basePos + Vector3.new(0, 0, -halfZ + 5), "StatisticsTerminalPrompt", "View Statistics", "Statistics")
end

--[[
	Tutorial identity: a friendly rounded-corner turret rising above the
	roof with a welcoming beacon on top - softer/rounder than the other
	buildings' hard edges, matching its "welcoming, learn here" purpose.
]]
local function addTutorialIdentity(def, model: Model)
	local basePos = def.position
	local turretHeight = 8

	PartUtils.CreatePart({
		name = "Turret",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(turretHeight, 6, 6),
		orientation = Vector3.new(0, 0, 90),
		position = basePos + Vector3.new(0, def.height + turretHeight / 2, 0),
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		canCollide = false,
		parent = model,
	})
	PartUtils.CreateDisc({
		name = "TurretTrim",
		diameter = 6.4,
		thickness = 0.3,
		position = basePos + Vector3.new(0, def.height + turretHeight, 0),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	local beacon = PartUtils.CreatePart({
		name = "TutorialBeacon",
		size = Vector3.new(2, 2, 2),
		position = basePos + Vector3.new(0, def.height + turretHeight + 1.5, 0),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = ACCENT_COLOR
	light.Range = LightingConfig.ACCENT_LIGHT_RANGE
	light.Brightness = LightingConfig.ACCENT_LIGHT_BRIGHTNESS
	light.Parent = beacon
end

--[[
	Tutorial Building: the rounded turret outside, and inside - a genuine
	front-to-back learning path (Message 20, section 7 - "the player should
	naturally move from one tutorial area to another"): welcome desk near
	the door -> an example question station in the middle, flanked by
	seating -> the Tutorial Terminal against the back wall, framed by wall
	info-panels.
]]
function BuildingInteriors.FurnishTutorial(def, model: Model)
	local basePos = def.position
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2

	if not CUSTOM_EXTERIOR_THEMES[CURRENT_THEME_ID] then
		addTutorialIdentity(def, model)
	end

	-- Welcome desk just inside the entrance - the first thing a new player
	-- reaches.
	PartUtils.CreatePart({
		name = "WelcomeDesk",
		size = Vector3.new(8, 3, 2),
		position = basePos + Vector3.new(0, 1.5, halfZ - 4),
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "WelcomeSign",
		size = Vector3.new(6, 1.4, 0.15),
		position = basePos + Vector3.new(0, 3.6, halfZ - 4),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	--[[
		Example question station in the middle of the room - a "12 x 8 = ?"
		style demo screen with a bench on each side, the room's clear second
		stop on the learning path.

		The screen used to hover in mid-air with nothing holding it up. It
		now stands on a real mount: a floor pedestal and a support post that
		both intersect the screen above and the floor below, so the station
		is one connected object.
	]]
	PartUtils.CreateDisc({
		name = "ExampleQuestionBase",
		diameter = 3.4,
		thickness = 0.4,
		position = basePos + Vector3.new(0, 0.2, 1),
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		canCollide = false,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "ExampleQuestionPost",
		size = Vector3.new(0.7, 3.4, 0.7),
		position = basePos + Vector3.new(0, 1.8, 1),
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		canCollide = false,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "ExampleQuestionScreen",
		size = Vector3.new(6, 3, 0.2),
		position = basePos + Vector3.new(0, 3.2, 1),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		transparency = 0.1,
		canCollide = false,
		parent = model,
	})
	for _, x in ipairs({ -4, 4 }) do
		PartUtils.CreatePart({
			name = "Chair",
			size = Vector3.new(1.5, 1.5, 1.5),
			position = basePos + Vector3.new(x, 0.75, 4),
			material = FURNITURE_MATERIAL,
			color = FURNITURE_COLOR,
			parent = model,
		})
	end

	-- Wall info-panels flanking the final stretch toward the terminal.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "InfoPanel",
			size = Vector3.new(0.2, 3, 4),
			position = basePos + Vector3.new(side * (halfX - 0.3), 4, -halfZ * 0.4),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			transparency = 0.25,
			canCollide = false,
			parent = model,
		})
	end

	terminal(model, basePos + Vector3.new(0, 0, -halfZ + 5), "TutorialTerminalPrompt", "Learn How to Play", "Tutorial")
end

return BuildingInteriors
