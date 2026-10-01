extends GdUnitTestSuite
## A7 (Map editor plan): the Objectives tab wears the house style - Deploy Objectives is a segment toggle
## (gold while deploying), Clear a ghost button, the 9" warning a danger-tone line, no HudTokens / font overrides.

const SCENE := preload("res://scenes/map_layout.tscn")

var _ed: Control


func before_test() -> void:
	_ed = auto_free(SCENE.instantiate())
	add_child(_ed)
	await get_tree().process_frame


func after_test() -> void:
	_ed = null


func _func_source(fn: String) -> String:
	var text := FileAccess.get_file_as_string("res://scripts/map_layout.gd")
	var start := text.find("func %s(" % fn)
	var end := text.find("\nfunc ", start + 1)
	return text.substr(start, (end if end >= 0 else text.length()) - start)


func test_a7_deploy_toggle_is_a_segment_and_turns_gold_while_deploying() -> void:
	var b: Button = _ed._objectives_toggle_btn
	assert_str(String(b.theme_type_variation)).is_equal(String(HouseStyle.SEGMENT))
	assert_bool(HouseStyle.is_selected(b)).is_false()
	b.button_pressed = true
	assert_bool(HouseStyle.is_selected(b)).override_failure_message("A7 — the toggle is not gold while deploying").is_true()
	assert_str(b.text).is_equal("Stop Deploying")
	b.button_pressed = false
	assert_bool(HouseStyle.is_selected(b)).is_false()
	assert_str(b.text).is_equal("Deploy Objectives")


func test_a7_clear_is_a_ghost_button_and_the_warning_a_danger_tone_at_small_or_larger() -> void:
	assert_str(String(_ed._objectives_clear_btn.theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	var w: Label = _ed._objectives_warning_label
	assert_bool(w.get_theme_color("font_color") == HouseStyle.tone_ink(HouseStyle.TONE_DANGER)).is_true()
	assert_int(w.get_theme_font_size("font_size")).is_greater_equal(HouseStyle.FONT_SMALL)


func test_a7_no_hud_tokens_or_font_overrides_in_the_objectives_builder() -> void:
	var src := _func_source("_setup_objectives_ui")
	assert_str(src).is_not_empty()
	for needle in ["HudTokens.", "add_theme_font_override", "add_theme_font_size_override", "add_theme_stylebox_override"]:
		assert_bool(src.contains(needle)).override_failure_message("A7 — _setup_objectives_ui still has %s" % needle).is_false()
