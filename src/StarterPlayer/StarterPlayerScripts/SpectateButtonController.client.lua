--[[
	SpectateButtonController.client.lua

	The Spectate button: a small, horizontally long, text-box-shaped button
	that appears near the bottom of the screen, just above the answer
	controls, when the local player is out of the running.

	WHEN IT APPEARS. Driven entirely by the server's per-player
	`SpectateAvailable` remote, never inferred client-side:
		- the player is eliminated by a wrong answer or a timeout
		- the player joins while a match is already in progress
	Both cases are the same state - you are not a contestant in the round
	currently being played - so both get the same button.

	THE GLOW. On first appearance the button pulses for two seconds and then
	settles into its normal look, so it catches the eye of someone who has
	just been knocked out without staying loud afterwards. The server sets
	`glow` only on that first fire; a later refresh leaves it off, so the
	highlight cannot re-trigger while the button is already sitting there.

	POSITIONING. Anchored to bottom-centre and deliberately short and wide.
	The arena's question and answer controls live on an in-world SurfaceGui
	rather than on this ScreenGui, so nothing here can overlap them - the
	offset from the bottom edge is what keeps it clear of the answer area on
	screen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ACCENT = Color3.fromRGB(70, 150, 230)
local PANEL = Color3.fromRGB(24, 27, 36)
local TEXT = Color3.fromRGB(232, 238, 248)

local GLOW_SECONDS = 2

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SpectateButtonGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 40
screenGui.Enabled = false
screenGui.Parent = playerGui

-- Short and wide, per spec - the shape of a text field rather than a
-- chunky action button, so it reads as an offer rather than a demand.
local button = Instance.new("TextButton")
button.Name = "SpectateButton"
button.Size = UDim2.new(0, 260, 0, 34)
button.AnchorPoint = Vector2.new(0.5, 1)
button.Position = UDim2.new(0.5, 0, 1, -128)
button.BackgroundColor3 = PANEL
button.AutoButtonColor = false
button.Text = "SPECTATE"
button.TextColor3 = TEXT
button.TextSize = 16
button.Font = Enum.Font.GothamMedium
button.BorderSizePixel = 0
button.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = button

local stroke = Instance.new("UIStroke")
stroke.Color = ACCENT
stroke.Thickness = 1
stroke.Transparency = 0.4
stroke.Parent = button

-- Tracks the running glow so a second appearance cannot stack two tweens
-- on the same stroke and leave it stuck mid-pulse.
local glowThread: thread? = nil

local function stopGlow()
	if glowThread then
		task.cancel(glowThread)
		glowThread = nil
	end
	stroke.Thickness = 1
	stroke.Transparency = 0.4
end

local function runGlow()
	stopGlow()
	glowThread = task.spawn(function()
		local pulseIn = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		local tween = TweenService:Create(stroke, pulseIn, { Thickness = 3, Transparency = 0 })
		tween:Play()
		task.wait(GLOW_SECONDS)
		tween:Cancel()
		-- Settle to the normal look rather than wherever the pulse stopped.
		TweenService:Create(stroke, TweenInfo.new(0.25), { Thickness = 1, Transparency = 0.4 }):Play()
		glowThread = nil
	end)
end

local function setVisible(visible: boolean, glow: boolean?)
	if not visible then
		stopGlow()
		screenGui.Enabled = false
		return
	end

	-- Already showing: refresh without re-triggering the highlight.
	if screenGui.Enabled then
		return
	end

	screenGui.Enabled = true
	if glow then
		runGlow()
	end
end

button.MouseButton1Click:Connect(function()
	-- Dismisses the offer. Spectating is the default state for a player who
	-- is out, so this is an acknowledgement rather than a mode switch -
	-- taking the button away leaves an unobstructed view of the arena.
	setVisible(false)
end)

RemoteEvents.Get("SpectateAvailable").OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	setVisible(payload.visible == true, payload.glow == true)
end)
