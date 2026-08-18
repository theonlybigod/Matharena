--[[
	EffectsController.client.lua

	Client-side visual flourishes (Message 12): confetti/fireworks on a
	match win, full-screen color flashes on correct/wrong/winner, and
	floating "+10 XP"-style reward popups. Purely presentational - reacts
	to existing server remotes (TurnResolved, MatchWinner, RewardGranted),
	never decides game state itself.

	Particle textures are intentionally left unset (Roblox's built-in
	ParticleEmitter default) rather than referencing a specific numbered
	texture asset id Claude can't verify actually exists.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local EffectsConfig = require(ReplicatedStorage.Modules.EffectsConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")

-- ===== Screen flash =====

local flashFrame = Instance.new("Frame")
flashFrame.Name = "ScreenFlash"
flashFrame.Size = UDim2.fromScale(1, 1)
flashFrame.BackgroundTransparency = 1
flashFrame.ZIndex = 50
flashFrame.Parent = mainUI

local function flashScreen(color: Color3)
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = 0.55
	TweenService:Create(
		flashFrame,
		TweenInfo.new(EffectsConfig.FLASH_DURATION_SECONDS, Enum.EasingStyle.Quad),
		{ BackgroundTransparency = 1 }
	):Play()
end

-- ===== Floating reward popups =====

local rewardColors: { [string]: Color3 } = {
	XP = UITheme.COLORS.Accent,
	Coins = UITheme.COLORS.Gold,
	Gems = UITheme.COLORS.Gem,
}

local function showFloatingReward(rewardType: string, amount: number)
	local label = Instance.new("TextLabel")
	label.Name = "FloatingReward"
	label.Size = UDim2.fromOffset(180, 40)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.62, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = rewardColors[rewardType] or UITheme.COLORS.Text
	label.Text = ("+%d %s"):format(amount, rewardType)
	label.ZIndex = 60
	label.Parent = mainUI

	local tween = TweenService:Create(
		label,
		TweenInfo.new(EffectsConfig.FLOATING_REWARD_DURATION_SECONDS, Enum.EasingStyle.Quad),
		{
			Position = label.Position - UDim2.fromOffset(0, EffectsConfig.FLOATING_REWARD_RISE_PIXELS),
			TextTransparency = 1,
		}
	)
	tween:Play()
	tween.Completed:Connect(function()
		label:Destroy()
	end)
end

RemoteEvents.Get("RewardGranted").OnClientEvent:Connect(function(payload)
	showFloatingReward(payload.type, payload.amount)
end)

-- ===== Confetti / fireworks (match win) =====

local function findArenaCenterPosition(): Vector3?
	local arena = Workspace:FindFirstChild("Arena")
	local centerStage = arena and arena:FindFirstChild("CenterStage")
	local stageBase = centerStage and centerStage:FindFirstChild("StageBase")
	if stageBase and stageBase:IsA("BasePart") then
		return stageBase.Position + Vector3.new(0, 15, 0)
	end
	return nil
end

local function createBurstEmitter(position: Vector3, color: Color3): ParticleEmitter
	local part = Instance.new("Part")
	part.Name = "EffectAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Position = position
	part.Parent = Workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Lifetime = NumberRange.new(1.5, 3)
	emitter.Speed = NumberRange.new(10, 25)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0 -- burst-only, via :Emit below
	emitter.Acceleration = Vector3.new(0, -25, 0)
	emitter.Parent = part

	Debris:AddItem(part, 5)
	return emitter
end

local function burstConfetti(position: Vector3)
	local perColor = math.floor(EffectsConfig.CONFETTI_PARTICLE_COUNT / #EffectsConfig.CONFETTI_COLORS)
	for _, color in ipairs(EffectsConfig.CONFETTI_COLORS) do
		local emitter = createBurstEmitter(position, color)
		emitter:Emit(perColor)
	end
end

local function burstFireworks(position: Vector3)
	for i = 1, EffectsConfig.FIREWORK_BURST_COUNT do
		task.delay((i - 1) * 0.4, function()
			local offset = Vector3.new(math.random(-15, 15), math.random(0, 10), math.random(-15, 15))
			local color = EffectsConfig.FIREWORK_COLORS[((i - 1) % #EffectsConfig.FIREWORK_COLORS) + 1]
			local emitter = createBurstEmitter(position + offset, color)
			emitter.Speed = NumberRange.new(20, 35)
			emitter:Emit(40)
		end)
	end
end

RemoteEvents.Get("MatchWinner").OnClientEvent:Connect(function(winnerName: string?)
	flashScreen(EffectsConfig.FLASH_COLORS.Winner)

	local position = findArenaCenterPosition()
	if position then
		burstConfetti(position)
		burstFireworks(position)
	end
end)

-- ===== Correct / wrong flashes =====

RemoteEvents.Get("TurnResolved").OnClientEvent:Connect(function(payload)
	if payload.correct then
		flashScreen(UITheme.GetSuccessColor())
	else
		flashScreen(UITheme.GetErrorColor())
	end
end)
