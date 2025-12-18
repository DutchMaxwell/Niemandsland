extends Node3D
## Manages all game objects: miniatures, dice, terrain
## Handles spawning, selection, dragging, and rotation
##
## TODO: Fix measurement line visually overlapping label text despite different Z heights.
##       This appears to be a depth rendering issue with no_depth_test enabled on both elements.

signal dice_rolled(total: int, results: Array)
signal object_selected(obj: Node3D)
signal object_deselected()
signal selection_changed(selected_objects: Array[Node3D])
signal distance_changed(distance_inches: float, from_pos: Vector3, to_pos: Vector3)
signal measurement_finished(distance_inches: float)
signal drag_ended()

@export var drag_height: float = 0.5
@export var rotation_speed_degrees: float = 2.0  # Degrees per second while R held
@export var min_drag_height: float = 0.01  # Minimum height above table when dragging

# Debug logging
@export var debug_dice_physics: bool = true  # Set to false to disable logging
var _debug_log_file: FileAccess = null
var _debug_log_timer: float = 0.0
const DEBUG_LOG_INTERVAL: float = 0.5  # Log every 0.5 seconds
var _is_rolling: bool = false

# Multi-selection support
var _selected_objects: Array[Node3D] = []
var _is_dragging: bool = false
var _drag_plane: Plane
var _dice_list: Array[RigidBody3D] = []
var _object_counter: int = 0

# Rotation tracking
var _is_rotating: bool = false

# Drag distance tracking
var _drag_start_positions: Dictionary = {}  # Object -> start position mapping
var _drag_anchor_position: Vector3 = Vector3.ZERO  # Primary drag anchor point
var _drag_line: MeshInstance3D = null  # Visual line during drag
var _drag_label: Label3D = null  # Distance label during drag

# Box selection (drag rectangle to select multiple objects)
var _is_box_selecting: bool = false
var _box_select_start: Vector2 = Vector2.ZERO
var _box_select_end: Vector2 = Vector2.ZERO
var _box_select_rect: ColorRect = null

# Measurement mode (Shift+Left-click to measure)
var _is_measuring: bool = false
var _measure_start_position: Vector3 = Vector3.ZERO
var _measure_start_snapped: bool = false  # True if start point snapped to object
var _measure_end_snapped: bool = false    # True if end point snapped to object
var _measure_start_object: Node3D = null  # Reference to start object for edge calculation
var _measure_end_object: Node3D = null    # Reference to end object for edge calculation
var _measure_line: MeshInstance3D = null
var _measure_label: Label3D = null

const METERS_TO_INCHES: float = 39.3701

# Preload resources (will be scenes in full version)
# Standard wargaming miniature sizes
const MINIATURE_HEIGHT: float = 0.032  # 32mm height
const MINIATURE_RADIUS: float = 0.016  # 32mm diameter base (16mm radius)


func _ready() -> void:
	_drag_plane = Plane(Vector3.UP, 0)
	_init_debug_log()


func _init_debug_log() -> void:
	if not debug_dice_physics:
		return
	# Open log file
	var log_path = "user://dice_debug.log"
	_debug_log_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _debug_log_file:
		_debug_log_file.store_line("=== DICE PHYSICS DEBUG LOG ===")
		_debug_log_file.store_line("Time: %s" % Time.get_datetime_string_from_system())
		_debug_log_file.store_line("Table collision: surface at y=0 (aligned with visual)")
		_debug_log_file.store_line("Dice: 16mm, 5g, expected rest y≈0.008")
		_debug_log_file.store_line("Physics: PURE JOLT - all interventions disabled for testing")
		_debug_log_file.store_line("Rescue threshold: y < -0.5m")
		_debug_log_file.store_line("-------------------------------")
		print("Debug log created at: %s" % ProjectSettings.globalize_path(log_path))
	else:
		print("ERROR: Could not create debug log file")


func _physics_process(delta: float) -> void:
	if not debug_dice_physics or _dice_list.is_empty():
		return

	_debug_log_timer += delta
	if _debug_log_timer < DEBUG_LOG_INTERVAL:
		return
	_debug_log_timer = 0.0

	# Log state of all dice
	_log_dice_states()


func _log_dice_states() -> void:
	var any_jittering = false
	var log_lines: Array[String] = []
	var timestamp = "%.2f" % (Time.get_ticks_msec() / 1000.0)

	log_lines.append("\n[%s] Dice States:" % timestamp)

	for i in range(_dice_list.size()):
		var dice = _dice_list[i]
		if not is_instance_valid(dice):
			continue

		var pos = dice.global_position
		var lin_vel = dice.linear_velocity
		var ang_vel = dice.angular_velocity
		var is_sleeping = dice.sleeping
		var is_frozen = dice.freeze

		var lin_speed = lin_vel.length()
		var ang_speed = ang_vel.length()

		var is_jittering = false
		var jitter_reason = ""
		var was_stabilized = false
		var was_rescued = false

		# RESCUE: If dice fell below -0.5m, teleport back to table
		if pos.y < -0.5:
			dice.global_position = Vector3(pos.x, 0.05, pos.z)
			dice.linear_velocity = Vector3.ZERO
			dice.angular_velocity = Vector3.ZERO
			dice.sleeping = true
			was_rescued = true
			_log_event("RESCUED %s from y=%.1f" % [dice.name, pos.y])

		# Only check dice near table surface (y between 0.005 and 0.05)
		# ALL INTERVENTIONS DISABLED - Testing pure Jolt physics
		elif pos.y > 0.005 and pos.y < 0.05:
			pass  # Just observe, don't intervene

		if is_jittering:
			any_jittering = true

		var status = "OK"
		if was_rescued:
			status = "RESCUED"
		elif was_stabilized:
			status = "STABILIZED"
		elif is_sleeping:
			status = "SLEEP"
		elif is_frozen:
			status = "FROZEN"
		elif is_jittering:
			status = "JITTER(%s)" % jitter_reason
		elif _is_rolling:
			status = "ROLLING"

		var line = "  Dice_%d: pos=(%.4f,%.4f,%.4f) lin_v=%.4f ang_v=%.2f [%s]" % [
			i + 1, pos.x, pos.y, pos.z, lin_speed, ang_speed, status
		]
		log_lines.append(line)

		# Console output only for actual jittering (not false positives)
		if is_jittering:
			print("[JITTER] Dice_%d y=%.4f lin_v=%.4f ang_v=%.2f" % [
				i + 1, pos.y, lin_speed, ang_speed
			])

	# Write to file
	if _debug_log_file:
		for line in log_lines:
			_debug_log_file.store_line(line)
		_debug_log_file.flush()

	# Also print summary if any dice are jittering
	if any_jittering:
		print("[DEBUG] Some dice are jittering - check dice_debug.log for details")


func _log_event(message: String) -> void:
	if not debug_dice_physics:
		return
	var timestamp = "%.2f" % (Time.get_ticks_msec() / 1000.0)
	var log_line = "[%s] %s" % [timestamp, message]
	print(log_line)
	if _debug_log_file:
		_debug_log_file.store_line(log_line)
		_debug_log_file.flush()


## Check if a D6 die is resting on an edge/corner instead of a flat face
## A face is flat when one local axis is nearly vertical (dot product with UP close to 1)
func _is_dice_on_edge(dice: RigidBody3D) -> bool:
	var dominated_threshold = 0.9  # cos(~25°) - how vertical an axis must be to count as "flat"

	# Get the local axes in world space
	var dice_basis = dice.global_transform.basis
	var local_x = dice_basis.x.normalized()
	var local_y = dice_basis.y.normalized()
	var local_z = dice_basis.z.normalized()

	# Check if any local axis is pointing mostly up or down (flat face)
	var up = Vector3.UP
	var x_alignment = absf(local_x.dot(up))
	var y_alignment = absf(local_y.dot(up))
	var z_alignment = absf(local_z.dot(up))

	# If any axis is well-aligned with vertical, dice is on a face
	if x_alignment > dominated_threshold or y_alignment > dominated_threshold or z_alignment > dominated_threshold:
		return false  # On a face, not an edge

	return true  # On an edge or corner


## Apply a small nudge torque to push the die off its edge onto a flat face
func _nudge_dice_off_edge(dice: RigidBody3D) -> void:
	# Wake up the dice if sleeping
	dice.sleeping = false

	# Find which way to nudge - towards the most aligned axis
	var dice_basis = dice.global_transform.basis
	var up = Vector3.UP

	var x_align = absf(dice_basis.x.dot(up))
	var y_align = absf(dice_basis.y.dot(up))
	var z_align = absf(dice_basis.z.dot(up))

	# Determine the best axis to rotate towards
	var nudge_axis: Vector3
	if x_align >= y_align and x_align >= z_align:
		# Rotate around Z or Y to make X point up/down
		nudge_axis = dice_basis.z if randf() > 0.5 else dice_basis.y
	elif y_align >= x_align and y_align >= z_align:
		# Rotate around X or Z to make Y point up/down
		nudge_axis = dice_basis.x if randf() > 0.5 else dice_basis.z
	else:
		# Rotate around X or Y to make Z point up/down
		nudge_axis = dice_basis.x if randf() > 0.5 else dice_basis.y

	# Apply a small torque impulse
	var nudge_strength = 0.00005  # Very gentle nudge
	dice.apply_torque_impulse(nudge_axis.normalized() * nudge_strength)


func _process(delta: float) -> void:
	# Continuous rotation while R is held - rotate all selected objects
	if _is_rotating and _selected_objects.size() > 0:
		var rotation_amount = deg_to_rad(rotation_speed_degrees) * delta * 60  # 60fps base
		for obj in _selected_objects:
			if is_instance_valid(obj):
				obj.rotate_y(rotation_amount)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton

		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				if mouse_event.shift_pressed:
					# Shift + Left-click starts measurement
					_start_measuring(mouse_event.position)
				else:
					# Pass Alt state for multi-select
					_try_select_at_mouse(mouse_event.position, mouse_event.alt_pressed)
			else:
				if _is_measuring:
					_stop_measuring(mouse_event.position)
				elif _is_box_selecting:
					_finish_box_selection(mouse_event.alt_pressed)
				else:
					_stop_dragging()

	elif event is InputEventMouseMotion:
		if _is_dragging:
			_update_drag(event.position)
		elif _is_box_selecting:
			_update_box_selection(event.position)
		elif _is_measuring:
			_update_measurement(event.position)

	# Rotation: hold R key for continuous rotation - requires selection
	elif event.is_action_pressed("rotate_object") and _selected_objects.size() > 0:
		_is_rotating = true
	elif event.is_action_released("rotate_object"):
		_is_rotating = false

	# ESC cancels current drag and restores original positions
	elif event.is_action_pressed("ui_cancel"):
		if _is_dragging:
			_cancel_drag()

	elif event.is_action_pressed("roll_dice"):
		roll_all_dice()


func _try_select_at_mouse(screen_pos: Vector2, alt_pressed: bool = false) -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 100

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = true

	var result = space_state.intersect_ray(query)

	if result and result.collider:
		var collider = result.collider

		# Check if it's a selectable object (not the table)
		if collider.is_in_group("selectable"):
			var already_selected = collider in _selected_objects

			if alt_pressed:
				# Alt+click: toggle selection (add/remove from selection)
				_toggle_object_selection(collider)
				# Only start dragging if object is now selected
				if collider in _selected_objects:
					_start_dragging(screen_pos)
			elif already_selected:
				# Clicking on already-selected object: just start dragging (keep multi-selection)
				_start_dragging(screen_pos)
			else:
				# Normal click on unselected object: replace selection
				_deselect_all()
				_add_to_selection(collider)
				_start_dragging(screen_pos)
		elif collider.is_in_group("table"):
			# Clicking on table starts box selection
			_start_box_selection(screen_pos, alt_pressed)


## Add an object to the current selection
func _add_to_selection(obj: Node3D) -> void:
	if obj in _selected_objects:
		return

	_selected_objects.append(obj)
	_highlight_object(obj)
	object_selected.emit(obj)
	selection_changed.emit(_selected_objects)


## Remove an object from the current selection
func _remove_from_selection(obj: Node3D) -> void:
	if obj not in _selected_objects:
		return

	_selected_objects.erase(obj)
	_unhighlight_object(obj)

	if _selected_objects.is_empty():
		object_deselected.emit()
	selection_changed.emit(_selected_objects)


## Toggle an object's selection state (Ctrl+click behavior)
func _toggle_object_selection(obj: Node3D) -> void:
	if obj in _selected_objects:
		_remove_from_selection(obj)
	else:
		_add_to_selection(obj)


## Deselect all objects
func _deselect_all() -> void:
	for obj in _selected_objects:
		if is_instance_valid(obj):
			_unhighlight_object(obj)
	_selected_objects.clear()
	object_deselected.emit()
	selection_changed.emit(_selected_objects)


## Apply highlight to an object to show it's selected
func _highlight_object(obj: Node3D) -> void:
	# Find all MeshInstance3D children and apply highlight
	for child in obj.get_children():
		if child is MeshInstance3D:
			var mat = child.material_override
			if mat is StandardMaterial3D:
				# Store original color and apply highlight
				child.set_meta("original_emission", mat.emission)
				child.set_meta("original_emission_enabled", mat.emission_enabled)
				mat.emission_enabled = true
				mat.emission = Color(0.3, 0.5, 1.0)  # Blue glow
				mat.emission_energy_multiplier = 0.5


## Remove highlight from an object
func _unhighlight_object(obj: Node3D) -> void:
	for child in obj.get_children():
		if child is MeshInstance3D:
			var mat = child.material_override
			if mat is StandardMaterial3D:
				# Restore original emission settings
				if child.has_meta("original_emission_enabled"):
					mat.emission_enabled = child.get_meta("original_emission_enabled")
					mat.emission = child.get_meta("original_emission")
				else:
					mat.emission_enabled = false


## Start box selection (drag rectangle to select multiple objects)
func _start_box_selection(screen_pos: Vector2, alt_pressed: bool) -> void:
	# If not holding Alt, clear current selection
	if not alt_pressed:
		_deselect_all()

	_is_box_selecting = true
	_box_select_start = screen_pos
	_box_select_end = screen_pos

	# Create selection rectangle UI
	_create_box_select_rect()


## Update box selection rectangle while dragging
func _update_box_selection(screen_pos: Vector2) -> void:
	if not _is_box_selecting:
		return

	_box_select_end = screen_pos
	_update_box_select_rect()


## Finish box selection and select all objects within the rectangle
func _finish_box_selection(alt_pressed: bool) -> void:
	if not _is_box_selecting:
		return

	# Find all selectable objects within the rectangle
	var rect = _get_box_select_rect()
	var camera = get_viewport().get_camera_3d()

	if camera:
		# Check all selectable objects
		for child in get_children():
			if child.is_in_group("selectable"):
				# Project object position to screen space
				var screen_pos = camera.unproject_position(child.global_position)

				# Check if within selection rectangle
				if rect.has_point(screen_pos):
					if alt_pressed and child in _selected_objects:
						# Alt + box select: toggle off if already selected
						_remove_from_selection(child)
					elif child not in _selected_objects:
						_add_to_selection(child)

	# Clean up
	_is_box_selecting = false
	_destroy_box_select_rect()


## Create the visual selection rectangle
func _create_box_select_rect() -> void:
	if _box_select_rect:
		_box_select_rect.queue_free()

	_box_select_rect = ColorRect.new()
	_box_select_rect.color = Color(0.3, 0.5, 1.0, 0.2)  # Semi-transparent blue

	# Add border using a StyleBoxFlat
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.3, 0.5, 1.0, 0.2)
	style.border_color = Color(0.3, 0.5, 1.0, 0.8)
	style.set_border_width_all(2)
	_box_select_rect.add_theme_stylebox_override("panel", style)

	# Add to UI layer
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "BoxSelectLayer"
	canvas_layer.layer = 100  # Above other UI
	add_child(canvas_layer)
	canvas_layer.add_child(_box_select_rect)

	_update_box_select_rect()


## Update the visual selection rectangle position and size
func _update_box_select_rect() -> void:
	if not _box_select_rect:
		return

	var rect = _get_box_select_rect()
	_box_select_rect.position = rect.position
	_box_select_rect.size = rect.size


## Get the normalized selection rectangle (handles negative sizes)
func _get_box_select_rect() -> Rect2:
	var min_pos = Vector2(
		min(_box_select_start.x, _box_select_end.x),
		min(_box_select_start.y, _box_select_end.y)
	)
	var max_pos = Vector2(
		max(_box_select_start.x, _box_select_end.x),
		max(_box_select_start.y, _box_select_end.y)
	)
	return Rect2(min_pos, max_pos - min_pos)


## Destroy the visual selection rectangle
func _destroy_box_select_rect() -> void:
	if _box_select_rect:
		var parent = _box_select_rect.get_parent()
		if parent:
			parent.queue_free()  # Also removes the CanvasLayer
		_box_select_rect = null


func _start_dragging(_screen_pos: Vector2) -> void:
	if _selected_objects.is_empty():
		return

	_is_dragging = true
	_drag_start_positions.clear()

	# Store start positions for all selected objects
	for obj in _selected_objects:
		if is_instance_valid(obj):
			_drag_start_positions[obj] = obj.global_position
			# For rigid bodies, make them kinematic while dragging
			if obj is RigidBody3D:
				obj.freeze = true

	# Use first selected object as anchor for distance calculation
	if _selected_objects.size() > 0:
		_drag_anchor_position = _selected_objects[0].global_position

	# Create drag visualization line
	_create_drag_line()


func _stop_dragging() -> void:
	if _is_dragging and not _selected_objects.is_empty():
		# Re-enable physics for rigid bodies
		for obj in _selected_objects:
			if is_instance_valid(obj) and obj is RigidBody3D:
				obj.freeze = false

		# Emit final distance for anchor object
		if _selected_objects.size() > 0:
			var anchor = _selected_objects[0]
			if is_instance_valid(anchor):
				var final_pos = anchor.global_position
				var distance_m = _drag_anchor_position.distance_to(final_pos)
				var distance_inches = distance_m * METERS_TO_INCHES
				if distance_inches > 0.1:  # Only emit if actually moved
					distance_changed.emit(distance_inches, _drag_anchor_position, final_pos)

		drag_ended.emit()

	_is_dragging = false
	_drag_start_positions.clear()
	_drag_anchor_position = Vector3.ZERO
	_destroy_drag_line()


## Cancel drag and restore all objects to their original positions
func _cancel_drag() -> void:
	if not _is_dragging:
		return

	# Restore all objects to their original positions
	for obj in _selected_objects:
		if is_instance_valid(obj) and _drag_start_positions.has(obj):
			obj.global_position = _drag_start_positions[obj]
			# Re-enable physics for rigid bodies
			if obj is RigidBody3D:
				obj.freeze = false

	_is_dragging = false
	_drag_start_positions.clear()
	_drag_anchor_position = Vector3.ZERO
	_destroy_drag_line()


## Create drag visualization line and label
func _create_drag_line() -> void:
	if _drag_line:
		_drag_line.queue_free()
	if _drag_label:
		_drag_label.queue_free()

	# Create line mesh
	_drag_line = MeshInstance3D.new()
	_drag_line.name = "DragLine"
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.ORANGE
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	_drag_line.material_override = material
	_drag_line.visible = false
	add_child(_drag_line)

	# Create 3D label
	_drag_label = Label3D.new()
	_drag_label.name = "DragLabel"
	_drag_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_drag_label.no_depth_test = true
	_drag_label.pixel_size = 0.001
	_drag_label.font_size = 24
	_drag_label.outline_size = 8
	_drag_label.modulate = Color.WHITE
	_drag_label.outline_modulate = Color.BLACK
	_drag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drag_label.visible = false
	add_child(_drag_label)


## Update drag line visualization
func _update_drag_line(from_pos: Vector3, to_pos: Vector3, distance_inches: float) -> void:
	if not _drag_line or not _drag_label:
		return

	# Calculate horizontal direction
	var direction = Vector3(to_pos.x - from_pos.x, 0, to_pos.z - from_pos.z)
	var length = direction.length()

	if length < 0.001:
		_drag_line.visible = false
		_drag_label.visible = false
		return

	_drag_line.visible = true
	_drag_label.visible = true

	# Create line mesh
	var line_mesh = BoxMesh.new()
	line_mesh.size = Vector3(length, 0.001, 0.002)
	_drag_line.mesh = line_mesh

	# Position at midpoint, slightly above table
	var midpoint = Vector3((from_pos.x + to_pos.x) / 2, 0.005, (from_pos.z + to_pos.z) / 2)
	_drag_line.global_position = midpoint

	# Rotate to align with direction
	var angle = atan2(direction.x, direction.z)
	_drag_line.rotation = Vector3(0, angle + PI/2, 0)

	# Update label
	_drag_label.global_position = Vector3(midpoint.x, 0.02, midpoint.z)
	_drag_label.text = "%.1f\"" % distance_inches
	_drag_label.rotation = Vector3(-PI/2, angle, 0)


## Destroy drag visualization
func _destroy_drag_line() -> void:
	if _drag_line:
		_drag_line.queue_free()
		_drag_line = null
	if _drag_label:
		_drag_label.queue_free()
		_drag_label = null


func _update_drag(screen_pos: Vector2) -> void:
	if _selected_objects.is_empty() or not _is_dragging:
		return

	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	var from = camera.project_ray_origin(screen_pos)
	var dir = camera.project_ray_normal(screen_pos)

	# Use first selected object as reference for drag plane
	var anchor = _selected_objects[0]
	if not is_instance_valid(anchor):
		return

	# Intersect with drag plane at table level (y=0) for XZ movement
	var drag_plane_at_table = Plane(Vector3.UP, 0)
	var intersection = drag_plane_at_table.intersects_ray(from, dir)

	if intersection:
		# Calculate movement delta in XZ only (from anchor's original XZ position)
		var anchor_start = _drag_start_positions.get(anchor, anchor.global_position)
		var delta_xz = Vector3(intersection.x - anchor_start.x, 0, intersection.z - anchor_start.z)

		# Move all selected objects by the same XZ delta, preserving their original Y
		for obj in _selected_objects:
			if is_instance_valid(obj):
				var obj_start = _drag_start_positions.get(obj, obj.global_position)
				var new_pos = Vector3(obj_start.x + delta_xz.x, obj_start.y, obj_start.z + delta_xz.z)
				obj.global_position = new_pos

		# Calculate horizontal distance for display
		var current_anchor_pos = anchor.global_position
		var horizontal_distance = _horizontal_distance(_drag_anchor_position, current_anchor_pos)
		var distance_inches = horizontal_distance * METERS_TO_INCHES

		# Update drag line visualization
		_update_drag_line(_drag_anchor_position, current_anchor_pos, distance_inches)

		# Emit distance
		distance_changed.emit(distance_inches, _drag_anchor_position, current_anchor_pos)


## Start measuring distance from a point on the table
func _start_measuring(screen_pos: Vector2) -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 100

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = true

	var result = space_state.intersect_ray(query)

	if result:
		_is_measuring = true
		# If hit an object, store reference and mark as snapped
		if result.collider.is_in_group("selectable"):
			_measure_start_object = result.collider
			_measure_start_position = result.collider.global_position
			_measure_start_position.y = 0.02  # Slightly above table for visibility
			_measure_start_snapped = true
		else:
			_measure_start_object = null
			_measure_start_position = result.position
			_measure_start_position.y = 0.02
			_measure_start_snapped = false

		# Create measurement line and label
		_create_measure_line()


## Update measurement line while dragging
func _update_measurement(screen_pos: Vector2) -> void:
	if not _is_measuring:
		return

	var end_data = _get_measure_end_position(screen_pos)
	if end_data:
		var end_center: Vector3 = end_data["position"]
		_measure_end_snapped = end_data["snapped"]
		_measure_end_object = end_data["object"]

		# Calculate edge positions for snapped objects
		var start_pos = _measure_start_position
		var end_pos = end_center

		# If start snapped to object, calculate edge closest to end
		if _measure_start_snapped and _measure_start_object:
			start_pos = _get_edge_position(_measure_start_object, _measure_start_position, end_center)

		# If end snapped to object, calculate edge closest to start
		if _measure_end_snapped and _measure_end_object:
			end_pos = _get_edge_position(_measure_end_object, end_center, _measure_start_position)

		# Calculate HORIZONTAL distance only (XZ plane) - edge to edge
		var distance_m = _horizontal_distance(start_pos, end_pos)
		var distance_inches = distance_m * METERS_TO_INCHES

		# Update line and label
		var both_snapped = _measure_start_snapped and _measure_end_snapped
		_update_measure_line(start_pos, end_pos, distance_inches, both_snapped)

		distance_changed.emit(distance_inches, start_pos, end_pos)


## Stop measuring and emit final result
func _stop_measuring(screen_pos: Vector2) -> void:
	if _is_measuring:
		var end_data = _get_measure_end_position(screen_pos)
		if end_data:
			var end_center: Vector3 = end_data["position"]
			var end_obj = end_data["object"]

			# Calculate edge positions
			var start_pos = _measure_start_position
			var end_pos = end_center

			if _measure_start_snapped and _measure_start_object:
				start_pos = _get_edge_position(_measure_start_object, _measure_start_position, end_center)

			if end_data["snapped"] and end_obj:
				end_pos = _get_edge_position(end_obj, end_center, _measure_start_position)

			# Calculate HORIZONTAL distance only - edge to edge
			var distance_m = _horizontal_distance(start_pos, end_pos)
			var distance_inches = distance_m * METERS_TO_INCHES
			measurement_finished.emit(distance_inches)

		# Clean up line and label
		if _measure_line:
			_measure_line.queue_free()
			_measure_line = null
		if _measure_label:
			_measure_label.queue_free()
			_measure_label = null

	_is_measuring = false
	_measure_start_position = Vector3.ZERO
	_measure_start_snapped = false
	_measure_end_snapped = false
	_measure_start_object = null
	_measure_end_object = null


## Get measurement end position - snaps to objects if hit
## Returns Dictionary with "position", "snapped", and "object" keys, or null
func _get_measure_end_position(screen_pos: Vector2) -> Variant:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return null

	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 100

	# First check if we hit an object
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = true

	var result = space_state.intersect_ray(query)

	if result:
		# If hit a selectable object, snap to its base position
		if result.collider.is_in_group("selectable"):
			var obj_pos = result.collider.global_position
			return {
				"position": Vector3(obj_pos.x, 0.02, obj_pos.z),
				"snapped": true,
				"object": result.collider
			}
		else:
			# Hit table or other surface - use that point
			return {
				"position": Vector3(result.position.x, 0.02, result.position.z),
				"snapped": false,
				"object": null
			}

	# Fallback: intersect with table plane
	var dir = camera.project_ray_normal(screen_pos)
	var table_plane = Plane(Vector3.UP, 0)
	var intersection = table_plane.intersects_ray(from, dir)
	if intersection:
		return {
			"position": Vector3(intersection.x, 0.02, intersection.z),
			"snapped": false,
			"object": null
		}

	return null


## Get the radius/size of an object for edge calculation
func _get_object_radius(obj: Node3D) -> float:
	if obj.is_in_group("miniature"):
		return MINIATURE_RADIUS  # 16mm = 0.016m
	elif obj.is_in_group("dice"):
		return 0.008  # Half of 16mm dice = 8mm diagonal approximation
	elif obj.is_in_group("terrain"):
		# Terrain is larger, estimate from typical sizes
		return 0.15  # 15cm average
	return 0.016  # Default to miniature size


## Calculate edge position on object closest to target point
func _get_edge_position(obj: Node3D, obj_center: Vector3, target_pos: Vector3) -> Vector3:
	var radius = _get_object_radius(obj)

	# Direction from object center to target (horizontal only)
	var dir = Vector3(target_pos.x - obj_center.x, 0, target_pos.z - obj_center.z)
	var dist = dir.length()

	if dist < 0.001:
		# Target is at center, pick arbitrary direction
		dir = Vector3(1, 0, 0)
	else:
		dir = dir.normalized()

	# Edge point is center + direction * radius
	var edge_pos = Vector3(obj_center.x + dir.x * radius, 0.02, obj_center.z + dir.z * radius)
	return edge_pos


## Calculate horizontal distance (XZ plane only, ignoring Y)
func _horizontal_distance(from_pos: Vector3, to_pos: Vector3) -> float:
	var dx = to_pos.x - from_pos.x
	var dz = to_pos.z - from_pos.z
	return sqrt(dx * dx + dz * dz)


## Create a visual line and label for measurement
func _create_measure_line() -> void:
	if _measure_line:
		_measure_line.queue_free()
	if _measure_label:
		_measure_label.queue_free()

	# Create line mesh
	_measure_line = MeshInstance3D.new()
	_measure_line.name = "MeasureLine"
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.YELLOW
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true  # Always visible
	_measure_line.material_override = material
	add_child(_measure_line)

	# Create 3D label for distance display (~2cm text height)
	# Not billboard - will be rotated to align with measurement line
	_measure_label = Label3D.new()
	_measure_label.name = "MeasureLabel"
	_measure_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED  # Align with line direction
	_measure_label.no_depth_test = true
	_measure_label.pixel_size = 0.001  # 1mm per pixel
	_measure_label.font_size = 24      # ~2.4cm text height
	_measure_label.outline_size = 8  # Thicker outline for better contrast
	_measure_label.modulate = Color.WHITE
	_measure_label.outline_modulate = Color.BLACK
	_measure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_measure_label)


## Update the measurement line mesh and label
func _update_measure_line(from_pos: Vector3, to_pos: Vector3, distance_inches: float, both_snapped: bool) -> void:
	if not _measure_line or not _measure_label:
		return

	# Calculate horizontal direction (XZ plane only)
	var direction = Vector3(to_pos.x - from_pos.x, 0, to_pos.z - from_pos.z)
	var length = direction.length()

	if length < 0.001:
		_measure_line.visible = false
		_measure_label.visible = false
		return

	_measure_line.visible = true
	_measure_label.visible = true

	# Create a thin flat box as line (horizontal on XZ plane)
	var line_mesh = BoxMesh.new()
	line_mesh.size = Vector3(length, 0.001, 0.002)  # Length along X, 1mm height, 2mm depth

	_measure_line.mesh = line_mesh

	# Position at midpoint, just above table surface
	var midpoint = (from_pos + to_pos) / 2
	midpoint.y = 0.005  # 0.5cm above table
	_measure_line.global_position = midpoint

	# Rotate to align with direction (rotation around Y axis)
	var angle = atan2(direction.x, direction.z)
	_measure_line.rotation = Vector3(0, angle + PI/2, 0)

	# Update label position (at midpoint, above line)
	_measure_label.global_position = Vector3(midpoint.x, 0.02, midpoint.z)  # 2cm above table
	_measure_label.text = "%.1f\"" % distance_inches

	# Rotate label to align with measurement line direction
	# Face along the line, tilted to be readable from above
	var label_angle = atan2(direction.x, direction.z)
	_measure_label.rotation = Vector3(-PI/2, label_angle, 0)  # Flat, facing up, aligned with line

	# Set line color based on snap status (label stays white)
	var line_color = Color.GREEN if both_snapped else Color.YELLOW

	# Update line material color
	var mat = _measure_line.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = line_color

	# Label stays white with black outline for best readability
	_measure_label.modulate = Color.WHITE


## Spawn a miniature at the given position
func spawn_miniature(pos: Vector3) -> Node3D:
	_object_counter += 1

	var miniature = StaticBody3D.new()
	miniature.name = "Miniature_%d" % _object_counter
	miniature.add_to_group("selectable")
	miniature.add_to_group("miniature")

	var base_height = 0.003  # 3mm base thickness

	# Create base (circular)
	var base_mesh = CylinderMesh.new()
	base_mesh.top_radius = MINIATURE_RADIUS
	base_mesh.bottom_radius = MINIATURE_RADIUS
	base_mesh.height = base_height

	var base_instance = MeshInstance3D.new()
	base_instance.mesh = base_mesh
	base_instance.position.y = base_height / 2

	var base_material = StandardMaterial3D.new()
	base_material.albedo_color = Color(0.1, 0.1, 0.1)
	base_instance.material_override = base_material
	miniature.add_child(base_instance)

	# Create simple model (cylinder as placeholder)
	var model_mesh = CylinderMesh.new()
	model_mesh.top_radius = MINIATURE_RADIUS * 0.4
	model_mesh.bottom_radius = MINIATURE_RADIUS * 0.6
	model_mesh.height = MINIATURE_HEIGHT

	var model_instance = MeshInstance3D.new()
	model_instance.mesh = model_mesh
	model_instance.position.y = MINIATURE_HEIGHT / 2 + base_height  # Above base

	var model_material = StandardMaterial3D.new()
	model_material.albedo_color = Color(randf(), randf(), randf())  # Random color
	model_instance.material_override = model_material
	miniature.add_child(model_instance)

	# Store material reference for selection highlight
	miniature.set_meta("model_material", model_material)
	miniature.set_meta("original_color", model_material.albedo_color)

	# Add collision
	var collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = MINIATURE_RADIUS
	shape.height = MINIATURE_HEIGHT + base_height
	collision.shape = shape
	collision.position.y = (MINIATURE_HEIGHT + base_height) / 2
	miniature.add_child(collision)

	# Set collision layers
	miniature.collision_layer = 1
	miniature.collision_mask = 1

	# Add selection methods
	miniature.set_script(preload("res://scripts/selectable_object.gd"))

	# IMPORTANT: Add to tree BEFORE setting global_position
	add_child(miniature)
	miniature.global_position = pos

	return miniature


## Spawn a D6 dice at the given position
func spawn_dice(pos: Vector3) -> RigidBody3D:
	_object_counter += 1

	var dice = RigidBody3D.new()
	dice.name = "Dice_%d" % _object_counter
	dice.add_to_group("selectable")
	dice.add_to_group("dice")
	dice.mass = 0.005  # 5 grams - realistic for 16mm plastic dice
	dice.collision_layer = 1
	dice.collision_mask = 1
	dice.physics_material_override = _create_dice_physics_material()

	# Physics settings - PURE JOLT, no custom damping
	# Default values: linear_damp=0, angular_damp=0 (Jolt handles everything)
	dice.linear_damp = 0.0
	dice.angular_damp = 0.0
	dice.can_sleep = true  # Allow physics to sleep when at rest
	dice.continuous_cd = false

	var dice_size = 0.016  # 16mm standard dice

	# Try to load 3D model, fallback to procedural
	var dice_body: Node3D = _load_dice_model()
	if dice_body:
		# Model is ~20mm, scale to 16mm
		dice_body.scale = Vector3(0.8, 0.8, 0.8)
		dice.add_child(dice_body)
		# Find mesh for material reference
		var mesh_instance = _find_mesh_instance(dice_body)
		if mesh_instance:
			dice.set_meta("model_material", mesh_instance.get_surface_override_material(0))
			dice.set_meta("original_color", Color.WHITE)
	else:
		# Fallback to procedural mesh
		var proc_mesh = _create_rounded_box_mesh(dice_size, dice_size * 0.12)
		dice.add_child(proc_mesh)
		dice.set_meta("model_material", proc_mesh.material_override)
		dice.set_meta("original_color", Color.WHITE)
		# Add pips only for procedural mesh
		_add_flat_pips(dice, dice_size)

	# Add collision (always needed)
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(dice_size, dice_size, dice_size)
	# No margin - testing pure Jolt defaults
	collision.shape = shape
	dice.add_child(collision)

	dice.set_script(preload("res://scripts/selectable_object.gd"))
	add_child(dice)
	dice.global_position = pos  # Set position AFTER adding to tree
	_dice_list.append(dice)

	_log_event("SPAWN %s at pos=(%.4f,%.4f,%.4f) mass=%.4f lin_damp=%.1f ang_damp=%.1f" % [
		dice.name, pos.x, pos.y, pos.z, dice.mass, dice.linear_damp, dice.angular_damp
	])

	return dice


## Load the 3D dice model from assets
func _load_dice_model() -> Node3D:
	var model_path = "res://assets/models/dice/d6_dice.glb"
	if ResourceLoader.exists(model_path):
		var scene = load(model_path)
		if scene:
			return scene.instantiate()
	return null


## Find MeshInstance3D in a node tree
func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var result = _find_mesh_instance(child)
		if result:
			return result
	return null


## Create a clean dice mesh - simple box with glossy material
## For true rounded corners, import a 3D model (glTF) from Blender
func _create_rounded_box_mesh(size: float, _radius: float) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	# Simple clean box
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(size, size, size)
	mesh_instance.mesh = box_mesh

	# Smooth white material with glossiness
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.95, 0.95)
	material.roughness = 0.15  # Glossy surface
	material.metallic = 0.0

	mesh_instance.material_override = material
	return mesh_instance


func _create_dice_physics_material() -> PhysicsMaterial:
	var mat = PhysicsMaterial.new()
	mat.bounce = 0.2  # Slight bounce for realistic feel
	mat.friction = 0.9  # High friction to stop rolling
	mat.rough = true  # Use rougher physics calculations
	return mat


## Add flat circular pips to each face of the dice
## Standard D6: opposite faces sum to 7 (1-6, 2-5, 3-4)
func _add_flat_pips(dice: RigidBody3D, size: float) -> void:
	var pip_material = StandardMaterial3D.new()
	pip_material.albedo_color = Color(0.08, 0.08, 0.08)  # Near black
	pip_material.roughness = 0.4
	pip_material.metallic = 0.0

	var pip_radius = size * 0.10  # Pip circle radius (~1.6mm for 16mm dice)
	var pip_depth = size * 0.01  # Very thin, proportional to dice
	var face_offset = size / 2 + size * 0.005  # Just above surface
	var pip_spacing = size * 0.28  # Distance between pips

	# Face 1 (top, +Y): single center pip
	_add_flat_pip(dice, Vector3(0, face_offset, 0), Vector3.UP, pip_radius, pip_depth, pip_material)

	# Face 6 (bottom, -Y): 6 pips in 2 columns of 3
	for col in [-1, 1]:
		for row in [-1, 0, 1]:
			_add_flat_pip(dice, Vector3(col * pip_spacing, -face_offset, row * pip_spacing), Vector3.DOWN, pip_radius, pip_depth, pip_material)

	# Face 2 (front, +Z): 2 pips diagonal
	_add_flat_pip(dice, Vector3(-pip_spacing, pip_spacing, face_offset), Vector3.BACK, pip_radius, pip_depth, pip_material)
	_add_flat_pip(dice, Vector3(pip_spacing, -pip_spacing, face_offset), Vector3.BACK, pip_radius, pip_depth, pip_material)

	# Face 5 (back, -Z): 5 pips (4 corners + center)
	_add_flat_pip(dice, Vector3(0, 0, -face_offset), Vector3.FORWARD, pip_radius, pip_depth, pip_material)
	for x in [-1, 1]:
		for y in [-1, 1]:
			_add_flat_pip(dice, Vector3(x * pip_spacing, y * pip_spacing, -face_offset), Vector3.FORWARD, pip_radius, pip_depth, pip_material)

	# Face 3 (right, +X): 3 pips diagonal
	_add_flat_pip(dice, Vector3(face_offset, 0, 0), Vector3.RIGHT, pip_radius, pip_depth, pip_material)
	_add_flat_pip(dice, Vector3(face_offset, pip_spacing, -pip_spacing), Vector3.RIGHT, pip_radius, pip_depth, pip_material)
	_add_flat_pip(dice, Vector3(face_offset, -pip_spacing, pip_spacing), Vector3.RIGHT, pip_radius, pip_depth, pip_material)

	# Face 4 (left, -X): 4 pips in corners
	for y in [-1, 1]:
		for z in [-1, 1]:
			_add_flat_pip(dice, Vector3(-face_offset, y * pip_spacing, z * pip_spacing), Vector3.LEFT, pip_radius, pip_depth, pip_material)


## Add a single flat circular pip (thin cylinder oriented to face normal)
func _add_flat_pip(parent: Node3D, pip_pos: Vector3, normal: Vector3, radius: float, depth: float, material: Material) -> void:
	var pip = MeshInstance3D.new()
	var cyl_mesh = CylinderMesh.new()
	cyl_mesh.top_radius = radius
	cyl_mesh.bottom_radius = radius
	cyl_mesh.height = depth
	cyl_mesh.radial_segments = 16  # Smooth circle
	cyl_mesh.rings = 1
	pip.mesh = cyl_mesh
	pip.material_override = material
	pip.position = pip_pos

	# Orient the flat cylinder to face outward from the dice face
	if normal == Vector3.UP:
		pass  # Default orientation is correct
	elif normal == Vector3.DOWN:
		pip.rotation_degrees.x = 180
	elif normal == Vector3.RIGHT:
		pip.rotation_degrees.z = -90
	elif normal == Vector3.LEFT:
		pip.rotation_degrees.z = 90
	elif normal == Vector3.BACK:
		pip.rotation_degrees.x = 90
	elif normal == Vector3.FORWARD:
		pip.rotation_degrees.x = -90

	parent.add_child(pip)


## Spawn terrain piece at the given position
func spawn_terrain(pos: Vector3) -> StaticBody3D:
	_object_counter += 1

	var terrain = StaticBody3D.new()
	terrain.name = "Terrain_%d" % _object_counter
	terrain.add_to_group("selectable")
	terrain.add_to_group("terrain")

	# Random terrain type
	var terrain_types = ["rock", "building", "tree"]
	var terrain_type = terrain_types[randi() % terrain_types.size()]

	var mesh: Mesh
	var height: float

	match terrain_type:
		"rock":
			mesh = _create_rock_mesh()
			height = 0.25
		"building":
			mesh = _create_building_mesh()
			height = 0.6
		"tree":
			mesh = _create_tree_mesh()
			height = 0.6
		_:
			mesh = BoxMesh.new()
			height = 0.3

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.position.y = height / 2

	var material = StandardMaterial3D.new()
	match terrain_type:
		"rock":
			material.albedo_color = Color(0.4, 0.4, 0.4)
		"building":
			material.albedo_color = Color(0.6, 0.5, 0.4)
		"tree":
			material.albedo_color = Color(0.2, 0.5, 0.2)

	mesh_instance.material_override = material
	terrain.add_child(mesh_instance)

	terrain.set_meta("model_material", material)
	terrain.set_meta("original_color", material.albedo_color)

	# Add collision based on terrain type
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	match terrain_type:
		"rock":
			shape.size = Vector3(0.4, height, 0.35)
		"building":
			shape.size = Vector3(0.5, height, 0.5)
		"tree":
			shape.size = Vector3(0.3, height, 0.3)
		_:
			shape.size = Vector3(0.3, height, 0.3)
	collision.shape = shape
	collision.position.y = height / 2
	terrain.add_child(collision)

	terrain.set_script(preload("res://scripts/selectable_object.gd"))

	# IMPORTANT: Add to tree BEFORE setting global_position
	add_child(terrain)
	terrain.global_position = pos

	return terrain


func _create_rock_mesh() -> Mesh:
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.4, 0.25, 0.35)  # Scaled up
	return mesh


func _create_building_mesh() -> Mesh:
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.5, 0.6, 0.5)  # Scaled up
	return mesh


func _create_tree_mesh() -> Mesh:
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.2
	mesh.bottom_radius = 0.08
	mesh.height = 0.6  # Scaled up
	return mesh


## Roll all dice on the table
func roll_all_dice() -> void:
	if _dice_list.is_empty():
		return

	_is_rolling = true
	_log_event("=== ROLL STARTED ===")

	for dice in _dice_list:
		if is_instance_valid(dice):
			var old_pos = dice.global_position
			# Lift dice above table (table top is at y=0.018)
			dice.global_position.y = 0.10  # 10cm above ground

			# Unfreeze and apply velocities
			dice.freeze = false
			dice.sleeping = false  # Wake up physics

			# Apply random velocity - good dice roll feel
			var lin_v = Vector3(
				randf_range(-0.4, 0.4),   # Horizontal spread
				randf_range(0.8, 1.5),    # Upward throw
				randf_range(-0.4, 0.4)    # Horizontal spread
			)
			var ang_v = Vector3(
				randf_range(-25, 25),     # More rotation
				randf_range(-25, 25),
				randf_range(-25, 25)
			)
			dice.linear_velocity = lin_v
			dice.angular_velocity = ang_v

			_log_event("  %s: lifted from y=%.4f to y=0.08, lin_v=(%.2f,%.2f,%.2f) ang_v=(%.1f,%.1f,%.1f)" % [
				dice.name, old_pos.y, lin_v.x, lin_v.y, lin_v.z, ang_v.x, ang_v.y, ang_v.z
			])

	# Wait for dice to settle, then read results
	await get_tree().create_timer(2.5).timeout
	_is_rolling = false
	_log_event("=== ROLL ENDED (2.5s elapsed) ===")
	_read_dice_results()


func _read_dice_results() -> void:
	var results: Array[int] = []
	var total: int = 0

	_log_event("--- READING DICE RESULTS ---")

	for dice in _dice_list:
		if is_instance_valid(dice):
			var result = _get_dice_top_face(dice)
			results.append(result)
			total += result

			var pos = dice.global_position
			var lin_speed = dice.linear_velocity.length()
			var ang_speed = dice.angular_velocity.length()
			_log_event("  %s: result=%d pos.y=%.4f lin_v=%.4f ang_v=%.2f sleeping=%s" % [
				dice.name, result, pos.y, lin_speed, ang_speed, str(dice.sleeping)
			])

	if not results.is_empty():
		_log_event("TOTAL: %d (results: %s)" % [total, str(results)])
		dice_rolled.emit(total, results)


func _get_dice_top_face(dice: RigidBody3D) -> int:
	# Find which face is pointing up
	var up = Vector3.UP
	var dice_up = dice.global_transform.basis.y
	var dice_right = dice.global_transform.basis.x
	var dice_forward = dice.global_transform.basis.z

	var dots = {
		1: dice_up.dot(up),
		6: (-dice_up).dot(up),
		3: dice_right.dot(up),
		4: (-dice_right).dot(up),
		2: dice_forward.dot(up),
		5: (-dice_forward).dot(up),
	}

	var max_dot = -2.0
	var result = 1

	for value in dots:
		if dots[value] > max_dot:
			max_dot = dots[value]
			result = value

	return result


## Clear all objects from the table
func clear_all_objects() -> void:
	for child in get_children():
		child.queue_free()

	_dice_list.clear()
	_selected_objects.clear()
	_object_counter = 0
