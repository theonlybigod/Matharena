--[[
	Sign.lua

	Builds the floating "MATHARENA" landmark sign: large, glowing
	typography suspended above the visual center of the lobby - no
	subtitle, no holographic ring, no border. This is the single, primary
	MATHARENA sign for the lobby.

	BillboardGui rewrite (final size pass): the text used to live in a
	SurfaceGui glued to the face of a single giant anchor Part
	(SignConfig.PANEL_SIZE). That hit a hard Roblox engine ceiling - 2048
	studs is the absolute maximum size for ANY single Part along any axis
	- which silently capped the sign at ~2.05x instead of the requested
	3x, no matter what the config said. A BillboardGui has no such limit:
	its Size is expressed directly in studs (not tied to any Part's
	physical dimensions), so the text can be made arbitrarily large by
	just changing SignConfig.BILLBOARD_SIZE, independent of Part size caps
	entirely. The anchor Part below is now just a small, ordinary-sized
	invisible part that holds the BillboardGui/PointLight/ParticleEmitter
	in place - it is NOT the visual surface anymore.

	Bonus from the rewrite: a BillboardGui always faces the camera (true
	billboarding), so the sign is now readable from literally any angle
	around the map, not just from directly in front of or behind a fixed
	Front/Back face pair - a strict improvement on the "keep the sign
	visible from around the map" requirement, achieved as a side effect
	of fixing the size cap rather than extra work.

	Branding cleanup pass: the holographic ring (a flattened blue Neon
	disc floating behind the text) and the old subtitle line beneath the
	title have both been removed entirely, per explicit direction that
	MATHARENA alone should be the sign's only visible branding, with no
	blue disc/platform of any kind beneath or around it.

	Energy beams removed (separate, earlier pass): an earlier pass added
	four upward neon beams connecting the sign down to the plaza. They
	ended up crossing directly through players' sightline to the sign/
	screen from ground level, obstructing the one thing this landmark
	exists to show - removed entirely rather than just made thinner/
	repositioned, per explicit direction to fully remove them.

	Sign cleanup pass: an earlier pass on this feature left two floating
	signs in the lobby at once - the original small "MatharenaLogo" (a
	solid neon panel, built in Decorations.lua) and this larger one. That
	was a duplication bug, not an intended two-sign design. The small one
	has been removed from Decorations.lua entirely (source, not just the
	Studio instance) so this is the only floating sign construction path
	left.

	This module only builds the static instances (position, text, glow,
	particles). The floating/bobbing motion is purely visual and is
	intentionally left to MatharenaSignController.client.lua
	(StarterPlayerScripts) instead of being animated here, so it doesn't
	cost server time/replication every frame for a cosmetic effect. That
	script tweens the anchor Part's Position; the BillboardGui (parented
	to the anchor) follows it automatically every frame with no extra code
	needed.

	The sign is named and attributed stably (SignConfig.SIGN_NAME, plus a
	matching boolean Attribute) so the client controller - or any later
	system - can find it reliably without depending on tree position.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local SignConfig = require(ReplicatedStorage.Modules.SignConfig)
local LobbyTheme = require(script.Parent.LobbyTheme)

local Sign = {}

-- Theme-driven glow color ONLY - text/position/size/font stay identical
-- across every map (SignConfig is shared with the client-side bob-motion
-- controller, which only reads position/bob timing, never color, so
-- overriding the glow color here doesn't affect that script). Defaults
-- to SignConfig's own value so this module behaves exactly as before if
-- SetTheme is never called.
local GLOW_COLOR = SignConfig.GLOW_COLOR

--[[
	Latches `theme`'s sign glow color for every subsequent Sign.Build call.
]]
function Sign.SetTheme(theme: LobbyTheme.Theme)
	GLOW_COLOR = theme.signGlowColor
end

--[[
	Builds the BillboardGui + TitleLabel on `anchor`. No background panel/
	frame behind the text - the glow comes from the text stroke, plus the
	shared PointLight/ParticleEmitter on the anchor part.
]]
local function createBillboard(anchor: BasePart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TitleBillboard"
	billboard.Adornee = anchor
	billboard.Size = UDim2.fromOffset(SignConfig.BILLBOARD_SIZE.X, SignConfig.BILLBOARD_SIZE.Y)
	billboard.AlwaysOnTop = false -- can still be occluded by buildings/geometry in front of it, like a real physical sign
	billboard.MaxDistance = 0 -- 0 = no distance cutoff, visible from anywhere in the lobby
	billboard.LightInfluence = 0 -- text reads as its own glowing typography, not affected by ambient/dusk lighting
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Name = "TitleLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = SignConfig.TEXT_FONT
	label.TextScaled = true
	label.Text = SignConfig.TEXT
	label.TextColor3 = SignConfig.TEXT_COLOR
	label.TextStrokeTransparency = SignConfig.TEXT_STROKE_TRANSPARENCY
	label.TextStrokeColor3 = GLOW_COLOR
	label.Parent = billboard

	-- Subtle top-to-bottom sheen on the lettering itself - the "shiny/
	-- reflective" quality, without needing any panel behind it.
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(SignConfig.TEXT_SHIMMER_COLORS[1], SignConfig.TEXT_SHIMMER_COLORS[2])
	gradient.Rotation = 90
	gradient.Parent = label
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

	-- Invisible anchor part - small and ordinary-sized now (not the giant
	-- visual surface it used to be). It only exists to hold the
	-- BillboardGui, the glow light, and the particle emitter in the right
	-- place, and to give MatharenaSignController.client.lua something to
	-- tween for the bob animation.
	local anchor = PartUtils.CreatePart({
		name = "SignPanel",
		size = Vector3.new(4, 4, 4),
		position = SignConfig.POSITION,
		transparency = 1,
		canCollide = false,
		parent = model,
	})
	model.PrimaryPart = anchor

	createBillboard(anchor)

	local glow = Instance.new("PointLight")
	glow.Color = GLOW_COLOR
	glow.Brightness = SignConfig.GLOW_BRIGHTNESS
	glow.Range = SignConfig.GLOW_RANGE
	glow.Parent = anchor

	-- Restrained sparkle - low rate so it reads as a soft accent, not a
	-- distraction from the text.
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(GLOW_COLOR)
	sparkle.Lifetime = NumberRange.new(1.5, 2.5)
	sparkle.Rate = SignConfig.PARTICLE_RATE
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new(0.6)
	sparkle.Parent = anchor

	model.Parent = parent
	return model
end

return Sign
