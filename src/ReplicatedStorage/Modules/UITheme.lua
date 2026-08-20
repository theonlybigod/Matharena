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

-- Message 26 UI overhaul ("make the whole interface 100x better"):
-- richer panel/button styling layered on top of the original flat
-- StylePanel/ApplyCorner helpers below (kept intact - lots of existing
-- controllers still call them directly for minor UI bits), so every
-- controller that adopts the new helpers gets a real visual upgrade
-- (gradient depth, a glowing accent border, icon glyphs) without
-- needing every single caller rewritten at once.
UITheme.PANEL_CORNER_RADIUS = UDim.new(0, 18) -- softer/larger than the original 12px, reads as more premium

-- A restrained top-to-bottom gradient (not a flat fill) - the single
-- cheapest lever for "looks 100x better" on every panel: real depth
-- instead of a flat color block, at zero extra draw cost (one
-- UIGradient per panel).
UITheme.PANEL_GRADIENT_COLORS = {
	Color3.fromRGB(30, 30, 40),
	Color3.fromRGB(16, 16, 22),
}

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
	Message 26: the upgraded panel style - a gradient fill (real depth,
	not flat color), a soft glowing accent border, and the larger rounded
	corners above. Used for anything meant to feel like a genuine "premium
	panel" (the bottom button bar's buttons, and every panel a button
	opens) rather than StylePanel's original plain flat rectangle, which
	remains available for smaller/minor UI bits that don't need the full
	treatment.
]]
function UITheme.StylePremiumPanel(panel: GuiObject, transparency: number?)
	panel.BackgroundColor3 = UITheme.PANEL_GRADIENT_COLORS[1]
	panel.BackgroundTransparency = transparency or 0.05
	panel.BorderSizePixel = 0
	UITheme.ApplyCorner(panel, UITheme.PANEL_CORNER_RADIUS)

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(UITheme.PANEL_GRADIENT_COLORS[1], UITheme.PANEL_GRADIENT_COLORS[2])
	gradient.Rotation = 90
	gradient.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.COLORS.Accent
	stroke.Thickness = 1.5
	stroke.Transparency = 0.55
	stroke.Parent = panel

	return panel
end

--[[
	Attaches a simple hover/press scale animation to a GuiButton. Purely
	presentational - has no effect on the button's actual click behavior.

	Bug fix (hover-makes-buttons-disappear): this used to capture
	`button.Size` ONCE, at the moment this function was called, into
	`originalSize`, then always tweened back to that captured value on
	MouseLeave. Every caller that builds a button via a shared constructor
	(see UITheme.CreateNavButton below) calls this function BEFORE setting
	the button's real final Size - the constructor attaches the hover effect
	first, then the caller (e.g. LobbyUIController.client.lua's
	createButton) resizes the button afterward. That meant `originalSize`
	was permanently locked to the button's default/interim size (not its
	real, final, laid-out size), so every hover snapped the button to the
	wrong size and every un-hover snapped it back to that same wrong size -
	which, sitting inside a UIListLayout alongside every other button, threw
	off the whole row's layout and could push a button visually out of its
	parent's bounds, reading as "the button disappeared".

	Fix: capture the base size LAZILY, on the first MouseEnter, instead of
	at attach time. Since any caller's resize always happens synchronously
	right after creation (before the game loop can ever deliver a mouse
	event), the first real MouseEnter is guaranteed to see the button's true
	final size, so `baseSize` is always correct regardless of call order.
]]
function UITheme.ApplyButtonHoverEffect(button: GuiButton)
	local baseSize: UDim2? = nil

	button.MouseEnter:Connect(function()
		baseSize = baseSize or button.Size
		TweenService:Create(button, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			Size = baseSize + UDim2.fromOffset(6, 6),
		}):Play()
	end)

	button.MouseLeave:Connect(function()
		baseSize = baseSize or button.Size
		TweenService:Create(button, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			Size = baseSize,
		}):Play()
	end)

	button.MouseButton1Down:Connect(function()
		baseSize = baseSize or button.Size
		TweenService:Create(button, TweenInfo.new(0.08, Enum.EasingStyle.Quad), {
			Size = baseSize - UDim2.fromOffset(4, 4),
		}):Play()
	end)
end

--[[
	Message 26: builds a "premium" nav button - an icon glyph stacked above
	a text label, a glowing accent underline that brightens on hover, and
	the existing hover/press scale animation - instead of a single flat
	TextButton with plain centered text. Used by the bottom button bar so
	each button reads as a deliberate icon-driven nav item.
]]
function UITheme.CreateNavButton(name: string, iconText: string, labelText: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	UITheme.StylePremiumPanel(button, 0.05)
	UITheme.ApplyButtonHoverEffect(button)

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(1, 0, 0.55, 0)
	icon.Position = UDim2.fromScale(0, 0.08)
	icon.BackgroundTransparency = 1
	icon.Font = Enum.Font.GothamBold
	icon.TextScaled = true
	icon.Text = iconText
	icon.TextColor3 = UITheme.COLORS.Text
	icon.Parent = button

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 0.3, 0)
	label.Position = UDim2.fromScale(0, 0.66)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = labelText
	label.TextColor3 = UITheme.COLORS.SubText
	label.Parent = button

	local underline = Instance.new("Frame")
	underline.Name = "Underline"
	underline.Size = UDim2.new(0.5, 0, 0, 3)
	underline.Position = UDim2.new(0.25, 0, 0.97, 0)
	underline.BackgroundColor3 = UITheme.COLORS.Accent
	underline.BackgroundTransparency = 0.5
	underline.BorderSizePixel = 0
	underline.Parent = button
	UITheme.ApplyCorner(underline, UDim.new(1, 0))

	button.MouseEnter:Connect(function()
		TweenService:Create(underline, TweenInfo.new(0.15), { BackgroundTransparency = 0 }):Play()
		TweenService:Create(label, TweenInfo.new(0.15), { TextColor3 = UITheme.COLORS.Text }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(underline, TweenInfo.new(0.15), { BackgroundTransparency = 0.5 }):Play()
		TweenService:Create(label, TweenInfo.new(0.15), { TextColor3 = UITheme.COLORS.SubText }):Play()
	end)

	return button
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
