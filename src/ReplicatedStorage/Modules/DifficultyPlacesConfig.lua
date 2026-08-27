--[[
	DifficultyPlacesConfig.lua

	True multi-Place Play Mode routing: the registry of which real Roblox
	Place each difficulty tier (GameplayConfig.QUEUE_TIERS id 1-5) lives
	on, isolated one-map-per-server per the project's "true multi-Place
	experience" architecture decision (see README.md's Play Mode
	Architecture section).

	This game's MAIN place (the one this script's own project.json
	describes, and everything under Workspace.Lobby/LobbyLava/etc. today)
	stays the single shared "Hub" - the multi-map exploration lobby
	players start in. It is NOT one of the five difficulty destinations
	below. Picking ANY difficulty from the Hub (or from another
	difficulty's Place) always routes through PlaceTeleportSystem to one
	of the five dedicated Places listed here.

	PLACE IDS ARE PLACEHOLDERS (0) UNTIL THE FIVE DESTINATION PLACES ARE
	ACTUALLY CREATED IN ROBLOX STUDIO. A placeId of 0 is never a valid
	real Place - PlaceTeleportSystem treats it as "not configured yet"
	and safely refuses to route there (fails closed, tells the player
	Play Mode isn't ready for that difficulty yet, does not error or
	teleport to place 0). Fill in each `placeId` below with the real
	value (visible as `game.PlaceId` when that Place is open in Studio,
	or from the Place's entry in Game Settings > Places) once created,
	then republish this Place so every server picks up the change.

	Every one of the five Places listed here is expected to sync the
	EXACT SAME src/ tree via its own <difficulty>.project.json (see repo
	root) - same ServerScriptService, same ReplicatedStorage, same
	StarterPlayer/StarterGui - so all shared systems (matchmaking, data
	saving, progression, shop, leaderboards, question generation) work
	identically everywhere with zero duplicated code. The only things
	that differ per Place are: which ONE MapsConfig map that Place's
	Main.server.lua builds (see Main.server.lua's use of
	DifficultyPlacesConfig.GetMapIdForPlace), and this table's `placeId`
	entries.
]]

local DifficultyPlacesConfig = {}

export type DifficultyPlaceDef = {
	tierId: number, -- matches a GameplayConfig.QUEUE_TIERS id (1-5)
	mapId: string, -- matches a MapsConfig.MAPS id - the ONLY map this Place builds
	displayName: string,
	placeId: number, -- real Roblox Place id once created; 0 = not yet configured
}

-- Placeholder placeId = 0 for every entry until the five Places exist.
-- Difficulty numbering matches GameplayConfig.QUEUE_TIERS exactly:
-- 1 Easy/Futuristic, 2 Medium/Under the Sea, 3 Hard/Ice Age (Tundra),
-- 4 Expert/Lava (Volcano), 5 Master/Space.
DifficultyPlacesConfig.PLACES = {
	{ tierId = 1, mapId = "Futuristic", displayName = "MathArena - Futuristic (Difficulty 1)", placeId = 0 },
	{ tierId = 2, mapId = "UnderTheSea", displayName = "MathArena - Under the Sea (Difficulty 2)", placeId = 0 },
	{ tierId = 3, mapId = "IceAge", displayName = "MathArena - Tundra (Difficulty 3)", placeId = 0 },
	{ tierId = 4, mapId = "Lava", displayName = "MathArena - Volcano (Difficulty 4)", placeId = 0 },
	{ tierId = 5, mapId = "Space", displayName = "MathArena - Space (Difficulty 5)", placeId = 0 },
} :: { DifficultyPlaceDef }

--[[
	Returns the DifficultyPlaceDef for `tierId`, or nil if `tierId` isn't
	one of the five known difficulty tiers. Callers must not assume this
	always returns something - see PlaceTeleportSystem's validation.
]]
function DifficultyPlacesConfig.GetPlaceForTier(tierId: number): DifficultyPlaceDef?
	for _, def in ipairs(DifficultyPlacesConfig.PLACES) do
		if def.tierId == tierId then
			return def
		end
	end
	return nil
end

--[[
	Returns the DifficultyPlaceDef whose placeId matches `placeId`, or nil
	if `placeId` doesn't belong to any configured difficulty destination -
	which is exactly the case for the Hub (this game's main Place) and for
	any difficulty Place whose placeId hasn't been filled in yet. Used at
	server start (Main.server.lua) and by PlaceTeleportSystem to determine
	"am I one of the five difficulty servers, and if so, which one?".
]]
function DifficultyPlacesConfig.GetPlaceForPlaceId(placeId: number): DifficultyPlaceDef?
	if placeId == 0 then
		return nil
	end
	for _, def in ipairs(DifficultyPlacesConfig.PLACES) do
		if def.placeId ~= 0 and def.placeId == placeId then
			return def
		end
	end
	return nil
end

--[[
	True only once every one of the five Places has a real (non-zero)
	placeId filled in. PlaceTeleportSystem uses this defensively, but
	each individual lookup already fails closed on its own (a single
	un-configured entry just can't be routed to yet, everything else
	still works) - this is only for a single "are we fully set up yet?"
	warning at server start.
]]
function DifficultyPlacesConfig.IsFullyConfigured(): boolean
	for _, def in ipairs(DifficultyPlacesConfig.PLACES) do
		if def.placeId == 0 then
			return false
		end
	end
	return true
end

return DifficultyPlacesConfig
