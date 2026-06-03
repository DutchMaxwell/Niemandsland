class_name HudTokens
extends RefCounted
## Design tokens for the "Tactical HUD" UI language — sleek, cyan primary + amber
## secondary. Everything is code-drawn (StyleBoxFlat + thin accent lines) so it is
## sharp at any resolution and needs no art assets. Reused by the HUD components
## and the per-screen restyle. Keep this the single source of truth.

# ===== Palette =====
const CYAN := Color(0.0, 0.85, 1.0)        # primary: structure, focus, primary action
const AMBER := Color(1.0, 0.64, 0.16)      # secondary: active/selected, warning, key values
const DANGER := Color(1.0, 0.33, 0.38)     # destructive

const SURFACE := Color(0.043, 0.058, 0.098, 0.98)  # panel fill (deep navy glass, not gray)
const RAISED := Color(1.0, 1.0, 1.0, 0.05)          # header strip lift
const HAIRLINE := Color(1.0, 1.0, 1.0, 0.10)        # subtle border / divider
const SUNKEN := Color(0.0, 0.0, 0.0, 0.32)          # input / preview wells
const TEXT := Color(0.92, 0.95, 0.98)
const TEXT_MUTED := Color(0.56, 0.61, 0.69)

# Status colours. Always pair with an icon/shape/label — never carry meaning by hue
# alone (CVD-safe, WCAG 1.4.1). Used by dialogs, coherency and dice readouts.
const SUCCESS := Color(0.30, 0.85, 0.55)   # confirmation / pass
const WARNING := Color(1.0, 0.75, 0.30)    # warning / empty (distinct from AMBER accent)

# ===== Geometry =====
const RADIUS := 4          # sleek: a touch of rounding (near-sharp)
const PAD := 16
const HEADER_H := 34
const ACCENT_LINE := 2
const BUTTON_H := 40

# Spacing scale (8pt grid + 4pt half-step). Use these for every separation /
# margin / content-margin instead of raw pixel literals.
const SPACE_4 := 4
const SPACE_8 := 8
const SPACE_12 := 12
const SPACE_16 := 16
const SPACE_24 := 24

# Dialog / hit-target tokens (shared by all dialogs via UiPolish helpers).
const DIALOG_MARGIN := 18    # outer content margin of a dialog
const SECTION_SEP := 10      # vertical gap between dialog sections
const BUTTON_HEIGHT := 42    # comfortable interactive height (>= ~44px hit target)

# ===== Motion =====
# Centralised so every animation references the same timing/scale and honours the
# Reduce-Motion toggle. Durations in seconds. (Material 3 easing/duration specs.)
const DUR_HOVER := 0.10
const DUR_PRESS := 0.06
const DUR_PANEL_IN := 0.22
const DUR_PANEL_OUT := 0.18
const DUR_SCREEN := 0.35
const SCALE_HOVER := 1.02
const SCALE_PRESS := 0.97
const SCALE_PUNCH := 1.06

# ===== Type =====
const FONT_DIR := "res://assets/ui_glassmorphism/fonts/"

static func head_font() -> FontFile:
	return load(FONT_DIR + "Orbitron.ttf")

static func body_font() -> FontFile:
	return load(FONT_DIR + "Inter.ttf")

static func mono_font() -> FontFile:
	return load(FONT_DIR + "SourceCodePro.ttf")

## Real bold via the Inter weight axis — avoids faux-bold (which doubles/frays at small
## sizes). Use as the RichTextLabel "bold_font" so every [b] renders crisp.
static func bold_font() -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = body_font()
	fv.variation_opentype = {"wght": 700}
	return fv


# ===== StyleBoxes =====

## Dark-glass panel with a hairline border and a soft drop shadow.
static func panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SURFACE
	s.set_corner_radius_all(RADIUS)
	s.set_border_width_all(1)
	s.border_color = HAIRLINE
	s.shadow_size = 16
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_offset = Vector2(0, 4)
	return s


## Sunken well for inputs / preview areas.
static func sunken_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SUNKEN
	s.set_corner_radius_all(RADIUS)
	s.set_border_width_all(1)
	s.border_color = HAIRLINE
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


## A flat button stylebox at the given fill/border (used for primary/ghost/danger).
static func button_style(fill: Color, border: Color, border_w: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(RADIUS)
	s.set_border_width_all(border_w)
	s.border_color = border
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


## Primary (cyan), ghost (hairline) and danger (amber/red) button state sets.
## Returns {"normal","hover","pressed"} stylebox dictionaries.
static func primary_button() -> Dictionary:
	return {
		"normal": button_style(Color(CYAN.r, CYAN.g, CYAN.b, 0.16), Color(CYAN.r, CYAN.g, CYAN.b, 0.85)),
		"hover": button_style(Color(CYAN.r, CYAN.g, CYAN.b, 0.28), CYAN),
		"pressed": button_style(Color(CYAN.r, CYAN.g, CYAN.b, 0.40), CYAN),
	}

static func ghost_button() -> Dictionary:
	return {
		"normal": button_style(Color(1, 1, 1, 0.03), HAIRLINE),
		"hover": button_style(Color(1, 1, 1, 0.08), Color(CYAN.r, CYAN.g, CYAN.b, 0.55)),
		"pressed": button_style(Color(CYAN.r, CYAN.g, CYAN.b, 0.18), CYAN),
	}

static func amber_button() -> Dictionary:
	return {
		"normal": button_style(Color(AMBER.r, AMBER.g, AMBER.b, 0.14), Color(AMBER.r, AMBER.g, AMBER.b, 0.8)),
		"hover": button_style(Color(AMBER.r, AMBER.g, AMBER.b, 0.26), AMBER),
		"pressed": button_style(Color(AMBER.r, AMBER.g, AMBER.b, 0.4), AMBER),
	}


# ===== Chrome =====

## A section header: Orbitron title (+ optional amber mono index) over an accent
## line (amber tick -> cyan rule). The signature chrome of the tactical HUD; drop it
## at the top of any panel/dialog content.
static func header(title: String, index: String = "") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)

	var row := HBoxContainer.new()
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", head_font())
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", TEXT)
	row.add_child(t)
	if index != "":
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sp)
		var idx := Label.new()
		idx.text = index
		idx.add_theme_font_override("font", mono_font())
		idx.add_theme_font_size_override("font_size", 12)
		idx.add_theme_color_override("font_color", AMBER)
		idx.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(idx)
	v.add_child(row)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 0)
	var amber := ColorRect.new()
	amber.color = AMBER
	amber.custom_minimum_size = Vector2(24, ACCENT_LINE)
	var cyan := ColorRect.new()
	cyan.color = Color(CYAN.r, CYAN.g, CYAN.b, 0.85)
	cyan.custom_minimum_size = Vector2(0, ACCENT_LINE)
	cyan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(amber)
	line.add_child(cyan)
	v.add_child(line)
	return v
