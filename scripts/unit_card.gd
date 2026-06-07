extends PanelContainer
class_name UnitCard
## Persistent, docked card for the currently selected unit.
## Combines static OPR data (quality, defense, cost, base, weapons, rules) with
## live battle state (alive models, wounds, activation, fatigue/shaken, caster
## points). Auto-shown on unit selection, refreshes its dynamic fields on a timer
## while visible. Unlike OPRStatsTooltip it stays docked and does not follow the
## cursor.

# ===== Constants =====

## Inset from the bottom-left corner of the viewport (pixels).
const MARGIN_FROM_EDGE: int = 16

## Interval for refreshing live state while the card is visible (seconds).
const REFRESH_INTERVAL: float = 0.3

# Gameplay stat sub-palette — a deliberate domain palette (quality/defense/cost/base/melee).
const COLOR_QUALITY: String = "#88ff88"
const COLOR_DEFENSE: String = "#8888ff"
const COLOR_COST: String = "#ffcc44"
const COLOR_BASE: String = "#cccccc"
const COLOR_MELEE: String = "#ff8888"
const COLOR_RULES: String = "#aaaaaa"
const COLOR_DIM: String = "#666666"

# Status colours derived from HudTokens so active/alive/dead/range match the rest of the UI.
var COLOR_RANGE := "#" + HudTokens.CYAN.to_html(false)
var COLOR_ACTIVE := "#" + HudTokens.AMBER.to_html(false)
var COLOR_ALIVE := "#" + HudTokens.SUCCESS.to_html(false)
var COLOR_DEAD := "#" + HudTokens.DANGER.to_html(false)

const PIP_FILLED: String = "▮"
const PIP_EMPTY: String = "▯"

# ===== Signals =====

## Emitted when the user dismisses the card via the close button.
signal closed()

# ===== Node References =====

@onready var _name_label: RichTextLabel = $MarginContainer/VBox/Header/NameLabel
@onready var _close_button: Button = $MarginContainer/VBox/Header/CloseButton
@onready var _stats_label: RichTextLabel = $MarginContainer/VBox/StatsLabel
@onready var _status_label: RichTextLabel = $MarginContainer/VBox/StatusLabel
@onready var _wounds_label: RichTextLabel = $MarginContainer/VBox/WoundsLabel
@onready var _separator: HSeparator = $MarginContainer/VBox/Separator
@onready var _weapons_label: RichTextLabel = $MarginContainer/VBox/WeaponsLabel
@onready var _rules_label: RichTextLabel = $MarginContainer/VBox/RulesLabel

# ===== Private Vars =====

## Unit currently displayed.
var _current_unit: GameUnit = null

## Additional distinct units in the selection (shown as "+N" in the header).
var _extra_units: int = 0

## Timer that drives live refreshes while visible.
var _refresh_timer: Timer = null

# ===== Lifecycle =====

func _ready() -> void:
	visible = false
	_close_button.pressed.connect(_on_close_pressed)

	# Tactical chrome: deep-navy glass panel + corner-bracket frame.
	add_theme_stylebox_override("panel", HudTokens.panel_style())
	var frame := HudFrame.new()
	frame.bracket_length = 12.0
	add_child(frame)

	# Real bold glyphs (Inter weight axis) directly on each label, so [b] names/headers
	# never faux-bold even if the card doesn't inherit the themed HUD.
	var bold := HudTokens.bold_font()
	for rtl: RichTextLabel in [_name_label, _stats_label, _status_label, _wounds_label, _weapons_label, _rules_label]:
		rtl.add_theme_font_override("bold_font", bold)
	_name_label.add_theme_font_size_override("bold_font_size", 22)  # larger, prominent unit name

	_refresh_timer = Timer.new()
	_refresh_timer.one_shot = false
	_refresh_timer.wait_time = REFRESH_INTERVAL
	_refresh_timer.timeout.connect(_refresh_dynamic)
	add_child(_refresh_timer)

# ===== Public Methods =====

## Shows the card for the given unit. extra_units indicates how many further
## distinct units are part of the same selection.
func show_unit(unit: GameUnit, extra_units: int = 0) -> void:
	if not unit:
		clear()
		return

	_current_unit = unit
	_extra_units = max(0, extra_units)
	_build_static()
	_refresh_dynamic()
	visible = true

	if _refresh_timer:
		_refresh_timer.start()

## Hides the card and stops live refreshes.
func clear() -> void:
	_current_unit = null
	_extra_units = 0
	visible = false
	if _refresh_timer:
		_refresh_timer.stop()

# ===== Private Methods =====

func _on_close_pressed() -> void:
	clear()
	closed.emit()

## Builds the content that does not change during play (weapons, rules, base).
func _build_static() -> void:
	if not _current_unit:
		return

	var weapons_text := _build_weapons_text()
	if weapons_text.is_empty():
		_weapons_label.visible = false
		_separator.visible = false
	else:
		_weapons_label.text = weapons_text
		_weapons_label.visible = true
		_separator.visible = true

	var rules_text := _build_rules_text()
	if rules_text.is_empty():
		_rules_label.visible = false
	else:
		_rules_label.text = rules_text
		_rules_label.visible = true

	_stats_label.text = _build_stats_text()

## Refreshes the live battle state (name count, status, wounds) and repositions.
func _refresh_dynamic() -> void:
	if not _current_unit:
		return

	_name_label.text = _build_name_text()
	_status_label.text = _build_status_text()
	_wounds_label.text = _build_wounds_text()

	reset_size()
	_apply_position()

## Pins the card to the bottom-left corner of the viewport.
func _apply_position() -> void:
	var vp := get_viewport()
	if not vp:
		return
	var vp_size := vp.get_visible_rect().size
	global_position = Vector2(MARGIN_FROM_EDGE, vp_size.y - size.y - MARGIN_FROM_EDGE)

# ===== Content Builders =====

func _build_name_text() -> String:
	var alive := _current_unit.get_alive_count()
	var total := _model_count()
	var alive_color := _alive_color(alive, total)
	var text := "[b]%s[/b]  [color=%s]%d[/color]/%d" % [
		_current_unit.get_name(), alive_color, alive, total
	]
	if _extra_units > 0:
		text += "  [color=%s](+%d)[/color]" % [COLOR_DIM, _extra_units]
	return text

func _build_stats_text() -> String:
	var quality := _current_unit.get_quality()
	var defense := _current_unit.get_defense()
	var parts: Array[String] = []
	if quality > 0:
		parts.append("Q [color=%s]%d+[/color]" % [COLOR_QUALITY, quality])
	if defense > 0:
		parts.append("D [color=%s]%d+[/color]" % [COLOR_DEFENSE, defense])
	var cost := _current_unit.get_cost()
	if cost > 0:
		parts.append("[color=%s]%d pts[/color]" % [COLOR_COST, cost])

	var base_text := _build_base_text()
	if not base_text.is_empty():
		parts.append("[color=%s]%s[/color]" % [COLOR_BASE, base_text])

	return "  |  ".join(parts)

func _build_base_text() -> String:
	var opr_unit := _get_opr_unit()
	if not opr_unit:
		return ""
	if opr_unit.base_is_oval:
		return "%dx%dmm oval" % [opr_unit.base_width_mm, opr_unit.base_depth_mm]
	return "%dmm round" % opr_unit.base_size_round

func _build_status_text() -> String:
	var parts: Array[String] = []

	if _current_unit.is_activated:
		var suffix := ""
		if _current_unit.activation_round > 0:
			suffix = " (R%d)" % _current_unit.activation_round
		parts.append("[color=%s]● Aktiviert%s[/color]" % [COLOR_ACTIVE, suffix])
	else:
		parts.append("[color=%s]○ Bereit[/color]" % COLOR_DIM)

	parts.append(_token_text("F", _current_unit.is_fatigued, COLOR_COST))
	parts.append(_token_text("S", _current_unit.is_shaken, COLOR_DEAD))

	if _current_unit.is_caster():
		parts.append("[color=%s]Casts %d/%d[/color]" % [
			COLOR_RANGE, _current_unit.casts_current, GameUnit.CASTER_POINTS_CAP
		])

	return "   ".join(parts)

func _token_text(letter: String, active: bool, active_color: String) -> String:
	if active:
		return "[color=%s][b]%s[/b][/color]" % [active_color, letter]
	return "[color=%s]%s[/color]" % [COLOR_DIM, letter]

func _build_wounds_text() -> String:
	var total := _model_count()
	var alive := _current_unit.get_alive_count()
	var text := "Models: [color=%s]%d[/color]/%d" % [_alive_color(alive, total), alive, total]

	var cur_total := 0
	var max_total := 0
	for model in _current_unit.models:
		max_total += model.wounds_max
		if model.is_alive:
			cur_total += model.wounds_current

	# Only show wound detail when at least one model has Tough (multiple wounds).
	if max_total > _current_unit.models.size():
		if _current_unit.models.size() == 1:
			# Single-model unit (hero/monster): show pips for its wounds.
			var model := _current_unit.models[0]
			text += "  •  Wunden: %s [color=%s](%d/%d)[/color]" % [
				_wound_pips(model.wounds_current, model.wounds_max),
				COLOR_BASE, model.wounds_current, model.wounds_max
			]
		else:
			text += "  •  Wunden: [color=%s]%d[/color]/%d" % [COLOR_COST, cur_total, max_total]

	return text

func _wound_pips(current: int, maximum: int) -> String:
	var filled := PIP_FILLED.repeat(max(0, current))
	var empty := PIP_EMPTY.repeat(max(0, maximum - current))
	return "[color=%s]%s[/color][color=%s]%s[/color]" % [COLOR_ALIVE, filled, COLOR_DIM, empty]

func _build_weapons_text() -> String:
	var opr_unit := _get_opr_unit()
	if opr_unit and opr_unit.weapons.size() > 0:
		var lines: Array[String] = ["[b]Waffen[/b]"]
		for weapon in opr_unit.weapons:
			lines.append("  " + _format_opr_weapon(weapon))
		return "\n".join(lines)

	# Fallback for non-OPR units: aggregate from the first model.
	if _current_unit.models.size() > 0:
		var weapons: Array = _current_unit.models[0].get_weapons()
		if not weapons.is_empty():
			var lines: Array[String] = ["[b]Waffen[/b]"]
			for weapon in weapons:
				lines.append("  " + _format_dict_weapon(weapon))
			return "\n".join(lines)

	return ""

func _format_opr_weapon(weapon: OPRApiClient.OPRWeapon) -> String:
	var parts: Array[String] = []
	if weapon.count > 1:
		parts.append("%dx %s" % [weapon.count, weapon.name])
	else:
		parts.append(weapon.name)

	if weapon.range_value > 0:
		parts.append("[color=%s]%d\"[/color]" % [COLOR_RANGE, weapon.range_value])
	else:
		parts.append("[color=%s]Melee[/color]" % COLOR_MELEE)

	parts.append("A%d" % weapon.attacks)

	if weapon.special_rules.size() > 0:
		parts.append("[color=%s](%s)[/color]" % [COLOR_RULES, ", ".join(weapon.special_rules)])

	return " ".join(parts)

func _format_dict_weapon(weapon: Variant) -> String:
	if not (weapon is Dictionary):
		return str(weapon)
	var w_name: String = weapon.get("name", "Unknown")
	var w_range: int = int(weapon.get("range", 0))
	var w_attacks: int = int(weapon.get("attacks", 1))
	var range_str := "[color=%s]Melee[/color]" % COLOR_MELEE
	if w_range > 0:
		range_str = "[color=%s]%d\"[/color]" % [COLOR_RANGE, w_range]
	var text := "%s %s A%d" % [w_name, range_str, w_attacks]
	# Special rules ride on the weapon dict (synced over the network for remote units).
	var rules := _dict_weapon_rule_names(weapon)
	if not rules.is_empty():
		text += " [color=%s](%s)[/color]" % [COLOR_RULES, ", ".join(rules)]
	return text


## Extracts a weapon dict's special-rule names, handling both string entries
## ("Blast(3)") and object entries ({"name": "AP", "rating": 1}), and both the
## camelCase "specialRules" and snake_case "special_rules" keys.
func _dict_weapon_rule_names(weapon: Dictionary) -> Array[String]:
	var raw: Variant = weapon.get("specialRules", weapon.get("special_rules", []))
	var names: Array[String] = []
	if not (raw is Array):
		return names
	for rule in raw:
		if rule is String:
			if not rule.is_empty():
				names.append(rule)
		elif rule is Dictionary:
			var rule_name: String = str(rule.get("name", ""))
			if rule_name.is_empty():
				continue
			var rating: Variant = rule.get("rating", null)
			if rating != null and str(rating) != "":
				names.append("%s(%s)" % [rule_name, str(rating)])
			else:
				names.append(rule_name)
	return names

func _build_rules_text() -> String:
	var lines: Array[String] = []

	# Joined Heroes shown as part of the unit.
	var attached_text := _build_attached_heroes_text()
	if not attached_text.is_empty():
		lines.append(attached_text)

	var rules: Array[String] = []
	var opr_unit := _get_opr_unit()
	if opr_unit:
		rules.append_array(opr_unit.equipment)
		rules.append_array(opr_unit.special_rules)
	else:
		for rule in _current_unit.get_special_rules():
			if rule is String:
				rules.append(rule)
			elif rule is Dictionary:
				rules.append(str(rule.get("name", "")))

	if not rules.is_empty():
		lines.append("[b]Regeln:[/b] [color=%s]%s[/color]" % [COLOR_RULES, ", ".join(rules)])

	return "\n".join(lines)


## Lists Heroes joined to this unit (name + Q/D), or "" if none.
func _build_attached_heroes_text() -> String:
	var parts: Array[String] = []
	for hero in _current_unit.get_attached_heroes():
		if hero is GameUnit:
			parts.append("%s [color=%s]Q%d+[/color] [color=%s]D%d+[/color]" % [
				hero.get_name(), COLOR_QUALITY, hero.get_quality(), COLOR_DEFENSE, hero.get_defense()
			])
	if parts.is_empty():
		return ""
	return "[b]Angeschlossener Held:[/b] [color=%s]%s[/color]" % [COLOR_RULES, ", ".join(parts)]

# ===== Helpers =====

## Returns the OPRUnit backing this unit, or null for non-OPR units.
func _get_opr_unit() -> OPRApiClient.OPRUnit:
	if _current_unit.source_type == "opr" and _current_unit.source_data:
		return _current_unit.source_data as OPRApiClient.OPRUnit
	return null

## Number of models in the unit (falls back to the declared size).
func _model_count() -> int:
	var count := _current_unit.models.size()
	if count == 0:
		return _current_unit.get_size()
	return count

func _alive_color(alive: int, total: int) -> String:
	if alive == 0:
		return COLOR_DEAD
	if alive < total:
		return COLOR_COST
	return COLOR_ALIVE
