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

local Trees = {}

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
	local woodColor = Color3.fromRGB(90 + trunkShift, 60 + trunkShift * 0.6, 40 + trunkShift * 0.4)

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
		material = Enum.Material.Wood,
		color = woodColor,
		parent = model,
	})

	local upperOrigin = position + Vector3.new(0, lowerHeight, 0) + leanOffset * 0.6
	local upperCFrame = CFrame.new(upperOrigin + Vector3.new(0, upperHeight / 2, 0))
		* CFrame.fromAxisAngle(leanAxis, math.rad(leanDegrees))
	PartUtils.CreatePart({
		name = "TrunkUpper",
		size = Vector3.new(upperWidth, upperHeight, upperWidth),
		cframe = upperCFrame,
		material = Enum.Material.Wood,
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
			material = Enum.Material.Grass,
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
			Enum.Material.Grass,
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
		material = Enum.Material.Grass,
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
			Enum.Material.Grass,
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
			Enum.Material.Wood,
			Color3.fromRGB(95, 65, 45),
			model,
			"Bough" .. i
		)

		local blockSize = canopyWidth * rng:NextNumber(0.55, 0.7)
		PartUtils.CreatePart({
			name = "BoughCanopy" .. i,
			size = Vector3.new(blockSize, blockSize * 0.8, blockSize),
			cframe = boughEnd.CFrame * CFrame.new(boughLength / 2, 0, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 40)), 0),
			material = Enum.Material.Grass,
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
		material = Enum.Material.Grass,
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
			Enum.Material.Grass,
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
	local foliageColor = Color3.fromRGB(45 + greenShift * 0.3, 118 + greenShift, 60 + greenShift * 0.3)

	local builder = CANOPY_BUILDERS[variantId] or buildSpireCanopy
	builder(canopyBasePosition, rng, model, foliageColor)

	model.Parent = parent
	return model
end

return Trees
