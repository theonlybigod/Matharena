--[[
	CenterStage.lua

	Builds the center stage: the raised stage disc, the question screen
	floating above, and the winner area marking. Tags key pieces via
	CollectionService so MatchSystem / CompetitionGameplay can find them
	later without hardcoded paths:
		"QuestionScreen" -> the screen Part - each face has a "ScreenGui"
		                     SurfaceGui with IdleLabel/ContestantLabel/
		                     QuestionLabel/TimerLabel/RoundLabel, plus
		                     AnswerBox/SubmitButton/LeavePracticeButton (see
		                     addScreenFace below); driven live by
		                     ArenaScreenController.client.lua
		"WinnerArea"    -> the winner area marker Part

	PILLAR REMOVAL: this used to also build a "HostPodium" - two vertical
	metal posts (a "Base" block plus a "Trim" bar) positioned directly in
	front of the question screen (ArenaConfig.HOST_PODIUM_OFFSET was
	(0,0,-6), right between the stage center and the screen). From most
	viewing angles those two posts read as literal pillars blocking the
	screen - confirmed by direct screenshot. It was never referenced by any
	gameplay system (CompetitionGameplay/MatchSystem/Elimination never look
	it up, it was untagged-and-unused beyond decoration), so it's been
	removed entirely - not hidden, not moved, not repositioned - per
	explicit "remove those pillars completely" direction. Nothing rebuilds
	it: buildPodium/HOST_PODIUM_OFFSET no longer exist in this file or
	ArenaConfig.lua, so Rojo/a rebuild cannot recreate them.

	The answer-input controls (AnswerBox/SubmitButton/LeavePracticeButton)
	are built here as real, static, server-created Instances - same
	principle as the text labels - so every client sees the identical
	geometry/layout. Only their Visible state and Text differ PER CLIENT,
	set locally by ArenaScreenController.client.lua depending on whether
	that specific client is the currently-active contestant/practicer -
	client-side Instance property writes are never replicated to other
	clients or the server, so one player seeing their own answer box does
	not make it appear (or become editable) for anyone else. Submitting
	still goes through the exact same SubmitAnswer/PracticeSubmitAnswer
	RemoteEvents as before, validated server-side exactly as before - this
	is purely a relocation of the input widgets, not a new input pathway.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local ArenaConfig = require(script.Parent.ArenaConfig)

local CenterStage = {}

local function buildStageDisc(parent: Instance): BasePart
	return PartUtils.CreateDisc({
		name = "StageBase",
		diameter = ArenaConfig.CENTER_STAGE_DIAMETER,
		thickness = ArenaConfig.CENTER_STAGE_HEIGHT,
		position = Vector3.new(0, ArenaConfig.CENTER_STAGE_HEIGHT / 2, 0),
		material = Enum.Material.Marble,
		color = Color3.fromRGB(20, 20, 24),
		parent = parent,
	})
end

--[[
	Builds one face of the arena's central question screen (the giant
	screen becomes the PRIMARY question display, on both faces, driven by
	the same authoritative server events every client already receives).

	Message 28 visual overhaul ("100x better... more polished, futuristic,
	impressive, while still keeping the question and gameplay information
	easy to read"): a proper framed broadcast-graphics layout instead of a
	flat single-color background - a header bar for the contestant/round
	info (visually separated from the body), a large focal question card
	with its own border, and a bottom info strip for the timer, rather than
	every label floating directly on the same flat background. Every
	element below is still exactly the same named instance
	(IdleLabel/ContestantLabel/QuestionLabel/TimerLabel/RoundLabel/
	AnswerBox/SubmitButton/LeavePracticeButton) that
	ArenaScreenController.client.lua already looks up - this is purely a
	visual/layout pass, no new elements the client needs to know about, no
	change to what's shown or when.

	Stable child names (read by ArenaScreenController.client.lua):
		"IdleLabel"      - shown when no turn is active ("MATHARENA")
		"ContestantLabel" - active contestant's name + category
		"QuestionLabel"   - the math question itself, the largest element
		"TimerLabel"      - remaining time
		"RoundLabel"      - round number / players remaining
	All hidden except IdleLabel by default; the client shows/hides them
	together when a turn starts/ends. Building this once here (rather than
	in the client script) keeps the actual screen layout part of the
	world's static geometry - the client only ever sets .Text/.Visible on
	instances that already exist, never constructs UI at runtime.
]]
local function addScreenFace(screen: BasePart, face: Enum.NormalId)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ScreenGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.Parent = screen

	-- Outer frame: a dark bezel with a glowing accent border, so the
	-- screen reads as a deliberately-framed broadcast display rather than
	-- a flat panel floating in space.
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
	background.BorderSizePixel = 0
	background.Parent = gui

	local bezelStroke = Instance.new("UIStroke")
	bezelStroke.Color = ArenaConfig.NEON_COLOR
	bezelStroke.Thickness = 4
	bezelStroke.Transparency = 0.2
	bezelStroke.Parent = background

	-- Faint corner accent brackets (broadcast-graphics styling) - four
	-- small L-shaped highlights, purely decorative, at each corner.
	for _, corner in ipairs({
		{ anchor = Vector2.new(0, 0), pos = UDim2.fromScale(0, 0) },
		{ anchor = Vector2.new(1, 0), pos = UDim2.fromScale(1, 0) },
		{ anchor = Vector2.new(0, 1), pos = UDim2.fromScale(0, 1) },
		{ anchor = Vector2.new(1, 1), pos = UDim2.fromScale(1, 1) },
	}) do
		local bracket = Instance.new("Frame")
		bracket.Name = "CornerBracket"
		bracket.AnchorPoint = corner.anchor
		bracket.Position = corner.pos
		bracket.Size = UDim2.fromOffset(36, 36)
		bracket.BackgroundTransparency = 1
		bracket.Parent = background
		local bracketStroke = Instance.new("UIStroke")
		bracketStroke.Color = ArenaConfig.NEON_COLOR
		bracketStroke.Thickness = 2
		bracketStroke.Transparency = 0.4
		bracketStroke.Parent = bracket
	end

	-- Header bar: a slightly lighter strip across the top, visually
	-- separating the contestant/category readout from the question body
	-- below it - the "broadcast lower-third" look, inverted to a header.
	-- Permanently visible (structural chrome, like a TV bezel) - only its
	-- child ContestantLabel actually toggles; the bar itself never needs
	-- to hide since IdleLabel (below, higher ZIndex) fully covers it at idle.
	local headerBar = Instance.new("Frame")
	headerBar.Name = "HeaderBar"
	headerBar.Size = UDim2.new(1, 0, 0.2, 0)
	headerBar.BackgroundColor3 = Color3.fromRGB(16, 17, 24)
	headerBar.BorderSizePixel = 0
	headerBar.ZIndex = 2
	headerBar.Parent = background

	local headerGradient = Instance.new("UIGradient")
	headerGradient.Color = ColorSequence.new(Color3.fromRGB(20, 21, 30), Color3.fromRGB(12, 13, 18))
	headerGradient.Rotation = 90
	headerGradient.Parent = headerBar

	local headerDivider = Instance.new("Frame")
	headerDivider.Name = "HeaderDivider"
	headerDivider.Size = UDim2.new(1, 0, 0, 2)
	headerDivider.Position = UDim2.new(0, 0, 1, 0)
	headerDivider.BackgroundColor3 = ArenaConfig.NEON_COLOR
	headerDivider.BackgroundTransparency = 0.3
	headerDivider.BorderSizePixel = 0
	headerDivider.ZIndex = 2
	headerDivider.Parent = headerBar

	-- IdleLabel sits at a higher ZIndex than every structural bar/card
	-- below, so it fully covers them while idle (exactly matching the old
	-- single-flat-background behavior) - toggled by the client exactly as
	-- before, no change needed there.
	local idleLabel = Instance.new("TextLabel")
	idleLabel.Name = "IdleLabel"
	idleLabel.Size = UDim2.fromScale(1, 1)
	idleLabel.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
	idleLabel.BackgroundTransparency = 0
	idleLabel.BorderSizePixel = 0
	idleLabel.ZIndex = 5
	idleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	idleLabel.Font = Enum.Font.GothamBlack
	idleLabel.TextScaled = true
	idleLabel.Text = "MATHARENA"
	idleLabel.Visible = true
	idleLabel.Parent = background

	local contestantLabel = Instance.new("TextLabel")
	contestantLabel.Name = "ContestantLabel"
	contestantLabel.Size = UDim2.new(1, -40, 1, 0)
	contestantLabel.Position = UDim2.fromScale(0, 0)
	contestantLabel.BackgroundTransparency = 1
	contestantLabel.TextColor3 = ArenaConfig.NEON_COLOR
	contestantLabel.Font = Enum.Font.GothamBold
	contestantLabel.TextScaled = true
	contestantLabel.Text = ""
	contestantLabel.Visible = false
	contestantLabel.ZIndex = 3
	contestantLabel.Parent = headerBar

	-- Question card: a distinct panel (not just floating text on the bare
	-- background) so the question itself reads as the screen's clear focal
	-- point. Permanently visible (structural chrome) - same reasoning as
	-- headerBar/footerBar above; only QuestionLabel itself toggles.
	local questionCard = Instance.new("Frame")
	questionCard.Name = "QuestionCard"
	questionCard.Size = UDim2.new(1, -60, 0.48, 0)
	questionCard.Position = UDim2.fromScale(0, 0.24)
	questionCard.BackgroundColor3 = Color3.fromRGB(14, 15, 20)
	questionCard.BorderSizePixel = 0
	questionCard.ZIndex = 2
	questionCard.Parent = background

	local questionCardStroke = Instance.new("UIStroke")
	questionCardStroke.Color = ArenaConfig.NEON_COLOR
	questionCardStroke.Thickness = 2
	questionCardStroke.Transparency = 0.6
	questionCardStroke.Parent = questionCard

	local questionLabel = Instance.new("TextLabel")
	questionLabel.Name = "QuestionLabel"
	questionLabel.Size = UDim2.new(1, -30, 1, -20)
	questionLabel.Position = UDim2.fromOffset(15, 10)
	questionLabel.BackgroundTransparency = 1
	questionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	questionLabel.Font = Enum.Font.GothamBlack
	questionLabel.TextScaled = true
	questionLabel.TextWrapped = true
	questionLabel.Text = ""
	questionLabel.Visible = false
	questionLabel.ZIndex = 3
	questionLabel.Parent = questionCard

	-- Bottom info strip: timer + round, visually grouped in their own
	-- footer band rather than floating loose on the background. Permanently
	-- visible - same reasoning as headerBar above.
	local footerBar = Instance.new("Frame")
	footerBar.Name = "FooterBar"
	footerBar.Size = UDim2.new(1, 0, 0.16, 0)
	footerBar.Position = UDim2.fromScale(0, 0.76)
	footerBar.BackgroundColor3 = Color3.fromRGB(16, 17, 24)
	footerBar.BorderSizePixel = 0
	footerBar.ZIndex = 2
	footerBar.Parent = background

	local footerDivider = Instance.new("Frame")
	footerDivider.Name = "FooterDivider"
	footerDivider.Size = UDim2.new(1, 0, 0, 2)
	footerDivider.BackgroundColor3 = ArenaConfig.NEON_COLOR
	footerDivider.BackgroundTransparency = 0.3
	footerDivider.BorderSizePixel = 0
	footerDivider.ZIndex = 2
	footerDivider.Parent = footerBar

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = UDim2.new(0.4, 0, 1, 0)
	timerLabel.Position = UDim2.fromScale(0.05, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.TextColor3 = Color3.fromRGB(255, 205, 60)
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.TextScaled = true
	timerLabel.Text = ""
	timerLabel.Visible = false
	timerLabel.ZIndex = 3
	timerLabel.Parent = footerBar

	local roundLabel = Instance.new("TextLabel")
	roundLabel.Name = "RoundLabel"
	roundLabel.Size = UDim2.new(0.4, 0, 1, 0)
	roundLabel.Position = UDim2.fromScale(0.55, 0)
	roundLabel.BackgroundTransparency = 1
	roundLabel.TextColor3 = Color3.fromRGB(200, 205, 215)
	roundLabel.Font = Enum.Font.Gotham
	roundLabel.TextScaled = true
	roundLabel.Text = ""
	roundLabel.Visible = false
	roundLabel.ZIndex = 3
	roundLabel.Parent = footerBar

	-- ===== Answer input row (moved off the player's personal popup
	-- entirely - this IS the input now, for both competitive turns and
	-- Practice Mode). Hidden/disabled by default; a client only shows and
	-- enables these for itself when it is the active contestant/practicer
	-- (see ArenaScreenController.client.lua). Given its own clear band
	-- (0.79-0.95) below the footer, so nothing clips or overflows. Given a
	-- ZIndex above IdleLabel too, though this is moot in practice since the
	-- client only ever shows these alongside the other active-turn labels,
	-- never while IdleLabel is showing.
	--
	-- Message 29 ("make the way you type your answer more engaging"):
	-- AnswerBox gets its own "AnswerBoxStroke" UIStroke, animated by
	-- ArenaScreenController.client.lua on Focused/FocusLost so it visibly
	-- glows brighter while the player is actively typing - a static server-
	-- built Instance (same principle as everything else on this screen);
	-- only its Transparency/Thickness/Color are ever touched, client-side,
	-- exactly like every other purely-visual property on this screen. =====
	local answerBox = Instance.new("TextBox")
	answerBox.Name = "AnswerBox"
	answerBox.Size = UDim2.new(0.42, 0, 0.16, 0)
	answerBox.Position = UDim2.fromScale(0.04, 0.79)
	answerBox.Font = Enum.Font.GothamBlack
	answerBox.TextScaled = true
	-- Bug fix: a freshly-created TextBox's default .Text is Roblox's own
	-- placeholder string ("Text Box"), not an empty string - PlaceholderText
	-- below only ever DISPLAYS instead of an empty .Text, it doesn't clear
	-- a non-empty one. Without this explicit clear, the very first time a
	-- player ever saw this box (before any clear-cycle had run), it showed
	-- that literal leftover default text, which - combined with
	-- ClearTextOnFocus = false below - had to be manually deleted before
	-- typing an actual answer.
	answerBox.Text = ""
	answerBox.PlaceholderText = "Type your answer..."
	answerBox.TextColor3 = Color3.fromRGB(20, 20, 25)
	answerBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	answerBox.ClearTextOnFocus = false
	answerBox.Visible = false
	answerBox.ZIndex = 6
	answerBox.Parent = background

	local answerBoxCorner = Instance.new("UICorner")
	answerBoxCorner.CornerRadius = UDim.new(0, 12)
	answerBoxCorner.Parent = answerBox

	local answerBoxStroke = Instance.new("UIStroke")
	answerBoxStroke.Name = "AnswerBoxStroke"
	answerBoxStroke.Color = ArenaConfig.NEON_COLOR
	answerBoxStroke.Thickness = 2
	answerBoxStroke.Transparency = 0.7
	answerBoxStroke.Parent = answerBox

	local submitButton = Instance.new("TextButton")
	submitButton.Name = "SubmitButton"
	submitButton.Size = UDim2.new(0.22, 0, 0.16, 0)
	submitButton.Position = UDim2.fromScale(0.48, 0.79)
	submitButton.BackgroundColor3 = ArenaConfig.NEON_COLOR
	submitButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	submitButton.Font = Enum.Font.GothamBold
	submitButton.TextScaled = true
	submitButton.Text = "SUBMIT"
	submitButton.Visible = false
	submitButton.ZIndex = 6
	submitButton.Parent = background

	local submitButtonCorner = Instance.new("UICorner")
	submitButtonCorner.CornerRadius = UDim.new(0, 12)
	submitButtonCorner.Parent = submitButton

	local submitButtonStroke = Instance.new("UIStroke")
	submitButtonStroke.Name = "SubmitButtonStroke"
	submitButtonStroke.Color = Color3.fromRGB(255, 255, 255)
	submitButtonStroke.Thickness = 0
	submitButtonStroke.Transparency = 1
	submitButtonStroke.Parent = submitButton

	local leavePracticeButton = Instance.new("TextButton")
	leavePracticeButton.Name = "LeavePracticeButton"
	leavePracticeButton.Size = UDim2.new(0.22, 0, 0.16, 0)
	leavePracticeButton.Position = UDim2.fromScale(0.74, 0.79)
	leavePracticeButton.BackgroundColor3 = Color3.fromRGB(190, 60, 60)
	leavePracticeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	leavePracticeButton.Font = Enum.Font.GothamBold
	leavePracticeButton.TextScaled = true
	leavePracticeButton.Text = "EXIT PRACTICE"
	leavePracticeButton.Visible = false
	leavePracticeButton.ZIndex = 6
	leavePracticeButton.Parent = background

	local leaveButtonCorner = Instance.new("UICorner")
	leaveButtonCorner.CornerRadius = UDim.new(0, 10)
	leaveButtonCorner.Parent = leavePracticeButton
end

local function buildQuestionScreen(parent: Instance, stageTopY: number): BasePart
	local screen = PartUtils.CreatePart({
		name = "QuestionScreen",
		size = Vector3.new(ArenaConfig.QUESTION_SCREEN_SIZE.X, ArenaConfig.QUESTION_SCREEN_SIZE.Y, 1),
		position = Vector3.new(0, stageTopY + ArenaConfig.QUESTION_SCREEN_HEIGHT_ABOVE_STAGE, 0),
		material = Enum.Material.Metal,
		color = Color3.fromRGB(15, 15, 18),
		canCollide = false,
		parent = parent,
	})

	-- Two faces so the screen reads from either side of the arena.
	addScreenFace(screen, Enum.NormalId.Front)
	addScreenFace(screen, Enum.NormalId.Back)

	CollectionService:AddTag(screen, "QuestionScreen")

	return screen
end

--[[
	Message 21 fix (section 6): same z-fighting pattern as the arena
	floor's ring segments (see ArenaDecorations.lua) - this marker
	previously sat with its bottom face at EXACTLY stageTopY, coincident
	with the stage disc's top face. Uses the same deliberate gap constant
	so both fixes stay consistent.
]]
local function buildWinnerArea(parent: Instance, stageTopY: number): BasePart
	local thickness = 0.3
	local marker = PartUtils.CreateDisc({
		name = "WinnerArea",
		diameter = ArenaConfig.WINNER_AREA_DIAMETER,
		thickness = thickness,
		position = Vector3.new(0, stageTopY + ArenaConfig.FLOOR_RING_HEIGHT_ABOVE_FLOOR + thickness / 2, 0),
		material = Enum.Material.Neon,
		color = ArenaConfig.NEON_COLOR,
		canCollide = false,
		parent = parent,
	})

	CollectionService:AddTag(marker, "WinnerArea")

	return marker
end

function CenterStage.BuildAll(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "CenterStage"
	folder.Parent = parent

	buildStageDisc(folder)
	local stageTopY = ArenaConfig.CENTER_STAGE_HEIGHT

	buildWinnerArea(folder, stageTopY)
	buildQuestionScreen(folder, stageTopY)

	return folder
end

return CenterStage
