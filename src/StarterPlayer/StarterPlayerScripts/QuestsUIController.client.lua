--[[
	QuestsUIController.client.lua

	The compact quest box - "quest offerings that pop up on the middle
	left side of the screen in a small box that can be completed for
	simple rewards if accepted". Backed by QuestsSystem (server); this
	script only displays whatever GetQuestsSnapshot returns and forwards
	Accept/Claim/Refresh/Cancel requests - the server re-validates
	everything (see QuestsSystem.lua's own doc comment on why a repeatable
	quest can't be double-claimed).

	Three fixed slot cards (Standard1, Standard2, Daily - QuestsConfig.
	SLOTS), each capable of showing a "standard", "daily", or occasional
	"challenge" quest depending on what the server currently has rolled
	into that slot. A slot on cooldown shows a live, client-side-ticking
	countdown ("Next quest in..." / "Come back tomorrow for new quests"
	for the daily slot) computed from the server's secondsUntilAvailable
	plus locally-elapsed time, so it counts down smoothly between polls
	rather than only updating once every 5 seconds - all derived from the
	server's own absolute unix-time bookkeeping (QuestsSystem's
	nextAvailableAt/refreshDayNumber), so it stays correct across a
	reconnect, a server restart, or any other interruption; nothing here
	is a source of truth, only a live-ticking display of it.

	While a standard slot's quest is offered-but-not-accepted, a large,
	clearly-visible reload-style REFRESH button plus a bold "x/3" counter
	lets the player reject it for a different one (up to 3x/day - see
	QuestsSystem.RefreshQuest); once accepted, a small CANCEL button lets
	them abandon progress without a cooldown. The panel is sized generously
	(EXPANDED_WIDTH/HEIGHT below) specifically so this cluster, the title/
	reward row, the description, and the progress bar each get their own
	row with real margins - nothing in this panel is meant to ever overlap
	at the panel's own native size.

	Fully manual: nothing here ever accepts/claims/refreshes a quest on
	its own. A slot's cooldown expiring only ever drives a purely
	informational "New Quest Available" banner that slides in from the
	LEFT edge of the screen and disappears shortly after - fired ONLY when
	a slot that was genuinely empty/on-cooldown becomes offerable again
	(QuestsSystem's "QuestReady" event, itself only ever fired once per
	cooldown cycle - never on a plain UI open, a snapshot refresh, or a
	reconnect where nothing actually changed). The player must open this
	quest box themselves and press Accept/Refresh/Claim.

	Collapse/close behavior: the whole box can ALWAYS be collapsed via its
	header toggle - the toggle button and setCollapsed() below never check
	any quest's accepted/claimable state, on purpose ("you have to accept
	before you're able to exit out" was reported as a bug - closing must
	never depend on anything being accepted first). Collapsed, it squeezes
	flush against the LEFT edge of the screen as a slim vertical rail (a
	rotated "QUESTS" label + the toggle), rather than just shrinking in
	place - expanding it slides it back out with the full card list.

	Visible whenever the player isn't actively in a match (same rule the
	lobby button bar uses: Lobby or Waiting) - hidden once a match
	actually starts, so it doesn't compete for attention with the arena
	screen during real gameplay.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MatchConfig = require(ReplicatedStorage.Modules.MatchConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
local UITheme = require(ReplicatedStorage.Modules.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")

local getQuestsSnapshotFunction = RemoteFunctions.Get("GetQuestsSnapshot")
local acceptQuestFunction = RemoteFunctions.Get("AcceptQuest")
local claimQuestFunction = RemoteFunctions.Get("ClaimQuest")
local cancelQuestFunction = RemoteFunctions.Get("CancelQuest")
local refreshQuestFunction = RemoteFunctions.Get("RefreshQuest")
local dismissQuestFunction = RemoteFunctions.Get("DismissQuest")

local KIND_COLORS = {
	standard = UITheme.COLORS.Accent,
	daily = UITheme.COLORS.Gold,
	challenge = Color3.fromRGB(230, 90, 200),
}
local KIND_LABELS = {
	standard = "QUEST",
	daily = "DAILY QUEST",
	challenge = "CHALLENGE QUEST",
}

-- ===== Compact box shell =====

-- Sized generously (wider AND noticeably taller than the original box) so
-- every card fits its title/reward row, description, refresh cluster,
-- progress bar, and action button on its own clearly-separated row with
-- real margins - see the per-card layout below for the exact row plan.
-- Kept intentionally a bit taller/roomier than a strictly-minimal fit so
-- the whole thing reads as less cramped at a glance, without removing or
-- shrinking any existing element.
local EXPANDED_WIDTH = 330
local EXPANDED_HEIGHT = 600
-- Collapsed rail ( = the compact "pop-up" that's left on-screen once the
-- quest box is closed): bumped up from the original 44x220 - "slightly
-- bigger, easier to see" - while staying a slim rail flush against the
-- LEFT edge, well clear of every other left-anchored piece of UI
-- (LobbyUIController's button bar, etc. all sit lower/centered, not
-- against this same edge), so the extra size can't overlap anything.
local COLLAPSED_WIDTH = 56
local COLLAPSED_HEIGHT = 260
local CARD_HEIGHT = 168

local EXPANDED_POSITION = UDim2.new(0, 24, 0.5, -EXPANDED_HEIGHT / 2)
local COLLAPSED_POSITION = UDim2.new(0, 0, 0.5, -COLLAPSED_HEIGHT / 2) -- flush against the screen's left edge

--[[
	QUEST UNLOCK GATE (client half).

	The authoritative gate is server-side (QuestsSystem returns a `locked`
	snapshot and never fires QuestReady until the first-time tutorial is
	done). This mirror exists purely so the box and its banner are hidden
	INSTANTLY on join, rather than flickering into view for the moment
	between the box being built and the first snapshot coming back.

	Declared HERE, above every use, rather than beside setBoxVisible far
	below: the QuestReady handler reads it hundreds of lines earlier, and a
	local declared after that point would be read as a nil GLOBAL there,
	which would silently suppress every quest banner forever.
]]
local questsUnlocked = false

local questBox = Instance.new("Frame")
questBox.Name = "QuestBox"
questBox.Size = UDim2.fromOffset(EXPANDED_WIDTH, EXPANDED_HEIGHT)
questBox.Position = EXPANDED_POSITION
questBox.ClipsDescendants = true
questBox.Visible = false
UITheme.StylePanel(questBox, 0.1)
questBox.Parent = mainUI

local questBoxTitle = Instance.new("TextLabel")
questBoxTitle.Name = "Title"
questBoxTitle.Size = UDim2.new(1, -48, 0, 28)
questBoxTitle.Position = UDim2.fromOffset(8, 8)
questBoxTitle.BackgroundTransparency = 1
questBoxTitle.Font = Enum.Font.GothamBlack
questBoxTitle.TextScaled = true
questBoxTitle.TextXAlignment = Enum.TextXAlignment.Left
questBoxTitle.TextColor3 = UITheme.COLORS.Accent
questBoxTitle.Text = "Quests"
questBoxTitle.Parent = questBox

-- Shown only while collapsed: a vertical "QUESTS" label running the
-- height of the slim rail, so the collapsed strip still reads as
-- something rather than a blank sliver against the screen edge.
local verticalTitle = Instance.new("TextLabel")
verticalTitle.Name = "VerticalTitle"
verticalTitle.AnchorPoint = Vector2.new(0.5, 0.5)
verticalTitle.Size = UDim2.fromOffset(COLLAPSED_HEIGHT - 60, 24)
verticalTitle.Position = UDim2.new(0.5, 0, 0.5, 10)
verticalTitle.Rotation = -90
verticalTitle.BackgroundTransparency = 1
verticalTitle.Font = Enum.Font.GothamBlack
verticalTitle.TextScaled = true
verticalTitle.TextColor3 = UITheme.COLORS.Accent
verticalTitle.Text = "QUESTS"
verticalTitle.Visible = false
verticalTitle.Parent = questBox

-- Quest log open/close toggle - collapses down to a slim vertical rail
-- flush with the screen edge.
local collapseButton = Instance.new("TextButton")
collapseButton.Name = "CollapseButton"
collapseButton.AnchorPoint = Vector2.new(0.5, 0)
collapseButton.Size = UDim2.fromOffset(34, 34) -- slightly bigger to match the enlarged collapsed rail, easier to tap/see
collapseButton.Position = UDim2.new(0.5, 0, 0, 10)
collapseButton.Font = Enum.Font.GothamBold
collapseButton.TextScaled = true
collapseButton.Text = "-"
collapseButton.TextColor3 = UITheme.COLORS.Text
collapseButton.BackgroundColor3 = UITheme.COLORS.Panel
UITheme.ApplyCorner(collapseButton)
UITheme.ApplyButtonHoverEffect(collapseButton)
collapseButton.Parent = questBox

local questList = Instance.new("Frame")
questList.Name = "QuestList"
questList.Size = UDim2.new(1, -16, 1, -44)
questList.Position = UDim2.fromOffset(8, 40)
questList.BackgroundTransparency = 1
questList.Parent = questBox

local questListLayout = Instance.new("UIListLayout")
questListLayout.SortOrder = Enum.SortOrder.LayoutOrder
questListLayout.Padding = UDim.new(0, 12)
questListLayout.Parent = questList

local collapsed = false
local collapseTween: Tween? = nil

local function setCollapsed(newCollapsed: boolean, animate: boolean)
	collapsed = newCollapsed
	collapseButton.Text = if collapsed then "+" else "-"

	questBoxTitle.Visible = not collapsed
	verticalTitle.Visible = collapsed
	if not collapsed then
		questList.Visible = true
	end

	local targetSize = UDim2.fromOffset(if collapsed then COLLAPSED_WIDTH else EXPANDED_WIDTH, if collapsed then COLLAPSED_HEIGHT else EXPANDED_HEIGHT)
	local targetPosition = if collapsed then COLLAPSED_POSITION else EXPANDED_POSITION

	if collapseTween then
		collapseTween:Cancel()
	end

	if not animate then
		questBox.Size = targetSize
		questBox.Position = targetPosition
		questList.Visible = not collapsed
		return
	end

	if collapsed then
		questList.Visible = false -- hide immediately so text doesn't smear across the narrowing rail
	end

	collapseTween = TweenService:Create(
		questBox,
		TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = targetSize, Position = targetPosition }
	)
	collapseTween:Play()
end

setCollapsed(false, false)

collapseButton.MouseButton1Click:Connect(function()
	setCollapsed(not collapsed, true)
end)

-- Fixed cards, one per QuestsConfig slot (built once; only their content
-- updates on refresh). The Daily slot gets its own small divider label
-- (visually distinct) instead of just being a 3rd identical card.
--
-- Per-card row plan (card width = questList width, ~304px at
-- EXPANDED_WIDTH=320) - every row gets its own y-band with margin, so
-- nothing here can overlap regardless of which state (offered/accepted/
-- claimable/on cooldown) a card is currently showing:
--   y=4-16   kindLabel (left) / cancelButton (top-right corner, accepted only)
--   y=18-38  titleLabel (left, ~62% width) / rewardLabel (right, ~34% width)
--   y=40-56  descriptionLabel (full width)
--   y=60-90  refreshButton + refreshCountLabel (offered+refreshable only)
--            OR cooldownLabel (on cooldown only) - mutually exclusive
--   y=92-108 progress bar (left, ~70% width) / progressLabel (right, ~26%)
--   y=110-132 actionButton (full width)
local SLOT_ORDER = { "Standard1", "Standard2", "Daily" }
local questCards: { [string]: any } = {}

for index, slotId in ipairs(SLOT_ORDER) do
	if slotId == "Daily" then
		local divider = Instance.new("TextLabel")
		divider.Name = "DailyDivider"
		divider.LayoutOrder = index * 10 - 1
		divider.Size = UDim2.new(1, 0, 0, 16)
		divider.BackgroundTransparency = 1
		divider.Font = Enum.Font.GothamBold
		divider.TextSize = 11
		divider.TextXAlignment = Enum.TextXAlignment.Left
		divider.TextColor3 = UITheme.COLORS.Gold
		divider.Text = "\u{2666} DAILY QUEST"
		divider.Parent = questList
	end

	local card = Instance.new("Frame")
	card.Name = "Card_" .. slotId
	card.LayoutOrder = index * 10
	card.Size = UDim2.new(1, 0, 0, CARD_HEIGHT)
	card.BackgroundColor3 = UITheme.COLORS.Panel
	card.Visible = false
	UITheme.ApplyCorner(card)
	card.Parent = questList

	local kindStripe = Instance.new("Frame")
	kindStripe.Name = "KindStripe"
	kindStripe.Size = UDim2.new(0, 4, 1, 0)
	kindStripe.BackgroundColor3 = UITheme.COLORS.Accent
	UITheme.ApplyCorner(kindStripe)
	kindStripe.Parent = card

	local kindLabel = Instance.new("TextLabel")
	kindLabel.Name = "KindLabel"
	kindLabel.Size = UDim2.new(1, -140, 0, 14)
	kindLabel.Position = UDim2.fromOffset(12, 6)
	kindLabel.BackgroundTransparency = 1
	kindLabel.Font = Enum.Font.GothamBold
	kindLabel.TextSize = 11
	kindLabel.TextXAlignment = Enum.TextXAlignment.Left
	kindLabel.TextColor3 = UITheme.COLORS.Accent
	kindLabel.Text = "QUEST"
	kindLabel.Parent = card

	-- Small cancel button, only shown while a quest is ACCEPTED (abandons
	-- progress, no cooldown).
	local cancelButton = Instance.new("TextButton")
	cancelButton.Name = "CancelButton"
	cancelButton.Size = UDim2.fromOffset(24, 24)
	cancelButton.Position = UDim2.new(1, -32, 0, 6)
	cancelButton.Font = Enum.Font.GothamBold
	cancelButton.TextScaled = true
	cancelButton.Text = "X"
	cancelButton.TextColor3 = UITheme.COLORS.Text
	cancelButton.BackgroundColor3 = UITheme.COLORS.Error
	cancelButton.Visible = false
	UITheme.ApplyCorner(cancelButton)
	UITheme.ApplyButtonHoverEffect(cancelButton)
	cancelButton.Parent = card

	-- Dismiss button - the same top-right "X" corner spot as CancelButton
	-- above, but for the OPPOSITE state: a quest that's currently OFFERED
	-- (not yet accepted). Mutually exclusive with CancelButton (a quest is
	-- never simultaneously offered and accepted), so sharing the same
	-- corner never overlaps anything. Rejecting here rerolls a new quest
	-- into this slot and starts the same 2-5 minute cooldown a claim uses
	-- (QuestsSystem.DismissQuest) - unlike RefreshQuest's reload button
	-- (instant, capped at 3/day), this has no daily cap of its own; the
	-- cooldown itself is the throttle. Available on every slot, including
	-- Daily.
	local dismissButton = Instance.new("TextButton")
	dismissButton.Name = "DismissButton"
	dismissButton.Size = UDim2.fromOffset(24, 24)
	dismissButton.Position = UDim2.new(1, -32, 0, 6)
	dismissButton.Font = Enum.Font.GothamBold
	dismissButton.TextScaled = true
	dismissButton.Text = "X"
	dismissButton.TextColor3 = UITheme.COLORS.Text
	dismissButton.BackgroundColor3 = UITheme.COLORS.Error
	dismissButton.Visible = false
	UITheme.ApplyCorner(dismissButton)
	UITheme.ApplyButtonHoverEffect(dismissButton)
	dismissButton.Parent = card

	--[[
		Title/reward split rebalanced from 60/40 to 55/45, with both font
		sizes eased one step.

		The reward label used to truncate: the daily quest's "100 Coins + 20
		Gems" did not fit its 111px box and rendered ellipsised, hiding the
		Gems half of the reward entirely.

		A first attempt moved the split to 52/48 on the basis of two sampled
		titles ("Quick Thinker" 104px, "Daily Marathon" 112px) - and broke
		the LONGEST title, "Practice Makes Perfect", which then truncated in
		its own box. Sampling two of three cards was not enough.

		So width alone cannot satisfy both: the longest title needs ~175px at
		17pt and the longest reward ~130px at 13pt, which is 305px on a card
		only 306px wide before padding. Easing the title to 15pt and the
		reward to 12pt brings their requirements to ~150px and ~120px, which
		the 55/45 split covers with slack on both sides.
	]]
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(0.55, -12, 0, 24)
	titleLabel.Position = UDim2.fromOffset(12, 24)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 15
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = UITheme.COLORS.Text
	titleLabel.Text = ""
	titleLabel.Parent = card

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "RewardLabel"
	rewardLabel.Size = UDim2.new(0.45, -12, 0, 24)
	rewardLabel.Position = UDim2.new(0.55, 0, 0, 24)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Font = Enum.Font.GothamBold
	rewardLabel.TextSize = 12
	rewardLabel.TextTruncate = Enum.TextTruncate.AtEnd
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Right
	rewardLabel.TextColor3 = UITheme.COLORS.Gold
	rewardLabel.Text = ""
	rewardLabel.Parent = card

	--[[
		Two-line, wrapped description.

		This was a single 18px-tall line at TextSize 13 with
		TextTruncate.AtEnd, which meant longer quests were silently
		ellipsised mid-sentence - "Answer 40 questions correctly today
		(competitive or practice)." rendered as "Answer 40 questions
		correctly to...", so the player could not read what the quest
		actually required. Two of the three visible cards were truncating.

		One line cannot hold these strings at any readable size (the longest
		runs ~400px at 13pt against a 282px box, and still overflows at
		11pt), so it has to wrap. TextSize eases to 11 and the box grows to
		26px, which is exactly two lines - and bottoms out at ~75px, just
		clear of the refresh cluster that starts at 75.9px. TextTruncate is
		kept as a safety net for any future quest string longer still.
	]]
	local descriptionLabel = Instance.new("TextLabel")
	descriptionLabel.Name = "DescriptionLabel"
	descriptionLabel.Size = UDim2.new(1, -24, 0, 26)
	descriptionLabel.Position = UDim2.fromOffset(12, 48)
	descriptionLabel.BackgroundTransparency = 1
	descriptionLabel.Font = Enum.Font.Gotham
	descriptionLabel.TextSize = 11
	descriptionLabel.TextWrapped = true
	descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
	descriptionLabel.TextTruncate = Enum.TextTruncate.AtEnd
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.TextColor3 = UITheme.COLORS.SubText
	descriptionLabel.Text = ""
	descriptionLabel.Parent = card

	-- Refresh cluster: a large, unmistakably reload-styled button plus a
	-- bold "x/3" counter beside it - only visible for an OFFERED (not yet
	-- accepted), available standard-slot quest with refreshes remaining.
	local refreshButton = Instance.new("TextButton")
	refreshButton.Name = "RefreshButton"
	refreshButton.Size = UDim2.fromOffset(34, 34)
	refreshButton.Position = UDim2.fromOffset(12, 78)
	refreshButton.Font = Enum.Font.GothamBlack
	refreshButton.TextScaled = true
	refreshButton.Text = "\u{21BB}"
	refreshButton.TextColor3 = UITheme.COLORS.Text
	refreshButton.BackgroundColor3 = UITheme.COLORS.Accent
	refreshButton.Visible = false
	UITheme.ApplyCorner(refreshButton)
	UITheme.ApplyButtonHoverEffect(refreshButton)
	refreshButton.Parent = card

	local refreshCountLabel = Instance.new("TextLabel")
	refreshCountLabel.Name = "RefreshCountLabel"
	refreshCountLabel.Size = UDim2.new(1, -58, 0, 34)
	refreshCountLabel.Position = UDim2.fromOffset(52, 78)
	refreshCountLabel.BackgroundTransparency = 1
	refreshCountLabel.Font = Enum.Font.GothamBlack
	refreshCountLabel.TextSize = 17
	refreshCountLabel.TextXAlignment = Enum.TextXAlignment.Left
	refreshCountLabel.TextYAlignment = Enum.TextYAlignment.Center
	refreshCountLabel.TextColor3 = UITheme.COLORS.Text
	refreshCountLabel.Text = ""
	refreshCountLabel.Visible = false
	refreshCountLabel.Parent = card

	-- Shown instead of the refresh cluster while the slot is on cooldown -
	-- a live countdown ("Next quest coming in...") or, for the Daily slot,
	-- "Come back tomorrow for new quests". Occupies the exact same row as
	-- the refresh cluster above (mutually exclusive - never both visible).
	local cooldownLabel = Instance.new("TextLabel")
	cooldownLabel.Name = "CooldownLabel"
	cooldownLabel.Size = UDim2.new(1, -24, 0, 34)
	cooldownLabel.Position = UDim2.fromOffset(12, 78)
	cooldownLabel.BackgroundTransparency = 1
	cooldownLabel.Font = Enum.Font.GothamBold
	cooldownLabel.TextSize = 14
	cooldownLabel.TextWrapped = true
	cooldownLabel.TextXAlignment = Enum.TextXAlignment.Left
	cooldownLabel.TextYAlignment = Enum.TextYAlignment.Center
	cooldownLabel.TextColor3 = UITheme.COLORS.SubText
	cooldownLabel.Text = ""
	cooldownLabel.Visible = false
	cooldownLabel.Parent = card

	--[[
		DAILY RESET COUNTDOWN.

		A separate always-on line for the daily slot, distinct from
		cooldownLabel. The two answer different questions: cooldownLabel says
		"when does a new quest appear in this slot", this says "how long is
		left in today's daily". Only the daily slot ever shows it, and it
		stays visible whether the quest is offered, accepted, complete or
		already claimed.
	]]
	local dailyResetLabel = Instance.new("TextLabel")
	dailyResetLabel.Name = "DailyResetLabel"
	dailyResetLabel.Size = UDim2.new(1, -24, 0, 16)
	dailyResetLabel.Position = UDim2.fromOffset(12, 4)
	dailyResetLabel.BackgroundTransparency = 1
	dailyResetLabel.Font = Enum.Font.GothamMedium
	dailyResetLabel.TextSize = 12
	dailyResetLabel.TextColor3 = Color3.fromRGB(150, 158, 178)
	dailyResetLabel.TextXAlignment = Enum.TextXAlignment.Right
	dailyResetLabel.Text = ""
	dailyResetLabel.Visible = false
	dailyResetLabel.Parent = card

	local barBackground = Instance.new("Frame")
	barBackground.Name = "BarBackground"
	barBackground.Size = UDim2.new(1, -100, 0, 9)
	barBackground.Position = UDim2.fromOffset(12, 122)
	barBackground.BackgroundColor3 = Color3.fromRGB(40, 42, 54)
	UITheme.ApplyCorner(barBackground)
	barBackground.Parent = card

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = UITheme.COLORS.Accent
	UITheme.ApplyCorner(barFill)
	barFill.Parent = barBackground

	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "ProgressLabel"
	progressLabel.Size = UDim2.new(0, 82, 0, 18)
	progressLabel.Position = UDim2.new(1, -94, 0, 118)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Font = Enum.Font.GothamBold
	progressLabel.TextSize = 12
	progressLabel.TextXAlignment = Enum.TextXAlignment.Right
	progressLabel.TextColor3 = UITheme.COLORS.SubText
	progressLabel.Text = ""
	progressLabel.Parent = card

	local actionButton = Instance.new("TextButton")
	actionButton.Name = "ActionButton"
	actionButton.Size = UDim2.new(1, -24, 0, 26)
	actionButton.Position = UDim2.fromOffset(12, 140)
	actionButton.Font = Enum.Font.GothamBold
	actionButton.TextScaled = true
	actionButton.TextColor3 = UITheme.COLORS.Text
	actionButton.BackgroundColor3 = UITheme.COLORS.Accent
	actionButton.Text = "ACCEPT"
	UITheme.ApplyCorner(actionButton)
	UITheme.ApplyButtonHoverEffect(actionButton)
	actionButton.Parent = card

	questCards[slotId] = {
		card = card,
		kindStripe = kindStripe,
		kindLabel = kindLabel,
		titleLabel = titleLabel,
		rewardLabel = rewardLabel,
		descriptionLabel = descriptionLabel,
		barBackground = barBackground,
		barFill = barFill,
		progressLabel = progressLabel,
		actionButton = actionButton,
		cancelButton = cancelButton,
		dismissButton = dismissButton,
		refreshButton = refreshButton,
		refreshCountLabel = refreshCountLabel,
		cooldownLabel = cooldownLabel,
		slotId = slotId,
		slotKind = nil :: string?,
		availableAtClock = nil :: number?, -- os.clock() timestamp this slot becomes available, nil if already available
		-- os.clock() timestamp of the next noon-UTC daily reset. Set for the
		-- daily slot only, and set REGARDLESS of whether the slot is on
		-- cooldown, because the daily countdown runs continuously - while the
		-- quest is offered, accepted, complete, or claimed.
		dailyResetAtClock = nil :: number?,
		dailyResetLabel = dailyResetLabel,
	}
end

-- ===== Refresh =====

local function formatDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	return ("%dm %ds"):format(minutes, secs)
end

--[[
	Hours-and-minutes form, for the daily reset countdown.

	The cooldown formatter above is minutes-and-seconds, which is right for
	a 2-5 minute wait and useless for a 23-hour one ("1410m 0s"). Seconds
	are shown only in the last minute, where they are the only thing
	changing.
]]
local function formatCountdown(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	if hours > 0 then
		return ("%dh %02dm"):format(hours, minutes)
	elseif minutes > 0 then
		return ("%dm"):format(minutes)
	end
	return ("%ds"):format(seconds % 60)
end

local function refreshFromSnapshot(snapshot)
	for _, entry in ipairs(snapshot) do
		local widgets = questCards[entry.slotId]
		if not widgets then
			continue
		end

		widgets.card.Visible = true
		widgets.slotKind = entry.slotKind

		-- Daily reset countdown: driven by the server's secondsUntilDailyReset,
		-- which is nil for every non-daily slot.
		if entry.secondsUntilDailyReset ~= nil then
			widgets.dailyResetAtClock = os.clock() + entry.secondsUntilDailyReset
			widgets.dailyResetLabel.Visible = true
			widgets.dailyResetLabel.Text = ("Resets in %s"):format(formatCountdown(entry.secondsUntilDailyReset))
		else
			widgets.dailyResetAtClock = nil
			widgets.dailyResetLabel.Visible = false
		end
		local kindColor = KIND_COLORS[entry.kind] or UITheme.COLORS.Accent
		widgets.kindStripe.BackgroundColor3 = kindColor
		widgets.kindLabel.TextColor3 = kindColor
		widgets.kindLabel.Text = KIND_LABELS[entry.kind] or "QUEST"
		widgets.titleLabel.Text = entry.title
		widgets.rewardLabel.Text = entry.rewardLabel
		widgets.descriptionLabel.Text = entry.description
		widgets.progressLabel.Text = ("%d / %d"):format(entry.progress, entry.target)
		widgets.barFill.Size = UDim2.new(math.clamp(entry.progress / entry.target, 0, 1), 0, 1, 0)
		widgets.cancelButton.Visible = entry.accepted
		-- Dismiss ONLY while offered (not yet accepted) and not on cooldown -
		-- an accepted quest uses CancelButton instead (same corner), and a
		-- quest already on cooldown has nothing offered to dismiss.
		widgets.dismissButton.Visible = entry.available and not entry.accepted

		local canRefresh = entry.available
			and not entry.accepted
			and entry.refreshesRemaining ~= nil
			and entry.refreshesRemaining > 0
		widgets.refreshButton.Visible = canRefresh
		if entry.refreshesRemaining ~= nil then
			widgets.refreshCountLabel.Visible = entry.available and not entry.accepted
			widgets.refreshCountLabel.Text = ("%d/%d REFRESHES"):format(
				entry.refreshesRemaining,
				entry.refreshesPerDay
			)
		else
			widgets.refreshCountLabel.Visible = false
		end

		if not entry.available then
			-- On cooldown: hide the refresh cluster/progress bar/action
			-- button, show the countdown (or the "come back tomorrow"
			-- message) instead. Track WHEN (in local os.clock() time) it'll
			-- flip so the per-second ticker below can count down smoothly
			-- between snapshot polls - the actual gate is always the server's
			-- own absolute nextAvailableAt, never this local clock.
			widgets.availableAtClock = os.clock() + entry.secondsUntilAvailable
			widgets.barBackground.Visible = false
			widgets.progressLabel.Visible = false
			widgets.actionButton.Visible = false
			widgets.cancelButton.Visible = false
			widgets.dismissButton.Visible = false
			widgets.refreshButton.Visible = false
			widgets.refreshCountLabel.Visible = false
			widgets.cooldownLabel.Visible = true
			--[[
				The daily slot's cooldown now ALWAYS runs to the next noon reset
				- claiming and dismissing both close it until then, so there is no
				longer a short dismiss cooldown to distinguish from a long claim
				one. The old duration-threshold test that existed for that reason
				is gone; the slot kind alone is now a correct signal.

				The exact time is on the always-visible DailyResetLabel above, so
				this line does not repeat it.
			]]
			if entry.slotKind == "daily" then
				widgets.cooldownLabel.Text = "Daily complete - next one at reset"
			else
				widgets.cooldownLabel.Text = ("Next quest coming in %s"):format(formatDuration(entry.secondsUntilAvailable))
			end
		else
			widgets.availableAtClock = nil
			widgets.barBackground.Visible = true
			widgets.progressLabel.Visible = true
			widgets.actionButton.Visible = true
			widgets.cooldownLabel.Visible = false

			if entry.canClaim then
				widgets.actionButton.Text = "CLAIM"
				widgets.actionButton.BackgroundColor3 = UITheme.COLORS.Success
				widgets.barFill.BackgroundColor3 = UITheme.COLORS.Success
			elseif entry.accepted then
				widgets.actionButton.Text = "IN PROGRESS"
				widgets.actionButton.BackgroundColor3 = UITheme.COLORS.Panel
				widgets.barFill.BackgroundColor3 = kindColor
			else
				widgets.actionButton.Text = "ACCEPT"
				widgets.actionButton.BackgroundColor3 = kindColor
				widgets.barFill.BackgroundColor3 = kindColor
			end
		end
	end
end

local function requestSnapshot()
	local ok, snapshot = pcall(function()
		return getQuestsSnapshotFunction:InvokeServer()
	end)
	if ok and snapshot then
		refreshFromSnapshot(snapshot)
	end
	return ok and snapshot or nil
end

for slotId, widgets in pairs(questCards) do
	widgets.actionButton.MouseButton1Click:Connect(function()
		widgets.actionButton.Active = false
		local snapshot = requestSnapshot()
		local currentEntry = nil
		if snapshot then
			for _, e in ipairs(snapshot) do
				if e.slotId == slotId then
					currentEntry = e
				end
			end
		end
		local result
		if currentEntry and currentEntry.canClaim then
			result = claimQuestFunction:InvokeServer(slotId)
		elseif currentEntry and currentEntry.available and not currentEntry.accepted then
			result = acceptQuestFunction:InvokeServer(slotId)
		end
		widgets.actionButton.Active = true
		if result and result.success then
			requestSnapshot()
		end
	end)

	widgets.cancelButton.MouseButton1Click:Connect(function()
		widgets.cancelButton.Active = false
		local result = cancelQuestFunction:InvokeServer(slotId)
		widgets.cancelButton.Active = true
		if result and result.success then
			requestSnapshot()
		end
	end)

	widgets.dismissButton.MouseButton1Click:Connect(function()
		widgets.dismissButton.Active = false
		local result = dismissQuestFunction:InvokeServer(slotId)
		widgets.dismissButton.Active = true
		if result and result.success then
			requestSnapshot()
		end
	end)

	widgets.refreshButton.MouseButton1Click:Connect(function()
		widgets.refreshButton.Active = false
		-- A quick spin flourish on click so the "reload" button reads as
		-- having actually done something, independent of the server's
		-- (near-instant) response.
		local spinTween = TweenService:Create(
			widgets.refreshButton,
			TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Rotation = widgets.refreshButton.Rotation + 180 }
		)
		spinTween:Play()
		local result = refreshQuestFunction:InvokeServer(slotId)
		widgets.refreshButton.Active = true
		if result and result.success then
			requestSnapshot()
		end
	end)
end

-- Immediate notification the instant a quest becomes claimable, rather
-- than waiting for the next periodic poll below.
RemoteEvents.Get("QuestCompleted").OnClientEvent:Connect(function()
	requestSnapshot()
end)

-- ===== "New Quest Available" banner - purely informational, fired ONLY
-- by the server's "QuestReady" event, which itself only fires once per
-- genuine cooldown cycle (a slot that was empty/on-cooldown just became
-- offerable again) - never on a plain UI open, a manual refresh poll, or
-- a reconnect where nothing actually changed (see QuestsSystem's
-- startReadyNotifyLoop). Slides in from the LEFT edge of the screen,
-- holds briefly, then continues off to the right and disappears - it is
-- NOT a button and never accepts anything; the player must open this
-- quest box themselves to act on it. =====

local BANNER_COLOR = Color3.fromRGB(255, 214, 10) -- bright gold, reads clearly against any backdrop
local BANNER_HOLD_SECONDS = 1.1
local BANNER_Y = 16
local BANNER_WIDTH = 380
local BANNER_OFFSCREEN_LEFT = UDim2.new(0, -BANNER_WIDTH - 40, 0, BANNER_Y)
local BANNER_RESTING = UDim2.new(0.5, -BANNER_WIDTH / 2, 0, BANNER_Y)
local BANNER_OFFSCREEN_RIGHT = UDim2.new(1, 40, 0, BANNER_Y)

local newQuestBanner = Instance.new("Frame")
newQuestBanner.Name = "NewQuestBanner"
newQuestBanner.Size = UDim2.fromOffset(BANNER_WIDTH, 44)
newQuestBanner.Position = BANNER_OFFSCREEN_LEFT
newQuestBanner.BackgroundColor3 = BANNER_COLOR
newQuestBanner.BorderSizePixel = 0
newQuestBanner.ZIndex = 40
newQuestBanner.Parent = mainUI
UITheme.ApplyCorner(newQuestBanner)

local newQuestBannerLabel = Instance.new("TextLabel")
newQuestBannerLabel.Name = "Label"
newQuestBannerLabel.Size = UDim2.fromScale(1, 1)
newQuestBannerLabel.BackgroundTransparency = 1
newQuestBannerLabel.Font = Enum.Font.GothamBlack
newQuestBannerLabel.TextScaled = true
newQuestBannerLabel.TextColor3 = Color3.fromRGB(20, 18, 10)
newQuestBannerLabel.Text = "NEW QUEST AVAILABLE"
newQuestBannerLabel.ZIndex = 41
newQuestBannerLabel.Parent = newQuestBanner

local bannerQueue: { string } = {}
local bannerShowing = false

local function showNextBanner()
	if bannerShowing or #bannerQueue == 0 then
		return
	end
	bannerShowing = true
	table.remove(bannerQueue, 1)

	newQuestBanner.Position = BANNER_OFFSCREEN_LEFT
	newQuestBanner.Visible = true

	-- Left-to-right entrance: slides in from fully off-screen-left to its
	-- resting center-top position.
	local inTween = TweenService:Create(
		newQuestBanner,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = BANNER_RESTING }
	)
	inTween:Play()

	task.delay(BANNER_HOLD_SECONDS, function()
		-- Continues the SAME left-to-right motion on out, exiting off the
		-- right edge, rather than reversing back the way it came - one
		-- continuous left-to-right pass across the screen.
		local outTween = TweenService:Create(
			newQuestBanner,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = BANNER_OFFSCREEN_RIGHT }
		)
		outTween:Play()
		outTween.Completed:Connect(function()
			newQuestBanner.Visible = false
			bannerShowing = false
			showNextBanner()
		end)
	end)
end

RemoteEvents.Get("QuestReady").OnClientEvent:Connect(function(data)
	-- Defence in depth: the server already refuses to fire this before the
	-- first-time tutorial is finished, so a banner can never interrupt the
	-- tutorial. Re-checked here so a stale in-flight event can't slip past.
	if not questsUnlocked then
		return
	end
	if not data or typeof(data) ~= "table" then
		return
	end
	table.insert(bannerQueue, data.slotId)
	requestSnapshot()
	showNextBanner()
end)

-- ===== Live per-second countdown ticker (independent of the periodic
-- server poll below, so cooldown text counts down smoothly) =====

task.spawn(function()
	while true do
		task.wait(1)
		for _, widgets in pairs(questCards) do
			--[[
				Daily reset countdown. Ticks independently of the cooldown text
				and independently of whether the slot is on cooldown at all,
				because the daily deadline runs whatever state the quest is in.

				At zero it does NOT roll over locally - the server owns the
				boundary. It shows "Resetting..." and the next poll brings the
				fresh quest and a new countdown.
			]]
			if widgets.dailyResetAtClock and widgets.dailyResetLabel.Visible then
				local untilReset = widgets.dailyResetAtClock - os.clock()
				widgets.dailyResetLabel.Text = if untilReset <= 0
					then "Resetting..."
					else ("Resets in %s"):format(formatCountdown(untilReset))
			end

			if widgets.availableAtClock and widgets.cooldownLabel.Visible then
				local remaining = widgets.availableAtClock - os.clock()
				-- The daily's cooldown always runs to the noon reset now, so the
				-- slot kind alone decides the message (see refreshFromSnapshot).
				if widgets.slotKind == "daily" then
					widgets.cooldownLabel.Text = "Daily complete - next one at reset"
				elseif remaining <= 0 then
					-- Let the next snapshot poll (or QuestReady event) flip this
					-- card over to available; just stop showing negative time.
					widgets.cooldownLabel.Text = "Next quest coming in..."
				else
					widgets.cooldownLabel.Text = ("Next quest coming in %s"):format(formatDuration(remaining))
				end
			end
		end
	end
end)

-- ===== Visibility + periodic refresh (only while actually visible, so
-- an in-match player isn't polled for no reason) =====

local visible = false

--[[
	See `questsUnlocked` near the top of this file for why the unlock flag
	is declared up there rather than here.
]]
local function setBoxVisible(newVisible: boolean)
	-- Locked always wins: nothing can show the quest box before the
	-- first-time tutorial is finished.
	if not questsUnlocked then
		newVisible = false
	end
	if newVisible == visible then
		return
	end
	visible = newVisible
	questBox.Visible = visible
	if visible then
		requestSnapshot()
	end
end

--[[
	Re-applies lobby visibility from the authoritative match state.

	Needed because the unlock flag resolves ASYNCHRONOUSLY (a remote round
	trip), while GameStateChanged / the startup snapshot can arrive first.
	Without this, a returning player's box was forced hidden by the gate,
	the unlock landed a moment later, and nothing ever asked again - so the
	quest box stayed invisible for the whole session.
]]
local function applyLobbyVisibility()
	local ok, snapshot = pcall(function()
		return RemoteFunctions.Get("GetMatchSnapshot"):InvokeServer()
	end)
	if ok and snapshot then
		setBoxVisible(
			snapshot.gameState == MatchConfig.GameState.Lobby
				or snapshot.gameState == MatchConfig.GameState.Waiting
		)
	end
end

RemoteEvents.Get("TutorialCompleted").OnClientEvent:Connect(function()
	if questsUnlocked then
		return
	end
	questsUnlocked = true
	applyLobbyVisibility()
end)

-- Returning players finished the tutorial in an earlier session, so they
-- never receive TutorialCompleted this join - ask once on startup, then
-- re-apply visibility, since the gate may already have forced the box
-- hidden before this answer came back.
task.spawn(function()
	local ok, state = pcall(function()
		return RemoteFunctions.Get("GetTutorialState"):InvokeServer()
	end)
	if ok and state and state.completed then
		questsUnlocked = true
		applyLobbyVisibility()
	end
end)

RemoteEvents.Get("GameStateChanged").OnClientEvent:Connect(function(state: string)
	setBoxVisible(state == MatchConfig.GameState.Lobby or state == MatchConfig.GameState.Waiting)
end)

task.spawn(function()
	local ok, snapshot = pcall(function()
		return RemoteFunctions.Get("GetMatchSnapshot"):InvokeServer()
	end)
	if ok and snapshot then
		setBoxVisible(snapshot.gameState == MatchConfig.GameState.Lobby or snapshot.gameState == MatchConfig.GameState.Waiting)
	end
end)

task.spawn(function()
	while true do
		task.wait(5)
		if visible then
			requestSnapshot()
		end
	end
end)

-- Exposed so TutorialUIController can force this box open/visible and
-- read its on-screen position for the guided tutorial's quest step,
-- without needing a new RemoteEvent or duplicating any quest UI.
local QuestBoxBridge = {}
function QuestBoxBridge.GetFrame(): Frame
	return questBox
end
function QuestBoxBridge.ForceExpanded()
	if collapsed then
		setCollapsed(false, true)
	end
end
_G.MathArenaQuestBoxBridge = QuestBoxBridge
