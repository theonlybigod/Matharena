--[[
	Elimination.lua

	Visual/physical elimination handling: grays out a contestant's
	platform (and restores it afterward) and moves their character to an
	open spectator seat (CollectionService tag "SpectatorSeat", built in
	ArenaBuilder, Message 3).
]]

local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaConfig = require(ServerScriptService.ArenaBuilder.ArenaConfig)

local Elimination = {}

local ELIMINATED_BASE_COLOR = Color3.fromRGB(70, 70, 70)
local ELIMINATED_GLOW_COLOR = Color3.fromRGB(90, 90, 90)

local function getBaseAndGlow(platform: Model): (BasePart?, BasePart?)
	local base = platform:FindFirstChild("Base")
	local glow = platform:FindFirstChild("GlowRing")
	return (base and base:IsA("BasePart")) and base or nil, (glow and glow:IsA("BasePart")) and glow or nil
end

function Elimination.SetPlatformGray(platform: Model)
	local base, glow = getBaseAndGlow(platform)
	if base then
		base.Color = ELIMINATED_BASE_COLOR
	end
	if glow then
		glow.Color = ELIMINATED_GLOW_COLOR
		glow.Material = Enum.Material.SmoothPlastic
	end
end

function Elimination.RestorePlatformColor(platform: Model)
	local base, glow = getBaseAndGlow(platform)
	if base then
		base.Color = ArenaConfig.PLATFORM_ALIVE_COLOR
	end
	if glow then
		glow.Color = ArenaConfig.NEON_COLOR
		glow.Material = Enum.Material.Neon
	end
end

function Elimination.RestoreAllPlatformColors()
	for _, platform in ipairs(CollectionService:GetTagged("ContestantPlatform")) do
		if platform:IsA("Model") then
			Elimination.RestorePlatformColor(platform)
		end
	end
end

--[[
	Seats a player in an open spectator seat (a real Roblox Seat, so
	Seat:Sit handles positioning correctly). Falls back to teleporting
	near a random seat's position if every seat is somehow occupied or the
	character has no Humanoid.
]]
function Elimination.MoveToSpectatorSeat(player: Player)
	local seats = CollectionService:GetTagged("SpectatorSeat")
	if #seats == 0 then
		warn("[Elimination] No SpectatorSeat-tagged instances found - cannot seat eliminated player.")
		return
	end

	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	local openSeats = {}
	for _, seat in ipairs(seats) do
		if seat:IsA("Seat") and seat.Occupant == nil then
			table.insert(openSeats, seat)
		end
	end

	local chosen = (#openSeats > 0) and openSeats[math.random(1, #openSeats)] or seats[math.random(1, #seats)]

	if humanoid and chosen:IsA("Seat") then
		chosen:Sit(humanoid)
	elseif chosen:IsA("BasePart") then
		character:PivotTo(chosen.CFrame + Vector3.new(0, 3, 0))
	end
end

return Elimination
