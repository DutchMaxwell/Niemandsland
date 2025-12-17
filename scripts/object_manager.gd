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
	var corner_radius = dice_size * 0.12  # Roundness factor

	# Create dice body with rounded edges
	var dice_body = _create_rounded_box_mesh(dice_size, corner_radius)
	dice.add_child(dice_body)

	# Get material reference for selection
	var dice_material = dice_body.material_override
	dice.set_meta("model_material", dice_material)
	dice.set_meta("original_color", Color.WHITE)

	# Add collision
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(dice_size, dice_size, dice_size)
	collision.shape = shape
	dice.add_child(collision)

	# Add flat pip circles on each face
	_add_flat_pips(dice, dice_size)

	dice.set_script(preload("res://scripts/selectable_object.gd"))
	dice.global_position = pos
	add_child(dice)
	_dice_list.append(dice)

	return dice


## Create a rounded cube mesh using ArrayMesh for proper beveled edges
func _create_rounded_box_mesh(size: float, radius: float) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	# Use ArrayMesh for procedural rounded cube
	var array_mesh = ArrayMesh.new()
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Parameters
	var half_size = size / 2.0
	var inner_size = half_size - radius
	var segments = 4  # Smoothness of bevels

	# Generate the 6 faces (flat parts)
	_add_rounded_cube_faces(surface_tool, inner_size, half_size)

	# Generate the 12 edges (cylindrical bevels)
	_add_rounded_cube_edges(surface_tool, inner_size, radius, segments)

	# Generate the 8 corners (spherical caps)
	_add_rounded_cube_corners(surface_tool, inner_size, radius, segments)

	# Generate normals for smooth shading
	surface_tool.generate_normals()

	# Create mesh
	array_mesh = surface_tool.commit()
	mesh_instance.mesh = array_mesh

	# Smooth white material with slight glossiness
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.95, 0.95)
	material.roughness = 0.15  # Glossy surface
	material.metallic = 0.0

	mesh_instance.material_override = material
	return mesh_instance


## Add the 6 flat faces of the rounded cube
func _add_rounded_cube_faces(st: SurfaceTool, inner: float, outer: float) -> void:
	# Top face (+Y)
	_add_quad(st,
		Vector3(-inner, outer, -inner),
		Vector3(-inner, outer, inner),
		Vector3(inner, outer, inner),
		Vector3(inner, outer, -inner))

	# Bottom face (-Y)
	_add_quad(st,
		Vector3(-inner, -outer, inner),
		Vector3(-inner, -outer, -inner),
		Vector3(inner, -outer, -inner),
		Vector3(inner, -outer, inner))

	# Front face (+Z)
	_add_quad(st,
		Vector3(-inner, -inner, outer),
		Vector3(-inner, inner, outer),
		Vector3(inner, inner, outer),
		Vector3(inner, -inner, outer))

	# Back face (-Z)
	_add_quad(st,
		Vector3(inner, -inner, -outer),
		Vector3(inner, inner, -outer),
		Vector3(-inner, inner, -outer),
		Vector3(-inner, -inner, -outer))

	# Right face (+X)
	_add_quad(st,
		Vector3(outer, -inner, inner),
		Vector3(outer, inner, inner),
		Vector3(outer, inner, -inner),
		Vector3(outer, -inner, -inner))

	# Left face (-X)
	_add_quad(st,
		Vector3(-outer, -inner, -inner),
		Vector3(-outer, inner, -inner),
		Vector3(-outer, inner, inner),
		Vector3(-outer, -inner, inner))


## Add a quad (two triangles) to the surface tool
func _add_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	# Triangle 1
	st.add_vertex(v0)
	st.add_vertex(v1)
	st.add_vertex(v2)
	# Triangle 2
	st.add_vertex(v0)
	st.add_vertex(v2)
	st.add_vertex(v3)


## Add the 12 cylindrical edge bevels
func _add_rounded_cube_edges(st: SurfaceTool, inner: float, radius: float, segments: int) -> void:
	# Edges along X axis (4)
	for y_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			_add_edge_bevel(st,
				Vector3(-inner, y_sign * inner, z_sign * inner),
				Vector3(inner, y_sign * inner, z_sign * inner),
				Vector3(0, y_sign, z_sign).normalized(), radius, segments)

	# Edges along Y axis (4)
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			_add_edge_bevel(st,
				Vector3(x_sign * inner, -inner, z_sign * inner),
				Vector3(x_sign * inner, inner, z_sign * inner),
				Vector3(x_sign, 0, z_sign).normalized(), radius, segments)

	# Edges along Z axis (4)
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			_add_edge_bevel(st,
				Vector3(x_sign * inner, y_sign * inner, -inner),
				Vector3(x_sign * inner, y_sign * inner, inner),
				Vector3(x_sign, y_sign, 0).normalized(), radius, segments)


## Add a single edge bevel (quarter cylinder)
func _add_edge_bevel(st: SurfaceTool, start: Vector3, end: Vector3, corner_dir: Vector3, radius: float, segments: int) -> void:
	var edge_dir = (end - start).normalized()

	# Find the two perpendicular directions for the bevel
	var perp1: Vector3
	var perp2: Vector3

	if abs(edge_dir.x) > 0.5:
		perp1 = Vector3(0, corner_dir.y, 0).normalized() if corner_dir.y != 0 else Vector3(0, 1, 0)
		perp2 = Vector3(0, 0, corner_dir.z).normalized() if corner_dir.z != 0 else Vector3(0, 0, 1)
	elif abs(edge_dir.y) > 0.5:
		perp1 = Vector3(corner_dir.x, 0, 0).normalized() if corner_dir.x != 0 else Vector3(1, 0, 0)
		perp2 = Vector3(0, 0, corner_dir.z).normalized() if corner_dir.z != 0 else Vector3(0, 0, 1)
	else:
		perp1 = Vector3(corner_dir.x, 0, 0).normalized() if corner_dir.x != 0 else Vector3(1, 0, 0)
		perp2 = Vector3(0, corner_dir.y, 0).normalized() if corner_dir.y != 0 else Vector3(0, 1, 0)

	# Create bevel strip
	for i in range(segments):
		var angle1 = (float(i) / segments) * PI / 2
		var angle2 = (float(i + 1) / segments) * PI / 2

		var offset1 = perp1 * cos(angle1) * radius + perp2 * sin(angle1) * radius
		var offset2 = perp1 * cos(angle2) * radius + perp2 * sin(angle2) * radius

		var v0 = start + offset1
		var v1 = end + offset1
		var v2 = end + offset2
		var v3 = start + offset2

		_add_quad(st, v0, v3, v2, v1)


## Add the 8 spherical corner caps
func _add_rounded_cube_corners(st: SurfaceTool, inner: float, radius: float, segments: int) -> void:
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			for z_sign in [-1.0, 1.0]:
				var corner = Vector3(x_sign * inner, y_sign * inner, z_sign * inner)
				var dir = Vector3(x_sign, y_sign, z_sign).normalized()
				_add_corner_cap(st, corner, dir, radius, segments)


## Add a single spherical corner cap (1/8 sphere)
func _add_corner_cap(st: SurfaceTool, center: Vector3, corner_dir: Vector3, radius: float, segments: int) -> void:
	# Determine the three axes for this octant
	var axis_x = Vector3(sign(corner_dir.x), 0, 0)
	var axis_y = Vector3(0, sign(corner_dir.y), 0)
	var axis_z = Vector3(0, 0, sign(corner_dir.z))

	# Create triangular patches for the corner
	for i in range(segments):
		for j in range(segments - i):
			var k = segments - i - j - 1

			# Barycentric-like coordinates for spherical interpolation
			var coords = [
				[i, j, k + 1],
				[i, j + 1, k],
				[i + 1, j, k],
				[i + 1, j + 1, k - 1] if k > 0 else null
			]

			var verts: Array[Vector3] = []
			for coord in coords:
				if coord != null:
					var dir = (axis_x * coord[0] + axis_y * coord[1] + axis_z * coord[2]).normalized()
					verts.append(center + dir * radius)

			if verts.size() >= 3:
				st.add_vertex(verts[0])
				st.add_vertex(verts[1])
				st.add_vertex(verts[2])

				if verts.size() == 4:
					st.add_vertex(verts[1])
					st.add_vertex(verts[3])
					st.add_vertex(verts[2])


func _create_dice_physics_material() -> PhysicsMaterial:
	var mat = PhysicsMaterial.new()
	mat.bounce = 0.4
	mat.friction = 0.6
	return mat


## Add flat circular pips to each face of the dice
## Standard D6: opposite faces sum to 7 (1-6, 2-5, 3-4)
func _add_flat_pips(dice: RigidBody3D, size: float) -> void:
	var pip_material = StandardMaterial3D.new()
	pip_material.albedo_color = Color(0.08, 0.08, 0.08)  # Near black
	pip_material.roughness = 0.4
	pip_material.metallic = 0.0

	var pip_radius = size * 0.07  # Pip circle radius
	var pip_depth = 0.002  # Very thin (flat circle)
	var face_offset = size / 2 + 0.001  # Just above surface
	var pip_spacing = size * 0.24  # Distance between pips

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
func _add_flat_pip(parent: Node3D, position: Vector3, normal: Vector3, radius: float, depth: float, material: Material) -> void:
	var pip = MeshInstance3D.new()
	var cyl_mesh = CylinderMesh.new()
	cyl_mesh.top_radius = radius
	cyl_mesh.bottom_radius = radius
	cyl_mesh.height = depth
	cyl_mesh.radial_segments = 16  # Smooth circle
	cyl_mesh.rings = 1
	pip.mesh = cyl_mesh
	pip.material_override = material
	pip.position = position

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
