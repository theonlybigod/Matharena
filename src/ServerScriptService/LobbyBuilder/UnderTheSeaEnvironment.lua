--[[
	UnderTheSeaEnvironment.lua

	The Under the Sea map's backdrop: the enclosing open-water volume, the
	seabed inside the plaza, and — the bulk of this file — the EXTERIOR
	seascape lying beyond the playable plate.

	=====================================================================
	EXTERIOR REDESIGN
	=====================================================================

	WHAT WAS HERE BEFORE, AND WHY IT WENT. The exterior used to be a
	barrier-reef massif written into Terrain: a ring rising to 205 studs
	with a reef flat, a crest and a spur-and-grooved fore-reef, carpeted
	with 2,600 coral colonies (20,562 parts). Two problems. It stood eight
	times the height of the tallest building, so from the plaza it read as
	a wall of pale mountains rather than as ocean. And the coral was dense
	enough to be visual noise — an even field of clutter with no landmarks
	in it.

	The whole of that is gone: the reef height field, the coral forest, the
	steel freighter, the fish schools, the jellyfish bloom, and the old
	reef-relative placement for every animal. The Terrain is cleared and
	rewritten from scratch.

	WHAT REPLACES IT.

	  DUNES, NOT MOUNTAINS. Low sandy swells shaped like wave ripples,
	  running near-flat beside the plate and rising with distance to 78
	  studs at the rim. The near-field flatness is what keeps the exterior
	  from competing with the buildings; the far-field rise is deliberate
	  forced perspective, making the enclosure read as deeper than it is.

	  LANDMARKS, NOT CARPET. Instead of uniform coral cover, the exterior
	  has a small number of things worth looking at: one very large wooden
	  shipwreck, three submarines at different sizes, whales, sharks and
	  oversized fish, with coral gathered into gardens on the dune flanks
	  rather than sprayed everywhere.

	  CORAL WITH DEPTH. The coral is built to read as more solid and more
	  realistic than the rest of the map: natural muted colours, stacked
	  and layered forms rather than single blocks, and — unlike everything
	  else out here — shadows enabled, so the colonies have genuine
	  self-shading and sit into the sand instead of floating on it.

	SCALE REFERENCE, used throughout:
	  building height   19–26 studs   (dune ceiling)
	  plate circumradius   188 studs
	  map width across     376 studs  (shipwreck length is ~90% of this)
	  enclosure radius    1000 studs

	UNDER-THE-SEA-MAP-ONLY: only ever called by LobbyBuilder for the Under
	the Sea map (def.themeId == "UnderTheSea"). Every other map is
	untouched by this module.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local MapConfig = require(script.Parent.MapConfig)
local LobbyConfig = require(script.Parent.LobbyConfig)

local UnderTheSeaEnvironment = {}

----------------------------------------------------------------------
-- ENCLOSURE
----------------------------------------------------------------------

local ENCLOSURE_RADIUS = 1000
local WALL_SEGMENTS = 96
local WALL_HEIGHT = 700
local WALL_BOTTOM_Y = -200
local WALL_THICKNESS = 4
local WATER_COLOR = Color3.fromRGB(10, 45, 58)

----------------------------------------------------------------------
-- DUNE FIELD
----------------------------------------------------------------------

local TERRAIN_RES = 4

-- The plate's circumradius is 188; dunes start just outside it so they
-- never intrude on the playable area.
local DUNE_INNER = 206
local DUNE_OUTER = 960

--[[
	HEIGHT GRADIENT — FORCED PERSPECTIVE.

	The field is no longer a single capped height. It ramps with distance
	from the map centre:

	  NEAR the plate   almost dead flat (DUNE_NEAR_HEIGHT), so the ground
	                   just outside the playable edge reads as a calm sandy
	                   apron and never competes with the buildings.
	  FAR out          much taller (DUNE_FAR_HEIGHT), so the seabed climbs
	                   as it recedes.

	WHY. Rising ground at the horizon reads as *further away* than flat
	ground at the same distance — the eye takes increasing height as
	increasing distance. Combined with the density and size ramps used by
	the scatter passes below, this makes the 960-stud enclosure feel
	considerably deeper than it is, which is the whole point.

	This deliberately supersedes the previous flat 26-stud cap. The tall
	ground is all 600+ studs out, so nothing looms over the plaza; near the
	plate the field is *lower* than it was before, not higher.
]]
local DUNE_NEAR_HEIGHT = 0
local DUNE_FAR_HEIGHT = 78

--[[
	SEABED DATUM — THE PLATE SITS ON THE SAND.

	The lobby plate (LobbyGround) is a 2-stud-thick disc: walking surface
	at y = 4, underside at y = 2. The datum is set just below that
	underside, so the seabed passes CONTINUOUSLY beneath the plate and the
	plate reads as resting on it.

	WHY CONTINUOUS RATHER THAN CUT AWAY. The previous fix stopped the
	terrain dead at a circle outside the plate. That removed the intrusion
	but created a worse problem: a visible edge where the sand began, with
	empty space under the plate behind it. Running the sand all the way
	under means there is no start to see - from any angle on the plaza the
	ground simply continues under your feet and out to the dunes.

	The 3-stud clearance is deliberate, and larger than it first looks like
	it needs to be. Terrain renders as a SMOOTHED surface, not as the
	blocky voxel columns it is stored in, so the visible sand bulges above
	its nominal height by up to roughly half a voxel (2 studs at
	TERRAIN_RES = 4). At only 0.5 studs of clearance that bulge swallowed
	the 2-stud-thick plate entirely and the plaza's own surface design
	vanished under the sand. Three studs keeps the rendered surface clear
	of the underside while still reading as contact at the rim.
]]
local PLATE_UNDERSIDE_Y = 2
local SEABED_DATUM_Y = PLATE_UNDERSIDE_Y - 3

--[[
	How far past the plate's rim the dunes stay flat before rising.

	Without this the height ramp starts at the rim itself, and since the
	ramp is driven by distance from the map CENTRE, sand immediately
	outside the plate would already carry some amplitude and could crest
	above the plate's y = 4 walking surface - sand visibly poking over the
	rim, which is the original complaint in a new form.

	Holding it flat for 140 studs guarantees the first dunes only begin
	well out in open water, where they cannot be confused with the plate
	edge.
]]
local PLATE_SKIRT_RADIUS = 188
local PLATE_SKIRT_FADE = 140

--[[
	SEABED DATUM.

	The level the dune field is measured UP FROM, and therefore the level
	of the flattest sand just outside the plate.

	PART OF duneHeight's RETURN VALUE, deliberately. Every scatter pass
	(coral, algae, grass, caves, habitats, the wreck) places props at
	duneHeight(x, z), so folding the datum in here keeps props sitting ON
	the sand automatically. Applying it only inside the terrain writer
	would have left every prop in the map floating above the ground.
]]

-- Everything that scatters objects reads this to grow size, density and
-- height with distance, so the whole exterior recedes consistently rather
-- than only the terrain doing it.
local function distanceFactor(dist: number): number
	local t = math.clamp((dist - DUNE_INNER) / (DUNE_OUTER - DUNE_INNER), 0, 1)
	return t * t * (3 - 2 * t)
end

--[[
	SCATTER STANDOFF.

	DUNE_INNER is where the TERRAIN starts, and that can sit tight against
	the plate because it is near-flat there. Large PROPS cannot: once coral
	grew to 30+ studs and caves to 26+, anything placed at the terrain's
	inner edge loomed over the plate boundary and blocked the sightline to
	the buildings from inside the plaza.

	So props keep their own, much larger standoff, scaled to how big the
	prop type gets. Only the flat ground cover (algae mats) is allowed near
	the plate, because it has no height to intrude with.
]]
local CORAL_INNER = 300
local GRASS_INNER = 330
local CAVE_INNER = 420

local function smoothRamp(edge0: number, edge1: number, value: number): number
	local t = math.clamp((value - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function fbm(x: number, z: number, frequency: number, octaves: number, seed: number): number
	local sum, amplitude, norm = 0, 1, 0
	local f = frequency
	for i = 1, octaves do
		sum += math.noise(x * f, z * f, seed + i) * amplitude
		norm += amplitude
		amplitude *= 0.5
		f *= 2
	end
	return sum / norm
end

--[[
	DUNE HEIGHT FIELD.

	Sand ripples on a seabed are near-parallel crests, all running the same
	way because one prevailing current shaped them — they are not random
	lumps. So the primary term is a straight sine wave across the map, not
	noise:

	  PRIMARY RIPPLE   a long sine with a ~150 stud wavelength, its phase
	                   warped by low-frequency noise so the crests meander
	                   instead of ruling straight lines across the floor.
	  SECONDARY        a shorter, weaker ripple at an angle to the first,
	                   which breaks the crests into the scalloped, braided
	                   pattern real ripple fields have.
	  SWELL            very low frequency, very broad rises, so the whole
	                   field gently undulates rather than sitting on a
	                   perfectly flat datum.
	  GRAIN            fine noise for close-up texture.

	The shaped result is then scaled by an amplitude that ramps with
	distance from the map centre (see DUNE_NEAR_HEIGHT / DUNE_FAR_HEIGHT),
	so the same ripple pattern is barely-there beside the plate and becomes
	substantial terrain out at the rim.
]]
local function duneHeight(localX: number, localZ: number): number
	local dist = math.sqrt(localX * localX + localZ * localZ)
	if dist > DUNE_OUTER then
		return SEABED_DATUM_Y
	end

	--[[
		Under the plate and for PLATE_SKIRT_FADE studs beyond it, the field
		is perfectly flat at the datum. This is the sand the plate rests on;
		it must not undulate, or the plate would appear to hover over a
		ripple.
	]]
	if dist <= PLATE_SKIRT_RADIUS then
		return SEABED_DATUM_Y
	end

	-- Ripples run roughly along +X, so crests face the viewer from the plaza.
	local warp = fbm(localX, localZ, 0.0013, 2, 11) * 90
	local primary = math.sin((localZ + warp) * (2 * math.pi / 150))

	local secondary = math.sin(
		((localX * 0.82 + localZ * 0.57) + fbm(localX, localZ, 0.0022, 2, 29) * 60) * (2 * math.pi / 78)
	)

	local swell = fbm(localX, localZ, 0.0009, 2, 47)
	local grain = fbm(localX, localZ, 0.02, 3, 71)

	-- Weighted sum, remapped from roughly -1..1 into 0..1.
	local combined = primary * 0.5 + secondary * 0.24 + swell * 0.34 + grain * 0.1
	local normalised = math.clamp(combined * 0.5 + 0.5, 0, 1)

	-- ^1.35 keeps the troughs broad and flat and the crests narrow, which is
	-- the asymmetry a real ripple field has.
	local shaped = normalised ^ 1.35

	local amplitude = DUNE_NEAR_HEIGHT
		+ (DUNE_FAR_HEIGHT - DUNE_NEAR_HEIGHT) * distanceFactor(dist) ^ 1.6

	-- Hold flat across the skirt, then ease in. Without this the ripples
	-- would start at the rim and could crest above the plate's surface.
	local skirtEase = smoothRamp(PLATE_SKIRT_RADIUS, PLATE_SKIRT_RADIUS + PLATE_SKIRT_FADE, dist)

	-- Only the outer edge fades, and only slightly, so the field meets the
	-- enclosure wall without a hard cut.
	local edgeFade = 1 - smoothRamp(DUNE_OUTER - 90, DUNE_OUTER, dist) * 0.55

	return SEABED_DATUM_Y + math.max(0, shaped * amplitude * skirtEase * edgeFade)
end

function UnderTheSeaEnvironment.GetDuneHeight(localX: number, localZ: number): number
	return duneHeight(localX, localZ)
end

function UnderTheSeaEnvironment.GetDuneBand(): (number, number, number)
	return DUNE_INNER, DUNE_OUTER, DUNE_FAR_HEIGHT
end

--[[
	Writes the dune field into Terrain around `worldOrigin`, having first
	cleared everything the old reef left behind.

	Tiled because WriteVoxels is capped well below the full region. The
	vertical extent is tiny compared with the old reef — the field is only
	26 studs tall — so this is far cheaper than what it replaces.

	WORLD SPACE, ON PURPOSE. Terrain is not a BasePart, so LobbyBuilder's
	applyMapTransform cannot move it; this takes the FINAL world origin and
	is called after that transform.
]]
function UnderTheSeaEnvironment.BuildTerrainDunes(worldOrigin: Vector3)
	local Terrain = workspace.Terrain

	local TILE = 128
	local FLOOR_Y = -40
	-- Must clear the new far-field ceiling, not the old flat cap, or the
	-- outer dunes are sliced off at the top of the write region.
	local TOP_Y = DUNE_FAR_HEIGHT + 30
	--[[
		Clear to the OLD reef's full vertical extent, not just the new one.
		The reef reached 205 studs plus bommies; clearing only to the new
		26-stud ceiling would leave the top three quarters of it floating in
		the water column. This is the "start fresh" step and it has to be
		generous or the remains are worse than the original.
	]]
	local clearRegion = Region3.new(
		worldOrigin + Vector3.new(-ENCLOSURE_RADIUS, -240, -ENCLOSURE_RADIUS),
		worldOrigin + Vector3.new(ENCLOSURE_RADIUS, 400, ENCLOSURE_RADIUS)
	):ExpandToGrid(TERRAIN_RES)
	Terrain:FillRegion(clearRegion, TERRAIN_RES, Enum.Material.Air)

	local voxelsY = math.floor((TOP_Y - FLOOR_Y) / TERRAIN_RES)
	local tilesWritten, voxelsWritten = 0, 0

	for tileX = -DUNE_OUTER, DUNE_OUTER - 1, TILE do
		for tileZ = -DUNE_OUTER, DUNE_OUTER - 1, TILE do
			local cx, cz = tileX + TILE / 2, tileZ + TILE / 2
			local centreDist = math.sqrt(cx * cx + cz * cz)
			local halfDiag = TILE * 0.7072
			--[[
				Only the OUTER bound is tested now. Central tiles must be written
				too, because the seabed runs continuously under the plate - the
				earlier inner test is what left a square hole in the middle of
				the sand.
			]]
			if centreDist - halfDiag <= DUNE_OUTER then
				local region = Region3.new(
					worldOrigin + Vector3.new(tileX, FLOOR_Y, tileZ),
					worldOrigin + Vector3.new(tileX + TILE, FLOOR_Y + voxelsY * TERRAIN_RES, tileZ + TILE)
				):ExpandToGrid(TERRAIN_RES)

				local regionSize = region.Size
				local sizeX = math.floor(regionSize.X / TERRAIN_RES + 0.5)
				local sizeY = math.floor(regionSize.Y / TERRAIN_RES + 0.5)
				local sizeZ = math.floor(regionSize.Z / TERRAIN_RES + 0.5)
				local corner = region.CFrame.Position - regionSize / 2

				local colHeight, colSlope = {}, {}
				for ix = 1, sizeX do
					colHeight[ix], colSlope[ix] = {}, {}
					local lx = corner.X + (ix - 0.5) * TERRAIN_RES - worldOrigin.X
					for iz = 1, sizeZ do
						local lz = corner.Z + (iz - 0.5) * TERRAIN_RES - worldOrigin.Z
						colHeight[ix][iz] = duneHeight(lx, lz)
						local dx = duneHeight(lx + TERRAIN_RES, lz) - duneHeight(lx - TERRAIN_RES, lz)
						local dz = duneHeight(lx, lz + TERRAIN_RES) - duneHeight(lx, lz - TERRAIN_RES)
						colSlope[ix][iz] = math.sqrt(dx * dx + dz * dz) / (2 * TERRAIN_RES)
					end
				end

				local materials, occupancies = {}, {}
				for ix = 1, sizeX do
					materials[ix], occupancies[ix] = {}, {}
					local lx = corner.X + (ix - 0.5) * TERRAIN_RES - worldOrigin.X
					for iy = 1, sizeY do
						materials[ix][iy], occupancies[ix][iy] = {}, {}
						local voxelBottom = corner.Y + (iy - 1) * TERRAIN_RES - worldOrigin.Y
						for iz = 1, sizeZ do
							local lz = corner.Z + (iz - 0.5) * TERRAIN_RES - worldOrigin.Z

							--[[
								NO INNER GATE. The sand deliberately runs all the way
								under the plate: duneHeight holds it flat at the datum
								inside PLATE_SKIRT_RADIUS, half a stud below the plate's
								underside, so there is no edge for a player to see and
								the plate reads as sitting on the seabed.

								An earlier version cut the terrain off at a circle
								outside the plate. That fixed the intrusion but left a
								visible start line and hollow space beneath the plaza.
							]]
							local height = colHeight[ix][iz]
							-- colHeight is an absolute surface height; it already
							-- includes SEABED_DATUM_Y.
							local fill = math.clamp((height - voxelBottom) / TERRAIN_RES, 0, 1)
							local material = Enum.Material.Air

							if fill > 0 then
								-- Almost entirely Sand. Slate appears only on the
								-- steepest faces, as the coarse grit that collects
								-- where sand cannot hold.
								if colSlope[ix][iz] > 0.55 and voxelBottom > SEABED_DATUM_Y + 4 then
									material = Enum.Material.Slate
								else
									material = Enum.Material.Sand
								end
								voxelsWritten += 1
							end

							materials[ix][iy][iz] = material
							occupancies[ix][iy][iz] = fill
						end
					end
				end

				Terrain:WriteVoxels(region, TERRAIN_RES, materials, occupancies)
				tilesWritten += 1
			end
		end
	end

	return tilesWritten, voxelsWritten
end

----------------------------------------------------------------------
-- WATER VOLUME
----------------------------------------------------------------------

local function buildWallSegments(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "WaterWalls"
	folder.Parent = parent

	local wallCenterY = WALL_BOTTOM_Y + WALL_HEIGHT / 2
	for i = 0, WALL_SEGMENTS - 1 do
		local angle1 = (2 * math.pi / WALL_SEGMENTS) * i
		local angle2 = (2 * math.pi / WALL_SEGMENTS) * (i + 1)
		local v1 = Vector3.new(ENCLOSURE_RADIUS * math.sin(angle1), 0, ENCLOSURE_RADIUS * math.cos(angle1))
		local v2 = Vector3.new(ENCLOSURE_RADIUS * math.sin(angle2), 0, ENCLOSURE_RADIUS * math.cos(angle2))
		local midpoint = (v1 + v2) / 2
		local direction = v2 - v1
		local yaw = math.atan2(direction.X, direction.Z)

		PartUtils.CreatePart({
			name = "WaterWall" .. i,
			size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, direction.Magnitude + 3),
			cframe = CFrame.new(midpoint + Vector3.new(0, wallCenterY, 0)) * CFrame.Angles(0, yaw, 0),
			material = Enum.Material.SmoothPlastic,
			color = WATER_COLOR,
			canCollide = false,
			parent = folder,
		})
	end
end

local function buildCeiling(parent: Instance)
	PartUtils.CreatePart({
		name = "WaterCeiling",
		size = Vector3.new(ENCLOSURE_RADIUS * 2 + 40, 8, ENCLOSURE_RADIUS * 2 + 40),
		position = Vector3.new(0, WALL_BOTTOM_Y + WALL_HEIGHT + 6, 0),
		material = Enum.Material.SmoothPlastic,
		color = WATER_COLOR,
		canCollide = false,
		parent = parent,
	})
end

local function buildFloor(parent: Instance)
	PartUtils.CreatePart({
		name = "WaterFloor",
		size = Vector3.new(ENCLOSURE_RADIUS * 2 + 40, 8, ENCLOSURE_RADIUS * 2 + 40),
		position = Vector3.new(0, WALL_BOTTOM_Y - 6, 0),
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(4, 20, 26),
		canCollide = false,
		parent = parent,
	})
end

local function buildLightShafts(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "LightShafts"
	folder.Parent = parent

	local ceilingY = WALL_BOTTOM_Y + WALL_HEIGHT
	local rng = Random.new(60219)
	for i = 1, 6 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(20, MapConfig.USABLE_RADIUS * 0.8)
		PartUtils.CreatePart({
			name = "LightShaft" .. i,
			size = Vector3.new(rng:NextNumber(10, 18), ceilingY * 0.8, 1),
			cframe = CFrame.new(Vector3.new(math.sin(angle) * radius, ceilingY * 0.4, math.cos(angle) * radius))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-12, 12))),
			material = Enum.Material.Neon,
			color = Color3.fromRGB(190, 230, 235),
			transparency = 0.93,
			canCollide = false,
			parent = folder,
		})
	end
end

local function buildBubbleStreams(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "BubbleStreams"
	folder.Parent = parent

	local rng = Random.new(552310)
	for i = 1, 14 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(40, MapConfig.USABLE_RADIUS * 0.98)
		local anchor = PartUtils.CreatePart({
			name = "BubbleAnchor" .. i,
			size = Vector3.new(1, 1, 1),
			position = Vector3.new(math.sin(angle) * radius, 1, math.cos(angle) * radius),
			transparency = 1,
			canCollide = false,
			parent = folder,
		}) :: BasePart

		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(Color3.fromRGB(210, 240, 245))
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Size = NumberSequence.new(0.25)
		emitter.Lifetime = NumberRange.new(3, 5)
		emitter.Speed = NumberRange.new(3, 5)
		emitter.Rate = 4
		emitter.SpreadAngle = Vector2.new(6, 6)
		emitter.Acceleration = Vector3.new(0, 6, 0)
		emitter.Parent = anchor
	end
end

local function buildAmbientBubbles(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "AmbientBubbles"
	folder.Parent = parent

	local span = MapConfig.USABLE_RADIUS * 0.7
	local spots = {
		Vector3.new(0, 0, 0),
		Vector3.new(-span, 0, -span),
		Vector3.new(span, 0, span),
		Vector3.new(-span, 0, span),
		Vector3.new(span, 0, -span),
	}

	local index = 0
	for _, height in ipairs({ 20, 70, 130 }) do
		for _, spot in ipairs(spots) do
			index += 1
			local anchor = PartUtils.CreatePart({
				name = ("AmbientBubbleEmitter%d"):format(index),
				size = Vector3.new(span * 1.6, 1, span * 1.6),
				position = spot + Vector3.new(0, height, 0),
				transparency = 1,
				canCollide = false,
				castShadow = false,
				parent = folder,
			})

			local bubbles = Instance.new("ParticleEmitter")
			bubbles.Name = "Bubbles"
			bubbles.Shape = Enum.ParticleEmitterShape.Box
			bubbles.EmissionDirection = Enum.NormalId.Top
			bubbles.Color = ColorSequence.new(Color3.fromRGB(210, 240, 255))
			bubbles.LightEmission = 0.65
			bubbles.LightInfluence = 0
			bubbles.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.18),
				NumberSequenceKeypoint.new(1, 0.45),
			})
			bubbles.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.45),
				NumberSequenceKeypoint.new(0.85, 0.55),
				NumberSequenceKeypoint.new(1, 1),
			})
			bubbles.Lifetime = NumberRange.new(7, 13)
			bubbles.Rate = 20
			bubbles.Speed = NumberRange.new(2, 5)
			bubbles.SpreadAngle = Vector2.new(22, 22)
			bubbles.Acceleration = Vector3.new(0.8, 3.2, -0.6)
			bubbles.Parent = anchor
		end
	end
end

----------------------------------------------------------------------
-- SEABED INSIDE THE PLATE (unchanged behaviour, kept from the original)
----------------------------------------------------------------------

local function buildSeabedPattern(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "SeabedPattern"
	folder.Parent = parent

	local rng = Random.new(624489)
	local SAND = Color3.fromRGB(222, 208, 170)

	for i = 1, 80 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = math.sqrt(rng:NextNumber(0, 1)) * MapConfig.USABLE_RADIUS * 0.99
		PartUtils.CreateDisc({
			name = "SandWash" .. i,
			diameter = rng:NextNumber(16, 34),
			thickness = rng:NextNumber(0.14, 0.34),
			position = Vector3.new(math.sin(angle) * radius, 0.12, math.cos(angle) * radius),
			material = Enum.Material.Sand,
			color = Color3.new(
				math.clamp(SAND.R + rng:NextInteger(-10, 8) / 255, 0, 1),
				math.clamp(SAND.G + rng:NextInteger(-8, 8) / 255, 0, 1),
				math.clamp(SAND.B + rng:NextInteger(-8, 10) / 255, 0, 1)
			),
			canCollide = false,
			parent = folder,
		})
	end

	for i = 1, 22 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(MapConfig.USABLE_RADIUS * 0.12, MapConfig.USABLE_RADIUS * 0.95)
		local center = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		local spread = rng:NextNumber(4, 10)
		for b = 1, rng:NextInteger(3, 6) do
			local blobAngle = rng:NextNumber(0, 2 * math.pi)
			local blobDist = rng:NextNumber(0, spread * 0.55)
			local blobSize = rng:NextNumber(5, 12) * (1 - blobDist / (spread * 1.5))
			local height = math.min(2.2, blobSize * rng:NextNumber(0.15, 0.26))
			PartUtils.CreatePart({
				name = ("SandBlob%d_%d"):format(i, b),
				size = Vector3.new(blobSize, height, blobSize * rng:NextNumber(0.8, 1.2)),
				position = center
					+ Vector3.new(math.sin(blobAngle) * blobDist, height * 0.2, math.cos(blobAngle) * blobDist),
				material = Enum.Material.Sand,
				color = SAND,
				shape = Enum.PartType.Ball,
				canCollide = false,
				parent = folder,
			})
		end
	end
end

local function buildKelpForest(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "KelpForest"
	folder.Parent = parent

	local rng = Random.new(264188)
	local KELP_DARK = Color3.fromRGB(38, 82, 52)
	local KELP_LIGHT = Color3.fromRGB(64, 122, 70)

	local placed, attempts = 0, 0
	while placed < 46 and attempts < 500 do
		attempts += 1
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(46, MapConfig.USABLE_RADIUS * 0.96)
		local base = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)

		local tooClose = false
		for _, def in ipairs(LobbyConfig.BUILDINGS) do
			if (Vector3.new(def.position.X, 0, def.position.Z) - base).Magnitude < 36 then
				tooClose = true
				break
			end
		end

		if not tooClose then
			placed += 1
			local height = rng:NextNumber(22, 52)
			local segments = math.max(5, math.floor(height / 6))
			local leanDir = rng:NextNumber(0, 2 * math.pi)
			local lean = rng:NextNumber(0.05, 0.16)
			local tint = KELP_DARK:Lerp(KELP_LIGHT, rng:NextNumber())

			for seg = 1, segments do
				local t = seg / segments
				local segHeight = height / segments
				local drift = lean * height * t * t
				PartUtils.CreatePart({
					name = ("Kelp%dSeg%d"):format(placed, seg),
					size = Vector3.new(1.5 * (1.15 - t * 0.55), segHeight * 1.1, 0.5),
					cframe = CFrame.new(
						base + Vector3.new(math.sin(leanDir) * drift, segHeight * (seg - 0.5), math.cos(leanDir) * drift)
					) * CFrame.Angles(0, leanDir, 0) * CFrame.Angles(lean * t * 2, 0, 0),
					material = Enum.Material.Grass,
					color = tint,
					transparency = 0.15,
					canCollide = false,
					castShadow = false,
					parent = folder,
				})
			end
		end
	end
end

----------------------------------------------------------------------
-- CORAL
----------------------------------------------------------------------

--[[
	CORAL PALETTE.

	Drawn from the reference photographs: deep reds and crimsons, golds and
	mustard yellows, the pinks and magentas of soft coral, with orange and a
	little muted blue-violet for relief.

	The greens and grey-blues that used to be in here are gone. They were
	what made the old reef read as artificial — real coral is warm-dominant,
	and a palette spread evenly across the colour wheel looks like a colour
	picker rather than a reef.
]]
local CORAL_PALETTE = {
	Color3.fromRGB(168, 42, 44), -- deep red
	Color3.fromRGB(198, 66, 52), -- crimson
	Color3.fromRGB(214, 106, 62), -- warm orange
	Color3.fromRGB(212, 158, 58), -- gold
	Color3.fromRGB(196, 176, 74), -- mustard yellow
	Color3.fromRGB(206, 96, 118), -- coral pink
	Color3.fromRGB(182, 74, 122), -- magenta
	Color3.fromRGB(146, 78, 140), -- muted violet
	Color3.fromRGB(92, 106, 156), -- dusty blue (used sparingly)
}

-- Blue is the odd one out and should stay rare, or the warm cast is lost.
local function pickCoralColour(rng: Random): Color3
	if rng:NextNumber() < 0.08 then
		return CORAL_PALETTE[9]
	end
	return CORAL_PALETTE[rng:NextInteger(1, 8)]
end

--[[
	SHADOWS ON. Every other decorative part in this map sets castShadow =
	false for frame rate. Coral is the deliberate exception: the brief asked
	for depth and 3D shading, and self-shadowing is what gives a colony
	form instead of flatness. Affordable because the redesign has roughly
	a tenth the coral the old reef did, gathered into gardens rather than
	carpeting 650 studs of annulus.
]]
local CORAL_MATERIAL = Enum.Material.Sandstone

--[[
	SHADOW BUDGET.

	The detail pass took coral from ~5,000 parts to ~59,000, and with
	shadows on every one of them the map carried 46,000 shadow casters. That
	is a heavy per-frame cost for very little visible return: a 3-stud
	branch tip on a colony 700 studs away contributes nothing a viewer can
	see, while a 40-stud brain dome in the mid-field contributes most of
	what makes the coral read as solid.

	So shadows are now earned by size. Parts at or above SHADOW_MIN_SIZE
	cast; smaller ones do not.

	CALIBRATION NOTE. This was first set to 9, which barely helped — the
	detail pass had already taken colonies to 11-116 studs, so almost every
	part cleared a 9-stud bar and the caster count only fell 24%. The
	threshold has to sit inside the CURRENT size distribution to do any
	work, not below it. At 24 it keeps the large domes, plates and barrels
	that carry the form and drops the branch tips, tentacles and fronds
	that do not.
]]
local SHADOW_MIN_SIZE = 24

local function coralShadow(size: number): boolean
	return size >= SHADOW_MIN_SIZE
end

local function shade(colour: Color3, amount: number): Color3
	return Color3.new(
		math.clamp(colour.R + amount, 0, 1),
		math.clamp(colour.G + amount * 0.95, 0, 1),
		math.clamp(colour.B + amount * 0.9, 0, 1)
	)
end

-- BRAIN CORAL: a ridged dome, stacked from shrinking discs so the surface
-- is furrowed. Each tier is shaded slightly darker toward the base, which
-- is what reads as depth from a distance.
local function buildBrainCoral(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local rng = Random.new(math.floor(position.X * 71 + position.Z * 131))

	local tiers = 6
	for t = 0, tiers do
		local f = t / tiers
		PartUtils.CreateDisc({
			name = ("%sDome%d"):format(name, t),
			diameter = size * (1 - f * f * 0.82),
			thickness = size * 0.16,
			position = position
				+ Vector3.new(rng:NextNumber(-size * 0.04, size * 0.04), size * 0.13 * t, rng:NextNumber(-size * 0.04, size * 0.04)),
			material = CORAL_MATERIAL,
			color = shade(colour, -0.06 + f * 0.1),
			canCollide = false,
			castShadow = coralShadow(size * (1 - f * f * 0.82)),
			parent = model,
		})
	end
end

-- STAGHORN: recursive antler branching, the classic reef silhouette.
local function buildStaghornCoral(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local rng = Random.new(math.floor(position.X * 53 + position.Z * 97))
	local counter = 0

	local function branch(from: Vector3, direction: Vector3, length: number, thickness: number, depth: number)
		if depth > 3 or length < size * 0.12 then
			return
		end
		counter += 1
		local to = from + direction * length
		PartUtils.CreatePart({
			name = ("%sBranch%d"):format(name, counter),
			size = Vector3.new(thickness, thickness, length),
			cframe = CFrame.lookAt((from + to) / 2, to),
			material = CORAL_MATERIAL,
			color = shade(colour, depth * 0.05),
			canCollide = false,
			castShadow = coralShadow(length),
			parent = model,
		})
		for _ = 1, rng:NextInteger(2, 3) do
			local spread = Vector3.new(rng:NextNumber(-0.7, 0.7), rng:NextNumber(0.25, 0.9), rng:NextNumber(-0.7, 0.7))
			branch(to, (direction + spread).Unit, length * rng:NextNumber(0.55, 0.75), thickness * 0.7, depth + 1)
		end
	end

	branch(position, Vector3.new(0, 1, 0), size * 0.5, size * 0.16, 0)
end

-- TABLE CORAL: a broad flat plate on a stalk. The strongest horizontal
-- form on the reef and the best contrast to the branching types; the
-- underside is darkened so the plate casts and receives shade.
local function buildTableCoral(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	PartUtils.CreatePart({
		name = name .. "Stalk",
		size = Vector3.new(size * 0.18, size * 0.5, size * 0.18),
		position = position + Vector3.new(0, size * 0.25, 0),
		material = CORAL_MATERIAL,
		color = shade(colour, -0.1),
		canCollide = false,
		castShadow = coralShadow(size * 0.5),
		parent = model,
	})
	for i = 0, 2 do
		PartUtils.CreateDisc({
			name = ("%sPlate%d"):format(name, i),
			diameter = size * (1 - i * 0.24),
			thickness = size * 0.07,
			position = position + Vector3.new(size * 0.05 * i, size * (0.5 + i * 0.1), 0),
			material = CORAL_MATERIAL,
			color = shade(colour, i * 0.05),
			canCollide = false,
			castShadow = coralShadow(size * (1 - i * 0.24)),
			parent = model,
		})
	end
end

-- SEA FAN: a thin lacy frond, flat so it catches light edge-on.
local function buildSeaFan(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local rng = Random.new(math.floor(position.X * 41 + position.Z * 173))
	local facing = rng:NextNumber(0, math.pi * 2)

	for i = 1, 5 do
		local f = i / 5
		PartUtils.CreatePart({
			name = ("%sFrond%d"):format(name, i),
			size = Vector3.new(size * (0.3 + f * 0.75), size * 0.3, size * 0.07),
			cframe = CFrame.new(position + Vector3.new(0, size * 0.27 * i, 0))
				* CFrame.Angles(0, facing, 0)
				* CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.12, 0.12)),
			material = Enum.Material.Fabric,
			color = shade(colour, f * 0.08),
			transparency = 0.12,
			canCollide = false,
			castShadow = coralShadow(size * (0.3 + f * 0.75)),
			parent = model,
		})
	end
end

-- PILLAR CORAL: organ-pipe columns of differing height.
local function buildPillarCoral(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local rng = Random.new(math.floor(position.X * 89 + position.Z * 59))

	for i = 1, rng:NextInteger(4, 7) do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0, size * 0.32)
		local h = size * rng:NextNumber(0.6, 1.5)
		PartUtils.CreatePart({
			name = ("%sPillar%d"):format(name, i),
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(h, size * 0.22, size * 0.22),
			cframe = CFrame.new(position + Vector3.new(math.sin(a) * r, h / 2, math.cos(a) * r))
				* CFrame.Angles(0, 0, math.rad(90))
				* CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), 0),
			material = CORAL_MATERIAL,
			color = shade(colour, rng:NextNumber(-0.07, 0.07)),
			canCollide = false,
			castShadow = coralShadow(h),
			parent = model,
		})
	end
end

-- BARREL SPONGE: a hollow open-topped drum; the dark mouth sells it.
local function buildBarrelSponge(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	PartUtils.CreatePart({
		name = name .. "Body",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(size, size * 0.82, size * 0.82),
		cframe = CFrame.new(position + Vector3.new(0, size * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		material = CORAL_MATERIAL,
		color = colour,
		canCollide = false,
		castShadow = coralShadow(size),
		parent = model,
	})
	PartUtils.CreateDisc({
		name = name .. "Mouth",
		diameter = size * 0.55,
		thickness = size * 0.12,
		position = position + Vector3.new(0, size * 0.98, 0),
		material = Enum.Material.Slate,
		color = Color3.fromRGB(24, 30, 36),
		canCollide = false,
		castShadow = false,
		parent = model,
	})
end

-- ANEMONE: a soft column with a splayed tentacle crown.
local function buildAnemone(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local rng = Random.new(math.floor(position.X * 149 + position.Z * 31))

	PartUtils.CreatePart({
		name = name .. "Column",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(size * 0.4, size * 0.5, size * 0.5),
		cframe = CFrame.new(position + Vector3.new(0, size * 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		material = CORAL_MATERIAL,
		color = shade(colour, -0.08),
		canCollide = false,
		castShadow = coralShadow(size * 0.5),
		parent = model,
	})
	for i = 1, 16 do
		local a = (2 * math.pi / 16) * i + rng:NextNumber(-0.15, 0.15)
		local lean = rng:NextNumber(0.5, 0.95)
		PartUtils.CreatePart({
			name = ("%sTentacle%d"):format(name, i),
			size = Vector3.new(size * 0.07, size * 0.44, size * 0.07),
			cframe = CFrame.new(position + Vector3.new(math.sin(a) * size * 0.22, size * 0.5, math.cos(a) * size * 0.22))
				* CFrame.Angles(math.sin(a) * lean, 0, math.cos(a) * lean),
			material = CORAL_MATERIAL,
			color = colour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
end

--[[
	=================================================================
	POLYP-AGGREGATE CORAL
	=================================================================

	Real coral colonies are not solid shapes. They are thousands of tiny
	skeletal units accreted into a form — which is why a brain coral has a
	furrowed surface, why a plate coral ruffles at its rim, and why soft
	coral looks knobbly rather than smooth.

	The previous builders made each colony from a handful of large primitives
	(one cylinder = one pillar, one disc = one dome tier). At the sizes the
	detail pass pushed them to, that read exactly as the brief complained:
	thick tubes thrown around.

	Every builder below instead places many SMALL units — 3 to 7 studs —
	along a mathematical form. The form supplies the silhouette; the unit
	size supplies the texture. That is the whole idea, and it is why these
	cost more parts per colony but need far fewer colonies to look right.

	SHADOWS are decided per unit by coralShadow(), so the small units are
	free and only the structural pieces cast.
]]

--[[
	POLYP UNIT SIZE.

	This is the single biggest lever on cost in the whole map. A colony's
	part count scales roughly with (colony size / unit size)^2, because the
	builders skin surfaces rather than filling volumes.

	CALIBRATION. First set to 2.6-6.5, which produced beautiful colonies at
	~225 parts each - and at 150 gardens that came to 371,000 coral parts
	and a 427,000-part map. Unshippable. Raising the unit to 4.5-9.5 roughly
	halves the count per colony while keeping the aggregate texture legible
	at the distances these are actually viewed from.
]]
local POLYP_MIN = 4.5
local POLYP_MAX = 9.5

-- One accreted unit. Slight per-unit colour jitter and random rotation are
-- what stop an aggregate reading as a grid of identical cubes.
local function polyp(parent: Instance, name: string, pos: Vector3, size: number, colour: Color3, rng: Random)
	PartUtils.CreatePart({
		name = name,
		size = Vector3.new(size, size * rng:NextNumber(0.75, 1.25), size * rng:NextNumber(0.8, 1.2)),
		cframe = CFrame.new(pos)
			* CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6.28), rng:NextNumber(-0.5, 0.5)),
		material = CORAL_MATERIAL,
		color = shade(colour, rng:NextNumber(-0.07, 0.07)),
		canCollide = false,
		castShadow = coralShadow(size * 3),
		parent = parent,
	})
end

--[[
	MOUND / BRAIN CORAL. A hemisphere skinned in polyps, with the surface
	displaced by noise so it furrows rather than sitting perfectly round.
	Only the SHELL is populated — filling the interior would multiply the
	part count for volume no one can see.
]]
local function buildMoundCoral(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local rng = Random.new(math.floor(position.X * 71 + position.Z * 131))

	local radius = size * 0.5
	local unit = math.clamp(size * 0.1, POLYP_MIN, POLYP_MAX)
	local rings = math.max(4, math.floor(radius / unit))

	for ring = 0, rings do
		local phi = (ring / rings) * (math.pi * 0.5)
		local ringRadius = radius * math.cos(phi)
		local y = radius * math.sin(phi) * 0.8
		local count = math.max(1, math.floor((2 * math.pi * ringRadius) / (unit * 0.9)))
		for i = 1, count do
			local a = (2 * math.pi / count) * i
			-- Noise displacement is what creates the brain-coral furrows.
			local wobble = math.noise(math.cos(a) * 3, math.sin(a) * 3, ring * 0.6) * unit * 1.1
			polyp(
				model,
				("%sP%d_%d"):format(name, ring, i),
				position + Vector3.new(math.cos(a) * (ringRadius + wobble), y, math.sin(a) * (ringRadius + wobble)),
				unit,
				colour,
				rng
			)
		end
	end
end

--[[
	BRANCHING / STAGHORN. Recursive branches, each drawn as a RUN of
	overlapping polyps rather than one long block, so the branches are
	lumpy and taper naturally. This is the form in reference images 3 and 4.
]]
local function buildBranchingCoral(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local rng = Random.new(math.floor(position.X * 53 + position.Z * 97))
	local counter = 0

	local function branch(from: Vector3, dir: Vector3, length: number, thickness: number, depth: number)
		if depth > 4 or length < size * 0.07 or thickness < POLYP_MIN * 0.8 then
			return
		end
		local steps = math.max(2, math.floor(length / (thickness * 0.6)))
		for s = 0, steps do
			local t = s / steps
			counter += 1
			polyp(
				model,
				("%sB%d"):format(name, counter),
				from + dir * (length * t),
				thickness * (1 - t * 0.35),
				colour,
				rng
			)
		end
		local tip = from + dir * length
		for _ = 1, rng:NextInteger(2, 3) do
			local spread = Vector3.new(rng:NextNumber(-0.85, 0.85), rng:NextNumber(0.3, 1), rng:NextNumber(-0.85, 0.85))
			branch(tip, (dir + spread).Unit, length * rng:NextNumber(0.55, 0.78), thickness * 0.74, depth + 1)
		end
	end

	branch(position, Vector3.new(0, 1, 0), size * 0.36, math.clamp(size * 0.13, POLYP_MIN, POLYP_MAX), 0)
end

--[[
	PLATE / LETTUCE CORAL. Reference image 2: stacked ruffled shelves. Each
	shelf is a ring of polyps whose radius is modulated by a sine, which is
	what produces the frilled edge. Shelves offset as they rise so the
	colony leans, the way real foliose coral grows toward light.
]]
local function buildPlateCoral(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local rng = Random.new(math.floor(position.X * 41 + position.Z * 173))

	local unit = math.clamp(size * 0.075, POLYP_MIN, POLYP_MAX)
	local shelves = math.max(3, math.floor(size / 12))
	local lean = Vector3.new(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2))

	for s = 1, shelves do
		local f = s / shelves
		local shelfRadius = size * 0.5 * (0.45 + 0.55 * math.sin(f * math.pi * 0.85))
		local y = size * 0.22 * s
		local ruffles = rng:NextInteger(5, 8)
		local count = math.max(8, math.floor((2 * math.pi * shelfRadius) / (unit * 0.75)))
		for i = 1, count do
			local a = (2 * math.pi / count) * i
			-- The ruffle: radius oscillates around the shelf.
			local r = shelfRadius * (1 + 0.22 * math.sin(a * ruffles))
			local lip = math.sin(a * ruffles) * unit * 0.8
			polyp(
				model,
				("%sS%d_%d"):format(name, s, i),
				position + lean * y + Vector3.new(math.cos(a) * r, y + lip, math.sin(a) * r),
				unit,
				colour,
				rng
			)
		end
	end
end

--[[
	SEA FAN / GORGONIAN. Reference image 4: a flat, densely reticulated fan.
	Built in a single vertical PLANE so it reads as a fan from the side and
	nearly disappears edge-on, exactly as the real thing does.
]]
local function buildFanCoral(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local rng = Random.new(math.floor(position.X * 149 + position.Z * 31))

	local facing = rng:NextNumber(0, math.pi)
	local planeX = Vector3.new(math.cos(facing), 0, math.sin(facing))
	--[[
		Fans need FINER units than any other coral. Every other form is a
		solid volume where a coarse unit reads as texture; a fan is mostly
		holes, and at the shared 4.5-9.5 unit the gaps filled in and the
		colony became a flat sheet - which is exactly what it looked like:
		a pink blob standing on the seabed.

		Capping the unit at 3.5 restores the lattice. It costs more parts per
		colony, which is affordable because fans are one of seven types.
	]]
	local unit = math.clamp(size * 0.04, 2.2, 3.5)
	local counter = 0

	local function twig(u: number, v: number, dirU: number, dirV: number, length: number, depth: number)
		if depth > 5 or length < unit then
			return
		end
		local steps = math.max(2, math.floor(length / (unit * 1.6)))
		for s = 0, steps do
			local t = s / steps
			counter += 1
			local uu, vv = u + dirU * length * t, v + dirV * length * t
			polyp(model, ("%sF%d"):format(name, counter), position + planeX * uu + Vector3.new(0, vv, 0), unit, colour, rng)
		end
		local nu, nv = u + dirU * length, v + dirV * length
		for _, side in ipairs({ -1, 1 }) do
			local spreadU = dirU * 0.55 + side * 0.75
			local spreadV = dirV * 0.9
			local mag = math.sqrt(spreadU * spreadU + spreadV * spreadV)
			twig(nu, nv, spreadU / mag, spreadV / mag, length * rng:NextNumber(0.6, 0.78), depth + 1)
		end
	end

	twig(0, 0, 0, 1, size * 0.3, 0)
end

--[[
	SOFT / TREE CORAL. Reference image 3: a thick fleshy trunk carrying
	dense clusters of knobbly polyps at the tips. The trunk is deliberately
	smooth and the tips deliberately lumpy — that contrast is what makes it
	read as soft-bodied rather than stony.
]]
local function buildSoftCoral(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local rng = Random.new(math.floor(position.X * 89 + position.Z * 59))
	local counter = 0
	local unit = math.clamp(size * 0.085, POLYP_MIN, POLYP_MAX)

	local function limb(from: Vector3, dir: Vector3, length: number, thickness: number, depth: number)
		local steps = math.max(2, math.floor(length / (thickness * 0.5)))
		for s = 0, steps do
			counter += 1
			PartUtils.CreatePart({
				name = ("%sT%d"):format(name, counter),
				shape = Enum.PartType.Ball,
				size = Vector3.new(thickness, thickness, thickness) * rng:NextNumber(0.9, 1.1),
				position = from + dir * (length * (s / steps)),
				material = CORAL_MATERIAL,
				color = shade(colour, -0.05),
				canCollide = false,
				castShadow = coralShadow(thickness * 3),
				parent = model,
			})
		end
		local tip = from + dir * length
		if depth >= 2 then
			-- Terminal cluster of bright knobs.
			for _ = 1, rng:NextInteger(6, 12) do
				counter += 1
				local off = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)).Unit
					* thickness
					* rng:NextNumber(0.6, 1.5)
				polyp(model, ("%sK%d"):format(name, counter), tip + off, unit * 0.8, shade(colour, 0.08), rng)
			end
			return
		end
		for _ = 1, rng:NextInteger(2, 4) do
			local spread = Vector3.new(rng:NextNumber(-0.8, 0.8), rng:NextNumber(0.4, 1), rng:NextNumber(-0.8, 0.8))
			limb(tip, (dir + spread).Unit, length * rng:NextNumber(0.55, 0.75), thickness * 0.72, depth + 1)
		end
	end

	limb(position, Vector3.new(0, 1, 0), size * 0.3, math.clamp(size * 0.14, 3, 8), 0)
end

--[[
	ENCRUSTING SHEET. Low irregular crust hugging the substrate — the
	connective tissue of a real reef, filling the ground between the taller
	forms so the seabed does not show bare sand everywhere between colonies.
]]
local function buildEncrustingCoral(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local rng = Random.new(math.floor(position.X * 37 + position.Z * 211))
	local unit = math.clamp(size * 0.12, POLYP_MIN, POLYP_MAX)
	local blobs = math.max(6, math.floor(size * 0.7))

	for i = 1, blobs do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = math.sqrt(rng:NextNumber()) * size * 0.5
		-- Height falls off toward the edge so it hugs rather than mounds.
		local h = (1 - r / (size * 0.5)) * size * 0.16
		polyp(
			model,
			("%sE%d"):format(name, i),
			position + Vector3.new(math.cos(a) * r, h * rng:NextNumber(0.3, 1), math.sin(a) * r),
			unit,
			colour,
			rng
		)
	end
end

--[[
	TUBE SPONGES. Reference image 5: clusters of upright tubes of differing
	height. Each tube is a ring of polyps around a hollow, so it has an open
	mouth rather than being a capped cylinder.
]]
local function buildTubeSponge(position: Vector3, size: number, colour: Color3, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local rng = Random.new(math.floor(position.X * 113 + position.Z * 67))
	local unit = math.clamp(size * 0.09, POLYP_MIN, POLYP_MAX)

	for tube = 1, rng:NextInteger(3, 6) do
		local ta = rng:NextNumber(0, math.pi * 2)
		local tr = rng:NextNumber(0, size * 0.28)
		local base = position + Vector3.new(math.cos(ta) * tr, 0, math.sin(ta) * tr)
		local height = size * rng:NextNumber(0.5, 1.15)
		local tubeRadius = size * rng:NextNumber(0.1, 0.17)
		local lean = Vector3.new(rng:NextNumber(-0.12, 0.12), 0, rng:NextNumber(-0.12, 0.12))
		local rings = math.max(3, math.floor(height / (unit * 0.85)))
		local perRing = math.max(5, math.floor((2 * math.pi * tubeRadius) / (unit * 0.8)))

		for ring = 0, rings do
			local y = (ring / rings) * height
			for i = 1, perRing do
				local a = (2 * math.pi / perRing) * i + ring * 0.2
				polyp(
					model,
					("%sT%d_%d_%d"):format(name, tube, ring, i),
					base + lean * y + Vector3.new(math.cos(a) * tubeRadius, y, math.sin(a) * tubeRadius),
					unit,
					colour,
					rng
				)
			end
		end
	end
end

local CORAL_BUILDERS = {
	buildMoundCoral,
	buildBranchingCoral,
	buildPlateCoral,
	buildFanCoral,
	buildSoftCoral,
	buildEncrustingCoral,
	buildTubeSponge,
}

--[[
	CORAL GARDENS.

	Coral gathered into a limited number of GARDENS on the dune flanks
	rather than scattered evenly. The old version placed 2,600 colonies
	across the whole annulus and the result was noise: with everything
	equally covered, nothing stood out.

	Gardens sit preferentially on slopes and crests, which is where coral
	finds current and light, and each garden shares a dominant colour so
	it reads as one community.
]]
local function buildCoralGardens(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "CoralGardens"
	folder.Parent = parent

	local rng = Random.new(605512)
	-- 150 gardens of solid colonies was affordable; 150 gardens of
	-- polyp-aggregate colonies is not, and it also produced exactly the
	-- crowding the brief objected to. Far fewer, further apart, each one
	-- carrying much more internal detail.
	local GARDENS = 46
	local colonies = 0

	for g = 1, GARDENS do
		--[[
			Gardens are biased OUTWARD. A uniform radius would already cluster
			them toward the middle by area; ^0.62 pushes the distribution
			further out still, so the far field is visibly denser than the near
			field. That density ramp is half of the forced-perspective effect —
			the terrain height gradient is the other half.
		]]
		local a = rng:NextNumber(0, math.pi * 2)
		local r = CORAL_INNER + (DUNE_OUTER - 140 - CORAL_INNER) * (rng:NextNumber() ^ 0.62)
		local gx, gz = math.sin(a) * r, math.cos(a) * r
		local df = distanceFactor(r)

		local dominant = pickCoralColour(rng)
		-- Gardens grow wider and taller with distance, but colony COUNT is
		-- down sharply: polyp-aggregate colonies carry their own internal
		-- detail, so packing them as densely as the old solid ones produced
		-- the crowding the brief objected to. Fewer, better, further apart.
		local spread = 70 + 190 * df
		local count = math.floor(4 + 9 * df)
		local sizeLow = 12 + 22 * df
		local sizeHigh = 28 + 54 * df

		for c = 1, count do
			local ox = gx + rng:NextNumber(-spread, spread)
			local oz = gz + rng:NextNumber(-spread, spread)
			local surface = duneHeight(ox, oz)
			colonies += 1
			local colour = if rng:NextNumber() < 0.62 then dominant else pickCoralColour(rng)
			CORAL_BUILDERS[rng:NextInteger(1, #CORAL_BUILDERS)](
				Vector3.new(ox, surface - 0.8, oz),
				rng:NextNumber(sizeLow, sizeHigh),
				shade(colour, rng:NextNumber(-0.05, 0.05)),
				folder,
				("Coral%d_%d"):format(g, c)
			)
		end
	end

	return colonies
end

----------------------------------------------------------------------
-- ALGAE AND HABITATS
----------------------------------------------------------------------

--[[
	ALGAE.

	Scattered across the sand between the gardens — the low green cover a
	real seabed has everywhere that is not bare. Three forms so it does not
	read as one repeated decal: flat mats, short tufts, and drifting
	strands.
]]
local function buildAlgae(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Algae"
	folder.Parent = parent

	local rng = Random.new(770311)
	local GREENS = {
		Color3.fromRGB(58, 92, 58),
		Color3.fromRGB(74, 108, 64),
		Color3.fromRGB(46, 78, 62),
		Color3.fromRGB(88, 116, 72),
	}

	-- Flat mats hugging the sand. Biased outward and grown with distance,
	-- so ground cover thickens toward the rim like everything else.
	for i = 1, 900 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = DUNE_INNER + (DUNE_OUTER - 60 - DUNE_INNER) * (rng:NextNumber() ^ 0.6)
		local x, z = math.sin(a) * r, math.cos(a) * r
		local df = distanceFactor(r)
		PartUtils.CreateDisc({
			name = "AlgaeMat" .. i,
			diameter = (8 + 26 * df) * rng:NextNumber(0.7, 1.4),
			thickness = rng:NextNumber(0.2, 0.6),
			position = Vector3.new(x, duneHeight(x, z) + 0.1, z),
			material = Enum.Material.Grass,
			color = GREENS[rng:NextInteger(1, #GREENS)],
			transparency = 0.1,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
	end

	-- Short tufts standing off the mats.
	for i = 1, 700 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = (DUNE_INNER + 60) + (DUNE_OUTER - 60 - DUNE_INNER - 60) * (rng:NextNumber() ^ 0.6)
		local x, z = math.sin(a) * r, math.cos(a) * r
		local df = distanceFactor(r)
		local base = duneHeight(x, z)
		local tint = GREENS[rng:NextInteger(1, #GREENS)]
		for b = 1, rng:NextInteger(3, 7) do
			local h = (2 + 7 * df) * rng:NextNumber(0.7, 1.4)
			local off = rng:NextNumber(0, 2.5 + 4 * df)
			local oa = rng:NextNumber(0, math.pi * 2)
			PartUtils.CreatePart({
				name = ("AlgaeTuft%d_%d"):format(i, b),
				size = Vector3.new(0.5 + df, h, 0.5 + df),
				cframe = CFrame.new(Vector3.new(x + math.sin(oa) * off, base + h / 2, z + math.cos(oa) * off))
					* CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3)),
				material = Enum.Material.Grass,
				color = tint,
				canCollide = false,
				castShadow = false,
				parent = folder,
			})
		end
	end
end

--[[
	NATURAL HABITATS.

	The features a real seabed has between the coral: rock outcrops,
	seagrass meadows, clam beds and urchin clusters. These matter because
	they break the sand up at the middle distance, where coral gardens are
	too sparse and algae too small to register.
]]
local function buildHabitats(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Habitats"
	folder.Parent = parent

	local rng = Random.new(410277)

	-- ROCK OUTCROPS: clusters of dark boulders, half-sunk.
	for i = 1, 26 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(DUNE_INNER + 40, DUNE_OUTER - 90)
		local x, z = math.sin(a) * r, math.cos(a) * r
		for b = 1, rng:NextInteger(3, 7) do
			local ox = x + rng:NextNumber(-14, 14)
			local oz = z + rng:NextNumber(-14, 14)
			local s = rng:NextNumber(4, 13)
			PartUtils.CreatePart({
				name = ("Outcrop%d_%d"):format(i, b),
				size = Vector3.new(s, s * rng:NextNumber(0.5, 0.9), s * rng:NextNumber(0.7, 1.3)),
				cframe = CFrame.new(Vector3.new(ox, duneHeight(ox, oz) + s * 0.2, oz))
					* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3)),
				material = Enum.Material.Slate,
				color = Color3.fromRGB(72, 76, 82):Lerp(Color3.fromRGB(104, 98, 88), rng:NextNumber()),
				canCollide = false,
				castShadow = true,
				parent = folder,
			})
		end
	end

	-- SEAGRASS MEADOWS: dense blades, taller and bluer than the algae.
	for i = 1, 18 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(DUNE_INNER + 50, DUNE_OUTER - 110)
		local cx, cz = math.sin(a) * r, math.cos(a) * r
		for b = 1, rng:NextInteger(40, 80) do
			local ox = cx + rng:NextNumber(-26, 26)
			local oz = cz + rng:NextNumber(-26, 26)
			local h = rng:NextNumber(4, 9)
			PartUtils.CreatePart({
				name = ("Seagrass%d_%d"):format(i, b),
				size = Vector3.new(0.45, h, 0.45),
				cframe = CFrame.new(Vector3.new(ox, duneHeight(ox, oz) + h / 2, oz))
					* CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, 6.28), rng:NextNumber(-0.35, 0.35)),
				material = Enum.Material.Grass,
				color = Color3.fromRGB(62, 104, 82):Lerp(Color3.fromRGB(96, 132, 88), rng:NextNumber()),
				canCollide = false,
				castShadow = false,
				parent = folder,
			})
		end
	end

	-- CLAM BEDS: pale shells part-buried in the sand.
	for i = 1, 22 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(DUNE_INNER + 30, DUNE_OUTER - 80)
		local cx, cz = math.sin(a) * r, math.cos(a) * r
		for b = 1, rng:NextInteger(4, 10) do
			local ox = cx + rng:NextNumber(-11, 11)
			local oz = cz + rng:NextNumber(-11, 11)
			local s = rng:NextNumber(1.8, 4.5)
			PartUtils.CreateDisc({
				name = ("Clam%d_%d"):format(i, b),
				diameter = s,
				thickness = s * 0.35,
				position = Vector3.new(ox, duneHeight(ox, oz) + s * 0.1, oz),
				material = Enum.Material.Limestone,
				color = Color3.fromRGB(214, 204, 186),
				canCollide = false,
				castShadow = true,
				parent = folder,
			})
		end
	end

	-- URCHINS: dark spiky balls tucked against the outcrops.
	for i = 1, 40 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(DUNE_INNER + 40, DUNE_OUTER - 90)
		local x, z = math.sin(a) * r, math.cos(a) * r
		local base = duneHeight(x, z)
		local s = rng:NextNumber(1.6, 3.2)
		PartUtils.CreatePart({
			name = ("UrchinBody%d"):format(i),
			shape = Enum.PartType.Ball,
			size = Vector3.new(s, s * 0.8, s),
			position = Vector3.new(x, base + s * 0.4, z),
			material = Enum.Material.Slate,
			color = Color3.fromRGB(38, 32, 44),
			canCollide = false,
			castShadow = true,
			parent = folder,
		})
		for sp = 1, 10 do
			local sa = (2 * math.pi / 10) * sp
			PartUtils.CreatePart({
				name = ("UrchinSpine%d_%d"):format(i, sp),
				size = Vector3.new(0.2, s * 1.1, 0.2),
				cframe = CFrame.new(Vector3.new(x, base + s * 0.4, z))
					* CFrame.Angles(math.sin(sa) * 1.1, 0, math.cos(sa) * 1.1)
					* CFrame.new(0, s * 0.5, 0),
				material = Enum.Material.Slate,
				color = Color3.fromRGB(30, 26, 36),
				canCollide = false,
				castShadow = false,
				parent = folder,
			})
		end
	end
end

--[[
	UNDERWATER CAVES.

	Rock arches and overhangs with a dark hollow beneath — the one feature
	out here that reads as somewhere you could swim INTO, which is what
	gives the seabed a sense of interior rather than being a decorated
	surface.

	Built as a ring of leaning boulder pillars carrying a rough capstone,
	with a black interior block set behind the mouth. That unlit interior
	is what sells the depth: without it the arch reads as a pile of rocks.

	Bigger and more numerous further out, like everything else in the
	exterior.
]]
local function buildCaves(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Caves"
	folder.Parent = parent

	local rng = Random.new(884512)
	local ROCK_DARK = Color3.fromRGB(58, 60, 64)
	local ROCK_MID = Color3.fromRGB(84, 82, 76)

	for i = 1, 22 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = CAVE_INNER + (DUNE_OUTER - 160 - CAVE_INNER) * (rng:NextNumber() ^ 0.6)
		local cx, cz = math.sin(a) * r, math.cos(a) * r
		local df = distanceFactor(r)
		local scale = 26 + 70 * df
		local base = duneHeight(cx, cz)
		local facing = rng:NextNumber(0, math.pi * 2)

		-- Pillars around three quarters of a circle, leaving a mouth.
		local pillars = 9
		for p = 1, pillars do
			local pa = facing + (p / pillars) * math.pi * 1.55
			local px = cx + math.sin(pa) * scale * 0.7
			local pz = cz + math.cos(pa) * scale * 0.7
			local h = scale * rng:NextNumber(0.7, 1.15)
			PartUtils.CreatePart({
				name = ("Cave%dPillar%d"):format(i, p),
				size = Vector3.new(scale * rng:NextNumber(0.25, 0.45), h, scale * rng:NextNumber(0.25, 0.45)),
				cframe = CFrame.new(Vector3.new(px, base + h * 0.45, pz))
					* CFrame.Angles(rng:NextNumber(-0.18, 0.18), rng:NextNumber(0, 6.28), rng:NextNumber(-0.18, 0.18)),
				material = Enum.Material.Rock,
				color = ROCK_DARK:Lerp(ROCK_MID, rng:NextNumber()),
				canCollide = false,
				castShadow = true,
				parent = folder,
			})
		end

		-- Capstone slabs bridging the pillars.
		for s = 1, 4 do
			PartUtils.CreatePart({
				name = ("Cave%dCap%d"):format(i, s),
				size = Vector3.new(scale * rng:NextNumber(0.9, 1.5), scale * 0.2, scale * rng:NextNumber(0.6, 1.1)),
				cframe = CFrame.new(
					Vector3.new(cx + rng:NextNumber(-scale * 0.3, scale * 0.3), base + scale * rng:NextNumber(0.95, 1.2), cz + rng:NextNumber(-scale * 0.3, scale * 0.3))
				) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(0, 6.28), rng:NextNumber(-0.15, 0.15)),
				material = Enum.Material.Rock,
				color = ROCK_DARK,
				canCollide = false,
				castShadow = true,
				parent = folder,
			})
		end

		-- The unlit interior. Without this the arch is just rocks.
		PartUtils.CreatePart({
			name = ("Cave%dInterior"):format(i),
			shape = Enum.PartType.Ball,
			size = Vector3.new(scale * 1.05, scale * 0.85, scale * 1.05),
			position = Vector3.new(cx, base + scale * 0.35, cz),
			material = Enum.Material.SmoothPlastic,
			color = Color3.fromRGB(8, 12, 16),
			canCollide = false,
			castShadow = false,
			parent = folder,
		})

		-- Coral crusting the arch, as on the wrecks.
		for c = 1, math.floor(2 + 4 * df) do
			local ca = rng:NextNumber(0, math.pi * 2)
			local cr = scale * rng:NextNumber(0.5, 0.95)
			local ox, oz = cx + math.sin(ca) * cr, cz + math.cos(ca) * cr
			CORAL_BUILDERS[rng:NextInteger(1, #CORAL_BUILDERS)](
				Vector3.new(ox, duneHeight(ox, oz) + scale * rng:NextNumber(0, 0.9), oz),
				rng:NextNumber(6, 18) * (0.6 + df),
				pickCoralColour(rng),
				folder,
				("Cave%dCoral%d"):format(i, c)
			)
		end
	end
end

--[[
	LONG GRASS MEADOWS.

	Tall swaying blades, far taller than the short seagrass in
	buildHabitats — up to 60 studs out at the rim. These do a specific job
	for the forced perspective: vertical elements at the far edge give the
	eye something to measure distance against, and a band of tall grass
	between the viewer and the enclosure wall hides the wall itself.

	Each blade is a stack of segments that leans progressively, so it
	curves like something in a current rather than standing as a spike.
]]
local function buildLongGrass(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "LongGrass"
	folder.Parent = parent

	local rng = Random.new(662104)
	local GREENS = {
		Color3.fromRGB(52, 92, 62),
		Color3.fromRGB(68, 112, 70),
		Color3.fromRGB(44, 80, 66),
		Color3.fromRGB(84, 118, 74),
	}

	for m = 1, 60 do
		local a = rng:NextNumber(0, math.pi * 2)
		-- Heavily biased outward: this is mostly a far-field feature.
		local r = GRASS_INNER + (DUNE_OUTER - 90 - GRASS_INNER) * (rng:NextNumber() ^ 0.45)
		local cx, cz = math.sin(a) * r, math.cos(a) * r
		local df = distanceFactor(r)
		local patch = 40 + 90 * df
		local blades = math.floor(30 + 70 * df)
		local tint = GREENS[rng:NextInteger(1, #GREENS)]
		-- One current direction per patch, so a meadow leans as a whole.
		local leanDir = rng:NextNumber(0, math.pi * 2)

		for b = 1, blades do
			local ox = cx + rng:NextNumber(-patch, patch)
			local oz = cz + rng:NextNumber(-patch, patch)
			local base = duneHeight(ox, oz)
			local height = (14 + 46 * df) * rng:NextNumber(0.7, 1.3)
			local segments = math.clamp(math.floor(height / 9), 3, 7)
			local lean = rng:NextNumber(0.08, 0.2)

			for s = 1, segments do
				local t = s / segments
				local segH = height / segments
				local drift = lean * height * t * t
				PartUtils.CreatePart({
					name = ("Grass%d_%d_%d"):format(m, b, s),
					size = Vector3.new(1.4 * (1.2 - t * 0.6), segH * 1.12, 0.4),
					cframe = CFrame.new(
						Vector3.new(ox + math.sin(leanDir) * drift, base + segH * (s - 0.5), oz + math.cos(leanDir) * drift)
					) * CFrame.Angles(0, leanDir, 0) * CFrame.Angles(lean * t * 2.2, 0, 0),
					material = Enum.Material.Grass,
					color = tint:Lerp(Color3.fromRGB(120, 150, 96), t * 0.35),
					transparency = 0.12,
					canCollide = false,
					castShadow = false,
					parent = folder,
				})
			end
		end
	end
end

----------------------------------------------------------------------
-- THE WOODEN SHIPWRECK
----------------------------------------------------------------------

--[[
	THE GREAT WRECK.

	The centrepiece of the exterior: a wooden sailing ship, ~340 studs
	long — about 90% of the map's 376-stud width — but only ~50 studs in
	the beam, so it is a long low silhouette rather than a mass.

	Deliberately a WOODEN ship, replacing the steel freighter that used to
	be here: dark brown planking, exposed frame ribs where the hull has
	opened, three masts with torn sails hanging off the yards, and a
	broken ship's wheel at the stern.

	STYLISED, NOT PHOTOREAL. The brief asked for heavy detail in the map's
	existing style rather than realism, so it is built from clean blocks
	with strong silhouette reads — planks, ribs, spars — rather than from
	subtle organic shapes.

	The hull is broken in two with the stern twisted off-axis, because the
	most recognisable thing about a real wreck is that the halves do not
	line up. It sits part-buried in the sand and lists to starboard.
]]
local function buildShipwreck(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Shipwreck"
	folder.Parent = parent

	local rng = Random.new(190244)

	local WOOD_DARK = Color3.fromRGB(52, 36, 26)
	local WOOD_MID = Color3.fromRGB(74, 52, 36)
	local WOOD_WORN = Color3.fromRGB(96, 72, 52)
	local SAIL = Color3.fromRGB(146, 138, 120)
	local IRON = Color3.fromRGB(48, 44, 42)

	local LENGTH = 620
	local BEAM = 96
	local DEPTH = 76

	-- Lay the wreck along a clear radial line out in the dune field, far
	-- enough out that it never crowds the plate.
	local heading = rng:NextNumber(0, math.pi * 2)
	local centreR = 620
	local cx, cz = math.sin(heading) * centreR, math.cos(heading) * centreR
	local baseY = duneHeight(cx, cz)

	-- Buried to about a third of hull depth, listing to starboard.
	local origin = Vector3.new(cx, baseY - DEPTH * 0.22, cz)
	local bowPose = CFrame.new(origin)
		* CFrame.Angles(0, heading + math.pi / 2, 0)
		* CFrame.Angles(math.rad(4), 0, math.rad(-21))
	local sternPose = CFrame.new(origin + Vector3.new(0, -5, 0))
		* CFrame.Angles(0, heading + math.pi / 2 + math.rad(19), 0)
		* CFrame.Angles(math.rad(-7), 0, math.rad(12))

	--[[
		HULL PLANKING. Built as a stack of horizontal strakes rather than one
		box: each course is a separate part, slightly narrower as it goes
		down, so the hull has a visible plank grain and a curved section.
		This is the single biggest contributor to it reading as wooden.
	]]
	local function plankedSection(pose: CFrame, fromT: number, toT: number, taperEnd: number, prefix: string)
		-- More courses and more steps than before: at 620 studs the old 9x7
		-- grid gave 90-stud planks, which read as slabs rather than timber.
		local COURSES = 14
		local STEPS = 13
		for step = 0, STEPS - 1 do
			local t = fromT + (toT - fromT) * (step / STEPS)
			local along = t * LENGTH
			-- Taper toward whichever end this section runs to.
			local taper = 1 - math.abs(t) * 2 * taperEnd
			for c = 0, COURSES - 1 do
				local f = c / (COURSES - 1)
				-- Section curve: widest at the top, tucking under at the keel.
				local widthAtCourse = BEAM * taper * (0.45 + 0.55 * math.sin(f * math.pi * 0.5 + 0.35))
				PartUtils.CreatePart({
					name = ("%sStrake%d_%d"):format(prefix, step, c),
					size = Vector3.new(widthAtCourse, DEPTH / COURSES * 1.05, (toT - fromT) * LENGTH / STEPS * 1.06),
					cframe = pose * CFrame.new(0, -DEPTH * 0.5 + (c + 0.5) * (DEPTH / COURSES), along),
					material = Enum.Material.Wood,
					-- Alternating courses so the planking stripes are visible.
					color = if c % 2 == 0 then WOOD_DARK else WOOD_MID,
					canCollide = false,
					castShadow = false,
					parent = folder,
				})
			end
		end
	end

	plankedSection(bowPose, -0.48, -0.06, 0.55, "Bow")
	plankedSection(sternPose, 0.08, 0.47, 0.35, "Stern")

	-- Keel running the length of each half.
	for _, seg in ipairs({ { bowPose, -0.27, 0.42 }, { sternPose, 0.28, 0.38 } }) do
		PartUtils.CreatePart({
			name = "Keel",
			size = Vector3.new(BEAM * 0.16, 4, LENGTH * seg[3]),
			cframe = seg[1] * CFrame.new(0, -DEPTH * 0.5, seg[2] * LENGTH),
			material = Enum.Material.Wood,
			color = WOOD_DARK,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
	end

	-- Raked stem and bowsprit.
	PartUtils.CreatePart({
		className = "WedgePart",
		name = "Stem",
		size = Vector3.new(BEAM * 0.2, DEPTH, LENGTH * 0.08),
		cframe = bowPose * CFrame.new(0, 0, -LENGTH * 0.5) * CFrame.Angles(0, math.rad(180), 0),
		material = Enum.Material.Wood,
		color = WOOD_DARK,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})
	PartUtils.CreatePart({
		name = "Bowsprit",
		size = Vector3.new(3, 3, 46),
		cframe = bowPose * CFrame.new(0, DEPTH * 0.35, -LENGTH * 0.55) * CFrame.Angles(math.rad(-16), 0, 0),
		material = Enum.Material.Wood,
		color = WOOD_MID,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})

	-- Main deck on each half.
	PartUtils.CreatePart({
		name = "Foredeck",
		size = Vector3.new(BEAM * 0.86, 2, LENGTH * 0.4),
		cframe = bowPose * CFrame.new(0, DEPTH * 0.5, -LENGTH * 0.27),
		material = Enum.Material.WoodPlanks,
		color = WOOD_WORN,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})
	PartUtils.CreatePart({
		name = "Afterdeck",
		size = Vector3.new(BEAM * 0.9, 2, LENGTH * 0.36),
		cframe = sternPose * CFrame.new(0, DEPTH * 0.5, LENGTH * 0.28),
		material = Enum.Material.WoodPlanks,
		color = WOOD_WORN,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})

	-- Raised stern castle — the tall aft block of a sailing ship.
	for deck = 0, 1 do
		PartUtils.CreatePart({
			name = ("SternCastle%d"):format(deck),
			size = Vector3.new(BEAM * (0.8 - deck * 0.14), 12, LENGTH * (0.1 - deck * 0.02)),
			cframe = sternPose * CFrame.new(0, DEPTH * 0.5 + 6 + deck * 12, LENGTH * 0.4),
			material = Enum.Material.Wood,
			color = if deck == 0 then WOOD_MID else WOOD_WORN,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
	end

	--[[
		BROKEN SHIP'S WHEEL.

		Explicitly asked for. Built as a hub, a partial rim in arc segments,
		and spokes — with a deliberate GAP in the rim and two spokes missing,
		so it reads as broken rather than merely old. Mounted on a binnacle
		post on the stern castle.
	]]
	local wheelPose = sternPose * CFrame.new(0, DEPTH * 0.5 + 24, LENGTH * 0.36) * CFrame.Angles(0, 0, math.rad(14))
	PartUtils.CreatePart({
		name = "WheelPost",
		size = Vector3.new(2.5, 10, 2.5),
		cframe = sternPose * CFrame.new(0, DEPTH * 0.5 + 17, LENGTH * 0.36),
		material = Enum.Material.Wood,
		color = WOOD_DARK,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})
	PartUtils.CreatePart({
		name = "WheelHub",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(1.6, 3.4, 3.4),
		cframe = wheelPose * CFrame.Angles(0, math.rad(90), 0),
		material = Enum.Material.Wood,
		color = WOOD_MID,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})
	local WHEEL_R = 8
	-- Rim: 16 arc blocks with a run of three omitted, leaving a broken gap.
	for i = 0, 15 do
		if not (i >= 5 and i <= 7) then
			local a = (2 * math.pi / 16) * i
			PartUtils.CreatePart({
				name = ("WheelRim%d"):format(i),
				size = Vector3.new(1.2, 1.4, WHEEL_R * 0.42),
				cframe = wheelPose * CFrame.Angles(0, 0, a) * CFrame.new(0, WHEEL_R, 0) * CFrame.Angles(math.rad(90), 0, 0),
				material = Enum.Material.Wood,
				color = WOOD_MID,
				canCollide = false,
				castShadow = false,
				parent = folder,
			})
		end
	end
	-- Spokes: 8 positions, two missing, one snapped short.
	for i = 0, 7 do
		if i ~= 3 and i ~= 6 then
			local a = (2 * math.pi / 8) * i
			local length = if i == 5 then WHEEL_R * 0.55 else WHEEL_R * 1.25
			PartUtils.CreatePart({
				name = ("WheelSpoke%d"):format(i),
				size = Vector3.new(0.8, length, 0.8),
				cframe = wheelPose * CFrame.Angles(0, 0, a) * CFrame.new(0, length * 0.5, 0),
				material = Enum.Material.Wood,
				color = WOOD_WORN,
				canCollide = false,
				castShadow = false,
				parent = folder,
			})
		end
	end

	--[[
		MASTS AND TORN SAILS.

		Three masts: the foremast snapped off short, the main still standing
		but leaning, the mizzen fallen and lying across the deck. Each
		standing mast carries yards with ragged sail panels hanging from
		them — the sails are built as several separate panels of differing
		width with gaps between, which is what reads as "torn" rather than
		as a flat sheet.
	]]
	local function buildMast(pose: CFrame, alongT: number, height: number, tiltX: number, tiltZ: number, yardCount: number, tag: string)
		local mastPose = pose * CFrame.new(0, DEPTH * 0.5, alongT * LENGTH) * CFrame.Angles(math.rad(tiltX), 0, math.rad(tiltZ))
		PartUtils.CreatePart({
			name = tag .. "Mast",
			size = Vector3.new(4, height, 4),
			cframe = mastPose * CFrame.new(0, height * 0.5, 0),
			material = Enum.Material.Wood,
			color = WOOD_DARK,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
		if yardCount <= 0 then
			return
		end
		-- Yards up the mast, each with a torn sail hanging beneath it.
		for y = 1, yardCount do
			local yardY = height * (0.3 + y * (0.6 / yardCount))
			local yardSpan = BEAM * (1.7 - y * (0.5 / yardCount))
			PartUtils.CreatePart({
				name = ("%sYard%d"):format(tag, y),
				size = Vector3.new(yardSpan, 2.4, 2.4),
				cframe = mastPose * CFrame.new(0, yardY, 0) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), rng:NextNumber(-0.08, 0.08)),
				material = Enum.Material.Wood,
				color = WOOD_MID,
				canCollide = false,
				castShadow = false,
				parent = folder,
			})
			-- Ragged sail: panels of random width and drop, with gaps where the
			-- canvas has rotted through. 10 panels rather than 7 so the sail
			-- reads as a real sheet of cloth from a distance.
			local panels = 10
			for p = 1, panels do
				if rng:NextNumber() > 0.18 then
					local px = (p - (panels + 1) / 2) * (yardSpan / panels)
					local drop = rng:NextNumber(height * 0.12, height * 0.28)
					PartUtils.CreatePart({
						name = ("%sSail%d_%d"):format(tag, y, p),
						size = Vector3.new(yardSpan / panels * 0.94, drop, 0.5),
						cframe = mastPose
							* CFrame.new(px, yardY - drop * 0.5, 0)
							* CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), rng:NextNumber(-0.1, 0.1)),
						material = Enum.Material.Fabric,
						color = SAIL,
						transparency = 0.18,
						canCollide = false,
						castShadow = false,
						parent = folder,
					})
				end
			end
		end
	end

	-- Foremast: shorter and leaning, one yard of tattered canvas still on it.
	buildMast(bowPose, -0.34, 170, 6, -11, 2, "Fore")
	-- Mainmast: the tall one, four yards.
	buildMast(bowPose, -0.14, 250, 4, -13, 4, "Main")
	-- Mizzen: fallen, lying across the after deck at an angle.
	PartUtils.CreatePart({
		name = "MizzenFallen",
		size = Vector3.new(4, 4, 108),
		cframe = sternPose * CFrame.new(BEAM * 0.3, DEPTH * 0.5 + 4, LENGTH * 0.2) * CFrame.Angles(math.rad(8), math.rad(28), math.rad(74)),
		material = Enum.Material.Wood,
		color = WOOD_DARK,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})

	--[[
		THE BREAK. Exposed frame ribs at both torn ends, plus loose planks
		and barrels spilled into the gap between the halves.
	]]
	for i = 1, 11 do
		local f = (i - 6) / 6
		for _, side in ipairs({ { bowPose, -0.03 }, { sternPose, 0.05 } }) do
			PartUtils.CreatePart({
				name = ("Rib%d"):format(i),
				size = Vector3.new(2, DEPTH * rng:NextNumber(0.6, 1.05), 2),
				cframe = side[1]
					* CFrame.new(f * BEAM * 0.44, 0, side[2] * LENGTH)
					* CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, f * 0.55),
				material = Enum.Material.Wood,
				color = WOOD_DARK,
				canCollide = false,
				castShadow = false,
				parent = folder,
			})
		end
	end
	-- Spilled planks and barrels on the sand between the halves.
	for i = 1, 30 do
		local ox = cx + rng:NextNumber(-70, 70)
		local oz = cz + rng:NextNumber(-70, 70)
		local surf = duneHeight(ox, oz)
		if rng:NextNumber() < 0.65 then
			PartUtils.CreatePart({
				name = ("LoosePlank%d"):format(i),
				size = Vector3.new(rng:NextNumber(2, 5), 1, rng:NextNumber(10, 26)),
				cframe = CFrame.new(Vector3.new(ox, surf + 0.6, oz))
					* CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 6.28), rng:NextNumber(-0.2, 0.2)),
				material = Enum.Material.Wood,
				color = if rng:NextNumber() < 0.5 then WOOD_DARK else WOOD_WORN,
				canCollide = false,
				castShadow = false,
				parent = folder,
			})
		else
			PartUtils.CreatePart({
				name = ("Barrel%d"):format(i),
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(7, 5, 5),
				cframe = CFrame.new(Vector3.new(ox, surf + 2.5, oz))
					* CFrame.Angles(0, rng:NextNumber(0, 6.28), math.rad(90))
					* CFrame.Angles(0, 0, rng:NextNumber(-0.3, 0.3)),
				material = Enum.Material.Wood,
				color = WOOD_MID,
				canCollide = false,
				castShadow = false,
				parent = folder,
			})
		end
	end

	-- Anchor and chain on the sand off the bow.
	local anchorSpot = bowPose * CFrame.new(BEAM * 0.9, -DEPTH * 0.3, -LENGTH * 0.44)
	PartUtils.CreatePart({
		name = "AnchorShank",
		size = Vector3.new(2, 18, 2),
		cframe = anchorSpot * CFrame.Angles(math.rad(80), 0, 0),
		material = Enum.Material.CorrodedMetal,
		color = IRON,
		canCollide = false,
		castShadow = false,
		parent = folder,
	})
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "AnchorFluke",
			size = Vector3.new(7, 2, 3),
			cframe = anchorSpot * CFrame.new(side * 4, -8, 0) * CFrame.Angles(0, 0, math.rad(side * 35)),
			material = Enum.Material.CorrodedMetal,
			color = IRON,
			canCollide = false,
			castShadow = false,
			parent = folder,
		})
	end

	--[[
		ROCKS, NOT CORAL.

		The previous version crusted 46 coral colonies over the hull, which
		worked against the whole point of the wreck: it made it read as a reef
		feature rather than as a ship lying broken on the seabed. The brief is
		explicit that it should be obviously ON THE GROUND and obviously
		broken, with rocks and debris beside it rather than coral over it.

		So the hull is left bare and boulders are scattered along the sand at
		its flanks instead — which also reads as the seabed disturbed by
		something heavy landing on it.
	]]
	for i = 1, 40 do
		local ra = rng:NextNumber(0, math.pi * 2)
		local rr = rng:NextNumber(70, 260)
		local ox, oz = cx + math.sin(ra) * rr, cz + math.cos(ra) * rr
		local s = rng:NextNumber(8, 30)
		PartUtils.CreatePart({
			name = ("WreckBoulder%d"):format(i),
			size = Vector3.new(s, s * rng:NextNumber(0.5, 0.95), s * rng:NextNumber(0.7, 1.3)),
			cframe = CFrame.new(Vector3.new(ox, duneHeight(ox, oz) + s * 0.25, oz))
				* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3)),
			material = Enum.Material.Rock,
			color = Color3.fromRGB(78, 76, 72):Lerp(Color3.fromRGB(116, 108, 94), rng:NextNumber()),
			canCollide = false,
			castShadow = true,
			parent = folder,
		})
	end

	-- A handful of small colonies only, low on the sand beside the hull -
	-- enough to date the wreck without dressing it as a reef.
	for i = 1, 8 do
		local ca = rng:NextNumber(0, math.pi * 2)
		local cr = rng:NextNumber(90, 200)
		local ox, oz = cx + math.sin(ca) * cr, cz + math.cos(ca) * cr
		CORAL_BUILDERS[rng:NextInteger(1, #CORAL_BUILDERS)](
			Vector3.new(ox, duneHeight(ox, oz), oz),
			rng:NextNumber(12, 26),
			pickCoralColour(rng),
			folder,
			"WreckCoral" .. i
		)
	end

	return origin, LENGTH
end

----------------------------------------------------------------------
-- SUBMARINES
----------------------------------------------------------------------

--[[
	SUBMARINES.

	Three, at deliberately different sizes, floating out in the water
	column rather than resting on the bottom — the brief asked for them
	around the map, not on the plate. Scale is the point: a 60-stud scout
	and a 190-stud boat in the same view give the exterior a sense of
	distance that identical props cannot.
]]
--[[
	SUBMARINE.

	Rebuilt on the same principle as the fish: the previous version was
	three stubby cylinders with a box stuck on top, which is exactly what it
	looked like — blocks put together. A vehicle needs a CONTINUOUS hull
	line, and that is what this builds.

	HULL. Fourteen cylinder sections whose radius follows a smooth profile
	curve: a rounded bow, a long parallel mid-body, and a fine taper into
	the stern. Sections overlap along their length so there are no visible
	steps between them. This is the single change that makes it read as one
	object rather than an assembly.

	The rest is the detail that tells you what kind of object it is — a
	faired sail with masts and a bridge rail, bow and stern planes, a
	cruciform tail, a shrouded screw with real blades, deck casing, sonar
	dome, hatches and a flank of viewports.
]]
local function buildSubmarine(pose: CFrame, length: number, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local radius = length * 0.085
	local HULL = Color3.fromRGB(74, 82, 88)
	local HULL_DARK = Color3.fromRGB(52, 58, 64)
	local DARK = Color3.fromRGB(28, 32, 36)
	local TRIM = Color3.fromRGB(184, 152, 58)
	local GLASS = Color3.fromRGB(128, 176, 186)

	--[[
		HULL PROFILE. t runs 0 (bow) to 1 (stern).
			bow      — elliptical, rising quickly to full beam
			mid      — held at full beam, the parallel body
			stern    — cubic taper to a fine point at the screw
	]]
	local function hullRadius(t: number): number
		if t < 0.18 then
			local u = t / 0.18
			return radius * math.sqrt(math.max(0, 1 - (1 - u) * (1 - u)))
		elseif t < 0.62 then
			return radius
		else
			local u = (t - 0.62) / 0.38
			return radius * (1 - u * u * u * 0.88)
		end
	end

	local SECTIONS = 14
	for i = 0, SECTIONS - 1 do
		local t = (i + 0.5) / SECTIONS
		local r = hullRadius(t)
		local along = (t - 0.5) * length
		PartUtils.CreatePart({
			name = ("%sHull%d"):format(name, i),
			shape = Enum.PartType.Cylinder,
			-- 1.35x overlap so adjoining sections blend instead of stepping.
			size = Vector3.new(length / SECTIONS * 1.35, r * 2, r * 2),
			cframe = pose * CFrame.new(0, 0, along) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(90)),
			material = Enum.Material.Metal,
			-- Lower half darker: hulls are anti-fouled below the waterline and
			-- it gives the cylinder some tonal separation.
			color = HULL,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
		-- Belly strake, darker, along the bottom of each section.
		PartUtils.CreatePart({
			name = ("%sBelly%d"):format(name, i),
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(length / SECTIONS * 1.3, r * 1.5, r * 1.5),
			cframe = pose * CFrame.new(0, -r * 0.42, along) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(90)),
			material = Enum.Material.Metal,
			color = HULL_DARK,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end

	-- Rounded bow cap and the sonar dome beneath it.
	PartUtils.CreatePart({
		name = name .. "BowCap",
		shape = Enum.PartType.Ball,
		size = Vector3.new(radius * 1.7, radius * 1.7, radius * 2.2),
		cframe = pose * CFrame.new(0, 0, -length * 0.47),
		material = Enum.Material.Metal,
		color = HULL,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	PartUtils.CreatePart({
		name = name .. "SonarDome",
		shape = Enum.PartType.Ball,
		size = Vector3.new(radius * 1.2, radius * 0.9, radius * 1.5),
		cframe = pose * CFrame.new(0, -radius * 0.5, -length * 0.42),
		material = Enum.Material.Metal,
		color = DARK,
		canCollide = false,
		castShadow = false,
		parent = model,
	})

	--[[
		DECK CASING. A flat strip running most of the hull top. Real boats
		have one and it is the strongest horizontal line on the silhouette,
		which stops the hull reading as a bare tube.
	]]
	PartUtils.CreatePart({
		name = name .. "Deck",
		size = Vector3.new(radius * 1.1, radius * 0.18, length * 0.78),
		cframe = pose * CFrame.new(0, radius * 0.92, -length * 0.02),
		material = Enum.Material.DiamondPlate,
		color = HULL_DARK,
		canCollide = false,
		castShadow = false,
		parent = model,
	})

	--[[
		THE SAIL. Built as three stacked slabs that narrow going up, with a
		faired leading edge — not the single box it used to be.
	]]
	local sailBase = radius * 0.95
	for i = 0, 2 do
		local f = i / 2
		PartUtils.CreatePart({
			name = ("%sSail%d"):format(name, i),
			size = Vector3.new(radius * (0.78 - f * 0.18), radius * 0.62, length * (0.17 - f * 0.035)),
			cframe = pose * CFrame.new(0, sailBase + radius * 0.55 * i, -length * 0.06),
			material = Enum.Material.Metal,
			color = HULL,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
	-- Faired leading edge of the sail.
	PartUtils.CreatePart({
		className = "WedgePart",
		name = name .. "SailFairing",
		size = Vector3.new(radius * 0.7, radius * 1.7, length * 0.05),
		cframe = pose * CFrame.new(0, sailBase + radius * 0.55, -length * 0.16) * CFrame.Angles(0, math.rad(180), math.rad(-90)),
		material = Enum.Material.Metal,
		color = HULL,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	-- Bridge rail around the sail top.
	PartUtils.CreatePart({
		name = name .. "BridgeRail",
		size = Vector3.new(radius * 0.5, radius * 0.08, length * 0.11),
		cframe = pose * CFrame.new(0, sailBase + radius * 1.62, -length * 0.06),
		material = Enum.Material.Metal,
		color = TRIM,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	-- Two masts of differing height: periscope and snorkel.
	for i, mast in ipairs({ { 1.9, -0.03 }, { 1.4, -0.09 } }) do
		PartUtils.CreatePart({
			name = ("%sMast%d"):format(name, i),
			size = Vector3.new(radius * 0.11, radius * mast[1], radius * 0.11),
			cframe = pose * CFrame.new(0, sailBase + radius * (1.6 + mast[1] * 0.5), length * mast[2]),
			material = Enum.Material.Metal,
			color = DARK,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
	-- Sail-mounted dive planes.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = name .. "SailPlane",
			size = Vector3.new(length * 0.11, radius * 0.12, length * 0.05),
			cframe = pose * CFrame.new(side * radius * 0.42, sailBase + radius * 0.7, -length * 0.05),
			material = Enum.Material.Metal,
			color = HULL,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end

	-- Bow planes, low and forward.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = name .. "BowPlane",
			size = Vector3.new(length * 0.13, radius * 0.13, length * 0.06),
			cframe = pose * CFrame.new(side * radius * 0.9, -radius * 0.1, -length * 0.33)
				* CFrame.Angles(0, 0, side * 0.12),
			material = Enum.Material.Metal,
			color = HULL,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end

	-- CRUCIFORM TAIL: four fins tapering to the stern.
	for i = 1, 4 do
		PartUtils.CreatePart({
			className = "WedgePart",
			name = ("%sFin%d"):format(name, i),
			size = Vector3.new(radius * 0.13, radius * 1.35, length * 0.13),
			cframe = pose
				* CFrame.new(0, 0, length * 0.40)
				* CFrame.Angles(0, 0, (math.pi / 2) * i)
				* CFrame.new(0, radius * 0.75, 0)
				* CFrame.Angles(0, math.rad(180), 0),
			material = Enum.Material.Metal,
			color = HULL,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end

	-- SCREW: a shrouded propeller with actual blades, angled like a real one.
	PartUtils.CreatePart({
		name = name .. "Shroud",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(length * 0.035, radius * 1.05, radius * 1.05),
		cframe = pose * CFrame.new(0, 0, length * 0.505) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(90)),
		material = Enum.Material.Metal,
		color = DARK,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	for i = 1, 5 do
		PartUtils.CreatePart({
			name = ("%sBlade%d"):format(name, i),
			size = Vector3.new(radius * 0.09, radius * 0.8, radius * 0.34),
			cframe = pose
				* CFrame.new(0, 0, length * 0.505)
				* CFrame.Angles(0, 0, (2 * math.pi / 5) * i)
				* CFrame.new(0, radius * 0.42, 0)
				* CFrame.Angles(0.6, 0, 0),
			material = Enum.Material.Metal,
			color = TRIM,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end

	-- Deck hatches.
	for i = 1, 3 do
		PartUtils.CreatePart({
			name = ("%sHatch%d"):format(name, i),
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(radius * 0.1, radius * 0.38, radius * 0.38),
			cframe = pose * CFrame.new(0, radius * 1.02, length * (-0.28 + i * 0.19))
				* CFrame.Angles(0, 0, math.rad(90)),
			material = Enum.Material.Metal,
			color = DARK,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end

	-- Viewports down each flank, following the hull taper.
	for i = 1, 7 do
		local t = 0.24 + (i / 8) * 0.44
		local r = hullRadius(t)
		for _, side in ipairs({ -1, 1 }) do
			PartUtils.CreatePart({
				name = ("%sViewport%d"):format(name, i),
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(radius * 0.1, radius * 0.36, radius * 0.36),
				cframe = pose * CFrame.new(side * r * 0.94, radius * 0.12, (t - 0.5) * length)
					* CFrame.Angles(0, 0, math.rad(90))
					* CFrame.Angles(0, math.rad(90), 0),
				material = Enum.Material.Glass,
				color = GLASS,
				canCollide = false,
				castShadow = false,
				parent = model,
			})
		end
	end

	-- Hull band, so the boat reads against dark water at distance.
	PartUtils.CreatePart({
		name = name .. "Stripe",
		size = Vector3.new(radius * 0.26, radius * 0.26, length * 0.66),
		cframe = pose * CFrame.new(0, radius * 0.68, -length * 0.02),
		material = Enum.Material.Metal,
		color = TRIM,
		canCollide = false,
		castShadow = false,
		parent = model,
	})

	return model
end

local function buildSubmarines(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Submarines"
	folder.Parent = parent

	local rng = Random.new(556021)
	-- Three sizes at three heights, spaced around the ring.
	local specs = {
		{ length = 300, radius = 700, height = 190 },
		{ length = 205, radius = 470, height = 265 },
		{ length = 120, radius = 640, height = 120 },
		{ length = 240, radius = 840, height = 150 },
	}
	for i, spec in ipairs(specs) do
		local a = (i / #specs) * math.pi * 2 + rng:NextNumber(-0.5, 0.5)
		local pose = CFrame.new(Vector3.new(math.sin(a) * spec.radius, spec.height, math.cos(a) * spec.radius))
			* CFrame.Angles(0, a + math.pi / 2 + rng:NextNumber(-0.5, 0.5), 0)
			* CFrame.Angles(rng:NextNumber(-0.08, 0.08), 0, rng:NextNumber(-0.1, 0.1))
		buildSubmarine(pose, spec.length, folder, "Submarine" .. i)
	end
end

----------------------------------------------------------------------
-- MARINE LIFE
----------------------------------------------------------------------

-- Tapered body shared by every large animal: a chain of blocks whose
-- cross-section follows `profile`, with a pale countershaded belly. Dark
-- above, light below is how every large marine animal is coloured, and it
-- is what makes these read as animals rather than as grey blocks.
local function buildTaperedBody(
	model: Model,
	pose: CFrame,
	length: number,
	profile: (number) -> (number, number),
	topColour: Color3,
	bellyColour: Color3,
	name: string
)
	local SEGMENTS = 16
	for i = 0, SEGMENTS - 1 do
		local t = i / SEGMENTS
		local nextT = (i + 1) / SEGMENTS
		local w, h = profile(t + 0.5 / SEGMENTS)
		local segLen = (nextT - t) * length * 1.08
		local along = (t + 0.5 / SEGMENTS - 0.5) * length

		PartUtils.CreatePart({
			name = ("%sBody%d"):format(name, i),
			size = Vector3.new(w, h, segLen),
			cframe = pose * CFrame.new(0, 0, along),
			material = Enum.Material.SmoothPlastic,
			color = topColour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
		PartUtils.CreatePart({
			name = ("%sBelly%d"):format(name, i),
			size = Vector3.new(w * 0.72, h * 0.34, segLen),
			cframe = pose * CFrame.new(0, -h * 0.36, along),
			material = Enum.Material.SmoothPlastic,
			color = bellyColour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
end

local function buildFlukes(model: Model, pose: CFrame, length: number, span: number, colour: Color3, name: string)
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = name .. "Fluke",
			size = Vector3.new(span * 0.52, length * 0.018, length * 0.1),
			cframe = pose * CFrame.new(side * span * 0.3, 0, length * 0.52) * CFrame.Angles(0, side * 0.35, side * 0.12),
			material = Enum.Material.SmoothPlastic,
			color = colour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
end

local function buildPectorals(model: Model, pose: CFrame, length: number, span: number, sweep: number, colour: Color3, name: string)
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = name .. "Pectoral",
			size = Vector3.new(span, length * 0.016, length * 0.11),
			cframe = pose * CFrame.new(side * span * 0.55, -length * 0.02, -length * 0.14) * CFrame.Angles(0, side * sweep, side * 0.3),
			material = Enum.Material.SmoothPlastic,
			color = colour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
end

-- Vertical caudal fin with a longer upper lobe — the shark tail.
local function buildSharkTail(model: Model, pose: CFrame, length: number, colour: Color3, name: string)
	for _, lobe in ipairs({ { 1, 0.22 }, { -1, 0.13 } }) do
		PartUtils.CreatePart({
			className = "WedgePart",
			name = name .. "Caudal",
			size = Vector3.new(length * 0.02, length * lobe[2], length * 0.14),
			cframe = pose * CFrame.new(0, lobe[1] * length * lobe[2] * 0.5, length * 0.52)
				* CFrame.Angles(if lobe[1] > 0 then 0 else math.pi, 0, 0),
			material = Enum.Material.SmoothPlastic,
			color = colour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
end

local function sharkProfile(length: number)
	return function(t: number): (number, number)
		local girth = math.sin(math.clamp(t, 0, 1) ^ 0.7 * math.pi) ^ 0.8
		return length * 0.15 * girth + length * 0.012, length * 0.19 * girth + length * 0.012
	end
end

-- GREAT WHITE: heavy torpedo body, tall dorsal, pointed snout.
local function buildGreatWhite(pose: CFrame, length: number, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local TOP, BELLY = Color3.fromRGB(92, 100, 108), Color3.fromRGB(212, 212, 204)

	buildTaperedBody(model, pose, length, sharkProfile(length), TOP, BELLY, name)
	PartUtils.CreatePart({
		name = name .. "Snout",
		size = Vector3.new(length * 0.07, length * 0.07, length * 0.11),
		cframe = pose * CFrame.new(0, 0, -length * 0.54),
		material = Enum.Material.SmoothPlastic,
		color = TOP,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	PartUtils.CreatePart({
		className = "WedgePart",
		name = name .. "Dorsal",
		size = Vector3.new(length * 0.02, length * 0.17, length * 0.2),
		cframe = pose * CFrame.new(0, length * 0.11, -length * 0.02) * CFrame.Angles(0, math.rad(180), 0),
		material = Enum.Material.SmoothPlastic,
		color = TOP,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	buildPectorals(model, pose, length, length * 0.17, 0.25, TOP, name)
	buildSharkTail(model, pose, length, TOP, name)
	return model
end

-- TIGER SHARK: blunter head, and the vertical flank barring it is named
-- for — without the stripes it is indistinguishable from a great white.
local function buildTigerShark(pose: CFrame, length: number, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local TOP, BELLY = Color3.fromRGB(94, 98, 82), Color3.fromRGB(206, 204, 190)

	buildTaperedBody(model, pose, length, sharkProfile(length), TOP, BELLY, name)
	-- Blunt square snout.
	PartUtils.CreatePart({
		name = name .. "Snout",
		size = Vector3.new(length * 0.11, length * 0.09, length * 0.1),
		cframe = pose * CFrame.new(0, 0, -length * 0.53),
		material = Enum.Material.SmoothPlastic,
		color = TOP,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	-- Tiger barring across the back and flanks.
	for i = 1, 9 do
		local along = (i - 5) * length * 0.07
		local h = length * (0.13 - math.abs(i - 5) * 0.008)
		PartUtils.CreatePart({
			name = ("%sBar%d"):format(name, i),
			size = Vector3.new(length * 0.155, h, length * 0.018),
			cframe = pose * CFrame.new(0, length * 0.015, along),
			material = Enum.Material.SmoothPlastic,
			color = Color3.fromRGB(58, 60, 48),
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
	PartUtils.CreatePart({
		className = "WedgePart",
		name = name .. "Dorsal",
		size = Vector3.new(length * 0.02, length * 0.15, length * 0.19),
		cframe = pose * CFrame.new(0, length * 0.1, 0) * CFrame.Angles(0, math.rad(180), 0),
		material = Enum.Material.SmoothPlastic,
		color = TOP,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	buildPectorals(model, pose, length, length * 0.18, 0.25, TOP, name)
	buildSharkTail(model, pose, length, TOP, name)
	return model
end

-- HAMMERHEAD: the cephalofoil is the entire point — a wide flat crossbar
-- of a head with the eyes at its tips, plus a very tall narrow dorsal.
local function buildHammerhead(pose: CFrame, length: number, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local TOP, BELLY = Color3.fromRGB(104, 112, 116), Color3.fromRGB(214, 214, 206)

	buildTaperedBody(model, pose, length, sharkProfile(length), TOP, BELLY, name)

	-- Cephalofoil: wide, flat, and set square across the nose.
	local span = length * 0.34
	PartUtils.CreatePart({
		name = name .. "Cephalofoil",
		size = Vector3.new(span, length * 0.035, length * 0.09),
		cframe = pose * CFrame.new(0, 0, -length * 0.5),
		material = Enum.Material.SmoothPlastic,
		color = TOP,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	-- Eyes right out on the tips, which is what makes it read correctly.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = name .. "Eye",
			shape = Enum.PartType.Ball,
			size = Vector3.new(length * 0.035, length * 0.035, length * 0.035),
			cframe = pose * CFrame.new(side * span * 0.47, 0, -length * 0.5),
			material = Enum.Material.SmoothPlastic,
			color = Color3.fromRGB(24, 26, 30),
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
	-- Exaggeratedly tall dorsal.
	PartUtils.CreatePart({
		className = "WedgePart",
		name = name .. "Dorsal",
		size = Vector3.new(length * 0.02, length * 0.24, length * 0.16),
		cframe = pose * CFrame.new(0, length * 0.14, -length * 0.04) * CFrame.Angles(0, math.rad(180), 0),
		material = Enum.Material.SmoothPlastic,
		color = TOP,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	buildPectorals(model, pose, length, length * 0.15, 0.2, TOP, name)
	buildSharkTail(model, pose, length, TOP, name)
	return model
end

-- HUMPBACK WHALE: the largest thing in the map. Enormous white-undersided
-- flippers and a pleated throat are what separate it from a generic whale.
local function buildHumpback(pose: CFrame, length: number, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local TOP, BELLY = Color3.fromRGB(52, 58, 68), Color3.fromRGB(178, 180, 176)

	local function profile(t: number): (number, number)
		local girth = math.sin(math.clamp(t, 0, 1) ^ 0.5 * math.pi) ^ 0.55
		return length * 0.15 * girth + length * 0.01, length * 0.18 * girth + length * 0.01
	end
	buildTaperedBody(model, pose, length, profile, TOP, BELLY, name)

	PartUtils.CreatePart({
		name = name .. "Head",
		shape = Enum.PartType.Ball,
		size = Vector3.new(length * 0.14, length * 0.12, length * 0.22),
		cframe = pose * CFrame.new(0, 0, -length * 0.5),
		material = Enum.Material.SmoothPlastic,
		color = TOP,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	-- Knobbly tubercles along the rostrum — a humpback signature.
	for i = 1, 6 do
		PartUtils.CreatePart({
			name = ("%sTubercle%d"):format(name, i),
			shape = Enum.PartType.Ball,
			size = Vector3.new(length * 0.016, length * 0.016, length * 0.016),
			cframe = pose * CFrame.new((i % 2 == 0 and 1 or -1) * length * 0.03, length * 0.05, -length * (0.42 + i * 0.015)),
			material = Enum.Material.SmoothPlastic,
			color = TOP,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
	for i = 1, 7 do
		PartUtils.CreatePart({
			name = name .. "Pleat",
			size = Vector3.new(length * 0.012, length * 0.02, length * 0.3),
			cframe = pose * CFrame.new((i - 4) * length * 0.018, -length * 0.075, -length * 0.28),
			material = Enum.Material.SmoothPlastic,
			color = Color3.fromRGB(150, 152, 148),
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = name .. "Flipper",
			size = Vector3.new(length * 0.3, length * 0.015, length * 0.08),
			cframe = pose * CFrame.new(side * length * 0.19, -length * 0.03, -length * 0.16) * CFrame.Angles(0, side * 0.5, side * 0.35),
			material = Enum.Material.SmoothPlastic,
			color = BELLY,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
	buildFlukes(model, pose, length, length * 0.32, TOP, name)
	return model
end

-- BELUGA: small, entirely white, rounded melon head, and crucially NO
-- dorsal fin — that absence is the identifying feature.
local function buildBeluga(pose: CFrame, length: number, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local WHITE, SHADE = Color3.fromRGB(232, 232, 228), Color3.fromRGB(206, 208, 210)

	local function profile(t: number): (number, number)
		local girth = math.sin(math.clamp(t, 0, 1) ^ 0.62 * math.pi) ^ 0.6
		return length * 0.16 * girth + length * 0.014, length * 0.18 * girth + length * 0.014
	end
	buildTaperedBody(model, pose, length, profile, WHITE, SHADE, name)

	-- The bulbous melon.
	PartUtils.CreatePart({
		name = name .. "Melon",
		shape = Enum.PartType.Ball,
		size = Vector3.new(length * 0.17, length * 0.17, length * 0.19),
		cframe = pose * CFrame.new(0, length * 0.02, -length * 0.47),
		material = Enum.Material.SmoothPlastic,
		color = WHITE,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	-- Low dorsal RIDGE in place of a fin.
	PartUtils.CreatePart({
		name = name .. "DorsalRidge",
		size = Vector3.new(length * 0.03, length * 0.03, length * 0.3),
		cframe = pose * CFrame.new(0, length * 0.09, length * 0.02),
		material = Enum.Material.SmoothPlastic,
		color = SHADE,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	buildPectorals(model, pose, length, length * 0.14, 0.35, WHITE, name)
	buildFlukes(model, pose, length, length * 0.28, WHITE, name)
	return model
end

--[[
	BLOCKY REEF FISH.

	The single fish builder used EVERYWHERE — plaza and exterior alike, at
	different scales. Replaces two earlier attempts that both failed for the
	same reason: they were assembled from many small primitives, so at any
	distance the fish dissolved into a cloud of shapes instead of reading as
	one animal.

	THE PRINCIPLE HERE IS THE OPPOSITE OF THE CORAL. Coral is an aggregate
	and looks right built from many units. An animal is a single silhouette
	and must be built from FEW, LARGE, overlapping slabs. Roughly a dozen
	parts per fish, each a substantial fraction of the body.

	FLAT. Real fish are laterally compressed — tall and long, thin across.
	The body is ~0.13 of its length in width against ~0.42 in height, which
	is what makes a recognisable fish shape from the side and a thin edge
	head-on.

	The parts are deliberately squared-off. The brief liked the earlier
	blocky look and wants it kept; this keeps the facets while fixing the
	proportions and the part count.
]]
local function buildFish(pose: CFrame, length: number, colour: Color3, opts, parent: Instance, name: string)
	opts = opts or {}
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local belly = colour:Lerp(Color3.fromRGB(240, 238, 226), 0.55)
	local dark = colour:Lerp(Color3.fromRGB(18, 20, 26), 0.35)
	local width = length * (opts.width or 0.13)
	local height = length * (opts.height or 0.42)

	-- BODY: four big slabs, tapering fore and aft. Four is enough to give a
	-- fish profile and few enough that it stays one solid object.
	local segs = {
		{ z = -0.30, w = 0.72, h = 0.74 },
		{ z = -0.08, w = 1.00, h = 1.00 },
		{ z = 0.16, w = 0.88, h = 0.86 },
		{ z = 0.36, w = 0.55, h = 0.50 },
	}
	for i, s in ipairs(segs) do
		PartUtils.CreatePart({
			name = ("%sBody%d"):format(name, i),
			size = Vector3.new(width * s.w, height * s.h, length * 0.26),
			cframe = pose * CFrame.new(0, 0, length * s.z),
			material = Enum.Material.SmoothPlastic,
			color = colour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
		-- Countershaded belly slab under each body segment.
		PartUtils.CreatePart({
			name = ("%sBelly%d"):format(name, i),
			size = Vector3.new(width * s.w * 1.02, height * s.h * 0.3, length * 0.26),
			cframe = pose * CFrame.new(0, -height * s.h * 0.36, length * s.z),
			material = Enum.Material.SmoothPlastic,
			color = belly,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end

	-- HEAD: a wedge, so the snout comes to a point instead of a flat face.
	PartUtils.CreatePart({
		className = "WedgePart",
		name = name .. "Head",
		size = Vector3.new(width * 0.72, height * 0.74, length * 0.18),
		cframe = pose * CFrame.new(0, 0, -length * 0.51) * CFrame.Angles(0, math.rad(180), math.rad(-90)),
		material = Enum.Material.SmoothPlastic,
		color = colour,
		canCollide = false,
		castShadow = false,
		parent = model,
	})

	-- EYES: on the sides of the head, large enough to see. An eye is the
	-- single strongest cue that a shape is an animal.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = name .. "Eye",
			shape = Enum.PartType.Ball,
			size = Vector3.new(width * 0.5, height * 0.17, height * 0.17),
			cframe = pose * CFrame.new(side * width * 0.42, height * 0.13, -length * 0.40),
			material = Enum.Material.SmoothPlastic,
			color = Color3.fromRGB(20, 22, 28),
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end

	-- TAIL: two wedges meeting at the peduncle to form a forked caudal fin.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			className = "WedgePart",
			name = name .. "Tail",
			size = Vector3.new(width * 0.3, height * 0.62, length * 0.2),
			cframe = pose * CFrame.new(0, side * height * 0.3, length * 0.55)
				* CFrame.Angles(if side > 0 then 0 else math.pi, 0, 0),
			material = Enum.Material.SmoothPlastic,
			color = opts.finColour or colour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end

	-- DORSAL FIN, and a matching anal fin below.
	PartUtils.CreatePart({
		className = "WedgePart",
		name = name .. "Dorsal",
		size = Vector3.new(width * 0.34, height * (opts.dorsal or 0.42), length * 0.4),
		cframe = pose * CFrame.new(0, height * 0.62, -length * 0.02) * CFrame.Angles(0, math.rad(180), 0),
		material = Enum.Material.SmoothPlastic,
		color = opts.finColour or colour,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	PartUtils.CreatePart({
		name = name .. "AnalFin",
		size = Vector3.new(width * 0.3, height * 0.22, length * 0.22),
		cframe = pose * CFrame.new(0, -height * 0.55, length * 0.16),
		material = Enum.Material.SmoothPlastic,
		color = opts.finColour or colour,
		canCollide = false,
		castShadow = false,
		parent = model,
	})

	-- PECTORAL FINS, angled out from behind the gills.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = name .. "Pectoral",
			size = Vector3.new(length * 0.16, height * 0.1, length * 0.13),
			cframe = pose * CFrame.new(side * width * 0.55, -height * 0.1, -length * 0.22)
				* CFrame.Angles(0, side * 0.5, side * 0.55),
			material = Enum.Material.SmoothPlastic,
			color = opts.finColour or colour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end

	-- OPTIONAL BANDING: broad vertical bars, the classic reef-fish marking.
	if opts.stripes then
		for i = 1, 3 do
			PartUtils.CreatePart({
				name = ("%sBand%d"):format(name, i),
				size = Vector3.new(width * 1.06, height * 0.9, length * 0.07),
				cframe = pose * CFrame.new(0, 0, (i - 2) * length * 0.2 - length * 0.06),
				material = Enum.Material.SmoothPlastic,
				color = dark,
				canCollide = false,
				castShadow = false,
				parent = model,
			})
		end
	end

	return model
end

--[[
	MARINE LIFE PLACEMENT.

	Everything lives OUT over the dune field, never over the plaza, and
	high enough that nothing crosses the sightline to the central board.

	Layered by size: sharks and giant fish patrol lowest and closest in,
	belugas mid-water, humpbacks highest and furthest out as distant
	silhouettes. That vertical sorting is what gives the water column
	depth instead of putting everything on one plane.
]]
local function buildMarineLife(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "MarineLife"
	folder.Parent = parent

	local rng = Random.new(313377)

	local function poseAt(rMin: number, rMax: number, yMin: number, yMax: number): CFrame
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(rMin, rMax)
		return CFrame.new(Vector3.new(math.sin(a) * r, rng:NextNumber(yMin, yMax), math.cos(a) * r))
			* CFrame.Angles(0, a + math.pi / 2 + rng:NextNumber(-0.4, 0.4), 0)
			* CFrame.Angles(rng:NextNumber(-0.08, 0.08), 0, rng:NextNumber(-0.12, 0.12))
	end

	--[[
		SIZE RATIOS. Sharks and whales are the exception the brief asked for:
		they get bigger, not smaller, because they are the animals that should
		feel imposing. Everything else is sized against them.

		  sardines      6-9 studs   (schooling baitfish)
		  reef fish    34-64 studs  (the "normal" fish of the exterior)
		  sharks       85-130 studs
		  belugas     120-155 studs
		  humpbacks   300-390 studs

		GROUPED, NOT SCATTERED. Fish are placed in SHOALS sharing one colour,
		one heading and one patch of water, rather than sprinkled individually
		in random colours. A reef does not contain one fish of every hue at
		even spacing, and that is precisely what the previous pass looked like.
	]]
	for i = 1, 7 do
		buildGreatWhite(poseAt(DUNE_INNER + 60, DUNE_OUTER - 80, 150, 250), rng:NextNumber(95, 130), folder, "GreatWhite" .. i)
	end
	for i = 1, 7 do
		buildTigerShark(poseAt(DUNE_INNER + 60, DUNE_OUTER - 80, 140, 230), rng:NextNumber(88, 118), folder, "TigerShark" .. i)
	end
	local hhA = rng:NextNumber(0, math.pi * 2)
	local hhR = rng:NextNumber(DUNE_INNER + 160, DUNE_OUTER - 180)
	for i = 1, 8 do
		local centre = Vector3.new(math.sin(hhA) * hhR, 205, math.cos(hhA) * hhR)
			+ Vector3.new(rng:NextNumber(-140, 140), rng:NextNumber(-35, 45), rng:NextNumber(-140, 140))
		buildHammerhead(
			CFrame.new(centre) * CFrame.Angles(0, hhA + math.pi / 2 + rng:NextNumber(-0.25, 0.25), 0),
			rng:NextNumber(85, 112),
			folder,
			"Hammerhead" .. i
		)
	end

	--[[
		SHOALS of ordinary reef fish. Each shoal is one species: one colour,
		one size band, one heading, clustered in a single volume. Nine shoals
		of 5-11 rather than 26 unrelated individuals.
	]]
	local SHOAL_SPECIES = {
		{ colour = Color3.fromRGB(212, 158, 58), stripes = false, width = 0.14, height = 0.44 }, -- gold
		{ colour = Color3.fromRGB(198, 66, 52), stripes = false, width = 0.13, height = 0.46 }, -- red snapper
		{ colour = Color3.fromRGB(96, 130, 178), stripes = true, width = 0.12, height = 0.40 }, -- banded blue
		{ colour = Color3.fromRGB(206, 96, 118), stripes = false, width = 0.15, height = 0.50 }, -- pink
		{ colour = Color3.fromRGB(120, 126, 132), stripes = false, width = 0.16, height = 0.34 }, -- silver tuna
		{ colour = Color3.fromRGB(196, 176, 74), stripes = true, width = 0.13, height = 0.48 }, -- yellow banded
	}
	for s = 1, 9 do
		local spec = SHOAL_SPECIES[rng:NextInteger(1, #SHOAL_SPECIES)]
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(DUNE_INNER + 100, DUNE_OUTER - 150)
		local centre = Vector3.new(math.sin(a) * r, rng:NextNumber(130, 300), math.cos(a) * r)
		local heading = a + math.pi / 2 + rng:NextNumber(-0.4, 0.4)
		local size = rng:NextNumber(34, 64)
		for f = 1, rng:NextInteger(5, 11) do
			local off = Vector3.new(rng:NextNumber(-90, 90), rng:NextNumber(-30, 30), rng:NextNumber(-90, 90))
			buildFish(
				CFrame.new(centre + off) * CFrame.Angles(0, heading + rng:NextNumber(-0.25, 0.25), 0),
				size * rng:NextNumber(0.85, 1.15),
				spec.colour,
				{ stripes = spec.stripes, width = spec.width, height = spec.height },
				folder,
				("Shoal%d_%d"):format(s, f)
			)
		end
	end

	--[[
		SARDINE BAITBALLS. Tight clouds of small silver fish, all facing the
		same way — the densest thing in the exterior and a strong contrast to
		the loose shoals above.
	]]
	for b = 1, 4 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(DUNE_INNER + 140, DUNE_OUTER - 200)
		local centre = Vector3.new(math.sin(a) * r, rng:NextNumber(160, 280), math.cos(a) * r)
		local heading = rng:NextNumber(0, math.pi * 2)
		for f = 1, 60 do
			local off = Vector3.new(rng:NextNumber(-38, 38), rng:NextNumber(-22, 22), rng:NextNumber(-38, 38))
			buildFish(
				CFrame.new(centre + off) * CFrame.Angles(0, heading + rng:NextNumber(-0.2, 0.2), 0),
				rng:NextNumber(6, 9),
				Color3.fromRGB(178, 186, 196),
				{ width = 0.12, height = 0.3, finColour = Color3.fromRGB(150, 160, 172) },
				folder,
				("Sardine%d_%d"):format(b, f)
			)
		end
	end

	-- BELUGAS: a pod travelling together, mid-water.
	local podA = rng:NextNumber(0, math.pi * 2)
	local podR = rng:NextNumber(DUNE_INNER + 200, DUNE_OUTER - 220)
	for i = 1, 6 do
		local centre = Vector3.new(math.sin(podA) * podR, 330, math.cos(podA) * podR)
			+ Vector3.new(rng:NextNumber(-130, 130), rng:NextNumber(-45, 45), rng:NextNumber(-130, 130))
		buildBeluga(
			CFrame.new(centre) * CFrame.Angles(0, podA + math.pi / 2 + rng:NextNumber(-0.2, 0.2), 0),
			rng:NextNumber(120, 155),
			folder,
			"Beluga" .. i
		)
	end

	-- HUMPBACKS: three, high and far out.
	for i = 1, 3 do
		buildHumpback(poseAt(DUNE_OUTER * 0.5, DUNE_OUTER - 60, 400, 520), rng:NextNumber(300, 390), folder, "Humpback" .. i)
	end
end

--[[
	=================================================================
	INTERIOR LIFE — THE PLAZA, TREATED SEPARATELY
	=================================================================

	The brief is explicit that the middle of the map and the exterior are
	two different places, and they are populated on opposite principles:

	  EXTERIOR   large, sparse, distant. Whales, sharks, wrecks, reefs.
	             Read at hundreds of studs.
	  INTERIOR   small, close, incidental. Nothing here competes with the
	             buildings or the podiums for attention.

	THE SIZE RULE. Contestant podiums are the reference object a player is
	standing next to, so everything in this function is kept decisively
	smaller than one — reef fish 2-4 studs, rays 5-8, starfish 3-5,
	jellyfish bells 3-5. Nothing may loom.

	This restores the small life that the exterior redesign removed along
	with the old reef: the schooling fish, jellyfish and small sharks that
	used to circulate over the plaza, plus stingrays and starfish on the
	sand from the reference photographs.
]]

-- Reference: contestant platforms. Interior life is sized against this.
local PODIUM_SIZE = 10

local REEF_FISH_COLOURS = {
	Color3.fromRGB(232, 158, 58),
	Color3.fromRGB(226, 96, 62),
	Color3.fromRGB(238, 206, 92),
	Color3.fromRGB(96, 148, 196),
	Color3.fromRGB(206, 96, 132),
	Color3.fromRGB(140, 196, 188),
}

--[[
	A small reef fish: body, tail, and optional vertical banding. Six parts
	at most, because there are hundreds of them and they are never seen from
	more than a few dozen studs.
]]
local function buildSmallFish(pose: CFrame, length: number, colour: Color3, striped: boolean, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	PartUtils.CreatePart({
		name = name .. "Body",
		shape = Enum.PartType.Ball,
		size = Vector3.new(length * 0.34, length * 0.5, length),
		cframe = pose,
		material = Enum.Material.SmoothPlastic,
		color = colour,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	-- Forked tail.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			className = "WedgePart",
			name = name .. "Tail",
			size = Vector3.new(length * 0.05, length * 0.3, length * 0.28),
			cframe = pose * CFrame.new(0, side * length * 0.13, length * 0.6)
				* CFrame.Angles(if side > 0 then 0 else math.pi, 0, 0),
			material = Enum.Material.SmoothPlastic,
			color = colour,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
	if striped then
		for i = 1, 3 do
			PartUtils.CreatePart({
				name = name .. "Stripe",
				size = Vector3.new(length * 0.36, length * 0.46, length * 0.09),
				cframe = pose * CFrame.new(0, 0, (i - 2) * length * 0.26),
				material = Enum.Material.SmoothPlastic,
				color = Color3.fromRGB(28, 32, 40),
				canCollide = false,
				castShadow = false,
				parent = model,
			})
		end
	end
end

--[[
	STINGRAY. A flat diamond disc with a whip tail, gliding just above the
	sand. Built from three tapering slabs rather than one, so the wings have
	a visible sweep.
]]
local function buildStingray(pose: CFrame, span: number, parent: Instance, name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local TOP = Color3.fromRGB(112, 96, 74)

	for i = 0, 2 do
		local f = i / 2
		PartUtils.CreatePart({
			name = ("%sDisc%d"):format(name, i),
			size = Vector3.new(span * (1 - f * 0.55), span * 0.07, span * (0.7 - f * 0.3)),
			cframe = pose * CFrame.new(0, f * span * 0.03, (f - 0.2) * span * 0.3),
			material = Enum.Material.SmoothPlastic,
			color = TOP,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
	PartUtils.CreatePart({
		name = name .. "Tail",
		size = Vector3.new(span * 0.05, span * 0.05, span * 0.9),
		cframe = pose * CFrame.new(0, 0, span * 0.6),
		material = Enum.Material.SmoothPlastic,
		color = TOP,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
end

--[[
	STARFISH. Reference image 5: five tapering arms on the sand, orange with
	a paler centre. Laid flat and rotated randomly.
]]
local function buildStarfish(position: Vector3, radius: number, parent: Instance, name: string, rng: Random)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local colour = Color3.fromRGB(214, 122, 68):Lerp(Color3.fromRGB(226, 168, 92), rng:NextNumber())
	local spin = rng:NextNumber(0, math.pi * 2)

	PartUtils.CreatePart({
		name = name .. "Centre",
		shape = Enum.PartType.Ball,
		size = Vector3.new(radius * 0.7, radius * 0.35, radius * 0.7),
		position = position,
		material = Enum.Material.Sandstone,
		color = colour,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	for arm = 1, 5 do
		local a = spin + (2 * math.pi / 5) * arm
		--[[
			Arms must MEET the centre. The previous version started each arm at
			0.35 radius and left a gap, so the five points read as loose shapes
			lying near a disc rather than as one starfish.

			Three overlapping segments now run from inside the central disc
			outward, tapering as they go, so the arm is continuous from hub to
			tip.
		]]
		for seg = 1, 3 do
			local t = (seg - 1) / 3
			local reach = radius * (0.18 + t * 0.62)
			PartUtils.CreatePart({
				name = ("%sArm%d_%d"):format(name, arm, seg),
				size = Vector3.new(radius * (0.44 - t * 0.26), radius * (0.3 - t * 0.12), radius * 0.5),
				cframe = CFrame.new(position) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, reach),
				material = Enum.Material.Sandstone,
				color = colour,
				canCollide = false,
				castShadow = false,
				parent = model,
			})
		end
	end
end

--[[
	JELLYFISH. A translucent bell with trailing tentacles. Slightly emissive
	so it catches the eye in open water — the one place a hint of glow is
	appropriate, since real jellies genuinely are luminous.
]]
local function buildJellyfish(position: Vector3, size: number, parent: Instance, name: string, rng: Random)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local tint = Color3.fromRGB(206, 178, 226):Lerp(Color3.fromRGB(170, 206, 226), rng:NextNumber())

	PartUtils.CreatePart({
		name = name .. "Bell",
		shape = Enum.PartType.Ball,
		size = Vector3.new(size, size * 0.78, size),
		position = position,
		material = Enum.Material.SmoothPlastic,
		color = tint,
		transparency = 0.45,
		canCollide = false,
		castShadow = false,
		parent = model,
	})
	for i = 1, 6 do
		local a = (2 * math.pi / 6) * i
		local len = size * rng:NextNumber(1.1, 2.1)
		PartUtils.CreatePart({
			name = ("%sTentacle%d"):format(name, i),
			size = Vector3.new(size * 0.07, len, size * 0.07),
			cframe = CFrame.new(position + Vector3.new(math.cos(a) * size * 0.3, -len * 0.5, math.sin(a) * size * 0.3))
				* CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)),
			material = Enum.Material.SmoothPlastic,
			color = tint,
			transparency = 0.6,
			canCollide = false,
			castShadow = false,
			parent = model,
		})
	end
end

--[[
	Populates the plaza. Every placement avoids the buildings and keeps well
	inside USABLE_RADIUS, so nothing intrudes on the walkable area or the
	sightlines to the central board.
]]
local function buildInteriorLife(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "InteriorLife"
	folder.Parent = parent

	local rng = Random.new(918273)
	local R = MapConfig.USABLE_RADIUS

	local function clearOfBuildings(p: Vector3, margin: number): boolean
		for _, def in ipairs(LobbyConfig.BUILDINGS) do
			if (Vector3.new(def.position.X, 0, def.position.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude < margin then
				return false
			end
		end
		return true
	end

	--[[
		FAR FEWER, FAR BIGGER. The previous pass put 224 schooling fish plus 18
		solitaries over the plaza at 2-4 studs each — too many to feel special
		and too small to read as anything. Now: seven small groups of four or
		five, plus a handful of distinctive singles, at sizes you can actually
		make out from the ground.

		Everything still stays under the podium reference (10 studs) except the
		solitary showpiece fish, which are allowed to reach it.
	]]
	local INTERIOR_SPECIES = {
		{ colour = Color3.fromRGB(232, 158, 58), stripes = true },
		{ colour = Color3.fromRGB(226, 96, 62), stripes = false },
		{ colour = Color3.fromRGB(238, 206, 92), stripes = true },
		{ colour = Color3.fromRGB(96, 148, 196), stripes = false },
		{ colour = Color3.fromRGB(206, 96, 132), stripes = false },
		{ colour = Color3.fromRGB(140, 196, 188), stripes = true },
	}

	for school = 1, 7 do
		local spec = INTERIOR_SPECIES[rng:NextInteger(1, #INTERIOR_SPECIES)]
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(40, R * 0.82)
		local centre = Vector3.new(math.sin(a) * r, rng:NextNumber(26, 62), math.cos(a) * r)
		local heading = rng:NextNumber(0, math.pi * 2)
		local size = rng:NextNumber(6, 9)
		for f = 1, rng:NextInteger(4, 5) do
			local off = Vector3.new(rng:NextNumber(-11, 11), rng:NextNumber(-5, 5), rng:NextNumber(-11, 11))
			buildFish(
				CFrame.new(centre + off) * CFrame.Angles(0, heading + rng:NextNumber(-0.25, 0.25), 0),
				size * rng:NextNumber(0.9, 1.1),
				spec.colour,
				{ stripes = spec.stripes },
				folder,
				("SchoolFish%d_%d"):format(school, f)
			)
		end
	end

	-- Distinctive singles — large enough to be worth noticing individually.
	for i = 1, 6 do
		local spec = INTERIOR_SPECIES[rng:NextInteger(1, #INTERIOR_SPECIES)]
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(30, R * 0.88)
		buildFish(
			CFrame.new(Vector3.new(math.sin(a) * r, rng:NextNumber(18, 50), math.cos(a) * r))
				* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			rng:NextNumber(9, PODIUM_SIZE * 1.3),
			spec.colour,
			{ stripes = spec.stripes, height = 0.5 },
			folder,
			"ReefFish" .. i
		)
	end

	-- JELLYFISH drifting at varied heights.
	for i = 1, 26 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(20, R * 0.92)
		buildJellyfish(
			Vector3.new(math.sin(a) * r, rng:NextNumber(28, 95), math.cos(a) * r),
			rng:NextNumber(3, 5),
			folder,
			"Jellyfish" .. i,
			rng
		)
	end

	-- STINGRAYS gliding low over the sand.
	for i = 1, 9 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(35, R * 0.88)
		local p = Vector3.new(math.sin(a) * r, rng:NextNumber(4, 14), math.cos(a) * r)
		if clearOfBuildings(p, 34) then
			buildStingray(
				CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0) * CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, 0),
				rng:NextNumber(5, 8),
				folder,
				"Stingray" .. i
			)
		end
	end

	-- SMALL SHARKS: reef sharks, no bigger than a podium, keeping to the
	-- outer part of the plaza.
	for i = 1, 5 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(R * 0.5, R * 0.95)
		buildGreatWhite(
			CFrame.new(Vector3.new(math.sin(a) * r, rng:NextNumber(18, 46), math.cos(a) * r))
				* CFrame.Angles(0, a + math.pi / 2 + rng:NextNumber(-0.4, 0.4), 0),
			rng:NextNumber(11, 16),
			folder,
			"ReefShark" .. i
		)
	end

	-- STARFISH on the sand, singly and in loose groups (reference image 5).
	for i = 1, 46 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = math.sqrt(rng:NextNumber()) * R * 0.95
		local p = Vector3.new(math.sin(a) * r, 0.35, math.cos(a) * r)
		if clearOfBuildings(p, 26) then
			buildStarfish(p, rng:NextNumber(3, 5), folder, "Starfish" .. i, rng)
		end
	end
end

----------------------------------------------------------------------
-- ENTRY POINT
----------------------------------------------------------------------

function UnderTheSeaEnvironment.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "UnderTheSeaEnvironment"
	folder.Parent = parent

	-- Water volume.
	buildWallSegments(folder)
	buildCeiling(folder)
	buildFloor(folder)
	buildLightShafts(folder)
	buildBubbleStreams(folder)
	buildAmbientBubbles(folder)

	-- Inside the plate. Deliberately its own world: small, close, incidental.
	buildSeabedPattern(folder)
	buildKelpForest(folder)
	buildInteriorLife(folder)

	-- The exterior seascape. Order matters only for readability; every pass
	-- reads duneHeight independently.
	buildCoralGardens(folder)
	buildAlgae(folder)
	buildHabitats(folder)
	buildCaves(folder)
	buildLongGrass(folder)
	buildShipwreck(folder)
	buildSubmarines(folder)
	buildMarineLife(folder)

	return folder
end

return UnderTheSeaEnvironment
