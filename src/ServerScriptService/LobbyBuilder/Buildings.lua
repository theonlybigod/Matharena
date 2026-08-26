--[[
	Buildings.lua

	Constructs the four named lobby buildings from LobbyConfig.BUILDINGS.
	Each building is a genuinely walkable shell (BuildingInteriors) with a
	neon roofline trim band, a doorway, interior furnishings/terminals,
	and a sign facing the plaza (+Z direction, where spawns are).

	LEADERBOARD REDESIGN + RELOCATION (Message 18): the leaderboard is no
	longer a LobbyConfig.BUILDINGS entry at all - it has its own dedicated
	region, LobbyConfig.LEADERBOARD_ANCHOR, on the map's west side (moved
	out of the back building row to "the currently empty side of the
	map"). LeaderboardBoards.BuildAll builds five separate, independently-
	named boards (WinsLeaderboard, XPLeaderboard, QuestionsSolvedLeaderboard,
	AccuracyLeaderboard, FastestAnswerLeaderboard) fanned across an arc
	there, facing back toward the plaza. This file never touches a
	DataStore itself; LeaderboardDisplay (ServerScriptService) finds the
	five boards by their stable names and fills in live values.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local LobbyConfig = require(script.Parent.LobbyConfig)
local LobbyTheme = require(script.Parent.LobbyTheme)
local BuildingInteriors = require(script.Parent.BuildingInteriors)
local BuildingSigns = require(script.Parent.BuildingSigns)
local LeaderboardBoards = require(script.Parent.LeaderboardBoards)

local Buildings = {}

local defaultTheme = LobbyTheme.Get()
local ACCENT_MATERIAL = defaultTheme.buildingAccentMaterial
local ACCENT_COLOR = defaultTheme.buildingAccentColor
local CURRENT_THEME_ID = defaultTheme.id

--[[
	Latches `theme` for this module's own trim-band color/material AND
	cascades to every other themed building-construction module
	(BuildingInteriors, BuildingSigns) - Buildings.lua already requires
	both, so this is the single call site LobbyBuilder needs for the whole
	"building" family rather than three separate calls.
]]
function Buildings.SetTheme(theme: LobbyTheme.Theme)
	ACCENT_MATERIAL = theme.buildingAccentMaterial
	ACCENT_COLOR = theme.buildingAccentColor
	CURRENT_THEME_ID = theme.id
	BuildingInteriors.SetTheme(theme)
	BuildingSigns.SetTheme(theme)
end

--[[
	The old addSign() helper lived here: it painted the building's name
	straight onto the "Base" header part's Back face with a full-face
	TextScaled label. It is gone, and nothing replaces it at this level,
	because BuildingInteriors now builds a real mounted EntranceNamePlate
	for EVERY theme - the custom-exterior themes get theirs at the tunnel
	mouth (themedEntranceTunnel), and the box themes get theirs on the
	facade (BuildShell's `not isCustomExterior` branch).

	Two reasons it had to go rather than stay as a fallback:

	1. It was the "very thin" name. A full-face TextScaled label on a wide,
	   short header is WIDTH-bound, so a long name like "Statistics
	   Building" rendered ~3.1-stud glyphs in a 9-stud header. See
	   BuildingInteriors.FormatSignText for the full explanation and the
	   two-line fix.
	2. Keeping it would now DOUBLE-print the name on the box themes: the
	   new facade plate stands at halfZ + 1.1, just proud of the header it
	   would have been painted on, so both would be visible at once on the
	   taller buildings.
]]

local function buildOne(def, parent: Instance, mapId: string): Model
	local model = Instance.new("Model")
	model.Name = def.name
	model.Parent = parent

	local base = BuildingInteriors.BuildShell(def, model)

	-- Roofline trim band is exterior box dressing too - skipped for the
	-- three custom-exterior themes (see BuildingInteriors.HasCustomExterior)
	-- since the dome/volcano/hull body already wraps clean past the
	-- building's own roofline; this band would otherwise be the one
	-- remaining strip of the old prism shell peeking through the wrap.
	if not BuildingInteriors.HasCustomExterior(CURRENT_THEME_ID) then
		PartUtils.CreatePart({
			name = "TrimBand",
			size = Vector3.new(def.size.X + 0.4, 0.6, def.size.Y + 0.4),
			position = def.position + Vector3.new(0, def.height - 1, 0),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
	end

	-- Signage is no longer applied here (see the note where addSign used to
	-- live) - BuildingInteriors.BuildShell has already built this building's
	-- EntranceNamePlate by now, for whichever theme is latched.
	if def.name == "Shop" then
		BuildingInteriors.FurnishShop(def, model)
	elseif def.name == "DailyRewards" then
		BuildingInteriors.FurnishRewards(def, model)
	elseif def.name == "StatisticsBuilding" then
		BuildingInteriors.FurnishStatistics(def, model)
	elseif def.name == "TutorialBuilding" then
		BuildingInteriors.FurnishTutorial(def, model)
	end

	--[[
		Make the building's own facade name plate a teleport target too.

		Players reported clicking "the writing right in front of the
		building" and nothing happening - that plate was pure decoration.
		It is a real Part, so a ClickDetector on it is the most reliable
		click surface in the whole system, and it is exactly where a player
		walking up to a building naturally aims.

		Searched by name rather than returned from BuildShell because the
		three custom-exterior themes build their plate in a different place
		(themedEntranceTunnel) than the box themes do.
	]]
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == "EntranceNamePlate" then
			BuildingSigns.MakeTeleportTarget(descendant, def.name, mapId, 200)
		end
	end

	-- Message 32: floating overhead sign above every building (distinct
	-- from the door-side plaque `addSign` above builds), clickable to
	-- teleport right to the building's entrance - see BuildingSigns.lua.
	-- Tagged with which map it belongs to (mapId) so a click can resolve
	-- the CORRECT map's copy of this building - see BuildingSigns.BuildOne
	-- and BuildingTeleportSystem.lua.
	-- The sign must clear the REAL top of whatever exterior this theme
	-- builds, not just the box roofline - on Lava the volcano cap rises far
	-- above def.height, and a sign anchored to the roofline ended up inside
	-- the mountain (invisible, and unclickable).
	BuildingSigns.BuildOne(def, model, mapId, BuildingInteriors.GetExteriorTopY(def, CURRENT_THEME_ID))

	model.PrimaryPart = base
	return model
end

function Buildings.BuildAll(parent: Instance, mapId: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Buildings"
	folder.Parent = parent

	for _, def in ipairs(LobbyConfig.BUILDINGS) do
		buildOne(def, folder, mapId)
	end

	-- Message 18: leaderboard region relocated out of the building row
	-- entirely - built from its own dedicated anchor/config, not a
	-- LobbyConfig.BUILDINGS entry.
	LeaderboardBoards.BuildAll(LobbyConfig.LEADERBOARD_ANCHOR, folder)

	return folder
end

return Buildings
