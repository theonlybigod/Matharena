--[[
	MathArenaAutoBuild.lua (Roblox Studio Plugin)  -- v3

	Keeps whichever MathArena Place you open in Studio's EDIT mode showing
	what the CURRENT builder code actually produces - detecting changes by
	itself, with no version number to remember and no stale geometry.

	----------------------------------------------------------------------
	WHY v2 KEPT BUILDING OLD MODELS (the three real bugs, now fixed)
	----------------------------------------------------------------------
	1. STUDIO CACHES require() FOREVER. This is the big one. `require(m)`
	   caches its result per Lua VM, keyed by the ModuleScript INSTANCE.
	   Rojo syncs by patching each script's .Source on the SAME instance,
	   so a plugin that required LobbyBuilder once kept using the code as
	   it was at that moment for the whole Studio session - every later
	   "rebuild" faithfully rebuilt the OLD code. That is exactly the
	   "reset build is building older models" symptom.
	   FIX: this plugin never requires anything until the source tree has
	   stopped changing (i.e. Rojo's sync has settled), so its one-and-only
	   require of the session captures current code. If sources change
	   again afterward, it does NOT pretend it can rebuild fresh - it marks
	   the geometry stale so the next place-open rebuilds correctly, and
	   says so. Reopening the place gives the plugin a new VM, hence a
	   genuinely fresh require. (Closing/reopening is the only thing that
	   truly clears Studio's module cache.)

	2. IT BUILT BEFORE ROJO HAD SYNCED. v2 waited a flat 2 seconds and
	   built. If Rojo connected later - the normal case when you open a
	   place first and start syncing after - the modules sitting in the
	   place file were the ones from the LAST PUBLISH, so it dutifully
	   rebuilt last-publish geometry and stamped it "current".
	   FIX: it now waits for the source fingerprint to hold steady before
	   doing anything, and re-checks continuously instead of once.

	3. CHANGE DETECTION NEEDED A MANUAL VERSION BUMP. BuildVersion.CURRENT
	   only helped if you remembered to increment it, so ordinary edits
	   were invisible and got skipped.
	   FIX: the plugin fingerprints the actual .Source of every build-
	   related script (reading .Source needs no require, so it is never
	   stale) plus a signature of the built geometry. Any difference in
	   either - code edit OR a part you moved/added/deleted by hand -
	   marks that map stale and rebuilds it. BuildVersion still works and
	   is still honoured; it is now just a backstop for live servers,
	   which cannot read .Source at all.

	----------------------------------------------------------------------
	WHAT COUNTS AS A CHANGE
	----------------------------------------------------------------------
	  - Any .Source edit under ServerScriptService.LobbyBuilder,
	    ServerScriptService.ArenaBuilder, or ReplicatedStorage.Modules
	    (deliberately a wide net - a false positive only costs one rebuild).
	  - Any script added to or removed from those trees.
	  - Any hand edit to the built geometry: parts added, deleted, moved,
	    resized or renamed under a map folder or Workspace.Arena.
	  - A BuildVersion.CURRENT bump.

	HAND EDITS ARE DISCARDED, BY DESIGN. This project treats code as the
	single source of truth for geometry, so a hand-moved part is drift to
	be corrected, not content to preserve - that is what "rebuild whether
	the edit was manual or by code" means. Every rebuild is one
	ChangeHistoryService recording, so Ctrl+Z restores what it destroyed,
	and the Auto-Build toggle turns the whole thing off while you are
	deliberately experimenting by hand.

	----------------------------------------------------------------------
	TOOLBAR
	----------------------------------------------------------------------
	  Rebuild Now   - force a full destroy-and-regenerate right now.
	  Auto-Build    - toggle automatic rebuilding for this place (the
	                  setting persists per place, via plugin settings).

	INSTALL: Studio -> Plugins tab -> "Plugins Folder", drop this file in,
	overwriting any older copy. Restart Studio if it does not hot-load.

	SAFE BY DESIGN: never runs in Play mode (Main.server.lua owns building
	there), never writes files, never saves or publishes, and cancels its
	ChangeHistory recording if a build errors so a failure cannot leave a
	half-built world behind.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Workspace = game:GetService("Workspace")

-- Play mode / Play Solo / Team Test: Main.server.lua already builds there.
if RunService:IsRunning() then
	return
end

local AUTO_BUILD_SETTING = "MathArenaAutoBuild_Enabled"

-- How long the source fingerprint must hold still before we trust it as
-- "Rojo has finished syncing". Long enough to ride out a multi-file sync,
-- short enough not to feel broken when Rojo is not running at all.
local SETTLE_SECONDS = 3
local SETTLE_POLL = 0.5
local SETTLE_TIMEOUT = 120

-- Attributes stamped on each built root folder.
local ATTR_SOURCE_FINGERPRINT = "MathArenaSourceFingerprint"
local ATTR_GEOMETRY_SIGNATURE = "MathArenaGeometrySignature"

--=========================================================================
-- Hashing helpers
--=========================================================================

--[[
	djb2-style 32-bit rolling hash, deterministic across sessions (unlike
	table addresses or tostring of an Instance) - that determinism is what
	makes a fingerprint stored in the place file still meaningful days
	later, on another machine, after a save/reopen round trip.

	Multiplier is 33, NOT FNV's 16777619, for an unglamorous but important
	reason: Lua numbers are doubles, exact only to 2^53. A 32-bit
	accumulator times 16777619 reaches ~7.2e16, past that limit, so the
	low bits get silently rounded away and the "hash" stops being a
	function of its input - it would report spurious changes on identical
	code, or miss real ones. 4294967295 * 33 + 255 is ~1.4e11, exact.

	Bytes are pulled in 4096-char batches: string.byte(s, i, j) returns
	multiple values, and one call per character over a 100KB+ source file
	(BuildingInteriors.lua alone is ~108KB) is what would make this crawl.
]]
local function hashString(text: string, seed: number?): number
	local hash = seed or 5381
	local length = #text
	local i = 1

	while i <= length do
		local j = math.min(i + 4095, length)
		local batch = { string.byte(text, i, j) }
		for k = 1, #batch do
			hash = bit32.band(hash * 33 + batch[k], 0xFFFFFFFF)
		end
		i = j + 1
	end

	return hash
end

--=========================================================================
-- Source fingerprint - "what does the build code look like right now?"
--=========================================================================

-- The trees whose code decides what the world looks like. Wide on purpose.
local function sourceRoots(): { Instance }
	local roots = {}
	for _, container in ipairs({ ServerScriptService, ReplicatedStorage }) do
		for _, name in ipairs({ "LobbyBuilder", "ArenaBuilder", "Modules" }) do
			local found = container:FindFirstChild(name)
			if found then
				table.insert(roots, found)
			end
		end
	end
	return roots
end

--[[
	Fingerprints every script's full path + .Source across those trees.

	Reading .Source is a plugin-security capability that does NOT involve
	require(), so this is immune to the module cache that caused bug 1 -
	it always reflects what is actually in the session right now, whether
	that came from Rojo a second ago or from the last publish.

	Accumulated with addition (commutative) so GetDescendants() ordering
	can never change the result for an unchanged tree.
]]
local function computeSourceFingerprint(): (number, number)
	local total = 0
	local scriptCount = 0

	for _, root in ipairs(sourceRoots()) do
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("LuaSourceContainer") then
				local ok, source = pcall(function()
					return (descendant :: any).Source
				end)
				if ok and typeof(source) == "string" then
					scriptCount += 1
					total = (total + hashString(descendant:GetFullName() .. "\0" .. source)) % 4294967296
				end
			end
		end
	end

	return total, scriptCount
end

--[[
	A much cheaper proxy fingerprint - path plus source LENGTH, never the
	source bytes - used only for the settle poll, which runs twice a second
	while waiting for Rojo. Full-hashing ~500KB of source at that cadence
	would visibly hitch Studio for no benefit: the poll only needs to
	answer "is the tree still changing?", and a sync in progress changes
	file lengths constantly.

	A same-length edit (say a colour value 100 -> 200) is invisible here,
	which is fine - the FULL fingerprint is what every actual build/stale
	decision uses, and it catches those.
]]
local function computeCheapFingerprint(): (number, number)
	local total = 0
	local scriptCount = 0

	for _, root in ipairs(sourceRoots()) do
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("LuaSourceContainer") then
				local ok, source = pcall(function()
					return (descendant :: any).Source
				end)
				if ok and typeof(source) == "string" then
					scriptCount += 1
					total = (total + hashString(descendant.Name) + #source * 31) % 4294967296
				end
			end
		end
	end

	return total, scriptCount
end

--=========================================================================
-- Geometry signature - "has this map been hand-edited since we built it?"
--=========================================================================

--[[
	Signs the built contents of one Workspace folder: every part's name,
	rounded position and rounded size, plus the total descendant count.

	Rounded to 0.01 studs so floating-point noise from Roblox's own
	serialization round-trip (save -> reopen) cannot masquerade as a hand
	edit and cause a pointless rebuild on every single open. Commutative
	accumulation again, for order independence.
]]
local function computeGeometrySignature(root: Instance): number
	local total = 0
	local count = 0

	for _, descendant in ipairs(root:GetDescendants()) do
		count += 1
		if descendant:IsA("BasePart") then
			local p, s = descendant.Position, descendant.Size
			total = (
				total
				+ hashString(
					("%s|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f"):format(descendant.Name, p.X, p.Y, p.Z, s.X, s.Y, s.Z)
				)
			) % 4294967296
		end
	end

	return (total + count) % 4294967296
end

--=========================================================================
-- Module resolution
--=========================================================================

local function resolveModules()
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	local mapsConfig = modules and modules:FindFirstChild("MapsConfig")
	local difficultyPlaces = modules and modules:FindFirstChild("DifficultyPlacesConfig")
	local lobbyBuilder = ServerScriptService:FindFirstChild("LobbyBuilder")
	local arenaBuilder = ServerScriptService:FindFirstChild("ArenaBuilder")

	if not (mapsConfig and difficultyPlaces and lobbyBuilder and arenaBuilder) then
		return nil, "MathArena's modules aren't in this session yet - start Rojo, let it sync, then press Rebuild Now."
	end

	local ok, result = pcall(function()
		return {
			MapsConfig = require(mapsConfig),
			DifficultyPlacesConfig = require(difficultyPlaces),
			LobbyBuilder = require(lobbyBuilder),
			ArenaBuilder = require(arenaBuilder),
		}
	end)

	if not ok then
		return nil, "couldn't load MathArena's modules: " .. tostring(result)
	end
	return result, nil
end

--=========================================================================
-- What this Place is supposed to contain
--=========================================================================

--[[
	Returns the list of Workspace folders this Place is responsible for,
	each with the builder call that (re)creates it - derived the exact same
	way Main.server.lua derives it, from DifficultyPlacesConfig against
	game.PlaceId, so Edit mode can never disagree with a real server.
]]
local function planForThisPlace(m): ({ { folderName: string, build: (boolean) -> () } }, string)
	local assignedPlace = m.DifficultyPlacesConfig.GetPlaceForPlaceId(game.PlaceId)
	local plan = {}

	if assignedPlace then
		local map = m.MapsConfig.GetMap(assignedPlace.mapId)
		if not map then
			return {}, ("tier %d's map id '%s' isn't in MapsConfig"):format(assignedPlace.tierId, tostring(assignedPlace.mapId))
		end

		table.insert(plan, {
			folderName = map.workspaceFolderName,
			build = function(force: boolean)
				m.LobbyBuilder.Build(map, force or nil, true)
				m.LobbyBuilder.EnsureSpawnsEnabled(map)
			end,
		})
		table.insert(plan, {
			folderName = "Arena",
			build = function(force: boolean)
				m.ArenaBuilder.BuildForMap(map, force or nil)
			end,
		})

		return plan, ("%s (tier %d)"):format(map.displayName, assignedPlace.tierId)
	end

	-- Hub: every map, plus the single shared unthemed arena.
	for _, map in ipairs(m.MapsConfig.MAPS) do
		table.insert(plan, {
			folderName = map.workspaceFolderName,
			build = function(force: boolean)
				m.LobbyBuilder.Build(map, force or nil)
			end,
		})
	end
	table.insert(plan, {
		folderName = "Arena",
		build = function(force: boolean)
			m.ArenaBuilder.Build(force or nil)
		end,
	})

	return plan, "the Hub (all maps + shared arena)"
end

--=========================================================================
-- Build
--=========================================================================

local sessionFingerprint: number? = nil

--[[
	Rebuilds whatever is stale (or everything, when `force`), then stamps
	each rebuilt folder with the current source fingerprint and a fresh
	geometry signature so the next open can tell what changed.

	Returns: didWork, summary
]]
local function performBuild(force: boolean): (boolean, string)
	local m, reason = resolveModules()
	if not m then
		return false, reason or "unavailable"
	end

	local plan, label = planForThisPlace(m)
	if #plan == 0 then
		return false, label
	end

	local fingerprint = computeSourceFingerprint()
	sessionFingerprint = fingerprint

	local rebuilt, skipped = {}, 0

	for _, entry in ipairs(plan) do
		local folder = Workspace:FindFirstChild(entry.folderName)
		local isStale = force or folder == nil

		if not isStale and folder then
			-- Code changed since this folder was built?
			isStale = folder:GetAttribute(ATTR_SOURCE_FINGERPRINT) ~= fingerprint
			-- Hand-edited since this folder was built? (Only meaningful if
			-- it carries a signature at all - geometry from before this
			-- system existed has none, and its fingerprint check already
			-- marked it stale.)
			if not isStale then
				local storedSignature = folder:GetAttribute(ATTR_GEOMETRY_SIGNATURE)
				if storedSignature ~= nil then
					isStale = computeGeometrySignature(folder) ~= storedSignature
				end
			end
		end

		if isStale then
			-- force=true here even for merely-stale folders: the builders'
			-- own MathArenaBuilt check would otherwise skip them, which is
			-- the whole trap this plugin exists to escape.
			entry.build(true)
			local built = Workspace:FindFirstChild(entry.folderName)
			if built then
				built:SetAttribute(ATTR_SOURCE_FINGERPRINT, fingerprint)
				built:SetAttribute(ATTR_GEOMETRY_SIGNATURE, computeGeometrySignature(built))
			end
			table.insert(rebuilt, entry.folderName)
		else
			skipped += 1
		end
	end

	if #rebuilt == 0 then
		return false, ("%s is already up to date (%d folder(s) checked)."):format(label, skipped)
	end

	local skippedNote = ""
	if skipped > 0 then
		skippedNote = (", left %d already-current folder(s) alone"):format(skipped)
	end

	return true, ("%s - rebuilt %s%s."):format(label, table.concat(rebuilt, ", "), skippedNote)
end

--[[
	Runs a build inside one ChangeHistoryService recording, so the whole
	thing is a single Ctrl+Z, and a mid-build error rolls back rather than
	leaving a half-destroyed world.
]]
local function runBuild(force: boolean)
	local recordingName = if force then "MathArena: Rebuild Now" else "MathArena: Auto-Build"
	local recording = ChangeHistoryService:TryBeginRecording(recordingName)

	local ok, didWork, summary = pcall(performBuild, force)

	if not ok then
		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel)
		end
		warn("[MathArenaAutoBuild] Build failed and was rolled back: " .. tostring(didWork))
		return
	end

	if not didWork then
		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel)
		end
		print("[MathArenaAutoBuild] " .. tostring(summary))
		return
	end

	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	print("[MathArenaAutoBuild] " .. tostring(summary) .. " Save or publish this place to keep it.")
end

--=========================================================================
-- Waiting for Rojo to settle, then watching for later changes
--=========================================================================

--[[
	Blocks until the source fingerprint stops moving - our proxy for "Rojo
	has finished its initial sync". Building before this point is what made
	v2 rebuild last-published code and then stamp it as current.

	Returns false if it never settles within the timeout (e.g. something is
	continuously re-syncing), in which case we leave the world alone rather
	than bake in a half-synced tree.
]]
local function waitForSourcesToSettle(): boolean
	local previous, previousCount = computeCheapFingerprint()
	local stableFor = 0
	local waited = 0

	while waited < SETTLE_TIMEOUT do
		task.wait(SETTLE_POLL)
		waited += SETTLE_POLL

		local current, currentCount = computeCheapFingerprint()
		if current == previous and currentCount == previousCount then
			stableFor += SETTLE_POLL
			if stableFor >= SETTLE_SECONDS and currentCount > 0 then
				return true
			end
		else
			stableFor = 0
			previous, previousCount = current, currentCount
		end
	end

	return false
end

--[[
	After the first build, keep fingerprinting. A later change cannot be
	safely rebuilt in this session (Studio's require cache still holds the
	old modules - see bug 1), so instead we CLEAR the stored fingerprint on
	every folder. That guarantees the next place-open sees a mismatch and
	rebuilds from genuinely fresh code, which is precisely "tracked to be
	rebuilt next time, even if never saved".
]]
local function markStaleForNextOpen(why: string)
	local cleared = 0
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:GetAttribute(ATTR_SOURCE_FINGERPRINT) ~= nil then
			child:SetAttribute(ATTR_SOURCE_FINGERPRINT, nil)
			cleared += 1
		end
	end
	if cleared > 0 then
		warn(
			("[MathArenaAutoBuild] %s - marked %d folder(s) to rebuild. Studio caches modules for the life of a session, so reopen this place to rebuild from the new code (Rebuild Now would reuse the cached copies)."):format(
				why,
				cleared
			)
		)
	end
end

local function watchForLaterChanges()
	local debounce: thread? = nil

	local function scheduleCheck()
		if debounce then
			task.cancel(debounce)
		end
		debounce = task.delay(2, function()
			debounce = nil
			local current = computeSourceFingerprint()
			if sessionFingerprint and current ~= sessionFingerprint then
				sessionFingerprint = current
				markStaleForNextOpen("Build code changed after this session's build")
			end
		end)
	end

	for _, root in ipairs(sourceRoots()) do
		root.DescendantAdded:Connect(scheduleCheck)
		root.DescendantRemoving:Connect(scheduleCheck)
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("LuaSourceContainer") then
				local ok, signal = pcall(function()
					return descendant:GetPropertyChangedSignal("Source")
				end)
				if ok and signal then
					signal:Connect(scheduleCheck)
				end
			end
		end
	end
end

--=========================================================================
-- Toolbar
--=========================================================================

local toolbar = plugin:CreateToolbar("MathArena")

local rebuildButton = toolbar:CreateButton(
	"Rebuild Now",
	"Force a full rebuild of this Place's world from the builder code currently loaded in this session.",
	"rbxasset://textures/AnimationEditor/icon_reset.png"
)
rebuildButton.ClickableWhenViewportHidden = true
rebuildButton.Click:Connect(function()
	runBuild(true)
	rebuildButton:SetActive(false)
end)

local autoEnabled = plugin:GetSetting(AUTO_BUILD_SETTING)
if autoEnabled == nil then
	autoEnabled = true
end

local autoButton = toolbar:CreateButton(
	"Auto-Build",
	"When on, this Place rebuilds itself on open whenever the builder code or the built geometry has changed.",
	"rbxasset://textures/AnimationEditor/icon_checkmark.png"
)
autoButton.ClickableWhenViewportHidden = true
autoButton:SetActive(autoEnabled)
autoButton.Click:Connect(function()
	autoEnabled = not autoEnabled
	plugin:SetSetting(AUTO_BUILD_SETTING, autoEnabled)
	autoButton:SetActive(autoEnabled)
	print("[MathArenaAutoBuild] Auto-build " .. (if autoEnabled then "enabled." else "disabled - use Rebuild Now when you want one."))
end)

--=========================================================================
-- Startup
--=========================================================================

task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	if not autoEnabled then
		print("[MathArenaAutoBuild] Auto-build is off for this place. Use Rebuild Now when you want one.")
		return
	end

	if not waitForSourcesToSettle() then
		warn("[MathArenaAutoBuild] Build code never stopped changing (or none is present) - skipping auto-build so a half-synced tree can't be baked in. Press Rebuild Now once Rojo has settled.")
		return
	end

	runBuild(false)
	watchForLaterChanges()
end)
