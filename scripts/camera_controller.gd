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

# Performance: Dirty flag to avoid unnecessary camera updates
var _transform_dirty: bool = true


func _ready() -> void:
	_camera = $Camera3D
	_mark_dirty()


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
		_mark_dirty()

	# Performance: Only update transform when dirty (something changed)
	if _transform_dirty:
		_apply_camera_transform()
		_transform_dirty = false


## Mark transform as needing update (call instead of direct _update_camera_transform)
func _mark_dirty() -> void:
	_transform_dirty = true


## Check if mouse is over a scrollable UI element (to prevent zoom when scrolling menus)
func _is_mouse_over_scrollable_ui() -> bool:
	var mouse_pos = get_viewport().get_mouse_position()

	# Find the UI layer and check for visible scroll containers
	var ui_layer = get_tree().root.find_child("UI", true, false)
	if not ui_layer:
		return false

	# Check LeftPanelScroll (hamburger menu)
	var left_panel = ui_layer.find_child("LeftPanelScroll", true, false)
	if left_panel and left_panel is Control and left_panel.visible:
		if left_panel.get_global_rect().has_point(mouse_pos):
			return true

	# Check any other visible ScrollContainers
	for child in ui_layer.get_children():
		if _check_scroll_container_recursive(child, mouse_pos):
			return true

	return false


## Recursively check if mouse is over any visible ScrollContainer
func _check_scroll_container_recursive(node: Node, mouse_pos: Vector2) -> bool:
	if node is ScrollContainer and node.visible:
		if node.get_global_rect().has_point(mouse_pos):
			return true

	for child in node.get_children():
		if _check_scroll_container_recursive(child, mouse_pos):
			return true

	return false


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

		# Scroll wheel for zoom - but NOT when mouse is over UI
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if not _is_mouse_over_scrollable_ui():
				_zoom(-zoom_speed)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not _is_mouse_over_scrollable_ui():
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
	_mark_dirty()


func _pan_camera(delta: Vector2) -> void:
	# Calculate pan direction based on camera orientation (mouse pan)
	var right = _camera.global_transform.basis.x
	var forward = -_camera.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()

	var pan_delta = (-right * delta.x + forward * delta.y) * pan_speed
	_target_position += pan_delta
	_mark_dirty()


func _keyboard_pan(direction: Vector2, delta: float) -> void:
	# Calculate pan direction based on camera view direction (not world coordinates)
	# Use the pivot's rotation (yaw) to determine forward/right in world space
	var camera_basis = global_transform.basis
	var right = camera_basis.x  # Local X is right
	var forward = -camera_basis.z  # Local -Z is forward

	# Flatten to horizontal plane
	right.y = 0
	forward.y = 0
	right = right.normalized()
	forward = forward.normalized()

	var pan_delta = (right * direction.x + forward * direction.y) * keyboard_pan_speed * delta
	_target_position += pan_delta
	_mark_dirty()


func _zoom(amount: float) -> void:
	_current_zoom = clamp(_current_zoom + amount, min_zoom, max_zoom)
	_mark_dirty()


## Actually apply the camera transform (called only when dirty)
func _apply_camera_transform() -> void:
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
	tween.tween_callback(_mark_dirty)


## Reset camera to default view
func reset_view() -> void:
	_target_position = Vector3.ZERO
	_pitch = -45.0
	_yaw = 0.0
	_current_zoom = 10.0  # Default zoom distance
	_mark_dirty()


## Set zoom level with automatic clamping
## @param zoom: New zoom distance in meters
func set_zoom(zoom: float) -> void:
	_current_zoom = clamp(zoom, min_zoom, max_zoom)
	_mark_dirty()


## Get current zoom level
## @return: Current zoom distance in meters
func get_zoom() -> float:
	return _current_zoom


## Adjust camera for table size
## @param table_size_feet: Table dimensions in feet
func adjust_for_table_size(table_size_feet: Vector2) -> void:
	var table_diagonal_feet = table_size_feet.length()
	var table_diagonal_meters = table_diagonal_feet * 0.3048
	var target_zoom = table_diagonal_meters * 0.7
	set_zoom(target_zoom)
