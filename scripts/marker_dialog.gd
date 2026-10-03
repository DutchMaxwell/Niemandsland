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

		var label := HouseStyle.label("%s: %d" % [marker_name, value] if value >= 0 else marker_name, HouseStyle.BODY)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(label)

		if value >= 0:
			hbox.add_child(_small(HouseStyle.step_text(-1, true), _on_counter_changed.bind(marker_name, -1)))
			hbox.add_child(_small(HouseStyle.step_text(1, true), _on_counter_changed.bind(marker_name, 1)))

		# U+00D7: Inter (the UI font) has no U+2715
		hbox.add_child(_small(HouseStyle.GLYPH_CLOSE, _on_remove_marker_pressed.bind(marker_name)))

		active_container.add_child(hbox)


## Rebuilds the library section: one apply-button + edit-button per saved token.
func _update_library_section() -> void:
	if not library_container:
		return
	for child in library_container.get_children():
		child.queue_free()
	if not token_library:
		return

	var names: Array = token_library.names()
	names.sort()   # rule + spell tokens mixed in — alphabetical keeps the list scannable
	for token_name in names:
		var row = HBoxContainer.new()

		var apply_btn := HouseStyle.button(token_name, HouseStyle.BUTTON)
		apply_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# The token colour tells buff (green) from debuff (red) at a glance; the effect text from
		# the army book (rule/spell) rides on the tooltip so picking needs no rules lookup.
		apply_btn.add_theme_color_override("font_color", token_library.get_color(token_name))
		var effect := token_library.get_effect(token_name)
		apply_btn.tooltip_text = effect if not effect.is_empty() \
				else "Apply '%s' to the current selection" % token_name
		apply_btn.pressed.connect(_on_library_apply.bind(token_name))
		row.add_child(apply_btn)

		var edit_btn := _small("Edit", _enter_edit_mode.bind(token_name))   # the UI font has no ✎
		edit_btn.tooltip_text = "Edit '%s' (name/color/effect) for all instances" % token_name
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


## Creates the dialog programmatically (no scene), in the house style (maintainer D98 = a): the shared unit
## dialog frame (house scrim + centred house panel), mirroring WoundsDialog / CastsDialog.
static func create_simple() -> MarkerDialog:
	var dialog = MarkerDialog.new()
	dialog.name = "MarkerDialog"
	var vbox := HouseStyle.dialog_frame(dialog, "MARKERS", Vector2(360, 0))

	# Title (per-target name, updated in _update_display)
	dialog.title_label = _caption(vbox, "Tokens")

	# Active tokens
	_caption(vbox, "ACTIVE")
	dialog.active_container = _list(vbox)
	vbox.add_child(HSeparator.new())

	# Reusable token library
	_caption(vbox, "SAVED TOKENS (CLICK TO APPLY, EDIT TO CHANGE)")
	dialog.library_container = _list(vbox)
	vbox.add_child(HSeparator.new())

	# New / edit token
	_caption(vbox, "NEW / EDIT TOKEN")
	var name_hbox = HBoxContainer.new()
	vbox.add_child(name_hbox)

	var custom_input = LineEdit.new()
	custom_input.placeholder_text = "Token name (e.g. Havoc)..."
	custom_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_hbox.add_child(custom_input)
	dialog.custom_input = custom_input

	var color_picker = OptionButton.new()
	color_picker.theme_type_variation = HouseStyle.BUTTON
	name_hbox.add_child(color_picker)
	dialog.color_picker = color_picker

	var counter_hbox = HBoxContainer.new()
	vbox.add_child(counter_hbox)

	var counter_check = CheckBox.new()
	counter_check.text = "Counter"
	counter_check.tooltip_text = "Adjustable +/- value for resource/stacking rules"
	counter_check.theme_type_variation = HouseStyle.BUTTON   # a check line, as in the game menu
	counter_hbox.add_child(counter_check)
	dialog.counter_check = counter_check

	_caption(counter_hbox, "START")

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

	# Action buttons (always visible at the bottom): Add is the main action
	var buttons_hbox = HBoxContainer.new()
	buttons_hbox.add_theme_constant_override(&"separation", HouseStyle.GAP_CONTROL)
	vbox.add_child(buttons_hbox)
	dialog.add_custom_button = HouseStyle.button("Add", HouseStyle.PRIMARY)
	buttons_hbox.add_child(dialog.add_custom_button)
	dialog.close_button = HouseStyle.button("Close", HouseStyle.BUTTON, HouseStyle.H_ACTION)
	buttons_hbox.add_child(dialog.close_button)

	dialog._setup_ui()
	return dialog


static func _caption(box: Container, text: String) -> Label:
	var l := HouseStyle.label(text, HouseStyle.CAPTION)
	box.add_child(l)
	return l


## A scrolling list (active tokens, the library), 90 px tall.
static func _list(box: VBoxContainer) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 90)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list


## A small house button of a token row (− / + / × / Edit), as wide as its word.
static func _small(text: String, on_press: Callable) -> Button:
	var b := HouseStyle.button(text, HouseStyle.BUTTON, HouseStyle.H_PIP)
	b.custom_minimum_size.x = HouseStyle.H_PIP
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.pressed.connect(on_press)
	return b
