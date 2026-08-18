--[[
	StreetLamps.lua

	Builds the lobby's signature street lamp fixture: a tall metal post,
	a single angled "neck" arm (reading as a curved shepherd's-hook
	silhouette - Roblox has no native curved-part primitive), a distinct
	lamp head housing with an inset glow bulb, and small Matharena-style
	neon accent trim. Replaces the old plain 12-stud pole + bare floating
	neon ball in Decorations.lua.

	Only one visual variant exists right now
	(StreetLampConfig.TYPE_ID = "StreetLampTypeA"). The design brief asked
	for "a unique signature design" with placement/orientation variation,
	not multiple visually distinct lamp types, so a second type wasn't
	invented just to have one - but the stable type id is still attached
	as a Model Attribute so a StreetLampTypeB could be added later without
	touching any call site.

	Static, source-generated geometry - only a lamp's position and yaw
	vary per-instance (from Decorations.lua); the model itself has no
	runtime randomness and no client-side animation (a street lamp's glow
	doesn't need to pulse/move, unlike the floating sign or the
	leaderboards' podium glow), keeping this both simple and cheap: one
	PointLight per lamp, no extra scripts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local StreetLampConfig = require(script.Parent.StreetLampConfig)

local StreetLamps = {}

--[[
	Builds one lamp at `position`, with the neck/head fanned by
	`yawDegrees` (the post and base are cylinders, symmetric around their
	own vertical axis, so yaw only actually affects which way the arm/head
	leans - that's the "orientation variation" the design brief asked for).
]]
function StreetLamps.Build(position: Vector3, yawDegrees: number, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "StreetLamp"
	model:SetAttribute(StreetLampConfig.TYPE_ID, true)

	local postHeight = StreetLampConfig.POST_HEIGHT
	local postRadius = StreetLampConfig.POST_DIAMETER / 2

	-- Small foundation plate + trim ring - reads as an actual constructed
	-- fixture rooted to the ground, not a pole stuck directly into the
	-- floor.
	PartUtils.CreateDisc({
		name = "Base",
		diameter = postRadius * 2 + 1,
		thickness = 0.4,
		position = position + Vector3.new(0, 0.2, 0),
		material = Enum.Material.Metal,
		color = StreetLampConfig.METAL_COLOR,
		parent = model,
	})
	PartUtils.CreateDisc({
		name = "BaseTrim",
		diameter = postRadius * 2 + 1.3,
		thickness = 0.12,
		position = position + Vector3.new(0, 0.42, 0),
		material = Enum.Material.Neon,
		color = StreetLampConfig.ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	-- Main post - a tall, clean cylinder (the "believable modern street
	-- lamp" body). Yaw-symmetric, so no rotation needed here at all.
	PartUtils.CreateDisc({
		name = "Post",
		diameter = postRadius * 2,
		thickness = postHeight,
		position = position + Vector3.new(0, postHeight / 2, 0),
		material = Enum.Material.Metal,
		color = StreetLampConfig.METAL_COLOR,
		parent = model,
	})

	-- One subtle accent ring partway up the post - a small futuristic
	-- structural detail, kept to a single ring so it stays "subtle"
	-- rather than busy.
	PartUtils.CreateDisc({
		name = "PostAccentRing",
		diameter = postRadius * 2 + 0.3,
		thickness = 0.15,
		position = position + Vector3.new(0, postHeight * 0.6, 0),
		material = Enum.Material.Neon,
		color = StreetLampConfig.ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	-- The neck: a single angled arm from the top of the post, tilted by
	-- NECK_ANGLE_DEGREES from vertical and fanned by this lamp's yaw, so
	-- it reads as a curved/hooked arm rather than a rigid right angle.
	local postTopCFrame = CFrame.new(position + Vector3.new(0, postHeight, 0)) * CFrame.Angles(0, math.rad(yawDegrees), 0)
	local neckLength = StreetLampConfig.NECK_LENGTH
	local neckTiltCFrame = postTopCFrame * CFrame.Angles(math.rad(StreetLampConfig.NECK_ANGLE_DEGREES), 0, 0)

	PartUtils.CreatePart({
		name = "Neck",
		size = Vector3.new(0.35, neckLength, 0.35),
		cframe = neckTiltCFrame * CFrame.new(0, neckLength / 2, 0),
		material = Enum.Material.Metal,
		color = StreetLampConfig.METAL_COLOR,
		canCollide = false,
		parent = model,
	})

	-- Lamp head housing - a real fixture shape hanging level at the end
	-- of the arm (like a lamp with a built-in swivel joint), not a bare
	-- glowing ball welded to a stick.
	local headPosition = (neckTiltCFrame * CFrame.new(0, neckLength, 0)).Position
	local head = PartUtils.CreatePart({
		name = "Head",
		size = StreetLampConfig.HEAD_SIZE,
		position = headPosition,
		material = Enum.Material.Metal,
		color = StreetLampConfig.METAL_COLOR,
		canCollide = false,
		parent = model,
	})

	-- Inset glow bulb - small and soft, not an oversized neon sphere.
	local bulb = PartUtils.CreatePart({
		name = "Bulb",
		size = Vector3.new(StreetLampConfig.BULB_SIZE, StreetLampConfig.BULB_SIZE * 0.55, StreetLampConfig.BULB_SIZE),
		position = headPosition - Vector3.new(0, StreetLampConfig.HEAD_SIZE.Y * 0.4, 0),
		material = Enum.Material.Neon,
		color = StreetLampConfig.GLOW_COLOR,
		canCollide = false,
		parent = model,
	})

	local light = Instance.new("PointLight")
	light.Color = StreetLampConfig.GLOW_COLOR
	light.Range = StreetLampConfig.LIGHT_RANGE
	light.Brightness = StreetLampConfig.LIGHT_BRIGHTNESS
	light.Parent = bulb

	-- Small Matharena-style accent: a thin neon cap trim on the head,
	-- tying it visually back to the rest of the lobby's brand accents.
	PartUtils.CreatePart({
		name = "HeadTrim",
		size = Vector3.new(StreetLampConfig.HEAD_SIZE.X + 0.2, 0.12, StreetLampConfig.HEAD_SIZE.Z + 0.2),
		position = headPosition + Vector3.new(0, StreetLampConfig.HEAD_SIZE.Y / 2 + 0.06, 0),
		material = Enum.Material.Neon,
		color = StreetLampConfig.ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	model.PrimaryPart = head
	model.Parent = parent
	return model
end

return StreetLamps
