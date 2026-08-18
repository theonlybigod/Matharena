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
local Config = require(ReplicatedStorage.Modules.Config)

local SeatingConfig = {}

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
		accentColor = Config.BRAND_NEON_COLOR,
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
		accentColor = Config.BRAND_NEON_COLOR,
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
		accentColor = Config.BRAND_NEON_COLOR,
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
			{ position = Vector3.new(9, 0, 9), yawDegrees = 45 },
			{ position = Vector3.new(-9, 0, 9), yawDegrees = -45 },
			{ position = Vector3.new(9, 0, -9), yawDegrees = 135 },
			{ position = Vector3.new(-9, 0, -9), yawDegrees = -135 },
		},
	},
	-- Two pairs flanking the main spawn-to-portal walkway, facing inward
	-- toward the path, far enough apart to leave real walking space
	-- between the two pairs.
	{
		id = "WalkwayZone",
		seatType = "SeatTypeA",
		placements = {
			{ position = Vector3.new(24, 0, 62), yawDegrees = -90 },
			{ position = Vector3.new(-24, 0, 62), yawDegrees = 90 },
			{ position = Vector3.new(24, 0, 40), yawDegrees = -90 },
			{ position = Vector3.new(-24, 0, 40), yawDegrees = 90 },
		},
	},
	-- A small open "lounge" cluster off to one side, chairs angled
	-- toward a shared center point rather than all facing the same way -
	-- reads as an actual social nook rather than a row.
	{
		id = "SocialLoungeZone",
		seatType = "SeatTypeB",
		placements = {
			{ position = Vector3.new(50, 0, 25), yawDegrees = 200 },
			{ position = Vector3.new(60, 0, 32), yawDegrees = 250 },
			{ position = Vector3.new(60, 0, 15), yawDegrees = 160 },
			{ position = Vector3.new(50, 0, 5), yawDegrees = 110 },
		},
	},
	-- One booth seat to the side of each remaining walk-in building's
	-- entrance, facing back toward the doorway - present without
	-- blocking it (LeaderboardHall is intentionally excluded here; it
	-- gets its own zone below since it's no longer a walk-in building).
	{
		id = "BuildingFrontZone",
		seatType = "SeatTypeC",
		placements = {
			{ position = Vector3.new(-70 + 13, 0, -40 + 12.5 + 4), yawDegrees = 180 }, -- Shop
			{ position = Vector3.new(-40 + 8, 0, -70 + 10 + 4), yawDegrees = 180 }, -- DailyRewards
			{ position = Vector3.new(40 - 8, 0, -70 + 10 + 4), yawDegrees = 180 }, -- TutorialBuilding
			{ position = Vector3.new(70 - 13, 0, -40 + 7.5 + 4), yawDegrees = 180 }, -- StatisticsBuilding
		},
	},
	-- Facing the leaderboard arc from a comfortable viewing distance -
	-- the old single-screen design had benches here; the five-board
	-- redesign didn't carry them forward, so this restores seating at
	-- that point of interest.
	{
		id = "LeaderboardViewingZone",
		seatType = "SeatTypeC",
		placements = {
			{ position = Vector3.new(-16, 0, -62), yawDegrees = 180 },
			{ position = Vector3.new(16, 0, -62), yawDegrees = 180 },
		},
	},
}

return SeatingConfig
