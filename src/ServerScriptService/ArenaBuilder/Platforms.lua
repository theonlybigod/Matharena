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
			"NameDisplay"     -- BillboardGui (Enabled=false by default - shown
			                     on hover only), contains a TextLabel named
			                     "NameLabel"
			"RankDisplay"     -- BillboardGui (Enabled=false by default - shown
			                     on hover only), contains a TextLabel named
			                     "RankLabel"
	  Future systems can find all platforms via:
			CollectionService:GetTagged("ContestantPlatform")
	  and identify a specific one via the PlatformIndex attribute, rather
	  than hardcoding Workspace paths.

	Spotlight fixtures removed entirely, per explicit direction ("I don't
	want those features anymore") - platforms no longer have a
	"SpotlightFixture"/SpotLight above them at all.

	Hover detection lives on the PLAYER CHARACTER standing on a platform,
	not on the platform itself - see MatchSystem/Teleporter.lua (which
	attaches/removes it when assigning/returning players) and
	PlatformHoverController.client.lua (which shows/hides NameDisplay/
	RankDisplay in response). An unoccupied platform has nothing to hover.
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
	-- Hover-only display pass: hidden by default now (was always visible).
	-- See PlatformHoverController.client.lua (StarterPlayerScripts), which
	-- toggles this Enabled flag locally per-viewer based on
	-- HoverDetector's MouseHoverEnter/MouseHoverLeave events (added below,
	-- on the platform's Base). The actual name/rank TEXT is still written
	-- the exact same way as before, by MatchSystem/Teleporter.lua - only
	-- visibility changed, not the underlying data flow.
	billboard.Enabled = false
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
		color = ArenaConfig.PLATFORM_ALIVE_COLOR,
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

	-- Message 26 ("add cool podiums that all the players stand on"):
	-- a genuine tiered game-show-style riser sitting ON TOP of Base,
	-- WITHOUT changing Base's own size/position at all - Base stays
	-- exactly as every other system already expects it (Teleporter's
	-- landing math uses base.Position directly, Elimination.lua recolors
	-- Base/GlowRing by name), so nothing downstream needs to change.
	-- Verified the podium's own top surface (baseHeight + tier heights)
	-- stays well below Teleporter's drop point (base.Position.Y + 6,
	-- i.e. ground + baseHeight/2 + 6) so players still fall a short,
	-- natural distance onto it instead of spawning inside the geometry.
	-- Message 30 ("make the podiums even bigger"): tiers scaled up ~40%
	-- from the original Message 26 sizes (1.2/0.9 studs tall, diameters
	-- PLATFORM_DIAMETER-1.5/-3.5) - verified via calculation that the
	-- Teleporter drop point (base.Position.Y + 6) still clears the new,
	-- taller podium top with a real 1.56-stud fall distance, not a
	-- players-spawn-inside-the-geometry situation.
	local tier1Height = 1.68
	local tier2Height = 1.26
	local tier1Diameter = ArenaConfig.PLATFORM_DIAMETER - 1
	local tier2Diameter = ArenaConfig.PLATFORM_DIAMETER - 3

	PartUtils.CreateDisc({
		name = "PodiumTier1",
		diameter = tier1Diameter,
		thickness = tier1Height,
		position = position + Vector3.new(0, baseHeight + tier1Height / 2, 0),
		material = Enum.Material.Metal,
		color = ArenaConfig.PODIUM_TIER1_COLOR,
		parent = model,
	})
	PartUtils.CreateDisc({
		name = "PodiumTier1Trim",
		diameter = tier1Diameter + 0.3,
		thickness = 0.25,
		position = position + Vector3.new(0, baseHeight + tier1Height, 0),
		material = Enum.Material.Neon,
		color = ArenaConfig.NEON_COLOR,
		canCollide = false,
		parent = model,
	})

	PartUtils.CreateDisc({
		name = "PodiumTier2",
		diameter = tier2Diameter,
		thickness = tier2Height,
		position = position + Vector3.new(0, baseHeight + tier1Height + tier2Height / 2, 0),
		material = Enum.Material.Marble,
		color = ArenaConfig.PODIUM_TIER2_COLOR,
		parent = model,
	})
	PartUtils.CreateDisc({
		name = "PodiumTier2Trim",
		diameter = tier2Diameter + 0.3,
		thickness = 0.2,
		position = position + Vector3.new(0, baseHeight + tier1Height + tier2Height, 0),
		material = Enum.Material.Neon,
		color = ArenaConfig.NEON_COLOR,
		canCollide = false,
		parent = model,
	})

	-- Podium number plate on the front-facing edge (toward the center
	-- stage), so each contestant's podium visibly reads as "Podium N"
	-- from across the arena, distinct from the NameDisplay billboard.
	local towardCenter = (Vector3.new(0, 0, 0) - position)
	if towardCenter.Magnitude > 0.1 then
		towardCenter = towardCenter.Unit
	else
		towardCenter = Vector3.new(0, 0, 1)
	end
	local plateCFrame = CFrame.new(
		position + towardCenter * (tier2Diameter / 2 - 0.05) + Vector3.new(0, baseHeight + tier1Height + tier2Height / 2, 0),
		position + towardCenter * 1000 + Vector3.new(0, baseHeight + tier1Height + tier2Height / 2, 0)
	)
	local numberPlate = PartUtils.CreatePart({
		name = "PodiumNumberPlate",
		size = Vector3.new(1.4, 0.9, 0.1),
		cframe = plateCFrame,
		material = Enum.Material.Neon,
		color = ArenaConfig.NEON_COLOR,
		canCollide = false,
		parent = model,
	})
	local plateGui = Instance.new("SurfaceGui")
	plateGui.Face = Enum.NormalId.Front
	plateGui.Parent = numberPlate
	local plateLabel = Instance.new("TextLabel")
	plateLabel.Size = UDim2.fromScale(1, 1)
	plateLabel.BackgroundTransparency = 1
	plateLabel.Font = Enum.Font.GothamBlack
	plateLabel.TextScaled = true
	plateLabel.TextColor3 = Color3.fromRGB(10, 10, 14)
	plateLabel.Text = tostring(index)
	plateLabel.Parent = plateGui

	addBillboardLabel(model, "NameDisplay", "NameLabel", baseHeight + tier1Height + tier2Height + 5, "Player " .. index)
	addBillboardLabel(model, "RankDisplay", "RankLabel", baseHeight + tier1Height + tier2Height + 2.5, "Rank -")

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
