--[[
	CentralBoard.lua

	Builds the lobby's central informational board - Message 2 refinement,
	section 6. A ground-anchored, upright sign in the plaza between the
	queue portal and the building row: a thin metal frame around a dark
	backing panel, readable "MATHARENA" typography with a controlled neon
	accent, mounted on two slim support poles. Deliberately NOT a stack of
	large blocks - see CentralBoardConfig.lua for the full design rationale
	and how this differs in purpose from the floating overhead sign
	(Sign.lua) and the leaderboard boards (LeaderboardBoards.lua).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local CentralBoardConfig = require(ReplicatedStorage.Modules.CentralBoardConfig)

local CentralBoard = {}

-- Builds one thin frame bar between two corner offsets (local X/Y offsets
-- from the panel's own center), so the four calls below trace a hollow
-- rectangle rather than a solid block.
local function frameBar(panelCFrame: CFrame, from: Vector2, to: Vector2, thickness: number, model: Instance, name: string)
	local mid = (from + to) / 2
	local length = (to - from).Magnitude + thickness
	local horizontal = math.abs(to.X - from.X) > math.abs(to.Y - from.Y)

	local size = if horizontal
		then Vector3.new(length, thickness, CentralBoardConfig.FRAME_DEPTH)
		else Vector3.new(thickness, length, CentralBoardConfig.FRAME_DEPTH)

	PartUtils.CreatePart({
		name = name,
		size = size,
		cframe = panelCFrame * CFrame.new(mid.X, mid.Y, -CentralBoardConfig.BOARD_THICKNESS / 2 - CentralBoardConfig.FRAME_DEPTH / 2),
		material = Enum.Material.Metal,
		color = CentralBoardConfig.FRAME_COLOR,
		canCollide = false,
		parent = model,
	})
end

--[[
	Builds one face's readable label + neon frame trim. Both Front and
	Back get a label so the board reads correctly whether a player is
	approaching from the portal side or the building side.
]]
local function buildFace(panel: BasePart, face: Enum.NormalId)
	local gui = Instance.new("SurfaceGui")
	gui.Name = face.Name .. "Gui"
	gui.Face = face
	gui.Parent = panel

	local container = Instance.new("Frame")
	container.Size = UDim2.fromScale(0.9, 0.9)
	container.Position = UDim2.fromScale(0.05, 0.05)
	container.BackgroundTransparency = 1
	container.Parent = gui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.65)
	title.Position = UDim2.fromScale(0, 0.05)
	title.BackgroundTransparency = 1
	title.Font = CentralBoardConfig.TITLE_FONT
	title.TextScaled = true
	title.Text = CentralBoardConfig.TITLE_TEXT
	title.TextColor3 = CentralBoardConfig.TITLE_COLOR
	title.TextStrokeTransparency = 0.4
	title.TextStrokeColor3 = CentralBoardConfig.ACCENT_COLOR
	title.Parent = container

	-- A thin neon underline beneath the text - the "controlled neon
	-- accent" called for, without any extra blocky geometry.
	local underline = Instance.new("Frame")
	underline.Name = "Underline"
	underline.Size = UDim2.new(0.7, 0, 0, 3)
	underline.Position = UDim2.fromScale(0.15, 0.78)
	underline.BackgroundColor3 = CentralBoardConfig.ACCENT_COLOR
	underline.BorderSizePixel = 0
	underline.Parent = container
end

--[[
	Builds the board and parents it under `parent` (the lobby folder).
	Returns the Model so LobbyBuilder can hold a reference if a later
	system ever needs one.
]]
function CentralBoard.Build(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = CentralBoardConfig.BOARD_NAME
	model:SetAttribute(CentralBoardConfig.BOARD_NAME, true)

	local baseCFrame = CFrame.new(CentralBoardConfig.POSITION) * CFrame.Angles(0, math.rad(CentralBoardConfig.FACING_YAW_DEGREES), 0)
	local panelCenterY = CentralBoardConfig.SUPPORT_HEIGHT + CentralBoardConfig.BOARD_HEIGHT / 2
	local panelCFrame = baseCFrame * CFrame.new(0, panelCenterY, 0)

	-- Two thin support poles - "thin structural elements", not a solid
	-- pedestal block.
	for _, side in ipairs({ -1, 1 }) do
		local poleX = side * (CentralBoardConfig.BOARD_WIDTH / 2 - CentralBoardConfig.SUPPORT_INSET)
		PartUtils.CreateDisc({
			name = "SupportPole" .. (side == -1 and "Left" or "Right"),
			diameter = CentralBoardConfig.SUPPORT_DIAMETER,
			thickness = CentralBoardConfig.SUPPORT_HEIGHT,
			position = (baseCFrame * CFrame.new(poleX, CentralBoardConfig.SUPPORT_HEIGHT / 2, 0)).Position,
			material = Enum.Material.Metal,
			color = CentralBoardConfig.FRAME_COLOR,
			parent = model,
		})
	end

	-- Dark backing panel - the "subtle depth" surface the frame stands
	-- proud of, and what the SurfaceGui text renders against.
	local panel = PartUtils.CreatePart({
		name = "BoardPanel",
		size = Vector3.new(CentralBoardConfig.BOARD_WIDTH, CentralBoardConfig.BOARD_HEIGHT, CentralBoardConfig.BOARD_THICKNESS),
		cframe = panelCFrame,
		material = Enum.Material.SmoothPlastic,
		color = CentralBoardConfig.BACKING_COLOR,
		canCollide = false,
		parent = model,
	})
	model.PrimaryPart = panel

	-- Thin hollow frame around the panel - four slim bars, not a solid
	-- border block. Local coordinates are relative to the panel's own
	-- center, in (X, Y) since the frame only needs to trace the panel's
	-- flat face.
	local halfW = CentralBoardConfig.BOARD_WIDTH / 2
	local halfH = CentralBoardConfig.BOARD_HEIGHT / 2
	local t = CentralBoardConfig.FRAME_THICKNESS
	frameBar(panelCFrame, Vector2.new(-halfW, halfH), Vector2.new(halfW, halfH), t, model, "FrameTop")
	frameBar(panelCFrame, Vector2.new(-halfW, -halfH), Vector2.new(halfW, -halfH), t, model, "FrameBottom")
	frameBar(panelCFrame, Vector2.new(-halfW, -halfH), Vector2.new(-halfW, halfH), t, model, "FrameLeft")
	frameBar(panelCFrame, Vector2.new(halfW, -halfH), Vector2.new(halfW, halfH), t, model, "FrameRight")

	buildFace(panel, Enum.NormalId.Front)
	buildFace(panel, Enum.NormalId.Back)

	local glow = Instance.new("PointLight")
	glow.Color = CentralBoardConfig.ACCENT_COLOR
	glow.Brightness = CentralBoardConfig.GLOW_BRIGHTNESS
	glow.Range = CentralBoardConfig.GLOW_RANGE
	glow.Parent = panel

	model.Parent = parent
	return model
end

return CentralBoard
