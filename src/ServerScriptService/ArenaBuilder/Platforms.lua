--[[
	Platforms.lua

	Builds the 12 contestant platforms arranged in a ring around the
	center stage.

	Stable discovery contract for MatchSystem / CompetitionGameplay (later
	prompts) — no gameplay logic is implemented here, only the fixtures:
		- Each platform Model is tagged "ContestantPlatform" (CollectionService)
		- Each platform Model has an attribute PlatformIndex (1..12)
		- Each platform Model has these named children:
			"Base"            -- the physical platform part
			"GlowRing"        -- decorative base ring
			"NameDisplay"     -- BillboardGui, contains a TextLabel named "NameLabel"
			"RankDisplay"     -- BillboardGui, contains a TextLabel named "RankLabel"
			"SpotlightFixture"-- Part above the platform, contains a SpotLight named "Spotlight"
	  Future systems can find all platforms via:
			CollectionService:GetTagged("ContestantPlatform")
	  and identify a specific one via the PlatformIndex attribute, rather
	  than hardcoding Workspace paths.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local ArenaConfig = require(script.Parent.ArenaConfig)

local Platforms = {}

--[[
	Derives the ring radius from the desired center-to-center arc spacing
	between adjacent platforms: chord = 2 * R * sin(pi / count).
]]
function Platforms.ComputeRingRadius(): number
	local count = ArenaConfig.PLATFORM_COUNT
	return ArenaConfig.PLATFORM_SPACING / (2 * math.sin(math.pi / count))
end

local function addBillboardLabel(parent: Instance, name: string, labelName: string, offsetY: number, defaultText: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = name
	billboard.Size = UDim2.fromOffset(120, 36)
	billboard.StudsOffset = Vector3.new(0, offsetY, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = labelName
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = defaultText
	label.Parent = billboard
end

local function buildOne(index: number, position: Vector3, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Platform" .. index
	model.Parent = parent

	local baseHeight = ArenaConfig.PLATFORM_HEIGHT
	local base = PartUtils.CreateDisc({
		name = "Base",
		diameter = ArenaConfig.PLATFORM_DIAMETER,
		thickness = baseHeight,
		position = position + Vector3.new(0, baseHeight / 2, 0),
		material = Enum.Material.Metal,
		color = Color3.fromRGB(50, 55, 65),
		parent = model,
	})

	-- Glow ring: a wider, thin neon disc sitting at the platform's base so
	-- only its rim is visible around the platform's foot, reading as a
	-- glowing halo. (Roblox part primitives have no true annulus/torus
	-- shape without a mesh asset, so this is the closest primitive-only
	-- approximation.)
	PartUtils.CreateDisc({
		name = "GlowRing",
		diameter = ArenaConfig.PLATFORM_DIAMETER + 2,
		thickness = 0.4,
		position = position + Vector3.new(0, 0.2, 0),
		material = Enum.Material.Neon,
		color = ArenaConfig.NEON_COLOR,
		canCollide = false,
		parent = model,
	})

	addBillboardLabel(model, "NameDisplay", "NameLabel", baseHeight + 6, "Player " .. index)
	addBillboardLabel(model, "RankDisplay", "RankLabel", baseHeight + 3.5, "Rank -")

	local fixture = PartUtils.CreatePart({
		name = "SpotlightFixture",
		size = Vector3.new(1, 1, 1),
		position = position + Vector3.new(0, 20, 0),
		material = Enum.Material.Metal,
		color = Color3.fromRGB(40, 40, 45),
		canCollide = false,
		transparency = 0.3,
		parent = model,
	})

	local spotlight = Instance.new("SpotLight")
	spotlight.Name = "Spotlight"
	spotlight.Face = Enum.NormalId.Bottom
	spotlight.Range = 30
	spotlight.Angle = 45
	spotlight.Brightness = 3
	spotlight.Color = Color3.fromRGB(255, 255, 255)
	spotlight.Parent = fixture

	model.PrimaryPart = base
	CollectionService:AddTag(model, "ContestantPlatform")
	model:SetAttribute("PlatformIndex", index)

	return model
end

function Platforms.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Platforms"
	folder.Parent = parent

	local radius = Platforms.ComputeRingRadius()
	local count = ArenaConfig.PLATFORM_COUNT

	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2
		local position = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		buildOne(i, position, folder)
	end

	return folder
end

return Platforms
