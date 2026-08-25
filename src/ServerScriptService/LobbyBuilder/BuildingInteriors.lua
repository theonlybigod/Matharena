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

local WALL_THICKNESS = 1
local MIN_DOOR_WIDTH = 8
local MAX_DOOR_WIDTH = 14

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
	local plateWidth = doorWidth + 6
	local platePart = PartUtils.CreatePart({
		name = "EntranceNamePlate",
		size = Vector3.new(plateWidth, 2.8, 0.4),
		position = basePos + Vector3.new(0, doorHeight + 1.9, halfZ + tunnelLength - 0.2),
		material = tunnelMaterial,
		color = tunnelColor,
		canCollide = false,
		parent = model,
	})
	local nameGui = Instance.new("SurfaceGui")
	nameGui.Face = Enum.NormalId.Back -- Back = +Z face, which faces the plaza/spawns (see addSign)
	nameGui.LightInfluence = 0
	nameGui.PixelsPerStud = 36
	nameGui.Parent = platePart

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 1)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextScaled = true
	nameLabel.Text = def.displayName or def.name or ""
	nameLabel.Parent = nameGui

	-- A pair of small accent lamps flanking the plate so it reads as lit
	-- signage rather than a plain placard, matching whichever theme this is.
	for _, side in ipairs({ -1, 1 }) do
		local lamp = PartUtils.CreatePart({
			name = "EntranceLamp",
			size = Vector3.new(0.5, 0.5, 0.5),
			position = basePos + Vector3.new(side * (plateWidth / 2 + 0.6), doorHeight + 1.9, halfZ + tunnelLength - 0.2),
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
	local halfDiag, domeRadius, collarTop, peakY = computeEnclosingEnvelope(def, 1.35, 0.62)
	local capHeight = peakY - collarTop
	local rng = Random.new(math.floor(basePos.X * 733 + basePos.Z * 271))
	local doorWidth = math.clamp(def.size.X * 0.22, MIN_DOOR_WIDTH, MAX_DOOR_WIDTH)
	local doorHeight = math.min(10, def.height - 4)

	-- Genuine stacked ice-brick construction: several tiers, each a RING
	-- OF INDIVIDUAL BRICK BLOCKS (not one smooth sphere/wrap) - every
	-- brick is a small rotated rectangular Part facing outward, tangent
	-- to its ring, so the building reads as hand-stacked ice blocks
	-- curving up into a dome - a genuinely custom-built structure, not a
	-- box with a shape wrapped around it.
	--
	-- Two zones (see computeEnclosingEnvelope above): a COLLAR of
	-- constant-radius brick rings from the ground up to the building's
	-- own roofline (so the box shell can never poke through), then a true
	-- quarter-circle DOME CAP only above that - the only part of the
	-- structure that actually curves inward, exactly like a real igloo's
	-- roof sitting on its own walls.
	local collarTierCount = 5
	local capTierCount = 5
	local tierCount = collarTierCount + capTierCount
	for tier = 1, tierCount do
		local tierY, tierRadius
		if tier <= collarTierCount then
			local collarFraction = (tier - 1) / collarTierCount
			tierY = collarTop * collarFraction
			tierRadius = domeRadius * (1 - collarFraction * 0.04) -- near-constant, a hair of taper for realism
		else
			local capFraction = (tier - collarTierCount) / capTierCount
			local angleFromTop = (math.pi / 2) * capFraction
			tierY = collarTop + capHeight * math.sin(angleFromTop)
			tierRadius = domeRadius * math.cos(angleFromTop)
		end

		if tierRadius < 1.5 then
			PartUtils.CreatePart({
				name = "DomeCap",
				size = Vector3.new(3, 2, 3),
				position = basePos + Vector3.new(0, tierY, 0),
				material = Enum.Material.Snow,
				color = Color3.fromRGB(240, 246, 251),
				shape = Enum.PartType.Ball,
				canCollide = false,
				parent = model,
			})
			continue
		end

		local brickHeight = peakY / tierCount * 1.4
		local brickWidth = math.max(3, tierRadius * 0.55)
		local brickCount = math.max(6, math.floor((2 * math.pi * tierRadius) / brickWidth))
		local isCollarTier = tier <= collarTierCount
		for b = 1, brickCount do
			local angle = (2 * math.pi / brickCount) * b + rng:NextNumber(-0.05, 0.05)

			-- Skip bricks inside the entrance notch on collar tiers only -
			-- this is what actually opens a walk-through archway into the
			-- dome instead of a fully-closed ring of ice bricks the tunnel
			-- dead-ends into. Cap tiers (above the roofline) stay complete
			-- since the crater/peak doesn't need an opening.
			if isCollarTier and isInEntranceNotch(angle, tierRadius, doorWidth) then
				continue
			end

			local brickPos = basePos + Vector3.new(math.sin(angle) * tierRadius, tierY, math.cos(angle) * tierRadius)
			PartUtils.CreatePart({
				name = ("IceBrickT%dB%d"):format(tier, b),
				size = Vector3.new(brickWidth * rng:NextNumber(0.85, 1.05), brickHeight, 1.4),
				cframe = CFrame.new(brickPos) * CFrame.Angles(0, angle, 0),
				material = WALL_MATERIAL,
				color = ROOFCAP_COLOR,
				canCollide = false,
				parent = model,
			})
		end

		-- A thin accent seam every other tier ties the dome into the
		-- theme's icy-cyan accent palette without flattening the brick
		-- texture into a smooth ring. Only above the doorway's own height,
		-- so no full unbroken ring ever crosses straight through the
		-- entrance opening.
		if tier % 2 == 0 and tierY > doorHeight + 1 then
			PartUtils.CreateDisc({
				name = "DomeSeamAccent" .. tier,
				diameter = tierRadius * 2 + 0.4,
				thickness = 0.2,
				position = basePos + Vector3.new(0, tierY - brickHeight * 0.5, 0),
				material = ACCENT_MATERIAL,
				color = ACCENT_COLOR,
				canCollide = false,
				parent = model,
			})
		end
	end

	-- Irregular snowdrift mounds around the base, so the dome doesn't sit
	-- on perfectly flat ground - kept clear of the entrance notch so none
	-- of them end up looking like they're blocking the doorway.
	local driftsPlaced = 0
	local driftAttempts = 0
	while driftsPlaced < 5 and driftAttempts < 20 do
		driftAttempts += 1
		local angle = rng:NextNumber(0, 2 * math.pi)
		local driftRadius = domeRadius * rng:NextNumber(0.85, 1.05)
		if isInEntranceNotch(angle, driftRadius, doorWidth) then
			continue
		end
		driftsPlaced += 1
		local driftSize = rng:NextNumber(3, 6)
		PartUtils.CreatePart({
			name = "SnowDrift" .. driftsPlaced,
			size = Vector3.new(driftSize, driftSize * 0.5, driftSize),
			position = basePos + Vector3.new(math.sin(angle) * driftRadius, driftSize * 0.2, math.cos(angle) * driftRadius),
			material = Enum.Material.Snow,
			color = Color3.fromRGB(238, 244, 250),
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = model,
		})
	end

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
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "TunnelRib",
			size = Vector3.new(1, doorHeight + 1.5, tunnelLength),
			position = basePos + Vector3.new(side * (doorWidth / 2 + 0.6), (doorHeight + 1.5) / 2, halfZ + tunnelLength / 2),
			material = WALL_MATERIAL,
			color = ROOFCAP_COLOR,
			canCollide = false,
			parent = model,
		})
	end
	PartUtils.CreatePart({
		name = "TunnelArch",
		size = Vector3.new(doorWidth + 2.4, 1.2, tunnelLength),
		position = basePos + Vector3.new(0, doorHeight + 1.6, halfZ + tunnelLength / 2),
		material = WALL_MATERIAL,
		color = ROOFCAP_COLOR,
		canCollide = false,
		parent = model,
	})
	for i = 1, 5 do
		local t = (i - 1) / 4
		local edgeX = -doorWidth / 2 - 1.2 + t * (doorWidth + 2.4)
		PartUtils.CreatePart({
			className = "WedgePart",
			name = "RimIcicle" .. i,
			size = Vector3.new(0.5, rng:NextNumber(1.4, 2.6), 0.5),
			cframe = CFrame.new(basePos + Vector3.new(edgeX, doorHeight + 1, halfZ + 1.5)) * CFrame.Angles(math.pi, 0, 0),
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
	local halfDiag, baseRadius, collarTop, peakHeight = computeEnclosingEnvelope(def, 1.18, 1.35)
	local craterY = collarTop + (peakHeight - collarTop) * 0.9
	local rng = Random.new(math.floor(basePos.X * 511 + basePos.Z * 907))
	local doorWidth = math.clamp(def.size.X * 0.22, MIN_DOOR_WIDTH, MAX_DOOR_WIDTH)
	local doorHeight = math.min(10, def.height - 4)

	-- Irregular boulder-chunk mound (the same ring-of-overlapping-chunks
	-- technique LavaEnvironment's own distant "pillar" volcanoes use),
	-- built at building scale so the WHOLE building reads as a
	-- hand-assembled mini-volcano - not a box with a smooth cone wrapped
	-- around it.
	--
	-- Two zones (see computeEnclosingEnvelope above): a COLLAR of
	-- near-constant-radius boulder rings from the ground up to the
	-- building's own roofline (so the box shell can never poke through
	-- the mound), then the actual CONE taper only above that, rising to
	-- the crater - exactly like a real volcano's wide base and narrow peak.
	local collarRingCount = 3
	local capRingCount = 4
	local ringCount = collarRingCount + capRingCount
	for ring = 1, ringCount do
		local ringY, ringRadius
		if ring <= collarRingCount then
			local collarFraction = (ring - 1) / collarRingCount
			ringY = collarTop * collarFraction
			ringRadius = baseRadius * (1 - collarFraction * 0.06)
		else
			local capFraction = (ring - collarRingCount) / capRingCount
			ringY = collarTop + (peakHeight - collarTop) * capFraction
			ringRadius = baseRadius * (1 - capFraction * 0.82)
		end
		local ringFraction = (ring - 1) / (ringCount - 1)
		local avgChunkSize = 7 * (1 - ringFraction * 0.3)
		-- Chunk count now SCALES WITH the ring's own circumference (same
		-- technique the igloo dome's brick rings already use) instead of a
		-- fixed small number - a fixed count left huge gaps once the collar
		-- radius grew to actually enclose the box (see computeEnclosingEnvelope
		-- above), letting the plain box floor/walls show straight through
		-- between sparse boulders.
		local chunkCount = math.max(10, math.floor((2 * math.pi * ringRadius) / (avgChunkSize * 0.78)))
		local isCollarRing = ring <= collarRingCount
		for c = 1, chunkCount do
			local angle = (2 * math.pi / chunkCount) * c + rng:NextNumber(-0.25, 0.25)

			-- Skip chunks inside the entrance notch on collar rings only -
			-- opens a real cave-mouth archway through the mound instead of
			-- a fully-closed ring the tunnel dead-ends into.
			if isCollarRing and isInEntranceNotch(angle, ringRadius, doorWidth) then
				continue
			end

			local chunkRadius = ringRadius * rng:NextNumber(0.82, 1.08)
			local chunkSize = rng:NextNumber(5, 9) * (1 - ringFraction * 0.3)
			local chunkPos = basePos
				+ Vector3.new(math.sin(angle) * chunkRadius, ringY + rng:NextNumber(-1.5, 1.5), math.cos(angle) * chunkRadius)
			-- Mostly flattened, angular rock slabs (not spheres/cubes) so
			-- neighboring chunks read as one broken rock surface rather
			-- than a pile of loose boulders.
			PartUtils.CreatePart({
				name = ("VolcanoChunkR%dC%d"):format(ring, c),
				size = Vector3.new(chunkSize * rng:NextNumber(1.1, 1.4), chunkSize * rng:NextNumber(0.4, 0.65), chunkSize * rng:NextNumber(1.1, 1.4)),
				cframe = CFrame.new(chunkPos) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 6.28), rng:NextNumber(-0.2, 0.2)),
				material = if rng:NextNumber() < 0.4 then Enum.Material.Rock else WALL_MATERIAL,
				color = ROOFCAP_COLOR,
				shape = Enum.PartType.Block,
				canCollide = false,
				parent = model,
			})
		end
	end

	PartUtils.CreateDisc({
		name = "VolcanoCrater",
		diameter = baseRadius * 0.45,
		thickness = 1.2,
		position = basePos + Vector3.new(0, craterY, 0),
		material = Enum.Material.CrackedLava,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	-- Irregular lava channels - varied count/angle/length, not two clean
	-- symmetric streaks.
	local channelCount = rng:NextInteger(4, 6)
	for i = 1, channelCount do
		local channelAngle = rng:NextNumber(0, 2 * math.pi)
		local channelLength = (peakHeight - collarTop) * rng:NextNumber(0.5, 0.9)
		local channelRadius = baseRadius * rng:NextNumber(0.25, 0.55)
		PartUtils.CreatePart({
			name = "LavaChannel" .. i,
			size = Vector3.new(rng:NextNumber(1, 2.6), channelLength, 0.35),
			cframe = CFrame.new(
				basePos + Vector3.new(math.sin(channelAngle) * channelRadius, craterY - channelLength * 0.4, math.cos(channelAngle) * channelRadius)
			) * CFrame.Angles(0, channelAngle, math.rad(rng:NextNumber(-10, 10))),
			material = Enum.Material.CrackedLava,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
	end

	-- Small heated glowing vents scattered on the surface.
	for i = 1, rng:NextInteger(3, 5) do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local ventRadius = baseRadius * rng:NextNumber(0.3, 0.9)
		local ventHeight = peakHeight * rng:NextNumber(0.08, 0.6)
		PartUtils.CreatePart({
			name = "HeatVent" .. i,
			size = Vector3.new(rng:NextNumber(1, 2), 0.25, rng:NextNumber(1, 2)),
			position = basePos + Vector3.new(math.sin(angle) * ventRadius, ventHeight, math.cos(angle) * ventRadius),
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
	for i, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "CaveArchRock" .. i,
			size = Vector3.new(3, doorHeight + 2, 3),
			cframe = CFrame.new(basePos + Vector3.new(side * (doorWidth / 2 + 1.6), (doorHeight + 2) / 2, halfZ + lavaTunnelLength - 2))
				* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			material = WALL_MATERIAL,
			color = ROOFCAP_COLOR,
			canCollide = false,
			parent = model,
		})
	end
	PartUtils.CreatePart({
		name = "CaveMouthLintel",
		size = Vector3.new(doorWidth + 6, 2, 3),
		position = basePos + Vector3.new(0, doorHeight + 2.2, halfZ + lavaTunnelLength - 2),
		material = WALL_MATERIAL,
		color = ROOFCAP_COLOR,
		canCollide = false,
		parent = model,
	})
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
	local halfDiag, hullRadius, collarTop, peakY = computeEnclosingEnvelope(def, 1.2, 0.55)
	local capHeight = peakY - collarTop
	local rng = Random.new(math.floor(basePos.X * 349 + basePos.Z * 617))
	local doorWidth = math.clamp(def.size.X * 0.22, MIN_DOOR_WIDTH, MAX_DOOR_WIDTH)
	local doorHeight = math.min(10, def.height - 4)

	local collarRingCount = 4
	for ring = 1, collarRingCount do
		local ringFraction = (ring - 1) / (collarRingCount - 1)
		local ringY = collarTop * ringFraction
		local ringRadius = hullRadius * (1 - ringFraction * 0.03)
		local plateHeight = collarTop / collarRingCount + 1.2
		-- Plate count SCALES WITH the ring's own circumference (same fix
		-- applied to the volcano's boulder rings above) - a fixed count
		-- left huge gaps once hullRadius grew enough to actually enclose
		-- the box, letting the plain walls show straight through.
		local plateWidth = 6
		local plateCount = math.max(12, math.floor((2 * math.pi * ringRadius) / (plateWidth * 0.85)))
		for p = 1, plateCount do
			local angle = (2 * math.pi / plateCount) * p + rng:NextNumber(-0.03, 0.03)

			-- Skip plates inside the entrance notch - opens a real airlock
			-- archway through the hull instead of a fully-closed ring the
			-- tunnel dead-ends into.
			if isInEntranceNotch(angle, ringRadius, doorWidth) then
				continue
			end

			local platePos = basePos + Vector3.new(math.sin(angle) * ringRadius, ringY, math.cos(angle) * ringRadius)
			PartUtils.CreatePart({
				name = ("HullPlateR%dP%d"):format(ring, p),
				size = Vector3.new(plateWidth, plateHeight, 1.4),
				cframe = CFrame.new(platePos) * CFrame.Angles(0, angle, 0),
				material = WALL_MATERIAL,
				color = ROOFCAP_COLOR,
				canCollide = false,
				parent = model,
			})
		end
		-- Seam ring only above the doorway's own height, so no unbroken
		-- ring crosses straight through the entrance opening.
		if ringY > doorHeight + 1 then
			PartUtils.CreateDisc({
				name = "HullSeam" .. ring,
				diameter = ringRadius * 2 + 0.4,
				thickness = 0.25,
				position = basePos + Vector3.new(0, ringY, 0),
				material = ACCENT_MATERIAL,
				color = ACCENT_COLOR,
				canCollide = false,
				parent = model,
			})
		end
	end

	-- Shallow rounded cap above the roofline - the curved deck/sail base
	-- a submarine hull tapers into, using the same quarter-circle profile
	-- as the igloo dome's cap zone.
	local capRingCount = 3
	for ring = 1, capRingCount do
		local capFraction = ring / capRingCount
		local angleFromTop = (math.pi / 2) * capFraction
		local ringY = collarTop + capHeight * math.sin(angleFromTop)
		local ringRadius = hullRadius * math.cos(angleFromTop)
		if ringRadius < 1.5 then
			PartUtils.CreatePart({
				name = "HullCapTip",
				size = Vector3.new(3, 2, 3),
				position = basePos + Vector3.new(0, ringY, 0),
				material = WALL_MATERIAL,
				color = ROOFCAP_COLOR,
				shape = Enum.PartType.Ball,
				canCollide = false,
				parent = model,
			})
		else
			local capPlateWidth = 4.5
			local plateCount = math.max(8, math.floor((2 * math.pi * ringRadius) / (capPlateWidth * 0.85)))
			for p = 1, plateCount do
				local angle = (2 * math.pi / plateCount) * p
				local platePos = basePos + Vector3.new(math.sin(angle) * ringRadius, ringY, math.cos(angle) * ringRadius)
				PartUtils.CreatePart({
					name = ("HullCapR%dP%d"):format(ring, p),
					size = Vector3.new(capPlateWidth, capHeight / capRingCount + 1, 1.2),
					cframe = CFrame.new(platePos) * CFrame.Angles(0, angle, 0),
					material = WALL_MATERIAL,
					color = ROOFCAP_COLOR,
					canCollide = false,
					parent = model,
				})
			end
		end
	end

	-- Conning tower + periscope near the front, above the entrance - the
	-- classic submarine silhouette element.
	local towerHeight = 5
	PartUtils.CreatePart({
		name = "ConningTower",
		size = Vector3.new(5, towerHeight, 5),
		position = basePos + Vector3.new(0, def.height + towerHeight / 2, halfZ * 0.3),
		material = WALL_MATERIAL,
		color = ROOFCAP_COLOR,
		canCollide = false,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "Periscope",
		size = Vector3.new(0.8, 4, 0.8),
		position = basePos + Vector3.new(0, def.height + towerHeight + 2, halfZ * 0.3),
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		canCollide = false,
		parent = model,
	})

	-- Portholes lining both sides of the hull.
	for _, side in ipairs({ -1, 1 }) do
		for _, offsetZ in ipairs({ -halfZ * 0.4, halfZ * 0.4 }) do
			local porthole = PartUtils.CreateDisc({
				name = "Porthole",
				diameter = 2.6,
				thickness = 0.3,
				position = basePos + Vector3.new(side * (hullRadius * 0.92), def.height * 0.55, offsetZ),
				material = GLASS_MATERIAL,
				color = GLASS_COLOR,
				canCollide = false,
				parent = model,
			})
			porthole.CFrame = porthole.CFrame * CFrame.Angles(0, 0, math.rad(90))
			local frame = PartUtils.CreateDisc({
				name = "PortholeFrame",
				diameter = 3,
				thickness = 0.4,
				position = basePos + Vector3.new(side * (hullRadius * 0.92), def.height * 0.55, offsetZ),
				material = ACCENT_MATERIAL,
				color = ACCENT_COLOR,
				canCollide = false,
				parent = model,
			})
			frame.CFrame = frame.CFrame * CFrame.Angles(0, 0, math.rad(90))
		end
	end

	-- Airlock hatch entrance tunnel - bridges the real doorway out past
	-- the hull's own curvature. Length reaches past the hull's own outer
	-- radius so the tunnel mouth (and its name plate) sits flush with the
	-- hull's real outer surface, not buried inside it.
	local hullTunnelLength = math.max(6, hullRadius - halfZ + 2)
	themedEntranceTunnel(def, model, hullTunnelLength, WALL_MATERIAL, ROOFCAP_COLOR)
	PartUtils.CreatePart({
		name = "HatchRim",
		size = Vector3.new(doorWidth + 1.6, 0.4, 0.4),
		position = basePos + Vector3.new(0, doorHeight + 0.3, halfZ + hullTunnelLength - 1),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})
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

	PartUtils.CreatePart({
		name = "Floor",
		size = Vector3.new(def.size.X, 0.5, def.size.Y),
		position = basePos + Vector3.new(0, 0.25, 0),
		material = Enum.Material.SmoothPlastic,
		color = INTERIOR_FLOOR_COLOR,
		parent = model,
	})

	PartUtils.CreatePart({
		name = "Ceiling",
		size = Vector3.new(def.size.X, 0.5, def.size.Y),
		position = basePos + Vector3.new(0, def.height - 0.25, 0),
		material = WALL_MATERIAL,
		color = CEILING_COLOR,
		parent = model,
	})

	PartUtils.CreatePart({
		name = "BackWall",
		size = Vector3.new(def.size.X, def.height, WALL_THICKNESS),
		position = basePos + Vector3.new(0, def.height / 2, -halfZ + WALL_THICKNESS / 2),
		material = WALL_MATERIAL,
		color = EXTERIOR_WALL_COLOR,
		parent = model,
	})

	-- Left/Right walls, each with two window strips (glass + neon frame)
	-- instead of a single flat surface - the "layered walls / large
	-- windows" the visual overhaul calls for.
	for _, side in ipairs({ -1, 1 }) do
		local wallX = side * (halfX - WALL_THICKNESS / 2)
		PartUtils.CreatePart({
			name = if side == -1 then "LeftWall" else "RightWall",
			size = Vector3.new(WALL_THICKNESS, def.height, def.size.Y),
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
		PartUtils.CreatePart({
		name = "FrontWallLeft",
		size = Vector3.new(sideSegWidth, doorHeight, WALL_THICKNESS),
		position = basePos + Vector3.new(-halfX + sideSegWidth / 2, doorHeight / 2, halfZ - WALL_THICKNESS / 2),
		material = WALL_MATERIAL,
		color = EXTERIOR_WALL_COLOR,
		parent = model,
		})
		PartUtils.CreatePart({
		name = "FrontWallRight",
		size = Vector3.new(sideSegWidth, doorHeight, WALL_THICKNESS),
		position = basePos + Vector3.new(halfX - sideSegWidth / 2, doorHeight / 2, halfZ - WALL_THICKNESS / 2),
		material = WALL_MATERIAL,
		color = EXTERIOR_WALL_COLOR,
		parent = model,
		})
		end

	-- "Base": the header above the doorway - full building width, carries
	-- the exterior sign/display exactly as Buildings.lua already expects.
	local base = PartUtils.CreatePart({
		name = "Base",
		size = Vector3.new(def.size.X, headerHeight, WALL_THICKNESS),
		position = basePos + Vector3.new(0, doorHeight + headerHeight / 2, halfZ - WALL_THICKNESS / 2),
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

	-- A couple of ceiling-mounted interior lights (kept minimal per the
	-- performance guidance - no more than needed to keep the room readable).
	for _, offsetZ in ipairs({ -halfZ / 2, halfZ / 2 }) do
		local light = PartUtils.CreatePart({
			name = "CeilingLight",
			size = Vector3.new(4, 0.2, 1.5),
			position = basePos + Vector3.new(0, def.height - 0.7, offsetZ),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
		local pointLight = Instance.new("PointLight")
		pointLight.Color = ACCENT_COLOR
		pointLight.Range = LightingConfig.ACCENT_LIGHT_RANGE
		pointLight.Brightness = LightingConfig.ACCENT_LIGHT_BRIGHTNESS
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

	-- Floating header naming exactly what this terminal does - "an
	-- obvious attention-grabbing feature", not a mystery box.
	local header = PartUtils.CreatePart({
		name = "TerminalHeader",
		size = Vector3.new(4.6, 1, 0.15),
		position = position + Vector3.new(0, 4.4, 0.4),
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
				PartUtils.CreatePart({
					name = "ShelfItem",
					size = Vector3.new(0.8, 0.8, 0.8),
					position = basePos + Vector3.new(side * (halfX - 2.1), shelfY + 0.55, offsetZ),
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

	-- Example question station in the middle of the room - a floating
	-- "12 x 8 = ?"-style demo screen with a bench on each side, the room's
	-- clear second stop on the learning path.
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
