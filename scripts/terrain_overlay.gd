extends Node3D
## Terrain Overlay - Displays terrain zones on the 3D table surface
## Shows colored, transparent overlays for each terrain type

const INCHES_TO_METERS := 0.0254
const GRID_SIZE_INCHES := 3.0

# Terrain colors (matching map_layout.gd)
const TERRAIN_COLORS := {
	1: Color(0.3, 0.5, 0.8, 0.4),      # RUINS - Blue
	2: Color(0.2, 0.6, 0.2, 0.4),      # FOREST - Green
	3: Color(0.6, 0.4, 0.2, 0.4),      # CONTAINER - Brown
	4: Color(0.8, 0.2, 0.2, 0.4)       # DANGEROUS - Red
}

var overlay_meshes: Array[MeshInstance3D] = []
var table_size_feet := Vector2(6, 4)


func _ready() -> void:
	# Position slightly above table surface to avoid z-fighting
	position.y = 0.002


func clear_overlay() -> void:
	for mesh in overlay_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	overlay_meshes.clear()


func update_overlay(grid_cells: Dictionary, table_size: Vector2, rotation_degrees: float) -> void:
	clear_overlay()
	table_size_feet = table_size

	if grid_cells.is_empty():
		return

	# Calculate grid dimensions
	var grid_dims = Vector2i(
		int(ceil(table_size_feet.x * 12.0 / GRID_SIZE_INCHES)),
		int(ceil(table_size_feet.y * 12.0 / GRID_SIZE_INCHES))
	)

	var cell_size_meters = GRID_SIZE_INCHES * INCHES_TO_METERS
	var rotation_rad = deg_to_rad(rotation_degrees)

	# Create a mesh for each terrain cell
	for cell_pos in grid_cells:
		var terrain_type = grid_cells[cell_pos]
		if terrain_type == 0:  # NONE
			continue

		var color = TERRAIN_COLORS.get(terrain_type, Color.WHITE)

		# Calculate position in grid coordinates (before rotation)
		var local_x = (cell_pos.x + 0.5) * cell_size_meters - (grid_dims.x * cell_size_meters / 2.0)
		var local_z = (cell_pos.y + 0.5) * cell_size_meters - (grid_dims.y * cell_size_meters / 2.0)

		# Apply rotation around center (Y-axis in 3D = rotation in XZ plane)
		var rotated_x = local_x * cos(rotation_rad) - local_z * sin(rotation_rad)
		var rotated_z = local_x * sin(rotation_rad) + local_z * cos(rotation_rad)

		var mesh_instance = _create_cell_mesh(Vector3(rotated_x, 0, rotated_z), cell_size_meters, color, rotation_degrees)
		add_child(mesh_instance)
		overlay_meshes.append(mesh_instance)


func _create_cell_mesh(pos: Vector3, size: float, color: Color, rotation_degrees: float = 0.0) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	# Create a flat quad
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(size * 0.95, size * 0.95)  # Slightly smaller to show grid lines

	mesh_instance.mesh = plane_mesh
	mesh_instance.position = pos
	mesh_instance.rotation.y = deg_to_rad(rotation_degrees)  # Rotate the cell to match grid

	# Create transparent material
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	mesh_instance.material_override = material

	return mesh_instance


func set_visible_overlay(is_visible: bool) -> void:
	for mesh in overlay_meshes:
		if is_instance_valid(mesh):
			mesh.visible = is_visible
