extends Node3D
class_name UnitBoundaryVisualizer
## Visualizes unit boundaries with colored outlines.
## Shows which models belong to which unit at a glance.

## Height above ground for the boundary mesh
const BOUNDARY_HEIGHT := 0.005  # 5mm above table surface

## Padding around models (in meters)
const BOUNDARY_PADDING := 0.003  # 3mm from base edge

## Smoothing factor for the hull (higher = smoother, no gaps)
const HULL_SMOOTHING := 24

## Border line thickness
const BORDER_THICKNESS := 0.003  # 3mm thin border

## Border alpha
const BORDER_ALPHA := 0.9

## Player colors (must match OPRArmyManager.PLAYER_COLORS)
const PLAYER_COLORS = {
	1: Color(0.2, 0.4, 0.8),   # Blue
	2: Color(0.8, 0.2, 0.2),   # Red
	3: Color(0.2, 0.7, 0.2),   # Green
	4: Color(0.7, 0.5, 0.1),   # Orange/Gold
}

## Cached boundary meshes per GameUnit
var _boundaries: Dictionary = {}  # GameUnit -> MeshInstance3D (border only)

## Cached token containers per GameUnit (for unit-wide tokens)
var _token_containers: Dictionary = {}  # GameUnit -> Node3D

## Cached leftmost boundary point per GameUnit (for token positioning)
var _boundary_token_positions: Dictionary = {}  # GameUnit -> Vector3

## Reference to army manager for player colors
var army_manager = null  # OPRArmyManager

## Update timer for smooth updates
var _update_timer: float = 0.0
const UPDATE_INTERVAL := 0.1  # Update every 100ms


func _ready() -> void:
	# Find army manager only if not already set by parent
	if not army_manager:
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

	# Skip single models - the miniature IS the unit
	if models.size() <= 1:
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

	# Don't remove boundary if unit has multiple models but they're temporarily not in tree
	# (e.g., during arrangement operations)
	if positions.size() < 2:
		# Only remove if unit actually has <= 1 models total
		if models.size() <= 1:
			_remove_unit_boundary(game_unit)
		# Otherwise keep existing boundary, just don't update it
		return

	# Calculate expanded convex hull with padding
	var hull_points = _calculate_smooth_hull(positions, base_radius + BOUNDARY_PADDING)

	if hull_points.size() < 3:
		_remove_unit_boundary(game_unit)
		return

	# Create or update mesh (border only)
	_create_boundary_mesh(game_unit, hull_points, player_color)

	# Update token container position
	_update_token_container_position(game_unit)


## Calculates a smooth convex hull with padding around positions
func _calculate_smooth_hull(positions: Array, padding: float) -> PackedVector2Array:
	if positions.size() < 2:
		return PackedVector2Array()

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


## Creates the 3D mesh for the boundary (border only, no fill)
func _create_boundary_mesh(game_unit, hull_points: PackedVector2Array, color: Color) -> void:
	if hull_points.size() < 3:
		return

	# Get or create boundary entry
	if game_unit not in _boundaries:
		var border_mesh = MeshInstance3D.new()
		border_mesh.name = "UnitBoundary"
		add_child(border_mesh)
		_boundaries[game_unit] = border_mesh

	var border_instance = _boundaries[game_unit] as MeshInstance3D

	# Create border mesh (outline only)
	_create_border_mesh(border_instance, hull_points, color)

	# Find leftmost point on boundary for token positioning
	var leftmost_point = hull_points[0]
	for point in hull_points:
		if point.x < leftmost_point.x:
			leftmost_point = point
	_boundary_token_positions[game_unit] = Vector3(leftmost_point.x - 0.02, 0.015, leftmost_point.y)


## Creates the border outline mesh with smooth joins
func _create_border_mesh(mesh_instance: MeshInstance3D, hull_points: PackedVector2Array, color: Color) -> void:
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var point_count = hull_points.size()
	if point_count < 3:
		return

	var half_thickness = BORDER_THICKNESS / 2.0

	# Create thick line segments as quads with mitered corners
	for i in range(point_count):
		var p0 = hull_points[(i - 1 + point_count) % point_count]
		var p1 = hull_points[i]
		var p2 = hull_points[(i + 1) % point_count]
		var p3 = hull_points[(i + 2) % point_count]

		# Direction vectors
		var dir1 = (p2 - p1).normalized()
		var dir2 = (p3 - p2).normalized()

		# Perpendicular vectors
		var perp1 = Vector2(-dir1.y, dir1.x) * half_thickness
		var perp2 = Vector2(-dir2.y, dir2.x) * half_thickness

		# Create quad vertices for this segment
		var v0 = Vector3(p1.x - perp1.x, BOUNDARY_HEIGHT, p1.y - perp1.y)
		var v1 = Vector3(p1.x + perp1.x, BOUNDARY_HEIGHT, p1.y + perp1.y)
		var v2 = Vector3(p2.x + perp1.x, BOUNDARY_HEIGHT, p2.y + perp1.y)
		var v3 = Vector3(p2.x - perp1.x, BOUNDARY_HEIGHT, p2.y - perp1.y)

		# Add vertices and triangles
		var base_idx = i * 4
		surface_tool.add_vertex(v0)
		surface_tool.add_vertex(v1)
		surface_tool.add_vertex(v2)
		surface_tool.add_vertex(v3)

		# Two triangles for the quad
		surface_tool.add_index(base_idx)
		surface_tool.add_index(base_idx + 1)
		surface_tool.add_index(base_idx + 2)

		surface_tool.add_index(base_idx)
		surface_tool.add_index(base_idx + 2)
		surface_tool.add_index(base_idx + 3)

	surface_tool.generate_normals()
	mesh_instance.mesh = surface_tool.commit()

	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, BORDER_ALPHA)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material


## Removes boundary visualization for a unit
func _remove_unit_boundary(game_unit) -> void:
	if game_unit in _boundaries:
		var mesh = _boundaries[game_unit]
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
		_boundaries.erase(game_unit)

	# Also remove token container if unit no longer has boundary
	if game_unit in _token_containers:
		var container = _token_containers[game_unit]
		if container and is_instance_valid(container):
			container.queue_free()
		_token_containers.erase(game_unit)


## Clears all boundary visualizations
func clear_all() -> void:
	for game_unit in _boundaries.keys():
		_remove_unit_boundary(game_unit)
	_boundaries.clear()


## Toggles visibility of all boundaries
func set_boundaries_visible(visible_flag: bool) -> void:
	for mesh in _boundaries.values():
		if mesh and is_instance_valid(mesh):
			mesh.visible = visible_flag


## Gets the token container for a unit (creates one if needed).
## Unit-wide tokens (Shaken, Fatigue, Activated) should be parented to this.
func get_token_container(game_unit) -> Node3D:
	if game_unit in _token_containers:
		var container = _token_containers[game_unit]
		if is_instance_valid(container):
			return container

	# Create new container
	var container = Node3D.new()
	container.name = "UnitTokenContainer"
	add_child(container)
	_token_containers[game_unit] = container

	# Position it at unit center
	_update_token_container_position(game_unit)

	return container


## Updates the token container position to the boundary edge.
func _update_token_container_position(game_unit) -> void:
	if game_unit not in _token_containers:
		return

	var container = _token_containers[game_unit]
	if not container or not is_instance_valid(container):
		return

	# Use the pre-calculated boundary position (leftmost point)
	if game_unit in _boundary_token_positions:
		container.global_position = _boundary_token_positions[game_unit]


## Checks if a unit has multiple models (uses boundary visualization).
func has_boundary(game_unit) -> bool:
	return game_unit in _boundaries
