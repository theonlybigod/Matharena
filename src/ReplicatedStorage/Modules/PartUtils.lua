--[[
	PartUtils.lua

	Shared helper for constructing BaseParts (or SpawnLocations, which are
	BaseParts too) with sensible defaults. Used by LobbyBuilder, ArenaBuilder,
	and any future world-construction module — lives in ReplicatedStorage so
	it's reusable rather than duplicated per builder.
]]

export type PartProps = {
	className: string?,
	name: string?,
	size: Vector3?,
	position: Vector3?,
	cframe: CFrame?,
	orientation: Vector3?,
	material: Enum.Material?,
	color: Color3?,
	canCollide: boolean?,
	transparency: number?,
	shape: Enum.PartType?,
	parent: Instance?,
}

local PartUtils = {}

function PartUtils.CreatePart(props: PartProps): BasePart
	local part = Instance.new(props.className or "Part") :: BasePart

	part.Name = props.name or part.ClassName
	part.Size = props.size or Vector3.new(4, 4, 4)
	part.CFrame = props.cframe or CFrame.new(props.position or Vector3.zero)
	part.Anchored = true
	part.CanCollide = if props.canCollide == nil then true else props.canCollide
	part.Material = props.material or Enum.Material.SmoothPlastic
	part.Color = props.color or Color3.fromRGB(255, 255, 255)
	part.Transparency = props.transparency or 0

	if props.shape and part:IsA("Part") then
		(part :: Part).Shape = props.shape
	end

	if props.orientation then
		part.Orientation = props.orientation
	end

	part.Parent = props.parent
	return part
end

--[[
	Creates a flat, disc-shaped Part (a Cylinder Part rotated so its circular
	caps face up/down instead of sideways). Useful for floors, stages,
	platform bases, and ring/halo decorations.

	`thickness` is the vertical height of the disc, `diameter` is its width.

	IMPORTANT: a Cylinder-shaped Part's native axis (where its circular caps
	sit) is its LOCAL X-axis, not Z. This builds the part with thickness
	already on the X-axis (Size = (thickness, diameter, diameter)) and then
	rotates it 90 degrees around Z via CFrame (not Orientation) so X ends up
	pointing straight up - a single, unambiguous transform. Setting
	.Orientation as a second write after .CFrame (as this used to do,
	through CreatePart's props.orientation path) is NOT equivalent for a
	shaped Part and previously produced a disc lying on its side instead of
	standing upright - e.g. a size-(2, 341.8, 341.8) LobbyGround ending up
	341.8 studs TALL instead of 2 studs thick, which is exactly the kind of
	corrupted, wildly-overlapping geometry that can make a scene render as
	a washed-out mess. Always build the correct final CFrame directly
	instead of layering Orientation on top of an already-set CFrame.
]]
function PartUtils.CreateDisc(props: {
	name: string?,
	diameter: number,
	thickness: number,
	position: Vector3,
	material: Enum.Material?,
	color: Color3?,
	canCollide: boolean?,
	transparency: number?,
	parent: Instance?,
}): BasePart
	return PartUtils.CreatePart({
		name = props.name,
		size = Vector3.new(props.thickness, props.diameter, props.diameter),
		cframe = CFrame.new(props.position) * CFrame.Angles(0, 0, math.rad(90)),
		material = props.material,
		color = props.color,
		canCollide = props.canCollide,
		transparency = props.transparency,
		shape = Enum.PartType.Cylinder,
		parent = props.parent,
	})
end

return PartUtils
