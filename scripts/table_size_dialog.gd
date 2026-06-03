extends Window
class_name TableSizeDialog
## Modal shown ONCE at game start to choose the table size. Afterwards the size is
## locked (changing it would wipe the built layout), so the in-game size panel is
## hidden. Emits `size_chosen` exactly once; closing defaults to the standard 6×4.

signal size_chosen(size_feet: Vector2)

const FEET_4X4 := Vector2(4, 4)
const FEET_6X4 := Vector2(6, 4)
const INCHES_TO_FEET := 1.0 / 12.0
const CM_TO_FEET := 1.0 / 30.48
const DEFAULT_SIZE := Vector2(6, 4)

var _unit_option: OptionButton
var _width_input: SpinBox
var _length_input: SpinBox
var _emitted := false


func _ready() -> void:
	title = "Choose Table Size"
	theme = ThemeManager.get_current_theme()
	UiPolish.keep_window_reachable(self, Vector2i(460, 520))  # never larger than the viewport
	unresizable = true
	exclusive = true
	borderless = true  # we draw our own tactical chrome (no gray Godot title bar)
	close_requested.connect(_on_close)
	visibility_changed.connect(func() -> void:
		if visible:
			UiPolish.grab_first_focus.call_deferred(self))
	_build_ui()


func _build_ui() -> void:
	# Tactical background panel (deep-navy glass + hairline + shadow) + corner brackets.
	var bg_panel := PanelContainer.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_panel.add_theme_stylebox_override("panel", HudTokens.panel_style())
	add_child(bg_panel)

	var margin := MarginContainer.new()
	UiPolish.set_dialog_margins(margin)
	bg_panel.add_child(margin)

	bg_panel.add_child(HudFrame.new())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UiPolish.SECTION_SEP)
	margin.add_child(vbox)

	vbox.add_child(HudTokens.header("TABLE SIZE", "/// GRID"))

	var info := Label.new()
	info.text = "Locked once chosen — switching later discards the layout you've built."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_override("font", HudTokens.mono_font())
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", UiPolish.TEXT_MUTED)
	vbox.add_child(info)

	var btn_6x4 := Button.new()
	btn_6x4.text = "72″ × 48″  (6 × 4 ft)  —  Standard"
	btn_6x4.custom_minimum_size = Vector2(0, 42)
	btn_6x4.theme_type_variation = "PrimaryButton"
	btn_6x4.pressed.connect(_emit.bind(FEET_6X4))
	vbox.add_child(btn_6x4)

	var btn_4x4 := Button.new()
	btn_4x4.text = "48″ × 48″  (4 × 4 ft)"
	btn_4x4.custom_minimum_size = Vector2(0, 42)
	btn_4x4.pressed.connect(_emit.bind(FEET_4X4))
	vbox.add_child(btn_4x4)

	vbox.add_child(HSeparator.new())

	var custom_label := Label.new()
	custom_label.text = "CUSTOM SIZE"
	custom_label.add_theme_font_override("font", HudTokens.mono_font())
	custom_label.add_theme_font_size_override("font_size", 12)
	custom_label.add_theme_color_override("font_color", UiPolish.TEXT_MUTED)
	vbox.add_child(custom_label)

	_unit_option = OptionButton.new()
	_unit_option.add_item("Inches")
	_unit_option.add_item("Centimeters")
	vbox.add_child(_unit_option)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	var wl := Label.new()
	wl.text = "Width:"
	row.add_child(wl)
	_width_input = SpinBox.new()
	_width_input.min_value = 12
	_width_input.max_value = 240
	_width_input.value = 72
	row.add_child(_width_input)

	var ll := Label.new()
	ll.text = "Length:"
	row.add_child(ll)
	_length_input = SpinBox.new()
	_length_input.min_value = 12
	_length_input.max_value = 240
	_length_input.value = 48
	row.add_child(_length_input)

	var apply := Button.new()
	apply.text = "Apply custom size"
	apply.custom_minimum_size = Vector2(0, 42)
	apply.pressed.connect(_on_apply_custom)
	vbox.add_child(apply)

	# Fixed anti-war footer (satirical — the table is the "war room").
	vbox.add_child(HSeparator.new())
	var quote := Label.new()
	quote.text = "“Gentlemen, you can't fight in here! This is the War Room!”\n— President Muffley · Dr. Strangelove (1964)"
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote.add_theme_font_size_override("font_size", 13)
	quote.add_theme_color_override("font_color", UiPolish.TEXT_MUTED)
	vbox.add_child(quote)


## Borderless windows get no WM close/ESC; provide keyboard escape (defaults to 6×4).
func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_on_close()
		get_viewport().set_input_as_handled()


func _on_apply_custom() -> void:
	_width_input.apply()
	_length_input.apply()
	var factor := INCHES_TO_FEET if _unit_option.selected == 0 else CM_TO_FEET
	_emit(Vector2(_width_input.value * factor, _length_input.value * factor))


func _on_close() -> void:
	_emit(DEFAULT_SIZE)


func _emit(size_feet: Vector2) -> void:
	if _emitted:
		return
	_emitted = true
	size_chosen.emit(size_feet)
