extends Control
class_name WoundsDialog
## Dialog for adjusting wounds on a model.
## Shows current/max wounds and allows increment/decrement.

signal wounds_changed(model: ModelInstance, new_wounds: int)
signal dialog_closed()

## Current model being edited
var _model: ModelInstance = null

## UI references (assigned in _ready or via scene)
@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var wounds_label: Label = $Panel/VBox/WoundsContainer/WoundsLabel
@onready var minus_button: Button = $Panel/VBox/WoundsContainer/MinusButton
@onready var plus_button: Button = $Panel/VBox/WoundsContainer/PlusButton
@onready var heal_full_button: Button = $Panel/VBox/HealFullButton
@onready var kill_button: Button = $Panel/VBox/KillButton
@onready var close_button: Button = $Panel/VBox/CloseButton

## Flag to prevent double signal connection
var _signals_connected: bool = false


func _ready() -> void:
	visible = false
	_setup_ui()
	# Debug: Listen for any GUI input
	gui_input.connect(_on_gui_input)


func _on_gui_input(_event: InputEvent) -> void:
	pass  # Input handled by child controls


func _setup_ui() -> void:
	# Skip if already connected (from create_simple)
	if _signals_connected:
		return
	_signals_connected = true

	# Connect buttons if they exist
	if minus_button:
		minus_button.pressed.connect(_on_minus_pressed)
	if plus_button:
		plus_button.pressed.connect(_on_plus_pressed)
	if heal_full_button:
		heal_full_button.pressed.connect(_on_heal_full_pressed)
	if kill_button:
		kill_button.pressed.connect(_on_kill_pressed)
	if close_button:
		close_button.pressed.connect(close)


## Opens the dialog for a specific model.
func open(model: ModelInstance) -> void:
	_model = model
	visible = true
	_update_display()
	# Panel is auto-centered via PRESET_CENTER, no manual positioning needed


## Closes the dialog.
func close() -> void:
	visible = false
	_model = null
	dialog_closed.emit()


## Updates the display with current model data.
func _update_display() -> void:
	if not _model:
		return

	if title_label:
		var unit_name = ""
		if _model.unit and _model.unit is GameUnit:
			unit_name = _model.unit.get_name()
		title_label.text = "%s - %s" % [unit_name, _model.get_display_name()]

	if wounds_label:
		wounds_label.text = "%d / %d" % [_model.wounds_current, _model.wounds_max]

	# Update button states
	if minus_button:
		minus_button.disabled = _model.wounds_current <= 0
	if plus_button:
		plus_button.disabled = _model.wounds_current >= _model.wounds_max
	if heal_full_button:
		heal_full_button.disabled = _model.wounds_current >= _model.wounds_max
	if kill_button:
		kill_button.disabled = not _model.is_alive


func _on_minus_pressed() -> void:
	if not _model or _model.wounds_current <= 0:
		return

	_model.wounds_current -= 1
	if _model.wounds_current <= 0:
		_model.is_alive = false

	wounds_changed.emit(_model, _model.wounds_current)
	_update_display()


func _on_plus_pressed() -> void:
	if not _model or _model.wounds_current >= _model.wounds_max:
		return

	_model.wounds_current += 1
	_model.is_alive = true

	wounds_changed.emit(_model, _model.wounds_current)
	_update_display()


func _on_heal_full_pressed() -> void:
	if not _model:
		return

	_model.reset_wounds()
	wounds_changed.emit(_model, _model.wounds_current)
	_update_display()


func _on_kill_pressed() -> void:
	if not _model:
		return

	_model.wounds_current = 0
	_model.is_alive = false

	wounds_changed.emit(_model, _model.wounds_current)
	_update_display()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			_on_minus_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			_on_plus_pressed()
			get_viewport().set_input_as_handled()


## Creates a simple wounds dialog programmatically (without scene).
static func create_simple() -> WoundsDialog:
	var dialog = WoundsDialog.new()
	dialog.name = "WoundsDialog"
	# Fill entire screen to block all input when visible
	dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP  # Block all clicks

	# Semi-transparent background to dim the scene and block input
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.4)  # Semi-transparent black
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # Block clicks
	dialog.add_child(bg)

	# Create centered panel container
	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(250, 200)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_STOP  # Panel captures its area
	dialog.add_child(panel)

	# VBox container
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS  # Pass clicks to children
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.name = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "Wounds"
	vbox.add_child(title)
	dialog.title_label = title

	# Wounds container
	var wounds_hbox = HBoxContainer.new()
	wounds_hbox.name = "WoundsContainer"
	wounds_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	wounds_hbox.mouse_filter = Control.MOUSE_FILTER_PASS  # Pass clicks to children
	vbox.add_child(wounds_hbox)

	# Minus button
	var minus_btn = Button.new()
	minus_btn.name = "MinusButton"
	minus_btn.text = "-"
	minus_btn.custom_minimum_size = Vector2(40, 40)
	minus_btn.mouse_filter = Control.MOUSE_FILTER_STOP  # Ensure button captures input
	wounds_hbox.add_child(minus_btn)
	dialog.minus_button = minus_btn

	# Wounds label
	var wounds_lbl = Label.new()
	wounds_lbl.name = "WoundsLabel"
	wounds_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wounds_lbl.custom_minimum_size = Vector2(80, 0)
	wounds_lbl.text = "0 / 0"
	wounds_hbox.add_child(wounds_lbl)
	dialog.wounds_label = wounds_lbl

	# Plus button
	var plus_btn = Button.new()
	plus_btn.name = "PlusButton"
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(40, 40)
	wounds_hbox.add_child(plus_btn)
	dialog.plus_button = plus_btn

	# Heal full button
	var heal_btn = Button.new()
	heal_btn.name = "HealFullButton"
	heal_btn.text = "Heal Full"
	vbox.add_child(heal_btn)
	dialog.heal_full_button = heal_btn

	# Kill button
	var kill_btn = Button.new()
	kill_btn.name = "KillButton"
	kill_btn.text = "Kill"
	vbox.add_child(kill_btn)
	dialog.kill_button = kill_btn

	# Close button
	var close_btn = Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "Close"
	vbox.add_child(close_btn)
	dialog.close_button = close_btn

	# Connect signals directly (not using _setup_ui which checks @onready vars)
	minus_btn.pressed.connect(dialog._on_minus_pressed)
	plus_btn.pressed.connect(dialog._on_plus_pressed)
	heal_btn.pressed.connect(dialog._on_heal_full_pressed)
	kill_btn.pressed.connect(dialog._on_kill_pressed)
	close_btn.pressed.connect(dialog.close)

	# Mark signals as connected to prevent double connection in _ready
	dialog._signals_connected = true

	return dialog
