extends Node
## Kenney UI Theme Generator
## Creates themes using Kenney UI assets (Fantasy and SciFi)

enum ThemeStyle {
	FANTASY_BEIGE,
	FANTASY_BLUE,
	FANTASY_BROWN,
	FANTASY_GREY,
	SCIFI_BLUE,
	SCIFI_GREEN,
	SCIFI_GREY,
	SCIFI_RED,
	SCIFI_YELLOW
}

## Theme configuration
class ThemeConfig:
	var style: ThemeStyle
	var name: String
	var is_scifi: bool
	var color_name: String  # "beige", "blue", "Blue", etc.

	func _init(p_style: ThemeStyle, p_name: String, p_is_scifi: bool, p_color: String):
		style = p_style
		name = p_name
		is_scifi = p_is_scifi
		color_name = p_color


# Theme configurations
static var THEME_CONFIGS = {
	ThemeStyle.FANTASY_BEIGE: ThemeConfig.new(ThemeStyle.FANTASY_BEIGE, "Fantasy (Beige)", false, "beige"),
	ThemeStyle.FANTASY_BLUE: ThemeConfig.new(ThemeStyle.FANTASY_BLUE, "Fantasy (Blue)", false, "blue"),
	ThemeStyle.FANTASY_BROWN: ThemeConfig.new(ThemeStyle.FANTASY_BROWN, "Fantasy (Brown)", false, "brown"),
	ThemeStyle.FANTASY_GREY: ThemeConfig.new(ThemeStyle.FANTASY_GREY, "Fantasy (Grey)", false, "grey"),
	ThemeStyle.SCIFI_BLUE: ThemeConfig.new(ThemeStyle.SCIFI_BLUE, "SciFi (Blue)", true, "Blue"),
	ThemeStyle.SCIFI_GREEN: ThemeConfig.new(ThemeStyle.SCIFI_GREEN, "SciFi (Green)", true, "Green"),
	ThemeStyle.SCIFI_GREY: ThemeConfig.new(ThemeStyle.SCIFI_GREY, "SciFi (Grey)", true, "Grey"),
	ThemeStyle.SCIFI_RED: ThemeConfig.new(ThemeStyle.SCIFI_RED, "SciFi (Red)", true, "Red"),
	ThemeStyle.SCIFI_YELLOW: ThemeConfig.new(ThemeStyle.SCIFI_YELLOW, "SciFi (Yellow)", true, "Yellow"),
}


## Create a theme with the given style
static func create_theme(style: ThemeStyle = ThemeStyle.FANTASY_BLUE) -> Theme:
	var theme = Theme.new()
	var config = THEME_CONFIGS[style]

	if config.is_scifi:
		_create_scifi_theme(theme, config)
	else:
		_create_fantasy_theme(theme, config)

	print("Created Kenney theme: %s" % config.name)
	return theme


## Create Fantasy theme
static func _create_fantasy_theme(theme: Theme, config: ThemeConfig) -> void:
	var base_path = "res://assets/kenney_ui/fantasy/PNG/"
	var color = config.color_name

	# === COLORS ===
	var text_bright = Color(0.95, 0.95, 0.95)
	var text_dim = Color(0.7, 0.7, 0.7)
	var text_accent: Color

	# Color-specific text accents
	match color:
		"beige":
			text_accent = Color(0.95, 0.85, 0.7)
		"blue":
			text_accent = Color(0.6, 0.8, 1.0)
		"brown":
			text_accent = Color(0.8, 0.6, 0.4)
		"grey":
			text_accent = Color(0.85, 0.85, 0.85)
		_:
			text_accent = Color.WHITE

	# === BUTTONS ===
	# Load button textures
	var button_normal_tex = load(base_path + "buttonLong_%s.png" % color)
	var button_pressed_tex = load(base_path + "buttonLong_%s_pressed.png" % color)
	var _button_hover_tex = button_normal_tex  # For future use

	# Button normal state
	var button_style_normal = StyleBoxTexture.new()
	button_style_normal.texture = button_normal_tex
	button_style_normal.texture_margin_left = 12
	button_style_normal.texture_margin_right = 12
	button_style_normal.texture_margin_top = 12
	button_style_normal.texture_margin_bottom = 12
	button_style_normal.content_margin_left = 16
	button_style_normal.content_margin_right = 16
	button_style_normal.content_margin_top = 8
	button_style_normal.content_margin_bottom = 8

	# Button hover state (slightly brighter)
	var button_style_hover = button_style_normal.duplicate()
	button_style_hover.modulate_color = Color(1.2, 1.2, 1.2)

	# Button pressed state
	var button_style_pressed = StyleBoxTexture.new()
	button_style_pressed.texture = button_pressed_tex
	button_style_pressed.texture_margin_left = 12
	button_style_pressed.texture_margin_right = 12
	button_style_pressed.texture_margin_top = 12
	button_style_pressed.texture_margin_bottom = 12
	button_style_pressed.content_margin_left = 16
	button_style_pressed.content_margin_right = 16
	button_style_pressed.content_margin_top = 8
	button_style_pressed.content_margin_bottom = 8

	# Button disabled state
	var button_style_disabled = button_style_normal.duplicate()
	button_style_disabled.modulate_color = Color(0.5, 0.5, 0.5, 0.7)

	theme.set_stylebox("normal", "Button", button_style_normal)
	theme.set_stylebox("hover", "Button", button_style_hover)
	theme.set_stylebox("pressed", "Button", button_style_pressed)
	theme.set_stylebox("disabled", "Button", button_style_disabled)
	theme.set_color("font_color", "Button", text_bright)
	theme.set_color("font_hover_color", "Button", text_accent)
	theme.set_color("font_pressed_color", "Button", text_bright)
	theme.set_color("font_disabled_color", "Button", text_dim)

	# === PANELS ===
	var panel_tex = load(base_path + "panel_%s.png" % color)
	var panel_inset_tex = load(base_path + "panelInset_%s.png" % color)

	# Panel style
	var panel_style = StyleBoxTexture.new()
	panel_style.texture = panel_tex  # Using panel_tex here
	panel_style.texture_margin_left = 16
	panel_style.texture_margin_right = 16
	panel_style.texture_margin_top = 16
	panel_style.texture_margin_bottom = 16
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16

	# Inset panel for containers
	var panel_inset_style = StyleBoxTexture.new()
	panel_inset_style.texture = panel_inset_tex
	panel_inset_style.texture_margin_left = 8
	panel_inset_style.texture_margin_right = 8
	panel_inset_style.texture_margin_top = 8
	panel_inset_style.texture_margin_bottom = 8
	panel_inset_style.content_margin_left = 12
	panel_inset_style.content_margin_right = 12
	panel_inset_style.content_margin_top = 12
	panel_inset_style.content_margin_bottom = 12

	theme.set_stylebox("panel", "PanelContainer", panel_style)
	theme.set_stylebox("panel", "Panel", panel_style)

	# === LABELS ===
	theme.set_color("font_color", "Label", text_bright)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	# === SLIDERS ===
	# Use bar backgrounds and colored bars
	var _bar_bg_h_left = load(base_path + "barBack_horizontalLeft.png")
	var bar_bg_h_mid = load(base_path + "barBack_horizontalMid.png")
	var _bar_bg_h_right = load(base_path + "barBack_horizontalRight.png")

	var slider_bg = StyleBoxTexture.new()
	slider_bg.texture = bar_bg_h_mid
	slider_bg.texture_margin_left = 4
	slider_bg.texture_margin_right = 4
	slider_bg.texture_margin_top = 4
	slider_bg.texture_margin_bottom = 4

	# Slider grabber (use button square)
	var slider_grabber_tex = load(base_path + "buttonSquare_%s.png" % color)
	var slider_grabber = StyleBoxTexture.new()
	slider_grabber.texture = slider_grabber_tex
	slider_grabber.texture_margin_left = 8
	slider_grabber.texture_margin_right = 8
	slider_grabber.texture_margin_top = 8
	slider_grabber.texture_margin_bottom = 8

	var slider_grabber_hl = slider_grabber.duplicate()
	slider_grabber_hl.modulate_color = Color(1.2, 1.2, 1.2)

	theme.set_stylebox("slider", "HSlider", slider_bg)
	theme.set_stylebox("grabber_area", "HSlider", slider_bg)
	theme.set_stylebox("grabber_area_highlight", "HSlider", slider_bg)

	# === LINE EDIT ===
	var line_edit_style = panel_inset_style.duplicate()
	line_edit_style.content_margin_left = 8
	line_edit_style.content_margin_right = 8
	line_edit_style.content_margin_top = 8
	line_edit_style.content_margin_bottom = 8

	var line_edit_focus = line_edit_style.duplicate()
	line_edit_focus.modulate_color = Color(1.1, 1.1, 1.1)

	theme.set_stylebox("normal", "LineEdit", line_edit_style)
	theme.set_stylebox("focus", "LineEdit", line_edit_focus)
	theme.set_color("font_color", "LineEdit", text_bright)
	theme.set_color("font_placeholder_color", "LineEdit", text_dim)
	theme.set_color("caret_color", "LineEdit", text_accent)
	theme.set_color("selection_color", "LineEdit", Color(text_accent.r, text_accent.g, text_accent.b, 0.3))

	# === OPTION BUTTON ===
	theme.set_stylebox("normal", "OptionButton", button_style_normal)
	theme.set_stylebox("hover", "OptionButton", button_style_hover)
	theme.set_stylebox("pressed", "OptionButton", button_style_pressed)
	theme.set_color("font_color", "OptionButton", text_bright)
	theme.set_color("font_hover_color", "OptionButton", text_accent)

	# === WINDOWS ===
	theme.set_stylebox("embedded_border", "Window", panel_style)
	theme.set_color("title_color", "Window", text_bright)


## Create SciFi theme
static func _create_scifi_theme(theme: Theme, config: ThemeConfig) -> void:
	var color_folder = config.color_name  # "Blue", "Green", etc.
	var base_path = "res://assets/kenney_ui/scifi/PNG/%s/Default/" % color_folder
	var extra_path = "res://assets/kenney_ui/scifi/PNG/Extra/Default/"

	# === COLORS ===
	var text_bright = Color(0.95, 0.95, 0.95)
	var text_dim = Color(0.7, 0.7, 0.7)
	var text_accent: Color

	# Color-specific accents
	match color_folder:
		"Blue":
			text_accent = Color(0.4, 0.8, 1.0)
		"Green":
			text_accent = Color(0.4, 1.0, 0.6)
		"Grey":
			text_accent = Color(0.9, 0.9, 0.9)
		"Red":
			text_accent = Color(1.0, 0.4, 0.4)
		"Yellow":
			text_accent = Color(1.0, 0.9, 0.3)
		_:
			text_accent = Color.WHITE

	# === BUTTONS ===
	# SciFi buttons use the square header variants
	var button_normal_tex = load(base_path + "button_square_header_large_rectangle.png")
	var _button_hover_tex = load(base_path + "button_square_header_large_rectangle.png")  # For future use

	var button_style_normal = StyleBoxTexture.new()
	button_style_normal.texture = button_normal_tex
	button_style_normal.texture_margin_left = 8
	button_style_normal.texture_margin_right = 8
	button_style_normal.texture_margin_top = 16
	button_style_normal.texture_margin_bottom = 8
	button_style_normal.content_margin_left = 16
	button_style_normal.content_margin_right = 16
	button_style_normal.content_margin_top = 12
	button_style_normal.content_margin_bottom = 12

	var button_style_hover = button_style_normal.duplicate()
	button_style_hover.modulate_color = Color(1.3, 1.3, 1.3)

	var button_style_pressed = button_style_normal.duplicate()
	button_style_pressed.modulate_color = Color(0.9, 0.9, 0.9)

	var button_style_disabled = button_style_normal.duplicate()
	button_style_disabled.modulate_color = Color(0.5, 0.5, 0.5, 0.6)

	theme.set_stylebox("normal", "Button", button_style_normal)
	theme.set_stylebox("hover", "Button", button_style_hover)
	theme.set_stylebox("pressed", "Button", button_style_pressed)
	theme.set_stylebox("disabled", "Button", button_style_disabled)
	theme.set_color("font_color", "Button", text_bright)
	theme.set_color("font_hover_color", "Button", text_accent)
	theme.set_color("font_pressed_color", "Button", text_bright)
	theme.set_color("font_disabled_color", "Button", text_dim)

	# === PANELS ===
	# Use glass panels from Extra folder
	var _panel_tex = load(extra_path + "panel_glass.png")  # Alternative panel texture
	var panel_screws_tex = load(extra_path + "panel_glass_screws.png")

	var panel_style = StyleBoxTexture.new()
	panel_style.texture = panel_screws_tex
	panel_style.texture_margin_left = 24
	panel_style.texture_margin_right = 24
	panel_style.texture_margin_top = 24
	panel_style.texture_margin_bottom = 24
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 20
	panel_style.content_margin_bottom = 20
	panel_style.modulate_color = Color(0.9, 0.9, 0.9, 0.95)

	theme.set_stylebox("panel", "PanelContainer", panel_style)
	theme.set_stylebox("panel", "Panel", panel_style)

	# === LABELS ===
	theme.set_color("font_color", "Label", text_bright)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.7))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	# === SLIDERS ===
	# Use the colored bar system
	var bar_bg_tex = load(base_path + "bar_square_large_m.png")
	var bar_fill_tex = load(base_path + "bar_square_gloss_large_m.png")

	var slider_bg = StyleBoxTexture.new()
	slider_bg.texture = bar_bg_tex
	slider_bg.texture_margin_left = 4
	slider_bg.texture_margin_right = 4
	slider_bg.texture_margin_top = 4
	slider_bg.texture_margin_bottom = 4

	var slider_fill = StyleBoxTexture.new()
	slider_fill.texture = bar_fill_tex
	slider_fill.texture_margin_left = 4
	slider_fill.texture_margin_right = 4
	slider_fill.texture_margin_top = 4
	slider_fill.texture_margin_bottom = 4

	theme.set_stylebox("slider", "HSlider", slider_bg)
	theme.set_stylebox("grabber_area", "HSlider", slider_fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)

	# === LINE EDIT ===
	var line_edit_tex = load(extra_path + "panel_rectangle.png")
	var line_edit_style = StyleBoxTexture.new()
	line_edit_style.texture = line_edit_tex
	line_edit_style.texture_margin_left = 8
	line_edit_style.texture_margin_right = 8
	line_edit_style.texture_margin_top = 8
	line_edit_style.texture_margin_bottom = 8
	line_edit_style.content_margin_left = 12
	line_edit_style.content_margin_right = 12
	line_edit_style.content_margin_top = 8
	line_edit_style.content_margin_bottom = 8
	line_edit_style.modulate_color = Color(0.8, 0.8, 0.8)

	var line_edit_focus = line_edit_style.duplicate()
	line_edit_focus.modulate_color = Color(1.0, 1.0, 1.0)

	theme.set_stylebox("normal", "LineEdit", line_edit_style)
	theme.set_stylebox("focus", "LineEdit", line_edit_focus)
	theme.set_color("font_color", "LineEdit", text_bright)
	theme.set_color("font_placeholder_color", "LineEdit", text_dim)
	theme.set_color("caret_color", "LineEdit", text_accent)
	theme.set_color("selection_color", "LineEdit", Color(text_accent.r, text_accent.g, text_accent.b, 0.3))

	# === OPTION BUTTON ===
	theme.set_stylebox("normal", "OptionButton", button_style_normal)
	theme.set_stylebox("hover", "OptionButton", button_style_hover)
	theme.set_stylebox("pressed", "OptionButton", button_style_pressed)
	theme.set_color("font_color", "OptionButton", text_bright)
	theme.set_color("font_hover_color", "OptionButton", text_accent)

	# === WINDOWS ===
	theme.set_stylebox("embedded_border", "Window", panel_style)
	theme.set_color("title_color", "Window", text_bright)


## Get list of all theme style names
static func get_theme_names() -> Array[String]:
	var names: Array[String] = []
	for style in THEME_CONFIGS:
		names.append(THEME_CONFIGS[style].name)
	return names


## Get theme style from name
static func get_style_from_name(theme_name: String) -> ThemeStyle:
	for style in THEME_CONFIGS:
		if THEME_CONFIGS[style].name == theme_name:
			return style
	return ThemeStyle.FANTASY_BLUE  # Default fallback
