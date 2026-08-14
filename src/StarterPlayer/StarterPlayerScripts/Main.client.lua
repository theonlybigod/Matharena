--[[
	Main.client.lua

	Client entry point. Bootstraps client-side setup. Kept minimal for the
	architecture pass — later prompts will add UI controllers and gameplay
	presentation logic here (or in client-only modules this script requires).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.Config)

local player = Players.LocalPlayer

print(("[Client] %s ready for %s v%s"):format(player.Name, Config.GAME_NAME, Config.VERSION))
