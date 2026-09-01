--[[
	PlayerAuraEffect.lua

	Gives every player a subtle themed aura on the maps that call for one:

	  - Lava        : rising embers, as though catching heat from the lava.
	  - UnderTheSea : rising bubbles clinging to and lifting off the player.

	RENAMED FROM PlayerEmberEffect. That module did exactly this job but was
	named and written for one map, so adding the underwater version would
	have meant a near-identical second copy differing only in colour and
	direction. The per-map differences are now data in AURAS below, and the
	attach logic is written once.

	SCOPE. Purely cosmetic. It attaches ParticleEmitters to character parts
	and does nothing else: no damage, no state, no data, nothing gameplay
	depends on. Deleting this module would change how players look and
	nothing else.

	WHY SERVER-SIDE. Attaching on the server means everyone sees everyone
	else's aura. A LocalScript would show it only to the player running it,
	so a lobby would have each player seeing only themselves lit - which
	defeats the point of a shared visual.

	MAP-GATED. The map is resolved from
	DifficultyPlacesConfig.GetPlaceForPlaceId(game.PlaceId), the same lookup
	PlaceTeleportSystem uses to decide which tier a server is, so this can
	never disagree with the map the server actually built. A map with no
	entry in AURAS simply gets nothing.

	DELIBERATELY SUBTLE. A character wreathed in flame or foam would fight
	the map's own effects for attention and make players hard to pick out
	against them. These read as "catching embers from the air" and "trailing
	bubbles", not as being on fire or boiling.

	NOTE ON EDIT MODE. Unlike the map's own particle effects, this cannot
	appear in the Edit viewport: it attaches to player characters, which do
	not exist until the game runs. That is inherent to the feature, not an
	oversight.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DifficultyPlacesConfig = require(ReplicatedStorage.Modules.DifficultyPlacesConfig)

local PlayerAuraEffect = {}

local EFFECT_NAME = "PlayerAura"

export type AuraDef = {
	displayName: string,
	innerColor: Color3,
	outerColor: Color3,
	sizeStart: number,
	sizeEnd: number,
	transparencyStart: number,
	lifetimeMin: number,
	lifetimeMax: number,
	rate: number,
	speedMin: number,
	speedMax: number,
	acceleration: Vector3,
	lightEmission: number,
}

local AURAS: { [string]: AuraDef } = {
	Lava = {
		displayName = "ember",
		innerColor = Color3.fromRGB(255, 156, 62),
		outerColor = Color3.fromRGB(150, 30, 14),
		-- Embers burn down to nothing as they rise.
		sizeStart = 0.28,
		sizeEnd = 0,
		transparencyStart = 0.25,
		lifetimeMin = 0.8,
		lifetimeMax = 1.6,
		rate = 3,
		speedMin = 1.5,
		speedMax = 3.5,
		acceleration = Vector3.new(0, 6, 0),
		lightEmission = 1,
	},

	UnderTheSea = {
		displayName = "bubble",
		innerColor = Color3.fromRGB(225, 245, 255),
		outerColor = Color3.fromRGB(150, 205, 235),
		-- Bubbles GROW as they rise and the pressure drops - the opposite of
		-- embers, and the detail that stops this looking like recoloured fire.
		sizeStart = 0.12,
		sizeEnd = 0.34,
		transparencyStart = 0.4,
		-- Longer-lived and faster-accelerating: water lifts a bubble harder
		-- than hot air lifts an ember.
		lifetimeMin = 1.4,
		lifetimeMax = 2.6,
		rate = 5,
		speedMin = 1,
		speedMax = 2.5,
		acceleration = Vector3.new(0, 9, 0),
		lightEmission = 0.6,
	},
}

--[[
	Builds one aura emitter on `parent`.

	`intensity` scales the rate only - the torso carries more than the head
	so the effect reads as rising from the body rather than sitting on top of
	the character like a hat.
]]
local function createEmitter(parent: Instance, def: AuraDef, intensity: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = EFFECT_NAME
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, def.innerColor),
		ColorSequenceKeypoint.new(1, def.outerColor),
	})
	emitter.LightEmission = def.lightEmission
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, def.sizeStart),
		NumberSequenceKeypoint.new(1, def.sizeEnd),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, def.transparencyStart),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(def.lifetimeMin, def.lifetimeMax)
	emitter.Rate = def.rate * intensity
	emitter.Speed = NumberRange.new(def.speedMin, def.speedMax)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Acceleration = def.acceleration
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Parent = parent
	return emitter
end

--[[
	Attaches the aura to one character.

	Guards against double-attaching, because CharacterAdded fires again on
	every respawn and a character that somehow kept its emitters would
	otherwise accumulate a second set each time.
]]
local function applyTo(character: Model, def: AuraDef)
	-- R15 and R6 name their parts differently, so fall back rather than
	-- assuming a rig type.
	local torso = character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")

	if torso and not torso:FindFirstChild(EFFECT_NAME) then
		createEmitter(torso, def, 1.6)
	end
	if head and not head:FindFirstChild(EFFECT_NAME) then
		createEmitter(head, def, 1)
	end
end

function PlayerAuraEffect.Init()
	local place = DifficultyPlacesConfig.GetPlaceForPlaceId(game.PlaceId)
	local mapId = place and place.mapId
	local def = mapId and AURAS[mapId]

	if not def then
		print(("[PlayerAuraEffect] Skipped - no aura defined for map %q."):format(tostring(mapId)))
		return
	end

	local function onCharacterAdded(character: Model)
		-- The rig parts stream in over a frame or two; waiting for the
		-- Humanoid is the cheapest reliable signal that the body exists.
		if not character:FindFirstChildOfClass("Humanoid") then
			character.ChildAdded:Wait()
		end
		task.defer(applyTo, character, def)
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

	print(("[PlayerAuraEffect] Initialized (%s aura for map %s)"):format(def.displayName, mapId))
end

return PlayerAuraEffect
