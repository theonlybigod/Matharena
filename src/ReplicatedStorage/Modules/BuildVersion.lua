--[[
	BuildVersion.lua

	One number that says "the world-building code has changed - anything
	built by an older version of it is stale and must be regenerated."

	WHY THIS EXISTS (the bug it fixes):
		LobbyBuilder.Build/ArenaBuilder.Build are deliberately skip-if-
		already-built (see their rerun policy) - they check a
		"MathArenaBuilt" attribute on the Workspace folder and return
		early if it's set. That attribute is saved INTO the place file, so
		once a Place has been built and published/saved even once, every
		later server start (and every later Studio open) skipped building
		forever - which meant new decorations, theme changes, arena
		changes, spawn fixes, etc. never appeared on that Place again, no
		matter how many times the code was edited, synced and republished.
		That is exactly why edits kept showing up on some Places but not
		others: the Places whose geometry happened to be built most
		recently looked current, and the rest were frozen at whatever the
		code looked like the day they were first built.

		Now both builders ALSO stamp "MathArenaBuildVersion" alongside
		"MathArenaBuilt". If what's stored doesn't equal CURRENT below,
		the geometry was made by older code and is rebuilt automatically -
		on a live server start, in a Studio Play test, and in Studio Edit
		mode via the MathArenaAutoBuild plugin (tools/StudioPlugins), all
		using the exact same code path. Nothing to remember per Place.

	HOW TO USE IT - the one rule:
		Whenever you change anything that affects what the builders
		actually PRODUCE - LobbyBuilder or ArenaBuilder or any of their
		construction modules (Floor, Buildings, BuildingInteriors,
		Decorations, Trees, StreetLamps, Seating, SpawnsAndPortal,
		LeaderboardBoards, Sign, the *Environment modules, MapBaseplate,
		Platforms, CenterStage, ArenaDecorations), or LobbyTheme /
		MapsConfig / LobbyConfig / MapConfig / ArenaConfig values that
		feed them - increment CURRENT by 1.

		You do NOT need to bump it for changes that don't build geometry
		(matchmaking, data, UI, teleport routing, question generation).
		Bumping it unnecessarily is harmless though - it just means every
		Place regenerates its world once on next start.

	COST OF A BUMP: the next server start (or Studio open) on each Place
	destroys and regenerates that Place's world once, then goes back to
	skipping until the next bump. A full Hub rebuild is all five maps plus
	the arena, so it is not instant - that is the intended, one-time price
	of a change actually reaching every Place.
]]

local BuildVersion = {}

-- Bump by 1 whenever builder output changes. See the rule above.
--   1 = pre-versioning (implicit; anything built before this module
--       existed has no stored version at all and is treated as stale)
--   2 = multi-Place pass: per-Place single-map builds, spawn-enable fix
--       (difficulty Places no longer depend on MapsConfig.isDefault),
--       and the per-map themed Arena embedded at its map's own origin
--       (ArenaBuilder.BuildForMap) instead of one shared arena at 0,0,0.
--   3 = building interiors pass: the Option B fit-out (feature screen per
--       building, streak path, preview column, terminals) plus the
--       Tutorial room's three-wall lecture layout - left wall for the
--       topic description, centre for the map image and clip, right for
--       tips - and the Under the Sea Tutorial building regrouped into a
--       proper model instead of loose parts in the Buildings folder.
--   4 = Under the Sea exterior redesign: the barrier-reef massif and its
--       2,600-colony coral forest are gone, replaced by a low sandy dune
--       field capped at building height, a 340-stud wooden shipwreck,
--       three submarines, coral gardens with shadows, algae, seabed
--       habitats, and layered marine life (great white / tiger /
--       hammerhead sharks, giant fish, belugas, humpbacks).
--   5 = Under the Sea detail pass: forced-perspective terrain (near-flat
--       by the plate, rising to 78 studs at the rim), 620-stud shipwreck,
--       four larger submarines, ~2x larger and more numerous marine life,
--       150 coral gardens with distance-scaled size and density, plus two
--       new habitat types - rock-arch caves with dark interiors, and tall
--       long-grass meadows biased to the far field.
--   6 = Under the Sea realism pass: coral rebuilt as polyp aggregates
--       (mound / branching / plate / fan / soft / encrusting / tube
--       sponge) from many small units rather than a few large primitives,
--       on a warm red-gold-pink palette; marine life rescaled to real
--       proportions (fish ~1 building, sharks 1.5x, humpbacks 5x) with
--       three whales instead of five; a new InteriorLife pass restoring
--       schooling fish, jellyfish, stingrays, reef sharks and starfish to
--       the plaza, all sized below a podium; and the shipwreck stripped of
--       hull coral in favour of boulders on the surrounding sand.
--   7 = Under the Sea animal pass: all fish rebuilt by a single buildFish
--       from a dozen large flat slabs (body, wedge head, forked tail,
--       dorsal/anal/pectoral fins, eyes, optional banding) so each reads as
--       one solid figure; exterior fish grouped into single-species shoals
--       plus sardine baitballs instead of scattered individuals; sharks and
--       whales enlarged (sharks 85-130, belugas 120-155, humpbacks
--       300-390); plaza fish cut from 242 to 40; starfish arms now joined
--       to the central disc; fan coral given finer units so it reads as a
--       lattice rather than a sheet.
--   8 = Under the Sea fixes: submarines rebuilt from a continuous
--       14-section hull profile with sail, planes, cruciform tail and
--       shrouded screw; and the exterior terrain no longer intrudes on the
--       plate - the dune field is gated per-COLUMN at DUNE_INNER (was a
--       per-tile test that let straddling tiles lay sand across the plaza,
--       leaving a square hole in the middle), and the seabed datum dropped
--       from 0 to -8 so near-plate sand sits ~12 studs below the walking
--       surface. The datum is folded into duneHeight so every scatter pass
--       still places props on the sand.
--   9 = Under the Sea seabed continuity: the sand now runs CONTINUOUSLY
--       beneath the lobby plate rather than being cut off at a circle
--       outside it, so there is no visible edge where the exterior
--       begins. Seabed datum sits 3 studs under the plate's underside
--       (clearance sized for terrain's smoothed render, which bulges ~half
--       a voxel above nominal), and a 140-stud flat skirt past the rim
--       stops the dunes cresting above the plate.
BuildVersion.CURRENT = 9

return BuildVersion
