extends GdUnitTestSuite
## E2E inventory of the Map Layout editor (row 42 of the UI inventory; Map editor plan step A0). Every
## control of today's editor is found by its text and does what it does today, so the restyle steps
## (A1-A13) can prove they changed the look and not the behaviour. Controls are driven by signal/method,
## not by pixel coordinates. test_inventory_check_names_a_removed_control proves the presence check can
## fail; the chrome tests are added WITH each restyle step (red on main).

const SCENE := preload("res://scenes/map_layout.tscn")

var _ed: Control
var _closed := false


func before_test() -> void:
	_ed = auto_free(SCENE.instantiate())
	add_child(_ed)
	_closed = false
	_ed.layout_closed.connect(func(): _closed = true)
	await _frames(2)


func after_test() -> void:
	_ed = null


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _buttons() -> Array[BaseButton]:
	var out: Array[BaseButton] = []
	for n: Node in _ed.find_children("*", "BaseButton", true, false):
		out.append(n as BaseButton)
	return out


## First control whose text equals `text` (optionally only inside `scope`).
func _by_text(text: String, scope: Node = null) -> BaseButton:
	var root: Node = scope if scope != null else _ed
	for n: Node in root.find_children("*", "BaseButton", true, false):
		var b := n as BaseButton
		var t: String = b.text if "text" in b else ""
		if t == text:
			return b
	return null


func _missing(names: Array) -> Array:
	var missing: Array = []
	for t: String in names:
		if _by_text(t) == null:
			missing.append(t)
	return missing


func _tab_body(title: String) -> Control:
	return _ed.find_child("Tab" + title, true, false) as Control


func _tab_button(title: String) -> Button:
	return _ed.find_child("Tab%sButton" % title, true, false) as Button


# ===== presence =====

func test_every_control_of_the_editor_is_present() -> void:
	var missing := _missing(["Save", "Load", "Clear All", "Close", "Ruins", "Forest", "Container",
		"Dangerous", "None", "↶ Undo", "↷ Redo", "Point Symmetry (Mirror)", "Auto-Generate Layout",
		"Deploy Objectives", "Show in Preview", "Symmetric (point-mirrored)", "Start Drawing", "Confirm"])
	assert_array(missing).override_failure_message("controls missing from the editor: %s" % [missing]).is_empty()
	assert_object(_ed.find_child("EditorTabs", true, false)).is_not_null()
	assert_str(_ed._editor_mode_btn.text).starts_with("Mode: ")
	assert_object(_ed._prefab_option_btn).is_not_null()
	assert_object(_ed._wall_option_btn).is_not_null()
	assert_object(_ed.rotation_slider).is_not_null()
	assert_object(_ed.deployment_type_option).is_not_null()


func test_inventory_check_names_a_removed_control() -> void:
	# RED proof: a control that is gone must be reported by the same check.
	_by_text("Auto-Generate Layout").queue_free()
	await _frames(2)
	assert_array(_missing(["Auto-Generate Layout"])).contains_exactly(["Auto-Generate Layout"])


func test_tabs_are_named_and_switch_their_bodies() -> void:
	assert_bool(_tab_body("Terrain").visible).is_true()
	assert_bool(_tab_body("Objectives").visible).is_false()
	assert_bool(_tab_body("Deployment").visible).is_false()
	_tab_button("Objectives").pressed.emit()
	assert_bool(_tab_body("Objectives").visible).is_true()
	assert_bool(_tab_body("Terrain").visible).is_false()
	_tab_button("Deployment").pressed.emit()
	assert_bool(_tab_body("Deployment").visible).is_true()
	assert_bool(_tab_body("Objectives").visible).is_false()
	assert_str(_tab_button("Deployment").text).is_equal("Deployment")
	assert_str(_tab_button("Terrain").text).is_equal("Terrain")
	assert_str(_tab_button("Objectives").text).is_equal("Objectives")


# ===== header =====

func test_save_and_load_open_their_dialogs_and_close_emits() -> void:
	_by_text("Save").pressed.emit()
	assert_bool(_ed.save_file_dialog.visible).is_true()
	_ed.save_file_dialog.hide()
	_by_text("Load").pressed.emit()
	assert_bool(_ed.load_file_dialog.visible).is_true()
	_ed.load_file_dialog.hide()
	_by_text("Close").pressed.emit()
	assert_bool(_closed).is_true()


func test_clear_all_clears_pieces_cells_and_walls_and_undo_brings_them_back() -> void:
	_ed.place_prefab(TerrainPrefabs.keys()[0], Vector2i(10, 10), 0, false, false)
	_ed.free_cells[Vector2i(2, 2)] = _ed.TerrainType.FOREST
	var before: int = _ed.placed_pieces.size()
	assert_int(before).is_greater(0)
	_by_text("Clear All").pressed.emit()
	assert_int(_ed.placed_pieces.size()).is_equal(0)
	assert_int(_ed.free_cells.size()).is_equal(0)
	_ed.undo()
	assert_int(_ed.placed_pieces.size()).is_equal(before)


# ===== terrain tab =====

func test_terrain_type_buttons_select_the_type() -> void:
	for pair: Array in [["Ruins", _ed.TerrainType.RUINS], ["Forest", _ed.TerrainType.FOREST],
			["Container", _ed.TerrainType.CONTAINER], ["Dangerous", _ed.TerrainType.DANGEROUS],
			["None", _ed.TerrainType.NONE]]:
		var b := _by_text(pair[0])
		b.button_pressed = true
		b.pressed.emit()
		assert_int(_ed.selected_terrain_type).is_equal(pair[1])


func test_mode_button_cycles_paint_walls_place_move_paint() -> void:
	var seen: Array = [_ed.editor_mode]
	for _i in 4:
		_ed._editor_mode_btn.pressed.emit()
		seen.append(_ed.editor_mode)
	assert_array(seen).contains_exactly([_ed.EditorMode.PAINT_CELLS, _ed.EditorMode.PLACE_WALLS,
		_ed.EditorMode.PLACE_PREFAB, _ed.EditorMode.MOVE_PIECES, _ed.EditorMode.PAINT_CELLS])
	assert_str(_ed._editor_mode_btn.text).is_equal("Mode: Paint Cells")


func test_mode_button_text_names_the_keys() -> void:
	_ed._editor_mode_btn.pressed.emit()
	assert_str(_ed._editor_mode_btn.text).is_equal("Mode: Place Walls")
	_ed._editor_mode_btn.pressed.emit()
	assert_str(_ed._editor_mode_btn.text).contains("R rotate").contains("F flip")
	_ed._editor_mode_btn.pressed.emit()
	assert_str(_ed._editor_mode_btn.text).contains("Del")


func test_prefab_dropdown_selects_a_piece_and_switches_to_place_mode() -> void:
	assert_int(_ed._prefab_option_btn.item_count).is_equal(TerrainPrefabs.keys().size())
	_ed._prefab_option_btn.item_selected.emit(1)
	assert_str(_ed.selected_prefab_key).is_equal(TerrainPrefabs.keys()[1])
	assert_int(_ed.editor_mode).is_equal(_ed.EditorMode.PLACE_PREFAB)


func test_undo_redo_enablement_follows_the_stacks() -> void:
	var undo_btn := _by_text("↶ Undo")
	var redo_btn := _by_text("↷ Redo")
	assert_bool(undo_btn.disabled).is_true()
	assert_bool(redo_btn.disabled).is_true()
	_ed.place_prefab(TerrainPrefabs.keys()[0], Vector2i(10, 10), 0, false, false)
	assert_bool(undo_btn.disabled).is_false()
	undo_btn.pressed.emit()
	assert_bool(undo_btn.disabled).is_true()
	assert_bool(redo_btn.disabled).is_false()
	redo_btn.pressed.emit()
	assert_int(_ed.placed_pieces.size()).is_equal(1)


func test_rotation_slider_sets_rotation_and_label() -> void:
	assert_str(_ed.rotation_label.text).is_equal("Rotation: 0°")
	_ed.rotation_slider.value = 30
	assert_float(_ed.grid_rotation_degrees).is_equal(30.0)
	assert_str(_ed.rotation_label.text).is_equal("Grid Rotation: 30°")


func test_point_symmetry_checkbox_toggles_the_flag() -> void:
	var cb := _by_text("Point Symmetry (Mirror)") as CheckBox
	cb.button_pressed = true
	assert_bool(_ed.point_symmetry_enabled).is_true()
	cb.button_pressed = false
	assert_bool(_ed.point_symmetry_enabled).is_false()


func test_auto_generate_makes_pieces() -> void:
	assert_int(_ed.placed_pieces.size()).is_equal(0)
	_by_text("Auto-Generate Layout").pressed.emit()
	assert_int(_ed.placed_pieces.size()).is_greater(0)


func test_stats_and_guideline_texts_keep_their_headings() -> void:
	assert_str(_ed.recommendations_label.text).starts_with("OPR Terrain Guidelines:")
	assert_str(_ed.recommendations_label.text).contains("Extended Guidelines:")
	assert_str(_ed.recommendations_label.text).contains("terrain pieces (have: ")
	assert_str(_ed.stats_label.text).is_not_empty()


# ===== objectives tab =====

func test_objectives_toggle_flips_its_text_and_the_editing_flag() -> void:
	var b := _by_text("Deploy Objectives")
	b.button_pressed = true
	assert_bool(_ed.objectives_editing).is_true()
	assert_str(b.text).is_equal("Stop Deploying")
	assert_int(_ed.selected_terrain_type).is_equal(_ed.TerrainType.NONE)
	b.button_pressed = false
	assert_bool(_ed.objectives_editing).is_false()
	assert_str(b.text).is_equal("Deploy Objectives")


func test_objectives_clear_empties_the_list_and_says_so() -> void:
	_ed.mission_objectives.assign([Vector2(20, 20), Vector2(50, 30)])
	_ed._update_objectives_status()
	assert_str(_ed._objectives_status_label.text).is_equal("2 objectives placed")
	_ed._objectives_clear_btn.pressed.emit()
	assert_int(_ed.mission_objectives.size()).is_equal(0)
	assert_str(_ed._objectives_status_label.text).is_equal("No objectives placed")


# ===== deployment tab =====

func test_deployment_dropdown_has_three_types_and_custom_shows_the_zone_panel() -> void:
	var o: OptionButton = _ed.deployment_type_option
	var items: Array = []
	for i in o.item_count:
		items.append(o.get_item_text(i))
	assert_array(items).contains_exactly(["None", "Front Line (12\")", "Custom Zones"])
	assert_bool(_ed._custom_zone_panel.visible).is_false()
	o.item_selected.emit(2)
	assert_bool(_ed._custom_zone_panel.visible).is_true()
	assert_bool(_ed.show_deployment_zones).is_true()
	o.item_selected.emit(0)
	assert_bool(_ed.show_deployment_zones).is_false()


func test_show_in_preview_checkbox_sets_the_flag() -> void:
	var cb := _by_text("Show in Preview") as CheckBox
	cb.button_pressed = true
	assert_bool(_ed.show_deployment_zones).is_true()


func test_custom_zone_start_confirm_clear_state_machine() -> void:
	_ed.deployment_type_option.item_selected.emit(2)
	var start := _by_text("Start Drawing")
	var confirm := _by_text("Confirm")
	var clear := _by_text("Clear", _ed._custom_zone_panel)
	assert_bool(confirm.disabled).is_true()
	start.pressed.emit()
	assert_bool(_ed.custom_zone_editing).is_true()
	assert_bool(start.disabled).is_true()
	for p in [Vector2(10, 10), Vector2(20, 10), Vector2(20, 20)]:
		_ed._handle_custom_zone_click(p)
	assert_bool(confirm.disabled).is_false()
	confirm.pressed.emit()
	assert_bool(_ed.custom_zone_editing).is_false()
	assert_str(_ed._custom_zone_status_label.text).is_equal("Custom zones defined!")
	assert_bool(start.disabled).is_false()
	clear.pressed.emit()
	assert_int(_ed.custom_zone_vertices_p1.size()).is_equal(0)
	assert_str(_ed._custom_zone_status_label.text).is_equal("Click grid to add zone vertices")
