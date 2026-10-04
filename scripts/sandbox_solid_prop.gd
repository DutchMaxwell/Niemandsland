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

var prop_id: String = ""
var prop_kind: int = 0
var footprint_inches: Vector2 = Vector2.ZERO


## Call once right after `new()`, before adding to the tree / positioning.
func configure(p_prop_id: String, p_kind: int, p_footprint_inches: Vector2) -> void:
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
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = STONE_COLOR
	mat.roughness = 0.93
	mesh.material = mat
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position.y = size.y * 0.5
	add_child(visual)
