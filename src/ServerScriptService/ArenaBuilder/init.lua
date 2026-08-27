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
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaConfig = require(script.ArenaConfig)
local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local Platforms = require(script.Platforms)
local CenterStage = require(script.CenterStage)
local ArenaDecorations = require(script.ArenaDecorations)
local MapsConfig = require(ReplicatedStorage.Modules.MapsConfig)
local LobbyTheme = require(ServerScriptService.LobbyBuilder.LobbyTheme)
local MapConfig = require(ServerScriptService.LobbyBuilder.MapConfig)

local ArenaBuilder = {}

local function buildFloor(arena: Instance)
	PartUtils.CreateDisc({
		name = "Floor",
		diameter = ArenaConfig.ARENA_RADIUS * 2,
		thickness = ArenaConfig.FLOOR_THICKNESS,
		position = Vector3.new(0, -ArenaConfig.FLOOR_THICKNESS / 2, 0),
		material = ArenaConfig.FLOOR_MATERIAL,
		color = ArenaConfig.FLOOR_COLOR,
		parent = arena,
	})
end

--[[
	Component-wise darken of `color` toward black by `factor` (0..1, where
	1 keeps the color unchanged and 0 goes fully black). Used by
	ArenaBuilder.BuildForMap to derive the two podium tier colors from a
	theme's spawnPadColor, the same way Platforms.lua's original hardcoded
	tier colors were just darker variants of a common metal tone - keeps
	the tiered-podium look consistent across every theme without each
	theme needing to hand-author two extra colors of its own.
]]
local function darken(color: Color3, factor: number): Color3
	return Color3.new(color.R * factor, color.G * factor, color.B * factor)
end

--[[
	Translates every BasePart already built under `root` to
	ArenaConfig.ORIGIN, run once at the end of Build().

	Deliberately mirrors LobbyBuilder's applyMapTransform: every arena
	construction module keeps building at its own local origin (0, 0, 0),
	and this is what places the finished result at its real world position
	- rather than threading a world offset through every module's internal
	position math.

	Shifting .Position (instead of re-deriving each CFrame) leaves every
	part's existing rotation untouched: a pure translation.
]]
local function applyArenaTransform(root: Instance, origin: Vector3)
	if origin.Magnitude == 0 then
		return
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Position += origin
		end
	end
end

--[[
	`origin` overrides ArenaConfig.ORIGIN (world-space position of the
	finished arena) for this one build - used by BuildForMap below to place
	a difficulty Place's Arena at its one assigned map's own position,
	instead of the Hub's shared (0, 0, 0). Omitted (nil), this is
	ArenaConfig.ORIGIN exactly as before - the Hub's own call site (below,
	Main.server.lua) never passes this, so its behavior is unchanged.
]]
function ArenaBuilder.Build(force: boolean?, origin: Vector3?)
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

	-- Must run AFTER every module above: they all build at local origin,
	-- and this moves the completed arena to its world position in one pass.
	applyArenaTransform(arena, origin or ArenaConfig.ORIGIN)

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

--[[
	Builds (or skips, per Build()'s own rerun policy) the Arena embedded
	inside `mapDef` - the one map a dedicated difficulty Place is assigned
	(see Main.server.lua). Unlike the Hub's plain Build()/Rebuild() calls
	above (which keep the Arena at the fixed ArenaConfig.ORIGIN with the
	default brand-neon/black-marble look), this:

	1. Re-skins the arena to `mapDef`'s theme (LobbyTheme.Get(mapDef.themeId))
	   by overwriting ArenaConfig.NEON_COLOR/FLOOR_COLOR/FLOOR_MATERIAL and
	   the two podium tier colors BEFORE building - Platforms.lua,
	   ArenaDecorations.lua, and CenterStage.lua all read these ArenaConfig
	   fields live at build time, so nothing in those three files needs to
	   change for this to take effect.
	2. Places the finished arena at `mapDef.origin + GROUND_ELEVATION` -
	   the exact same world-space transform LobbyBuilder.Build applies to
	   that map's own lobby (see LobbyBuilder's applyMapTransform) - so the
	   arena's floor sits at the same position and height as that map,
	   genuinely embedded in it rather than a separate structure elsewhere.

	Safe to call every server start, same as Build() - a no-op once the
	Arena is already marked built (recoloring only happens as part of an
	actual build/rebuild, never retroactively on an already-built Arena).
]]
function ArenaBuilder.BuildForMap(mapDef: MapsConfig.MapDef)
	local theme = LobbyTheme.Get(mapDef.themeId)

	ArenaConfig.NEON_COLOR = theme.portalAccentColor
	ArenaConfig.FLOOR_COLOR = theme.floorColor
	ArenaConfig.FLOOR_MATERIAL = theme.floorMaterial
	ArenaConfig.PODIUM_TIER1_COLOR = darken(theme.spawnPadColor, 0.55)
	ArenaConfig.PODIUM_TIER2_COLOR = darken(theme.spawnPadColor, 0.25)

	local origin = mapDef.origin + Vector3.new(0, MapConfig.GROUND_ELEVATION, 0)
	return ArenaBuilder.Build(nil, origin)
end

return ArenaBuilder
