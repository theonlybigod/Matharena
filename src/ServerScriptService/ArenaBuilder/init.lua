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

	NOTE ON GLOBAL LIGHTING: Bloom, ColorCorrection, and Fog are configured
	here as part of the arena's atmosphere. Lighting is a single global
	service (not scoped per-area), so these settings supersede whatever
	LobbyBuilder set and will also be visible while standing in the lobby.
	This was flagged as an expected tradeoff when LobbyBuilder was built.
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
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

local function applyAtmosphere()
	Lighting.Ambient = Color3.fromRGB(15, 15, 22)
	Lighting.OutdoorAmbient = Color3.fromRGB(15, 15, 22)
	Lighting.Brightness = 1
	Lighting.ClockTime = 0
	Lighting.FogColor = Color3.fromRGB(8, 8, 14)
	Lighting.FogEnd = 250

	local bloom = Lighting:FindFirstChild("MatharenaBloom") :: BloomEffect
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Name = "MatharenaBloom"
		bloom.Parent = Lighting
	end
	bloom.Intensity = 0.6
	bloom.Size = 24
	bloom.Threshold = 1.4

	local colorCorrection = Lighting:FindFirstChild("MatharenaColorCorrection") :: ColorCorrectionEffect
	if not colorCorrection then
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Name = "MatharenaColorCorrection"
		colorCorrection.Parent = Lighting
	end
	colorCorrection.Contrast = 0.1
	colorCorrection.Saturation = 0.1
	colorCorrection.TintColor = Color3.fromRGB(230, 240, 255)
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

	applyAtmosphere()
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
