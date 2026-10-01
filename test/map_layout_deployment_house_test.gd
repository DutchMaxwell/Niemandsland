extends GdUnitTestSuite
## A8 (Map editor plan): the Deployment tab wears the house style - the zone type dropdown in a captioned
## row, Start Drawing the one primary action, Confirm / Clear ghost buttons, no HudTokens / colour overrides.

const SCENE := preload("res://scenes/map_layout.tscn")

var _ed: Control


func before_test() -> void:
	_ed = auto_free(SCENE.instantiate())
	add_child(_ed)
	await get_tree().process_frame


func after_test() -> void:
	_ed = null


func _scene_block(node_name: String) -> String:
	var text := FileAccess.get_file_as_string("res://scenes/map_layout.tscn")
	var start := text.find('[node name="%s"' % node_name)
	var end := text.find("\n[node ", start + 1)
	return text.substr(start, (end if end >= 0 else text.length()) - start)


func test_a8_zone_type_dropdown_sits_in_a_captioned_row() -> void:
	var row: Node = _ed.deployment_type_option.get_parent()
	assert_bool(row is HBoxContainer and row.get_child(0) is Label and row.get_child(1) == _ed.deployment_type_option) \
		.override_failure_message("A8 — the zone type dropdown is not inside a HouseStyle.field_row").is_true()
	assert_object(_ed.find_child("DeploymentTypeRow", true, false)).is_not_null()
	# and that row really lives in the Deployment tab body (it moved with the tab)
	var in_tab := false
	for tab_name in ["TabAufstellung", "TabDeployment"]:
		var tab := _ed.find_child(tab_name, true, false)
		in_tab = in_tab or (tab != null and tab.is_ancestor_of(row))
	assert_bool(in_tab).is_true()


func test_a8_zone_buttons_use_house_variants() -> void:
	assert_str(String(_ed._custom_zone_start_btn.theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
	assert_str(String(_ed._custom_zone_confirm_btn.theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	assert_str(String(_ed._custom_zone_clear_btn.theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	assert_str(String(_ed.find_child("DeploymentLabel", true, false).theme_type_variation)).is_equal(String(HouseStyle.EYEBROW))


func test_a8_no_paint_overrides_on_the_deployment_controls() -> void:
	for c: Control in [_ed.deployment_check, _ed.deployment_type_option, _ed._custom_zone_symmetric_check]:
		assert_bool(c.has_theme_color_override("font_color")) \
			.override_failure_message("A8 — %s still has a font_color override" % c.name).is_false()
	for n in ["DeploymentLabel", "DeploymentTypeOption", "DeploymentCheck", "ObjectivesCheck"]:
		assert_str(_scene_block(n)).override_failure_message("A8 — %s has scene overrides" % n).not_contains("theme_override_")
	var text := FileAccess.get_file_as_string("res://scripts/map_layout.gd")
	var start := text.find("func _setup_custom_zone_ui(")
	var src := text.substr(start, text.find("\nfunc ", start + 1) - start)
	assert_bool(src.contains("HudTokens.")).is_false()
