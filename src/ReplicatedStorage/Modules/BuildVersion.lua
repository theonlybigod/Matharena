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
BuildVersion.CURRENT = 4

return BuildVersion
