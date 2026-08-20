--[[
	CentralBoardConfig.lua

	Shared configuration for the lobby's central informational board -
	Message 2 refinement, section 6 ("Redesign the middle board"). This is
	a DISTINCT landmark from both:
		- LobbyBuilder/Sign.lua's floating overhead "MATHARENA" sign
		  (SignConfig.lua) - that one floats high above the map center and
		  is readable from anywhere.
		- LeaderboardBoards.lua's five stat boards - those display live
		  leaderboard data, not branding.
	This board is a ground-anchored, upright informational/branding sign
	standing in the open plaza between the queue portal and the building
	row - a clean, thin-framed, readable board rather than a stacked block
	structure.

	Lives in ReplicatedStorage/Modules alongside SignConfig.lua/
	LightingConfig.lua (not ServerScriptService/LobbyBuilder/LobbyConfig.lua)
	purely for consistency with the other landmark-sign config - nothing
	here is actually required client-side yet, but keeping all "named
	landmark" configs in one place matches the existing precedent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)

local CentralBoardConfig = {}

-- Stable name/Attribute, per the design brief's own suggested naming
-- ("MatharenaBoard").
CentralBoardConfig.BOARD_NAME = "MatharenaBoard"

-- World position: in the open plaza between the queue portal (0,0,0) and
-- the building row (nearest building entrance apron sits at roughly
-- Z=-13; the building row itself starts around Z=-34). Z=-45 keeps clear
-- of both the portal's own footprint (portal size 12x12, so it only
-- extends to Z=+/-6) and every building/apron, and sits well inside the
-- tree/street-lamp rings (which orbit much further out), so it can never
-- collide with procedurally-placed decorations.
CentralBoardConfig.POSITION = Vector3.new(0, 0, -45)
CentralBoardConfig.FACING_YAW_DEGREES = 0 -- faces toward +Z, i.e. toward the portal/spawns - the direction players approach from

-- Overall board size: wide and short (a "sign board" silhouette), not a
-- tall slab - "reduce unnecessary blockiness... refined silhouette".
CentralBoardConfig.BOARD_WIDTH = 16
CentralBoardConfig.BOARD_HEIGHT = 7
CentralBoardConfig.BOARD_THICKNESS = 0.5

-- Thin structural frame (a hollow rectangle of slim bars around the
-- backing panel) instead of a solid block border.
CentralBoardConfig.FRAME_THICKNESS = 0.35 -- how deep/wide each frame bar is
CentralBoardConfig.FRAME_DEPTH = 0.6 -- how far the frame stands proud of the backing panel (subtle depth)

-- Support: two thin poles from the ground up to the panel's underside -
-- "thin structural elements", not a solid pedestal block.
CentralBoardConfig.SUPPORT_HEIGHT = 4 -- ground to panel bottom
CentralBoardConfig.SUPPORT_DIAMETER = 0.5
CentralBoardConfig.SUPPORT_INSET = 2.5 -- studs in from each edge of the board width

CentralBoardConfig.BACKING_COLOR = Color3.fromRGB(20, 22, 28) -- dark, calm backing so text/frame read clearly against it
CentralBoardConfig.FRAME_COLOR = Color3.fromRGB(60, 63, 70) -- dark metal, matches the rest of the lobby's metal accents
CentralBoardConfig.ACCENT_COLOR = LightingConfig.CENTRAL_FEATURE -- same brand-blue family as the portal/floating sign - "visually connected to the rest of the Matharena branding"

CentralBoardConfig.TITLE_TEXT = "MATHARENA"
CentralBoardConfig.TITLE_COLOR = Color3.fromRGB(255, 255, 255)
CentralBoardConfig.TITLE_FONT = Enum.Font.Oswald -- same condensed sans as the floating sign, for a consistent typographic identity

CentralBoardConfig.GLOW_BRIGHTNESS = 1.4 -- a controlled neon accent, deliberately dimmer than the floating sign's own light (that one is the taller landmark; this is a secondary, ground-level one)
CentralBoardConfig.GLOW_RANGE = 24

return CentralBoardConfig
