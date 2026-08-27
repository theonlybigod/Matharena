--[[
	Teleporter.lua

	Moves players between the lobby's spawn locations and the arena's
	contestant platforms, and keeps each platform's NameDisplay/RankDisplay
	fixtures (built in ArenaBuilder, Message 3) in sync with who occupies
	them. Finds platforms via the "ContestantPlatform" CollectionService
	tag and lobby spawns via Workspace.Lobby.Spawns — no hardcoded instance
	paths beyond those two well-known containers.

	Hover-only name/rank display pass: hover detection lives on the PLAYER
	CHARACTER itself (not the platform), so mousing over a player's
	character specifically is what shows their name/rank - not just mousing
	over empty platform floor near them. A ClickDetector is added to every
	BasePart of the character when they're assigned a platform (so hovering
	any visible part of their body - torso, limbs, head - triggers it, not
	just one narrow hitbox), tagged "HoverableCharacter" with a
	"PlatformIndex" attribute so PlatformHoverController.client.lua
	(StarterPlayerScripts) can find the matching platform's displays.
	Removed again in ReturnToLobby, since a returning character is the same
	instance (not respawned), so stale detectors would otherwise keep
	pointing at a platform that's no longer occupied.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataSystem = require(ServerScriptService.DataSystem)
local DifficultyPlacesConfig = require(ReplicatedStorage.Modules.DifficultyPlacesConfig)
local MapsConfig = require(ReplicatedStorage.Modules.MapsConfig)

local Teleporter = {}

local HOVERABLE_TAG = "HoverableCharacter"

--[[
	Which Workspace folder ReturnToLobby below should send players back to.
	On a dedicated difficulty Place (DifficultyPlacesConfig.GetPlaceForPlaceId
	returns non-nil), that's the one map this Place actually builds -
	"Lobby" (Futuristic's folder name) doesn't exist there at all, since
	Main.server.lua only ever builds that Place's one assigned map. On the
	Hub (nil - the Hub isn't one of the five difficulty Places), this stays
	"Lobby" exactly as before this multi-Place system existed - the Hub
	always builds every map, but Futuristic/"Lobby" remains the one every
	other Hub-only system (spawns, queue portal, etc.) treats as home.
	Computed once at server start, same pattern as
	PlaceTeleportSystem's own module-level `myPlace`.
]]
local function getLobbyFolderName(): string
	local assignedPlace = DifficultyPlacesConfig.GetPlaceForPlaceId(game.PlaceId)
	if assignedPlace then
		local mapDef = MapsConfig.GetMap(assignedPlace.mapId)
		if mapDef then
			return mapDef.workspaceFolderName
		end
	end
	return "Lobby"
end

local LOBBY_FOLDER_NAME = getLobbyFolderName()

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
	Adds a "HoverDetector" ClickDetector to every BasePart of `character`
	(so hovering any visible part of their body triggers it, not just one
	narrow hitbox), tags the character itself for discovery, and stamps the
	platform's index so the client can look up which displays to show.
]]
local function attachHoverDetectors(character: Model, platformIndex: number)
	CollectionService:AddTag(character, HOVERABLE_TAG)
	character:SetAttribute("PlatformIndex", platformIndex)

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local detector = Instance.new("ClickDetector")
			detector.Name = "HoverDetector"
			detector.MaxActivationDistance = 100
			detector.Parent = descendant
		end
	end
end

--[[
	Removes every HoverDetector added above, and the tag/attribute, so a
	character returning to the lobby doesn't keep triggering a platform's
	displays it no longer occupies.
]]
local function removeHoverDetectors(character: Model)
	if not CollectionService:HasTag(character, HOVERABLE_TAG) then
		return
	end

	CollectionService:RemoveTag(character, HOVERABLE_TAG)
	character:SetAttribute("PlatformIndex", nil)

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local detector = descendant:FindFirstChild("HoverDetector")
			if detector then
				detector:Destroy()
			end
		end
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

		attachHoverDetectors(character, platform:GetAttribute("PlatformIndex"))

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
	local lobby = Workspace:FindFirstChild(LOBBY_FOLDER_NAME)
	local spawnsFolder = lobby and lobby:FindFirstChild("Spawns")
	local spawnParts = spawnsFolder and spawnsFolder:GetChildren() or {}

	if #spawnParts == 0 then
		warn("[Teleporter] No lobby spawn locations found - cannot return players to the lobby.")
		return
	end

	for i, player in ipairs(players) do
		local character = player.Character
		if character then
			removeHoverDetectors(character)
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
