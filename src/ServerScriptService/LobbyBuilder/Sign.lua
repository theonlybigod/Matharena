--[[
	Sign.lua

	Builds the floating "MATHARENA" landmark sign: large, glowing,
	borderless typography suspended above the visual center of the lobby,
	topped with a subtitle, a slowly-rotating holographic ring, and upward
	energy beams connecting it down toward the plaza below - a genuine
	"major installation" rather than just hovering text. This is the
	single, primary MATHARENA sign for the lobby.

	Sign cleanup pass: an earlier pass on this feature left two floating
	signs in the lobby at once - the original small "MatharenaLogo" (a
	solid neon panel, built in Decorations.lua) and this larger one. That
	was a duplication bug, not an intended two-sign design. The small one
	has been removed from Decorations.lua entirely (source, not just the
	Studio instance) so this is the only floating sign construction path
	left. This module also dropped its own metal trim bars - a physical
	frame around the text is exactly the "heavy border" this redesign
	removes; the glowing text stroke + light + particles + ring + beams now
	carry the sign's visual identity instead of a panel/frame.

	This module only builds the static instances (position, size, text,
	glow, particles, ring, beams). The floating/bobbing motion and the
	ring's rotation are purely visual and are intentionally left to
	MatharenaSignController.client.lua (StarterPlayerScripts) instead of
	being animated here, so neither costs server time/replication every
	frame for a cosmetic effect.

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
-- No background panel/frame behind the text - the glow comes from the
-- text stroke, plus the shared PointLight/ParticleEmitter on the part.
-- Reserves a strip at the bottom of the panel for a smaller subtitle
-- label, so the main title still reads as the dominant element.
local function createFaceLabel(panel: BasePart, face: Enum.NormalId)
	local gui = Instance.new("SurfaceGui")
	gui.Name = face.Name .. "Gui"
	gui.Face = face
	gui.Parent = panel

	local subtitleFraction = SignConfig.SUBTITLE_HEIGHT_FRACTION

	local label = Instance.new("TextLabel")
	label.Name = "TitleLabel"
	label.Size = UDim2.new(1, 0, 1 - subtitleFraction, 0)
	label.Position = UDim2.fromScale(0, 0)
	label.BackgroundTransparency = 1
	label.Font = SignConfig.TEXT_FONT
	label.TextScaled = true
	label.Text = SignConfig.TEXT
	label.TextColor3 = SignConfig.TEXT_COLOR
	label.TextStrokeTransparency = SignConfig.TEXT_STROKE_TRANSPARENCY
	label.TextStrokeColor3 = SignConfig.GLOW_COLOR
	label.Parent = gui

	-- Subtle top-to-bottom sheen on the lettering itself - the "shiny/
	-- reflective" quality, without needing any panel behind it.
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(SignConfig.TEXT_SHIMMER_COLORS[1], SignConfig.TEXT_SHIMMER_COLORS[2])
	gradient.Rotation = 90
	gradient.Parent = label

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "SubtitleLabel"
	subtitleLabel.Size = UDim2.new(1, 0, subtitleFraction, 0)
	subtitleLabel.Position = UDim2.new(0, 0, 1 - subtitleFraction, 0)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = Enum.Font.Gotham
	subtitleLabel.TextScaled = true
	subtitleLabel.Text = SignConfig.SUBTITLE_TEXT
	subtitleLabel.TextColor3 = SignConfig.GLOW_COLOR
	subtitleLabel.TextTransparency = 0.15
	subtitleLabel.Parent = gui
end

--[[
	Holographic ring: a flattened, mostly-transparent Cylinder disc
	floating just behind the text - reads immediately as a sci-fi hologram
	accent rather than a physical frame. Rotated client-side (see
	MatharenaSignController.client.lua); this just builds the static part.
]]
local function createRing(panel: BasePart): BasePart
	return PartUtils.CreateDisc({
		name = "HoloRing",
		diameter = SignConfig.RING_DIAMETER,
		thickness = SignConfig.RING_THICKNESS,
		position = panel.Position,
		material = Enum.Material.Neon,
		color = SignConfig.GLOW_COLOR,
		transparency = 0.82,
		canCollide = false,
		parent = panel.Parent,
	})
end

--[[
	Upward energy beams: thin, semi-transparent neon columns rising from
	the plaza toward the sign, arranged in a ring around (not through) the
	queue portal's own footprint - ties the floating sign visually to the
	ground below it, reading as a deliberate installation rather than text
	that happens to hover in the sky. Static/anchored, no per-frame cost.
]]
local function createBeams(parent: Instance, panel: BasePart)
	local beamHeight = panel.Position.Y - SignConfig.PANEL_SIZE.Y / 2
	for i = 1, SignConfig.BEAM_COUNT do
		local angle = (2 * math.pi / SignConfig.BEAM_COUNT) * i
		local x = SignConfig.BEAM_RADIUS * math.sin(angle)
		local z = SignConfig.BEAM_RADIUS * math.cos(angle)

		PartUtils.CreatePart({
			name = "EnergyBeam" .. i,
			size = Vector3.new(SignConfig.BEAM_THICKNESS, beamHeight, SignConfig.BEAM_THICKNESS),
			position = Vector3.new(x, beamHeight / 2, z),
			material = Enum.Material.Neon,
			color = SignConfig.GLOW_COLOR,
			transparency = 0.55,
			canCollide = false,
			parent = parent,
		})
	end
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

	-- Invisible anchor part. It only exists to hold the SurfaceGuis, the
	-- glow light, and the particle emitter in the right place - it has no
	-- visible fill/color/material of its own, so nothing reads as a panel
	-- or border around the lettering.
	local panel = PartUtils.CreatePart({
		name = "SignPanel",
		size = SignConfig.PANEL_SIZE,
		position = SignConfig.POSITION,
		transparency = 1,
		canCollide = false,
		parent = model,
	})
	model.PrimaryPart = panel

	createFaceLabel(panel, Enum.NormalId.Front)
	createFaceLabel(panel, Enum.NormalId.Back)
	createRing(panel)
	createBeams(model, panel)

	local glow = Instance.new("PointLight")
	glow.Color = SignConfig.GLOW_COLOR
	glow.Brightness = SignConfig.GLOW_BRIGHTNESS
	glow.Range = SignConfig.GLOW_RANGE
	glow.Parent = panel

	-- Restrained sparkle - low rate so it reads as a soft accent, not a
	-- distraction from the text.
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(SignConfig.GLOW_COLOR)
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
