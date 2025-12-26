extends Node3D
## Camera controller with orbit, pan, and zoom functionality
## Optimized for tabletop gaming view

@export var rotation_speed: float = 0.005
@export var pan_speed: float = 0.005
@export var zoom_speed: float = 0.15  # Fine zoom increments for smooth control
@export var min_zoom: float = 1.0  # Close zoom without clipping into terrain
@export var max_zoom: float = 25.0  # Extended max for larger tables
@export var min_pitch: float = -80.0  # degrees
@export var max_pitch: float = -10.0  # degrees

var _camera: Camera3D
var _current_zoom: float = 10.0
var _pitch: float = -45.0  # degrees
var _yaw: float = 0.0  # degrees
var _target_position: Vector3 = Vector3.ZERO
var _is_rotating: bool = false
var _is_panning: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _collision_margin: float = 0.5  # Safety margin to prevent clipping


func _ready() -> void:
	_camera = $Camera3D
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
	# Calculate pan direction based on camera orientation
	var right = _camera.global_transform.basis.x
	var forward = -_camera.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()

	var pan_delta = (-right * delta.x + forward * delta.y) * pan_speed
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
		var desired_offset = Vector3(0, -sin(pitch_rad), cos(pitch_rad)) * _current_zoom
		var desired_camera_pos = _target_position + (global_transform.basis * desired_offset)

		# Raycast from target to desired camera position to check for collisions
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(_target_position, desired_camera_pos)
		query.exclude = []  # Could exclude specific objects if needed

		var result = space_state.intersect_ray(query)

		# If we hit something, position camera just before the collision point
		var final_offset = desired_offset
		if result:
			var collision_point = result.position
			var safe_distance = _target_position.distance_to(collision_point) - _collision_margin
			safe_distance = max(safe_distance, min_zoom)  # Don't go closer than min_zoom

			# Calculate shortened offset to stop before collision
			var direction = desired_offset.normalized()
			final_offset = direction * safe_distance

		_camera.position = final_offset
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
	_current_zoom = 10.0
	_update_camera_transform()
