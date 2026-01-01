extends Node3D
## Terrain Overlay - Displays terrain zones on the 3D table surface
##
## Shows colored, transparent overlays for each terrain type placed on the map layout editor.
## Meshes are positioned slightly above the table surface to prevent z-fighting.
##
## The overlay automatically updates when the map layout changes and applies rotation
## to match the grid orientation.

# ==============================================================================
# CONSTANTS
# ==============================================================================

const INCHES_TO_METERS := 0.0254
const GRID_SIZE_INCHES := 3.0

## Height offset above table to prevent z-fighting (2mm)
const Z_FIGHT_OFFSET := 0.002

## Mesh size reduction factor to show grid lines between cells
const CELL_SIZE_REDUCTION := 0.95

## Terrain type enumeration (matches map_layout.gd TerrainType enum)
enum TerrainType {
	NONE = 0,
	RUINS = 1,
	FOREST = 2,
	CONTAINER = 3,
	DANGEROUS = 4
}

# Terrain colors (matching map_layout.gd)
const TERRAIN_COLORS := {
	TerrainType.RUINS: Color(0.3, 0.5, 0.8, 0.4),      # Blue
	TerrainType.FOREST: Color(0.2, 0.6, 0.2, 0.4),     # Green
	TerrainType.CONTAINER: Color(0.6, 0.4, 0.2, 0.4),  # Brown
	TerrainType.DANGEROUS: Color(0.8, 0.2, 0.2, 0.4)   # Red
}

# ==============================================================================
# STATE
# ==============================================================================

var overlay_meshes: Array[MeshInstance3D] = []
var table_size_feet := Vector2(6, 4)


func _ready() -> void:
	# Position slightly above table surface to avoid z-fighting
	position.y = Z_FIGHT_OFFSET


## Clear all terrain overlay meshes from the scene
func clear_overlay() -> void:
	for mesh in overlay_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	overlay_meshes.clear()


## Update terrain overlay based on map layout
##
## @param grid_cells: Dictionary mapping Vector2i cell positions to terrain types
## @param table_size: Table dimensions in feet (Vector2)
## @param rotation_degrees: Grid rotation angle in degrees
func update_overlay(grid_cells: Dictionary, table_size: Vector2, rotation_degrees: float) -> void:
	# Validate inputs
	if not is_instance_valid(self):
		push_error("TerrainOverlay: Invalid instance during update")
		return

	if table_size.x <= 0 or table_size.y <= 0:
		push_error("TerrainOverlay: Invalid table size (%.1f, %.1f)" % [table_size.x, table_size.y])
		return

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
		if terrain_type == TerrainType.NONE:
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


## Create a mesh instance for a single terrain cell
##
## Creates a flat quad mesh with transparent colored material
##
## @param pos: World position for the mesh center
## @param size: Cell size in meters
## @param color: Terrain color with alpha for transparency
## @param rotation_degrees: Rotation angle to match grid orientation
## @return: Configured MeshInstance3D ready to be added to scene tree
func _create_cell_mesh(pos: Vector3, size: float, color: Color, rotation_degrees: float = 0.0) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	# Create a flat quad (slightly smaller to show grid lines between cells)
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(size * CELL_SIZE_REDUCTION, size * CELL_SIZE_REDUCTION)

	mesh_instance.mesh = plane_mesh
	mesh_instance.position = pos
	mesh_instance.rotation.y = deg_to_rad(rotation_degrees)  # Rotate to match grid

	# Create transparent, unshaded material
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from both sides

	mesh_instance.material_override = material

	return mesh_instance


## Toggle visibility of all terrain overlay meshes
##
## @param is_visible: true to show overlays, false to hide them
func set_visible_overlay(is_visible: bool) -> void:
	for mesh in overlay_meshes:
		if is_instance_valid(mesh):
			mesh.visible = is_visible
