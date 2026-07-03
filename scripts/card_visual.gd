class_name CardVisual
extends Control
## Reusable card presentation for the unit dock (Handover D / D1). ONE component for both the dock-strip
## cards and the presented card: a layered face (base > subtle bevel > content) with rounded corners and
## a drop-shadow pass, plus damped-spring dynamics for position / rotation / scale so cards deal into
## place (fan arrangement + overshoot) instead of a linear tween. Hover feedback is a subtle LIFT +
## shadow only — the perspective tilt/sheen/scroll-sway were removed (bus 033: the wobble was too much).
##
## No true 3D, no SubViewport — pure 2D Control + springs. Presentation only: it never changes game
## state. Give it content via set_content_node().

# === Feel tunables (D1: EVERY knob lives here so tuning is trivial) =========================
# Cards are RIGID once dealt in: NO hover lift/scale, NO shadow grow (maintainer: "bewegt sich zu viel").
# The only motion is the deal-in / deal-out spring; selection is a static cyan border (set_selected).
const SHADOW_SPREAD_PX: float = 6.0      # drop-shadow spread
const SHADOW_OFFSET_PX: float = 4.0      # drop-shadow downward offset
const CORNER_RADIUS_PX: int = 10         # rounded corners
const BEVEL_ALPHA: float = 0.16          # subtle top bevel highlight

# Damped-spring constants (D3). stiffness = how hard it pulls to target; damping = 1.0 ≈ critical.
const POS_STIFFNESS: float = 220.0
const POS_DAMPING: float = 0.80          # < 1 overshoots (deal-in wobble); ~1 settles clean
const ROT_STIFFNESS: float = 180.0
const ROT_DAMPING: float = 0.85
const SCALE_STIFFNESS: float = 260.0
const SCALE_DAMPING: float = 0.82
const SETTLE_EPSILON: float = 0.05       # below this (px / deg / %) the spring is "settled" → early-out

# Hand-fan (D4: one constant; maintainer can zero it out). Applied by the dock via set_fan().
const FAN_ENABLED: bool = true
const FAN_DEG_PER_CARD: float = 1.5      # slight arc; must stay scannable

# === State ===
var _shadow: Panel = null
var _face: Panel = null
var _content_holder: Control = null
var _selected: bool = false

# spring state: current + velocity for position (Vector2), rotation (deg), scale (float)
var _target_pos: Vector2 = Vector2.ZERO
var _cur_pos: Vector2 = Vector2.ZERO
var _vel_pos: Vector2 = Vector2.ZERO
var _target_rot: float = 0.0
var _cur_rot: float = 0.0
var _vel_rot: float = 0.0
var _target_scale: float = 1.0
var _cur_scale: float = 1.0
var _vel_scale: float = 0.0
var _fan_rot: float = 0.0                # extra fan rotation from the dock (static arrangement, not hover)

# === Lifecycle ===

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = size * 0.5
	_build_layers()
	set_process(false)   # only run the spring while something is actually moving (D3 early-out)
	resized.connect(_on_resized)


func _build_layers() -> void:
	# Shadow pass (own layer, behind the face) — D1 "drop shadow as its own pass".
	_shadow = Panel.new()
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow.add_theme_stylebox_override("panel", _shadow_style(SHADOW_SPREAD_PX, SHADOW_OFFSET_PX))
	add_child(_shadow)
	# Face (base + bevel), carries the tilt shader.
	_face = Panel.new()
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.add_theme_stylebox_override("panel", _face_style())
	# The face is a plain StyleBox Panel — no shader (hover is a lift + shadow, no tilt; bus 033).
	add_child(_face)
	# Content holder above the face (labels/stats set by the owner).
	_content_holder = Control.new()
	_content_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content_holder)
	_on_resized()


func _on_resized() -> void:
	pivot_offset = size * 0.5
	if _face:
		_face.size = size
	if _content_holder:
		_content_holder.size = size
	_layout_shadow(1.0)


# === Public API ===

## Attach the card's content (labels, stats, status dots). Reparented above the face.
func set_content_node(node: Control) -> void:
	if _content_holder == null:
		return
	for c in _content_holder.get_children():
		c.queue_free()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_holder.add_child(node)
	# Fill the card so the content lays out at the CARD width (not its own min width) — otherwise the
	# header name label is starved of width and ellipsizes even short names (bus 034). Anchors AND
	# offsets so the content tracks the card size exactly.
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Spring the card toward a slot transform (the dock calls this on layout / rebuild / present).
func spring_to(target_position: Vector2, target_rotation_deg: float = 0.0, target_scale: float = 1.0) -> void:
	_target_pos = target_position
	_target_rot = target_rotation_deg
	_target_scale = target_scale
	_wake()


## Snap instantly (no spring) — for the initial build so cards don't fly in from origin.
func snap_to(target_position: Vector2, target_rotation_deg: float = 0.0, target_scale: float = 1.0) -> void:
	_target_pos = target_position
	_cur_pos = target_position
	_vel_pos = Vector2.ZERO
	_target_rot = target_rotation_deg
	_cur_rot = target_rotation_deg
	_vel_rot = 0.0
	_target_scale = target_scale
	_cur_scale = target_scale
	_vel_scale = 0.0
	_apply_transform()


## Selected state (D8): a persistent lift + a cyan Tactical-HUD accent border on the face — the approved
## selection language for the strip (replaces the legacy blue panel frame).
func set_selected(sel: bool) -> void:
	if _selected == sel:
		return
	_selected = sel
	if _face:
		_face.add_theme_stylebox_override("panel", _face_style_selected() if sel else _face_style())
	_wake()


## Fan rotation from the dock (D4): index-based slight arc. No-op when FAN_ENABLED is false.
func set_fan(fan_degrees: float) -> void:
	_fan_rot = fan_degrees if FAN_ENABLED else 0.0
	_wake()


# === Spring integration ===

func _wake() -> void:
	if not is_processing():
		set_process(true)


func _process(delta: float) -> void:
	# ONLY the deal-in / deal-out spring moves the card (position / rotation / scale toward the target).
	# No hover lift, no shadow grow — cards stay rigid once settled (maintainer: "bewegt sich zu viel").
	var sx: Vector2 = _spring_step(_cur_pos.x, _target_pos.x, _vel_pos.x, POS_STIFFNESS, POS_DAMPING, delta)
	var sy: Vector2 = _spring_step(_cur_pos.y, _target_pos.y, _vel_pos.y, POS_STIFFNESS, POS_DAMPING, delta)
	_cur_pos = Vector2(sx.x, sy.x)
	_vel_pos = Vector2(sx.y, sy.y)
	var sr: Vector2 = _spring_step(_cur_rot, _target_rot + _fan_rot, _vel_rot, ROT_STIFFNESS, ROT_DAMPING, delta)
	_cur_rot = sr.x
	_vel_rot = sr.y
	var ss: Vector2 = _spring_step(_cur_scale, _target_scale, _vel_scale, SCALE_STIFFNESS, SCALE_DAMPING, delta)
	_cur_scale = ss.x
	_vel_scale = ss.y

	_apply_transform()
	_layout_shadow(1.0)

	# Early-out: stop only once BOTH velocity AND distance-to-target have settled on every axis — checking
	# position distance alone let the scale/rotation freeze mid-deal (cards settling at e.g. scale 0.66).
	var moving: bool = _vel_pos.length() > SETTLE_EPSILON or absf(_vel_rot) > SETTLE_EPSILON \
		or absf(_vel_scale) > SETTLE_EPSILON or _cur_pos.distance_to(_target_pos) > SETTLE_EPSILON \
		or absf(_cur_rot - (_target_rot + _fan_rot)) > SETTLE_EPSILON \
		or absf(_cur_scale - _target_scale) > SETTLE_EPSILON
	if not moving:
		set_process(false)


func _apply_transform() -> void:
	position = _cur_pos
	pivot_offset = size * 0.5
	rotation_degrees = _cur_rot          # spring rotation only (fan/deal-in) — no hover lean
	scale = Vector2(_cur_scale, _cur_scale)


# One damped-spring step for a scalar. Returns Vector2(new_value, new_velocity) so the caller keeps the
# velocity across frames (persistent velocity is what gives the overshoot/settle, not a linear tween).
func _spring_step(cur: float, target: float, vel: float, stiffness: float, damping: float, delta: float) -> Vector2:
	var accel: float = (target - cur) * stiffness - vel * (2.0 * sqrt(stiffness) * damping)
	var nv: float = vel + accel * delta
	return Vector2(cur + nv * delta, nv)


func _layout_shadow(grow: float) -> void:
	if _shadow == null:
		return
	var spread: float = SHADOW_SPREAD_PX * grow
	_shadow.position = Vector2(-spread * 0.5, -spread * 0.5 + SHADOW_OFFSET_PX)
	_shadow.size = size + Vector2(spread, spread)
	_shadow.add_theme_stylebox_override("panel", _shadow_style(spread, SHADOW_OFFSET_PX))


# === Styles ===

func _face_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.14, 0.16, 0.20, 0.98)
	s.set_corner_radius_all(CORNER_RADIUS_PX)
	s.border_width_top = 1
	s.border_color = Color(1, 1, 1, BEVEL_ALPHA)   # subtle top bevel highlight
	return s


## Face with a cyan accent border for the selected strip card (Tactical-HUD selection glow).
func _face_style_selected() -> StyleBoxFlat:
	var s := _face_style()
	s.set_border_width_all(2)
	s.border_color = Color(0.36, 0.80, 0.92, 0.9)
	return s


func _shadow_style(spread: float, _offset: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.0)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = int(spread)
	s.set_corner_radius_all(CORNER_RADIUS_PX)
	return s
