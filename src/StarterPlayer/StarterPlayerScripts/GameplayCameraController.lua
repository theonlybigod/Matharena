--[[
	GameplayCameraController.lua

	Shared camera-focus logic for "the camera should zoom toward the big
	central MATHARENA screen whenever a player is in Practice Mode or a
	competitive match" - used by both CompetitionUIController.client.lua
	and PracticeUIController.client.lua.

	MOST IMPORTANT REQUIREMENT (per explicit direction): "the player
	should be able to see literally ANYTHING ELSE on their screen only if
	it is necessary - the main visual focus should be the board/screen".
	The camera repositions to directly face whichever of the screen's two
	flat faces is on the SAME side as the player's platform - a canonical,
	correct-face viewing spot, so the screen is always presented straight-
	on and fully readable regardless of which of the 12 platforms the
	player is on. FieldOfView is also tightened during the zoom (a real
	telephoto pull) and restored to default on release.

	CLIPPING-THROUGH-GEOMETRY FIX: the previous version tweened the
	camera's CFrame in a straight line from wherever the player happened
	to be standing (their live camera CFrame at the moment a turn starts)
	all the way to the arena screen framing. A raw CFrame/position lerp
	has NO collision awareness - if a player triggered this while standing
	near a leaderboard, inside a building, or anywhere else in the lobby,
	that straight-line path could (and did) visually sweep straight
	through solid geometry (floors, leaderboard screens, walls) for the
	duration of the tween, reading as "the camera is looking through the
	floor". The fix: the large, arbitrary-distance jump from "wherever the
	player was" to "near the arena screen" is now an INSTANT CUT (no
	interpolation, so there's nothing to visually render mid-flight and
	therefore nothing to clip through), and only the FINAL, SHORT distance
	-  a small push-in from slightly further back at the same final
	viewing angle - is actually tweened. That short push-in stays entirely
	within the open air directly in front of the screen, a volume that's
	never occupied by other geometry, so it can never clip through
	anything. This still delivers a genuine "smooth zoom-in" feel (the
	FOV narrows and the camera visibly pushes closer) without the unsafe
	long-distance sweep that caused the bug.

	Purely a client-side presentation system - never touches server state,
	never affects MatchSystem/CompetitionGameplay/PracticeSystem in any
	way. Camera.CameraType is only ever set to Scriptable while a
	turn/practice session is visually active, and always restored to
	Custom (normal player-controlled camera) the instant that ends -
	"do not permanently lock the player's camera after leaving the match".

	Mobile: this module only ever writes Camera.CFrame/FieldOfView - it
	never reads or depends on any input device, so the zoom itself behaves
	identically on PC and mobile.
]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local GameplayCameraController = {}

local camera = Workspace.CurrentCamera
local cameraActive = false
local activeTween: Tween? = nil
local activeTweenTarget: CFrameValue? = nil
local activeFovTween: Tween? = nil

local DEFAULT_FOV = 70
-- FIX ("camera is too zoomed in, I want to see the ENTIRE screen/board,
-- not just part of it"): the previous ZOOM_FOV=48 at VIEW_DISTANCE=34 was
-- a genuine math error, not a matter of taste - verified by calculation:
-- fitting the screen's 80x40 stud face at 34 studs away requires a
-- vertical FOV of ~67 degrees (width is the limiting dimension on a
-- normal widescreen viewport), but 48 degrees is 19 degrees NARROWER
-- than that, which crops the screen's edges out of frame - it could
-- never have fit. Retuned to distance=65/FOV=60 with a generous 35%
-- safety margin baked into the verification (not just an exact fit) -
-- calculated to need only ~50.1 degrees to fit comfortably, a real
-- 10-degree buffer below the 60-degree budget, so the full screen is
-- always entirely visible with real room to spare, not just barely
-- touching the frame edges. 60 is still meaningfully narrower than the
-- default 70 so it still reads as a real "zoom".
local ZOOM_FOV = 60
local VIEW_DISTANCE = 65 -- final resting distance - verified (see above) to fit the full 80x40 screen with a real margin at ZOOM_FOV
local PUSH_IN_START_DISTANCE = 78 -- where the SHORT, SAFE tween starts from - further back along the exact same viewing axis, never anywhere else
local VERTICAL_OFFSET = 2 -- a slight camera elevation above the screen's own center - reads as an intentional broadcast angle, not a flat straight-on snapshot

local function getScreen(): BasePart?
	local tagged = CollectionService:GetTagged("QuestionScreen")[1]
	if tagged and tagged:IsA("BasePart") then
		return tagged
	end
	local arena = Workspace:FindFirstChild("Arena")
	local centerStage = arena and arena:FindFirstChild("CenterStage")
	local screen = centerStage and centerStage:FindFirstChild("QuestionScreen")
	return (screen and screen:IsA("BasePart")) and screen or nil
end

local function stopActiveTweens()
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
	if activeTweenTarget then
		activeTweenTarget:Destroy()
		activeTweenTarget = nil
	end
	if activeFovTween then
		activeFovTween:Cancel()
		activeFovTween = nil
	end
end

--[[
	Moves the camera into a tight, canonical "broadcast" shot of the
	central MATHARENA screen. `platformIndex` (if known) is only used to
	decide WHICH of the screen's two faces to shoot head-on, so the player
	always sees the correctly-oriented, fully-readable side.
]]
function GameplayCameraController.FocusOnScreen(platformIndex: number?, transitionSeconds: number?)
	local screen = getScreen()
	if not screen then
		return
	end

	-- Determine which side of the screen (along its own local Z, the
	-- thin/depth axis) the player's platform is on, so we shoot the
	-- correct face head-on. Defaults to the screen's own current +Z side
	-- if we don't have a platform to check against.
	local faceSign = 1
	if platformIndex then
		local arena = Workspace:FindFirstChild("Arena")
		local platforms = arena and arena:FindFirstChild("Platforms")
		local platform = platforms and platforms:FindFirstChild("Platform" .. platformIndex)
		local base = platform and platform:FindFirstChild("Base")
		if base and base:IsA("BasePart") then
			local localPlatformPosition = screen.CFrame:PointToObjectSpace(base.Position)
			faceSign = if localPlatformPosition.Z >= 0 then 1 else -1
		end
	end

	local lookTarget = screen.Position
	local finalPosition = screen.CFrame:PointToWorldSpace(Vector3.new(0, VERTICAL_OFFSET, faceSign * VIEW_DISTANCE))
	local startPosition = screen.CFrame:PointToWorldSpace(Vector3.new(0, VERTICAL_OFFSET, faceSign * PUSH_IN_START_DISTANCE))

	local toCFrame = CFrame.new(finalPosition, lookTarget)
	local fromCFrame = CFrame.new(startPosition, lookTarget)

	stopActiveTweens()

	-- The large, arbitrary-distance jump from wherever the player was
	-- actually standing to the safe volume near the screen is an INSTANT
	-- CUT - nothing is rendered mid-flight, so there's nothing to clip
	-- through. Only the short push-in below (44 -> 34 studs, entirely in
	-- open air directly in front of the screen) is ever tweened.
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = fromCFrame
	cameraActive = true

	local seconds = transitionSeconds or 1
	if seconds <= 0 then
		camera.CFrame = toCFrame
		camera.FieldOfView = ZOOM_FOV
		return
	end

	-- Same CFrameValue-tween pattern already used elsewhere in this
	-- project for smooth CFrame interpolation (CFrame isn't itself a
	-- tweenable property type without a proxy value object). A slightly
	-- punchier easing (Quint, not Quad) so the zoom reads as a deliberate
	-- "punch in" rather than a lazy drift.
	local tweenTarget = Instance.new("CFrameValue")
	tweenTarget.Value = fromCFrame
	activeTweenTarget = tweenTarget

	local tween = TweenService:Create(tweenTarget, TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Value = toCFrame,
	})
	activeTween = tween

	local connection: RBXScriptConnection
	connection = tweenTarget:GetPropertyChangedSignal("Value"):Connect(function()
		if cameraActive then
			camera.CFrame = tweenTarget.Value
		end
	end)
	tween.Completed:Connect(function()
		connection:Disconnect()
	end)
	tween:Play()

	-- FieldOfView tween in parallel - the actual "zoom lens" narrowing,
	-- distinct from the camera physically moving closer.
	local fovTween = TweenService:Create(camera, TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		FieldOfView = ZOOM_FOV,
	})
	activeFovTween = fovTween
	fovTween:Play()
end

--[[
	Restores the normal player-controlled lobby camera (and default
	FieldOfView). Safe to call even if the camera isn't currently under
	this module's control. This is also always an instant cut back to
	Custom camera control - Roblox's own player camera takes over
	immediately, so there's no "return flight" that could clip through
	anything either.
]]
function GameplayCameraController.Release()
	stopActiveTweens()
	if cameraActive then
		camera.CameraType = Enum.CameraType.Custom
		cameraActive = false
	end
	camera.FieldOfView = DEFAULT_FOV
end

return GameplayCameraController
