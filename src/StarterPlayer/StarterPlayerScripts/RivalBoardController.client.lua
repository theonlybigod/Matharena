--[[
	RivalBoardController.client.lua

	Fills the Rival Board inside the Statistics building - the head-to-head
	comparison between the local player and the current global #1 in each of
	the five leaderboard categories.

	SCOPE. This script owns PRESENTATION ONLY. Every value it displays
	arrives from the server already computed and already formatted (see
	RivalBoardSystem). It never reads another player's data, never touches a
	leaderboard, and never computes a standing - if this file were rewritten
	by an exploiter the worst outcome is a wrong-looking board on their own
	screen.

	WHY A SURFACEGUI AND NOT AN OVERLAY. The whole point of this feature is
	that it cannot be reached from the bottom bar; the buildings were
	previously redundant because everything in them was one click away. A
	SurfaceGui lives on a real part in the room, so being in the room is the
	only way to read it. Do not "helpfully" mirror this into a ScreenGui.

	REFRESH POLICY. The board is populated on approach rather than on a
	timer: a player standing in the lobby should not be invoking a remote
	every few seconds for a board they cannot see. See the proximity loop at
	the bottom - it only fetches when the player is within VIEW_DISTANCE and
	the cached copy has gone stale.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)

local player = Players.LocalPlayer

-- Studs from the board within which we bother fetching/refreshing. The
-- Statistics room is small, so this comfortably covers "standing anywhere
-- inside" without firing while the player is out in the plaza.
local VIEW_DISTANCE = 60
-- Matches RivalBoardSystem's own rate limit, so the client never asks more
-- often than the server would answer with fresh data anyway.
local REFRESH_SECONDS = 3

local CANVAS = Vector2.new(900, 460)
local BG = Color3.fromRGB(16, 18, 26)
local TEXT_DIM = Color3.fromRGB(150, 158, 178)
local TEXT_BRIGHT = Color3.fromRGB(238, 242, 250)
local GOLD = Color3.fromRGB(255, 200, 62)
local GREEN = Color3.fromRGB(120, 220, 150)

local boards: { [BasePart]: any } = {}
local vaults: { [BasePart]: any } = {}
-- Physical day-plinths in the Daily Rewards room, keyed by day number. Driven
-- from the SAME snapshot as the wall vault, so the two can never disagree.
local plinthLabels: { [number]: { billboard: BillboardGui, day: TextLabel, reward: TextLabel, state: TextLabel } } = {}
local plinthCaps: { [number]: { BasePart } } = {}
local lastFetch = 0
local lastVaultFetch = 0
local cached: any = nil

local function makeLabel(parent: Instance, size: UDim2, pos: UDim2, text: string, color: Color3, align: Enum.TextXAlignment, weight: Enum.FontWeight)
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = pos
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextXAlignment = align
	label.FontFace = Font.fromEnum(Enum.Font.GothamMedium)
	label.FontFace.Weight = weight
	label.Parent = parent
	return label
end

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
	--[[
		Back, not Front. A Part's Front face points along its LOCAL -Z, and the
		board is mounted flat against the back wall with no rotation - so Front
		would render the display into the wall behind it, invisible from the
		room. Back is +Z, which faces the doorway the player walks in through.
	]]
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

	-- Column headers
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
				-- Holding #1 is the one thing worth calling out visually.
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

--[[
	Builds the Streak Vault panel: seven day slots across the wall showing the
	full claim ring at once. Same structure-once/update-text-later approach as
	the Rival Board.
]]
local function buildVault(part: BasePart)
	if vaults[part] then
		return
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "StreakVaultGui"
	gui.Adornee = part
	-- Back = +Z, facing the doorway. See the Rival Board's note on Front/-Z.
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

	makeLabel(bg, UDim2.new(1, -40, 0, 54), UDim2.new(0, 20, 0, 14), "YOUR STREAK VAULT", TEXT_BRIGHT, Enum.TextXAlignment.Left, Enum.FontWeight.Bold)
	local status = makeLabel(bg, UDim2.new(1, -40, 0, 30), UDim2.new(0, 20, 0, 68), "Loading streak...", TEXT_DIM, Enum.TextXAlignment.Left, Enum.FontWeight.Regular)

	-- Seven slots across the panel.
	local rows = {}
	local slotWidth = 116
	for i = 1, 7 do
		local x = 20 + (i - 1) * (slotWidth + 8)

		local card = Instance.new("Frame")
		card.Size = UDim2.new(0, slotWidth, 0, 250)
		card.Position = UDim2.new(0, x, 0, 130)
		card.BackgroundColor3 = Color3.fromRGB(28, 31, 42)
		card.BorderSizePixel = 0
		card.Parent = bg

		local marker = Instance.new("Frame")
		marker.Size = UDim2.new(1, 0, 0, 6)
		marker.BackgroundColor3 = TEXT_DIM
		marker.BorderSizePixel = 0
		marker.Parent = card

		rows[i] = {
			card = card,
			marker = marker,
			day = makeLabel(card, UDim2.new(1, -12, 0, 34), UDim2.new(0, 6, 0, 18), "", TEXT_DIM, Enum.TextXAlignment.Center, Enum.FontWeight.Bold),
			reward = makeLabel(card, UDim2.new(1, -12, 0, 60), UDim2.new(0, 6, 0, 66), "", TEXT_BRIGHT, Enum.TextXAlignment.Center, Enum.FontWeight.Bold),
			state = makeLabel(card, UDim2.new(1, -12, 0, 34), UDim2.new(0, 6, 0, 190), "", TEXT_DIM, Enum.TextXAlignment.Center, Enum.FontWeight.Medium),
		}
	end

	vaults[part] = { gui = gui, rows = rows, status = status }
end

local function renderVault(snapshot: any)
	for _, vault in pairs(vaults) do
		if not snapshot then
			vault.status.Text = "Streak unavailable - try again shortly"
			continue
		end

		local track = snapshot.track or {}
		vault.status.Text = if snapshot.canClaimToday
			then "A reward is ready to claim today"
			else "Today's reward already collected - come back tomorrow"

		for i, row in ipairs(vault.rows) do
			local entry = track[i]
			if entry then
				row.card.Visible = true
				row.day.Text = ("DAY %d"):format(entry.day)
				row.reward.Text = entry.label or ""
				-- offsetFromToday == 0 is the next claim; anything the server
				-- marked collected is already banked this pass through the ring.
				if entry.collected then
					row.state.Text = "COLLECTED"
					row.marker.BackgroundColor3 = GREEN
					row.state.TextColor3 = GREEN
				elseif entry.offsetFromToday == 0 then
					row.state.Text = if snapshot.canClaimToday then "CLAIM NOW" else "NEXT"
					row.marker.BackgroundColor3 = GOLD
					row.state.TextColor3 = GOLD
				else
					row.state.Text = ("+%d days"):format(entry.offsetFromToday or i - 1)
					row.marker.BackgroundColor3 = TEXT_DIM
					row.state.TextColor3 = TEXT_DIM
				end
			else
				row.card.Visible = false
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

--[[
	Attaches a small floating label to one physical day-plinth. The plinth and
	its cap carry a "StreakDay" attribute set by the builder, which is how a
	world object is matched to its entry in the server snapshot without
	depending on instance names or ordering.
]]
local function buildPlinthLabel(part: BasePart)
	local day = part:GetAttribute("StreakDay")
	if typeof(day) ~= "number" or plinthLabels[day] then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StreakDayLabel"
	billboard.Adornee = part
	billboard.Size = UDim2.fromOffset(150, 90)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
	-- Only readable up close, on purpose: seven of these visible from across
	-- the plaza would be exactly the header clutter we removed earlier.
	billboard.MaxDistance = 45
	billboard.AlwaysOnTop = false
	billboard.Parent = part

	local dayLabel = makeLabel(billboard, UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 0, 0), "", TEXT_DIM, Enum.TextXAlignment.Center, Enum.FontWeight.Bold)
	local reward = makeLabel(billboard, UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, 26), "", TEXT_BRIGHT, Enum.TextXAlignment.Center, Enum.FontWeight.Bold)
	local state = makeLabel(billboard, UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 0, 62), "", TEXT_DIM, Enum.TextXAlignment.Center, Enum.FontWeight.Medium)

	plinthLabels[day] = { billboard = billboard, day = dayLabel, reward = reward, state = state }
end

local function registerCap(part: BasePart)
	local day = part:GetAttribute("StreakDay")
	if typeof(day) ~= "number" then
		return
	end
	plinthCaps[day] = plinthCaps[day] or {}
	table.insert(plinthCaps[day], part)
end

--[[
	Paints the physical plinths from the same snapshot the wall panel uses.

	The snapshot's track is REORDERED to start at today, so its array index is
	not the day number - entry.day is. The plinths are laid out Day 1..7 in
	space, so we match on entry.day rather than position in the array.
]]
local function renderPlinths(snapshot: any)
	if not snapshot or not snapshot.track then
		return
	end
	for _, entry in ipairs(snapshot.track) do
		local label = plinthLabels[entry.day]
		local colour = TEXT_DIM
		local stateText = ""

		if entry.collected then
			colour, stateText = GREEN, "COLLECTED"
		elseif entry.offsetFromToday == 0 then
			colour = GOLD
			stateText = if snapshot.canClaimToday then "CLAIM NOW" else "NEXT"
		else
			stateText = ("+%d days"):format(entry.offsetFromToday or 0)
		end

		if label then
			label.day.Text = ("DAY %d"):format(entry.day)
			label.reward.Text = entry.label or ""
			label.state.Text = stateText
			label.state.TextColor3 = colour
		end
		for _, cap in ipairs(plinthCaps[entry.day] or {}) do
			if cap.Parent then
				cap.Color = colour
			end
		end
	end
end

for _, part in ipairs(CollectionService:GetTagged("StreakVaultBoard")) do
	if part:IsA("BasePart") then
		buildVault(part)
	end
end
CollectionService:GetInstanceAddedSignal("StreakVaultBoard"):Connect(function(part)
	if part:IsA("BasePart") then
		buildVault(part)
	end
end)
CollectionService:GetInstanceRemovedSignal("StreakVaultBoard"):Connect(function(part)
	vaults[part] = nil
end)

for _, part in ipairs(CollectionService:GetTagged("StreakDayPlinth")) do
	if part:IsA("BasePart") then
		buildPlinthLabel(part)
	end
end
CollectionService:GetInstanceAddedSignal("StreakDayPlinth"):Connect(function(part)
	if part:IsA("BasePart") then
		buildPlinthLabel(part)
	end
end)
for _, part in ipairs(CollectionService:GetTagged("StreakDayCap")) do
	if part:IsA("BasePart") then
		registerCap(part)
	end
end
CollectionService:GetInstanceAddedSignal("StreakDayCap"):Connect(function(part)
	if part:IsA("BasePart") then
		registerCap(part)
	end
end)

--[[
	Fetch on approach. Deliberately not a fixed timer: a player who never
	enters the Statistics building should never invoke this remote at all.
]]
local remote: RemoteFunction? = nil
local vaultRemote: RemoteFunction? = nil
task.spawn(function()
	remote = RemoteFunctions.Get("GetRivalComparison")
end)
task.spawn(function()
	-- Owned by DailyRewardsSystem, not by this controller - the vault reads
	-- the same server-computed snapshot the Daily popup does.
	vaultRemote = RemoteFunctions.Get("GetDailyRewardSnapshot")
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
			-- InvokeServer can throw if the server handler errors or the player
			-- leaves mid-call; a raised error here would kill this Heartbeat
			-- connection and neither board would ever update again.
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

	-- Streak Vault (wall panel) and the physical day-plinths, both from one
	-- snapshot. `next(vaults)` gates the fetch because the plinths and the
	-- panel are always built together in the same room.
	if vaultRemote and next(vaults) ~= nil and nearAny(vaults, rootPos) and (now - lastVaultFetch) >= REFRESH_SECONDS then
		lastVaultFetch = now
		task.spawn(function()
			local ok, snapshot = pcall(function()
				return (vaultRemote :: RemoteFunction):InvokeServer()
			end)
			local data = if ok then snapshot else nil
			renderVault(data)
			renderPlinths(data)
		end)
	end
end)
