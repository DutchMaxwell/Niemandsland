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
signal context_menu_requested(screen_pos: Vector2, selected_objects: Array)

@export var drag_height: float = 0.5  # Drag height in meters
@export var rotation_speed_degrees: float = 2.0  # Degrees per second while R held
@export var min_drag_height: float = 0.01  # Minimum height above table when dragging
@export var drag_lift_height: float = 0.05  # Lift height when dragging (5cm)

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

# Selection mode control (can be disabled for map layout mode)
var selection_enabled: bool = true

# Clipboard for copy/paste
var _clipboard: Array[Node3D] = []  # Stores references to copied objects for duplication

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
var _measure_terrain_warning: Label3D = null  # Warning icon for terrain (⚠️ or 💀)
var _measure_los_warning: Label3D = null  # Warning icon for LOS blocking (🚫)

const METERS_TO_INCHES: float = 39.3701

# Network manager reference
var _network_manager: Node = null

# Terrain overlay reference (for terrain hints)
var terrain_overlay: Node3D = null

# Long-press for context menu
var _long_press_timer: float = 0.0
var _long_press_position: Vector2 = Vector2.ZERO
var _is_long_pressing: bool = false
var _long_press_object: Node3D = null
const LONG_PRESS_DURATION: float = 0.4  # Seconds to hold for context menu
const LONG_PRESS_MOVE_THRESHOLD: float = 10.0  # Pixels - cancel if moved more than this

# Preload resources (will be scenes in full version)
# Standard wargaming miniature sizes
const MINIATURE_HEIGHT: float = 0.032  # 32mm height
const MINIATURE_RADIUS: float = 0.016  # 32mm diameter base (16mm radius)


func _ready() -> void:
	_drag_plane = Plane(Vector3.UP, 0)
	_init_debug_log()

	# Get network manager reference (deferred to ensure scene is ready)
	call_deferred("_get_network_manager")


func _get_network_manager() -> void:
	_network_manager = get_node_or_null("/root/Main/NetworkManager")


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

	# Long-press timer for context menu
	if _is_long_pressing:
		_long_press_timer += delta
		if _long_press_timer >= LONG_PRESS_DURATION:
			_trigger_context_menu()
			_cancel_long_press()


## Checks if a GUI element is blocking input (e.g., modal dialog)
func _is_gui_blocking_input() -> bool:
	# Check if any modal Control is visible and covering the viewport
	var ui_layer = get_tree().root.find_child("UI", true, false)
	if ui_layer:
		# Check for WoundsDialog or other modal dialogs
		var wounds_dialog = ui_layer.find_child("WoundsDialog", false, false)
		if wounds_dialog and wounds_dialog is Control and wounds_dialog.visible:
			return true
	return false


func _input(event: InputEvent) -> void:
	# Skip if GUI is handling input (dialog open, etc.)
	if _is_gui_blocking_input():
		return

	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton

		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# Check if we're in custom zone editing mode
				if terrain_overlay and terrain_overlay.is_editing_custom_zones():
					# Add vertex at click position (snapped to 1" grid)
					var table_pos = _get_table_position_at_screen(mouse_event.position)
					if table_pos != Vector3.INF:
						terrain_overlay.add_custom_zone_vertex(table_pos)
					return  # Don't process normal click handling

				if mouse_event.shift_pressed:
					# Shift + Left-click starts measurement
					_start_measuring(mouse_event.position)
				else:
					# Start long-press detection and selection
					_start_long_press(mouse_event.position)
					_try_select_at_mouse(mouse_event.position, mouse_event.alt_pressed)
			else:
				# Mouse released - cancel long press and handle other actions
				_cancel_long_press()
				if _is_measuring:
					_stop_measuring(mouse_event.position)
				elif _is_box_selecting:
					_finish_box_selection(mouse_event.alt_pressed)
				else:
					_stop_dragging()

	elif event is InputEventMouseMotion:
		# Check if mouse moved too far during long press
		if _is_long_pressing:
			var distance = event.position.distance_to(_long_press_position)
			if distance > LONG_PRESS_MOVE_THRESHOLD:
				_cancel_long_press()

		if _is_dragging:
			_update_drag(event.position)
		elif _is_box_selecting:
			_update_box_selection(event.position)
		elif _is_measuring:
			_update_measurement(event.position)

	# Rotation: hold R key for continuous rotation - requires selection
	# Only activate if Shift is NOT pressed (Shift+R is for group rotation in main.gd)
	elif event.is_action_pressed("rotate_object") and _selected_objects.size() > 0:
		if not Input.is_key_pressed(KEY_SHIFT):
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
	# Skip selection if disabled (e.g., map layout mode)
	if not selection_enabled:
		return

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
			# Skip locked objects
			if is_object_locked(collider):
				return

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


## Public: Get currently selected objects
func get_selected_objects() -> Array[Node3D]:
	return _selected_objects.duplicate()


## Public: Select specific objects (replaces current selection)
func select_objects(objects: Array) -> void:
	_deselect_all()
	for obj in objects:
		if obj is Node3D and is_instance_valid(obj):
			_add_to_selection(obj)


## Start long-press detection for context menu
func _start_long_press(screen_pos: Vector2) -> void:
	_is_long_pressing = true
	_long_press_timer = 0.0
	_long_press_position = screen_pos


## Cancel long-press detection
func _cancel_long_press() -> void:
	_is_long_pressing = false
	_long_press_timer = 0.0


## Trigger the context menu after successful long-press
func _trigger_context_menu() -> void:
	if _selected_objects.is_empty():
		return

	# Stop any dragging
	if _is_dragging:
		_cancel_drag()

	# Emit context menu signal
	context_menu_requested.emit(_long_press_position, _selected_objects.duplicate())


## Apply highlight to an object to show it's selected
## Uses a visual ring overlay instead of material modification to avoid Godot material bugs
func _highlight_object(obj: Node3D) -> void:
	# Check if already highlighted
	if obj.get_node_or_null("SelectionHighlight"):
		return

	# Get base size for the highlight ring
	var base_radius = 0.016  # Default 32mm
	var game_unit = UnitUtils.get_game_unit(obj)
	if game_unit and game_unit.unit_properties:
		var oval_width = game_unit.unit_properties.get("base_size_oval_width", 0)
		var oval_length = game_unit.unit_properties.get("base_size_oval_length", 0)
		if oval_width > 0 and oval_length > 0:
			base_radius = (max(oval_width, oval_length) / 2.0) * 0.001
		else:
			var base_mm = game_unit.unit_properties.get("base_size_round", 32)
			base_radius = (base_mm / 2.0) * 0.001

	# Create highlight ring container
	var highlight = Node3D.new()
	highlight.name = "SelectionHighlight"

	# Create glowing torus ring around the base
	var ring = MeshInstance3D.new()
	ring.name = "Ring"
	var torus = TorusMesh.new()
	torus.inner_radius = base_radius + 0.001
	torus.outer_radius = base_radius + 0.004
	ring.mesh = torus

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.6, 1.0)
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat
	ring.position = Vector3(0, 0.003, 0)

	highlight.add_child(ring)
	obj.add_child(highlight)


## Remove highlight from an object
func _unhighlight_object(obj: Node3D) -> void:
	var highlight = obj.get_node_or_null("SelectionHighlight")
	if highlight:
		highlight.queue_free()


## Start box selection (drag rectangle to select multiple objects)
func _start_box_selection(screen_pos: Vector2, alt_pressed: bool) -> void:
	# Skip box selection if disabled (e.g., map layout mode)
	if not selection_enabled:
		return

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

	# Store start positions for all selected objects and lift them
	for obj in _selected_objects:
		if is_instance_valid(obj):
			_drag_start_positions[obj] = obj.global_position
			# For rigid bodies, make them kinematic while dragging
			if obj is RigidBody3D:
				obj.freeze = true
			# Lift object above the table surface
			obj.global_position.y += drag_lift_height

	# Use first selected object as anchor for distance calculation (using original position)
	if _selected_objects.size() > 0:
		_drag_anchor_position = _drag_start_positions[_selected_objects[0]]

	# Create drag visualization line
	_create_drag_line()


func _stop_dragging() -> void:
	if _is_dragging and not _selected_objects.is_empty():
		# Smoothly lower objects back down and re-enable physics for rigid bodies
		for obj in _selected_objects:
			if is_instance_valid(obj):
				# For static bodies, snap to table surface (y=0)
				# For rigid bodies, lower by lift height and let physics handle it
				var target_y: float
				if obj is RigidBody3D:
					target_y = obj.global_position.y - drag_lift_height
				else:
					# Static bodies snap to table surface
					target_y = 0.0

				var tween = create_tween()
				tween.set_ease(Tween.EASE_OUT)
				tween.set_trans(Tween.TRANS_QUAD)
				tween.tween_property(obj, "global_position:y", target_y, 0.2)
				# Re-enable physics after animation completes
				if obj is RigidBody3D:
					tween.tween_callback(func(): obj.freeze = false)

		# Emit final distance for anchor object
		if _selected_objects.size() > 0:
			var anchor = _selected_objects[0]
			if is_instance_valid(anchor):
				var final_pos = anchor.global_position
				# Use table surface level for distance calculation
				final_pos.y = 0.0
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

	# Check terrain along the drag path
	var terrain_warning_text = ""
	var terrain_warning_color = Color.WHITE
	var line_color = Color.CYAN  # Default drag line color

	if terrain_overlay and terrain_overlay.has_method("get_terrain_at_world_position"):
		# Sample terrain at multiple points along the line
		var num_samples = int(max(3, length * 20))  # At least 3 samples, more for longer lines
		var has_difficult = false
		var has_dangerous = false

		for i in range(num_samples):
			var t = float(i) / float(num_samples - 1)
			var sample_pos = from_pos.lerp(to_pos, t)
			var terrain_type = terrain_overlay.get_terrain_at_world_position(sample_pos)

			# TerrainType enum: NONE=0, RUINS=1, FOREST=2, CONTAINER=3, DANGEROUS=4
			if terrain_type == 2:  # FOREST (Difficult Terrain)
				has_difficult = true
			elif terrain_type == 4:  # DANGEROUS
				has_dangerous = true

		# Set warning based on terrain (Dangerous overrides Difficult)
		if has_dangerous:
			terrain_warning_text = "💀"
			terrain_warning_color = Color.RED
			line_color = Color.RED
		elif has_difficult:
			terrain_warning_text = "⚠️"
			terrain_warning_color = Color.ORANGE
			line_color = Color.ORANGE

	# Update line material color
	var mat = _drag_line.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = line_color

	# Update terrain warning label (smaller font than measurement mode)
	if terrain_warning_text != "":
		if not _measure_terrain_warning:
			_measure_terrain_warning = Label3D.new()
			_measure_terrain_warning.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_measure_terrain_warning.no_depth_test = true
			_measure_terrain_warning.font_size = 28  # Smaller than measurement mode
			add_child(_measure_terrain_warning)

		_measure_terrain_warning.visible = true
		_measure_terrain_warning.text = terrain_warning_text
		_measure_terrain_warning.modulate = terrain_warning_color
		# Position above the distance label
		_measure_terrain_warning.global_position = Vector3(midpoint.x, 0.06, midpoint.z)
	else:
		if _measure_terrain_warning:
			_measure_terrain_warning.visible = false


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

		# Move all selected objects by the same XZ delta, keeping them lifted
		for obj in _selected_objects:
			if is_instance_valid(obj):
				var obj_start = _drag_start_positions.get(obj, obj.global_position)
				# Keep object at lifted height (original Y + lift height)
				var new_pos = Vector3(obj_start.x + delta_xz.x, obj_start.y + drag_lift_height, obj_start.z + delta_xz.z)
				obj.global_position = new_pos

				# Broadcast position to other clients
				if _network_manager and _network_manager.is_multiplayer_active():
					if obj.has_meta("network_id"):
						var net_id = obj.get_meta("network_id")
						_network_manager.broadcast_move(net_id, new_pos)

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


## Get edge distance from center in a specific direction for an object.
## For oval bases, calculates actual ellipse edge distance.
## dir_x, dir_z should be normalized direction components.
func _get_edge_distance_in_direction(obj: Node3D, dir_x: float, dir_z: float) -> float:
	if not obj.is_in_group("miniature"):
		if obj.is_in_group("dice"):
			return 0.008
		elif obj.is_in_group("terrain"):
			return 0.015
		return 0.016

	var game_unit = obj.get_meta("game_unit", null) as GameUnit
	if not game_unit or not game_unit.unit_properties:
		return MINIATURE_RADIUS

	var props = game_unit.unit_properties

	if props.get("base_is_oval", false):
		# Oval base - calculate actual ellipse edge distance
		var width_mm = props.get("base_width_mm", 32)
		var depth_mm = props.get("base_depth_mm", 32)
		var a = (width_mm / 2.0) * 0.001  # Semi-axis X (width/2) in meters
		var b = (depth_mm / 2.0) * 0.001  # Semi-axis Z (depth/2) in meters

		# Distance to ellipse edge in direction (dir_x, dir_z):
		# r = (a * b) / sqrt(b² * dir_x² + a² * dir_z²)
		var denominator = sqrt(b * b * dir_x * dir_x + a * a * dir_z * dir_z)
		if denominator < 0.0001:
			return (a + b) / 2.0  # Fallback to average
		return (a * b) / denominator
	else:
		# Round base - simple radius
		var base_mm = props.get("base_size_round", 32)
		return (base_mm / 2.0) * 0.001


## Calculate edge position on object closest to target point
func _get_edge_position(obj: Node3D, obj_center: Vector3, target_pos: Vector3) -> Vector3:
	# Direction from object center to target (horizontal only)
	var dir = Vector3(target_pos.x - obj_center.x, 0, target_pos.z - obj_center.z)
	var dist = dir.length()

	if dist < 0.001:
		# Target is at center, pick arbitrary direction
		dir = Vector3(1, 0, 0)
	else:
		dir = dir.normalized()

	# Get edge distance in this direction (handles oval bases)
	var edge_dist = _get_edge_distance_in_direction(obj, dir.x, dir.z)

	# Edge point is center + direction * edge_distance
	var edge_pos = Vector3(obj_center.x + dir.x * edge_dist, 0.02, obj_center.z + dir.z * edge_dist)
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

	# Update line material color (green if both ends snapped, yellow otherwise)
	var line_color = Color.GREEN if both_snapped else Color.YELLOW

	# Check LOS blocking along the measurement path
	var los_blocked = false
	if terrain_overlay and terrain_overlay.has_method("get_terrain_at_world_position") and terrain_overlay.has_method("is_terrain_los_blocking"):
		# Sample terrain at multiple points along the line
		var num_samples = int(max(5, length * 30))  # More samples for accurate LOS check

		for i in range(num_samples):
			var t = float(i) / float(num_samples - 1)
			var sample_pos = from_pos.lerp(to_pos, t)
			var terrain_type = terrain_overlay.get_terrain_at_world_position(sample_pos)

			if terrain_type != 0:  # Not NONE
				# Check if viewer or target is in the same terrain
				var viewer_in_terrain = (i == 0)  # First sample is viewer
				var target_in_terrain = (i == num_samples - 1)  # Last sample is target

				# For intermediate samples, assume neither is in terrain
				if terrain_overlay.is_terrain_los_blocking(terrain_type, viewer_in_terrain, target_in_terrain):
					los_blocked = true
					line_color = Color.RED  # Change line to red if LOS is blocked
					break

	var mat = _measure_line.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = line_color

	# Show LOS blocking warning if blocked
	if los_blocked:
		if not _measure_los_warning:
			_measure_los_warning = Label3D.new()
			_measure_los_warning.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_measure_los_warning.no_depth_test = true
			_measure_los_warning.font_size = 32
			add_child(_measure_los_warning)

		_measure_los_warning.visible = true
		_measure_los_warning.text = "🚫"  # Blocked symbol
		_measure_los_warning.modulate = Color.RED
		# Position slightly higher than other labels
		_measure_los_warning.global_position = Vector3(midpoint.x, 0.08, midpoint.z)
	else:
		if _measure_los_warning:
			_measure_los_warning.visible = false

	# Label stays white with black outline for best readability
	_measure_label.modulate = Color.WHITE


## Spawn a miniature at the given position
## If broadcast is true and multiplayer is active, syncs to other clients
func spawn_miniature(pos: Vector3, broadcast: bool = true, network_id: int = -1) -> Node3D:
	_object_counter += 1

	# Generate network ID if not provided
	var obj_network_id = network_id if network_id >= 0 else _object_counter

	var miniature = StaticBody3D.new()
	miniature.name = "Miniature_%d" % _object_counter
	miniature.set_meta("network_id", obj_network_id)
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

	# Enable shadow casting for base
	base_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

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

	# Broadcast to other clients if in multiplayer
	if broadcast and _network_manager and _network_manager.is_multiplayer_active():
		_network_manager.broadcast_spawn("miniature", pos, obj_network_id)

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
## If broadcast is true and multiplayer is active, syncs to other clients
func spawn_terrain(pos: Vector3, broadcast: bool = true, network_id: int = -1) -> StaticBody3D:
	_object_counter += 1

	# Generate network ID if not provided
	var obj_network_id = network_id if network_id >= 0 else _object_counter + 10000  # Offset to avoid conflicts

	var terrain = StaticBody3D.new()
	terrain.name = "Terrain_%d" % _object_counter
	terrain.set_meta("network_id", obj_network_id)
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
			height = 0.25  # 25cm
		"building":
			mesh = _create_building_mesh()
			height = 0.6  # 60cm
		"tree":
			mesh = _create_tree_mesh()
			height = 0.6  # 60cm
		_:
			mesh = BoxMesh.new()
			height = 0.3  # 30cm

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

	# Broadcast to other clients if in multiplayer
	if broadcast and _network_manager and _network_manager.is_multiplayer_active():
		_network_manager.broadcast_spawn("terrain", pos, obj_network_id)

	return terrain


## Load and spawn a custom 3D model from GLB/GLTF/STL file
func spawn_custom_model(file_path: String, pos: Vector3, _broadcast: bool = true) -> Node3D:
	_object_counter += 1
	var obj_network_id = _object_counter + 20000  # Offset for custom models

	var model_scene: Node3D = null
	var extension = file_path.get_extension().to_lower()

	# Load based on file type (no base - we add our own below)
	match extension:
		"glb", "gltf":
			model_scene = _load_gltf_model(file_path, false)
		"stl":
			model_scene = _load_stl_model(file_path)
		"obj":
			model_scene = _load_obj_model(file_path, "", false)
		"fbx":
			# FBX cannot be loaded at runtime - Godot converts it during import
			push_warning("FBX files must be converted to GLB first. Use Blender or import into Godot project.")
			print("FBX Runtime-Import nicht möglich. Bitte zuerst zu GLB konvertieren:")
			print("  - Blender: File > Import FBX, dann File > Export > glTF 2.0 (.glb)")
			print("  - Oder die FBX-Datei ins Godot-Projekt ziehen (wird automatisch konvertiert)")
			return null
		_:
			push_error("Unsupported model format: %s" % extension)
			return null

	if not model_scene:
		return null

	# Wrap in StaticBody3D for selection/collision
	var wrapper = StaticBody3D.new()
	wrapper.name = "CustomModel_%d" % _object_counter
	wrapper.set_meta("network_id", obj_network_id)
	wrapper.set_meta("model_path", file_path)
	wrapper.add_to_group("selectable")
	wrapper.add_to_group("custom_model")

	# Add the loaded model as child
	wrapper.add_child(model_scene)

	# Calculate bounding box for collision BEFORE adding base
	var aabb = _calculate_aabb(model_scene)
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = aabb.size
	collision.shape = shape
	collision.position = aabb.position + aabb.size / 2
	wrapper.add_child(collision)

	# Scale to reasonable size (target ~5cm height for miniatures)
	var max_dim = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
	var scale_factor = 1.0
	if max_dim > 0.001:
		var target_size = 0.05  # 5cm default target size
		scale_factor = target_size / max_dim
		model_scene.scale = Vector3(scale_factor, scale_factor, scale_factor)

	# Add 32mm base for custom models
	var base = _create_miniature_base()
	wrapper.add_child(base)

	# Position model so its bottom sits on top of base
	# The scaled AABB's lowest point (position.y) must be at base_height
	var base_height = 0.003  # 3mm base height
	var scaled_aabb_min_y = aabb.position.y * scale_factor
	model_scene.position.y = base_height - scaled_aabb_min_y

	# Update collision to include base + model
	var base_radius = 0.016  # 32mm diameter (16mm radius)
	var scaled_model_height = aabb.size.y * scale_factor
	var total_height = scaled_model_height + base_height
	shape.size = Vector3(base_radius * 2, total_height, base_radius * 2)
	collision.position = Vector3(0, total_height / 2, 0)

	# Enable shadows for model
	_enable_shadows_recursive(wrapper)

	wrapper.set_script(preload("res://scripts/selectable_object.gd"))

	# Add to scene
	add_child(wrapper)
	wrapper.global_position = pos

	print("Loaded custom model: %s" % file_path.get_file())
	return wrapper


## Load a GLB/GLTF model with optional 32mm base
func _load_gltf_model(file_path: String, add_base: bool = true) -> Node3D:
	var gltf_doc = GLTFDocument.new()
	var gltf_state = GLTFState.new()

	var error = gltf_doc.append_from_file(file_path, gltf_state)
	if error != OK:
		push_error("Failed to load GLTF: %s (error %d)" % [file_path, error])
		return null

	var model_scene = gltf_doc.generate_scene(gltf_state)
	if not model_scene:
		push_error("Failed to generate scene from GLTF: %s" % file_path)
		return null

	# If base not needed, return model as-is
	if not add_base:
		return model_scene

	# Wrap in Node3D with base
	var root = Node3D.new()
	root.name = "GLTF_Model"

	# Add wargaming base
	var base = _create_miniature_base()
	root.add_child(base)

	# Calculate model bounds to position it on top of base
	var aabb = _calculate_aabb(model_scene)
	var base_top = 0.003  # 3mm base height

	# Position model so its bottom sits on top of base
	model_scene.position.y = base_top - aabb.position.y

	root.add_child(model_scene)

	# Enable shadow casting for all meshes
	_enable_shadows_recursive(root)

	print("Loaded GLTF with 32mm base: %s" % file_path.get_file())
	return root


## Load an STL model (binary or ASCII) with automatic base
func _load_stl_model(file_path: String) -> Node3D:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open STL file: %s" % file_path)
		return null

	var mesh: ArrayMesh = null

	# Check if binary or ASCII STL
	var header = file.get_buffer(80)
	var header_str = header.get_string_from_ascii()

	# Reset to start
	file.seek(0)

	if header_str.begins_with("solid") and not _is_binary_stl(file):
		mesh = _parse_ascii_stl(file)
	else:
		mesh = _parse_binary_stl(file)

	file.close()

	if not mesh:
		push_error("Failed to parse STL: %s" % file_path)
		return null

	# Create mesh instance with default material
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh

	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.7, 0.7)  # Default gray
	material.roughness = 0.5
	material.metallic = 0.0
	mesh_instance.material_override = material

	# Return mesh instance directly (base will be added by spawn_custom_model)
	# Enable shadow casting
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	return mesh_instance


## Create a standard wargaming base (32mm diameter)
func _create_miniature_base() -> MeshInstance3D:
	var base_radius = 0.016  # 16mm radius = 32mm diameter base
	var base_height = 0.003  # 3mm height

	var base_mesh = CylinderMesh.new()
	base_mesh.top_radius = base_radius
	base_mesh.bottom_radius = base_radius
	base_mesh.height = base_height

	var base_instance = MeshInstance3D.new()
	base_instance.mesh = base_mesh
	base_instance.name = "Base"

	# Position base so top is at y=0 (model sits on top)
	base_instance.position.y = base_height / 2

	# Black material for base
	var base_material = StandardMaterial3D.new()
	base_material.albedo_color = Color(0.1, 0.1, 0.1)  # Dark black
	base_material.roughness = 0.8
	base_instance.material_override = base_material

	# IMPORTANT: Enable shadow casting for the base!
	base_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	return base_instance


## Check if STL is binary (some ASCII files start with "solid" but are binary)
func _is_binary_stl(file: FileAccess) -> bool:
	# Binary STL: 80 byte header + 4 byte triangle count
	# Check if file size matches expected binary size
	var file_size = file.get_length()
	file.seek(80)
	var tri_count = file.get_32()
	file.seek(0)

	# Binary: 80 + 4 + (50 * tri_count)
	var expected_size = 84 + (50 * tri_count)
	return abs(file_size - expected_size) < 10  # Allow small tolerance


## Parse binary STL file
func _parse_binary_stl(file: FileAccess) -> ArrayMesh:
	# Skip 80 byte header
	file.seek(80)

	var tri_count = file.get_32()
	if tri_count == 0 or tri_count > 10000000:  # Sanity check
		push_error("Invalid triangle count in STL: %d" % tri_count)
		return null

	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()

	vertices.resize(tri_count * 3)
	normals.resize(tri_count * 3)

	for i in range(tri_count):
		# Read normal (3 floats)
		var nx = file.get_float()
		var ny = file.get_float()
		var nz = file.get_float()
		var normal = Vector3(nx, ny, nz)

		# Read 3 vertices
		for v in range(3):
			var x = file.get_float()
			var y = file.get_float()
			var z = file.get_float()
			vertices[i * 3 + v] = Vector3(x, y, z)
			normals[i * 3 + v] = normal

		# Skip attribute byte count (2 bytes)
		file.get_16()

	# Create mesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	print("Loaded binary STL: %d triangles" % tri_count)
	return mesh


## Parse ASCII STL file
func _parse_ascii_stl(file: FileAccess) -> ArrayMesh:
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var current_normal = Vector3.UP

	var content = file.get_as_text()
	var lines = content.split("\n")

	for line in lines:
		line = line.strip_edges().to_lower()

		if line.begins_with("facet normal"):
			var parts = line.split(" ")
			if parts.size() >= 5:
				current_normal = Vector3(
					float(parts[2]),
					float(parts[3]),
					float(parts[4])
				)

		elif line.begins_with("vertex"):
			var parts = line.split(" ")
			if parts.size() >= 4:
				var vertex = Vector3(
					float(parts[1]),
					float(parts[2]),
					float(parts[3])
				)
				vertices.append(vertex)
				normals.append(current_normal)

	if vertices.size() == 0:
		return null

	# Create mesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	@warning_ignore("integer_division")
	print("Loaded ASCII STL: %d triangles" % (vertices.size() / 3))
	return mesh


## Load an OBJ model (Wavefront format) with optional texture support
## texture_path: Optional path to a texture file (PNG, JPG, etc.)
## add_base: If true, adds a 32mm wargaming base under the model
func _load_obj_model(file_path: String, texture_path: String = "", add_base: bool = true) -> Node3D:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open OBJ file: %s" % file_path)
		return null

	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var uvs: Array[Vector2] = []  # Texture coordinates
	var mesh_vertices = PackedVector3Array()
	var mesh_normals = PackedVector3Array()
	var mesh_uvs = PackedVector2Array()  # UV array for mesh

	var content = file.get_as_text()
	file.close()

	var lines = content.split("\n")

	for line in lines:
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue

		var parts = line.split(" ", false)  # Split by space, skip empty
		if parts.size() < 2:
			continue

		match parts[0]:
			"v":  # Vertex position
				if parts.size() >= 4:
					vertices.append(Vector3(
						float(parts[1]),
						float(parts[2]),
						float(parts[3])
					))
			"vt":  # Texture coordinate (UV)
				if parts.size() >= 3:
					uvs.append(Vector2(
						float(parts[1]),
						1.0 - float(parts[2])  # Flip V coordinate (OBJ uses bottom-left origin)
					))
			"vn":  # Vertex normal
				if parts.size() >= 4:
					normals.append(Vector3(
						float(parts[1]),
						float(parts[2]),
						float(parts[3])
					))
			"f":  # Face
				var face_verts: Array[int] = []
				var face_uvs: Array[int] = []
				var face_normals: Array[int] = []

				for i in range(1, parts.size()):
					var indices = parts[i].split("/")
					# OBJ indices are 1-based
					var v_idx = int(indices[0]) - 1
					face_verts.append(v_idx)

					# UV index (v/vt/vn format)
					if indices.size() >= 2 and not indices[1].is_empty():
						var uv_idx = int(indices[1]) - 1
						face_uvs.append(uv_idx)
					else:
						face_uvs.append(-1)

					# Normal index (v/vt/vn format)
					if indices.size() >= 3 and not indices[2].is_empty():
						var n_idx = int(indices[2]) - 1
						face_normals.append(n_idx)
					else:
						face_normals.append(-1)

				# Triangulate face (fan triangulation)
				for i in range(1, face_verts.size() - 1):
					var tri_indices = [0, i, i + 1]
					for ti in tri_indices:
						var v_idx = face_verts[ti]
						if v_idx >= 0 and v_idx < vertices.size():
							mesh_vertices.append(vertices[v_idx])

							# Use UV if available
							var uv_idx = face_uvs[ti] if ti < face_uvs.size() else -1
							if uv_idx >= 0 and uv_idx < uvs.size():
								mesh_uvs.append(uvs[uv_idx])
							else:
								mesh_uvs.append(Vector2.ZERO)

							# Use normal if available
							var n_idx = face_normals[ti] if ti < face_normals.size() else -1
							if n_idx >= 0 and n_idx < normals.size():
								mesh_normals.append(normals[n_idx])
							else:
								mesh_normals.append(Vector3.UP)

	if mesh_vertices.size() == 0:
		push_error("No geometry found in OBJ: %s" % file_path)
		return null

	# Check if we have valid normals from the OBJ file
	# The shader handles backface lighting, so we just need normals to exist
	var has_valid_normals = false
	for i in range(mesh_normals.size()):
		if mesh_normals[i].length_squared() > 0.0001:
			has_valid_normals = true
			break

	if not has_valid_normals:
		# No valid normals in file, calculate from geometry
		print("  No normals in OBJ, calculating from geometry")
		mesh_normals = _calculate_smooth_normals(mesh_vertices)

	# Create mesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh_vertices
	arrays[Mesh.ARRAY_NORMAL] = mesh_normals
	if mesh_uvs.size() == mesh_vertices.size():
		arrays[Mesh.ARRAY_TEX_UV] = mesh_uvs

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Create mesh instance
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh

	# Create shader material with two-sided lighting
	# This flips normals for backfaces so both sides are lit correctly
	# (TTS/Unity does this automatically, Godot requires a shader)
	var shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool use_texture = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;

void fragment() {
	// Ensure normal always faces the camera for proper lighting
	// VIEW points FROM camera TO fragment in Godot
	// So if dot(NORMAL, VIEW) > 0, they point same direction = normal faces away
	// In that case, flip the normal to face the camera
	if (dot(NORMAL, VIEW) > 0.0) {
		NORMAL = -NORMAL;
	}

	if (use_texture) {
		ALBEDO = texture(albedo_texture, UV).rgb * albedo_color.rgb;
	} else {
		ALBEDO = albedo_color.rgb;
	}
	ROUGHNESS = roughness;
}
"""

	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("albedo_color", Color(0.7, 0.7, 0.7))
	material.set_shader_parameter("roughness", 0.9)
	material.set_shader_parameter("use_texture", false)

	# Load texture if provided
	if not texture_path.is_empty():
		var texture = _load_texture(texture_path)
		if texture:
			material.set_shader_parameter("albedo_texture", texture)
			material.set_shader_parameter("albedo_color", Color.WHITE)
			material.set_shader_parameter("use_texture", true)
			print("Applied texture: %s" % texture_path.get_file())

	mesh_instance.material_override = material

	# Wrap in Node3D
	var root = Node3D.new()
	root.name = "OBJ_Model"

	if add_base:
		# Add wargaming base
		var base = _create_miniature_base()
		root.add_child(base)

		# Position mesh on top of base
		var mesh_aabb = mesh.get_aabb()
		var base_top = 0.003
		mesh_instance.position.y = base_top - mesh_aabb.position.y
	else:
		# No base - just use mesh as-is
		mesh_instance.position.y = 0

	root.add_child(mesh_instance)

	# Enable shadow casting for all meshes
	_enable_shadows_recursive(root)

	var uv_info = " with UVs" if mesh_uvs.size() > 0 else ""
	@warning_ignore("integer_division")
	print("Loaded OBJ: %d triangles%s" % [mesh_vertices.size() / 3, uv_info])
	return root


## Load a texture from file path (supports PNG, JPG, WEBP)
## Detects format from file content (magic bytes), not extension
func _load_texture(texture_path: String) -> ImageTexture:
	if not FileAccess.file_exists(texture_path):
		push_warning("Texture file not found: %s" % texture_path)
		return null

	# Read file content
	var file = FileAccess.open(texture_path, FileAccess.READ)
	if not file:
		push_warning("Failed to open texture file: %s" % texture_path)
		return null

	var buffer = file.get_buffer(file.get_length())
	file.close()

	if buffer.size() < 12:
		push_warning("Texture file too small: %s" % texture_path)
		return null

	# Detect format from magic bytes (file signature)
	var image = Image.new()
	var error: Error = ERR_FILE_UNRECOGNIZED

	# PNG: 89 50 4E 47 0D 0A 1A 0A (first 8 bytes)
	if buffer[0] == 0x89 and buffer[1] == 0x50 and buffer[2] == 0x4E and buffer[3] == 0x47:
		error = image.load_png_from_buffer(buffer)
	# JPEG: FF D8 FF (first 3 bytes)
	elif buffer[0] == 0xFF and buffer[1] == 0xD8 and buffer[2] == 0xFF:
		error = image.load_jpg_from_buffer(buffer)
	# WebP: RIFF....WEBP (bytes 0-3 = RIFF, bytes 8-11 = WEBP)
	elif buffer[0] == 0x52 and buffer[1] == 0x49 and buffer[2] == 0x46 and buffer[3] == 0x46:
		if buffer.size() >= 12 and buffer[8] == 0x57 and buffer[9] == 0x45 and buffer[10] == 0x42 and buffer[11] == 0x50:
			error = image.load_webp_from_buffer(buffer)
	# BMP: 42 4D (BM)
	elif buffer[0] == 0x42 and buffer[1] == 0x4D:
		error = image.load_bmp_from_buffer(buffer)
	# TGA: Try as fallback (no reliable magic bytes)
	else:
		# Try TGA as last resort
		error = image.load_tga_from_buffer(buffer)

	if error != OK:
		# Log the magic bytes for debugging
		var magic = "%02X %02X %02X %02X" % [buffer[0], buffer[1], buffer[2], buffer[3]]
		push_warning("Failed to load texture: %s (error %d, magic: %s)" % [texture_path, error, magic])
		return null

	# Generate mipmaps for better rendering at distance
	image.generate_mipmaps()

	var texture = ImageTexture.create_from_image(image)
	return texture


## Enable shadow casting for all MeshInstance3D nodes recursively
func _enable_shadows_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	for child in node.get_children():
		_enable_shadows_recursive(child)


## Calculate smooth normals for a mesh (vertex normals averaged from face normals)
## Uses centroid-based detection to ensure normals point outward
func _calculate_smooth_normals(vertices: PackedVector3Array) -> PackedVector3Array:
	var normals = PackedVector3Array()
	normals.resize(vertices.size())

	# Initialize all normals to zero
	for i in range(normals.size()):
		normals[i] = Vector3.ZERO

	@warning_ignore("integer_division")
	var tri_count = vertices.size() / 3

	if tri_count == 0:
		return normals

	# Calculate mesh centroid (average of all vertices)
	var centroid = Vector3.ZERO
	for i in range(vertices.size()):
		centroid += vertices[i]
	centroid /= vertices.size()

	# Calculate face normals, ensuring they point outward from centroid
	var flipped_count = 0

	for i in range(tri_count):
		var idx0 = i * 3
		var idx1 = i * 3 + 1
		var idx2 = i * 3 + 2

		var v0 = vertices[idx0]
		var v1 = vertices[idx1]
		var v2 = vertices[idx2]

		# Calculate face center
		var face_center = (v0 + v1 + v2) / 3.0

		# Calculate face normal using cross product
		var edge1 = v1 - v0
		var edge2 = v2 - v0
		var face_normal = edge1.cross(edge2).normalized()

		# Check if normal points outward (away from centroid)
		# The vector from centroid to face center should align with normal
		var outward_dir = (face_center - centroid).normalized()
		if face_normal.dot(outward_dir) < 0:
			# Normal is pointing inward, flip it
			face_normal = -face_normal
			flipped_count += 1

		# Add face normal to all three vertices of this triangle
		normals[idx0] += face_normal
		normals[idx1] += face_normal
		normals[idx2] += face_normal

	# Normalize all vertex normals
	for i in range(normals.size()):
		if normals[i].length_squared() > 0.0001:
			normals[i] = normals[i].normalized()
		else:
			normals[i] = Vector3.UP  # Fallback for degenerate cases

	if flipped_count > 0:
		print("  Fixed %d/%d inverted face normals" % [flipped_count, tri_count])

	return normals


## Calculate AABB for a node and all its children
func _calculate_aabb(node: Node3D) -> AABB:
	var aabb = AABB()
	var found_mesh = false

	for child in node.get_children():
		if child is MeshInstance3D:
			# Get local AABB and transform by child's position/scale
			var mesh_aabb = child.get_aabb()
			# Apply child's transform to the AABB
			var transformed_aabb = AABB(
				mesh_aabb.position * child.scale + child.position,
				mesh_aabb.size * child.scale
			)
			if not found_mesh:
				aabb = transformed_aabb
				found_mesh = true
			else:
				aabb = aabb.merge(transformed_aabb)

		if child is Node3D:
			var child_aabb = _calculate_aabb(child)
			if child_aabb.size.length() > 0:
				# Transform child AABB by child's position/scale
				var transformed_aabb = AABB(
					child_aabb.position * child.scale + child.position,
					child_aabb.size * child.scale
				)
				if not found_mesh:
					aabb = transformed_aabb
					found_mesh = true
				else:
					aabb = aabb.merge(transformed_aabb)

	# Default if nothing found
	if not found_mesh:
		aabb = AABB(Vector3(-0.025, 0, -0.025), Vector3(0.05, 0.05, 0.05))

	return aabb


func _create_rock_mesh() -> Mesh:
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.4, 0.25, 0.35)  # Rock dimensions
	return mesh


func _create_building_mesh() -> Mesh:
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.5, 0.6, 0.5)  # Building dimensions
	return mesh


func _create_tree_mesh() -> Mesh:
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.2  # Tree crown radius
	mesh.bottom_radius = 0.08  # Tree trunk radius
	mesh.height = 0.6  # Tree height
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
## If broadcast is true and multiplayer is active, syncs to other clients
func clear_all_objects(broadcast: bool = true) -> void:
	# Broadcast to other clients if in multiplayer (before clearing locally)
	if broadcast and _network_manager and _network_manager.is_multiplayer_active():
		_network_manager.broadcast_clear()

	for child in get_children():
		child.queue_free()

	_dice_list.clear()
	_selected_objects.clear()
	_object_counter = 0


## ============================================================================
## TTS (Tabletop Simulator) Import Functions
## ============================================================================

## Import models from a TTS save file with textures from cache directories
## json_path: Path to the TTS save JSON file
## models_cache_dir: Path to TTS Models/ cache directory
## images_cache_dir: Path to TTS Images/ cache directory
## Returns: Array of imported objects
func import_tts_save(json_path: String, models_cache_dir: String, images_cache_dir: String) -> Array[Node3D]:
	var imported_objects: Array[Node3D] = []

	# Parse the TTS save file
	var parse_result = TTSImporter.parse_tts_save(json_path)
	if not parse_result.error.is_empty():
		push_error("TTS Import failed: %s" % parse_result.error)
		return imported_objects

	# Get unique models (avoid importing duplicates)
	var unique_models = TTSImporter.get_unique_models(parse_result)

	print("=== TTS Import Starting ===")
	print("Save: %s" % parse_result.save_name)
	print("Unique models to import: %d" % unique_models.size())

	# Import each unique model
	var success_count = 0
	var fail_count = 0

	for tts_obj in unique_models:
		var imported = _import_tts_object(tts_obj, models_cache_dir, images_cache_dir)
		if imported:
			imported_objects.append(imported)
			success_count += 1
		else:
			fail_count += 1

	print("=== TTS Import Complete ===")
	print("Success: %d | Failed: %d" % [success_count, fail_count])

	return imported_objects


## Import a single TTS object
func _import_tts_object(tts_obj: TTSImporter.TTSObject, models_dir: String, images_dir: String) -> Node3D:
	# Find the mesh file in cache
	var mesh_path = TTSImporter.find_cache_file(tts_obj.mesh_url, models_dir, [".obj", ".OBJ"])
	if mesh_path.is_empty():
		print("  [SKIP] %s - mesh not found in cache" % tts_obj.name)
		return null

	# Find texture file if URL is specified
	var texture_path = ""
	if not tts_obj.diffuse_url.is_empty():
		texture_path = TTSImporter.find_cache_file(tts_obj.diffuse_url, images_dir, [".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG"])

	# Load the model (no base for TTS imports - they're often bases themselves)
	var extension = mesh_path.get_extension().to_lower()
	var model_scene: Node3D = null

	match extension:
		"obj":
			model_scene = _load_obj_model(mesh_path, texture_path, false)  # No auto-base
		_:
			push_warning("Unsupported TTS mesh format: %s" % extension)
			return null

	if not model_scene:
		print("  [FAIL] %s - could not load mesh" % tts_obj.name)
		return null

	# Calculate model bounds to determine appropriate scale
	var mesh_aabb = _calculate_aabb(model_scene)
	var max_dim = max(mesh_aabb.size.x, max(mesh_aabb.size.y, mesh_aabb.size.z))

	# TTS OBJ files seem to be in a unit where models are ~100-1000x too large
	# We'll scale based on max dimension to get reasonable table-sized objects
	# Target: largest dimension should be ~0.1m (10cm) for most bases
	var model_scale = 0.001  # Default: assume OBJ is in mm
	if max_dim > 1.0:
		# Model is in larger units - scale it down to table size
		model_scale = 0.1 / max_dim  # Target 10cm max dimension
	model_scene.scale = Vector3(model_scale, model_scale, model_scale)

	print("    Scale: %.6f (raw max dim: %.2f)" % [model_scale, max_dim])

	# Calculate scaled AABB for collision and positioning
	var scaled_aabb = AABB(mesh_aabb.position * model_scale, mesh_aabb.size * model_scale)

	# Position model so its bottom sits on table surface (y=0)
	model_scene.position.y = -scaled_aabb.position.y

	# Wrap in StaticBody3D for selection
	_object_counter += 1
	var wrapper = StaticBody3D.new()
	wrapper.name = "TTS_%s_%d" % [tts_obj.name.replace(" ", "_"), _object_counter]
	wrapper.set_meta("network_id", _object_counter + 30000)
	wrapper.set_meta("tts_mesh_url", tts_obj.mesh_url)
	wrapper.set_meta("tts_diffuse_url", tts_obj.diffuse_url)
	wrapper.add_to_group("selectable")
	wrapper.add_to_group("tts_import")

	# Add loaded model
	wrapper.add_child(model_scene)

	# Calculate collision from model bounds (model bottom is at y=0 now)
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = scaled_aabb.size
	collision.shape = shape
	collision.position = Vector3(0, scaled_aabb.size.y / 2, 0)  # Center of model, starting from y=0
	wrapper.add_child(collision)

	# Apply TTS color tint if not white
	if tts_obj.color != Color.WHITE:
		_apply_color_tint(model_scene, tts_obj.color)

	# Add script for selection
	wrapper.set_script(preload("res://scripts/selectable_object.gd"))

	# Add to scene at TTS position (converted to meters)
	add_child(wrapper)

	# TTS position: 1 unit ≈ 1 inch = 0.0254m
	var pos_scale = 0.0254  # 1 inch = 0.0254m
	wrapper.global_position = Vector3(
		tts_obj.position.x * pos_scale,
		0,  # Place on table surface
		tts_obj.position.z * pos_scale
	)

	# Apply rotation (TTS uses degrees, only Y rotation for table objects)
	wrapper.rotation_degrees = Vector3(0, tts_obj.rotation.y, 0)

	var tex_info = " + texture" if not texture_path.is_empty() else ""
	print("  [OK] %s%s" % [tts_obj.name, tex_info])

	return wrapper


## Apply a color tint to all materials in a model
func _apply_color_tint(node: Node3D, color: Color) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mat = child.material_override
			if mat is StandardMaterial3D:
				# Only apply color tint to NON-textured models
				# Textured models (like painted miniatures) already have correct colors baked in
				# Applying ColorDiffuse would incorrectly darken/tint them
				if not mat.albedo_texture:
					mat.albedo_color = color

		if child is Node3D:
			_apply_color_tint(child, color)


## Spawn TTS models at grid positions (for preview/selection)
## Arranges models in a grid layout on the table
func spawn_tts_models_grid(tts_objects: Array[TTSImporter.TTSObject], models_dir: String, images_dir: String, spacing: float = 0.1) -> Array[Node3D]:
	var imported: Array[Node3D] = []

	var grid_size = int(ceil(sqrt(tts_objects.size())))
	var start_x = -float(grid_size) / 2.0 * spacing
	var start_z = -float(grid_size) / 2.0 * spacing

	var idx = 0
	for tts_obj in tts_objects:
		var grid_x = idx % grid_size
		@warning_ignore("integer_division")
		var grid_z = idx / grid_size

		var model = _import_tts_object(tts_obj, models_dir, images_dir)
		if model:
			# Override position to grid layout
			model.global_position = Vector3(
				start_x + grid_x * spacing,
				0,
				start_z + grid_z * spacing
			)
			imported.append(model)

		idx += 1

	return imported


## ============================================================================
## TTS Online Import Functions (Downloads from URLs)
## ============================================================================

## Download manager reference
var _download_manager: TTSDownloadManager = null
var _pending_tts_import: TTSImporter.TTSParseResult = null

## Signal for online import completion
signal tts_online_import_completed(imported_count: int, failed_count: int)
signal tts_download_progress(current: int, total: int, url: String)


## Get or create the download manager
func _get_download_manager() -> TTSDownloadManager:
	if _download_manager == null:
		_download_manager = TTSDownloadManager.new()
		add_child(_download_manager)
		_download_manager.all_downloads_completed.connect(_on_downloads_completed)
		_download_manager.progress_updated.connect(_on_download_progress)
	return _download_manager


## Import TTS save from online URLs (downloads models and textures automatically)
## json_path: Path to the TTS save JSON file
## Returns immediately, emits tts_online_import_completed when done
func import_tts_save_online(json_path: String) -> void:
	print("=== TTS Online Import Starting ===")
	print("JSON: %s" % json_path)

	# Parse the TTS save file
	var parse_result = TTSImporter.parse_tts_save(json_path)
	if not parse_result.error.is_empty():
		push_error("TTS Import failed: %s" % parse_result.error)
		tts_online_import_completed.emit(0, 0)
		return

	# Get unique models (avoid downloading duplicates)
	var unique_models = TTSImporter.get_unique_models(parse_result)
	print("Save: %s" % parse_result.save_name)
	print("Unique models to download: %d" % unique_models.size())

	# Store for later use after downloads complete
	_pending_tts_import = parse_result
	_pending_tts_import.objects = unique_models  # Use unique models only

	# Queue all downloads
	var dm = _get_download_manager()
	dm.reset()
	dm.queue_tts_objects(unique_models)

	# Start downloads
	dm.start_downloads()


## Import TTS save from online URLs (synchronous version - blocks until complete)
## For use when you need the result immediately
func import_tts_save_online_sync(json_path: String) -> Array[Node3D]:
	var imported_objects: Array[Node3D] = []

	# Parse the TTS save file
	var parse_result = TTSImporter.parse_tts_save(json_path)
	if not parse_result.error.is_empty():
		push_error("TTS Import failed: %s" % parse_result.error)
		return imported_objects

	# Get unique models
	var unique_models = TTSImporter.get_unique_models(parse_result)

	print("=== TTS Online Import (Sync) ===")
	print("Save: %s" % parse_result.save_name)
	print("Unique models: %d" % unique_models.size())

	# Queue and start downloads
	var dm = _get_download_manager()
	dm.reset()
	dm.queue_tts_objects(unique_models)

	# Wait for downloads to complete
	if dm._pending_downloads.size() > 0:
		dm.start_downloads()
		await dm.all_downloads_completed

	# Now import all models from cache
	var success_count = 0
	var fail_count = 0

	for tts_obj in unique_models:
		var imported = _import_tts_object_from_cache(tts_obj, dm)
		if imported:
			imported_objects.append(imported)
			success_count += 1
		else:
			fail_count += 1

	print("=== TTS Online Import Complete ===")
	print("Success: %d | Failed: %d" % [success_count, fail_count])

	return imported_objects


## Handle download completion - import all models
func _on_downloads_completed(_completed: Dictionary) -> void:
	if _pending_tts_import == null:
		return

	print("=== Downloads Complete - Importing Models ===")

	var dm = _get_download_manager()
	var success_count = 0
	var fail_count = 0

	for tts_obj in _pending_tts_import.objects:
		var imported = _import_tts_object_from_cache(tts_obj, dm)
		if imported:
			success_count += 1
		else:
			fail_count += 1

	print("=== TTS Import Complete ===")
	print("Success: %d | Failed: %d" % [success_count, fail_count])

	_pending_tts_import = null
	tts_online_import_completed.emit(success_count, fail_count)


## Forward download progress
func _on_download_progress(current: int, total: int, url: String) -> void:
	tts_download_progress.emit(current, total, url)


## Import a single TTS object from download cache
func _import_tts_object_from_cache(tts_obj: TTSImporter.TTSObject, dm: TTSDownloadManager) -> Node3D:
	# Find the mesh file in download cache
	var mesh_path = dm.find_cached_file(tts_obj.mesh_url, true)
	if mesh_path.is_empty():
		print("  [SKIP] %s - mesh not downloaded" % tts_obj.name)
		return null

	# Find texture file if URL is specified
	var texture_path = ""
	if not tts_obj.diffuse_url.is_empty():
		texture_path = dm.find_cached_file(tts_obj.diffuse_url, false)

	# Load the model WITHOUT base - base will be added separately after scaling
	var extension = mesh_path.get_extension().to_lower()
	var model_scene: Node3D = null

	match extension:
		"obj":
			model_scene = _load_obj_model(mesh_path, texture_path, false)  # Never add base here
		_:
			push_warning("Unsupported TTS mesh format: %s" % extension)
			return null

	if not model_scene:
		print("  [FAIL] %s - could not load mesh" % tts_obj.name)
		return null

	# TTS uses 1 unit = 1 inch, Godot uses meters
	# Scale model to convert inches to meters: 1 inch = 0.0254 meters
	var tts_scale = 0.0254  # 1 inch = 0.0254m
	model_scene.scale = Vector3(tts_scale, tts_scale, tts_scale)

	# Calculate model bounds for collision (after scaling)
	var mesh_aabb = _calculate_aabb(model_scene)

	# Add base for child models (real miniatures) - created OUTSIDE the scaled model
	var add_base = tts_obj.is_child_model
	var base_height = 0.003  # 3mm base height

	# Position model so its bottom sits on table/base surface
	# mesh_aabb.position.y is the lowest point of the model (already scaled)
	if add_base:
		# Place model's bottom on top of base
		model_scene.position.y = base_height - mesh_aabb.position.y
	else:
		# Place model's bottom on table surface (y=0)
		model_scene.position.y = -mesh_aabb.position.y

	var base_info = " + base" if add_base else ""
	print("    Size: %.1fmm x %.1fmm x %.1fmm%s" % [mesh_aabb.size.x * 1000, mesh_aabb.size.y * 1000, mesh_aabb.size.z * 1000, base_info])

	# Wrap in StaticBody3D for selection
	_object_counter += 1
	var wrapper = StaticBody3D.new()
	wrapper.name = "TTS_%s_%d" % [tts_obj.name.replace(" ", "_"), _object_counter]
	wrapper.set_meta("network_id", _object_counter + 30000)
	wrapper.set_meta("tts_mesh_url", tts_obj.mesh_url)
	wrapper.set_meta("tts_diffuse_url", tts_obj.diffuse_url)
	wrapper.add_to_group("selectable")
	wrapper.add_to_group("tts_import")

	# Add loaded model
	wrapper.add_child(model_scene)

	# Add base AFTER model (not inside scaled model_scene)
	if add_base:
		var base = _create_miniature_base()
		wrapper.add_child(base)

	# Calculate collision from model + base bounds (model bottom is now at y=0 or base_height)
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	if add_base:
		# Include base in collision - model sits on base
		var base_radius = 0.016  # 32mm diameter (16mm radius)
		var total_height = mesh_aabb.size.y + base_height
		shape.size = Vector3(base_radius * 2, total_height, base_radius * 2)
		collision.position = Vector3(0, total_height / 2, 0)
	else:
		# Model bottom is at y=0
		shape.size = mesh_aabb.size
		collision.position = Vector3(0, mesh_aabb.size.y / 2, 0)
	collision.shape = shape
	wrapper.add_child(collision)

	# Apply TTS color tint if not white
	if tts_obj.color != Color.WHITE:
		_apply_color_tint(model_scene, tts_obj.color)

	# IMPORTANT: Enable shadow casting for all meshes (model + base)
	_enable_shadows_recursive(wrapper)

	# Add script for selection
	wrapper.set_script(preload("res://scripts/selectable_object.gd"))

	# Add to scene at TTS position (converted to meters)
	add_child(wrapper)

	# TTS position: 1 unit ≈ 1 inch = 0.0254m
	var pos_scale = 0.0254  # 1 inch = 0.0254m
	wrapper.global_position = Vector3(
		tts_obj.position.x * pos_scale,
		0,  # Place on table surface
		tts_obj.position.z * pos_scale
	)

	# Apply rotation (TTS uses degrees, only Y rotation for table objects)
	wrapper.rotation_degrees = Vector3(0, tts_obj.rotation.y, 0)

	var tex_info = " + texture" if not texture_path.is_empty() else ""
	print("  [OK] %s%s" % [tts_obj.name, tex_info])

	return wrapper


## ============================================================================
## Arrangement Functions (TTS-style formations)
## ============================================================================

## Get table position from screen position (for input handling)
## @param screen_pos: Screen coordinates to project
## @return: World position on table, or Vector3.INF if not intersecting
func _get_table_position_at_screen(screen_pos: Vector2) -> Vector3:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return Vector3.INF

	var from = camera.project_ray_origin(screen_pos)
	var dir = camera.project_ray_normal(screen_pos)

	# Intersect with table plane (y=0)
	var table_plane = Plane(Vector3.UP, 0)
	var intersection = table_plane.intersects_ray(from, dir)

	if intersection:
		return Vector3(intersection.x, 0, intersection.z)

	return Vector3.INF


## Get cursor position on the table from current mouse position
func get_cursor_table_position() -> Vector3:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return Vector3.ZERO

	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)

	# Intersect with table plane (y=0)
	var table_plane = Plane(Vector3.UP, 0)
	var intersection = table_plane.intersects_ray(from, dir)

	if intersection:
		return Vector3(intersection.x, 0, intersection.z)

	return Vector3.ZERO


## Get the maximum base diameter from a list of objects (in meters)
## Returns the largest base diameter to ensure proper spacing for all models
func _get_max_base_diameter(objects: Array) -> float:
	var max_diameter = 0.032  # Default 32mm

	for obj in objects:
		if not is_instance_valid(obj):
			continue

		var game_unit = UnitUtils.get_game_unit(obj)
		if game_unit and game_unit.unit_properties:
			var oval_width = game_unit.unit_properties.get("base_size_oval_width", 0)
			var oval_length = game_unit.unit_properties.get("base_size_oval_length", 0)
			if oval_width > 0 and oval_length > 0:
				var diameter = max(oval_width, oval_length) * 0.001
				max_diameter = maxf(max_diameter, diameter)
			else:
				var base_mm = game_unit.unit_properties.get("base_size_round", 32)
				var diameter = base_mm * 0.001
				max_diameter = maxf(max_diameter, diameter)

	return max_diameter


## Arrange selected objects in N rows at cursor position (keys 1-9)
func arrange_selected_in_rows(num_rows: int, cursor_pos: Vector3) -> void:
	if _selected_objects.size() < 2:
		return

	var objects = _selected_objects.duplicate()
	var count = objects.size()
	var cols = ceili(float(count) / num_rows)

	# Calculate spacing based on largest base size to prevent overlap
	# Spacing = diameter + constant edge gap (8mm)
	var max_diameter = _get_max_base_diameter(objects)
	var edge_gap = 0.008  # 8mm constant gap between base edges
	var spacing = max_diameter + edge_gap

	# Start from cursor position (first object at cursor)
	var start_x = cursor_pos.x
	var start_z = cursor_pos.z

	var idx = 0
	for row in range(num_rows):
		for col in range(cols):
			if idx >= count:
				break
			var obj = objects[idx]
			if is_instance_valid(obj):
				obj.global_position = Vector3(
					start_x + col * spacing,
					obj.global_position.y,
					start_z + row * spacing
				)
			idx += 1

	print("Arranged %d objects in %d rows at cursor (spacing: %.0fmm)" % [count, num_rows, spacing * 1000])


## Arrange selected objects in arrow/wedge formation at cursor (A key)
func arrange_selected_arrow(cursor_pos: Vector3) -> void:
	if _selected_objects.size() < 2:
		return

	var objects = _selected_objects.duplicate()
	var count = objects.size()

	# Calculate spacing based on largest base size to prevent overlap
	# Spacing = diameter + constant edge gap (8mm)
	var max_diameter = _get_max_base_diameter(objects)
	var edge_gap = 0.008  # 8mm constant gap between base edges
	var spacing = max_diameter + edge_gap
	var row_spacing = max_diameter + edge_gap  # Same spacing for rows to prevent overlap

	# Arrow formation: 1 in front (at cursor), then 2, then 3, etc.
	var row = 0
	var idx = 0
	var row_count = 1

	while idx < count:
		# Position objects in this row, centered on cursor X
		var row_start_x = cursor_pos.x - (row_count - 1) * spacing / 2

		for col in range(row_count):
			if idx >= count:
				break
			var obj = objects[idx]
			if is_instance_valid(obj):
				obj.global_position = Vector3(
					row_start_x + col * spacing,
					obj.global_position.y,
					cursor_pos.z + row * row_spacing
				)
			idx += 1

		row += 1
		row_count += 1

	print("Arranged %d objects in arrow formation at cursor (spacing: %.0fmm)" % [count, spacing * 1000])


## Copy selected objects to clipboard (Ctrl+C)
func copy_to_clipboard() -> void:
	if _selected_objects.is_empty():
		return

	_clipboard.clear()
	for obj in _selected_objects:
		if is_instance_valid(obj):
			_clipboard.append(obj)

	print("Copied %d objects to clipboard" % _clipboard.size())


## Paste objects from clipboard at cursor position (Ctrl+V)
func paste_from_clipboard(cursor_pos: Vector3) -> void:
	if _clipboard.is_empty():
		print("Clipboard is empty")
		return

	# Calculate center of clipboard objects
	var clipboard_center = Vector3.ZERO
	var valid_count = 0
	for obj in _clipboard:
		if is_instance_valid(obj):
			clipboard_center += obj.global_position
			valid_count += 1

	if valid_count == 0:
		_clipboard.clear()
		return

	clipboard_center /= valid_count

	# Paste at cursor position, maintaining relative positions
	var pasted_count = 0
	_deselect_all()  # Deselect current selection

	for obj in _clipboard:
		if not is_instance_valid(obj):
			continue

		var copy: Node3D = null

		# Check if it's a TTS import (has mesh URL meta)
		if obj.has_meta("tts_mesh_url"):
			copy = _duplicate_tts_object(obj)
		else:
			# Generic duplication for other objects
			copy = obj.duplicate()
			_object_counter += 1
			copy.name = obj.name.split("_")[0] + "_%d" % _object_counter

		if copy:
			add_child(copy)
			# Position relative to cursor (maintaining formation)
			var offset = obj.global_position - clipboard_center
			copy.global_position = cursor_pos + offset
			copy.global_position.y = obj.global_position.y  # Keep original height
			# Select the pasted object
			_add_to_selection(copy)
			pasted_count += 1

	print("Pasted %d objects at cursor" % pasted_count)


## Duplicate a TTS-imported object
func _duplicate_tts_object(original: Node3D) -> Node3D:
	# Deep duplicate the object
	var copy = original.duplicate()

	# Assign new unique ID
	_object_counter += 1
	copy.name = original.name.split("_")[0] + "_%d" % _object_counter
	copy.set_meta("network_id", _object_counter + 30000)

	# Make sure it's in the right groups
	if not copy.is_in_group("selectable"):
		copy.add_to_group("selectable")
	if not copy.is_in_group("tts_import"):
		copy.add_to_group("tts_import")

	return copy


## ============================================================================
## Terrain System
## ============================================================================

## Spawn terrain from TTS URLs at given spawn position
## Returns the spawned terrain object
func spawn_tts_terrain(mesh_url: String, diffuse_url: String, tts_scale: Vector3, spawn_pos: Vector3, terrain_name: String = "Terrain") -> Node3D:
	if mesh_url.is_empty():
		push_error("spawn_tts_terrain: No mesh URL provided")
		return null

	# Get or create download manager
	var dm = _get_download_manager()

	# Check if already cached
	var mesh_path = dm.find_cached_file(mesh_url, true)
	var texture_path = ""

	if mesh_path.is_empty():
		# Need to download
		print("  [DOWNLOAD] Terrain mesh: %s" % mesh_url.get_file())
		dm.queue_download(mesh_url, true)
		if not diffuse_url.is_empty():
			dm.queue_download(diffuse_url, false)

		# Wait for downloads
		dm.start_downloads()
		await dm.all_downloads_completed

		mesh_path = dm.find_cached_file(mesh_url, true)

	if not diffuse_url.is_empty():
		texture_path = dm.find_cached_file(diffuse_url, false)

	if mesh_path.is_empty():
		push_error("spawn_tts_terrain: Failed to download mesh")
		return null

	# Load the model (no base for terrain)
	var model_scene = _load_obj_model(mesh_path, texture_path, false)
	if not model_scene:
		push_error("spawn_tts_terrain: Failed to load mesh")
		return null

	# Apply TTS scale (inches to meters, plus terrain's own scale)
	var scale_factor = 0.0254  # TTS units to meters
	var final_scale = tts_scale * scale_factor
	model_scene.scale = final_scale

	# Calculate bounds for collision BEFORE scaling was applied (raw mesh bounds)
	# Then apply scale to the AABB
	var raw_aabb = _calculate_aabb(model_scene)
	# The AABB from _calculate_aabb doesn't include parent scale, so we need to apply it
	var mesh_aabb = AABB(
		raw_aabb.position * final_scale,
		raw_aabb.size * final_scale
	)

	# Ensure minimum collision size for clickability
	var min_size = 0.05  # 5cm minimum
	mesh_aabb.size.x = max(mesh_aabb.size.x, min_size)
	mesh_aabb.size.y = max(mesh_aabb.size.y, min_size)
	mesh_aabb.size.z = max(mesh_aabb.size.z, min_size)

	print("  Terrain AABB: %.3f x %.3f x %.3f" % [mesh_aabb.size.x, mesh_aabb.size.y, mesh_aabb.size.z])

	# Create wrapper
	_object_counter += 1
	var wrapper = StaticBody3D.new()
	wrapper.name = "Terrain_%s_%d" % [terrain_name.replace(" ", "_"), _object_counter]
	wrapper.set_meta("network_id", _object_counter + 40000)  # Terrain IDs start at 40000
	wrapper.set_meta("tts_mesh_url", mesh_url)
	wrapper.set_meta("tts_diffuse_url", diffuse_url)
	wrapper.set_meta("terrain_name", terrain_name)
	wrapper.add_to_group("selectable")
	wrapper.add_to_group("tts_import")
	wrapper.add_to_group("terrain_piece")

	# Add model
	wrapper.add_child(model_scene)

	# Add collision
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = mesh_aabb.size
	collision.shape = shape
	collision.position = mesh_aabb.position + mesh_aabb.size / 2
	wrapper.add_child(collision)

	# Enable shadow casting for terrain
	_enable_shadows_recursive(wrapper)

	# Add script for selection
	wrapper.set_script(preload("res://scripts/selectable_object.gd"))

	# Add to scene
	add_child(wrapper)
	wrapper.global_position = spawn_pos

	print("  [OK] Terrain: %s" % terrain_name)
	return wrapper


## ============================================================================
## Lock/Unlock System
## ============================================================================

## Toggle lock state of selected objects
func toggle_lock_selected() -> void:
	if _selected_objects.is_empty():
		return

	# Check if any are unlocked - if so, lock all. Otherwise unlock all.
	var any_unlocked = false
	for obj in _selected_objects:
		if is_instance_valid(obj) and not obj.get_meta("locked", false):
			any_unlocked = true
			break

	var new_state = any_unlocked  # Lock if any unlocked, unlock if all locked
	var count = 0

	for obj in _selected_objects:
		if is_instance_valid(obj):
			_set_object_locked(obj, new_state)
			count += 1

	var state_text = "Locked" if new_state else "Unlocked"
	print("%s %d objects" % [state_text, count])

	# Deselect if locking
	if new_state:
		_deselect_all()


## Set lock state of a single object
func _set_object_locked(obj: Node3D, locked: bool) -> void:
	obj.set_meta("locked", locked)

	# Visual feedback - change material or add indicator
	if locked:
		obj.add_to_group("locked")
		# Dim the object slightly to indicate locked state
		_set_object_dimmed(obj, true)
	else:
		obj.remove_from_group("locked")
		_set_object_dimmed(obj, false)


## Check if object is locked
func is_object_locked(obj: Node3D) -> bool:
	return obj.get_meta("locked", false)


## Apply dimming effect to show locked state
func _set_object_dimmed(obj: Node3D, dimmed: bool) -> void:
	# Find all MeshInstance3D children and adjust their material
	for child in obj.get_children():
		if child is MeshInstance3D:
			var mesh_inst = child as MeshInstance3D
			if mesh_inst.material_override:
				var mat = mesh_inst.material_override as StandardMaterial3D
				if mat:
					if dimmed:
						mat.albedo_color = mat.albedo_color.darkened(0.3)
					else:
						mat.albedo_color = mat.albedo_color.lightened(0.3)
		# Recurse into children
		if child.get_child_count() > 0:
			_set_object_dimmed(child, dimmed)


## ============================================================================
## Group Rotation System (Shift+R)
## ============================================================================

## Rotate selected objects as a group around the first object (Shift+R)
## Called continuously while Shift+R is held, so no print statements
func rotate_selected_group(angle_degrees: float) -> void:
	if _selected_objects.size() < 2:
		# Single object or no selection - just rotate the object itself
		if _selected_objects.size() == 1:
			var obj = _selected_objects[0]
			if is_instance_valid(obj):
				obj.rotate_y(deg_to_rad(angle_degrees))
		return

	# Find the first valid object as pivot point
	var pivot_obj: Node3D = null
	for obj in _selected_objects:
		if is_instance_valid(obj):
			pivot_obj = obj
			break

	if not pivot_obj:
		return

	var pivot_pos = pivot_obj.global_position
	var angle_rad = deg_to_rad(angle_degrees)

	# Rotate all selected objects around the pivot
	for obj in _selected_objects:
		if not is_instance_valid(obj):
			continue

		if obj == pivot_obj:
			# Pivot object just rotates in place
			obj.rotate_y(angle_rad)
		else:
			# Calculate offset from pivot
			var offset = obj.global_position - pivot_pos

			# Rotate offset around Y axis
			var new_offset = Vector3(
				offset.x * cos(angle_rad) - offset.z * sin(angle_rad),
				offset.y,
				offset.x * sin(angle_rad) + offset.z * cos(angle_rad)
			)

			# Apply new position
			obj.global_position = pivot_pos + new_offset

			# Also rotate the object itself to face the same relative direction
			obj.rotate_y(angle_rad)
