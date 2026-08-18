--[[
	ClientSettingsState.lua

	Shared client-side settings cache + change notification (Message 12).
	A plain ModuleScript (not a .client.lua) specifically so
	SettingsUIController, AudioController, and ResponsiveUIController can
	all require() it and stay in sync - LocalScripts can't require() each
	other directly, so this is the one place that actually talks to
	SettingsSystem (server) and everything else just subscribes to it.

	Fetches the player's real saved settings once on load (via
	GetSettingsSnapshot), then keeps a local cache that updates
	optimistically the instant the player changes something in the
	Settings panel - persistence to the server happens in the background,
	but the UI/audio/scale react immediately rather than waiting on a
	round trip.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsConfig = require(ReplicatedStorage.Modules.SettingsConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)

local ClientSettingsState = {}

local current: { [string]: any } = table.clone(SettingsConfig.DEFAULTS)
local subscribers: { (string, any) -> () } = {}
local loaded = false
local loadWaiters: { () -> () } = {}

function ClientSettingsState.Get(key: string): any
	return current[key]
end

function ClientSettingsState.GetAll(): { [string]: any }
	return table.clone(current)
end

--[[
	Subscribes to every settings change. Callback receives (key, newValue).
	Fires once immediately per current value if `fireImmediately` is true,
	so a late-subscribing script (e.g. one built after settings already
	loaded) gets the current state without a race.
]]
function ClientSettingsState.Subscribe(callback: (string, any) -> (), fireImmediately: boolean?)
	table.insert(subscribers, callback)
	if fireImmediately then
		for key, value in pairs(current) do
			task.spawn(callback, key, value)
		end
	end
end

--[[
	Applies a settings change locally (updates the cache, notifies
	subscribers) and persists it to the server. Validates/clamps with the
	same SettingsConfig rules the server uses, so the local cache never
	holds an out-of-range value even before the server round-trip.
]]
function ClientSettingsState.Set(key: string, value: any)
	local ok, clamped = SettingsConfig.ValidateAndClamp(key, value)
	if not ok then
		return
	end

	current[key] = clamped
	if key == "colorblindMode" then
		UITheme.SetColorblindMode(clamped)
	end
	for _, callback in ipairs(subscribers) do
		task.spawn(callback, key, clamped)
	end

	RemoteEvents.Get("UpdateSetting"):FireServer(key, clamped)
end

--[[
	Runs `callback` once settings have finished their initial load (or
	immediately, if already loaded).
]]
function ClientSettingsState.OnLoaded(callback: () -> ())
	if loaded then
		task.spawn(callback)
	else
		table.insert(loadWaiters, callback)
	end
end

task.spawn(function()
	local ok, snapshot = pcall(function()
		return RemoteFunctions.Get("GetSettingsSnapshot"):InvokeServer()
	end)

	if ok and snapshot then
		for key, value in pairs(snapshot) do
			current[key] = value
		end
	end

	UITheme.SetColorblindMode(current.colorblindMode == true)

	loaded = true
	for _, waiter in ipairs(loadWaiters) do
		task.spawn(waiter)
	end
end)

return ClientSettingsState
