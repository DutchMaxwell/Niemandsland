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
## never open larger than (or stranded off) the screen. `target` is the design size; it
## is shrunk to at most (frac_w, frac_h) of the current viewport.
static func clamp_window_to_viewport(win: Window, target: Vector2i,
		frac_w: float = 0.92, frac_h: float = 0.9) -> void:
	if not is_instance_valid(win):
		return
	win.size = clamped_size(target, _host_rect(win), frac_w, frac_h)


## The area a dialog must fit within = its HOST window, not its own viewport. A Window
## is itself a Viewport, so win.get_viewport() can return the dialog's own (tiny default)
## rect — use the root window's visible rect (logical units, so it respects UI scale).
static func _host_rect(win: Window) -> Vector2:
	var tree := win.get_tree()
	if tree and tree.root:
		return tree.root.get_visible_rect().size
	return Vector2(DisplayServer.screen_get_size())


## Reachability: move keyboard/controller focus to the first focusable descendant so a
## dialog is operable without a mouse. Wire a dialog's visibility_changed to call this
## (deferred) on open. No-op if nothing is focusable.
static func grab_first_focus(root: Node) -> void:
	if not is_instance_valid(root):
		return
	var c := _first_focusable(root)
	if c:
		c.grab_focus()


static func _first_focusable(node: Node) -> Control:
	for child in node.get_children():
		if child is Control:
			var ctrl := child as Control
			if ctrl.visible and ctrl.focus_mode == Control.FOCUS_ALL and not ctrl.is_queued_for_deletion():
				return ctrl
		var deep := _first_focusable(child)
		if deep:
			return deep
	return null


## Pure clamp math (testable): shrink `target` to at most (frac_w, frac_h) of `vp_size`,
## with a small absolute floor so a dialog is never clamped to nothing.
static func clamped_size(target: Vector2i, vp_size: Vector2,
		frac_w: float = 0.92, frac_h: float = 0.9) -> Vector2i:
	var w := int(min(float(target.x), vp_size.x * frac_w))
	var h := int(min(float(target.y), vp_size.y * frac_h))
	return Vector2i(max(w, 240), max(h, 180))


## One-call reachability for a dialog Window: clamp now AND re-clamp whenever the host
## window resizes, so a dialog opened on a wide monitor is never stranded off-edge after
## the window shrinks. Call once from the dialog's _ready(); replaces a fixed `size =`.
static func keep_window_reachable(win: Window, target: Vector2i,
		frac_w: float = 0.92, frac_h: float = 0.9) -> void:
	if not is_instance_valid(win):
		return
	clamp_window_to_viewport(win, target, frac_w, frac_h)
	# Re-clamp when the HOST window resizes (root.size_changed). Setting win.size fires
	# the dialog's own size_changed, not root's, so there is no feedback loop. Disconnect
	# on free so a freed-and-recreated dialog (e.g. TableSizeDialog) never leaks the closure.
	var tree := win.get_tree()
	if tree and tree.root:
		var root := tree.root
		var cb := func() -> void:
			clamp_window_to_viewport(win, target, frac_w, frac_h)
		root.size_changed.connect(cb)
		win.tree_exiting.connect(func() -> void:
			if root.size_changed.is_connected(cb):
				root.size_changed.disconnect(cb))
