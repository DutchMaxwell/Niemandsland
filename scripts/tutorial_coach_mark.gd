class_name TutorialCoachMark
extends CanvasLayer
## Full-screen coach-mark overlay for the guided tutorial (T0): dims the screen, cuts a
## rectangular "spotlight" hole around ONE target (a UI Control rect or a screen-projected
## 3D position), shows one imperative instruction, and pulses the spotlight border to draw
## the eye. A Skip button is ALWAYS visible so the player can leave the tutorial cleanly at
## any point — never a modal trap. Clicks land normally inside the spotlight hole (soft input
## mask: everything OUTSIDE the hole is absorbed via `_has_point`, the hole falls through to
## the game). Purely code-drawn (bands + ring in `_draw`, HudTokens palette) — no art assets.

# ===== Constants =====
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.60)   # soft screen dim outside the spotlight
const SPOTLIGHT_PAD := 14.0                      # breathing room added around the target rect
const RING_WIDTH := 3.0
const PULSE_PERIOD := 1.4                        # seconds per pulse cycle
const CARD_GAP := 18.0                           # gap between spotlight and instruction card
const CARD_MARGIN := 18.0                        # min distance of the card from screen edges
const CARD_MAX_WIDTH := 340.0
const OVERLAY_LAYER := 128                       # above the HUD CanvasLayer

# ===== Signals =====
signal skip_pressed()

# ===== Private state =====
var _target_rect: Rect2 = Rect2()
var _has_target: bool = false
var _pulse_phase: float = 0.0
var _dim: Control = null
var _card: PanelContainer = null
var _label: Label = null
var _skip_btn: Button = null


# ===== Lifecycle =====

func _ready() -> void:
	layer = OVERLAY_LAYER
	_build()
	set_process(true)


func _process(delta: float) -> void:
	# Cheap per-frame work only: advance the pulse phase, ask the dim layer to redraw,
	# and keep the card glued to the (possibly moving) spotlight. No allocations.
	_pulse_phase = fmod(_pulse_phase + delta, PULSE_PERIOD)
	if _dim != null:
		_dim.queue_redraw()
	_reposition_card()


# ===== Public API =====

## Point the spotlight at a screen rectangle and set the one-line instruction.
func show_step(instruction: String, target_rect: Rect2) -> void:
	if _label != null:
		_label.text = instruction
	set_target_rect(target_rect)
	visible = true


## Update just the spotlight rect — called every frame for a moving 3D target.
func set_target_rect(target_rect: Rect2) -> void:
	_target_rect = target_rect.grow(SPOTLIGHT_PAD)
	_has_target = true


## Hide the whole overlay (tutorial ended / skipped).
func hide_overlay() -> void:
	visible = false
	set_process(false)


# ===== Construction =====

func _build() -> void:
	_dim = _DimLayer.new()
	_dim.owner_overlay = self
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP  # absorbs clicks OUTSIDE the hole (see _has_point)
	add_child(_dim)

	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE  # text never blocks input
	_card.add_theme_stylebox_override("panel", HudTokens.panel_style())
	_card.custom_minimum_size = Vector2(0, 0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", HudTokens.SPACE_16)
	margin.add_theme_constant_override("margin_right", HudTokens.SPACE_16)
	margin.add_theme_constant_override("margin_top", HudTokens.SPACE_12)
	margin.add_theme_constant_override("margin_bottom", HudTokens.SPACE_12)
	_card.add_child(margin)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(CARD_MAX_WIDTH, 0)
	_label.add_theme_font_override("font", HudTokens.body_font())
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", HudTokens.TEXT)
	margin.add_child(_label)
	add_child(_card)

	_skip_btn = Button.new()
	_skip_btn.text = "Skip tutorial"
	_skip_btn.focus_mode = Control.FOCUS_NONE
	_skip_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var ghost := HudTokens.ghost_button()
	_skip_btn.add_theme_stylebox_override("normal", ghost["normal"])
	_skip_btn.add_theme_stylebox_override("hover", ghost["hover"])
	_skip_btn.add_theme_stylebox_override("pressed", ghost["pressed"])
	_skip_btn.add_theme_color_override("font_color", HudTokens.TEXT)
	_skip_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_skip_btn.offset_left = -160.0
	_skip_btn.offset_right = -CARD_MARGIN
	_skip_btn.offset_top = CARD_MARGIN
	_skip_btn.offset_bottom = CARD_MARGIN + HudTokens.BUTTON_HEIGHT
	_skip_btn.pressed.connect(func() -> void: skip_pressed.emit())
	add_child(_skip_btn)


## Keep the instruction card just below the spotlight (or above it when there is no room
## below), horizontally centred on the spotlight and clamped inside the screen.
func _reposition_card() -> void:
	if _card == null:
		return
	var vp := _card.get_viewport_rect().size
	var card_size := _card.size
	if not _has_target:
		_card.position = ((vp - card_size) * 0.5)
		return
	var below_y := _target_rect.end.y + CARD_GAP
	var above_y := _target_rect.position.y - CARD_GAP - card_size.y
	var y: float = below_y
	if below_y + card_size.y > vp.y - CARD_MARGIN:
		y = maxf(above_y, CARD_MARGIN)
	var cx := _target_rect.get_center().x
	var x := clampf(cx - card_size.x * 0.5, CARD_MARGIN, maxf(CARD_MARGIN, vp.x - card_size.x - CARD_MARGIN))
	_card.position = Vector2(x, y)


# ===== Dim layer (inner class) =====

## The dimming layer: draws four dark bands framing the spotlight hole plus a pulsing
## accent ring, and — crucially — reports "not under the mouse" INSIDE the hole so clicks
## there fall through to the game while clicks outside are absorbed (soft input mask).
class _DimLayer extends Control:
	var owner_overlay: TutorialCoachMark = null

	func _has_point(point: Vector2) -> bool:
		if owner_overlay == null or not owner_overlay._has_target:
			return true
		return not owner_overlay._target_rect.has_point(point)

	func _draw() -> void:
		if owner_overlay == null:
			return
		if not owner_overlay._has_target:
			draw_rect(Rect2(Vector2.ZERO, size), DIM_COLOR)
			return
		var r: Rect2 = owner_overlay._target_rect
		# Four dim bands around the clear hole.
		draw_rect(Rect2(0.0, 0.0, size.x, r.position.y), DIM_COLOR)                       # top
		draw_rect(Rect2(0.0, r.end.y, size.x, size.y - r.end.y), DIM_COLOR)               # bottom
		draw_rect(Rect2(0.0, r.position.y, r.position.x, r.size.y), DIM_COLOR)            # left
		draw_rect(Rect2(r.end.x, r.position.y, size.x - r.end.x, r.size.y), DIM_COLOR)    # right
		# Pulsing accent ring (cyan primary, breathes 0..1 over the period).
		var t := 0.5 - 0.5 * cos(TAU * owner_overlay._pulse_phase / PULSE_PERIOD)
		var glow := HudTokens.CYAN
		glow.a = 0.55 + 0.45 * t
		var ring := r.grow(2.0 + 4.0 * t)
		draw_rect(ring, glow, false, RING_WIDTH)
