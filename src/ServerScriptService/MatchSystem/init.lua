--[[
	MatchSystem

	Will own match lifecycle: lobbies/queueing, turn order, question
	presentation, timing, elimination, and win conditions.

	This is intentionally a scaffold for the architecture pass — no
	gameplay logic yet. Later prompts will flesh this out and may add
	sibling ModuleScripts under this folder for sub-responsibilities
	(e.g. Turns.lua, Elimination.lua) that this module composes.
]]

local MatchSystem = {}

--[[
	Initializes MatchSystem. Called once from the server entry point.
]]
function MatchSystem.Init()
	print("[MatchSystem] Initialized (scaffold only, no gameplay yet)")
end

return MatchSystem
