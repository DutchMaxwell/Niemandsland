extends GdUnitTestSuite
## E2E — the Settings window, row 25 of the UI inventory (uimenus step 9). Every control of today's window is
## found by the words the player reads and does what it does today: ATMOSPHERE (5 presets, War-torn, Distant
## war sounds), PARAMETERS (2 colour pickers + 12 sliders), Close, AUDIO (5 sliders), DISPLAY (UI Scale, Reduce
## Motion, Fullscreen, Move Trails, Rule Texts, Tilt-Shift, Combat Stage + beat, Movement Limit, AI Explanations),
## Privacy & data. The lighting / atmosphere controllers are stubs that record the calls; the persisted display
## settings are toggled and put back. Fullscreen and Print to Console are found but not pressed (real window /
## console side effects). test_inventory_check_names_a_removed_control proves the presence check can fail.

const PRESETS := ["Day", "Sunset", "Night", "Overcast", "Rain"]
const TOGGLES := ["War-torn (fires at ruins)", "Distant war sounds", "Calm Mode", "Reduce Motion", "Fullscreen", "Show Move Trails",
	"Show Rule Texts at the Table", "Tilt-Shift (Depth of Field)", "Combat Stage (paces the resolution)",
	"Enforce Movement Limit", "AI Explanations Stay Up", "Combat Effects"]
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
	func choose_atmosphere(n: String) -> void: applied = n   # (the panel picks through this: a pick of the player's own)
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
	GraphicsSettings.set_calm_mode(false)
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


## "Reset this page" on the pages whose settings live in GraphicsSettings: the Gameplay page goes back to the shipped
## defaults (a fresh GraphicsSettings); Audio has no reset (red on main: no reset). The changed values are put back.
func test_reset_puts_a_page_back_to_the_shipped_defaults() -> void:
	assert_bool(_panel.has_method("reset_page")).override_failure_message("no reset").is_true()
	if not _panel.has_method("reset_page"):
		return
	var fields := ["show_move_trails", "show_rule_floats", "gore_level", "combat_stage_hold_s", "enforce_movement_limit"]
	var before := {}
	for f: String in fields:
		before[f] = GraphicsSettings.get(f)
	_toggle("Show Move Trails").button_pressed = false
	_toggle("Enforce Movement Limit").button_pressed = false
	var gore := _label("Gore").get_parent().get_child(1) as OptionButton
	gore.select(2)
	gore.item_selected.emit(2)
	_panel.reset_page("Gameplay")
	var after := {}
	for f: String in fields:
		after[f] = GraphicsSettings.get(f)
		GraphicsSettings.set(f, before[f])
	GraphicsSettings.save_settings()
	assert_dict(after).is_equal({"show_move_trails": true, "show_rule_floats": true, "gore_level": 1,
		"combat_stage_hold_s": 2.5, "enforce_movement_limit": true})
	_panel.show_page("Audio")
	assert_bool(_panel._reset_button.visible).override_failure_message("Audio offers a reset").is_false()
	_panel.show_page("Gameplay")
	assert_bool(_panel._reset_button.visible).is_true()


## English only (repository rule): the Calm Mode tooltip carried a German half after " / " (red on main).
func test_the_calm_mode_tooltip_is_english_only() -> void:
	var tip := _toggle("Calm Mode").tooltip_text
	assert_bool(tip.contains(" / ")).override_failure_message("a second language in the tooltip: %s" % tip).is_false()
	assert_str(tip).is_equal("Turns down combat effects, motion and pulsing selection aids in one click.")


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


## In the menu the sheet is drawn at the menu's scale, at the table at the table's (red on main: one theme).
func test_the_modal_sheet_wears_the_menus_scale() -> void:
	var root := _panel.get_child(0) as Control
	_panel.hide()
	_panel.show()
	_panel.set_modal(true)
	assert_object(root.theme).is_same(HouseStyle.menu_theme())
	assert_int(_label("Sun Color").get_theme_font_size(&"font_size")).is_equal(HouseStyle.MENU_FONT_BODY)
	_panel.set_modal(false)
	assert_object(root.theme).is_same(HouseStyle.theme())
	assert_int(_label("Sun Color").get_theme_font_size(&"font_size")).is_equal(HouseStyle.FONT_BODY)


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


## One line of help under each setting, in the caption style, once per open (sheet 05; red on main: no help lines).
func test_settings_carry_one_line_of_help_each() -> void:
	_panel.hide()
	_panel.show()
	_panel.hide()
	_panel.show()   # twice: the lines are added once
	var help: Dictionary = _panel.get_script().get_script_constant_map().get("HELP", {})
	assert_bool(help.is_empty()).override_failure_message("no help lines").is_false()
	if help.is_empty():
		return
	for name: String in ["Fullscreen", "Calm Mode", "Combat Effects", "Gore", "UI Scale", "Master Volume"]:
		var found := _panel.find_children("*", "Label", true, false).filter(func(l: Node) -> bool: return (l as Label).text == help.get(name, "?"))
		assert_int(found.size()).override_failure_message("%s has %d help lines" % [name, found.size()]).is_equal(1)
		if found.size() == 1:
			assert_str(String((found[0] as Label).theme_type_variation)).is_equal(String(HouseStyle.CAPTION))
	var tilt := _toggle("Tilt-Shift (Depth of Field)")
	var below := tilt.get_parent().get_child(tilt.get_index() + 1) as Label
	assert_str(below.text if below != null else "").override_failure_message("the help line is not under its switch").is_equal(help["Tilt-Shift (Depth of Field)"])


## A sheet that is shown at once (the menu builds it visible, so visibility_changed never fires) still wears the house
## look on its first open (red on main: the section titles stay plain until the sheet is closed and opened again).
func test_a_sheet_shown_at_once_wears_the_house_look() -> void:
	var fresh: Node = load("res://scripts/lighting_panel.gd").new()
	add_child(fresh)
	fresh.initialize(_light)
	await get_tree().process_frame
	await get_tree().process_frame
	var title: Label = null
	for n: Node in fresh.find_children("*", "Label", true, false):
		if (n as Label).text == "PARAMETERS:":
			title = n as Label
	assert_str(String(title.theme_type_variation)).override_failure_message("the first open is not restyled").is_equal(String(HouseStyle.EYEBROW))
	fresh.queue_free()


func test_volume_sliders_set_their_bus_and_are_put_back() -> void:
	for bus: String in _panel.volume_sliders:
		var s: HSlider = _panel.volume_sliders[bus]
		var before := s.value
		s.value = before - 3.0 if before > s.min_value + 3.0 else before + 3.0
		assert_float(AudioManager.get_bus_volume(bus)).override_failure_message("%s did not reach the audio bus" % bus).is_equal_approx(s.value, 0.01)
		s.value = before


## Volumes read in per cent of the slider (0 % at the bottom, 100 % at the top); the dB value moves to the tooltip
## and the stored value stays in dB (red on main: the label reads "-6 dB").
func test_volumes_read_in_per_cent_with_the_db_in_the_tooltip() -> void:
	for bus: String in _panel.volume_sliders:
		var s: HSlider = _panel.volume_sliders[bus]
		var value_label := s.get_parent().get_child(0).get_child(1) as Label
		var before := s.value
		s.value = s.min_value
		assert_str(value_label.text).override_failure_message("%s reads %s" % [bus, value_label.text]).is_equal("0 %")
		s.value = s.max_value
		assert_str(value_label.text).is_equal("100 %")
		assert_str(value_label.tooltip_text).is_equal("%d dB" % int(s.max_value))
		s.value = before
		assert_float(AudioManager.get_bus_volume(bus)).is_equal_approx(before, 0.01)


## The wheel scrolls the settings list and never sets a value: a slider under the pointer must not take
## the wheel (red on main: 19 of 19 sliders are scrollable, so scrolling the list changed the UI scale and
## the audio settings file).
func test_no_slider_of_the_sheet_takes_the_mouse_wheel() -> void:
	var sliders := _panel.find_children("*", "HSlider", true, false)
	assert_int(sliders.size()).override_failure_message("the check found only %d sliders" % sliders.size()).is_greater_equal(19)
	var scrollable := sliders.filter(func(n: Node) -> bool: return (n as HSlider).scrollable)
	assert_int(scrollable.size()).override_failure_message("%d of %d sliders take the mouse wheel" % [scrollable.size(), sliders.size()]).is_equal(0)


func test_display_toggles_reach_graphics_settings_and_are_put_back() -> void:
	var fields := {"Reduce Motion": "reduce_motion", "Show Move Trails": "show_move_trails",
		"Show Rule Texts at the Table": "show_rule_floats", "Tilt-Shift (Depth of Field)": "tilt_shift",
		"Combat Stage (paces the resolution)": "show_combat_stage", "Enforce Movement Limit": "enforce_movement_limit",
		"AI Explanations Stay Up": "ai_explain_persistent", "Combat Effects": "show_combat_effects", "Board Mist and Steam": "show_board_mist"}
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


## Graphics > Quality: five segments in preset order; a press sets the preset, a preset set elsewhere (the in-game
## dropdown) moves the mark (red on main: no quality row). The preset is put back.
func test_the_quality_row_sets_and_follows_the_preset() -> void:
	var row := _panel.find_child("QualityRow", true, false) as HBoxContainer
	assert_object(row).override_failure_message("no quality row").is_not_null()
	if row == null:
		return
	assert_bool(_panel._page("Graphics").is_ancestor_of(row)).is_true()
	assert_array(row.get_children().map(func(b: Node) -> String: return (b as Button).text)).is_equal(["Performance", "Low", "Medium", "High", "Ultra"])
	var before: int = GraphicsSettings.current_preset
	var other: int = GraphicsSettings.QualityPreset.LOW if before != GraphicsSettings.QualityPreset.LOW else GraphicsSettings.QualityPreset.HIGH
	(row.get_child(other) as Button).pressed.emit()
	var set_by_row: int = GraphicsSettings.current_preset
	GraphicsSettings.apply_preset(before)
	var marked: bool = HouseStyle.is_selected(row.get_child(before) as Button) and not HouseStyle.is_selected(row.get_child(other) as Button)
	assert_int(set_by_row).is_equal(other)
	assert_bool(marked).override_failure_message("the row does not follow a preset set elsewhere").is_true()


## Graphics, Audio and Gameplay hold their controls (sheet 05; red on main: they are still on Lighting lab).
func test_graphics_audio_and_gameplay_hold_their_controls() -> void:
	var pages := {"Graphics": ["Tilt-Shift (Depth of Field)", "Board Mist and Steam", "Combat Effects", "Miniature Idle Motion"],
		"Audio": ["Distant war sounds"],
		"Gameplay": ["Show Move Trails", "Show Rule Texts at the Table", "Combat Stage (paces the resolution)",
			"Enforce Movement Limit", "AI Explanations Stay Up"]}
	for page: String in pages:
		for text: String in pages[page]:
			assert_bool(_panel._page(page).is_ancestor_of(_toggle(text))).override_failure_message("%s is not on %s" % [text, page]).is_true()
	assert_bool(_panel._page("Graphics").is_ancestor_of(_panel.find_child("TableFrameOption", true, false))).override_failure_message("the frame is not on Graphics").is_true()
	assert_bool(_panel._page("Gameplay").is_ancestor_of(_label("Gore"))).override_failure_message("Gore is not on Gameplay").is_true()
	for bus: String in _panel.volume_sliders:
		assert_bool(_panel._page("Audio").is_ancestor_of(_panel.volume_sliders[bus])).override_failure_message("%s volume is not on Audio" % bus).is_true()


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


func test_calm_toggle_is_a_preset_over_the_display_switches_and_is_put_back() -> void:
	var calm := _toggle("Calm Mode")
	assert_object(calm).is_not_null()
	var before := {}
	for f: String in ["show_combat_effects", "idle_motion", "reduce_motion", "tilt_shift"]:
		before[f] = GraphicsSettings.get(f)
	calm.toggled.emit(true)
	assert_bool(GraphicsSettings.calm_mode).override_failure_message("Calm does not reach GraphicsSettings").is_true()
	assert_bool(GraphicsSettings.show_combat_effects).is_false()
	assert_bool(GraphicsSettings.reduce_motion).is_true()
	assert_bool(_toggle("Combat Effects").button_pressed).override_failure_message("the forced switch must show its new state").is_false()
	calm.toggled.emit(false)
	assert_bool(GraphicsSettings.calm_mode).is_false()
	for f: String in before:
		assert_bool(GraphicsSettings.get(f)).override_failure_message("%s was not restored" % f).is_equal(before[f])


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


## Sheet 05: a rail of six pages, one page shown at a time, the sheet opening on the one that holds the
## controls (red on main: the sheet has no page rail).
func test_the_sheet_has_six_pages_and_shows_one_at_a_time() -> void:
	var rail := _panel.find_child("PageRail", true, false) as Control
	assert_object(rail).override_failure_message("the sheet has no page rail").is_not_null()
	if rail == null:
		return
	var buttons: Array = rail.get_children().filter(func(n: Node) -> bool: return n is Button)
	var names: Array = buttons.map(func(n: Node) -> String: return (n as Button).text)
	assert_array(names).is_equal(["Display", "Graphics", "Audio", "Gameplay", "Accessibility", "Lighting lab"])
	assert_bool(_panel._page("Display").visible).override_failure_message("the sheet does not open on Display").is_true()
	(buttons[5] as Button).pressed.emit()
	for p: String in names:
		assert_bool(_panel._page(p).visible).override_failure_message("page %s" % p).is_equal(p == "Lighting lab")
	assert_bool((buttons[5] as Button).button_pressed).is_true()


## Display holds Fullscreen and UI Scale, Accessibility holds Calm Mode and Reduce Motion (sheet 05; red on main:
## everything is on Lighting lab).
func test_display_and_accessibility_hold_their_controls() -> void:
	for text: String in ["Fullscreen", "Calm Mode", "Reduce Motion"]:
		var page := "Display" if text == "Fullscreen" else "Accessibility"
		var t := _toggle(text)
		assert_object(t).override_failure_message("no toggle %s" % text).is_not_null()
		if t != null:
			assert_bool(_panel._page(page).is_ancestor_of(t)).override_failure_message("%s is not on %s" % [text, page]).is_true()
	assert_bool(_panel._page("Display").is_ancestor_of(_label("UI Scale"))).override_failure_message("UI Scale is not on Display").is_true()


## In the menu the sheet is drawn at the mockup's size with a wider rail headed by the eyebrow and the title; the table's
## sheet keeps its compact form (sheet 05; red on main: 760 px and a 620 px scroll box in both).
func test_the_modal_sheet_is_drawn_at_the_mockups_size() -> void:
	var sheet := _panel.find_child("Sheet", true, false) as Control
	var rail := _panel.find_child("PageRail", true, false) as Control
	var window := _panel.get_viewport().get_visible_rect().size
	_panel.set_modal(true)
	assert_float(sheet.custom_minimum_size.x).is_equal(minf(1340.0, window.x - 128.0))
	assert_float(sheet.custom_minimum_size.y).is_equal(minf(840.0, window.y - 120.0))
	assert_float(rail.custom_minimum_size.x).is_equal(290.0)
	var head := _panel.find_child("RailHead", true, false) as Control
	assert_object(head).override_failure_message("no head over the rail").is_not_null()
	if head == null:
		return
	assert_bool(head.visible).is_true()
	var header := sheet.find_child("Header", true, false)
	assert_bool((header.get_child(0) as Control).visible).override_failure_message("the header row still carries the title").is_false()
	_panel.set_modal(false)
	assert_float(sheet.custom_minimum_size.x).is_equal(760.0)
	assert_float(rail.custom_minimum_size.x).is_equal(200.0)
	assert_bool(head.visible).is_false()
	assert_bool((header.get_child(0) as Control).visible).is_true()


## In the menu the page buttons are flat 56 px rows with an icon, 19 px text and a gold tick at the open page; the table's
## sheet keeps its segments (sheet 05; red on main: segments of 40 px, no icon, no tick).
func test_the_menus_page_buttons_are_rows_with_an_icon_and_a_tick() -> void:
	var rail := _panel.find_child("PageRail", true, false) as Control
	var buttons: Array = rail.get_children().filter(func(n: Node) -> bool: return n is Button)
	_panel.set_modal(true)
	_panel.show_page("Graphics")
	for b: Button in buttons:
		assert_float(b.custom_minimum_size.y).is_equal(56.0)
		assert_object(b.icon).override_failure_message("%s has no icon" % b.text).is_not_null()
		assert_int(b.get_theme_font_size(&"font_size")).is_equal(19)
		var tick := b.get_node_or_null("Tick") as Control
		assert_object(tick).override_failure_message("%s has no tick" % b.text).is_not_null()
		if tick != null:
			assert_bool(tick.visible).override_failure_message("tick of %s" % b.text).is_equal(b.text == "Graphics")
	var separator := _panel.find_child("LabSeparator", true, false) as Control
	assert_object(separator).override_failure_message("no rule above the Lighting lab").is_not_null()
	if separator == null:
		return
	assert_bool(separator.visible).is_true()
	_panel.set_modal(false)
	for b: Button in buttons:
		assert_float(b.custom_minimum_size.y).is_equal(float(HouseStyle.H_ACTION))
		assert_object(b.icon).is_null()
		assert_bool((b.get_node("Tick") as Control).visible).is_false()


## The menu's sheet has a footer under the pages (the note, Reset this page, a gold Close with its Esc cap) and draws its
## switches as the 46 x 26 pill; the table's sheet has neither (sheet 05; red on main: no footer, Godot's own switch).
func test_the_modal_sheet_has_a_footer_and_pill_switches() -> void:
	var footer := _panel.find_child("Footer", true, false) as Control
	assert_object(footer).override_failure_message("no footer row").is_not_null()
	if footer == null:
		return
	var close := footer.get_node("FooterClose") as Button
	assert_bool(close.visible).override_failure_message("the footer Close shows at the table").is_false()
	_panel.set_modal(true)
	assert_bool(close.visible).is_true()
	assert_float(close.size.y if close.size.y > 0.0 else close.custom_minimum_size.y).is_equal(44.0)
	assert_str((close.get_child(0) as Label).text).is_equal("Esc")
	var note := footer.get_child(0) as Label
	assert_str(note.text).is_equal("Changes apply at once and are saved.")
	assert_bool(note.visible).is_true()
	var pill := HouseStyle.menu_theme().get_icon(&"checked", &"CheckButton")
	assert_that(pill.get_size()).is_equal(Vector2(46, 26))
	assert_object(HouseStyle.menu_theme().get_icon(&"unchecked", &"CheckButton")).is_not_same(pill)
	assert_int(HouseStyle.menu_theme().get_icon(&"grabber", &"HSlider").get_width()).is_equal(20)
	_panel.show()
	close.pressed.emit()
	assert_bool(_panel.visible).override_failure_message("the footer Close did not hide the sheet").is_false()
	_panel.set_modal(false)
	assert_bool(close.visible).is_false()
	assert_bool(note.visible).is_false()


## In the menu the Graphics page is one row per setting in the order of sheet 05 - the name and its help at the left, the
## control at the right, a hairline under each; no setting leaves the page and every help line stays exactly once
## (red on main: the controls stand in a list with their help under them).
func test_the_menus_graphics_page_is_one_row_per_setting() -> void:
	_panel.set_modal(true)
	var page: Node = _panel._page("Graphics")
	var rows: Array = page.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with("Row"))
	assert_int(rows.size()).override_failure_message("rows: %d" % rows.size()).is_equal(6)
	if rows.size() != 6:
		return
	var names: Array = rows.map(func(r: Node) -> String: return String(r.name))
	assert_array(names).is_equal(["RowQuality", "RowTilt-Shift(DepthofField)", "RowBoardMistandSteam", "RowCombatEffects",
		"RowMiniatureIdleMotion", "RowTableframe"])
	for row: Control in rows:
		assert_float((row.get_child(0) as Control).custom_minimum_size.y).is_equal(78.0)
		assert_float(row.get_child(1).custom_minimum_size.y).is_equal(1.0)
	var tilt := _toggle("Tilt-Shift (Depth of Field)")
	assert_object(tilt).override_failure_message("the switch is not found by its name").is_null()   # its text moved to the row
	var found: Array = []
	for n: Node in page.find_children("*", "CheckButton", true, false):
		found.append(str(n.get_meta("row_name", "")))
	assert_array(found).contains_exactly(["Tilt-Shift (Depth of Field)", "Board Mist and Steam", "Combat Effects",
		"Miniature Idle Motion"])
	var help: Dictionary = _panel.get_script().get_script_constant_map().get("HELP", {})
	for key: String in ["Quality", "Tilt-Shift (Depth of Field)", "Board Mist and Steam", "Combat Effects",
			"Miniature Idle Motion", "TableFrameOption"]:
		var lines := page.find_children("*", "Label", true, false).filter(
			func(l: Node) -> bool: return (l as Label).text == help[key])
		assert_int(lines.size()).override_failure_message("%s has %d help lines" % [key, lines.size()]).is_equal(1)
	var frame: OptionButton = page.find_child("TableFrameOption", true, false)
	assert_str(frame.get_item_text(0)).is_equal("Today's look")
	assert_float(frame.custom_minimum_size.x).is_equal(300.0)
	assert_bool(page.find_child("QualityRow", true, false) != null).is_true()
	# Reset this page still reaches the switches whose text moved into their rows.
	var tilt_switch: CheckButton = null
	for n: Node in page.find_children("*", "CheckButton", true, false):
		if n.get_meta("row_name", "") == "Tilt-Shift (Depth of Field)":
			tilt_switch = n as CheckButton
	var tilt_before: bool = GraphicsSettings.tilt_shift
	var fresh: Object = (GraphicsSettings.get_script() as Script).new()
	var shipped: bool = fresh.get("tilt_shift")
	fresh.free()
	tilt_switch.button_pressed = not shipped
	_panel.reset_page("Graphics")
	assert_bool(GraphicsSettings.tilt_shift).override_failure_message("reset did not reach a switch in a row").is_equal(shipped)
	GraphicsSettings.tilt_shift = tilt_before
	GraphicsSettings.save_settings()
	_panel.hide()
	_panel.show()   # the restyle adds no second help line under a control that is in a row
	for key: String in ["Combat Effects"]:
		var again := page.find_children("*", "Label", true, false).filter(
			func(l: Node) -> bool: return (l as Label).text == help[key])
		assert_int(again.size()).is_equal(1)


## The Accessibility page, which holds two switches, stands as rows too (Calm Mode, Reduce Motion) with its name as an eyebrow.
func test_the_menus_accessibility_page_is_two_rows() -> void:
	_panel.set_modal(true)
	var page: Node = _panel._page("Accessibility")
	var rows: Array = page.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with("Row"))
	assert_array(rows.map(func(r: Node) -> String: return String(r.name))).is_equal(["RowCalmMode", "RowReduceMotion"])
	var names: Array = []
	for n: Node in page.find_children("*", "CheckButton", true, false):
		names.append(str(n.get_meta("row_name", "")))
	assert_array(names).contains_exactly(["Calm Mode", "Reduce Motion"])


## The Audio page stands as one row per volume - the slider and its per cent (mono, gold) at the right - and a slider still
## sets its bus and its own per-cent text.
func test_the_menus_audio_page_is_one_row_per_volume() -> void:
	_panel.set_modal(true)
	var page: Node = _panel._page("Audio")
	var rows: Array = page.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with("Row"))
	assert_int(rows.size()).override_failure_message("rows: %d" % rows.size()).is_equal(_panel.volume_sliders.size())
	var help: Dictionary = _panel.get_script().get_script_constant_map().get("HELP", {})
	for bus: String in _panel.volume_sliders:
		var slider: HSlider = _panel.volume_sliders[bus]
		assert_bool(page.is_ancestor_of(slider)).is_true()
		assert_bool(slider.get_parent().get_child(1) is Label).override_failure_message("no per cent beside the slider").is_true()
		var value_label: Label = slider.get_parent().get_child(1)
		assert_object(value_label.get_theme_font("font")).is_same(HouseStyle.mono())
		var before: float = slider.value
		slider.value = before - 1.0 if before > slider.min_value else before + 1.0
		assert_bool(value_label.text.ends_with("%")).is_true()
		slider.value = before
	for key: String in ["Master Volume", "Music Volume"]:
		var lines := page.find_children("*", "Label", true, false).filter(func(l: Node) -> bool: return (l as Label).text == help[key])
		assert_int(lines.size()).override_failure_message("%s has %d help lines" % [key, lines.size()]).is_equal(1)


## In the menu Display and Gameplay stand as rows too (step 79, the rest): the page's name as an eyebrow (no "DISPLAY:"),
## one row per setting in the page's order, a slider with its value in mono beside it, one help line each (red before:
## the old list with the help under each control).
func test_the_menus_display_and_gameplay_pages_are_one_row_per_setting() -> void:
	_panel.set_modal(true)
	var expected := {"Display": ["RowUIScale", "RowFullscreen"], "Gameplay": ["RowShowMoveTrails",
		"RowShowRuleTextsattheTable", "RowGore", "RowCombatStage(pacestheresolution)", "RowStagebeat",
		"RowEnforceMovementLimit", "RowAIExplanationsStayUp"]}
	for page_name: String in expected:
		var page: Node = _panel._page(page_name)
		var names: Array = page.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with("Row")).map(
			func(r: Node) -> String: return String(r.name)).filter(func(n: String) -> bool: return n != "RowMonitor")
		assert_array(names).override_failure_message("%s: %s" % [page_name, str(names)]).is_equal(expected[page_name])
		var colon := page.find_children("*", "Label", true, false).filter(func(l: Node) -> bool: return (l as Label).text.ends_with(":"))
		assert_array(colon).override_failure_message("%s keeps a heading with a colon" % page_name).is_empty()
	var help: Dictionary = _panel.get_script().get_script_constant_map().get("HELP", {})
	for key: String in ["UI Scale", "Fullscreen", "Gore", "Show Move Trails"]:
		var lines := _panel.find_children("*", "Label", true, false).filter(func(l: Node) -> bool: return (l as Label).text == help[key])
		assert_int(lines.size()).override_failure_message("%s has %d help lines" % [key, lines.size()]).is_equal(1)
	var beat: HSlider = null
	for n: Node in _panel._page("Gameplay").find_children("*", "HSlider", true, false):
		beat = n as HSlider
	if beat == null:
		return
	var value := beat.get_parent().get_child(1) as Label
	assert_object(value.get_theme_font("font")).is_same(HouseStyle.mono())
	var before: float = GraphicsSettings.combat_stage_hold_s
	beat.value = 6.0 if before != 6.0 else 1.0
	assert_str(value.text).is_equal("%.1fs" % beat.value)
	assert_float(GraphicsSettings.combat_stage_hold_s).is_equal_approx(beat.value, 0.01)
	beat.value = before


## Sheet 05: Quality is one joined group of 40 px segments, a dropdown in a row is 44 px high (red before: five loose
## 26 px buttons, 30 px dropdowns).
func test_the_menus_quality_is_one_group_and_dropdowns_are_44_px() -> void:
	_panel.set_modal(true)
	var row := _panel.find_child("QualityRow", true, false) as HBoxContainer
	assert_int(row.get_theme_constant(&"separation")).is_equal(0)
	assert_float((row.get_child(0) as Control).custom_minimum_size.y).is_equal(40.0)
	var frame := _panel.find_child("TableFrameOption", true, false) as Control
	assert_float(frame.custom_minimum_size.y).is_equal(44.0)


## Gap review 28.11. (sheet 05): in the menu the rail is set off - a darker column with a hairline at its right - and the
## Graphics page carries its heading "How the table looks" under the eyebrow (red before: neither).
func test_the_menus_rail_is_set_off_and_graphics_has_its_heading() -> void:
	_panel.set_modal(true)
	await get_tree().process_frame
	var column := _panel.find_child("RailColumn", true, false) as PanelContainer
	var box := column.get_theme_stylebox(&"panel") as StyleBoxFlat if column != null else null
	assert_bool(box != null and box.border_width_right >= 1 and box.bg_color.a > 0.0).override_failure_message(
		"the rail is not set off").is_true()
	var heading := _panel.find_child("PageHeading", true, false) as Label
	assert_str(heading.text if heading != null else "").is_equal("How the table looks")
	_panel.set_modal(false)
