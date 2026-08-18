--[[
	Buildings.lua

	Constructs the five named lobby buildings from LobbyConfig.BUILDINGS.
	Each building is now a genuinely walkable shell (BuildingInteriors) with
	a neon roofline trim band, a doorway, interior furnishings/terminals,
	and a sign facing the plaza (+Z direction, where spawns are).

	LeaderboardHall (Message 11) gets a bigger, custom display instead of
	the generic name-only sign: a SurfaceGui with a title plus 5 columns
	(Wins/XP/Questions Solved/Accuracy/Fastest Answer), each pre-built with
	placeholder rows. This building was built back in Message 2 specifically
	in anticipation of a leaderboard display, so this is that display's
	static geometry - LeaderboardDisplay (Message 11, ServerScriptService)
	finds these instances by path and periodically fills in the row text
	from LeaderboardSystem's live OrderedDataStore data. Nothing in this
	file talks to a DataStore itself - it only builds empty placeholder
	labels for that other module to populate.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local LobbyConfig = require(script.Parent.LobbyConfig)
local BuildingInteriors = require(script.Parent.BuildingInteriors)

local Buildings = {}

local function addSign(basePart: BasePart, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- Back = +Z face, which faces the plaza/spawns
	gui.Parent = basePart

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	label.Parent = gui
end

-- Leaderboard categories shown on LeaderboardHall's display board. Kept in
-- the same order as the design doc (Wins, XP, Questions Solved, Accuracy,
-- Fastest Answer). DISPLAY_ROWS is how many entries fit on the physical
-- board - LeaderboardSystem itself can track more than this; the board
-- just shows the top slice of it.
local LEADERBOARD_CATEGORIES = {
	{ id = "Wins", label = "Wins" },
	{ id = "XP", label = "XP" },
	{ id = "QuestionsSolved", label = "Questions Solved" },
	{ id = "Accuracy", label = "Accuracy" },
	{ id = "FastestAnswer", label = "Fastest Answer" },
}
local LEADERBOARD_DISPLAY_ROWS = 5

--[[
	Builds LeaderboardHall's custom display: a title bar plus 5 equal
	columns (one per category), each with a header label and
	LEADERBOARD_DISPLAY_ROWS placeholder row labels named "Row1".."RowN" so
	LeaderboardDisplay (a separate server module) can find and fill them in
	by a stable path without this file needing to know anything about
	DataStores or live data.
]]
local function addLeaderboardDisplay(basePart: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardDisplay"
	gui.Face = Enum.NormalId.Back -- same face as other buildings' signs, facing the plaza/spawns
	gui.Parent = basePart

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, 0, 0.14, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = LobbyConfig.NEON_COLOR
	titleLabel.Text = "LEADERBOARDS"
	titleLabel.Parent = root

	local categoriesRow = Instance.new("Frame")
	categoriesRow.Name = "CategoriesRow"
	categoriesRow.Size = UDim2.new(1, 0, 0.86, 0)
	categoriesRow.Position = UDim2.new(0, 0, 0.14, 0)
	categoriesRow.BackgroundTransparency = 1
	categoriesRow.Parent = root

	local categoriesLayout = Instance.new("UIListLayout")
	categoriesLayout.FillDirection = Enum.FillDirection.Horizontal
	categoriesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	categoriesLayout.Parent = categoriesRow

	for _, category in ipairs(LEADERBOARD_CATEGORIES) do
		local column = Instance.new("Frame")
		column.Name = category.id .. "Column"
		column.Size = UDim2.new(1 / #LEADERBOARD_CATEGORIES, 0, 1, 0)
		column.BackgroundTransparency = 1
		column.Parent = categoriesRow

		local columnLayout = Instance.new("UIListLayout")
		columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
		columnLayout.Parent = column

		local rowSlots = 1 + LEADERBOARD_DISPLAY_ROWS -- header + N rows

		local headerLabel = Instance.new("TextLabel")
		headerLabel.Name = "Header"
		headerLabel.LayoutOrder = 0
		headerLabel.Size = UDim2.new(1, 0, 1 / rowSlots, 0)
		headerLabel.BackgroundTransparency = 1
		headerLabel.Font = Enum.Font.GothamBold
		headerLabel.TextScaled = true
		headerLabel.TextColor3 = LobbyConfig.NEON_COLOR
		headerLabel.Text = category.label
		headerLabel.Parent = column

		for row = 1, LEADERBOARD_DISPLAY_ROWS do
			local rowLabel = Instance.new("TextLabel")
			rowLabel.Name = "Row" .. row
			rowLabel.LayoutOrder = row
			rowLabel.Size = UDim2.new(1, 0, 1 / rowSlots, 0)
			rowLabel.BackgroundTransparency = 1
			rowLabel.Font = Enum.Font.Gotham
			rowLabel.TextScaled = true
			rowLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
			rowLabel.Text = row .. ". -"
			rowLabel.Parent = column
		end
	end
end

local function buildOne(def, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = def.name
	model.Parent = parent

	-- Leaderboard Hall is no longer a walk-in building (Message 16) - it's
	-- a freestanding screen structure with its own frame/plinth, so it
	-- skips BuildShell/the shared TrimBand entirely.
	if def.name == "LeaderboardHall" then
		local base = BuildingInteriors.BuildLeaderboardScreen(def, model)
		addLeaderboardDisplay(base)
		model.PrimaryPart = base
		return model
	end

	local base = BuildingInteriors.BuildShell(def, model)

	PartUtils.CreatePart({
		name = "TrimBand",
		size = Vector3.new(def.size.X + 0.4, 0.6, def.size.Y + 0.4),
		position = def.position + Vector3.new(0, def.height - 1, 0),
		material = Enum.Material.Neon,
		color = LobbyConfig.NEON_COLOR,
		canCollide = false,
		parent = model,
	})

	if def.name == "Shop" then
		addSign(base, def.displayName)
		BuildingInteriors.FurnishShop(def, model)
	elseif def.name == "DailyRewards" then
		addSign(base, def.displayName)
		BuildingInteriors.FurnishRewards(def, model)
	elseif def.name == "StatisticsBuilding" then
		addSign(base, def.displayName)
		BuildingInteriors.FurnishStatistics(def, model)
	elseif def.name == "TutorialBuilding" then
		addSign(base, def.displayName)
		BuildingInteriors.FurnishTutorial(def, model)
	else
		addSign(base, def.displayName)
	end

	model.PrimaryPart = base
	return model
end

function Buildings.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Buildings"
	folder.Parent = parent

	for _, def in ipairs(LobbyConfig.BUILDINGS) do
		buildOne(def, folder)
	end

	return folder
end

return Buildings
