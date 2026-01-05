extends Control
class_name MarkerDialog
## Dialog for adding/removing markers on models or units.
## Shows standard OPR markers and allows custom freetext markers.

signal marker_added(target: Variant, marker: UnitMarker)
signal marker_removed(target: Variant, marker_name: String)
signal dialog_closed()

## Target for markers (ModelInstance or GameUnit)
var _target: Variant = null

## Is target a unit (applies to all models)
var _is_unit: bool = false

## UI references
@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var standard_container: GridContainer = $Panel/VBox/StandardMarkers
@onready var active_container: VBoxContainer = $Panel/VBox/ActiveMarkers
@onready var custom_input: LineEdit = $Panel/VBox/CustomContainer/CustomInput
@onready var color_picker: OptionButton = $Panel/VBox/CustomContainer/ColorPicker
@onready var add_custom_button: Button = $Panel/VBox/CustomContainer/AddButton
@onready var close_button: Button = $Panel/VBox/CloseButton

## Standard marker buttons
var _standard_buttons: Dictionary = {}


func _ready() -> void:
	visible = false
	_setup_ui()


func _setup_ui() -> void:
	if add_custom_button:
		add_custom_button.pressed.connect(_on_add_custom_pressed)
	if close_button:
		close_button.pressed.connect(close)

	# Setup color picker
	if color_picker:
		color_picker.clear()
		color_picker.add_item("Red", 0)
		color_picker.add_item("Yellow", 1)
		color_picker.add_item("Green", 2)
		color_picker.add_item("Blue", 3)
		color_picker.add_item("Purple", 4)
		color_picker.add_item("White", 5)

	# Create standard marker buttons
	_create_standard_marker_buttons()


func _create_standard_marker_buttons() -> void:
	if not standard_container:
		return

	# Clear existing
	for child in standard_container.get_children():
		child.queue_free()
	_standard_buttons.clear()

	# Create button for each standard marker
	for marker_name in UnitMarker.STANDARD_MARKERS.keys():
		var def = UnitMarker.STANDARD_MARKERS[marker_name]
		var btn = Button.new()
		btn.text = "%s %s" % [def.icon, marker_name]
		btn.toggle_mode = true
		btn.tooltip_text = def.description
		btn.pressed.connect(_on_standard_marker_toggled.bind(marker_name))
		standard_container.add_child(btn)
		_standard_buttons[marker_name] = btn


## Opens the dialog for a model.
func open_for_model(model: ModelInstance) -> void:
	_target = model
	_is_unit = false
	visible = true
	_update_display()
	_center_dialog()


## Opens the dialog for a unit (applies to all models).
func open_for_unit(game_unit: GameUnit) -> void:
	_target = game_unit
	_is_unit = true
	visible = true
	_update_display()
	_center_dialog()


func _center_dialog() -> void:
	var viewport_size = get_viewport_rect().size
	position = (viewport_size - size) / 2


## Closes the dialog.
func close() -> void:
	visible = false
	_target = null
	dialog_closed.emit()


## Updates the display with current markers.
func _update_display() -> void:
	if not _target:
		return

	# Update title
	if title_label:
		if _is_unit and _target is GameUnit:
			title_label.text = "Markers: %s" % _target.get_name()
		elif _target is ModelInstance:
			title_label.text = "Markers: %s" % _target.get_display_name()

	# Get current markers
	var current_markers: Array = []
	if _target is ModelInstance:
		current_markers = _target.markers
	elif _target is GameUnit:
		# For unit, show markers from first model as representative
		if _target.models.size() > 0:
			current_markers = _target.models[0].markers

	# Update standard marker button states
	for marker_name in _standard_buttons:
		var btn = _standard_buttons[marker_name] as Button
		btn.button_pressed = marker_name in current_markers

	# Update active markers list
	_update_active_markers(current_markers)


func _update_active_markers(markers: Array) -> void:
	if not active_container:
		return

	# Clear existing
	for child in active_container.get_children():
		child.queue_free()

	# Add current markers
	for marker_name in markers:
		var hbox = HBoxContainer.new()

		var label = Label.new()
		label.text = marker_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(label)

		var remove_btn = Button.new()
		remove_btn.text = "✕"
		remove_btn.pressed.connect(_on_remove_marker_pressed.bind(marker_name))
		hbox.add_child(remove_btn)

		active_container.add_child(hbox)


func _on_standard_marker_toggled(marker_name: String) -> void:
	if not _target:
		return

	var btn = _standard_buttons.get(marker_name) as Button
	if not btn:
		return

	if btn.button_pressed:
		# Add marker
		var marker = UnitMarker.create_standard(marker_name)
		_add_marker(marker)
	else:
		# Remove marker
		_remove_marker(marker_name)


func _on_add_custom_pressed() -> void:
	if not _target or not custom_input:
		return

	var text = custom_input.text.strip_edges()
	if text.is_empty():
		return

	# Get selected color
	var color = Color.WHITE
	if color_picker:
		var color_idx = color_picker.selected
		if color_idx >= 0 and color_idx < UnitMarker.CUSTOM_COLORS.size():
			color = UnitMarker.CUSTOM_COLORS[color_idx]

	var marker = UnitMarker.create_custom(text, color)
	_add_marker(marker)

	# Clear input
	custom_input.text = ""


func _add_marker(marker: UnitMarker) -> void:
	if _target is ModelInstance:
		_target.add_marker(marker.name)
	elif _target is GameUnit:
		_target.add_marker_to_all(marker.name)

	marker_added.emit(_target, marker)
	_update_display()


func _on_remove_marker_pressed(marker_name: String) -> void:
	_remove_marker(marker_name)


func _remove_marker(marker_name: String) -> void:
	if _target is ModelInstance:
		_target.remove_marker(marker_name)
	elif _target is GameUnit:
		_target.remove_marker_from_all(marker_name)

	# Update standard button state
	if _standard_buttons.has(marker_name):
		var btn = _standard_buttons[marker_name] as Button
		btn.button_pressed = false

	marker_removed.emit(_target, marker_name)
	_update_display()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()


## Creates a marker dialog programmatically (without scene).
static func create_simple() -> MarkerDialog:
	var dialog = MarkerDialog.new()
	dialog.name = "MarkerDialog"

	# Create panel
	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(300, 400)
	dialog.add_child(panel)

	# VBox container
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.name = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "Markers"
	vbox.add_child(title)
	dialog.title_label = title

	# Standard markers section
	var std_label = Label.new()
	std_label.text = "Standard Markers:"
	vbox.add_child(std_label)

	var std_grid = GridContainer.new()
	std_grid.name = "StandardMarkers"
	std_grid.columns = 2
	vbox.add_child(std_grid)
	dialog.standard_container = std_grid

	# Separator
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# Active markers section
	var active_label = Label.new()
	active_label.text = "Active Markers:"
	vbox.add_child(active_label)

	var active_scroll = ScrollContainer.new()
	active_scroll.custom_minimum_size = Vector2(0, 100)
	vbox.add_child(active_scroll)

	var active_vbox = VBoxContainer.new()
	active_vbox.name = "ActiveMarkers"
	active_scroll.add_child(active_vbox)
	dialog.active_container = active_vbox

	# Separator
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	# Custom marker section
	var custom_label = Label.new()
	custom_label.text = "Custom Marker:"
	vbox.add_child(custom_label)

	var custom_hbox = HBoxContainer.new()
	custom_hbox.name = "CustomContainer"
	vbox.add_child(custom_hbox)

	var custom_input = LineEdit.new()
	custom_input.name = "CustomInput"
	custom_input.placeholder_text = "Enter marker text..."
	custom_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_hbox.add_child(custom_input)
	dialog.custom_input = custom_input

	var color_picker = OptionButton.new()
	color_picker.name = "ColorPicker"
	custom_hbox.add_child(color_picker)
	dialog.color_picker = color_picker

	var add_btn = Button.new()
	add_btn.name = "AddButton"
	add_btn.text = "Add"
	custom_hbox.add_child(add_btn)
	dialog.add_custom_button = add_btn

	# Close button
	var close_btn = Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "Close"
	vbox.add_child(close_btn)
	dialog.close_button = close_btn

	# Setup
	dialog._setup_ui()

	return dialog
