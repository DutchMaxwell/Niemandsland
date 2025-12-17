extends Node3D
## Manages all game objects: miniatures, dice, terrain
## Handles spawning, selection, dragging, and rotation

signal dice_rolled(total: int, results: Array)
signal object_selected(obj: Node3D)
signal object_deselected()

@export var drag_height: float = 0.5
@export var rotation_snap_degrees: float = 45.0

var _selected_object: Node3D = null
var _is_dragging: bool = false
var _drag_plane: Plane
var _dice_list: Array[RigidBody3D] = []
var _object_counter: int = 0

# Preload resources (will be scenes in full version)
# Using larger scale for visibility (1 unit ≈ 10cm for good visuals)
const MINIATURE_HEIGHT: float = 0.4  # ~4cm visual height
const MINIATURE_RADIUS: float = 0.12  # ~25mm base scaled up for visibility


func _ready() -> void:
	_drag_plane = Plane(Vector3.UP, 0)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton

		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_try_select_at_mouse(mouse_event.position)
			else:
				_stop_dragging()

	elif event is InputEventMouseMotion and _is_dragging:
		_update_drag(event.position)

	elif event.is_action_pressed("rotate_object") and _selected_object:
		_rotate_selected_object()

	elif event.is_action_pressed("roll_dice"):
		roll_all_dice()


func _try_select_at_mouse(screen_pos: Vector2) -> void:
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
			_select_object(collider)
			_start_dragging(screen_pos)
		elif collider.is_in_group("table"):
			_deselect_current()


func _select_object(obj: Node3D) -> void:
	if _selected_object == obj:
		return

	_deselect_current()
	_selected_object = obj

	# Visual feedback - highlight selected object
	if obj.has_method("set_selected"):
		obj.set_selected(true)

	object_selected.emit(obj)


func _deselect_current() -> void:
	if _selected_object:
		if _selected_object.has_method("set_selected"):
			_selected_object.set_selected(false)
		_selected_object = null
		object_deselected.emit()


func _start_dragging(screen_pos: Vector2) -> void:
	if not _selected_object:
		return

	_is_dragging = true

	# For rigid bodies, make them kinematic while dragging
	if _selected_object is RigidBody3D:
		_selected_object.freeze = true


func _stop_dragging() -> void:
	if _is_dragging and _selected_object:
		# Re-enable physics for rigid bodies
		if _selected_object is RigidBody3D:
			_selected_object.freeze = false

	_is_dragging = false


func _update_drag(screen_pos: Vector2) -> void:
	if not _selected_object or not _is_dragging:
		return

	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	var from = camera.project_ray_origin(screen_pos)
	var dir = camera.project_ray_normal(screen_pos)

	# Intersect with drag plane at object height
	var plane_height = _selected_object.global_position.y
	var drag_plane_at_height = Plane(Vector3.UP, -plane_height)
	var intersection = drag_plane_at_height.intersects_ray(from, dir)

	if intersection:
		_selected_object.global_position = intersection


func _rotate_selected_object() -> void:
	if not _selected_object:
		return

	# Rotate by snap amount
	_selected_object.rotate_y(deg_to_rad(rotation_snap_degrees))


## Spawn a miniature at the given position
func spawn_miniature(pos: Vector3) -> Node3D:
	_object_counter += 1

	var mini = StaticBody3D.new()
	mini.name = "Miniature_%d" % _object_counter
	mini.add_to_group("selectable")
	mini.add_to_group("miniature")

	# Create base (circular)
	var base_mesh = CylinderMesh.new()
	base_mesh.top_radius = MINIATURE_RADIUS
	base_mesh.bottom_radius = MINIATURE_RADIUS
	base_mesh.height = 0.03  # Thicker base

	var base_instance = MeshInstance3D.new()
	base_instance.mesh = base_mesh
	base_instance.position.y = 0.015

	var base_material = StandardMaterial3D.new()
	base_material.albedo_color = Color(0.1, 0.1, 0.1)
	base_instance.material_override = base_material
	mini.add_child(base_instance)

	# Create simple model (cylinder as placeholder)
	var model_mesh = CylinderMesh.new()
	model_mesh.top_radius = MINIATURE_RADIUS * 0.5
	model_mesh.bottom_radius = MINIATURE_RADIUS * 0.7
	model_mesh.height = MINIATURE_HEIGHT

	var model_instance = MeshInstance3D.new()
	model_instance.mesh = model_mesh
	model_instance.position.y = MINIATURE_HEIGHT / 2 + 0.03  # Above base

	var model_material = StandardMaterial3D.new()
	model_material.albedo_color = Color(randf(), randf(), randf())  # Random color
	model_instance.material_override = model_material
	mini.add_child(model_instance)

	# Store material reference for selection highlight
	mini.set_meta("model_material", model_material)
	mini.set_meta("original_color", model_material.albedo_color)

	# Add collision
	var collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = MINIATURE_RADIUS
	shape.height = MINIATURE_HEIGHT + 0.03  # Include base
	collision.shape = shape
	collision.position.y = (MINIATURE_HEIGHT + 0.03) / 2
	mini.add_child(collision)

	# Set collision layers
	mini.collision_layer = 1
	mini.collision_mask = 1

	# Add selection methods
	mini.set_script(preload("res://scripts/selectable_object.gd"))

	mini.global_position = pos
	add_child(mini)

	return mini


## Spawn a D6 dice at the given position
func spawn_dice(pos: Vector3) -> RigidBody3D:
	_object_counter += 1

	var dice = RigidBody3D.new()
	dice.name = "Dice_%d" % _object_counter
	dice.add_to_group("selectable")
	dice.add_to_group("dice")
	dice.mass = 0.5
	dice.collision_layer = 1
	dice.collision_mask = 1
	dice.physics_material_override = _create_dice_physics_material()

	var dice_size = 0.15
	var corner_radius = dice_size * 0.15  # 15% roundness

	# Create rounded dice body
	var dice_body = _create_rounded_cube(dice_size, corner_radius)
	dice.add_child(dice_body)

	# Get material reference for selection
	var dice_material = dice_body.material_override
	dice.set_meta("model_material", dice_material)
	dice.set_meta("original_color", Color.WHITE)

	# Add collision (slightly smaller for rounded feel)
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(dice_size * 0.95, dice_size * 0.95, dice_size * 0.95)
	collision.shape = shape
	dice.add_child(collision)

	# Add proper pip patterns for each face
	_add_dice_pips_proper(dice, dice_size)

	dice.set_script(preload("res://scripts/selectable_object.gd"))
	dice.global_position = pos
	add_child(dice)
	_dice_list.append(dice)

	return dice


func _create_rounded_cube(size: float, radius: float) -> MeshInstance3D:
	# Create main cube body
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(size, size, size)
	mesh_instance.mesh = box_mesh

	# Smooth white material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.95, 0.95)  # Slightly off-white
	material.roughness = 0.2  # Smooth/glossy
	material.metallic = 0.0
	mesh_instance.material_override = material

	# Add corner spheres for rounded appearance
	var corner_material = StandardMaterial3D.new()
	corner_material.albedo_color = Color(0.95, 0.95, 0.95)
	corner_material.roughness = 0.2

	var half = size / 2 - radius * 0.5
	var corners = [
		Vector3(-half, -half, -half), Vector3(-half, -half, half),
		Vector3(-half, half, -half), Vector3(-half, half, half),
		Vector3(half, -half, -half), Vector3(half, -half, half),
		Vector3(half, half, -half), Vector3(half, half, half),
	]

	for corner_pos in corners:
		var sphere = MeshInstance3D.new()
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = radius
		sphere_mesh.height = radius * 2
		sphere_mesh.radial_segments = 16
		sphere_mesh.rings = 8
		sphere.mesh = sphere_mesh
		sphere.material_override = corner_material
		sphere.position = corner_pos
		mesh_instance.add_child(sphere)

	return mesh_instance


func _create_dice_physics_material() -> PhysicsMaterial:
	var mat = PhysicsMaterial.new()
	mat.bounce = 0.4
	mat.friction = 0.6
	return mat


## Add proper pip patterns for a D6
## Standard D6: opposite faces sum to 7 (1-6, 2-5, 3-4)
## Layout: +Y=1, -Y=6, +Z=2, -Z=5, +X=3, -X=4
func _add_dice_pips_proper(dice: RigidBody3D, size: float) -> void:
	var pip_material = StandardMaterial3D.new()
	pip_material.albedo_color = Color(0.1, 0.1, 0.1)  # Dark gray/black
	pip_material.roughness = 0.3

	var pip_radius = size * 0.08
	var face_offset = size / 2 + 0.001  # Slightly above surface
	var pip_spacing = size * 0.25  # Distance between pips

	# Face 1 (top, +Y): single center pip
	_add_pip(dice, Vector3(0, face_offset, 0), Vector3.UP, pip_radius, pip_material)

	# Face 6 (bottom, -Y): 6 pips in 2 columns of 3
	for col in [-1, 1]:
		for row in [-1, 0, 1]:
			_add_pip(dice, Vector3(col * pip_spacing, -face_offset, row * pip_spacing), Vector3.DOWN, pip_radius, pip_material)

	# Face 2 (front, +Z): 2 pips diagonal
	_add_pip(dice, Vector3(-pip_spacing, pip_spacing, face_offset), Vector3.BACK, pip_radius, pip_material)
	_add_pip(dice, Vector3(pip_spacing, -pip_spacing, face_offset), Vector3.BACK, pip_radius, pip_material)

	# Face 5 (back, -Z): 5 pips (4 corners + center)
	_add_pip(dice, Vector3(0, 0, -face_offset), Vector3.FORWARD, pip_radius, pip_material)  # Center
	for x in [-1, 1]:
		for y in [-1, 1]:
			_add_pip(dice, Vector3(x * pip_spacing, y * pip_spacing, -face_offset), Vector3.FORWARD, pip_radius, pip_material)

	# Face 3 (right, +X): 3 pips diagonal
	_add_pip(dice, Vector3(face_offset, 0, 0), Vector3.RIGHT, pip_radius, pip_material)  # Center
	_add_pip(dice, Vector3(face_offset, pip_spacing, -pip_spacing), Vector3.RIGHT, pip_radius, pip_material)
	_add_pip(dice, Vector3(face_offset, -pip_spacing, pip_spacing), Vector3.RIGHT, pip_radius, pip_material)

	# Face 4 (left, -X): 4 pips in corners
	for y in [-1, 1]:
		for z in [-1, 1]:
			_add_pip(dice, Vector3(-face_offset, y * pip_spacing, z * pip_spacing), Vector3.LEFT, pip_radius, pip_material)


func _add_pip(parent: Node3D, position: Vector3, _normal: Vector3, radius: float, material: Material) -> void:
	var pip = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2
	sphere_mesh.radial_segments = 12
	sphere_mesh.rings = 6
	pip.mesh = sphere_mesh
	pip.material_override = material
	pip.position = position
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

	terrain.global_position = pos
	add_child(terrain)

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

	var results: Array[int] = []

	for dice in _dice_list:
		if is_instance_valid(dice):
			# Apply random force and torque
			dice.freeze = false
			dice.linear_velocity = Vector3(
				randf_range(-1, 1),
				randf_range(2, 4),
				randf_range(-1, 1)
			)
			dice.angular_velocity = Vector3(
				randf_range(-20, 20),
				randf_range(-20, 20),
				randf_range(-20, 20)
			)

	# Wait for dice to settle, then read results
	await get_tree().create_timer(2.0).timeout
	_read_dice_results()


func _read_dice_results() -> void:
	var results: Array[int] = []
	var total: int = 0

	for dice in _dice_list:
		if is_instance_valid(dice):
			var result = _get_dice_top_face(dice)
			results.append(result)
			total += result

	if not results.is_empty():
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
	_selected_object = null
	_object_counter = 0
