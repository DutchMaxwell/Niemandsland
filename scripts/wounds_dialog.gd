extends Control
class_name WoundsDialog
## Dialog for adjusting wounds on a model.
## Shows current/max wounds and allows increment/decrement.

signal wounds_changed(model: ModelInstance, new_wounds: int)
signal dialog_closed()

## Current model being edited
var _model: ModelInstance = null

## UI references (assigned in _ready or via scene)
@onready var title_label: Label = $Panel/Margin/VBox/TitleLabel
@onready var wounds_label: Label = $Panel/Margin/VBox/WoundsContainer/WoundsLabel
@onready var minus_button: Button = $Panel/Margin/VBox/WoundsContainer/MinusButton
@onready var plus_button: Button = $Panel/Margin/VBox/WoundsContainer/PlusButton
@onready var heal_full_button: Button = $Panel/Margin/VBox/HealFullButton
@onready var kill_button: Button = $Panel/Margin/VBox/KillButton
@onready var close_button: Button = $Panel/Margin/VBox/CloseButton

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


## Creates a simple wounds dialog programmatically (without scene), in the house style (maintainer D98 = a).
static func create_simple() -> WoundsDialog:
	var dialog = WoundsDialog.new()
	dialog.name = "WoundsDialog"
	var vbox := HouseStyle.dialog_frame(dialog, "WOUNDS", Vector2(250, 200))

	# Title (dynamic unit/model name under the header)
	var title := HouseStyle.label("Wounds", HouseStyle.CAPTION)
	title.name = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	dialog.title_label = title

	# − current / max + (the steps press _on_step)
	dialog.wounds_label = HouseStyle.label("0 / 0", HouseStyle.VALUE)
	dialog.wounds_label.name = "WoundsLabel"
	var row := HouseStyle.step_row("WoundsContainer", dialog.wounds_label, dialog._on_step)
	vbox.add_child(row)
	dialog.minus_button = row.get_node("MinusButton")
	dialog.plus_button = row.get_node("PlusButton")

	# Heal full (the main action), kill (ends the model), close
	dialog.heal_full_button = _action(vbox, "HealFullButton", "HEAL FULL", HouseStyle.PRIMARY, dialog._on_heal_full_pressed)
	dialog.kill_button = _action(vbox, "KillButton", "KILL", HouseStyle.DANGER_BUTTON, dialog._on_kill_pressed)
	dialog.close_button = _action(vbox, "CloseButton", "CLOSE", HouseStyle.BUTTON, dialog.close)

	# Mark signals as connected to prevent double connection in _ready
	dialog._signals_connected = true
	return dialog


func _on_step(delta: int) -> void:
	if delta > 0:
		_on_plus_pressed()
	else:
		_on_minus_pressed()


static func _action(box: VBoxContainer, node_name: String, text: String, variant: StringName, on_press: Callable) -> Button:
	var b := HouseStyle.button(text, variant, HouseStyle.H_ACTION)
	b.name = node_name
	b.pressed.connect(on_press)
	box.add_child(b)
	return b
