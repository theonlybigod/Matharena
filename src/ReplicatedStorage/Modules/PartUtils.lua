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
	castShadow: boolean?,
	parent: Instance?,
}

local PartUtils = {}

--[[
	SHADOW BUDGET

	Roblox defaults CastShadow to true on every part, and this project had
	never overridden it: a measured 28,462 of 28,462 world parts were
	shadow casters. Shadow-map cost scales with caster count, and it is the
	single largest rendering cost in the build - the maps range from 908
	parts (Futuristic) to 12,162 (IceAge).

	Two categories are excluded automatically below, because in both cases
	the shadow is either WRONG or invisible - this is a look improvement
	first and a performance win second, not a quality sacrifice:

	  NEON (5,675 parts). A Neon surface reads as self-illuminated - a
	  glowing sign, lava vein, or floor inlay. Having it cast a hard
	  occlusion shadow is a straight contradiction: the thing appears to
	  emit light while also blocking it. Dropping the shadow is what makes
	  neon read as "glowing" rather than "bright coloured plastic", which
	  is exactly the restrained-glow look LightingConfig is aiming for.

	  TINY DETAIL (under TINY_DETAIL_VOLUME studs³, 7,924 parts). Trim
	  slivers, bolts, small decorative shards and similar. At any normal
	  camera distance their shadows are sub-pixel noise that reads as
	  shimmer/acne rather than depth, so removing them makes the scene
	  CLEANER as well as cheaper.

	Structural geometry - walls, roofs, floors, trunks, rocks, buildings -
	is untouched and still casts shadows, so the scene keeps all the
	shadowing that actually conveys form and grounding.

	Always overridable per-part via props.castShadow when a specific piece
	genuinely needs the opposite.
]]
PartUtils.TINY_DETAIL_VOLUME = 8 -- studs³; e.g. a 2x2x2 cube is exactly at the threshold and still casts

--[[
	Whether a part of this material/size should cast a shadow by default.
	Pure function of the two inputs so callers (and tests) can reason about
	it without constructing a part.
]]
function PartUtils.ShouldCastShadow(material: Enum.Material, size: Vector3): boolean
	if material == Enum.Material.Neon then
		return false
	end
	if (size.X * size.Y * size.Z) < PartUtils.TINY_DETAIL_VOLUME then
		return false
	end
	return true
end

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

	-- See the SHADOW BUDGET note above.
	part.CastShadow = if props.castShadow == nil
		then PartUtils.ShouldCastShadow(part.Material, part.Size)
		else props.castShadow

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
	castShadow: boolean?,
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
		castShadow = props.castShadow,
		shape = Enum.PartType.Cylinder,
		parent = props.parent,
	})
end

return PartUtils
