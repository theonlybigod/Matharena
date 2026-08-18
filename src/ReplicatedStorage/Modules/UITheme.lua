--[[
	UITheme.lua

	Shared visual constants and small reusable helpers (rounded corners,
	panel styling, button hover/press animation, panel open tween) so every
	client UI controller gets a consistent "rounded, modern, animated"
	look without duplicating tween/styling boilerplate in each script.

	Client-only presentation logic, but lives here (ReplicatedStorage)
	rather than under StarterPlayer because it's genuinely reusable across
	every UI controller script, matching where other shared, non-secret
	constants (Config, MatchConfig, GameplayConfig) already live.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.Config)

local UITheme = {}

UITheme.COLORS = {
	Background = Color3.fromRGB(12, 12, 18),
	Panel = Color3.fromRGB(22, 22, 30),
	Accent = Config.BRAND_NEON_COLOR,
	Success = Color3.fromRGB(60, 200, 90),
	Error = Color3.fromRGB(220, 60, 60),
	Gold = Color3.fromRGB(255, 215, 0),
	Gem = Color3.fromRGB(170, 130, 255),
	Text = Color3.fromRGB(255, 255, 255),
	SubText = Color3.fromRGB(190, 195, 210),
}

UITheme.CORNER_RADIUS = UDim.new(0, 12)

-- Colorblind mode (Message 12): when enabled, Success/Error resolve to a
-- blue/orange pair instead of green/red. Blue-orange remains
-- distinguishable across protanopia, deuteranopia, and tritanopia, unlike
-- green/red which is exactly the pair most colorblind types confuse.
-- Static UITheme.COLORS.Success/Error are left as-is for anything that
-- genuinely only ever wants "the success color" regardless of mode (rare);
-- call sites that show correct/wrong feedback to the player should use
-- GetSuccessColor()/GetErrorColor() instead so they respect this setting.
local colorblindModeEnabled = false
local COLORBLIND_SUCCESS = Color3.fromRGB(70, 150, 255)
local COLORBLIND_ERROR = Color3.fromRGB(255, 150, 40)

function UITheme.SetColorblindMode(enabled: boolean)
	colorblindModeEnabled = enabled
end

function UITheme.GetSuccessColor(): Color3
	return colorblindModeEnabled and COLORBLIND_SUCCESS or UITheme.COLORS.Success
end

function UITheme.GetErrorColor(): Color3
	return colorblindModeEnabled and COLORBLIND_ERROR or UITheme.COLORS.Error
end

--[[
	Adds a UICorner to any GuiObject. Returns the UICorner in case the
	caller wants to tweak it further.
]]
function UITheme.ApplyCorner(instance: Instance, radius: UDim?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UITheme.CORNER_RADIUS
	corner.Parent = instance
	return corner
end

--[[
	Applies the standard panel look (background color, transparency,
	no border, rounded corners) to a Frame/TextButton/etc.
]]
function UITheme.StylePanel(panel: GuiObject, transparency: number?)
	panel.BackgroundColor3 = UITheme.COLORS.Panel
	panel.BackgroundTransparency = transparency or 0.1
	panel.BorderSizePixel = 0
	UITheme.ApplyCorner(panel)
end

--[[
	Attaches a simple hover/press scale animation to a GuiButton. Purely
	presentational - has no effect on the button's actual click behavior.
]]
function UITheme.ApplyButtonHoverEffect(button: GuiButton)
	local originalSize = button.Size

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			Size = originalSize + UDim2.fromOffset(6, 6),
		}):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			Size = originalSize,
		}):Play()
	end)

	button.MouseButton1Down:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.08, Enum.EasingStyle.Quad), {
			Size = originalSize - UDim2.fromOffset(4, 4),
		}):Play()
	end)
end

--[[
	Scales a panel in from zero to its current size - call right after
	making it visible/parenting it.
]]
function UITheme.PlayOpenTween(panel: GuiObject)
	local targetSize = panel.Size
	panel.Size = UDim2.new(targetSize.X.Scale, 0, targetSize.Y.Scale, 0)
	TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = targetSize,
	}):Play()
end

return UITheme
