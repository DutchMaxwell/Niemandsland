extends Control
class_name MarkerDialog
## Dialog for managing CUSTOM tokens on a model or unit: add/remove, adjust
## counters, plus a reusable token library (apply existing tokens, or edit one
## for all its instances). Standard OPR markers are intentionally NOT shown here.

signal marker_added(target: Variant, marker: UnitMarker)
signal marker_removed(target: Variant, marker_name: String)
signal marker_value_changed(target: Variant, marker_name: String, value: int)
signal marker_edited(old_name: String, new_name: String, color: Color, effect: String)
signal dialog_closed()

## Target for markers (ModelInstance or GameUnit)
var _target: Variant = null

## Is target a unit (applies to all models)
var _is_unit: bool = false

## UI references (all built in create_simple, so plain vars - no scene needed)
var title_label: Label = null
var active_container: VBoxContainer = null
var library_container: VBoxContainer = null
var custom_input: LineEdit = null
var color_picker: OptionButton = null
var add_custom_button: Button = null
var close_button: Button = null
var counter_check: CheckBox = null
var counter_value_spin: SpinBox = null
var effect_input: LineEdit = null

## Library of reusable token definitions (set by RadialMenuController).
var token_library: TokenLibrary = null

## When non-empty, the dialog is editing this library token (Add button -> Save).
var _editing_name: String = ""

## Guards against connecting signals twice.
var _signals_connected: bool = false


func _ready() -> void:
	visible = false
	_setup_ui()


func _setup_ui() -> void:
	if _signals_connected:
		return
	_signals_connected = true

	if add_custom_button:
		add_custom_button.pressed.connect(_on_add_custom_pressed)
	if close_button:
		close_button.pressed.connect(close)

	# Custom colours (indices match UnitMarker.CUSTOM_COLORS)
	if color_picker:
		color_picker.clear()
		color_picker.add_item("Red", 0)
		color_picker.add_item("Yellow", 1)
		color_picker.add_item("Green", 2)
		color_picker.add_item("Blue", 3)
		color_picker.add_item("Purple", 4)
		color_picker.add_item("White", 5)


## Opens the dialog for a model.
func open_for_model(model: ModelInstance) -> void:
	_target = model
	_is_unit = false
	_exit_edit_mode()
	visible = true
	_update_display()


## Opens the dialog for a unit (applies to all models).
func open_for_unit(game_unit: GameUnit) -> void:
	_target = game_unit
	_is_unit = true
	_exit_edit_mode()
	visible = true
	_update_display()


## Closes the dialog.
func close() -> void:
	visible = false
	_target = null
	_exit_edit_mode()
	dialog_closed.emit()


## Updates the display with current tokens + the library.
func _update_display() -> void:
	if title_label:
		if _is_unit and _target is GameUnit:
			title_label.text = "Tokens: %s" % _target.get_name()
		elif _target is ModelInstance:
			title_label.text = "Tokens: %s" % _target.get_display_name()
		else:
			title_label.text = "Tokens"

	var current_markers: Array = []
	if _target is ModelInstance:
		current_markers = _target.markers
	elif _target is GameUnit and _target.models.size() > 0:
		current_markers = _target.models[0].markers

	_update_active_markers(current_markers)
	_update_library_section()


func _update_active_markers(markers: Array) -> void:
	if not active_container:
		return

	for child in active_container.get_children():
		child.queue_free()

	for marker_name in markers:
		var hbox = HBoxContainer.new()

		var value = _marker_value_for(marker_name)

		var label = Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s: %d" % [marker_name, value] if value >= 0 else marker_name
		hbox.add_child(label)

		if value >= 0:
			var minus_btn = Button.new()
			minus_btn.text = "-"
			minus_btn.pressed.connect(_on_counter_changed.bind(marker_name, -1))
			hbox.add_child(minus_btn)

			var plus_btn = Button.new()
			plus_btn.text = "+"
			plus_btn.pressed.connect(_on_counter_changed.bind(marker_name, 1))
			hbox.add_child(plus_btn)

		var remove_btn = Button.new()
		remove_btn.text = "✕"
		remove_btn.pressed.connect(_on_remove_marker_pressed.bind(marker_name))
		hbox.add_child(remove_btn)

		active_container.add_child(hbox)


## Rebuilds the library section: one apply-button + edit-button per saved token.
func _update_library_section() -> void:
	if not library_container:
		return
	for child in library_container.get_children():
		child.queue_free()
	if not token_library:
		return

	for token_name in token_library.names():
		var row = HBoxContainer.new()

		var apply_btn = Button.new()
		apply_btn.text = token_name
		apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		apply_btn.tooltip_text = "Apply '%s' to the current selection" % token_name
		apply_btn.pressed.connect(_on_library_apply.bind(token_name))
		row.add_child(apply_btn)

		var edit_btn = Button.new()
		edit_btn.text = "✎"
		edit_btn.tooltip_text = "Edit '%s' (name/color/effect) for all instances" % token_name
		edit_btn.pressed.connect(_enter_edit_mode.bind(token_name))
		row.add_child(edit_btn)

		library_container.add_child(row)


## Returns the counter value of a marker, or -1 if it is a status (non-counter).
func _marker_value_for(marker_name: String) -> int:
	var model: ModelInstance = null
	if _target is ModelInstance:
		model = _target
	elif _target is GameUnit and _target.models.size() > 0:
		model = _target.models[0]
	if model and model.is_counter_marker(marker_name):
		return model.get_marker_value(marker_name)
	return -1


## Adjusts a counter marker by delta (clamped to >= 0) and notifies listeners.
func _on_counter_changed(marker_name: String, delta: int) -> void:
	if not _target:
		return
	var current = _marker_value_for(marker_name)
	if current < 0:
		return
	var new_value = maxi(0, current + delta)

	if _target is ModelInstance:
		_target.set_marker_value(marker_name, new_value)
	elif _target is GameUnit:
		_target.set_marker_value_on_all(marker_name, new_value)

	marker_value_changed.emit(_target, marker_name, new_value)
	_update_display()


## Applies an existing library token to the current target.
func _on_library_apply(token_name: String) -> void:
	if not _target or not token_library:
		return
	var def := token_library.get_definition(token_name)
	if def.is_empty():
		return
	var color: Color = def.get("color", Color.WHITE)
	var effect: String = def.get("effect", "")
	var marker: UnitMarker
	if def.get("is_counter", false):
		marker = UnitMarker.create_counter(token_name, color, 0, effect)
	else:
		marker = UnitMarker.create_custom(token_name, color, effect)
	_add_marker(marker)


## Loads a library token into the edit fields (Add button becomes Save).
func _enter_edit_mode(token_name: String) -> void:
	if not token_library:
		return
	_editing_name = token_name
	if custom_input:
		custom_input.text = token_name
	if effect_input:
		effect_input.text = token_library.get_effect(token_name)
	if counter_check:
		counter_check.button_pressed = token_library.is_counter(token_name)
		counter_check.disabled = true  # type can't change on edit
	if color_picker:
		var col := token_library.get_color(token_name)
		for i in range(UnitMarker.CUSTOM_COLORS.size()):
			if UnitMarker.CUSTOM_COLORS[i].is_equal_approx(col):
				color_picker.selected = i
				break
	if add_custom_button:
		add_custom_button.text = "Save"


## Leaves edit mode and resets the edit fields.
func _exit_edit_mode() -> void:
	_editing_name = ""
	if custom_input:
		custom_input.text = ""
	if effect_input:
		effect_input.text = ""
	if counter_check:
		counter_check.disabled = false
	if add_custom_button:
		add_custom_button.text = "Add"


func _on_add_custom_pressed() -> void:
	if not custom_input:
		return
	var text = custom_input.text.strip_edges()
	if text.is_empty():
		return

	var color = Color.WHITE
	if color_picker:
		var color_idx = color_picker.selected
		if color_idx >= 0 and color_idx < UnitMarker.CUSTOM_COLORS.size():
			color = UnitMarker.CUSTOM_COLORS[color_idx]

	var effect := effect_input.text.strip_edges() if effect_input else ""

	# Edit mode: update the library definition (and all instances) instead of adding.
	if not _editing_name.is_empty():
		marker_edited.emit(_editing_name, text, color, effect)
		_exit_edit_mode()
		_update_display()
		return

	# Add mode: needs a target to attach the new token to.
	if not _target:
		return

	var marker: UnitMarker
	if counter_check and counter_check.button_pressed:
		var start_value := int(counter_value_spin.value) if counter_value_spin else 0
		marker = UnitMarker.create_counter(text, color, start_value, effect)
	else:
		marker = UnitMarker.create_custom(text, color, effect)
	_add_marker(marker)

	custom_input.text = ""
	if effect_input:
		effect_input.text = ""


func _add_marker(marker: UnitMarker) -> void:
	if _target is ModelInstance:
		_target.add_marker(marker.name)
		if marker.is_counter:
			_target.set_marker_value(marker.name, marker.counter_value)
	elif _target is GameUnit:
		_target.add_marker_to_all(marker.name)
		if marker.is_counter:
			_target.set_marker_value_on_all(marker.name, marker.counter_value)

	marker_added.emit(_target, marker)
	_update_display()


func _on_remove_marker_pressed(marker_name: String) -> void:
	_remove_marker(marker_name)


func _remove_marker(marker_name: String) -> void:
	if _target is ModelInstance:
		_target.remove_marker(marker_name)
	elif _target is GameUnit:
		_target.remove_marker_from_all(marker_name)

	marker_removed.emit(_target, marker_name)
	_update_display()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


## Creates the dialog programmatically (no scene). Full-rect overlay that dims +
## blocks the game, with a centered panel - mirrors WoundsDialog / CastsDialog.
static func create_simple() -> MarkerDialog:
	var dialog = MarkerDialog.new()
	dialog.name = "MarkerDialog"
	dialog.theme = ThemeManager.get_current_theme()  # so PrimaryButton/DangerButton variations resolve
	dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP

	# Dim background that blocks input to the scene behind
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.4)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog.add_child(bg)

	# Centered panel
	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(360, 0)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", HudTokens.panel_style())
	dialog.add_child(panel)

	var margin = MarginContainer.new()
	UiPolish.set_dialog_margins(margin)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", HudTokens.SPACE_8)
	margin.add_child(vbox)

	# Tactical header (Orbitron title + amber index + accent line)
	vbox.add_child(HudTokens.header("MARKERS", "/// MARK"))

	# Title (per-target name, updated in _update_display)
	var title = Label.new()
	title.text = "Tokens"
	title.add_theme_font_override("font", HudTokens.mono_font())
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", UiPolish.TEXT_MUTED)
	vbox.add_child(title)
	dialog.title_label = title

	# Active tokens
	var active_label = Label.new()
	active_label.text = "ACTIVE"
	active_label.add_theme_font_override("font", HudTokens.mono_font())
	active_label.add_theme_font_size_override("font_size", 12)
	active_label.add_theme_color_override("font_color", UiPolish.TEXT_MUTED)
	vbox.add_child(active_label)

	var active_scroll = ScrollContainer.new()
	active_scroll.custom_minimum_size = Vector2(0, 90)
	active_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(active_scroll)

	var active_vbox = VBoxContainer.new()
	active_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_scroll.add_child(active_vbox)
	dialog.active_container = active_vbox

	vbox.add_child(HSeparator.new())

	# Reusable token library
	var lib_label = Label.new()
	lib_label.text = "SAVED TOKENS (CLICK TO APPLY, ✎ TO EDIT)"
	lib_label.add_theme_font_override("font", HudTokens.mono_font())
	lib_label.add_theme_font_size_override("font_size", 12)
	lib_label.add_theme_color_override("font_color", UiPolish.TEXT_MUTED)
	vbox.add_child(lib_label)

	var lib_scroll = ScrollContainer.new()
	lib_scroll.custom_minimum_size = Vector2(0, 90)
	lib_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(lib_scroll)

	var lib_vbox = VBoxContainer.new()
	lib_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lib_scroll.add_child(lib_vbox)
	dialog.library_container = lib_vbox

	vbox.add_child(HSeparator.new())

	# New / edit token
	var new_label = Label.new()
	new_label.text = "NEW / EDIT TOKEN"
	new_label.add_theme_font_override("font", HudTokens.mono_font())
	new_label.add_theme_font_size_override("font_size", 12)
	new_label.add_theme_color_override("font_color", UiPolish.TEXT_MUTED)
	vbox.add_child(new_label)

	var name_hbox = HBoxContainer.new()
	vbox.add_child(name_hbox)

	var custom_input = LineEdit.new()
	custom_input.placeholder_text = "Token name (e.g. Havoc)..."
	custom_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_hbox.add_child(custom_input)
	dialog.custom_input = custom_input

	var color_picker = OptionButton.new()
	name_hbox.add_child(color_picker)
	dialog.color_picker = color_picker

	var counter_hbox = HBoxContainer.new()
	vbox.add_child(counter_hbox)

	var counter_check = CheckBox.new()
	counter_check.text = "Counter"
	counter_check.tooltip_text = "Adjustable +/- value for resource/stacking rules"
	counter_hbox.add_child(counter_check)
	dialog.counter_check = counter_check

	var start_label = Label.new()
	start_label.text = "START"
	start_label.add_theme_font_override("font", HudTokens.mono_font())
	start_label.add_theme_font_size_override("font_size", 12)
	start_label.add_theme_color_override("font_color", UiPolish.TEXT_MUTED)
	counter_hbox.add_child(start_label)

	var counter_spin = SpinBox.new()
	counter_spin.min_value = 0
	counter_spin.max_value = 99
	counter_spin.value = 0
	counter_hbox.add_child(counter_spin)
	dialog.counter_value_spin = counter_spin

	var effect_field = LineEdit.new()
	effect_field.placeholder_text = "Effect/description (shown on hover, optional)..."
	effect_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(effect_field)
	dialog.effect_input = effect_field

	# Action buttons (always visible at the bottom)
	var buttons_hbox = HBoxContainer.new()
	vbox.add_child(buttons_hbox)

	var add_btn = Button.new()
	add_btn.text = "Add"
	add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_btn.theme_type_variation = "PrimaryButton"
	UiPolish.primary_button(add_btn)
	buttons_hbox.add_child(add_btn)
	dialog.add_custom_button = add_btn

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiPolish.primary_button(close_btn)
	buttons_hbox.add_child(close_btn)
	dialog.close_button = close_btn

	# Corner-bracket chrome on top (instrumentation look) — must be the panel's last child
	panel.add_child(HudFrame.new())

	dialog._setup_ui()
	return dialog
