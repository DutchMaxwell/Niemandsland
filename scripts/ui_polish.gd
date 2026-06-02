class_name UiPolish
extends RefCounted
## Thin compatibility/helper layer over the single source of truth, HudTokens.
## Historically this held its own palette, which DRIFTED from HudTokens (different
## danger/muted/radius) — the classic "per-screen inconsistency" tell. It now simply
## re-exports HudTokens tokens and offers a few dialog helpers, so existing callers
## keep working while every value resolves to one place. Prefer HudTokens directly in
## new code. Pure/static -> trivially testable, no scene deps.

# ===== Tokens (re-exported from HudTokens — do NOT redefine values here) =====
const ACCENT: Color = HudTokens.CYAN          # cyan: active / primary / "loading"
const DESTRUCTIVE: Color = HudTokens.DANGER   # red: destructive / error
const SUCCESS: Color = HudTokens.SUCCESS      # green: success / confirmation
const WARNING: Color = HudTokens.WARNING      # amber: warning / empty
const TEXT_MUTED: Color = HudTokens.TEXT_MUTED  # dimmed secondary / hint text

const DIALOG_MARGIN: int = HudTokens.DIALOG_MARGIN  # outer content margin of a dialog
const SECTION_SEP: int = HudTokens.SECTION_SEP      # vertical separation between sections
const BUTTON_HEIGHT: int = HudTokens.BUTTON_HEIGHT  # comfortable hit-target height


# ===== Helpers =====

## "rrggbb" for a colour, for BBCode (RichTextLabel) [color=#...] tags.
static func hex(c: Color) -> String:
	return c.to_html(false)


## Apply the standard dialog content margins to a MarginContainer.
static func set_dialog_margins(m: MarginContainer, px: int = DIALOG_MARGIN) -> void:
	m.add_theme_constant_override("margin_left", px)
	m.add_theme_constant_override("margin_top", px)
	m.add_theme_constant_override("margin_right", px)
	m.add_theme_constant_override("margin_bottom", px)


## Give a button the standard comfortable height (keeps any existing min width).
static func primary_button(btn: Button) -> void:
	btn.custom_minimum_size = Vector2(btn.custom_minimum_size.x, BUTTON_HEIGHT)


## A subtle "sunken glass" panel style for read-only / preview surfaces — delegates
## to HudTokens so radius/colour match the rest of the tactical theme.
static func sunken_panel_style() -> StyleBoxFlat:
	return HudTokens.sunken_style()


## Reachability: clamp a free-floating Window's size to the visible viewport so it can
## never open larger than (or stranded off) the screen, then centre it. Call from a
## dialog's _ready() and again on the window's size_changed. `target` is the design
## size; it is shrunk to at most (frac_w, frac_h) of the current viewport.
static func clamp_window_to_viewport(win: Window, target: Vector2i,
		frac_w: float = 0.92, frac_h: float = 0.9) -> void:
	if win == null:
		return
	var vp_rect := Vector2(target)
	var parent_vp := win.get_viewport()
	if parent_vp:
		vp_rect = parent_vp.get_visible_rect().size
	elif win.is_inside_tree():
		vp_rect = Vector2(DisplayServer.screen_get_size())
	var w := int(min(float(target.x), vp_rect.x * frac_w))
	var h := int(min(float(target.y), vp_rect.y * frac_h))
	win.size = Vector2i(max(w, 240), max(h, 180))
