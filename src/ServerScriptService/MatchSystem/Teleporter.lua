--[[
	Teleporter.lua

	Moves players between the lobby's spawn locations and the arena's
	contestant platforms, and keeps each platform's NameDisplay/RankDisplay
	fixtures (built in ArenaBuilder, Message 3) in sync with who occupies
	them. Finds platforms via the "ContestantPlatform" CollectionService
	tag and lobby spawns via Workspace.Lobby.Spawns — no hardcoded instance
	paths beyond those two well-known containers.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local DataSystem = require(ServerScriptService.DataSystem)

local Teleporter = {}

local function getSortedPlatforms(): { Model }
	local tagged = CollectionService:GetTagged("ContestantPlatform")
	table.sort(tagged, function(a, b)
		return (a:GetAttribute("PlatformIndex") or 0) < (b:GetAttribute("PlatformIndex") or 0)
	end)
	return tagged
end

local function setDisplayText(platform: Model, displayName: string, labelName: string, text: string)
	local display = platform:FindFirstChild(displayName)
	if not display then
		return
	end

	local label = display:FindFirstChild(labelName)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

--[[
	Teleports each player onto their own contestant platform (in list
	order -> platform index order) and updates that platform's name/rank
	display. Returns a { [Player]: Model } map of who's on which platform.
]]
function Teleporter.AssignPlatforms(players: { Player }): { [Player]: Model }
	local platforms = getSortedPlatforms()
	local assignments: { [Player]: Model } = {}

	for i, player in ipairs(players) do
		local platform = platforms[i]
		if not platform then
			warn(
				("[Teleporter] No platform available for %s (index %d exceeds %d available platforms)."):format(
					player.Name,
					i,
					#platforms
				)
			)
			continue
		end

		local character = player.Character or player.CharacterAdded:Wait()
		local base = platform:FindFirstChild("Base") :: BasePart?
		if base then
			character:PivotTo(CFrame.new(base.Position + Vector3.new(0, 6, 0)))
		end

		local profile = DataSystem.GetProfile(player)
		setDisplayText(platform, "NameDisplay", "NameLabel", player.Name)
		setDisplayText(platform, "RankDisplay", "RankLabel", profile and profile.rank or "Unranked")

		platform:SetAttribute("OccupyingUserId", player.UserId)
		assignments[player] = platform
	end

	return assignments
end

--[[
	Teleports players back to the lobby's spawn locations, round-robin
	across however many spawns exist.
]]
function Teleporter.ReturnToLobby(players: { Player })
	local lobby = Workspace:FindFirstChild("Lobby")
	local spawnsFolder = lobby and lobby:FindFirstChild("Spawns")
	local spawnParts = spawnsFolder and spawnsFolder:GetChildren() or {}

	if #spawnParts == 0 then
		warn("[Teleporter] No lobby spawn locations found - cannot return players to the lobby.")
		return
	end

	for i, player in ipairs(players) do
		local character = player.Character
		if character then
			local spawnPart = spawnParts[((i - 1) % #spawnParts) + 1] :: BasePart
			character:PivotTo(spawnPart.CFrame + Vector3.new(0, 3, 0))
		end
	end
end

--[[
	Resets a single platform's display fixtures back to their defaults and
	clears its occupancy attribute.
]]
function Teleporter.ClearPlatform(platform: Model)
	local index = platform:GetAttribute("PlatformIndex")
	setDisplayText(platform, "NameDisplay", "NameLabel", "Player " .. tostring(index or "-"))
	setDisplayText(platform, "RankDisplay", "RankLabel", "Rank -")
	platform:SetAttribute("OccupyingUserId", nil)
end

function Teleporter.ClearAllPlatforms()
	for _, platform in ipairs(getSortedPlatforms()) do
		Teleporter.ClearPlatform(platform)
	end
end

return Teleporter
