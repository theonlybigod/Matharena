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
-- Used to tag the Rival Board so RivalBoardController can find it on any
-- map without depending on a hardcoded instance path.
local CollectionService = game:GetService("CollectionService")
local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)
local CosmeticsConfig = require(ReplicatedStorage.Modules.CosmeticsConfig)
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
	-- Space now gets a full-body exterior too: a vertical rocket ship (see
	-- addSpaceRocketBody). Being in this table is what makes BuildShell skip
	-- the box's own windows/canopy/roof cap, so the plain prism underneath
	-- never shows through the hull wrapped around it.
	Space = true,
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

--[[
	SHIP-INTERIOR FIT-OUT (Space theme only).

	The buildings are rockets now, but their interiors were still generic
	rooms - a flat floor, flat walls and freestanding furniture, which reads
	as a shop that happens to be inside a rocket rather than as a deck of the
	ship itself.

	This adds the structure that makes a room read as a spacecraft interior,
	and it is applied to EVERY Space building on top of whatever that
	building's own furniture already is (see the call in BuildShell), so the
	Shop still reads as a shop and the Tutorial still reads as a classroom -
	they are just now unmistakably aboard a ship:

	  - RIBS: structural hoops arching over the ceiling at intervals down the
	    room, the single strongest "inside a hull" cue.
	  - FLOOR GRATING: a lit strip runway down the centre aisle.
	  - CONSOLE BANKS: low instrument benches against the side walls, angled
	    screens facing inward.
	  - VIEWPORTS: glowing round windows set into both side walls at eye
	    height, matching the portholes on the outside of the hull.
	  - OVERHEAD PIPING: conduit runs along the wall/ceiling junction.

	Everything here is non-collidable and kept above waist height or flush to
	a wall, so it never narrows the walkable floor or blocks the doorway.
]]
local function addSpaceInteriorFitOut(def, model: Model)
	local basePos = def.position
	local halfX = def.size.X / 2 - WALL_THICKNESS
	local halfZ = def.size.Y / 2 - WALL_THICKNESS
	local ceilingY = def.height - 1.5

	-- 1. Structural ribs arching over the ceiling.
	local ribCount = math.max(3, math.floor(def.size.Y / 7))
	for i = 0, ribCount do
		local z = -halfZ + (halfZ * 2) * (i / ribCount)
		local segs = 9
		for s = 0, segs do
			local a = math.pi * (s / segs)
			local x = math.cos(a) * halfX
			local y = ceilingY - 4 + math.sin(a) * 3.4
			PartUtils.CreatePart({
				name = ("HullRib%dS%d"):format(i, s),
				size = Vector3.new(1.1, (math.pi * halfX / segs) * 1.5, 1.1),
				cframe = CFrame.new(basePos + Vector3.new(x, y, z)) * CFrame.Angles(0, 0, a - math.pi / 2),
				material = Enum.Material.Metal,
				color = Color3.fromRGB(96, 102, 118),
				canCollide = false,
				parent = model,
			})
		end
	end

	-- 2. Lit floor grating down the centre aisle (flush, walk-over).
	for i = 0, math.floor(def.size.Y / 3) do
		local z = -halfZ + i * 3
		PartUtils.CreatePart({
			name = "DeckGrate" .. i,
			size = Vector3.new(3.2, 0.08, 2.2),
			position = basePos + Vector3.new(0, SOLID_SLAB_THICKNESS + 0.05, z),
			material = Enum.Material.DiamondPlate,
			color = Color3.fromRGB(70, 76, 90),
			canCollide = false,
			parent = model,
		})
		if i % 2 == 0 then
			PartUtils.CreatePart({
				name = "DeckGrateLight" .. i,
				size = Vector3.new(0.35, 0.1, 2),
				position = basePos + Vector3.new(1.9, SOLID_SLAB_THICKNESS + 0.06, z),
				material = Enum.Material.Neon,
				color = ACCENT_COLOR,
				canCollide = false,
				parent = model,
			})
			PartUtils.CreatePart({
				name = "DeckGrateLight" .. i,
				size = Vector3.new(0.35, 0.1, 2),
				position = basePos + Vector3.new(-1.9, SOLID_SLAB_THICKNESS + 0.06, z),
				material = Enum.Material.Neon,
				color = ACCENT_COLOR,
				canCollide = false,
				parent = model,
			})
		end
	end

	for _, side in ipairs({ -1, 1 }) do
		-- 3. Viewports set into the side walls, matching the hull portholes.
		for w = 1, 3 do
			local z = -halfZ * 0.6 + (halfZ * 1.2) * ((w - 1) / 2)
			local port = PartUtils.CreatePart({
				name = "InteriorViewport" .. w,
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(0.5, 4, 4),
				cframe = CFrame.new(basePos + Vector3.new(side * (halfX - 0.2), 7.5, z))
					* CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, math.rad(90), 0),
				material = Enum.Material.Neon,
				color = Color3.fromRGB(120, 190, 255),
				transparency = 0.25,
				canCollide = false,
				parent = model,
			})
			local pl = Instance.new("PointLight")
			pl.Color = Color3.fromRGB(120, 190, 255)
			pl.Range = 12
			pl.Brightness = 1
			pl.Shadows = true
			pl.Parent = port
		end

		-- 4. Console bank along the wall, below the viewports.
		--[[
			REMOVED. These were two solid blocks per room with an angled accent
			panel on top, standing in as "instrumentation". They were not
			interactive, not sittable and not readable - furniture-shaped filler.
			The ribs, viewports, conduit and deck grating below/above still carry
			the "inside a ship" read, and those are STRUCTURE rather than props,
			which is why they stay.
		]]

		-- 5. Conduit run at the wall/ceiling junction.
		for _, pipeOffset in ipairs({ 0, 1.3 }) do
			PartUtils.CreatePart({
				name = "CeilingConduit",
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(def.size.Y - 2, 0.7, 0.7),
				cframe = CFrame.new(basePos + Vector3.new(side * (halfX - 1.4 - pipeOffset), ceilingY - 1.2, 0))
					* CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(90)),
				material = Enum.Material.Metal,
				color = Color3.fromRGB(108, 114, 130),
				canCollide = false,
				parent = model,
			})
		end
	end
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

		-- How far up the shell this ring sits, 0 at the foot and 1 at the
		-- top. Passed to colorPicker so a theme can vary its surface by
		-- HEIGHT rather than only at random - real weathering is stratified
		-- (ash and oxidised rock collect low, fresher rock sits high), and a
		-- purely random scatter reads as noise instead of geology. Pickers
		-- that don't care simply ignore the extra argument.
		local heightT = (y - baseY) / math.max(topY - baseY, 0.001)

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
				--[[
					ENTRANCE NOTCH MUST ACCOUNT FOR PIECE WIDTH.

					This used to test the raw `doorWidth`, which left the doorway
					physically blocked. The notch correctly skips any piece whose
					CENTRE falls inside it - but every piece is `pieceWidth` wide,
					and pieceWidth is arcSpacing * SHELL_OVERLAP (1.9x). So the
					first piece OUTSIDE the notch still reached back across it by
					up to half its own width.

					Measured on the Space Shop: pieces 13.2 studs wide centred at
					x = +/-6.9, i.e. spanning inward to x = +/-0.3 - the two sides
					nearly touched, leaving a 0.6-stud slot. A raycast down the
					centreline slipped through it and reported the door open, but a
					character (~4 studs wide) could not fit.

					Widening the notch by pieceWidth pushes the nearest surviving
					piece a full half-width clear of the opening, so the doorway is
					genuinely `doorWidth` studs of open air.
				]]
				if doorWidth and y <= notchTopY and isInEntranceNotch(angle, radius, doorWidth + pieceWidth) then
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
					material = if opts.materialPicker then opts.materialPicker(rng, heightT) else opts.material,
					color = if opts.colorPicker then opts.colorPicker(rng, heightT) else opts.color,
					--[[
						THE OUTER LAYER IS SOLID. This is the fix for "you can
						phase through the buildings".

						Every piece of every custom exterior used to be
						non-collidable, which meant the igloo dome, the volcano
						mound and the submarine hull were pure decoration: a
						player could walk straight through the mountainside and
						end up standing inside the wrap, between it and the box
						shell. The box shell's own walls were the only real
						collision, and they sit far inside the visible silhouette.

						Only layer 0 collides. Layers above 0 are the staggered
						seam-filling copies (see angleOffset/layerInset above) -
						they sit BEHIND the outer surface by construction, so
						giving them collision would add a second redundant hull
						just inside the first and double the static collision cost
						for no gameplay difference.

						The entrance stays open: the notch check above skips every
						piece inside the doorway arc for all layers, so there is
						simply no geometry across the entrance to collide with.

						These are all Anchored, so this is static collision
						geometry only - no physics simulation cost.
					]]
					canCollide = layer == 0,
					--[[
						Only the OUTER layer casts shadows.

						Layers above 0 exist purely to plug the outer layer's
						seams: see angleOffset/layerInset above, which
						deliberately rotate them behind those seams and inset
						them so they never poke back out through the surface.
						Their shadows therefore fall entirely INSIDE the shell,
						where nothing can see them.

						The outer layer keeps casting, so the structure still
						throws its full silhouette onto the ground and still
						self-shadows across its own surface relief - the two
						things that actually make a dome or volcano read as
						solid rather than flat.

						These shells are the single largest shadow cost in the
						build: 11,456 parts across all maps, 62% of every
						remaining shadow caster after the PartUtils neon/tiny
						pass.
					]]
					castShadow = layer == 0,
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
			-- Same piece-width correction as buildContinuousShell above: the
			-- apron's chunks are also SHELL_OVERLAP times wider than their
			-- spacing, so a raw doorWidth notch leaves them overhanging the
			-- walk-up to the entrance.
			if opts.doorWidth and isInEntranceNotch(angle, radius, opts.doorWidth + pieceWidth) then
				continue
			end
			local pos = basePos + Vector3.new(math.sin(angle) * radius, y, math.cos(angle) * radius)
			PartUtils.CreatePart({
				name = ("%sR%dP%d"):format(opts.namePrefix, ring, p),
				size = Vector3.new(pieceWidth, opts.thickness or 2.2, bandDepth),
				cframe = CFrame.new(pos)
					* CFrame.Angles(0, angle, 0)
					* CFrame.Angles(math.rad(rng:NextNumber(-4, 4)), 0, 0),
				-- The apron lies at the very FOOT of the shell, so it is shaded
				-- from the bottom of the height ramp (see buildContinuousShell's
				-- heightT) rather than the middle - ash and weathered scree, not
				-- the charcoal of the mid flank. Without this the apron came out
				-- darker than the rock immediately above it, which reads as a
				-- shadow ring rather than as ground the mound grows out of.
				material = if opts.materialPicker then opts.materialPicker(rng, 0.04) else opts.material,
				color = if opts.colorPicker then opts.colorPicker(rng, 0.04) else opts.color,
				--[[
					SOLID. The apron used to be non-collidable on the reasoning that
					a shallow band at the foot of the mound would be a trip hazard.
					In practice it read as a phase-through: the apron is visibly a
					raised rocky lip around each volcano, and walking straight
					through it looked broken.

					Safe to make solid, measured rather than assumed: on the Lava map
					the apron's top surfaces sit at Y 5.2-6.8 against a walkable floor
					at Y 4, i.e. a step of 1.2-2.8 studs. A Roblox character's default
					MaxSlopeAngle/hip height clears a step of that size, so players
					walk up onto it rather than being stopped dead at the foot of
					every building.

					The entrance stays clear regardless: buildGroundSkirt applies the
					same width-corrected entrance notch as the shell (see the
					`doorWidth + pieceWidth` check above), so no apron piece is
					created across the doorway approach.
				]]
				canCollide = true,
				-- Shadow casting stays OFF, unchanged: a ~2-stud band flush with
				-- the floor casts essentially no visible shadow, and the shell
				-- above already grounds the structure. Only collision changed.
				castShadow = false,
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
			-- Solid, like the shell it is cut into (see buildContinuousShell's
			-- canCollide comment). The voussoirs trace a half-circle whose
			-- springing line is at doorHeight - archRadius + 1.2, so the arch
			-- only ever occupies the space ABOVE head height at the centre of
			-- the opening - it frames the doorway without narrowing the
			-- walkable gap between the jambs.
			canCollide = true,
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
			-- Genuinely solid door frame. archRadius is doorWidth/2 + 1.6, so
			-- the two jambs stand just OUTSIDE the door opening and leave the
			-- full doorWidth (8-14 studs) clear to walk through.
			canCollide = true,
			parent = model,
		})
	end
end

local function themedEntranceTunnel(def, model: Model, tunnelLength: number, tunnelMaterial: Enum.Material, tunnelColor: Color3)
	local basePos = def.position
	local halfZ = def.size.Y / 2
	local doorWidth = math.clamp(def.size.X * 0.22, MIN_DOOR_WIDTH, MAX_DOOR_WIDTH)
	local doorHeight = math.min(10, def.height - 4)

	-- Tunnel walls and roof are SOLID: this is the corridor bridging the
	-- mound's outer surface to the real doorway, so it has to be a genuine
	-- passage rather than a decorative sleeve a player can step sideways
	-- out of into the inside of the mountain. Each wall stands at
	-- doorWidth/2 + 0.4, i.e. just outside the opening, so the full door
	-- width stays walkable; the roof sits at doorHeight, above head height.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "EntranceTunnelWall",
			size = Vector3.new(0.8, doorHeight, tunnelLength),
			position = basePos + Vector3.new(side * (doorWidth / 2 + 0.4), doorHeight / 2, halfZ + tunnelLength / 2),
			material = tunnelMaterial,
			color = tunnelColor,
			canCollide = true,
			parent = model,
		})
	end
	PartUtils.CreatePart({
		name = "EntranceTunnelRoof",
		size = Vector3.new(doorWidth + 1.6, 0.8, tunnelLength),
		position = basePos + Vector3.new(0, doorHeight + 0.4, halfZ + tunnelLength / 2),
		material = tunnelMaterial,
		color = tunnelColor,
		canCollide = true,
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
	-- Space: a vertical ROCKET. Narrow radius (a rocket is a slim cylinder,
	-- only just wider than the box it wraps) and a large capHeight, because
	-- almost all of a rocket's silhouette is the tall body and nose cone
	-- rising above the roofline. This makes the craft noticeably taller than
	-- the Lava volcanoes, which was the brief.
	Space = { radius = 1.06, capHeight = 2.2, skirt = 1.45 },
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
		-- Ice, not Snow: the keystone caps the dome and is the most visible
		-- single piece of it, so leaving it as near-white Snow kept the whole
		-- structure reading as an igloo no matter what the shell below did.
		material = Enum.Material.Ice,
		color = Color3.fromRGB(158, 205, 230),
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
				--[[
					This one stays SNOW deliberately. It is the thin layer lying ON
					TOP of the dome, and it is what makes the ice beneath read as
					ice: a surface only looks icy in contrast to something matte and
					whiter next to it. Convert this too and the whole dome flattens
					into one uniform blue mass.
				]]
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
		-- Ice at the foot too, matching the shell. Slightly paler than the
		-- dome above so the base still reads as a distinct ledge rather than
		-- melting into the wall.
		material = Enum.Material.Ice,
		color = Color3.fromRGB(172, 212, 234),
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

	local function rockMaterial(r: Random, heightT: number?): Enum.Material
		local t = heightT or 0.5
		local roll = r:NextNumber()
		-- Slate/Sand read as ash and weathered scree, so they are weighted
		-- toward the FOOT of the mound where that debris actually collects;
		-- Basalt (fresh, glassy flow rock) is weighted toward the crater.
		if t < 0.35 and roll < 0.3 then
			return Enum.Material.Slate
		elseif roll < 0.3 then
			return Enum.Material.Basalt
		elseif roll < 0.58 then
			return Enum.Material.Rock
		elseif roll < 0.78 then
			return Enum.Material.Cobblestone
		end
		return WALL_MATERIAL
	end

	--[[
		COOLED-MAGMA SHADING - the fix for "every surface is the same grey all
		the way through".

		This used to be ROOFCAP_COLOR plus a shade offset of -7..+9 out of 255,
		i.e. under 4% lightness variation on a single near-black base. At that
		amplitude the variation is below what is perceptible against a dark
		surface under lobby lighting, so all ~1,100 rocks per building read as
		one flat mass.

		It is now a real palette of cooled-lava tones, blended by HEIGHT so the
		mound is stratified rather than randomly speckled - which is what makes
		it read as rock instead of noise:
		  - FOOT: pale ash grey and weathered brown - old, dust-covered scree.
		  - MID: charcoal and iron-oxide rust - the bulk of the flank.
		  - CRATER: near-black fresh basalt with a faint ember warmth, since
		    this is the most recently cooled rock on the structure.

		Every tone is still desaturated and dark enough to sit in the same
		family as ROOFCAP_COLOR, so the buildings stay cohesive with the rest
		of the Lava map rather than turning into a colour swatch.
	]]
	local ASH_LOW = Color3.fromRGB(104, 99, 96) -- pale ash / dust
	local WEATHERED_LOW = Color3.fromRGB(78, 66, 58) -- weathered brown scree
	local CHARCOAL_MID = Color3.fromRGB(54, 50, 50) -- charcoal flank
	local RUST_MID = Color3.fromRGB(72, 47, 38) -- oxidised iron streak
	local FRESH_HIGH = Color3.fromRGB(31, 27, 28) -- fresh black basalt
	local EMBER_HIGH = Color3.fromRGB(58, 33, 26) -- faint ember warmth near the crater

	local function rockColor(r: Random, heightT: number?): Color3
		local t = math.clamp(heightT or 0.5, 0, 1)

		-- Two candidate tones per band, picked between at random, then the
		-- band itself is chosen by height with a soft overlap so there is no
		-- hard seam between strata.
		local low = if r:NextNumber() < 0.5 then ASH_LOW else WEATHERED_LOW
		local mid = if r:NextNumber() < 0.5 then CHARCOAL_MID else RUST_MID
		local high = if r:NextNumber() < 0.75 then FRESH_HIGH else EMBER_HIGH

		-- Soften the boundary so a given ring can draw from either side of it.
		local blend = math.clamp(t + r:NextNumber(-0.18, 0.18), 0, 1)
		local base
		if blend < 0.5 then
			base = low:Lerp(mid, blend / 0.5)
		else
			base = mid:Lerp(high, (blend - 0.5) / 0.5)
		end

		-- Per-piece grain on top of the band, wide enough to actually see.
		local grain = r:NextNumber(-0.055, 0.055)
		return Color3.new(
			math.clamp(base.R + grain, 0, 1),
			math.clamp(base.G + grain * 0.85, 0, 1),
			math.clamp(base.B + grain * 0.75, 0, 1)
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
			-- Solid, matching the flank it caps - the rim is the top edge of a
			-- now-climbable mountain, so it needs to stop a player rather than
			-- let them drop through into the crater.
			canCollide = true,
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
	--[[
		LAVA THAT ACTUALLY DRIPS FROM THE TOP.

		Three things were wrong with the previous flows. They STARTED partway
		down (startT was a random 0.05-0.2 below the crater), so the lava
		appeared out of nowhere on the flank instead of spilling over the rim.
		They often STOPPED partway down (endT as low as 0.7), leaving a flow
		hanging in mid-slope. And every segment was one flat ACCENT_COLOR at
		full brightness, so a 40-stud flow had no sense of cooling as it ran.

		Now: every flow begins AT the crater rim (t = 0) and runs the full
		height of the mound to the apron, tapers as it descends the way a real
		spill thins out, and is colour-graded from white-hot at the lip through
		orange to a dark crusted red at the foot. A few segments per flow get a
		PointLight so the flow genuinely casts light onto the rock beside it.
	]]
	local HOT_LIP = Color3.fromRGB(255, 238, 170) -- white-hot at the crater lip
	local FLOW_MID = Color3.fromRGB(255, 116, 24) -- bright orange mid-flow
	local CRUSTED = Color3.fromRGB(122, 28, 12) -- dark crusted red at the foot

	local function lavaFlowColor(t: number): Color3
		if t < 0.45 then
			return HOT_LIP:Lerp(FLOW_MID, t / 0.45)
		end
		return FLOW_MID:Lerp(CRUSTED, (t - 0.45) / 0.55)
	end

	local flowBottomY = collarTop * 0.12
	local flowSpan = craterY - flowBottomY
	local channelCount = rng:NextInteger(4, 6)
	for i = 1, channelCount do
		-- Spread the flows around the mound instead of letting them clump:
		-- an even base angle with jitter, so no two spill over the same lip.
		local channelAngle = (2 * math.pi / channelCount) * i + rng:NextNumber(-0.35, 0.35)
		local segments = 16
		local channelWidth = rng:NextNumber(2.2, 3.6)
		local segStep = flowSpan / segments

		for s = 0, segments do
			local t = s / segments
			local y = craterY - flowSpan * t
			-- +0.35 so the flow sits just proud of the rock rather than
			-- z-fighting with the shell slabs it runs over.
			local r = volcanoProfile(y) + 0.35
			local dr = volcanoProfile(y + segStep * 0.5) - volcanoProfile(y - segStep * 0.5)
			local slant = math.sqrt(dr * dr + segStep * segStep)

			-- Wide and heavy where it pours over the rim, thinning as it runs
			-- out of momentum near the bottom.
			local widthTaper = channelWidth * (1 - 0.45 * t)
			-- A slight wander across the slope, so a flow snakes rather than
			-- dropping in a dead-straight vertical stripe.
			local wander = math.sin(t * 3.1 + i) * 0.05

			PartUtils.CreatePart({
				name = ("LavaChannel%dS%d"):format(i, s),
				size = Vector3.new(widthTaper, math.max(slant * SHELL_OVERLAP, 1.5), 0.55),
				cframe = CFrame.new(
					basePos
						+ Vector3.new(
							math.sin(channelAngle + wander) * r,
							y,
							math.cos(channelAngle + wander) * r
						)
				) * CFrame.Angles(0, channelAngle + wander, 0) * CFrame.Angles(math.atan2(dr, segStep), 0, 0),
				material = Enum.Material.CrackedLava,
				color = lavaFlowColor(t),
				canCollide = false,
				parent = model,
			})
		end

		-- Overflow tongue at the lip: a short, wider slab lying across the
		-- rim itself, so the flow reads as spilling OVER the crater edge
		-- rather than starting just below it.
		local lipRadius = volcanoProfile(craterY) + 0.2
		PartUtils.CreatePart({
			name = ("LavaOverflowLip%d"):format(i),
			size = Vector3.new(channelWidth * 1.5, 1.1, 3.2),
			cframe = CFrame.new(
				basePos + Vector3.new(math.sin(channelAngle) * lipRadius, craterY + 0.5, math.cos(channelAngle) * lipRadius)
			) * CFrame.Angles(0, channelAngle, 0),
			material = Enum.Material.CrackedLava,
			color = HOT_LIP,
			canCollide = false,
			parent = model,
		})

		-- Hanging drips: short stubs breaking off the flow partway down,
		-- which is what actually sells "dripping" rather than "painted on".
		for d = 1, rng:NextInteger(2, 4) do
			local dripT = rng:NextNumber(0.15, 0.8)
			local dripY = craterY - flowSpan * dripT
			local dripR = volcanoProfile(dripY) + 0.45
			local dripAngle = channelAngle + rng:NextNumber(-0.12, 0.12)
			PartUtils.CreatePart({
				name = ("LavaDrip%dD%d"):format(i, d),
				size = Vector3.new(rng:NextNumber(0.5, 1.1), rng:NextNumber(1.8, 4.2), 0.5),
				cframe = CFrame.new(
					basePos + Vector3.new(math.sin(dripAngle) * dripR, dripY, math.cos(dripAngle) * dripR)
				) * CFrame.Angles(0, dripAngle, 0),
				material = Enum.Material.Neon,
				color = lavaFlowColor(dripT),
				transparency = 0.1,
				canCollide = false,
				parent = model,
			})
		end

		-- Two lights per flow (not per segment - 16 lights per flow across
		-- four buildings would be a real rendering cost for no visual gain),
		-- placed high and mid so the flow lights the rock it runs over.
		for _, lightT in ipairs({ 0.08, 0.5 }) do
			local lightY = craterY - flowSpan * lightT
			local lightR = volcanoProfile(lightY) + 1
			local glowPart = PartUtils.CreatePart({
				name = ("LavaFlowGlow%d"):format(i),
				size = Vector3.new(0.4, 0.4, 0.4),
				position = basePos
					+ Vector3.new(math.sin(channelAngle) * lightR, lightY, math.cos(channelAngle) * lightR),
				transparency = 1,
				canCollide = false,
				parent = model,
			})
			local flowLight = Instance.new("PointLight")
			flowLight.Color = lavaFlowColor(lightT)
			flowLight.Range = 26
			flowLight.Brightness = 1.6
			flowLight.Parent = glowPart
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

--[[
	"Landed Craft" (Space): half angular HULL, half flying-saucer DISC.

	The lower two thirds is a faceted, straight-flanked hull - a grounded
	ship's body, built from the same continuous overlapping-slab shell every
	other theme uses, so it is one solid mass rather than stacked plates.
	Above the roofline it flares OUT into a saucer: a broad overhanging
	flange far wider than the hull, capped by a shallow dome and a cockpit
	blister. That flare is what makes the silhouette read as a UFO rather
	than as a tower - a saucer's defining feature is that it is widest well
	above its base and overhangs what is underneath it.

	SOLID, BUT STILL ENTERABLE. buildContinuousShell makes its OUTER layer
	collidable (layer 0), so a player cannot walk through the hull. The
	doorway stays open because every shell ring skips the pieces inside the
	entrance notch, and the entrance tunnel bridges out through the flange
	to the real doorway - the same arrangement the Lava volcano uses.

	The underside ring of landing lights and the landing legs are decorative
	only (non-collide) so they can never trip a player walking up to the door.
]]
local function addSpaceCraftBody(def, model: Model)
	local basePos = def.position
	local halfZ = def.size.Y / 2
	local halfDiag, hullRadius, hullTop, peakY =
		computeEnclosingEnvelope(def, EXTERIOR_ENVELOPE.Space.radius, EXTERIOR_ENVELOPE.Space.capHeight)
	local rng = Random.new(math.floor(basePos.X * 613 + basePos.Z * 149))
	local doorWidth = math.clamp(def.size.X * 0.22, MIN_DOOR_WIDTH, MAX_DOOR_WIDTH)
	local doorHeight = math.min(10, def.height - 4)

	-- Where the hull stops and the saucer flange begins. Two thirds hull,
	-- one third saucer, per the brief's "half hull half saucer" split
	-- measured by silhouette rather than by strict height.
	local flangeY = hullTop * 0.72
	local flangeRadius = hullRadius * 1.34 -- the overhang that makes it a saucer
	local rimThickness = 3.2

	--[[
		Profile: straight-flanked hull, then a rapid outward flare to the
		saucer rim, then a shallow dome closing to the cockpit.
	]]
	local function craftProfile(y: number): number
		if y <= flangeY then
			-- Hull: very slight inward batter so it reads as machined.
			local t = y / math.max(flangeY, 0.001)
			return hullRadius * (1 - 0.06 * t)
		elseif y <= hullTop then
			-- Flare out to the saucer rim.
			local t = (y - flangeY) / math.max(hullTop - flangeY, 0.001)
			return hullRadius * 0.94 + (flangeRadius - hullRadius * 0.94) * math.sin(t * math.pi / 2)
		end
		-- Dome above the rim, closing toward the cockpit.
		local t = math.clamp((y - hullTop) / math.max(peakY - hullTop, 0.001), 0, 1)
		return flangeRadius * math.cos(t * math.pi / 2) * 0.98 + 1.5
	end

	local HULL_LIGHT = Color3.fromRGB(150, 158, 178)
	local HULL_DARK = Color3.fromRGB(74, 80, 96)
	local function plateColor(r: Random, heightT: number?): Color3
		-- Panelled metal: alternating light/dark plates with a little grain,
		-- so the hull reads as built from sections rather than one flat skin.
		local base = if r:NextNumber() < 0.5 then HULL_LIGHT else HULL_DARK
		local g = r:NextNumber(-0.05, 0.05)
		return Color3.new(
			math.clamp(base.R + g, 0, 1),
			math.clamp(base.G + g, 0, 1),
			math.clamp(base.B + g, 0, 1)
		)
	end
	local function plateMaterial(r: Random): Enum.Material
		return if r:NextNumber() < 0.5 then Enum.Material.Metal else Enum.Material.DiamondPlate
	end

	buildContinuousShell({
		model = model,
		basePos = basePos,
		rng = rng,
		profile = craftProfile,
		topY = peakY,
		stepY = 2.6,
		pieceTarget = 7,
		thickness = 3.0,
		layers = 2,
		-- Machined hull: almost no jitter, unlike the volcano's broken rock.
		radialJitter = 0.12,
		tiltJitter = 0.015,
		namePrefix = "CraftPlate",
		materialPicker = plateMaterial,
		colorPicker = plateColor,
		doorWidth = doorWidth,
		notchTopY = doorHeight + 2.5,
	})

	-- Saucer rim band: a hard edge right at the widest point, which is what
	-- actually sells the overhang.
	local rimCount = math.max(20, math.ceil((2 * math.pi * flangeRadius) / 4))
	local rimSpacing = (2 * math.pi * flangeRadius) / rimCount
	for c = 1, rimCount do
		local ang = (2 * math.pi / rimCount) * c
		PartUtils.CreatePart({
			name = "SaucerRim" .. c,
			size = Vector3.new(rimSpacing * SHELL_OVERLAP, rimThickness, 5),
			cframe = CFrame.new(basePos + Vector3.new(math.sin(ang) * flangeRadius, hullTop, math.cos(ang) * flangeRadius))
				* CFrame.Angles(0, ang, 0),
			material = Enum.Material.Metal,
			color = HULL_LIGHT,
			canCollide = true, -- part of the solid body
			parent = model,
		})
		-- Underside landing lights, inset under the overhang.
		if c % 2 == 0 then
			local lamp = PartUtils.CreatePart({
				name = "SaucerUnderLight" .. c,
				size = Vector3.new(2.2, 0.5, 2.2),
				position = basePos
					+ Vector3.new(math.sin(ang) * (flangeRadius - 2.5), hullTop - rimThickness / 2 - 0.3, math.cos(ang) * (flangeRadius - 2.5)),
				material = Enum.Material.Neon,
				color = ACCENT_COLOR,
				canCollide = false,
				parent = model,
			})
			if c % 6 == 0 then
				local l = Instance.new("PointLight")
				l.Color = ACCENT_COLOR
				l.Range = 22
				l.Brightness = 1.6
				l.Parent = lamp
			end
		end
	end

	-- Cockpit blister on top - the saucer's dome canopy.
	local cockpit = PartUtils.CreatePart({
		name = "SaucerCockpit",
		shape = Enum.PartType.Ball,
		size = Vector3.new(flangeRadius * 0.5, flangeRadius * 0.42, flangeRadius * 0.5),
		position = basePos + Vector3.new(0, peakY, 0),
		material = Enum.Material.Glass,
		color = GLASS_COLOR,
		transparency = 0.35,
		canCollide = true,
		parent = model,
	})
	local cockpitLight = Instance.new("PointLight")
	cockpitLight.Color = ACCENT_COLOR
	cockpitLight.Range = 26
	cockpitLight.Brightness = 1.4
	cockpitLight.Parent = cockpit

	-- Beacon at the very top.
	local beacon = PartUtils.CreatePart({
		name = "CraftBeacon",
		size = Vector3.new(1.4, 1.4, 1.4),
		position = basePos + Vector3.new(0, peakY + flangeRadius * 0.26, 0),
		material = Enum.Material.Neon,
		color = ACCENT_COLOR,
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})
	local bl = Instance.new("PointLight")
	bl.Color = ACCENT_COLOR
	bl.Range = 30
	bl.Brightness = 2
	bl.Parent = beacon

	--[[
		Landing legs. Non-collidable on purpose: they splay outward across
		the ground exactly where a player walks up to the entrance, and a
		solid strut at shin height there would be a constant snag. The hull
		above them is what actually stops the player.
	]]
	for leg = 1, 4 do
		local ang = (math.pi / 2) * leg + math.pi / 4
		-- Skip a leg that would land across the doorway approach.
		if not isInEntranceNotch(ang, hullRadius, doorWidth * 2.2) then
			local footR = hullRadius * 1.12
			local top = basePos + Vector3.new(math.sin(ang) * hullRadius * 0.8, flangeY * 0.55, math.cos(ang) * hullRadius * 0.8)
			local foot = basePos + Vector3.new(math.sin(ang) * footR, 0.6, math.cos(ang) * footR)
			local mid = (top + foot) / 2
			PartUtils.CreatePart({
				name = "LandingLeg" .. leg,
				size = Vector3.new(2, (top - foot).Magnitude, 2),
				cframe = CFrame.lookAt(mid, foot) * CFrame.Angles(math.rad(90), 0, 0),
				material = Enum.Material.Metal,
				color = HULL_DARK,
				canCollide = false,
				parent = model,
			})
			PartUtils.CreateDisc({
				name = "LandingFoot" .. leg,
				diameter = 6,
				thickness = 0.8,
				position = foot - Vector3.new(0, 0.3, 0),
				material = Enum.Material.Metal,
				color = HULL_DARK,
				canCollide = false,
				parent = model,
			})
		end
	end

	-- Boarding tunnel out through the flange to the real doorway, framed by
	-- a metal archway - same functional arrangement as the other themes.
	local tunnelLength = math.max(6, flangeRadius - halfZ + 3)
	themedEntranceTunnel(def, model, tunnelLength, Enum.Material.Metal, HULL_DARK)

	local ringCount = math.max(2, math.ceil((tunnelLength - 2.5) / 2.4))
	for r = 0, ringCount do
		buildEntranceArch({
			model = model,
			basePos = basePos,
			doorWidth = doorWidth,
			doorHeight = doorHeight,
			z = halfZ + ((tunnelLength - 2.5) / ringCount) * r,
			segments = 11,
			blockDepth = 2.0,
			thickness = ((tunnelLength - 2.5) / ringCount) * SHELL_OVERLAP,
			material = Enum.Material.Metal,
			color = if r % 2 == 0 then HULL_LIGHT else HULL_DARK,
		})
	end
end

--[[
	"Rocket Ship" (Space): a vertical launch vehicle standing on its fins.

	Classic storybook rocket, in the colours that read as one instantly: a
	white body with a red nose cone and red fins, banded with dark trim, a
	row of portholes up one side and an engine skirt at the base. Deliberately
	taller than the Lava volcanoes (see EXTERIOR_ENVELOPE.Space) so the Space
	map's skyline is the tallest of the five.

	SHAPE. The profile is a near-straight cylinder for the whole body - a
	rocket's defining feature is that it does NOT taper until the very top -
	then a short shoulder and a long conical nose. buildContinuousShell tiles
	it with overlapping plates exactly like every other theme, so the hull is
	one continuous mass rather than stacked rings.

	SOLID, BUT ENTERABLE. The shell's outer layer collides, so a player
	cannot walk through the hull; the entrance notch (now width-corrected -
	see buildContinuousShell) leaves a genuinely clear doorway, and the
	boarding tunnel bridges out to it.

	The fins are placed at 90-degree intervals and any fin that would land
	across the doorway approach is skipped, so nothing ever fouls the walk-in.
]]
local function addSpaceRocketBody(def, model: Model)
	local basePos = def.position
	local halfZ = def.size.Y / 2
	local halfDiag, bodyRadius, collarTop, peakY =
		computeEnclosingEnvelope(def, EXTERIOR_ENVELOPE.Space.radius, EXTERIOR_ENVELOPE.Space.capHeight)
	local rng = Random.new(math.floor(basePos.X * 613 + basePos.Z * 149))
	local doorWidth = math.clamp(def.size.X * 0.22, MIN_DOOR_WIDTH, MAX_DOOR_WIDTH)
	local doorHeight = math.min(10, def.height - 4)

	-- Classic rocket palette.
	local BODY_WHITE = Color3.fromRGB(238, 240, 245)
	local ROCKET_RED = Color3.fromRGB(196, 40, 42)
	local TRIM_DARK = Color3.fromRGB(44, 46, 54)

	-- Vertical layout. The body runs straight up most of the height; the
	-- nose cone occupies the top third.
	local shoulderY = collarTop + (peakY - collarTop) * 0.34 -- body stops tapering here
	local noseBase = shoulderY

	local function rocketProfile(y: number): number
		if y <= noseBase then
			-- Straight body with only the faintest taper, so it reads as a
			-- machined cylinder rather than a cone.
			local t = y / math.max(noseBase, 0.001)
			return bodyRadius * (1 - 0.07 * t)
		end
		-- Conical nose: radius falls to a point at the tip.
		local t = math.clamp((y - noseBase) / math.max(peakY - noseBase, 0.001), 0, 1)
		return bodyRadius * 0.93 * (1 - t) ^ 0.82
	end

	--[[
		Paint scheme as a pure function of height (0..1 up the rocket), with no
		random component. The old version jittered each plate's colour to break
		up the tiling; with a smooth cylindrical hull there is no tiling to
		break up, and per-segment noise would instead show as visible banding.
	]]
	local noseFraction = noseBase / math.max(peakY, 0.001)
	local function plateColorAt(t: number): Color3
		if t >= noseFraction then
			return ROCKET_RED
		elseif t < 0.05 then
			return TRIM_DARK -- scorched engine skirt at the very bottom
		end
		-- Two red bands up the white body, a classic rocket detail.
		local band = (t > 0.30 and t < 0.36) or (t > 0.58 and t < 0.63)
		return if band then ROCKET_RED else BODY_WHITE
	end

	--[[
		SMOOTH HULL.

		This used to go through buildContinuousShell, which tiles a surface with
		overlapping rectangular slabs and jitters each one. That technique is
		right for broken rock (the volcano) but wrong for a manufactured hull:
		a rocket's cross-section is a CIRCLE, and approximating a circle with
		rectangles is faceted by construction. It also cost 3,838 parts per map.

		A rocket is a surface of revolution, so the honest primitive is a
		CYLINDER - which Roblox renders as a genuinely round surface, not an
		approximation. Stacking thin cylinders of varying radius gives a hull
		that is perfectly smooth around its circumference, with the only
		stepping being vertical (and that is hidden by using fine steps through
		the curved nose, where radius actually changes).

		The doorway is the one thing a cylinder cannot express, since it has no
		hole. So the hull is built in two zones:

		  - THE SHELL ZONE (ground up to just above the interior ceiling): arc
		    segments, with the entrance notch carved out.
		  - ABOVE THE INTERIOR: solid cylinders, all the way to the tip.

		WHY THE SHELL ZONE COVERS THE WHOLE INTERIOR, not just the door band.
		A solid cylinder's VOLUME includes the room, so any solid section whose
		height range overlaps the interior is a solid slab sitting inside it.
		That is exactly what happened when the ceilings were raised: the room
		grew up into `HullSection12`, a 4-stud-thick puck at radius 21 spanning
		Y 16.4-20.6, which cut straight through a feature screen spanning
		Y 8.5-23.0 - measured as 3/3 blocked sightlines on all four buildings.

		Solid cylinders are only safe ABOVE the ceiling, where there is no room
		for them to be inside of. Below that the hull has to be a true shell.

		Part count is still far below the original per-plate approach, because
		the nose and upper body - most of the height - remain solid cylinders.
	]]
	local notchTop = doorHeight + 2.5
	--[[
		Top of the shell zone: clear of the interior ceiling, never below the
		door band, and never past the nose (where there is no interior and the
		radius is changing fast enough that arc segments would be wasteful).
	]]
	local shellTop = math.min(math.max(notchTop, def.height + 3), noseBase)

	-- Zone 1: shell of arc segments over the full interior height, leaving
	-- the entrance open.
	do
		local bandStep = 2.2
		for y = 0, shellTop, bandStep do
			local radius = rocketProfile(y)
			local circumference = 2 * math.pi * radius
			local count = math.max(24, math.ceil(circumference / 4))
			local arcSpacing = circumference / count
			local pieceWidth = arcSpacing * 1.25 -- modest overlap; no jitter to hide
			for s = 1, count do
				local a = (2 * math.pi / count) * s
				-- The notch is only carved through the door band itself; above it
				-- the shell closes all the way round.
				local carve = y <= notchTop and isInEntranceNotch(a, radius, doorWidth + pieceWidth)
				if not carve then
					PartUtils.CreatePart({
						name = ("HullBandY%dS%d"):format(math.floor(y), s),
						size = Vector3.new(pieceWidth, bandStep * 1.25, 2.4),
						cframe = CFrame.new(basePos + Vector3.new(math.sin(a) * radius, y, math.cos(a) * radius))
							* CFrame.Angles(0, a, 0),
						material = Enum.Material.SmoothPlastic,
						color = plateColorAt(y / peakY),
						canCollide = true,
						parent = model,
					})
				end
			end
		end
	end

	-- Zone 2: solid cylinders from above the interior ceiling to the tip.
	do
		local y = shellTop
		while y < peakY do
			-- Fine steps through the nose (where the radius is changing fast),
			-- coarser up the straight body where consecutive rings are the same
			-- size and a taller segment is indistinguishable from several short
			-- ones.
			local step = if y >= noseBase then 1.1 else 4.0
			local segTop = math.min(y + step, peakY)
			-- Use the radius at the segment's MIDPOINT so a tapering section is
			-- centred on the true profile rather than always erring wide.
			local radius = rocketProfile((y + segTop) / 2)
			if radius > 0.4 then
				local segHeight = (segTop - y) * 1.06 -- slight overlap, no visible seam
				PartUtils.CreatePart({
					name = ("HullSection%d"):format(math.floor(y)),
					shape = Enum.PartType.Cylinder,
					-- A Cylinder's length is on X, so it is laid on its side and
					-- rotated upright.
					size = Vector3.new(segHeight, radius * 2, radius * 2),
					cframe = CFrame.new(basePos + Vector3.new(0, (y + segTop) / 2, 0))
						* CFrame.Angles(0, 0, math.rad(90)),
					material = Enum.Material.SmoothPlastic,
					color = plateColorAt(((y + segTop) / 2) / peakY),
					canCollide = true,
					parent = model,
				})
			end
			y = segTop
		end
	end

	-- Nose tip cap, so the cone closes to a real point instead of a ragged
	-- ring of plates.
	PartUtils.CreatePart({
		name = "RocketNoseTip",
		shape = Enum.PartType.Ball,
		size = Vector3.new(bodyRadius * 0.42, bodyRadius * 0.55, bodyRadius * 0.42),
		position = basePos + Vector3.new(0, peakY - bodyRadius * 0.12, 0),
		material = Enum.Material.Metal,
		color = ROCKET_RED,
		canCollide = true,
		parent = model,
	})

	--[[
		SOLID DECK UNDER THE WHOLE HULL.

		The box shell's own Floor only spans def.size (the rectangle), but the
		rocket hull is a CIRCLE of bodyRadius around it. Between the box's edge
		and the hull wall there is a ring of floorless space, and the boarding
		tunnel outside the front wall has no floor of its own either - both are
		places a player can end up standing on nothing but the map ground far
		below, which reads as falling through the interior.

		This deck is one solid disc covering the entire hull footprint, set so
		its TOP is flush with the box floor's top surface (no lip to trip on),
		plus a matching strip down the boarding tunnel.
	]]
	--[[
		Deck height is READ FROM THE BOX FLOOR, not assumed.

		An earlier version set this to SOLID_SLAB_THICKNESS on the theory that
		the box floor's top sat there. It does not: BuildShell positions the
		Floor slab relative to basePos differently, and the whole map is then
		bulk-translated by MapConfig.GROUND_ELEVATION. The result was a deck
		whose top stood at world Y 8.5 against a box floor top of 4.5 and a
		plaza at 4.0 - a 4-stud wall right across the entrance, which stopped a
		walking character dead every time.

		BuildShell has already created "Floor" by the time this runs (see the
		addThemedRoofSilhouette call site), so the honest answer is simply to
		ask it how high its own surface is and match. Falls back to the old
		constant only if the Floor is somehow absent.
	]]
	local boxFloor = model:FindFirstChild("Floor")
	local FLOOR_TOP = if boxFloor and boxFloor:IsA("BasePart")
		then (boxFloor.Position.Y + boxFloor.Size.Y / 2) - basePos.Y
		else SOLID_SLAB_THICKNESS
	local DECK_THICKNESS = 2
	PartUtils.CreateDisc({
		name = "RocketDeck",
		diameter = bodyRadius * 2.1,
		thickness = DECK_THICKNESS,
		position = basePos + Vector3.new(0, FLOOR_TOP - DECK_THICKNESS / 2, 0),
		material = Enum.Material.DiamondPlate,
		color = TRIM_DARK,
		canCollide = true,
		parent = model,
	})

	local gantryLength = math.max(6, bodyRadius - halfZ + 4)
	PartUtils.CreatePart({
		name = "RocketGantryFloor",
		size = Vector3.new(doorWidth + 3, DECK_THICKNESS, gantryLength + 6),
		position = basePos + Vector3.new(0, FLOOR_TOP - DECK_THICKNESS / 2, halfZ + gantryLength / 2),
		material = Enum.Material.DiamondPlate,
		color = TRIM_DARK,
		canCollide = true,
		parent = model,
	})

	--[[
		NO BOARDING RAMP. An earlier version stepped four solid blocks up from
		the plaza to the gantry, which turned out to be both unnecessary and
		actively harmful: the gantry deck's top sits at SOLID_SLAB_THICKNESS
		(4.5) and the plaza ground is at 4.0, so the lip is half a stud - a
		character walks over it without noticing. The ramp blocks instead
		overlapped the gantry floor and stopped a walking character dead in the
		tunnel (measured: character halted 16 studs short of the room).
	]]

	-- Beacon on the very tip.
	local beacon = PartUtils.CreatePart({
		name = "RocketBeacon",
		size = Vector3.new(1.5, 1.5, 1.5),
		position = basePos + Vector3.new(0, peakY + 1.6, 0),
		material = Enum.Material.Neon,
		color = ACCENT_COLOR,
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})
	local bl = Instance.new("PointLight")
	bl.Color = ACCENT_COLOR
	bl.Range = 30
	bl.Brightness = 2
	bl.Parent = beacon

	--[[
		FINS. Four tapered red fins standing at the base, each a wedge running
		from the hull outward and downward to the ground - the silhouette that
		makes a cylinder read as a rocket.

		Any fin whose bearing falls across the doorway approach is skipped
		entirely, so a fin can never stand in front of the entrance. Fins are
		non-collidable: they splay out at ankle height exactly where players
		walk, and the hull behind them is what actually stops anyone.
	]]
	local finHeight = math.min(collarTop * 0.9, 26)
	for fin = 1, 4 do
		local ang = (math.pi / 2) * fin + math.pi / 4
		if not isInEntranceNotch(ang, bodyRadius, doorWidth * 2.4) then
			local outR = bodyRadius * 1.55
			for seg = 1, 5 do
				-- Stepped wedge: wider and lower as it runs outward, which gives
				-- the swept-back fin profile without needing a mesh.
				local t = seg / 5
				local r = bodyRadius * 0.9 + (outR - bodyRadius * 0.9) * t
				local h = finHeight * (1 - t * 0.78)
				PartUtils.CreatePart({
					name = ("RocketFin%dS%d"):format(fin, seg),
					size = Vector3.new(1.6, h, (outR - bodyRadius * 0.9) / 5 * 1.9),
					cframe = CFrame.new(basePos + Vector3.new(math.sin(ang) * r, h / 2, math.cos(ang) * r))
						* CFrame.Angles(0, ang, 0),
					material = Enum.Material.Metal,
					color = ROCKET_RED,
					canCollide = false,
					parent = model,
				})
			end
		end
	end

	--[[
		NO ENGINE CLUSTER. The skirt, nozzles and exhaust glows are gone.

		They were described as "tucked under the base, visible between the
		fins", but there is no "under" on these buildings: the rocket stands on
		the ground and the room floor is AT ground level, so everything meant to
		sit beneath the hull ended up inside the room instead.

		Measured on StatisticsBuilding, whose floor surface is at Y=4.5:

		  RocketEngineSkirt  Y=5.2, a 45-stud-DIAMETER disc - i.e. a solid
		                     plate 0.7 studs above the floor spanning the whole
		                     36x19 room. This is what was hiding the streak
		                     plinths and swallowing the seats.
		  RocketNozzle1-3    Y=5.6, 5-stud cylinders at seat height, directly
		                     in front of the feature screen.
		  RocketExhaustGlow  Y=0.5, plus the orange PointLights already removed
		                     for washing the interiors warm.

		Nothing is lost outside: the base of each rocket is ringed by fins and
		sits flush on the plaza, so none of this was ever visible from the
		exterior anyway - it was only ever furniture in the middle of a room.
	]]

	-- Cable run / spine down the back of the hull (opposite the door).
	for s = 1, 10 do
		local sy = collarTop * (0.08 * s)
		if sy < noseBase then
			PartUtils.CreatePart({
				name = "RocketSpine" .. s,
				size = Vector3.new(2.4, collarTop * 0.085, 1.2),
				cframe = CFrame.new(basePos + Vector3.new(0, sy, -(rocketProfile(sy) + 0.5)))
					* CFrame.Angles(0, math.pi, 0),
				material = Enum.Material.Metal,
				color = TRIM_DARK,
				canCollide = false,
				parent = model,
			})
		end
	end

	-- Girth rings at the painted band seams. These are single discs rather
	-- than rings of small blocks: a block ring around a smooth cylinder would
	-- reintroduce exactly the faceting the cylindrical hull exists to avoid.
	for _, bandT in ipairs({ 0.33, 0.60 }) do
		local by = peakY * bandT
		PartUtils.CreateDisc({
			name = "RocketGirthRing",
			diameter = rocketProfile(by) * 2 + 1.4,
			thickness = 1.6,
			position = basePos + Vector3.new(0, by, 0),
			material = Enum.Material.Metal,
			color = TRIM_DARK,
			canCollide = false,
			parent = model,
		})
	end

	-- Capsule collar where the body meets the nose cone.
	PartUtils.CreateDisc({
		name = "RocketCapsuleCollar",
		diameter = rocketProfile(noseBase) * 2.25,
		thickness = 2.2,
		position = basePos + Vector3.new(0, noseBase, 0),
		material = Enum.Material.Metal,
		color = TRIM_DARK,
		canCollide = false,
		parent = model,
	})

	--[[
		Portholes up the body. Placed on the two SIDE bearings only (+/-90
		degrees from the door), so none of them land on the entrance face where
		the name plate goes.
	]]
	for _, sideAng in ipairs({ math.pi / 2, -math.pi / 2 }) do
		for w = 1, 4 do
			local wy = collarTop * (0.28 + 0.2 * (w - 1))
			local wr = rocketProfile(wy) + 0.3
			PartUtils.CreatePart({
				name = ("RocketPorthole%d"):format(w),
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(0.6, 3.2, 3.2),
				cframe = CFrame.new(basePos + Vector3.new(math.sin(sideAng) * wr, wy, math.cos(sideAng) * wr))
					* CFrame.Angles(0, sideAng, 0)
					* CFrame.Angles(0, 0, math.rad(90)),
				material = Enum.Material.Neon,
				color = ACCENT_COLOR,
				transparency = 0.25,
				canCollide = false,
				parent = model,
			})
		end
	end

	-- Boarding gantry out to the real doorway, framed by metal arch rings.
	local tunnelLength = math.max(6, bodyRadius - halfZ + 4)
	themedEntranceTunnel(def, model, tunnelLength, Enum.Material.Metal, TRIM_DARK)

	local ringCount = math.max(2, math.ceil((tunnelLength - 2.5) / 2.4))
	for r = 0, ringCount do
		buildEntranceArch({
			model = model,
			basePos = basePos,
			doorWidth = doorWidth,
			doorHeight = doorHeight,
			z = halfZ + ((tunnelLength - 2.5) / ringCount) * r,
			segments = 11,
			blockDepth = 2.0,
			thickness = ((tunnelLength - 2.5) / ringCount) * SHELL_OVERLAP,
			material = Enum.Material.Metal,
			color = if r % 2 == 0 then BODY_WHITE else TRIM_DARK,
		})
	end
end

local ROOF_SILHOUETTE_BUILDERS = {
	IceAge = addIceAgeDome,
	Lava = addLavaVolcanoRoof,
	UnderTheSea = addUnderTheSeaHull,
	Space = addSpaceRocketBody,
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
	--[[
		NO DECORATIVE FLOURISH. addThemedFlourish used to drop a small floating
		orrery (a tilted neon ring with a glowing ball at its centre, hovering
		unsupported) into every building on every map. It is exactly the kind of
		object that reads as placeholder: it hangs in mid-air, means nothing,
		and does nothing. Each building's purpose now supplies its own contents,
		so there is nothing to pad out.
	]]

	--[[
		Space-only ship fit-out: hull ribs, deck grating, viewports, console
		banks and conduit. Applied here in the shared shell, alongside
		addThemedFlourish above, so every Space building gets it without
		touching the four Furnish* functions - each of those keeps owning what
		its room is FOR (shop stock, reward plinths, tutorial stations, stat
		terminals), and this only supplied the surrounding ship structure.

		HISTORICAL - the call below is gone. See the note that follows.
	]]
	--[[
		NO SPACE-ONLY INTERIOR FIT-OUT.

		This used to call addSpaceInteriorFitOut, which was gated on
		CURRENT_THEME_ID == "Space" and therefore ran on this map and no other.
		It dressed every Space room with ceiling conduit runs and wall
		viewports - 10 extra parts per building that the Lava, Ice Age, Under
		the Sea and Futuristic rooms do not have.

		Removed because the interiors are meant to be identical across all five
		maps: a blank room whose only content is its one feature screen, plus
		seating where a player actually sits. Wall and floor COLOUR still varies
		per map through LobbyTheme, which is the intended per-map difference -
		adding geometry to one map is not.

		The fit-out function itself is left in place, unreferenced, in case the
		ship-interior look is wanted again later; it is dead code and safe to
		delete.
	]]

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
--[[
	Builds a terminal: dais, archway frame, header sign, stand and prompt.

	`bare` builds ONLY the stand and its ProximityPrompt, skipping the dais,
	arch and header. That exists because the Daily Rewards terminal's arch and
	header were deleted by hand in Studio while its stand and prompt were
	kept - a rebuild through the full path put them straight back, which was
	exactly the opposite of what the manual pass intended.
]]
local function terminal(
	model: Model,
	position: Vector3,
	promptName: string,
	promptText: string,
	objectText: string,
	bare: boolean?
)
	if not bare then
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
	end -- closes `if not bare`

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
--[[
	=====================================================================
	INTERIOR PROPS
	=====================================================================

	This is the fix for "there are weird/random objects inside them that
	don't really make sense".

	THE PROBLEM IT REPLACES. Every single object a player could actually
	look at inside a building was the same primitive: an ACCENT_COLOR neon
	CUBE. Shop merchandise was a 0.8 cube. Aisle stock was a 0.9 cube.
	The featured display was a 1.2 cube. The Tutorial's "Chair" was a 1.5
	cube. The Daily Rewards trophies were neon balls floating 1.95 studs
	above their pedestals with nothing holding them up. So walking into the
	shop showed you thirty-two identical glowing boxes on shelves - which
	reads as placeholder geometry, not as stock.

	THE FIX. Props are now built from a small vocabulary of recognisable
	SHAPES (crate, carton, bottle, canister, orb) in a range of muted goods
	colours, so a shelf carries an assortment of things rather than a row of
	clones. Nothing here adds objects for the sake of filling space: the
	counts are the same as before, it is the identity of each object that
	changed.

	Colours are deliberately NOT ACCENT_COLOR. Reserving the theme accent
	for screens, trim and interaction points is what lets a player tell at a
	glance which things in the room they can actually use - when the
	merchandise glowed in exactly the same neon as the terminal, nothing
	read as interactive.
]]
local GOODS_TINTS = {
	Color3.fromRGB(196, 142, 74), -- kraft / cardboard
	Color3.fromRGB(122, 148, 168), -- pale steel
	Color3.fromRGB(150, 82, 74), -- clay red
	Color3.fromRGB(96, 128, 108), -- muted green
	Color3.fromRGB(168, 160, 132), -- sand
	Color3.fromRGB(108, 96, 132), -- dusty violet
}

--[[
	Places `count` assorted goods in a row centred on `center`, spread
	across `spanX` studs and resting ON the surface at center.Y (each shape
	is offset up by half its own height, so nothing floats and nothing sinks
	into the shelf).
]]
local function stockGoods(model: Model, rng: Random, name: string, center: Vector3, spanX: number, count: number)
	for n = 1, count do
		-- Evenly spaced along the run, with a little jitter so the row isn't
		-- mechanically regular.
		local slot = if count == 1 then 0.5 else (n - 1) / (count - 1)
		local offsetX = (slot - 0.5) * spanX + rng:NextNumber(-0.12, 0.12)
		local offsetZ = rng:NextNumber(-0.15, 0.15)
		local tint = GOODS_TINTS[rng:NextInteger(1, #GOODS_TINTS)]
		local roll = rng:NextNumber()

		if roll < 0.34 then
			-- Stacked crate: a squat box, occasionally double-stacked.
			local h = rng:NextNumber(0.55, 0.8)
			local w = rng:NextNumber(0.7, 0.95)
			PartUtils.CreatePart({
				name = name,
				size = Vector3.new(w, h, w * 0.85),
				cframe = CFrame.new(center + Vector3.new(offsetX, h / 2, offsetZ))
					* CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0),
				material = Enum.Material.WoodPlanks,
				color = tint,
				canCollide = false,
				parent = model,
			})
			if rng:NextNumber() < 0.4 then
				local h2 = rng:NextNumber(0.4, 0.6)
				PartUtils.CreatePart({
					name = name,
					size = Vector3.new(w * 0.85, h2, w * 0.7),
					cframe = CFrame.new(center + Vector3.new(offsetX, h + h2 / 2, offsetZ))
						* CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0),
					material = Enum.Material.WoodPlanks,
					color = GOODS_TINTS[rng:NextInteger(1, #GOODS_TINTS)],
					canCollide = false,
					parent = model,
				})
			end
		elseif roll < 0.62 then
			-- Bottle / canister: an upright cylinder with a small cap, the
			-- silhouette that most obviously is not a box.
			local h = rng:NextNumber(0.9, 1.3)
			local d = rng:NextNumber(0.34, 0.5)
			PartUtils.CreatePart({
				name = name,
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(h, d, d),
				cframe = CFrame.new(center + Vector3.new(offsetX, h / 2, offsetZ)) * CFrame.Angles(0, 0, math.rad(90)),
				material = Enum.Material.Glass,
				color = tint,
				transparency = 0.25,
				canCollide = false,
				parent = model,
			})
			PartUtils.CreatePart({
				name = name,
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(0.16, d * 0.62, d * 0.62),
				cframe = CFrame.new(center + Vector3.new(offsetX, h + 0.06, offsetZ)) * CFrame.Angles(0, 0, math.rad(90)),
				material = FURNITURE_MATERIAL,
				color = FURNITURE_COLOR,
				canCollide = false,
				parent = model,
			})
		elseif roll < 0.85 then
			-- Tall carton: a narrow upright box, e.g. a packaged product.
			local h = rng:NextNumber(1.0, 1.45)
			PartUtils.CreatePart({
				name = name,
				size = Vector3.new(rng:NextNumber(0.45, 0.62), h, rng:NextNumber(0.3, 0.42)),
				cframe = CFrame.new(center + Vector3.new(offsetX, h / 2, offsetZ))
					* CFrame.Angles(0, rng:NextNumber(-0.25, 0.25), 0),
				material = Enum.Material.SmoothPlastic,
				color = tint,
				canCollide = false,
				parent = model,
			})
		else
			-- Orb in a cradle: the one genuinely "special" item, and the only
			-- prop that still glows - so a rare accent read rather than the
			-- default one.
			local d = rng:NextNumber(0.5, 0.7)
			PartUtils.CreatePart({
				name = name,
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(0.14, d * 0.9, d * 0.9),
				cframe = CFrame.new(center + Vector3.new(offsetX, 0.07, offsetZ)) * CFrame.Angles(0, 0, math.rad(90)),
				material = FURNITURE_MATERIAL,
				color = FURNITURE_COLOR,
				canCollide = false,
				parent = model,
			})
			PartUtils.CreatePart({
				name = name,
				shape = Enum.PartType.Ball,
				size = Vector3.new(d, d, d),
				position = center + Vector3.new(offsetX, 0.14 + d / 2, offsetZ),
				material = Enum.Material.Neon,
				color = ACCENT_COLOR,
				transparency = 0.25,
				canCollide = false,
				parent = model,
			})
		end
	end
end

--[[
	A real, sittable chair - replaces the 1.5-stud cubes that were named
	"Chair" and "DataStationBench" but were plain Parts a player could
	neither sit on nor recognise as furniture. Faces `yaw` degrees.
]]
local function buildChair(model: Model, position: Vector3, yaw: number, name: string)
	local cf = CFrame.new(position) * CFrame.Angles(0, math.rad(yaw), 0)
	local seatH = 1.6

	PartUtils.CreatePart({
		className = "Seat",
		name = name,
		size = Vector3.new(2, 0.35, 1.9),
		cframe = cf * CFrame.new(0, seatH, 0),
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		parent = model,
	})
	-- Backrest on the Back (+Z) side, behind a player facing the seat's
	-- Front/-Z direction - same convention as Seating.lua's bench.
	PartUtils.CreatePart({
		name = name .. "Back",
		size = Vector3.new(2, 1.9, 0.25),
		cframe = cf * CFrame.new(0, seatH + 0.95, 0.83),
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		canCollide = false,
		parent = model,
	})
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			PartUtils.CreatePart({
				name = name .. "Leg",
				size = Vector3.new(0.22, seatH, 0.22),
				cframe = cf * CFrame.new(sx * 0.8, seatH / 2, sz * 0.75),
				material = FURNITURE_MATERIAL,
				color = FURNITURE_COLOR,
				canCollide = false,
				parent = model,
			})
		end
	end
end

--[[
	FEATURE SCREEN.

	The single large display that IS each building's interior.

	Every lobby building was previously furnished with props - shelves,
	counters, monitor banks, desks, pedestals - none of which did anything.
	The rooms are now deliberately EMPTY except for one big screen on the back
	wall carrying that building's one feature, plus seating only where a
	player actually needs to sit and read.

	Sized from the room rather than fixed, so it fills the back wall on every
	building regardless of footprint, and mounted low enough to be readable
	standing in the doorway.

	The returned part is tagged, which is how the client controllers find it
	(see RivalBoardController, TutorialScreenController, ShopFeaturedController).
	The SurfaceGui itself is built client-side; this is just the surface.
]]
local function buildFeatureScreen(def, model: Model, partName: string, tagName: string): BasePart
	local basePos = def.position
	local halfZ = def.size.Y / 2

	--[[
		SIZED WITH REAL CEILING CLEARANCE.

		This was `math.min(def.height - 7, 16)` with the centre at `height/2 + 4`,
		which put the screen top at exactly `def.height - 3` and the FRAME top
		(height + 1) at `def.height - 2.5`. Interior headroom is `def.height - 1`,
		so the frame cleared the ceiling by half a stud - it scaled with the room
		but never actually gained clearance, so raising ceilings alone would not
		have fixed it.

		Now reserved explicitly: 4.5 studs below the panel for the sill, and
		CEILING_GAP above the frame. The screen takes whatever is left, capped at
		18 so a tall room does not produce an absurd panel.
	]]
	local CEILING_GAP = 6 -- studs of clear ceiling above the frame
	local SILL = 4.5 -- studs from floor to the bottom of the panel
	local interiorHeight = def.height - 1

	local width = math.min(def.size.X - 6, 30)
	local height = math.clamp(interiorHeight - SILL - CEILING_GAP - 1, 8, 18)
	local centreY = SILL + height / 2
	local wallZ = -halfZ + WALL_THICKNESS + 0.4

	local screen = PartUtils.CreatePart({
		name = partName,
		size = Vector3.new(width, height, 0.5),
		position = basePos + Vector3.new(0, centreY, wallZ),
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(14, 16, 22),
		canCollide = false,
		parent = model,
	})
	CollectionService:AddTag(screen, tagName)

	-- Thin lit surround, so the panel reads as a powered display rather than
	-- a dark rectangle painted on the wall.
	PartUtils.CreatePart({
		name = partName .. "Frame",
		size = Vector3.new(width + 1, height + 1, 0.3),
		position = basePos + Vector3.new(0, centreY, wallZ - 0.25),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	return screen
end

--[[
	SIDE-WALL FEATURE SCREEN.

	The same panel as buildFeatureScreen, mounted on a LEFT (-X) or RIGHT (+X)
	wall instead of the back one. Used by the Tutorial room, which presents a
	single topic across three surfaces at once - description on the left,
	map image and clip in the centre, tips on the right - so a seated player
	takes in the whole topic by turning their head rather than paging three
	times.

	`side` is -1 for the left wall or +1 for the right, taken from the point
	of view of a player who has walked in and is facing the back wall (they
	enter from +Z looking toward -Z, so their left hand is -X).

	ROTATION. A Part's SurfaceGui here renders on its Back face, which is
	local +Z. Yawing the part by side * -90 degrees turns that face to point
	inward across the room: -90 sends +Z to +X for the left wall, +90 sends it
	to -X for the right. The part's local X then runs along the room's DEPTH,
	which is why `width` below is measured from def.size.Y rather than
	def.size.X - a side wall is as long as the room is deep.

	Height and centre height are computed exactly as buildFeatureScreen does,
	so all three panels line up as one continuous band around the room rather
	than three panels at three different heights.
]]
local function buildSideScreen(def, model: Model, partName: string, tagName: string, side: number): BasePart
	local basePos = def.position
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2

	-- Along the wall = room depth. Matches the back panel's height exactly.
	local width = math.min(def.size.Y - 6, 26)
	local height = math.min(def.height - 7, 16)
	local centreY = height / 2 + 4

	-- Sit the panel slightly forward of centre so it stays beside the seating
	-- rather than behind it, and remains readable from the front row.
	local alongZ = -halfZ * 0.15
	local wallX = side * (halfX - WALL_THICKNESS - 0.4)
	local yaw = side * -90

	local screen = PartUtils.CreatePart({
		name = partName,
		size = Vector3.new(width, height, 0.5),
		position = basePos + Vector3.new(wallX, centreY, alongZ),
		orientation = Vector3.new(0, yaw, 0),
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(14, 16, 22),
		canCollide = false,
		parent = model,
	})
	CollectionService:AddTag(screen, tagName)

	-- Frame sits fractionally closer to the wall than the panel, so the lit
	-- surround reads as a bezel behind the screen rather than in front of it.
	PartUtils.CreatePart({
		name = partName .. "Frame",
		size = Vector3.new(width + 1, height + 1, 0.3),
		position = basePos + Vector3.new(side * (halfX - WALL_THICKNESS - 0.15), centreY, alongZ),
		orientation = Vector3.new(0, yaw, 0),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	return screen
end

--[[
	SHOP: Featured Item of the Day.

	Stripped to the screen, a full-height preview column showing the featured
	item's colour at scale, and the purchase terminal. The shelves, aisle
	islands, counter, register and display cases are gone - they were scenery
	around a terminal, and the catalogue itself lives in the Shop UI.
]]
function BuildingInteriors.FurnishShop(def, model: Model)
	local basePos = def.position
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2

	if not CUSTOM_EXTERIOR_THEMES[CURRENT_THEME_ID] then
		addShopIdentity(def, model)
	end

	buildFeatureScreen(def, model, "FeaturedItemBoard", "FeaturedItemBoard")

	--[[
		The tall tinted preview column (FeaturedPreviewBase plinth +
		FeaturedPreviewShaft neon cylinder) that used to stand here is
		REMOVED (BuildVersion 22) - reported as an unwanted glowing beam
		roughly double a character's height inside every Shop building.
		ShopFeaturedController's matching shaft-tint code is removed too.
		The featured item's colour is still shown via the FeaturedItemBoard
		wall screen above.
	]]

	-- Purchase terminal - centered against the back wall now that there is
	-- no preview column to keep clear of.
	terminal(model, basePos + Vector3.new(-halfX * 0.85, 0, -halfZ * 0.15), "ShopTerminalPrompt", "Open Shop", "Shop", true)

	--[[
		SHOP SIDE (BuildVersion 31): mirrors the Rewards side below exactly -
		"the open shop screen on the left side of the shop... make it the
		same one that is on the right side for the open rewards". Same
		buildSideScreen() panel, same terminal() helper, just on the LEFT
		(-X) wall instead of the right, labelled "OPEN SHOP" instead of
		"OPEN REWARDS", and tinted with this file's own ACCENT_COLOR rather
		than the Boundless gold used for the Rewards sign, so the two reads
		as the Shop's own colour vs. the Rewards side's colour rather than
		identical twins.
	]]
	local shopBoard = buildSideScreen(def, model, "ShopOpenBoard", "ShopOpenBoard", -1)
	local shopBoardGui = Instance.new("SurfaceGui")
	shopBoardGui.Name = "ShopOpenBoardGui"
	shopBoardGui.Face = Enum.NormalId.Back
	shopBoardGui.LightInfluence = 0
	shopBoardGui.Parent = shopBoard
	local shopBoardBg = Instance.new("Frame")
	shopBoardBg.Size = UDim2.fromScale(1, 1)
	shopBoardBg.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
	shopBoardBg.BorderSizePixel = 0
	shopBoardBg.Parent = shopBoardGui
	local shopBoardLabel = Instance.new("TextLabel")
	shopBoardLabel.Size = UDim2.new(1, -20, 1, -20)
	shopBoardLabel.Position = UDim2.fromOffset(10, 10)
	shopBoardLabel.BackgroundTransparency = 1
	shopBoardLabel.Font = Enum.Font.GothamBlack
	shopBoardLabel.TextScaled = true
	shopBoardLabel.TextColor3 = ACCENT_COLOR
	shopBoardLabel.TextWrapped = true
	shopBoardLabel.Text = "OPEN\nSHOP"
	shopBoardLabel.Parent = shopBoardBg

	--[[
		REWARDS SIDE (BuildVersion 22): reward-only cosmetics get their own
		physical presence on the opposite side of the room from the Shop
		terminal, mirroring its presentation - a big wall sign plus a stand
		of its own, rather than only being reachable through the Shop panel's
		Rewards toggle. Uses the SAME terminal() helper and the SAME
		buildSideScreen() panel every other big wall screen in this file
		uses, just on the right (+X) wall instead of the back one, and with
		a static "OPEN REWARDS" label built directly here rather than a
		client controller - there is no daily-rotating content to drive, so
		unlike FeaturedItemBoard this needs no ShopFeaturedController-style
		Script at all.
	]]
	local rewardsBoard = buildSideScreen(def, model, "RewardsBoard", "RewardsBoard", 1)
	local rewardsGui = Instance.new("SurfaceGui")
	rewardsGui.Name = "RewardsBoardGui"
	rewardsGui.Face = Enum.NormalId.Back
	rewardsGui.LightInfluence = 0
	rewardsGui.Parent = rewardsBoard
	local rewardsBg = Instance.new("Frame")
	rewardsBg.Size = UDim2.fromScale(1, 1)
	rewardsBg.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
	rewardsBg.BorderSizePixel = 0
	rewardsBg.Parent = rewardsGui
	local rewardsLabel = Instance.new("TextLabel")
	rewardsLabel.Size = UDim2.new(1, -20, 1, -20)
	rewardsLabel.Position = UDim2.fromOffset(10, 10)
	rewardsLabel.BackgroundTransparency = 1
	rewardsLabel.Font = Enum.Font.GothamBlack
	rewardsLabel.TextScaled = true
	rewardsLabel.TextColor3 = CosmeticsConfig.RARITY_COLORS.Boundless
	rewardsLabel.TextWrapped = true
	rewardsLabel.Text = "OPEN\nREWARDS"
	rewardsLabel.Parent = rewardsBg

	-- Rewards terminal, mirrored to the opposite side from the Shop
	-- terminal - triggering it opens the same Shop panel already used for
	-- purchasing, switched straight to its Rewards view (see
	-- ShopUIController.client.lua's RewardsTerminalPrompt wiring).
	terminal(model, basePos + Vector3.new(halfX * 0.85, 0, -halfZ * 0.15), "RewardsTerminalPrompt", "Open Rewards", "Rewards", true)
end

--[==[ SUPERSEDED - the old Shop fit-out (shelves, aisle islands, counter,
	register, display cases and goods). Removed as part of the blank-room
	pass: none of it was interactive, and the room's purpose is now the
	featured-item screen above.

	A leveled long-bracket is used because the block below contains its own
	long comments, and Lua long comments do not nest.

	-- Deterministic per-building, so the shop's stock is identical on every
	-- rebuild and on every map that has one - same seeding convention the
	-- exterior builders use.
	local rng = Random.new(math.floor(basePos.X * 131 + basePos.Z * 977))

	--[[
		FEATURED ITEM OF THE DAY - the reason to walk into the Shop.

		A display stand carrying one cosmetic, rotating daily: a board with the
		item's name, category, description and price, and a full-height preview
		column beside it tinted to that item's previewColor so you can see the
		colour at scale before spending on it. The bottom-bar Shop button shows
		the catalogue as a list of small swatches; this shows one item properly.

		DELIBERATELY THE SIMPLE VERSION. It is a SPOTLIGHT, not a discount: no
		price is changed, no purchase happens here, and no server code is
		involved. Buying still goes through the existing Shop terminal and
		ShopSystem exactly as before.

		That matters because a discounted daily deal would mean touching
		ShopSystem's purchase validation - live economy code where a mistake
		lets players buy at the wrong price. A display-only spotlight gets most
		of the "come and look" value with none of that risk.

		Which item is featured is derived from the UTC date on the client (see
		ShopFeaturedController), so every player sees the same item on the same
		day without needing a remote or any stored state.
	]]
	local featuredBoard = PartUtils.CreatePart({
		name = "FeaturedItemBoard",
		size = Vector3.new(math.min(def.size.X - 14, 13), 8, 0.5),
		position = basePos + Vector3.new(-halfX * 0.34, 8.5, -halfZ + WALL_THICKNESS + 0.4),
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(16, 18, 26),
		canCollide = false,
		parent = model,
	})
	CollectionService:AddTag(featuredBoard, "FeaturedItemBoard")

	PartUtils.CreatePart({
		name = "FeaturedItemBoardFrame",
		size = Vector3.new(math.min(def.size.X - 14, 13) + 1, 9.2, 0.3),
		position = basePos + Vector3.new(-halfX * 0.34, 8.5, -halfZ + WALL_THICKNESS + 0.15),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	-- Preview column: a plinth with a tall tinted shaft above it, recoloured
	-- by the client to the featured item's previewColor.
	local previewX = halfX * 0.34
	PartUtils.CreateDisc({
		name = "FeaturedPreviewBase",
		diameter = 5,
		thickness = 0.8,
		position = basePos + Vector3.new(previewX, 0.4, -halfZ * 0.55),
		material = Enum.Material.Metal,
		color = Color3.fromRGB(52, 56, 68),
		canCollide = false,
		parent = model,
	})
	local previewShaft = PartUtils.CreatePart({
		name = "FeaturedPreviewShaft",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(9, 3, 3),
		cframe = CFrame.new(basePos + Vector3.new(previewX, 5.3, -halfZ * 0.55)) * CFrame.Angles(0, 0, math.rad(90)),
		material = Enum.Material.Neon,
		color = ACCENT_COLOR,
		transparency = 0.2,
		canCollide = false,
		parent = model,
	})
	CollectionService:AddTag(previewShaft, "FeaturedPreviewShaft")

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
				-- Assorted stock resting ON the shelf board (shelf is 0.25
				-- thick, so its top face is at shelfY + 0.125 and stockGoods
				-- seats each item up from there by half its own height). Three
				-- varied goods per board instead of one identical neon cube.
				stockGoods(
					model,
					rng,
					"ShelfItem",
					basePos + Vector3.new(side * (halfX - 2.1), shelfY + 0.125, offsetZ),
					2.2,
					3
				)
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
		-- Goods along the TOP of each island (the island is 4 tall, so its
		-- deck is at y=4), two runs offset either side of the centreline so
		-- the island is stocked from both browsing aisles - the same
		-- double-sided read as before, but with real merchandise.
		for _, itemOffsetZ in ipairs({ -halfZ * 0.25, 0, halfZ * 0.25 }) do
			for _, faceX in ipairs({ -1, 1 }) do
				stockGoods(
					model,
					rng,
					"AisleItem",
					basePos + Vector3.new(aisleX + faceX * 0.55, 4, itemOffsetZ + halfZ * 0.05),
					0.9,
					2
				)
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
		-- The featured item on each plinth, under a glass case - this is the
		-- "look but don't buy yet" showcase, so unlike the open shelving the
		-- goods here are deliberately presented behind glass.
		stockGoods(model, rng, "DisplayItem", basePos + Vector3.new(x, 3, -halfZ * 0.35), 0.9, 1)
		PartUtils.CreatePart({
			name = "DisplayCase",
			size = Vector3.new(1.7, 2, 1.7),
			position = basePos + Vector3.new(x, 4, -halfZ * 0.35),
			material = Enum.Material.Glass,
			color = Color3.fromRGB(210, 225, 235),
			transparency = 0.72,
			canCollide = false,
			parent = model,
		})
		PartUtils.CreatePart({
			name = "DisplayCaseTrim",
			size = Vector3.new(1.85, 0.14, 1.85),
			position = basePos + Vector3.new(x, 5.05, -halfZ * 0.35),
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

]==]

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
--[[
	DAILY REWARDS: Streak Vault.

	The screen carries the full seven-day claim ring, and the seven plinths
	below are that ring made PHYSICAL - a reward path you walk along, each
	lit by state (collected / claim now / upcoming) by the client.

	The path is the one thing kept from the old fit-out's intent: it is the
	building's actual content, not decoration. The milestone wall panels,
	pedestals and trophies are gone - they were blank glowing squares and
	props that displayed nothing.
]]
function BuildingInteriors.FurnishRewards(def, model: Model)
	local basePos = def.position
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2

	if not CUSTOM_EXTERIOR_THEMES[CURRENT_THEME_ID] then
		addRewardsIdentity(def, model)
	end

	--[[
		LIFETIME REWARDS now takes the back wall - previously Daily's spot
		(the old StreakVaultBoard). Daily's entire presentation moves to the
		floor below. Rendered by RivalBoardController.client.lua, same as
		before - only which wall it's mounted on changed (buildFeatureScreen,
		the back-wall helper, instead of buildSideScreen).
	]]
	buildFeatureScreen(def, model, "LifetimeRewardsBoard", "LifetimeRewardsBoard")

	--[[
		DAILY REWARDS FLOOR RUNWAY (third pass - reading direction + sizing):
		ONE continuous floor screen, turned 90 degrees flat so it reads as a
		rug/runway you walk along, keeping the same rough outline the old
		wall screen had (title up top, status under it, day slots at the
		bottom) but rotated into the floor plane rather than re-designed from
		scratch:

		  - "Top of the screen" (title + status) is nearest the BACK WALL
		    (-Z, right where the old vertical wall screen actually stood, and
		    right beside the Lifetime board that now occupies that wall).
		  - "Bottom of the screen" (the day slots) is nearest the DOOR (+Z) -
		    matching the old screen's own top-to-bottom order (title, status,
		    slots), just read while walking from far (back wall) to close
		    (door) instead of scanned top-to-bottom on a vertical panel.
		  - Text within each segment still reads left-to-right, ordinary
		    English direction - only the FAR-TO-CLOSE progression down the
		    room is what changed from a normal screen.

		FIT TO THE FLOOR: the three segments' depths are scaled together so
		they always fill the room's actual usable depth (leaving clearance at
		the back wall and the door) rather than a fixed size that might float
		in empty space or overflow in a smaller room.

		HEIGHT FIX (kept from the previous pass): every segment is bottom-
		aligned to this room's actual Floor surface (measured directly - this
		room's Floor part top sits at basePos.Y + FLOOR_SURFACE_Y, not at
		basePos.Y itself), so they sit ON TOP of the real floor as a thin
		walkable overlay. The very first version of this runway sat slightly
		BELOW the real floor - confirmed via GetTouchingParts only ever
		reporting the room's plain Floor part, never a tile - which silently
		broke touch-to-claim.

		No terminal, no standing boards, no side-offset plinths/caps - Daily
		Rewards is reachable ONLY by walking over this floor now (no
		bottom-bar button, no E-press terminal).
	]]
	local FLOOR_SURFACE_Y = 0.5 -- measured against this room's actual Floor part
	local DAYS = 7
	local tileWidth = math.min((halfX * 1.6) / DAYS, 5)
	local rowWidth = tileWidth * DAYS
	local runwayWidth = math.min(rowWidth + 4, halfX * 1.8)

	-- Natural (unscaled) depths for the three segments, kept in the same
	-- rough proportions the old wall screen used (title/status got roughly
	-- as much vertical room as the day-slot row did).
	local titleDepthNatural = 6
	local instructionDepthNatural = 3
	local tileDepthNatural = 5
	local totalNatural = titleDepthNatural + instructionDepthNatural + tileDepthNatural

	-- Usable depth: the room's full depth minus clearance at the back wall
	-- (so the title segment doesn't touch the Lifetime board's wall) and at
	-- the door (so nothing sits in the doorway itself).
	local backClearance = 3
	local doorClearance = 3
	local usableDepth = (halfZ * 2) - backClearance - doorClearance
	local depthScale = usableDepth / totalNatural

	local titleDepth = titleDepthNatural * depthScale
	local instructionDepth = instructionDepthNatural * depthScale
	local tileDepth = tileDepthNatural * depthScale

	-- Cursor starts at the back wall (-Z, "top of the screen") and walks
	-- toward the door (+Z, "bottom of the screen"), placing each segment
	-- flush against the previous one - far side to close side, matching
	-- the old screen's own top-to-bottom order.
	local cursorZ = -halfZ + backClearance

	-- ===== "Top of the screen": title + status (personalized - client-driven) =====
	local titleZ = cursorZ + titleDepth / 2
	local titleTile = PartUtils.CreatePart({
		name = "DailyRewardsTitleTile",
		size = Vector3.new(runwayWidth, 0.3, titleDepth),
		position = basePos + Vector3.new(0, FLOOR_SURFACE_Y + 0.15, titleZ),
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(16, 18, 26),
		canCollide = false,
		parent = model,
	})
	CollectionService:AddTag(titleTile, "DailyRewardsTitleTile")
	cursorZ += titleDepth

	-- ===== Middle: instruction (static text, built directly here) =====
	local instructionZ = cursorZ + instructionDepth / 2
	local instructionTile = PartUtils.CreatePart({
		name = "DailyRewardsInstructionTile",
		size = Vector3.new(runwayWidth, 0.3, instructionDepth),
		position = basePos + Vector3.new(0, FLOOR_SURFACE_Y + 0.15, instructionZ),
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(16, 18, 26),
		canCollide = false,
		parent = model,
	})
	local instructionGui = Instance.new("SurfaceGui")
	instructionGui.Face = Enum.NormalId.Top
	instructionGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	-- Canvas SWAPPED relative to the part's actual width/depth (this
	-- segment is wide and shallow physically) to match Face=Top's default
	-- axis mapping - confirmed empirically that fighting this any other way
	-- (e.g. rotating the TextLabel itself) makes the wrapping engine compute
	-- line-breaks in the narrow UNROTATED box, cramming the sentence into
	-- one word per line. Instead: build the content in NATURAL wide-format
	-- coordinates inside a wrapper sized to those natural dimensions, then
	-- rotate the WHOLE wrapper 90 as one rigid unit - the wrapper's own
	-- declared size (900x300, wide) is what the text-wrapping engine sees,
	-- giving the sentence plenty of room, and the ROTATED bounding box
	-- (300x900) exactly matches the swapped canvas, so nothing clips.
	instructionGui.CanvasSize = Vector2.new(300, 900)
	instructionGui.LightInfluence = 0
	instructionGui.Parent = instructionTile

	local instructionWrapper = Instance.new("Frame")
	instructionWrapper.AnchorPoint = Vector2.new(0.5, 0.5)
	instructionWrapper.Position = UDim2.fromScale(0.5, 0.5)
	instructionWrapper.Size = UDim2.fromOffset(900, 300)
	instructionWrapper.Rotation = 90
	instructionWrapper.BackgroundTransparency = 1
	instructionWrapper.Parent = instructionGui

	local instructionLabel = Instance.new("TextLabel")
	instructionLabel.Size = UDim2.new(1, -80, 1, -60)
	instructionLabel.Position = UDim2.fromOffset(40, 30)
	instructionLabel.BackgroundTransparency = 1
	instructionLabel.Font = Enum.Font.Gotham
	instructionLabel.TextScaled = true
	instructionLabel.TextWrapped = true
	instructionLabel.TextColor3 = Color3.fromRGB(200, 205, 220)
	instructionLabel.Text = "Run over the day to collect the reward"
	instructionLabel.Parent = instructionWrapper
	cursorZ += instructionDepth

	-- ===== "Bottom of the screen": seven day cells, nearest the door =====
	-- Day 1 (left, -X) through day 7 (right, +X) - FIXED positions, never
	-- reordered; only which cell is lit "today" changes.
	local dayRowZ = cursorZ + tileDepth / 2
	for day = 1, DAYS do
		local x = -rowWidth / 2 + (day - 0.5) * tileWidth
		local tile = PartUtils.CreatePart({
			name = ("StreakDayFloorPad%d"):format(day),
			-- Visible gap between tiles (was 0.15, nearly touching - too
			-- cramped to read as 7 distinct cards) so each day reads as its
			-- own clearly separated card, not one continuous slab.
			size = Vector3.new(tileWidth - 1, 0.3, tileDepth),
			position = basePos + Vector3.new(x, FLOOR_SURFACE_Y + 0.15, dayRowZ),
			material = Enum.Material.SmoothPlastic,
			color = Color3.fromRGB(20, 22, 30),
			canCollide = false,
			parent = model,
		})
		tile:SetAttribute("StreakDay", day)
		CollectionService:AddTag(tile, "StreakDayFloorPad")
	end
end

--[===[ SUPERSEDED - the old Daily Rewards fit-out (milestone wall panels,
	centre pedestals, trophies and the blank ProgressionWall). Replaced by the
	streak screen and the physical streak path above.

	Level-3 bracket (--[===[ ... ) because the block below ALREADY contains a
	level-2 comment from an earlier cleanup pass; a level-2 opener here would
	be closed by it and leave real code exposed.


	--[[
		STREAK VAULT - the reason to walk into this building.

		A wall panel showing the full seven-day claim ring: which days you have
		already collected on this pass, which one is next, and what each day
		pays out. The bottom-bar Daily button opens the claim popup; this shows
		the whole cycle laid out at once, which the popup does not.

		Like the Rival Board, it is a SurfaceGui on a real part rather than a
		ScreenGui - a world surface cannot be mirrored onto the bottom bar, so
		being in the room is the only way to read it.

		No new server code backs this. DailyRewardsSystem already exposes
		"GetDailyRewardSnapshot", which returns the reordered seven-day track
		with each day's label and collected state, computed server-side from the
		player's profile. Adding a second source of truth for streak state would
		be a way for the vault and the popup to start disagreeing.
	]]
	local vaultWidth = math.min(def.size.X - 6, 22)
	local vault = PartUtils.CreatePart({
		name = "StreakVaultBoard",
		size = Vector3.new(vaultWidth, 10, 0.5),
		position = basePos + Vector3.new(0, 9, -halfZ + WALL_THICKNESS + 0.4),
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(16, 18, 26),
		canCollide = false,
		parent = model,
	})
	CollectionService:AddTag(vault, "StreakVaultBoard")

	PartUtils.CreatePart({
		name = "StreakVaultFrame",
		size = Vector3.new(vaultWidth + 1.2, 11.2, 0.3),
		position = basePos + Vector3.new(0, 9, -halfZ + WALL_THICKNESS + 0.15),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	if not CUSTOM_EXTERIOR_THEMES[CURRENT_THEME_ID] then
		addRewardsIdentity(def, model)
	end

	-- Side-wall milestone screens - small floating panels suggesting
	-- individual reward tiers, flanking the walk from door to terminal.
	--[[
		THE STREAK RING AS PHYSICAL GEOMETRY.

		Seven day-plinths in a row down the room, one per day of the claim
		cycle, each with its own small BillboardGui showing the day number, what
		it pays and whether it is already collected. You walk PAST your streak
		rather than reading it as a list - the wall panel above gives the
		overview, these are the thing you physically move along.

		The plinths are laid out along the room's depth and offset to one side of
		the centre aisle, so the walk from the door to the terminal is never
		obstructed - the same clearance rule the Tutorial welcome desk needed.

		State comes from the same server snapshot the wall panel uses; the
		client controller drives both, so a plinth can never disagree with the
		panel two metres above it.
	]]
	local DAYS = 7
	for day = 1, DAYS do
		local t = (day - 1) / (DAYS - 1)
		local z = halfZ * 0.55 - t * (halfZ * 1.25)
		local x = -halfX * 0.55

		local plinth = PartUtils.CreatePart({
			name = ("StreakDayPlinth%d"):format(day),
			size = Vector3.new(3.2, 3.4, 3.2),
			position = basePos + Vector3.new(x, 1.7, z),
			material = FURNITURE_MATERIAL,
			color = FURNITURE_COLOR,
			parent = model,
		})
		plinth:SetAttribute("StreakDay", day)
		CollectionService:AddTag(plinth, "StreakDayPlinth")

		-- Lit cap: recoloured per state by the client (collected / next / later).
		local cap = PartUtils.CreateDisc({
			name = ("StreakDayCap%d"):format(day),
			diameter = 2.8,
			thickness = 0.45,
			position = basePos + Vector3.new(x, 3.6, z),
			material = Enum.Material.Neon,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
		cap:SetAttribute("StreakDay", day)
		CollectionService:AddTag(cap, "StreakDayCap")
	end

	--[[
		MILESTONE PEDESTALS AND TROPHIES REMOVED. Reconciled with a manual pass
		in Studio where all three pedestals and their trophies were deleted by
		hand - verified by inspection (no MilestonePedestal or MilestoneTrophy*
		parts remain in the built room).

		Removed from source rather than left in, so LobbyBuilder.Rebuild()
		reproduces the deletion instead of putting them back.

		They also no longer had a job: the seven StreakDayPlinths above are the
		room's physical walk-past progression, and the Streak Vault panel is its
		summary. Three trophies in the middle of the aisle were the older idea
		of the same thing, standing in the way of the newer one.
	]]

	--[==[ ORPHANED TROPHY BODY - dead with the pedestals removed above.
		Commented out with a leveled long-bracket because the block contains its
		own nested long comments, which a plain double-bracket cannot survive.
		Its loop variables (i, offsetZ, trophyScale, isCentre, bowl) no longer
		exist, so leaving it live would error at build time.

		--[[
			An actual TROPHY standing on the pedestal, not a neon sphere

			The pedestal is 2.5 tall, so its top face is at y=2.5; every piece
			below stacks up from there and physically touches the piece under
			it. Built as base -> stem -> bowl -> handles, which is the
			silhouette that actually reads as "trophy" - the previous floating
			ball read as an unexplained energy orb, which is exactly the kind of
			object that doesn't make sense in a rewards hall.
		]]
		local isCentre = i == 2
		local trophyTint = if isCentre then Color3.fromRGB(255, 200, 62) else Color3.fromRGB(186, 190, 198)
		local trophyScale = if isCentre then 1.25 else 1

		PartUtils.CreateDisc({
			name = "MilestoneTrophyBase" .. i,
			diameter = 1.5 * trophyScale,
			thickness = 0.35,
			position = basePos + Vector3.new(0, 2.68, offsetZ),
			material = Enum.Material.Marble,
			color = Color3.fromRGB(48, 46, 52),
			canCollide = false,
			parent = model,
		})
		PartUtils.CreatePart({
			name = "MilestoneTrophyStem" .. i,
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(0.85 * trophyScale, 0.28, 0.28),
			cframe = CFrame.new(basePos + Vector3.new(0, 3.28 * 1, offsetZ)) * CFrame.Angles(0, 0, math.rad(90)),
			material = Enum.Material.Metal,
			color = trophyTint,
			canCollide = false,
			parent = model,
		})
		local bowl = PartUtils.CreatePart({
			name = "MilestoneTrophyCup" .. i,
			shape = Enum.PartType.Ball,
			size = Vector3.new(1.25 * trophyScale, 1.1 * trophyScale, 1.25 * trophyScale),
			position = basePos + Vector3.new(0, 4.15, offsetZ),
			material = Enum.Material.Metal,
			color = trophyTint,
			canCollide = false,
			parent = model,
		})
		for _, side in ipairs({ -1, 1 }) do
			PartUtils.CreateDisc({
				name = "MilestoneTrophyHandle" .. i,
				diameter = 0.62 * trophyScale,
				thickness = 0.13,
				position = basePos + Vector3.new(side * 0.72 * trophyScale, 4.25, offsetZ),
				material = Enum.Material.Metal,
				color = trophyTint,
				canCollide = false,
				parent = model,
			})
		end
		-- Only the centre (gold) trophy is lit, so the row has a clear focal
		-- point rather than three equally glowing objects.
		if isCentre then
			local trophyLight = Instance.new("PointLight")
			trophyLight.Color = trophyTint
			trophyLight.Range = 12
			trophyLight.Brightness = 1.2
			trophyLight.Shadows = true
			trophyLight.Parent = bowl
		end
	end
	]==]

	--[[
		PROGRESSION WALL REMOVED. Another blank accent slab across the back
		wall, and it is where the Streak Vault board now sits - reconciled with
		the manual Studio pass, which deleted it.
	]]
	--[[
		BARE terminal: stand and prompt only. The dais, arch and header were
		deleted by hand in Studio here; rebuilding them would undo that.
	]]
	terminal(model, basePos + Vector3.new(0, 0, -halfZ + 5), "DailyRewardsTerminalPrompt", "Claim Daily Reward", "Daily Rewards", true)
end

]===]

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
--[[
	STATISTICS: Rival Board.

	The screen and two seats to read it from. Nothing else.

	The old fit-out - six wall monitors, two DataStation desks with their own
	screens, and a full-wall blank StatScreen - displayed nothing at all. The
	Rival Board is the room's entire purpose, so it gets the whole back wall.
]]
function BuildingInteriors.FurnishStatistics(def, model: Model)
	local basePos = def.position
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2

	if not CUSTOM_EXTERIOR_THEMES[CURRENT_THEME_ID] then
		addStatisticsIdentity(def, model)
	end

	buildFeatureScreen(def, model, "RivalBoard", "RivalBoard")

	-- Two seats facing the screen (yaw 180 = facing -Z, the back wall).
	-- Set well back so a seated player has the whole panel in view.
	for _, seatX in ipairs({ -3.5, 3.5 }) do
		buildChair(model, basePos + Vector3.new(seatX, 0, halfZ * 0.3), 180, "ViewingSeat")
	end
end

--[==[ SUPERSEDED - the old Statistics fit-out (wall monitors, DataStation
	desks and the blank full-wall StatScreen). None of it displayed anything;
	the Rival Board above is the room's content.


	--[[
		RIVAL BOARD - the reason to actually walk into this building.

		A large panel mounted on the back wall, directly facing the doorway, so
		it is the first thing in view on entering. RivalBoardSystem (server)
		supplies the data and RivalBoardController (client) fills the
		SurfaceGui; this only builds the physical surface and tags it so the
		controller can find it on any map without hardcoded paths.

		It is a world surface rather than a ScreenGui deliberately - see
		RivalBoardSystem's header. A SurfaceGui cannot be shown on the bottom
		bar, which is exactly the property that stops this building being
		redundant with the Stats button.

		Mounted at eye height on the back wall's INNER face (basePos.Z - halfZ
		plus the wall thickness), rotated to face +Z toward the entrance.
	]]
	local boardWidth = math.min(def.size.X - 6, 22)
	local board = PartUtils.CreatePart({
		name = "RivalBoard",
		size = Vector3.new(boardWidth, 11, 0.5),
		position = basePos + Vector3.new(0, 9, -halfZ + WALL_THICKNESS + 0.4),
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(16, 18, 26),
		canCollide = false,
		parent = model,
	})
	CollectionService:AddTag(board, "RivalBoard")

	-- Lit frame so the panel reads as a powered display rather than a dark
	-- rectangle painted on the wall.
	PartUtils.CreatePart({
		name = "RivalBoardFrame",
		size = Vector3.new(boardWidth + 1.2, 12.2, 0.3),
		position = basePos + Vector3.new(0, 9, -halfZ + WALL_THICKNESS + 0.15),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	if not CUSTOM_EXTERIOR_THEMES[CURRENT_THEME_ID] then
		addStatisticsIdentity(def, model)
	end

	--[[
		DECLUTTERED. This room used to hold six wall monitors, two "DataStation"
		desks with their own screens, and a StatScreen - none of which did
		anything. They were furniture-shaped blocks standing in for a purpose
		the room did not have.

		The room now has exactly one job: the Rival Board above. So the fit-out
		is just seating placed to READ that board - two chairs on the centre
		line, set back from the wall and facing it. Everything a player sees in
		here is either the board, a way to look at the board, or the teleport
		terminal they arrived through.

		Seats face -Z (yaw 180 in buildChair's convention) because the board is
		mounted on the -Z back wall.
	]]
	for _, seatX in ipairs({ -3.5, 3.5 }) do
		buildChair(model, basePos + Vector3.new(seatX, 0, -halfZ * 0.05), 180, "ViewingSeat")
	end

	--[[
		NO TERMINAL IN THIS ROOM. Reconciled with a manual pass in Studio where
		the Statistics terminal (stand, arch and header) was deleted by hand -
		verified by inspection: the building now contains no ProximityPrompt at
		all, where every other terminal room still has one.

		Removed from source rather than rebuilt, so LobbyBuilder.Rebuild()
		reproduces the deletion instead of silently putting the terminal back.

		Nothing is lost by this: the room's purpose is the Rival Board, and the
		Stats overlay is still one click away on the bottom bar. The terminal
		was a second route to a panel that was already reachable.
	]]
end

]==]

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
--[[
	TUTORIAL: lecture room.

	The screen, two rows of seats facing it, and the paging pads. This is the
	one building where sitting down matters - the content is seven topics you
	read through at your own pace, so it is laid out as a small lecture room.

	The welcome desk, demo-question station and blank info panels are gone.
]]
function BuildingInteriors.FurnishTutorial(def, model: Model)
	local basePos = def.position
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2

	if not CUSTOM_EXTERIOR_THEMES[CURRENT_THEME_ID] then
		addTutorialIdentity(def, model)
	end

	local screen = buildFeatureScreen(def, model, "TutorialScreen", "TutorialScreen")
	local screenWidth = screen.Size.X
	local screenY = screen.Position.Y - basePos.Y

	--[[
		The two side walls. One topic is shown across all three panels at once:
		the centre carries the map image and its short looping clip, the left
		carries the topic's title and description, and the right carries its
		tips. Paging with either pad advances all three together, so they can
		never disagree about which topic is on show.

		Built here rather than inside buildFeatureScreen because the Tutorial is
		the only room that earns three surfaces - it is the one place a player
		sits and reads for several minutes. The Shop, Daily Rewards and
		Statistics rooms deliberately keep a single focal panel.
	]]
	buildSideScreen(def, model, "TutorialScreenLeft", "TutorialScreenLeft", -1)
	buildSideScreen(def, model, "TutorialScreenRight", "TutorialScreenRight", 1)

	--[[
		Paging pads, one either side of the screen at standing height.

		Physical click targets rather than GUI buttons, for the same reason the
		building signs use them: a transparent GuiButton over world space
		swallows clicks meant for anything behind it.
	]]
	for _, pad in
		ipairs({
			{ name = "TutorialPrevButton", x = -(screenWidth / 2 + 2), tag = "TutorialPrev" },
			{ name = "TutorialNextButton", x = screenWidth / 2 + 2, tag = "TutorialNext" },
		})
	do
		local part = PartUtils.CreatePart({
			name = pad.name,
			size = Vector3.new(2.8, 2.8, 0.6),
			position = basePos + Vector3.new(pad.x, screenY - 2, -halfZ + WALL_THICKNESS + 0.5),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
		CollectionService:AddTag(part, pad.tag)
		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 60
		click.Parent = part
	end

	-- Two rows of three, facing the screen on the -Z wall.
	for rowIndex, rowZ in ipairs({ -halfZ * 0.05, halfZ * 0.42 }) do
		for _, seatX in ipairs({ -4.5, 0, 4.5 }) do
			buildChair(model, basePos + Vector3.new(seatX, 0, rowZ), 180, ("LectureSeatR%d"):format(rowIndex))
		end
	end
end

--[==[ SUPERSEDED - the old Tutorial fit-out (welcome desk, demo question
	station, cube chairs and blank info panels). Replaced by the lecture room
	above.


	if not CUSTOM_EXTERIOR_THEMES[CURRENT_THEME_ID] then
		addTutorialIdentity(def, model)
	end

	--[[
		TUTORIAL WALL SCREEN - the reason to walk into this building.

		The same seven topics the bottom-bar Tutorial button shows, presented on
		a big screen you sit down in front of instead of in a popup over the
		game. The bottom-bar button is deliberately KEPT: this is an additional
		way to read the tutorial, not a replacement, so a player who just wants
		the text quickly is never forced to walk here.

		Content comes from ReplicatedStorage.Modules.TutorialTopicsConfig, which
		the overlay also reads - one source of text, two presentations.

		The screen is paged with two physical buttons flanking it, each carrying
		a ClickDetector. Physical click targets rather than GUI buttons for the
		same reason the building signs use them: a transparent GUI button laid
		over world space would swallow clicks meant for anything behind it.
	]]
	local screenWidth = math.min(def.size.X - 6, 22)
	local tutorialScreen = PartUtils.CreatePart({
		name = "TutorialScreen",
		size = Vector3.new(screenWidth, 11, 0.5),
		position = basePos + Vector3.new(0, 9, -halfZ + WALL_THICKNESS + 0.4),
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(16, 18, 26),
		canCollide = false,
		parent = model,
	})
	CollectionService:AddTag(tutorialScreen, "TutorialScreen")

	PartUtils.CreatePart({
		name = "TutorialScreenFrame",
		size = Vector3.new(screenWidth + 1.2, 12.2, 0.3),
		position = basePos + Vector3.new(0, 9, -halfZ + WALL_THICKNESS + 0.15),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	-- Paging buttons, one either side of the screen at standing height.
	for _, button in
		ipairs({
			{ name = "TutorialPrevButton", x = -(screenWidth / 2 + 1.6), tag = "TutorialPrev" },
			{ name = "TutorialNextButton", x = screenWidth / 2 + 1.6, tag = "TutorialNext" },
		})
	do
		local pad = PartUtils.CreatePart({
			name = button.name,
			size = Vector3.new(2.6, 2.6, 0.6),
			position = basePos + Vector3.new(button.x, 6, -halfZ + WALL_THICKNESS + 0.5),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
		CollectionService:AddTag(pad, button.tag)
		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 40
		click.Parent = pad
	end

	--[[
		Seating facing the screen, in two rows like a small lecture room. Seats
		face -Z (yaw 180 in buildChair's convention) because the screen is on
		the -Z back wall. Rows are set back far enough that a seated player has
		the whole screen in view rather than craning at it.
	]]
	for rowIndex, rowZ in ipairs({ -halfZ * 0.10, halfZ * 0.32 }) do
		for _, seatX in ipairs({ -4.5, 0, 4.5 }) do
			buildChair(model, basePos + Vector3.new(seatX, 0, rowZ), 180, ("LectureSeatR%d"):format(rowIndex))
		end
	end

	--[[
		NO TERMINAL IN THIS ROOM. Same manual-deletion reconciliation as the
		Statistics building - the Tutorial terminal was removed by hand in
		Studio (verified: no ProximityPrompt remains in this building), so it is
		removed from source too and a rebuild will not recreate it.

		The room's purpose is now the wall screen and its seating, and the
		bottom-bar Tutorial button still opens the overlay, so the terminal was
		a third route to content already available two other ways.
	]]
end

]==]

return BuildingInteriors

--[==[ REMOVED - old Tutorial walk-through layout, replaced by the wall screen
	and lecture seating above. A leveled long-bracket is used here because the
	block below contains its own long comments, and Lua long comments do NOT
	nest - a plain double-bracket comment would be closed by the first inner
	closing bracket and leave real code exposed after the return.

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
	-- Real chairs facing the demo screen, angled slightly inward the way
	-- seating around a lesson actually is. These used to be 1.5-stud cubes
	-- named "Chair" - not sittable, and not recognisable as furniture.
	for _, side in ipairs({ -1, 1 }) do
		buildChair(model, basePos + Vector3.new(side * 4, 0, 4), 180 - side * 18, "Chair")
	end

	-- Wall info-panels removed with the rest of the old walk-through layout:
	-- they were blank accent slabs implying information they never carried.
	terminal(model, basePos + Vector3.new(0, 0, -halfZ + 5), "TutorialTerminalPrompt", "Learn How to Play", "Tutorial")
end
]==]
