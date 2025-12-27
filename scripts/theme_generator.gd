extends Node
## Theme Generator for OpenTTS
## Creates a consistent AAA-quality glassmorphic theme

static func create_theme() -> Theme:
	var theme = Theme.new()

	# === COLORS ===
	var bg_dark = Color(0.078, 0.098, 0.137, 0.85)  # #141823 with alpha
	var bg_medium = Color(0.1, 0.12, 0.16, 0.9)
	var bg_light = Color(0.15, 0.17, 0.2, 0.95)
	var accent_cyan = Color(0.0, 0.85, 1.0)  # #00D9FF
	var text_bright = Color(0.95, 0.95, 0.95)
	var text_dim = Color(0.7, 0.7, 0.7)
	var border_subtle = Color(1, 1, 1, 0.1)

	# === BUTTONS ===
	var button_style_normal = StyleBoxFlat.new()
	button_style_normal.bg_color = bg_dark
	button_style_normal.border_width_all = 1
	button_style_normal.border_color = border_subtle
	button_style_normal.corner_radius_all = 8
	button_style_normal.content_margin_left = 16
	button_style_normal.content_margin_right = 16
	button_style_normal.content_margin_top = 8
	button_style_normal.content_margin_bottom = 8
	button_style_normal.shadow_size = 4
	button_style_normal.shadow_color = Color(0, 0, 0, 0.3)

	var button_style_hover = button_style_normal.duplicate()
	button_style_hover.bg_color = bg_medium
	button_style_hover.border_color = accent_cyan
	button_style_hover.border_width_all = 2
	button_style_hover.shadow_size = 6
	button_style_hover.shadow_color = Color(0, 0.85, 1, 0.2)

	var button_style_pressed = button_style_normal.duplicate()
	button_style_pressed.bg_color = bg_light
	button_style_pressed.border_color = accent_cyan
	button_style_pressed.shadow_size = 2

	var button_style_disabled = button_style_normal.duplicate()
	button_style_disabled.bg_color = Color(0.05, 0.05, 0.05, 0.5)
	button_style_disabled.border_color = Color(0.3, 0.3, 0.3, 0.3)

	theme.set_stylebox("normal", "Button", button_style_normal)
	theme.set_stylebox("hover", "Button", button_style_hover)
	theme.set_stylebox("pressed", "Button", button_style_pressed)
	theme.set_stylebox("disabled", "Button", button_style_disabled)
	theme.set_color("font_color", "Button", text_bright)
	theme.set_color("font_hover_color", "Button", accent_cyan)
	theme.set_color("font_pressed_color", "Button", accent_cyan)
	theme.set_color("font_disabled_color", "Button", text_dim)
	theme.set_constant("h_separation", "Button", 4)

	# === LABELS ===
	theme.set_color("font_color", "Label", text_bright)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.5))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	# === PANELS ===
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = bg_dark
	panel_style.border_width_all = 1
	panel_style.border_color = border_subtle
	panel_style.corner_radius_all = 12
	panel_style.shadow_size = 8
	panel_style.shadow_color = Color(0, 0, 0, 0.4)
	panel_style.content_margin_all = 12

	theme.set_stylebox("panel", "PanelContainer", panel_style)
	theme.set_stylebox("panel", "Panel", panel_style)

	# === SLIDERS ===
	var slider_style = StyleBoxFlat.new()
	slider_style.bg_color = bg_medium
	slider_style.corner_radius_all = 4
	slider_style.content_margin_all = 2

	var slider_grabber = StyleBoxFlat.new()
	slider_grabber.bg_color = accent_cyan
	slider_grabber.corner_radius_all = 6
	slider_grabber.shadow_size = 4
	slider_grabber.shadow_color = Color(0, 0.85, 1, 0.4)

	var slider_grabber_hl = slider_grabber.duplicate()
	slider_grabber_hl.bg_color = Color(0.2, 0.9, 1.0)
	slider_grabber_hl.shadow_size = 6

	theme.set_stylebox("slider", "HSlider", slider_style)
	theme.set_stylebox("grabber_area", "HSlider", slider_style)
	theme.set_stylebox("grabber_area_highlight", "HSlider", slider_style)
	theme.set_icon("grabber", "HSlider", _create_circle_icon(accent_cyan, 12))
	theme.set_icon("grabber_highlight", "HSlider", _create_circle_icon(Color(0.2, 0.9, 1.0), 14))

	# === WINDOWS ===
	var window_style = StyleBoxFlat.new()
	window_style.bg_color = Color(0.06, 0.08, 0.11, 0.95)
	window_style.border_width_all = 2
	window_style.border_color = Color(0, 0.85, 1, 0.3)
	window_style.corner_radius_all = 16
	window_style.shadow_size = 16
	window_style.shadow_color = Color(0, 0, 0, 0.6)

	theme.set_stylebox("embedded_border", "Window", window_style)
	theme.set_color("title_color", "Window", text_bright)

	# === LINE EDIT ===
	var line_edit_normal = StyleBoxFlat.new()
	line_edit_normal.bg_color = bg_medium
	line_edit_normal.border_width_all = 1
	line_edit_normal.border_color = border_subtle
	line_edit_normal.corner_radius_all = 6
	line_edit_normal.content_margin_all = 8

	var line_edit_focus = line_edit_normal.duplicate()
	line_edit_focus.border_color = accent_cyan
	line_edit_focus.border_width_all = 2

	theme.set_stylebox("normal", "LineEdit", line_edit_normal)
	theme.set_stylebox("focus", "LineEdit", line_edit_focus)
	theme.set_color("font_color", "LineEdit", text_bright)
	theme.set_color("font_placeholder_color", "LineEdit", text_dim)
	theme.set_color("caret_color", "LineEdit", accent_cyan)
	theme.set_color("selection_color", "LineEdit", Color(0, 0.85, 1, 0.3))

	# === OPTION BUTTON ===
	theme.set_stylebox("normal", "OptionButton", button_style_normal)
	theme.set_stylebox("hover", "OptionButton", button_style_hover)
	theme.set_stylebox("pressed", "OptionButton", button_style_pressed)
	theme.set_color("font_color", "OptionButton", text_bright)
	theme.set_color("font_hover_color", "OptionButton", accent_cyan)

	# === SCROLL CONTAINER ===
	var scroll_style = StyleBoxFlat.new()
	scroll_style.bg_color = Color(0.1, 0.1, 0.1, 0.3)
	scroll_style.corner_radius_all = 4

	var scrollbar_style = StyleBoxFlat.new()
	scrollbar_style.bg_color = Color(0, 0.85, 1, 0.4)
	scrollbar_style.corner_radius_all = 4

	theme.set_stylebox("scroll", "VScrollBar", scroll_style)
	theme.set_stylebox("scroll_focus", "VScrollBar", scroll_style)
	theme.set_stylebox("grabber", "VScrollBar", scrollbar_style)
	theme.set_stylebox("grabber_highlight", "VScrollBar", scrollbar_style)
	theme.set_stylebox("grabber_pressed", "VScrollBar", scrollbar_style)

	return theme


static func _create_circle_icon(color: Color, size: int) -> Texture2D:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = size / 2.0
	var radius = size / 2.0

	for x in range(size):
		for y in range(size):
			var dist = Vector2(x, y).distance_to(Vector2(center, center))
			if dist <= radius:
				var alpha = 1.0 - (dist / radius) * 0.3  # Soft edge
				img.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * alpha))

	return ImageTexture.create_from_image(img)
