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
		var head: String = "[b][color=#cc88ff]%s[/color][/b]%s" % [nm, (" (%d)" % thr if thr > 0 else "")]
		var entry: String = head + "\n[color=#aaaaaa]" + eff + "[/color]"
		# Any special rule the spell grants → append its rule text after the spell text.
		if am and am.has_method("rules_referenced_in") and am.has_method("get_rule_description"):
			for r in am.rules_referenced_in(eff):
				var desc: String = str(am.get_rule_description(r))
				if not desc.is_empty():
					entry += "\n[color=#888888]► [b]%s[/b]: %s[/color]" % [str(r), desc]
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


## Creates a simple casts dialog programmatically (without scene).
static func create_simple() -> CastsDialog:
	var dialog = CastsDialog.new()
	dialog.name = "CastsDialog"
	dialog.theme = ThemeManager.get_current_theme()  # so PrimaryButton/DangerButton variations resolve
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

	# Create centered panel container (deep-navy glass + hairline + shadow chrome)
	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(250, 180)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", HudTokens.panel_style())
	dialog.add_child(panel)

	# Inner margin so content clears the corner-bracket chrome
	var margin = MarginContainer.new()
	margin.name = "Margin"
	UiPolish.set_dialog_margins(margin)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(margin)

	# VBox container
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", HudTokens.SECTION_SEP)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(vbox)

	# Tactical header (Orbitron title + amber index + accent line)
	vbox.add_child(HudTokens.header("CASTS", "/// CAST"))

	# Title (per-unit caster-points subtitle, updated in _update_display)
	var title = Label.new()
	title.name = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "Caster Points"
	title.add_theme_font_override("font", HudTokens.mono_font())
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", UiPolish.TEXT_MUTED)
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
	per_round.text = "+0 PER ROUND"
	per_round.add_theme_font_override("font", HudTokens.mono_font())
	per_round.add_theme_font_size_override("font_size", 12)
	per_round.add_theme_color_override("font_color", UiPolish.TEXT_MUTED)
	vbox.add_child(per_round)
	dialog.per_round_label = per_round

	# Reset button (destructive: clears manual adjustment)
	var reset_btn = Button.new()
	reset_btn.name = "ResetButton"
	reset_btn.text = "RESET TO PER-ROUND"
	reset_btn.tooltip_text = "Reset points to per-round value"
	reset_btn.theme_type_variation = "DangerButton"
	vbox.add_child(reset_btn)
	dialog.reset_button = reset_btn

	# Close button (primary action: confirm + dismiss)
	var close_btn = Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "CLOSE"
	close_btn.theme_type_variation = "PrimaryButton"
	vbox.add_child(close_btn)
	dialog.close_button = close_btn

	# Corner-bracket chrome on top (instrumentation look), as the LAST panel child
	var frame = HudFrame.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(frame)

	# Connect signals directly
	minus_btn.pressed.connect(dialog._on_minus_pressed)
	plus_btn.pressed.connect(dialog._on_plus_pressed)
	reset_btn.pressed.connect(dialog._on_reset_pressed)
	close_btn.pressed.connect(dialog.close)

	# Mark signals as connected to prevent double connection in _ready
	dialog._signals_connected = true

	return dialog
