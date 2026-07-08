extends Node3D
## Represents a remote player as a floating head at their camera position.
##
## The head follows the remote player's exact 3D camera position and rotates
## to match their look direction. Features animated eyelids (blink) and
## eyebrows for expressiveness. Per-player colour comes from the shared PlayerPalette (bus 036) so the
## avatar always matches the player's army bases + cursor.

# ===== Constants =====

const HEAD_RADIUS := 0.07
const EYE_OFFSET_X := 0.03
const EYE_OFFSET_Y := 0.01
const EYE_OFFSET_Z := -0.06
const EYE_WHITE_RADIUS := 0.015
const PUPIL_RADIUS := 0.008
const PUPIL_OFFSET_Z := -0.006
const EYELID_RADIUS := 0.016
const EYEBROW_SIZE := Vector3(0.025, 0.004, 0.008)
const EYEBROW_OFFSET_Y := 0.025
const LABEL_OFFSET_Y := 0.12

## Default resting spot (before/without live camera-position packets): at this player's
## table edge by slot, so the head is never stranded in the dead centre after a reconnect.
const FEET_TO_METERS := 0.3048
const DEFAULT_EDGE_MARGIN_M := 0.15
const DEFAULT_HEIGHT_M := 0.35

const BLINK_MIN_INTERVAL := 2.0
const BLINK_MAX_INTERVAL := 6.0
const BLINK_DURATION := 0.15

# Name label: explicit pixel_size keeps it small + crisp (the default 0.005 made it ~16 cm tall).
const NAME_LABEL_FONT_SIZE := 48
const NAME_LABEL_PIXEL_SIZE := 0.0009  # ~4.3 cm tall

# Fade the avatar as its owner zooms IN, so it stops hiding the detail they're inspecting; at max
# zoom only a faint ghost remains. `zoom` is the camera distance from the table in metres.
const FADE_ZOOM_MIN := 0.06   # fully zoomed in (matches camera min_zoom) -> ghost
const FADE_ZOOM_FULL := 6.0   # at/beyond this distance the avatar is fully opaque
const GHOST_ALPHA := 0.12     # faintest the avatar gets

# ===== Variables =====

var peer_id: int = 0
var player_color: Color = Color.WHITE

var _head_mesh: MeshInstance3D
var _name_label: Label3D
var _left_eyelid: MeshInstance3D
var _right_eyelid: MeshInstance3D

# Zoom-based transparency (issue: avatar fades as its owner zooms in).
var _current_alpha: float = 1.0
var _mesh_instances: Array[MeshInstance3D] = []

# Smooth interpolation for head rotation
var _target_yaw: float = 0.0
var _target_pitch: float = -45.0
var _current_yaw: float = 0.0
var _current_pitch: float = -45.0

# Smooth interpolation for position (follows remote camera)
var _target_position: Vector3 = Vector3.ZERO
var _position_initialized: bool = false

# Blink animation
var _blink_timer: float = 0.0
var _next_blink_at: float = 3.0
var _is_blinking: bool = false
var _blink_progress: float = 0.0

# Dice roll animation
var _is_rolling: bool = false
var _roll_timer: float = 0.0
var _roll_duration: float = 1.2
var _original_head_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	_build_avatar()


func _process(delta: float) -> void:
	# Smooth head rotation — full camera direction, no dampening
	_current_yaw = lerp(_current_yaw, _target_yaw, delta * 5.0)
	_current_pitch = lerp(_current_pitch, _target_pitch, delta * 5.0)
	if _head_mesh:
		_head_mesh.rotation_degrees = Vector3(_current_pitch, _current_yaw, 0)

	# Smooth position interpolation (follows remote camera in 3D)
	if _position_initialized:
		position = position.lerp(_target_position, delta * 5.0)

	# Blink animation
	_update_blink(delta)

	# Dice roll animation
	if _is_rolling:
		_roll_timer += delta
		var t := _roll_timer / _roll_duration
		if t >= 1.0:
			_is_rolling = false
			_roll_timer = 0.0
			if _head_mesh:
				_head_mesh.position = _original_head_pos
		else:
			var bob := sin(t * PI * 3.0) * 0.05 * (1.0 - t)
			if _head_mesh:
				_head_mesh.position = _original_head_pos + Vector3(0, bob, 0)


# ===== Public API =====

## Initialize the avatar for a specific peer. Colour keys off the durable SLOT (not the
## transport peer_id, which the relay re-issues on a guest rejoin), with a modulo wrap so
## a high monotonic slot / pending slot 0 never falls to WHITE. peer_id is kept for the label.
func setup(p_peer_id: int, p_slot: int, table_size_feet: Vector2) -> void:
	peer_id = p_peer_id
	player_color = PlayerPalette.color_for_slot(p_slot)   # shared slot→palette (matches army bases, bus 036)
	# Rest at this player's table edge (by slot) so the head is never stuck in the dead centre
	# when camera-position packets are missing/delayed; snaps to the live camera on the first
	# update_position().
	position = _default_edge_position(p_slot, table_size_feet)
	_build_avatar()


## A sensible default resting position at the player's table edge, derived from their slot.
func _default_edge_position(slot: int, table_size_feet: Vector2) -> Vector3:
	var hx := table_size_feet.x * 0.5 * FEET_TO_METERS + DEFAULT_EDGE_MARGIN_M
	var hz := table_size_feet.y * 0.5 * FEET_TO_METERS + DEFAULT_EDGE_MARGIN_M
	var s := (((slot - 1) % 4) + 1) if slot > 0 else 1
	match s:
		2: return Vector3(hx, DEFAULT_HEIGHT_M, 0.0)    # right
		3: return Vector3(0.0, DEFAULT_HEIGHT_M, -hz)   # front
		4: return Vector3(0.0, DEFAULT_HEIGHT_M, hz)    # back
		_: return Vector3(-hx, DEFAULT_HEIGHT_M, 0.0)   # left (slot 1 / default)


## Update the remote player's camera look direction
func update_look_direction(yaw: float, pitch: float) -> void:
	_target_yaw = yaw
	_target_pitch = pitch


## Update avatar position to follow remote camera (full 3D)
func update_position(pos_x: float, pos_y: float, pos_z: float) -> void:
	_target_position = Vector3(pos_x, pos_y, pos_z)
	if not _position_initialized:
		position = _target_position
		_position_initialized = true


## Fade the avatar based on its owner's camera zoom (distance from the table): fully opaque when
## zoomed out, a faint ghost when fully zoomed in, so it doesn't hide the spot they're inspecting.
func update_zoom(zoom: float) -> void:
	_apply_alpha(alpha_for_zoom(zoom))


## Maps a camera zoom-distance (metres) to the avatar's alpha (GHOST_ALPHA..1.0). Static + pure.
static func alpha_for_zoom(zoom: float) -> float:
	var t: float = clampf((zoom - FADE_ZOOM_MIN) / (FADE_ZOOM_FULL - FADE_ZOOM_MIN), 0.0, 1.0)
	return lerpf(GHOST_ALPHA, 1.0, t)


## Apply an alpha (0..1) to the whole avatar — every mesh via GeometryInstance3D.transparency, plus
## the name label's modulate. Skipped when unchanged to avoid per-packet churn.
func _apply_alpha(alpha: float) -> void:
	if is_equal_approx(alpha, _current_alpha):
		return
	_current_alpha = alpha
	for mi: MeshInstance3D in _mesh_instances:
		if is_instance_valid(mi):
			mi.transparency = 1.0 - alpha
	if _name_label:
		_name_label.modulate.a = alpha


## Play dice roll animation
func play_dice_roll_animation() -> void:
	if _head_mesh:
		_is_rolling = true
		_roll_timer = 0.0
		_original_head_pos = _head_mesh.position


## Update the floating name label (called when the player's name syncs in).
func set_player_name(display_name: String) -> void:
	if _name_label:
		_name_label.text = display_name


## Recolour the avatar (name label + head) when a slot-table sync corrects this peer's colour on a guest
## that had spawned it with a stale slot (bus 036).
func set_player_color(color: Color) -> void:
	player_color = color
	if _name_label:
		_name_label.modulate = color
	if is_instance_valid(_head_mesh) and _head_mesh.mesh and _head_mesh.mesh.material is StandardMaterial3D:
		(_head_mesh.mesh.material as StandardMaterial3D).albedo_color = color


# ===== Avatar Construction =====

## Build the 3D avatar from primitives — head only with eyes, pupils, lids, brows
func _build_avatar() -> void:
	# Clean up existing meshes
	for child in get_children():
		child.queue_free()

	# Head sphere
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = player_color
	head_mat.roughness = 0.6
	head_mat.metallic = 0.1

	_head_mesh = MeshInstance3D.new()
	var head := SphereMesh.new()
	head.radius = HEAD_RADIUS
	head.height = HEAD_RADIUS * 2
	head.material = head_mat
	_head_mesh.mesh = head
	_head_mesh.position = Vector3.ZERO
	add_child(_head_mesh)
	_original_head_pos = _head_mesh.position

	# Build eyes (white + pupil + eyelid)
	_left_eyelid = _build_eye(-1)
	_right_eyelid = _build_eye(1)

	# Build eyebrows
	_build_eyebrow(-1)
	_build_eyebrow(1)

	# Name label — a small crisp label (explicit pixel_size, else the default 0.005 made it huge).
	_name_label = Label3D.new()
	_name_label.text = "Player %d" % peer_id
	_name_label.font_size = NAME_LABEL_FONT_SIZE
	_name_label.pixel_size = NAME_LABEL_PIXEL_SIZE
	_name_label.modulate = player_color
	_name_label.outline_modulate = Color.BLACK
	_name_label.outline_size = 6
	_name_label.position = Vector3(0, LABEL_OFFSET_Y, 0)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	add_child(_name_label)

	# Cache every mesh instance so update_zoom() can fade the whole avatar at once.
	_mesh_instances.clear()
	for node in find_children("*", "MeshInstance3D", true, false):
		_mesh_instances.append(node)

	# Randomize first blink interval
	_next_blink_at = randf_range(BLINK_MIN_INTERVAL, BLINK_MAX_INTERVAL)


## Build one eye assembly (white + pupil + eyelid) and return the eyelid
func _build_eye(side: int) -> MeshInstance3D:
	var eye_container := Node3D.new()
	eye_container.name = "Eye_L" if side == -1 else "Eye_R"
	eye_container.position = Vector3(side * EYE_OFFSET_X, EYE_OFFSET_Y, EYE_OFFSET_Z)
	_head_mesh.add_child(eye_container)

	# Eye white
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color.WHITE
	eye_mat.emission_enabled = true
	eye_mat.emission = Color.WHITE
	eye_mat.emission_energy_multiplier = 0.5

	var eye_white := MeshInstance3D.new()
	var white_mesh := SphereMesh.new()
	white_mesh.radius = EYE_WHITE_RADIUS
	white_mesh.height = EYE_WHITE_RADIUS * 2
	white_mesh.material = eye_mat
	eye_white.mesh = white_mesh
	eye_container.add_child(eye_white)

	# Pupil (dark sphere, slightly in front)
	var pupil_mat := StandardMaterial3D.new()
	pupil_mat.albedo_color = Color(0.05, 0.05, 0.05)

	var pupil := MeshInstance3D.new()
	var pupil_mesh := SphereMesh.new()
	pupil_mesh.radius = PUPIL_RADIUS
	pupil_mesh.height = PUPIL_RADIUS * 2
	pupil_mesh.material = pupil_mat
	pupil.mesh = pupil_mesh
	pupil.position = Vector3(0, 0, PUPIL_OFFSET_Z)
	eye_container.add_child(pupil)

	# Eyelid (colored sphere, Y-scaled for blink)
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = player_color.darkened(0.3)

	var eyelid := MeshInstance3D.new()
	var lid_mesh := SphereMesh.new()
	lid_mesh.radius = EYELID_RADIUS
	lid_mesh.height = EYELID_RADIUS * 2
	lid_mesh.material = lid_mat
	eyelid.mesh = lid_mesh
	eyelid.position = Vector3(0, EYE_WHITE_RADIUS * 0.5, 0)
	eyelid.scale = Vector3(1.0, 0.1, 1.0)  # Open: nearly flat
	eye_container.add_child(eyelid)

	return eyelid


## Build one eyebrow above an eye
func _build_eyebrow(side: int) -> void:
	var brow_mat := StandardMaterial3D.new()
	brow_mat.albedo_color = player_color.darkened(0.5)

	var brow := MeshInstance3D.new()
	var brow_mesh := BoxMesh.new()
	brow_mesh.size = EYEBROW_SIZE
	brow_mesh.material = brow_mat
	brow.mesh = brow_mesh
	brow.position = Vector3(
		side * EYE_OFFSET_X,
		EYE_OFFSET_Y + EYEBROW_OFFSET_Y,
		EYE_OFFSET_Z
	)
	_head_mesh.add_child(brow)


# ===== Blink Animation =====

## Timer-based blink with random intervals
func _update_blink(delta: float) -> void:
	if _is_blinking:
		_blink_progress += delta
		var half := BLINK_DURATION / 2.0

		if _blink_progress >= BLINK_DURATION:
			# Blink complete — eyes open
			_is_blinking = false
			_blink_progress = 0.0
			_set_eyelid_openness(0.1)
			_next_blink_at = randf_range(BLINK_MIN_INTERVAL, BLINK_MAX_INTERVAL)
			_blink_timer = 0.0
		elif _blink_progress < half:
			# Closing phase
			var t := _blink_progress / half
			_set_eyelid_openness(lerp(0.1, 1.0, t))
		else:
			# Opening phase
			var t := (_blink_progress - half) / half
			_set_eyelid_openness(lerp(1.0, 0.1, t))
	else:
		_blink_timer += delta
		if _blink_timer >= _next_blink_at:
			_is_blinking = true
			_blink_progress = 0.0


## Set eyelid Y scale: 0.1 = open (flat), 1.0 = closed (full sphere)
func _set_eyelid_openness(value: float) -> void:
	if _left_eyelid:
		_left_eyelid.scale.y = value
	if _right_eyelid:
		_right_eyelid.scale.y = value
