--[[
	BuildingSignController.client.lua

	Wires every building's clickable overhead sign (BuildingSigns.lua,
	tagged "BuildingSignButton" with a "BuildingName" attribute) to fire
	"RequestTeleportToBuilding" on click - see BuildingTeleportSystem.lua
	(server) for where that teleport actually lands (directly in front of
	the building's real doorway).

	Handles both signs that already exist by the time this script runs
	(the normal case - LobbyBuilder.Build() runs at server start, well
	before any player's client scripts do) and any that might appear
	later (CollectionService:GetInstanceAddedSignal), so this never
	depends on a specific load-order race.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)

local requestTeleportToBuildingEvent = RemoteEvents.Get("RequestTeleportToBuilding")

local wired: { [Instance]: boolean } = {}

local function wireButton(button: Instance)
	if wired[button] or not button:IsA("GuiButton") then
		return
	end
	wired[button] = true

	button.MouseButton1Click:Connect(function()
		local buildingName = button:GetAttribute("BuildingName")
		if typeof(buildingName) == "string" then
			requestTeleportToBuildingEvent:FireServer(buildingName)
		end
	end)
end

for _, button in ipairs(CollectionService:GetTagged("BuildingSignButton")) do
	wireButton(button)
end

CollectionService:GetInstanceAddedSignal("BuildingSignButton"):Connect(wireButton)
