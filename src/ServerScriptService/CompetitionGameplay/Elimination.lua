--[[
	Elimination.lua

	Visual/physical elimination handling: grays out a contestant's
	platform (and restores it afterward) and moves their character out of
	the contest to the arena's spectator rim.

	SPECTATOR SEATS ARE GONE. This used to seat the player in one of the
	"SpectatorSeat"-tagged Seats built by ArenaBuilder. Those seat rings
	were deleted manually in Studio and removed from source (see
	ArenaBuilder/ArenaDecorations.lua), which left this function finding
	zero tagged seats, warning, and returning - so an eliminated player
	simply stayed standing on their contestant platform, which reads as
	not having been eliminated at all.

	It now relocates them to a STANDING spot on the same rim those seats
	used to occupy, computed from the platform ring radius plus
	ArenaConfig.SPECTATOR_RING_OFFSETS - the identical geometry, without
	depending on any seat instance existing. Nothing else about elimination
	changed, and the public function name is unchanged so every existing
	caller in CompetitionGameplay keeps working.
]]

local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaConfig = require(ServerScriptService.ArenaBuilder.ArenaConfig)
local Platforms = require(ServerScriptService.ArenaBuilder.Platforms)

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
	Moves an eliminated player off their platform to the arena's spectator
	rim - a standing position, since the spectator Seats no longer exist
	(see this file's header).

	The destination is derived the same way the seat rings were: the
	platform ring radius plus one of ArenaConfig.SPECTATOR_RING_OFFSETS, at
	an angle taken from the player's OWN platform where possible, so an
	eliminated contestant steps back from roughly where they were standing
	rather than being teleported across the arena. Falls back to a random
	angle when their platform can't be resolved.

	The character is faced back toward the arena centre, so an eliminated
	player is left looking at the QuestionScreen and the remaining contest
	rather than out at the boundary wall.
]]
function Elimination.MoveToSpectatorSeat(player: Player)
	local character = player.Character
	if not character or not character.PrimaryPart then
		return
	end

	-- The arena is built around its own local origin and then translated to
	-- ArenaConfig.ORIGIN, so the rim is measured from that same centre.
	local centre = ArenaConfig.ORIGIN

	-- Angle: reuse the player's own platform bearing when we can find it.
	-- Teleporter stamps "OccupyingUserId" on a platform when it seats a
	-- contestant there (and clears it on exit), so that is the authoritative
	-- player -> platform link.
	local angle: number? = nil
	for _, platform in ipairs(CollectionService:GetTagged("ContestantPlatform")) do
		if platform:IsA("Model") and platform:GetAttribute("OccupyingUserId") == player.UserId then
			local p = platform:GetPivot().Position - centre
			angle = math.atan2(p.X, p.Z)
			break
		end
	end
	angle = angle or (math.random() * 2 * math.pi)

	local offsets = ArenaConfig.SPECTATOR_RING_OFFSETS
	local offset = offsets[math.random(1, #offsets)]
	local radius = Platforms.ComputeRingRadius() + offset

	local spot = centre
		+ Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		+ Vector3.new(0, 4, 0) -- stand clear of the arena floor

	-- Face back toward the centre of the arena.
	character:PivotTo(CFrame.lookAt(spot, Vector3.new(centre.X, spot.Y, centre.Z)))
end

return Elimination
