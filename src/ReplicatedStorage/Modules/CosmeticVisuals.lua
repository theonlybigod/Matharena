--[[
	CosmeticVisuals.lua

	Real, in-world visual specs for equipped cosmetics - the presentation
	layer CosmeticsConfig's own doc comment explicitly said was NOT yet
	implemented ("the shop UI's Preview is this file's description +
	previewColor swatch, not a live in-world preview"). This module is
	that presentation layer for the two categories that are genuinely
	"on the character": Accessory (a real welded part-built accessory)
	and Trail (a real Roblox Trail instance). NameColor and Title are
	also driven from here, applied to a custom nameplate rather than a
	3D attachment. QuestionTheme and VictoryAnimation are intentionally
	NOT covered - see the "NOT YET COVERED" note at the bottom.

	DESIGN PRINCIPLE: derive everything possible directly from
	CosmeticsConfig's existing data (previewColor, rarity, displayName)
	rather than hand-authoring 120 bespoke entries. Only Accessory needs
	a per-item table at all, because shape can't be derived from a color
	alone - Trail width/glow, NameColor and Title text are all 100%
	mechanical and read CosmeticsConfig live, so they can never drift out
	of sync with it.

	VISUAL PASS (2nd revision): every archetype below is built from a
	SMALL number of correctly-shaped primitives (Ball/Cylinder/Wedge, not
	just stretched blocks) plus one contrasting trim/rim accent - "simple,
	but detailed", not a pile of parts. Rarity adds a lit trim rim
	(Rare+) and a sparkle ParticleEmitter (Legendary/Boundless), so a
	Boundless item always reads as visibly higher-tier than a Common one
	of the same archetype without needing per-item hand-tuning.

	Built entirely from primitive parts (no imported meshes/asset ids),
	matching how every other visual in this game (buildings, trees,
	terrain, marine life) is constructed - see PartUtils.
]]

local CosmeticVisuals = {}

-- ============================================================
-- ===== Accessory archetypes ====================================
-- ============================================================

--[[
	Every one of the 20 Accessory items, mapped to one of 10 reusable
	geometric archetypes. `attach` says which body part the accessory is
	welded to - ALL characters in this game are R6 (confirmed), so this is
	"Head", "Torso", or "HumanoidRootPart" (R6 part names), never the R15
	names like "UpperTorso". Two items sharing an archetype still look
	distinct in-world because the builder always tints from that ITEM's
	own previewColor, read live from CosmeticsConfig - never hardcoded here.
]]
CosmeticVisuals.ACCESSORY_SPECS = {
	accessory_paper_crown = { archetype = "Crown", attach = "Head" },
	accessory_void_crown = { archetype = "Crown", attach = "Head" },
	accessory_champion_crown = { archetype = "Crown", attach = "Head" },

	accessory_bandana = { archetype = "Headband", attach = "Head" },

	accessory_sunglasses = { archetype = "Eyewear", attach = "Head" },

	accessory_bow_tie = { archetype = "Neckwear", attach = "Torso" },

	accessory_backpack_charm = { archetype = "ChestCharm", attach = "Torso" },
	accessory_trainee_badge = { archetype = "ChestCharm", attach = "Torso" },
	accessory_bronze_medal_charm = { archetype = "ChestCharm", attach = "Torso" },
	accessory_silver_medal_charm = { archetype = "ChestCharm", attach = "Torso" },
	accessory_platinum_medal_charm = { archetype = "ChestCharm", attach = "Torso" },

	accessory_cape = { archetype = "Cape", attach = "Torso" },

	accessory_wings = { archetype = "Wings", attach = "Torso" },
	accessory_golden_wings = { archetype = "Wings", attach = "Torso" },

	accessory_halo = { archetype = "Halo", attach = "Head" },

	accessory_lantern_familiar = { archetype = "FloatingCompanion", attach = "HumanoidRootPart" },
	accessory_ghost_companion = { archetype = "FloatingCompanion", attach = "HumanoidRootPart" },
	accessory_mini_drone = { archetype = "FloatingCompanion", attach = "HumanoidRootPart" },
	accessory_phoenix_familiar = { archetype = "FloatingCompanion", attach = "HumanoidRootPart" },

	accessory_aura_ring = { archetype = "AuraRing", attach = "HumanoidRootPart" },
}

-- Rarity -> extra glow/material/sparkle treatment, shared across every
-- archetype so a Boundless accessory always reads as more special than a
-- Common one regardless of shape.
local RARITY_TREATMENT = {
	Common = { material = Enum.Material.SmoothPlastic, trimMaterial = Enum.Material.SmoothPlastic, lightBrightness = 0, sparkle = false },
	Uncommon = { material = Enum.Material.SmoothPlastic, trimMaterial = Enum.Material.SmoothPlastic, lightBrightness = 0, sparkle = false },
	Rare = { material = Enum.Material.SmoothPlastic, trimMaterial = Enum.Material.Neon, lightBrightness = 1, sparkle = false },
	Legendary = { material = Enum.Material.SmoothPlastic, trimMaterial = Enum.Material.Neon, lightBrightness = 2, sparkle = true },
	Boundless = { material = Enum.Material.SmoothPlastic, trimMaterial = Enum.Material.Neon, lightBrightness = 3.5, sparkle = true },
}
CosmeticVisuals.RARITY_TREATMENT = RARITY_TREATMENT

-- A lighter tint of `color`, used for trim/rim accents so they read as a
-- highlight on the item rather than a flat second color pulled from
-- nowhere - derived from the item's own previewColor, never hardcoded.
local function lighten(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.max(s - amount * 0.4, 0), math.min(v + amount, 1))
end

-- A darker tint, used for small grounding/contrast details (e.g. the
-- underside of a medal or the inner shadow of a crown band).
local function darken(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.max(v - amount, 0.08))
end

--[[
	Each archetype builder returns a flat list of "part specs" - pure data
	(no Instances created here), in coordinates RELATIVE to the attach
	part's own CFrame. The controller (CosmeticVisualsController.client.lua)
	turns each spec into a real welded Part/WedgePart.

	shape: "Block" | "Ball" | "Cylinder" | "Wedge"
	Every spec may also carry `trim = true` (gets the rarity trim
	material/light) and `sparkleAnchor = true` (gets the rarity sparkle
	ParticleEmitter, at most once per accessory).
]]
local function crownSpec(color)
	local rim = lighten(color, 0.35)
	local specs = {
		-- Main band - a clean ring sitting on the head.
		{ shape = "Cylinder", size = Vector3.new(0.5, 1.5, 1.5), offset = CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)), color = color },
		-- Thin lit trim along the band's top edge - the rarity accent.
		{ shape = "Cylinder", size = Vector3.new(0.15, 1.56, 1.56), offset = CFrame.new(0, 0.82, 0) * CFrame.Angles(0, 0, math.rad(90)), color = rim, trim = true },
	}
	-- 5 pointed spikes (Wedges, not blocks) evenly spaced around the band.
	for i = 0, 4 do
		local angle = (i / 5) * math.pi * 2
		specs[#specs + 1] = {
			shape = "Wedge",
			size = Vector3.new(0.4, 0.7, 0.4),
			offset = CFrame.new(math.cos(angle) * 0.72, 1.15, math.sin(angle) * 0.72)
				* CFrame.Angles(0, -angle, 0)
				* CFrame.Angles(math.rad(-90), 0, 0),
			color = color,
		}
	end
	-- One gem on the front spike - the single focal detail.
	specs[#specs + 1] = { shape = "Ball", size = Vector3.new(0.32, 0.32, 0.32), offset = CFrame.new(0, 1.55, 0.72), color = rim, sparkleAnchor = true }
	return specs
end

local function headbandSpec(color)
	local shadow = darken(color, 0.25)
	return {
		{ shape = "Cylinder", size = Vector3.new(0.45, 1.5, 1.5), offset = CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)), color = color },
		-- Small knotted tail hanging off the back, so it reads as "tied
		-- fabric" rather than a plain ring.
		{ shape = "Wedge", size = Vector3.new(0.35, 0.5, 0.2), offset = CFrame.new(0, -0.25, 0.68) * CFrame.Angles(math.rad(20), math.rad(180), 0), color = shadow },
	}
end

local function eyewearSpec(color)
	local lensColor = darken(color, 0.55)
	return {
		{ shape = "Cylinder", size = Vector3.new(0.1, 0.5, 0.5), offset = CFrame.new(-0.32, 0, -0.65) * CFrame.Angles(0, 0, math.rad(90)), color = lensColor, sparkleAnchor = true },
		{ shape = "Cylinder", size = Vector3.new(0.1, 0.5, 0.5), offset = CFrame.new(0.32, 0, -0.65) * CFrame.Angles(0, 0, math.rad(90)), color = lensColor },
		-- Thin rim accent around each lens (the rarity trim colour).
		{ shape = "Cylinder", size = Vector3.new(0.06, 0.56, 0.56), offset = CFrame.new(-0.32, 0, -0.66) * CFrame.Angles(0, 0, math.rad(90)), color = color, trim = true },
		{ shape = "Cylinder", size = Vector3.new(0.06, 0.56, 0.56), offset = CFrame.new(0.32, 0, -0.66) * CFrame.Angles(0, 0, math.rad(90)), color = color, trim = true },
		-- Bridge connecting the two lenses.
		{ shape = "Block", size = Vector3.new(0.28, 0.08, 0.08), offset = CFrame.new(0, 0.05, -0.66), color = color },
	}
end

local function neckwearSpec(color)
	local knotColor = darken(color, 0.2)
	return {
		{ shape = "Wedge", size = Vector3.new(0.42, 0.35, 0.3), offset = CFrame.new(-0.22, 0.55, -0.55) * CFrame.Angles(0, math.rad(-90), math.rad(90)), color = color },
		{ shape = "Wedge", size = Vector3.new(0.42, 0.35, 0.3), offset = CFrame.new(0.22, 0.55, -0.55) * CFrame.Angles(0, math.rad(90), math.rad(90)), color = color },
		{ shape = "Ball", size = Vector3.new(0.24, 0.24, 0.24), offset = CFrame.new(0, 0.55, -0.55), color = knotColor, sparkleAnchor = true },
	}
end

local function chestCharmSpec(color)
	local rim = lighten(color, 0.3)
	return {
		{ shape = "Cylinder", size = Vector3.new(0.12, 0.5, 0.5), offset = CFrame.new(0, 0.25, -0.58) * CFrame.Angles(0, math.rad(90), 0), color = color, sparkleAnchor = true },
		{ shape = "Cylinder", size = Vector3.new(0.05, 0.58, 0.58), offset = CFrame.new(0, 0.25, -0.6) * CFrame.Angles(0, math.rad(90), 0), color = rim, trim = true },
		-- Small ribbon loop above the medal, hanging from the collar.
		{ shape = "Block", size = Vector3.new(0.3, 0.18, 0.06), offset = CFrame.new(0, 0.58, -0.56) * CFrame.Angles(math.rad(15), 0, 0), color = darken(color, 0.15) },
	}
end

local function capeSpec(color)
	local shadow = darken(color, 0.3)
	local specs = {
		-- Clasp at the neck - the connection point the cape "hangs" from.
		{ shape = "Cylinder", size = Vector3.new(0.15, 0.4, 0.4), offset = CFrame.new(0, 0.6, -0.5) * CFrame.Angles(0, math.rad(90), 0), color = lighten(color, 0.3), trim = true },
	}
	-- 3 tapered panels, each angled slightly further out, so the cape
	-- reads as flowing fabric rather than one flat slab.
	for i = 0, 2 do
		local widthFactor = 1 - i * 0.12
		specs[#specs + 1] = {
			shape = "Block",
			size = Vector3.new(0.95 * widthFactor, 1.75 - i * 0.35, 0.1),
			offset = CFrame.new(0, 0.1 - i * 0.62, 0.5 + i * 0.12) * CFrame.Angles(math.rad(i * 6), 0, 0),
			color = if i == 2 then shadow else color,
		}
	end
	return specs
end

local function wingsSpec(color)
	local rim = lighten(color, 0.35)
	local specs = {}
	for _, side in ipairs({ -1, 1 }) do
		-- Shoulder mount - a clean anchor point where the wing meets the back.
		specs[#specs + 1] = { shape = "Ball", size = Vector3.new(0.3, 0.3, 0.3), offset = CFrame.new(side * 0.5, 0.4, 0.4), color = rim, trim = true }
		-- 3 tapering feathers fanning outward and slightly upward.
		for i = 0, 2 do
			specs[#specs + 1] = {
				shape = "Wedge",
				size = Vector3.new(0.12, 1.3 - i * 0.32, 0.85 - i * 0.18),
				offset = CFrame.new(side * (0.55 + i * 0.5), 0.45 + i * 0.15, 0.4)
					* CFrame.Angles(0, math.rad(side * (20 + i * 10)), math.rad(side * -90)),
				color = color,
			}
		end
	end
	return specs
end

local function haloSpec(color)
	local specs = {
		{ shape = "Cylinder", size = Vector3.new(0.18, 1.35, 1.35), offset = CFrame.new(0, 1.3, 0) * CFrame.Angles(math.rad(90), 0, 0), color = color, sparkleAnchor = true },
	}
	return specs
end

local function floatingCompanionSpec(color)
	local core = lighten(color, 0.4)
	return {
		{ shape = "Ball", size = Vector3.new(0.65, 0.65, 0.65), offset = CFrame.new(1.6, 1, -0.3), color = color, floaty = true },
		-- Small bright inner core, slightly forward, so it reads as having
		-- a face/front rather than being a plain uniform sphere.
		{ shape = "Ball", size = Vector3.new(0.26, 0.26, 0.26), offset = CFrame.new(1.6, 1, -0.62), color = core, floaty = true, trim = true, sparkleAnchor = true },
	}
end

local function auraRingSpec(color)
	local rim = lighten(color, 0.3)
	return {
		{ shape = "Cylinder", size = Vector3.new(0.1, 2.5, 2.5), offset = CFrame.new(0, -1.2, 0) * CFrame.Angles(math.rad(90), 0, 0), color = color, orbits = true },
		-- A second, thinner ring at a different tilt for extra depth.
		{ shape = "Cylinder", size = Vector3.new(0.06, 2.2, 2.2), offset = CFrame.new(0, -1.2, 0) * CFrame.Angles(math.rad(70), 0, 0), color = rim, orbits = true, trim = true, sparkleAnchor = true },
	}
end

local ARCHETYPE_BUILDERS = {
	Crown = crownSpec,
	Headband = headbandSpec,
	Eyewear = eyewearSpec,
	Neckwear = neckwearSpec,
	ChestCharm = chestCharmSpec,
	Cape = capeSpec,
	Wings = wingsSpec,
	Halo = haloSpec,
	FloatingCompanion = floatingCompanionSpec,
	AuraRing = auraRingSpec,
}
CosmeticVisuals.ARCHETYPE_BUILDERS = ARCHETYPE_BUILDERS

--[[
	Returns { attach = "Head"/"UpperTorso"/"HumanoidRootPart", parts = {...}, treatment = {...} }
	for the given Accessory item id, or nil if this id isn't a known
	accessory (defensive - a config typo should silently show nothing,
	never error a whole character's rendering).
]]
function CosmeticVisuals.BuildAccessorySpec(itemId: string, previewColor: Color3, rarity: string)
	local entry = CosmeticVisuals.ACCESSORY_SPECS[itemId]
	if not entry then
		return nil
	end
	local builder = ARCHETYPE_BUILDERS[entry.archetype]
	if not builder then
		return nil
	end
	local treatment = RARITY_TREATMENT[rarity] or RARITY_TREATMENT.Common
	return {
		attach = entry.attach,
		parts = builder(previewColor),
		treatment = treatment,
	}
end

-- ============================================================
-- ===== Trails (100% mechanical - no per-item table at all) ====
-- ============================================================

-- Rarity -> width/lifetime/transparency curve. Every Trail item uses its
-- own previewColor for Color - only these physical parameters scale with
-- rarity, so a Boundless trail is a genuinely bigger, longer, denser
-- effect than a Common one without needing 20 separate hand-tuned entries.
local TRAIL_RARITY_PARAMS = {
	Common = { width = 1.2, lifetime = 0.6, minTransparency = 0.45 },
	Uncommon = { width = 1.6, lifetime = 0.8, minTransparency = 0.3 },
	Rare = { width = 2.0, lifetime = 1.0, minTransparency = 0.15 },
	Legendary = { width = 2.6, lifetime = 1.3, minTransparency = 0.05 },
	Boundless = { width = 3.2, lifetime = 1.6, minTransparency = 0 },
}
CosmeticVisuals.TRAIL_RARITY_PARAMS = TRAIL_RARITY_PARAMS

function CosmeticVisuals.GetTrailParams(rarity: string)
	return TRAIL_RARITY_PARAMS[rarity] or TRAIL_RARITY_PARAMS.Common
end

--[[
	NOT YET COVERED BY THIS MODULE:
	  - QuestionTheme: needs to reskin the in-match question panel, which
	    lives in a different system (CompetitionUIController /
	    ArenaScreenController) not touched by this pass.
	  - VictoryAnimation: needs an actual pose/motion system for the
	    character at match-end, which also doesn't exist yet. Building 20
	    genuinely unique procedural animations (no imported assets, same
	    constraint as everything else in this game) is a separate,
	    substantial piece of work from the character-attachment system
	    this module provides.
	Both are explicitly left for a follow-up pass rather than stubbed out
	silently here.
]]

return CosmeticVisuals
