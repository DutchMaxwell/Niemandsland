extends Control
class_name CastsDialog
## Dialog for adjusting caster points on a unit.
## Shows current points, per-round gain, and allows manual adjustment via +/- buttons.

signal casts_changed(unit: GameUnit, new_casts: int)
signal dialog_closed()

## Current unit being edited
var _unit: GameUnit = null

## Faction spell list, built lazily on first open (below the per-round line).
var _spells_label: RichTextLabel = null

## UI references (assigned in _ready or via create_simple)
@onready var title_label: Label = $Panel/Margin/VBox/TitleLabel
@onready var casts_label: Label = $Panel/Margin/VBox/CastsContainer/CastsLabel
@onready var minus_button: Button = $Panel/Margin/VBox/CastsContainer/MinusButton
@onready var plus_button: Button = $Panel/Margin/VBox/CastsContainer/PlusButton
@onready var per_round_label: Label = $Panel/Margin/VBox/PerRoundLabel
@onready var reset_button: Button = $Panel/Margin/VBox/ResetButton
@onready var close_button: Button = $Panel/Margin/VBox/CloseButton

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
	_populate_spells()


## Closes the dialog.
func close() -> void:
	visible = false
	_unit = null
	dialog_closed.emit()


## Build (once) + populate the faction spell list below the per-round line; hidden if the unit's
## faction has no spells. This dialog shows the full list inline (name · cost · effect) since you
## are already in the caster context — the unit card has the compact hover version.
func _populate_spells() -> void:
	if per_round_label == null:
		return
	var vbox := per_round_label.get_parent()
	if vbox == null:
		return
	if _spells_label == null:
		_spells_label = RichTextLabel.new()
		_spells_label.bbcode_enabled = true
		_spells_label.fit_content = true
		_spells_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_spells_label.custom_minimum_size = Vector2(300, 0)
		vbox.add_child(_spells_label)
		vbox.move_child(_spells_label, per_round_label.get_index() + 1)
	var spells := _resolve_spells()
	if spells.is_empty():
		_spells_label.visible = false
		return
	_spells_label.visible = true
	var am = get_node_or_null("/root/Main/OPRArmyManager")
	var parts := PackedStringArray(["[b]SPELLS[/b]"])
	for sp in spells:
		var nm: String = str(sp.get("name", ""))
		var thr: int = int(sp.get("threshold", 0))
		var eff: String = str(sp.get("effect", ""))
		var head: String = "[b][color=#%s]%s[/color][/b]%s" % [HouseStyle.ACCENT.to_html(false), nm,
			(" (%d)" % thr if thr > 0 else "")]
		var entry: String = head + "\n[color=#%s]%s[/color]" % [HouseStyle.INK.to_html(false), eff]
		# Any special rule the spell grants → append its rule text after the spell text.
		if am and am.has_method("rules_referenced_in") and am.has_method("get_rule_description"):
			for r in am.rules_referenced_in(eff):
				var desc: String = str(am.get_rule_description(r))
				if not desc.is_empty():
					entry += "\n[color=#%s]► [b]%s[/b]: %s[/color]" % [HouseStyle.MUTED.to_html(false), str(r), desc]
		parts.append(entry)
	_spells_label.text = "\n\n".join(parts)


## The current unit's faction spell list, via the OPR army manager (real-game tree path).
func _resolve_spells() -> Array:
	if _unit == null:
		return []
	var am = get_node_or_null("/root/Main/OPRArmyManager")
	if am and am.has_method("get_spells_for_unit"):
		return am.get_spells_for_unit(_unit)
	return []


## Updates the display with current unit data.
func _update_display() -> void:
	if not _unit:
		return

	if title_label:
		title_label.text = "%s - CASTER POINTS" % _unit.get_name().to_upper()

	if casts_label:
		casts_label.text = "%d / %d" % [_unit.casts_current, GameUnit.CASTER_POINTS_CAP]

	if per_round_label:
		per_round_label.text = "+%d PER ROUND" % _unit.casts_per_round

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


## Creates a simple casts dialog programmatically (without scene), in the house style (maintainer D98 = a).
static func create_simple() -> CastsDialog:
	var dialog = CastsDialog.new()
	dialog.name = "CastsDialog"
	var vbox := HouseStyle.dialog_frame(dialog, "CASTS", Vector2(250, 180))

	# Title (per-unit caster-points subtitle, updated in _update_display)
	var title := HouseStyle.label("Caster Points", HouseStyle.CAPTION)
	title.name = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	dialog.title_label = title

	# − current / cap + (the steps press _on_step)
	dialog.casts_label = HouseStyle.label("0 / 6", HouseStyle.VALUE)
	dialog.casts_label.name = "CastsLabel"
	var row := HouseStyle.step_row("CastsContainer", dialog.casts_label, dialog._on_step)
	vbox.add_child(row)
	dialog.minus_button = row.get_node("MinusButton")
	dialog.plus_button = row.get_node("PlusButton")

	# Per round label (the spell list is inserted right under it on first open)
	var per_round := HouseStyle.label("+0 PER ROUND", HouseStyle.CAPTION)
	per_round.name = "PerRoundLabel"
	per_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(per_round)
	dialog.per_round_label = per_round

	# Reset (drops the manual adjustment: a danger line), close (the main action: confirm + dismiss)
	dialog.reset_button = _action(vbox, "ResetButton", "RESET TO PER-ROUND", HouseStyle.DANGER_BUTTON, dialog._on_reset_pressed)
	dialog.reset_button.tooltip_text = "Reset points to per-round value"
	dialog.close_button = _action(vbox, "CloseButton", "CLOSE", HouseStyle.PRIMARY, dialog.close)

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
