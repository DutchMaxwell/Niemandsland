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

## Tree count scales with the oval area (~this many trees per square inch), clamped.
const FOREST_TREE_DENSITY := 0.08
const FOREST_TREE_MAX := 14
## Even fill of the oval via phyllotaxis (sunflower): trees out to this radius fraction at the
## golden angle + a little jitter, so ANY count covers the whole pad evenly without clustering.
const FOREST_FILL_RADIUS := 0.82
const FOREST_JITTER := 0.05
const GOLDEN_ANGLE := 2.39996323
const HAZARD_MINE_COUNT := 6
const TREE_VARIANTS: Array[String] = ["tree_a", "tree_b", "tree_c"]

## A forest is an OVAL textured ground pad (the movable area-terrain base) populated with trees.
## footprint = the oval's bounding box (long axis × widest point); trees scatter inside the
## ellipse. The pad sits UP from the table (a thin plinth) to avoid z-fighting.
const FOREST_FLOOR_TEX_DEFAULT := "res://assets/sandbox_forest_floor.webp"
## A non-grassland forest crops its floor from the biome's BATTLEMAP (the same R2 photo the table
## uses) instead of shipping a per-biome tile — keyed by the prop_id biome prefix. Grassland keeps
## its tuned bundled texture (no key). Kept in sync with ObjectManager's prefix list.
const FOREST_FLOOR_BATTLEMAP_KEY_BY_PREFIX: Dictionary = {
	"desert_": "arid_desert",
	"tundra_": "frozen_tundra",
	"volcanic_": "volcanic_ash",
	"jungle_": "alien_jungle",
	"urban_": "urban_ruins",
}
## Crop this many inches square out of the battlemap so one tile reads at roughly the same scale
## as FOREST_FLOOR_TILE_INCHES, given the table's reference width (battlemap spans the whole table).
const FOREST_FLOOR_CROP_INCHES := 6.0
const BATTLEMAP_REFERENCE_WIDTH_INCHES := 72.0
## Inset the (seeded-random) crop origin from the battlemap edges so it never samples the border.
const FOREST_FLOOR_CROP_MARGIN := 0.08
## Anti-tiling shader that hides the texture's repetition on larger pads (see the .gdshader).
const FOREST_FLOOR_SHADER := "res://shaders/forest_floor.gdshader"
const FOREST_BASE_THICKNESS_INCHES := 0.12
const FOREST_OVAL_SEGMENTS := 32
## Forest-floor texture tiles every this many inches (≈ the battlefield stone scale ~3.3"), so
## leaves/moss read at the right small size instead of one giant image stretched over the pad.
const FOREST_FLOOR_TILE_INCHES := 3.0

## Tree height range (inches) — each tree is randomly scaled within this for variety. Applied
## to both the R2 GLB (fit to height) and the procedural fallback.
const TREE_MIN_HEIGHT_INCHES := 4.0
const TREE_MAX_HEIGHT_INCHES := 6.0
const TREE_TRUNK_COLOR := Color(0.36, 0.26, 0.16)
const TREE_FOLIAGE_COLOR := Color(0.20, 0.42, 0.18)
const MINE_RADIUS_INCHES := 0.35
const MINE_COLOR := Color(0.22, 0.20, 0.18)

# === Public state ===

var prop_id: String = ""
var prop_kind: int = 0
var footprint_inches: Vector2 = Vector2.ZERO
## Biome prefix ("" = grassland) selecting the forest's tree set + floor texture.
var biome_prefix: String = ""

# === Private state ===

## Stored so the async tree upgrade can rebuild the IDENTICAL seeded scatter on every client.
var _seed_val: int = 0
var _trees_lib: TreesLibrary = null
var _tree_upgrade_started: bool = false
## Battlemap source for the non-grassland forest-floor crop (async, one-shot). _floor_mesh is the
## pad whose material gets swapped once the biome battlemap is cropped.
var _biome_lib: BiomeLibrary = null
var _floor_mesh: MeshInstance3D = null
var _floor_upgrade_started: bool = false

# === Public ===

## Set identity + dimensions and build the selection collider. Call once after `new()`.
func configure(p_prop_id: String, p_kind: int, p_footprint_inches: Vector2, p_biome_prefix: String = "") -> void:
	prop_id = p_prop_id
	prop_kind = p_kind
	footprint_inches = p_footprint_inches
	biome_prefix = p_biome_prefix

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
func build(seed_val: int, trees_lib: TreesLibrary, biome_lib: BiomeLibrary = null) -> void:
	_seed_val = seed_val
	_trees_lib = trees_lib
	_biome_lib = biome_lib
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


## Tree count for this oval: scales with its area, clamped to [1, FOREST_TREE_MAX].
func _forest_tree_count() -> int:
	var area := PI * (footprint_inches.x * 0.5) * (footprint_inches.y * 0.5)
	return clampi(int(round(area * FOREST_TREE_DENSITY)), 1, FOREST_TREE_MAX)


## Fill the oval EVENLY (phyllotaxis) with a size-scaled number of trees, each randomly sized
## and turned + a little jitter so it reads natural, not mechanical.
func _build_forest(rng: RandomNumberGenerator, trees_lib: TreesLibrary) -> void:
	var base_top := _build_forest_base()
	# Instant pass: real GLB trees where the biome's models are already cached, procedural cones
	# otherwise. If the biome set isn't cached yet, download it and swap the cones for real trees
	# at the SAME seeded layout, so every client converges on identical art.
	_populate_forest(rng, trees_lib, base_top)
	if trees_lib != null and not trees_lib.all_models_cached(biome_prefix):
		_upgrade_forest_trees(base_top)
	# A non-grassland forest swaps its grassland-fallback floor for a crop of the biome battlemap.
	_maybe_upgrade_forest_floor()


## Fill the oval EVENLY (phyllotaxis) with a size-scaled number of trees, each randomly sized and
## turned + a little jitter so it reads natural, not mechanical. Deterministic in `rng`, so a
## re-seeded re-run reproduces the exact scatter (used by the async GLB upgrade below).
func _populate_forest(rng: RandomNumberGenerator, trees_lib: TreesLibrary, base_top: float) -> void:
	var a := footprint_inches.x * INCHES_TO_METERS * 0.5
	var b := footprint_inches.y * INCHES_TO_METERS * 0.5
	var count := _forest_tree_count()
	var base_off := rng.randf_range(0.0, TAU)
	for i in range(count):
		var variant := TREE_VARIANTS[rng.randi() % TREE_VARIANTS.size()]
		var h := rng.randf_range(TREE_MIN_HEIGHT_INCHES, TREE_MAX_HEIGHT_INCHES) * INCHES_TO_METERS
		var tree := _make_tree(variant, trees_lib, h)
		add_child(tree)
		var r := sqrt((i + 0.5) / float(count)) * FOREST_FILL_RADIUS
		var ang := base_off + i * GOLDEN_ANGLE
		var jx := rng.randf_range(-FOREST_JITTER, FOREST_JITTER)
		var jz := rng.randf_range(-FOREST_JITTER, FOREST_JITTER)
		# _make_tree already set position.y so the trunk base sits at 0; ADD the pad top + x/z
		# (don't overwrite y, or the base would sink/float by the GLB's pivot offset).
		tree.position += Vector3(a * (r * cos(ang) + jx), base_top, b * (r * sin(ang) + jz))
		tree.rotation.y = rng.randf_range(0.0, TAU)
		tree.set_meta(MEMBER_META, self)


## Download the biome's tree GLBs, then replace the procedural members with real trees at the
## identical seeded layout. One-shot; the floor pad + collider are left untouched.
func _upgrade_forest_trees(base_top: float) -> void:
	if _tree_upgrade_started or _trees_lib == null:
		return
	_tree_upgrade_started = true
	var ok: bool = await _trees_lib.ensure_all_models(biome_prefix)
	if not ok or not is_instance_valid(self):
		return
	for child in get_children():
		if child.has_meta(MEMBER_META):
			child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_val
	_populate_forest(rng, _trees_lib, base_top)


## If this forest carries a non-grassland biome, crop a tile of that biome's battlemap and swap it
## onto the floor pad (downloading the battlemap if the table hasn't cached it). One-shot; the pad
## was built on the grassland fallback so it's never untextured. Grassland keeps its tuned tile.
func _maybe_upgrade_forest_floor() -> void:
	if _floor_upgrade_started or _biome_lib == null or not is_instance_valid(_floor_mesh):
		return
	var key: String = FOREST_FLOOR_BATTLEMAP_KEY_BY_PREFIX.get(biome_prefix, "")
	if key.is_empty():
		return  # grassland (or unknown) — keep the tuned bundled floor
	_floor_upgrade_started = true
	var path: String = _biome_lib.get_cached_path(key)
	if path.is_empty():
		path = await _biome_lib.ensure_biome(key)
	if path.is_empty() or not is_instance_valid(self) or not is_instance_valid(_floor_mesh):
		return  # unavailable / offline — keep the grassland fallback
	var crop_tex := _crop_floor_tile(path)
	if crop_tex == null:
		return
	_floor_mesh.material_override = _forest_floor_material_for_texture(crop_tex)


## Bake a tile-sized square crop of the battlemap WebP at `path` into an ImageTexture. The crop
## origin is seeded-random within an inset region, so each forest samples a different patch (no two
## pads look identical) and the anti-tiling shader hides the crop's own repetition. Seeded from
## _seed_val so every multiplayer client crops the identical patch.
func _crop_floor_tile(path: String) -> Texture2D:
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(path)) != OK:
		push_warning("TerrainGroupBase: failed to load battlemap %s" % path)
		return null
	var px_per_inch := float(img.get_width()) / BATTLEMAP_REFERENCE_WIDTH_INCHES
	var crop_px := clampi(int(round(FOREST_FLOOR_CROP_INCHES * px_per_inch)), 1, mini(img.get_width(), img.get_height()))
	var margin_x := int(img.get_width() * FOREST_FLOOR_CROP_MARGIN)
	var margin_y := int(img.get_height() * FOREST_FLOOR_CROP_MARGIN)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_val
	var ox := rng.randi_range(margin_x, maxi(margin_x, img.get_width() - crop_px - margin_x))
	var oy := rng.randi_range(margin_y, maxi(margin_y, img.get_height() - crop_px - margin_y))
	var crop := img.get_region(Rect2i(ox, oy, crop_px, crop_px))
	if crop.get_format() != Image.FORMAT_RGBA8:
		crop.convert(Image.FORMAT_RGBA8)  # WebP RGB8 can corrupt on some NVIDIA GPUs (see GPU memory)
	crop.generate_mipmaps()
	return ImageTexture.create_from_image(crop)


## The oval forest-floor pad: a thin elliptical disc (custom mesh so the floor texture tiles at
## a real-world scale via planar UVs, not one stretched image) sitting up from the table.
## Returns its top Y (where the trees stand).
func _build_forest_base() -> float:
	var a := footprint_inches.x * INCHES_TO_METERS * 0.5
	var b := footprint_inches.y * INCHES_TO_METERS * 0.5
	var t := FOREST_BASE_THICKNESS_INCHES * INCHES_TO_METERS
	var tile := FOREST_FLOOR_TILE_INCHES * INCHES_TO_METERS
	var seg := FOREST_OVAL_SEGMENTS
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(seg):
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(a * cos(a0), t, b * sin(a0))
		var p1 := Vector3(a * cos(a1), t, b * sin(a1))
		# Top fan (planar UVs from world XZ → tiles every `tile`).
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(Vector3(0, t, 0))
		st.set_uv(Vector2(p0.x / tile, p0.z / tile)); st.add_vertex(p0)
		st.set_uv(Vector2(p1.x / tile, p1.z / tile)); st.add_vertex(p1)
		# Rim down to the table, outward-facing.
		var b0 := Vector3(p0.x, 0, p0.z)
		var b1 := Vector3(p1.x, 0, p1.z)
		var nrm := Vector3(cos(a0), 0, sin(a0))
		st.set_normal(nrm)
		st.set_uv(Vector2(0, 0)); st.add_vertex(p0)
		st.set_uv(Vector2(0, 1)); st.add_vertex(b0)
		st.set_uv(Vector2(1, 1)); st.add_vertex(b1)
		st.set_uv(Vector2(0, 0)); st.add_vertex(p0)
		st.set_uv(Vector2(1, 1)); st.add_vertex(b1)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p1)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _forest_floor_material()
	add_child(mi)
	_floor_mesh = mi
	return t


## The initial floor material: every forest builds on the grassland tile; non-grassland biomes then
## async-swap to a crop of their battlemap (see _maybe_upgrade_forest_floor).
func _forest_floor_material() -> Material:
	var tex := _load_texture(FOREST_FLOOR_TEX_DEFAULT)
	if tex == null:
		return _forest_floor_fallback_material()
	return _forest_floor_material_for_texture(tex)


## Wrap a floor texture in the anti-tiling shader (it samples a second rotated tap + varies macro
## brightness, hiding the repetition on larger pads); falls back to a plain tiled material if the
## shader fails to load. Shared by the initial build and the battlemap-crop swap.
func _forest_floor_material_for_texture(tex: Texture2D) -> Material:
	var shader: Shader = load(FOREST_FLOOR_SHADER) if ResourceLoader.exists(FOREST_FLOOR_SHADER) else null
	if shader == null:
		var plain := _forest_floor_fallback_material()
		plain.albedo_texture = tex
		plain.albedo_color = Color.WHITE
		return plain
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("albedo_tex", tex)
	return mat


func _forest_floor_fallback_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = TREE_FOLIAGE_COLOR.darkened(0.4)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.texture_repeat = true                       # UVs tile the texture across the pad
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static var _tex_cache: Dictionary = {}

static func _load_texture(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex_cache[path] = tex
	return tex


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


## A tree member at the given height (metres): the R2 GLB fit to height if cached, else a
## procedural trunk + foliage cone.
func _make_tree(variant: String, trees_lib: TreesLibrary, height_m: float) -> Node3D:
	if trees_lib != null:
		var scene := trees_lib.get_model_scene(biome_prefix + variant)
		if scene != null:
			var inst := scene.instantiate() as Node3D
			_fit_height(inst, height_m)
			return inst
	var root := Node3D.new()
	var h := height_m
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
