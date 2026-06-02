class_name UiPolish
extends RefCounted
## Shared UI polish tokens + helpers, distilled from the already-polished reference
## screens (startup menu, table-size dialog, radial menu) so the rest of the UI can
## match them consistently. Colours follow the "Dark Glassmorphism" design system
## (docs/UI_MODERNIZATION_PLAN.md). Pure/static -> trivially testable, no scene deps.

# ===== Design tokens =====
const ACCENT := Color(0.0, 0.85, 1.0)        # cyan: active / primary / "loading"
const DESTRUCTIVE := Color(1.0, 0.35, 0.43)  # red: destructive / error
const SUCCESS := Color(0.30, 0.85, 0.55)     # green: success / confirmation
const WARNING := Color(1.0, 0.75, 0.30)      # amber: warning / empty
const TEXT_MUTED := Color(0.55, 0.58, 0.66)  # dimmed secondary / hint text

const DIALOG_MARGIN := 18  # outer content margin of a dialog (px)
const SECTION_SEP := 10    # vertical separation between sections (px)
const BUTTON_HEIGHT := 42  # comfortable primary-button / hit-target height (px)


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


## A subtle "sunken glass" panel style for read-only / preview surfaces, so they
## read against the light-glass theme while staying on-style.
static func sunken_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.0, 0.0, 0.0, 0.25)
	s.border_color = Color(1.0, 1.0, 1.0, 0.10)
	s.set_border_width_all(1)
	s.set_corner_radius_all(12)
	s.set_content_margin_all(10)
	return s
