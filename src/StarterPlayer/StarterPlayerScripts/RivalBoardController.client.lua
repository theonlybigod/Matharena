--[[
	RivalBoardController.client.lua

	Drives three physical, world-mounted boards (never reachable from the
	bottom bar - being in the room is the only way to read them):
	  - The Rival Board inside the Statistics building.
	  - The Daily Rewards header board + its seven floor tiles.
	  - The Lifetime Rewards board.

	SCOPE. This script owns PRESENTATION ONLY. Every value it displays
	arrives from the server already computed and already formatted. It
	never reads another player's data and never computes a standing/streak/
	milestone itself - if this file were rewritten by an exploiter the
	worst outcome is a wrong-looking board on their own screen.

	REFRESH POLICY. Each board is populated on approach rather than on a
	timer: a player standing somewhere else should not be invoking a remote
	every few seconds for a board they cannot see. See the proximity loop
	at the bottom - it only fetches when the player is within VIEW_DISTANCE
	and the cached copy has gone stale.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
local LifetimeRewardsConfig = require(ReplicatedStorage.Modules.LifetimeRewardsConfig)

local player = Players.LocalPlayer

-- Studs from a board within which we bother fetching/refreshing. Rooms in
-- this game are small, so this comfortably covers "standing anywhere
-- inside" without firing while the player is out in the plaza.
local VIEW_DISTANCE = 60
-- Matches the servers' own rate limits, so the client never asks more often
-- than the server would answer with fresh data anyway.
local REFRESH_SECONDS = 3

local CANVAS = Vector2.new(900, 460)
local BG = Color3.fromRGB(16, 18, 26)
local TEXT_DIM = Color3.fromRGB(150, 158, 178)
local TEXT_BRIGHT = Color3.fromRGB(238, 242, 250)
local GOLD = Color3.fromRGB(255, 200, 62)
local GREEN = Color3.fromRGB(120, 220, 150)

local boards: { [BasePart]: any } = {}
local dailyHeaders: { [BasePart]: any } = {}
local lifetimeBoards: { [BasePart]: any } = {}
-- Physical floor tiles in the Daily Rewards room, keyed by day number (fixed
-- 1-7 left-to-right - see BuildingInteriors.FurnishRewards). Driven from the
-- SAME snapshot as the header board, so the two can never disagree.
local floorTiles: { [number]: any } = {}
local lastFetch = 0
local lastDailyFetch = 0
local lastLifetimeFetch = 0
local cached: any = nil

local function makeLabel(parent: Instance, size: UDim2, pos: UDim2, text: string, color: Color3, align: Enum.TextXAlignment, weight: Enum.FontWeight, fontEnum: Enum.Font?)
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = pos
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextXAlignment = align
	label.FontFace = Font.fromEnum(fontEnum or Enum.Font.GothamMedium)
	label.FontFace.Weight = weight
	label.Parent = parent
	return label
end

-- ============================================================
-- ===== Rival Board (Statistics building) =====================
-- ============================================================

--[[
	Builds the static furniture of one board: title, column headers and five
	empty category rows. Row contents are filled later by render(); building
	the structure once and only updating .Text avoids rebuilding ~40 GUI
	instances every refresh.
]]
local function buildBoard(part: BasePart)
	if boards[part] then
		return
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "RivalBoardGui"
	gui.Adornee = part
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = CANVAS
	gui.LightInfluence = 0
	gui.Parent = part

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = BG
	bg.BorderSizePixel = 0
	bg.Parent = gui

	makeLabel(bg, UDim2.new(1, -40, 0, 54), UDim2.new(0, 20, 0, 14), "YOU vs THE LEADERS", TEXT_BRIGHT, Enum.TextXAlignment.Left, Enum.FontWeight.Bold)

	local status = makeLabel(bg, UDim2.new(1, -40, 0, 30), UDim2.new(0, 20, 0, 68), "Loading standings...", TEXT_DIM, Enum.TextXAlignment.Left, Enum.FontWeight.Regular)

	makeLabel(bg, UDim2.new(0, 240, 0, 26), UDim2.new(0, 20, 0, 104), "CATEGORY", TEXT_DIM, Enum.TextXAlignment.Left, Enum.FontWeight.Bold)
	makeLabel(bg, UDim2.new(0, 150, 0, 26), UDim2.new(0, 270, 0, 104), "YOU", TEXT_DIM, Enum.TextXAlignment.Right, Enum.FontWeight.Bold)
	makeLabel(bg, UDim2.new(0, 240, 0, 26), UDim2.new(0, 435, 0, 104), "#1", TEXT_DIM, Enum.TextXAlignment.Right, Enum.FontWeight.Bold)
	makeLabel(bg, UDim2.new(0, 190, 0, 26), UDim2.new(0, 690, 0, 104), "TO CLOSE", TEXT_DIM, Enum.TextXAlignment.Right, Enum.FontWeight.Bold)

	local rows = {}
	for i = 1, 5 do
		local y = 140 + (i - 1) * 62

		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 6, 0, 46)
		stripe.Position = UDim2.new(0, 20, 0, y)
		stripe.BorderSizePixel = 0
		stripe.BackgroundColor3 = TEXT_DIM
		stripe.Parent = bg

		rows[i] = {
			stripe = stripe,
			title = makeLabel(bg, UDim2.new(0, 220, 0, 34), UDim2.new(0, 38, 0, y + 6), "", TEXT_BRIGHT, Enum.TextXAlignment.Left, Enum.FontWeight.Medium),
			you = makeLabel(bg, UDim2.new(0, 150, 0, 34), UDim2.new(0, 270, 0, y + 6), "", TEXT_BRIGHT, Enum.TextXAlignment.Right, Enum.FontWeight.Bold),
			leader = makeLabel(bg, UDim2.new(0, 240, 0, 34), UDim2.new(0, 435, 0, y + 6), "", TEXT_DIM, Enum.TextXAlignment.Right, Enum.FontWeight.Medium),
			gap = makeLabel(bg, UDim2.new(0, 190, 0, 34), UDim2.new(0, 690, 0, y + 6), "", TEXT_DIM, Enum.TextXAlignment.Right, Enum.FontWeight.Medium),
		}
	end

	boards[part] = { gui = gui, rows = rows, status = status }
end

local function render(data: any)
	for _, board in pairs(boards) do
		if not data then
			board.status.Text = "Standings unavailable - try again shortly"
			continue
		end

		board.status.Text = if data.hasStandings
			then "Live global standings"
			else "No standings recorded yet - be the first"

		for i, row in ipairs(board.rows) do
			local entry = data.rows and data.rows[i]
			if entry then
				row.title.Text = entry.title
				row.you.Text = entry.yourValue
				row.leader.Text = ("%s  %s"):format(entry.leaderValue, entry.leaderName)
				row.gap.Text = entry.gapText
				row.stripe.BackgroundColor3 = entry.accent or TEXT_DIM
				row.you.TextColor3 = if entry.youLead then GOLD else TEXT_BRIGHT
				row.gap.TextColor3 = if entry.youLead then GOLD else TEXT_DIM
			else
				row.title.Text = ""
				row.you.Text = ""
				row.leader.Text = ""
				row.gap.Text = ""
			end
		end
	end
end

for _, part in ipairs(CollectionService:GetTagged("RivalBoard")) do
	if part:IsA("BasePart") then
		buildBoard(part)
	end
end
CollectionService:GetInstanceAddedSignal("RivalBoard"):Connect(function(part)
	if part:IsA("BasePart") then
		buildBoard(part)
	end
end)
CollectionService:GetInstanceRemovedSignal("RivalBoard"):Connect(function(part)
	boards[part] = nil
end)

-- ============================================================
-- ===== Daily Rewards: header board + floor tiles ==============
-- ============================================================

--[[
	Builds the Daily Rewards title tile: a big centred Bangers title
	("DAILY REWARDS", matching the Shop's "FEATURED TODAY" treatment) plus
	the streak/claim-availability status line underneath it, laid flat on
	the floor (Face=Top) as part of the same continuous runway asset the
	instruction segment and the seven day cells are on - not a standing
	board. The old standing version stood in front of the door, which is
	exactly the placement this was moved away from.
]]
local function buildDailyHeader(part: BasePart)
	if dailyHeaders[part] then
		return
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "DailyRewardsHeaderGui"
	gui.Adornee = part
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	-- Canvas SWAPPED relative to the part's actual width/depth (this
	-- segment is wide and shallow physically). Content is built in NATURAL
	-- wide-format coordinates (900x220, the same rough numbers the old
	-- vertical wall screen used) inside a wrapper sized to those natural
	-- dimensions, then the WHOLE wrapper is rotated 90 as one rigid unit -
	-- the wrapper's own declared size is what the text-layout engine sees,
	-- giving "DAILY REWARDS" and the status line plenty of natural room
	-- instead of being squeezed into a narrow pre-rotated box (confirmed
	-- empirically: rotating individual labels instead cramped them badly).
	-- The rotated bounding box (220x900) exactly matches the canvas, so
	-- nothing clips off the edge of the tile.
	gui.CanvasSize = Vector2.new(220, 900)
	gui.LightInfluence = 0
	gui.Parent = part

	local bg = Instance.new("Frame")
	bg.AnchorPoint = Vector2.new(0.5, 0.5)
	bg.Position = UDim2.fromScale(0.5, 0.5)
	bg.Size = UDim2.fromOffset(900, 220)
	bg.Rotation = 90
	bg.BackgroundColor3 = BG
	bg.BorderSizePixel = 0
	bg.Parent = gui

	makeLabel(
		bg,
		UDim2.new(1, 0, 0, 110),
		UDim2.new(0, 0, 0, 10),
		"DAILY REWARDS",
		GOLD,
		Enum.TextXAlignment.Center,
		Enum.FontWeight.Bold,
		Enum.Font.Bangers
	)
	local status = makeLabel(
		bg,
		UDim2.new(1, -60, 0, 50),
		UDim2.new(0, 30, 0, 140),
		"Loading streak...",
		TEXT_DIM,
		Enum.TextXAlignment.Center,
		Enum.FontWeight.Regular
	)

	dailyHeaders[part] = { status = status }
end

local function renderDailyHeader(snapshot: any)
	for _, header in pairs(dailyHeaders) do
		if not snapshot then
			header.status.Text = "Streak unavailable - try again shortly"
		else
			header.status.Text = if snapshot.canClaimToday
				then ("A reward is ready - Streak Day %d/7"):format(snapshot.currentStreakDay)
				else "Today's reward already collected - come back tomorrow"
		end
	end
end

--[[
	Builds one floor tile's SurfaceGui (Face=Top, since it's mounted flat on
	the floor and read by looking down while walking toward/over it) - day
	number, reward label, and state, styled like a card the same way the
	old wall vault's slots were. "Make the screen be the button itself" -
	this IS the walkable button, not decoration next to one.
]]
local function buildFloorTile(part: BasePart)
	local day = part:GetAttribute("StreakDay")
	if typeof(day) ~= "number" or floorTiles[day] then
		return
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "StreakDayTileGui"
	gui.Adornee = part
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	-- Square canvas, enlarged further for real breathing room per explicit
	-- "texts are very compact and compressed" feedback (was 220, then 300).
	gui.CanvasSize = Vector2.new(360, 360)
	gui.LightInfluence = 0
	gui.Parent = part

	-- The content wrapper is rotated 90 as a whole (square canvas, so this
	-- never clips or distorts) - Face=Top's default axis mapping otherwise
	-- renders text sideways, confirmed empirically standing in the room and
	-- screenshotting it.
	local bg = Instance.new("Frame")
	bg.AnchorPoint = Vector2.new(0.5, 0.5)
	bg.Position = UDim2.fromScale(0.5, 0.5)
	bg.Size = UDim2.fromOffset(360, 360)
	bg.Rotation = 90
	bg.BackgroundColor3 = Color3.fromRGB(28, 31, 42)
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local marker = Instance.new("Frame")
	marker.Size = UDim2.new(1, 0, 0, 18)
	marker.BackgroundColor3 = TEXT_DIM
	marker.BorderSizePixel = 0
	marker.Parent = bg

	-- Generous side margins (40, was 12-24) and clear vertical gaps between
	-- the three lines, rather than everything packed edge to edge.
	local dayLabel = makeLabel(bg, UDim2.new(1, -80, 0, 70), UDim2.new(0, 40, 0, 40), ("DAY %d"):format(day), TEXT_DIM, Enum.TextXAlignment.Center, Enum.FontWeight.Bold)
	local rewardLabel = makeLabel(bg, UDim2.new(1, -80, 0, 130), UDim2.new(0, 40, 0, 130), "", TEXT_BRIGHT, Enum.TextXAlignment.Center, Enum.FontWeight.Bold)
	local stateLabel = makeLabel(bg, UDim2.new(1, -80, 0, 60), UDim2.new(0, 40, 0, 280), "", TEXT_DIM, Enum.TextXAlignment.Center, Enum.FontWeight.Medium)

	floorTiles[day] = { part = part, marker = marker, day = dayLabel, reward = rewardLabel, state = stateLabel }
end

--[[
	Paints the floor tiles from the same snapshot the header board uses.
	track entries carry their own fixed `day` field regardless of array
	position (the array itself is a rolling window starting at today, but
	the tiles are fixed left-to-right by day - see BuildingInteriors'
	comment on why - so this matches on entry.day, never on array index).
]]
local function renderFloorTiles(snapshot: any)
	if not snapshot or not snapshot.track then
		return
	end
	for _, entry in ipairs(snapshot.track) do
		local tile = floorTiles[entry.day]
		if tile then
			tile.reward.Text = entry.label or ""
			local colour, stateText
			-- BUG FIX: this used to check `entry.collected`, a field that does
			-- not exist on the snapshot's track entries - the real field is
			-- `isCollected` (see DailyRewardsSystem.BuildSnapshot). Reading the
			-- wrong name meant this branch was silently always false, so an
			-- already-collected day never got its green "CLAIMED" tint - it
			-- fell through to the "today"/"+N days" branches instead, every
			-- single time, for every player.
			if entry.isCollected then
				colour, stateText = GREEN, "\u{2713} CLAIMED"
			elseif entry.offsetFromToday == 0 then
				colour = GOLD
				stateText = if snapshot.canClaimToday then "WALK HERE TO CLAIM" else "CLAIMED TODAY"
			else
				colour = TEXT_DIM
				stateText = ("+%d days"):format(entry.offsetFromToday or 0)
			end
			tile.marker.BackgroundColor3 = colour
			tile.state.Text = stateText
			tile.state.TextColor3 = colour
		end
	end
end

for _, part in ipairs(CollectionService:GetTagged("DailyRewardsTitleTile")) do
	if part:IsA("BasePart") then
		buildDailyHeader(part)
	end
end
CollectionService:GetInstanceAddedSignal("DailyRewardsTitleTile"):Connect(function(part)
	if part:IsA("BasePart") then
		buildDailyHeader(part)
	end
end)
CollectionService:GetInstanceRemovedSignal("DailyRewardsTitleTile"):Connect(function(part)
	dailyHeaders[part] = nil
end)

for _, part in ipairs(CollectionService:GetTagged("StreakDayFloorPad")) do
	if part:IsA("BasePart") then
		buildFloorTile(part)
	end
end
CollectionService:GetInstanceAddedSignal("StreakDayFloorPad"):Connect(function(part)
	if part:IsA("BasePart") then
		buildFloorTile(part)
	end
end)

-- ============================================================
-- ===== Lifetime Rewards board ==================================
-- ============================================================

--[[
	Builds the Lifetime Rewards panel: a big centred Bangers title (matching
	the Shop's "FEATURED TODAY" treatment) over a two-column grid of every
	category from LifetimeRewardsConfig, each with its progress bar and a
	Claim button that flips to a permanent COMPLETE badge - the exact same
	visual language and claim flow the popup used to have, kept deliberately
	unchanged per "keep the general overview the same... I like how it is
	right now", just given its own wall presence.

	Split into two columns rather than one long scrolling list: a
	SurfaceGui ScrollingFrame technically works, but scrolling a world panel
	with a mouse wheel from a few studs away is finicky in practice, and all
	21 milestones (18 + 3 new "very hard to obtain" ones) comfortably fit
	two columns of 3 categories each without needing to scroll at all.
]]
local LIFETIME_CANVAS = Vector2.new(900, 760)

local function buildLifetimeBoard(part: BasePart)
	if lifetimeBoards[part] then
		return
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "LifetimeRewardsGui"
	gui.Adornee = part
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = LIFETIME_CANVAS
	gui.LightInfluence = 0
	gui.Parent = part

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = BG
	bg.BorderSizePixel = 0
	bg.Parent = gui

	makeLabel(
		bg,
		UDim2.new(1, 0, 0, 60),
		UDim2.new(0, 0, 0, 8),
		"LIFETIME REWARDS",
		GOLD,
		Enum.TextXAlignment.Center,
		Enum.FontWeight.Bold,
		Enum.Font.Bangers
	)

	local sorted = LifetimeRewardsConfig.GetSorted()
	local halfCategoryCount = math.ceil(#LifetimeRewardsConfig.CATEGORY_ORDER / 2)
	local columnXs = { 24, 466 }
	local columnWidth = 410

	local rows: { [string]: any } = {}
	local columnY = { 80, 80 }

	local lastCategory: string? = nil
	local currentColumn = 1
	local categoriesSeen = 0

	for _, milestone in ipairs(sorted) do
		if milestone.category ~= lastCategory then
			lastCategory = milestone.category
			categoriesSeen += 1
			if categoriesSeen > halfCategoryCount then
				currentColumn = 2
			end

			local header = makeLabel(
				bg,
				UDim2.new(0, columnWidth, 0, 24),
				UDim2.new(0, columnXs[currentColumn], 0, columnY[currentColumn]),
				milestone.category:upper(),
				TEXT_DIM,
				Enum.TextXAlignment.Left,
				Enum.FontWeight.Bold
			)
			header.TextSize = 15
			columnY[currentColumn] += 30
		end

		local y = columnY[currentColumn]
		local row = Instance.new("Frame")
		row.Size = UDim2.new(0, columnWidth, 0, 42)
		row.Position = UDim2.new(0, columnXs[currentColumn], 0, y)
		row.BackgroundColor3 = Color3.fromRGB(28, 31, 42)
		row.BorderSizePixel = 0
		row.Parent = bg

		local label = makeLabel(
			row,
			UDim2.new(1, -110, 0, 20),
			UDim2.new(0, 10, 0, 2),
			milestone.label,
			TEXT_BRIGHT,
			Enum.TextXAlignment.Left,
			Enum.FontWeight.Medium
		)
		label.TextSize = 13

		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(1, -120, 0, 6)
		barBg.Position = UDim2.new(0, 10, 1, -12)
		barBg.BackgroundColor3 = Color3.fromRGB(40, 42, 54)
		barBg.BorderSizePixel = 0
		barBg.Parent = row

		local barFill = Instance.new("Frame")
		barFill.Size = UDim2.new(0, 0, 1, 0)
		barFill.BackgroundColor3 = TEXT_DIM
		barFill.BorderSizePixel = 0
		barFill.Parent = barBg

		local claimBtn = Instance.new("TextButton")
		claimBtn.Size = UDim2.fromOffset(96, 30)
		claimBtn.Position = UDim2.new(1, -102, 0, 6)
		claimBtn.Font = Enum.Font.GothamBold
		claimBtn.TextScaled = true
		claimBtn.TextColor3 = TEXT_BRIGHT
		claimBtn.BackgroundColor3 = GREEN
		claimBtn.Text = "CLAIM"
		claimBtn.Visible = false
		claimBtn.Parent = row

		local completeBadge = makeLabel(
			row,
			UDim2.fromOffset(96, 30),
			UDim2.new(1, -102, 0, 6),
			"\u{2713} DONE",
			GREEN,
			Enum.TextXAlignment.Center,
			Enum.FontWeight.Bold
		)
		completeBadge.Visible = false

		rows[milestone.id] = { row = row, label = label, barFill = barFill, claimButton = claimBtn, completeBadge = completeBadge }

		local remoteFn = RemoteFunctions.Get("ClaimLifetimeMilestone")
		claimBtn.MouseButton1Click:Connect(function()
			claimBtn.Active = false
			local result = remoteFn:InvokeServer(milestone.id)
			claimBtn.Active = true
			if result and result.success then
				lastLifetimeFetch = 0
			end
		end)

		columnY[currentColumn] += 48
	end

	lifetimeBoards[part] = { rows = rows }
end

local function renderLifetimeBoard(snapshot: any)
	if not snapshot then
		return
	end
	for _, board in pairs(lifetimeBoards) do
		for _, milestone in ipairs(snapshot.milestones) do
			local widgets = board.rows[milestone.id]
			if widgets then
				local progressFraction = math.clamp(milestone.progress / milestone.target, 0, 1)
				widgets.barFill.Size = UDim2.new(progressFraction, 0, 1, 0)
				if milestone.status == "Claimed" then
					widgets.claimButton.Visible = false
					widgets.completeBadge.Visible = true
					widgets.barFill.BackgroundColor3 = GREEN
				elseif milestone.status == "Available" then
					widgets.claimButton.Visible = true
					widgets.completeBadge.Visible = false
					widgets.barFill.BackgroundColor3 = GREEN
				else
					widgets.claimButton.Visible = false
					widgets.completeBadge.Visible = false
					widgets.barFill.BackgroundColor3 = Color3.fromRGB(90, 140, 230)
				end
			end
		end
	end
end

for _, part in ipairs(CollectionService:GetTagged("LifetimeRewardsBoard")) do
	if part:IsA("BasePart") then
		buildLifetimeBoard(part)
	end
end
CollectionService:GetInstanceAddedSignal("LifetimeRewardsBoard"):Connect(function(part)
	if part:IsA("BasePart") then
		buildLifetimeBoard(part)
	end
end)
CollectionService:GetInstanceRemovedSignal("LifetimeRewardsBoard"):Connect(function(part)
	lifetimeBoards[part] = nil
end)

-- ============================================================
-- ===== Fetch on approach =======================================
-- ============================================================

local remote: RemoteFunction? = nil
local dailyRemote: RemoteFunction? = nil
local lifetimeRemote: RemoteFunction? = nil
task.spawn(function()
	remote = RemoteFunctions.Get("GetRivalComparison")
end)
task.spawn(function()
	-- Owned by DailyRewardsSystem, not by this controller - the header
	-- board and the floor tiles both read the same server snapshot.
	dailyRemote = RemoteFunctions.Get("GetDailyRewardSnapshot")
end)
task.spawn(function()
	-- Owned by LifetimeRewardsSystem - the wall board reads the exact same
	-- snapshot the old popup's Lifetime tab did.
	lifetimeRemote = RemoteFunctions.Get("GetLifetimeRewardsSnapshot")
end)

-- Shared helper: is the player standing near any part in `set`?
local function nearAny(set, rootPos: Vector3): boolean
	for part in pairs(set) do
		if part.Parent and (part.Position - rootPos).Magnitude <= VIEW_DISTANCE then
			return true
		end
	end
	return false
end

RunService.Heartbeat:Connect(function()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local rootPos = (root :: BasePart).Position
	local now = os.clock()

	-- Rival Board
	if remote and next(boards) ~= nil and nearAny(boards, rootPos) and (now - lastFetch) >= REFRESH_SECONDS then
		lastFetch = now
		task.spawn(function()
			local ok, result = pcall(function()
				return (remote :: RemoteFunction):InvokeServer()
			end)
			if ok then
				cached = result
				render(result)
			else
				render(nil)
			end
		end)
	end

	-- Daily Rewards header board + floor tiles, both from one snapshot.
	-- `next(dailyHeaders)` gates the fetch because the header and the
	-- tiles are always built together in the same room.
	if dailyRemote and next(dailyHeaders) ~= nil and nearAny(dailyHeaders, rootPos) and (now - lastDailyFetch) >= REFRESH_SECONDS then
		lastDailyFetch = now
		task.spawn(function()
			local ok, snapshot = pcall(function()
				return (dailyRemote :: RemoteFunction):InvokeServer()
			end)
			local data = if ok then snapshot else nil
			renderDailyHeader(data)
			renderFloorTiles(data)
		end)
	end

	-- Lifetime Rewards wall board - same building, own remote/snapshot
	-- shape. lastLifetimeFetch reset to 0 by a Claim button click (see
	-- buildLifetimeBoard) forces this to fire on the very next Heartbeat
	-- rather than waiting out the rest of the normal refresh interval.
	if lifetimeRemote and next(lifetimeBoards) ~= nil and nearAny(lifetimeBoards, rootPos) and (now - lastLifetimeFetch) >= REFRESH_SECONDS then
		lastLifetimeFetch = now
		task.spawn(function()
			local ok, snapshot = pcall(function()
				return (lifetimeRemote :: RemoteFunction):InvokeServer()
			end)
			renderLifetimeBoard(if ok then snapshot else nil)
		end)
	end
end)
