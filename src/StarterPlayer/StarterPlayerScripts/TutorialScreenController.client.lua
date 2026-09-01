--[[
	TutorialScreenController.client.lua

	Drives the tutorial wall screen inside the Tutorial building - the seven
	topics presented on a large screen with lecture seating in front of it,
	paged with two physical buttons either side.

	RELATIONSHIP TO THE BOTTOM-BAR BUTTON. The Tutorial button on the bottom
	bar is deliberately unchanged and still opens the overlay. This screen is
	an ADDITIONAL way to read the same content, not a replacement - a player
	who wants the text immediately never has to walk anywhere. The building
	version is for reading it properly, sat down, without a popup covering
	the game.

	ONE SOURCE OF TEXT. Both surfaces require
	ReplicatedStorage.Modules.TutorialTopicsConfig. The topics were
	previously a local table inside TutorialUIController; they were moved out
	specifically so this screen could show identical content without a second
	copy that would drift on the next wording change.

	NO SERVER INVOLVEMENT. The topics are static text shipped in a shared
	module and the paging state is per-client, so there is nothing to
	validate and nothing worth spending a remote on. Contrast the Rival Board
	and Streak Vault, which show per-player data and therefore must be
	server-computed.

	PHYSICAL BUTTONS, NOT GUI BUTTONS. Paging uses ClickDetectors on real
	parts. A transparent GUI button laid over world space swallows clicks
	meant for anything behind it - the same reason the building teleport
	signs moved to ClickDetectors.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local TutorialTopicsConfig = require(ReplicatedStorage.Modules.TutorialTopicsConfig)
local MapsConfig = require(ReplicatedStorage.Modules.MapsConfig)

local TOPICS = TutorialTopicsConfig.TOPICS

local CANVAS = Vector2.new(900, 460)
local BG = Color3.fromRGB(16, 18, 26)
local TEXT_DIM = Color3.fromRGB(150, 158, 178)
local TEXT_BRIGHT = Color3.fromRGB(238, 242, 250)
local ACCENT = Color3.fromRGB(120, 200, 255)

-- Paging state is shared across every tutorial screen this client can see.
-- In practice there is one per map, but keeping a single index means two
-- screens can never disagree about which topic is showing.
local currentIndex = 1

-- One table per wall. Keyed by the screen Part so a rebuilt map's new parts
-- replace the old entries cleanly.
local centreScreens: { [BasePart]: any } = {}
local leftScreens: { [BasePart]: any } = {}
local rightScreens: { [BasePart]: any } = {}

--[[
	Which map is this screen standing in?

	Every map builds the same Tutorial building translated by its own origin,
	so the screen's own ancestry is an exact answer - walk up to the direct
	child of Workspace and match its name against MapsConfig. This is what
	lets the centre wall show THIS arena rather than a generic image: a
	player sitting in the Under the Sea tutorial sees Under the Sea.
]]
local function mapIdFor(part: BasePart): string?
	local node: Instance? = part
	while node and node.Parent ~= Workspace do
		node = node.Parent
	end
	if not node then
		return nil
	end
	for _, def in ipairs(MapsConfig.MAPS) do
		if def.workspaceFolderName == node.Name then
			return def.id
		end
	end
	return nil
end

local function makeLabel(parent: Instance, size: UDim2, pos: UDim2, text: string, color: Color3, weight: Enum.FontWeight)
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = pos
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.FontFace = Font.fromEnum(Enum.Font.GothamMedium)
	label.FontFace.Weight = weight
	label.Parent = parent
	return label
end

--[[
	Shared surface setup. Every wall uses the same canvas, background and
	face, so they read as one installation rather than three unrelated
	panels.
]]
local function makeSurface(part: BasePart, name: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Adornee = part
	-- Back = +Z. A Part's Front face is its local -Z, which here points into
	-- the wall the screen is mounted on. The side walls are yawed 90 degrees
	-- when built, so this same face ends up pointing across the room.
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

	return gui, bg
end

--[[
	CENTRE WALL: the map image with a short clip looping over it, the topic's
	caption, the topic counter and the progress pips.

	The VideoFrame sits ON TOP of the ImageLabel deliberately. The still is
	the fallback: if the clip has no id set, or fails to load, or is still
	moderating, the image underneath is what the player sees instead of a
	black rectangle. If neither is set, the labelled placeholder shows which
	asset is missing rather than failing silently.
]]
local function buildCentre(part: BasePart)
	if centreScreens[part] then
		return
	end

	local gui, bg = makeSurface(part, "TutorialScreenGui")

	local counter = makeLabel(bg, UDim2.new(0, 300, 0, 28), UDim2.new(0, 30, 0, 22), "", ACCENT, Enum.FontWeight.Bold)
	counter.TextSize = 24

	-- Media stage. Fixed 16:9-ish block so the image and clip always agree.
	local stage = Instance.new("Frame")
	stage.Size = UDim2.new(1, -60, 0, 264)
	stage.Position = UDim2.new(0, 30, 0, 58)
	stage.BackgroundColor3 = Color3.fromRGB(8, 9, 13)
	stage.BorderSizePixel = 0
	stage.ClipsDescendants = true
	stage.Parent = bg

	local image = Instance.new("ImageLabel")
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Crop
	image.Image = ""
	image.Parent = stage

	local video = Instance.new("VideoFrame")
	video.Size = UDim2.fromScale(1, 1)
	video.BackgroundTransparency = 1
	video.Looped = true
	video.Volume = 0
	video.Video = ""
	video.Visible = false
	video.Parent = stage

	local placeholder = makeLabel(stage, UDim2.new(1, -40, 1, -40), UDim2.new(0, 20, 0, 20), "", TEXT_DIM, Enum.FontWeight.Medium)
	placeholder.TextSize = 22
	placeholder.TextWrapped = true
	placeholder.TextXAlignment = Enum.TextXAlignment.Center
	placeholder.TextYAlignment = Enum.TextYAlignment.Center

	local caption = makeLabel(bg, UDim2.new(1, -60, 0, 44), UDim2.new(0, 30, 0, 332), "", TEXT_BRIGHT, Enum.FontWeight.Bold)
	caption.TextSize = 34

	local hint = makeLabel(bg, UDim2.new(1, -60, 0, 28), UDim2.new(0, 30, 0, 404), "Use the panels either side of this screen to change topic", ACCENT, Enum.FontWeight.Medium)
	hint.TextSize = 20

	-- Progress pips, one per topic, so a seated player can see how far
	-- through the set they are without counting. Width is divided across the
	-- canvas rather than fixed, since the topic list is now long enough that
	-- fixed-width pips would run off the panel.
	local pips = {}
	local pipWidth = math.max(6, math.floor(840 / #TOPICS) - 4)
	for i = 1, #TOPICS do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.new(0, pipWidth, 0, 6)
		pip.Position = UDim2.new(0, 30 + (i - 1) * (pipWidth + 4), 0, 386)
		pip.BorderSizePixel = 0
		pip.BackgroundColor3 = TEXT_DIM
		pip.Parent = bg
		pips[i] = pip
	end

	centreScreens[part] = {
		gui = gui,
		counter = counter,
		caption = caption,
		image = image,
		video = video,
		placeholder = placeholder,
		pips = pips,
		media = TutorialTopicsConfig.GetMapMedia(mapIdFor(part)),
		mediaApplied = false,
	}
end

--[[
	LEFT WALL: the topic's title and full description. This is the wall a
	player actually reads, so it gets the whole canvas for prose and nothing
	else competing for attention.
]]
local function buildLeft(part: BasePart)
	if leftScreens[part] then
		return
	end

	local gui, bg = makeSurface(part, "TutorialScreenLeftGui")

	local kicker = makeLabel(bg, UDim2.new(0, 400, 0, 26), UDim2.new(0, 34, 0, 26), "WHAT IT IS", ACCENT, Enum.FontWeight.Bold)
	kicker.TextSize = 22

	local title = makeLabel(bg, UDim2.new(1, -68, 0, 62), UDim2.new(0, 34, 0, 58), "", TEXT_BRIGHT, Enum.FontWeight.Bold)
	title.TextSize = 48

	local rule = Instance.new("Frame")
	rule.Size = UDim2.new(1, -68, 0, 3)
	rule.Position = UDim2.new(0, 34, 0, 126)
	rule.BorderSizePixel = 0
	rule.BackgroundColor3 = ACCENT
	rule.Parent = bg

	local body = makeLabel(bg, UDim2.new(1, -68, 0, 292), UDim2.new(0, 34, 0, 146), "", TEXT_DIM, Enum.FontWeight.Regular)
	body.TextSize = 28
	body.TextWrapped = true

	leftScreens[part] = { gui = gui, title = title, body = body }
end

--[[
	RIGHT WALL: the topic's tips, one per row. Rows are built once at the
	maximum tip count across all topics and then shown or hidden per topic,
	so paging never rebuilds instances.
]]
local MAX_TIPS = (function()
	local most = 0
	for _, topic in ipairs(TOPICS) do
		local count = topic.tips and #topic.tips or 0
		if count > most then
			most = count
		end
	end
	return math.max(most, 1)
end)()

local function buildRight(part: BasePart)
	if rightScreens[part] then
		return
	end

	local gui, bg = makeSurface(part, "TutorialScreenRightGui")

	local kicker = makeLabel(bg, UDim2.new(0, 400, 0, 26), UDim2.new(0, 34, 0, 26), "TIPS & HEADS-UPS", ACCENT, Enum.FontWeight.Bold)
	kicker.TextSize = 22

	local rule = Instance.new("Frame")
	rule.Size = UDim2.new(1, -68, 0, 3)
	rule.Position = UDim2.new(0, 34, 0, 68)
	rule.BorderSizePixel = 0
	rule.BackgroundColor3 = ACCENT
	rule.Parent = bg

	local rows = {}
	for i = 1, MAX_TIPS do
		local top = 96 + (i - 1) * 104

		local bullet = Instance.new("Frame")
		bullet.Size = UDim2.new(0, 10, 0, 10)
		bullet.Position = UDim2.new(0, 36, 0, top + 10)
		bullet.BorderSizePixel = 0
		bullet.BackgroundColor3 = ACCENT
		bullet.Parent = bg

		local text = makeLabel(bg, UDim2.new(1, -100, 0, 92), UDim2.new(0, 62, 0, top), "", TEXT_BRIGHT, Enum.FontWeight.Medium)
		text.TextSize = 27
		text.TextWrapped = true

		rows[i] = { bullet = bullet, text = text }
	end

	rightScreens[part] = { gui = gui, rows = rows }
end

--[[
	Applies the map's image/clip ids once per centre screen.

	The media never changes with the topic - it is the ARENA the player is
	standing in - so this runs once rather than on every page turn, and a
	VideoFrame that is already playing is never restarted mid-loop.
]]
local function applyMedia(screen)
	if screen.mediaApplied then
		return
	end
	screen.mediaApplied = true

	local media = screen.media
	local hasImage = (media.imageId or 0) > 0
	local hasVideo = (media.videoId or 0) > 0

	if hasImage then
		screen.image.Image = ("rbxassetid://%d"):format(media.imageId)
	end

	if hasVideo then
		screen.video.Video = ("rbxassetid://%d"):format(media.videoId)
		screen.video.Visible = true
		screen.video:Play()
	end

	if hasImage or hasVideo then
		screen.placeholder.Text = ""
	else
		-- Names the map so it is obvious WHICH entry in
		-- TutorialTopicsConfig.MAP_MEDIA still needs ids pasted in.
		screen.placeholder.Text = ("%s\n\nNo image or clip set yet.\nAdd the asset ids to TutorialTopicsConfig.MAP_MEDIA."):format(media.label)
	end
end

local function render()
	local topic = TOPICS[currentIndex]
	if not topic then
		return
	end

	for _, screen in pairs(centreScreens) do
		applyMedia(screen)
		screen.counter.Text = ("TOPIC %d OF %d"):format(currentIndex, #TOPICS)
		screen.caption.Text = topic.caption or topic.title
		for i, pip in ipairs(screen.pips) do
			pip.BackgroundColor3 = if i == currentIndex then ACCENT else TEXT_DIM
		end
	end

	for _, screen in pairs(leftScreens) do
		screen.title.Text = topic.title
		screen.body.Text = topic.body
	end

	local tips = topic.tips or {}
	for _, screen in pairs(rightScreens) do
		for i, row in ipairs(screen.rows) do
			local tip = tips[i]
			row.text.Text = tip or ""
			-- Hide the bullet too, so an unused row leaves no orphan dot.
			row.bullet.Visible = tip ~= nil
		end
	end
end

local function step(delta: number)
	-- Wrap rather than clamp, so paging past either end continues round the
	-- set instead of dead-ending on a button that silently does nothing.
	currentIndex = ((currentIndex - 1 + delta) % #TOPICS) + 1
	render()
end

local function wireButton(part: BasePart, delta: number)
	local click = part:FindFirstChildOfClass("ClickDetector")
	if not click then
		return
	end
	click.MouseClick:Connect(function()
		step(delta)
	end)
end

local function bindTag(tag: string, handler: (BasePart) -> ())
	for _, part in ipairs(CollectionService:GetTagged(tag)) do
		if part:IsA("BasePart") then
			handler(part)
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(part)
		if part:IsA("BasePart") then
			handler(part)
		end
	end)
end

bindTag("TutorialScreen", function(part)
	buildCentre(part)
	render()
end)
CollectionService:GetInstanceRemovedSignal("TutorialScreen"):Connect(function(part)
	centreScreens[part] = nil
end)

bindTag("TutorialScreenLeft", function(part)
	buildLeft(part)
	render()
end)
CollectionService:GetInstanceRemovedSignal("TutorialScreenLeft"):Connect(function(part)
	leftScreens[part] = nil
end)

bindTag("TutorialScreenRight", function(part)
	buildRight(part)
	render()
end)
CollectionService:GetInstanceRemovedSignal("TutorialScreenRight"):Connect(function(part)
	rightScreens[part] = nil
end)

bindTag("TutorialPrev", function(part)
	wireButton(part, -1)
end)
bindTag("TutorialNext", function(part)
	wireButton(part, 1)
end)

render()
