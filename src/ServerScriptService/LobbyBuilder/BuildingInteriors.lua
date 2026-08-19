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
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local LobbyConfig = require(script.Parent.LobbyConfig)
local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)

local BuildingInteriors = {}

local WALL_THICKNESS = 1
local DOOR_WIDTH = 8

local INTERIOR_WALL_COLOR = Color3.fromRGB(40, 43, 50)
local INTERIOR_FLOOR_COLOR = Color3.fromRGB(30, 32, 38)
local EXTERIOR_WALL_COLOR = Color3.fromRGB(52, 56, 66)
local ACCENT_COLOR = LobbyConfig.NEON_COLOR
local GLASS_COLOR = Color3.fromRGB(120, 200, 255)

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
		material = Enum.Material.Metal,
		color = Color3.fromRGB(50, 53, 60),
		parent = model,
	})

	PartUtils.CreatePart({
		name = "BackWall",
		size = Vector3.new(def.size.X, def.height, WALL_THICKNESS),
		position = basePos + Vector3.new(0, def.height / 2, -halfZ + WALL_THICKNESS / 2),
		material = Enum.Material.Metal,
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
			material = Enum.Material.Metal,
			color = EXTERIOR_WALL_COLOR,
			parent = model,
		})

		local windowHeight = math.min(5, def.height - 6)
		local windowWidth = math.min(6, def.size.Y * 0.3)
		for _, offsetZ in ipairs({ -def.size.Y / 4, def.size.Y / 4 }) do
			PartUtils.CreatePart({
				name = "WindowFrame",
				size = Vector3.new(0.3, windowHeight + 0.6, windowWidth + 0.6),
				position = basePos + Vector3.new(side * (halfX - 0.15), def.height * 0.55, offsetZ),
				material = Enum.Material.Metal,
				color = ACCENT_COLOR,
				canCollide = false,
				parent = model,
			})
			PartUtils.CreatePart({
				name = "Window",
				size = Vector3.new(0.15, windowHeight, windowWidth),
				position = basePos + Vector3.new(side * (halfX - 0.15), def.height * 0.55, offsetZ),
				material = Enum.Material.Glass,
				color = GLASS_COLOR,
				transparency = 0.45,
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
		material = Enum.Material.Metal,
		color = EXTERIOR_WALL_COLOR,
		parent = model,
		})
		PartUtils.CreatePart({
		name = "FrontWallRight",
		size = Vector3.new(sideSegWidth, doorHeight, WALL_THICKNESS),
		position = basePos + Vector3.new(halfX - sideSegWidth / 2, doorHeight / 2, halfZ - WALL_THICKNESS / 2),
		material = Enum.Material.Metal,
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
		material = Enum.Material.Metal,
		color = Color3.fromRGB(60, 65, 75),
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
		material = Enum.Material.Metal,
		color = Color3.fromRGB(60, 65, 75),
		canCollide = false,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "CanopyTrim",
		size = Vector3.new(DOOR_WIDTH + 4.2, 0.25, 0.25),
		position = basePos + Vector3.new(0, doorHeight - 0.6, halfZ + 4.4),
		material = Enum.Material.Neon,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	-- Doorway accent trim (neon strip framing the entrance).
	PartUtils.CreatePart({
		name = "DoorwayTrim",
		size = Vector3.new(DOOR_WIDTH + 1, 0.4, WALL_THICKNESS + 0.2),
		position = basePos + Vector3.new(0, doorHeight, halfZ - WALL_THICKNESS / 2),
		material = Enum.Material.Neon,
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
		material = Enum.Material.Metal,
		color = Color3.fromRGB(45, 48, 56),
		parent = model,
	})
	PartUtils.CreatePart({
		name = "RoofCapTrim",
		size = Vector3.new(def.size.X - capInset * 2 + 0.3, 0.3, def.size.Y - capInset * 2 + 0.3),
		position = basePos + Vector3.new(0, def.height + 1.5, 0),
		material = Enum.Material.Neon,
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
			material = Enum.Material.Neon,
			color = Color3.fromRGB(230, 240, 255),
			canCollide = false,
			parent = model,
		})
		local pointLight = Instance.new("PointLight")
		pointLight.Color = Color3.fromRGB(220, 230, 255)
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
			material = Enum.Material.Metal,
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
			material = Enum.Material.Metal,
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
		material = Enum.Material.Metal,
		color = Color3.fromRGB(45, 48, 56),
		parent = model,
	})

	PartUtils.CreatePart({
		name = "Screen",
		size = Vector3.new(2.4, 1.6, 0.15),
		position = position + Vector3.new(0, 0.8, 0.85),
		material = Enum.Material.Neon,
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
	Shop identity: angled glass storefront bays flanking the entrance -
	makes the Shop read as "browse from outside" the moment you approach,
	distinct from every other building's flat facade.
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
			material = Enum.Material.Glass,
			color = GLASS_COLOR,
			transparency = 0.35,
			canCollide = false,
			parent = model,
		})
	end
end

--[[
	Shop: counter, a couple of floating cosmetic display plinths, the
	angled storefront bays, TWO tiers of wall shelving rows, and the Shop
	Terminal (opens the existing Shop UI). Message 18, section 5 asks
	specifically for "rows" (plural) of shelving along the walls, so this
	adds a second, higher tier and a third position along each wall on top
	of the single row Message 17 already had.
]]
function BuildingInteriors.FurnishShop(def, model: Model)
	local basePos = def.position

	addShopIdentity(def, model)

	-- Two tiers of wall shelving, three positions per wall, along both
	-- side walls (clear of the center walkway) - reads as real store
	-- shelving rows rather than a couple of floating props.
	for _, side in ipairs({ -1, 1 }) do
		for _, shelfY in ipairs({ 3.2, 5.6 }) do
			for _, offsetZ in ipairs({ -7, -1.5, 4 }) do
				PartUtils.CreatePart({
					name = "WallShelf",
					size = Vector3.new(3.2, 0.25, 1.4),
					position = basePos + Vector3.new(side * (def.size.X / 2 - 2.1), shelfY, offsetZ),
					material = Enum.Material.Metal,
					color = Color3.fromRGB(50, 53, 62),
					parent = model,
				})
				PartUtils.CreatePart({
					name = "ShelfItem",
					size = Vector3.new(0.8, 0.8, 0.8),
					position = basePos + Vector3.new(side * (def.size.X / 2 - 2.1), shelfY + 0.55, offsetZ),
					material = Enum.Material.Neon,
					color = ACCENT_COLOR,
					canCollide = false,
					parent = model,
				})
			end
		end
	end

	-- Floor accent stripe leading from the doorway to the counter.
	PartUtils.CreatePart({
		name = "FloorAccent",
		size = Vector3.new(2, 0.05, def.size.Y - 8),
		position = basePos + Vector3.new(0, 0.53, 1),
		material = Enum.Material.Neon,
		color = ACCENT_COLOR,
		transparency = 0.5,
		canCollide = false,
		parent = model,
	})

	PartUtils.CreatePart({
		name = "Counter",
		size = Vector3.new(10, 3.5, 2.5),
		position = basePos + Vector3.new(0, 1.75, -def.size.Y / 2 + 4),
		material = Enum.Material.Metal,
		color = Color3.fromRGB(50, 53, 62),
		parent = model,
	})

	for _, x in ipairs({ -8, 8 }) do
		PartUtils.CreatePart({
			name = "DisplayPlinth",
			size = Vector3.new(2, 3, 2),
			position = basePos + Vector3.new(x, 1.5, 2),
			material = Enum.Material.Metal,
			color = Color3.fromRGB(45, 48, 56),
			parent = model,
		})
		PartUtils.CreatePart({
			name = "DisplayItem",
			size = Vector3.new(1.2, 1.2, 1.2),
			position = basePos + Vector3.new(x, 3.6, 2),
			material = Enum.Material.Neon,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
	end

	terminal(model, basePos + Vector3.new(0, 0, -def.size.Y / 2 + 6.5), "ShopTerminalPrompt", "Open Shop", "Shop")
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
			material = Enum.Material.Metal,
			color = Color3.fromRGB(50, 53, 62),
			parent = model,
		})
		PartUtils.CreatePart({
			name = "RewardTowerTrim" .. i,
			size = Vector3.new(tier.size + 0.3, 0.25, tier.size + 0.3),
			position = basePos + Vector3.new(0, y + tier.height, 0),
			material = Enum.Material.Neon,
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
	Daily Rewards: the stepped trophy tower, a big progression wall panel,
	side-wall milestone screens, and the Rewards Terminal (opens the
	existing win-based Rewards UI).
]]
function BuildingInteriors.FurnishRewards(def, model: Model)
	local basePos = def.position

	addRewardsIdentity(def, model)

	-- Side-wall milestone screens - small floating panels suggesting
	-- individual reward tiers, flanking the main progression wall.
	for _, side in ipairs({ -1, 1 }) do
		for i, offsetZ in ipairs({ -4, 3 }) do
			PartUtils.CreatePart({
				name = "MilestonePanel" .. i,
				size = Vector3.new(0.2, 2.2, 2.2),
				position = basePos + Vector3.new(side * (def.size.X / 2 - 0.3), 5, offsetZ),
				material = Enum.Material.Neon,
				color = ACCENT_COLOR,
				transparency = 0.2,
				canCollide = false,
				parent = model,
			})
		end
	end

	PartUtils.CreatePart({
		name = "ProgressionWall",
		size = Vector3.new(def.size.X - 6, def.height - 8, 0.3),
		position = basePos + Vector3.new(0, def.height / 2, -def.size.Y / 2 + 1),
		material = Enum.Material.Neon,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	terminal(
		model,
		basePos + Vector3.new(0, 0, def.size.Y / 2 - 5),
		"RewardsTerminalPrompt",
		"Open Rewards",
		"Rewards"
	)
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
		material = Enum.Material.Metal,
		color = Color3.fromRGB(55, 58, 66),
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
			material = Enum.Material.Neon,
			color = ACCENT_COLOR,
			canCollide = false,
			parent = model,
		})
	end

	local beacon = PartUtils.CreatePart({
		name = "SpireBeacon",
		size = Vector3.new(1.4, 1.4, 1.4),
		position = basePos + Vector3.new(0, spireTop + 0.7, 0),
		material = Enum.Material.Neon,
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
	Statistics Building: the data spire, a stat-screen wall, side monitor
	screens, a chair at the terminal, and the Statistics Terminal (opens
	the existing Stats modal).
]]
function BuildingInteriors.FurnishStatistics(def, model: Model)
	local basePos = def.position

	addStatisticsIdentity(def, model)

	-- Side monitor screens along both walls (clear of the center walkway).
	for _, side in ipairs({ -1, 1 }) do
		for _, offsetZ in ipairs({ -3, 3 }) do
			PartUtils.CreatePart({
				name = "MonitorStand",
				size = Vector3.new(0.4, 2.5, 1.6),
				position = basePos + Vector3.new(side * (def.size.X / 2 - 1.5), 2.5, offsetZ),
				material = Enum.Material.Metal,
				color = Color3.fromRGB(45, 48, 56),
				parent = model,
			})
			PartUtils.CreatePart({
				name = "MonitorScreen",
				size = Vector3.new(0.15, 1.6, 1.2),
				position = basePos + Vector3.new(side * (def.size.X / 2 - 1.25), 2.9, offsetZ),
				material = Enum.Material.Neon,
				color = ACCENT_COLOR,
				canCollide = false,
				parent = model,
			})
		end
	end

	PartUtils.CreatePart({
		name = "StatScreen",
		size = Vector3.new(def.size.X - 8, def.height - 6, 0.3),
		position = basePos + Vector3.new(0, def.height / 2, -def.size.Y / 2 + 1),
		material = Enum.Material.Neon,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	terminal(
		model,
		basePos + Vector3.new(0, 0, def.size.Y / 2 - 5),
		"StatisticsTerminalPrompt",
		"View Statistics",
		"Statistics"
	)
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
		material = Enum.Material.Metal,
		color = Color3.fromRGB(50, 53, 62),
		canCollide = false,
		parent = model,
	})
	PartUtils.CreateDisc({
		name = "TurretTrim",
		diameter = 6.4,
		thickness = 0.3,
		position = basePos + Vector3.new(0, def.height + turretHeight, 0),
		material = Enum.Material.Neon,
		color = ACCENT_COLOR,
		canCollide = false,
		parent = model,
	})

	local beacon = PartUtils.CreatePart({
		name = "TutorialBeacon",
		size = Vector3.new(2, 2, 2),
		position = basePos + Vector3.new(0, def.height + turretHeight + 1.5, 0),
		material = Enum.Material.Neon,
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
	Tutorial Building: the rounded turret, a welcome desk, a couple of
	seating chairs, wall info-panels, and the Tutorial Terminal (opens
	TutorialUIController).
]]
function BuildingInteriors.FurnishTutorial(def, model: Model)
	local basePos = def.position

	addTutorialIdentity(def, model)

	-- Wall info-panels flanking the room (clear of the center walkway).
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "InfoPanel",
			size = Vector3.new(0.2, 3, 4),
			position = basePos + Vector3.new(side * (def.size.X / 2 - 0.3), 4, -2),
			material = Enum.Material.Neon,
			color = ACCENT_COLOR,
			transparency = 0.25,
			canCollide = false,
			parent = model,
		})
	end

	-- A couple of simple seating chairs near the welcome desk.
	for _, x in ipairs({ -3, 3 }) do
		PartUtils.CreatePart({
			name = "Chair",
			size = Vector3.new(1.5, 1.5, 1.5),
			position = basePos + Vector3.new(x, 0.75, -def.size.Y / 2 + 6),
			material = Enum.Material.Metal,
			color = Color3.fromRGB(55, 58, 66),
			parent = model,
		})
	end

	PartUtils.CreatePart({
		name = "WelcomeDesk",
		size = Vector3.new(8, 3, 2),
		position = basePos + Vector3.new(0, 1.5, -def.size.Y / 2 + 3),
		material = Enum.Material.Metal,
		color = Color3.fromRGB(50, 53, 62),
		parent = model,
	})

	terminal(
		model,
		basePos + Vector3.new(0, 0, def.size.Y / 2 - 5),
		"TutorialTerminalPrompt",
		"Learn How to Play",
		"Tutorial"
	)
end

return BuildingInteriors
