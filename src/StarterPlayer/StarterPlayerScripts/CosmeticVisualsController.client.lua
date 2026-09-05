--[[
	CosmeticVisualsController.client.lua

	Renders the real in-world visuals for equipped cosmetics on EVERY
	character in the game (not just the local player) - the presentation
	layer CosmeticVisuals.lua/CosmeticsConfig's own doc comment said was
	missing. Driven entirely by the EquippedAccessory / EquippedTrail /
	EquippedNameColor / EquippedTitle attributes ShopSystem now replicates
	onto each Player instance (see ShopSystem.lua's pushInventoryUpdated) -
	Attributes replicate to every client automatically, including for
	characters that spawned before this local player even joined, so this
	script never needs its own remote.

	SCOPE: Accessory + Trail (genuinely "on the character") plus a new
	custom nameplate carrying NameColor + Title (there was no nameplate
	system to hook into, so this builds one, replacing the default Roblox
	nameplate so the two never show side by side). QuestionTheme and
	VictoryAnimation are NOT handled here - see CosmeticVisuals.lua's own
	"NOT YET COVERED" note.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CosmeticsConfig = require(ReplicatedStorage.Modules.CosmeticsConfig)
local CosmeticVisuals = require(ReplicatedStorage.Modules.CosmeticVisuals)

-- Per-character live state, so a rebuild only touches what actually
-- changed rather than tearing down/rebuilding everything on every
-- attribute change.
local characterState: { [Model]: any } = {}
-- Parts needing a per-frame CFrame update (floating companions, the aura
-- ring) - kept in one flat list rather than a per-character connection,
-- so there is exactly one Heartbeat connection for the whole game
-- regardless of how many players have one of these equipped.
local animatedParts: { { part: BasePart, attach: BasePart, spec: any, phase: number } } = {}

local function clearAccessory(character: Model)
	local state = characterState[character]
	if not state or not state.accessoryFolder then
		return
	end
	for i = #animatedParts, 1, -1 do
		if animatedParts[i].part:IsDescendantOf(state.accessoryFolder) then
			table.remove(animatedParts, i)
		end
	end
	state.accessoryFolder:Destroy()
	state.accessoryFolder = nil
end

local function buildAccessory(character: Model, player: Player)
	clearAccessory(character)

	local itemId = player:GetAttribute("EquippedAccessory")
	if typeof(itemId) ~= "string" then
		return
	end
	local item = CosmeticsConfig.GetItem(itemId)
	if not item or item.category ~= "Accessory" then
		return
	end
	local spec = CosmeticVisuals.BuildAccessorySpec(itemId, item.previewColor, item.rarity)
	if not spec then
		return
	end
	local attachPart = character:FindFirstChild(spec.attach)
	if not attachPart or not attachPart:IsA("BasePart") then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "MathArenaAccessory"
	folder.Parent = character

	local state = characterState[character]
	if state then
		state.accessoryFolder = folder
	end

	for i, partSpec in ipairs(spec.parts) do
		-- Shape actually matters here: a "Cylinder"/"Ball" spec must become a
		-- round part, and "Wedge" needs a real WedgePart (Roblox has no Wedge
		-- PartType - it's a distinct ClassName). Building everything as a plain
		-- block regardless of `shape` was a real bug in the first pass of this
		-- controller - every ring/lens/spike rendered as a rectangular slab.
		local part
		if partSpec.shape == "Wedge" then
			part = Instance.new("WedgePart")
		else
			part = Instance.new("Part")
			if partSpec.shape == "Ball" then
				part.Shape = Enum.PartType.Ball
			elseif partSpec.shape == "Cylinder" then
				part.Shape = Enum.PartType.Cylinder
			end
			-- "Block" needs nothing extra - Enum.PartType.Block is the default.
		end
		part.Name = "AccessoryPart" .. i
		part.Size = partSpec.size
		part.Color = partSpec.color
		part.Material = if partSpec.trim then spec.treatment.trimMaterial else spec.treatment.material
		part.CanCollide = false
		part.CanQuery = false
		part.Massless = true
		part.CFrame = attachPart.CFrame * partSpec.offset
		part.Parent = folder

		if partSpec.trim and spec.treatment.lightBrightness > 0 then
			local light = Instance.new("PointLight")
			light.Color = partSpec.color
			light.Range = 6
			light.Brightness = spec.treatment.lightBrightness
			light.Parent = part
		end

		if partSpec.sparkleAnchor and spec.treatment.sparkle then
			-- One sparkle emitter per accessory (only on the designated
			-- anchor part), for Legendary/Boundless only - a small persistent
			-- shimmer rather than a heavy particle storm.
			local sparkle = Instance.new("ParticleEmitter")
			sparkle.Color = ColorSequence.new(partSpec.color)
			sparkle.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.08),
				NumberSequenceKeypoint.new(1, 0),
			})
			sparkle.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			})
			sparkle.Lifetime = NumberRange.new(0.6, 1)
			sparkle.Rate = 6
			sparkle.Speed = NumberRange.new(0.2, 0.5)
			sparkle.SpreadAngle = Vector2.new(180, 180)
			sparkle.Parent = part
		end

		if partSpec.floaty or partSpec.orbits then
			-- Independently animated (bob/orbit) rather than rigidly welded -
			-- updated once per frame by the single shared Heartbeat loop
			-- below, positioned relative to the attach part's CURRENT CFrame
			-- so it still follows the character around.
			table.insert(animatedParts, { part = part, attach = attachPart, spec = partSpec, phase = i })
		else
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = attachPart
			weld.Part1 = part
			weld.Parent = part
		end
	end
end

-- ===== Trail =====

local function ensureTrailRig(character: Model): (Trail?, Attachment?, Attachment?)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	local existing = root:FindFirstChild("MathArenaTrail")
	if existing and existing:IsA("Trail") then
		return existing, existing.Attachment0, existing.Attachment1
	end

	local a0 = Instance.new("Attachment")
	a0.Name = "MathArenaTrailA0"
	a0.Position = Vector3.new(0, 1, 0.6)
	a0.Parent = root

	local a1 = Instance.new("Attachment")
	a1.Name = "MathArenaTrailA1"
	a1.Position = Vector3.new(0, -1, 0.6)
	a1.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = "MathArenaTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Enabled = false
	trail.Parent = root
	return trail, a0, a1
end

local function buildTrail(character: Model, player: Player)
	local trail = ensureTrailRig(character)
	if not trail then
		return
	end

	local itemId = player:GetAttribute("EquippedTrail")
	local item = typeof(itemId) == "string" and CosmeticsConfig.GetItem(itemId)
	if not item or item.category ~= "Trail" then
		trail.Enabled = false
		return
	end

	local params = CosmeticVisuals.GetTrailParams(item.rarity)
	trail.Enabled = true
	trail.Color = ColorSequence.new(item.previewColor)
	trail.Lifetime = params.lifetime
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, params.minTransparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- Attachment SEPARATION (not the Trail's own width property, which
	-- doesn't exist - Trail width is entirely a function of how far apart
	-- Attachment0/Attachment1 are) scales with rarity so a Boundless trail
	-- reads as a genuinely wider ribbon than a Common one.
	local root = character:FindFirstChild("HumanoidRootPart")
	local a0 = root and root:FindFirstChild("MathArenaTrailA0")
	local a1 = root and root:FindFirstChild("MathArenaTrailA1")
	if a0 and a1 then
		a0.Position = Vector3.new(0, params.width / 2, 0.6)
		a1.Position = Vector3.new(0, -params.width / 2, 0.6)
	end
end

-- ===== Nameplate (NameColor + Title) =====

-- Strips the surrounding quote marks CosmeticsConfig's Title displayNames
-- carry (e.g. '"Grandmaster"') down to the plain word ("Grandmaster") for
-- display under the name, rather than showing the literal quote marks in
-- the 3D nameplate.
local function titleText(displayName: string): string
	return (displayName:gsub('^"(.*)"$', "%1"))
end

local function buildNameplate(character: Model, player: Player)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Hide the default Roblox nameplate so ours is the only one shown -
		-- otherwise the two would render stacked on top of each other.
		humanoid.NameDisplayDistance = 0
	end

	local gui = head:FindFirstChild("MathArenaNameplate")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "MathArenaNameplate"
		gui.Adornee = head
		-- IMPORTANT: for a BillboardGui, UDim2 Offset is measured in STUDS, not
		-- pixels - the first version of this used (200, 50), producing a
		-- genuinely 200-stud-wide sign (dwarfing the character completely,
		-- and rendering as a huge blank plane or a thin edge-on sliver
		-- depending on viewing distance/angle). (5, 1.4) is sized in actual
		-- studs - a small, ordinary-looking nameplate.
		gui.Size = UDim2.fromOffset(5, 1.4)
		gui.StudsOffset = Vector3.new(0, 1.1, 0)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 60
		gui.Parent = head

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.Size = UDim2.new(1, 0, 0.65, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.TextStrokeTransparency = 0.4
		nameLabel.Text = player.DisplayName
		nameLabel.Parent = gui

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "TitleLabel"
		titleLabel.Size = UDim2.new(1, 0, 0.35, 0)
		titleLabel.Position = UDim2.new(0, 0, 0.65, 0)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Font = Enum.Font.GothamMedium
		titleLabel.TextScaled = true
		titleLabel.TextStrokeTransparency = 0.5
		titleLabel.TextColor3 = Color3.fromRGB(255, 215, 120)
		titleLabel.Text = ""
		titleLabel.Visible = false
		titleLabel.Parent = gui
	end

	local nameLabel = gui.NameLabel :: TextLabel
	local titleLabel = gui.TitleLabel :: TextLabel

	local colorItemId = player:GetAttribute("EquippedNameColor")
	local colorItem = typeof(colorItemId) == "string" and CosmeticsConfig.GetItem(colorItemId)
	nameLabel.TextColor3 = if colorItem and colorItem.category == "NameColor"
		then colorItem.previewColor
		else Color3.new(1, 1, 1)

	local titleItemId = player:GetAttribute("EquippedTitle")
	local titleItem = typeof(titleItemId) == "string" and CosmeticsConfig.GetItem(titleItemId)
	if titleItem and titleItem.category == "Title" then
		titleLabel.Text = titleText(titleItem.displayName)
		titleLabel.Visible = true
	else
		titleLabel.Text = ""
		titleLabel.Visible = false
	end
end

-- ===== Per-character wiring =====

local function refreshAll(character: Model, player: Player)
	buildAccessory(character, player)
	buildTrail(character, player)
	buildNameplate(character, player)
end

local function onCharacterAdded(player: Player, character: Model)
	characterState[character] = {}
	-- Character parts (Head/UpperTorso/HumanoidRootPart) can still be
	-- streaming in at spawn - a short bounded wait, same pattern used
	-- elsewhere in this codebase (CharacterPreviewBuilder), rather than
	-- silently building against parts that don't exist yet.
	task.spawn(function()
		for _ = 1, 100 do
			if character:FindFirstChild("HumanoidRootPart") and character:FindFirstChild("Head") then
				break
			end
			RunService.Heartbeat:Wait()
		end
		if character.Parent then
			refreshAll(character, player)
		end
	end)
end

local function onCharacterRemoving(character: Model)
	clearAccessory(character)
	characterState[character] = nil
end

local function watchPlayer(player: Player)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	player.CharacterRemoving:Connect(onCharacterRemoving)

	-- Live-react to any equip change, for every category, on whichever
	-- character this player currently has.
	for _, attributeName in ipairs({ "EquippedAccessory", "EquippedTrail", "EquippedNameColor", "EquippedTitle" }) do
		player:GetAttributeChangedSignal(attributeName):Connect(function()
			local character = player.Character
			if not character then
				return
			end
			if attributeName == "EquippedAccessory" then
				buildAccessory(character, player)
			elseif attributeName == "EquippedTrail" then
				buildTrail(character, player)
			else
				buildNameplate(character, player)
			end
		end)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)

-- Single shared Heartbeat for every "floaty"/"orbits" accessory part in
-- the whole game (see buildAccessory above) - cheap even with several
-- players wearing one, since it's just a CFrame write per part per frame.
RunService.Heartbeat:Connect(function(dt)
	for i = #animatedParts, 1, -1 do
		local entry = animatedParts[i]
		if not entry.part.Parent or not entry.attach.Parent then
			table.remove(animatedParts, i)
			continue
		end
		entry.phase += dt
		local attachCFrame = entry.attach.CFrame
		if entry.spec.floaty then
			local bob = math.sin(entry.phase * 2) * 0.15
			entry.part.CFrame = attachCFrame * entry.spec.offset * CFrame.new(0, bob, 0)
		elseif entry.spec.orbits then
			local angle = entry.phase * 1.2
			entry.part.CFrame = attachCFrame * CFrame.Angles(0, angle, 0) * entry.spec.offset
		end
	end
end)
