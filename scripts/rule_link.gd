class_name RuleLink
extends Button
## An underlined rule / spell / weapon-rule link on the unit card. Its TEXT wraps inside the card (a
## LinkButton cannot wrap: a long name ran past a strip card's edge) and its TOOLTIP wraps (Godot's
## default tooltip is a single non-wrapping line, so long OPR rule descriptions ran off the screen —
## maintainer; _make_custom_tooltip returns a width-capped, word-wrapped panel). tooltip_text carries the
## "Name — description" string (set by the dock from army_manager); the dock also reads meta "rule_meta"
## for the spell-range ring.

const TOOLTIP_WIDTH := 300.0


## A link in `tone` (HouseStyle.TONE_*) at `font_px`: as wide as its text, never wider than `max_w`
## (it wraps there instead of leaving the card).
static func make(label: String, meta_key: String, tone: StringName, font_px: int, max_w: float) -> RuleLink:
	var b := RuleLink.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override(&"font_size", font_px)
	var ink := HouseStyle.tone_color(tone)
	for c: StringName in [&"font_color", &"font_pressed_color", &"font_focus_color"]:
		b.add_theme_color_override(c, ink)
	for c: StringName in [&"font_hover_color", &"font_hover_pressed_color"]:
		b.add_theme_color_override(c, HouseStyle.INK)
	for state: StringName in [&"normal", &"pressed", &"disabled"]:
		b.add_theme_stylebox_override(state, HouseStyle.link_box(tone))
	for state: StringName in [&"hover", &"hover_pressed"]:
		b.add_theme_stylebox_override(state, HouseStyle.link_box(tone, true))
	b.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	# A wrapping button is first measured at width 0 (one word per line): floor it at its text's own
	# width, capped by the room it has — a short name stays on one line, a long one wraps in the card.
	var font: Font = HouseStyle.theme().default_font
	var natural := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	b.custom_minimum_size = Vector2(minf(ceilf(natural) + 1.0, max_w), 0)
	b.set_meta("rule_meta", meta_key)
	return b


func _make_custom_tooltip(for_text: String) -> Object:
	if for_text.strip_edges().is_empty():
		return null   # no text -> no popup (an unwired link once popped an empty panel)
	var panel := PanelContainer.new()
	panel.theme = HouseStyle.theme()
	panel.add_theme_stylebox_override(&"panel", HouseStyle.tooltip_box())
	var label := HouseStyle.label(for_text, HouseStyle.BODY)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(TOOLTIP_WIDTH, 0)
	panel.add_child(label)
	return panel
