--[[
	MatharenaSignController.client.lua

	Drives the purely-visual motion for the lobby's MATHARENA landmark sign
	(see ServerScriptService/LobbyBuilder/Sign.lua): the panel's floating/
	bobbing motion, and the holographic ring's slow rotation. This is all
	this script does - the sign's actual size, text, glow, ring, and energy
	beams are all built server-side so every client sees the same static
	geometry; only these two purely-visual motions are done here, client-
	side, so they cost no server time or network replication per frame.

	Reads its amplitude/period from SignConfig, so the motion can be
	retuned without touching this script.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local SignConfig = require(ReplicatedStorage.Modules.SignConfig)

local lobby = Workspace:WaitForChild("Lobby")
local sign = lobby:WaitForChild(SignConfig.SIGN_NAME)
local panel = sign:WaitForChild("SignPanel") :: BasePart
local ring = sign:WaitForChild("HoloRing") :: BasePart

local function startBobTween(targetPanel: BasePart): Tween
	local basePosition = targetPanel.Position
	local tween = TweenService:Create(
		targetPanel,
		TweenInfo.new(
			SignConfig.BOB_PERIOD_SECONDS / 2,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1, -- repeat forever
			true -- reverse, so it eases back down instead of snapping
		),
		{ Position = basePosition + Vector3.new(0, SignConfig.BOB_HEIGHT, 0) }
	)
	tween:Play()
	return tween
end

-- Slow, continuous rotation for the holographic ring - a RenderStepped-
-- driven CFrame update rather than a Tween, since a Tween can't smoothly
-- loop a full 360-degree rotation (it would snap back to 0 each cycle).
-- Cheap: one part, one CFrame write per frame, purely cosmetic.
local function startRingRotation(targetRing: BasePart)
	local RunService = game:GetService("RunService")
	local basePosition = targetRing.Position
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(deltaTime)
		if not targetRing.Parent then
			connection:Disconnect()
			return
		end
		elapsed += deltaTime
		local angle = (elapsed / SignConfig.RING_ROTATION_PERIOD_SECONDS) * math.pi * 2
		-- Apply the world-Y spin FIRST, while the frame is still
		-- axis-aligned with world space, THEN apply the same Z=90 tilt
		-- PartUtils.CreateDisc used to stand the ring up flat - this way
		-- the spin is unambiguously "rotate in place around the world
		-- vertical axis", not a rotation about some already-tilted local
		-- axis that would make the ring wobble instead of spin flat.
		targetRing.CFrame = CFrame.new(basePosition) * CFrame.Angles(0, angle, 0) * CFrame.Angles(0, 0, math.rad(90))
	end)
end

local bobTween = startBobTween(panel)
startRingRotation(ring)

-- If the lobby is ever rebuilt (LobbyBuilder.Rebuild()), the old sign
-- instance gets destroyed and a new one built in its place. Re-anchor this
-- controller to the fresh instance so the animations keep running instead
-- of silently tweening/rotating a destroyed part.
sign.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		bobTween:Cancel()

		local newSign = lobby:WaitForChild(SignConfig.SIGN_NAME)
		local newPanel = newSign:WaitForChild("SignPanel") :: BasePart
		local newRing = newSign:WaitForChild("HoloRing") :: BasePart

		startBobTween(newPanel)
		startRingRotation(newRing)
	end
end)
