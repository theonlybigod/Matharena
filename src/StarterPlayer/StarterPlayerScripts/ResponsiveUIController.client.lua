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

	Height-fit fix ("the Rewards/Shop pop-up reaches below the screen,
	overlapping the bottom button bar"): this used to compute the fit scale
	from viewport WIDTH alone. On a wide-but-short viewport (a common shape
	when testing via a narrow embedded/preview window), the width-based
	scale can stay close to 1.0 even though the tallest fixed-offset popup
	(RewardsPanel, 520px tall) genuinely doesn't fit the available height
	once the top bar and bottom button bar are accounted for - nothing
	about the OLD width-only formula would ever shrink the UI to compensate
	for that, regardless of how short the viewport got. Now takes the
	MINIMUM of the width-based and height-based ratios (a standard
	"letterbox fit"), so the whole UI actually shrinks when height is the
	binding constraint, not just when width is.
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
-- against.
--
-- The old comment here described this as "roughly matches the widest
-- fixed-size element, the 580px lobby button bar, with some margin". That
-- went stale: LobbyButtonBar is now 880px, so at REFERENCE_WIDTH 900 the
-- "margin" is 20px, not the comfortable buffer the number was chosen for.
-- Measured fixed-pixel top-level panels, widest first: LobbyButtonBar 880,
-- NextPlayerBanner 560, TutorialGuideBanner 500, NewQuestBanner 380,
-- IntroCountdown 360, QueueStatus 340, QuestBox 330x600, RewardToast 320.
local REFERENCE_WIDTH = 920
-- The desktop-assumed reference HEIGHT: the tallest fixed-offset popup
-- (RewardsPanel, 520px) plus enough headroom above/below for the top bar
-- and bottom button bar to both stay fully visible and un-overlapped at
-- the same time.
local REFERENCE_HEIGHT = 760
--[[
	Floor on the auto-fit scale.

	This was 0.55, chosen when the button bar was 580px wide (580 * 0.55 =
	319px, which fits a 390px-wide phone in portrait). At today's 880px bar
	that same floor renders 484px - so on a narrow portrait viewport the
	bar overflowed the screen and the clamp PREVENTED the fit logic from
	shrinking it any further. The floor, not the formula, was the bug.

	0.44 puts the 880px bar at 387px, so it fits a 390px-wide portrait
	viewport - the narrowest common phone. Landscape was never affected:
	there the height ratio binds first and already clamps here.
]]
local MIN_FIT_SCALE = 0.44
local MAX_FIT_SCALE = 1.0

local uiScale = Instance.new("UIScale")
uiScale.Name = "ResponsiveScale"
uiScale.Parent = mainUI

local userPreferenceScale = 1.0

local function computeFitScale(): number
	local viewportSize = camera.ViewportSize
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return 1.0
	end
	local widthScale = viewportSize.X / REFERENCE_WIDTH
	local heightScale = viewportSize.Y / REFERENCE_HEIGHT
	-- Whichever dimension is more constrained wins - a wide-but-short
	-- viewport shrinks based on height even if width alone would've stayed
	-- near 1.0, and vice versa for a narrow-but-tall one.
	return math.clamp(math.min(widthScale, heightScale), MIN_FIT_SCALE, MAX_FIT_SCALE)
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
