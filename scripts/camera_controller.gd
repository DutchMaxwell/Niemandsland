extends Node3D
## Camera controller with orbit, pan, and zoom functionality
## Optimized for tabletop gaming view
## Supports WASD movement and Q/E rotation

@export var rotation_speed: float = 0.005
@export var pan_speed: float = 0.005  # Pan speed for mouse camera movement
@export var keyboard_pan_speed: float = 0.75  # Pan speed for WASD movement
@export var keyboard_rotation_speed: float = 90.0  # Rotation speed for Q/E (degrees per second)
@export var zoom_speed: float = 0.12  # Zoom step as a fraction of current distance
@export var min_zoom: float = 0.06  # Minimum zoom distance (close-up on a single model)
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
	# Small near plane so close-up zoom doesn't clip into miniatures (they are only
	# a few cm tall, far below the default 0.05 m near plane).
	if _camera:
		_camera.near = 0.01
	_mark_dirty()


func _process(delta: float) -> void:
	# Handle WASD keyboard movement (only when Shift is NOT pressed to avoid conflicts)
	_move_direction = Vector2.ZERO
	_rotation_direction = 0.0

	# Movement is POLLED via Input.is_key_pressed, which bypasses GUI focus — so a
	# focused text field (e.g. the chat input) would otherwise still pan the camera.
	# Freeze movement while any LineEdit has focus.
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return

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


## Centre the orbit pivot on a world position (e.g. a unit centroid from the unit-card dock).
func focus_on(world_pos: Vector3) -> void:
	_target_position = world_pos
	_mark_dirty()


## Check if mouse is over a scrollable UI element (to prevent zoom when scrolling menus).
##
## SURVIVES the move to _unhandled_input, unlike every other hand-rolled UI guard in this project.
## Control.mouse_force_pass_scroll_events defaults to TRUE, so MOUSE_FILTER_STOP does NOT stop wheel
## events: they walk the whole chain and are consumed only if a control calls accept_event().
## Measured on 4.6.2 — wheel over a STOP PanelContainer/Button: nothing consumed; over a
## ScrollContainer whose content FITS: nothing consumed; over one that can actually scroll: only the
## PRESS half is consumed, the release still arrives here. Since the branches below zoom on both
## halves, dropping this guard would zoom the camera half a notch per tick while scrolling a menu.
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


## Camera control lives in _unhandled_input, NEVER in _input. Godot dispatches
##     _input group  →  GUI (Control._gui_input)  →  _unhandled_input group
## and aborts as soon as the event is handled, so by the time we run, any Control that owns this
## click has already consumed it. In _input the RMB/MMB branches below had no UI check at all:
## right-clicking any HUD button jerked the camera into an orbit, and middle-clicking one panned it.
## The engine now answers "is the pointer over UI?" per event, freshly and correctly.
## The wheel is the one exception — see _is_mouse_over_scrollable_ui.
func _unhandled_input(event: InputEvent) -> void:
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

	# NOTE: mouse MOTION is deliberately not handled here — see _input below.


## Mouse MOTION cannot ride along in _unhandled_input, and this is the one place the measured design
## was wrong. Godot routes motion to gui_find_control(pos) whenever gui.mouse_focus is NULL — which is
## exactly the state during a drag that STARTED on the table — and a MOUSE_FILTER_STOP ancestor then
## consumes it. Measured on 4.6.2: a right-drag orbit sweeping from the table across the dice panel
## loses half its motion events at stage 3, so the camera silently stops turning mid-sweep over the
## bottom-right quadrant. A gesture that is ALREADY live therefore claims motion here in stage 1; the
## button that starts it still faces the UI in _unhandled_input, so right-clicking a HUD button still
## does not begin an orbit.
func _input(event: InputEvent) -> void:
	if not (_is_rotating or _is_panning):
		return
	var motion_event := event as InputEventMouseMotion
	if motion_event == null:
		return
	if _is_rotating:
		_rotate_camera(motion_event.relative)
	else:
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
	# Proportional zoom: each scroll changes distance by a fraction of the current
	# distance, so it stays smooth from table overview down to a single model.
	_current_zoom = clamp(_current_zoom * (1.0 + amount), min_zoom, max_zoom)
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
	var target_zoom = table_diagonal_meters * 0.95
	set_zoom(target_zoom)
