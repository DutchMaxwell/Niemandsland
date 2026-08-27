extends GdUnitTestSuite
## NML-1088: the ruin walls' and corner posts' COLLISION geometry follows the RULE
## constants (0.25" wall thickness, 0.25" corner), never the shell art (0.4" shells,
## 0.6" posts). The art branch is chosen by _ruin_panels_ready(), i.e. by whether the
## async panel download already filled user://ruins_cache — so an art-sized collider
## made the AI's deployment probe read a different table on a cold box than on a warm
## one (same seed, different deployment). The MESH still gets the fat look.

const OverlayScript = preload("res://scripts/terrain_overlay.gd")

const _RULE_WALL_M := OverlayScript.WALL_THICKNESS_INCHES * OverlayScript.INCHES_TO_METERS
const _RULE_CORNER_M := OverlayScript.CORNER_SIZE_INCHES * OverlayScript.INCHES_TO_METERS
const _TABLE := Vector2(6.0, 4.0)


## A RuinsLibrary whose "is the panel set cached?" answer is scripted and which never
## hands out a texture, so the materials take their bundled fallback (no network, no
## cache, no tree).
class StubRuins extends RuinsLibrary:
	var cached := false

	func all_panels_cached(_theme_prefix: String = "") -> bool:
		return cached

	func get_texture(_panel: String) -> Texture2D:
		return null


func _overlay(panels_cached: bool) -> Node3D:
	# Never added to the tree: _ready() would build a real RuinsLibrary + downloader.
	var overlay: Node3D = auto_free(OverlayScript.new())
	var lib := StubRuins.new()
	lib.cached = panels_cached
	overlay._ruins_library = lib
	auto_free(lib)
	assert_bool(overlay._ruin_panels_ready()).is_equal(panels_cached)
	return overlay


func _box_extents(body: Node) -> Vector3:
	for child in body.get_children():
		if child is CollisionShape3D:
			return ((child as CollisionShape3D).shape as BoxShape3D).size
	return Vector3.ZERO


func _shell_wall(panels_cached: bool) -> StaticBody3D:
	var seg := {"edge_cell": Vector2i(4, 4), "edge_side": 0, "role": "full", "length_inches": 3.0}
	var body: StaticBody3D = _overlay(panels_cached)._create_shell_wall(seg, 3.0, false, false)
	auto_free(body)
	return body


## The corner post is only built inside the layout loop; feed it two perpendicular
## segments sharing the grid's centre point (always on the table).
func _corner_post(panels_cached: bool) -> Node3D:
	var overlay := _overlay(panels_cached)
	var dims: Vector2i = overlay._calculate_grid_dims(_TABLE)
	var cell := OverlayScript.GRID_SIZE_INCHES * OverlayScript.INCHES_TO_METERS
	var corner_cell := Vector2i(dims.x / 2, dims.y / 2)
	var segments := [
		{"edge_cell": corner_cell, "edge_side": 0, "wall_key": "n", "length_inches": 3.0},
		{"edge_cell": corner_cell, "edge_side": 3, "wall_key": "w", "length_inches": 3.0},
	]
	overlay._add_wall_corner_pieces(segments, dims, cell, 0.0, 0.0, _TABLE)
	assert_int(overlay._wall_instances.size()).is_equal(1)
	return overlay._wall_instances[0]


func test_wall_collider_thickness_is_the_rule_constant_with_panels_cached() -> void:
	assert_float(_box_extents(_shell_wall(true)).z).is_equal_approx(_RULE_WALL_M, 1e-9)


func test_wall_collider_thickness_is_the_rule_constant_without_panels() -> void:
	# The fallback branch never sees _create_shell_wall; check the box wall it builds.
	var body: StaticBody3D = _overlay(false)._create_procedural_wall(3.0, OverlayScript.WALL_HEIGHT_INCHES)
	auto_free(body)
	assert_float(_box_extents(body).z).is_equal_approx(_RULE_WALL_M, 1e-9)


func test_wall_collider_is_cache_independent() -> void:
	# The whole point: update_wall_models picks the shell body when the panels are cached
	# and the procedural box when they are not — both must block the SAME volume.
	var fallback: StaticBody3D = _overlay(false)._create_procedural_wall(3.0, OverlayScript.WALL_HEIGHT_INCHES)
	auto_free(fallback)
	assert_vector(_box_extents(_shell_wall(true))).is_equal(_box_extents(fallback))


func test_corner_post_collider_is_cache_independent_and_rule_sized() -> void:
	var warm := _box_extents(_corner_post(true))
	var cold := _box_extents(_corner_post(false))
	assert_vector(warm).is_equal(cold)
	assert_float(warm.x).is_equal_approx(_RULE_CORNER_M, 1e-9)
	assert_float(warm.z).is_equal_approx(_RULE_CORNER_M, 1e-9)


func test_shell_wall_mesh_still_wears_the_fat_art_depth() -> void:
	# The art must NOT shrink with the collider: the two masonry quads still sit on the
	# 0.4" shell faces, so the fix is invisible on the table.
	var half_art := OverlayScript.RUIN_SHELL_THICKNESS_INCHES * OverlayScript.INCHES_TO_METERS / 2.0
	var body: StaticBody3D = _shell_wall(true)
	var front := 0.0
	var back := 0.0
	for child in body.get_children():
		if child is MeshInstance3D:
			front = maxf(front, (child as MeshInstance3D).position.z)
			back = minf(back, (child as MeshInstance3D).position.z)
	assert_float(front).is_equal_approx(half_art, 1e-6)
	assert_float(back).is_equal_approx(-half_art, 1e-6)
	# ...and the collider is thinner than the art it hides inside.
	assert_bool(_box_extents(body).z < half_art * 2.0).is_true()
