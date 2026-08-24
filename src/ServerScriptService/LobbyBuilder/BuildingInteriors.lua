--[[
	BuildingInteriors.lua

	Message 15 gave every building a genuinely walkable shell. Message 16
	is a major visual overhaul on top of that shell: a shared architectural
	language (entrance canopy, window strips, a layered roof cap with neon
	trim) applied to every building, PLUS one distinct "identity" massing
	element per building so Shop/DailyRewards/Tutorial/StatisticsBuilding
	read as different structures from across the lobby, not the same box
	with a different sign:
		- Shop: angled glass storefront bays flanking the entrance
		- DailyRewards: a stepped, trophy-like tower rising off the roof
		- Tutorial: a rounded corner turret with a beacon light
		- StatisticsBuilding: a tall vertical "data spire" with neon rings

	LEADERBOARD: Leaderboard Hall no longer gets any geometry from this
	file. It isn't a walk-in building (Message 15/16), and it isn't a
	single freestanding screen either anymore - that design (the old
	BuildLeaderboardScreen below) has been replaced by five separate
	boards fanned across an arc; see LobbyBuilder/LeaderboardBoards.lua,
	which Buildings.lua calls directly for the "LeaderboardHall" entry
	instead of anything in this file.

	Terminals (Shop/Rewards/Statistics/Tutorial): unchanged from Message 15
	- each terminal Part gets a ProximityPrompt with a stable Name, and the
	CLIENT controller that already owns the corresponding panel connects
	directly to that prompt's Triggered signal. No new remotes, no
	duplicate UI/shop/rewards/statistics logic.

	Multi-theme support: every color/material below that isn't purely
	functional (ProximityPrompt config, doorway sizing math, etc.) is
	driven by a small set of mutable module-level variables, latched via
	BuildingInteriors.SetTheme(theme) once per map build (see
	LobbyBuilder/init.lua and Buildings.lua, which cascades its own
	SetTheme call into this module) - every function below already closes
	over these same variables, so a theme swap needs no other changes
	anywhere in this file:
		WALL_MATERIAL / EXTERIOR_WALL_COLOR - structural exterior walls,
			ceiling, roof cap, entrance canopy, doorway header.
		INTERIOR_WALL_COLOR / INTERIOR_FLOOR_COLOR - the (currently mostly
			unused, kept for future interior-specific surfaces) interior
			shell tones.
		FURNITURE_MATERIAL / FURNITURE_COLOR - every freestanding interior
			fixture (shelves, terminal stands, counters, pedestals,
			monitors, benches) and every roof-mounted "identity" massing
			structure's solid body (the reward tower, data spire, turret).
		ACCENT_MATERIAL / ACCENT_COLOR - every glowing trim/accent surface
			that used to be a flat Enum.Material.Neon - roofline/canopy/
			doorway trim, terminal screens, identity-structure trim rings,
			shop marquee, milestone panels, monitor screens, and so on.
		GLASS_MATERIAL / GLASS_COLOR / GLASS_TRANSPARENCY - the side-wall
			window strips and the Shop's storefront bays. For the Lava
			theme this becomes a genuinely different MATERIAL (CrackedLava
			"lava vents" glowing through the wall) rather than a tinted
			pane of Glass, not just a recolor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)
local LobbyTheme = require(script.Parent.LobbyTheme)

local BuildingInteriors = {}

local WALL_THICKNESS = 1
local MIN_DOOR_WIDTH = 8
local MAX_DOOR_WIDTH = 14

local defaultTheme = LobbyTheme.Get()
local WALL_MATERIAL = defaultTheme.buildingWallMaterial
local EXTERIOR_WALL_COLOR = defaultTheme.buildingExteriorWallColor
local INTERIOR_WALL_COLOR = defaultTheme.buildingInteriorWallColor
local INTERIOR_FLOOR_COLOR = defaultTheme.buildingInteriorFloorColor
local CEILING_COLOR = defaultTheme.buildingCeilingColor
local ROOFCAP_COLOR = defaultTheme.buildingRoofCapColor
local HEADER_COLOR = defaultTheme.buildingHeaderColor
local CANOPY_COLOR = defaultTheme.buildingCanopyColor
local ACCENT_MATERIAL = defaultTheme.buildingAccentMaterial
local ACCENT_COLOR = defaultTheme.buildingAccentColor
local GLASS_MATERIAL = defaultTheme.buildingGlassMaterial
local GLASS_COLOR = defaultTheme.buildingGlassColor
local GLASS_TRANSPARENCY = defaultTheme.buildingGlassTransparency
local FURNITURE_MATERIAL = defaultTheme.buildingFurnitureMaterial
local FURNITURE_COLOR = defaultTheme.buildingFurnitureColor

--[[
	Latches `theme` for every building-interior/exterior color and
	material in this file - see the module doc comment above for exactly
	which surfaces each field drives.
]]
function BuildingInteriors.SetTheme(theme: LobbyTheme.Theme)
	WALL_MATERIAL = theme.buildingWallMaterial
	EXTERIOR_WALL_COLOR = theme.buildingExteriorWallColor
	INTERIOR_WALL_COLOR = theme.buildingInteriorWallColor
	INTERIOR_FLOOR_COLOR = theme.buildingInteriorFloorColor
	CEILING_COLOR = theme.buildingCeilingColor
	ROOFCAP_COLOR = theme.buildingRoofCapColor
	HEADER_COLOR = theme.buildingHeaderColor
	CANOPY_COLOR = theme.buildingCanopyColor
	ACCENT_MATERIAL = theme.buildingAccentMaterial
	ACCENT_COLOR = theme.buildingAccentColor
	GLASS_MATERIAL = theme.buildingGlassMaterial
	GLASS_COLOR = theme.buildingGlassColor
	GLASS_TRANSPARENCY = theme.buildingGlassTransparency
	FURNITURE_MATERIAL = theme.buildingFurnitureMaterial
	FURNITURE_COLOR = theme.buildingFurnitureColor
end

--[[
	Builds the hollow shell for one building: floor, ceiling, left/right/back
	solid walls, and a plaza-facing (Back/+Z) wall split around a doorway
	gap. Returns the "Base" header part (same role addSign/
	addLeaderboardDisplay already expect - a part whose Back face they can
	put a SurfaceGui on) so Buildings.lua's existing calls don't change.
]]
function BuildingInteriors.BuildShell(def, model: Model): BasePart
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2
	-- Message 20: doorway scales with the building's own width (was a flat
	-- 8 studs regardless of size) - an 8-stud door reads as tiny against a
	-- 61-stud-wide exterior now that buildings are much bigger.
	local DOOR_WIDTH = math.clamp(def.size.X * 0.22, MIN_DOOR_WIDTH, MAX_DOOR_WIDTH)
	local doorHeight = math.min(10, def.height - 4)
	local headerHeight = def.height - doorHeight
	local doorHalfWidth = DOOR_WIDTH / 2
	local basePos = def.position

	PartUtils.CreatePart({
		name = "Floor",
		size = Vector3.new(def.size.X, 0.5, def.size.Y),
		position = basePos + Vector3.new(0, 0.25, 0),
		material = Enum.Material.SmoothPlastic,
		color = INTERIOR_FLOOR_COLOR,
		parent = model,
	})

	PartUtils.CreatePart({
		name = "Ceiling",
		size = Vector3.new(def.size.X, 0.5, def.size.Y),
		position = basePos + Vector3.new(0, def.height - 0.25, 0),
		material = WALL_MATERIAL,
		color = CEILING_COLOR,
		parent = model,
	})

	PartUtils.CreatePart({
		name = "BackWall",
		size = Vector3.new(def.size.X, def.height, WALL_THICKNESS),
		position = basePos + Vector3.new(0, def.height / 2, -halfZ + WALL_THICKNESS / 2),
		material = WALL_MATERIAL,
		color = EXTERIOR_WALL_COLOR,
		parent = model,
	})

	-- Left/Right walls, each with two window strips (glass + neon frame)
	-- instead of a single flat surface - the "layered walls / large
	-- windows" the visual overhaul calls for.
	for _, side in ipairs({ -1, 1 }) do
		local wallX = side * (halfX - WALL_THICKNESS / 2)
		PartUtils.CreatePart({
			name = if side == -1 then "LeftWall" else "RightWall",
			size = Vector3.new(WALL_THICKNESS, def.height, def.size.Y),
			position = basePos + Vector3.new(wallX, def.height / 2, 0),
			material = WALL_MATERIAL,
			color = EXTERIOR_WALL_COLOR,
			parent = model,
		})

		local windowHeight = math.min(5, def.height - 6)
		local windowWidth = math.min(6, def.size.Y * 0.22)
		-- Message 20: a third window pair for the now much-deeper side
		-- walls - two windows looked sparse spread across 30+ studs of depth.
		local windowOffsets = if def.size.Y > 24
			then { -def.size.Y / 3, 0, def.size.Y / 3 }
			else { -def.size.Y / 4, def.size.Y / 4 }
		for _, offsetZ in ipairs(windowOffsets) do
			PartUtils.CreatePart({
				name = "WindowFrame",
				size = Vector3.new(0.3, windowHeight + 0.6, windowWidth + 0.6),
				position = basePos + Vector3.new(side * (halfX - 0.15), def.height * 0.55, offsetZ),
				material = ACCENT_MATERIAL,
				color = ACCENT_COLOR,
				canCollide = false,
				parent = model,
			})
			PartUtils.CreatePart({
				name = "Window",
				size = Vector3.new(0.15, windowHeight, windowWidth),
				position = basePos + Vector3.new(side * (halfX - 0.15), def.height * 0.55, offsetZ),
				material = GLASS_MATERIAL,
				color = GLASS_COLOR,
				transparency = GLASS_TRANSPARENCY,
				canCollide = false,
				parent = model,
			})
		end
	end

	-- Plaza-facing wall, split around the doorway gap.
	local sideSegWidth = halfX - doorHalfWidth
	if sideSegWidth > 0.5 then
		PartUtils.CreatePart({
		name = "FrontWallLeft",
		size = Vector3.new(sideSegWidth, doorHeight, WALL_THICKNESS),
		position = basePos + Vector3.new(-halfX + sideSegWidth / 2, doorHeight / 2, halfZ - WALL_THICKNESS / 2),
		material = WALL_MATERIAL,
		color = EXTERIOR_WALL_COLOR,
		parent = model,
		})
		PartUtils.CreatePart({
		name = "FrontWallRight",
		size = Vector3.new(sideSegWidth, doorHeight, WALL_THICKNESS),
		position = basePos + Vector3.new(halfX - sideSegWidth / 2, doorHeight / 2, halfZ - WALL_THICKNESS / 2),
		material = WALL_MATERIAL,
		color = EXTERIOR_WALL_COLOR,
		parent = model,
		})
		end

	-- "Base": the header above the doorway - full building width, carries
	-- the exterior sign/display exactly as Buildings.lua already expects.
	local base = PartUtils.CreatePart({
		name = "Base",
		size = Vector3.new(def.size.X, headerHeight, WALL_THICKNESS),
		position = basePos + Vector3.new(0, doorHeight + headerHeight / 2, halfZ - WALL_THICKNESS / 2),
		material = WALL_MATERIAL,
		color = HEADER_COLOR,
		parent = model,
	})

	-- Entrance canopy: an angled overhang projecting out from above the
	-- doorway, the single biggest "this looks designed, not extruded"
	-- upgrade an entrance can get cheaply.
	PartUtils.CreatePart({
		className = "WedgePart",
		name = "EntranceCanopy",
		size = Vector3.new(DOOR_WIDTH + 4, 2.5, 5),
		cframe = CFrame.new(basePos + Vector3.new(0, doorHeight + 0.5, halfZ + 2))
			* CFrame.Angles(0, math.rad(180), 0),
		material = WALL_MATERIAL,
		color = CANOPY_COLOR,
		canCollide = false,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "CanopyTrim",
		size = Vector3.new(DOOR_WIDTH + 4.2, 0.25, 0.25),
		position = basePos + Vector3.new(0, doorHeight - 0.6, halfZ + 4.4),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	-- Doorway accent trim (neon strip framing the entrance).
	PartUtils.CreatePart({
		name = "DoorwayTrim",
		size = Vector3.new(DOOR_WIDTH + 1, 0.4, WALL_THICKNESS + 0.2),
		position = basePos + Vector3.new(0, doorHeight, halfZ - WALL_THICKNESS / 2),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	-- Layered roof cap: a smaller, inset volume sitting on the ceiling
	-- with a glowing edge, so the silhouette reads as two stacked masses
	-- rather than one flat-topped box.
	local capInset = 3
	PartUtils.CreatePart({
		name = "RoofCap",
		size = Vector3.new(def.size.X - capInset * 2, 1.5, def.size.Y - capInset * 2),
		position = basePos + Vector3.new(0, def.height + 0.75, 0),
		material = WALL_MATERIAL,
		color = ROOFCAP_COLOR,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "RoofCapTrim",
		size = Vector3.new(def.size.X - capInset * 2 + 0.3, 0.3, def.size.Y - capInset * 2 + 0.3),
		position = basePos + Vector3.new(0, def.height + 1.5, 0),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	-- A couple of ceiling-mounted interior lights (kept minimal per the
	-- performance guidance - no more than needed to keep the room readable).
	for _, offsetZ in ipairs({ -halfZ / 2, halfZ / 2 }) do
		local light = PartUtils.CreatePart({
			name = "CeilingLight",
			size = Vector3.new(4, 0.2, 1.5),
			position = basePos + Vector3.new(0, def.height - 0.7, offsetZ),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
		local pointLight = Instance.new("PointLight")
		pointLight.Color = ACCENT_COLOR
		pointLight.Range = LightingConfig.ACCENT_LIGHT_RANGE
		pointLight.Brightness = LightingConfig.ACCENT_LIGHT_BRIGHTNESS
		pointLight.Parent = light
	end

	-- Floor tile seam pattern (Message 18, section 4 "flooring patterns") -
	-- a handful of thin recessed-look strips running the depth of the room,
	-- shared by every building automatically since it lives in the shell
	-- rather than each Furnish* function repeating it.
	local tileSpacing = def.size.X / 4
	for i = 1, 3 do
		PartUtils.CreatePart({
			name = "FloorSeam" .. i,
			size = Vector3.new(0.15, 0.02, def.size.Y - 2),
			position = basePos + Vector3.new(-halfX + tileSpacing * i, 0.51, 0),
			material = WALL_MATERIAL,
			color = Color3.fromRGB(20, 22, 27),
			canCollide = false,
			parent = model,
		})
	end

	-- Ceiling structural support beams (Message 18, section 4 "ceiling
	-- details / structural supports") - simple recessed-look beams, again
	-- shared automatically by every building via the shell.
	for _, offsetZ in ipairs({ -halfZ * 0.6, 0, halfZ * 0.6 }) do
		PartUtils.CreatePart({
			name = "CeilingBeam",
			size = Vector3.new(def.size.X - 1, 0.4, 0.6),
			position = basePos + Vector3.new(0, def.height - 0.7, offsetZ),
			material = WALL_MATERIAL,
			color = Color3.fromRGB(38, 41, 48),
			canCollide = false,
			parent = model,
		})
	end

	return base
end

local function terminal(model: Model, position: Vector3, promptName: string, promptText: string, objectText: string)
	local stand = PartUtils.CreatePart({
		name = promptName:gsub("Prompt$", "Stand"),
		size = Vector3.new(3, 3.5, 1.5),
		position = position,
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		parent = model,
	})

	PartUtils.CreatePart({
		name = "Screen",
		size = Vector3.new(2.4, 1.6, 0.15),
		position = position + Vector3.new(0, 0.8, 0.85),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = promptName
	prompt.ActionText = objectText
	prompt.ObjectText = promptText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = stand

	return stand
end

--[[
	Shop identity: angled glass storefront bays flanking the entrance, plus
	an illuminated marquee sign above the canopy - makes the Shop read as
	"browse from outside" the moment you approach, distinct from every
	other building's flat facade.

	Message 29 ("make each shop 10x better"): added the marquee (a genuine
	lit sign distinct from the plain name plate on Base) and a warm accent
	spotlight over each storefront bay, so the exterior itself reads as
	"an actual store" even before anyone walks in.
]]
local function addShopIdentity(def, model: Model)
	local basePos = def.position
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2

	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			className = "WedgePart",
			name = "StorefrontBay",
			size = Vector3.new(4, 6, 3),
			cframe = CFrame.new(basePos + Vector3.new(side * (halfX - 2), 4, halfZ + 1))
				* CFrame.Angles(0, math.rad(side == -1 and 90 or -90), 0),
			material = GLASS_MATERIAL,
			color = GLASS_COLOR,
			transparency = GLASS_TRANSPARENCY,
			canCollide = false,
			parent = model,
		})
	end

	-- Illuminated marquee above the entrance canopy - a genuine "this is a
	-- store" beacon, distinct from the plain name plate already on Base.
	local marquee = PartUtils.CreatePart({
		name = "ShopMarquee",
		size = Vector3.new(def.size.X * 0.5, 2, 0.3),
		position = basePos + Vector3.new(0, def.height + 3, halfZ + 4.6),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})
	local marqueeGui = Instance.new("SurfaceGui")
	marqueeGui.Face = Enum.NormalId.Front
	marqueeGui.Parent = marquee
	local marqueeLabel = Instance.new("TextLabel")
	marqueeLabel.Size = UDim2.fromScale(1, 1)
	marqueeLabel.BackgroundTransparency = 1
	marqueeLabel.Font = Enum.Font.GothamBlack
	marqueeLabel.TextScaled = true
	marqueeLabel.TextColor3 = Color3.fromRGB(10, 12, 16)
	marqueeLabel.Text = "OPEN"
	marqueeLabel.Parent = marqueeGui
end

--[[
	Shop: a clear front-to-back store layout using the building's full,
	now much larger floor (Message 20 - "the biggest interior treatment"):
		entrance foyer -> two freestanding aisle islands (with wall shelving
		flanking both sides) -> a cosmetic showcase row -> the counter and
		terminal against the back wall.
	Every row/aisle leaves a clear walkway - the center aisle (|x|<4) runs
	straight from the door to the terminal, and the side walkways (between
	the wall shelves and the freestanding islands) stay clear too.
]]
function BuildingInteriors.FurnishShop(def, model: Model)
	local basePos = def.position
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2

	addShopIdentity(def, model)

	-- Two tiers of wall shelving along both side walls, spanning the full
	-- depth of the room now that there's much more of it to use.
	local wallShelfOffsets = { -halfZ + 4, -halfZ / 3, halfZ / 3 - 2, halfZ - 5 }
	for _, side in ipairs({ -1, 1 }) do
		for _, shelfY in ipairs({ 3.2, 5.6 }) do
			for _, offsetZ in ipairs(wallShelfOffsets) do
				PartUtils.CreatePart({
					name = "WallShelf",
					size = Vector3.new(3.2, 0.25, 1.4),
					position = basePos + Vector3.new(side * (halfX - 2.1), shelfY, offsetZ),
					material = FURNITURE_MATERIAL,
					color = FURNITURE_COLOR,
					parent = model,
				})
				PartUtils.CreatePart({
					name = "ShelfItem",
					size = Vector3.new(0.8, 0.8, 0.8),
					position = basePos + Vector3.new(side * (halfX - 2.1), shelfY + 0.55, offsetZ),
					material = ACCENT_MATERIAL,
					color = ACCENT_COLOR,
					canCollide = false,
					parent = model,
				})
			end
		end
	end

	-- Two freestanding, double-sided aisle islands in the middle third of
	-- the room - the actual "browse between rows" store experience the
	-- wall shelving alone can't provide. Positioned well clear of both the
	-- center walkway (|x|<4) and the side walkways (between the island and
	-- the wall shelves).
	for _, aisleX in ipairs({ -halfX * 0.4, halfX * 0.4 }) do
		PartUtils.CreatePart({
			name = "AisleIsland",
			size = Vector3.new(2.2, 4, halfZ * 0.7),
			position = basePos + Vector3.new(aisleX, 2, halfZ * 0.05),
			material = FURNITURE_MATERIAL,
			color = FURNITURE_COLOR,
			parent = model,
		})
		for _, itemOffsetZ in ipairs({ -halfZ * 0.25, 0, halfZ * 0.25 }) do
			for _, faceX in ipairs({ -1, 1 }) do
				PartUtils.CreatePart({
					name = "AisleItem",
					size = Vector3.new(0.9, 0.9, 0.9),
					position = basePos
						+ Vector3.new(aisleX + faceX * 1.5, 4.2, itemOffsetZ + halfZ * 0.05),
					material = ACCENT_MATERIAL,
					color = ACCENT_COLOR,
					canCollide = false,
					parent = model,
				})
			end
		end
	end

	-- Floor accent stripe leading from the doorway straight down the
	-- center aisle to the counter.
	PartUtils.CreatePart({
		name = "FloorAccent",
		size = Vector3.new(2, 0.05, def.size.Y - 8),
		position = basePos + Vector3.new(0, 0.53, 1),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		transparency = 0.5,
		canCollide = false,
		parent = model,
	})

	-- Cosmetic showcase row, just in front of the counter - the "look but
	-- don't buy yet" zone between the aisles and checkout.
	for _, x in ipairs({ -halfX * 0.35, 0, halfX * 0.35 }) do
		PartUtils.CreatePart({
			name = "DisplayPlinth",
			size = Vector3.new(2, 3, 2),
			position = basePos + Vector3.new(x, 1.5, -halfZ * 0.35),
			material = FURNITURE_MATERIAL,
			color = FURNITURE_COLOR,
			parent = model,
		})
		PartUtils.CreatePart({
			name = "DisplayItem",
			size = Vector3.new(1.2, 1.2, 1.2),
			position = basePos + Vector3.new(x, 3.6, -halfZ * 0.35),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
	end

	-- Counter + register + terminal against the back wall - the store's
	-- clear "end point", now with a proper checkout register (a small
	-- raised monitor + neon accent) and its own overhead spotlight, rather
	-- than a bare counter slab.
	PartUtils.CreatePart({
		name = "Counter",
		size = Vector3.new(math.min(14, def.size.X - 8), 3.5, 2.5),
		position = basePos + Vector3.new(0, 1.75, -halfZ + 4),
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "CounterRegister",
		size = Vector3.new(1.6, 1.2, 1.2),
		position = basePos + Vector3.new(0, 4.1, -halfZ + 3.6),
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "CounterRegisterScreen",
		size = Vector3.new(1, 0.7, 0.1),
		position = basePos + Vector3.new(0, 4.3, -halfZ + 3.05),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	terminal(model, basePos + Vector3.new(0, 0, -halfZ + 7.5), "ShopTerminalPrompt", "Open Shop", "Shop")
end

--[[
	DailyRewards identity: a stepped, trophy-like tower rising off the
	roof - three shrinking tiers with neon seams, reading as "progression/
	achievement" from across the lobby.
]]
local function addRewardsIdentity(def, model: Model)
	local basePos = def.position
	local tiers = { { size = 10, height = 3 }, { size = 7, height = 3 }, { size = 4, height = 4 } }
	local y = def.height + 1.5

	for i, tier in ipairs(tiers) do
		PartUtils.CreatePart({
			name = "RewardTower" .. i,
			size = Vector3.new(tier.size, tier.height, tier.size),
			position = basePos + Vector3.new(0, y + tier.height / 2, 0),
			material = FURNITURE_MATERIAL,
			color = FURNITURE_COLOR,
			parent = model,
		})
		PartUtils.CreatePart({
			name = "RewardTowerTrim" .. i,
			size = Vector3.new(tier.size + 0.3, 0.25, tier.size + 0.3),
			position = basePos + Vector3.new(0, y + tier.height, 0),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
		y += tier.height
	end

	PartUtils.CreatePart({
		name = "RewardBeacon",
		size = Vector3.new(1.2, 1.2, 1.2),
		position = basePos + Vector3.new(0, y + 1, 0),
		material = Enum.Material.Neon,
		color = Color3.fromRGB(255, 215, 0),
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})
end

--[[
	Daily Rewards: the stepped trophy tower outside, and inside - a clear
	"hall of milestones" using the building's larger floor (Message 20):
	entrance -> a center row of milestone pedestals players walk past ->
	the progression wall + Rewards Terminal against the back wall. Side-
	wall milestone screens flank the whole walk.
]]
function BuildingInteriors.FurnishRewards(def, model: Model)
	local basePos = def.position
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2

	addRewardsIdentity(def, model)

	-- Side-wall milestone screens - small floating panels suggesting
	-- individual reward tiers, flanking the walk from door to terminal.
	for _, side in ipairs({ -1, 1 }) do
		for i, offsetZ in ipairs({ halfZ - 6, 0, -halfZ + 8 }) do
			PartUtils.CreatePart({
				name = "MilestonePanel" .. i,
				size = Vector3.new(0.2, 2.4, 2.4),
				position = basePos + Vector3.new(side * (halfX - 0.3), 5, offsetZ),
				material = ACCENT_MATERIAL,
				color = ACCENT_COLOR,
				transparency = 0.2,
				canCollide = false,
				parent = model,
			})
		end
	end

	-- Center row of milestone pedestals - the actual "hall" walk-through,
	-- filling the room's middle rather than leaving it empty between the
	-- door and the back wall. Spaced to leave clear side walkways.
	for i, offsetZ in ipairs({ halfZ * 0.45, 0, -halfZ * 0.45 }) do
		PartUtils.CreatePart({
			name = "MilestonePedestal" .. i,
			size = Vector3.new(3, 2.5, 3),
			position = basePos + Vector3.new(0, 1.25, offsetZ),
			material = FURNITURE_MATERIAL,
			color = FURNITURE_COLOR,
			parent = model,
		})
		PartUtils.CreatePart({
			name = "MilestoneTrophy" .. i,
			size = Vector3.new(1.4, 1.4, 1.4),
			position = basePos + Vector3.new(0, 3.2, offsetZ),
			material = Enum.Material.Neon,
			color = if i == 2 then Color3.fromRGB(255, 215, 0) else ACCENT_COLOR,
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = model,
		})
	end

	PartUtils.CreatePart({
		name = "ProgressionWall",
		size = Vector3.new(def.size.X - 6, def.height - 8, 0.3),
		position = basePos + Vector3.new(0, def.height / 2, -halfZ + 1),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	terminal(model, basePos + Vector3.new(0, 0, -halfZ + 5), "DailyRewardsTerminalPrompt", "Claim Daily Reward", "Daily Rewards")
end

--[[
	Statistics identity: a tall vertical "data spire" rising well above
	the roofline with stacked neon rings - reads as "data/analytics" from
	a distance, and gives the shortest building real verticality/presence.
]]
local function addStatisticsIdentity(def, model: Model)
	local basePos = def.position
	local spireHeight = 16
	local spireTop = def.height + spireHeight

	PartUtils.CreatePart({
		name = "DataSpire",
		size = Vector3.new(1.6, spireHeight, 1.6),
		position = basePos + Vector3.new(0, def.height + spireHeight / 2, 0),
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		canCollide = false,
		parent = model,
	})

	for i = 1, 3 do
		local ringY = def.height + (spireHeight / 4) * i
		PartUtils.CreateDisc({
			name = "SpireRing" .. i,
			diameter = 3 + i * 0.6,
			thickness = 0.3,
			position = basePos + Vector3.new(0, ringY, 0),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
	end

	local beacon = PartUtils.CreatePart({
		name = "SpireBeacon",
		size = Vector3.new(1.4, 1.4, 1.4),
		position = basePos + Vector3.new(0, spireTop + 0.7, 0),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = ACCENT_COLOR
	light.Range = LightingConfig.ACCENT_LIGHT_RANGE
	light.Brightness = LightingConfig.ACCENT_LIGHT_BRIGHTNESS
	light.Parent = beacon
end

--[[
	Statistics Building: the data spire outside, and inside - a data
	"reading room" (Message 20): entrance -> a center row of player-
	statistics terminal stations with simple bench seating -> the big
	stat-screen wall + Statistics Terminal against the back wall. Side
	monitor screens flank the room.
]]
function BuildingInteriors.FurnishStatistics(def, model: Model)
	local basePos = def.position
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2

	addStatisticsIdentity(def, model)

	-- Side monitor screens along both walls, spanning the room's depth.
	for _, side in ipairs({ -1, 1 }) do
		for _, offsetZ in ipairs({ halfZ - 4, 0, -halfZ + 5 }) do
			PartUtils.CreatePart({
				name = "MonitorStand",
				size = Vector3.new(0.4, 2.5, 1.6),
				position = basePos + Vector3.new(side * (halfX - 1.5), 2.5, offsetZ),
				material = FURNITURE_MATERIAL,
				color = FURNITURE_COLOR,
				parent = model,
			})
			PartUtils.CreatePart({
				name = "MonitorScreen",
				size = Vector3.new(0.15, 1.6, 1.2),
				position = basePos + Vector3.new(side * (halfX - 1.25), 2.9, offsetZ),
				material = ACCENT_MATERIAL,
				color = ACCENT_COLOR,
				canCollide = false,
				parent = model,
			})
		end
	end

	-- Center row of player-data terminal stations with a bench each, so
	-- the room's middle reads as a place to actually sit and review your
	-- own stats, not empty floor between the door and the back wall.
	for _, offsetZ in ipairs({ halfZ * 0.4, -halfZ * 0.15 }) do
		PartUtils.CreatePart({
			name = "DataStation",
			size = Vector3.new(3, 2.8, 1.4),
			position = basePos + Vector3.new(0, 1.4, offsetZ),
			material = FURNITURE_MATERIAL,
			color = FURNITURE_COLOR,
			parent = model,
		})
		PartUtils.CreatePart({
			name = "DataStationScreen",
			size = Vector3.new(2.2, 1.3, 0.15),
			position = basePos + Vector3.new(0, 2.9, offsetZ - 0.6),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
		PartUtils.CreatePart({
			name = "DataStationBench",
			size = Vector3.new(2.6, 1, 1.2),
			position = basePos + Vector3.new(0, 0.6, offsetZ + 1.6),
			material = FURNITURE_MATERIAL,
			color = FURNITURE_COLOR,
			parent = model,
		})
	end

	PartUtils.CreatePart({
		name = "StatScreen",
		size = Vector3.new(def.size.X - 8, def.height - 6, 0.3),
		position = basePos + Vector3.new(0, def.height / 2, -halfZ + 1),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	terminal(model, basePos + Vector3.new(0, 0, -halfZ + 5), "StatisticsTerminalPrompt", "View Statistics", "Statistics")
end

--[[
	Tutorial identity: a friendly rounded-corner turret rising above the
	roof with a welcoming beacon on top - softer/rounder than the other
	buildings' hard edges, matching its "welcoming, learn here" purpose.
]]
local function addTutorialIdentity(def, model: Model)
	local basePos = def.position
	local turretHeight = 8

	PartUtils.CreatePart({
		name = "Turret",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(turretHeight, 6, 6),
		orientation = Vector3.new(0, 0, 90),
		position = basePos + Vector3.new(0, def.height + turretHeight / 2, 0),
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		canCollide = false,
		parent = model,
	})
	PartUtils.CreateDisc({
		name = "TurretTrim",
		diameter = 6.4,
		thickness = 0.3,
		position = basePos + Vector3.new(0, def.height + turretHeight, 0),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	local beacon = PartUtils.CreatePart({
		name = "TutorialBeacon",
		size = Vector3.new(2, 2, 2),
		position = basePos + Vector3.new(0, def.height + turretHeight + 1.5, 0),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		shape = Enum.PartType.Ball,
		canCollide = false,
		parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = ACCENT_COLOR
	light.Range = LightingConfig.ACCENT_LIGHT_RANGE
	light.Brightness = LightingConfig.ACCENT_LIGHT_BRIGHTNESS
	light.Parent = beacon
end

--[[
	Tutorial Building: the rounded turret outside, and inside - a genuine
	front-to-back learning path (Message 20, section 7 - "the player should
	naturally move from one tutorial area to another"): welcome desk near
	the door -> an example question station in the middle, flanked by
	seating -> the Tutorial Terminal against the back wall, framed by wall
	info-panels.
]]
function BuildingInteriors.FurnishTutorial(def, model: Model)
	local basePos = def.position
	local halfX = def.size.X / 2
	local halfZ = def.size.Y / 2

	addTutorialIdentity(def, model)

	-- Welcome desk just inside the entrance - the first thing a new player
	-- reaches.
	PartUtils.CreatePart({
		name = "WelcomeDesk",
		size = Vector3.new(8, 3, 2),
		position = basePos + Vector3.new(0, 1.5, halfZ - 4),
		material = FURNITURE_MATERIAL,
		color = FURNITURE_COLOR,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "WelcomeSign",
		size = Vector3.new(6, 1.4, 0.15),
		position = basePos + Vector3.new(0, 3.6, halfZ - 4),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	-- Example question station in the middle of the room - a floating
	-- "12 x 8 = ?"-style demo screen with a bench on each side, the room's
	-- clear second stop on the learning path.
	PartUtils.CreatePart({
		name = "ExampleQuestionScreen",
		size = Vector3.new(6, 3, 0.2),
		position = basePos + Vector3.new(0, 3.2, 1),
		material = ACCENT_MATERIAL,
		color = ACCENT_COLOR,
		transparency = 0.1,
		canCollide = false,
		parent = model,
	})
	for _, x in ipairs({ -4, 4 }) do
		PartUtils.CreatePart({
			name = "Chair",
			size = Vector3.new(1.5, 1.5, 1.5),
			position = basePos + Vector3.new(x, 0.75, 4),
			material = FURNITURE_MATERIAL,
			color = FURNITURE_COLOR,
			parent = model,
		})
	end

	-- Wall info-panels flanking the final stretch toward the terminal.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "InfoPanel",
			size = Vector3.new(0.2, 3, 4),
			position = basePos + Vector3.new(side * (halfX - 0.3), 4, -halfZ * 0.4),
			material = ACCENT_MATERIAL,
			color = ACCENT_COLOR,
			transparency = 0.25,
			canCollide = false,
			parent = model,
		})
	end

	terminal(model, basePos + Vector3.new(0, 0, -halfZ + 5), "TutorialTerminalPrompt", "Learn How to Play", "Tutorial")
end

return BuildingInteriors
