class_name CardFace
extends RefCounted
## Builds the unit-card CONTENT in the shipped Tactical-HUD design language (docs/archive/
## AAA_UI_PLAYBOOK.md — sleek dark-navy base, cyan accents, amber warnings). One builder feeds BOTH the
## presented card and the compact strip card (Handover D7), so the layout stays consistent. Pure view:
## it takes a plain data Dictionary and returns a Control; it never reads game state directly.
##
## data = { name:String, points:int, quality:int, defense:int, alive:int, total:int,
##          activated:bool, fatigued:bool, shaken:bool, caster:bool, coherent:bool, dead:bool,
##          player_color:Color }

# === Palette (Tactical-HUD) ===
const NAVY := Color(0.10, 0.13, 0.19)
const NAVY_HI := Color(0.16, 0.20, 0.28)
const CYAN := Color(0.36, 0.80, 0.92)
const AMBER := Color(0.96, 0.62, 0.18)
const RED := Color(0.95, 0.36, 0.31)
const TEXT := Color(0.90, 0.93, 0.97)
const TEXT_DIM := Color(0.58, 0.64, 0.72)
const CHIP_OFF := Color(0.22, 0.26, 0.33)


## Presented card content (the big card). `on_action` (optional) is called with the action kind string
## ("activation"/"fatigued"/"shaken"/"casts"/"wounds"/"details"/"revive") when an action chip is pressed;
## the dock connects it to _card_action. Left empty in the dev preview so the chips are inert.
static func build_presented(data: Dictionary, on_action: Callable = Callable(), include_actions: bool = true, collapse_weapons: bool = false) -> Control:
	var margin := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 12)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	# Header band: name (auto-fit + ellipsize so long names never truncate mid-word) + points.
	var header := HBoxContainer.new()
	var name_lbl := _fit_name(str(data.get("name", "Unit")), 19, 15, 20)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_lbl)
	header.add_child(_label("%d pts" % int(data.get("points", 0)), 14, TEXT_DIM))
	col.add_child(header)
	col.add_child(_rule(CYAN, 0.28, 1.0))   # subtle header divider (bus 027)

	# Stat row: Q + D die-chips, alive counter pushed right.
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	stats.add_child(_die_chip("Q", "%d+" % int(data.get("quality", 0))))
	stats.add_child(_die_chip("D", "%d+" % int(data.get("defense", 0))))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(spacer)
	var alive := int(data.get("alive", 0))
	var total := int(data.get("total", 0))
	# Counter: red when destroyed, amber when wounded, else normal.
	var counter_color := TEXT
	if bool(data.get("dead", false)) or alive == 0:
		counter_color = RED
	elif alive < total:
		counter_color = AMBER
	stats.add_child(_label("%d/%d" % [alive, total], 18, counter_color))
	col.add_child(stats)

	# Status strip: lit/unlit chips.
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 6)
	strip.add_child(_status_chip("Activated", bool(data.get("activated", false)), CYAN))
	strip.add_child(_status_chip("Fatigued", bool(data.get("fatigued", false)), AMBER))
	strip.add_child(_status_chip("Shaken", bool(data.get("shaken", false)), AMBER))
	if bool(data.get("caster", false)):
		strip.add_child(_status_chip("Caster", true, CYAN))
	col.add_child(strip)

	# Weapons block — one line per distinct weapon (name+count · RNG A· AP·), special rules on a small
	# second line. data.weapons = [{name, meta, rules}] built by the caller from the SAME distributed-
	# loadout aggregation the old UnitCard uses (D8 reuse), NOT re-derived here.
	var weapons: Array = data.get("weapons", [])
	if not weapons.is_empty() and not bool(data.get("dead", false)):
		col.add_child(_rule(NAVY_HI))
		if collapse_weapons:
			# Strip-size fallback (bus 033): a one-line weapon summary instead of the full block, so a
			# dense strip stays legible. The full block shows on the focus card / on hover.
			var names: Array[String] = []
			for w in weapons:
				names.append(str((w as Dictionary).get("name", "")))
			var summary := _label("⚔ " + ", ".join(names), 11, TEXT_DIM)
			summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			summary.clip_text = true
			col.add_child(summary)
		else:
			for w in weapons:
				var row := HBoxContainer.new()
				var nm := _label(str((w as Dictionary).get("name", "")), 12, TEXT)
				nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				nm.clip_text = true
				row.add_child(nm)
				row.add_child(_label(str((w as Dictionary).get("meta", "")), 12, TEXT_DIM))
				col.add_child(row)
				var wr := str((w as Dictionary).get("rules", ""))
				if not wr.is_empty():
					col.add_child(_label("    " + wr, 10, CYAN))

	# Rules + Spells list — each name is a hover target (the dock wires meta_hover to the description
	# tooltip + spell-range ring, bus 033). This absorbs the old detail Info card; there is no Info button.
	if not bool(data.get("dead", false)):
		var rules_rt := _rules_list(data)
		if rules_rt != null:
			col.add_child(rules_rt)

	# Amber coherency strip (only when out of coherency and not dead).
	if not bool(data.get("coherent", true)) and not bool(data.get("dead", false)):
		col.add_child(_warning_strip("⚠  Out of coherency"))

	# Action bar — presented/focus card only (strip cards omit it via include_actions=false). No Info
	# button: the rules list above replaces the old detail card.
	if include_actions:
		var pad := Control.new()
		pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(pad)
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 4)
		if bool(data.get("dead", false)):
			actions.add_child(_action_btn("↺", "Revive", "revive", on_action))
		else:
			actions.add_child(_action_btn("▶", "Act", "activation", on_action))
			actions.add_child(_action_btn("~", "Fat", "fatigued", on_action))
			actions.add_child(_action_btn("!", "Shk", "shaken", on_action))
			if bool(data.get("caster", false)):
				actions.add_child(_action_btn("✦", "Cast", "casts", on_action))
			actions.add_child(_action_btn("✚", "Wnd", "wounds", on_action))
		col.add_child(actions)

	return margin


## The hoverable Rules (+ Spells) list as a RichTextLabel of [url] spans, named "RulesList" so the dock
## can wire meta_hover_started/ended to descriptions + the spell-range ring. data.rules_list = Array of
## rule-name Strings; data.spells = Array of {name, threshold}. Returns null when there is nothing to
## show. Spell spans are keyed "spell:<name>".
static func _rules_list(data: Dictionary) -> RichTextLabel:
	var rule_names: Array = data.get("rules_list", [])
	var spells: Array = data.get("spells", []) if bool(data.get("caster", false)) else []
	if rule_names.is_empty() and spells.is_empty():
		return null
	var rt := RichTextLabel.new()
	rt.name = "RulesList"
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.meta_underlined = true
	rt.mouse_filter = Control.MOUSE_FILTER_STOP
	rt.add_theme_font_size_override("normal_font_size", 11)
	rt.add_theme_color_override("default_color", TEXT_DIM)
	var lines: Array[String] = []
	if not rule_names.is_empty():
		var spans: Array[String] = []
		for r in rule_names:
			spans.append("[url=%s]%s[/url]" % [str(r), str(r)])
		lines.append("[color=%s]Rules[/color]  %s" % [TEXT_DIM.to_html(false), "  ".join(spans)])
	if not spells.is_empty():
		var sp: Array[String] = []
		for s in spells:
			var sd := s as Dictionary
			sp.append("[url=spell:%s]%s (%d+)[/url]" % [str(sd.get("name", "")), str(sd.get("name", "")), int(sd.get("threshold", 0))])
		lines.append("[color=%s]Spells[/color]  %s" % [CYAN.to_html(false), "  ".join(sp)])
	rt.text = "\n".join(lines)
	return rt



# === Pieces ===

static func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A unit-name label that never truncates mid-word: drop a font step when the name is long, then let
## the label ellipsize if it still overflows the available width.
static func _fit_name(text: String, size_big: int, size_small: int, max_chars: int) -> Label:
	var l := Label.new()
	l.text = text
	# Auto-shrink a step past the char budget, THEN ellipsize only if it still overflows the label's
	# width (bus 034: ~24 chars must fit; do not clip short names). clip_text=false so an expand-filled
	# label uses its full allotted width before the ellipsis kicks in.
	l.add_theme_font_size_override("font_size", size_big if text.length() <= max_chars else size_small)
	l.add_theme_color_override("font_color", TEXT)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


## Compact icon+label action button with hover state (chip-styled), part of the presented-card design.
## When pressed, calls `on_action.call(kind)` (if valid) so the dock routes it to _card_action.
static func _action_btn(icon: String, label: String, kind: String, on_action: Callable) -> Button:
	var b := Button.new()
	b.text = "%s %s" % [icon, label]
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", CYAN)
	b.add_theme_stylebox_override("normal", _chip_style(NAVY_HI, CYAN))
	b.add_theme_stylebox_override("hover", _chip_style(Color(CYAN.r, CYAN.g, CYAN.b, 0.22), CYAN))
	b.add_theme_stylebox_override("pressed", _chip_style(NAVY, CYAN))
	if on_action.is_valid():
		b.pressed.connect(func() -> void: on_action.call(kind))
	return b


static func _rule(color: Color, alpha: float = 0.55, height: float = 2.0) -> Control:
	var r := ColorRect.new()
	r.color = Color(color.r, color.g, color.b, alpha)
	r.custom_minimum_size = Vector2(0, height)
	return r


## A die-face chip: a rounded square with the stat glyph over its value (Q 4+, D 3+).
static func _die_chip(glyph: String, value: String) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _chip_style(NAVY_HI, CYAN))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	for s in ["left", "right", "top", "bottom"]:
		h.add_theme_constant_override("margin_" + s, 4)
	h.add_child(_label(glyph, 12, CYAN))
	h.add_child(_label(value, 17, TEXT))
	box.add_child(h)
	return box


static func _status_chip(text: String, lit: bool, lit_color: Color) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _chip_style(NAVY_HI if lit else NAVY, lit_color if lit else CHIP_OFF))
	var l := _label(text, 11, (lit_color if lit else TEXT_DIM))
	box.add_child(l)
	return box



static func _warning_strip(text: String) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _chip_style(Color(AMBER.r, AMBER.g, AMBER.b, 0.18), AMBER))
	box.add_child(_label(text, 13, AMBER))
	return box


static func _chip_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(5)
	s.set_border_width_all(1)
	s.border_color = Color(border.r, border.g, border.b, 0.7)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s
