--[[
	Sign.lua

	Builds the floating "MATHARENA" landmark sign: a large, glowing,
	double-sided panel suspended above the visual center of the lobby
	(Message 2 addition).

	This module only builds the static instances (position, size, text,
	trim, glow, particles). The floating/bobbing motion is purely visual
	and is intentionally left to MatharenaSignController.client.lua
	(StarterPlayerScripts) instead of being animated here, so it doesn't
	cost server time/replication every frame for a cosmetic effect.

	The sign is named and attributed stably (SignConfig.SIGN_NAME, plus a
	matching boolean Attribute) so the client controller - or any later
	system - can find it reliably without depending on tree position.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local SignConfig = require(ReplicatedStorage.Modules.SignConfig)

local Sign = {}

-- Builds one face's readable label (Front and Back both get one, so the
-- sign is legible from the building side and the plaza/spawn side alike).
local function createFaceLabel(panel: BasePart, face: Enum.NormalId)
	local gui = Instance.new("SurfaceGui")
	gui.Name = face.Name .. "Gui"
	gui.Face = face
	gui.Parent = panel

	local label = Instance.new("TextLabel")
	label.Name = "TitleLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = SignConfig.TEXT_FONT
	label.TextScaled = true
	label.Text = SignConfig.TEXT
	label.TextColor3 = SignConfig.TEXT_COLOR
	label.TextStrokeTransparency = SignConfig.TEXT_STROKE_TRANSPARENCY
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = gui
end

-- Thin, shiny trim bar along the top or bottom edge of the panel. Kept to
-- just these two so the sign reads as clean/simple rather than busy.
local function createTrimBar(model: Model, verticalSign: number)
	local thickness = 1
	PartUtils.CreatePart({
		name = if verticalSign > 0 then "TrimTop" else "TrimBottom",
		size = Vector3.new(SignConfig.PANEL_SIZE.X + 2, thickness, SignConfig.PANEL_SIZE.Z + 1),
		position = SignConfig.POSITION + Vector3.new(0, verticalSign * (SignConfig.PANEL_SIZE.Y / 2 + thickness / 2), 0),
		material = Enum.Material.Metal,
		color = SignConfig.TRIM_COLOR,
		canCollide = false,
		parent = model,
	})
end

--[[
	Builds the sign and parents it under `parent` (the lobby folder).
	Returns the Model so LobbyBuilder can hold a reference if it ever needs
	one, though nothing currently requires that.
]]
function Sign.Build(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = SignConfig.SIGN_NAME
	model:SetAttribute(SignConfig.SIGN_NAME, true)

	local panel = PartUtils.CreatePart({
		name = "SignPanel",
		size = SignConfig.PANEL_SIZE,
		position = SignConfig.POSITION,
		material = Enum.Material.Neon,
		color = SignConfig.PANEL_COLOR,
		canCollide = false,
		parent = model,
	})
	model.PrimaryPart = panel

	createFaceLabel(panel, Enum.NormalId.Front)
	createFaceLabel(panel, Enum.NormalId.Back)

	createTrimBar(model, 1)
	createTrimBar(model, -1)

	local glow = Instance.new("PointLight")
	glow.Color = SignConfig.PANEL_COLOR
	glow.Brightness = SignConfig.GLOW_BRIGHTNESS
	glow.Range = SignConfig.GLOW_RANGE
	glow.Parent = panel

	-- Restrained sparkle - low rate so it reads as a soft accent, not a
	-- distraction from the text.
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(SignConfig.PANEL_COLOR)
	sparkle.Lifetime = NumberRange.new(1.5, 2.5)
	sparkle.Rate = SignConfig.PARTICLE_RATE
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new(0.6)
	sparkle.Parent = panel

	model.Parent = parent
	return model
end

return Sign
