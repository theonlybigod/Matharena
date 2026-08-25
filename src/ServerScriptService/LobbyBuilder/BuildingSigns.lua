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

local defaultTheme = LobbyTheme.Get()
local ACCENT_COLOR = defaultTheme.buildingSignAccentColor

--[[
	Latches `theme`'s accent color for every subsequent BuildOne call.
]]
function BuildingSigns.SetTheme(theme: LobbyTheme.Theme)
	ACCENT_COLOR = theme.buildingSignAccentColor
end
-- High enough to clear every building's tallest roof topper (the
-- Statistics data spire is the tallest, at +16 above def.height) with
-- clean room to spare - bumped from 22 to give the much-larger
-- billboard below more air above the roofline.
local SIGN_HEIGHT_ABOVE_BUILDING = 28
-- "Much much larger... extremely easy to read from a reasonable
-- distance" - doubled again from the previous (36, 10) pass. Verified
-- against LobbyConfig.BUILDINGS' actual positions (scaled by
-- MapConfig.SCALE_FACTOR): the CLOSEST pair of adjacent building centers
-- (DailyRewards <-> TutorialBuilding) is ~88.4 studs apart. At this size,
-- each sign's half-width is 36 studs, so two adjacent signs need at most
-- 72 combined studs of width to clear each other - leaving a genuine
-- ~16-stud gap even for the tightest pair, so a much bigger sign still
-- never visually overlaps its neighbor. Going any larger (e.g. a further
-- doubling to 144 wide) would close that gap entirely and risk exactly
-- the "text clipping or overlap" this pass is required to avoid.
local BILLBOARD_SIZE = Vector2.new(72, 20) -- studs, matching Sign.lua's own UDim2.fromOffset convention

--[[
	Builds one building's overhead sign + connector beam, parented into
	`parent` (the Buildings folder). `mapId` is tagged onto the clickable
	sign button ("MapId" attribute, alongside the existing "BuildingName")
	so BuildingSignController.client.lua can tell BuildingTeleportSystem
	WHICH map's copy of this building was actually clicked - two maps can
	both have a building named "Shop", at two completely different world
	positions. Returns the invisible anchor part.
]]
function BuildingSigns.BuildOne(def, parent: Instance, mapId: string): BasePart
	local topY = def.position.Y + def.height
	local anchorY = topY + SIGN_HEIGHT_ABOVE_BUILDING

	-- Connector beam: a short glowing line from the sign down to the
	-- building's roofline - "points to where it is", distinct from the
	-- main MATHARENA sign (which has no such connector).
	local beamHeight = SIGN_HEIGHT_ABOVE_BUILDING - 3
	PartUtils.CreatePart({
		name = "SignConnector",
		size = Vector3.new(0.3, beamHeight, 0.3),
		position = Vector3.new(def.position.X, topY + beamHeight / 2, def.position.Z),
		material = Enum.Material.Neon,
		color = ACCENT_COLOR,
		transparency = 0.3,
		canCollide = false,
		parent = parent,
	})

	local anchor = PartUtils.CreatePart({
		name = def.name .. "SignAnchor",
		size = Vector3.new(2, 2, 2),
		position = Vector3.new(def.position.X, anchorY, def.position.Z),
		transparency = 1,
		canCollide = false,
		parent = parent,
	})

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BuildingSignBillboard"
	billboard.Adornee = anchor
	billboard.Size = UDim2.fromOffset(BILLBOARD_SIZE.X, BILLBOARD_SIZE.Y)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 450 -- scaled up to match the much larger sign - readable from further away, but not from clear across the whole map
	billboard.LightInfluence = 0
	billboard.Parent = anchor

	local button = Instance.new("TextButton")
	button.Name = "SignButton"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBlack
	button.TextScaled = true
	button.Text = def.displayName
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextStrokeTransparency = 0.15
	button.TextStrokeColor3 = ACCENT_COLOR
	button.Parent = billboard

	-- Small "click to visit" hint beneath the name, so a player
	-- understands the sign is interactive rather than pure decoration.
	local hint = Instance.new("TextLabel")
	hint.Name = "ClickHint"
	hint.Size = UDim2.new(1, 0, 0, 14)
	hint.Position = UDim2.new(0, 0, 1, -2)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextScaled = true
	hint.TextColor3 = ACCENT_COLOR
	hint.Text = "click to visit"
	hint.Parent = button

	CollectionService:AddTag(button, "BuildingSignButton")
	button:SetAttribute("BuildingName", def.name)
	button:SetAttribute("MapId", mapId)

	local glow = Instance.new("PointLight")
	glow.Color = ACCENT_COLOR
	glow.Brightness = 1.4
	glow.Range = 24
	glow.Parent = anchor

	return anchor
end

return BuildingSigns
