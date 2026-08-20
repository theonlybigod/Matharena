--[[
	Seating.lua

	Builds the lobby's seating: a single, upgraded bench design (see
	SeatingConfig.SEAT_TYPE), placed into five hand-designed seating
	zones. Every seat model carries:
		- Attribute SeatingConfig.DECORATIVE_ATTRIBUTE = true
		- Attribute "SeatType" = SeatingConfig.SEAT_TYPE.id
		- Attribute "SeatingZone" = the zone id (e.g. "WalkwayZone")
	so later systems (or just manual inspection) can reliably identify
	seating without depending on tree position/naming.

	Rebuild pass (seating/trees/branding cleanup): the previous four
	distinct seat types (SeatTypeA-D) have been replaced with ONE upgraded
	bench, built from SeatTypeA's silhouette as a starting reference but
	bigger, taller, and more detailed - a real cross-brace between the
	legs, angled corner caps at each end of the backrest, and a double
	neon trim (base underglow + backrest top trim) instead of the single
	strip the old version had.

	Real interactive Seat (not just decorative): the main seat surface is
	now built with className "Seat" (a real Roblox Seat instance), not a
	plain Part - "account for the actual Seat orientation" in the design
	brief only makes sense for a genuine Seat, and a plain decorative Part
	can't be sat on at all, so there was nothing to verify facing
	direction against before. A Roblox Seat's occupant faces the seat
	part's own Front direction (local -Z, i.e. its CFrame's LookVector).
	Every bench's CFrame is computed by BuildAll (via yawTowards below) so
	that LookVector always points from the bench's position toward the
	map's true center (world (0, 0)) - "every bench faces the center of
	the map" holds by construction for every zone, not per-placement
	authored angles. The backrest is built on the OPPOSITE side (local
	+Z, "Back") from the seat's Front/facing direction, matching normal
	chair convention (support behind the seated player, not in front of
	them) - the previous decorative-only version had this backwards
	(harmless while nothing could actually sit in it, but wrong once the
	seat became a real, sittable Seat).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PartUtils = require(ReplicatedStorage.Modules.PartUtils)
local SeatingConfig = require(script.Parent.SeatingConfig)

local Seating = {}

--[[
	Computes the yaw (degrees) that makes a part's default -Z-facing
	orientation (zero rotation) point exactly from `fromPos` toward
	`toPos`, ignoring height. Same validated convention used for spawn
	facing (LobbyConfig.lua's yawTowards): yaw = atan2(-dirX, -dirZ) for a
	CFrame.Angles(0, yaw, 0) rotation, so a Roblox Seat's occupant (who
	faces the seat's own -Z/Front direction) ends up facing exactly
	toward `toPos`.
]]
local function yawTowards(fromPos: Vector3, toPos: Vector3): number
	local dir = toPos - fromPos
	return math.deg(math.atan2(-dir.X, -dir.Z))
end

--[[
	Builds the single upgraded bench at `cframe` (already oriented so its
	Front/-Z direction faces the map center - see yawTowards above),
	parented into `model`.
]]
local function buildBench(cframe: CFrame, model: Model, def: SeatingConfig.SeatTypeDef)
	local legHeight = 1.7 -- was 1.2 - taller, more substantial stance
	local legWidth = 0.5 -- was 0.35 - thicker, more substantial legs
	local seatY = legHeight + def.seatSize.Y / 2

	-- Real, sittable Seat (not a plain decorative Part) - see module doc
	-- for why this matters for verifying facing direction.
	PartUtils.CreatePart({
		className = "Seat",
		name = "Seat",
		size = def.seatSize,
		cframe = cframe * CFrame.new(0, seatY, 0),
		material = def.seatMaterial,
		color = def.seatColor,
		parent = model,
	})

	-- Center console/spine trim down the middle of the seat surface - a
	-- small raised detail line, purely cosmetic, that reads as
	-- "constructed/futuristic" rather than a single flat plank.
	PartUtils.CreatePart({
		name = "SeatSpineTrim",
		size = Vector3.new(0.35, 0.06, def.seatSize.Z - 0.3),
		cframe = cframe * CFrame.new(0, seatY + def.seatSize.Y / 2 + 0.03, 0),
		material = Enum.Material.Neon,
		color = def.accentColor,
		canCollide = false,
		parent = model,
	})

	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "Leg",
			size = Vector3.new(legWidth, legHeight, def.seatSize.Z - 0.2),
			cframe = cframe * CFrame.new(side * (def.seatSize.X / 2 - 0.6), legHeight / 2, 0),
			material = Enum.Material.Metal,
			color = Color3.fromRGB(60, 63, 70),
			parent = model,
		})
	end

	-- Cross-brace bar connecting the two legs near the ground - a real
	-- structural detail the previous version didn't have, reads as an
	-- actually-engineered bench frame rather than two independent legs.
	PartUtils.CreatePart({
		name = "CrossBrace",
		size = Vector3.new(def.seatSize.X - 1.2, 0.25, 0.25),
		cframe = cframe * CFrame.new(0, legHeight * 0.35, def.seatSize.Z / 2 - 0.15),
		material = Enum.Material.Metal,
		color = Color3.fromRGB(60, 63, 70),
		canCollide = false,
		parent = model,
	})

	-- Backrest on the Back (+Z) side - BEHIND a player facing the seat's
	-- Front/-Z direction, matching normal chair convention (see module
	-- doc for why this flipped from the previous decorative-only build).
	local backrestZ = def.seatSize.Z / 2
	PartUtils.CreatePart({
		name = "Backrest",
		size = Vector3.new(def.seatSize.X, def.backrestHeight, 0.3),
		cframe = cframe * CFrame.new(0, seatY + def.backrestHeight / 2, backrestZ),
		material = def.seatMaterial,
		color = def.seatColor,
		canCollide = false,
		parent = model,
	})

	-- Angled corner caps at each end of the backrest top - a small
	-- futuristic accent detail (not full armrests), new in this pass.
	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			className = "WedgePart",
			name = "BackrestCornerCap",
			size = Vector3.new(0.6, 0.5, 0.6),
			cframe = cframe
				* CFrame.new(side * (def.seatSize.X / 2 - 0.1), seatY + def.backrestHeight + 0.15, backrestZ)
				* CFrame.Angles(0, math.rad(side == -1 and 90 or -90), 0),
			material = Enum.Material.Metal,
			color = Color3.fromRGB(60, 63, 70),
			canCollide = false,
			parent = model,
		})
	end

	-- Backrest top trim (new) + base underglow strip (kept from before,
	-- now on the Front/-Z edge to match the corrected facing) - a double
	-- neon accent instead of the single strip the old version had.
	PartUtils.CreatePart({
		name = "BackrestTopTrim",
		size = Vector3.new(def.seatSize.X - 0.4, 0.1, 0.15),
		cframe = cframe * CFrame.new(0, seatY + def.backrestHeight + 0.05, backrestZ),
		material = Enum.Material.Neon,
		color = def.accentColor,
		canCollide = false,
		parent = model,
	})
	PartUtils.CreatePart({
		name = "UnderglowStrip",
		size = Vector3.new(def.seatSize.X - 0.6, 0.1, 0.15),
		cframe = cframe * CFrame.new(0, legHeight - 0.15, -def.seatSize.Z / 2 + 0.1),
		material = Enum.Material.Neon,
		color = def.accentColor,
		canCollide = false,
		parent = model,
	})
end

--[[
	Builds every seat in every zone from SeatingConfig.ZONES, parented
	into a single "LobbySeating" folder under `parent` (the lobby folder).
	Returns the folder, plus a flat list of every seat's world position -
	Decorations.lua feeds that list into street lamp / tree placement
	avoidance so nothing gets built on top of a seating zone.
]]
function Seating.BuildAll(parent: Instance): (Folder, { Vector3 })
	local folder = Instance.new("Folder")
	folder.Name = "LobbySeating"
	folder:SetAttribute(SeatingConfig.ROOT_ATTRIBUTE, true)
	folder.Parent = parent

	local allPositions = {}
	local seatDef = SeatingConfig.SEAT_TYPE

	for _, zone in ipairs(SeatingConfig.ZONES) do
		local zoneFolder = Instance.new("Folder")
		zoneFolder.Name = zone.id
		zoneFolder:SetAttribute("SeatingZone", zone.id)
		zoneFolder.Parent = folder

		for i, placement in ipairs(zone.placements) do
			local model = Instance.new("Model")
			model.Name = seatDef.id .. i
			model:SetAttribute(SeatingConfig.DECORATIVE_ATTRIBUTE, true)
			model:SetAttribute("SeatType", seatDef.id)
			model:SetAttribute("SeatingZone", zone.id)

			-- Faces the map's true center (world (0, 0)), ignoring height.
			local mapCenter = Vector3.new(0, placement.position.Y, 0)
			local yaw = yawTowards(placement.position, mapCenter)
			local cframe = CFrame.new(placement.position) * CFrame.Angles(0, math.rad(yaw), 0)
			buildBench(cframe, model, seatDef)

			model.Parent = zoneFolder
			table.insert(allPositions, placement.position)
		end
	end

	return folder, allPositions
end

return Seating
