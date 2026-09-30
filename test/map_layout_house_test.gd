extends GdUnitTestSuite
## Chrome tests for the Map editor restyle (Map editor plan A2-A13): the editor wears the HouseStyle
## theme and variants instead of HudTokens / theme overrides. Added WITH each restyle step, red on main.
## Behaviour is pinned separately by test/e2e/e2e_map_editor_inventory_test.gd.

const SCENE := preload("res://scenes/map_layout.tscn")
const SCENE_PATH := "res://scenes/map_layout.tscn"

var _ed: Control


func before_test() -> void:
	_ed = auto_free(SCENE.instantiate())
	add_child(_ed)
	await get_tree().process_frame


func after_test() -> void:
	_ed = null


## The text of one scene node block (from its [node name="X"...] line to the next [node).
func _scene_block(node_name: String) -> String:
	var text := FileAccess.get_file_as_string(SCENE_PATH)
	var start := text.find('[node name="%s"' % node_name)
	if start < 0:
		return ""
	var end := text.find("\n[node ", start + 1)
	return text.substr(start, (end if end >= 0 else text.length()) - start)


func _variation(path: String) -> StringName:
	return (_ed.get_node(path) as Control).theme_type_variation


# ===== A2: root + header =====

func test_a2_root_wears_the_house_theme() -> void:
	assert_bool(_ed.theme == HouseStyle.theme()) \
		.override_failure_message("A2 — the editor root does not carry HouseStyle.theme()").is_true()


func test_a2_header_buttons_and_title_use_house_variants() -> void:
	assert_str(String(_variation("%SaveButton"))).is_equal(String(HouseStyle.PRIMARY))
	assert_str(String(_variation("%LoadButton"))).is_equal(String(HouseStyle.BUTTON))
	assert_str(String(_variation("%ClearButton"))).is_equal(String(HouseStyle.DANGER_BUTTON))
	assert_str(String(_variation("%CloseButton"))).is_equal(String(HouseStyle.ICON))
	assert_str(String(_variation("MarginContainer/VBox/Header/Title"))).is_equal(String(HouseStyle.EYEBROW))


func test_a2_no_hud_frame_or_accent_line_left() -> void:
	assert_object(_ed.find_child("HeaderAccentLine", true, false)).is_null()
	for n: Node in _ed.find_children("*", "", true, false):
		assert_bool(n.get_script() != null and str(n.get_script().resource_path).ends_with("hud_frame.gd")) \
			.override_failure_message("A2 — a HudFrame bracket is still on %s" % n.get_path()).is_false()


func test_a2_panels_use_the_house_panel_variant_not_scene_styleboxes() -> void:
	for p in ["MarginContainer/VBox/MainContent/LeftPanelContainer", "MarginContainer/VBox/MainContent/GridPanel"]:
		assert_str(String(_variation(p))).is_equal(String(HouseStyle.PANEL_VARIANT))
	assert_str(FileAccess.get_file_as_string(SCENE_PATH)).not_contains("StyleBoxFlat_")


func test_a2_header_block_of_the_scene_has_no_theme_overrides() -> void:
	for n in ["Header", "Title", "SaveButton", "LoadButton", "ClearButton", "CloseButton"]:
		assert_str(_scene_block(n)) \
			.override_failure_message("A2 — %s still carries theme_override_ in the scene" % n) \
			.not_contains("theme_override_")


# ===== A3: tabs = three segment buttons =====

func _tab_btn(n: String) -> Button:
	return _ed.find_child(n, true, false) as Button


func _selected_tabs(names: Array) -> Array:
	return names.filter(func(n): return _tab_btn(n) != null and HouseStyle.is_selected(_tab_btn(n)))


func test_a3_tabs_are_three_segment_buttons_with_exactly_one_selected() -> void:
	var names := ["TabTerrainButton", "TabObjectivesButton", "TabDeploymentButton"]
	for n in names:
		var b := _tab_btn(n)
		assert_object(b).override_failure_message("A3 — %s missing" % n).is_not_null()
		if b != null:
			assert_str(String(b.theme_type_variation).trim_suffix(HouseStyle.SELECTED_SUFFIX)).is_equal(String(HouseStyle.SEGMENT))
	assert_array(_selected_tabs(names)).contains_exactly(["TabTerrainButton"])
	if _tab_btn("TabDeploymentButton") != null:
		_tab_btn("TabDeploymentButton").pressed.emit()
	assert_array(_selected_tabs(names)).contains_exactly(["TabDeploymentButton"])


func test_a3_no_godot_tab_container_left_in_the_editor() -> void:
	assert_array(_ed.find_children("*", "TabContainer", true, false)).is_empty()
