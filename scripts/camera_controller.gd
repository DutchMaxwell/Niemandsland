extends Node3D
## Camera controller with orbit, pan, and zoom functionality
## Optimized for tabletop gaming view
## Supports WASD movement and Q/E rotation

@export var rotation_speed: float = 0.005
@export var pan_speed: float = 0.005  # Pan speed for mouse camera movement
@export var keyboard_pan_speed: float = 1.5  # Pan speed for WASD movement
@export var keyboard_rotation_speed: float = 90.0  # Rotation speed for Q/E (degrees per second)
@export var zoom_speed: float = 0.15  # Zoom speed for smooth control
@export var min_zoom: float = 0.5  # Minimum zoom distance
@export var max_zoom: float = 25.0  # Maximum zoom for larger tables
@export var min_pitch: float = -80.0  # degrees
@export var max_pitch: float = -10.0  # degrees

var _camera: Camera3D
var _current_zoom: float = 10.0  # Default zoom distance
var _pitch: float = -45.0  # degrees
var _yaw: float = 0.0  # degrees
var _target_position: Vector3 = Vector3.ZERO
var _is_rotating: bool = false
var _is_panning: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO

# WASD movement state
var _move_direction: Vector2 = Vector2.ZERO
var _rotation_direction: float = 0.0


func _ready() -> void:
	_camera = $Camera3D
	_update_camera_transform()


func _process(delta: float) -> void:
	# Handle WASD keyboard movement (only when Shift is NOT pressed to avoid conflicts)
	_move_direction = Vector2.ZERO
	_rotation_direction = 0.0

	# Skip WASD if Shift is held (used for other shortcuts like Shift+A, Shift+R)
	if not Input.is_key_pressed(KEY_SHIFT):
		if Input.is_key_pressed(KEY_W):
			_move_direction.y += 1.0
		if Input.is_key_pressed(KEY_S):
			_move_direction.y -= 1.0
		if Input.is_key_pressed(KEY_A):
			_move_direction.x -= 1.0
		if Input.is_key_pressed(KEY_D):
			_move_direction.x += 1.0

	# Q/E for rotation
	if Input.is_key_pressed(KEY_Q):
		_rotation_direction = 1.0
	if Input.is_key_pressed(KEY_E):
		_rotation_direction = -1.0

	# Apply movement if any direction is pressed
	if _move_direction != Vector2.ZERO:
		_keyboard_pan(_move_direction.normalized(), delta)

	# Apply rotation if Q or E is pressed
	if _rotation_direction != 0.0:
		_yaw += _rotation_direction * keyboard_rotation_speed * delta
		_update_camera_transform()


func _input(event: InputEvent) -> void:
	# Handle mouse button events
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton

		# Right click for rotation
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_is_rotating = mouse_event.pressed
			if mouse_event.pressed:
				_last_mouse_pos = mouse_event.position

		# Middle click for panning
		elif mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = mouse_event.pressed
			if mouse_event.pressed:
				_last_mouse_pos = mouse_event.position

		# Scroll wheel for zoom
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-zoom_speed)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(zoom_speed)

	# Handle mouse motion
	elif event is InputEventMouseMotion:
		var motion_event = event as InputEventMouseMotion

		if _is_rotating:
			_rotate_camera(motion_event.relative)
		elif _is_panning:
			_pan_camera(motion_event.relative)


func _rotate_camera(delta: Vector2) -> void:
	_yaw -= delta.x * rotation_speed * 100
	_pitch -= delta.y * rotation_speed * 100
	_pitch = clamp(_pitch, min_pitch, max_pitch)
	_update_camera_transform()


func _pan_camera(delta: Vector2) -> void:
	# Calculate pan direction based on camera orientation (mouse pan)
	var right = _camera.global_transform.basis.x
	var forward = -_camera.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()

	var pan_delta = (-right * delta.x + forward * delta.y) * pan_speed
	_target_position += pan_delta
	_update_camera_transform()


func _keyboard_pan(direction: Vector2, delta: float) -> void:
	# Calculate pan direction based on camera view direction (not world coordinates)
	# Use the pivot's rotation (yaw) to determine forward/right in world space
	var basis = global_transform.basis
	var right = basis.x  # Local X is right
	var forward = -basis.z  # Local -Z is forward

	# Flatten to horizontal plane
	right.y = 0
	forward.y = 0
	right = right.normalized()
	forward = forward.normalized()

	var pan_delta = (right * direction.x + forward * direction.y) * keyboard_pan_speed * delta
	_target_position += pan_delta
	_update_camera_transform()


func _zoom(amount: float) -> void:
	_current_zoom = clamp(_current_zoom + amount, min_zoom, max_zoom)
	_update_camera_transform()


func _update_camera_transform() -> void:
	# Update pivot position
	global_position = _target_position

	# Update pivot rotation (yaw only)
	rotation_degrees.y = _yaw

	# Update camera position and rotation (pitch and distance)
	if _camera:
		var pitch_rad = deg_to_rad(_pitch)
		var offset = Vector3(0, -sin(pitch_rad), cos(pitch_rad)) * _current_zoom
		_camera.position = offset
		_camera.look_at(_target_position, Vector3.UP)


## Center camera on a specific world position
func focus_on(world_position: Vector3) -> void:
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_target_position", world_position, 0.5)
	tween.tween_callback(_update_camera_transform)


## Reset camera to default view
func reset_view() -> void:
	_target_position = Vector3.ZERO
	_pitch = -45.0
	_yaw = 0.0
	_current_zoom = 10.0  # Default zoom distance
	_update_camera_transform()
