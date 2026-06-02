extends Node
## Theme generator for the "Tactical HUD" UI language (sleek; cyan primary + amber
## secondary). The single source of truth for tokens/styles is
## scripts/hud/hud_tokens.gd; this file adapts them to Godot's Theme and the standard
## controls, and registers button variations: PrimaryButton / AmberButton / DangerButton.

const T := preload("res://scripts/hud/hud_tokens.gd")
const ICON_PATH := "res://assets/ui_glassmorphism/icons/"

static var _cached_theme: Theme = null


static func get_theme() -> Theme:
	if _cached_theme:
		return _cached_theme
	_cached_theme = create_theme()
	return _cached_theme


static func create_theme() -> Theme:
	var th := Theme.new()
	th.default_font = T.body_font()
	th.default_font_size = 15

	_buttons(th)
	_panels(th)
	_window(th)
	_popup(th)
	_inputs(th)
	_option(th)
	_checks(th)
	_sliders(th)
	_scrollbars(th)
	_progress(th)
	_tabs(th)
	_tree(th)
	_tooltip(th)
	_labels(th)
	_separators(th)

	print("[HudTheme] created")
	return th


# ===== Focus =====
## Visible keyboard/controller focus ring: a >=2px cyan border clearing >=3:1 against
## the deep-navy SURFACE (WCAG 2.4.13). Reused by every interactive control so focus is
## never invisible or clipped. `expand` lifts the ring off the control so it reads on
## small/dense widgets (checkboxes, tabs).
static func _focus(expand: float = 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.set_corner_radius_all(T.RADIUS)
	s.set_border_width_all(2)
	s.border_color = Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.85)
	if expand > 0.0:
		s.expand_margin_left = expand
		s.expand_margin_right = expand
		s.expand_margin_top = expand
		s.expand_margin_bottom = expand
	return s


# ===== Buttons (default = ghost; variations for primary/amber/danger) =====
static func _apply_button(th: Theme, type: String, styles: Dictionary, font_color: Color) -> void:
	th.set_stylebox("normal", type, styles.normal)
	th.set_stylebox("hover", type, styles.hover)
	th.set_stylebox("pressed", type, styles.pressed)
	th.set_stylebox("disabled", type, T.button_style(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.06)))
	th.set_stylebox("focus", type, _focus())
	th.set_color("font_color", type, font_color)
	th.set_color("font_hover_color", type, Color.WHITE)
	th.set_color("font_pressed_color", type, Color.WHITE)
	th.set_color("font_disabled_color", type, Color(1, 1, 1, 0.35))


static func _buttons(th: Theme) -> void:
	_apply_button(th, "Button", T.ghost_button(), T.TEXT)

	th.set_type_variation("PrimaryButton", "Button")
	_apply_button(th, "PrimaryButton", T.primary_button(), Color(0.86, 0.97, 1.0))

	th.set_type_variation("AmberButton", "Button")
	_apply_button(th, "AmberButton", T.amber_button(), T.AMBER)

	th.set_type_variation("DangerButton", "Button")
	var danger := {
		"normal": T.button_style(Color(T.DANGER.r, T.DANGER.g, T.DANGER.b, 0.12), Color(T.DANGER.r, T.DANGER.g, T.DANGER.b, 0.7)),
		"hover": T.button_style(Color(T.DANGER.r, T.DANGER.g, T.DANGER.b, 0.24), T.DANGER),
		"pressed": T.button_style(Color(T.DANGER.r, T.DANGER.g, T.DANGER.b, 0.36), T.DANGER),
	}
	_apply_button(th, "DangerButton", danger, T.DANGER)


# ===== Panels =====
static func _panels(th: Theme) -> void:
	th.set_stylebox("panel", "Panel", T.panel_style())
	th.set_stylebox("panel", "PanelContainer", T.panel_style())


# ===== Window / dialog =====
static func _window(th: Theme) -> void:
	var p := T.panel_style()
	p.corner_radius_top_left = 6
	p.corner_radius_top_right = 6
	p.corner_radius_bottom_right = 6
	p.corner_radius_bottom_left = 6
	p.shadow_size = 28
	p.shadow_color = Color(0, 0, 0, 0.55)
	p.content_margin_left = 16
	p.content_margin_top = 16
	p.content_margin_right = 16
	p.content_margin_bottom = 16
	th.set_stylebox("embedded_border", "Window", p)
	th.set_stylebox("panel", "AcceptDialog", p.duplicate())
	th.set_color("title_color", "Window", T.TEXT)


# ===== Popup menu =====
static func _popup(th: Theme) -> void:
	var p := T.panel_style()
	p.content_margin_left = 8
	p.content_margin_right = 8
	p.content_margin_top = 8
	p.content_margin_bottom = 8
	p.shadow_size = 22
	th.set_stylebox("panel", "PopupMenu", p)
	th.set_stylebox("panel", "PopupPanel", p.duplicate())

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.16)
	hover.set_corner_radius_all(T.RADIUS)
	th.set_stylebox("hover", "PopupMenu", hover)
	th.set_color("font_color", "PopupMenu", T.TEXT)
	th.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	th.set_color("font_accelerator_color", "PopupMenu", T.TEXT_MUTED)

	_load_icon(th, "checked", "PopupMenu", "check-square-fill.svg")
	_load_icon(th, "unchecked", "PopupMenu", "square-bold.svg")
	_load_icon(th, "radio_checked", "PopupMenu", "radio-button-fill.svg")
	_load_icon(th, "radio_unchecked", "PopupMenu", "circle-fill.svg")


# ===== Inputs =====
static func _inputs(th: Theme) -> void:
	var normal := T.sunken_style()
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	th.set_stylebox("normal", "LineEdit", normal)

	var focus := _focus()
	focus.bg_color = T.SUNKEN
	th.set_stylebox("focus", "LineEdit", focus)

	var read_only := normal.duplicate()
	read_only.bg_color = Color(0, 0, 0, 0.14)
	th.set_stylebox("read_only", "LineEdit", read_only)

	th.set_color("font_color", "LineEdit", T.TEXT)
	th.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.38))
	th.set_color("caret_color", "LineEdit", T.CYAN)
	th.set_color("selection_color", "LineEdit", Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.30))
	th.set_color("clear_button_color", "LineEdit", Color(1, 1, 1, 0.5))
	th.set_color("clear_button_color_pressed", "LineEdit", Color.WHITE)
	_load_icon(th, "clear", "LineEdit", "x-bold.svg")


# ===== Option button =====
static func _option(th: Theme) -> void:
	var g := T.ghost_button()
	th.set_stylebox("normal", "OptionButton", g.normal)
	th.set_stylebox("hover", "OptionButton", g.hover)
	th.set_stylebox("pressed", "OptionButton", g.pressed)
	th.set_stylebox("disabled", "OptionButton", T.button_style(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.06)))
	th.set_stylebox("focus", "OptionButton", _focus())
	th.set_color("font_color", "OptionButton", T.TEXT)
	th.set_color("font_hover_color", "OptionButton", Color.WHITE)
	th.set_color("font_pressed_color", "OptionButton", Color.WHITE)
	_load_icon(th, "arrow", "OptionButton", "caret-down-bold.svg")
	th.set_constant("arrow_margin", "OptionButton", 6)
	th.set_constant("h_separation", "OptionButton", 4)


# ===== Check controls =====
static func _checks(th: Theme) -> void:
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled"]:
		th.set_stylebox(state, "CheckBox", empty.duplicate())
		th.set_stylebox(state, "CheckButton", empty.duplicate())
	# Visible focus ring (was StyleBoxEmpty -> keyboard/controller users saw nothing).
	th.set_stylebox("focus", "CheckBox", _focus(3.0))
	th.set_stylebox("focus", "CheckButton", _focus(3.0))
	th.set_color("font_color", "CheckBox", T.TEXT)
	th.set_color("font_color", "CheckButton", T.TEXT)
	_load_icon(th, "checked", "CheckBox", "check-square-fill.svg")
	_load_icon(th, "unchecked", "CheckBox", "square-bold.svg")
	_load_icon(th, "checked", "CheckButton", "toggle-right-fill.svg")
	_load_icon(th, "unchecked", "CheckButton", "toggle-left.svg")
	_load_icon(th, "checked_disabled", "CheckButton", "toggle-right-fill-disabled.svg")
	_load_icon(th, "unchecked_disabled", "CheckButton", "toggle-left-disabled.svg")


# ===== Sliders =====
static func _sliders(th: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.14)
	track.set_corner_radius_all(80)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", track.duplicate())
	var hi := track.duplicate()
	hi.bg_color = Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.6)
	th.set_stylebox("grabber_area_highlight", "HSlider", hi)
	_load_icon(th, "grabber", "HSlider", "dot-bold.svg")
	_load_icon(th, "grabber_highlight", "HSlider", "dot-bold-highlight.svg")
	_load_icon(th, "grabber", "VSlider", "dot-bold.svg")
	_load_icon(th, "grabber_highlight", "VSlider", "dot-bold-highlight.svg")
	var vtrack := track.duplicate()
	vtrack.content_margin_top = 0
	vtrack.content_margin_bottom = 0
	vtrack.content_margin_left = 6
	vtrack.content_margin_right = 6
	th.set_stylebox("slider", "VSlider", vtrack)
	th.set_stylebox("grabber_area", "VSlider", vtrack.duplicate())
	th.set_stylebox("grabber_area_highlight", "VSlider", hi.duplicate())


# ===== Scrollbars =====
static func _scrollbars(th: Theme) -> void:
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(1, 1, 1, 0.22)
	grabber.set_corner_radius_all(6)
	var hi := grabber.duplicate()
	hi.bg_color = Color(1, 1, 1, 0.4)
	var pressed := grabber.duplicate()
	pressed.bg_color = Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.7)
	for axis in ["HScrollBar", "VScrollBar"]:
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		th.set_stylebox("scroll", axis, sb)
		th.set_stylebox("grabber", axis, grabber.duplicate())
		th.set_stylebox("grabber_highlight", axis, hi.duplicate())
		th.set_stylebox("grabber_pressed", axis, pressed.duplicate())
		th.set_icon("decrement", axis, null)
		th.set_icon("increment", axis, null)


# ===== Progress =====
static func _progress(th: Theme) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = T.SUNKEN
	bg.set_corner_radius_all(T.RADIUS)
	th.set_stylebox("background", "ProgressBar", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.55)
	fill.set_corner_radius_all(T.RADIUS)
	th.set_stylebox("fill", "ProgressBar", fill)
	th.set_color("font_color", "ProgressBar", T.TEXT)


# ===== Tabs =====
static func _tabs(th: Theme) -> void:
	th.set_stylebox("panel", "TabContainer", T.panel_style())

	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(1, 1, 1, 0.06)
	sel.border_width_bottom = 2
	sel.border_color = T.CYAN
	sel.content_margin_left = 12
	sel.content_margin_right = 12
	sel.content_margin_top = 6
	sel.content_margin_bottom = 6
	th.set_stylebox("tab_selected", "TabContainer", sel)

	var unsel := sel.duplicate()
	unsel.bg_color = Color(1, 1, 1, 0.0)
	unsel.border_width_bottom = 0
	th.set_stylebox("tab_unselected", "TabContainer", unsel)

	var hov := unsel.duplicate()
	hov.bg_color = Color(1, 1, 1, 0.06)
	th.set_stylebox("tab_hovered", "TabContainer", hov)
	th.set_stylebox("tab_disabled", "TabContainer", unsel.duplicate())
	th.set_stylebox("tab_focus", "TabContainer", _focus())

	th.set_color("font_selected_color", "TabContainer", Color.WHITE)
	th.set_color("font_unselected_color", "TabContainer", T.TEXT_MUTED)
	th.set_color("font_hovered_color", "TabContainer", T.TEXT)
	th.set_font_size("font_size", "TabContainer", 14)
	th.set_constant("side_margin", "TabContainer", 10)


# ===== Tree =====
static func _tree(th: Theme) -> void:
	var p := T.panel_style()
	p.bg_color = Color(0, 0, 0, 0.10)
	th.set_stylebox("panel", "Tree", p)
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.22)
	sel.set_corner_radius_all(4)
	th.set_stylebox("selected", "Tree", sel)
	var hov := StyleBoxFlat.new()
	hov.bg_color = Color(1, 1, 1, 0.08)
	th.set_stylebox("hovered", "Tree", hov)
	th.set_stylebox("focus", "Tree", _focus())
	th.set_color("font_color", "Tree", T.TEXT)
	th.set_color("font_hovered_color", "Tree", Color.WHITE)
	th.set_color("guide_color", "Tree", Color(1, 1, 1, 0.06))
	th.set_font_size("font_size", "Tree", 14)


# ===== Tooltip =====
static func _tooltip(th: Theme) -> void:
	var p := StyleBoxFlat.new()
	p.bg_color = Color(0.05, 0.06, 0.085, 0.97)
	p.set_corner_radius_all(T.RADIUS)
	p.set_border_width_all(1)
	p.border_color = T.HAIRLINE
	p.content_margin_left = 10
	p.content_margin_right = 10
	p.content_margin_top = 7
	p.content_margin_bottom = 7
	p.shadow_size = 14
	p.shadow_color = Color(0, 0, 0, 0.45)
	th.set_stylebox("panel", "TooltipPanel", p)
	th.set_color("font_color", "TooltipLabel", T.TEXT)
	th.set_font_size("font_size", "TooltipLabel", 14)


# ===== Labels =====
static func _labels(th: Theme) -> void:
	th.set_color("font_color", "Label", T.TEXT)
	th.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))


# ===== Separators =====
static func _separators(th: Theme) -> void:
	var h := StyleBoxLine.new()
	h.color = T.HAIRLINE
	th.set_stylebox("separator", "HSeparator", h)
	var v := StyleBoxLine.new()
	v.color = T.HAIRLINE
	v.vertical = true
	th.set_stylebox("separator", "VSeparator", v)


# ===== Helpers =====
static func _load_icon(th: Theme, name: String, type: String, file: String) -> void:
	var icon = load(ICON_PATH + file)
	if icon:
		th.set_icon(name, type, icon)
