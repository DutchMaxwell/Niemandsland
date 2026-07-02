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
const TEXT := Color(0.90, 0.93, 0.97)
const TEXT_DIM := Color(0.58, 0.64, 0.72)
const CHIP_OFF := Color(0.22, 0.26, 0.33)


## Presented card content (the big card).
static func build_presented(data: Dictionary) -> Control:
	var margin := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 12)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	# Header band: name (accent-underlined) + points.
	var header := HBoxContainer.new()
	var name_lbl := _label(str(data.get("name", "Unit")), 20, TEXT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	header.add_child(name_lbl)
	header.add_child(_label("%d pts" % int(data.get("points", 0)), 14, TEXT_DIM))
	col.add_child(header)
	col.add_child(_rule(CYAN))

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
	stats.add_child(_label("%d/%d" % [alive, total], 18, (AMBER if alive < total else TEXT)))
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

	# Amber coherency strip (only when out of coherency and not dead).
	if not bool(data.get("coherent", true)) and not bool(data.get("dead", false)):
		col.add_child(_warning_strip("⚠  Out of coherency"))

	return margin


## Compact strip card content.
static func build_strip(data: Dictionary) -> Control:
	var margin := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 8)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	margin.add_child(col)
	var nm := _label(str(data.get("name", "Unit")), 14, TEXT)
	nm.clip_text = true
	col.add_child(nm)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 5)
	stats.add_child(_label("Q%d+" % int(data.get("quality", 0)), 12, TEXT_DIM))
	stats.add_child(_label("D%d+" % int(data.get("defense", 0)), 12, TEXT_DIM))
	col.add_child(stats)
	var alive := int(data.get("alive", 0))
	var total := int(data.get("total", 0))
	col.add_child(_label("%d/%d" % [alive, total], 13, (AMBER if alive < total else TEXT)))
	# One-row status dots.
	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", 4)
	if bool(data.get("activated", false)): dots.add_child(_dot(CYAN))
	if bool(data.get("fatigued", false)): dots.add_child(_dot(AMBER))
	if bool(data.get("shaken", false)): dots.add_child(_dot(AMBER))
	col.add_child(dots)
	return margin


# === Pieces ===

static func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func _rule(color: Color) -> Control:
	var r := ColorRect.new()
	r.color = Color(color.r, color.g, color.b, 0.55)
	r.custom_minimum_size = Vector2(0, 2)
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


static func _dot(color: Color) -> Control:
	var d := PanelContainer.new()
	d.custom_minimum_size = Vector2(9, 9)
	d.add_theme_stylebox_override("panel", _chip_style(color, color))
	return d


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
