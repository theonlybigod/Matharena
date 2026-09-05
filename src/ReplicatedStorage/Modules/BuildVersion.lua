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
--  10 = Ice Age FrozenPeaks reposition: the 8 part-built foothill peaks
--       moved from a fixed ring at 70-92% of ENCLOSURE_RADIUS (700-920
--       studs, deep inside the real Terrain mountain range built by
--       BuildTerrainMountains) onto the snow apron between the plaza rim
--       and the range's own inner edge (210-300 studs), with each peak's
--       Y now sampled from the same mountainHeight(x, z) the terrain range
--       itself uses instead of a hardcoded -20, so the base sits flush
--       with the snow instead of buried in or floating above it.
--  11 = Ice Age FrozenPeaks ground-contact fix: version 10's placement
--       still embedded every peak 2-7 studs into the terrain, because
--       buildFrozenPeak's tier-0 shingles get random jitter AND a
--       rotated CFrame, so a model's true GetBoundingBox() bottom does
--       not sit at the Y it was built at - mountainHeight(x, z) was
--       correct, but nothing accounted for that gap between intended and
--       actual geometry. buildFrozenPeak now returns its model, and
--       buildFrozenPeaks measures each one's real bounding-box bottom
--       after building it and shifts it vertically by whatever the actual
--       difference turns out to be, plus a small deliberate
--       GROUND_CLEARANCE (1.5 studs) so the base sits ON the snow rather
--       than exactly flush-touching it.
--  12 = Ice Age FrozenPeaks ground-truth snap: version 11 still left every
--       peak sitting ~0.5 studs INTO the terrain, because Terrain's actual
--       rendered surface bulges above the analytic mountainHeight() value
--       by roughly half a voxel (~2 studs) depending on neighbouring
--       occupancy - not something predictable from the formula alone.
--       LobbyBuilder now calls the new IceAgeEnvironment.
--       SnapFrozenPeaksToTerrain(frozenPeaksFolder) immediately after
--       BuildTerrainMountains actually writes the range, which raycasts
--       each peak's real position against the just-built Terrain and
--       shifts it to sit exactly CLEARANCE studs above the true surface -
--       ground truth instead of a second analytic guess.
--  13 = Ice Age FrozenPeaks footprint sampling: version 12's snap still used
--       a single centre raycast, so it guaranteed clearance AT the model's
--       centre point but not across its whole ~60-stud base - apron height
--       genuinely varies across that span, so an outlying shingle could sit
--       over locally higher terrain than the centre and still dip in.
--       SnapFrozenPeaksToTerrain now samples the centre plus an 8-point
--       ring at the model's own bounding-radius and corrects against the
--       HIGHEST terrain point found across all of them, guaranteeing the
--       entire footprint clears rather than just its centre.
--  14 = Ice Age FrozenPeaks sampling density: version 13's single ring still
--       missed a dip on FrozenPeak7 (an irregular jittered blob, not a
--       clean disc, so bumps can sit at any radius fraction). Now samples
--       three concentric rings (35%/70%/100% of radius) at 12 angles each,
--       and uses the bounding box's DIAGONAL as the sample radius (not just
--       its shorter half-width) so a non-square footprint's corners are
--       covered too, not just the nearer edge.
--  15 = Ice Age FrozenPeaks locked to hand-placed positions: after version
--       14's procedural+ground-truth-snap placement was live and verified
--       clean (zero overlap, confirmed by dense per-part sampling), the
--       positions were manually fine-tuned by hand in Studio and approved
--       as final. buildFrozenPeaks now uses 8 hardcoded Vector3 literals
--       (read directly off the hand-placed Tundra place) instead of
--       procedural angle/radius placement, and LobbyBuilder no longer calls
--       SnapFrozenPeaksToTerrain for IceAge - both changes exist specifically
--       so no future rebuild can move these peaks again. The discarded
--       angle/radius RNG draws are kept in buildFrozenPeaks purely so each
--       peak's shape generation (baseRadius, peakHeight, shingle jitter)
--       consumes the same RNG sequence as before and stays byte-identical.
--  16 = Ice Age FrozenPeaks position correction: version 15's hardcoded
--       positions were captured from a stale/incorrect read - re-verified
--       directly against the currently-connected Tundra place (single-map
--       session, confirmed via Workspace containing only LobbyIceAge/Arena,
--       no other maps), read twice independently with identical results
--       both times, and found to differ from version 15's values by up to
--       ~30 studs on some axes. HAND_PLACED_POSITIONS updated to the
--       confirmed-correct values; no other logic changed.
BuildVersion.CURRENT = 16
--  17 = Ice Age FrozenPeaks ground-clearance fix: with SnapFrozenPeaksToTerrain
--       removed (version 15), the raw hand-placed Y values had no correction
--       against the actual terrain and all 8 peaks ended up embedded 4.5-8.5
--       studs into the snow (found via the same dense per-part sampling used
--       to verify version 14). Fixed with a Y-ONLY vertical nudge per peak -
--       X/Z left byte-identical to version 16 - computed from each peak's
--       measured worst-clearance point so every peak now clears the terrain
--       by exactly 1.5 studs, verified with a second independent dense-
--       sampling pass after the shift.
BuildVersion.CURRENT = 17
--  18 = Ice Age FrozenPeaks: version 17's ground-clearance fix reverted per
--       explicit request ("they look odd now") - each peak shifted back
--       down by the exact inverse of version 17's own per-peak correction,
--       restoring HAND_PLACED_POSITIONS to their original hand-placed Y
--       values (matching version 16 to within ~0.005 studs of float
--       rounding). X/Z untouched throughout. Peaks are once again embedded
--       several studs into the terrain, same as before version 17 - that is
--       the explicitly requested state, not an oversight.
BuildVersion.CURRENT = 18
--  19 = Ice Age flower beds removed. Decorations.lua's createFlowerBed (one
--       bed per building - FlowerBedSoil, Flower1/2/3, FlowerStem1/2/3, 28
--       parts total across 4 buildings) is now skipped specifically for
--       IceAge via a CURRENT_THEME_ID guard - flowers at the foot of a
--       snowbound building read as thematically wrong, and were explicitly
--       requested removed. Every other theme (Futuristic, Lava, Space,
--       UnderTheSea) is unaffected - createFlowerBed itself is untouched,
--       only IceAge's call to it is skipped. Also removed live from the
--       already-built Tundra place.
BuildVersion.CURRENT = 19
--  20 = Flower beds extended to ALL FIVE maps, not just IceAge. Version 19's
--       CURRENT_THEME_ID guard is replaced with a flat ENABLE_FLOWER_BEDS =
--       false switch, so createFlowerBed's call site never runs regardless
--       of theme. createFlowerBed itself stays defined but unused, in case
--       a future theme wants flowers back. The now-unused CURRENT_THEME_ID
--       tracking added in version 19 is removed along with it.
BuildVersion.CURRENT = 20
--  21 = Ice Age FrozenPeaks re-grounded. Versions 15-18's hardcoded
--       HAND_PLACED_POSITIONS were captured as ABSOLUTE Y values at the
--       time - fine until the terrain itself changed height underneath
--       them (a snow-flush/terrain fix landed after they were captured),
--       at which point the peaks silently stayed at their old fixed Y
--       while the ground they were placed against moved - discovered as
--       peaks floating 19-45 studs above the real terrain, not touching
--       it at all, despite the X/Z and source code being completely
--       unchanged. HAND_PLACED_POSITIONS' Y values are corrected to sit
--       back on the CURRENT real terrain at a consistent -5 clearance
--       (matching the previously-approved slight-embed look); X/Z
--       untouched. This is the known fragility of storing an ABSOLUTE
--       fixed position rather than a terrain-relative one: it will drift
--       out of sync again if the terrain is ever rebuilt with different
--       heights at these specific points in the future.
BuildVersion.CURRENT = 21
--  22 = Shop terminal glow-beam removed. FeaturedPreviewShaft (a ~9-stud
--       tall Neon cylinder, client-tinted to the featured item's colour
--       by ShopFeaturedController) and its FeaturedPreviewBase plinth are
--       gone from BuildingInteriors.FurnishShop - reported as an unwanted
--       glowing beam roughly double a character's height inside every
--       Shop building on every map. ShopFeaturedController's shaft-tint
--       binding/tracking code is removed to match; the FeaturedItemBoard
--       wall screen (today's featured item text) is untouched.
BuildVersion.CURRENT = 22
--  23 = Shop Rewards side added. FurnishShop now also builds a mirrored
--       Rewards terminal + a big "OPEN REWARDS" wall sign on the shop's
--       right (+X) wall, opposite the existing Shop terminal on the left -
--       reward-only cosmetics now have their own physical presence in the
--       building, not just the Shop panel's Rewards toggle. New instances:
--       RewardsBoard/RewardsBoardFrame (side wall screen),
--       RewardsTerminalStand/RewardsTerminalPrompt (terminal).
BuildVersion.CURRENT = 23
--  24 = Daily Rewards floor claim pads + wall title redesign. FurnishRewards
--       now also builds 7 "StreakDayFloorPad" parts directly in the
--       walking path (the existing StreakDayPlinths sit beside the path on
--       purpose, so a player walks past them, not over them) plus a normal-
--       font "Run over the day to collect the reward" sign.
--       DailyRewardsSystem wires real touch-to-claim on these pads
--       server-side. The StreakVaultBoard wall title ("YOUR STREAK VAULT")
--       and its status line are now centred in Bangers, matching the
--       Shop's "FEATURED TODAY" treatment. The popup's old 7-day row +
--       "CLAIM TODAY'S REWARD" button are removed - claiming is now floor-
--       only, the popup just reflects status.
BuildVersion.CURRENT = 24
--  25 = Lifetime Rewards wall board. FurnishRewards now also builds a
--       "LifetimeRewardsBoard" on the Daily Rewards room's left wall (via
--       the shared buildSideScreen helper), rendered by
--       RivalBoardController.client.lua with the same centred-Bangers-title
--       treatment as the Shop and the Streak Vault: a two-column grid of
--       every LifetimeRewardsConfig category with working progress bars
--       and Claim buttons, mirroring the popup's Lifetime tab exactly
--       (same remotes, same snapshot) rather than a second source of truth.
BuildVersion.CURRENT = 25
--  26 = Daily Rewards floor rebuild + Lifetime board relocation. The old
--       StreakVaultBoard (back wall), StreakDayPlinth/StreakDayCap
--       (side-offset props), and the DailyRewardsTerminalStand/Prompt are
--       all REMOVED. Daily Rewards is now floor-only: a standing header
--       board ("DAILY REWARDS" + streak status) plus seven fixed
--       left-to-right walkable floor tiles (day 1 always leftmost, day 7
--       always rightmost - never reordered), each one a real touchable
--       claim button. LifetimeRewardsBoard moved from the left side wall
--       to the back wall (Daily's old spot). No bottom-bar Daily button,
--       no E-press terminal - Daily Rewards is reachable only by walking
--       into the building. Also: 3 new Lifetime milestones (2000 lifetime
--       correct answers, a 20-match win streak, 50 hours played).
BuildVersion.CURRENT = 26
--  27 = Daily Rewards floor runway, second pass. The standing header board
--       and standing instruction sign (both mounted vertically, in front
--       of the door - not wanted there) are REMOVED. Everything is now
--       one continuous floor-mounted runway, Face=Top throughout: a
--       title segment ("DAILY REWARDS" + streak status), an instruction
--       segment ("Run over the day...", static), then the seven day
--       cells - all turned flat so it reads as a rug/runway you walk
--       along. Also fixes a real touch-to-claim bug: the previous floor
--       tiles sat slightly BELOW this room's actual floor surface
--       (measured, not guessed), so a walking character's feet never
--       actually overlapped them - confirmed via GetTouchingParts only
--       ever reporting the room's plain Floor part, never a tile. Every
--       segment is now bottom-aligned to the real floor surface.
BuildVersion.CURRENT = 27
--  28 = Daily Rewards floor runway, reading-direction + sizing fix. Order
--       reversed: the title+status segment ("top of the screen") is now
--       nearest the back wall (beside the Lifetime board), the seven day
--       cells ("bottom of the screen") are nearest the door - far side to
--       close side, matching the old vertical wall screen's own top-to-
--       bottom order instead of the reverse. All three segments' depths
--       now scale together to fill the room's actual usable floor depth
--       (with clearance at the back wall and the door) instead of a
--       fixed size.
BuildVersion.CURRENT = 28
--  29 = Daily Rewards floor runway - text spaciousness fix. Individually
--       rotating TextLabels (previous pass) made the text-wrapping engine
--       compute line breaks in the narrow UNROTATED box, cramming the
--       "run over the day..." sentence into one word per line. Fixed by
--       building each segment's content in NATURAL wide-format
--       coordinates (matching the old vertical wall screen's own
--       numbers) inside a wrapper Frame sized to those natural
--       dimensions, then rotating the WHOLE wrapper 90 as one rigid unit
--       - the wrapper's declared (unrotated) size is what the text-layout
--       engine sees, so every label gets its full natural amount of room
--       regardless of the physical part's swapped canvas. Day-cell canvas
--       also enlarged (220->300) for more breathing room.
BuildVersion.CURRENT = 29
--  30 = Daily Rewards floor runway - real bug fix + more spacious day
--       cells. Fixed a genuine bug: renderFloorTiles checked
--       `entry.collected`, a field that doesn't exist on the snapshot's
--       track entries (the real field is `isCollected`) - so the green
--       "CLAIMED" tint could never trigger for an already-collected day,
--       silently, for every player, since this floor screen was built.
--       Also: visible gaps between day tiles (was nearly touching),
--       larger canvas (360, was 300) and generous margins/line spacing
--       inside each tile, since the previous pass still read as cramped.
BuildVersion.CURRENT = 30
--  31 = Shop "OPEN SHOP" wall sign added. FurnishShop now builds a mirrored
--       side screen on the Shop's LEFT (-X) wall (buildSideScreen, same
--       helper the "OPEN REWARDS" sign on the right wall already used),
--       tagged "ShopOpenBoard", labelled "OPEN SHOP" in this file's own
--       ACCENT_COLOR. Closes the gap where the Rewards side had a big
--       obvious wall sign and the Shop side (despite already having its
--       own terminal) did not.
BuildVersion.CURRENT = 31

return BuildVersion
