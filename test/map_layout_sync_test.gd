extends GdUnitTestSuite
## F5 (Map editor plan, bug B4): a client editor that received the host's layout must keep every
## piece through its next _rebuild_derived() (any click rebuilds). main.gd used to write the derived
## grid_cells directly, which the rebuild then wiped.

const SCENE := preload("res://scenes/map_layout.tscn")


func _adopt(ed: Control, cells: Dictionary, walls: Array[Dictionary]) -> void:
	if ed.has_method("apply_synced_layout"):
		ed.call("apply_synced_layout", cells, walls, [], 0.0)
	else:  # pre-F5 main.gd path: derived fields written directly
		ed.grid_cells = cells
		ed.wall_segments = walls


func test_synced_layout_survives_a_rebuild() -> void:
	var ed: Control = SCENE.instantiate()
	add_child(ed)
	auto_free(ed)
	var cells := {Vector2i(4, 4): ed.TerrainType.RUINS, Vector2i(5, 4): ed.TerrainType.RUINS, Vector2i(9, 9): ed.TerrainType.FOREST}
	var walls: Array[Dictionary] = [{"edge_cell": Vector2i(4, 4), "edge_side": 0, "wall_key": "w", "length_inches": 3.0, "sub_position": 0}]
	_adopt(ed, cells, walls)
	ed._rebuild_derived()
	assert_int(ed.grid_cells.size()) \
		.override_failure_message("F5 — the client editor lost the synced terrain on its next rebuild") \
		.is_equal(3)
	assert_int(ed.wall_segments.size()).is_equal(1)


func test_synced_layout_is_replaced_by_the_next_sync_not_merged() -> void:
	var ed: Control = SCENE.instantiate()
	add_child(ed)
	auto_free(ed)
	if not ed.has_method("apply_synced_layout"):
		fail("F5 — no apply_synced_layout seam on the editor")
		return
	ed.apply_synced_layout({Vector2i(1, 1): ed.TerrainType.RUINS}, [], [], 0.0)
	ed.apply_synced_layout({Vector2i(2, 2): ed.TerrainType.FOREST}, [], [], 0.0)
	ed._rebuild_derived()
	assert_bool(ed.grid_cells.has(Vector2i(1, 1))).is_false()
	assert_bool(ed.grid_cells.has(Vector2i(2, 2))).is_true()
