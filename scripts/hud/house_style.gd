class_name HouseStyle
extends RefCounted
## The in-game house style (maintainer decision 23.09.2026): ONE place for the design tokens and
## the small style builder every in-game window uses. The values are the approved HUD mockup's
## (model-forge ingame-hud-mockup-2026-09-22/style.css); the dice window is the first consumer and
## the prototype the later windows copy.
##
## How a window uses it:
##   HouseStyle.apply(panel)                       once, on the window's root PanelContainer
##   HouseStyle.panel_header("DICE ROLLER")        eyebrow title + collapse control
##   HouseStyle.button(text, HouseStyle.PIP)       buttons by variant (BUTTON/SEGMENT/PIP/PRIMARY/ICON)
##   HouseStyle.set_selected(btn, true)            the selected state (gold segment / accent pip)
##   HouseStyle.field_row / stepper / card / label  rows, steppers, sunken cards, text roles
## A window never sets a colour, radius, border or font size itself — it picks a variant. The looks
## live in theme() as type variations, so hover / pressed / disabled come from the theme, not code.
## HudTokens stays for the windows that are not migrated yet.

const FONT_PATH := "res://assets/ui_glassmorphism/fonts/Inter.ttf"

# ===== Palette (mockup :root) =====
const INK := Color("e9e9df")          # text
const MUTED := Color("a7b0b6")        # captions, secondary text
const ACCENT := Color("87babc")       # eyebrow titles, hover rims, selected pips (mockup --cyan)
const GOLD := Color("d9bd83")         # the primary action, selected segments, key values
const ON_GOLD := Color("1a1408")      # text on a gold fill
const ON_ACCENT := Color("dff2f2")    # text on a selected pip
const PANEL := Color(0.047, 0.075, 0.098, 0.92)   # rgba(12,19,25): .86 in the mockup, denser in-game (no backdrop blur)
const LINE := Color("334047")         # control rims
const LINE_SOFT := Color(0.529, 0.729, 0.737, 0.22)   # window rim (accent at 22 %)
const FILL := Color(1, 1, 1, 0.03)    # a resting control
const FILL_RAISED := Color(1, 1, 1, 0.05)   # icon buttons
const WELL := Color(0, 0, 0, 0.30)    # sunken cards: counter, result, log
# State colours: always paired with a label or glyph, never hue alone.
const OK := Color("5fbf8a")
const WARN := Color("e0a34a")
const DANGER := Color("c0563f")
# Interaction alphas over ACCENT / GOLD (mockup hover .12-.16, selected pip .20, primary hover brightness 1.08).
const HOVER_ALPHA := 0.12
const PRESS_ALPHA := 0.22
const SELECTED_ALPHA := 0.20
const GOLD_HOVER_LIGHTEN := 0.08
const GOLD_PRESS_DARKEN := 0.12
const DISABLED_ALPHA := 0.40

# ===== Geometry (px at the 1920x1080 base; the canvas_items stretch scales the rest) =====
const BORDER := 1
const RADIUS_PANEL := 8
const RADIUS_CARD := 6
const RADIUS_CONTROL := 5
const PAD_PANEL := 14
const PAD_CARD_X := 10
const PAD_CARD_Y := 8
const PAD_BUTTON_X := 6
const GAP_SECTION := 10     # between a window's sections
const GAP_ROW := 8          # between rows inside a section
const GAP_CONTROL := 4      # between controls in a row
const CAPTION_W := 72       # the label column of a field row
const H_SEGMENT := 32
const H_PIP := 30
const H_ACTION := 40
const H_CHIP := 28
const ICON_BUTTON := 28

# ===== Type =====
const FONT_BODY := 14
const FONT_ACTION := 15
const FONT_CAPTION := 13
const FONT_SMALL := 12
const FONT_EYEBROW := 12
const FONT_VALUE := 22
const EYEBROW_SPACING := 2   # extra px per glyph (mockup letter-spacing .12em)

# ===== Variants (theme type variations; pick one per control) =====
const PANEL_VARIANT := &"HsPanel"   # a window root
const CARD := &"HsCard"             # sunken card: counter, result, log
const BUTTON := &"HsButton"         # ghost button: Quick, re-roll chips, stepper steps
const SEGMENT := &"HsSegment"       # one of a segmented group; selected = gold
const PIP := &"HsPip"               # one of a pip row; selected = accent
const PRIMARY := &"HsPrimary"       # the one main action (gold)
const ICON := &"HsIcon"             # close / collapse
const BODY := &"HsBody"             # plain text / a small value
const CAPTION := &"HsCaption"       # muted field label
const EYEBROW := &"HsEyebrow"       # the window title
const VALUE := &"HsValue"           # a big number (the dice count)
const NOTE := &"HsNote"             # a gold key line (roll purpose, result summary)
const SMALL := &"HsSmall"           # dense readout text (log lines, tally counts)
const HIT := &"HsHit"               # a success count next to its glyph
const SELECTED_SUFFIX := "On"

# ===== Glyphs (Inter carries each one; the dice-panel inventory test checks has_char) =====
const GLYPH_COLLAPSE := "▼"
const GLYPH_EXPAND := "▲"
const GLYPH_MINUS := "−"

const _META_EXPANDED_OFFSET := &"hs_expanded_offset"

static var _theme: Theme = null


# ===== Theme =====

## The shared Theme: every variant above as a type variation. Built once, reused by every window.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = load(FONT_PATH) as Font
	t.default_font_size = FONT_BODY

	t.set_type_variation(PANEL_VARIANT, &"PanelContainer")
	t.set_stylebox(&"panel", PANEL_VARIANT, _box(PANEL, LINE_SOFT, RADIUS_PANEL, PAD_PANEL, PAD_PANEL))
	t.set_type_variation(CARD, &"PanelContainer")
	t.set_stylebox(&"panel", CARD, _box(WELL, LINE, RADIUS_CARD, PAD_CARD_X, PAD_CARD_Y))

	var hover := _box(_alpha(ACCENT, HOVER_ALPHA), ACCENT, RADIUS_CONTROL, PAD_BUTTON_X, 0)
	var press := _box(_alpha(ACCENT, PRESS_ALPHA), ACCENT, RADIUS_CONTROL, PAD_BUTTON_X, 0)
	var off := _box(_alpha(FILL, 0.5), _alpha(LINE, 0.5), RADIUS_CONTROL, PAD_BUTTON_X, 0)
	var rest := _box(FILL, LINE, RADIUS_CONTROL, PAD_BUTTON_X, 0)
	for v: StringName in [BUTTON, SEGMENT, PIP]:
		_button_variant(t, v, rest, hover, press, off, INK, FONT_BODY)
	var gold := _box(GOLD, GOLD, RADIUS_CONTROL, PAD_BUTTON_X, 0)
	var gold_hover := _box(GOLD.lightened(GOLD_HOVER_LIGHTEN), GOLD.lightened(GOLD_HOVER_LIGHTEN), RADIUS_CONTROL, PAD_BUTTON_X, 0)
	var gold_press := _box(GOLD.darkened(GOLD_PRESS_DARKEN), GOLD.darkened(GOLD_PRESS_DARKEN), RADIUS_CONTROL, PAD_BUTTON_X, 0)
	var gold_off := _box(_alpha(GOLD, DISABLED_ALPHA), _alpha(GOLD, DISABLED_ALPHA), RADIUS_CONTROL, PAD_BUTTON_X, 0)
	_button_variant(t, _on(SEGMENT), gold, gold_hover, gold_press, gold_off, ON_GOLD, FONT_BODY)
	var pip_on := _box(_alpha(ACCENT, SELECTED_ALPHA), ACCENT, RADIUS_CONTROL, PAD_BUTTON_X, 0)
	var pip_on_hover := _box(_alpha(ACCENT, SELECTED_ALPHA + HOVER_ALPHA), ACCENT, RADIUS_CONTROL, PAD_BUTTON_X, 0)
	_button_variant(t, _on(PIP), pip_on, pip_on_hover, press, off, ON_ACCENT, FONT_BODY)
	var primary := [_radius(gold, RADIUS_CARD), _radius(gold_hover, RADIUS_CARD),
		_radius(gold_press, RADIUS_CARD), _radius(gold_off, RADIUS_CARD)]
	_button_variant(t, PRIMARY, primary[0], primary[1], primary[2], primary[3], ON_GOLD, FONT_ACTION)
	t.set_color(&"font_disabled_color", PRIMARY, _alpha(ON_GOLD, 0.7))
	_button_variant(t, ICON, _box(FILL_RAISED, LINE, RADIUS_CARD, 0, 0),
		_box(_alpha(ACCENT, HOVER_ALPHA + 0.04), ACCENT, RADIUS_CARD, 0, 0),
		_box(_alpha(ACCENT, PRESS_ALPHA), ACCENT, RADIUS_CARD, 0, 0), off, INK, FONT_BODY)
	# Quick and the other ghost actions keep the calmer ghost rim radius of the mockup (6).
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		t.set_stylebox(state, BUTTON, _radius(t.get_stylebox(state, BUTTON) as StyleBoxFlat, RADIUS_CARD))

	_label_variant(t, BODY, INK, FONT_BODY)
	_label_variant(t, CAPTION, MUTED, FONT_CAPTION)
	_label_variant(t, EYEBROW, ACCENT, FONT_EYEBROW)
	var spaced := FontVariation.new()
	spaced.base_font = t.default_font
	spaced.spacing_glyph = EYEBROW_SPACING
	t.set_font(&"font", EYEBROW, spaced)
	_label_variant(t, VALUE, INK, FONT_VALUE)
	_label_variant(t, NOTE, GOLD, FONT_CAPTION)
	_label_variant(t, SMALL, INK, FONT_SMALL)
	_label_variant(t, HIT, ACCENT, FONT_BODY)
	t.set_color(&"font_color", &"Label", INK)

	# A slim scrollbar for sunken lists (the dice log).
	var grab := _box(LINE, LINE, RADIUS_CONTROL, 0, 0)
	var grab_hot := _box(ACCENT, ACCENT, RADIUS_CONTROL, 0, 0)
	var track := StyleBoxEmpty.new()
	track.content_margin_left = 3
	track.content_margin_right = 3
	t.set_stylebox(&"scroll", &"VScrollBar", track)
	t.set_stylebox(&"grabber", &"VScrollBar", grab)
	t.set_stylebox(&"grabber_highlight", &"VScrollBar", grab_hot)
	t.set_stylebox(&"grabber_pressed", &"VScrollBar", grab_hot)
	_theme = t
	return t


# ===== Builder =====

## Styles a window root: its whole subtree resolves the variants from theme().
static func apply(root: Control) -> void:
	root.theme = theme()
	if root is PanelContainer:
		root.theme_type_variation = PANEL_VARIANT


## A focus-less button of `variant`, filling its row. `height` < 0 takes the variant's default.
static func button(text: String, variant: StringName = BUTTON, height: int = -1) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variant
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, height if height >= 0 else _default_height(variant))
	return b


## Marks a SEGMENT / PIP button selected (gold segment, accent pip) or back to resting.
static func set_selected(b: Button, selected: bool) -> void:
	var base := String(b.theme_type_variation).trim_suffix(SELECTED_SUFFIX)
	b.theme_type_variation = StringName(base + SELECTED_SUFFIX) if selected else StringName(base)


static func is_selected(b: Button) -> bool:
	return String(b.theme_type_variation).ends_with(SELECTED_SUFFIX)


## A label in one of the text roles (BODY, CAPTION, EYEBROW, VALUE, NOTE, SMALL, HIT).
static func label(text: String, variant: StringName = CAPTION) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variant
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## A row of equal buttons — a segmented group (SEGMENT) or a pip row (PIP). The buttons are the
## row's children, in `texts` order.
static func button_row(texts: Array, variant: StringName, height: int = -1) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", GAP_CONTROL)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for text: Variant in texts:
		row.add_child(button(str(text), variant, height))
	return row


## "Caption  [content]": a muted label column, then the content filling the rest.
static func field_row(caption: String, content: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", GAP_SECTION)
	var l := label(caption, CAPTION)
	l.custom_minimum_size = Vector2(CAPTION_W, 0)
	row.add_child(l)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(content)
	return row


## A stepper: one ghost button per delta (negatives left of `middle`, positives right), each
## pressing on_step(delta). Buttons are named "<name_prefix><delta>" ("Modifier+1").
static func stepper(deltas: Array, middle: Control, on_step: Callable, name_prefix: String = "Step") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", GAP_CONTROL)
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var placed_middle := false
	for d: Variant in deltas:
		var delta := int(d)
		if delta > 0 and not placed_middle:
			row.add_child(middle)
			placed_middle = true
		var b := button(step_text(delta), BUTTON, H_PIP)
		b.name = "%s%+d" % [name_prefix, delta]
		b.pressed.connect(on_step.bind(delta))
		row.add_child(b)
	if not placed_middle:
		row.add_child(middle)
	return row


## "−10" / "+5": a step label with the typographic minus.
static func step_text(delta: int) -> String:
	return ("+%d" % delta) if delta > 0 else (GLYPH_MINUS + str(absi(delta)))


## A sunken card (counter, result, log) holding `child`.
static func card(child: Control = null) -> PanelContainer:
	var c := PanelContainer.new()
	c.theme_type_variation = CARD
	if child != null:
		c.add_child(child)
	return c


## The window header: eyebrow title left, collapse control right (named "CollapseButton").
static func panel_header(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Header"
	row.add_theme_constant_override(&"separation", GAP_ROW)
	var t := label(title.to_upper(), EYEBROW)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	var b := button(GLYPH_COLLAPSE, ICON, ICON_BUTTON)
	b.name = "CollapseButton"
	b.tooltip_text = "Collapse"
	b.custom_minimum_size = Vector2(ICON_BUTTON, ICON_BUTTON)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(b)
	return row


## Folds a window to its header or unfolds it: hides / shows `body`, flips the collapse glyph and
## lets the window shrink toward its anchored edge (a bottom-anchored window keeps its bottom edge,
## a top-anchored one its top edge), restoring the expanded rect on unfold.
static func set_collapsed(panel: Control, body: Array, collapse_button: Button, collapsed: bool) -> void:
	for node: Variant in body:
		(node as CanvasItem).visible = not collapsed
	collapse_button.text = GLYPH_EXPAND if collapsed else GLYPH_COLLAPSE
	collapse_button.tooltip_text = "Expand" if collapsed else "Collapse"
	var grows_up := panel.grow_vertical == Control.GROW_DIRECTION_BEGIN
	if collapsed:
		if not panel.has_meta(_META_EXPANDED_OFFSET):
			panel.set_meta(_META_EXPANDED_OFFSET, panel.offset_top if grows_up else panel.offset_bottom)
		# A zero-height rect: the minimum size re-grows it away from the anchored edge.
		if grows_up:
			panel.offset_top = panel.offset_bottom
		else:
			panel.offset_bottom = panel.offset_top
	elif panel.has_meta(_META_EXPANDED_OFFSET):
		if grows_up:
			panel.offset_top = panel.get_meta(_META_EXPANDED_OFFSET)
		else:
			panel.offset_bottom = panel.get_meta(_META_EXPANDED_OFFSET)
		panel.remove_meta(_META_EXPANDED_OFFSET)


# ===== Internals =====

static func _default_height(variant: StringName) -> int:
	match StringName(String(variant).trim_suffix(SELECTED_SUFFIX)):
		SEGMENT:
			return H_SEGMENT
		PRIMARY:
			return H_ACTION
		ICON:
			return ICON_BUTTON
		_:
			return H_PIP


static func _on(variant: StringName) -> StringName:
	return StringName(String(variant) + SELECTED_SUFFIX)


static func _alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a if c.a < 1.0 else a)


static func _box(fill: Color, rim: Color, radius: int, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = rim
	s.set_border_width_all(BORDER)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	return s


static func _radius(s: StyleBoxFlat, radius: int) -> StyleBoxFlat:
	var copy := s.duplicate() as StyleBoxFlat
	copy.set_corner_radius_all(radius)
	return copy


static func _button_variant(t: Theme, v: StringName, rest: StyleBox, hover: StyleBox, press: StyleBox,
		off: StyleBox, ink: Color, font_size: int) -> void:
	t.set_type_variation(v, &"Button")
	t.set_stylebox(&"normal", v, rest)
	t.set_stylebox(&"hover", v, hover)
	t.set_stylebox(&"pressed", v, press)
	t.set_stylebox(&"hover_pressed", v, press)
	t.set_stylebox(&"disabled", v, off)
	t.set_stylebox(&"focus", v, StyleBoxEmpty.new())
	for c: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		t.set_color(c, v, ink)
	t.set_color(&"font_disabled_color", v, _alpha(MUTED, DISABLED_ALPHA + 0.1))
	t.set_font_size(&"font_size", v, font_size)


static func _label_variant(t: Theme, v: StringName, ink: Color, font_size: int) -> void:
	t.set_type_variation(v, &"Label")
	t.set_color(&"font_color", v, ink)
	t.set_font_size(&"font_size", v, font_size)
