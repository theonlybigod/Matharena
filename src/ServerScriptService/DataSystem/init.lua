--[[
	DataSystem

	Will own player data persistence: DataStore access, profile loading/
	saving, stats, and any other data that needs to survive across sessions.

	This is intentionally a scaffold for the architecture pass — no
	persistence logic yet. Later prompts will flesh this out and may add
	sibling ModuleScripts under this folder for sub-responsibilities.
]]

local DataSystem = {}

--[[
	Initializes DataSystem. Called once from the server entry point.
]]
function DataSystem.Init()
	print("[DataSystem] Initialized (scaffold only, no persistence yet)")
end

return DataSystem
