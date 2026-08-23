--[[
	ArenaBuilder

	Procedurally constructs the competition arena (floor, platforms, center
	stage, spectator seating, rim lighting, moving beams, and post-effects)
	under Workspace.Arena, from source-controlled data in ArenaConfig.

	Rerun policy mirrors LobbyBuilder (same project-wide decision):
		- Build() is safe to call every server start. If Workspace.Arena
		  is already marked built (via the "MathArenaBuilt" attribute),
		  it does nothing.
		- Rebuild() forces a full rebuild, destroying and regenerating
		  everything currently under Workspace.Arena, with a warning
		  stating exactly what will be destroyed before doing so.

	To (re)build the arena by hand from Roblox Studio (Edit mode or Play
	mode command bar):
		require(game.ServerScriptService.ArenaBuilder).Build()   -- build if not already built
		require(game.ServerScriptService.ArenaBuilder).Rebuild() -- force full rebuild

	NOTE ON GLOBAL LIGHTING (permanent fix): this module used to own a
	SECOND, independent atmosphere implementation here (`applyAtmosphere` -
	hardcoded Ambient/Brightness/ClockTime/Fog values, plus its own
	from-scratch BloomEffect/ColorCorrectionEffect dedup pass) that
	duplicated LobbyLighting.Apply()'s job with DIFFERENT values for the
	exact same global Lighting properties. Lighting is a single global
	service (not scoped per-area), so having two independent owners for the
	same properties meant whichever one happened to run LAST silently won -
	purely a function of call order in Main.server.lua, not a real
	invariant. That's exactly the class of bug that caused this project's
	recurring "whole map goes white/blown-out" glitch: nothing was actually
	broken about either implementation individually, they just periodically
	fought over the same global state whenever the ordering assumption
	didn't hold (e.g. a manual/forced Rebuild() of one builder without an
	immediately-following LobbyLighting.Apply() call).
	`applyAtmosphere` and its call site have been deleted entirely (not
	just made idempotent) - LobbyLighting.Apply() (called unconditionally on
	every server start from Main.server.lua, regardless of whether either
	builder actually rebuilds anything) is now the ONLY code in the project
	that ever touches Lighting.Ambient/OutdoorAmbient/Brightness/ClockTime/
	Fog*/Bloom*/ColorCorrection*, sourced entirely from LightingConfig.lua.
	There is no second implementation left to fall out of sync, regardless
	of build order, forced rebuilds, or which builder ran most recently.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(script.ArenaConfig)
local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local Platforms = require(script.Platforms)
local CenterStage = require(script.CenterStage)
local ArenaDecorations = require(script.ArenaDecorations)

local ArenaBuilder = {}

local function buildFloor(arena: Instance)
	PartUtils.CreateDisc({
		name = "Floor",
		diameter = ArenaConfig.ARENA_RADIUS * 2,
		thickness = ArenaConfig.FLOOR_THICKNESS,
		position = Vector3.new(0, -ArenaConfig.FLOOR_THICKNESS / 2, 0),
		material = Enum.Material.Marble,
		color = ArenaConfig.FLOOR_COLOR,
		parent = arena,
	})
end

function ArenaBuilder.Build(force: boolean?)
	local arena = Workspace:WaitForChild("Arena")

	local alreadyBuilt = arena:GetAttribute("MathArenaBuilt") == true
	if alreadyBuilt and not force then
		print("[ArenaBuilder] Arena already built; skipping. Call ArenaBuilder.Rebuild() to force a full rebuild.")
		return
	end

	if alreadyBuilt and force then
		warn(
			("[ArenaBuilder] Rebuilding arena: destroying %d existing top-level instance(s) under Workspace.Arena (and everything inside them)."):format(
				#arena:GetChildren()
			)
		)
	end

	for _, child in ipairs(arena:GetChildren()) do
		child:Destroy()
	end

	buildFloor(arena)
	Platforms.BuildAll(arena)
	CenterStage.BuildAll(arena)
	ArenaDecorations.BuildAll(arena)

	arena:SetAttribute("MathArenaBuilt", true)
	arena:SetAttribute("MathArenaBuiltAt", DateTime.now().UnixTimestamp)

	print("[ArenaBuilder] Arena build complete.")
end

--[[
	Forces a full rebuild, destroying and regenerating everything currently
	under Workspace.Arena. Intended to be run manually, e.g. from the
	Studio command bar:
		require(game.ServerScriptService.ArenaBuilder).Rebuild()
]]
function ArenaBuilder.Rebuild()
	return ArenaBuilder.Build(true)
end

return ArenaBuilder
