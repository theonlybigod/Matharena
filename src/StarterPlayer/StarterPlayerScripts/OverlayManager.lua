--[[
	OverlayManager.lua

	Shared registry so the lobby's various full-screen overlay panels
	(Stats, Settings, Shop, Rewards, Tutorial, the Practice mode-select/
	confirm popups, the Play tier-select popup) can never be open at the
	same time. Before this module existed, each panel-owning script
	(LobbyUIController, SettingsUIController, ShopUIController,
	RewardsUIController, TutorialUIController, PracticeUIController) set
	its own overlay's `.Visible = true` directly, with no coordination
	between them - so a player could open Settings, then Stats, then Shop,
	and end up with all three stacked on screen at once, only ever
	dismissable one at a time via each panel's own Close button.

	Every overlay-owning script now calls OverlayManager.Register(overlay)
	once at load, then OverlayManager.Show(overlay) instead of setting
	`overlay.Visible = true` directly. Show() hides every OTHER registered
	overlay first, so opening one always closes whatever else was open -
	there is exactly one overlay visible at a time, regardless of which
	button (bottom bar or an in-world terminal) opened it. Closing (a
	panel's own Close button, or clicking its own toggle button again) is
	unaffected - each script still owns hiding its own overlay directly;
	OverlayManager only ever needs to be involved on the "open" side.
]]

local OverlayManager = {}

local registered: { Frame } = {}

--[[
	Registers `overlay` so future Show() calls (for THIS or any other
	registered overlay) know about it. Safe to call once per overlay at
	script load time, before the overlay is ever shown.
]]
function OverlayManager.Register(overlay: Frame)
	if table.find(registered, overlay) then
		return
	end
	table.insert(registered, overlay)
end

--[[
	Shows `overlay` and hides every other registered overlay. This is the
	one function that actually enforces mutual exclusivity - call this
	anywhere a script used to just do `overlay.Visible = true`.
]]
function OverlayManager.Show(overlay: Frame)
	for _, other in ipairs(registered) do
		if other ~= overlay then
			other.Visible = false
		end
	end
	overlay.Visible = true
end

--[[
	Hides `overlay`. Equivalent to `overlay.Visible = false` - provided
	for symmetry with Show(), not because hiding needs any special
	cross-overlay coordination.
]]
function OverlayManager.Hide(overlay: Frame)
	overlay.Visible = false
end

--[[
	Hides every registered overlay. Not currently required by any caller,
	but provided as a clean escape hatch (e.g. a future "close everything"
	keybind) rather than something each script would have to reinvent.
]]
function OverlayManager.HideAll()
	for _, overlay in ipairs(registered) do
		overlay.Visible = false
	end
end

return OverlayManager
