--[[
	MatharenaSignController.client.lua

	Drives the purely-visual bobbing motion for the lobby's MATHARENA
	landmark sign (see ServerScriptService/LobbyBuilder/Sign.lua). This is
	all this script does - the sign's actual size, text, and glow are all
	built server-side so every client sees the same static geometry; only
	this one purely-visual motion is done here, client-side, so it costs
	no server time or network replication per frame.

	Branding cleanup pass: the holographic ring and its client-side
	rotation code have been removed entirely, matching Sign.lua no longer
	building a "HoloRing" part at all - this script used to
	WaitForChild("HoloRing") with no timeout, which would now hang forever
	waiting for a part that will never exist if left in place.

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

local bobTween = startBobTween(panel)

-- If the lobby is ever rebuilt (LobbyBuilder.Rebuild()), the old sign
-- instance gets destroyed and a new one built in its place. Re-anchor this
-- controller to the fresh instance so the animation keeps running instead
-- of silently tweening a destroyed part.
sign.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		bobTween:Cancel()

		local newSign = lobby:WaitForChild(SignConfig.SIGN_NAME)
		local newPanel = newSign:WaitForChild("SignPanel") :: BasePart

		startBobTween(newPanel)
	end
end)
