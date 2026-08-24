--[[
	SeatingConfig.lua

	Centralized configuration for the lobby's seating.

	Rebuild pass (seating/trees/branding cleanup): every previous seat
	type (SeatTypeB "Lounge Chair", SeatTypeC "Booth Seat", SeatTypeD
	"Portal Stool") has been removed entirely from the source tree, per
	explicit direction to delete all existing seating and settle on ONE
	consistent upgraded bench design going forward. Only SeatTypeA
	remains, rebuilt bigger/taller/more detailed (see its comment below)
	and used for every seating zone - Seating.lua no longer has separate
	builder functions for the removed types.

	ZONES: where seating actually goes, and how many seats per zone.
	Positions are hand-placed (not ring-generated) since "arrange seating
	in locations that make logical sense" calls for deliberate placement
	near real points of interest, not a procedural ring - kept clear of
	buildings, leaderboards, the stage, spawns, and main paths, same
	verified clearances as before. Every placement now only carries a
	position - Seating.lua computes each bench's facing yaw directly from
	that position toward the map's true center (0, 0), so "every bench
	faces the center of the map" holds by construction rather than by
	separately-authored per-placement angles that could drift out of sync.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)
local LobbyConfig = require(script.Parent.LobbyConfig)
local MapConfig = require(script.Parent.MapConfig)
local LobbyTheme = require(script.Parent.LobbyTheme)

local SeatingConfig = {}

local SCALE = MapConfig.SCALE_FACTOR

--[[
	Looks up a building's def from LobbyConfig.BUILDINGS by stable NAME
	rather than a numeric array index - see the original comment history;
	names can't drift out of sync the way positional indices could if the
	BUILDINGS array's length/order ever changes again.
]]
local function findBuildingByName(name: string)
	for _, def in ipairs(LobbyConfig.BUILDINGS) do
		if def.name == name then
			return def
		end
	end
	error(("SeatingConfig: no LobbyConfig.BUILDINGS entry named %q"):format(name))
end

local function scaled(x: number, z: number): Vector3
	return Vector3.new(x * SCALE, 0, z * SCALE)
end

SeatingConfig.ROOT_ATTRIBUTE = "LobbySeating" -- set on the top-level seating Folder
SeatingConfig.DECORATIVE_ATTRIBUTE = "Decorative" -- set on every seat model (true) - it's dressing, not an interactive gameplay object

export type SeatTypeDef = {
	id: string,
	seatSize: Vector3,
	backrestHeight: number,
	seatMaterial: Enum.Material,
	seatColor: Color3,
	accentColor: Color3,
	frameMaterial: Enum.Material,
	frameColor: Color3,
}

local defaultTheme = LobbyTheme.Get()

-- Single upgraded bench design ("Classic Bench", rebuilt): the previous
-- SeatTypeA silhouette (two leg supports, a modest backrest, no
-- armrests, a thin neon underglow strip) is preserved as the starting
-- reference, per explicit direction, but scaled up substantially -
-- roughly 1.4x on the seat's length/depth (preserving the same
-- approximate aspect ratio, so it reads as "longer and taller", not
-- stretched in only one direction) and further on backrest height for a
-- more substantial, taller presence. See Seating.lua for the actual
-- extra detail geometry (cross-brace, corner caps, double trim) that
-- makes this read as "more detailed/more futuristic", not just a bigger
-- version of the same simple shape.
SeatingConfig.SEAT_TYPE = {
	id = "SeatTypeA",
	seatSize = Vector3.new(10.5, 0.7, 3.8), -- was (7.5, 0.6, 2.7) - same ~2.78:1 length:depth ratio, scaled ~1.4x
	backrestHeight = 3.6, -- was 2.5 - a taller, more substantial backrest
	seatMaterial = defaultTheme.seatMaterial,
	seatColor = defaultTheme.seatColor,
	accentColor = defaultTheme.seatAccentColor,
	frameMaterial = defaultTheme.seatFrameMaterial,
	frameColor = defaultTheme.seatFrameColor,
}

--[[
	Latches `theme` onto SeatingConfig.SEAT_TYPE in place (mutating the
	same table Seating.lua already holds a reference to) for every
	subsequent Seating.BuildAll call.
]]
function SeatingConfig.SetTheme(theme: LobbyTheme.Theme)
	local seatType = SeatingConfig.SEAT_TYPE
	seatType.seatMaterial = theme.seatMaterial
	seatType.seatColor = theme.seatColor
	seatType.accentColor = theme.seatAccentColor
	seatType.frameMaterial = theme.seatFrameMaterial
	seatType.frameColor = theme.seatFrameColor
end

export type SeatPlacement = {
	position: Vector3,
}

export type SeatingZone = {
	id: string,
	placements: { SeatPlacement },
}

-- ASSUMPTION (documented, not stopped for): exact seat counts/positions
-- per zone aren't specified in the brief beyond "intentional locations...
-- previously requested reduced seating density" - the values below reuse
-- the same verified-clear positions as before (hand-checked against
-- spawns/buildings/portal/leaderboard footprints in Decorations.lua's
-- placement pass), just now all built as the single upgraded bench type.
--
-- Manual edit reconciliation: PortalPlazaZone (4 stools around the queue
-- portal) was manually deleted directly in Studio. Removed from source
-- entirely here to match - simply leaving it out (rather than hiding it
-- some other way) so a future LobbyBuilder.Rebuild() reproduces the
-- deletion instead of silently re-creating seats that were deliberately
-- removed.
SeatingConfig.ZONES = {
	{
		id = "WalkwayZone",
		placements = {
			{ position = scaled(24, 62) },
			{ position = scaled(-24, 62) },
			{ position = scaled(24, 40) },
			{ position = scaled(-24, 40) },
		},
	},
	{
		id = "SocialLoungeZone",
		placements = {
			{ position = scaled(50, 25) },
			{ position = scaled(60, 32) },
			{ position = scaled(60, 15) },
			{ position = scaled(50, 5) },
		},
	},
	{
		id = "BuildingFrontZone",
		placements = {
			{ position = findBuildingByName("Shop").position + Vector3.new(16, 0, 19) },
			{ position = findBuildingByName("DailyRewards").position + Vector3.new(11, 0, 17) },
			{ position = findBuildingByName("TutorialBuilding").position + Vector3.new(-11, 0, 17) },
			{ position = findBuildingByName("StatisticsBuilding").position + Vector3.new(-16, 0, 13.5) },
		},
	},
	{
		id = "LeaderboardViewingZone",
		placements = {
			{ position = LobbyConfig.LEADERBOARD_ANCHOR.position + scaled(18, -20) },
			{ position = LobbyConfig.LEADERBOARD_ANCHOR.position + scaled(-18, -20) },
		},
	},
}

return SeatingConfig
