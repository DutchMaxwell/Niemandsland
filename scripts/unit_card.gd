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
## Items that GRANT a rule (Combat Shield → Shielded) are shown in this colour so they stand out
## from plain rules; hovering one reveals the granted rule(s) + their descriptions.
const COLOR_ITEM: String = "#ffcc44"
## Faction spells listed on a caster's card (hover → effect); distinct from rules/items.
const COLOR_SPELL: String = "#cc88ff"
const COLOR_DIM: String = "#666666"

# Status colours derived from HudTokens so active/alive/dead/range match the rest of the UI.
var COLOR_RANGE := "#" + HudTokens.CYAN.to_html(false)
var COLOR_ACTIVE := "#" + HudTokens.AMBER.to_html(false)
var COLOR_ALIVE := "#" + HudTokens.SUCCESS.to_html(false)
var COLOR_DEAD := "#" + HudTokens.DANGER.to_html(false)

## Optional reference (set by main.gd) used to resolve OPR special-rule descriptions
## — works for loaded saves + remote units via the session cache.
var army_manager: OPRArmyManager = null
## Optional reference (set by main.gd) used to preview a spell's range ring around the caster on
## hover (purple ring, like the G range rings but temporary). Null → no preview.
var range_ring_controller: Node = null

## Special-rule hover explanation: rules are shown underlined; hovering one for
## RULE_HOVER_DELAY opens a small popup with its full text.
const RULE_HOVER_DELAY: float = 1.0
var _rule_popup: PanelContainer = null
var _rule_popup_label: RichTextLabel = null
var _rule_hover_timer: Timer = null
var _hovered_rule: String = ""

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

	# Special rules (unit-level AND per-weapon) are clickable [url] spans -> underlined;
	# hovering one for ~1s opens a small popup with the rule's full description.
	for lbl: RichTextLabel in [_rules_label, _weapons_label]:
		lbl.meta_underlined = true
		lbl.meta_hover_started.connect(_on_rule_hover_started)
		lbl.meta_hover_ended.connect(_on_rule_hover_ended)
	_setup_rule_popup()

	_rule_hover_timer = Timer.new()
	_rule_hover_timer.one_shot = true
	_rule_hover_timer.wait_time = RULE_HOVER_DELAY
	_rule_hover_timer.timeout.connect(_on_rule_hover_timeout)
	add_child(_rule_hover_timer)

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
	_hovered_rule = ""
	if _rule_hover_timer:
		_rule_hover_timer.stop()
	if _rule_popup:
		_rule_popup.visible = false
	_clear_spell_range_preview()
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
		parts.append("[color=%s]● Activated%s[/color]" % [COLOR_ACTIVE, suffix])
	else:
		parts.append("[color=%s]○ Ready[/color]" % COLOR_DIM)

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
			text += "  •  Wounds:%s [color=%s](%d/%d)[/color]" % [
				_wound_pips(model.wounds_current, model.wounds_max),
				COLOR_BASE, model.wounds_current, model.wounds_max
			]
		else:
			text += "  •  Wounds:[color=%s]%d[/color]/%d" % [COLOR_COST, cur_total, max_total]

	return text

func _wound_pips(current: int, maximum: int) -> String:
	var filled := PIP_FILLED.repeat(max(0, current))
	var empty := PIP_EMPTY.repeat(max(0, maximum - current))
	return "[color=%s]%s[/color][color=%s]%s[/color]" % [COLOR_ALIVE, filled, COLOR_DIM, empty]

func _build_weapons_text() -> String:
	var opr_unit := _get_opr_unit()
	if opr_unit and opr_unit.weapons.size() > 0:
		var lines: Array[String] = ["[b]Weapons[/b]"]
		for weapon in opr_unit.weapons:
			lines.append("  " + _format_opr_weapon(weapon))
		return "\n".join(lines)

	# Fallback for non-OPR units: aggregate from the first model.
	if _current_unit.models.size() > 0:
		var weapons: Array = _current_unit.models[0].get_weapons()
		if not weapons.is_empty():
			var lines: Array[String] = ["[b]Weapons[/b]"]
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
		parts.append("(%s)" % _rule_url_list(weapon.special_rules))

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
		text += " (%s)" % _rule_url_list(rules)
	return text


## Render rule names as underlined [url] spans so hovering one shows its description
## (the [url] meta is the rule name -> _on_rule_hover_* -> get_rule_description).
func _rule_url_list(rules) -> String:
	var spans: Array[String] = []
	for r in rules:
		var rname := str(r)
		spans.append("[url=%s][color=%s]%s[/color][/url]" % [rname, COLOR_RULES, rname])
	return ", ".join(spans)


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

	# item -> granted rules, read from unit_properties so the cascade survives save/load + MP sync
	# (a synced/loaded unit may not carry the live OPRUnit object).
	var item_grants := _item_grants()

	if not rules.is_empty():
		# A rule an item GRANTS (Combat Shield → Shielded) is reached by hovering the item, not
		# listed as a flat sibling — collect those names to hide from the top line.
		var granted_by_item := {}
		for it in item_grants:
			for g in item_grants[it]:
				granted_by_item[str(g)] = true
		# Each entry is an underlined [url] span; hovering it ~1s opens a popup (see
		# _on_rule_hover_*). An item that grants rules shows in the item colour; its popup lists
		# the granted rule(s) + their descriptions instead of the item's own (often empty).
		var rule_spans: Array[String] = []
		var seen := {}
		for rule_name in rules:
			if granted_by_item.has(rule_name):
				continue  # revealed via its granting item's hover cascade
			if seen.has(rule_name):
				continue  # an item name can sit in both equipment + special_rules
			seen[rule_name] = true
			var col: String = COLOR_ITEM if item_grants.has(rule_name) else COLOR_RULES
			rule_spans.append("[url=%s][color=%s]%s[/color][/url]" % [rule_name, col, rule_name])
		lines.append("[b]Rules:[/b] %s" % ", ".join(rule_spans))

	# Caster units: list the faction's spells (name + casting cost; hover → effect).
	if _current_unit.has_method("is_caster") and _current_unit.is_caster():
		var spell_spans: Array[String] = []
		for sp in _faction_spells():
			var sname: String = str(sp.get("name", ""))
			if sname.is_empty():
				continue
			var thr: int = int(sp.get("threshold", 0))
			var lbl: String = "%s (%d)" % [sname, thr] if thr > 0 else sname
			spell_spans.append("[url=spell:%s][color=%s]%s[/color][/url]" % [sname, COLOR_SPELL, lbl])
		if not spell_spans.is_empty():
			lines.append("[b]Spells:[/b] %s" % ", ".join(spell_spans))

	return "\n".join(lines)


## Builds the small hover popup used for rule explanations (created once).
func _setup_rule_popup() -> void:
	_rule_popup = PanelContainer.new()
	_rule_popup.top_level = true  # position in absolute canvas space, not relative to the card
	_rule_popup.visible = false
	_rule_popup.z_index = 4096
	_rule_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.07, 0.10, 0.97)
	bg.border_color = Color(HudTokens.CYAN.r, HudTokens.CYAN.g, HudTokens.CYAN.b, 0.6)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(8)
	_rule_popup.add_theme_stylebox_override("panel", bg)
	_rule_popup_label = RichTextLabel.new()
	_rule_popup_label.bbcode_enabled = true
	_rule_popup_label.fit_content = true
	_rule_popup_label.scroll_active = false
	_rule_popup_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rule_popup_label.custom_minimum_size = Vector2(280, 0)
	_rule_popup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rule_popup_label.add_theme_font_override("bold_font", HudTokens.bold_font())
	_rule_popup.add_child(_rule_popup_label)
	add_child(_rule_popup)


func _on_rule_hover_started(meta: Variant) -> void:
	_hovered_rule = str(meta)
	if _rule_hover_timer:
		_rule_hover_timer.start()
	# Spell with a radius → preview its reach around the caster immediately (the effect popup
	# still follows after the hover delay).
	if _hovered_rule.begins_with("spell:"):
		_show_spell_range_preview(_hovered_rule.substr(6))


func _on_rule_hover_ended(_meta: Variant) -> void:
	_hovered_rule = ""
	if _rule_hover_timer:
		_rule_hover_timer.stop()
	if _rule_popup:
		_rule_popup.visible = false
	_clear_spell_range_preview()


## Show a purple range ring of the spell's radius around the caster's models (no ring if the spell
## has no range). Reuses the G-ring controller's separate spell-preview layer.
func _show_spell_range_preview(spell_name: String) -> void:
	if range_ring_controller == null or not range_ring_controller.has_method("show_spell_preview"):
		return
	var radius := OPRApiClient.spell_radius_inches(_spell_effect(spell_name))
	if radius <= 0:
		return
	range_ring_controller.show_spell_preview(_caster_model_nodes(), radius)


func _clear_spell_range_preview() -> void:
	if range_ring_controller and range_ring_controller.has_method("clear_spell_preview"):
		range_ring_controller.clear_spell_preview()


## The table model nodes of the current (caster) unit — where the spell-range ring is anchored.
func _caster_model_nodes() -> Array:
	var nodes: Array = []
	if _current_unit:
		for m in _current_unit.models:
			if m and is_instance_valid(m.node):
				nodes.append(m.node)
	return nodes


func _on_rule_hover_timeout() -> void:
	if _hovered_rule.is_empty() or not _rule_popup:
		return
	var item_grants := _item_grants()
	var text := ""
	if _hovered_rule.begins_with("spell:"):
		# Faction spell → show its effect, then any special rule it grants (spell text + rule text).
		var spell_name := _hovered_rule.substr(6)
		var effect := _spell_effect(spell_name)
		text = "[b][color=%s]%s[/color][/b]\n%s" % [
			COLOR_SPELL, spell_name, effect if not effect.is_empty() else "[i]No description available.[/i]"]
		if not effect.is_empty() and army_manager and army_manager.has_method("rules_referenced_in"):
			for r in army_manager.rules_referenced_in(effect):
				text += "\n\n[b][color=%s]%s[/color][/b]\n%s" % [COLOR_RULES, str(r), _resolve_rule_desc(str(r))]
	elif item_grants.has(_hovered_rule):
		# Item → cascade: this entry is an item; show the rule(s) it grants + each description,
		# instead of the item's own (usually empty) description.
		text = "[b][color=%s]%s[/color][/b]\n[i][color=%s]Grants:[/color][/i]" % [
			COLOR_ITEM, _hovered_rule, COLOR_DIM]
		for g in item_grants[_hovered_rule]:
			text += "\n[b][color=%s]%s[/color][/b]\n%s" % [COLOR_RULES, str(g), _resolve_rule_desc(str(g))]
	else:
		text = "[b][color=%s]%s[/color][/b]\n%s" % [COLOR_RULES, _hovered_rule, _resolve_rule_desc(_hovered_rule)]
	_rule_popup_label.text = text
	_rule_popup.reset_size()
	# Place near the cursor, clamped to stay on screen.
	var pos := get_global_mouse_position() + Vector2(16, 16)
	var vp := get_viewport_rect().size
	pos.x = min(pos.x, vp.x - _rule_popup.size.x - 8)
	pos.y = min(pos.y, vp.y - _rule_popup.size.y - 8)
	_rule_popup.global_position = pos
	_rule_popup.visible = true


## Resolve a rule's OPR description (or a placeholder) for the hover popup.
func _resolve_rule_desc(rule_name: String) -> String:
	var desc := ""
	if army_manager and army_manager.has_method("get_rule_description"):
		desc = army_manager.get_rule_description(rule_name)
	if desc.is_empty():
		desc = "[i]No description available.[/i]"
	return desc


## The faction's spell list for the current (caster) unit, via the army manager.
func _faction_spells() -> Array:
	if army_manager and army_manager.has_method("get_spells_for_unit"):
		return army_manager.get_spells_for_unit(_current_unit)
	return []


## The effect text of a faction spell by name (or "" if not found).
func _spell_effect(spell_name: String) -> String:
	for sp in _faction_spells():
		if str(sp.get("name", "")) == spell_name:
			return str(sp.get("effect", ""))
	return ""


## Item → granted-rules map for the current unit, from unit_properties (persists + MP-syncs).
func _item_grants() -> Dictionary:
	if _current_unit and _current_unit.unit_properties is Dictionary:
		var g: Variant = _current_unit.unit_properties.get("item_grants", {})
		if g is Dictionary:
			return g
	return {}


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
	return "[b]Joined Hero:[/b] [color=%s]%s[/color]" % [COLOR_RULES, ", ".join(parts)]

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
