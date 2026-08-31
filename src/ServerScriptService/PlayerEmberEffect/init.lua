--[[
	PlayerEmberEffect.lua

	Gives every player a faint ember aura on the Volcano map - a few glowing
	flecks rising off the character, as though they are standing close enough
	to the lava to be catching light from it.

	SCOPE. Purely cosmetic. It attaches ParticleEmitters to character parts
	and does nothing else: no damage, no state, no data, nothing gameplay
	depends on. Removing this module would change how the map looks and
	nothing else.

	WHY SERVER-SIDE. Attaching on the server means everyone sees everyone
	else's embers. A LocalScript would only show the effect to the player
	running it, so a lobby of players would each see only themselves alight -
	which defeats the point of a shared visual.

	MAP-GATED. This is a Lava-map idea, not a global one - players should not
	smoulder in the Space or Ice Age lobbies. The map is resolved from
	DifficultyPlacesConfig.GetPlaceForPlaceId(game.PlaceId), the same lookup
	PlaceTeleportSystem uses to decide which tier a server is, so this can
	never disagree with what map the server actually built.

	DELIBERATELY SUBTLE. Rate 3-5 per emitter over two attachment points is
	a handful of flecks at a time. This is meant to read as "catching embers
	from the air", not as being on fire - a character wreathed in flame would
	fight with the map's own lava for attention and make players hard to
	pick out against it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DifficultyPlacesConfig = require(ReplicatedStorage.Modules.DifficultyPlacesConfig)

local PlayerEmberEffect = {}

-- Only this map gets embers.
local ENABLED_MAP_ID = "Lava"

local EMBER_HOT = Color3.fromRGB(255, 156, 62)
local EMBER_COOL = Color3.fromRGB(150, 30, 14)

local EFFECT_NAME = "PlayerEmbers"

--[[
	Builds one ember emitter.

	`intensity` scales the rate only - the torso carries slightly more than
	the head so the effect reads as rising from the body rather than sitting
	on top of the character like a hat.
]]
local function createEmitter(parent: Instance, intensity: number)
	local embers = Instance.new("ParticleEmitter")
	embers.Name = EFFECT_NAME
	embers.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, EMBER_HOT),
		ColorSequenceKeypoint.new(1, EMBER_COOL),
	})
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.28),
		NumberSequenceKeypoint.new(1, 0),
	})
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Lifetime = NumberRange.new(0.8, 1.6)
	embers.Rate = 3 * intensity
	embers.Speed = NumberRange.new(1.5, 3.5)
	embers.SpreadAngle = Vector2.new(35, 35)
	-- Positive Y so embers rise off the player the way hot ash does.
	embers.Acceleration = Vector3.new(0, 6, 0)
	embers.Rotation = NumberRange.new(0, 360)
	embers.RotSpeed = NumberRange.new(-90, 90)
	embers.Parent = parent
	return embers
end

--[[
	Attaches the aura to one character.

	Guards against double-attaching, because CharacterAdded fires again on
	every respawn and a character that somehow kept its emitters would
	otherwise accumulate a second set each time.
]]
local function applyTo(character: Model)
	-- R15 and R6 differ here, so fall back rather than assuming a rig type.
	local torso = character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")

	if torso and not torso:FindFirstChild(EFFECT_NAME) then
		createEmitter(torso, 1.6)
	end
	if head and not head:FindFirstChild(EFFECT_NAME) then
		createEmitter(head, 1)
	end
end

local function onCharacterAdded(character: Model)
	-- The rig parts stream in over a frame or two; waiting for the Humanoid
	-- is the cheapest reliable signal that the body exists.
	if not character:FindFirstChildOfClass("Humanoid") then
		character.ChildAdded:Wait()
	end
	task.defer(applyTo, character)
end

function PlayerEmberEffect.Init()
	local place = DifficultyPlacesConfig.GetPlaceForPlaceId(game.PlaceId)
	local mapId = place and place.mapId

	if mapId ~= ENABLED_MAP_ID then
		print(("[PlayerEmberEffect] Skipped - this server is map %q, embers are %s-only.")
			:format(tostring(mapId), ENABLED_MAP_ID))
		return
	end

	local function hook(player: Player)
		player.CharacterAdded:Connect(onCharacterAdded)
		if player.Character then
			onCharacterAdded(player.Character)
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)

	print("[PlayerEmberEffect] Initialized (Lava map ember aura)")
end

return PlayerEmberEffect
