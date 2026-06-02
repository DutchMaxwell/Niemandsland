extends Node
## Glassmorphism Theme Generator — "Dark Glassmorphism" design system
## (see docs/UI_MODERNIZATION_PLAN.md). Subtle dark glass surfaces, hairline
## borders, soft drop shadows, a single cyan accent, consistent corner radii.

const FONT_PATH = "res://assets/ui_glassmorphism/fonts/"
const ICON_PATH = "res://assets/ui_glassmorphism/icons/"

# ===== Design tokens =====
const ACCENT := Color(0.0, 0.85, 1.0)            # cyan — primary / hover / focus
const RADIUS_CONTROL := 10                       # buttons, inputs, options, tabs
const RADIUS_PANEL := 14                         # panels, windows, popups
const TEXT_PRIMARY := Color(0.96, 0.97, 0.99)
const HAIRLINE := Color(1.0, 1.0, 1.0, 0.12)     # subtle glass border
const SHADOW := Color(0.0, 0.0, 0.0, 0.38)       # soft drop shadow
const SURFACE := Color(0.11, 0.12, 0.17, 0.96)   # opaque dark glass (windows/popups)

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


## Create a glass-style StyleBoxFlat. `tint` is the strength of the light film over
## the dark background (subtle, not a gray box); `border_alpha` is the hairline.
static func _create_glass_style(
	tint: float = 0.12,
	corner_radius: int = RADIUS_CONTROL,
	border_alpha: float = 0.12,
	border_width: int = 1,
	content_margin: float = 10.0,
	shadow_size: int = 0
) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, tint)
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
	if shadow_size > 0:
		style.shadow_size = shadow_size
		style.shadow_color = SHADOW
		style.shadow_offset = Vector2(0, 3)
	return style


## A 1px accent focus ring (transparent fill) for keyboard/click focus.
static func _accent_focus(corner_radius: int = RADIUS_CONTROL) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.75)
	s.corner_radius_top_left = corner_radius
	s.corner_radius_top_right = corner_radius
	s.corner_radius_bottom_right = corner_radius
	s.corner_radius_bottom_left = corner_radius
	return s


## Setup button styles
static func _setup_buttons(theme: Theme) -> void:
	# Subtle glass that brightens on hover and presses brighter still.
	theme.set_stylebox("normal", "Button", _create_glass_style(0.16, RADIUS_CONTROL, 0.14))

	var hover = _create_glass_style(0.26, RADIUS_CONTROL, 0.0)
	hover.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45)
	hover.border_width_left = 1
	hover.border_width_top = 1
	hover.border_width_right = 1
	hover.border_width_bottom = 1
	theme.set_stylebox("hover", "Button", hover)

	theme.set_stylebox("pressed", "Button", _create_glass_style(0.36, RADIUS_CONTROL, 0.18))
	theme.set_stylebox("disabled", "Button", _create_glass_style(0.06, RADIUS_CONTROL, 0.08))
	theme.set_stylebox("focus", "Button", _accent_focus())

	theme.set_color("font_color", "Button", TEXT_PRIMARY)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.4))


## Setup panel styles — subtle dark glass card with soft shadow.
static func _setup_panels(theme: Theme) -> void:
	var panel = _create_glass_style(0.10, RADIUS_PANEL, 0.10, 1, 15.0, 18)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelContainer", panel.duplicate())


## Setup label styles — crisp, no blur shadow.
static func _setup_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", TEXT_PRIMARY)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))


## Setup line edit styles — sunken dark field with an accent focus ring.
static func _setup_line_edit(theme: Theme) -> void:
	var normal = _create_glass_style(0.0, RADIUS_CONTROL, 0.12, 1, 12.0)
	normal.bg_color = Color(0, 0, 0, 0.22)
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	theme.set_stylebox("normal", "LineEdit", normal)

	var focus = _accent_focus()
	focus.bg_color = Color(0, 0, 0, 0.22)
	theme.set_stylebox("focus", "LineEdit", focus)

	var read_only = normal.duplicate()
	read_only.bg_color = Color(0, 0, 0, 0.12)
	theme.set_stylebox("read_only", "LineEdit", read_only)

	theme.set_color("font_color", "LineEdit", TEXT_PRIMARY)
	theme.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.4))
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("clear_button_color", "LineEdit", Color(1, 1, 1, 0.55))
	theme.set_color("clear_button_color_pressed", "LineEdit", Color.WHITE)

	var x_icon = load(ICON_PATH + "x-bold.svg")
	if x_icon:
		theme.set_icon("clear", "LineEdit", x_icon)


## Setup checkbox and checkbutton styles
static func _setup_check_controls(theme: Theme) -> void:
	# CheckBox
	var cb_normal = _create_glass_style(0.0, RADIUS_CONTROL, 0.0, 0, 0)
	cb_normal.content_margin_right = 10
	theme.set_stylebox("normal", "CheckBox", cb_normal)
	theme.set_stylebox("hover", "CheckBox", cb_normal.duplicate())
	theme.set_stylebox("pressed", "CheckBox", cb_normal.duplicate())
	theme.set_stylebox("disabled", "CheckBox", cb_normal.duplicate())
	theme.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	theme.set_constant("h_separation", "CheckBox", 0)
	theme.set_color("font_color", "CheckBox", TEXT_PRIMARY)

	var checked_icon = load(ICON_PATH + "check-square-fill.svg")
	var unchecked_icon = load(ICON_PATH + "square-bold.svg")
	if checked_icon:
		theme.set_icon("checked", "CheckBox", checked_icon)
	if unchecked_icon:
		theme.set_icon("unchecked", "CheckBox", unchecked_icon)

	# CheckButton (toggle switch style)
	var cbt_normal = _create_glass_style(0.0, RADIUS_CONTROL, 0.0, 0, 0)
	cbt_normal.content_margin_left = 10
	theme.set_stylebox("normal", "CheckButton", cbt_normal)
	theme.set_stylebox("hover", "CheckButton", cbt_normal.duplicate())
	theme.set_stylebox("pressed", "CheckButton", cbt_normal.duplicate())
	theme.set_stylebox("disabled", "CheckButton", cbt_normal.duplicate())
	theme.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	theme.set_constant("h_separation", "CheckButton", 0)
	theme.set_color("font_color", "CheckButton", TEXT_PRIMARY)

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
	var slider_bg = StyleBoxFlat.new()
	slider_bg.bg_color = Color(1, 1, 1, 0.18)
	slider_bg.corner_radius_top_left = 80
	slider_bg.corner_radius_top_right = 80
	slider_bg.corner_radius_bottom_right = 80
	slider_bg.corner_radius_bottom_left = 80
	slider_bg.content_margin_top = 6
	slider_bg.content_margin_bottom = 6
	theme.set_stylebox("slider", "HSlider", slider_bg)
	theme.set_stylebox("grabber_area", "HSlider", slider_bg.duplicate())

	var slider_highlight = slider_bg.duplicate()
	slider_highlight.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55)
	theme.set_stylebox("grabber_area_highlight", "HSlider", slider_highlight)

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
	var grabber = StyleBoxFlat.new()
	grabber.bg_color = Color(1, 1, 1, 0.28)
	grabber.corner_radius_top_left = 8
	grabber.corner_radius_top_right = 8
	grabber.corner_radius_bottom_right = 8
	grabber.corner_radius_bottom_left = 8

	var grabber_highlight = grabber.duplicate()
	grabber_highlight.bg_color = Color(1, 1, 1, 0.45)

	var grabber_pressed = grabber.duplicate()
	grabber_pressed.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.7)

	var h_scroll = StyleBoxEmpty.new()
	h_scroll.content_margin_top = 5
	h_scroll.content_margin_bottom = 5
	theme.set_stylebox("scroll", "HScrollBar", h_scroll)
	theme.set_stylebox("scroll_focus", "HScrollBar", h_scroll.duplicate())
	theme.set_stylebox("grabber", "HScrollBar", grabber)
	theme.set_stylebox("grabber_highlight", "HScrollBar", grabber_highlight)
	theme.set_stylebox("grabber_pressed", "HScrollBar", grabber_pressed)

	var v_scroll = StyleBoxFlat.new()
	v_scroll.bg_color = Color(0.6, 0.6, 0.6, 0)
	v_scroll.content_margin_left = 5
	v_scroll.content_margin_right = 5
	theme.set_stylebox("scroll", "VScrollBar", v_scroll)
	theme.set_stylebox("scroll_focus", "VScrollBar", v_scroll.duplicate())
	theme.set_stylebox("grabber", "VScrollBar", grabber.duplicate())
	theme.set_stylebox("grabber_highlight", "VScrollBar", grabber_highlight.duplicate())
	theme.set_stylebox("grabber_pressed", "VScrollBar", grabber_pressed.duplicate())

	theme.set_icon("decrement", "VScrollBar", null)
	theme.set_icon("decrement_highlight", "VScrollBar", null)
	theme.set_icon("increment", "VScrollBar", null)
	theme.set_icon("increment_highlight", "VScrollBar", null)


## Setup option button (dropdown)
static func _setup_option_button(theme: Theme) -> void:
	theme.set_stylebox("normal", "OptionButton", _create_glass_style(0.16, RADIUS_CONTROL, 0.14))
	theme.set_stylebox("hover", "OptionButton", _create_glass_style(0.26, RADIUS_CONTROL, 0.18))
	theme.set_stylebox("pressed", "OptionButton", _create_glass_style(0.36, RADIUS_CONTROL, 0.18))
	theme.set_stylebox("disabled", "OptionButton", _create_glass_style(0.06, RADIUS_CONTROL, 0.08))
	theme.set_stylebox("focus", "OptionButton", _accent_focus())

	theme.set_color("font_color", "OptionButton", TEXT_PRIMARY)
	theme.set_color("font_hover_color", "OptionButton", Color.WHITE)
	theme.set_color("font_pressed_color", "OptionButton", Color.WHITE)
	theme.set_color("font_disabled_color", "OptionButton", Color(1, 1, 1, 0.4))

	var arrow_icon = load(ICON_PATH + "caret-down-bold.svg")
	if arrow_icon:
		theme.set_icon("arrow", "OptionButton", arrow_icon)
	theme.set_constant("arrow_margin", "OptionButton", 6)
	theme.set_constant("h_separation", "OptionButton", 4)


## Setup popup menu — opaque dark glass, hairline border, soft shadow.
static func _setup_popup_menu(theme: Theme) -> void:
	var panel = StyleBoxFlat.new()
	panel.bg_color = SURFACE
	panel.border_width_left = 1
	panel.border_width_top = 1
	panel.border_width_right = 1
	panel.border_width_bottom = 1
	panel.border_color = HAIRLINE
	panel.corner_radius_top_left = RADIUS_PANEL
	panel.corner_radius_top_right = RADIUS_PANEL
	panel.corner_radius_bottom_right = RADIUS_PANEL
	panel.corner_radius_bottom_left = RADIUS_PANEL
	panel.content_margin_left = 10
	panel.content_margin_top = 10
	panel.content_margin_right = 10
	panel.content_margin_bottom = 10
	panel.shadow_size = 22
	panel.shadow_color = SHADOW
	theme.set_stylebox("panel", "PopupMenu", panel)
	theme.set_stylebox("panel", "PopupPanel", panel.duplicate())

	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.10)
	hover.corner_radius_top_left = 8
	hover.corner_radius_top_right = 8
	hover.corner_radius_bottom_right = 8
	hover.corner_radius_bottom_left = 8
	theme.set_stylebox("hover", "PopupMenu", hover)
	theme.set_color("font_color", "PopupMenu", TEXT_PRIMARY)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)

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
	background.bg_color = Color(0, 0, 0, 0.22)
	background.corner_radius_top_left = RADIUS_CONTROL
	background.corner_radius_top_right = RADIUS_CONTROL
	background.corner_radius_bottom_right = RADIUS_CONTROL
	background.corner_radius_bottom_left = RADIUS_CONTROL
	theme.set_stylebox("background", "ProgressBar", background)

	var fill = StyleBoxFlat.new()
	fill.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45)
	fill.corner_radius_top_left = RADIUS_CONTROL
	fill.corner_radius_top_right = RADIUS_CONTROL
	fill.corner_radius_bottom_right = RADIUS_CONTROL
	fill.corner_radius_bottom_left = RADIUS_CONTROL
	theme.set_stylebox("fill", "ProgressBar", fill)

	theme.set_color("font_color", "ProgressBar", TEXT_PRIMARY)


## Setup tab container
static func _setup_tabs(theme: Theme) -> void:
	var panel = _create_glass_style(0.10, RADIUS_PANEL, 0.10, 1, 0)
	theme.set_stylebox("panel", "TabContainer", panel)

	var tab_selected = StyleBoxFlat.new()
	tab_selected.bg_color = Color(1, 1, 1, 0.16)
	tab_selected.border_width_bottom = 2
	tab_selected.border_color = ACCENT
	tab_selected.corner_radius_top_left = 8
	tab_selected.corner_radius_top_right = 8
	tab_selected.content_margin_left = 12
	tab_selected.content_margin_right = 12
	tab_selected.content_margin_top = 6
	tab_selected.content_margin_bottom = 6
	theme.set_stylebox("tab_selected", "TabContainer", tab_selected)

	var tab_unselected = StyleBoxFlat.new()
	tab_unselected.bg_color = Color(1, 1, 1, 0.04)
	tab_unselected.corner_radius_top_left = 8
	tab_unselected.corner_radius_top_right = 8
	tab_unselected.content_margin_left = 12
	tab_unselected.content_margin_right = 12
	tab_unselected.content_margin_top = 6
	tab_unselected.content_margin_bottom = 6
	theme.set_stylebox("tab_unselected", "TabContainer", tab_unselected)

	var tab_hovered = tab_unselected.duplicate()
	tab_hovered.bg_color = Color(1, 1, 1, 0.12)
	theme.set_stylebox("tab_hovered", "TabContainer", tab_hovered)

	var tab_disabled = tab_unselected.duplicate()
	tab_disabled.bg_color = Color(1, 1, 1, 0.02)
	theme.set_stylebox("tab_disabled", "TabContainer", tab_disabled)

	theme.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())

	theme.set_color("font_selected_color", "TabContainer", Color.WHITE)
	theme.set_color("font_unselected_color", "TabContainer", Color(1, 1, 1, 0.5))
	theme.set_color("font_hovered_color", "TabContainer", TEXT_PRIMARY)
	theme.set_font_size("font_size", "TabContainer", 14)
	theme.set_constant("side_margin", "TabContainer", 12)


## Setup tree view
static func _setup_tree(theme: Theme) -> void:
	var panel = _create_glass_style(0.0, RADIUS_PANEL, 0.10, 1, 10)
	theme.set_stylebox("panel", "Tree", panel)

	var selected = StyleBoxFlat.new()
	selected.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.22)
	selected.corner_radius_top_left = 6
	selected.corner_radius_top_right = 6
	selected.corner_radius_bottom_right = 6
	selected.corner_radius_bottom_left = 6
	theme.set_stylebox("selected", "Tree", selected)

	var hovered = StyleBoxFlat.new()
	hovered.bg_color = Color(1, 1, 1, 0.10)
	hovered.content_margin_left = 10
	theme.set_stylebox("hovered", "Tree", hovered)

	theme.set_stylebox("focus", "Tree", StyleBoxEmpty.new())

	theme.set_color("font_color", "Tree", TEXT_PRIMARY)
	theme.set_color("font_hovered_color", "Tree", Color.WHITE)
	theme.set_color("font_disabled_color", "Tree", Color(1, 1, 1, 0.24))
	theme.set_color("guide_color", "Tree", Color(1, 1, 1, 0.08))
	theme.set_constant("h_separation", "Tree", -5)
	theme.set_constant("item_margin", "Tree", 14)
	theme.set_constant("inner_item_margin_left", "Tree", 5)
	theme.set_font_size("font_size", "Tree", 14)


## Setup tooltip — dark glass, hairline border.
static func _setup_tooltip(theme: Theme) -> void:
	var panel = StyleBoxFlat.new()
	panel.bg_color = Color(0.05, 0.06, 0.09, 0.96)
	panel.border_width_left = 1
	panel.border_width_top = 1
	panel.border_width_right = 1
	panel.border_width_bottom = 1
	panel.border_color = HAIRLINE
	panel.corner_radius_top_left = RADIUS_CONTROL
	panel.corner_radius_top_right = RADIUS_CONTROL
	panel.corner_radius_bottom_right = RADIUS_CONTROL
	panel.corner_radius_bottom_left = RADIUS_CONTROL
	panel.content_margin_left = 10
	panel.content_margin_right = 10
	panel.content_margin_top = 7
	panel.content_margin_bottom = 7
	panel.shadow_size = 14
	panel.shadow_color = SHADOW
	theme.set_stylebox("panel", "TooltipPanel", panel)

	theme.set_color("font_color", "TooltipLabel", TEXT_PRIMARY)
	theme.set_font_size("font_size", "TooltipLabel", 15)


## Setup window/dialog styles — opaque dark glass, hairline border, soft shadow.
static func _setup_window(theme: Theme) -> void:
	var panel = StyleBoxFlat.new()
	panel.bg_color = SURFACE
	panel.border_width_left = 1
	panel.border_width_top = 1
	panel.border_width_right = 1
	panel.border_width_bottom = 1
	panel.border_color = HAIRLINE
	panel.corner_radius_top_left = RADIUS_PANEL
	panel.corner_radius_top_right = RADIUS_PANEL
	panel.corner_radius_bottom_right = RADIUS_PANEL
	panel.corner_radius_bottom_left = RADIUS_PANEL
	panel.content_margin_left = 16
	panel.content_margin_top = 16
	panel.content_margin_right = 16
	panel.content_margin_bottom = 16
	panel.shadow_size = 26
	panel.shadow_color = Color(0, 0, 0, 0.5)
	theme.set_stylebox("embedded_border", "Window", panel)
	theme.set_stylebox("panel", "AcceptDialog", panel.duplicate())

	theme.set_color("title_color", "Window", TEXT_PRIMARY)


## Setup separators — hairline.
static func _setup_separators(theme: Theme) -> void:
	var h_sep = StyleBoxLine.new()
	h_sep.color = Color(1, 1, 1, 0.10)
	theme.set_stylebox("separator", "HSeparator", h_sep)

	var v_sep = StyleBoxLine.new()
	v_sep.color = Color(1, 1, 1, 0.10)
	v_sep.vertical = true
	theme.set_stylebox("separator", "VSeparator", v_sep)
