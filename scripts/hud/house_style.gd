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
const DANGER_INK_LIFT := 0.15   # danger text lifted to ~5:1 on a panel (DANGER itself reads ~4.1:1 at 14 px)

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
const W_RAIL := 54          # a tool-rail button (mockup .rail-btn in a 66 px rail)
const H_RAIL := 56
const PAD_RAIL := 6
const RAIL_ICON := 22       # drawn size of a rail icon
const H_KEYCAP := 24
const RADIUS_KEYCAP := 3
const RADIUS_SHEET := 10
const PAD_SHEET := 22
const SHEET_FILL := Color("0e161c")                    # an overlay sheet (mockup --panel-solid)
const SCRIM := Color(0.016, 0.027, 0.039, 0.66)        # behind an overlay sheet (mockup rgba(4,7,10,.66))
const KEYCAP_FILL := Color("1b262d")                   # a key cap (mockup kbd)
const H_BAR := 32           # a top-bar item (mockup chips 34 / buttons 38 on a 60 px bar; here no bar behind)
const BAR_TOP := 12         # the top bar's row
const PAD_CHIP_X := 10
const PAD_BAR_PRIMARY_X := 14
const DOT := 8              # the side dot of a turn chip
const RADIUS_PILL := 13     # a status pill on a unit card (mockup .pill)
const PAD_PILL_X := 7
## Tones of a card's pills and links.
const TONE_GOLD := &"gold"       # activated
const TONE_WARN := &"warn"       # fatigued, shaken, wounds
const TONE_ACCENT := &"accent"   # caster, revive, rule links
const TONE_MUTED := &"muted"     # weapon rule links, offline
const TONE_OK := &"ok"           # online, reconnected
const TONE_DANGER := &"danger"   # failed, refused, lost for good

# ===== Type =====
const FONT_BODY := 14
const FONT_ACTION := 15
const FONT_CAPTION := 13
const FONT_SMALL := 12
const FONT_EYEBROW := 12
const FONT_VALUE := 22
const EYEBROW_SPACING := 2   # extra px per glyph (mockup letter-spacing .12em)
const FONT_RAIL := 11        # a rail button's label

# ===== Variants (theme type variations; pick one per control) =====
const PANEL_VARIANT := &"HsPanel"   # a window root
const CARD := &"HsCard"             # sunken card: counter, result, log
const BUTTON := &"HsButton"         # ghost button: Quick, re-roll chips, stepper steps
const SEGMENT := &"HsSegment"       # one of a segmented group; selected = gold
const PIP := &"HsPip"               # one of a pip row; selected = accent
const PRIMARY := &"HsPrimary"       # the one main action (gold)
const ICON := &"HsIcon"             # close / collapse
const DANGER_BUTTON := &"HsDanger"  # a ghost button that ends something for good (End Battle)
const BODY := &"HsBody"             # plain text / a small value
const CAPTION := &"HsCaption"       # muted field label
const EYEBROW := &"HsEyebrow"       # the window title
const VALUE := &"HsValue"           # a big number (the dice count)
const NOTE := &"HsNote"             # a gold key line (roll purpose, result summary)
const SMALL := &"HsSmall"           # dense readout text (log lines, tally counts)
const HIT := &"HsHit"               # a success count next to its glyph
const RAIL := &"HsRail"             # a tool in the tool rail; the open tool = selected (gold)
const RAIL_PANEL := &"HsRailPanel"  # the rail's own slim frame
const KEYCAP := &"HsKeyCap"         # a key in a shortcut hint (static)
const KEY := &"HsKey"               # a key cap you can click: it presses that key
const TOOL_LINE := &"HsToolLine"    # a row: an action's name left, its keys right (mockup .tool-line)
const SHEET := &"HsSheet"           # an overlay sheet (the controls help)
const BAR_BUTTON := &"HsBarButton"  # a top-bar button: it carries a window's dark fill itself (no bar behind)
const BAR_PRIMARY := &"HsBarPrimary"  # the top bar's one main action (gold): Next Round
const CHIP := &"HsChip"             # a top-bar state chip: the phase (muted)
const CHIP_ROUND := &"HsChipRound"  # the round (gold)
const CHIP_TURN := &"HsChipTurn"    # your turn (accent dot)
const CHIP_ENEMY := &"HsChipEnemy"  # the opponent's turn (danger dot)
## A chip's text colour and its dot (transparent = no dot).
const CHIP_INK := {CHIP: MUTED, CHIP_ROUND: GOLD, CHIP_TURN: INK, CHIP_ENEMY: INK}
const CHIP_DOT := {CHIP: Color(0, 0, 0, 0), CHIP_ROUND: Color(0, 0, 0, 0), CHIP_TURN: ACCENT, CHIP_ENEMY: DANGER}
const SELECTED_SUFFIX := "On"

# ===== Glyphs (Inter carries each one; the dice-panel inventory test checks has_char) =====
const GLYPH_COLLAPSE := "▼"
const GLYPH_EXPAND := "▲"
const GLYPH_MINUS := "−"
const GLYPH_CLOSE := "×"
const GLYPH_GO := "›"

# ===== Dice =====
## The dice look — ONE switch for the physics dice, their tally icons and the dice log
## (DiceLook: &"classic" ivory, &"house" smoked + gold, &"brass" brass + black enamel).
const DICE_LOOK := &"classic"

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
	# A switched-on action line (Terrain mode, zones shown): the accent of a selected pip.
	_button_variant(t, _on(BUTTON), _radius(pip_on, RADIUS_CARD), _radius(pip_on_hover, RADIUS_CARD),
		_radius(press, RADIUS_CARD), _radius(off, RADIUS_CARD), ON_ACCENT, FONT_BODY)
	# End Battle: a ghost button in danger ink with a danger rim, filling red under the pointer.
	_button_variant(t, DANGER_BUTTON, _box(FILL, _alpha(DANGER, 0.55), RADIUS_CARD, PAD_BUTTON_X, 0),
		_box(_alpha(DANGER, HOVER_ALPHA), DANGER, RADIUS_CARD, PAD_BUTTON_X, 0),
		_box(_alpha(DANGER, PRESS_ALPHA), DANGER, RADIUS_CARD, PAD_BUTTON_X, 0), _radius(off, RADIUS_CARD),
		tone_ink(TONE_DANGER), FONT_BODY)

	# Tool rail: quiet buttons until hovered, the open tool in gold (mockup .rail-btn / .active).
	var none := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), RADIUS_CARD, 2, PAD_RAIL)
	var rail_hover := _box(FILL_RAISED, Color(0, 0, 0, 0), RADIUS_CARD, 2, PAD_RAIL)
	var rail_press := _box(_alpha(ACCENT, HOVER_ALPHA), Color(0, 0, 0, 0), RADIUS_CARD, 2, PAD_RAIL)
	_button_variant(t, RAIL, none, rail_hover, rail_press, none, MUTED, FONT_RAIL)
	t.set_color(&"font_hover_color", RAIL, INK)
	var rail_on := _box(_alpha(GOLD, 0.10), _alpha(GOLD, 0.5), RADIUS_CARD, 2, PAD_RAIL)
	var rail_on_hover := _box(_alpha(GOLD, 0.16), _alpha(GOLD, 0.7), RADIUS_CARD, 2, PAD_RAIL)
	_button_variant(t, _on(RAIL), rail_on, rail_on_hover, rail_on_hover, rail_on, GOLD, FONT_RAIL)
	for v: StringName in [RAIL, _on(RAIL)]:
		var ink: Color = t.get_color(&"font_color", v)
		for c: StringName in [&"icon_normal_color", &"icon_pressed_color", &"icon_focus_color", &"icon_hover_pressed_color"]:
			t.set_color(c, v, ink)
		t.set_color(&"icon_hover_color", v, t.get_color(&"font_hover_color", v))
		t.set_constant(&"icon_max_width", v, RAIL_ICON)
		t.set_constant(&"h_separation", v, 2)
	t.set_type_variation(RAIL_PANEL, &"PanelContainer")
	t.set_stylebox(&"panel", RAIL_PANEL, _box(PANEL, LINE_SOFT, RADIUS_PANEL, PAD_RAIL, PAD_RAIL))

	# Keys: a static cap for hints, a clickable cap that presses its key (hover rim in accent).
	var cap := _box(KEYCAP_FILL, LINE, RADIUS_KEYCAP, 6, 1)
	_label_variant(t, KEYCAP, INK, FONT_SMALL)
	t.set_stylebox(&"normal", KEYCAP, cap)
	# A cap you can click wears a faint accent rim at rest, so it reads apart from a hint cap.
	var key_rest := _box(KEYCAP_FILL, _alpha(ACCENT, 0.45), RADIUS_KEYCAP, 6, 1)
	_button_variant(t, KEY, key_rest, _box(_alpha(ACCENT, HOVER_ALPHA + 0.04), ACCENT, RADIUS_KEYCAP, 6, 1),
		_box(_alpha(ACCENT, PRESS_ALPHA), ACCENT, RADIUS_KEYCAP, 6, 1), key_rest, INK, FONT_SMALL)
	t.set_type_variation(TOOL_LINE, &"PanelContainer")
	t.set_stylebox(&"panel", TOOL_LINE, _box(FILL, LINE, RADIUS_CARD, 12, 4))
	t.set_type_variation(SHEET, &"PanelContainer")
	t.set_stylebox(&"panel", SHEET, _box(SHEET_FILL, LINE_SOFT, RADIUS_SHEET, PAD_SHEET, PAD_SHEET))

	# Top bar: no strip behind the items — each carries the window's dark fill itself, so the table
	# shows between them and the bar covers no more of it than the items it replaced.
	var bar_rest := _box(PANEL, LINE, RADIUS_CARD, PAD_CHIP_X, 0)
	var bar_hover := _box(PANEL.blend(_alpha(ACCENT, HOVER_ALPHA)), ACCENT, RADIUS_CARD, PAD_CHIP_X, 0)
	var bar_press := _box(PANEL.blend(_alpha(ACCENT, PRESS_ALPHA)), ACCENT, RADIUS_CARD, PAD_CHIP_X, 0)
	_button_variant(t, BAR_BUTTON, bar_rest, bar_hover, bar_press, bar_rest, INK, FONT_BODY)
	var bar_on := _box(PANEL.blend(_alpha(ACCENT, SELECTED_ALPHA)), ACCENT, RADIUS_CARD, PAD_CHIP_X, 0)
	_button_variant(t, _on(BAR_BUTTON), bar_on, bar_hover, bar_press, bar_on, ON_ACCENT, FONT_BODY)
	_button_variant(t, BAR_PRIMARY, _pad_x(primary[0], PAD_BAR_PRIMARY_X), _pad_x(primary[1], PAD_BAR_PRIMARY_X),
		_pad_x(primary[2], PAD_BAR_PRIMARY_X), _pad_x(primary[3], PAD_BAR_PRIMARY_X), ON_GOLD, FONT_ACTION)
	t.set_color(&"font_disabled_color", BAR_PRIMARY, _alpha(ON_GOLD, 0.7))
	for v: StringName in [CHIP, CHIP_ROUND, CHIP_TURN, CHIP_ENEMY]:
		var tint: Color = {CHIP: LINE, CHIP_ROUND: GOLD, CHIP_TURN: ACCENT, CHIP_ENEMY: DANGER}[v]
		t.set_type_variation(v, &"PanelContainer")
		t.set_stylebox(&"panel", v, _box(PANEL.blend(_alpha(tint, 0.10 if v != CHIP else 0.0)),
			tint if v == CHIP else _alpha(tint, 0.55), RADIUS_CARD, PAD_CHIP_X, 0))

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
## pressing on_step(delta). Buttons are named "<name_prefix><delta>" ("Modifier+1"). `sign_only`
## labels a single-step stepper "−" / "+" so the steps never read like the value between them.
static func stepper(deltas: Array, middle: Control, on_step: Callable, name_prefix: String = "Step",
		sign_only: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", GAP_CONTROL)
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var placed_middle := false
	for d: Variant in deltas:
		var delta := int(d)
		if delta > 0 and not placed_middle:
			row.add_child(middle)
			placed_middle = true
		var b := button(step_text(delta, sign_only), BUTTON, H_PIP)
		b.name = "%s%+d" % [name_prefix, delta]
		b.pressed.connect(on_step.bind(delta))
		row.add_child(b)
	if not placed_middle:
		row.add_child(middle)
	return row


## "−10" / "+5" (or just "−" / "+" with `sign_only`): a step label with the typographic minus.
static func step_text(delta: int, sign_only: bool = false) -> String:
	if sign_only:
		return "+" if delta > 0 else GLYPH_MINUS
	return ("+%d" % delta) if delta > 0 else (GLYPH_MINUS + str(absi(delta)))


## A sunken card (counter, result, log) holding `child`.
static func card(child: Control = null) -> PanelContainer:
	var c := PanelContainer.new()
	c.theme_type_variation = CARD
	if child != null:
		c.add_child(child)
	return c


## The window header: eyebrow title left, its control right — a collapse control ("CollapseButton")
## or, for a window that lives in the tool rail or over the table, a close control ("CloseButton", ×).
static func panel_header(title: String, closes: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Header"
	row.add_theme_constant_override(&"separation", GAP_ROW)
	var t := label(title.to_upper(), EYEBROW)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	var b := button(GLYPH_CLOSE if closes else GLYPH_COLLAPSE, ICON, ICON_BUTTON)
	b.name = "CloseButton" if closes else "CollapseButton"
	b.tooltip_text = "Close" if closes else "Collapse"
	b.custom_minimum_size = Vector2(ICON_BUTTON, ICON_BUTTON)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(b)
	return row


## A key of a shortcut hint ("Shift", "G") — a label, not a button.
static func key_cap(text: String) -> Label:
	var l := label(text, KEYCAP)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## A key cap you can click: pressing it does what pressing that key does (the caller wires it).
static func key_button(text: String, tooltip: String) -> Button:
	var b := button(text, KEY, H_KEYCAP)
	b.tooltip_text = tooltip
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## A tool line (mockup .tool-line): the action's name left, then its keys — key_cap hints and / or
## key_button actions — right. The line itself is a frame, not a button.
static func tool_line(text: String, keys: Array) -> PanelContainer:
	var line := PanelContainer.new()
	line.theme_type_variation = TOOL_LINE
	line.custom_minimum_size = Vector2(0, H_ACTION)
	line.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", GAP_CONTROL)
	var l := label(text, BODY)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	for k: Variant in keys:
		row.add_child(k as Control)
	line.add_child(row)
	return line


## An action line: a full-width ghost button, its name left and an optional hint glyph right
## (GLYPH_GO for "opens something"). A switch line shows its state with set_selected.
static func action_line(text: String, trailing: String = "") -> Button:
	var b := button(text, BUTTON, H_ACTION)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_constant_override(&"h_separation", GAP_ROW)
	if trailing != "":
		var t := label(trailing, HIT)
		t.name = "Trailing"
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t.offset_right = -PAD_CARD_X - 2
		b.add_child(t)
	return b


## A tool-rail button: its icon above a small label; the open tool is set_selected (gold).
static func rail_button(text: String, icon: Texture2D) -> Button:
	var b := button(text, RAIL, H_RAIL)
	b.icon = icon
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.custom_minimum_size = Vector2(W_RAIL, H_RAIL)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b


## A top-bar state chip (mockup .chip): spaced capitals in the variant's tint, a side dot for a turn.
## It paints, so it owns its pixels (STOP).
static func chip(text: String, variant: StringName = CHIP) -> PanelContainer:
	var c := PanelContainer.new()
	c.custom_minimum_size = Vector2(0, H_BAR)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override(&"separation", GAP_ROW - 2)
	c.add_child(row)
	var dot := Panel.new()
	dot.name = "Dot"
	dot.custom_minimum_size = Vector2(DOT, DOT)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dot)
	var l := label(text, EYEBROW)
	l.name = "Text"
	row.add_child(l)
	set_chip(c, text, variant)
	return c


## Sets a chip's text and tint (the turn chip turns from yours to the opponent's).
static func set_chip(c: PanelContainer, text: String, variant: StringName) -> void:
	c.theme_type_variation = variant
	var l := c.get_node("Row/Text") as Label
	l.text = text
	l.add_theme_color_override(&"font_color", CHIP_INK[variant])
	var dot := c.get_node("Row/Dot") as Panel
	dot.visible = (CHIP_DOT[variant] as Color).a > 0.0
	if dot.visible:
		var s := _box(CHIP_DOT[variant], CHIP_DOT[variant], int(DOT * 0.5), 0, 0)
		s.set_border_width_all(0)
		dot.add_theme_stylebox_override(&"panel", s)


## The colour of a pill / link tone.
static func tone_color(tone: StringName) -> Color:
	match tone:
		TONE_GOLD:
			return GOLD
		TONE_WARN:
			return WARN
		TONE_MUTED:
			return MUTED
		TONE_OK:
			return OK
		TONE_DANGER:
			return DANGER
		_:
			return ACCENT


## A tone as text on a panel: its colour, the danger red lifted so it stays readable at 14 px.
static func tone_ink(tone: StringName) -> Color:
	return DANGER.lightened(DANGER_INK_LIFT) if tone == TONE_DANGER else tone_color(tone)


## A status pill's box (mockup .pill): lit = the tone (gold solid, the others a tint), unlit = a ghost;
## hovered = the tone's rim.
static func pill_box(tone: StringName, lit: bool, hovered: bool = false) -> StyleBoxFlat:
	var c := tone_color(tone)
	var fill := FILL
	var rim := LINE
	if lit:
		fill = c if tone == TONE_GOLD else _alpha(c, SELECTED_ALPHA)
		rim = c
		if hovered:
			fill = c.lightened(GOLD_HOVER_LIGHTEN) if tone == TONE_GOLD else _alpha(c, SELECTED_ALPHA + HOVER_ALPHA)
	elif hovered:
		fill = _alpha(c, HOVER_ALPHA)
		rim = c
	return _box(fill, rim, RADIUS_PILL, PAD_PILL_X, 3)


## A pill's text colour: dark on gold, the tone on a tint, muted when off.
static func pill_ink(tone: StringName, lit: bool) -> Color:
	if not lit:
		return MUTED
	return ON_GOLD if tone == TONE_GOLD else tone_color(tone)


## A rule / spell link's box (mockup .rule-link): no fill, a soft underline rule in the tone.
static func link_box(tone: StringName, hovered: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_width_bottom = BORDER
	s.border_color = tone_color(tone) if hovered else _alpha(tone_color(tone), 0.45)
	s.content_margin_bottom = 1
	return s


## A hover tooltip's box (rule descriptions): the sheet fill with the window rim.
static func tooltip_box() -> StyleBoxFlat:
	return _box(SHEET_FILL, LINE_SOFT, RADIUS_CARD, PAD_CARD_X, PAD_CARD_Y)


## A warning strip's box (coherency): a warn tint with a warn rim.
static func warning_box() -> StyleBoxFlat:
	return _box(_alpha(WARN, 0.12), _alpha(WARN, 0.55), RADIUS_CARD, PAD_CARD_X, PAD_CARD_Y)


## Dresses a button that must keep its own font (the ☰ menu button: Inter has no ☰) in a variant's
## boxes, without the variant's side padding.
static func borrow_look(b: Button, variant: StringName) -> void:
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]:
		b.add_theme_stylebox_override(state, _pad_x(theme().get_stylebox(state, variant), 0))


## A crisp, state-tinted icon from an inline SVG (white strokes on transparent, 48 x 48 view box);
## drawn at RAIL_ICON, rendered at twice that so it stays sharp at 2560 x 1440.
static func svg_icon(svg: String) -> ImageTexture:
	var img := Image.new()
	img.load_svg_from_string(svg, RAIL_ICON * 2 / 48.0)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A modal sheet over a dimmed screen (mockup .overlay / .sheet): {"root": the full-screen holder,
## "sheet": the centred PanelContainer, "body": its content VBox, "close": the × button}.
static func overlay_sheet(title: String, width: int) -> Dictionary:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = theme()
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(scrim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centre)
	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.theme_type_variation = SHEET
	sheet.custom_minimum_size = Vector2(width, 0)
	centre.add_child(sheet)
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", GAP_SECTION)
	sheet.add_child(body)
	var header := panel_header(title, true)
	body.add_child(header)
	return {"root": root, "sheet": sheet, "body": body, "close": header.get_node("CloseButton")}


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
		BAR_BUTTON, BAR_PRIMARY:
			return H_BAR
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


static func _pad_x(s: StyleBox, pad_x: int) -> StyleBox:
	var copy := s.duplicate() as StyleBox
	copy.content_margin_left = pad_x
	copy.content_margin_right = pad_x
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
