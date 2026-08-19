--[[
	LeaderboardBoards.lua

	Builds the five separate physical leaderboard boards (Wins, XP,
	Questions Solved, Accuracy, Fastest Answer), arranged in an
	approximately 120-degree arc within the existing leaderboard region
	(the position/footprint LobbyConfig.BUILDINGS' "LeaderboardHall" entry
	has always described). This REPLACES the earlier single combined
	board (one big SurfaceGui with 5 columns) with five independently
	named, independently scrollable boards - see Buildings.lua for the
	call site.

	Each board is a small futuristic screen (plinth, support posts, a
	neon-framed panel) carrying a SurfaceGui with:
		- a title (the category's display name)
		- a ScrollingFrame of up to LeaderboardConfig.TOP_LIMIT (100) rows,
		  pre-built here with placeholder text; LeaderboardDisplay (a
		  separate server module) fills in live values on its refresh
		  cadence. This module never talks to a DataStore itself.

	Row1/Row2/Row3 get their podium (gold/silver/bronze) rank-badge color
	baked in at BUILD time, not refresh time - since rows are always
	ordered by rank, Row1 is always "whoever is #1 right now", so the
	styling never needs to be recomputed on refresh (only the text does).
	Row1's rank badge is also CollectionService-tagged so a single shared
	client script can drive its subtle glow pulse across all five boards
	at once, rather than five separate animation loops.

	All five boards share identical size/styling; only accentColor (see
	LeaderboardConfig) and the title text differ - "consistent styling,
	subtle per-category accent" per the design spec.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)
local LeaderboardConfig = require(ServerScriptService.LeaderboardConfig)

local LeaderboardBoards = {}

-- Tag used by StarterPlayerScripts/LeaderboardPodiumGlowController.client.lua
-- to find every board's 1st-place rank badge without hardcoding five paths.
local GOLD_GLOW_TAG = "LeaderboardGoldGlow"

local function buildRow(scroll: ScrollingFrame, rank: number)
	local row = Instance.new("Frame")
	row.Name = "Row" .. rank
	row.LayoutOrder = rank
	row.Size = UDim2.new(1, 0, 0, LeaderboardConfig.ROW_HEIGHT_PIXELS)
	row.BackgroundTransparency = 1
	row.Parent = scroll

	local podiumColor = LeaderboardConfig.PODIUM_COLORS[rank]
	local badgeSize = if rank == 1 then 48 elseif rank <= 3 then 42 else 36

	local badge = Instance.new("Frame")
	badge.Name = "RankBadge"
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.new(0, 8, 0.5, 0)
	badge.Size = UDim2.fromOffset(badgeSize, badgeSize)
	badge.BackgroundColor3 = podiumColor or Color3.fromRGB(50, 53, 62)
	badge.BorderSizePixel = 0
	badge.Parent = row

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(1, 0)
	badgeCorner.Parent = badge

	if rank == 1 then
		CollectionService:AddTag(badge, GOLD_GLOW_TAG)
	end

	local rankLabel = Instance.new("TextLabel")
	rankLabel.Name = "RankLabel"
	rankLabel.Size = UDim2.fromScale(1, 1)
	rankLabel.BackgroundTransparency = 1
	rankLabel.Font = if rank <= 3 then Enum.Font.GothamBlack else Enum.Font.GothamBold
	rankLabel.TextScaled = true
	rankLabel.TextColor3 = if podiumColor then Color3.new(0, 0, 0) else Color3.fromRGB(230, 230, 235)
	rankLabel.Text = tostring(rank)
	rankLabel.Parent = badge

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.AnchorPoint = Vector2.new(0, 0.5)
	nameLabel.Position = UDim2.new(0, 8 + badgeSize + 12, 0.5, 0)
	nameLabel.Size = UDim2.new(1, -(8 + badgeSize + 12) - 130, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = if rank == 1 then Enum.Font.GothamBlack else Enum.Font.Gotham
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = Color3.fromRGB(230, 230, 235)
	nameLabel.Text = "-"
	nameLabel.Parent = row

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "ValueLabel"
	valueLabel.AnchorPoint = Vector2.new(1, 0.5)
	valueLabel.Position = UDim2.new(1, -8, 0.5, 0)
	valueLabel.Size = UDim2.fromOffset(120, LeaderboardConfig.ROW_HEIGHT_PIXELS - 8)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = if rank == 1 then Enum.Font.GothamBlack else Enum.Font.GothamBold
	valueLabel.TextScaled = true
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.TextColor3 = Color3.fromRGB(230, 230, 235)
	valueLabel.Text = "-"
	valueLabel.Parent = row
end

local function buildDisplay(panel: BasePart, category)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardDisplay"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = LeaderboardConfig.GUI_CANVAS_SIZE
	gui.Parent = panel

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, 0, 0, LeaderboardConfig.TITLE_HEIGHT_PIXELS)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.Oswald
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = category.accentColor
	titleLabel.Text = category.displayName:upper()
	titleLabel.Parent = root

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "EntriesScroll"
	scroll.Position = UDim2.new(0, 0, 0, LeaderboardConfig.TITLE_HEIGHT_PIXELS)
	scroll.Size = UDim2.new(1, 0, 1, -LeaderboardConfig.TITLE_HEIGHT_PIXELS)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Active = true -- required for the ScrollingFrame to accept mouse/touch scroll input
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = category.accentColor
	scroll.CanvasSize = UDim2.new(0, 0, 0, LeaderboardConfig.TOP_LIMIT * LeaderboardConfig.ROW_HEIGHT_PIXELS)
	scroll.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	for rank = 1, LeaderboardConfig.TOP_LIMIT do
		buildRow(scroll, rank)
	end
end

--[[
	Builds one board model for `category`, positioned/oriented along the
	arc, and parents it directly into `parent` (the Buildings folder) -
	each board is a top-level sibling of Shop/DailyRewards/etc, named
	category.boardName, not nested under a shared "hall" model.

	`facingYawDegrees` (Message 18/19/20) rotates the arc's POSITION shape
	as a rigid group so its center can sit anywhere on the map - 0 (the
	original default) faces north/+Z. This only affects where the board
	CENTERS end up, though; each board's actual facing direction (Message
	21) is computed separately below via an exact look-at toward
	LeaderboardConfig.VIEW_FOCAL_POINT, not derived from this yaw at all.

	Message 21 fix (section 2, "the end two leaderboards are not properly
	visible"): the PREVIOUS orientation formula rotated each board by
	(-angleDegrees + yaw) - a reasonable-looking approximation that fans
	each board inward by an amount proportional to its position along the
	arc, assuming that produces a curve converging on the viewing area.
	It doesn't, in general - measured with the actual arc/anchor geometry,
	the two end boards ended up facing about 32 degrees off from the real
	viewing area near the map's center, while the middle boards were only
	off by a few degrees, which is exactly the "end boards aren't visible"
	symptom. The actual fix is to stop approximating and directly aim each
	board's face at one explicit point - correct by construction for every
	board, including the two ends, regardless of how the arc is
	repositioned/resized in the future.
]]
local function buildOneBoard(category, angleDegrees: number, arcCenter: Vector3, parent: Instance, facingYawDegrees: number?)
	local yaw = facingYawDegrees or 0
	local angleRad = math.rad(angleDegrees)

	-- Shallow concave bow: wide horizontal spread (ARC_SPREAD_RADIUS),
	-- but only a small depth variation (ARC_DEPTH) so the flanking boards
	-- don't push out past the lobby floor - see the module doc comment
	-- in LeaderboardConfig.lua for why this isn't a true arc radius. This
	-- local offset is computed in the arc's OWN frame (as if facing north)
	-- and then rotated by the group's facing yaw, so the fan shape itself
	-- never changes regardless of which way the whole group points.
	local localOffset = Vector3.new(
		LeaderboardConfig.ARC_SPREAD_RADIUS * math.sin(angleRad),
		0,
		-LeaderboardConfig.ARC_DEPTH * (1 - math.cos(angleRad))
	)
	local yawRotation = CFrame.Angles(0, math.rad(yaw), 0)
	local boardPosition = arcCenter + (yawRotation * localOffset)

	-- Orientation: aim this board's Back face (where the SurfaceGui and
	-- the neon frame both live) directly at the shared focal point, so
	-- every board - including the two ends - genuinely faces the viewing
	-- area rather than an approximation of it.
	local toFocal = LeaderboardConfig.VIEW_FOCAL_POINT - boardPosition
	local facingYaw = math.atan2(toFocal.X, toFocal.Z)
	local baseCFrame = CFrame.new(boardPosition) * CFrame.Angles(0, facingYaw, 0)

	local model = Instance.new("Model")
	model.Name = category.boardName
	model:SetAttribute(category.boardName, true)

	local width = LeaderboardConfig.BOARD_WIDTH
	local height = LeaderboardConfig.BOARD_HEIGHT
	local plinthDepth = 5
	local plinthY = 0.5
	local postHeight = 4
	local panelBottomY = plinthY + postHeight

	PartUtils.CreatePart({
		name = "Plinth",
		size = Vector3.new(width + 2, 1, plinthDepth),
		cframe = baseCFrame * CFrame.new(0, plinthY, 0),
		material = Enum.Material.Metal,
		color = Color3.fromRGB(45, 48, 56),
		parent = model,
	})
	PartUtils.CreatePart({
		name = "PlinthTrim",
		size = Vector3.new(width + 2.3, 0.2, plinthDepth + 0.3),
		cframe = baseCFrame * CFrame.new(0, plinthY + 0.55, 0),
		material = Enum.Material.Neon,
		color = category.accentColor,
		canCollide = false,
		parent = model,
	})

	-- Two simple support posts (kept as plain vertical posts rather than
	-- angled wedges - with five of these on screen at once, simpler
	-- geometry keeps both the look "clean" per spec and the part count
	-- performant).
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "SupportPost",
			size = Vector3.new(1, postHeight, 1),
			cframe = baseCFrame * CFrame.new(side * (width / 2 - 1), plinthY + postHeight / 2, 0),
			material = Enum.Material.Metal,
			color = Color3.fromRGB(45, 48, 56),
			canCollide = false,
			parent = model,
		})
	end

	local panel = PartUtils.CreatePart({
		name = "Base",
		size = Vector3.new(width, height, 1),
		cframe = baseCFrame * CFrame.new(0, panelBottomY + height / 2, 0),
		material = Enum.Material.Metal,
		color = Color3.fromRGB(20, 22, 28),
		parent = model,
	})
	model.PrimaryPart = panel

	-- Thin neon frame - "simple, clean futuristic frame", not a heavy
	-- decorated border.
	PartUtils.CreatePart({
		name = "FrameTop",
		size = Vector3.new(width + 0.6, 0.3, 1.3),
		cframe = baseCFrame * CFrame.new(0, panelBottomY + height + 0.15, 0),
		material = Enum.Material.Neon,
		color = category.accentColor,
		canCollide = false,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "FrameBottom",
		size = Vector3.new(width + 0.6, 0.3, 1.3),
		cframe = baseCFrame * CFrame.new(0, panelBottomY - 0.15, 0),
		material = Enum.Material.Neon,
		color = category.accentColor,
		canCollide = false,
		parent = model,
	})
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "FrameSide",
			size = Vector3.new(0.3, height + 0.6, 1.3),
			cframe = baseCFrame * CFrame.new(side * (width / 2 + 0.15), panelBottomY + height / 2, 0),
			material = Enum.Material.Neon,
			color = category.accentColor,
			canCollide = false,
			parent = model,
		})
	end

	local glow = Instance.new("PointLight")
	glow.Color = category.accentColor
	glow.Range = LightingConfig.ACCENT_LIGHT_RANGE
	glow.Brightness = LightingConfig.ACCENT_LIGHT_BRIGHTNESS * 0.9 -- calmer-lighting pass: five of these sit close together along the arc, so kept a touch below the shared reference
	glow.Parent = panel

	buildDisplay(panel, category)

	model.Parent = parent
	return model
end

--[[
	Builds all five boards, fanned across LeaderboardConfig.ARC_TOTAL_DEGREES
	centered on `def.position` (LobbyConfig.LEADERBOARD_ANCHOR - its own
	dedicated region, not a LobbyConfig.BUILDINGS entry). `def.facingYawDegrees`
	is optional (defaults to 0/north-facing, the original behavior).
]]
function LeaderboardBoards.BuildAll(def, parent: Instance)
	local categories = LeaderboardConfig.CATEGORIES
	local count = #categories
	local totalDegrees = LeaderboardConfig.ARC_TOTAL_DEGREES
	local step = if count > 1 then totalDegrees / (count - 1) else 0
	local startAngle = -totalDegrees / 2

	for i, category in ipairs(categories) do
		local angleDegrees = startAngle + step * (i - 1)
		buildOneBoard(category, angleDegrees, def.position, parent, def.facingYawDegrees)
	end
end

return LeaderboardBoards
