--[[
	SettingsSystem

	Server-authoritative settings persistence (Message 12) - completes the
	generic, empty `profile.settings` field DataSystem added back in
	Message 11 in anticipation of exactly this. Settings (music/SFX
	volume, graphics quality, UI scale, colorblind mode) aren't security-
	sensitive the way currency is, but they still persist through the same
	trusted profile/DataStore pipeline as everything else, and the server
	still validates every incoming value against SettingsConfig rather
	than trusting the client's number/string/boolean at face value.

	Two remotes:
		"GetSettingsSnapshot" (RemoteFunction, client -> server, read-only)
			Returns the player's current settings, merged with
			SettingsConfig.DEFAULTS for any keys not yet in their profile
			(new players, or settings added after their profile was
			created).
		"UpdateSetting" (RemoteEvent, client -> server)
			payload: (key: string, value: number | string | boolean)
			Validated via SettingsConfig.ValidateAndClamp; unknown keys or
			wrong-typed values are silently ignored (not an error to the
			client - malformed input just doesn't do anything). Rate-
			limited via RemoteThrottle so a client can't spam updates.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SettingsConfig = require(ReplicatedStorage.Modules.SettingsConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)

local RemoteThrottle = require(ServerScriptService.RemoteThrottle)
local DataSystem = require(ServerScriptService.DataSystem)

local SettingsSystem = {}

local UPDATE_SETTING_COOLDOWN_SECONDS = 0.25

local function buildSnapshot(player: Player): { [string]: any }
	local profile = DataSystem.GetProfile(player)
	local snapshot = table.clone(SettingsConfig.DEFAULTS)

	if profile then
		for key, value in pairs(profile.settings) do
			snapshot[key] = value
		end
	end

	return snapshot
end

--[[
	Validates and applies a single setting update for `player`. Returns
	true if it was applied, false if the key/value was rejected. Exposed
	as a function (not just inline in the remote handler) so it can be
	unit-exercised directly, same pattern as ShopSystem/ProgressionSystem.
]]
function SettingsSystem.UpdateSetting(player: Player, key: string, value: any): boolean
	local profile = DataSystem.GetProfile(player)
	if not profile then
		return false
	end

	local ok, clamped = SettingsConfig.ValidateAndClamp(key, value)
	if not ok then
		return false
	end

	profile.settings[key] = clamped
	return true
end

function SettingsSystem.Init()
	local getSettingsSnapshotFunction = RemoteFunctions.Get("GetSettingsSnapshot")
	getSettingsSnapshotFunction.OnServerInvoke = function(player: Player)
		return buildSnapshot(player)
	end

	local updateSettingEvent = RemoteEvents.Get("UpdateSetting")
	updateSettingEvent.OnServerEvent:Connect(function(player: Player, key: unknown, value: unknown)
		if typeof(key) ~= "string" then
			return
		end
		if not RemoteThrottle.Check(player, "UpdateSetting", UPDATE_SETTING_COOLDOWN_SECONDS) then
			return
		end
		SettingsSystem.UpdateSetting(player, key, value)
	end)

	print("[SettingsSystem] Initialized")
end

return SettingsSystem
