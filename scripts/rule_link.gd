class_name RuleLink
extends Button
## An underlined rule / spell / weapon-rule link on the unit card whose TEXT and TOOLTIP wrap. It was a
## LinkButton, which cannot wrap: a long spell name pushed a whole strip card past its edge (23.09.:
## nothing on a card may be cut). It keeps the LinkButton look — no box, the text underlined. Godot's
## default tooltip is a single non-wrapping line, so long OPR rule descriptions ran off the screen
## (maintainer); overriding _make_custom_tooltip returns a width-capped, word-wrapped panel instead.
## tooltip_text still carries the "Name — description" string (set by the dock from army_manager); the
## dock also reads meta "rule_meta" for the spell-range ring.

const TOOLTIP_WIDTH := 300.0

## The widest the link may get (the card's content width); it wraps there. 0 = no cap.
var max_width := 0.0


## A wrapping button is first measured at width 0 (one word per line): once its font is known, floor it
## at its text's own width, capped by the room on the card — short names stay on one line.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		var natural := get_theme_font(&"font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			get_theme_font_size(&"font_size")).x + 1.0
		custom_minimum_size.x = minf(ceilf(natural), max_width) if max_width > 0.0 else ceilf(natural)


func _make_custom_tooltip(for_text: String) -> Object:
	if for_text.strip_edges().is_empty():
		return null   # no text -> no popup (an unwired link once popped an empty panel)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.14, 0.98)
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.36, 0.80, 0.92, 0.6)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	var label := Label.new()
	label.text = for_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(TOOLTIP_WIDTH, 0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.90, 0.94, 0.98))
	panel.add_child(label)
	return panel
