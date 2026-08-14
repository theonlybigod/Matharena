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
		orientation = Vector3.new(0, 0, 90),
		position = props.position,
		material = props.material,
		color = props.color,
		canCollide = props.canCollide,
		transparency = props.transparency,
		shape = Enum.PartType.Cylinder,
		parent = props.parent,
	})
end

return PartUtils
