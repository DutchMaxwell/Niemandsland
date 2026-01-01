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

## Deployment zone types
enum DeploymentType {
	NONE = 0,
	FRONT_LINE = 1,      # 12" from long table edges
	CORNER_DEPLOYMENT = 2,
	DAWN_ASSAULT = 3,
	PITCHED_BATTLE = 4,
	MEETING_ENGAGEMENT = 5
}

# Terrain colors (matching map_layout.gd)
const TERRAIN_COLORS := {
	TerrainType.RUINS: Color(0.3, 0.5, 0.8, 0.4),      # Blue
	TerrainType.FOREST: Color(0.2, 0.6, 0.2, 0.4),     # Green
	TerrainType.CONTAINER: Color(0.6, 0.4, 0.2, 0.4),  # Brown
	TerrainType.DANGEROUS: Color(0.8, 0.2, 0.2, 0.4)   # Red
}

# Deployment zone colors
const DEPLOYMENT_COLORS := {
	"player1": Color(0.2, 0.5, 1.0, 0.3),  # Blue for Player 1
	"player2": Color(1.0, 0.3, 0.2, 0.3)   # Red for Player 2
}

# ==============================================================================
# STATE
# ==============================================================================

var overlay_meshes: Array[MeshInstance3D] = []
var deployment_zone_meshes: Array[MeshInstance3D] = []
var table_size_feet := Vector2(6, 4)
var current_deployment_type := DeploymentType.NONE
var deployment_zones_visible := false


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

	# Update deployment zones when table size changes
	_update_deployment_zones()

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


## Set deployment zone type and create visualizations
##
## @param deployment_type: Type of deployment zone to display
func set_deployment_zones(deployment_type: int) -> void:
	current_deployment_type = deployment_type
	_update_deployment_zones()


## Toggle visibility of deployment zones
##
## @param is_visible: true to show deployment zones, false to hide them
func set_deployment_zones_visible(is_visible: bool) -> void:
	deployment_zones_visible = is_visible
	for mesh in deployment_zone_meshes:
		if is_instance_valid(mesh):
			mesh.visible = is_visible


## Clear all deployment zone meshes
func _clear_deployment_zones() -> void:
	for mesh in deployment_zone_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	deployment_zone_meshes.clear()


## Update deployment zone visualization based on current type
func _update_deployment_zones() -> void:
	_clear_deployment_zones()

	if current_deployment_type == DeploymentType.NONE:
		return

	# Convert table size from feet to meters
	var table_width_m = table_size_feet.x * 12.0 * INCHES_TO_METERS  # Long edge (X-axis)
	var table_depth_m = table_size_feet.y * 12.0 * INCHES_TO_METERS  # Short edge (Z-axis)

	match current_deployment_type:
		DeploymentType.FRONT_LINE:
			_create_front_line_zones(table_width_m, table_depth_m)
		DeploymentType.CORNER_DEPLOYMENT:
			_create_corner_deployment_zones(table_width_m, table_depth_m)
		DeploymentType.DAWN_ASSAULT:
			_create_dawn_assault_zones(table_width_m, table_depth_m)
		DeploymentType.PITCHED_BATTLE:
			_create_pitched_battle_zones(table_width_m, table_depth_m)
		DeploymentType.MEETING_ENGAGEMENT:
			_create_meeting_engagement_zones(table_width_m, table_depth_m)


## Create Front-line deployment zones (12" from long table edges)
func _create_front_line_zones(table_width: float, table_depth: float) -> void:
	var deployment_depth = 12.0 * INCHES_TO_METERS  # 12" deployment zone

	# Player 1 zone (bottom, facing forward along +Z)
	var p1_position = Vector3(0, 0, -table_depth/2 + deployment_depth/2)
	var p1_size = Vector2(table_width, deployment_depth)
	var p1_mesh = _create_deployment_zone_mesh(p1_position, p1_size, DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2 zone (top, facing backward along -Z)
	var p2_position = Vector3(0, 0, table_depth/2 - deployment_depth/2)
	var p2_size = Vector2(table_width, deployment_depth)
	var p2_mesh = _create_deployment_zone_mesh(p2_position, p2_size, DEPLOYMENT_COLORS["player2"])
	add_child(p2_mesh)
	deployment_zone_meshes.append(p2_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_mesh.visible = deployment_zones_visible


## Placeholder for Corner Deployment
func _create_corner_deployment_zones(table_width: float, table_depth: float) -> void:
	# TODO: Implement corner deployment zones
	pass


## Placeholder for Dawn Assault
func _create_dawn_assault_zones(table_width: float, table_depth: float) -> void:
	# TODO: Implement dawn assault zones
	pass


## Placeholder for Pitched Battle
func _create_pitched_battle_zones(table_width: float, table_depth: float) -> void:
	# TODO: Implement pitched battle zones
	pass


## Placeholder for Meeting Engagement
func _create_meeting_engagement_zones(table_width: float, table_depth: float) -> void:
	# TODO: Implement meeting engagement zones
	pass


## Create a mesh for a deployment zone
##
## @param pos: Center position of the deployment zone
## @param size: Size of the deployment zone (width, depth)
## @param color: Color of the deployment zone
## @return: Configured MeshInstance3D
func _create_deployment_zone_mesh(pos: Vector3, size: Vector2, color: Color) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	# Create a flat quad for the deployment zone
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = size

	mesh_instance.mesh = plane_mesh
	mesh_instance.position = pos

	# Create semi-transparent, unshaded material
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	mesh_instance.material_override = material

	return mesh_instance


## Check if a world position is within a deployment zone
##
## @param world_pos: Position to check (in 3D world coordinates)
## @return: Dictionary with keys: "in_zone" (bool), "player" (String: "player1"/"player2"/"none")
func is_position_in_deployment_zone(world_pos: Vector3) -> Dictionary:
	if current_deployment_type == DeploymentType.NONE:
		return {"in_zone": false, "player": "none"}

	var table_width_m = table_size_feet.x * 12.0 * INCHES_TO_METERS
	var table_depth_m = table_size_feet.y * 12.0 * INCHES_TO_METERS
	var deployment_depth = 12.0 * INCHES_TO_METERS

	match current_deployment_type:
		DeploymentType.FRONT_LINE:
			# Check if in Player 1 zone (bottom, -Z side)
			if world_pos.z >= (-table_depth_m/2) and world_pos.z <= (-table_depth_m/2 + deployment_depth):
				if abs(world_pos.x) <= table_width_m/2:
					return {"in_zone": true, "player": "player1"}

			# Check if in Player 2 zone (top, +Z side)
			if world_pos.z <= (table_depth_m/2) and world_pos.z >= (table_depth_m/2 - deployment_depth):
				if abs(world_pos.x) <= table_width_m/2:
					return {"in_zone": true, "player": "player2"}

	return {"in_zone": false, "player": "none"}


## Get terrain type at a world position
##
## @param world_pos: Position to check (in 3D world coordinates)
## @return: TerrainType enum value at that position
func get_terrain_at_world_position(world_pos: Vector3) -> int:
	# TODO: Implement terrain lookup based on grid_cells
	# This will be used for terrain hints (difficult terrain, dangerous, etc.)
	return TerrainType.NONE
