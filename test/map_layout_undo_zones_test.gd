extends GdUnitTestSuite
## R5 (Map editor plan): every custom-zone vertex is an undo step; an old zone that Start Drawing kept on
## screen comes back when the first new vertex is undone.

const SCENE := preload("res://scenes/map_layout.tscn")

var _ed: Control


func before_test() -> void:
	_ed = auto_free(SCENE.instantiate())
	add_child(_ed)
	await get_tree().process_frame
	_ed.custom_zone_symmetric = false


func after_test() -> void:
	_ed = null


func test_r5_three_vertices_then_undo_leaves_two() -> void:
	_ed._on_custom_zone_start()
	for p in [Vector2(20, 30), Vector2(40, 30), Vector2(40, 50)]:
		_ed._handle_custom_zone_click(p)
	assert_int(_ed.custom_zone_vertices_p1.size()).is_equal(3)
	_ed.undo()
	assert_int(_ed.custom_zone_vertices_p1.size()).override_failure_message("R5 — Undo did not take back the last vertex").is_equal(2)
	assert_bool(_ed._custom_zone_confirm_btn.disabled).is_true()  # < 3 points again
	_ed.redo()
	assert_int(_ed.custom_zone_vertices_p1.size()).is_equal(3)
	assert_bool(_ed._custom_zone_confirm_btn.disabled).is_false()


func test_r5_undoing_the_first_new_vertex_brings_the_old_zone_back() -> void:
	_ed.custom_zone_vertices_p1.assign([Vector2(10, 30), Vector2(30, 30), Vector2(30, 50)])
	_ed._on_custom_zone_start()
	_ed._handle_custom_zone_click(Vector2(60, 30))
	assert_int(_ed.custom_zone_vertices_p1.size()).is_equal(1)
	_ed.undo()
	assert_int(_ed.custom_zone_vertices_p1.size()).override_failure_message("R5 — the old zone did not come back").is_equal(3)
	assert_bool(_ed.custom_zone_vertices_p1[0] == Vector2(10, 30)).is_true()


func test_r5_symmetric_mode_undoes_both_mirrored_lists_together() -> void:
	_ed.custom_zone_symmetric = true
	_ed._on_custom_zone_start()
	_ed._handle_custom_zone_click(Vector2(20, 30))
	_ed._handle_custom_zone_click(Vector2(40, 30))
	_ed.undo()
	assert_int(_ed.custom_zone_vertices_p1.size()).is_equal(1)
	assert_int(_ed.custom_zone_vertices_p2.size()).is_equal(1)
