--[[
	CharacterPreviewBuilder.lua

	Shared helper for building a live, correctly-posed ViewportFrame render
	of a player's own avatar - used by the Shop panel's item details, the
	Inventory panel's item details, and the Shop building's wall-mounted
	Featured Item board. One implementation instead of three copies that
	could quietly drift apart.

	HISTORY OF WHAT DIDN'T WORK (kept here so this isn't re-attempted the
	same way twice):
	  - Anchoring immediately after CreateHumanoidModelFromDescription and
	    then PivotTo-ing the model left accessories' Handles wherever they
	    were originally welded (measured once at ~55 studs from the body),
	    since a Weld's C0/C1 is only continuously re-applied by the physics
	    joint solver, which doesn't run on Anchored parts.
	  - "Fix" attempt: move the model to real (unanchored) Workspace,
	    wait several real physics frames so the joint solver settles
	    accessories, THEN anchor and reparent into the ViewportFrame. This
	    reliably made things WORSE - reproducibly returned a model with
	    Humanoid/Shirt/Pants/BodyColors but ZERO actual body parts at all
	    (not even HumanoidRootPart), even in total isolation with no other
	    caller running at the same time. Something about the real-Workspace
	    unanchored round trip is actively destructive to a
	    HumanoidDescription-built model, not merely slow to settle - the
	    root cause was not pinned down before this was reverted.

	CURRENT APPROACH: never move the model out of the ViewportFrame at all.
	Wait (bounded) for the real body to appear, THEN wait a further short
	beat for accessories to attach, then do a PER-ACCESSORY sanity check:
	if an accessory's Handle ends up implausibly far from the body (the
	exact failure mode measured before), drop just that one accessory
	instead of either faking its position or discarding the whole
	preview. Everything else about the character (including any
	correctly-attached accessories) still shows.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CharacterPreviewBuilder = {}

export type PreviewHandle = {
	model: Model,
	focusPoint: Vector3,
	modelHeight: number,
	distance: number,
}

-- An accessory Handle further than this from the body's own center is
-- treated as a mispositioned/unsettled weld rather than a real part of the
-- rig - measured failures put a bad Handle around 50+ studs out, so this
-- comfortably separates "real accessory" from "broken weld" without ever
-- rejecting a legitimately large hat/wings/etc.
local MAX_PLAUSIBLE_ACCESSORY_DISTANCE = 15

--[[
	Builds a model of `player`'s own current avatar and parents it into
	`viewport`. Returns a PreviewHandle with the framing numbers a caller
	needs to point a Camera at it, or nil if the HumanoidDescription/model
	couldn't be built at all (network hiccup, moderated avatar data, etc -
	callers should leave their viewport on its empty background rather
	than error).

	Yields (network call + a short settle wait), so callers should run this
	in its own coroutine (task.spawn) rather than inline.
]]
function CharacterPreviewBuilder.Build(player: Player, viewport: ViewportFrame): PreviewHandle?
	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if not ok or not description then
		warn("[CharacterPreviewBuilder] Could not load HumanoidDescription:", description)
		return nil
	end

	local ok2, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok2 or not model then
		warn("[CharacterPreviewBuilder] Could not build character model:", model)
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")

	-- Wait (bounded) for the real body to exist - CreateHumanoidModelFromDescription
	-- does not always return a model with every BasePart already inserted.
	local rootPart: BasePart? = nil
	for _ = 1, 150 do
		rootPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			break
		end
		RunService.Heartbeat:Wait()
	end
	if not rootPart then
		warn("[CharacterPreviewBuilder] Model never gained a HumanoidRootPart - giving up on this preview")
		model:Destroy()
		return nil
	end
	model.PrimaryPart = rootPart

	-- Anchor immediately, IN PLACE - never move this model to real Workspace
	-- physics (see the module doc comment for why that made things worse).
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	if humanoid then
		humanoid.PlatformStand = true
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end

	model.Parent = viewport
	model:PivotTo(CFrame.new(0, 0, 0))

	-- A short settle beat for any accessory attachment still in flight,
	-- then the per-accessory sanity check described in the module doc
	-- comment - drop only the specific accessories that ended up
	-- implausibly far away, not the whole preview.
	for _ = 1, 5 do
		RunService.Heartbeat:Wait()
	end

	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Accessory") then
			local handlePart = child:FindFirstChild("Handle")
			if handlePart and handlePart:IsA("BasePart") then
				local distance = (handlePart.Position - rootPart.Position).Magnitude
				if distance > MAX_PLAUSIBLE_ACCESSORY_DISTANCE then
					child:Destroy()
				else
					handlePart.Anchored = true
					handlePart.CanCollide = false
				end
			end
		end
	end
	-- Re-pivot after the settle beat and accessory cleanup, in case
	-- anything nudged the model during that window.
	model:PivotTo(CFrame.new(0, 0, 0))

	local center, size = model:GetBoundingBox()
	local modelHeight = size.Y
	local focusPoint = center.Position
	-- Derived from the model's own measured height (roughly 5-6 studs for a
	-- typical R15 rig) rather than a fixed guess, so unusually tall/short
	-- avatars still frame correctly without clipping.
	local distance = modelHeight * 1.7

	return {
		model = model,
		focusPoint = focusPoint,
		modelHeight = modelHeight,
		distance = distance,
	}
end

--[[
	Connects a slow orbiting camera around `handle`, only while
	`isVisible()` returns true (skip the work entirely while the panel/
	board isn't being looked at). Returns the RBXScriptConnection so a
	caller can disconnect it if the viewport is ever torn down, though in
	practice every current caller keeps its viewport for the whole session.
]]
function CharacterPreviewBuilder.ConnectOrbit(camera: Camera, handle: PreviewHandle, isVisible: () -> boolean): RBXScriptConnection
	camera.FieldOfView = 30
	local angle = 0
	return RunService.RenderStepped:Connect(function(dt)
		if not isVisible() then
			return
		end
		angle += dt * 0.5
		local camPos = handle.focusPoint
			+ Vector3.new(math.sin(angle) * handle.distance, handle.modelHeight * 0.15, math.cos(angle) * handle.distance)
		camera.CFrame = CFrame.new(camPos, handle.focusPoint + Vector3.new(0, handle.modelHeight * 0.05, 0))
	end)
end

return CharacterPreviewBuilder
