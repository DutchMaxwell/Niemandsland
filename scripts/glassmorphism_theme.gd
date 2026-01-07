extends Node
## Glassmorphism Theme Generator
## Creates a modern glassmorphism UI theme based on Audacious Assets

const FONT_PATH = "res://assets/ui_glassmorphism/fonts/"
const ICON_PATH = "res://assets/ui_glassmorphism/icons/"

# Cached resources
static var _inter_font: FontFile = null
static var _mono_font: FontFile = null
static var _cached_theme: Theme = null


## Get or create the glassmorphism theme
static func get_theme() -> Theme:
	if _cached_theme:
		return _cached_theme
	_cached_theme = create_theme()
	return _cached_theme


## Create the glassmorphism theme
static func create_theme() -> Theme:
	var theme = Theme.new()

	# Load fonts
	_inter_font = load(FONT_PATH + "Inter.ttf") as FontFile
	_mono_font = load(FONT_PATH + "SourceCodePro.ttf") as FontFile

	if _inter_font:
		theme.default_font = _inter_font
	theme.default_font_size = 16

	# Apply styles
	_setup_colors(theme)
	_setup_buttons(theme)
	_setup_panels(theme)
	_setup_labels(theme)
	_setup_line_edit(theme)
	_setup_check_controls(theme)
	_setup_sliders(theme)
	_setup_scrollbars(theme)
	_setup_option_button(theme)
	_setup_popup_menu(theme)
	_setup_progress_bar(theme)
	_setup_tabs(theme)
	_setup_tree(theme)
	_setup_tooltip(theme)
	_setup_window(theme)
	_setup_separators(theme)

	print("[GlassmorphismTheme] Theme created successfully")
	return theme


## Setup common colors
static func _setup_colors(_theme: Theme) -> void:
	pass  # Colors are set per-component


## Create a glass-style StyleBoxFlat
static func _create_glass_style(
	alpha: float = 0.33,
	corner_radius: int = 8,
	border_alpha: float = 1.0,
	border_width: int = 1,
	content_margin: float = 10.0
) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, alpha)
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = Color(1, 1, 1, border_alpha)
	style.border_blend = true
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.content_margin_left = content_margin
	style.content_margin_right = content_margin
	style.content_margin_top = content_margin * 0.6
	style.content_margin_bottom = content_margin * 0.6
	return style


## Setup button styles
static func _setup_buttons(theme: Theme) -> void:
	# Normal state - semi-transparent white
	var normal = _create_glass_style(0.33, 8, 1.0)
	theme.set_stylebox("normal", "Button", normal)

	# Hover state - slightly more opaque
	var hover = _create_glass_style(0.16, 8, 0.53)
	theme.set_stylebox("hover", "Button", hover)

	# Pressed state - more opaque
	var pressed = _create_glass_style(0.55, 8, 1.0)
	theme.set_stylebox("pressed", "Button", pressed)

	# Disabled state
	var disabled = _create_glass_style(0.16, 8, 0.53)
	theme.set_stylebox("disabled", "Button", disabled)

	# Focus - empty (no visible focus ring)
	var focus = StyleBoxEmpty.new()
	theme.set_stylebox("focus", "Button", focus)

	# Colors
	theme.set_color("font_color", "Button", Color.WHITE)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.5))


## Setup panel styles
static func _setup_panels(theme: Theme) -> void:
	# Panel - rounded with border
	var panel = _create_glass_style(0.33, 20, 1.0, 1, 15.0)
	theme.set_stylebox("panel", "Panel", panel)

	# PanelContainer - same style
	var panel_container = _create_glass_style(0.33, 20, 1.0, 1, 15.0)
	theme.set_stylebox("panel", "PanelContainer", panel_container)


## Setup label styles
static func _setup_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", Color.WHITE)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.5))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)


## Setup line edit styles
static func _setup_line_edit(theme: Theme) -> void:
	var normal = _create_glass_style(0.16, 8, 1.0, 2, 10.0)
	normal.content_margin_top = 2
	normal.content_margin_bottom = 2
	theme.set_stylebox("normal", "LineEdit", normal)

	var focus = StyleBoxEmpty.new()
	theme.set_stylebox("focus", "LineEdit", focus)

	var read_only = _create_glass_style(0.33, 8, 1.0, 1, 10.0)
	read_only.bg_color = Color(0.52, 0.52, 0.52, 0.33)
	theme.set_stylebox("read_only", "LineEdit", read_only)

	theme.set_color("font_color", "LineEdit", Color.WHITE)
	theme.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.64))
	theme.set_color("clear_button_color", "LineEdit", Color(1, 1, 1, 0.67))
	theme.set_color("clear_button_color_pressed", "LineEdit", Color.WHITE)

	# Load X icon for clear button
	var x_icon = load(ICON_PATH + "x-bold.svg")
	if x_icon:
		theme.set_icon("clear", "LineEdit", x_icon)


## Setup checkbox and checkbutton styles
static func _setup_check_controls(theme: Theme) -> void:
	# CheckBox
	var cb_normal = _create_glass_style(0.33, 8, 1.0, 1, 0)
	cb_normal.content_margin_right = 10
	theme.set_stylebox("normal", "CheckBox", cb_normal)

	var cb_hover = _create_glass_style(0.16, 8, 0.53, 1, 0)
	cb_hover.content_margin_right = 10
	theme.set_stylebox("hover", "CheckBox", cb_hover)

	var cb_pressed = _create_glass_style(0.55, 8, 1.0, 1, 0)
	cb_pressed.content_margin_right = 10
	theme.set_stylebox("pressed", "CheckBox", cb_pressed)

	var cb_disabled = _create_glass_style(0.16, 8, 0.53, 1, 0)
	cb_disabled.content_margin_right = 10
	theme.set_stylebox("disabled", "CheckBox", cb_disabled)

	theme.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	theme.set_constant("h_separation", "CheckBox", 0)

	# Load checkbox icons
	var checked_icon = load(ICON_PATH + "check-square-fill.svg")
	var unchecked_icon = load(ICON_PATH + "square-bold.svg")
	if checked_icon:
		theme.set_icon("checked", "CheckBox", checked_icon)
	if unchecked_icon:
		theme.set_icon("unchecked", "CheckBox", unchecked_icon)

	# CheckButton (toggle switch style)
	var cbt_normal = _create_glass_style(0.33, 8, 1.0, 1, 0)
	cbt_normal.content_margin_left = 10
	theme.set_stylebox("normal", "CheckButton", cbt_normal)
	theme.set_stylebox("hover", "CheckButton", cbt_normal.duplicate())
	theme.set_stylebox("pressed", "CheckButton", cbt_normal.duplicate())
	theme.set_stylebox("disabled", "CheckButton", cbt_normal.duplicate())
	theme.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	theme.set_constant("h_separation", "CheckButton", 0)

	# Toggle icons
	var toggle_on = load(ICON_PATH + "toggle-right-fill.svg")
	var toggle_off = load(ICON_PATH + "toggle-left.svg")
	var toggle_on_disabled = load(ICON_PATH + "toggle-right-fill-disabled.svg")
	var toggle_off_disabled = load(ICON_PATH + "toggle-left-disabled.svg")
	if toggle_on:
		theme.set_icon("checked", "CheckButton", toggle_on)
	if toggle_off:
		theme.set_icon("unchecked", "CheckButton", toggle_off)
	if toggle_on_disabled:
		theme.set_icon("checked_disabled", "CheckButton", toggle_on_disabled)
	if toggle_off_disabled:
		theme.set_icon("unchecked_disabled", "CheckButton", toggle_off_disabled)


## Setup slider styles
static func _setup_sliders(theme: Theme) -> void:
	# HSlider
	var slider_bg = StyleBoxFlat.new()
	slider_bg.bg_color = Color(1, 1, 1, 0.33)
	slider_bg.corner_radius_top_left = 80
	slider_bg.corner_radius_top_right = 80
	slider_bg.corner_radius_bottom_right = 80
	slider_bg.corner_radius_bottom_left = 80
	slider_bg.content_margin_top = 6
	slider_bg.content_margin_bottom = 6
	theme.set_stylebox("slider", "HSlider", slider_bg)
	theme.set_stylebox("grabber_area", "HSlider", slider_bg.duplicate())

	var slider_highlight = slider_bg.duplicate()
	slider_highlight.bg_color = Color(1, 1, 1, 0.67)
	theme.set_stylebox("grabber_area_highlight", "HSlider", slider_highlight)

	# Grabber icons
	var grabber = load(ICON_PATH + "dot-bold.svg")
	var grabber_disabled = load(ICON_PATH + "dot-bold-disabled.svg")
	var grabber_highlight = load(ICON_PATH + "dot-bold-highlight.svg")
	if grabber:
		theme.set_icon("grabber", "HSlider", grabber)
		theme.set_icon("grabber", "VSlider", grabber)
	if grabber_disabled:
		theme.set_icon("grabber_disabled", "HSlider", grabber_disabled)
		theme.set_icon("grabber_disabled", "VSlider", grabber_disabled)
	if grabber_highlight:
		theme.set_icon("grabber_highlight", "HSlider", grabber_highlight)
		theme.set_icon("grabber_highlight", "VSlider", grabber_highlight)

	# VSlider - similar setup
	var vslider_bg = slider_bg.duplicate()
	vslider_bg.content_margin_left = 6
	vslider_bg.content_margin_right = 7
	vslider_bg.content_margin_top = 0
	vslider_bg.content_margin_bottom = 0
	theme.set_stylebox("slider", "VSlider", vslider_bg)
	theme.set_stylebox("grabber_area", "VSlider", vslider_bg.duplicate())
	theme.set_stylebox("grabber_area_highlight", "VSlider", slider_highlight.duplicate())


## Setup scrollbar styles
static func _setup_scrollbars(theme: Theme) -> void:
	# Grabber styles
	var grabber = StyleBoxFlat.new()
	grabber.bg_color = Color(1, 1, 1, 0.5)
	grabber.border_width_left = 1
	grabber.border_width_top = 1
	grabber.border_width_right = 1
	grabber.border_width_bottom = 1
	grabber.border_color = Color.WHITE
	grabber.corner_radius_top_left = 4
	grabber.corner_radius_top_right = 4
	grabber.corner_radius_bottom_right = 4
	grabber.corner_radius_bottom_left = 4

	var grabber_highlight = grabber.duplicate()
	grabber_highlight.bg_color = Color(1, 1, 1, 0.67)

	var grabber_pressed = grabber.duplicate()
	grabber_pressed.bg_color = Color.WHITE

	# HScrollBar
	var h_scroll = StyleBoxEmpty.new()
	h_scroll.content_margin_top = 5
	h_scroll.content_margin_bottom = 5
	theme.set_stylebox("scroll", "HScrollBar", h_scroll)
	theme.set_stylebox("scroll_focus", "HScrollBar", h_scroll.duplicate())
	theme.set_stylebox("grabber", "HScrollBar", grabber)
	theme.set_stylebox("grabber_highlight", "HScrollBar", grabber_highlight)
	theme.set_stylebox("grabber_pressed", "HScrollBar", grabber_pressed)

	# VScrollBar
	var v_scroll = StyleBoxFlat.new()
	v_scroll.bg_color = Color(0.6, 0.6, 0.6, 0)
	v_scroll.content_margin_left = 5
	v_scroll.content_margin_right = 5
	theme.set_stylebox("scroll", "VScrollBar", v_scroll)
	theme.set_stylebox("scroll_focus", "VScrollBar", v_scroll.duplicate())
	theme.set_stylebox("grabber", "VScrollBar", grabber.duplicate())
	theme.set_stylebox("grabber_highlight", "VScrollBar", grabber_highlight.duplicate())
	theme.set_stylebox("grabber_pressed", "VScrollBar", grabber_pressed.duplicate())

	# Remove increment/decrement icons
	theme.set_icon("decrement", "VScrollBar", null)
	theme.set_icon("decrement_highlight", "VScrollBar", null)
	theme.set_icon("increment", "VScrollBar", null)
	theme.set_icon("increment_highlight", "VScrollBar", null)


## Setup option button (dropdown)
static func _setup_option_button(theme: Theme) -> void:
	var normal = _create_glass_style(0.33, 8, 1.0)
	theme.set_stylebox("normal", "OptionButton", normal)
	theme.set_stylebox("hover", "OptionButton", _create_glass_style(0.16, 8, 0.53))
	theme.set_stylebox("pressed", "OptionButton", _create_glass_style(0.55, 8, 1.0))
	theme.set_stylebox("disabled", "OptionButton", _create_glass_style(0.16, 8, 0.53))
	theme.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())

	theme.set_color("font_color", "OptionButton", Color.WHITE)
	theme.set_color("font_hover_color", "OptionButton", Color(0.95, 0.95, 0.95))
	theme.set_color("font_pressed_color", "OptionButton", Color.WHITE)
	theme.set_color("font_disabled_color", "OptionButton", Color(0.875, 0.875, 0.875, 0.5))

	var arrow_icon = load(ICON_PATH + "caret-down-bold.svg")
	if arrow_icon:
		theme.set_icon("arrow", "OptionButton", arrow_icon)
	theme.set_constant("arrow_margin", "OptionButton", 4)
	theme.set_constant("h_separation", "OptionButton", 4)


## Setup popup menu
static func _setup_popup_menu(theme: Theme) -> void:
	var panel = StyleBoxFlat.new()
	panel.bg_color = Color(0, 0, 0, 0.78)
	panel.border_width_left = 4
	panel.border_width_top = 4
	panel.border_width_right = 4
	panel.border_width_bottom = 4
	panel.border_color = Color.WHITE
	panel.corner_radius_top_left = 4
	panel.corner_radius_top_right = 4
	panel.corner_radius_bottom_right = 4
	panel.corner_radius_bottom_left = 4
	panel.content_margin_left = 15
	panel.content_margin_top = 15
	panel.content_margin_right = 15
	panel.content_margin_bottom = 15
	theme.set_stylebox("panel", "PopupMenu", panel)
	theme.set_stylebox("panel", "PopupPanel", panel.duplicate())

	# Icons
	var checked = load(ICON_PATH + "check-square-fill.svg")
	var unchecked = load(ICON_PATH + "square-bold.svg")
	var radio_checked = load(ICON_PATH + "radio-button-fill.svg")
	var radio_unchecked = load(ICON_PATH + "circle-fill.svg")
	if checked:
		theme.set_icon("checked", "PopupMenu", checked)
	if unchecked:
		theme.set_icon("unchecked", "PopupMenu", unchecked)
	if radio_checked:
		theme.set_icon("radio_checked", "PopupMenu", radio_checked)
	if radio_unchecked:
		theme.set_icon("radio_unchecked", "PopupMenu", radio_unchecked)


## Setup progress bar
static func _setup_progress_bar(theme: Theme) -> void:
	var background = StyleBoxFlat.new()
	background.bg_color = Color(1, 1, 1, 0)
	background.border_width_left = 1
	background.border_width_top = 1
	background.border_width_right = 1
	background.border_width_bottom = 1
	background.border_color = Color.WHITE
	background.corner_radius_top_left = 8
	background.corner_radius_top_right = 8
	background.corner_radius_bottom_right = 8
	background.corner_radius_bottom_left = 8
	theme.set_stylebox("background", "ProgressBar", background)

	var fill = StyleBoxFlat.new()
	fill.bg_color = Color(1, 1, 1, 0.25)
	fill.corner_radius_top_left = 8
	fill.corner_radius_top_right = 8
	fill.corner_radius_bottom_right = 8
	fill.corner_radius_bottom_left = 8
	theme.set_stylebox("fill", "ProgressBar", fill)

	theme.set_color("font_color", "ProgressBar", Color.WHITE)


## Setup tab container
static func _setup_tabs(theme: Theme) -> void:
	var panel = _create_glass_style(0.33, 20, 1.0, 1, 0)
	theme.set_stylebox("panel", "TabContainer", panel)

	var tab_selected = StyleBoxFlat.new()
	tab_selected.bg_color = Color(1, 1, 1, 0.33)
	tab_selected.content_margin_left = 9
	tab_selected.content_margin_right = 9
	theme.set_stylebox("tab_selected", "TabContainer", tab_selected)

	var tab_unselected = StyleBoxFlat.new()
	tab_unselected.bg_color = Color(1, 1, 1, 0.16)
	tab_unselected.content_margin_left = 9
	theme.set_stylebox("tab_unselected", "TabContainer", tab_unselected)

	var tab_hovered = StyleBoxFlat.new()
	tab_hovered.bg_color = Color(1, 1, 1, 0.25)
	tab_hovered.content_margin_left = 9
	tab_hovered.content_margin_right = 9
	theme.set_stylebox("tab_hovered", "TabContainer", tab_hovered)

	var tab_disabled = StyleBoxFlat.new()
	tab_disabled.bg_color = Color(0, 0, 0, 0.33)
	tab_disabled.content_margin_left = 9
	tab_disabled.content_margin_right = 9
	theme.set_stylebox("tab_disabled", "TabContainer", tab_disabled)

	theme.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())

	theme.set_color("font_selected_color", "TabContainer", Color.WHITE)
	theme.set_color("font_unselected_color", "TabContainer", Color(1, 1, 1, 0.5))
	theme.set_font_size("font_size", "TabContainer", 14)
	theme.set_constant("side_margin", "TabContainer", 21)


## Setup tree view
static func _setup_tree(theme: Theme) -> void:
	var panel = _create_glass_style(0.0, 20, 1.0, 1, 10)
	theme.set_stylebox("panel", "Tree", panel)

	var selected = StyleBoxFlat.new()
	selected.bg_color = Color(1, 1, 1, 0.33)
	theme.set_stylebox("selected", "Tree", selected)

	var hovered = StyleBoxFlat.new()
	hovered.bg_color = Color(1, 1, 1, 0.16)
	hovered.content_margin_left = 10
	theme.set_stylebox("hovered", "Tree", hovered)

	theme.set_stylebox("focus", "Tree", StyleBoxEmpty.new())

	theme.set_color("font_color", "Tree", Color.WHITE)
	theme.set_color("font_hovered_color", "Tree", Color(0.95, 0.95, 0.95))
	theme.set_color("font_disabled_color", "Tree", Color(1, 1, 1, 0.24))
	theme.set_color("guide_color", "Tree", Color(1, 1, 1, 0.67))
	theme.set_color("relationship_line_color", "Tree", Color(1, 0.98, 0.98, 0.33))
	theme.set_color("parent_hl_line_color", "Tree", Color(1, 0.98, 0.98, 0.67))
	theme.set_color("children_hl_line_color", "Tree", Color(1, 1, 1, 0.67))

	theme.set_constant("draw_relationship_lines", "Tree", 1)
	theme.set_constant("parent_hl_line_width", "Tree", 3)
	theme.set_constant("children_hl_line_width", "Tree", 2)
	theme.set_constant("h_separation", "Tree", -5)
	theme.set_constant("item_margin", "Tree", 14)
	theme.set_constant("inner_item_margin_left", "Tree", 5)
	theme.set_font_size("font_size", "Tree", 14)


## Setup tooltip
static func _setup_tooltip(theme: Theme) -> void:
	var panel = StyleBoxFlat.new()
	panel.bg_color = Color(0, 0, 0, 0.67)
	panel.border_width_left = 1
	panel.border_width_top = 1
	panel.border_width_right = 1
	panel.border_width_bottom = 1
	panel.border_color = Color.WHITE
	panel.corner_radius_top_left = 20
	panel.corner_radius_top_right = 20
	panel.corner_radius_bottom_right = 20
	panel.corner_radius_bottom_left = 20
	panel.content_margin_left = 10
	panel.content_margin_right = 10
	theme.set_stylebox("panel", "TooltipPanel", panel)

	theme.set_color("font_color", "TooltipLabel", Color.WHITE)
	theme.set_font_size("font_size", "TooltipLabel", 16)


## Setup window/dialog styles
static func _setup_window(theme: Theme) -> void:
	var panel = StyleBoxFlat.new()
	panel.bg_color = Color(0, 0, 0, 0.78)
	panel.border_width_left = 4
	panel.border_width_top = 4
	panel.border_width_right = 4
	panel.border_width_bottom = 4
	panel.border_color = Color.WHITE
	panel.corner_radius_top_left = 4
	panel.corner_radius_top_right = 4
	panel.corner_radius_bottom_right = 4
	panel.corner_radius_bottom_left = 4
	panel.content_margin_left = 15
	panel.content_margin_top = 15
	panel.content_margin_right = 15
	panel.content_margin_bottom = 15
	theme.set_stylebox("embedded_border", "Window", panel)
	theme.set_stylebox("panel", "AcceptDialog", panel.duplicate())

	theme.set_color("title_color", "Window", Color.WHITE)


## Setup separators
static func _setup_separators(theme: Theme) -> void:
	var h_sep = StyleBoxLine.new()
	h_sep.color = Color.WHITE
	theme.set_stylebox("separator", "HSeparator", h_sep)

	var v_sep = StyleBoxLine.new()
	v_sep.color = Color.WHITE
	v_sep.vertical = true
	theme.set_stylebox("separator", "VSeparator", v_sep)
