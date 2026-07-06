class_name RuleLink
extends LinkButton
## An underlined rule / spell / weapon-rule link on the unit card whose tooltip WRAPS. Godot's default
## tooltip is a single non-wrapping line, so long OPR rule descriptions ran off the screen (maintainer);
## overriding _make_custom_tooltip returns a width-capped, word-wrapped panel instead. tooltip_text still
## carries the "Name — description" string (set by the dock from army_manager); the dock also reads
## meta "rule_meta" for the spell-range ring.

const TOOLTIP_WIDTH := 300.0


func _make_custom_tooltip(for_text: String) -> Object:
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
