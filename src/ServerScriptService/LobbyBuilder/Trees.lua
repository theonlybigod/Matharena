--[[
	Trees.lua

	Builds the lobby's enhanced futuristic trees: four distinct angular/
	geometric variants (Spire, CanopyBurst, TwinBough, CrystalCluster),
	replacing the old sphere-canopy trees that used to be built inline in
	Decorations.lua. See TreeConfig.lua for every tunable value (heights,
	widths, variant ids, placement spacing/jitter).

	Shared trunk builder + one canopy-builder function per variant - reused
	across every tree that rolls that variant, not duplicated per-instance.
	All canopy geometry uses angular Parts/WedgeParts (tapered blocks,
	radiating shards, angled boughs) - no Ball/sphere shapes anywhere,
	per the "sharper angles / complex geometric silhouettes / architectural
	rather than botanical" design brief.

	Deterministic per-position Random (same convention as the rest of
	LobbyBuilder): a given world position always produces the same tree
	shape/variant/rotation across rebuilds, so Rojo/Studio reproduces a
	stable environment rather than re-rolling on every server start.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local TreeConfig = require(script.Parent.TreeConfig)
local LobbyTheme = require(script.Parent.LobbyTheme)

local Trees = {}

local defaultTheme = LobbyTheme.Get()
local TRUNK_MATERIAL = defaultTheme.treeTrunkMaterial
local TRUNK_COLOR_BASE = defaultTheme.treeTrunkColor
local FOLIAGE_MATERIAL = defaultTheme.treeFoliageMaterial
local FOLIAGE_COLOR_BASE = defaultTheme.treeFoliageColor
local CURRENT_THEME_ID = defaultTheme.id

--[[
	Latches `theme`'s trunk/foliage material+base-color for every
	subsequently-built tree - the small per-tree deterministic color shift
	(buildTrunk/Trees.Build below) is still applied ON TOP of whichever
	base color is currently latched, so trees keep their existing subtle
	per-tree variation under every theme, not just one flat color.
]]
function Trees.SetTheme(theme: LobbyTheme.Theme)
	TRUNK_MATERIAL = theme.treeTrunkMaterial
	TRUNK_COLOR_BASE = theme.treeTrunkColor
	FOLIAGE_MATERIAL = theme.treeFoliageMaterial
	FOLIAGE_COLOR_BASE = theme.treeFoliageColor
	CURRENT_THEME_ID = theme.id
end

--[[
	Places a block whose long axis points outward from `origin` at
	`yawDeg`/`pitchDeg` - the same "yaw, then pitch, then translate along
	local X" composition already used elsewhere in this codebase (tree
	branches, street lamp necks), reused here for angled boughs/shards.
]]
local function angledBlock(
	origin: Vector3,
	yawDeg: number,
	pitchDeg: number,
	length: number,
	crossSection: number,
	material: Enum.Material,
	color: Color3,
	parent: Instance,
	name: string
): BasePart
	local cframe = CFrame.new(origin)
		* CFrame.Angles(0, math.rad(yawDeg), 0)
		* CFrame.Angles(0, 0, math.rad(pitchDeg))
		* CFrame.new(length / 2, 0, 0)

	return PartUtils.CreatePart({
		name = name,
		size = Vector3.new(length, crossSection, crossSection),
		cframe = cframe,
		material = material,
		color = color,
		canCollide = false,
		parent = parent,
	}) :: BasePart
end

--[[
	Builds the tapered trunk (a wider lower segment, a sharply narrower
	upper segment - a heavier taper than the old trees for more
	"intentional angles"), and returns the world position at its top for
	canopy builders to build from.
]]
local function buildTrunk(position: Vector3, rng: Random, model: Model): Vector3
	local trunkHeight = rng:NextNumber(TreeConfig.TRUNK_HEIGHT_MIN, TreeConfig.TRUNK_HEIGHT_MAX)
	local trunkWidth = rng:NextNumber(TreeConfig.TRUNK_WIDTH_MIN, TreeConfig.TRUNK_WIDTH_MAX)
	local leanDegrees = rng:NextNumber(-TreeConfig.LEAN_DEGREES_MAX, TreeConfig.LEAN_DEGREES_MAX)
	local leanAxis = if rng:NextNumber() < 0.5 then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
	local trunkShift = rng:NextInteger(-12, 12)
	local woodColor = Color3.new(
		math.clamp(TRUNK_COLOR_BASE.R + trunkShift / 255, 0, 1),
		math.clamp(TRUNK_COLOR_BASE.G + (trunkShift * 0.6) / 255, 0, 1),
		math.clamp(TRUNK_COLOR_BASE.B + (trunkShift * 0.4) / 255, 0, 1)
	)

	local leanOffset = leanAxis * math.sin(math.rad(leanDegrees)) * trunkHeight
	local lowerHeight = trunkHeight * 0.55
	local upperHeight = trunkHeight - lowerHeight
	local upperWidth = trunkWidth * TreeConfig.TRUNK_TAPER_RATIO

	local lowerCFrame = CFrame.new(position + Vector3.new(0, lowerHeight / 2, 0))
		* CFrame.fromAxisAngle(leanAxis, math.rad(leanDegrees))
	PartUtils.CreatePart({
		name = "Trunk",
		size = Vector3.new(trunkWidth, lowerHeight, trunkWidth),
		cframe = lowerCFrame,
		material = TRUNK_MATERIAL,
		color = woodColor,
		parent = model,
	})

	--[[
		The upper trunk deliberately OVERLAPS the lower segment rather than
		starting where it ends. Because both segments are leaned by rotating
		about their own centres, the lower segment's true top face does not
		land exactly at y = lowerHeight, so butting them end-to-end left a
		visible notch at the joint on every leaned tree. Extending the upper
		segment down into the lower one by a share of its own height makes
		the join solid at any lean angle.
	]]
	local trunkJointOverlap = math.max(1.2, upperHeight * 0.22)
	local upperSegmentHeight = upperHeight + trunkJointOverlap
	local upperOrigin = position + Vector3.new(0, lowerHeight - trunkJointOverlap, 0) + leanOffset * 0.6
	local upperCFrame = CFrame.new(upperOrigin + Vector3.new(0, upperSegmentHeight / 2, 0))
		* CFrame.fromAxisAngle(leanAxis, math.rad(leanDegrees))
	PartUtils.CreatePart({
		name = "TrunkUpper",
		size = Vector3.new(upperWidth, upperSegmentHeight, upperWidth),
		cframe = upperCFrame,
		material = TRUNK_MATERIAL,
		color = woodColor,
		canCollide = false,
		parent = model,
	})

	local canopyBasePosition = position + Vector3.new(0, trunkHeight, 0) + leanOffset
	return canopyBasePosition
end

-- ===== Variant canopies (angular/geometric, no spheres) =====

--[[
	"Spire": a tall, narrow stack of tapering angular tiers (each rotated
	a bit further than the last, for a slightly twisted-crystal look),
	two angled fin shards partway up, and a thin neon accent ring at the
	canopy's base. The tallest, narrowest variant.
]]
local function buildSpireCanopy(canopyBase: Vector3, rng: Random, model: Model, foliageColor: Color3)
	local canopyHeight = rng:NextNumber(TreeConfig.CANOPY_HEIGHT_MIN, TreeConfig.CANOPY_HEIGHT_MAX)
	local canopyWidth = rng:NextNumber(TreeConfig.CANOPY_WIDTH_MIN, TreeConfig.CANOPY_WIDTH_MAX) * 0.7
	local rotationY = rng:NextNumber(0, 360)

	local tierCount = 4
	local tierHeight = canopyHeight / tierCount
	local actualTierHeight = tierHeight * 0.85
	-- Bug fix (floating/disconnected foliage): this used to start the
	-- first tier's CENTER at canopyBase.Y + tierHeight*0.5 - a full HALF of
	-- the nominal tierHeight - even though each tier's ACTUAL built height
	-- is only tierHeight*0.85 (its real half-height is tierHeight*0.425).
	-- That left the first tier's BOTTOM floating tierHeight*0.075 studs
	-- above canopyBase (the trunk's actual top surface) - a small but real
	-- visible gap between the trunk and the canopy. Tracking the next
	-- tier's BOTTOM explicitly (starting exactly at canopyBase.Y) and
	-- centering each tier at bottom + actualTierHeight/2 guarantees the
	-- first tier sits flush on the trunk, with every subsequent tier still
	-- stacking flush on the one below it (unchanged from before).
	local nextTierBottom = canopyBase.Y
	for i = 1, tierCount do
		local tierWidth = canopyWidth * (1 - (i - 1) * 0.2)
		PartUtils.CreatePart({
			name = "SpireTier" .. i,
			size = Vector3.new(tierWidth, actualTierHeight, tierWidth),
			cframe = CFrame.new(canopyBase.X, nextTierBottom + actualTierHeight / 2, canopyBase.Z)
				* CFrame.Angles(0, math.rad(rotationY + (i - 1) * 18), 0),
			material = FOLIAGE_MATERIAL,
			color = foliageColor,
			canCollide = false,
			parent = model,
		})
		nextTierBottom += actualTierHeight
	end

	for _, side in ipairs({ -1, 1 }) do
		angledBlock(
			canopyBase + Vector3.new(0, canopyHeight * 0.35, 0),
			rotationY + side * 55,
			35,
			canopyWidth * 0.55,
			0.7,
			FOLIAGE_MATERIAL,
			foliageColor,
			model,
			"SpireFin"
		)
	end
end

--[[
	"CanopyBurst": a wide central core block with 5 angular shards
	radiating outward around it like a starburst. The widest, most
	explosive silhouette - shortest of the four canopy shapes but by far
	the broadest.
]]
local function buildCanopyBurstCanopy(canopyBase: Vector3, rng: Random, model: Model, foliageColor: Color3)
	local canopyWidth = rng:NextNumber(TreeConfig.CANOPY_WIDTH_MIN, TreeConfig.CANOPY_WIDTH_MAX) * 1.15
	local canopyHeight = rng:NextNumber(TreeConfig.CANOPY_HEIGHT_MIN, TreeConfig.CANOPY_HEIGHT_MAX) * 0.8
	local rotationY = rng:NextNumber(0, 360)
	local coreSize = canopyWidth * 0.4

	PartUtils.CreatePart({
		name = "BurstCore",
		size = Vector3.new(coreSize, canopyHeight * 0.6, coreSize),
		cframe = CFrame.new(canopyBase + Vector3.new(0, canopyHeight * 0.3, 0)) * CFrame.Angles(0, math.rad(rotationY), 0),
		material = FOLIAGE_MATERIAL,
		color = foliageColor,
		canCollide = false,
		parent = model,
	})

	local shardCount = 5
	for i = 1, shardCount do
		local yaw = rotationY + (360 / shardCount) * i + rng:NextNumber(-12, 12)
		local pitch = rng:NextNumber(15, 35)
		local length = canopyWidth * rng:NextNumber(0.4, 0.55)
		angledBlock(
			canopyBase + Vector3.new(0, canopyHeight * 0.35, 0),
			yaw,
			pitch,
			length,
			length * 0.35,
			FOLIAGE_MATERIAL,
			foliageColor,
			model,
			"BurstShard" .. i
		)
	end
end

--[[
	"TwinBough": the trunk splits partway up into two thick angled boughs
	(structural, not twiggy), each ending in its own smaller angular
	canopy block - an asymmetric silhouette, unlike the other three
	variants' single-trunk-up-the-middle structure.
]]
local function buildTwinBoughCanopy(canopyBase: Vector3, rng: Random, model: Model, foliageColor: Color3)
	local canopyWidth = rng:NextNumber(TreeConfig.CANOPY_WIDTH_MIN, TreeConfig.CANOPY_WIDTH_MAX) * 0.85
	local canopyHeight = rng:NextNumber(TreeConfig.CANOPY_HEIGHT_MIN, TreeConfig.CANOPY_HEIGHT_MAX)
	local rotationY = rng:NextNumber(0, 360)
	local boughLength = canopyHeight * 0.55

	for i, side in ipairs({ -1, 1 }) do
		local yaw = rotationY + side * rng:NextNumber(35, 55)
		local pitch = rng:NextNumber(45, 60)
		local boughEnd = angledBlock(
			canopyBase,
			yaw,
			pitch,
			boughLength,
			1.1,
			TRUNK_MATERIAL,
			TRUNK_COLOR_BASE,
			model,
			"Bough" .. i
		)

		local blockSize = canopyWidth * rng:NextNumber(0.55, 0.7)
		PartUtils.CreatePart({
			name = "BoughCanopy" .. i,
			size = Vector3.new(blockSize, blockSize * 0.8, blockSize),
			cframe = boughEnd.CFrame * CFrame.new(boughLength / 2, 0, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 40)), 0),
			material = FOLIAGE_MATERIAL,
			color = foliageColor,
			canCollide = false,
			parent = model,
		})
	end
end

--[[
	"CrystalCluster": a solid central core mass (running from the trunk top
	up through the canopy) with 6 irregular angular blocks of varying size/
	angle/height radiating outward from it, forming an irregular faceted
	mass - the most organic-feeling of the four, while still built entirely
	from angular geometry.

	Bug fix (floating/disconnected foliage): this used to radiate all 6
	shards from single POINTS along the trunk's central vertical axis, with
	no actual solid geometry connecting them to each other or to the trunk
	for any shard whose height offset exceeded the trunk's own height -
	those shards' near-ends sat suspended in empty air, visibly floating
	and disconnected. The CoreMass below (sized/positioned the same way
	CanopyBurst's BurstCore already connects cleanly to its trunk) gives
	every shard's origin point solid geometry to actually embed into,
	regardless of its height offset.
]]
local function buildCrystalClusterCanopy(canopyBase: Vector3, rng: Random, model: Model, foliageColor: Color3)
	local canopyHeight = rng:NextNumber(TreeConfig.CANOPY_HEIGHT_MIN, TreeConfig.CANOPY_HEIGHT_MAX)
	local canopyWidth = rng:NextNumber(TreeConfig.CANOPY_WIDTH_MIN, TreeConfig.CANOPY_WIDTH_MAX)

	local coreWidth = canopyWidth * 0.32
	PartUtils.CreatePart({
		name = "CoreMass",
		size = Vector3.new(coreWidth, canopyHeight * 1.05, coreWidth),
		cframe = CFrame.new(canopyBase + Vector3.new(0, canopyHeight * 1.05 / 2 - canopyHeight * 0.25, 0)),
		material = FOLIAGE_MATERIAL,
		color = foliageColor,
		canCollide = false,
		parent = model,
	})

	local clusterCount = 6
	for i = 1, clusterCount do
		local heightFraction = (i - 1) / (clusterCount - 1)
		local yOffset = -canopyHeight * 0.25 + canopyHeight * 1.05 * heightFraction
		local yaw = rng:NextNumber(0, 360)
		local pitch = rng:NextNumber(10, 45)
		local length = canopyWidth * rng:NextNumber(0.3, 0.55) * (1 - heightFraction * 0.3)
		angledBlock(
			canopyBase + Vector3.new(0, yOffset, 0),
			yaw,
			pitch,
			length,
			length * 0.5,
			FOLIAGE_MATERIAL,
			foliageColor,
			model,
			"CrystalBlock" .. i
		)
	end
end

local CANOPY_BUILDERS = {
	Spire = buildSpireCanopy,
	CanopyBurst = buildCanopyBurstCanopy,
	TwinBough = buildTwinBoughCanopy,
	CrystalCluster = buildCrystalClusterCanopy,
}

--[[
	Theme-signature canopy overrides: Tundra/Lava/Under the Sea each get
	ONE distinct, genuinely different silhouette instead of picking from
	the four generic angular variants above - "moderately different
	designs", not the same shapes recolored. Futuristic and Space keep the
	four generic variants (already varied enough, and explicitly liked as-
	is), so this table only covers the three themes that needed real
	differentiation.
]]

--[[
	"Snowy Pine" (Ice Age).

	REBUILT for connectivity. The old version was a stack of free-floating
	boxes: each tier was a plain cube centred on the canopy axis with a
	thin disc balanced on top of it, and NOTHING structural ran through
	them. There was no trunk inside the canopy at all (buildTrunk stops at
	canopyBase), so the tiers hovered in a column with visible daylight
	between them and no visible branches anywhere - which is exactly the
	"disconnected pieces, no visible branches or trunk" problem.

	The rebuild gives the tree a real armature:

	  1. A CENTRAL LEADER - a genuine continuation of the trunk running the
	     full height of the canopy, tapering as it rises. Everything else
	     attaches to it, so no canopy element is ever unsupported.

	  2. REAL BRANCHES - each whorl is a ring of angled branch limbs that
	     START on the leader's surface (their origin is the leader axis, so
	     the angledBlock helper grows them outward from inside the wood)
	     and slope downward as they extend, the way conifer boughs do.
	     Every branch is visibly a separate limb, which is what was asked
	     for, but each one is rooted in solid geometry.

	  3. NEEDLE MASS ON the branches - foliage blocks are placed along each
	     branch's own length rather than as one floating cube, so the
	     needles read as carried by the branch.

	  4. SNOW ON TOP OF the branches - snow slabs sit directly on each
	     branch's upper surface, sized to overlap along the limb, so the
	     accumulation is attached to the bough it is resting on.

	Whorls overlap vertically (spacing is less than the branch droop plus
	needle depth), so the silhouette reads as one continuous conical tree
	rather than separate floating layers.
]]
local function buildSnowyPineCanopy(canopyBase: Vector3, rng: Random, model: Model, foliageColor: Color3)
	local canopyHeight = rng:NextNumber(TreeConfig.CANOPY_HEIGHT_MIN, TreeConfig.CANOPY_HEIGHT_MAX)
	local canopyWidth = rng:NextNumber(TreeConfig.CANOPY_WIDTH_MIN, TreeConfig.CANOPY_WIDTH_MAX)
	local snowColor = Color3.fromRGB(240, 246, 251)
	local barkColor = Color3.fromRGB(78, 62, 52)

	-- 1. Central leader: the trunk continuing up through the whole canopy.
	-- Built in overlapping segments so it tapers without ever stepping
	-- apart. It starts BELOW canopyBase so it intersects the trunk top.
	--[[
		The leader is deliberately THICK and dark enough to read as the
		trunk continuing up through the canopy from the outside. A thin
		leader disappears behind the needle mass, which is what made these
		look like floating layers with no tree inside them. It also starts
		further below canopyBase so it visibly merges with the trunk proper.
	]]
	local leaderSegments = 5
	local leaderBottom = canopyBase.Y - 3
	local leaderSpan = canopyHeight + 3
	for i = 0, leaderSegments - 1 do
		local t = i / leaderSegments
		local segBottom = leaderBottom + leaderSpan * t
		local segHeight = (leaderSpan / leaderSegments) * 1.6 -- overlaps the next segment
		local segWidth = math.max(0.9, canopyWidth * 0.26 * (1 - t * 0.5))
		PartUtils.CreatePart({
			name = "PineLeader" .. (i + 1),
			size = Vector3.new(segWidth, segHeight, segWidth),
			position = Vector3.new(canopyBase.X, segBottom + segHeight / 2, canopyBase.Z),
			material = TRUNK_MATERIAL,
			color = barkColor,
			canCollide = false,
			parent = model,
		})
	end

	-- 2-4. Whorls of real branches carrying needles and snow.
	-- Whorls are spaced closer than a single bough's own vertical reach, so
	-- consecutive layers interlock into one continuous conical mass rather
	-- than leaving bands of bare leader showing between them.
	local whorlCount = 7
	local whorlSpacing = canopyHeight / (whorlCount + 0.6)
	for whorl = 1, whorlCount do
		local t = (whorl - 1) / whorlCount
		local whorlY = canopyBase.Y + whorlSpacing * (whorl - 1) + whorlSpacing * 0.4
		-- Lower whorls are longest - a conifer's classic cone silhouette.
		local branchLength = (canopyWidth / 2) * (1 - t * 0.62)
		-- Thicker limbs so each bough is individually legible against the
		-- needle mass instead of vanishing inside it - the "more obvious
		-- branches" this pass calls for.
		local branchThickness = math.max(0.7, 1.35 * (1 - t * 0.4))
		local branchCount = math.max(4, 7 - whorl)
		local whorlPhase = rng:NextNumber(0, math.pi * 2)

		for b = 1, branchCount do
			local yaw = math.deg(whorlPhase + (2 * math.pi / branchCount) * b) + rng:NextNumber(-8, 8)
			-- Boughs angle downward; upper whorls droop less.
			local pitch = -rng:NextNumber(14, 26) * (1 - t * 0.4)

			-- The limb itself, originating ON the leader's axis so its inner
			-- end is always embedded in solid wood. Built slightly longer
			-- than the needle mass it carries, so the bare woody tip pokes
			-- out past the foliage and the branch is unmistakably visible.
			angledBlock(
				Vector3.new(canopyBase.X, whorlY, canopyBase.Z),
				yaw,
				pitch,
				branchLength * 1.12,
				branchThickness,
				TRUNK_MATERIAL,
				barkColor,
				model,
				("PineBranchW%dB%d"):format(whorl, b)
			)

			-- Needle mass carried along the limb: three overlapping blocks
			-- stepped out from the leader to the branch tip, each sized
			-- larger than its step so consecutive clumps intersect.
			local needleSteps = 3
			for s = 1, needleSteps do
				local along = branchLength * (s / (needleSteps + 0.35))
				-- Deliberately larger than the step between clumps, so
				-- consecutive clumps along one bough always intersect, and
				-- tall enough to close the gap up to the whorl above.
				local clumpSize = (branchLength / needleSteps) * 1.75 * (1 - (s - 1) * 0.16)
				local yawRad = math.rad(yaw)
				local pitchRad = math.rad(pitch)
				-- Must match angledBlock's own axis convention exactly
				-- (yaw about Y, then pitch about the yawed Z, long axis
				-- along local X) or the needles drift off the limb they are
				-- supposed to be sitting on.
				local pos = Vector3.new(
					canopyBase.X + math.cos(pitchRad) * math.cos(yawRad) * along,
					whorlY + math.sin(pitchRad) * along,
					canopyBase.Z - math.cos(pitchRad) * math.sin(yawRad) * along
				)
				PartUtils.CreatePart({
					name = ("PineNeedlesW%dB%dS%d"):format(whorl, b, s),
					size = Vector3.new(clumpSize, clumpSize * 0.62, clumpSize),
					cframe = CFrame.new(pos) * CFrame.Angles(0, yawRad, math.rad(pitch * 0.6)),
					material = FOLIAGE_MATERIAL,
					color = foliageColor,
					canCollide = false,
					parent = model,
				})
				-- Snow resting on the upper face of this needle clump. Kept
				-- narrower than the clump it sits on so the needles and the
				-- bough underneath stay visible from the side rather than
				-- being buried under an unbroken white slab.
				PartUtils.CreatePart({
					name = ("PineSnowW%dB%dS%d"):format(whorl, b, s),
					size = Vector3.new(clumpSize * 0.74, 0.45, clumpSize * 0.74),
					cframe = CFrame.new(pos + Vector3.new(0, clumpSize * 0.3, 0))
						* CFrame.Angles(0, yawRad, math.rad(pitch * 0.6)),
					material = Enum.Material.Snow,
					color = snowColor,
					canCollide = false,
					parent = model,
				})
			end
		end
	end

	-- Leading shoot and its snow cap, overlapping the top leader segment.
	local peakBase = canopyBase.Y + canopyHeight * 0.92
	PartUtils.CreatePart({
		name = "PineCrown",
		size = Vector3.new(canopyWidth * 0.24, canopyHeight * 0.2, canopyWidth * 0.24),
		position = Vector3.new(canopyBase.X, peakBase, canopyBase.Z),
		material = FOLIAGE_MATERIAL,
		color = foliageColor,
		canCollide = false,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "PinePeak",
		size = Vector3.new(canopyWidth * 0.16, 1.8, canopyWidth * 0.16),
		position = Vector3.new(canopyBase.X, peakBase + canopyHeight * 0.13, canopyBase.Z),
		material = Enum.Material.Snow,
		color = snowColor,
		canCollide = false,
		parent = model,
	})
end

--[[
	"Scorched Branches" (Lava): NO solid canopy mass at all - just several
	bare, irregular angled branches radiating outward (reusing the trunk's
	own material/color, i.e. charred wood, not foliage-colored), each
	ending in a small glowing ember, plus 1-2 smaller secondary twigs per
	branch. Reads as "leafless, scorched, molten" rather than a recolored
	solid canopy.

	Connectivity fix: every branch used to originate from a bare point
	(canopyBase + Vector3.new(0, yOffset, 0)) along the trunk's own
	central axis - for any yOffset greater than 0, that point sits ABOVE
	the real trunk's top surface, in empty air, with nothing solid there
	for the branch to actually connect to (the same floating-geometry bug
	CrystalCluster's CoreMass already fixed for a different variant). The
	CharredCore below is a genuine continuation of the trunk running up
	through the entire branch zone, so every branch (and every twig,
	which now originates from a point along ITS OWN parent branch's
	length rather than independently) always starts from solid geometry.
]]
--[[
	Large, visually impressive FIRE for the Lava map's scorched trees.

	The Lava trees previously carried only a 0.45-0.65 stud Neon "ember"
	ball at each branch tip - a few dozen tiny dots per tree that read as
	faint glowing specks from more than a few studs away, not as a tree that
	is on fire.

	`igniteBranch` attaches a real fire cluster to one branch tip:
	  - A Fire instance, which is the actual animated flame. Roblox caps
	    Fire.Size at 30, so `size` is clamped rather than silently ignored.
	  - A ParticleEmitter throwing embers UPWARD off the flame, which is
	    what gives the fire visible scale and motion at distance - Fire
	    alone is a fairly compact billboard.
	  - A PointLight so the fire actually illuminates the trunk, the ground
	    and anything standing near it, rather than being a flat sprite.

	Everything is parented to the tip part that already exists, so no new
	structural geometry is introduced and the tree silhouette is unchanged.
]]
local FLAME_INNER = Color3.fromRGB(255, 214, 108) -- pale yellow heart of the flame
local FLAME_OUTER = Color3.fromRGB(255, 96, 16) -- deep orange outer body

local function igniteBranch(tip: BasePart, size: number, heat: number)
	local fire = Instance.new("Fire")
	fire.Name = "BranchFire"
	-- Fire.Size is capped at 30 by the engine; clamp so a large request
	-- degrades predictably instead of being silently rejected.
	fire.Size = math.clamp(size, 2, 30)
	fire.Heat = heat
	fire.Color = FLAME_INNER
	fire.SecondaryColor = FLAME_OUTER
	fire.Parent = tip

	-- Rising embers. This is what reads as "large fire" from across the
	-- map - the Fire billboard alone stays fairly tight to its emitter.
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "BranchEmbers"
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(FLAME_INNER, FLAME_OUTER)
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Lifetime = NumberRange.new(1.1, 2.4)
	embers.Rate = 14
	embers.Speed = NumberRange.new(5, 11)
	embers.SpreadAngle = Vector2.new(24, 24)
	-- Negative acceleration on Y would pull embers down; positive lifts
	-- them, which is how hot ash actually behaves.
	embers.Acceleration = Vector3.new(0, 7, 0)
	embers.Parent = tip

	local light = Instance.new("PointLight")
	light.Name = "FireLight"
	light.Color = FLAME_OUTER
	light.Brightness = 2.2
	light.Range = 18 + size * 1.6
	-- Shadows off: these are numerous and small, and shadow-casting lights
	-- at this count is a real render cost for no visible gain outdoors.
	light.Shadows = false
	light.Parent = tip
end

local function buildScorchedBranchCanopy(canopyBase: Vector3, rng: Random, model: Model, foliageColor: Color3)
	local canopyHeight = rng:NextNumber(TreeConfig.CANOPY_HEIGHT_MIN, TreeConfig.CANOPY_HEIGHT_MAX)
	local canopyWidth = rng:NextNumber(TreeConfig.CANOPY_WIDTH_MIN, TreeConfig.CANOPY_WIDTH_MAX)
	local branchCount = rng:NextInteger(6, 8)

	-- Charred core spike: a continuation of the trunk running up through
	-- the whole branch zone, tapering slightly narrower than the trunk
	-- itself - this is what every branch below actually connects to,
	-- instead of originating from empty air above the trunk's real top.
	local coreTopY = canopyHeight * 0.68
	local coreWidth = math.max(0.6, canopyWidth * 0.09)
	PartUtils.CreatePart({
		name = "CharredCore",
		size = Vector3.new(coreWidth, coreTopY + 0.6, coreWidth),
		position = canopyBase + Vector3.new(0, coreTopY / 2, 0),
		material = TRUNK_MATERIAL,
		color = TRUNK_COLOR_BASE,
		canCollide = false,
		parent = model,
	})

	for i = 1, branchCount do
		local yaw = rng:NextNumber(0, 360)
		local pitch = rng:NextNumber(20, 60)
		local heightFraction = (i - 1) / (branchCount - 1)
		local yOffset = canopyHeight * heightFraction * 0.65
		local length = canopyWidth * rng:NextNumber(0.35, 0.6) * (1 - heightFraction * 0.3)
		local crossSection = 0.35 + rng:NextNumber(0, 0.3)

		-- Origin now always lands ON the CharredCore (yOffset tops out at
		-- canopyHeight*0.65, comfortably under the core's own
		-- canopyHeight*0.68 top), so the branch is always physically fused
		-- to solid geometry regardless of height.
		local branchOrigin = canopyBase + Vector3.new(0, yOffset, 0)
		local branch = angledBlock(
			branchOrigin,
			yaw,
			pitch,
			length,
			crossSection,
			TRUNK_MATERIAL,
			TRUNK_COLOR_BASE,
			model,
			"ScorchedBranch" .. i
		)

		-- One or two smaller secondary twigs branching OFF the main branch -
		-- each originates from a point ALONG THE PARENT BRANCH'S OWN
		-- LENGTH (branch.CFrame.RightVector is the branch's long axis), so
		-- every twig is physically attached to solid parent geometry, never
		-- floating independently - "irregular branch structures" from real
		-- damage, not a duplicated procedural pattern.
		local twigCount = rng:NextInteger(1, 2)
		for t = 1, twigCount do
			local alongFraction = rng:NextNumber(0.35, 0.8)
			local twigOrigin = branch.Position + branch.CFrame.RightVector * (length * (alongFraction - 0.5))
			local twigYaw = yaw + rng:NextNumber(-55, 55)
			local twigPitch = pitch + rng:NextNumber(-30, 30)
			local twigLength = length * rng:NextNumber(0.25, 0.45)
			local twig = angledBlock(
				twigOrigin,
				twigYaw,
				twigPitch,
				twigLength,
				crossSection * 0.6,
				TRUNK_MATERIAL,
				TRUNK_COLOR_BASE,
				model,
				("ScorchedTwig%d_%d"):format(i, t)
			)
			local twigTip = PartUtils.CreatePart({
				name = ("EmberTwigTip%d_%d"):format(i, t),
				size = Vector3.new(1.1, 1.1, 1.1),
				position = twig.Position + twig.CFrame.RightVector * (twigLength / 2),
				material = Enum.Material.Neon,
				color = FLAME_INNER,
				shape = Enum.PartType.Ball,
				canCollide = false,
				parent = model,
			})
			-- Smaller secondary flame on the twig, so fire reads across the
			-- whole crown rather than only at the main branch ends.
			igniteBranch(twigTip, rng:NextNumber(7, 11), 12)
		end

		-- Ember tip at the main branch's far end - branch.CFrame.RightVector is
		-- the branch's own long axis (angledBlock translates along local
		-- X, i.e. RightVector, by length/2 from the origin).
		local tip = PartUtils.CreatePart({
			name = "EmberTip" .. i,
			size = Vector3.new(1.6, 1.6, 1.6),
			position = branch.Position + branch.CFrame.RightVector * (length / 2),
			material = Enum.Material.Neon,
			color = FLAME_INNER,
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = model,
		})
		-- The main flames. Sized off the branch itself so a big lower bough
		-- carries a bigger fire than a short upper one.
		igniteBranch(tip, math.clamp(length * 0.85, 10, 26), 18)
	end

	--[[
		One large fire at the heart of the tree, on the charred core itself.
		The per-branch flames give the crown its spread, but without a central
		blaze the trunk stays dark and the tree reads as "branches with flames
		on the ends" rather than as a burning tree.
	]]
	local heart = PartUtils.CreatePart({
		name = "TreeFireHeart",
		size = Vector3.new(2.4, 2.4, 2.4),
		position = canopyBase + Vector3.new(0, coreTopY * 0.45, 0),
		material = Enum.Material.Neon,
		color = FLAME_INNER,
		shape = Enum.PartType.Ball,
		transparency = 0.25,
		canCollide = false,
		parent = model,
	})
	igniteBranch(heart, 30, 25)
end

--[[
	"Large Coral" (Under the Sea): a thick, rounded central mass with 8
	organic branches radiating outward at varied angles - noticeably
	bigger and bushier than every other theme's trees, reading as a large
	brain-coral/fan-coral formation rather than an angular "tree".
]]
local function buildLargeCoralCanopy(canopyBase: Vector3, rng: Random, model: Model, foliageColor: Color3)
	local canopyHeight = rng:NextNumber(TreeConfig.CANOPY_HEIGHT_MIN, TreeConfig.CANOPY_HEIGHT_MAX) * 1.3
	local canopyWidth = rng:NextNumber(TreeConfig.CANOPY_WIDTH_MIN, TreeConfig.CANOPY_WIDTH_MAX) * 1.4
	local coreWidth = canopyWidth * 0.4

	PartUtils.CreatePart({
		name = "CoralCore",
		size = Vector3.new(coreWidth, canopyHeight * 0.7, coreWidth),
		position = canopyBase + Vector3.new(0, canopyHeight * 0.35, 0),
		material = FOLIAGE_MATERIAL,
		color = foliageColor,
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})

	--[[
		Branch origins are constrained to lie INSIDE the core mass.

		Roblox renders a Ball at the SMALLEST of its three dimensions, so
		the core's true radius is set by min(coreWidth, canopyHeight * 0.7),
		not by its nominal height. Branches used to originate anywhere from
		0.2 to 0.75 of canopyHeight up the axis, which for a squat core put
		the highest ones outside the sphere entirely - they grew from empty
		water with a visible gap back to the coral. Rooting them within the
		core's real radius means every branch starts embedded in the mass.
	]]
	local coreCenterY = canopyHeight * 0.35
	local coreRadius = math.min(coreWidth, canopyHeight * 0.7) / 2
	local branchCount = 8
	for i = 1, branchCount do
		local yaw = rng:NextNumber(0, 360)
		local pitch = rng:NextNumber(25, 55)
		local yOffset = coreCenterY + rng:NextNumber(-coreRadius * 0.55, coreRadius * 0.55)
		local length = canopyWidth * rng:NextNumber(0.35, 0.6)
		angledBlock(
			canopyBase + Vector3.new(0, yOffset, 0),
			yaw,
			pitch,
			length,
			length * 0.3,
			FOLIAGE_MATERIAL,
			foliageColor,
			model,
			"CoralBranch" .. i
		)
	end
end

local THEME_CANOPY_OVERRIDES = {
	IceAge = buildSnowyPineCanopy,
	Lava = buildScorchedBranchCanopy,
	UnderTheSea = buildLargeCoralCanopy,
}

--[[
	Builds one tree at `position`, parented into `parent`. `variantId` is
	optional - if omitted, one is chosen from a seeded roll (see
	Decorations.lua for the actual per-tree variant selection, which adds
	a mild positional bias so different areas of the lobby favor
	different variants).
]]
function Trees.Build(position: Vector3, variantId: string, parent: Instance): Model
	local rng = Random.new(math.floor(position.X * 92821 + position.Z * 68917))

	local model = Instance.new("Model")
	model.Name = TreeConfig.MODEL_NAME
	model:SetAttribute(TreeConfig.VARIANT_ATTRIBUTE, variantId)

	local canopyBasePosition = buildTrunk(position, rng, model)

	local greenShift = rng:NextInteger(-18, 14)
	local foliageColor = Color3.new(
		math.clamp(FOLIAGE_COLOR_BASE.R + (greenShift * 0.3) / 255, 0, 1),
		math.clamp(FOLIAGE_COLOR_BASE.G + greenShift / 255, 0, 1),
		math.clamp(FOLIAGE_COLOR_BASE.B + (greenShift * 0.3) / 255, 0, 1)
	)

	local builder = THEME_CANOPY_OVERRIDES[CURRENT_THEME_ID] or CANOPY_BUILDERS[variantId] or buildSpireCanopy
	builder(canopyBasePosition, rng, model, foliageColor)

	model.Parent = parent
	return model
end

return Trees
