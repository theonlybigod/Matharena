--[[
	WorkspacePadController.client.lua

	The scratch pad: a square WORKSPACE button beside the question box that
	expands into a split view - the current question on the left, a
	free-drawing surface on the right - so a player can work something out
	rather than holding it in their head.

	WHY A CANVAS OF FRAMES. Roblox has no drawing primitive for a GUI, so
	each stroke segment is a thin rotated Frame laid between consecutive
	mouse positions. That is the standard approach and it is cheap, but it
	does mean a stroke's cost is proportional to how far the pointer moved,
	which is why MIN_SEGMENT guards against emitting a segment for sub-pixel
	jitter and MAX_SEGMENTS caps a runaway session.

	THE ERASER IS NOT AN UNDO. It removes whole segments it touches, several
	times thicker than the pen per spec, so it behaves like a real eraser
	rubbing things out rather than stepping back through history.

	DIMMING THE REST. Opening the pad shrinks and fades the other on-screen
	UI so the split view is what the player is looking at. Anything the
	controller dims is restored exactly on close, including for GUIs that
	appeared while the pad was open.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PANEL = Color3.fromRGB(24, 27, 36)
local CANVAS_BG = Color3.fromRGB(18, 20, 27)
local TEXT = Color3.fromRGB(232, 238, 248)
local ACCENT = Color3.fromRGB(70, 150, 230)

local PEN_COLOR = Color3.fromRGB(255, 255, 255) -- white, per spec
local PEN_THICKNESS = 3
local ERASER_THICKNESS = PEN_THICKNESS * 6 -- "a few times thicker than the pen"

local MIN_SEGMENT = 2 -- pixels; below this the pointer has effectively not moved
local MAX_SEGMENTS = 4000 -- hard ceiling so a long session cannot spiral

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "WorkspacePadGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 60
screenGui.Parent = playerGui

----------------------------------------------------------------------
-- The small square launcher, sat beside the question box.
----------------------------------------------------------------------

local launcher = Instance.new("TextButton")
launcher.Name = "WorkspaceLauncher"
launcher.Size = UDim2.fromOffset(56, 56)
launcher.AnchorPoint = Vector2.new(1, 0.5)
launcher.Position = UDim2.new(1, -24, 0.5, 0)
launcher.BackgroundColor3 = PANEL
launcher.AutoButtonColor = false
launcher.Text = "WORK\nSPACE"
launcher.TextColor3 = TEXT
launcher.TextSize = 11
launcher.Font = Enum.Font.GothamBold
launcher.BorderSizePixel = 0
launcher.Visible = false
launcher.Parent = screenGui

local launcherCorner = Instance.new("UICorner")
launcherCorner.CornerRadius = UDim.new(0, 8)
launcherCorner.Parent = launcher

local launcherStroke = Instance.new("UIStroke")
launcherStroke.Color = ACCENT
launcherStroke.Thickness = 1
launcherStroke.Transparency = 0.4
launcherStroke.Parent = launcher

----------------------------------------------------------------------
-- The expanded split view.
----------------------------------------------------------------------

local overlay = Instance.new("Frame")
overlay.Name = "WorkspaceOverlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.35
overlay.BorderSizePixel = 0
overlay.Visible = false
overlay.Parent = screenGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.new(0.86, 0, 0.8, 0)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = PANEL
panel.BorderSizePixel = 0
panel.Parent = overlay

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

-- Left half: the question as it currently stands.
local questionHalf = Instance.new("Frame")
questionHalf.Name = "QuestionHalf"
questionHalf.Size = UDim2.new(0.5, -18, 1, -84)
questionHalf.Position = UDim2.fromOffset(12, 60)
questionHalf.BackgroundColor3 = CANVAS_BG
questionHalf.BorderSizePixel = 0
questionHalf.Parent = panel

local qCorner = Instance.new("UICorner")
qCorner.CornerRadius = UDim.new(0, 8)
qCorner.Parent = questionHalf

local questionLabel = Instance.new("TextLabel")
questionLabel.Size = UDim2.new(1, -28, 1, -28)
questionLabel.Position = UDim2.fromOffset(14, 14)
questionLabel.BackgroundTransparency = 1
questionLabel.Text = ""
questionLabel.TextColor3 = TEXT
questionLabel.TextSize = 40
questionLabel.Font = Enum.Font.GothamBold
questionLabel.TextWrapped = true
questionLabel.TextXAlignment = Enum.TextXAlignment.Left
questionLabel.TextYAlignment = Enum.TextYAlignment.Center
questionLabel.Parent = questionHalf

-- Right half: the drawing surface. ClipsDescendants keeps strokes inside
-- the pad even when the pointer leaves it mid-drag.
local canvas = Instance.new("Frame")
canvas.Name = "Canvas"
canvas.Size = UDim2.new(0.5, -18, 1, -84)
canvas.Position = UDim2.new(0.5, 6, 0, 60)
canvas.BackgroundColor3 = CANVAS_BG
canvas.BorderSizePixel = 0
canvas.ClipsDescendants = true
canvas.Parent = panel

local canvasCorner = Instance.new("UICorner")
canvasCorner.CornerRadius = UDim.new(0, 8)
canvasCorner.Parent = canvas

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 40)
title.Position = UDim2.fromOffset(16, 12)
title.BackgroundTransparency = 1
title.Text = "WORKSPACE"
title.TextColor3 = ACCENT
title.TextSize = 18
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

----------------------------------------------------------------------
-- Tools.
----------------------------------------------------------------------

local currentTool: "Pen" | "Eraser" = "Pen"

local function makeToolButton(name: string, text: string, offsetX: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromOffset(96, 30)
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, offsetX, 1, -14)
	b.BackgroundColor3 = CANVAS_BG
	b.AutoButtonColor = false
	b.Text = text
	b.TextColor3 = TEXT
	b.TextSize = 14
	b.Font = Enum.Font.GothamMedium
	b.BorderSizePixel = 0
	b.Parent = panel

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = b

	local s = Instance.new("UIStroke")
	s.Color = ACCENT
	s.Thickness = 1
	s.Transparency = 0.6
	s.Name = "Stroke"
	s.Parent = b

	return b
end

local closeButton = makeToolButton("CloseButton", "CLOSE", -14)
local clearButton = makeToolButton("ClearButton", "CLEAR", -118)
local eraserButton = makeToolButton("EraserButton", "ERASER", -222)
local penButton = makeToolButton("PenButton", "PEN", -326)

local function refreshToolButtons()
	for tool, b in pairs({ Pen = penButton, Eraser = eraserButton }) do
		local active = currentTool == tool
		local s = b:FindFirstChild("Stroke") :: UIStroke
		s.Transparency = if active then 0 else 0.6
		s.Thickness = if active then 2 else 1
		b.BackgroundColor3 = if active then PANEL else CANVAS_BG
	end
end

penButton.MouseButton1Click:Connect(function()
	currentTool = "Pen"
	refreshToolButtons()
end)
eraserButton.MouseButton1Click:Connect(function()
	currentTool = "Eraser"
	refreshToolButtons()
end)

----------------------------------------------------------------------
-- Drawing.
----------------------------------------------------------------------

--[[
	Stroke storage.

	Segment CENTRES are kept in a parallel plain-Lua array rather than read
	back off each Frame. Reading `seg.Position.X.Offset` is an instance
	property access that crosses the Luau/engine boundary; the eraser tests
	every segment on every pointer move, so at the 4000-segment ceiling and
	60Hz that was up to 240,000 boundary crossings a second. Holding the
	centres in Lua turns each test into two array reads.

	The two arrays are strictly parallel - every insert and every removal
	touches both, and removals use an unordered swap-pop, which is O(1)
	instead of the O(n) shift `table.remove` performs on a mid-array index.
	Order is irrelevant here: these are independent marks on a canvas, not a
	sequence.
]]
local segments: { Frame } = {}
local centres: { Vector2 } = {}

local function clearCanvas()
	for _, seg in ipairs(segments) do
		seg:Destroy()
	end
	table.clear(segments)
	table.clear(centres)
end

clearButton.MouseButton1Click:Connect(clearCanvas)

--[[
	Lays one stroke segment between two points, as a thin Frame rotated to
	match the angle between them. Positions are relative to the canvas.
]]
local function drawSegment(from: Vector2, to: Vector2)
	if #segments >= MAX_SEGMENTS then
		return
	end

	local delta = to - from
	local length = delta.Magnitude
	local midpoint = from + delta * 0.5

	local seg = Instance.new("Frame")
	seg.Size = UDim2.fromOffset(math.ceil(length + PEN_THICKNESS), PEN_THICKNESS)
	seg.AnchorPoint = Vector2.new(0.5, 0.5)
	seg.Position = UDim2.fromOffset(midpoint.X, midpoint.Y)
	seg.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	seg.BackgroundColor3 = PEN_COLOR
	seg.BorderSizePixel = 0
	seg.Parent = canvas

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = seg

	table.insert(segments, seg)
	table.insert(centres, midpoint)
end

--[[
	Removes every segment whose centre falls within the eraser's radius.

	Compares SQUARED distances so the per-segment test needs no square root,
	and iterates backwards so a swap-pop cannot move an unchecked element
	into a slot already passed.
]]
local function eraseAt(point: Vector2)
	local radiusSquared = ERASER_THICKNESS * ERASER_THICKNESS
	local count = #segments
	for i = count, 1, -1 do
		local centre = centres[i]
		local dx = centre.X - point.X
		local dy = centre.Y - point.Y
		if dx * dx + dy * dy <= radiusSquared then
			segments[i]:Destroy()
			-- Unordered swap-pop: move the last element into this slot.
			local last = #segments
			segments[i] = segments[last]
			centres[i] = centres[last]
			segments[last] = nil
			centres[last] = nil
		end
	end
end

local drawing = false
local lastPoint: Vector2? = nil

local function canvasPoint(screenPos: Vector2): Vector2
	local origin = canvas.AbsolutePosition
	return screenPos - origin
end

local function withinCanvas(point: Vector2): boolean
	local size = canvas.AbsoluteSize
	return point.X >= 0 and point.Y >= 0 and point.X <= size.X and point.Y <= size.Y
end

canvas.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	drawing = true
	local point = canvasPoint(Vector2.new(input.Position.X, input.Position.Y))
	lastPoint = point
	if currentTool == "Eraser" then
		eraseAt(point)
	else
		-- A click without a drag should still leave a dot.
		drawSegment(point, point)
	end
end)

--[[
	Pointer movement.

	Bound to the canvas's own InputChanged rather than UserInputService's,
	so the handler does not run for every mouse move anywhere on screen for
	the entire session - only while the pointer is actually over the pad.
]]
canvas.InputChanged:Connect(function(input)
	if not drawing or not overlay.Visible then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local point = canvasPoint(Vector2.new(input.Position.X, input.Position.Y))
	if not withinCanvas(point) then
		lastPoint = point
		return
	end

	if currentTool == "Eraser" then
		-- Only sweep once the pointer has actually travelled; without this the
		-- eraser rescans the whole segment list on sub-pixel jitter.
		local previous = lastPoint
		if not previous or (point - previous).Magnitude >= MIN_SEGMENT then
			eraseAt(point)
			lastPoint = point
		end
		return
	end

	local previous = lastPoint
	if previous and (point - previous).Magnitude >= MIN_SEGMENT then
		drawSegment(previous, point)
		lastPoint = point
	elseif not previous then
		lastPoint = point
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		drawing = false
		lastPoint = nil
	end
end)

----------------------------------------------------------------------
-- Opening and closing: shrink and fade everything else.
----------------------------------------------------------------------

local dimmed: { [ScreenGui]: number } = {}

local function setOtherUIDimmed(dim: boolean)
	if dim then
		for _, gui in ipairs(playerGui:GetChildren()) do
			if gui:IsA("ScreenGui") and gui ~= screenGui and gui.Enabled then
				dimmed[gui] = gui.DisplayOrder
				-- Push behind the pad and shrink slightly, so the split view
				-- is unmistakably the thing in focus.
				gui.DisplayOrder = gui.DisplayOrder - 100
				for _, child in ipairs(gui:GetChildren()) do
					if child:IsA("GuiObject") then
						TweenService:Create(child, TweenInfo.new(0.18), { Size = UDim2.new(
							child.Size.X.Scale * 0.94,
							child.Size.X.Offset * 0.94,
							child.Size.Y.Scale * 0.94,
							child.Size.Y.Offset * 0.94
						) }):Play()
					end
				end
			end
		end
	else
		for gui, order in pairs(dimmed) do
			if gui.Parent then
				gui.DisplayOrder = order
				for _, child in ipairs(gui:GetChildren()) do
					if child:IsA("GuiObject") then
						TweenService:Create(child, TweenInfo.new(0.18), { Size = UDim2.new(
							child.Size.X.Scale / 0.94,
							child.Size.X.Offset / 0.94,
							child.Size.Y.Scale / 0.94,
							child.Size.Y.Offset / 0.94
						) }):Play()
					end
				end
			end
		end
		table.clear(dimmed)
	end
end

local function setOpen(open: boolean)
	overlay.Visible = open
	setOtherUIDimmed(open)
	if open then
		refreshToolButtons()
	else
		drawing = false
		lastPoint = nil
	end
end

launcher.MouseButton1Click:Connect(function()
	setOpen(not overlay.Visible)
end)
closeButton.MouseButton1Click:Connect(function()
	setOpen(false)
end)

----------------------------------------------------------------------
-- Question feed. The pad mirrors whatever the arena screen is showing.
----------------------------------------------------------------------

local function showLauncher(visible: boolean)
	launcher.Visible = visible
	if not visible then
		setOpen(false)
	end
end

RemoteEvents.Get("TurnStarted").OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or not payload.questionText then
		showLauncher(false)
		-- A cleared turn wipes the pad; the next question is a fresh problem.
		clearCanvas()
		return
	end
	questionLabel.Text = payload.questionText
	showLauncher(true)
end)

RemoteEvents.Get("PracticeQuestionStarted").OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or not payload.questionText then
		return
	end
	questionLabel.Text = payload.questionText
	clearCanvas()
	showLauncher(true)
end)

RemoteEvents.Get("TurnResolved").OnClientEvent:Connect(function()
	-- Leave the pad open if the player is mid-thought, but retire the
	-- launcher until the next question arrives.
	launcher.Visible = false
end)

refreshToolButtons()
