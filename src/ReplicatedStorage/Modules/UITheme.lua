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
	Text = Color3.fromRGB(255, 255, 255),
	SubText = Color3.fromRGB(190, 195, 210),
}

UITheme.CORNER_RADIUS = UDim.new(0, 12)

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
