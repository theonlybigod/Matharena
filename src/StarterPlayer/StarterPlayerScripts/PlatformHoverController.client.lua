--[[
	PlatformHoverController.client.lua

	Hover-only player name/rank display pass: ArenaBuilder/Platforms.lua
	builds each contestant platform's "NameDisplay"/"RankDisplay"
	BillboardGuis hidden by default (Enabled = false) instead of always
	visible, per explicit direction that the constantly-visible "Player #"
	/ rank text was "too distracting and gets in the way of the MATHARENA
	screen". This script is what actually shows them again - but only
	while the local player's mouse is hovering that specific PLAYER'S
	CHARACTER (not just the platform/empty floor near them).

	Hover detection lives on the character itself: MatchSystem/
	Teleporter.lua adds a "HoverDetector" ClickDetector to every BasePart
	of a player's character when they're assigned a platform (tagged
	"HoverableCharacter", with a "PlatformIndex" attribute pointing at
	which platform's displays to control), and removes them again when
	the player returns to the lobby. This script just listens for those
	events and shows/hides the matching platform's displays - it never
	builds or owns any hover-detection instances itself.

	Client-only, purely visual: this never touches the actual name/rank
	TEXT (that's still written server-side by MatchSystem/Teleporter.lua,
	completely unchanged) or sends anything to the server - a
	ClickDetector's hover events fire locally, per-observing-client, which
	is exactly the right shape for "the client only controls the visual
	hover presentation" while "the server remains authoritative for
	player rank/data". Every player hovering independently sees only what
	THEY are pointing at; nothing is broadcast to other clients.
]]

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local FADE_TIME = 0.12
local HOVERABLE_TAG = "HoverableCharacter"

local function fadeIn(billboard: BillboardGui)
	billboard.Enabled = true
	local label = billboard:FindFirstChildWhichIsA("TextLabel")
	if not label then
		return
	end
	label.TextTransparency = 1
	TweenService:Create(label, TweenInfo.new(FADE_TIME), { TextTransparency = 0 }):Play()
end

local function fadeOut(billboard: BillboardGui)
	local label = billboard:FindFirstChildWhichIsA("TextLabel")
	if not label then
		billboard.Enabled = false
		return
	end
	local tween = TweenService:Create(label, TweenInfo.new(FADE_TIME), { TextTransparency = 1 })
	tween.Completed:Connect(function()
		-- Only actually hide once fully faded, and only if nothing
		-- re-triggered a hover in the meantime (fresh fade-in would have
		-- already set TextTransparency back toward 0, so a stale
		-- "finished fading out" tween won't clobber a genuine re-hover).
		if label.TextTransparency >= 1 then
			billboard.Enabled = false
		end
	end)
	tween:Play()
end

--[[
	Finds the platform whose PlatformIndex attribute matches the
	character's - reuses the existing "ContestantPlatform" tag/
	PlatformIndex discovery contract rather than hardcoding paths.
]]
local function findPlatformByIndex(platformIndex: number): Model?
	for _, platform in ipairs(CollectionService:GetTagged("ContestantPlatform")) do
		if platform:GetAttribute("PlatformIndex") == platformIndex then
			return platform
		end
	end
	return nil
end

local function showDisplaysFor(character: Model)
	local platformIndex = character:GetAttribute("PlatformIndex")
	local platform = platformIndex and findPlatformByIndex(platformIndex)
	if not platform then
		return
	end

	local nameDisplay = platform:FindFirstChild("NameDisplay") :: BillboardGui?
	local rankDisplay = platform:FindFirstChild("RankDisplay") :: BillboardGui?
	if nameDisplay then
		fadeIn(nameDisplay)
	end
	if rankDisplay then
		fadeIn(rankDisplay)
	end
end

local function hideDisplaysFor(character: Model)
	local platformIndex = character:GetAttribute("PlatformIndex")
	local platform = platformIndex and findPlatformByIndex(platformIndex)
	if not platform then
		return
	end

	local nameDisplay = platform:FindFirstChild("NameDisplay") :: BillboardGui?
	local rankDisplay = platform:FindFirstChild("RankDisplay") :: BillboardGui?
	if nameDisplay then
		fadeOut(nameDisplay)
	end
	if rankDisplay then
		fadeOut(rankDisplay)
	end
end

local wiredDetectors = {} :: { [ClickDetector]: boolean }

local function wireDetector(detector: ClickDetector, character: Model)
	if wiredDetectors[detector] then
		return
	end
	wiredDetectors[detector] = true

	detector.MouseHoverEnter:Connect(function()
		showDisplaysFor(character)
	end)
	detector.MouseHoverLeave:Connect(function()
		hideDisplaysFor(character)
	end)
end

local function wireCharacter(character: Model)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("ClickDetector") and descendant.Name == "HoverDetector" then
			wireDetector(descendant, character)
		end
	end

	-- Teleporter.lua adds HoverDetectors to parts that already exist at
	-- the moment a player is assigned a platform, but wire up any added
	-- afterward too (defensive - covers any future ordering changes).
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ClickDetector") and descendant.Name == "HoverDetector" then
			wireDetector(descendant, character)
		end
	end)
end

for _, character in ipairs(CollectionService:GetTagged(HOVERABLE_TAG)) do
	wireCharacter(character)
end

CollectionService:GetInstanceAddedSignal(HOVERABLE_TAG):Connect(wireCharacter)
