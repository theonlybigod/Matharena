--[[
	TreeConfig.lua

	Centralized configuration for the lobby's enhanced futuristic trees
	(Message 2 refinement, replacing the old sphere-canopy trees inline in
	Decorations.lua). Four distinct angular/geometric variants - see
	Trees.lua for the construction functions, one per variant id.

	Height doubling: the old trees were trunk 5-10 + a roughly comparable
	sphere canopy on top, averaging a total height around 15 studs. This
	pass targets trunk 10-16 + canopy 12-22 (canopy alone is often taller
	than the trunk - "canopy occupying a substantial portion of overall
	height"), averaging a total around 30 studs - roughly double.

	Stable identifiers: every tree Model is named TreeConfig.MODEL_NAME
	("LobbyTree") with a "TreeVariant" Attribute (one of VARIANT_IDS), and
	the root Trees folder carries the "Vegetation" Attribute - matching
	the naming the design brief asked for.

	Uses angular Parts/WedgeParts throughout (tapered blocks, faceted
	shard clusters, angled boughs) instead of the old Ball-shaped foliage
	spheres - "sharper, more intentional angles... complex geometric
	silhouettes... stylized futuristic trees with architectural/geometric
	complexity, rather than realistic botanical trees".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)

local TreeConfig = {}

TreeConfig.ROOT_ATTRIBUTE = "Vegetation"
TreeConfig.MODEL_NAME = "LobbyTree"
TreeConfig.VARIANT_ATTRIBUTE = "TreeVariant"

TreeConfig.VARIANT_IDS = { "Spire", "CanopyBurst", "TwinBough", "CrystalCluster" }

-- Scaled up again for the Lava map's "bigger and more noticeable" pass:
-- trunk range raised from 10-16. Trees now stand well clear of the
-- street lamps and read as landmarks from across the plaza rather than
-- as background dressing.
TreeConfig.TRUNK_HEIGHT_MIN = 16
TreeConfig.TRUNK_HEIGHT_MAX = 26
-- Trunk widths raised in proportion (was 1.8-3.4) so the taller trunks
-- don't read as spindly poles.
TreeConfig.TRUNK_WIDTH_MIN = 2.8
TreeConfig.TRUNK_WIDTH_MAX = 5.2
TreeConfig.TRUNK_TAPER_RATIO = 0.45 -- upper trunk segment width = lower width * this (was 0.65 - a sharper step)

-- Canopy sized so it's a substantial fraction of - often taller than -
-- the trunk itself, unlike the old canopy which was roughly trunk-sized.
-- Bumped up from an initial 12-22 pass after measuring realized tree
-- heights in Studio came in under the "roughly double" target once each
-- variant's own internal proportion multipliers were accounted for.
TreeConfig.CANOPY_HEIGHT_MIN = 24
TreeConfig.CANOPY_HEIGHT_MAX = 38
TreeConfig.CANOPY_WIDTH_MIN = 15
TreeConfig.CANOPY_WIDTH_MAX = 27

TreeConfig.LEAN_DEGREES_MAX = 6 -- kept modest - these are meant to read as "designed", not wind-blown
TreeConfig.ROTATION_JITTER_DEGREES = 360 -- full free yaw per tree

-- Placement: trees get their OWN ring spacing (not LobbyConfig.TREE_SPACING,
-- which street lamps also multiply from - decoupling them lets tree
-- spacing grow for the bigger canopies without also spreading out lamps).
-- Map-scale refinement: scaled up from 32/6/14 for the +50% larger map.
TreeConfig.RING_SPACING = 48
TreeConfig.RING_JITTER = 9 -- studs; more than before - "avoid evenly spaced rows"
TreeConfig.CLUSTER_CHANCE = 0.22
TreeConfig.SKIP_CHANCE = 0.18 -- slightly more open breathing room than before (was 0.15)
-- Clearance raised with the tree size (was 20). The canopies are now up
-- to 27 wide, so a 20-stud avoid radius would let a branch overhang a
-- path or a bench.
TreeConfig.AVOID_RADIUS = 26

return TreeConfig
