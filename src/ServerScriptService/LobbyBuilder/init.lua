--[[
	LobbyBuilder

	Procedurally constructs the entire lobby (floor, buildings, spawns,
	queue portal, decorations, lighting) under Workspace.Lobby, from
	source-controlled data in LobbyConfig.

	Rerun policy (decided by design, see project history):
		- Build() is safe to call every server start. If Workspace.Lobby
		  is already marked built (via the "MathArenaBuilt" attribute),
		  it does nothing.
		- Rebuild() forces a full rebuild, destroying and regenerating
		  everything currently under Workspace.Lobby. It prints a warning
		  stating exactly what will be destroyed before doing so.

	To (re)build the lobby by hand from Roblox Studio (Edit mode or Play
	mode command bar):
		require(game.ServerScriptService.LobbyBuilder).Build()   -- build if not already built
		require(game.ServerScriptService.LobbyBuilder).Rebuild() -- force full rebuild
]]

local Workspace = game:GetService("Workspace")

local MapConfig = require(script.MapConfig)
local Buildings = require(script.Buildings)
local Decorations = require(script.Decorations)
local SpawnsAndPortal = require(script.SpawnsAndPortal)
local Floor = require(script.Floor)
local LobbyLighting = require(script.LobbyLighting)
local Sign = require(script.Sign)

local LobbyBuilder = {}

--[[
	Message 22, section 1: applies MapConfig.GROUND_ELEVATION as a single
	bulk vertical translation to every BasePart already built under
	`lobby`, run once at the end of Build(). Every construction module
	(Floor/Buildings/Decorations/SpawnsAndPortal/Sign/LeaderboardBoards)
	still builds everything assuming the ground sits at its own local Y=0 -
	this is what actually raises the whole finished lobby afterward, rather
	than threading a global elevation offset through every module's
	internal math. Shifting .Position (not re-deriving each CFrame) leaves
	every part's existing rotation untouched - a pure vertical translation.
]]
local function applyGroundElevation(lobby: Instance)
	if MapConfig.GROUND_ELEVATION == 0 then
		return
	end

	local offset = Vector3.new(0, MapConfig.GROUND_ELEVATION, 0)
	for _, descendant in ipairs(lobby:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Position += offset
		end
	end
end

function LobbyBuilder.Build(force: boolean?)
	local lobby = Workspace:WaitForChild("Lobby")

	local alreadyBuilt = lobby:GetAttribute("MathArenaBuilt") == true
	if alreadyBuilt and not force then
		print("[LobbyBuilder] Lobby already built; skipping. Call LobbyBuilder.Rebuild() to force a full rebuild.")
		return
	end

	if alreadyBuilt and force then
		warn(
			("[LobbyBuilder] Rebuilding lobby: destroying %d existing top-level instance(s) under Workspace.Lobby (and everything inside them)."):format(
				#lobby:GetChildren()
			)
		)
	end

	for _, child in ipairs(lobby:GetChildren()) do
		child:Destroy()
	end

	LobbyLighting.Apply()
	Floor.Build(lobby)
	Buildings.BuildAll(lobby)
	SpawnsAndPortal.BuildSpawns(lobby)
	SpawnsAndPortal.BuildQueuePortal(lobby)
	Decorations.BuildAll(lobby)
	Sign.Build(lobby)

	applyGroundElevation(lobby)

	lobby:SetAttribute("MathArenaBuilt", true)
	lobby:SetAttribute("MathArenaBuiltAt", DateTime.now().UnixTimestamp)

	print("[LobbyBuilder] Lobby build complete.")
end

--[[
	Forces a full rebuild, destroying and regenerating everything currently
	under Workspace.Lobby. Intended to be run manually, e.g. from the
	Studio command bar:
		require(game.ServerScriptService.LobbyBuilder).Rebuild()
]]
function LobbyBuilder.Rebuild()
	return LobbyBuilder.Build(true)
end

return LobbyBuilder
