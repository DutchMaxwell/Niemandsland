extends GdUnitTestSuite
## E2E — the Settings window, row 25 of the UI inventory (uimenus step 9). Every control of today's window is
## found by the words the player reads and does what it does today: ATMOSPHERE (5 presets, War-torn, Distant
## war sounds), PARAMETERS (2 colour pickers + 12 sliders), Close, AUDIO (5 sliders), DISPLAY (UI Scale, Reduce
## Motion, Fullscreen, Move Trails, Rule Texts, Tilt-Shift, Combat Stage + beat, Movement Limit, AI Explanations),
## Privacy & data. The lighting / atmosphere controllers are stubs that record the calls; the persisted display
## settings are toggled and put back. Fullscreen and Print to Console are found but not pressed (real window /
## console side effects). test_inventory_check_names_a_removed_control proves the presence check can fail.

const PRESETS := ["Day", "Sunset", "Night", "Overcast", "Rain"]
const TOGGLES := ["War-torn (fires at ruins)", "Distant war sounds", "Reduce Motion", "Fullscreen", "Show Move Trails",
	"Show Rule Texts at the Table", "Tilt-Shift (Depth of Field)", "Combat Stage (paces the resolution)",
	"Enforce Movement Limit", "AI Explanations Stay Up"]
const LABELS := ["ATMOSPHERE:", "PARAMETERS:", "Sun Color", "Ambient Color", "AUDIO:", "DISPLAY:", "UI Scale",
	"Master Volume", "Music Volume", "SFX Volume", "Ambience Volume", "UI Volume"]
const SLIDER_KEYS := ["sun_energy", "sun_angle_h", "sun_angle_v", "ambient_energy", "exposure", "shadow_opacity",
	"shadow_blur", "ssao_intensity", "ssr_intensity", "glow_intensity", "contrast", "saturation"]

class StubLight extends Node:
	var current_preset := {"sun_energy": 1.5, "sun_angle_h": 0.0, "sun_angle_v": 0.0, "ambient_energy": 1.0, "exposure": 1.0,
		"shadow_opacity": 0.5, "shadow_blur": 2.0, "ssao_intensity": 2.0, "ssr_intensity": 1.0, "glow_intensity": 1.0,
		"contrast": 1.0, "saturation": 1.0, "sun_color": Color.WHITE, "ambient_color": Color.WHITE}
	var calls := {}
	var printed := 0
	func set_sun_energy(v: float) -> void: calls["sun_energy"] = v
	func set_sun_angles(h: float, v: float) -> void: calls["sun_angles"] = [h, v]
	func set_ambient_energy(v: float) -> void: calls["ambient_energy"] = v
	func set_exposure(v: float) -> void: calls["exposure"] = v
	func set_shadow_opacity(v: float) -> void: calls["shadow_opacity"] = v
	func set_shadow_blur(v: float) -> void: calls["shadow_blur"] = v
	func set_ssao_intensity(v: float) -> void: calls["ssao_intensity"] = v
	func set_ssr_intensity(v: float) -> void: calls["ssr_intensity"] = v
	func set_glow_intensity(v: float) -> void: calls["glow_intensity"] = v
	func set_contrast(v: float) -> void: calls["contrast"] = v
	func set_saturation(v: float) -> void: calls["saturation"] = v
	func set_sun_color(c: Color) -> void: calls["sun_color"] = c
	func set_ambient_color(c: Color) -> void: calls["ambient_color"] = c
	func print_current_settings() -> void: printed += 1

class StubAtmosphere extends Node:
	signal atmosphere_changed(preset_name: String)
	var applied := ""
	var fires := false
	var war := false
	func get_atmosphere_names() -> Array: return PRESETS
	func apply_atmosphere(n: String) -> void: applied = n
	func is_fires_enabled() -> bool: return fires
	func set_fires_enabled(on: bool) -> void: fires = on
	func is_war_sounds_enabled() -> bool: return war
	func set_war_sounds_enabled(on: bool) -> void: war = on
	func cancel_transition() -> void: pass

var _panel: Node
var _light: StubLight
var _atm: StubAtmosphere
var _privacy: PrivacyMenu


func before_test() -> void:
	_light = StubLight.new()
	_atm = StubAtmosphere.new()
	_privacy = load("res://scenes/privacy/privacy_menu.tscn").instantiate() as PrivacyMenu
	add_child(_light)
	add_child(_atm)
	add_child(_privacy)
	_privacy.hide()
	_panel = load("res://scripts/lighting_panel.gd").new()
	add_child(_panel)
	_panel.initialize(_light)
	_panel.set_atmosphere_controller(_atm)
	_panel.set_privacy_menu(_privacy)
	await get_tree().process_frame


func after_test() -> void:
	_panel.queue_free()
	_privacy.queue_free()
	_light.queue_free()
	_atm.queue_free()


func _button(text: String) -> Button:
	for n: Node in _panel.find_children("*", "Button", true, false):
		if (n as Button).text == text and not n is CheckButton:
			return n as Button
	return null


func _toggle(text: String) -> CheckButton:
	for n: Node in _panel.find_children("*", "CheckButton", true, false):
		if (n as CheckButton).text == text:
			return n as CheckButton
	return null


func _label(text: String) -> Label:
	for n: Node in _panel.find_children("*", "Label", true, false):
		if (n as Label).text == text:
			return n as Label
	return null


func _missing() -> Array:
	var missing: Array = []
	for t: String in PRESETS + ["Close"]:
		if _button(t) == null:
			missing.append("button: %s" % t)
	for t: String in TOGGLES:
		if _toggle(t) == null:
			missing.append("toggle: %s" % t)
	for t: String in LABELS:
		if _label(t) == null:
			missing.append("label: %s" % t)
	for k: String in SLIDER_KEYS:
		if not _panel.sliders.has(k):
			missing.append("slider: %s" % k)
	for k: String in ["sun_color", "ambient_color"]:
		if not _panel.color_pickers.has(k):
			missing.append("picker: %s" % k)
	if _panel.volume_sliders.size() != 5:
		missing.append("audio sliders: %d of 5" % _panel.volume_sliders.size())
	if _button("Privacy & data") == null and _button(_privacy.localized_text("heading")) == null:
		missing.append("button: Privacy & data")
	return missing


func test_every_control_of_row_25_is_in_the_window() -> void:
	assert_array(_missing()).override_failure_message("settings controls missing: %s" % str(_missing())).is_empty()
	assert_bool(_panel.find_child("PrivacyDataButton", true, false) != null).is_true()
	if OS.is_debug_build():
		assert_object(_button("Print to Console")).is_not_null()


func test_atmosphere_presets_apply_and_the_two_toggles_reach_the_controller() -> void:
	for p: String in PRESETS:
		_button(p).pressed.emit()
		assert_str(_atm.applied).is_equal(p)
	_toggle("War-torn (fires at ruins)").toggled.emit(true)
	assert_bool(_atm.fires).is_true()
	_toggle("Distant war sounds").toggled.emit(true)
	assert_bool(_atm.war).is_true()


func test_every_parameter_slider_and_picker_reaches_the_lighting_controller() -> void:
	for k: String in SLIDER_KEYS:
		var s: HSlider = _panel.sliders[k]
		s.value = s.max_value
	for k: String in ["sun_energy", "ambient_energy", "exposure", "shadow_opacity", "shadow_blur", "ssao_intensity",
			"ssr_intensity", "glow_intensity", "contrast", "saturation"]:
		assert_bool(_light.calls.has(k)).override_failure_message("slider %s did not reach the controller" % k).is_true()
	assert_bool(_light.calls.has("sun_angles")).is_true()
	(_panel.color_pickers["sun_color"] as ColorPickerButton).color_changed.emit(Color.RED)
	(_panel.color_pickers["ambient_color"] as ColorPickerButton).color_changed.emit(Color.BLUE)
	assert_that(_light.calls["sun_color"]).is_equal(Color.RED)
	assert_that(_light.calls["ambient_color"]).is_equal(Color.BLUE)


func test_close_hides_the_window() -> void:
	_panel.show()
	_button("Close").pressed.emit()
	assert_bool(_panel.visible).is_false()


func test_escape_and_the_x_hide_the_panel() -> void:
	_panel.show()
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	_panel._unhandled_input(esc)
	assert_bool(_panel.visible).is_false()
	_panel.show()
	(_panel.find_child("CloseButton", true, false) as Button).pressed.emit()
	assert_bool(_panel.visible).is_false()


func test_panel_is_a_house_style_sheet_that_is_not_modal() -> void:
	var root := _panel.get_child(0) as Control
	assert_int(root.mouse_filter).override_failure_message("the settings sheet must not lock the table").is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool((root.get_node("Scrim") as ColorRect).visible).override_failure_message("no scrim over the table while tuning the light").is_false()
	var sheet := root.find_child("Sheet", true, false) as Control
	assert_int(sheet.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_object(root.theme).is_same(HouseStyle.theme())


func test_controls_wear_the_house_look_once_the_sheet_opens() -> void:
	_panel.hide()
	_panel.show()
	for t: String in PRESETS + ["Close"]:
		assert_str(String(_button(t).theme_type_variation)).override_failure_message("%s is not a house line" % t).is_equal(String(HouseStyle.BUTTON))
	for t: String in ["ATMOSPHERE:", "PARAMETERS:", "AUDIO:", "DISPLAY:"]:
		assert_str(String(_label(t).theme_type_variation)).override_failure_message("%s is not an eyebrow" % t).is_equal(String(HouseStyle.EYEBROW))
		assert_bool(_label(t).has_theme_font_size_override("font_size")).is_false()
	assert_str(String(_label("Sun Color").theme_type_variation)).is_equal(String(HouseStyle.BODY))
	assert_object(HouseStyle.theme().get_stylebox(&"grabber_area", &"HSlider")).is_not_null()


func test_volume_sliders_set_their_bus_and_are_put_back() -> void:
	for bus: String in _panel.volume_sliders:
		var s: HSlider = _panel.volume_sliders[bus]
		var before := s.value
		s.value = before - 3.0 if before > s.min_value + 3.0 else before + 3.0
		assert_float(AudioManager.get_bus_volume(bus)).override_failure_message("%s did not reach the audio bus" % bus).is_equal_approx(s.value, 0.01)
		s.value = before


func test_display_toggles_reach_graphics_settings_and_are_put_back() -> void:
	var fields := {"Reduce Motion": "reduce_motion", "Show Move Trails": "show_move_trails",
		"Show Rule Texts at the Table": "show_rule_floats", "Tilt-Shift (Depth of Field)": "tilt_shift",
		"Combat Stage (paces the resolution)": "show_combat_stage", "Enforce Movement Limit": "enforce_movement_limit",
		"AI Explanations Stay Up": "ai_explain_persistent"}
	for text: String in fields:
		var t := _toggle(text)
		var field: String = fields[text]
		var before: bool = GraphicsSettings.get(field)
		assert_bool(t.button_pressed).override_failure_message("%s does not show its saved state" % text).is_equal(before)
		t.toggled.emit(not before)
		assert_bool(GraphicsSettings.get(field)).override_failure_message("%s did not reach GraphicsSettings" % text).is_equal(not before)
		t.toggled.emit(before)
		assert_bool(GraphicsSettings.get(field)).is_equal(before)
	assert_bool(_toggle("Fullscreen").button_pressed).is_equal(GraphicsSettings.fullscreen)


func test_ui_scale_and_stage_beat_sliders_reach_graphics_settings_and_are_put_back() -> void:
	var scale_slider := _label("UI Scale").get_parent().get_parent().get_child(1) as HSlider
	var before_scale: float = GraphicsSettings.ui_scale
	scale_slider.value = before_scale + 0.1 if before_scale + 0.1 <= scale_slider.max_value else before_scale - 0.1
	assert_float(GraphicsSettings.ui_scale).is_equal_approx(scale_slider.value, 0.01)
	scale_slider.value = before_scale
	var beat_label: Label = null
	for n: Node in _panel.find_children("*", "Label", true, false):
		if (n as Label).text.begins_with("Stage beat:"):
			beat_label = n as Label
	assert_object(beat_label).is_not_null()
	var beat := beat_label.get_parent().get_child(0) as HSlider
	var before_beat: float = GraphicsSettings.combat_stage_hold_s
	beat.value = 6.0 if before_beat != 6.0 else 1.0
	assert_float(GraphicsSettings.combat_stage_hold_s).is_equal_approx(beat.value, 0.01)
	assert_str(beat_label.text).is_equal("Stage beat: %.1fs" % beat.value)
	beat.value = before_beat


func test_privacy_and_data_button_opens_the_privacy_panel() -> void:
	(_panel.find_child("PrivacyDataButton", true, false) as Button).pressed.emit()
	assert_bool(_privacy.visible).is_true()


func test_inventory_check_names_a_removed_control() -> void:
	assert_array(_missing()).is_empty()
	var rain := _button("Rain")
	var parent := rain.get_parent()
	parent.remove_child(rain)
	var missing := _missing()
	parent.add_child(rain)
	assert_array(missing).contains_exactly(["button: Rain"])
