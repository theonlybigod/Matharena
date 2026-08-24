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

	Real interactive Seats (not just decorative): the seat surface is built
	from TWO real Roblox Seat instances side by side - "SeatLeft" and
	"SeatRight" - not a plain Part, and not a single wide Seat either. A
	single Seat instance only ever holds one occupant regardless of its
	size, so a bench meant to seat two people at once needs two separate
	Seat instances; "account for the actual Seat orientation" in the
	design brief only makes sense for a genuine Seat, and a plain
	decorative Part can't be sat on at all, so there was nothing to verify
	facing direction against before. A Roblox Seat's occupant faces the
	seat part's own Front direction (local -Z, i.e. its CFrame's LookVector).
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
	Latches `theme` for every subsequent Seating.BuildAll call - delegates
	to SeatingConfig.SetTheme since every color/material this module uses
	comes from `def` (SeatingConfig.SEAT_TYPE), read live, not copied into
	its own local constants.
]]
function Seating.SetTheme(theme)
	SeatingConfig.SetTheme(theme)
end

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

	-- Message 30 ("flat bench, no laser in the middle, seat two people -
	-- one on the left, one on the right"): this used to be ONE Seat
	-- instance spanning the bench's full width - visually a two-person
	-- bench, but a Roblox Seat only ever holds a single occupant no matter
	-- how wide it's built, so only one player could actually sit at a
	-- time, and the seat surface had a raised Neon "SeatSpineTrim" strip
	-- running down its exact center (the "laser in the middle" - a thin
	-- glowing bar bisecting the seat). Both are fixed here: SeatSpineTrim
	-- is removed entirely (not hidden), and the single Seat is replaced by
	-- TWO separate, side-by-side Seat instances - SeatLeft and SeatRight -
	-- each sized to one half of the bench (minus a small gap between them
	-- so they read as two distinct seats on one flat surface, not a
	-- divider down the middle), so two players can sit at once, one on
	-- each half, with nothing raised between them.
	local seatGap = 0.3
	local seatWidth = (def.seatSize.X - seatGap) / 2
	local seatXOffset = (seatWidth + seatGap) / 2
	for _, side in ipairs({ { name = "SeatLeft", sign = -1 }, { name = "SeatRight", sign = 1 } }) do
		PartUtils.CreatePart({
			className = "Seat",
			name = side.name,
			size = Vector3.new(seatWidth, def.seatSize.Y, def.seatSize.Z),
			cframe = cframe * CFrame.new(side.sign * seatXOffset, seatY, 0),
			material = def.seatMaterial,
			color = def.seatColor,
			parent = model,
		})
	end

	for _, side in ipairs({ -1, 1 }) do
		PartUtils.CreatePart({
			name = "Leg",
			size = Vector3.new(legWidth, legHeight, def.seatSize.Z - 0.2),
			cframe = cframe * CFrame.new(side * (def.seatSize.X / 2 - 0.6), legHeight / 2, 0),
			material = def.frameMaterial,
			color = def.frameColor,
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
		material = def.frameMaterial,
		color = def.frameColor,
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
			material = def.frameMaterial,
			color = def.frameColor,
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
