--[[
	ResponsiveUIController.client.lua

	Mobile/responsive pass (Message 12). The rest of the UI (Messages
	5-11) was built with fixed pixel sizes assuming a desktop-width
	viewport (e.g. a 580px-wide button bar, 560px-wide top bar) - on a
	phone-width screen those would clip or overflow. Rather than rewrite
	every UI controller to use scale-based sizing (a much larger change
	this "final polish" pass shouldn't take on), this adds a single
	UIScale to MainUI that shrinks the whole UI proportionally to fit
	smaller viewports, combined multiplicatively with the player's manual
	"UI Scale" preference (Settings panel, Message 12) on top.

	Roblox's TextButton/TextBox/ImageButton already handle touch input
	natively with no code changes needed - this script only handles the
	sizing/fit concern, not input handling.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ClientSettingsState = require(script.Parent.ClientSettingsState)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")
local camera = Workspace.CurrentCamera

-- The desktop-assumed reference width the rest of the UI was designed
-- against (roughly matches the widest fixed-size element, the 580px
-- lobby button bar, with some margin).
local REFERENCE_WIDTH = 900
local MIN_FIT_SCALE = 0.55
local MAX_FIT_SCALE = 1.0

local uiScale = Instance.new("UIScale")
uiScale.Name = "ResponsiveScale"
uiScale.Parent = mainUI

local userPreferenceScale = 1.0

local function computeFitScale(): number
	local viewportWidth = camera.ViewportSize.X
	if viewportWidth <= 0 then
		return 1.0
	end
	return math.clamp(viewportWidth / REFERENCE_WIDTH, MIN_FIT_SCALE, MAX_FIT_SCALE)
end

local function applyScale()
	uiScale.Scale = computeFitScale() * userPreferenceScale
end

camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)

ClientSettingsState.Subscribe(function(key: string, value: any)
	if key == "uiScale" then
		userPreferenceScale = value
		applyScale()
	end
end, true)

applyScale()
