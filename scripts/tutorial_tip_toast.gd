class_name TutorialTipToast
extends CanvasLayer
## A lightweight, non-blocking, dismissible contextual-tip toast (T2) in the coach-mark
## visual language: an accent-barred glass panel, bottom-left, with a "TIP" eyebrow, one
## short line of body text and a "GOT IT" dismiss button. Purely code-drawn (HudTokens),
## never modal — only the dismiss button takes clicks; the panel itself and everything
## else fall through to the game. Auto-fades after HOLD_SECONDS if the player ignores it.
##
## TutorialTips owns the once-ever / one-at-a-time / not-during-a-tutorial policy; this
## widget just presents one message and reports when it is gone (button or timeout).

# ===== Constants =====
const OVERLAY_LAYER := 120                       # above the HUD, below the coach mark (128)
const HOLD_SECONDS := 7.0                        # auto-dismiss if the player never clicks
const FADE_SECONDS := 0.5
const MAX_WIDTH := 380.0
const MARGIN := 24.0                             # distance from the bottom-left screen corner
const ACCENT_W := 3.0

# ===== Signals =====
signal dismissed()

# ===== Private state =====
var _root: Control = null
var _panel: PanelContainer = null
var _label: Label = null
var _button: Button = null
var _fade_tween: Tween = null
var _closing: bool = false


# ===== Lifecycle =====

func _ready() -> void:
	layer = OVERLAY_LAYER
	_build()


# ===== Public API =====

## Present one tip. Starts the auto-dismiss timer; the player may also click GOT IT.
func show_tip(text: String) -> void:
	if _label != null:
		_label.text = text
	_arm_auto_dismiss()


## Dismiss now (fade out, then free), emitting `dismissed` exactly once.
func dismiss() -> void:
	if _closing:
		return
	_closing = true
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_SECONDS)
	tw.tween_callback(func() -> void:
		dismissed.emit()
		queue_free())


# ===== Construction =====

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE  # the overlay itself never blocks input
	add_child(_root)

	var accent := PanelContainer.new()
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	accent.add_theme_stylebox_override("panel", HudTokens.panel_style())
	accent.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	accent.offset_left = MARGIN
	accent.offset_bottom = -MARGIN
	accent.grow_horizontal = Control.GROW_DIRECTION_END
	accent.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(accent)
	_panel = accent

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", HudTokens.SPACE_16)
	margin.add_theme_constant_override("margin_right", HudTokens.SPACE_16)
	margin.add_theme_constant_override("margin_top", HudTokens.SPACE_12)
	margin.add_theme_constant_override("margin_bottom", HudTokens.SPACE_12)
	accent.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", HudTokens.SPACE_8)
	margin.add_child(vbox)

	var eyebrow := Label.new()
	eyebrow.text = "TIP"
	eyebrow.add_theme_font_override("font", HudTokens.mono_font())
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", HudTokens.CYAN)
	vbox.add_child(eyebrow)

	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(MAX_WIDTH, 0)
	_label.add_theme_font_override("font", HudTokens.body_font())
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", HudTokens.TEXT)
	vbox.add_child(_label)

	_button = Button.new()
	_button.text = "GOT IT"
	_button.focus_mode = Control.FOCUS_NONE
	_button.mouse_filter = Control.MOUSE_FILTER_STOP  # the ONLY click target in the toast
	_button.custom_minimum_size = Vector2(0, HudTokens.BUTTON_HEIGHT)
	var ghost := HudTokens.ghost_button()
	_button.add_theme_stylebox_override("normal", ghost["normal"])
	_button.add_theme_stylebox_override("hover", ghost["hover"])
	_button.add_theme_stylebox_override("pressed", ghost["pressed"])
	_button.add_theme_color_override("font_color", HudTokens.TEXT)
	_button.add_theme_font_size_override("font_size", 13)
	_button.pressed.connect(dismiss)
	vbox.add_child(_button)


func _arm_auto_dismiss() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_interval(HOLD_SECONDS)
	_fade_tween.tween_callback(dismiss)
