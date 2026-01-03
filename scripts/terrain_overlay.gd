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

## Deployment zone types (18 total from OPR)
enum DeploymentType {
	NONE = 0,
	# Standard (1-6)
	FRONT_LINE = 1,          # 12" from long edges
	GROUND_WAR = 2,          # 12" from short edges
	SIDE_BATTLE = 3,         # 12" from one long edge each
	DISORDERED = 4,          # Two 15" radius circles
	SPEARHEAD = 5,           # Corner triangles (24" from corners)
	OPPOSING_FORCES = 6,     # Diagonal deployment
	# Asymmetric (7-12)
	OPEN_WARZONE = 7,        # Player 1: 12" from short edge, Player 2: 12" from long edges
	PUSHBACK = 8,            # Player 1: 18" from short edge, Player 2: 6" from opposite short
	CORNERED = 9,            # Player 1: 12" radius corner, Player 2: 18" from opposite short
	ENCIRCLED = 10,          # Player 1: 15" radius center, Player 2: 6" from all edges
	BEHIND_ENEMY_LINES = 11, # Player 1: 12" from short edge, Player 2: 12" from opposite long edges
	LIGHTNING_STRIKE = 12,   # Player 1: 6" from short edge, Player 2: 18" from all edges
	# Advanced (13-18)
	NO_MANS_LAND = 13,       # 9" from short edges
	LONG_HAUL = 14,          # 6" from long edges
	FLANK_ASSAULT = 15,      # 6" from one long edge each
	FRONTAL_CLASH = 16,      # 15" radius circles near short edges
	TACTICAL_PUSH = 17,      # 18" radius circles offset
	MEETING_ENGAGEMENT = 18  # Center rectangle zones
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
var grid_cells := {}  # Dictionary[Vector2i, TerrainType] - stores terrain data
var grid_rotation_degrees := 0.0


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
	grid_rotation_degrees = rotation_degrees

	print("TerrainOverlay.update_overlay: rotation = %.1f°, cells = %d" % [rotation_degrees, grid_cells.size()])

	# Store grid_cells for terrain lookup
	self.grid_cells = grid_cells

	# Update deployment zones when table size changes
	_update_deployment_zones()

	if grid_cells.is_empty():
		return

	# Use diagonal to ensure grid covers entire table at any rotation
	var width_inches = table_size_feet.x * 12.0
	var height_inches = table_size_feet.y * 12.0
	var diagonal = sqrt(width_inches * width_inches + height_inches * height_inches)
	var grid_size = int(ceil(diagonal / GRID_SIZE_INCHES))

	# Round UP to even number for intersection point at center
	if grid_size % 2 != 0:
		grid_size += 1

	var grid_dims = Vector2i(grid_size, grid_size)

	var cell_size_meters = GRID_SIZE_INCHES * INCHES_TO_METERS
	var rotation_rad = deg_to_rad(rotation_degrees)

	# Table bounds for culling cells outside the table
	var table_width_m = table_size_feet.x * 12.0 * INCHES_TO_METERS
	var table_depth_m = table_size_feet.y * 12.0 * INCHES_TO_METERS

	# Helper to check if a 2D point is within table bounds
	var is_point_in_table = func(x: float, z: float) -> bool:
		return abs(x) <= table_width_m / 2.0 and abs(z) <= table_depth_m / 2.0

	# Create a mesh for each terrain cell
	for cell_pos in grid_cells:
		var terrain_type = grid_cells[cell_pos]
		if terrain_type == TerrainType.NONE:
			continue

		var color = TERRAIN_COLORS.get(terrain_type, Color.WHITE)

		# Calculate cell center position in grid coordinates (grid centered on intersection)
		# Cells are offset by 0.5 from intersection points
		var local_x = (cell_pos.x - grid_dims.x / 2.0 + 0.5) * cell_size_meters
		var local_z = (cell_pos.y - grid_dims.y / 2.0 + 0.5) * cell_size_meters

		# Calculate all 4 corners of the cell in local space
		var half_cell = cell_size_meters / 2.0
		var corners_local = [
			Vector2(local_x - half_cell, local_z - half_cell),
			Vector2(local_x + half_cell, local_z - half_cell),
			Vector2(local_x + half_cell, local_z + half_cell),
			Vector2(local_x - half_cell, local_z + half_cell)
		]

		# Rotate all corners and check if any are inside table bounds
		var any_inside = false
		for corner in corners_local:
			var rotated_corner_x = corner.x * cos(rotation_rad) - corner.y * sin(rotation_rad)
			var rotated_corner_z = corner.x * sin(rotation_rad) + corner.y * cos(rotation_rad)
			if is_point_in_table.call(rotated_corner_x, rotated_corner_z):
				any_inside = true
				break

		# Skip cells that have no corners inside table
		if not any_inside:
			continue

		# Apply rotation to cell center for mesh positioning
		var rotated_x = local_x * cos(rotation_rad) - local_z * sin(rotation_rad)
		var rotated_z = local_x * sin(rotation_rad) + local_z * cos(rotation_rad)

		# Create mesh at rotated position WITH rotation to match grid
		var mesh_instance = _create_cell_mesh(Vector3(rotated_x, 0, rotated_z), cell_size_meters, color, rotation_degrees)
		add_child(mesh_instance)
		overlay_meshes.append(mesh_instance)


## Create a mesh instance for a single terrain cell
##
## Creates a flat quad mesh with transparent colored material
##
## @param pos: World position for the mesh center (already rotated)
## @param size: Cell size in meters
## @param color: Terrain color with alpha for transparency
## @param rotation_degrees: Grid rotation for the mesh itself
## @return: Configured MeshInstance3D ready to be added to scene tree
func _create_cell_mesh(pos: Vector3, size: float, color: Color, rotation_degrees: float = 0.0) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	# Create a flat quad (slightly smaller to show grid lines between cells)
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(size * CELL_SIZE_REDUCTION, size * CELL_SIZE_REDUCTION)

	mesh_instance.mesh = plane_mesh
	mesh_instance.position = pos
	# Negate rotation because Godot Y-axis rotation is clockwise (viewed from above)
	# while our position rotation is counter-clockwise
	mesh_instance.rotation.y = -deg_to_rad(rotation_degrees)

	if rotation_degrees != 0:
		print("  Created cell mesh: pos=(%.2f, %.2f, %.2f), rotation_y=%.1f° (negated)" % [pos.x, pos.y, pos.z, -rotation_degrees])

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
## @param show_overlay: true to show overlays, false to hide them
func set_visible_overlay(show_overlay: bool) -> void:
	for mesh in overlay_meshes:
		if is_instance_valid(mesh):
			mesh.visible = show_overlay


## Set deployment zone type and create visualizations
##
## @param deployment_type: Type of deployment zone to display
func set_deployment_zones(deployment_type: int) -> void:
	current_deployment_type = deployment_type
	_update_deployment_zones()


## Toggle visibility of deployment zones
##
## @param show_zones: true to show deployment zones, false to hide them
func set_deployment_zones_visible(show_zones: bool) -> void:
	deployment_zones_visible = show_zones
	for mesh in deployment_zone_meshes:
		if is_instance_valid(mesh):
			mesh.visible = show_zones


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
		# Standard (1-6)
		DeploymentType.FRONT_LINE:
			_create_front_line_zones(table_width_m, table_depth_m)
		DeploymentType.GROUND_WAR:
			_create_ground_war_zones(table_width_m, table_depth_m)
		DeploymentType.SIDE_BATTLE:
			_create_side_battle_zones(table_width_m, table_depth_m)
		DeploymentType.DISORDERED:
			_create_disordered_zones(table_width_m, table_depth_m)
		DeploymentType.SPEARHEAD:
			_create_spearhead_zones(table_width_m, table_depth_m)
		DeploymentType.OPPOSING_FORCES:
			_create_opposing_forces_zones(table_width_m, table_depth_m)
		# Asymmetric (7-12)
		DeploymentType.OPEN_WARZONE:
			_create_open_warzone_zones(table_width_m, table_depth_m)
		DeploymentType.PUSHBACK:
			_create_pushback_zones(table_width_m, table_depth_m)
		DeploymentType.CORNERED:
			_create_cornered_zones(table_width_m, table_depth_m)
		DeploymentType.ENCIRCLED:
			_create_encircled_zones(table_width_m, table_depth_m)
		DeploymentType.BEHIND_ENEMY_LINES:
			_create_behind_enemy_lines_zones(table_width_m, table_depth_m)
		DeploymentType.LIGHTNING_STRIKE:
			_create_lightning_strike_zones(table_width_m, table_depth_m)
		# Advanced (13-18)
		DeploymentType.NO_MANS_LAND:
			_create_no_mans_land_zones(table_width_m, table_depth_m)
		DeploymentType.LONG_HAUL:
			_create_long_haul_zones(table_width_m, table_depth_m)
		DeploymentType.FLANK_ASSAULT:
			_create_flank_assault_zones(table_width_m, table_depth_m)
		DeploymentType.FRONTAL_CLASH:
			_create_frontal_clash_zones(table_width_m, table_depth_m)
		DeploymentType.TACTICAL_PUSH:
			_create_tactical_push_zones(table_width_m, table_depth_m)
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


## STANDARD DEPLOYMENT ZONES (2-6)

## Ground War - 12" from short table edges
func _create_ground_war_zones(table_width: float, table_depth: float) -> void:
	var deployment_depth = 12.0 * INCHES_TO_METERS

	# Player 1 zone (left side, -X)
	var p1_position = Vector3(-table_width/2 + deployment_depth/2, 0, 0)
	var p1_size = Vector2(deployment_depth, table_depth)
	var p1_mesh = _create_deployment_zone_mesh(p1_position, p1_size, DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2 zone (right side, +X)
	var p2_position = Vector3(table_width/2 - deployment_depth/2, 0, 0)
	var p2_size = Vector2(deployment_depth, table_depth)
	var p2_mesh = _create_deployment_zone_mesh(p2_position, p2_size, DEPLOYMENT_COLORS["player2"])
	add_child(p2_mesh)
	deployment_zone_meshes.append(p2_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_mesh.visible = deployment_zones_visible


## Side Battle - 12" from one long edge each (split table horizontally)
func _create_side_battle_zones(table_width: float, table_depth: float) -> void:
	var deployment_depth = 12.0 * INCHES_TO_METERS

	# Player 1 zone (bottom half, -Z)
	var p1_position = Vector3(0, 0, -table_depth/4)
	var p1_size = Vector2(table_width, deployment_depth)
	var p1_mesh = _create_deployment_zone_mesh(p1_position, p1_size, DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2 zone (top half, +Z)
	var p2_position = Vector3(0, 0, table_depth/4)
	var p2_size = Vector2(table_width, deployment_depth)
	var p2_mesh = _create_deployment_zone_mesh(p2_position, p2_size, DEPLOYMENT_COLORS["player2"])
	add_child(p2_mesh)
	deployment_zone_meshes.append(p2_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_mesh.visible = deployment_zones_visible


## Disordered - Two 15" radius circles
func _create_disordered_zones(table_width: float, table_depth: float) -> void:
	var radius = 15.0 * INCHES_TO_METERS
	var circle_offset = table_depth / 4  # Place circles 1/4 from edges

	# Player 1 circle (bottom, -Z)
	var p1_position = Vector3(0, 0, -circle_offset)
	var p1_mesh = _create_circular_deployment_zone(p1_position, radius, DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2 circle (top, +Z)
	var p2_position = Vector3(0, 0, circle_offset)
	var p2_mesh = _create_circular_deployment_zone(p2_position, radius, DEPLOYMENT_COLORS["player2"])
	add_child(p2_mesh)
	deployment_zone_meshes.append(p2_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_mesh.visible = deployment_zones_visible


## Spearhead - Corner triangles (24" from corners)
func _create_spearhead_zones(table_width: float, table_depth: float) -> void:
	var corner_dist = 24.0 * INCHES_TO_METERS

	# Player 1 corners (bottom-left and bottom-right)
	# Bottom-left triangle
	var p1_bl_position = Vector3(-table_width/2 + corner_dist/2, 0, -table_depth/2 + corner_dist/2)
	var p1_bl_mesh = _create_deployment_zone_mesh(p1_bl_position, Vector2(corner_dist, corner_dist), DEPLOYMENT_COLORS["player1"])
	add_child(p1_bl_mesh)
	deployment_zone_meshes.append(p1_bl_mesh)

	# Bottom-right triangle
	var p1_br_position = Vector3(table_width/2 - corner_dist/2, 0, -table_depth/2 + corner_dist/2)
	var p1_br_mesh = _create_deployment_zone_mesh(p1_br_position, Vector2(corner_dist, corner_dist), DEPLOYMENT_COLORS["player1"])
	add_child(p1_br_mesh)
	deployment_zone_meshes.append(p1_br_mesh)

	# Player 2 corners (top-left and top-right)
	# Top-left triangle
	var p2_tl_position = Vector3(-table_width/2 + corner_dist/2, 0, table_depth/2 - corner_dist/2)
	var p2_tl_mesh = _create_deployment_zone_mesh(p2_tl_position, Vector2(corner_dist, corner_dist), DEPLOYMENT_COLORS["player2"])
	add_child(p2_tl_mesh)
	deployment_zone_meshes.append(p2_tl_mesh)

	# Top-right triangle
	var p2_tr_position = Vector3(table_width/2 - corner_dist/2, 0, table_depth/2 - corner_dist/2)
	var p2_tr_mesh = _create_deployment_zone_mesh(p2_tr_position, Vector2(corner_dist, corner_dist), DEPLOYMENT_COLORS["player2"])
	add_child(p2_tr_mesh)
	deployment_zone_meshes.append(p2_tr_mesh)

	for mesh in [p1_bl_mesh, p1_br_mesh, p2_tl_mesh, p2_tr_mesh]:
		mesh.visible = deployment_zones_visible


## Opposing Forces - Diagonal deployment
func _create_opposing_forces_zones(table_width: float, table_depth: float) -> void:
	var zone_width = 18.0 * INCHES_TO_METERS

	# Player 1 diagonal (bottom-left to top-left)
	var p1_width = zone_width
	var p1_depth = table_depth
	var p1_position = Vector3(-table_width/2 + p1_width/2, 0, 0)
	var p1_mesh = _create_deployment_zone_mesh(p1_position, Vector2(p1_width, p1_depth), DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2 diagonal (bottom-right to top-right)
	var p2_width = zone_width
	var p2_depth = table_depth
	var p2_position = Vector3(table_width/2 - p2_width/2, 0, 0)
	var p2_mesh = _create_deployment_zone_mesh(p2_position, Vector2(p2_width, p2_depth), DEPLOYMENT_COLORS["player2"])
	add_child(p2_mesh)
	deployment_zone_meshes.append(p2_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_mesh.visible = deployment_zones_visible


## ASYMMETRIC DEPLOYMENT ZONES (7-12)

## Open Warzone - P1: 12" from short edge, P2: 12" from long edges
func _create_open_warzone_zones(table_width: float, table_depth: float) -> void:
	var deployment_dist = 12.0 * INCHES_TO_METERS

	# Player 1: 12" from left short edge
	var p1_position = Vector3(-table_width/2 + deployment_dist/2, 0, 0)
	var p1_mesh = _create_deployment_zone_mesh(p1_position, Vector2(deployment_dist, table_depth), DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2: 12" from both long edges (top and bottom)
	var p2_bottom_position = Vector3(0, 0, -table_depth/2 + deployment_dist/2)
	var p2_bottom_mesh = _create_deployment_zone_mesh(p2_bottom_position, Vector2(table_width, deployment_dist), DEPLOYMENT_COLORS["player2"])
	add_child(p2_bottom_mesh)
	deployment_zone_meshes.append(p2_bottom_mesh)

	var p2_top_position = Vector3(0, 0, table_depth/2 - deployment_dist/2)
	var p2_top_mesh = _create_deployment_zone_mesh(p2_top_position, Vector2(table_width, deployment_dist), DEPLOYMENT_COLORS["player2"])
	add_child(p2_top_mesh)
	deployment_zone_meshes.append(p2_top_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_bottom_mesh.visible = deployment_zones_visible
	p2_top_mesh.visible = deployment_zones_visible


## Pushback - P1: 18" from short edge, P2: 6" from opposite short
func _create_pushback_zones(table_width: float, table_depth: float) -> void:
	var p1_depth = 18.0 * INCHES_TO_METERS
	var p2_depth = 6.0 * INCHES_TO_METERS

	# Player 1: 18" from left edge
	var p1_position = Vector3(-table_width/2 + p1_depth/2, 0, 0)
	var p1_mesh = _create_deployment_zone_mesh(p1_position, Vector2(p1_depth, table_depth), DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2: 6" from right edge
	var p2_position = Vector3(table_width/2 - p2_depth/2, 0, 0)
	var p2_mesh = _create_deployment_zone_mesh(p2_position, Vector2(p2_depth, table_depth), DEPLOYMENT_COLORS["player2"])
	add_child(p2_mesh)
	deployment_zone_meshes.append(p2_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_mesh.visible = deployment_zones_visible


## Cornered - P1: 12" radius corner, P2: 18" from opposite short
func _create_cornered_zones(table_width: float, table_depth: float) -> void:
	var p1_radius = 12.0 * INCHES_TO_METERS
	var p2_depth = 18.0 * INCHES_TO_METERS

	# Player 1: 12" radius circle in corner (bottom-left)
	var p1_position = Vector3(-table_width/2 + p1_radius, 0, -table_depth/2 + p1_radius)
	var p1_mesh = _create_circular_deployment_zone(p1_position, p1_radius, DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2: 18" from opposite short edge (right)
	var p2_position = Vector3(table_width/2 - p2_depth/2, 0, 0)
	var p2_mesh = _create_deployment_zone_mesh(p2_position, Vector2(p2_depth, table_depth), DEPLOYMENT_COLORS["player2"])
	add_child(p2_mesh)
	deployment_zone_meshes.append(p2_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_mesh.visible = deployment_zones_visible


## Encircled - P1: 15" radius center, P2: 6" from all edges
func _create_encircled_zones(table_width: float, table_depth: float) -> void:
	var p1_radius = 15.0 * INCHES_TO_METERS
	var p2_margin = 6.0 * INCHES_TO_METERS

	# Player 1: 15" radius circle in center
	var p1_position = Vector3(0, 0, 0)
	var p1_mesh = _create_circular_deployment_zone(p1_position, p1_radius, DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2: 6" from all edges (4 rectangles around the perimeter)
	# Top
	var p2_top = _create_deployment_zone_mesh(
		Vector3(0, 0, table_depth/2 - p2_margin/2),
		Vector2(table_width, p2_margin),
		DEPLOYMENT_COLORS["player2"]
	)
	add_child(p2_top)
	deployment_zone_meshes.append(p2_top)

	# Bottom
	var p2_bottom = _create_deployment_zone_mesh(
		Vector3(0, 0, -table_depth/2 + p2_margin/2),
		Vector2(table_width, p2_margin),
		DEPLOYMENT_COLORS["player2"]
	)
	add_child(p2_bottom)
	deployment_zone_meshes.append(p2_bottom)

	# Left
	var p2_left = _create_deployment_zone_mesh(
		Vector3(-table_width/2 + p2_margin/2, 0, 0),
		Vector2(p2_margin, table_depth - 2 * p2_margin),
		DEPLOYMENT_COLORS["player2"]
	)
	add_child(p2_left)
	deployment_zone_meshes.append(p2_left)

	# Right
	var p2_right = _create_deployment_zone_mesh(
		Vector3(table_width/2 - p2_margin/2, 0, 0),
		Vector2(p2_margin, table_depth - 2 * p2_margin),
		DEPLOYMENT_COLORS["player2"]
	)
	add_child(p2_right)
	deployment_zone_meshes.append(p2_right)

	for mesh in [p1_mesh, p2_top, p2_bottom, p2_left, p2_right]:
		mesh.visible = deployment_zones_visible


## Behind Enemy Lines - P1: 12" from short edge, P2: 12" from opposite long edges
func _create_behind_enemy_lines_zones(table_width: float, table_depth: float) -> void:
	var deployment_dist = 12.0 * INCHES_TO_METERS

	# Player 1: 12" from left short edge
	var p1_position = Vector3(-table_width/2 + deployment_dist/2, 0, 0)
	var p1_mesh = _create_deployment_zone_mesh(p1_position, Vector2(deployment_dist, table_depth), DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2: 12" from top and bottom long edges
	var p2_top_position = Vector3(0, 0, table_depth/2 - deployment_dist/2)
	var p2_top_mesh = _create_deployment_zone_mesh(p2_top_position, Vector2(table_width, deployment_dist), DEPLOYMENT_COLORS["player2"])
	add_child(p2_top_mesh)
	deployment_zone_meshes.append(p2_top_mesh)

	var p2_bottom_position = Vector3(0, 0, -table_depth/2 + deployment_dist/2)
	var p2_bottom_mesh = _create_deployment_zone_mesh(p2_bottom_position, Vector2(table_width, deployment_dist), DEPLOYMENT_COLORS["player2"])
	add_child(p2_bottom_mesh)
	deployment_zone_meshes.append(p2_bottom_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_top_mesh.visible = deployment_zones_visible
	p2_bottom_mesh.visible = deployment_zones_visible


## Lightning Strike - P1: 6" from short edge, P2: 18" from all edges
func _create_lightning_strike_zones(table_width: float, table_depth: float) -> void:
	var p1_depth = 6.0 * INCHES_TO_METERS
	var p2_margin = 18.0 * INCHES_TO_METERS

	# Player 1: 6" from left short edge
	var p1_position = Vector3(-table_width/2 + p1_depth/2, 0, 0)
	var p1_mesh = _create_deployment_zone_mesh(p1_position, Vector2(p1_depth, table_depth), DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2: 18" from all edges (center rectangle)
	var p2_width = table_width - 2 * p2_margin
	var p2_depth = table_depth - 2 * p2_margin
	var p2_position = Vector3(0, 0, 0)
	var p2_mesh = _create_deployment_zone_mesh(p2_position, Vector2(p2_width, p2_depth), DEPLOYMENT_COLORS["player2"])
	add_child(p2_mesh)
	deployment_zone_meshes.append(p2_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_mesh.visible = deployment_zones_visible


## ADVANCED DEPLOYMENT ZONES (13-18)

## No Man's Land - 9" from short edges
func _create_no_mans_land_zones(table_width: float, table_depth: float) -> void:
	var deployment_dist = 9.0 * INCHES_TO_METERS

	# Player 1 zone (left side)
	var p1_position = Vector3(-table_width/2 + deployment_dist/2, 0, 0)
	var p1_mesh = _create_deployment_zone_mesh(p1_position, Vector2(deployment_dist, table_depth), DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2 zone (right side)
	var p2_position = Vector3(table_width/2 - deployment_dist/2, 0, 0)
	var p2_mesh = _create_deployment_zone_mesh(p2_position, Vector2(deployment_dist, table_depth), DEPLOYMENT_COLORS["player2"])
	add_child(p2_mesh)
	deployment_zone_meshes.append(p2_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_mesh.visible = deployment_zones_visible


## Long Haul - 6" from long edges
func _create_long_haul_zones(table_width: float, table_depth: float) -> void:
	var deployment_depth = 6.0 * INCHES_TO_METERS

	# Player 1 zone (bottom)
	var p1_position = Vector3(0, 0, -table_depth/2 + deployment_depth/2)
	var p1_mesh = _create_deployment_zone_mesh(p1_position, Vector2(table_width, deployment_depth), DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2 zone (top)
	var p2_position = Vector3(0, 0, table_depth/2 - deployment_depth/2)
	var p2_mesh = _create_deployment_zone_mesh(p2_position, Vector2(table_width, deployment_depth), DEPLOYMENT_COLORS["player2"])
	add_child(p2_mesh)
	deployment_zone_meshes.append(p2_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_mesh.visible = deployment_zones_visible


## Flank Assault - 6" from one long edge each
func _create_flank_assault_zones(table_width: float, table_depth: float) -> void:
	var deployment_depth = 6.0 * INCHES_TO_METERS

	# Player 1 zone (bottom half)
	var p1_position = Vector3(0, 0, -table_depth/4)
	var p1_mesh = _create_deployment_zone_mesh(p1_position, Vector2(table_width, deployment_depth), DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2 zone (top half)
	var p2_position = Vector3(0, 0, table_depth/4)
	var p2_mesh = _create_deployment_zone_mesh(p2_position, Vector2(table_width, deployment_depth), DEPLOYMENT_COLORS["player2"])
	add_child(p2_mesh)
	deployment_zone_meshes.append(p2_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_mesh.visible = deployment_zones_visible


## Frontal Clash - 15" radius circles near short edges
func _create_frontal_clash_zones(table_width: float, table_depth: float) -> void:
	var radius = 15.0 * INCHES_TO_METERS
	var edge_offset = 15.0 * INCHES_TO_METERS  # Distance from edge to circle center

	# Player 1 circle (left side)
	var p1_position = Vector3(-table_width/2 + edge_offset, 0, 0)
	var p1_mesh = _create_circular_deployment_zone(p1_position, radius, DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2 circle (right side)
	var p2_position = Vector3(table_width/2 - edge_offset, 0, 0)
	var p2_mesh = _create_circular_deployment_zone(p2_position, radius, DEPLOYMENT_COLORS["player2"])
	add_child(p2_mesh)
	deployment_zone_meshes.append(p2_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_mesh.visible = deployment_zones_visible


## Tactical Push - 18" radius circles offset
func _create_tactical_push_zones(table_width: float, table_depth: float) -> void:
	var radius = 18.0 * INCHES_TO_METERS
	var x_offset = table_width / 4  # 1/4 from center
	var z_offset = table_depth / 4  # 1/4 from center

	# Player 1 circle (bottom-left quadrant)
	var p1_position = Vector3(-x_offset, 0, -z_offset)
	var p1_mesh = _create_circular_deployment_zone(p1_position, radius, DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2 circle (top-right quadrant)
	var p2_position = Vector3(x_offset, 0, z_offset)
	var p2_mesh = _create_circular_deployment_zone(p2_position, radius, DEPLOYMENT_COLORS["player2"])
	add_child(p2_mesh)
	deployment_zone_meshes.append(p2_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_mesh.visible = deployment_zones_visible


## Meeting Engagement - Center rectangle zones
func _create_meeting_engagement_zones(table_width: float, table_depth: float) -> void:
	var zone_width = 24.0 * INCHES_TO_METERS
	var zone_height = 18.0 * INCHES_TO_METERS
	var separation = 6.0 * INCHES_TO_METERS

	# Player 1 zone (left of center)
	var p1_position = Vector3(-separation/2 - zone_width/2, 0, 0)
	var p1_mesh = _create_deployment_zone_mesh(p1_position, Vector2(zone_width, zone_height), DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2 zone (right of center)
	var p2_position = Vector3(separation/2 + zone_width/2, 0, 0)
	var p2_mesh = _create_deployment_zone_mesh(p2_position, Vector2(zone_width, zone_height), DEPLOYMENT_COLORS["player2"])
	add_child(p2_mesh)
	deployment_zone_meshes.append(p2_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_mesh.visible = deployment_zones_visible


## Helper function to create circular deployment zones
func _create_circular_deployment_zone(center: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	# Create a cylinder mesh for circular zone (very flat)
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = radius
	cylinder_mesh.bottom_radius = radius
	cylinder_mesh.height = 0.001  # Very thin
	cylinder_mesh.radial_segments = 32  # Smooth circle

	mesh_instance.mesh = cylinder_mesh
	mesh_instance.position = center
	mesh_instance.rotation.x = 0  # Flat on table

	# Create semi-transparent material
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	mesh_instance.material_override = material

	return mesh_instance


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

	match current_deployment_type:
		DeploymentType.FRONT_LINE:
			var deployment_depth = 12.0 * INCHES_TO_METERS
			# Player 1 zone (bottom)
			if world_pos.z >= (-table_depth_m/2) and world_pos.z <= (-table_depth_m/2 + deployment_depth):
				if abs(world_pos.x) <= table_width_m/2:
					return {"in_zone": true, "player": "player1"}
			# Player 2 zone (top)
			if world_pos.z <= (table_depth_m/2) and world_pos.z >= (table_depth_m/2 - deployment_depth):
				if abs(world_pos.x) <= table_width_m/2:
					return {"in_zone": true, "player": "player2"}

		DeploymentType.GROUND_WAR:
			var deployment_depth = 12.0 * INCHES_TO_METERS
			# Player 1 zone (left)
			if world_pos.x >= (-table_width_m/2) and world_pos.x <= (-table_width_m/2 + deployment_depth):
				if abs(world_pos.z) <= table_depth_m/2:
					return {"in_zone": true, "player": "player1"}
			# Player 2 zone (right)
			if world_pos.x <= (table_width_m/2) and world_pos.x >= (table_width_m/2 - deployment_depth):
				if abs(world_pos.z) <= table_depth_m/2:
					return {"in_zone": true, "player": "player2"}

		DeploymentType.SIDE_BATTLE:
			var deployment_depth = 12.0 * INCHES_TO_METERS
			# Player 1 zone (bottom half)
			if abs(world_pos.x) <= table_width_m/2:
				if world_pos.z <= -table_depth_m/4 + deployment_depth/2 and world_pos.z >= -table_depth_m/4 - deployment_depth/2:
					return {"in_zone": true, "player": "player1"}
			# Player 2 zone (top half)
			if abs(world_pos.x) <= table_width_m/2:
				if world_pos.z >= table_depth_m/4 - deployment_depth/2 and world_pos.z <= table_depth_m/4 + deployment_depth/2:
					return {"in_zone": true, "player": "player2"}

		DeploymentType.DISORDERED:
			var radius = 15.0 * INCHES_TO_METERS
			var circle_offset = table_depth_m / 4
			# Player 1 circle (bottom)
			if world_pos.distance_to(Vector3(0, 0, -circle_offset)) <= radius:
				return {"in_zone": true, "player": "player1"}
			# Player 2 circle (top)
			if world_pos.distance_to(Vector3(0, 0, circle_offset)) <= radius:
				return {"in_zone": true, "player": "player2"}

		DeploymentType.SPEARHEAD:
			var corner_dist = 24.0 * INCHES_TO_METERS
			# Player 1 corners (bottom-left and bottom-right)
			var p1_bl_center = Vector3(-table_width_m/2 + corner_dist/2, 0, -table_depth_m/2 + corner_dist/2)
			var p1_br_center = Vector3(table_width_m/2 - corner_dist/2, 0, -table_depth_m/2 + corner_dist/2)
			if _is_in_rect(world_pos, p1_bl_center, Vector2(corner_dist, corner_dist)):
				return {"in_zone": true, "player": "player1"}
			if _is_in_rect(world_pos, p1_br_center, Vector2(corner_dist, corner_dist)):
				return {"in_zone": true, "player": "player1"}
			# Player 2 corners (top-left and top-right)
			var p2_tl_center = Vector3(-table_width_m/2 + corner_dist/2, 0, table_depth_m/2 - corner_dist/2)
			var p2_tr_center = Vector3(table_width_m/2 - corner_dist/2, 0, table_depth_m/2 - corner_dist/2)
			if _is_in_rect(world_pos, p2_tl_center, Vector2(corner_dist, corner_dist)):
				return {"in_zone": true, "player": "player2"}
			if _is_in_rect(world_pos, p2_tr_center, Vector2(corner_dist, corner_dist)):
				return {"in_zone": true, "player": "player2"}

		DeploymentType.OPPOSING_FORCES:
			var zone_width = 18.0 * INCHES_TO_METERS
			# Player 1 diagonal (left side)
			if world_pos.x >= -table_width_m/2 and world_pos.x <= -table_width_m/2 + zone_width:
				if abs(world_pos.z) <= table_depth_m/2:
					return {"in_zone": true, "player": "player1"}
			# Player 2 diagonal (right side)
			if world_pos.x <= table_width_m/2 and world_pos.x >= table_width_m/2 - zone_width:
				if abs(world_pos.z) <= table_depth_m/2:
					return {"in_zone": true, "player": "player2"}

		# Asymmetric deployment zones
		DeploymentType.OPEN_WARZONE:
			var deployment_dist = 12.0 * INCHES_TO_METERS
			# Player 1: left short edge
			if world_pos.x >= -table_width_m/2 and world_pos.x <= -table_width_m/2 + deployment_dist:
				if abs(world_pos.z) <= table_depth_m/2:
					return {"in_zone": true, "player": "player1"}
			# Player 2: top and bottom long edges
			if abs(world_pos.x) <= table_width_m/2:
				if world_pos.z >= table_depth_m/2 - deployment_dist or world_pos.z <= -table_depth_m/2 + deployment_dist:
					return {"in_zone": true, "player": "player2"}

		DeploymentType.NO_MANS_LAND:
			var deployment_dist = 9.0 * INCHES_TO_METERS
			# Player 1 (left)
			if world_pos.x >= -table_width_m/2 and world_pos.x <= -table_width_m/2 + deployment_dist:
				if abs(world_pos.z) <= table_depth_m/2:
					return {"in_zone": true, "player": "player1"}
			# Player 2 (right)
			if world_pos.x <= table_width_m/2 and world_pos.x >= table_width_m/2 - deployment_dist:
				if abs(world_pos.z) <= table_depth_m/2:
					return {"in_zone": true, "player": "player2"}

		# Add basic checks for remaining types (can be expanded)
		_:
			# For deployment types without specific logic yet, always return in_zone true
			# This prevents false warnings until all types are fully implemented
			return {"in_zone": true, "player": "unknown"}

	return {"in_zone": false, "player": "none"}


## Helper function to check if a position is inside a rectangle
func _is_in_rect(world_pos: Vector3, rect_center: Vector3, rect_size: Vector2) -> bool:
	var half_width = rect_size.x / 2.0
	var half_depth = rect_size.y / 2.0
	return abs(world_pos.x - rect_center.x) <= half_width and abs(world_pos.z - rect_center.z) <= half_depth


## Get terrain type at a world position
##
## @param world_pos: Position to check (in 3D world coordinates)
## @return: TerrainType enum value at that position
func get_terrain_at_world_position(world_pos: Vector3) -> int:
	if grid_cells.is_empty():
		return TerrainType.NONE

	# Use diagonal to match update_overlay grid dimensions
	var width_inches = table_size_feet.x * 12.0
	var height_inches = table_size_feet.y * 12.0
	var diagonal = sqrt(width_inches * width_inches + height_inches * height_inches)
	var grid_size = int(ceil(diagonal / GRID_SIZE_INCHES))

	# Round UP to even number for intersection point at center
	if grid_size % 2 != 0:
		grid_size += 1

	var grid_dims = Vector2i(grid_size, grid_size)

	var cell_size_meters = GRID_SIZE_INCHES * INCHES_TO_METERS
	var rotation_rad = deg_to_rad(grid_rotation_degrees)

	# Reverse rotation to get local coordinates
	var rotated_x = world_pos.x * cos(-rotation_rad) - world_pos.z * sin(-rotation_rad)
	var rotated_z = world_pos.x * sin(-rotation_rad) + world_pos.z * cos(-rotation_rad)

	# Convert to grid coordinates (centered grid)
	var grid_x = int(floor(rotated_x / cell_size_meters + grid_dims.x / 2.0))
	var grid_z = int(floor(rotated_z / cell_size_meters + grid_dims.y / 2.0))

	var cell_pos = Vector2i(grid_x, grid_z)

	# Lookup terrain type
	if grid_cells.has(cell_pos):
		return grid_cells[cell_pos]

	return TerrainType.NONE


## Check if terrain blocks line of sight
##
## @param terrain_type: TerrainType to check
## @param viewer_in_terrain: Is the viewer inside this terrain?
## @param target_in_terrain: Is the target inside this terrain?
## @return: true if LOS is blocked
func is_terrain_los_blocking(terrain_type: int, viewer_in_terrain: bool, target_in_terrain: bool) -> bool:
	match terrain_type:
		TerrainType.CONTAINER:
			# Container always blocks unless you can fly over
			return true
		TerrainType.FOREST, TerrainType.RUINS:
			# Forest/Ruins block LOS unless viewer or target is inside
			return not (viewer_in_terrain or target_in_terrain)

	return false
