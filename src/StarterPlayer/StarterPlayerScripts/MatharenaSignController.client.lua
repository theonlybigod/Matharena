--[[
	MatharenaSignController.client.lua

	Drives the purely-visual bobbing motion for every map's MATHARENA
	landmark sign (see ServerScriptService/LobbyBuilder/Sign.lua). This is
	all this script does - each sign's actual size, text, and glow are all
	built server-side so every client sees the same static geometry; only
	this one purely-visual motion is done here, client-side, so it costs
	no server time or network replication per frame.

	Multi-map support: every map registered in MapsConfig.lua gets its own
	sign (same SignConfig.SIGN_NAME in every map's own Workspace folder,
	just possibly a different glow color per LobbyTheme) - this script
	independently finds and bobs EACH one, rather than assuming there's
	only ever a single "Lobby" folder to look in.

	Branding cleanup pass: the holographic ring and its client-side
	rotation code have been removed entirely, matching Sign.lua no longer
	building a "HoloRing" part at all - this script used to
	WaitForChild("HoloRing") with no timeout, which would now hang forever
	waiting for a part that will never exist if left in place.

	Bounded waits (fixes a real leak): not every mapDef in MapsConfig.MAPS
	is guaranteed to have a Workspace folder on every server - a dedicated
	difficulty Place's own project.json only ever declares its ONE
	assigned map (see place.<name>.project.json), and the Hub itself now
	only builds Futuristic (see Main.server.lua) rather than all five.
	WaitForChild below used to have no timeout, so the four maps that
	don't exist on a given server each leaked a permanently-suspended
	coroutine (isolated by task.spawn, so harmless to anything else, but
	still four dangling "Infinite yield possible" warnings per player,
	forever). Every WaitForChild here now has a bounded timeout and skips
	gracefully (nil-checked, no warning, no leak) rather than hanging.

	Reads its amplitude/period from SignConfig, so the motion can be
	retuned without touching this script.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local SignConfig = require(ReplicatedStorage.Modules.SignConfig)
local MapsConfig = require(ReplicatedStorage.Modules.MapsConfig)

local function startBobTween(targetPanel: BasePart): Tween
	local basePosition = targetPanel.Position
	local tween = TweenService:Create(
		targetPanel,
		TweenInfo.new(
			SignConfig.BOB_PERIOD_SECONDS / 2,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1, -- repeat forever
			true -- reverse, so it eases back down instead of snapping
		),
		{ Position = basePosition + Vector3.new(0, SignConfig.BOB_HEIGHT, 0) }
	)
	tween:Play()
	return tween
end

--[[
	Waits for `mapDef`'s own map folder + sign + panel, then starts (and
	perpetually re-starts, across a LobbyBuilder.Rebuild()) the bob tween
	for that one map's sign - independent of every other map's sign.
]]
local function watchMapSign(mapDef: MapsConfig.MapDef)
	local lobby = Workspace:WaitForChild(mapDef.workspaceFolderName, 30)
	if not lobby then
		-- Not every server builds every map (see this function's updated doc
		-- comment above) - skip gracefully rather than hang forever.
		return
	end

	local sign = lobby:WaitForChild(SignConfig.SIGN_NAME, 30)
	if not sign then
		return
	end

	local panel = sign:WaitForChild("SignPanel", 30) :: BasePart?
	if not panel then
		return
	end

	local bobTween = startBobTween(panel)

	-- If this map is ever rebuilt (LobbyBuilder.Rebuild()), the old sign
	-- instance gets destroyed and a new one built in its place. Re-anchor
	-- to the fresh instance so the animation keeps running instead of
	-- silently tweening a destroyed part.
	sign.AncestryChanged:Connect(function(_, newParent)
		if newParent == nil then
			bobTween:Cancel()

			local newSign = lobby:WaitForChild(SignConfig.SIGN_NAME, 30)
			if not newSign then
				return
			end
			local newPanel = newSign:WaitForChild("SignPanel", 30) :: BasePart?
			if not newPanel then
				return
			end

			bobTween = startBobTween(newPanel)
		end
	end)
end

for _, mapDef in ipairs(MapsConfig.MAPS) do
	task.spawn(watchMapSign, mapDef)
end
