extends GdUnitTestSuite
## R2 (Map editor plan): the wheel always zooms (Shift+wheel turns the piece being placed), and one muted hint
## line under the mode names the keys of the current mode with key caps.

const SCENE := preload("res://scenes/map_layout.tscn")

var _ed: Control


func before_test() -> void:
	_ed = auto_free(SCENE.instantiate())
	add_child(_ed)
	await get_tree().process_frame


func after_test() -> void:
	_ed = null


func _keys() -> Array:
	var hint := _ed.find_child("ModeHint", true, false)
	var keys: Array = []
	if hint != null:
		for c: Node in hint.get_children():
			if c is Label and (c as Label).theme_type_variation == HouseStyle.KEYCAP:
				keys.append((c as Label).text)
	return keys


func test_r2_wheel_zooms_in_place_mode_and_shift_wheel_rotates() -> void:
	_ed.editor_mode = _ed.EditorMode.PLACE_PREFAB
	var zoom0: float = _ed.zoom_level
	var rot0: int = _ed._preview_rotation
	_ed._handle_wheel(true, false, Vector2.ZERO)
	assert_float(_ed.zoom_level).override_failure_message("R2 — the wheel does not zoom in Place mode").is_greater(zoom0)
	assert_int(_ed._preview_rotation).is_equal(rot0)
	_ed._handle_wheel(true, true, Vector2.ZERO)
	assert_int(_ed._preview_rotation).is_equal((rot0 + 90) % 360)
	assert_float(_ed.zoom_level).is_greater(zoom0 - 0.0001)


func test_r2_wheel_zooms_out_in_other_modes() -> void:
	_ed.editor_mode = _ed.EditorMode.PAINT_CELLS
	_ed._handle_wheel(true, false, Vector2.ZERO)
	var z: float = _ed.zoom_level
	_ed._handle_wheel(false, false, Vector2.ZERO)
	assert_float(_ed.zoom_level).is_less(z)


func test_r2_hint_names_the_keys_of_each_mode() -> void:
	_ed.editor_mode = _ed.EditorMode.PLACE_PREFAB
	_ed._update_modular_terrain_ui()
	assert_array(_keys()).contains_exactly(["R", "F", "Shift"])
	_ed.editor_mode = _ed.EditorMode.MOVE_PIECES
	_ed._update_modular_terrain_ui()
	assert_array(_keys()).contains_exactly(["R", "F", "Del"])
	_ed.editor_mode = _ed.EditorMode.PAINT_CELLS
	_ed._update_modular_terrain_ui()
	assert_array(_keys()).is_empty()
	assert_object(_ed.find_child("ModeHint", true, false)).is_not_null()
