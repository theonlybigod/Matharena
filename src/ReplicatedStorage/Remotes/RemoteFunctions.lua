--[[
	RemoteFunctions.lua

	Shared registry/factory for RemoteFunctions used by MathArena.

	Usage:
		local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
		local SomeFunction = RemoteFunctions.Get("SomeFunctionName")

	On the server, Get() creates the RemoteFunction instance if it doesn't
	exist yet (the server should then set .OnServerInvoke). On the client,
	Get() waits for the server to have created it.

	This module does not define any gameplay-specific remote names itself —
	those will be added by the systems that need them in later prompts.
]]

local RunService = game:GetService("RunService")

local RemoteFunctions = {}

local cache: { [string]: RemoteFunction } = {}

local function getInstancesFolder(): Folder
	local existing = script:FindFirstChild("Instances")
	if existing then
		return existing
	end

	if RunService:IsServer() then
		local folder = Instance.new("Folder")
		folder.Name = "Instances"
		folder.Parent = script
		return folder
	end

	return script:WaitForChild("Instances")
end

--[[
	Returns the RemoteFunction with the given name, creating it on the server
	if it does not already exist. On the client, this will yield until the
	server has created it.
]]
function RemoteFunctions.Get(name: string): RemoteFunction
	local cached = cache[name]
	if cached then
		return cached
	end

	local folder = getInstancesFolder()
	local remote = folder:FindFirstChild(name)

	if not remote then
		if RunService:IsServer() then
			remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		else
			remote = folder:WaitForChild(name)
		end
	end

	cache[name] = remote :: RemoteFunction
	return remote :: RemoteFunction
end

return RemoteFunctions
