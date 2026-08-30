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

local TutorialTopicsConfig = require(ReplicatedStorage.Modules.TutorialTopicsConfig)

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

local screens: { [BasePart]: any } = {}

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

local function buildScreen(part: BasePart)
	if screens[part] then
		return
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "TutorialScreenGui"
	gui.Adornee = part
	-- Back = +Z. A Part's Front face is its local -Z, which here points into
	-- the wall the screen is mounted on.
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

	local counter = makeLabel(bg, UDim2.new(0, 300, 0, 28), UDim2.new(0, 30, 0, 22), "", ACCENT, Enum.FontWeight.Bold)
	counter.TextSize = 24

	local title = makeLabel(bg, UDim2.new(1, -60, 0, 56), UDim2.new(0, 30, 0, 54), "", TEXT_BRIGHT, Enum.FontWeight.Bold)
	title.TextSize = 46

	local body = makeLabel(bg, UDim2.new(1, -60, 0, 250), UDim2.new(0, 30, 0, 122), "", TEXT_DIM, Enum.FontWeight.Regular)
	body.TextSize = 26
	body.TextWrapped = true

	local hint = makeLabel(bg, UDim2.new(1, -60, 0, 28), UDim2.new(0, 30, 0, 404), "Use the panels either side of this screen to change topic", ACCENT, Enum.FontWeight.Medium)
	hint.TextSize = 20

	-- Progress pips, one per topic, so a seated player can see how far
	-- through the set they are without counting.
	local pips = {}
	for i = 1, #TOPICS do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.new(0, 40, 0, 6)
		pip.Position = UDim2.new(0, 30 + (i - 1) * 48, 0, 386)
		pip.BorderSizePixel = 0
		pip.BackgroundColor3 = TEXT_DIM
		pip.Parent = bg
		pips[i] = pip
	end

	screens[part] = { gui = gui, counter = counter, title = title, body = body, pips = pips }
end

local function render()
	local topic = TOPICS[currentIndex]
	if not topic then
		return
	end
	for _, screen in pairs(screens) do
		screen.counter.Text = ("TOPIC %d OF %d"):format(currentIndex, #TOPICS)
		screen.title.Text = topic.title
		screen.body.Text = topic.body
		for i, pip in ipairs(screen.pips) do
			pip.BackgroundColor3 = if i == currentIndex then ACCENT else TEXT_DIM
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
	buildScreen(part)
	render()
end)
CollectionService:GetInstanceRemovedSignal("TutorialScreen"):Connect(function(part)
	screens[part] = nil
end)

bindTag("TutorialPrev", function(part)
	wireButton(part, -1)
end)
bindTag("TutorialNext", function(part)
	wireButton(part, 1)
end)

render()
