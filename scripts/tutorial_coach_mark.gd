class_name TutorialCoachMark
extends CanvasLayer
## Full-screen coach-mark overlay for the guided tutorial: dims the screen, cuts a
## rectangular "spotlight" hole around ONE target (a UI Control rect or a screen-projected
## 3D box), shows one imperative instruction plus a small lesson/step progress line, and
## pulses the spotlight border. Two escape hatches are ALWAYS visible — SKIP LESSON and
## END TUTORIAL — so the player is never trapped.
##
## Input handling ("soft mask"): when a step requests masking, everything OUTSIDE the
## spotlight hole absorbs GUI clicks via `_has_point` while the hole falls through to the
## game. Steps that need free 3D interaction (drags, camera) run unmasked (dim ignores the
## mouse) or in BANNER mode (no dim at all — instruction card only), so a gesture can never
## be cut off by the overlay. Purely code-drawn (HudTokens palette) — no art assets.

# ===== Constants =====
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.60)   # soft screen dim outside the spotlight
const SPOTLIGHT_PAD := 14.0                      # breathing room added around the target rect
const RING_WIDTH := 3.0
const PULSE_PERIOD := 1.4                        # seconds per pulse cycle
const CARD_GAP := 18.0                           # gap between spotlight and instruction card
const CARD_MARGIN := 18.0                        # min distance of the card from screen edges
const CARD_MAX_WIDTH := 360.0
const BANNER_TOP_Y := 64.0                       # banner-mode card y (below the battle-log tab)
const OVERLAY_LAYER := 128                       # above the HUD CanvasLayer
const BUTTON_W := 150.0

# ===== Signals =====
signal skip_lesson_pressed()
signal end_pressed()
## Concept-card acknowledgement ("GOT IT") — only shown for steps with no on-board action
## to detect (e.g. the R2 regiments card on a Grimdark Future board). Action steps never
## show this button; they advance on real gameplay signals.
signal continue_pressed()

# ===== Private state =====
var _target_rect: Rect2 = Rect2()
var _has_target: bool = false
var _pulse_phase: float = 0.0
var _dim: Control = null
var _card: PanelContainer = null
var _progress_label: Label = null
var _label: Label = null
var _skip_lesson_btn: Button = null
var _end_btn: Button = null
var _continue_btn: Button = null


# ===== Lifecycle =====

func _ready() -> void:
	layer = OVERLAY_LAYER
	_build()
	set_process(true)


func _process(delta: float) -> void:
	# Cheap per-frame work only: advance the pulse phase, ask the dim layer to redraw,
	# and keep the card glued to the (possibly moving) spotlight. No allocations.
	_pulse_phase = fmod(_pulse_phase + delta, PULSE_PERIOD)
	if _dim != null and _dim.visible:
		_dim.queue_redraw()
	_reposition_card()


# ===== Public API =====

## Spotlight mode: point at a screen rectangle, set the instruction, choose whether
## input outside the spotlight is soft-masked (never mask steps that involve drags).
func show_step(instruction: String, target_rect: Rect2, mask: bool = true) -> void:
	if _label != null:
		_label.text = instruction
	set_target_rect(target_rect)
	if _dim != null:
		_dim.visible = true
		_dim.mouse_filter = Control.MOUSE_FILTER_STOP if mask else Control.MOUSE_FILTER_IGNORE
	visible = true


## Banner mode: instruction card only — no dim, no spotlight, no input interference.
## For steps where the whole table is the stage (camera lesson, free-form steps).
func show_banner(instruction: String) -> void:
	if _label != null:
		_label.text = instruction
	_has_target = false
	if _dim != null:
		_dim.visible = false
		_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = true


## The small "LESSON 2/6 · IMPORTING ARMIES — STEP 1/3" line above the instruction.
func set_progress_text(text: String) -> void:
	if _progress_label != null:
		_progress_label.text = text
		_progress_label.visible = not text.is_empty()


## Update just the spotlight rect — called every frame for a moving 3D target.
func set_target_rect(target_rect: Rect2) -> void:
	_target_rect = target_rect.grow(SPOTLIGHT_PAD)
	_has_target = true


## Show or hide the "GOT IT" concept-card acknowledgement button. Set true only for steps
## that have no on-board action to detect; action steps keep it hidden and advance on real
## gameplay signals (never a generic Next button).
func set_continue_visible(show_continue: bool) -> void:
	if _continue_btn != null:
		_continue_btn.visible = show_continue


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
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", HudTokens.SPACE_16)
	margin.add_theme_constant_override("margin_right", HudTokens.SPACE_16)
	margin.add_theme_constant_override("margin_top", HudTokens.SPACE_12)
	margin.add_theme_constant_override("margin_bottom", HudTokens.SPACE_12)
	_card.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", HudTokens.SPACE_4)
	margin.add_child(vbox)
	_progress_label = Label.new()
	_progress_label.add_theme_font_override("font", HudTokens.mono_font())
	_progress_label.add_theme_font_size_override("font_size", 12)
	_progress_label.add_theme_color_override("font_color", HudTokens.AMBER)
	_progress_label.visible = false
	vbox.add_child(_progress_label)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(CARD_MAX_WIDTH, 0)
	_label.add_theme_font_override("font", HudTokens.body_font())
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", HudTokens.TEXT)
	vbox.add_child(_label)
	add_child(_card)

	# Escape hatches, top-right, stacked: SKIP LESSON above END TUTORIAL.
	_skip_lesson_btn = _build_button("SKIP LESSON", CARD_MARGIN)
	_skip_lesson_btn.pressed.connect(func() -> void: skip_lesson_pressed.emit())
	add_child(_skip_lesson_btn)
	_end_btn = _build_button("END TUTORIAL", CARD_MARGIN + HudTokens.BUTTON_HEIGHT + HudTokens.SPACE_8)
	_end_btn.pressed.connect(func() -> void: end_pressed.emit())
	add_child(_end_btn)

	# Concept-card acknowledgement, bottom-centre, hidden until a step requests it.
	_continue_btn = Button.new()
	_continue_btn.text = "GOT IT"
	_continue_btn.focus_mode = Control.FOCUS_NONE
	_continue_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var amber := HudTokens.amber_button()
	_continue_btn.add_theme_stylebox_override("normal", amber["normal"])
	_continue_btn.add_theme_stylebox_override("hover", amber["hover"])
	_continue_btn.add_theme_stylebox_override("pressed", amber["pressed"])
	_continue_btn.add_theme_color_override("font_color", HudTokens.TEXT)
	_continue_btn.add_theme_font_size_override("font_size", 14)
	_continue_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_continue_btn.offset_left = -BUTTON_W * 0.5
	_continue_btn.offset_right = BUTTON_W * 0.5
	_continue_btn.offset_top = -(HudTokens.BUTTON_HEIGHT + CARD_MARGIN)
	_continue_btn.offset_bottom = -CARD_MARGIN
	_continue_btn.visible = false
	_continue_btn.pressed.connect(func() -> void: continue_pressed.emit())
	add_child(_continue_btn)


func _build_button(text: String, top: float) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var ghost := HudTokens.ghost_button()
	btn.add_theme_stylebox_override("normal", ghost["normal"])
	btn.add_theme_stylebox_override("hover", ghost["hover"])
	btn.add_theme_stylebox_override("pressed", ghost["pressed"])
	btn.add_theme_color_override("font_color", HudTokens.TEXT)
	btn.add_theme_font_size_override("font_size", 13)
	btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	btn.offset_left = -(BUTTON_W + CARD_MARGIN)
	btn.offset_right = -CARD_MARGIN
	btn.offset_top = top
	btn.offset_bottom = top + HudTokens.BUTTON_HEIGHT
	return btn


## Keep the instruction card just below the spotlight (or above it when there is no
## room below), clamped inside the screen. Banner mode parks it top-centre instead.
func _reposition_card() -> void:
	if _card == null:
		return
	var vp := _card.get_viewport_rect().size
	var card_size := _card.size
	if not _has_target:
		_card.position = Vector2((vp.x - card_size.x) * 0.5, BANNER_TOP_Y)
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
