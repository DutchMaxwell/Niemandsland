class_name DiceManager
extends Node
## Manages dice spawning, rolling, and result reading.
## Extracted from object_manager.gd for better separation of concerns.

signal dice_rolled(total: int, results: Array)

# Debug logging (disabled by default for production)
@export var debug_dice_physics: bool = false
var _debug_log_file: FileAccess = null
var _debug_log_timer: float = 0.0
const DEBUG_LOG_INTERVAL: float = 0.5  # Log every 0.5 seconds

var _is_rolling: bool = false
var _dice_list: Array[RigidBody3D] = []
var _object_counter: int = 0

# Parent node where dice will be added
var _dice_container: Node3D = null


func _ready() -> void:
	_init_debug_log()


## Initialize with a container node for spawned dice
func initialize(container: Node3D) -> void:
	_dice_container = container


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

	if _dice_container:
		_dice_container.add_child(dice)
	else:
		push_warning("DiceManager: No container set, adding dice to self")
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


## Get the list of all dice
func get_dice_list() -> Array[RigidBody3D]:
	return _dice_list


## Check if currently rolling
func is_rolling() -> bool:
	return _is_rolling


## Clear all dice from the scene
func clear_all_dice() -> void:
	for dice in _dice_list:
		if is_instance_valid(dice):
			dice.queue_free()
	_dice_list.clear()


## Remove a specific dice from tracking
func remove_dice(dice: RigidBody3D) -> void:
	_dice_list.erase(dice)
