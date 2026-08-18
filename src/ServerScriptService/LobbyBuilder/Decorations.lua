--[[
	Decorations.lua

	Builds the lobby's decorative dressing: a perimeter ring of trees
	(every LobbyConfig.TREE_SPACING studs), streetlights and benches on
	concentric rings further inset, flower beds near each building
	entrance, and a floating, particle-emitting Matharena logo above the
	plaza.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local LobbyConfig = require(script.Parent.LobbyConfig)

local Decorations = {}

local half = LobbyConfig.LOBBY_SIZE / 2

--[[
	Deterministic per-position Random - the same world position always
	produces the same tree shape/lean/rotation across rebuilds (Message 16
	requires variation be "controlled enough that Rojo/Studio produces a
	stable intended environment", not fresh dice every server start).
]]
local function seededRandom(position: Vector3): Random
	local seed = math.floor(position.X * 92821 + position.Z * 68917)
	return Random.new(seed)
end

--[[
	True if `position` is within `radius` studs (XZ only) of anything in
	`points` - used to keep jittered tree placement away from spawns,
	building entrances, and the queue portal.
]]
local function isNear(position: Vector3, points: { Vector3 }, radius: number): boolean
	for _, point in ipairs(points) do
		if (Vector2.new(position.X, position.Z) - Vector2.new(point.X, point.Z)).Magnitude < radius then
			return true
		end
	end
	return false
end

-- Generates positions around a square ring, `inset` studs in from the
-- lobby edge, spaced `spacing` studs apart along each side, with a small
-- deterministic jitter and occasional skip/cluster so the placement
-- doesn't read as "tree -> exactly N studs -> tree" (Message 16, section 6).
-- `avoidPoints`/`avoidRadius` keep trees clear of spawns/buildings/portal.
local function ringPositions(
	inset: number,
	spacing: number,
	jitter: number?,
	avoidPoints: { Vector3 }?,
	avoidRadius: number?
): { Vector3 }
	local r = half - inset
	local rawPositions = {}

	for x = -r, r, spacing do
		table.insert(rawPositions, Vector3.new(x, 0, r))
		table.insert(rawPositions, Vector3.new(x, 0, -r))
	end

	local z = -r + spacing
	while z < r - spacing / 2 do
		table.insert(rawPositions, Vector3.new(r, 0, z))
		table.insert(rawPositions, Vector3.new(-r, 0, z))
		z += spacing
	end

	if not jitter then
		return rawPositions
	end

	local positions = {}
	for _, rawPosition in ipairs(rawPositions) do
		local rng = seededRandom(rawPosition)

		-- Skip ~15% of slots entirely for open breathing room between clusters.
		if rng:NextNumber() > 0.15 then
			local jittered = rawPosition + Vector3.new(rng:NextNumber(-jitter, jitter), 0, rng:NextNumber(-jitter, jitter))

			if not (avoidPoints and isNear(jittered, avoidPoints, avoidRadius or 0)) then
				table.insert(positions, jittered)

				-- ~25% chance of a small nearby cluster instead of a single tree.
				if rng:NextNumber() < 0.25 then
					local clusterOffset = Vector3.new(rng:NextNumber(-7, 7), 0, rng:NextNumber(-7, 7))
					local clusterPosition = jittered + clusterOffset
					if not (avoidPoints and isNear(clusterPosition, avoidPoints, avoidRadius or 0)) then
						table.insert(positions, clusterPosition)
					end
				end
			end
		end
	end

	return positions
end

--[[
	Adds a short angled branch near the top of the trunk - a handful of
	these per tree break up the "trunk goes straight into a ball" look
	without needing per-tree scripts (still just seeded Random + parts).
]]
local function createBranch(originPosition: Vector3, rng: Random, index: number, parent: Instance, woodColor: Color3)
	local length = rng:NextNumber(2, 4.2)
	local thickness = rng:NextNumber(0.35, 0.65)
	local yaw = rng:NextNumber(0, 360)
	local pitch = rng:NextNumber(25, 55)

	local cframe = CFrame.new(originPosition)
		* CFrame.Angles(0, math.rad(yaw), 0)
		* CFrame.Angles(0, 0, math.rad(pitch))
		* CFrame.new(length / 2, 0, 0)

	PartUtils.CreatePart({
		name = "Branch" .. index,
		size = Vector3.new(length, thickness, thickness),
		cframe = cframe,
		material = Enum.Material.Wood,
		color = woodColor,
		canCollide = false,
		parent = parent,
	}) 

end

--[[
	Builds one varied tree at `position`. Every dimension (trunk
	height/width/taper, branch count/angle, canopy style/size/shape, lean,
	rotation, color) is derived from a Random seeded by the position
	itself, so nearby trees look genuinely different from each other
	without needing per-tree scripts or any randomness that changes
	between rebuilds.

	Three canopy styles, picked per-tree, for real silhouette variety
	rather than every tree being the same sphere-on-a-stick:
		"Round"   - a single full sphere, optionally with a small offset
		            secondary clump for asymmetry
		"Layered" - three overlapping spheres of decreasing size stacked
		            upward, a fuller/bushier silhouette
		"Pine"    - three tapering spheres narrowing toward the top, a
		            distinctly taller/narrower conifer-like silhouette
]]
local function createTree(position: Vector3, parent: Instance)
	local rng = seededRandom(position)

	local trunkHeight = rng:NextNumber(5, 10)
	local trunkWidth = rng:NextNumber(1.0, 2.1)
	local canopyWidth = rng:NextNumber(5, 9.5)
	local canopyHeight = canopyWidth * rng:NextNumber(0.75, 1.25)
	local leanDegrees = rng:NextNumber(-7, 7)
	local leanAxis = if rng:NextNumber() < 0.5 then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
	local rotationY = rng:NextNumber(0, 360)
	local greenShift = rng:NextInteger(-18, 12)
	local trunkShift = rng:NextInteger(-12, 12)
	local woodColor = Color3.fromRGB(90 + trunkShift, 60 + trunkShift * 0.6, 40 + trunkShift * 0.4)
	local foliageColor = Color3.fromRGB(45 + greenShift * 0.3, 120 + greenShift, 60 + greenShift * 0.3)

	local model = Instance.new("Model")
	model.Name = "Tree"
	model.Parent = parent

	local leanOffset = leanAxis * math.sin(math.rad(leanDegrees)) * trunkHeight

	-- Tapered trunk: a wider lower segment and a narrower upper segment,
	-- rather than one uniform cylinder-box.
	local lowerHeight = trunkHeight * 0.6
	local upperHeight = trunkHeight - lowerHeight
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
		size = Vector3.new(trunkWidth * 0.65, upperHeight, trunkWidth * 0.65),
		cframe = upperCFrame,
		material = Enum.Material.Wood,
		color = woodColor,
		canCollide = false,
		parent = model,
	})

	local canopyBasePosition = position + Vector3.new(0, trunkHeight, 0) + leanOffset

	-- A couple of short branches near the top of the trunk.
	local branchCount = rng:NextInteger(2, 3)
	for i = 1, branchCount do
		createBranch(canopyBasePosition - Vector3.new(0, canopyHeight * 0.15, 0), rng, i, model, woodColor)
	end

	local canopyStyleRoll = rng:NextNumber()
	local canopyCenter = canopyBasePosition + Vector3.new(0, canopyHeight * 0.4, 0)

	if canopyStyleRoll < 0.4 then
		-- "Round": single sphere, optionally with an asymmetric secondary clump.
		PartUtils.CreatePart({
			name = "Foliage",
			size = Vector3.new(canopyWidth, canopyHeight, canopyWidth),
			cframe = CFrame.new(canopyCenter) * CFrame.Angles(0, math.rad(rotationY), 0),
			material = Enum.Material.Grass,
			color = foliageColor,
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = model,
		})

		if rng:NextNumber() < 0.5 then
			local secondarySize = canopyWidth * rng:NextNumber(0.45, 0.65)
			local secondaryOffset = Vector3.new(
				rng:NextNumber(-canopyWidth * 0.4, canopyWidth * 0.4),
				rng:NextNumber(-canopyHeight * 0.2, canopyHeight * 0.3),
				rng:NextNumber(-canopyWidth * 0.4, canopyWidth * 0.4)
			)
			PartUtils.CreatePart({
				name = "FoliageSecondary",
				size = Vector3.new(secondarySize, secondarySize, secondarySize),
				position = canopyCenter + secondaryOffset,
				material = Enum.Material.Grass,
				color = foliageColor,
				shape = Enum.PartType.Ball,
				canCollide = false,
				parent = model,
			})
		end
	elseif canopyStyleRoll < 0.7 then
		-- "Layered": three overlapping spheres of decreasing size, stacked
		-- upward, for a fuller/bushier silhouette.
		local sizes = { canopyWidth, canopyWidth * 0.75, canopyWidth * 0.5 }
		local y = canopyBasePosition.Y
		for i, size in ipairs(sizes) do
			PartUtils.CreatePart({
				name = "FoliageLayer" .. i,
				size = Vector3.new(size, size * 0.85, size),
				cframe = CFrame.new(canopyBasePosition.X, y, canopyBasePosition.Z)
					* CFrame.Angles(0, math.rad(rotationY + i * 15), 0),
				material = Enum.Material.Grass,
				color = foliageColor,
				shape = Enum.PartType.Ball,
				canCollide = false,
				parent = model,
			})
			y += size * 0.45
		end
	else
		-- "Pine": three tapering spheres narrowing toward the top - a
		-- distinctly taller/narrower conifer-like silhouette.
		local tierCount = 3
		local y = canopyBasePosition.Y
		for i = 1, tierCount do
			local tierWidth = canopyWidth * (1 - (i - 1) * 0.28)
			local tierHeight = canopyHeight * 0.55
			PartUtils.CreatePart({
				name = "FoliageTier" .. i,
				size = Vector3.new(tierWidth, tierHeight, tierWidth),
				position = Vector3.new(canopyBasePosition.X, y + tierHeight * 0.35, canopyBasePosition.Z),
				material = Enum.Material.Grass,
				color = foliageColor,
				shape = Enum.PartType.Ball,
				canCollide = false,
				parent = model,
			})
			y += tierHeight * 0.7
		end
	end
end

local function createStreetlight(position: Vector3, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Streetlight"
	model.Parent = parent

	PartUtils.CreatePart({
		name = "Pole",
		size = Vector3.new(0.8, 12, 0.8),
		position = position + Vector3.new(0, 6, 0),
		material = Enum.Material.Metal,
		color = Color3.fromRGB(50, 50, 55),
		parent = model,
	})

	local lamp = PartUtils.CreatePart({
		name = "Lamp",
		size = Vector3.new(1.6, 1.6, 1.6),
		position = position + Vector3.new(0, 12, 0),
		material = Enum.Material.Neon,
		color = LobbyConfig.NEON_COLOR,
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})

	local light = Instance.new("PointLight")
	light.Color = LobbyConfig.NEON_COLOR
	light.Range = 16
	light.Brightness = 2
	light.Parent = lamp
end

local function createBench(position: Vector3, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Bench"
	model.Parent = parent

	PartUtils.CreatePart({
		name = "Seat",
		size = Vector3.new(4, 0.4, 1.5),
		position = position + Vector3.new(0, 1.2, 0),
		material = Enum.Material.WoodPlanks,
		color = Color3.fromRGB(110, 80, 55),
		parent = model,
	})

	PartUtils.CreatePart({
		name = "Back",
		size = Vector3.new(4, 1.2, 0.3),
		position = position + Vector3.new(0, 1.9, -0.6),
		material = Enum.Material.WoodPlanks,
		color = Color3.fromRGB(110, 80, 55),
		parent = model,
	})
end

local FLOWER_COLORS = {
	Color3.fromRGB(230, 60, 90),
	Color3.fromRGB(250, 200, 40),
	Color3.fromRGB(140, 90, 230),
}

local function createFlowerBed(position: Vector3, parent: Instance)
	for i, color in ipairs(FLOWER_COLORS) do
		PartUtils.CreatePart({
			name = "Flower" .. i,
			size = Vector3.new(0.8, 0.8, 0.8),
			position = position + Vector3.new((i - 2) * 1.2, 0.4, 0),
			material = Enum.Material.Neon,
			color = color,
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = parent,
		})
	end
end

local function createFloatingLogo(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "MatharenaLogo"
	model.Parent = parent

	local panel = PartUtils.CreatePart({
		name = "LogoPanel",
		size = Vector3.new(20, 6, 1),
		position = Vector3.new(0, LobbyConfig.LOGO_HEIGHT, 0),
		material = Enum.Material.Neon,
		color = LobbyConfig.NEON_COLOR,
		canCollide = false,
		parent = model,
	})

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- faces the plaza/spawns (+Z)
	gui.Parent = panel

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = "MATHARENA"
	label.Parent = gui

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(LobbyConfig.NEON_COLOR)
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Rate = 8
	emitter.Speed = NumberRange.new(1, 2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = panel

	-- Gentle floating bob, driven by TweenService rather than a per-frame
	-- loop script, so the position replicates efficiently on its own.
	local tween = TweenService:Create(
		panel,
		TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = panel.Position + Vector3.new(0, 3, 0) }
	)
	tween:Play()

	return model
end

function Decorations.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Decorations"
	folder.Parent = parent

	-- Keep tree placement clear of spawns, building entrances/footprints,
	-- and the queue portal (Message 16, section 6).
	local avoidPoints = { LobbyConfig.QUEUE_PORTAL_POSITION }
	for _, spawnPosition in ipairs(LobbyConfig.SPAWN_POSITIONS) do
		table.insert(avoidPoints, spawnPosition)
	end
	for _, def in ipairs(LobbyConfig.BUILDINGS) do
		table.insert(avoidPoints, def.position)
		-- Also avoid the plaza-facing entrance apron in front of each building.
		table.insert(avoidPoints, def.position + Vector3.new(0, 0, def.size.Y / 2 + 6))
	end

	local treesFolder = Instance.new("Folder")
	treesFolder.Name = "Trees"
	treesFolder.Parent = folder
	for _, position in ipairs(ringPositions(LobbyConfig.PERIMETER_INSET, LobbyConfig.TREE_SPACING, 5, avoidPoints, 10)) do
		createTree(position, treesFolder)
	end

	local lightsFolder = Instance.new("Folder")
	lightsFolder.Name = "Streetlights"
	lightsFolder.Parent = folder
	for _, position in ipairs(ringPositions(LobbyConfig.PERIMETER_INSET + 10, LobbyConfig.TREE_SPACING * 2)) do
		createStreetlight(position, lightsFolder)
	end

	local benchesFolder = Instance.new("Folder")
	benchesFolder.Name = "Benches"
	benchesFolder.Parent = folder
	for _, position in ipairs(ringPositions(LobbyConfig.PERIMETER_INSET + 20, LobbyConfig.TREE_SPACING * 2)) do
		createBench(position, benchesFolder)
	end

	local flowersFolder = Instance.new("Folder")
	flowersFolder.Name = "FlowerBeds"
	flowersFolder.Parent = folder
	for _, def in ipairs(LobbyConfig.BUILDINGS) do
		createFlowerBed(def.position + Vector3.new(0, 0, def.size.Y / 2 + 2), flowersFolder)
	end

	createFloatingLogo(folder)

	return folder
end

return Decorations
