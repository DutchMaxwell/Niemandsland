class_name TerrainGroupBase
extends StaticBody3D
## A single draggable base hosting several terrain visuals — a tree-group "forest" or a
## dangerous-terrain cluster — so they push and rotate as ONE casual-sandbox piece. This is
## the terrain analogue of RegimentTray: members are reparented under the base and ride it
## rigidly. Members are visual-only Node3Ds; the base owns one footprint collider for
## click-selection.
##
## Forests and hazard fields are flat AREA terrain — Forests are Difficult Terrain and
## minefields are Dangerous Terrain in OPR — so a miniature stays at table level inside them
## (the base is NOT on the ground layer). Representation/handling only; no rule is enforced
## here (difficult/dangerous effects live in the measure/terrain code).
##
## Member scatter is seeded so every multiplayer client builds an identical cluster.

# === Constants ===

const GROUP := "terrain_group_base"
## Back-pointer meta set on each member so a click on a member resolves to its base
## (see ObjectManager._regiment_root).
const MEMBER_META := "terrain_group_base"
## Kept in sync with object_manager.gd — movable terrain, off the ground layer so minis
## pass through at table level; mask 0 so it never settles on anything.
const MOVABLE_TERRAIN_COLLISION_LAYER := 4

const INCHES_TO_METERS := 0.0254
## Selection collider height (metres): tall enough that clicking the cluster from a shallow
## camera angle still hits the base, short enough not to block neighbouring drops.
const SELECT_COLLIDER_HEIGHT_M := 0.12

## Sandbox kind ids — kept in sync with ObjectManager.SandboxPropKind (referenced by value,
## not by name, so this class does NOT depend on ObjectManager and the two don't form a
## cyclic class_name dependency that would stall the threaded scene loader).
const KIND_FOREST := 1
const KIND_HAZARD_CLUSTER := 2

const FOREST_TREE_COUNT := 6
const HAZARD_MINE_COUNT := 6
const TREE_VARIANTS: Array[String] = ["tree_a", "tree_b", "tree_c"]

## Target tree height (metres source = inches). Tabletop scatter trees read better small
## next to 28 mm minis — the previous 3.4" trees dwarfed them. Applied to BOTH the R2 GLB
## (scaled to fit) and the procedural fallback.
const TREE_HEIGHT_INCHES := 2.0
const TREE_TRUNK_COLOR := Color(0.36, 0.26, 0.16)
const TREE_FOLIAGE_COLOR := Color(0.20, 0.42, 0.18)
const MINE_RADIUS_INCHES := 0.35
const MINE_COLOR := Color(0.22, 0.20, 0.18)

# === Public state ===

var prop_id: String = ""
var prop_kind: int = 0
var footprint_inches: Vector2 = Vector2.ZERO

# === Public ===

## Set identity + dimensions and build the selection collider. Call once after `new()`.
func configure(p_prop_id: String, p_kind: int, p_footprint_inches: Vector2) -> void:
	prop_id = p_prop_id
	prop_kind = p_kind
	footprint_inches = p_footprint_inches

	add_to_group("selectable")
	add_to_group("terrain")
	add_to_group("sandbox_terrain")
	add_to_group(GROUP)
	collision_layer = MOVABLE_TERRAIN_COLLISION_LAYER
	collision_mask = 0
	set_meta("prop_id", prop_id)
	set_meta("prop_kind", prop_kind)

	_build_select_collider()


## Build and adopt the cluster's members (trees or mines) with a seeded scatter. `trees_lib`
## may be null (procedural trees then). Safe to call once, after adding to the tree.
func build(seed_val: int, trees_lib: TreesLibrary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	match prop_kind:
		KIND_HAZARD_CLUSTER:
			_build_mines(rng)
		_:
			_build_forest(rng, trees_lib)


## Reparent already-instantiated member nodes onto this base at the given local positions
## (used on load to reproduce a saved cluster exactly). `members` = Array of
## {node: Node3D, position: Vector3, rotation_y: float}.
func adopt_members(members: Array) -> void:
	for entry in members:
		var n := entry.get("node", null) as Node3D
		if n == null or not is_instance_valid(n):
			continue
		if n.get_parent() != self:
			if n.get_parent():
				n.get_parent().remove_child(n)
			add_child(n)
		n.position = entry.get("position", Vector3.ZERO)
		n.rotation.y = entry.get("rotation_y", 0.0)
		n.set_meta(MEMBER_META, self)


## Serialized member arrangement (local position + Y rotation per member) for save files.
func member_states() -> Array:
	var states: Array = []
	for child in get_children():
		if not child.has_meta(MEMBER_META):
			continue
		var n := child as Node3D
		states.append({
			"position": [n.position.x, n.position.y, n.position.z],
			"rotation_y": n.rotation.y,
		})
	return states

# === Private ===

func _build_select_collider() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(
		footprint_inches.x * INCHES_TO_METERS,
		SELECT_COLLIDER_HEIGHT_M,
		footprint_inches.y * INCHES_TO_METERS)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = SELECT_COLLIDER_HEIGHT_M * 0.5
	add_child(collider)


func _build_forest(rng: RandomNumberGenerator, trees_lib: TreesLibrary) -> void:
	for i in range(FOREST_TREE_COUNT):
		var variant := TREE_VARIANTS[rng.randi() % TREE_VARIANTS.size()]
		var tree := _make_tree(variant, trees_lib)
		_adopt_scattered(tree, rng)


func _build_mines(rng: RandomNumberGenerator) -> void:
	for i in range(HAZARD_MINE_COUNT):
		_adopt_scattered(_make_mine(), rng)


## Parent a member, scatter it within the footprint, give it a random facing + a back-pointer.
func _adopt_scattered(member: Node3D, rng: RandomNumberGenerator) -> void:
	add_child(member)
	var hw := footprint_inches.x * INCHES_TO_METERS * 0.5
	var hd := footprint_inches.y * INCHES_TO_METERS * 0.5
	member.position = Vector3(rng.randf_range(-hw, hw), 0.0, rng.randf_range(-hd, hd))
	member.rotation.y = rng.randf_range(0.0, TAU)
	member.set_meta(MEMBER_META, self)


## A tree member: the R2 GLB (scaled to TREE_HEIGHT_INCHES) if cached, else a procedural
## trunk + foliage cone of the same height.
func _make_tree(variant: String, trees_lib: TreesLibrary) -> Node3D:
	if trees_lib != null:
		var scene := trees_lib.get_model_scene(variant)
		if scene != null:
			var inst := scene.instantiate() as Node3D
			_fit_height(inst, TREE_HEIGHT_INCHES * INCHES_TO_METERS)
			return inst
	var root := Node3D.new()
	var h := TREE_HEIGHT_INCHES * INCHES_TO_METERS
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = TREE_TRUNK_COLOR
	trunk_mat.roughness = 0.95
	var trunk := CylinderMesh.new()
	trunk.top_radius = h * 0.05
	trunk.bottom_radius = h * 0.06
	trunk.height = h * 0.4
	root.add_child(_mesh_node(trunk, trunk_mat, Vector3(0, h * 0.2, 0)))
	var foliage_mat := StandardMaterial3D.new()
	foliage_mat.albedo_color = TREE_FOLIAGE_COLOR
	foliage_mat.roughness = 0.95
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = h * 0.3
	cone.height = h * 0.7
	root.add_child(_mesh_node(cone, foliage_mat, Vector3(0, h * 0.6, 0)))
	return root


## A mine member: a low dark dome (procedural; the in-game minefield art is grassland-only).
func _make_mine() -> Node3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = MINE_COLOR
	mat.metallic = 0.4
	mat.roughness = 0.6
	var dome := SphereMesh.new()
	var r := MINE_RADIUS_INCHES * INCHES_TO_METERS
	dome.radius = r
	dome.height = r
	return _mesh_node(dome, mat, Vector3(0, r * 0.2, 0))


func _mesh_node(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi


## Uniformly scale a runtime GLB to a target height (metres) and drop its base to y = 0.
static func _fit_height(node: Node3D, target_h: float) -> void:
	var aabb: AABB = _mesh_aabb(node, Transform3D.IDENTITY, AABB(), true)[1]
	if aabb.size.y < 0.0001 or target_h < 0.0001:
		return
	var s := target_h / aabb.size.y
	node.scale = Vector3(s, s, s)
	node.position.y = -aabb.position.y * s


static func _mesh_aabb(node: Node, xform: Transform3D, acc: AABB, first: bool) -> Array:
	var node_xform := xform
	if node is Node3D:
		node_xform = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_aabb: AABB = node_xform * (node as MeshInstance3D).mesh.get_aabb()
		acc = mesh_aabb if first else acc.merge(mesh_aabb)
		first = false
	for child: Node in node.get_children():
		var result := _mesh_aabb(child, node_xform, acc, first)
		first = result[0]
		acc = result[1]
	return [first, acc]
