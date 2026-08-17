--[[
	LobbyLighting.lua

	Applies the lobby's atmosphere settings to the (single, global) Lighting
	service. Split out from LobbyBuilder/init.lua (previously a local
	`applyLighting` function) so it can be called unconditionally on every
	server start - independent of whether Workspace.Lobby's geometry was
	just generated or already existed as a source-controlled bake - and so
	its exact values are documented in one place instead of being buried
	inside the build-skip control flow.

	NOTE: Lighting is a single global service shared by the whole place,
	not something scoped to Workspace.Lobby. These settings also apply to
	the Arena until a later prompt gives the Arena its own atmosphere.

	These same values are mirrored as $properties on the Lighting node in
	default.project.json, so the lobby's atmosphere is also visible in
	Studio Edit mode immediately after a Rojo sync, without needing Play
	mode to run this module. If you change the values here, update
	default.project.json's Lighting node to match.
]]

local Lighting = game:GetService("Lighting")

local LobbyLighting = {}

function LobbyLighting.Apply()
	Lighting.Ambient = Color3.fromRGB(40, 45, 60)
	Lighting.OutdoorAmbient = Color3.fromRGB(40, 45, 60)
	Lighting.Brightness = 2
	Lighting.ClockTime = 21
	Lighting.FogColor = Color3.fromRGB(20, 20, 30)
	Lighting.FogEnd = 500
end

return LobbyLighting
