class_name CardFace
extends RefCounted
## Builds the unit-card CONTENT in the house style (scripts/hud/house_style.gd — the dice window's design,
## maintainer 23.09.: a visual alignment only; every word, number, tag, rule, state and warning stays).
## One builder feeds BOTH the presented card and the compact strip card (Handover D7), so the layout
## stays consistent. Pure view: it takes a plain data Dictionary and returns a Control; it never reads
## game state directly. Nothing is trimmed: long names and weapon names wrap, links wrap inside the card.
##
## data = { name:String, points:int, quality:int, defense:int, alive:int, total:int,
##          activated:bool, fatigued:bool, shaken:bool, caster:bool, coherent:bool, dead:bool,
##          player_color:Color }

const PAD := HouseStyle.PAD_PANEL
const PAD_COMPACT := 10
const NAME_FLOOR := 96      # a wrapping label is measured at width 0 first — never below this
const WEAPON_FLOOR := 72


## Presented card content (the big card). `on_action` (optional) is called with the action kind string
## ("activation"/"fatigued"/"shaken"/"casts"/"wounds"/"details"/"revive") when an action chip is pressed;
## the dock connects it to _card_action. Left empty for strip cards (and the dev preview): the chips are
## then plain display pills and the card is the compact strip layout. `card_w` is the card's width.
static func build_presented(data: Dictionary, on_action: Callable = Callable(), collapse_weapons: bool = false,
		card_w: float = 320.0) -> Control:
	var compact := not on_action.is_valid()
	var pad: int = PAD_COMPACT if compact else PAD
	var inner: float = card_w - 2.0 * pad
	var margin := MarginContainer.new()
	margin.theme = HouseStyle.theme()
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", HouseStyle.GAP_ROW if compact else HouseStyle.GAP_SECTION)
	margin.add_child(col)
	var dead := bool(data.get("dead", false))

	# Header: the name (a step smaller past 20 characters, wrapping — never trimmed) and the points.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
	var name_text := str(data.get("name", "Unit"))
	var name_lbl := _label(name_text, (19 if name_text.length() <= 20 else 15) - (2 if compact else 0), HouseStyle.INK)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.custom_minimum_size = Vector2(NAME_FLOOR, 0)
	header.add_child(name_lbl)
	var pts := _label("%d pts" % int(data.get("points", 0)), 13 if compact else 14, HouseStyle.GOLD)
	pts.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	header.add_child(pts)
	col.add_child(header)

	# Stats: Quality, Defense and the alive counter (red when destroyed, warn when wounded).
	var alive := int(data.get("alive", 0))
	var total := int(data.get("total", 0))
	var counter_color := HouseStyle.INK
	if dead or alive == 0:
		counter_color = HouseStyle.DANGER
	elif alive < total:
		counter_color = HouseStyle.WARN
	var q := "%d+" % int(data.get("quality", 0))
	var d := "%d+" % int(data.get("defense", 0))
	var count := "%d/%d" % [alive, total]
	col.add_child(_stats_compact(q, d, count, counter_color) if compact else _stats_boxes(q, d, count, counter_color))

	# Status pills: on the presented card they ARE the controls (a click toggles the state / opens the
	# wound or cast window); strip cards get display pills. A flow, so extra pills wrap.
	var strip := HFlowContainer.new()
	strip.add_theme_constant_override("h_separation", 5)
	strip.add_theme_constant_override("v_separation", 6)
	if dead:
		strip.add_child(_status_chip("↺ Revive", false, HouseStyle.TONE_ACCENT, compact, on_action, "revive"))
	else:
		strip.add_child(_status_chip("Activated", bool(data.get("activated", false)), HouseStyle.TONE_GOLD, compact, on_action, "activation"))
		strip.add_child(_status_chip("Fatigued", bool(data.get("fatigued", false)), HouseStyle.TONE_WARN, compact, on_action, "fatigued"))
		strip.add_child(_status_chip("Shaken", bool(data.get("shaken", false)), HouseStyle.TONE_WARN, compact, on_action, "shaken"))
		if bool(data.get("caster", false)):
			strip.add_child(_status_chip("Caster", true, HouseStyle.TONE_ACCENT, compact, on_action, "casts"))
		if bool(data.get("woundable", false)):
			strip.add_child(_status_chip("✚ Wounds", false, HouseStyle.TONE_WARN, compact, on_action, "wounds"))
	col.add_child(strip)

	# Weapons — one row per distinct weapon (name+count · range, attacks, AP), its rules as links below.
	# data.weapons = [{name, meta, rules}] from the dock's distributed-loadout aggregation (D8 reuse).
	var weapons: Array = data.get("weapons", [])
	if not weapons.is_empty() and not dead:
		if collapse_weapons:
			# Strip-size fallback (bus 033; no live caller): the weapon names on one wrapping line.
			var names: Array[String] = []
			for w in weapons:
				names.append(str((w as Dictionary).get("name", "")))
			var summary := _label("⚔ " + ", ".join(names), 11, HouseStyle.MUTED)
			summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			summary.custom_minimum_size = Vector2(inner, 0)
			col.add_child(summary)
		else:
			var list := VBoxContainer.new()
			list.add_theme_constant_override("separation", 2 if compact else 3)
			for i in weapons.size():
				var w := weapons[i] as Dictionary
				if i > 0 and not compact:
					list.add_child(_rule(HouseStyle.LINE))
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
				var nm := _label(str(w.get("name", "")), 12 if compact else 13, HouseStyle.INK)
				nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				nm.custom_minimum_size = Vector2(WEAPON_FLOOR, 0)
				row.add_child(nm)
				var meta := _label(str(w.get("meta", "")), 12 if compact else 13, HouseStyle.ACCENT)
				meta.vertical_alignment = VERTICAL_ALIGNMENT_TOP
				row.add_child(meta)
				list.add_child(row)
				var wr := str(w.get("rules", ""))
				if not wr.is_empty():
					list.add_child(_weapon_rules_list(wr.split(", ", false), compact, inner))
			col.add_child(list)

	# Rules + Spells — each name is a hover target (the dock wires its description tooltip and, for a
	# spell, the range ring). This absorbs the old detail Info card; there is no Info button.
	if not dead:
		for part in _rules_list(data, compact, inner):
			col.add_child(part)

	# Warn strip (only when out of coherency and not dead).
	if not bool(data.get("coherent", true)) and not dead:
		col.add_child(_warning_strip("⚠  Out of coherency", compact))

	return margin


## Quality / Defense / alive counter as the mockup's three stat boxes: the value over its glyph.
static func _stats_boxes(q: String, d: String, count: String, count_color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
	row.add_child(_stat_box(q, "Q", HouseStyle.INK))
	row.add_child(_stat_box(d, "D", HouseStyle.INK))
	row.add_child(_stat_box(count, "", count_color))
	return row


static func _stat_box(value: String, glyph: String, color: Color) -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	var val := _label(value, 20, color)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(val)
	if not glyph.is_empty():
		var g := HouseStyle.label(glyph, HouseStyle.EYEBROW)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(g)
	var box := HouseStyle.card(v)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box


## The strip card's narrow stat line: [Q 3+] [D 3+] … 3/3.
static func _stats_compact(q: String, d: String, count: String, count_color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for pair: Array in [["Q", q], ["D", d]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		h.add_child(HouseStyle.label(pair[0], HouseStyle.EYEBROW))
		h.add_child(_label(pair[1], 15, HouseStyle.INK))
		var chip := HouseStyle.card(h)
		chip.add_theme_stylebox_override(&"panel", HouseStyle.pill_box(HouseStyle.TONE_ACCENT, false))
		row.add_child(chip)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_label(count, 16, count_color))
	return row


## Unit rules + spells: a caption ("Rules" / "Spells") over a flow of links. The dock finds and wires
## every RuleLink. Returns [] when there is nothing to show. Spell links are keyed "spell:<name>".
static func _rules_list(data: Dictionary, compact: bool, inner: float) -> Array:
	var parts: Array = []
	var rule_names: Array = data.get("rules_list", [])
	var spells: Array = data.get("spells", []) if bool(data.get("caster", false)) else []
	var px := 11 if compact else 13
	if not rule_names.is_empty():
		parts.append(HouseStyle.label("Rules", HouseStyle.EYEBROW))
		var flow := _flow("RulesList")
		for r in rule_names:
			flow.add_child(RuleLink.make(str(r), str(r), HouseStyle.TONE_ACCENT, px, inner))
		parts.append(flow)
	if not spells.is_empty():
		var cap := HouseStyle.label("Spells", HouseStyle.EYEBROW)
		cap.add_theme_color_override(&"font_color", HouseStyle.GOLD)
		parts.append(cap)
		var flow := _flow("SpellsList")
		for s in spells:
			var sd := s as Dictionary
			flow.add_child(RuleLink.make("%s (%d+)" % [str(sd.get("name", "")), int(sd.get("threshold", 0))],
				"spell:" + str(sd.get("name", "")), HouseStyle.TONE_GOLD, px, inner))
		parts.append(flow)
	return parts


## A weapon's named special rules as hover/click targets (maintainer #5), wired by the dock alongside
## the unit rules.
static func _weapon_rules_list(names: PackedStringArray, compact: bool, inner: float) -> Control:
	var flow := _flow("WeaponRules")
	for nm in names:
		var t := nm.strip_edges()
		if not t.is_empty():
			flow.add_child(RuleLink.make(t, t, HouseStyle.TONE_MUTED, 11 if compact else 12, inner))
	return flow


# === Pieces ===

static func _flow(node_name: String) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.name = node_name
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 4)
	return flow


static func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func _rule(color: Color) -> Control:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, HouseStyle.BORDER)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A status pill. On the presented card it is CLICKABLE (on_action wired + a kind): clicking toggles the
## state / opens the wound or cast window — the chips ARE the controls (maintainer). On strip cards (no
## on_action) it is a plain lit/unlit display pill.
static func _status_chip(text: String, lit: bool, tone: StringName, compact: bool, on_action: Callable = Callable(),
		kind: String = "") -> Control:
	var px := 11 if compact else 12
	if not (on_action.is_valid() and not kind.is_empty()):
		var box := PanelContainer.new()
		box.add_theme_stylebox_override(&"panel", HouseStyle.pill_box(tone, lit))
		box.add_child(_label(text, px, HouseStyle.pill_ink(tone, lit)))
		return box
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override(&"font_size", px)
	for c: StringName in [&"font_color", &"font_pressed_color", &"font_hover_pressed_color"]:
		b.add_theme_color_override(c, HouseStyle.pill_ink(tone, lit))
	b.add_theme_color_override(&"font_hover_color", HouseStyle.pill_ink(tone, lit) if lit else HouseStyle.INK)
	b.add_theme_stylebox_override(&"normal", HouseStyle.pill_box(tone, lit))
	b.add_theme_stylebox_override(&"hover", HouseStyle.pill_box(tone, lit, true))
	b.add_theme_stylebox_override(&"pressed", HouseStyle.pill_box(tone, not lit))
	b.add_theme_stylebox_override(&"hover_pressed", HouseStyle.pill_box(tone, not lit, true))
	b.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	b.pressed.connect(func() -> void: on_action.call(kind))
	return b


static func _warning_strip(text: String, compact: bool) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override(&"panel", HouseStyle.warning_box())
	var l := _label(text, 12 if compact else 13, HouseStyle.WARN)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(NAME_FLOOR, 0)
	box.add_child(l)
	return box
