class_name SandboxSolidProp
extends StaticBody3D
## A freely placed SOLID shelf piece: the grid Blocker's 6x3x2.5" profile (CONTAINER: impassable, solid
## sight, a flat roof minis stand on). Its ONE collider is exactly the rule box, so the visible mass never
## disagrees with the sight/movement OBB (main._sandbox_terrain_shapes). Plain stone look for now.

const GROUP := "sandbox_terrain"
## Kept in sync with object_manager.gd / SandboxTerrainProp. Mask 0: it never settles on anything.
const GROUND_COLLISION_LAYER := 1
const MOVABLE_TERRAIN_COLLISION_LAYER := 4
const INCHES_TO_METERS := 0.0254
const STONE_COLOR := Color(0.28, 0.29, 0.305)   # plain stone grey, a touch cool so warm Sunset light keeps it grey (maintainer 04.10.)

## Bundled low-detail looks (maintainer D5: the bundled fallback ships first, a detailed model later on his upload
## word). A look is boxes inside the 6x3x2.5" rule box: [x0, x1, y0, y1, z0, z1, colour] in inches (x = long side,
## y = up, z = short side). Walls sit 0.05" inside the footprint so doors and shutters stay within it.
const LOOKS := {
	"plain": [[-3.0, 3.0, 0.0, 2.5, -1.5, 1.5, "stone"]],
	# Slab-roof storehouse (pick B, 3D v2): mossy foot, granite walls, broad coping rim, oak door on the -Z front.
	"house_b": [[-2.95, 2.95, 0.0, 0.3, -1.45, 1.45, "moss"], [-2.95, 2.95, 0.3, 2.42, -1.45, 1.45, "ashlar"],
		[-3.0, 3.0, 2.34, 2.5, -1.5, -1.24, "coping"], [-3.0, 3.0, 2.34, 2.5, 1.24, 1.5, "coping"],
		[-3.0, -2.74, 2.34, 2.5, -1.24, 1.24, "coping"], [2.74, 3.0, 2.34, 2.5, -1.24, 1.24, "coping"],
		[-0.4, 0.4, 0.0, 1.4, -1.5, -1.45, "wood"]],
	# Heather outcrop (pick C, 3D rock 2): grass foot, two offset granite beds, lichen and tufts on the flat top.
	"rock_c": [[-3.0, 3.0, 0.0, 0.1, -1.5, 1.5, "grass"], [-2.9, 2.85, 0.1, 1.2, -1.42, 1.4, "granite"],
		[-2.95, 2.95, 1.2, 2.4, -1.45, 1.45, "granite_top"], [-2.4, -1.4, 2.4, 2.5, -0.9, -0.1, "lichen"],
		[0.3, 1.5, 2.4, 2.5, 0.2, 1.0, "lichen"], [1.8, 2.5, 2.4, 2.48, -1.1, -0.4, "tuft"]],
}
const COLOURS := {"stone": STONE_COLOR, "moss": Color(0.20, 0.25, 0.10), "ashlar": Color(0.29, 0.29, 0.305),
	"coping": Color(0.23, 0.235, 0.25), "wood": Color(0.27, 0.18, 0.11), "grass": Color(0.27, 0.30, 0.13),
	"granite": Color(0.31, 0.315, 0.33), "granite_top": Color(0.36, 0.365, 0.38), "lichen": Color(0.38, 0.40, 0.22),
	"tuft": Color(0.33, 0.24, 0.14)}

const SKIRT_MARGIN_INCHES := 0.8
const SKIRT_HEIGHT_INCHES := 0.4   # reaches the table and the lowest 0.2" of the walls, nothing higher
const SKIRT_OPACITY := 0.7

static var _skirt_textures := {}   # footprint -> ImageTexture, shared by every piece of that size

var prop_id: String = ""
var prop_kind: int = 0
var footprint_inches: Vector2 = Vector2.ZERO


## Show a detailed model (3.5) instead of the bundled look. The model's origin is the footprint centre on the ground,
## like the prop's; the collider stays the rule box.
func use_model(model: Node3D) -> void:
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = false
	add_child(model)


## Call once right after `new()`, before adding to the tree / positioning.
func configure(p_prop_id: String, p_kind: int, p_footprint_inches: Vector2, p_look: String = "plain") -> void:
	prop_id = p_prop_id
	prop_kind = p_kind
	footprint_inches = p_footprint_inches
	for g in ["selectable", "terrain", GROUP]:
		add_to_group(g)
	collision_layer = GROUND_COLLISION_LAYER | MOVABLE_TERRAIN_COLLISION_LAYER
	collision_mask = 0
	set_meta("prop_id", prop_id)
	set_meta("prop_kind", prop_kind)
	# Local +X = the footprint's long side, the axis the shape provider's he.x and yaw describe.
	var size := Vector3(footprint_inches.x, TerrainRules.CONTAINER_HEIGHT_INCHES, footprint_inches.y) * INCHES_TO_METERS
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = size.y * 0.5
	add_child(col)
	# The look: boxes of LOOKS[p_look] (unknown -> plain), one material per colour. Rules never read it.
	var mats := {}
	for part: Array in LOOKS.get(p_look, LOOKS["plain"]):
		var lo := Vector3(part[0], part[2], part[4])
		var hi := Vector3(part[1], part[3], part[5])
		if not mats.has(part[6]):
			mats[part[6]] = StandardMaterial3D.new()
			mats[part[6]].albedo_color = COLOURS[part[6]]
			mats[part[6]].roughness = 0.93
		var mesh := BoxMesh.new()
		mesh.size = (hi - lo) * INCHES_TO_METERS
		mesh.material = mats[part[6]]
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.position = (hi + lo) * 0.5 * INCHES_TO_METERS
		add_child(visual)
	add_child(GrasslandFootScatter.new().setup(footprint_inches, false))   # stones + grass at the foot (S6-2)
	# Soft contact shadow (maintainer 05.10.): a Decal child, so it moves, turns and goes with the piece. Decoration only.
	var skirt := Decal.new()
	skirt.name = "ContactSkirt"
	skirt.texture_albedo = _skirt_texture(footprint_inches)
	skirt.modulate = Color(1, 1, 1, SKIRT_OPACITY)
	skirt.size = Vector3(footprint_inches.x + 2.0 * SKIRT_MARGIN_INCHES, SKIRT_HEIGHT_INCHES,
		footprint_inches.y + 2.0 * SKIRT_MARGIN_INCHES) * INCHES_TO_METERS
	add_child(skirt)
	add_child(GrasslandFootDressing.new().setup(footprint_inches))   # earth + moss at the foot (S6-1)


## Opaque under the footprint, fading (squared) to nothing SKIRT_MARGIN_INCHES outside its edge, 10 px per inch; built
## once per footprint. (A GradientTexture2D square fill stayed near-transparent in that ring, measured 05.10.)
static func _skirt_texture(fp: Vector2) -> ImageTexture:
	if _skirt_textures.has(fp):
		return _skirt_textures[fp]
	var w := fp.x + 2.0 * SKIRT_MARGIN_INCHES
	var h := fp.y + 2.0 * SKIRT_MARGIN_INCHES
	var img := Image.create(int(w * 10.0), int(h * 10.0), false, Image.FORMAT_RGBA8)
	for py in img.get_height():
		for px in img.get_width():
			var dx := maxf(absf((px + 0.5) / 10.0 - w * 0.5) - fp.x * 0.5, 0.0)
			var dz := maxf(absf((py + 0.5) / 10.0 - h * 0.5) - fp.y * 0.5, 0.0)
			var a := clampf(1.0 - sqrt(dx * dx + dz * dz) / SKIRT_MARGIN_INCHES, 0.0, 1.0)
			img.set_pixel(px, py, Color(0, 0, 0, a * a))
	_skirt_textures[fp] = ImageTexture.create_from_image(img)
	return _skirt_textures[fp]
