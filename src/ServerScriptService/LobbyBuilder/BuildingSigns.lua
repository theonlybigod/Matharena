--[[
	BuildingSigns.lua

	Floating overhead signs above each of the four lobby buildings (Shop,
	DailyRewards, TutorialBuilding, StatisticsBuilding) - "a sign on top
	of it, similar but different to the MATHARENA sign... that tells them
	that points to where it is". Reuses the same BillboardGui-on-an-
	invisible-anchor pattern as the main MATHARENA sign (Sign.lua) so it's
	readable from any angle and isn't capped by Roblox's ~2048-stud
	Part-size ceiling, but is deliberately smaller/simpler and colored with
	the building-trim accent (LobbyConfig.NEON_COLOR) rather than the
	central-feature neon the main sign uses, so each reads as "this
	building's own sign", not a second MATHARENA landmark. A short glowing
	connector beam runs from the sign down to the building's roof - the
	"points to where it is" element the main sign deliberately doesn't
	have (that one floats independently over the plaza with no connector,
	per its own module's "energy beams removed" history).

	Clickable (Message 32 - "if you click on them above the shop, you
	teleport right in front of it"): each sign's label is a real
	TextButton (not a TextLabel), tagged "BuildingSignButton" with a
	"BuildingName" attribute, so BuildingSignController.client.lua
	(StarterPlayerScripts) can find every one of them and fire
	"RequestTeleportToBuilding" on click - see BuildingTeleportSystem.lua
	(server) for where that teleport actually lands (directly in front of
	the building's real doorway, not this sign, not the building's
	center).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local LobbyTheme = require(script.Parent.LobbyTheme)

local BuildingSigns = {}

--[[
	Tag + attribute contract shared by every clickable teleport target.

	WHY CLICKDETECTORS: the overhead sign's clickable element used to be a
	TextButton inside a BillboardGui, and that turned out to be an
	unreliable foundation. A BillboardGui parented to a Workspace part is
	not in the GUI input pipeline at all, and even once hosted in PlayerGui
	its hit-testing proved inconsistent in practice. A ClickDetector on a
	real Part has none of those problems: it is raycast against actual
	geometry, and critically its MouseClick fires ON THE SERVER with the
	clicking Player passed in - so the teleport is server-authoritative by
	construction, with no client GUI, no RemoteEvent, and no client trust
	involved in the click itself.
]]
BuildingSigns.TELEPORT_TARGET_TAG = "BuildingTeleportTarget"

--[[
	Marks `part` as a clickable "go to this building" target: records which
	building and which map it belongs to, gives it a ClickDetector, and tags
	it so BuildingTeleportSystem can wire it up on the server.

	Used for BOTH clickable surfaces, so a player's instinct lands
	somewhere real either way:
	  - the overhead floating sign above the building, and
	  - the building's own facade name plate ("the writing right in front
	    of the building", which players reported clicking).
]]
function BuildingSigns.MakeTeleportTarget(part: BasePart, buildingName: string, mapId: string, maxDistance: number?)
	part:SetAttribute("BuildingName", buildingName)
	part:SetAttribute("MapId", mapId)

	-- A ClickDetector only fires for parts the mouse can actually raycast
	-- against, so the part must stay queryable even when it is invisible.
	part.CanQuery = true

	local detector = Instance.new("ClickDetector")
	detector.Name = "TeleportClickDetector"
	detector.MaxActivationDistance = maxDistance or 1000
	detector.CursorIcon = ""
	detector.Parent = part

	CollectionService:AddTag(part, BuildingSigns.TELEPORT_TARGET_TAG)
end

local defaultTheme = LobbyTheme.Get()
local ACCENT_COLOR = defaultTheme.buildingSignAccentColor

--[[
	Latches `theme`'s accent color for every subsequent BuildOne call.
]]
function BuildingSigns.SetTheme(theme: LobbyTheme.Theme)
	ACCENT_COLOR = theme.buildingSignAccentColor
end
--[[
	Clearance ABOVE THE REAL TOP OF THE BUILT EXTERIOR, not above
	def.height.

	This used to be a flat +28 over def.position.Y + def.height, which was
	written when every building was a box whose tallest topper was the
	Statistics spire at +16. It is badly wrong for the custom exteriors:
	the Lava volcano's cap alone rises ~1.6x the building's half-diagonal
	above the roofline (roughly +32 on a typical building), so the sign
	anchor sat INSIDE the volcano. A BillboardGui buried in geometry is
	both invisible and unclickable - which is exactly why the teleport
	button could not be seen or used on that map.

	BuildingInteriors.GetExteriorTopY now reports each theme's true peak,
	and this is the clean air kept above it.
]]
local SIGN_CLEARANCE_ABOVE_EXTERIOR = 30
--[[
	SIZE UNITS: a BillboardGui's Size Offset is in PIXELS, not studs, and
	does NOT shrink with distance. Verified live: AbsoluteSize stayed
	exactly (80, 26) at both 221 studs and 70 studs from the sign.

	The previous value and its comment were written on the assumption that
	Offset was studs - it reasoned about "half-width is 36 studs" and
	whether adjacent signs 88 studs apart would overlap. None of that math
	applied, and the real consequence was that every teleport sign rendered
	as a fixed 80x26 PIXEL badge - about 5% of a 1636px-wide viewport, and
	a correspondingly tiny click target.

	At pixel scale the sign is screen-constant, so this only has to be sized
	once for readability rather than balanced against building spacing.
]]
local BILLBOARD_SIZE = Vector2.new(300, 100) -- PIXELS (see above)

--[[
	HEADERS NO LONGER CROWD THE CENTRAL BOARD.

	This used to be 900 - far enough that all four building headers stayed
	drawn at full pixel size from anywhere on the map, including from the
	spawn row looking north at the MatharenaBoard. Because a BillboardGui's
	Size is in PIXELS and does not shrink with distance (see BILLBOARD_SIZE),
	four 200x66px badges sat permanently across the middle of the screen -
	directly over the central board a player is walking toward. That is the
	"headers block the screen" problem: not the signs' world positions, but
	their screen-constant size combined with unlimited draw distance.

	260 is a deliberate "walk up to it" range: comfortably wider than the
	gap between adjacent buildings (~44 studs of clearance, ~115 studs
	centre to centre), so a header is readable well before you reach its
	building and its click target stays usable - but short enough that
	standing at the spawn row or the plaza, where the central board is the
	thing you are meant to be reading, draws none of them.

	VERIFIED IN PLAY MODE against the built Lava map, which is where the
	final number comes from. The distance that matters is the 3D one to the
	sign ANCHOR, and the anchor sits ~83 studs above ground (crater peak
	plus SIGN_CLEARANCE_ABOVE_EXTERIOR), so it is much larger than the
	ground distance to the building. Measured from the plaza at (1050,14,60):
		Shop 166, StatisticsBuilding 161, DailyRewards 191, Tutorial 191.
	Measured walking up to the Shop entrance: 97.
	So 260 - and even 120 - still drew every header across the middle of the
	screen from the plaza.

	WHY THIS IS BACK UP AT 420. The previous value of 100/55 existed purely
	to stop headers covering the central screen, by culling them before a
	player ever got close enough to see one. That is no longer the mechanism
	doing that job: GameplayCameraController now disables these billboards
	outright for the duration of Practice and Competitive question views (see
	its setSignageHidden), which removes them from exactly the situation that
	mattered and leaves them free to be large and readable everywhere else.
]]
local SIGN_MAX_DISTANCE = 420

--[[
	How far a player can be and still CLICK a sign to teleport.

	Deliberately decoupled from SIGN_MAX_DISTANCE. Clicking used to be wired
	as `SIGN_MAX_DISTANCE + 100`, which tied the interaction range to the
	range at which the billboard is legible - so when the visual distance was
	tuned down to 55 to stop headers crowding the screen, the click range
	silently collapsed to 155 studs with it, and teleporting stopped working
	from anywhere but right next to the building.

	Those two ranges answer different questions. "How far away is this text
	still worth drawing?" is a readability judgement. "How far away may I be
	and still click this?" should just be: anywhere on the map.

	2000 comfortably exceeds the longest sightline on any map - the usable
	radius is ~224 studs, so the far corner-to-corner distance is under 650
	even allowing for height - with plenty of headroom for larger maps later.
]]
local SIGN_CLICK_DISTANCE = 2000

--[[
	Builds one building's overhead sign + connector beam, parented into
	`parent` (the Buildings folder). `mapId` is tagged onto the clickable
	sign button ("MapId" attribute, alongside the existing "BuildingName")
	so BuildingSignController.client.lua can tell BuildingTeleportSystem
	WHICH map's copy of this building was actually clicked - two maps can
	both have a building named "Shop", at two completely different world
	positions. Returns the invisible anchor part.
]]
function BuildingSigns.BuildOne(def, parent: Instance, mapId: string, exteriorTopY: number?): BasePart
	-- `exteriorTopY` is the real top of the built exterior for this map's
	-- theme (Buildings.lua supplies it from
	-- BuildingInteriors.GetExteriorTopY). Falling back to the old
	-- roofline-only estimate keeps this callable standalone.
	local topY = exteriorTopY or (def.position.Y + def.height + 16)
	local anchorY = topY + SIGN_CLEARANCE_ABOVE_EXTERIOR

	-- Connector beam: a glowing line from the sign down to the top of the
	-- structure - "points to where it is", distinct from the main MATHARENA
	-- sign (which has no such connector). Spans from the real exterior peak
	-- up to the sign, so on a volcano it starts at the crater rim rather
	-- than somewhere inside the mountain.
	local beamBottom = def.position.Y + def.height
	local beamHeight = math.max(4, anchorY - 4 - beamBottom)
	PartUtils.CreatePart({
		name = "SignConnector",
		size = Vector3.new(0.5, beamHeight, 0.5),
		position = Vector3.new(def.position.X, beamBottom + beamHeight / 2, def.position.Z),
		material = Enum.Material.Neon,
		color = ACCENT_COLOR,
		transparency = 0.3,
		canCollide = false,
		parent = parent,
	})

	--[[
		The anchor is invisible, but it is now also the overhead sign's real
		CLICK TARGET, so it is sized to roughly match the sign's visual
		footprint instead of the old 2x2x2 nub. A 2-stud cube was far smaller
		than the sign drawn over it, so even a click that visually landed dead
		centre on the words had no geometry behind it to hit.
	]]
	local anchor = PartUtils.CreatePart({
		name = def.name .. "SignAnchor",
		size = Vector3.new(26, 9, 2),
		position = Vector3.new(def.position.X, anchorY, def.position.Z),
		transparency = 1,
		canCollide = false,
		parent = parent,
	})

	BuildingSigns.MakeTeleportTarget(anchor, def.name, mapId, SIGN_CLICK_DISTANCE)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BuildingSignBillboard"
	billboard.Adornee = anchor
	billboard.Size = UDim2.fromOffset(BILLBOARD_SIZE.X, BILLBOARD_SIZE.Y)
	--[[
		AlwaysOnTop is FALSE.

		It was briefly set true, to satisfy "stay readable even when a wall or a
		screen passes in front". That turned out to be actively broken: with
		AlwaysOnTop = true these billboards render as NOTHING AT ALL - not
		occluded, not dimmed, simply absent.

		Verified by A/B test on the Lava map, camera parked 90 studs directly in
		front of the Shop sign anchor, changing one property at a time:
			Size 200x66, AoT false, dist 100  -> renders
			Size 300x100, AoT false, dist 100 -> renders, visibly larger
			Size 300x100, AoT TRUE,  dist 100 -> INVISIBLE
		So the size increase is fine and AlwaysOnTop alone is the cause.

		Nothing is lost by turning it off. The reason AlwaysOnTop was wanted -
		stopping headers covering the central board during a question - is
		already handled properly by GameplayCameraController, which disables
		these billboards outright for the whole Practice/Competitive question
		view and re-enables them on release. Depth testing is not doing that
		job, so it costs nothing to leave it on.
	]]
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = SIGN_MAX_DISTANCE
	billboard.LightInfluence = 0
	billboard.Parent = anchor

	--[[
		The sign is now PURELY VISUAL - a Frame, not a TextButton.

		Clicking is handled entirely by the ClickDetector on the anchor Part
		(see MakeTeleportTarget). Keeping a transparent GuiButton here would
		actively BREAK that: a GUI element under the cursor absorbs the click
		and stops the mouse from reaching world geometry, so the button and
		the ClickDetector would fight each other and neither would reliably
		win. Exactly one thing owns the click now.
	]]
	local container = Instance.new("Frame")
	container.Name = "SignContent"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.Parent = billboard

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "SignName"
	nameLabel.Size = UDim2.new(1, 0, 0.72, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextScaled = true
	nameLabel.Text = def.displayName
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeTransparency = 0.15
	nameLabel.TextStrokeColor3 = ACCENT_COLOR
	nameLabel.Parent = container

	-- "click to visit" hint beneath the name, so a player understands the
	-- sign is interactive rather than pure decoration.
	local hint = Instance.new("TextLabel")
	hint.Name = "ClickHint"
	hint.Size = UDim2.new(1, 0, 0.24, 0)
	hint.Position = UDim2.new(0, 0, 0.74, 0)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamBold
	hint.TextScaled = true
	hint.TextColor3 = ACCENT_COLOR
	hint.TextStrokeTransparency = 0.4
	hint.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	hint.Text = "click to visit"
	hint.Parent = container

	local glow = Instance.new("PointLight")
	glow.Color = ACCENT_COLOR
	glow.Brightness = 1.4
	glow.Range = 24
	glow.Parent = anchor

	return anchor
end

return BuildingSigns
