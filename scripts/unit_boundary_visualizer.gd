extends Node3D
class_name UnitBoundaryVisualizer
## Visualizes unit boundaries with transparent colored hulls.
## Shows which models belong to which unit at a glance.

## Height above ground for the boundary mesh
const BOUNDARY_HEIGHT := 0.015  # 1.5cm above table surface

## Padding around models (in meters)
const BOUNDARY_PADDING := 0.03  # 3cm padding around models

## Smoothing factor for the hull (higher = smoother)
const HULL_SMOOTHING := 12

## Transparency alpha value
const BOUNDARY_ALPHA := 0.35

## Border line thickness
const BORDER_THICKNESS := 0.008  # 8mm border

## Border alpha (more visible than fill)
const BORDER_ALPHA := 0.85

## Player colors (must match OPRArmyManager.PLAYER_COLORS)
const PLAYER_COLORS = {
	1: Color(0.2, 0.4, 0.8),   # Blue
	2: Color(0.8, 0.2, 0.2),   # Red
	3: Color(0.2, 0.7, 0.2),   # Green
	4: Color(0.7, 0.5, 0.1),   # Orange/Gold
}

## Cached boundary meshes per GameUnit
var _boundaries: Dictionary = {}  # GameUnit -> { "fill": MeshInstance3D, "border": MeshInstance3D }

## Reference to army manager for player colors
var army_manager = null  # OPRArmyManager

## Update timer for smooth updates
var _update_timer: float = 0.0
const UPDATE_INTERVAL := 0.1  # Update every 100ms


func _ready() -> void:
	# Find army manager
	army_manager = get_node_or_null("/root/Main/OPRArmyManager")


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		update_all_boundaries()


## Creates or updates boundary visualization for all units
func update_all_boundaries() -> void:
	if not army_manager:
		army_manager = get_node_or_null("/root/Main/OPRArmyManager")
		if not army_manager:
			return

	# Track which units still exist
	var existing_units: Array = []

	# Update boundaries for all game units
	for unit_id in army_manager.game_units:
		var game_unit = army_manager.game_units[unit_id]
		if game_unit:
			existing_units.append(game_unit)
			_update_unit_boundary(game_unit)

	# Remove boundaries for units that no longer exist
	var units_to_remove: Array = []
	for unit in _boundaries.keys():
		if unit not in existing_units:
			units_to_remove.append(unit)

	for unit in units_to_remove:
		_remove_unit_boundary(unit)


## Updates boundary for a single unit
func _update_unit_boundary(game_unit) -> void:
	var models = game_unit.get_alive_models()

	# Need at least 1 model
	if models.size() == 0:
		_remove_unit_boundary(game_unit)
		return

	# Get player color
	var player_id = game_unit.unit_properties.get("player_id", 1)
	var player_color = PLAYER_COLORS.get(player_id, Color.GRAY)

	# Get model positions
	var positions: Array = []
	var base_radius: float = 0.016  # Default 32mm base

	# Get base size from unit
	var base_mm = game_unit.unit_properties.get("base_size_round", 32)
	base_radius = (base_mm / 2.0) * 0.001

	for model in models:
		if model.node and is_instance_valid(model.node) and model.node.is_inside_tree():
			var pos = model.node.global_position
			positions.append(Vector2(pos.x, pos.z))

	if positions.size() == 0:
		_remove_unit_boundary(game_unit)
		return

	# Calculate expanded convex hull with padding
	var hull_points = _calculate_smooth_hull(positions, base_radius + BOUNDARY_PADDING)

	if hull_points.size() < 3:
		# For 1-2 models, create a circle/capsule shape
		hull_points = _create_simple_boundary(positions, base_radius + BOUNDARY_PADDING)

	# Create or update mesh
	_create_boundary_mesh(game_unit, hull_points, player_color)


## Calculates a smooth convex hull with padding around positions
func _calculate_smooth_hull(positions: Array, padding: float) -> PackedVector2Array:
	if positions.size() == 0:
		return PackedVector2Array()

	if positions.size() == 1:
		# Single point - create circle
		return _create_circle(positions[0], padding)

	if positions.size() == 2:
		# Two points - create capsule
		return _create_capsule(positions[0], positions[1], padding)

	# Expand each point into a circle, then compute convex hull
	var expanded_points: PackedVector2Array = []

	for pos in positions:
		# Add circle points around each model position
		for i in range(HULL_SMOOTHING):
			var angle = (float(i) / HULL_SMOOTHING) * TAU
			var offset = Vector2(cos(angle), sin(angle)) * padding
			expanded_points.append(pos + offset)

	# Compute convex hull
	return Geometry2D.convex_hull(expanded_points)


## Creates a circle shape for single model
func _create_circle(center: Vector2, radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	var segments = 16

	for i in range(segments):
		var angle = (float(i) / segments) * TAU
		var offset = Vector2(cos(angle), sin(angle)) * radius
		points.append(center + offset)

	return points


## Creates a capsule shape for two models
func _create_capsule(p1: Vector2, p2: Vector2, radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	var segments = 8  # Per semicircle

	var dir = (p2 - p1).normalized()
	var perp = Vector2(-dir.y, dir.x)

	# First semicircle around p1
	var start_angle = atan2(perp.y, perp.x)
	for i in range(segments + 1):
		var angle = start_angle + PI * (float(i) / segments)
		var offset = Vector2(cos(angle), sin(angle)) * radius
		points.append(p1 + offset)

	# Second semicircle around p2
	for i in range(segments + 1):
		var angle = start_angle + PI + PI * (float(i) / segments)
		var offset = Vector2(cos(angle), sin(angle)) * radius
		points.append(p2 + offset)

	return points


## Creates simple boundary for 1-2 models
func _create_simple_boundary(positions: Array, radius: float) -> PackedVector2Array:
	if positions.size() == 1:
		return _create_circle(positions[0], radius)
	elif positions.size() == 2:
		return _create_capsule(positions[0], positions[1], radius)
	return PackedVector2Array()


## Creates the 3D mesh for the boundary
func _create_boundary_mesh(game_unit, hull_points: PackedVector2Array, color: Color) -> void:
	if hull_points.size() < 3:
		return

	# Get or create boundary entry
	if game_unit not in _boundaries:
		var fill_mesh = MeshInstance3D.new()
		fill_mesh.name = "BoundaryFill"
		add_child(fill_mesh)

		var border_mesh = MeshInstance3D.new()
		border_mesh.name = "BoundaryBorder"
		add_child(border_mesh)

		_boundaries[game_unit] = {
			"fill": fill_mesh,
			"border": border_mesh
		}

	var entry = _boundaries[game_unit]
	var fill_instance = entry["fill"] as MeshInstance3D
	var border_instance = entry["border"] as MeshInstance3D

	# Create fill mesh (polygon)
	_create_fill_mesh(fill_instance, hull_points, color)

	# Create border mesh (outline)
	_create_border_mesh(border_instance, hull_points, color)


## Creates the filled polygon mesh
func _create_fill_mesh(mesh_instance: MeshInstance3D, hull_points: PackedVector2Array, color: Color) -> void:
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Triangulate the polygon
	var indices = Geometry2D.triangulate_polygon(hull_points)

	if indices.size() == 0:
		return

	# Add vertices
	for point in hull_points:
		surface_tool.add_vertex(Vector3(point.x, BOUNDARY_HEIGHT, point.y))

	# Add triangles (reversed for correct facing)
	for i in range(0, indices.size(), 3):
		surface_tool.add_index(indices[i])
		surface_tool.add_index(indices[i + 2])
		surface_tool.add_index(indices[i + 1])

	surface_tool.generate_normals()
	mesh_instance.mesh = surface_tool.commit()

	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, BOUNDARY_ALPHA)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from both sides
	mesh_instance.material_override = material


## Creates the border outline mesh
func _create_border_mesh(mesh_instance: MeshInstance3D, hull_points: PackedVector2Array, color: Color) -> void:
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var point_count = hull_points.size()
	if point_count < 3:
		return

	# Create thick line segments as quads
	for i in range(point_count):
		var p1 = hull_points[i]
		var p2 = hull_points[(i + 1) % point_count]

		var dir = (p2 - p1).normalized()
		var perp = Vector2(-dir.y, dir.x) * (BORDER_THICKNESS / 2.0)

		# Create quad vertices (inner and outer edge)
		var v0 = Vector3(p1.x - perp.x, BOUNDARY_HEIGHT + 0.001, p1.y - perp.y)
		var v1 = Vector3(p1.x + perp.x, BOUNDARY_HEIGHT + 0.001, p1.y + perp.y)
		var v2 = Vector3(p2.x + perp.x, BOUNDARY_HEIGHT + 0.001, p2.y + perp.y)
		var v3 = Vector3(p2.x - perp.x, BOUNDARY_HEIGHT + 0.001, p2.y - perp.y)

		# Add two triangles for the quad
		var base_idx = i * 4
		surface_tool.add_vertex(v0)
		surface_tool.add_vertex(v1)
		surface_tool.add_vertex(v2)
		surface_tool.add_vertex(v3)

		surface_tool.add_index(base_idx)
		surface_tool.add_index(base_idx + 1)
		surface_tool.add_index(base_idx + 2)

		surface_tool.add_index(base_idx)
		surface_tool.add_index(base_idx + 2)
		surface_tool.add_index(base_idx + 3)

	surface_tool.generate_normals()
	mesh_instance.mesh = surface_tool.commit()

	# Create material (slightly brighter than fill)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, BORDER_ALPHA)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.3
	mesh_instance.material_override = material


## Removes boundary visualization for a unit
func _remove_unit_boundary(game_unit) -> void:
	if game_unit in _boundaries:
		var entry = _boundaries[game_unit]
		if entry["fill"] and is_instance_valid(entry["fill"]):
			entry["fill"].queue_free()
		if entry["border"] and is_instance_valid(entry["border"]):
			entry["border"].queue_free()
		_boundaries.erase(game_unit)


## Clears all boundary visualizations
func clear_all() -> void:
	for game_unit in _boundaries.keys():
		_remove_unit_boundary(game_unit)
	_boundaries.clear()


## Toggles visibility of all boundaries
func set_boundaries_visible(visible_flag: bool) -> void:
	for entry in _boundaries.values():
		if entry["fill"] and is_instance_valid(entry["fill"]):
			entry["fill"].visible = visible_flag
		if entry["border"] and is_instance_valid(entry["border"]):
			entry["border"].visible = visible_flag
