extends Control
class_name CastsDialog
## Dialog for adjusting caster points on a unit.
## Shows current points, per-round gain, and allows manual adjustment via +/- buttons.

signal casts_changed(unit: GameUnit, new_casts: int)
signal dialog_closed()

## Current unit being edited
var _unit: GameUnit = null

## UI references (assigned in _ready or via create_simple)
@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var casts_label: Label = $Panel/VBox/CastsContainer/CastsLabel
@onready var minus_button: Button = $Panel/VBox/CastsContainer/MinusButton
@onready var plus_button: Button = $Panel/VBox/CastsContainer/PlusButton
@onready var per_round_label: Label = $Panel/VBox/PerRoundLabel
@onready var reset_button: Button = $Panel/VBox/ResetButton
@onready var close_button: Button = $Panel/VBox/CloseButton

## Flag to prevent double signal connection
var _signals_connected: bool = false


func _ready() -> void:
	visible = false
	_setup_ui()


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
	if reset_button:
		reset_button.pressed.connect(_on_reset_pressed)
	if close_button:
		close_button.pressed.connect(close)


## Opens the dialog for a specific unit.
func open(unit: GameUnit) -> void:
	_unit = unit
	visible = true
	_update_display()


## Closes the dialog.
func close() -> void:
	visible = false
	_unit = null
	dialog_closed.emit()


## Updates the display with current unit data.
func _update_display() -> void:
	if not _unit:
		return

	if title_label:
		title_label.text = "%s - Caster Points" % _unit.get_name()

	if casts_label:
		casts_label.text = "%d / %d" % [_unit.casts_current, GameUnit.CASTER_POINTS_CAP]

	if per_round_label:
		per_round_label.text = "+%d per round" % _unit.casts_per_round

	# Update button states
	if minus_button:
		minus_button.disabled = _unit.casts_current <= 0
	if plus_button:
		plus_button.disabled = _unit.casts_current >= GameUnit.CASTER_POINTS_CAP


func _on_minus_pressed() -> void:
	if not _unit or _unit.casts_current <= 0:
		return

	_unit.casts_current -= 1
	casts_changed.emit(_unit, _unit.casts_current)
	_update_display()


func _on_plus_pressed() -> void:
	if not _unit or _unit.casts_current >= GameUnit.CASTER_POINTS_CAP:
		return

	_unit.casts_current += 1
	casts_changed.emit(_unit, _unit.casts_current)
	_update_display()


func _on_reset_pressed() -> void:
	if not _unit:
		return

	_unit.reset_caster_points()
	casts_changed.emit(_unit, _unit.casts_current)
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


## Creates a simple casts dialog programmatically (without scene).
static func create_simple() -> CastsDialog:
	var dialog = CastsDialog.new()
	dialog.name = "CastsDialog"
	# Fill entire screen to block all input when visible
	dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP

	# Semi-transparent background to dim the scene and block input
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.4)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog.add_child(bg)

	# Create centered panel container
	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(250, 180)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog.add_child(panel)

	# VBox container
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.name = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "Caster Points"
	vbox.add_child(title)
	dialog.title_label = title

	# Casts container (- / current / +)
	var casts_hbox = HBoxContainer.new()
	casts_hbox.name = "CastsContainer"
	casts_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	casts_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(casts_hbox)

	# Minus button
	var minus_btn = Button.new()
	minus_btn.name = "MinusButton"
	minus_btn.text = "-"
	minus_btn.custom_minimum_size = Vector2(40, 40)
	minus_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	casts_hbox.add_child(minus_btn)
	dialog.minus_button = minus_btn

	# Casts label
	var casts_lbl = Label.new()
	casts_lbl.name = "CastsLabel"
	casts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	casts_lbl.custom_minimum_size = Vector2(80, 0)
	casts_lbl.text = "0 / 6"
	casts_hbox.add_child(casts_lbl)
	dialog.casts_label = casts_lbl

	# Plus button
	var plus_btn = Button.new()
	plus_btn.name = "PlusButton"
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(40, 40)
	casts_hbox.add_child(plus_btn)
	dialog.plus_button = plus_btn

	# Per round label
	var per_round = Label.new()
	per_round.name = "PerRoundLabel"
	per_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	per_round.text = "+0 per round"
	per_round.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(per_round)
	dialog.per_round_label = per_round

	# Reset button
	var reset_btn = Button.new()
	reset_btn.name = "ResetButton"
	reset_btn.text = "Reset to Per-Round"
	reset_btn.tooltip_text = "Reset points to per-round value"
	vbox.add_child(reset_btn)
	dialog.reset_button = reset_btn

	# Close button
	var close_btn = Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "Close"
	vbox.add_child(close_btn)
	dialog.close_button = close_btn

	# Connect signals directly
	minus_btn.pressed.connect(dialog._on_minus_pressed)
	plus_btn.pressed.connect(dialog._on_plus_pressed)
	reset_btn.pressed.connect(dialog._on_reset_pressed)
	close_btn.pressed.connect(dialog.close)

	# Mark signals as connected to prevent double connection in _ready
	dialog._signals_connected = true

	return dialog
