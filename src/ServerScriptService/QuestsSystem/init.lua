--[[
	QuestsSystem

	Server-authoritative SLOT-based repeatable quest loop ("quest
	offerings that pop up... for simple rewards if accepted"). Entirely
	separate from every other reward system - see QuestsConfig.lua's own
	doc comment for how it differs from the win-based track, the daily
	streak, and the lifetime-progress track.

	There are always exactly 3 slots (QuestsConfig.SLOTS): Standard1,
	Standard2, and Daily - each slot holds ONE currently-assigned quest at
	a time (profile.quests[slotId], DataSystem.lua). A standard slot's
	quest is occasionally a "challenge" quest instead (see QuestsConfig's
	RollQuestForSlot) - purely a matter of which quest got rolled into
	that slot, not a 4th slot.

	Lifecycle per slot:
		1. Not accepted + available now: shown as an offer (AcceptQuest).
		2. Accepted: state.snapshotValue = the quest's metric value AT THIS
		   MOMENT. Progress is always computed as currentMetricValue -
		   snapshotValue, so a player who already has, say, 40 lifetime
		   correct answers doesn't instantly complete a fresh "answer 15
		   correctly" quest the moment they accept it.
		3. Complete (progress >= target): ClaimQuest available.
		4. Claimed: reward granted, a NEW quest is immediately rolled into
		   the slot, but stays hidden/un-offerable until state.nextAvailableAt
		   (standard/challenge: now + a random 2-5 minutes; daily: the next
		   real UTC day boundary) - "refresh once completed every 2-5
		   minutes randomly" / "one daily quest every day".
		5. Rejected (RefreshQuest, standard slots only): while an OFFERED-
		   BUT-NOT-YET-ACCEPTED standard quest is showing, the player can
		   reject it for a different one instead of accepting it - up to
		   REFRESHES_PER_DAY (3) times per slot per real day, no cooldown
		   and no reward either way. Once a slot's 3 daily refreshes are
		   used up, the player has to wait for the next real day for that
		   budget to replenish.

	A background loop (see startReadyNotifyLoop) watches every online
	player's slots and fires "QuestReady" the instant a slot's cooldown
	expires, so the top-of-screen "New Quest Available" banner doesn't
	depend on the client happening to poll at the right moment. That
	banner is purely informational (QuestsUIController.client.lua) - it
	never accepts a quest on the player's behalf; the player must open the
	quest bar themselves and choose Accept/Refresh/Claim.

	Every quest's metric reads an EXISTING profile counter (see
	QuestsConfig) - this module never invents a parallel stat.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local QuestsConfig = require(ReplicatedStorage.Modules.QuestsConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)

local DataSystem = require(ServerScriptService.DataSystem)
local ProgressionSystem = require(ServerScriptService.ProgressionSystem)
local RemoteThrottle = require(ServerScriptService.RemoteThrottle)

local QuestsSystem = {}

local SECONDS_PER_DAY = 86400
local READY_NOTIFY_TICK_SECONDS = 2
local REFRESHES_PER_DAY = 3 -- standard slots only; see RefreshQuest

--[[
	DAILY RESET BOUNDARY.

	The daily quest rolls over at 12:00 (noon) UTC every day, NOT at
	midnight and NOT on a rolling 24-hour timer from when the player last
	touched it. That distinction is the whole point: the reset is a fixed
	wall-clock moment, so it happens whether the player accepted the quest,
	ignored it, dismissed it, claimed it, or was not online at all.

	TIMEZONE. os.time() is UTC on Roblox servers, so this is noon UTC for
	everyone. A per-player local noon would mean the same quest resetting
	at different moments for different players, which makes the countdown
	impossible to state consistently and is not what a "daily" is.
]]
local DAILY_RESET_HOUR_UTC = 12

--[[
	The next noon-UTC boundary strictly after `now`.

	Works off the calendar date rather than arithmetic on the epoch, so it
	stays correct regardless of how os.time() lines up with day boundaries.
	If we are before today's noon, the boundary is today's noon; if we are
	at or past it, it is tomorrow's.
]]
local function nextDailyResetAt(now: number): number
	local parts = os.date("!*t", now)
	local todayNoon = os.time({
		year = parts.year,
		month = parts.month,
		day = parts.day,
		hour = DAILY_RESET_HOUR_UTC,
		min = 0,
		sec = 0,
	})
	if now < todayNoon then
		return todayNoon
	end
	return todayNoon + SECONDS_PER_DAY
end

--[[
	Which daily PERIOD a moment falls in. Two moments share a period id
	only if no noon boundary has passed between them, so comparing a
	stored id against the current one is how the system detects "the daily
	has rolled over since we last looked" without needing a timer.
]]
local function dailyPeriodNumber(unixTime: number): number
	return math.floor((unixTime - DAILY_RESET_HOUR_UTC * 3600) / SECONDS_PER_DAY)
end

QuestsSystem.NextDailyResetAt = nextDailyResetAt
QuestsSystem.DailyPeriodNumber = dailyPeriodNumber

local getQuestsSnapshotFunction = RemoteFunctions.Get("GetQuestsSnapshot")
local acceptQuestFunction = RemoteFunctions.Get("AcceptQuest")
local claimQuestFunction = RemoteFunctions.Get("ClaimQuest")
local cancelQuestFunction = RemoteFunctions.Get("CancelQuest")
local refreshQuestFunction = RemoteFunctions.Get("RefreshQuest")
local dismissQuestFunction = RemoteFunctions.Get("DismissQuest")
local questCompletedEvent = RemoteEvents.Get("QuestCompleted") -- server -> client: an already-accepted quest just became claimable
local questReadyEvent = RemoteEvents.Get("QuestReady") -- server -> client: a slot's cooldown just expired and a new quest is offerable ("New Quest Available" banner)

local function dayNumber(unixTime: number): number
	return math.floor(unixTime / SECONDS_PER_DAY)
end

--[[
	QUEST UNLOCK GATE.

	Quests do not exist for a player until they have finished the
	first-time tutorial - "I want the quests to only pop up after they
	complete the tutorial for the first time". The gate is the persisted
	profile flag (DataSystem.tutorialCompleted, written by TutorialSystem),
	NOT merely having joined a server, so it survives rejoins and server
	hops exactly like every other bit of profile state.

	Read straight off the profile rather than through TutorialSystem to
	avoid a require cycle - TutorialSystem already depends on DataSystem,
	and so does this module.

	False for an unloaded profile, which is the safe direction: a player
	momentarily sees no quests instead of the quest loop running for
	someone who has never done the tutorial.
]]
local function questsUnlocked(player: Player): boolean
	local profile = DataSystem.GetProfile(player)
	return profile ~= nil and profile.tutorialCompleted == true
end


--[[
	Lazily initializes (on first read) and returns the slot state for
	`slotId`. A brand-new slot rolls its first quest immediately and is
	available right away (nextAvailableAt = 0) - notifiedReady starts true
	so the player's very first-ever quest in a slot doesn't spawn a
	"New Quest Available" banner (there's nothing to be notified ABOUT
	yet; only refreshes after a claim should banner).
]]
local function getSlotState(profile: any, slotDef)
	local state = profile.quests[slotDef.slotId]
	if not state then
		local quest, effectiveKind = QuestsConfig.RollQuestForSlot(slotDef)
		state = {
			questId = quest.id,
			effectiveKind = effectiveKind,
			accepted = false,
			snapshotValue = 0,
			nextAvailableAt = 0,
			notifiedReady = true,
			lastDayNumber = nil,
			refreshesUsed = 0,
			refreshDayNumber = dayNumber(os.time()),
			-- Which noon-to-noon period this daily quest belongs to. Compared
			-- against the current period on every read to detect rollover.
			dailyPeriod = dailyPeriodNumber(os.time()),
		}
		profile.quests[slotDef.slotId] = state
	end

	--[[
		DAILY ROLLOVER, ENFORCED ON READ.

		Checked here rather than on a timer so it is impossible to miss: any
		path that touches the slot - opening the quest log, progress being
		recorded, the ready-notify loop - re-evaluates it. That is what makes
		the reset happen regardless of what the player did with the quest, and
		it also covers a player who was offline across the boundary, since
		their first read after rejoining sees a stale period.

		Rolling over discards whatever was in the slot - accepted or not,
		partially progressed or not - and rolls a fresh quest that is
		immediately available. An unclaimed completed daily is forfeited,
		which is the intended meaning of a daily deadline.
	]]
	if slotDef.kind == "daily" then
		local period = dailyPeriodNumber(os.time())
		if state.dailyPeriod ~= period then
			local quest, effectiveKind = QuestsConfig.RollQuestForSlot(slotDef)
			state.questId = quest.id
			state.effectiveKind = effectiveKind
			state.accepted = false
			state.snapshotValue = 0
			state.nextAvailableAt = 0 -- offerable straight away at the boundary
			state.notifiedReady = false -- banner the new daily once
			state.dailyPeriod = period
		end
	end
	-- Old-format saved slot states (from before the refresh feature) won't have these fields - default them in-place rather than requiring a migration pass.
	if state.refreshesUsed == nil then
		state.refreshesUsed = 0
		state.refreshDayNumber = dayNumber(os.time())
	end
	return state
end

local function isAvailableNow(state): boolean
	return os.time() >= state.nextAvailableAt
end

--[[
	Resets `state`'s daily refresh budget (refreshesUsed) to 0 if the real
	day has moved on since it was last used/reset - the wait after
	exhausting all 3 refreshes is simply "until tomorrow". Called before
	every read/use of refreshesUsed so the budget is always current.
]]
local function reconcileRefreshBudget(state)
	local today = dayNumber(os.time())
	if state.refreshDayNumber ~= today then
		state.refreshDayNumber = today
		state.refreshesUsed = 0
	end
end

--[[
	Builds the full quest snapshot for the compact quest box: every
	slot's current quest (title/description/reward label/kind), whether
	it's currently accepted, its progress, whether it can be claimed, and
	- if it's on cooldown - how many seconds remain until the next quest
	is offerable. Returns an empty list only if the player has no loaded
	profile.
]]
function QuestsSystem.BuildSnapshot(player: Player)
	local profile = DataSystem.GetProfile(player)
	if not profile then
		return {}
	end

	local snapshot = {}
	for _, slotDef in ipairs(QuestsConfig.SLOTS) do
		local state = getSlotState(profile, slotDef)
		local quest = QuestsConfig.GetQuestById(state.questId)
		if quest then
			local available = isAvailableNow(state)
			local progress = if state.accepted then math.max(0, quest.metric(profile) - state.snapshotValue) else 0
			reconcileRefreshBudget(state)
			table.insert(snapshot, {
				slotId = slotDef.slotId,
				slotKind = slotDef.kind, -- the slot's base kind ("standard"/"daily") - drives layout/position
				kind = state.effectiveKind, -- what's ACTUALLY assigned right now ("standard"/"daily"/"challenge") - drives color/label
				questId = quest.id,
				title = quest.title,
				description = quest.description,
				rewardLabel = quest.rewardLabel,
				target = quest.target,
				accepted = state.accepted,
				progress = math.min(progress, quest.target),
				canClaim = state.accepted and progress >= quest.target,
				available = available,
				secondsUntilAvailable = math.max(0, state.nextAvailableAt - os.time()),
				--[[
					DAILY COUNTDOWN. Seconds until the next noon-UTC reset, sent
					for the daily slot only (nil elsewhere, so the UI can tell the
					two cases apart).

					This is deliberately NOT the same number as
					secondsUntilAvailable. That one counts down a per-slot
					cooldown; this counts down to a fixed wall-clock moment and
					keeps ticking regardless of whether the quest is offered,
					accepted, completed or claimed - which is exactly what the
					player needs to see on a daily.
				]]
				secondsUntilDailyReset = if slotDef.kind == "daily"
					then math.max(0, nextDailyResetAt(os.time()) - os.time())
					else nil,
				refreshesRemaining = if slotDef.kind == "standard" then math.max(0, REFRESHES_PER_DAY - state.refreshesUsed) else nil,
				refreshesPerDay = if slotDef.kind == "standard" then REFRESHES_PER_DAY else nil,
			})
		end
	end
	return snapshot
end

--[[
	Accepts the current quest in `slotId` for `player` - snapshots the
	quest's metric value NOW so only future progress counts. Returns true
	on success, or (false, reason) - "UnknownSlot", "NoProfile",
	"NotAvailable" (still on cooldown), or "AlreadyAccepted".
]]
function QuestsSystem.AcceptQuest(player: Player, slotId: string): (boolean, string?)
	local slotDef = QuestsConfig.GetSlot(slotId)
	if not slotDef then
		return false, "UnknownSlot"
	end

	local profile = DataSystem.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end

	local state = getSlotState(profile, slotDef)
	if not isAvailableNow(state) then
		return false, "NotAvailable"
	end
	if state.accepted then
		return false, "AlreadyAccepted"
	end

	local quest = QuestsConfig.GetQuestById(state.questId)
	if not quest then
		return false, "UnknownSlot"
	end

	state.accepted = true
	state.snapshotValue = quest.metric(profile)
	return true
end

--[[
	Cancels the currently-ACCEPTED quest in `slotId` for `player`,
	abandoning its progress. Deliberately does NOT start a cooldown or
	reroll the quest - the exact same quest becomes immediately
	acceptable again, since only a CLAIM should trigger the 2-5 minute (or
	one-per-day) refresh. Returns true on success, or (false, reason) -
	"UnknownSlot", "NoProfile", or "NotAccepted".
]]
function QuestsSystem.CancelQuest(player: Player, slotId: string): (boolean, string?)
	local slotDef = QuestsConfig.GetSlot(slotId)
	if not slotDef then
		return false, "UnknownSlot"
	end

	local profile = DataSystem.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end

	local state = getSlotState(profile, slotDef)
	if not state.accepted then
		return false, "NotAccepted"
	end

	state.accepted = false
	state.snapshotValue = 0
	return true
end

--[[
	Claims the completed quest in `slotId` for `player`. Returns true on
	success, or (false, reason) - "UnknownSlot", "NoProfile",
	"NotAccepted", or "NotComplete". On success: grants the reward,
	immediately rolls a NEW quest into the slot, and sets that slot's
	cooldown (2-5 random minutes for standard/challenge slots, the next
	UTC day boundary for the daily slot) - the new quest stays hidden
	until the cooldown expires (see the ready-notify loop below).
]]
function QuestsSystem.ClaimQuest(player: Player, slotId: string): (boolean, string?)
	local slotDef = QuestsConfig.GetSlot(slotId)
	if not slotDef then
		return false, "UnknownSlot"
	end

	local profile = DataSystem.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end

	local state = getSlotState(profile, slotDef)
	if not state.accepted then
		return false, "NotAccepted"
	end

	local quest = QuestsConfig.GetQuestById(state.questId)
	if not quest then
		return false, "UnknownSlot"
	end

	local progress = quest.metric(profile) - state.snapshotValue
	if progress < quest.target then
		return false, "NotComplete"
	end

	-- Reset/reroll FIRST, before any further (non-yielding) work below -
	-- same duplicate-claim safety pattern used by every other reward
	-- system in this project - so a rapid double-click can't grant the
	-- reward twice.
	local now = os.time()
	local newQuest, newKind = QuestsConfig.RollQuestForSlot(slotDef)
	state.questId = newQuest.id
	state.effectiveKind = newKind
	state.accepted = false
	state.snapshotValue = 0
	state.notifiedReady = false
	if slotDef.kind == "daily" then
		state.lastDayNumber = dayNumber(now)
		-- Claiming the daily does NOT open a 2-5 minute cooldown like the
		-- standard slots. The next daily arrives at the next noon-UTC reset
		-- and not a moment sooner, however early in the period it was
		-- claimed. getSlotState's rollover check is what actually swaps the
		-- quest in; this just keeps the slot closed until then.
		state.nextAvailableAt = nextDailyResetAt(now)
	else
		state.nextAvailableAt = now
			+ math.random(QuestsConfig.STANDARD_REFRESH_MIN_SECONDS, QuestsConfig.STANDARD_REFRESH_MAX_SECONDS)
	end

	if quest.coins then
		ProgressionSystem.AwardCoins(player, quest.coins)
	end
	if quest.gems then
		ProgressionSystem.AwardGems(player, quest.gems)
	end

	return true
end

--[[
	Rejects the current OFFERED (not-yet-accepted) quest in `slotId` for
	`player`, immediately rolling a different one into the same slot - no
	cooldown, no reward, just a fresh option. Standard slots only, capped
	at REFRESHES_PER_DAY (3) uses per slot per real day. Returns true on
	success, or (false, reason) - "UnknownSlot", "NotEligible" (Daily
	doesn't get refreshes), "NoProfile", "NotAvailable", "AlreadyAccepted",
	or "RefreshLimitReached".
]]
function QuestsSystem.RefreshQuest(player: Player, slotId: string): (boolean, string?)
	local slotDef = QuestsConfig.GetSlot(slotId)
	if not slotDef then
		return false, "UnknownSlot"
	end
	if slotDef.kind ~= "standard" then
		return false, "NotEligible"
	end

	local profile = DataSystem.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end

	local state = getSlotState(profile, slotDef)
	if not isAvailableNow(state) then
		return false, "NotAvailable"
	end
	if state.accepted then
		return false, "AlreadyAccepted"
	end

	reconcileRefreshBudget(state)
	if state.refreshesUsed >= REFRESHES_PER_DAY then
		return false, "RefreshLimitReached"
	end

	state.refreshesUsed += 1
	local newQuest, newKind = QuestsConfig.RollQuestForSlot(slotDef)
	state.questId = newQuest.id
	state.effectiveKind = newKind
	return true
end

--[[
	Dismisses (rejects, via the quest card's X button) the current OFFERED
	(not-yet-accepted) quest in `slotId` for `player`, BEFORE it's ever
	accepted - distinct from CancelQuest (which abandons an ALREADY-
	ACCEPTED quest's progress with no cooldown) and from RefreshQuest
	(which also rejects an offered quest, but instantly and only up to
	REFRESHES_PER_DAY times). Dismissing immediately rerolls a new quest
	into the slot - exactly like a claim does - and puts the slot on the
	SAME 2-5 minute randomized cooldown standard/challenge claims use
	(QuestsConfig.STANDARD_REFRESH_MIN/MAX_SECONDS), regardless of the
	slot's kind - including the Daily slot, which otherwise only ever
	refreshes on the next UTC day boundary; a deliberately-dismissed Daily
	quest gets the same short 2-5 minute wait as everything else, not a
	full extra day.

	Does NOT touch refreshesUsed/REFRESHES_PER_DAY at all - the dismiss
	cooldown is its own throttle (you simply can't dismiss again until it
	expires), entirely separate from and in addition to the existing
	standard-slot refresh-limit system above, which this function leaves
	untouched.

	Persists exactly like every other slot mutation here: written straight
	into `profile.quests[slotId]` (nextAvailableAt as an absolute os.time()
	unix timestamp), so it survives a disconnect/rejoin or a server change
	the same way a claim's or refresh's cooldown already does - nothing
	additional to persist.

	Returns true on success, or (false, reason) - "UnknownSlot",
	"NoProfile", "NotAvailable" (already on cooldown - nothing offered to
	dismiss), or "AlreadyAccepted" (use CancelQuest instead).
]]
function QuestsSystem.DismissQuest(player: Player, slotId: string): (boolean, string?)
	local slotDef = QuestsConfig.GetSlot(slotId)
	if not slotDef then
		return false, "UnknownSlot"
	end

	local profile = DataSystem.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end

	local state = getSlotState(profile, slotDef)
	if not isAvailableNow(state) then
		return false, "NotAvailable"
	end
	if state.accepted then
		return false, "AlreadyAccepted"
	end

	local newQuest, newKind = QuestsConfig.RollQuestForSlot(slotDef)
	state.questId = newQuest.id
	state.effectiveKind = newKind
	state.accepted = false
	state.snapshotValue = 0
	state.notifiedReady = false
	if slotDef.kind == "daily" then
		--[[
			Dismissing the daily does not hand out a replacement early. The
			slot closes until the next noon reset, the same as claiming it.

			Without this the daily inherited the standard slots' 2-5 minute
			reroll, so a player could dismiss it repeatedly and pull a fresh
			daily every few minutes - which defeats the point of a daily and
			is exactly the behaviour the brief asked to remove.
		]]
		state.nextAvailableAt = nextDailyResetAt(os.time())
	else
		state.nextAvailableAt = os.time()
			+ math.random(QuestsConfig.STANDARD_REFRESH_MIN_SECONDS, QuestsConfig.STANDARD_REFRESH_MAX_SECONDS)
	end

	return true
end

--[[
	Checks every ACCEPTED quest for `player` against its current progress
	and fires "QuestCompleted" for any that just became claimable, so the
	compact quest box can highlight it immediately rather than waiting for
	the next snapshot poll. Call this after anything that could move a
	quest metric (a correct answer, a win) - safe to call redundantly,
	since it only ever notifies, never mutates state itself.
]]
function QuestsSystem.CheckForNewlyCompleted(player: Player)
	local profile = DataSystem.GetProfile(player)
	if not profile then
		return
	end

	for _, slotDef in ipairs(QuestsConfig.SLOTS) do
		local state = getSlotState(profile, slotDef)
		if state.accepted then
			local quest = QuestsConfig.GetQuestById(state.questId)
			if quest then
				local progress = quest.metric(profile) - state.snapshotValue
				if progress >= quest.target then
					questCompletedEvent:FireClient(player, { slotId = slotDef.slotId, title = quest.title })
				end
			end
		end
	end
end

--[[
	Background loop: every READY_NOTIFY_TICK_SECONDS, checks every
	currently-online player's slots for one whose cooldown just expired
	(available now, not yet notified) and fires "QuestReady" exactly once
	for it - the top-of-screen "New Quest Available" banner
	(QuestsUIController.client.lua). Purely informational: the client
	never auto-accepts from this - the player has to open the quest bar
	themselves. Deliberately independent of any gameplay event, since a
	slot becoming available is purely time-based, not triggered by
	anything the player does.
]]
local function startReadyNotifyLoop()
	task.spawn(function()
		while true do
			task.wait(READY_NOTIFY_TICK_SECONDS)
			for _, player in ipairs(Players:GetPlayers()) do
				-- Never surface a "New Quest Available" banner to a player who
				-- has not finished the first-time tutorial. Deliberately checked
				-- BEFORE getSlotState, which lazily rolls a slot's first quest -
				-- so a locked player's slots are not even initialised yet, and
				-- their first quests roll fresh once they finish the tutorial.
				local profile = if questsUnlocked(player) then DataSystem.GetProfile(player) else nil
				if profile then
					for _, slotDef in ipairs(QuestsConfig.SLOTS) do
						local state = getSlotState(profile, slotDef)
						if not state.accepted and not state.notifiedReady and isAvailableNow(state) then
							state.notifiedReady = true
							local quest = QuestsConfig.GetQuestById(state.questId)
							if quest then
								questReadyEvent:FireClient(player, {
									slotId = slotDef.slotId,
									kind = state.effectiveKind,
									title = quest.title,
								})
							end
						end
					end
				end
			end
		end
	end)
end

function QuestsSystem.Init()
	getQuestsSnapshotFunction.OnServerInvoke = function(player: Player)
		-- Locked until the first-time tutorial is done. Returning an explicit
		-- `locked` snapshot (rather than an empty one) lets the client hide
		-- the quest box outright instead of rendering three empty slots.
		if not questsUnlocked(player) then
			return { locked = true, slots = {} }
		end
		return QuestsSystem.BuildSnapshot(player)
	end

	acceptQuestFunction.OnServerInvoke = function(player: Player, slotId: unknown)
		if typeof(slotId) ~= "string" then
			return { success = false, reason = "InvalidRequest" }
		end
		-- Server-authoritative unlock check: a client that somehow fires this
		-- before finishing the tutorial cannot start the quest loop early.
		if not questsUnlocked(player) then
			return { success = false, reason = "TutorialIncomplete" }
		end
		if not RemoteThrottle.Check(player, "AcceptQuest", 0.5) then
			return { success = false, reason = "TooManyRequests" }
		end
		local ok, reason = QuestsSystem.AcceptQuest(player, slotId)
		return { success = ok, reason = reason }
	end

	claimQuestFunction.OnServerInvoke = function(player: Player, slotId: unknown)
		if typeof(slotId) ~= "string" then
			return { success = false, reason = "InvalidRequest" }
		end
		if not RemoteThrottle.Check(player, "ClaimQuest", 0.5) then
			return { success = false, reason = "TooManyRequests" }
		end
		local ok, reason = QuestsSystem.ClaimQuest(player, slotId)
		return { success = ok, reason = reason }
	end

	cancelQuestFunction.OnServerInvoke = function(player: Player, slotId: unknown)
		if typeof(slotId) ~= "string" then
			return { success = false, reason = "InvalidRequest" }
		end
		if not RemoteThrottle.Check(player, "CancelQuest", 0.5) then
			return { success = false, reason = "TooManyRequests" }
		end
		local ok, reason = QuestsSystem.CancelQuest(player, slotId)
		return { success = ok, reason = reason }
	end

	refreshQuestFunction.OnServerInvoke = function(player: Player, slotId: unknown)
		if typeof(slotId) ~= "string" then
			return { success = false, reason = "InvalidRequest" }
		end
		if not RemoteThrottle.Check(player, "RefreshQuest", 0.5) then
			return { success = false, reason = "TooManyRequests" }
		end
		local ok, reason = QuestsSystem.RefreshQuest(player, slotId)
		return { success = ok, reason = reason }
	end

	dismissQuestFunction.OnServerInvoke = function(player: Player, slotId: unknown)
		if typeof(slotId) ~= "string" then
			return { success = false, reason = "InvalidRequest" }
		end
		if not RemoteThrottle.Check(player, "DismissQuest", 0.5) then
			return { success = false, reason = "TooManyRequests" }
		end
		local ok, reason = QuestsSystem.DismissQuest(player, slotId)
		return { success = ok, reason = reason }
	end

	startReadyNotifyLoop()

	print("[QuestsSystem] Initialized")
end

return QuestsSystem
