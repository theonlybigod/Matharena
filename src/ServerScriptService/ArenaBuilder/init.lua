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

--[[
	Message 22, section 2 ("make the entire map lighter... Arena lighting"):
	boosted moderately (not as bright as the lobby's own dusk pass) so the
	arena keeps its more dramatic, focused "game-show spotlight" mood while
	still being noticeably easier to see than before.

	IMPORTANT (fixed a real latent bug while touching this): this function
	used to create its OWN separately-named BloomEffect/ColorCorrectionEffect
	("MatharenaBloom"/"MatharenaColorCorrection"), completely independent
	from LobbyLighting.lua's own "LobbyBloom"/"LobbyColorCorrection" pair -
	since Lighting is one global service, calling both Build() functions
	(as Main.server.lua always does) meant TWO separate, differently-named
	BloomEffects could end up enabled simultaneously, stacking - the exact
	class of bug that caused a real full-white rendering glitch earlier in
	this project (see PartUtils.CreateDisc's fix comment for the other half
	of that incident). This now finds and reuses the SAME single instance
	LobbyLighting manages (deduplicating by CLASS, not by the name it
	expects), so there can only ever be one BloomEffect/ColorCorrectionEffect
	under Lighting no matter which builder ran most recently.
]]
local function applyAtmosphere()
	Lighting.Ambient = Color3.fromRGB(38, 40, 55)
	Lighting.OutdoorAmbient = Color3.fromRGB(38, 40, 55)
	Lighting.Brightness = 1.6
	Lighting.ClockTime = 0
	Lighting.FogColor = Color3.fromRGB(10, 10, 16)
	Lighting.FogEnd = 250

	local bloom: BloomEffect? = nil
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("BloomEffect") then
			if bloom then
				warn(("[ArenaBuilder] Removing duplicate BloomEffect %q - keeping %q."):format(child.Name, bloom.Name))
				child:Destroy()
			else
				bloom = child
			end
		end
	end
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Parent = Lighting
	end
	bloom.Name = "LobbyBloom"
	bloom.Enabled = true
	bloom.Intensity = 0.6
	bloom.Size = 24
	bloom.Threshold = 1.4

	local colorCorrection: ColorCorrectionEffect? = nil
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("ColorCorrectionEffect") then
			if colorCorrection then
				warn(
					("[ArenaBuilder] Removing duplicate ColorCorrectionEffect %q - keeping %q."):format(
						child.Name,
						colorCorrection.Name
					)
				)
				child:Destroy()
			else
				colorCorrection = child
			end
		end
	end
	if not colorCorrection then
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Parent = Lighting
	end
	colorCorrection.Name = "LobbyColorCorrection"
	colorCorrection.Enabled = true
	colorCorrection.Contrast = 0.08
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
