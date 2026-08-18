--[[
	LeaderboardPodiumGlowController.client.lua

	Drives a single, subtle pulsing glow for every leaderboard's 1st-place
	rank badge at once. LeaderboardBoards.lua (server) tags each board's
	Row1 rank badge with CollectionService tag "LeaderboardGoldGlow" at
	build time - this script just finds all of them and animates them,
	so there's one shared client-side effect instead of five separate
	animation loops (matching the "keep effects performant with multiple
	boards visible" requirement).

	Purely visual (a color/transparency pulse on an existing GuiObject),
	so it's entirely client-side - no server involvement, no remotes.
]]

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local GOLD_GLOW_TAG = "LeaderboardGoldGlow"
local PULSE_TWEEN_INFO = TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local animated: { [Instance]: boolean } = {}

local function animate(badge: Instance)
	if animated[badge] or not badge:IsA("GuiObject") then
		return
	end
	animated[badge] = true

	-- A soft UIStroke that pulses in/out - a subtle glow ring around the
	-- gold badge, not a change to the badge's own fill (which would make
	-- the rank number harder to read).
	local stroke = Instance.new("UIStroke")
	stroke.Name = "GoldGlowStroke"
	stroke.Color = Color3.fromRGB(255, 245, 200)
	stroke.Thickness = 2
	stroke.Transparency = 0.7
	stroke.Parent = badge

	local tween = TweenService:Create(stroke, PULSE_TWEEN_INFO, { Transparency = 0.1 })
	tween:Play()
end

for _, badge in ipairs(CollectionService:GetTagged(GOLD_GLOW_TAG)) do
	animate(badge)
end

CollectionService:GetInstanceAddedSignal(GOLD_GLOW_TAG):Connect(animate)
