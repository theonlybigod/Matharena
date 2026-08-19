--[[
	SeatingConfig.lua

	Centralized configuration for the lobby's seating (Message 2
	addition/refinement, replacing the single repeated bench design with
	four distinct seat types arranged into five logically-placed seating
	zones).

	SEAT_TYPES: visual/material parameters for each distinct seat design.
	Kept intentionally different from each other in shape, backrest,
	armrests, support style, and material - see Seating.lua for the
	actual construction functions, one per type.

	ZONES: where each type of seating actually goes, and how many seats
	per zone. Positions/yaws are hand-placed (not ring-generated) since
	"arrange seating in locations that make logical sense" calls for
	deliberate placement near real points of interest, not a procedural
	ring. Seating.lua turns each zone entry into actual seat instances.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)
local LobbyConfig = require(script.Parent.LobbyConfig)
local MapConfig = require(script.Parent.MapConfig)

local SeatingConfig = {}

local SCALE = MapConfig.SCALE_FACTOR

-- Zones anchored to the map's CENTER (portal plaza, walkway, social
-- lounge, leaderboard viewing) scale uniformly with the map - this both
-- moves them outward for the larger footprint AND increases the actual
-- spacing between them proportionally ("spread seating into comfortable
-- social areas"). Zones anchored to a BUILDING (BuildingFrontZone) instead
-- add a fixed, unscaled offset to that building's own (already-scaled)
-- LobbyConfig position, since the offset is relative to the building's
-- footprint size, which isn't being resized - see LobbyConfig.lua.
local function scaled(x: number, z: number): Vector3
	return Vector3.new(x * SCALE, 0, z * SCALE)
end

SeatingConfig.ROOT_ATTRIBUTE = "LobbySeating" -- set on the top-level seating Folder
SeatingConfig.DECORATIVE_ATTRIBUTE = "Decorative" -- set on every seat model (true) - it's dressing, not an interactive object

export type SeatTypeDef = {
	id: string,
	seatSize: Vector3,
	backrestHeight: number?, -- nil = no backrest (SeatTypeD)
	hasArmrests: boolean,
	supportStyle: string, -- "Legs" | "PedestalBlock" | "PedestalPost" - documentation only, Seating.lua has one builder function per type id
	seatMaterial: Enum.Material,
	seatColor: Color3,
	accentColor: Color3,
}

SeatingConfig.SEAT_TYPES = {
	-- "Classic Bench", refined: two thin leg supports, a modest backrest,
	-- no armrests, a thin neon underglow strip along the base. The
	-- general-purpose walkway seat.
	SeatTypeA = {
		id = "SeatTypeA",
		seatSize = Vector3.new(4.5, 0.4, 1.6),
		backrestHeight = 1.5,
		hasArmrests = false,
		supportStyle = "Legs",
		seatMaterial = Enum.Material.SmoothPlastic,
		seatColor = Color3.fromRGB(235, 235, 240),
		accentColor = LightingConfig.DECORATIVE,
	},
	-- "Lounge Chair": single-seat width, armrests, a single centered
	-- pedestal block support, a warmer material - the social-lounge seat.
	SeatTypeB = {
		id = "SeatTypeB",
		seatSize = Vector3.new(2.6, 0.4, 2.2),
		backrestHeight = 1.9,
		hasArmrests = true,
		supportStyle = "PedestalBlock",
		seatMaterial = Enum.Material.SmoothPlastic,
		seatColor = Color3.fromRGB(90, 70, 60),
		accentColor = Color3.fromRGB(255, 170, 90),
	},
	-- "Booth Seat": tall backrest with side wings for an enclosed booth
	-- feel, a solid block base (not legs), dark metal - the
	-- building-entrance / points-of-interest seat.
	SeatTypeC = {
		id = "SeatTypeC",
		seatSize = Vector3.new(3.4, 0.4, 1.8),
		backrestHeight = 3,
		hasArmrests = false,
		supportStyle = "Block",
		seatMaterial = Enum.Material.Metal,
		seatColor = Color3.fromRGB(45, 48, 56),
		accentColor = LightingConfig.DECORATIVE,
	},
	-- "Portal Stool": low, round, backless - deliberately unobtrusive so
	-- it never blocks sightlines to the queue portal or the floating
	-- sign directly overhead.
	SeatTypeD = {
		id = "SeatTypeD",
		seatSize = Vector3.new(1.8, 0.35, 1.8), -- diameter x thickness x diameter (round seat)
		backrestHeight = nil,
		hasArmrests = false,
		supportStyle = "PedestalPost",
		seatMaterial = Enum.Material.SmoothPlastic,
		seatColor = Color3.fromRGB(230, 230, 235),
		accentColor = LightingConfig.DECORATIVE,
	},
}

export type SeatPlacement = {
	position: Vector3,
	yawDegrees: number,
}

export type SeatingZone = {
	id: string,
	seatType: string,
	placements: { SeatPlacement },
}

-- ASSUMPTION (documented, not stopped for): exact seat counts/positions
-- per zone aren't specified in the brief beyond "several zones, logically
-- placed, with walking space between groups" - the values below are a
-- reasonable concrete layout satisfying that, hand-checked against
-- spawns/buildings/portal footprints in Decorations.lua's placement pass.
SeatingConfig.ZONES = {
	-- Around the queue portal, at the lobby's visual/social center - low
	-- stools so nothing blocks the view up to the floating sign or across
	-- to the portal itself.
	{
		id = "PortalPlazaZone",
		seatType = "SeatTypeD",
		placements = {
			{ position = scaled(9, 9), yawDegrees = 45 },
			{ position = scaled(-9, 9), yawDegrees = -45 },
			{ position = scaled(9, -9), yawDegrees = 135 },
			{ position = scaled(-9, -9), yawDegrees = -135 },
		},
	},
	-- Two pairs flanking the main spawn-to-portal walkway, facing inward
	-- toward the path, far enough apart to leave real walking space
	-- between the two pairs.
	{
		id = "WalkwayZone",
		seatType = "SeatTypeA",
		placements = {
			{ position = scaled(24, 62), yawDegrees = -90 },
			{ position = scaled(-24, 62), yawDegrees = 90 },
			{ position = scaled(24, 40), yawDegrees = -90 },
			{ position = scaled(-24, 40), yawDegrees = 90 },
		},
	},
	-- A small open "lounge" cluster off to one side, chairs angled
	-- toward a shared center point rather than all facing the same way -
	-- reads as an actual social nook rather than a row.
	{
		id = "SocialLoungeZone",
		seatType = "SeatTypeB",
		placements = {
			{ position = scaled(50, 25), yawDegrees = 200 },
			{ position = scaled(60, 32), yawDegrees = 250 },
			{ position = scaled(60, 15), yawDegrees = 160 },
			{ position = scaled(50, 5), yawDegrees = 110 },
		},
	},
	-- One booth seat to the side of each remaining walk-in building's
	-- entrance, facing back toward the doorway - present without
	-- blocking it (LeaderboardHall is intentionally excluded here; it
	-- gets its own zone below since it's no longer a walk-in building).
	-- Offsets are fixed/unscaled - they're relative to each building's own
	-- (unscaled) footprint size - added onto that building's already-scaled
	-- LobbyConfig position.
	{
		id = "BuildingFrontZone",
		seatType = "SeatTypeC",
		placements = {
			{ position = LobbyConfig.BUILDINGS[1].position + Vector3.new(13, 0, 16.5), yawDegrees = 180 }, -- Shop
			{ position = LobbyConfig.BUILDINGS[2].position + Vector3.new(8, 0, 14), yawDegrees = 180 }, -- DailyRewards
			{ position = LobbyConfig.BUILDINGS[4].position + Vector3.new(-8, 0, 14), yawDegrees = 180 }, -- TutorialBuilding
			{ position = LobbyConfig.BUILDINGS[5].position + Vector3.new(-13, 0, 11.5), yawDegrees = 180 }, -- StatisticsBuilding
		},
	},
	-- Facing the leaderboard arc from a comfortable viewing distance -
	-- the old single-screen design had benches here; the five-board
	-- redesign didn't carry them forward, so this restores seating at
	-- that point of interest. Offset from the (already-scaled) hall
	-- position, itself scaled to keep pace with the leaderboard arc's own
	-- radius (see LeaderboardConfig.lua).
	{
		id = "LeaderboardViewingZone",
		seatType = "SeatTypeC",
		placements = {
			{ position = LobbyConfig.BUILDINGS[3].position + scaled(-16, 18), yawDegrees = 180 },
			{ position = LobbyConfig.BUILDINGS[3].position + scaled(16, 18), yawDegrees = 180 },
		},
	},
}

return SeatingConfig
