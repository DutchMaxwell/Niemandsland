extends GdUnitTestSuite
## Headless regression tests for ObjectManager's core table-object lifecycle:
## spawning (miniature / terrain), network-id identity, selection, teardown, and the
## pure base-footprint / arrange-spacing / cursor helpers. The drag / box-select /
## raw-input paths need a live camera + viewport and are exercised manually; this
## suite locks down the non-input logic that carries the most refactor risk.
##
## object_manager.gd has no class_name, so _om is typed Node3D and its dynamic
## methods need explicit result types (not :=).

const ObjectManagerScript = preload("res://scripts/object_manager.gd")

var _om: Node3D


func before_test() -> void:
	# Added to the tree so _ready runs and spawn_*'s add_child() has a valid parent.
	# No NetworkManager sibling exists here, so broadcasts no-op (we also pass false).
	_om = auto_free(ObjectManagerScript.new())
	add_child(_om)


func _unit_node(props: Dictionary) -> Node3D:
	var node: Node3D = auto_free(Node3D.new())
	add_child(node)
	var unit := GameUnit.new()
	unit.unit_properties = props
	node.set_meta("game_unit", unit)
	return node


# ===== Spawning + network-id identity =====

func test_spawn_miniature_adds_grouped_child_with_network_id() -> void:
	var m: Node3D = _om.spawn_miniature(Vector3(0.1, 0, 0.2), false)
	assert_that(m).is_not_null()
	assert_bool(m.is_in_group("selectable")).is_true()
	assert_bool(m.is_in_group("miniature")).is_true()
	assert_bool(m.has_meta("network_id")).is_true()
	assert_bool(m.get_parent() == _om).is_true()


func test_spawn_miniature_assigns_unique_ids_and_names() -> void:
	var a: Node3D = _om.spawn_miniature(Vector3.ZERO, false)
	var b: Node3D = _om.spawn_miniature(Vector3.ZERO, false)
	assert_int(int(a.get_meta("network_id"))).is_not_equal(int(b.get_meta("network_id")))
	assert_str(a.name).is_not_equal(b.name)


func test_spawn_miniature_honours_explicit_network_id() -> void:
	var m: Node3D = _om.spawn_miniature(Vector3.ZERO, false, 42)
	assert_int(int(m.get_meta("network_id"))).is_equal(42)


func test_spawn_terrain_is_terrain_grouped_with_offset_id() -> void:
	var t: Node3D = _om.spawn_terrain(Vector3.ZERO, false)
	assert_bool(t.is_in_group("terrain")).is_true()
	assert_bool(t.is_in_group("selectable")).is_true()
	# Auto terrain ids are offset (+10000) so they never collide with miniature ids.
	assert_int(int(t.get_meta("network_id"))).is_greater(9999)


func test_find_by_network_id() -> void:
	var m: Node3D = _om.spawn_miniature(Vector3.ZERO, false, 7)
	assert_bool(_om.find_by_network_id(7) == m).is_true()
	assert_that(_om.find_by_network_id(-1)).is_null()
	assert_that(_om.find_by_network_id(9999)).is_null()


# ===== Selection =====

func test_select_then_deselect() -> void:
	var a: Node3D = _om.spawn_miniature(Vector3.ZERO, false)
	var b: Node3D = _om.spawn_miniature(Vector3(0.05, 0, 0), false)
	_om.select_objects([a, b])
	assert_int(_om.get_selected_objects().size()).is_equal(2)
	_om.deselect_all()
	assert_int(_om.get_selected_objects().size()).is_equal(0)


func test_select_ignores_invalid_entries() -> void:
	var a: Node3D = _om.spawn_miniature(Vector3.ZERO, false)
	_om.select_objects([a, null])
	assert_int(_om.get_selected_objects().size()).is_equal(1)


func test_select_emits_selection_changed() -> void:
	var a: Node3D = _om.spawn_miniature(Vector3.ZERO, false)
	var seen := [0]
	_om.selection_changed.connect(func(_objs): seen[0] += 1)
	_om.select_objects([a])
	assert_int(seen[0]).is_greater(0)


# ===== Teardown =====

func test_clear_all_objects_resets_state() -> void:
	_om.spawn_miniature(Vector3.ZERO, false)
	_om.spawn_miniature(Vector3.ZERO, false)
	var a: Node3D = _om.spawn_miniature(Vector3.ZERO, false)
	_om.select_objects([a])
	_om.clear_all_objects(false)
	assert_int(_om.get_selected_objects().size()).is_equal(0)
	# queue_free() is deferred — children clear out on the next frame.
	await get_tree().process_frame
	assert_int(_om.get_child_count()).is_equal(0)


# ===== Pure helpers: base footprint / arrange spacing / cursor =====

func test_base_footprint_round() -> void:
	var fp: Vector2 = _om._base_footprint(_unit_node({"base_size_round": 40}))
	assert_float(fp.x).is_equal_approx(0.040, 0.0001)
	assert_float(fp.y).is_equal_approx(0.040, 0.0001)


func test_base_footprint_oval_uses_both_axes() -> void:
	var fp: Vector2 = _om._base_footprint(_unit_node({
		"base_is_oval": true, "base_width_mm": 25, "base_depth_mm": 50,
	}))
	assert_float(fp.x).is_equal_approx(0.025, 0.0001)
	assert_float(fp.y).is_equal_approx(0.050, 0.0001)


func test_base_footprint_defaults_without_unit() -> void:
	var node: Node3D = auto_free(Node3D.new())
	add_child(node)
	var fp: Vector2 = _om._base_footprint(node)
	assert_float(fp.x).is_equal_approx(0.032, 0.0001)
	assert_float(fp.y).is_equal_approx(0.032, 0.0001)


func test_arrange_spacing_empty_returns_default() -> void:
	var s: Vector2 = _om._arrange_spacing([])
	assert_float(s.x).is_equal_approx(0.04, 0.0001)
	assert_float(s.y).is_equal_approx(0.04, 0.0001)


func test_cursor_table_position_without_camera_is_zero() -> void:
	# With no active Camera3D in the test viewport the helper must fall back to
	# Vector3.ZERO rather than crash.
	assert_bool(_om.get_cursor_table_position() == Vector3.ZERO).is_true()
