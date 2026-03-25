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
const FINE_GRID_SIZE_INCHES := 1.0  # 1" grid for custom zone editing

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

## Overlay display mode for terrain visualization
## FLAT: Colored 2D planes only (default, existing behavior)
## MODELS: 3D GLB models only (generated terrain)
## BOTH: 2D planes + 3D models overlaid
enum OverlayMode {
	FLAT = 0,
	MODELS = 1,
	BOTH = 2
}

## Deployment zone types
## NOTE: Only FRONT_LINE is included from OPR free rules.
## Other deployment types (Ground War, Spearhead, etc.) are behind OPR's paywall.
## CUSTOM allows players to draw their own deployment zones using polygon vertices.
enum DeploymentType {
	NONE = 0,
	FRONT_LINE = 1,   # 12" from long edges (OPR free rules)
	CUSTOM = 2        # User-defined polygon zones
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

## Overlay mode: FLAT (2D planes), MODELS (3D GLBs), BOTH
var overlay_mode := OverlayMode.FLAT

## Currently loaded terrain theme key (empty = none)
var terrain_theme_key := ""

## Custom deployment zone polygons (in meters, world coordinates)
## Each zone is an array of Vector3 points defining the polygon vertices
var custom_zone_player1: Array[Vector3] = []
var custom_zone_player2: Array[Vector3] = []

## Custom zone editing mode
enum CustomZoneMode {
	NONE,           # Not editing custom zones
	SYMMETRIC,      # Both zones mirrored (point-symmetric around table center)
	ASYMMETRIC_P1,  # Drawing Player 1 zone
	ASYMMETRIC_P2   # Drawing Player 2 zone
}
var custom_zone_mode := CustomZoneMode.NONE

## Signal emitted when custom zone editing state changes
signal custom_zone_editing_changed(is_editing: bool, mode: CustomZoneMode)
signal custom_zone_vertex_added(player: int, vertex: Vector3)
signal custom_zone_completed(player: int)

## Fine grid (1") for custom zone editing
var fine_grid_meshes: Array[MeshInstance3D] = []
var fine_grid_visible := false

## Vertex markers showing placed polygon points during editing
var vertex_markers: Array[MeshInstance3D] = []
var preview_line_mesh: MeshInstance3D = null

## Mission objectives - displayed as markers with 3" seize radius
var objective_meshes: Array[Node3D] = []  # Can be MeshInstance3D or Node3D containers
var objective_ring_meshes: Array[MeshInstance3D] = []
var mission_objectives: Array[Vector3] = []  # World positions in meters

## Battle Map background mesh (full table size)
var _battle_map_mesh: MeshInstance3D = null

## Base plate textures (terrain_type_name -> ImageTexture)
var _base_plate_textures: Dictionary = {}

## Terrain Library reference for GLB loading
var terrain_library: Node = null

## Wall model cache and instances
var _wall_model_cache: Dictionary = {}   ## wall_glb_path -> PackedScene/Node3D
var _wall_instances: Array[Node3D] = []

## Placed object instances (trees + containers)
var _object_instances: Array[Node3D] = []


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
## @param cells_data: Dictionary mapping Vector2i cell positions to terrain types
## @param table_size: Table dimensions in feet (Vector2)
## @param grid_rotation: Grid rotation angle in degrees
func update_overlay(cells_data: Dictionary, table_size: Vector2, grid_rotation: float) -> void:
	# Validate inputs
	if not is_instance_valid(self):
		push_error("TerrainOverlay: Invalid instance during update")
		return

	if table_size.x <= 0 or table_size.y <= 0:
		push_error("TerrainOverlay: Invalid table size (%.1f, %.1f)" % [table_size.x, table_size.y])
		return

	clear_overlay()
	table_size_feet = table_size
	grid_rotation_degrees = grid_rotation

	print("TerrainOverlay.update_overlay: rotation = %.1f°, cells = %d" % [grid_rotation, cells_data.size()])

	# Store grid_cells for terrain lookup
	self.grid_cells = cells_data

	# Update deployment zones when table size changes
	_update_deployment_zones()

	if cells_data.is_empty():
		return

	var grid_dims := _calculate_grid_dims(table_size)
	var cell_size_meters := GRID_SIZE_INCHES * INCHES_TO_METERS
	var rotation_rad := deg_to_rad(grid_rotation)
	var table_width_m := table_size_feet.x * 12.0 * INCHES_TO_METERS
	var table_depth_m := table_size_feet.y * 12.0 * INCHES_TO_METERS

	# Build connected regions for seamless rendering
	var regions := _get_connected_regions(cells_data)

	if not _base_plate_textures.is_empty() and not regions.is_empty():
		# Textured path: one seamless mesh per connected region + border outlines
		for region in regions:
			var terrain_type: int = region["terrain_type"]
			var cells: Array = region["cells"]
			# Filter cells to only those within table bounds
			var visible_cells: Array[Vector2i] = []
			for cell_pos in cells:
				if _is_cell_visible(cell_pos, grid_dims, cell_size_meters, rotation_rad, table_width_m, table_depth_m):
					visible_cells.append(cell_pos)
			if visible_cells.is_empty():
				continue
			# Create one seamless mesh for the entire region
			var mesh_instance := _create_connected_region_mesh(visible_cells, terrain_type, grid_dims, cell_size_meters, rotation_rad, grid_rotation)
			if mesh_instance:
				mesh_instance.visible = true
				add_child(mesh_instance)
				overlay_meshes.append(mesh_instance)
			# Create border outline around the region
			var border_mesh := _create_region_border(visible_cells, terrain_type, grid_dims, cell_size_meters, rotation_rad)
			if border_mesh:
				border_mesh.visible = true
				add_child(border_mesh)
				overlay_meshes.append(border_mesh)
	else:
		# Fallback: per-cell colored planes (no textures loaded)
		for cell_pos: Vector2i in cells_data:
			var terrain_type: int = cells_data[cell_pos]
			if terrain_type == TerrainType.NONE:
				continue
			if not _is_cell_visible(cell_pos, grid_dims, cell_size_meters, rotation_rad, table_width_m, table_depth_m):
				continue
			var color: Color = TERRAIN_COLORS.get(terrain_type, Color.WHITE)
			var local_x: float = (cell_pos.x - grid_dims.x / 2.0 + 0.5) * cell_size_meters
			var local_z: float = (cell_pos.y - grid_dims.y / 2.0 + 0.5) * cell_size_meters
			var rotated_x: float = local_x * cos(rotation_rad) - local_z * sin(rotation_rad)
			var rotated_z: float = local_x * sin(rotation_rad) + local_z * cos(rotation_rad)
			var mesh_instance := _create_cell_mesh(Vector3(rotated_x, 0, rotated_z), cell_size_meters, color, grid_rotation)
			mesh_instance.visible = true
			add_child(mesh_instance)
			overlay_meshes.append(mesh_instance)

	print("TerrainOverlay: Created %d mesh instances from %d cells_data entries" % [overlay_meshes.size(), cells_data.size()])


## Calculate grid dimensions from table size
func _calculate_grid_dims(table_size: Vector2) -> Vector2i:
	var width_inches := table_size.x * 12.0
	var height_inches := table_size.y * 12.0
	var diagonal := sqrt(width_inches * width_inches + height_inches * height_inches)
	var grid_size := int(ceil(diagonal / GRID_SIZE_INCHES))
	if grid_size % 2 != 0:
		grid_size += 1
	return Vector2i(grid_size, grid_size)


## Check if a cell has any corner within table bounds (for culling)
func _is_cell_visible(cell_pos: Vector2i, grid_dims: Vector2i, cell_size_meters: float, rotation_rad: float, table_width_m: float, table_depth_m: float) -> bool:
	var local_x := (cell_pos.x - grid_dims.x / 2.0 + 0.5) * cell_size_meters
	var local_z := (cell_pos.y - grid_dims.y / 2.0 + 0.5) * cell_size_meters
	var half_cell := cell_size_meters / 2.0
	var corners: Array[Vector2] = [
		Vector2(local_x - half_cell, local_z - half_cell),
		Vector2(local_x + half_cell, local_z - half_cell),
		Vector2(local_x + half_cell, local_z + half_cell),
		Vector2(local_x - half_cell, local_z + half_cell)
	]
	for corner: Vector2 in corners:
		var rx: float = corner.x * cos(rotation_rad) - corner.y * sin(rotation_rad)
		var rz: float = corner.x * sin(rotation_rad) + corner.y * cos(rotation_rad)
		if abs(rx) <= table_width_m / 2.0 and abs(rz) <= table_depth_m / 2.0:
			return true
	return false


## Get connected regions from cells_data using flood-fill
func _get_connected_regions(cells_data: Dictionary) -> Array[Dictionary]:
	var visited := {}
	var regions: Array[Dictionary] = []
	for cell_pos: Vector2i in cells_data:
		if visited.has(cell_pos):
			continue
		var terrain_type: int = cells_data[cell_pos]
		if terrain_type == TerrainType.NONE:
			continue
		var region_cells: Array[Vector2i] = []
		var stack: Array[Vector2i] = [cell_pos]
		while stack.size() > 0:
			var current: Vector2i = stack.pop_back()
			if visited.has(current):
				continue
			if not cells_data.has(current):
				continue
			if cells_data[current] != terrain_type:
				continue
			visited[current] = true
			region_cells.append(current)
			stack.append(Vector2i(current.x + 1, current.y))
			stack.append(Vector2i(current.x - 1, current.y))
			stack.append(Vector2i(current.x, current.y + 1))
			stack.append(Vector2i(current.x, current.y - 1))
		regions.append({"terrain_type": terrain_type, "cells": region_cells})
	return regions


## Create one seamless mesh for a connected region of cells using SurfaceTool
func _create_connected_region_mesh(cells: Array[Vector2i], terrain_type: int, grid_dims: Vector2i, cell_size_meters: float, rotation_rad: float, grid_rotation: float) -> MeshInstance3D:
	if cells.is_empty():
		return null

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var cos_r := cos(rotation_rad)
	var sin_r := sin(rotation_rad)
	var half_cell := cell_size_meters / 2.0

	for cell_pos: Vector2i in cells:
		var local_x: float = (cell_pos.x - grid_dims.x / 2.0 + 0.5) * cell_size_meters
		var local_z: float = (cell_pos.y - grid_dims.y / 2.0 + 0.5) * cell_size_meters

		# 4 corners of the cell (NO size reduction — seamless)
		var corners_local: Array[Vector2] = [
			Vector2(local_x - half_cell, local_z - half_cell),  # top-left
			Vector2(local_x + half_cell, local_z - half_cell),  # top-right
			Vector2(local_x + half_cell, local_z + half_cell),  # bottom-right
			Vector2(local_x - half_cell, local_z + half_cell),  # bottom-left
		]

		# Rotate corners to world space
		var world_corners: Array[Vector3] = []
		for c: Vector2 in corners_local:
			var rx: float = c.x * cos_r - c.y * sin_r
			var rz: float = c.x * sin_r + c.y * cos_r
			world_corners.append(Vector3(rx, 0, rz))

		# UV: tile based on cell position for seamless tiling
		var uv_base := Vector2(float(cell_pos.x), float(cell_pos.y))
		var uvs := [
			uv_base,                                    # top-left
			uv_base + Vector2(1, 0),                    # top-right
			uv_base + Vector2(1, 1),                    # bottom-right
			uv_base + Vector2(0, 1),                    # bottom-left
		]

		# Triangle 1: top-left, top-right, bottom-right
		st.set_uv(uvs[0])
		st.set_normal(Vector3.UP)
		st.add_vertex(world_corners[0])
		st.set_uv(uvs[1])
		st.set_normal(Vector3.UP)
		st.add_vertex(world_corners[1])
		st.set_uv(uvs[2])
		st.set_normal(Vector3.UP)
		st.add_vertex(world_corners[2])

		# Triangle 2: top-left, bottom-right, bottom-left
		st.set_uv(uvs[0])
		st.set_normal(Vector3.UP)
		st.add_vertex(world_corners[0])
		st.set_uv(uvs[2])
		st.set_normal(Vector3.UP)
		st.add_vertex(world_corners[2])
		st.set_uv(uvs[3])
		st.set_normal(Vector3.UP)
		st.add_vertex(world_corners[3])

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()

	# Apply base plate texture material
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var type_name := _terrain_type_to_name(terrain_type)
	if _base_plate_textures.has(type_name):
		material.albedo_texture = _base_plate_textures[type_name]
		material.albedo_color = Color(1, 1, 1, 0.8)
		# Enable UV tiling/repeat for seamless textures
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		material.uv1_scale = Vector3(1, 1, 1)
	else:
		var color: Color = TERRAIN_COLORS.get(terrain_type, Color.WHITE)
		material.albedo_color = color

	mesh_instance.material_override = material
	return mesh_instance


## Create border outline around a connected region using ImmediateMesh
func _create_region_border(cells: Array[Vector2i], terrain_type: int, grid_dims: Vector2i, cell_size_meters: float, rotation_rad: float) -> MeshInstance3D:
	if cells.is_empty():
		return null

	# Build a set for fast lookup
	var cell_set := {}
	for c: Vector2i in cells:
		cell_set[c] = true

	var cos_r := cos(rotation_rad)
	var sin_r := sin(rotation_rad)
	var half_cell := cell_size_meters / 2.0

	# Collect outer edge segments: for each cell, check 4 neighbors
	# If neighbor is NOT in the region, that edge is an outer border
	var edge_segments: Array[Array] = []  # Array of [Vector3, Vector3] line pairs

	for cell_pos: Vector2i in cells:
		var local_x: float = (cell_pos.x - grid_dims.x / 2.0 + 0.5) * cell_size_meters
		var local_z: float = (cell_pos.y - grid_dims.y / 2.0 + 0.5) * cell_size_meters

		# Check each of the 4 edges
		# North (-Y in grid = -Z in local): neighbor at (x, y-1)
		if not cell_set.has(Vector2i(cell_pos.x, cell_pos.y - 1)):
			var p1 := Vector2(local_x - half_cell, local_z - half_cell)
			var p2 := Vector2(local_x + half_cell, local_z - half_cell)
			edge_segments.append([p1, p2])
		# East (+X): neighbor at (x+1, y)
		if not cell_set.has(Vector2i(cell_pos.x + 1, cell_pos.y)):
			var p1 := Vector2(local_x + half_cell, local_z - half_cell)
			var p2 := Vector2(local_x + half_cell, local_z + half_cell)
			edge_segments.append([p1, p2])
		# South (+Y in grid = +Z in local): neighbor at (x, y+1)
		if not cell_set.has(Vector2i(cell_pos.x, cell_pos.y + 1)):
			var p1 := Vector2(local_x + half_cell, local_z + half_cell)
			var p2 := Vector2(local_x - half_cell, local_z + half_cell)
			edge_segments.append([p1, p2])
		# West (-X): neighbor at (x-1, y)
		if not cell_set.has(Vector2i(cell_pos.x - 1, cell_pos.y)):
			var p1 := Vector2(local_x - half_cell, local_z + half_cell)
			var p2 := Vector2(local_x - half_cell, local_z - half_cell)
			edge_segments.append([p1, p2])

	if edge_segments.is_empty():
		return null

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	for seg: Array in edge_segments:
		var p1: Vector2 = seg[0]
		var p2: Vector2 = seg[1]
		# Rotate to world space
		var rx1: float = p1.x * cos_r - p1.y * sin_r
		var rz1: float = p1.x * sin_r + p1.y * cos_r
		var rx2: float = p2.x * cos_r - p2.y * sin_r
		var rz2: float = p2.x * sin_r + p2.y * cos_r
		# Y=0.0005 local → sits just above base plate surface but below deployment zones
		im.surface_add_vertex(Vector3(rx1, 0.0005, rz1))
		im.surface_add_vertex(Vector3(rx2, 0.0005, rz2))

	im.surface_end()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = im

	# Border color: terrain color at full opacity, slightly darkened
	var base_color: Color = TERRAIN_COLORS.get(terrain_type, Color.WHITE)
	var border_color := Color(base_color.r * 0.7, base_color.g * 0.7, base_color.b * 0.7, 1.0)

	var material := StandardMaterial3D.new()
	material.albedo_color = border_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material

	return mesh_instance


## Create a mesh instance for a single terrain cell
##
## Creates a flat quad mesh with transparent colored material
##
## @param pos: World position for the mesh center (already rotated)
## @param cell_size: Cell size in meters
## @param color: Terrain color with alpha for transparency
## @param grid_rotation: Grid rotation for the mesh itself
## @return: Configured MeshInstance3D ready to be added to scene tree
func _create_cell_mesh(pos: Vector3, cell_size: float, color: Color, grid_rotation: float = 0.0) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	# Create a flat quad (slightly smaller to show grid lines between cells)
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(cell_size * CELL_SIZE_REDUCTION, cell_size * CELL_SIZE_REDUCTION)

	mesh_instance.mesh = plane_mesh
	mesh_instance.position = pos
	# Negate rotation because Godot Y-axis rotation is clockwise (viewed from above)
	# while our position rotation is counter-clockwise
	mesh_instance.rotation.y = -deg_to_rad(grid_rotation)

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
		DeploymentType.FRONT_LINE:
			_create_front_line_zones(table_width_m, table_depth_m)
		DeploymentType.CUSTOM:
			_create_custom_polygon_zones()


## Create Front-line deployment zones (12" from long table edges)
func _create_front_line_zones(table_width: float, table_depth: float) -> void:
	var deployment_depth = 12.0 * INCHES_TO_METERS  # 12" deployment zone

	# Player 1 zone (bottom, facing forward along +Z)
	# Y=0.001 local → absolute Y=0.003 (above base plates at Y=0.002)
	var p1_position = Vector3(0, 0.001, -table_depth/2 + deployment_depth/2)
	var p1_size = Vector2(table_width, deployment_depth)
	var p1_mesh = _create_deployment_zone_mesh(p1_position, p1_size, DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2 zone (top, facing backward along -Z)
	var p2_position = Vector3(0, 0.001, table_depth/2 - deployment_depth/2)
	var p2_size = Vector2(table_width, deployment_depth)
	var p2_mesh = _create_deployment_zone_mesh(p2_position, p2_size, DEPLOYMENT_COLORS["player2"])
	add_child(p2_mesh)
	deployment_zone_meshes.append(p2_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_mesh.visible = deployment_zones_visible


# ==============================================================================
# CUSTOM POLYGON DEPLOYMENT ZONES
# ==============================================================================

## Create custom polygon deployment zones from stored vertices
func _create_custom_polygon_zones() -> void:
	# Create Player 1 zone if vertices exist
	if custom_zone_player1.size() >= 3:
		var p1_mesh = _create_polygon_zone_mesh(custom_zone_player1, DEPLOYMENT_COLORS["player1"])
		add_child(p1_mesh)
		deployment_zone_meshes.append(p1_mesh)
		p1_mesh.visible = deployment_zones_visible

	# Create Player 2 zone if vertices exist
	if custom_zone_player2.size() >= 3:
		var p2_mesh = _create_polygon_zone_mesh(custom_zone_player2, DEPLOYMENT_COLORS["player2"])
		add_child(p2_mesh)
		deployment_zone_meshes.append(p2_mesh)
		p2_mesh.visible = deployment_zones_visible


## Create a mesh from polygon vertices using triangulation
func _create_polygon_zone_mesh(vertices: Array[Vector3], color: Color) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	if vertices.size() < 3:
		return mesh_instance

	# Convert 3D vertices to 2D for triangulation (XZ plane)
	var points_2d: PackedVector2Array = PackedVector2Array()
	for v in vertices:
		points_2d.append(Vector2(v.x, v.z))

	# Triangulate the polygon
	var indices = Geometry2D.triangulate_polygon(points_2d)
	if indices.is_empty():
		push_warning("TerrainOverlay: Failed to triangulate custom zone polygon")
		return mesh_instance

	# Create mesh using SurfaceTool
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Add vertices
	for i in range(indices.size()):
		var idx = indices[i]
		var v = vertices[idx]
		st.add_vertex(Vector3(v.x, 0.001, v.z))  # Slightly above ground

	st.generate_normals()
	mesh_instance.mesh = st.commit()

	# Create semi-transparent material
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	mesh_instance.material_override = material

	return mesh_instance


# ==============================================================================
# CUSTOM ZONE EDITING API
# ==============================================================================

## Start editing custom deployment zones
## @param symmetric: If true, both zones are drawn simultaneously (point-symmetric)
func start_custom_zone_editing(symmetric: bool) -> void:
	if symmetric:
		custom_zone_mode = CustomZoneMode.SYMMETRIC
	else:
		custom_zone_mode = CustomZoneMode.ASYMMETRIC_P1

	# Clear existing custom zones
	custom_zone_player1.clear()
	custom_zone_player2.clear()

	# Show fine grid for vertex placement
	show_fine_grid()
	_clear_vertex_markers()

	custom_zone_editing_changed.emit(true, custom_zone_mode)
	print("Custom zone editing started: %s" % ("symmetric" if symmetric else "asymmetric P1"))


## Add a vertex to the current custom zone being edited
## @param world_pos: Position in world coordinates (meters)
## Note: Position is automatically snapped to 1" grid intersection
func add_custom_zone_vertex(world_pos: Vector3) -> void:
	# Snap to 1" grid intersection
	var snapped_pos = snap_to_fine_grid(world_pos)

	match custom_zone_mode:
		CustomZoneMode.SYMMETRIC:
			# Add vertex to P1 zone
			custom_zone_player1.append(snapped_pos)
			custom_zone_vertex_added.emit(1, snapped_pos)

			# Add point-symmetric vertex to P2 zone (mirrored around center)
			var mirrored_pos = Vector3(-snapped_pos.x, snapped_pos.y, -snapped_pos.z)
			custom_zone_player2.append(mirrored_pos)
			custom_zone_vertex_added.emit(2, mirrored_pos)

		CustomZoneMode.ASYMMETRIC_P1:
			custom_zone_player1.append(snapped_pos)
			custom_zone_vertex_added.emit(1, snapped_pos)

		CustomZoneMode.ASYMMETRIC_P2:
			custom_zone_player2.append(snapped_pos)
			custom_zone_vertex_added.emit(2, snapped_pos)

	# Update visualization
	_update_deployment_zones()
	_update_vertex_markers()


## Complete the current custom zone and move to next (for asymmetric mode)
func complete_current_custom_zone() -> void:
	match custom_zone_mode:
		CustomZoneMode.SYMMETRIC:
			# Both zones completed simultaneously
			custom_zone_mode = CustomZoneMode.NONE
			custom_zone_completed.emit(1)
			custom_zone_completed.emit(2)
			custom_zone_editing_changed.emit(false, CustomZoneMode.NONE)
			# Hide editing aids
			hide_fine_grid()
			_clear_vertex_markers()

		CustomZoneMode.ASYMMETRIC_P1:
			# P1 done, start P2
			custom_zone_completed.emit(1)
			custom_zone_mode = CustomZoneMode.ASYMMETRIC_P2
			custom_zone_editing_changed.emit(true, custom_zone_mode)
			# Keep grid, clear markers for new zone
			_clear_vertex_markers()
			print("Player 1 zone completed. Now drawing Player 2 zone.")

		CustomZoneMode.ASYMMETRIC_P2:
			# P2 done, editing complete
			custom_zone_completed.emit(2)
			custom_zone_mode = CustomZoneMode.NONE
			custom_zone_editing_changed.emit(false, CustomZoneMode.NONE)
			# Hide editing aids
			hide_fine_grid()
			_clear_vertex_markers()
			print("Player 2 zone completed. Custom zone editing finished.")


## Cancel custom zone editing
func cancel_custom_zone_editing() -> void:
	custom_zone_mode = CustomZoneMode.NONE
	custom_zone_player1.clear()
	custom_zone_player2.clear()
	_update_deployment_zones()
	# Hide editing aids
	hide_fine_grid()
	_clear_vertex_markers()
	custom_zone_editing_changed.emit(false, CustomZoneMode.NONE)


## Remove the last vertex from the current zone being edited
func undo_last_custom_zone_vertex() -> void:
	match custom_zone_mode:
		CustomZoneMode.SYMMETRIC:
			if not custom_zone_player1.is_empty():
				custom_zone_player1.pop_back()
			if not custom_zone_player2.is_empty():
				custom_zone_player2.pop_back()

		CustomZoneMode.ASYMMETRIC_P1:
			if not custom_zone_player1.is_empty():
				custom_zone_player1.pop_back()

		CustomZoneMode.ASYMMETRIC_P2:
			if not custom_zone_player2.is_empty():
				custom_zone_player2.pop_back()

	_update_deployment_zones()
	_update_vertex_markers()


## Check if currently editing custom zones
func is_editing_custom_zones() -> bool:
	return custom_zone_mode != CustomZoneMode.NONE


## Get the current editing mode
func get_custom_zone_mode() -> CustomZoneMode:
	return custom_zone_mode


## Set custom zone vertices directly (for loading saved zones)
func set_custom_zones(p1_vertices: Array[Vector3], p2_vertices: Array[Vector3]) -> void:
	custom_zone_player1 = p1_vertices.duplicate()
	custom_zone_player2 = p2_vertices.duplicate()
	if current_deployment_type == DeploymentType.CUSTOM:
		_update_deployment_zones()


## Get custom zone vertices (for saving)
func get_custom_zones() -> Dictionary:
	return {
		"player1": custom_zone_player1.duplicate(),
		"player2": custom_zone_player2.duplicate()
	}


# ==============================================================================
# FINE GRID (1") FOR CUSTOM ZONE EDITING
# ==============================================================================

## Show the 1" fine grid for custom zone editing
func show_fine_grid() -> void:
	if fine_grid_visible:
		return

	_create_fine_grid()
	fine_grid_visible = true


## Hide the 1" fine grid
func hide_fine_grid() -> void:
	_clear_fine_grid()
	fine_grid_visible = false


## Clear all fine grid meshes
func _clear_fine_grid() -> void:
	for mesh in fine_grid_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	fine_grid_meshes.clear()


## Create the 1" fine grid visualization
func _create_fine_grid() -> void:
	_clear_fine_grid()

	var table_width_m = table_size_feet.x * 12.0 * INCHES_TO_METERS
	var table_depth_m = table_size_feet.y * 12.0 * INCHES_TO_METERS
	var cell_size = FINE_GRID_SIZE_INCHES * INCHES_TO_METERS

	# Grid line color (subtle gray)
	var line_color = Color(0.4, 0.4, 0.4, 0.5)

	# Create horizontal lines (along X axis)
	var num_z_lines = int(table_depth_m / cell_size) + 1
	for i in range(num_z_lines + 1):
		var z = -table_depth_m / 2.0 + i * cell_size
		if z > table_depth_m / 2.0 + 0.001:
			continue
		var line = _create_grid_line(
			Vector3(-table_width_m / 2.0, 0.003, z),
			Vector3(table_width_m / 2.0, 0.003, z),
			line_color
		)
		add_child(line)
		fine_grid_meshes.append(line)

	# Create vertical lines (along Z axis)
	var num_x_lines = int(table_width_m / cell_size) + 1
	for i in range(num_x_lines + 1):
		var x = -table_width_m / 2.0 + i * cell_size
		if x > table_width_m / 2.0 + 0.001:
			continue
		var line = _create_grid_line(
			Vector3(x, 0.003, -table_depth_m / 2.0),
			Vector3(x, 0.003, table_depth_m / 2.0),
			line_color
		)
		add_child(line)
		fine_grid_meshes.append(line)


## Create a single grid line mesh
func _create_grid_line(start: Vector3, end: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	var im = ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(start)
	im.surface_add_vertex(end)
	im.surface_end()

	mesh_instance.mesh = im

	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	mesh_instance.material_override = material

	return mesh_instance


## Snap a world position to the nearest 1" grid intersection
## @param world_pos: Position in world coordinates
## @return: Snapped position on the nearest grid intersection
func snap_to_fine_grid(world_pos: Vector3) -> Vector3:
	var cell_size = FINE_GRID_SIZE_INCHES * INCHES_TO_METERS
	var table_width_m = table_size_feet.x * 12.0 * INCHES_TO_METERS
	var table_depth_m = table_size_feet.y * 12.0 * INCHES_TO_METERS

	# Snap to nearest intersection
	var snapped_x = round((world_pos.x + table_width_m / 2.0) / cell_size) * cell_size - table_width_m / 2.0
	var snapped_z = round((world_pos.z + table_depth_m / 2.0) / cell_size) * cell_size - table_depth_m / 2.0

	# Clamp to table bounds
	snapped_x = clamp(snapped_x, -table_width_m / 2.0, table_width_m / 2.0)
	snapped_z = clamp(snapped_z, -table_depth_m / 2.0, table_depth_m / 2.0)

	return Vector3(snapped_x, 0.0, snapped_z)


## Clear vertex markers
func _clear_vertex_markers() -> void:
	for marker in vertex_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	vertex_markers.clear()


## Update vertex markers to show current polygon vertices
func _update_vertex_markers() -> void:
	_clear_vertex_markers()

	# Get current vertices based on mode
	var vertices: Array[Vector3] = []
	match custom_zone_mode:
		CustomZoneMode.SYMMETRIC, CustomZoneMode.ASYMMETRIC_P1:
			vertices = custom_zone_player1
		CustomZoneMode.ASYMMETRIC_P2:
			vertices = custom_zone_player2

	# Create marker for each vertex
	for i in range(vertices.size()):
		var v = vertices[i]
		var marker = _create_vertex_marker(v, i + 1)
		add_child(marker)
		vertex_markers.append(marker)

	# In symmetric mode, also show P2 markers
	if custom_zone_mode == CustomZoneMode.SYMMETRIC:
		for i in range(custom_zone_player2.size()):
			var v = custom_zone_player2[i]
			var marker = _create_vertex_marker(v, i + 1, DEPLOYMENT_COLORS["player2"])
			add_child(marker)
			vertex_markers.append(marker)


## Create a vertex marker (small sphere with number)
func _create_vertex_marker(pos: Vector3, number: int, color: Color = Color(0.2, 0.5, 1.0, 0.8)) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	var sphere = SphereMesh.new()
	sphere.radius = 0.01  # 1cm radius
	sphere.height = 0.02
	mesh_instance.mesh = sphere
	mesh_instance.position = Vector3(pos.x, 0.015, pos.z)  # Slightly above table

	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	mesh_instance.material_override = material

	# Add number label
	var label = Label3D.new()
	label.text = str(number)
	label.position.y = 0.02
	label.pixel_size = 0.001
	label.font_size = 32
	label.modulate = Color.WHITE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mesh_instance.add_child(label)

	return mesh_instance


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

		DeploymentType.CUSTOM:
			# Check custom polygon zones using point-in-polygon test
			if _is_point_in_polygon(world_pos, custom_zone_player1):
				return {"in_zone": true, "player": "player1"}
			if _is_point_in_polygon(world_pos, custom_zone_player2):
				return {"in_zone": true, "player": "player2"}

	return {"in_zone": false, "player": "none"}


## Check if a point is inside a polygon (2D test on XZ plane)
## Uses ray casting algorithm
func _is_point_in_polygon(point: Vector3, polygon: Array[Vector3]) -> bool:
	if polygon.size() < 3:
		return false

	var inside := false
	var n := polygon.size()

	var j := n - 1
	for i in range(n):
		var pi := polygon[i]
		var pj := polygon[j]

		# Ray casting on XZ plane
		if ((pi.z > point.z) != (pj.z > point.z)) and \
		   (point.x < (pj.x - pi.x) * (point.z - pi.z) / (pj.z - pi.z) + pi.x):
			inside = not inside
		j = i

	return inside


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


# ==============================================================================
# MISSION OBJECTIVES
# ==============================================================================

## Update mission objectives display
##
## @param objectives: Array of Vector3 world positions (in meters)
func update_objectives(objectives: Array) -> void:
	_clear_objectives()
	mission_objectives.clear()

	for obj in objectives:
		if obj is Vector3:
			mission_objectives.append(obj)

	if mission_objectives.is_empty():
		return

	# Create meshes for each objective
	for i in range(mission_objectives.size()):
		var obj_pos = mission_objectives[i]
		_create_objective_marker(obj_pos, i + 1)

	print("TerrainOverlay: Created %d objective markers" % mission_objectives.size())


## Clear all objective meshes
func _clear_objectives() -> void:
	for mesh in objective_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	objective_meshes.clear()

	for mesh in objective_ring_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	objective_ring_meshes.clear()


## Create a single objective marker with 3" seize radius ring
##
## @param pos: World position in meters
## @param number: Objective number for label
func _create_objective_marker(pos: Vector3, number: int) -> void:
	var objective_color = Color(1.0, 0.85, 0.2, 1.0)  # Gold/yellow
	var border_color = Color(0.1, 0.1, 0.1, 1.0)  # Black border
	var ring_color = Color(1.0, 0.85, 0.2, 0.25)  # Semi-transparent gold

	# Create 3" seize radius ring (flat disc)
	var seize_radius_m = 3.0 * INCHES_TO_METERS
	var ring_mesh = _create_seize_radius_ring(pos, seize_radius_m, ring_color)
	add_child(ring_mesh)
	objective_ring_meshes.append(ring_mesh)

	# Create objective token marker (1" diameter flat disc with black border)
	var token_container = _create_objective_token(pos, number, objective_color, border_color)
	add_child(token_container)
	objective_meshes.append(token_container)


## Create a ring mesh for the 3" seize radius
func _create_seize_radius_ring(pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	# Create a flat disc mesh using CylinderMesh with very small height
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 0.002  # Very thin disc (2mm)
	cylinder.radial_segments = 64

	mesh_instance.mesh = cylinder
	mesh_instance.position = Vector3(pos.x, Z_FIGHT_OFFSET * 2, pos.z)

	# Create transparent material
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	mesh_instance.material_override = material

	return mesh_instance


## Create an objective token marker (like unit tokens: 1" diameter, black border, numbered)
func _create_objective_token(pos: Vector3, number: int, fill_color: Color, border_color: Color) -> Node3D:
	var container = Node3D.new()
	container.position = Vector3(pos.x, Z_FIGHT_OFFSET * 3, pos.z)

	# Token dimensions: 1" diameter = 0.0254m, but we use half for radius
	var token_radius = 0.5 * INCHES_TO_METERS  # 0.5" radius = 1" diameter
	var border_width = 0.08 * INCHES_TO_METERS  # Border thickness
	var token_height = 0.003  # 3mm thick

	# Create black border disc (slightly larger)
	var border_mesh = MeshInstance3D.new()
	var border_cylinder = CylinderMesh.new()
	border_cylinder.top_radius = token_radius + border_width
	border_cylinder.bottom_radius = token_radius + border_width
	border_cylinder.height = token_height
	border_cylinder.radial_segments = 32
	border_mesh.mesh = border_cylinder
	border_mesh.position = Vector3(0, 0, 0)

	var border_material = StandardMaterial3D.new()
	border_material.albedo_color = border_color
	border_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	border_mesh.material_override = border_material
	container.add_child(border_mesh)

	# Create gold fill disc (on top of border)
	var fill_mesh = MeshInstance3D.new()
	var fill_cylinder = CylinderMesh.new()
	fill_cylinder.top_radius = token_radius
	fill_cylinder.bottom_radius = token_radius
	fill_cylinder.height = token_height + 0.001  # Slightly higher to prevent z-fighting
	fill_cylinder.radial_segments = 32
	fill_mesh.mesh = fill_cylinder
	fill_mesh.position = Vector3(0, 0.001, 0)

	var fill_material = StandardMaterial3D.new()
	fill_material.albedo_color = fill_color
	fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mesh.material_override = fill_material
	container.add_child(fill_mesh)

	# Create 3D text label for the objective number
	var label_3d = Label3D.new()
	label_3d.text = str(number)
	label_3d.font_size = 72
	label_3d.pixel_size = 0.0003  # Scale to fit on token
	label_3d.position = Vector3(0, token_height + 0.002, 0)
	label_3d.rotation_degrees = Vector3(-90, 0, 0)  # Face upward
	label_3d.modulate = border_color  # Black text
	label_3d.outline_modulate = fill_color
	label_3d.outline_size = 8
	label_3d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_3d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_3d.no_depth_test = true  # Always visible
	label_3d.shaded = false
	container.add_child(label_3d)

	return container


## Legacy function - kept for compatibility
func _create_objective_pillar(pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	# Create a small cylinder as marker
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.02  # 2cm top
	cylinder.bottom_radius = 0.03  # 3cm bottom
	cylinder.height = 0.08  # 8cm tall
	cylinder.radial_segments = 16

	mesh_instance.mesh = cylinder
	# Position at half height so bottom touches ground
	mesh_instance.position = Vector3(pos.x, 0.04 + Z_FIGHT_OFFSET, pos.z)

	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.5

	mesh_instance.material_override = material

	return mesh_instance


## Get objectives for AI/gameplay use
func get_objectives() -> Array[Vector3]:
	return mission_objectives.duplicate()


# ==============================================================================
# OVERLAY MODE
# ==============================================================================

## Set the overlay display mode
## FLAT: Shows colored 2D planes (default behavior)
## MODELS: Hides flat overlays (3D terrain models are managed by terrain_library)
## BOTH: Shows flat overlays AND 3D models
func set_overlay_mode(mode: OverlayMode) -> void:
	overlay_mode = mode

	# Update flat overlay visibility based on mode
	var show_flat := mode != OverlayMode.MODELS
	for mesh in overlay_meshes:
		if is_instance_valid(mesh):
			mesh.visible = show_flat

	print("TerrainOverlay: Overlay mode set to %d" % mode)


## Get the current overlay mode
func get_overlay_mode() -> OverlayMode:
	return overlay_mode


## Set the terrain theme key (for save/load serialization)
func set_terrain_theme(theme_key: String) -> void:
	terrain_theme_key = theme_key


## Get the current terrain theme key
func get_terrain_theme() -> String:
	return terrain_theme_key


# ==============================================================================
# BATTLE MAP (S5)
# ==============================================================================

## Set a battle map texture as the table background
## @param theme_key: Theme key to load battle_map.png from
func set_battle_map(theme_key: String) -> void:
	clear_battle_map()

	if theme_key.is_empty():
		return

	var battle_map_path := "res://assets/terrain/%s/battle_map.png" % theme_key
	if not FileAccess.file_exists(battle_map_path):
		print("TerrainOverlay: Battle map not found: %s" % battle_map_path)
		return

	var image := Image.load_from_file(battle_map_path)
	if not image:
		push_warning("TerrainOverlay: Failed to load battle map image: %s" % battle_map_path)
		return

	var texture := ImageTexture.create_from_image(image)

	# Create PlaneMesh in table size
	var table_width_m := table_size_feet.x * 12.0 * INCHES_TO_METERS
	var table_depth_m := table_size_feet.y * 12.0 * INCHES_TO_METERS

	_battle_map_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(table_width_m, table_depth_m)
	_battle_map_mesh.mesh = plane

	# Position BELOW base plates (TerrainOverlay is at Y=0.002, so -0.001 → absolute Y=0.001)
	_battle_map_mesh.position = Vector3(0, -0.001, 0)

	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_battle_map_mesh.material_override = material

	add_child(_battle_map_mesh)
	set_terrain_theme(theme_key)
	print("TerrainOverlay: Battle map loaded for theme '%s'" % theme_key)


## Clear the battle map background
func clear_battle_map() -> void:
	if is_instance_valid(_battle_map_mesh):
		_battle_map_mesh.queue_free()
	_battle_map_mesh = null


# ==============================================================================
# BASE PLATE TEXTURES (S6)
# ==============================================================================

## Load base plate textures for a terrain theme
## @param theme_key: Theme key to load from
func load_base_plate_textures(theme_key: String) -> void:
	_base_plate_textures.clear()

	if theme_key.is_empty():
		return

	var base_path := "res://assets/terrain/%s/base_plates/" % theme_key
	for terrain_type_name in ["ruins", "forest", "dangerous"]:
		var img_path: String = base_path + terrain_type_name + ".png"
		if FileAccess.file_exists(img_path):
			var image := Image.load_from_file(img_path)
			if image:
				_base_plate_textures[terrain_type_name] = ImageTexture.create_from_image(image)

	print("TerrainOverlay: Loaded %d base plate textures" % _base_plate_textures.size())


## Create a textured cell mesh (if base_plate_textures are loaded, use texture; else fallback to color)
func _create_textured_cell_mesh(pos: Vector3, cell_size: float, terrain_type: int, grid_rotation: float = 0.0) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()

	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(cell_size * CELL_SIZE_REDUCTION, cell_size * CELL_SIZE_REDUCTION)
	mesh_instance.mesh = plane_mesh
	mesh_instance.position = pos
	mesh_instance.rotation.y = -deg_to_rad(grid_rotation)

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Try to use base plate texture
	var type_name := _terrain_type_to_name(terrain_type)
	if _base_plate_textures.has(type_name):
		material.albedo_texture = _base_plate_textures[type_name]
		material.albedo_color = Color(1, 1, 1, 0.8)  # Slightly transparent
	else:
		# Fallback: colored plane
		var color: Color = TERRAIN_COLORS.get(terrain_type, Color.WHITE)
		material.albedo_color = color

	mesh_instance.material_override = material
	return mesh_instance


## Convert TerrainType enum to lowercase name string
func _terrain_type_to_name(terrain_type: int) -> String:
	match terrain_type:
		TerrainType.RUINS: return "ruins"
		TerrainType.FOREST: return "forest"
		TerrainType.DANGEROUS: return "dangerous"
		TerrainType.CONTAINER: return "container"
	return ""


# ==============================================================================
# WALL 3D PLACEMENT (S8)
# ==============================================================================

## Update wall model instances based on wall segments from map layout
## @param wall_segments: Array of Dictionaries with {edge_cell, edge_side, wall_key, length_inches, sub_position}
## @param t_size: Table size in feet
## @param rotation: Grid rotation in degrees
func update_wall_models(wall_segments: Array, t_size: Vector2, rotation: float) -> void:
	_clear_wall_instances()

	if wall_segments.is_empty() or not terrain_library:
		return

	var cell_size_meters := GRID_SIZE_INCHES * INCHES_TO_METERS

	# Compute grid dimensions (same as update_overlay)
	var width_inches := t_size.x * 12.0
	var height_inches := t_size.y * 12.0
	var diagonal := sqrt(width_inches * width_inches + height_inches * height_inches)
	var grid_size := int(ceil(diagonal / GRID_SIZE_INCHES))
	if grid_size % 2 != 0:
		grid_size += 1
	var grid_dims := Vector2i(grid_size, grid_size)

	var rotation_rad := deg_to_rad(rotation)

	for segment in wall_segments:
		var edge_cell: Vector2i = segment.get("edge_cell", Vector2i.ZERO)
		var edge_side: int = segment.get("edge_side", 0)
		var wall_key: String = segment.get("wall_key", "")
		var length_inches: float = segment.get("length_inches", 3.0)
		var sub_position: int = segment.get("sub_position", 0)

		# Load wall model
		var model := _get_wall_model(wall_key)
		if not model:
			continue

		# Calculate edge center position
		var local_x := (edge_cell.x - grid_dims.x / 2.0 + 0.5) * cell_size_meters
		var local_z := (edge_cell.y - grid_dims.y / 2.0 + 0.5) * cell_size_meters

		# Offset to edge center
		var half_cell := cell_size_meters / 2.0
		var edge_offset := Vector2.ZERO
		var wall_y_rotation := 0.0

		match edge_side:
			0:  # Nord (top edge, -Z)
				edge_offset = Vector2(0, -half_cell)
				wall_y_rotation = 0.0
			1:  # Ost (right edge, +X)
				edge_offset = Vector2(half_cell, 0)
				wall_y_rotation = PI / 2.0
			2:  # Sued (bottom edge, +Z)
				edge_offset = Vector2(0, half_cell)
				wall_y_rotation = PI
			3:  # West (left edge, -X)
				edge_offset = Vector2(-half_cell, 0)
				wall_y_rotation = -PI / 2.0

		local_x += edge_offset.x
		local_z += edge_offset.y

		# Offset for 1"-segments within the 3"-edge
		# sub_position: 0=left, 1=center, 2=right relative to edge center
		if length_inches < 3.0:
			var sub_offset := (float(sub_position) - 1.0) * INCHES_TO_METERS
			match edge_side:
				0, 2:  # Horizontal edges
					local_x += sub_offset
				1, 3:  # Vertical edges
					local_z += sub_offset

		# Apply grid rotation
		var rotated_x := local_x * cos(rotation_rad) - local_z * sin(rotation_rad)
		var rotated_z := local_x * sin(rotation_rad) + local_z * cos(rotation_rad)

		# Skip walls outside table boundaries
		if not _is_position_within_table(rotated_x, rotated_z, t_size):
			continue

		# Place model — preserve Y from AABB correction in _get_wall_model()
		model.position.x = rotated_x
		model.position.z = rotated_z
		model.rotation.y = wall_y_rotation - deg_to_rad(rotation)
		add_child(model)
		_wall_instances.append(model)

	# Add corner pieces where perpendicular walls meet
	_add_wall_corner_pieces(wall_segments, grid_dims, cell_size_meters, rotation_rad, rotation, t_size)


## Add corner pieces at intersections where two perpendicular walls meet
func _add_wall_corner_pieces(wall_segments: Array, grid_dims: Vector2i, cell_size_meters: float, rotation_rad: float, rotation: float, t_size: Vector2) -> void:
	if not terrain_library or terrain_theme_key.is_empty():
		return

	var half_cell := cell_size_meters / 2.0
	var corner_size := 0.25 * INCHES_TO_METERS  # 0.25" corner piece

	# Build a dictionary of wall endpoints: corner_pos -> Array of wall_keys
	# Each wall segment touches two corners of its edge
	var corner_walls := {}  # Vector2i corner point -> Array[String] of adjacent wall keys

	for segment in wall_segments:
		var edge_cell: Vector2i = segment.get("edge_cell", Vector2i.ZERO)
		var edge_side: int = segment.get("edge_side", 0)
		var wall_key: String = segment.get("wall_key", "")

		# Determine the two corner grid-points of this edge
		# Corner coordinates are in grid-point space (not cell space)
		var corner_a: Vector2i
		var corner_b: Vector2i
		match edge_side:
			0:  # North edge: corners at (x,y) and (x+1,y)
				corner_a = edge_cell
				corner_b = Vector2i(edge_cell.x + 1, edge_cell.y)
			1:  # East edge: corners at (x+1,y) and (x+1,y+1)
				corner_a = Vector2i(edge_cell.x + 1, edge_cell.y)
				corner_b = Vector2i(edge_cell.x + 1, edge_cell.y + 1)
			2:  # South edge: corners at (x,y+1) and (x+1,y+1)
				corner_a = Vector2i(edge_cell.x, edge_cell.y + 1)
				corner_b = Vector2i(edge_cell.x + 1, edge_cell.y + 1)
			3:  # West edge: corners at (x,y) and (x,y+1)
				corner_a = edge_cell
				corner_b = Vector2i(edge_cell.x, edge_cell.y + 1)

		if not corner_walls.has(corner_a):
			corner_walls[corner_a] = []
		corner_walls[corner_a].append(wall_key)
		if not corner_walls.has(corner_b):
			corner_walls[corner_b] = []
		corner_walls[corner_b].append(wall_key)

	# Place corner pieces where 2+ walls share a corner point
	for corner_point: Vector2i in corner_walls:
		var keys: Array = corner_walls[corner_point]
		if keys.size() < 2:
			continue

		# Corner position in local grid coordinates (grid points are at cell boundaries)
		var local_x := (corner_point.x - grid_dims.x / 2.0) * cell_size_meters
		var local_z := (corner_point.y - grid_dims.y / 2.0) * cell_size_meters

		var rotated_x := local_x * cos(rotation_rad) - local_z * sin(rotation_rad)
		var rotated_z := local_x * sin(rotation_rad) + local_z * cos(rotation_rad)

		if not _is_position_within_table(rotated_x, rotated_z, t_size):
			continue

		# Get wall height from first wall key
		var wall_height_inches := 3.0
		var texture_path := ""
		var theme_data = terrain_library.get_theme_data(terrain_theme_key)
		if theme_data:
			for wd in theme_data.walls:
				if wd["key"] == keys[0]:
					wall_height_inches = wd.get("height_inches", 3.0)
					texture_path = wd.get("texture", "")
					break

		var target_height := wall_height_inches * INCHES_TO_METERS

		# Create corner box
		var root := Node3D.new()
		var mesh_instance := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(corner_size, target_height, corner_size)
		mesh_instance.mesh = box
		mesh_instance.position.y = target_height / 2.0 - Z_FIGHT_OFFSET

		# Apply same texture as adjacent wall
		if not texture_path.is_empty() and FileAccess.file_exists(texture_path):
			var image := Image.load_from_file(texture_path)
			if image:
				var texture := ImageTexture.create_from_image(image)
				var material := StandardMaterial3D.new()
				material.albedo_texture = texture
				material.cull_mode = BaseMaterial3D.CULL_DISABLED
				mesh_instance.material_override = material

		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mesh_instance)

		root.position.x = rotated_x
		root.position.z = rotated_z
		add_child(root)
		_wall_instances.append(root)


## Get a wall model instance — dual path: textured BoxMesh or legacy GLB
func _get_wall_model(wall_key: String) -> Node3D:
	if not terrain_library or terrain_theme_key.is_empty():
		return null

	var theme_data = terrain_library.get_theme_data(terrain_theme_key)
	if not theme_data:
		return null

	# Find wall definition
	var wall_def: Dictionary = {}
	for wd in theme_data.walls:
		if wd["key"] == wall_key:
			wall_def = wd
			break

	if wall_def.is_empty():
		return null

	var wall_length_inches: float = wall_def.get("length_inches", 3.0)
	var wall_height_inches: float = wall_def.get("height_inches", 3.0)

	# Path 1: Texture-based BoxMesh wall (seamless)
	var texture_path: String = wall_def.get("texture", "")
	if not texture_path.is_empty() and FileAccess.file_exists(texture_path):
		return _create_textured_box_wall(texture_path, wall_length_inches, wall_height_inches)

	# Path 2: Legacy GLB model
	var wall_glb: String = wall_def.get("glb", "")
	if wall_glb.is_empty() or not FileAccess.file_exists(wall_glb):
		return null

	return _create_glb_wall(wall_glb, wall_length_inches, wall_height_inches)


## Create a textured BoxMesh wall with exact dimensions for seamless placement
func _create_textured_box_wall(texture_path: String, length_inches: float, height_inches: float) -> Node3D:
	var root := Node3D.new()

	var target_length := length_inches * INCHES_TO_METERS
	var target_height := height_inches * INCHES_TO_METERS
	var wall_thickness := 0.25 * INCHES_TO_METERS  # 0.25" thick

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(target_length, target_height, wall_thickness)
	mesh_instance.mesh = box

	# Box center at half height so bottom sits on table (compensate TerrainOverlay Y offset)
	mesh_instance.position.y = target_height / 2.0 - Z_FIGHT_OFFSET

	# Load and apply texture
	var image := Image.load_from_file(texture_path)
	if image:
		var texture := ImageTexture.create_from_image(image)
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_instance.material_override = material

	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mesh_instance)
	return root


## Create a wall from GLB model, scaled to target size (legacy path)
func _create_glb_wall(wall_glb: String, length_inches: float, height_inches: float) -> Node3D:
	if not _wall_model_cache.has(wall_glb):
		var loaded: Node3D = terrain_library._load_glb_model(wall_glb)
		if not loaded:
			return null
		_wall_model_cache[wall_glb] = loaded

	var cached: Node3D = _wall_model_cache[wall_glb]
	var instance: Node3D = cached.duplicate()

	# Scale wall to target size (length x height in inches)
	var aabb: AABB = terrain_library._calculate_aabb(instance)
	if aabb.size.length() > 0.001:
		var target_length := length_inches * INCHES_TO_METERS
		var target_height := height_inches * INCHES_TO_METERS
		var scale_x := target_length / maxf(aabb.size.x, 0.001)
		var scale_y := target_height / maxf(aabb.size.y, 0.001)
		var uniform := minf(scale_x, scale_y)
		instance.scale = Vector3(uniform, uniform, uniform)

		# Lift model so bottom sits on table (compensate TerrainOverlay Y offset)
		var scaled_min_y: float = aabb.position.y * uniform
		instance.position.y = -scaled_min_y - Z_FIGHT_OFFSET

	return instance


## Clear all wall instances
func _clear_wall_instances() -> void:
	for instance in _wall_instances:
		if is_instance_valid(instance):
			instance.queue_free()
	_wall_instances.clear()


# ==============================================================================
# PLACED OBJECTS: TREES + CONTAINERS (S9)
# ==============================================================================

## Update placed object instances (trees and containers)
## @param objects: Array of Dictionaries {object_key, cell, offset, object_type}
## @param t_size: Table size in feet
## @param rotation: Grid rotation in degrees
func update_placed_objects(objects: Array, t_size: Vector2, rotation: float) -> void:
	_clear_placed_objects()

	if objects.is_empty() or not terrain_library:
		return

	var cell_size_meters := GRID_SIZE_INCHES * INCHES_TO_METERS

	# Compute grid dimensions
	var width_inches := t_size.x * 12.0
	var height_inches := t_size.y * 12.0
	var diagonal := sqrt(width_inches * width_inches + height_inches * height_inches)
	var grid_size := int(ceil(diagonal / GRID_SIZE_INCHES))
	if grid_size % 2 != 0:
		grid_size += 1
	var grid_dims := Vector2i(grid_size, grid_size)

	var rotation_rad := deg_to_rad(rotation)

	for obj in objects:
		var object_key: String = obj.get("object_key", "")
		var cell: Vector2i = obj.get("cell", Vector2i.ZERO)
		var offset: Vector2 = obj.get("offset", Vector2(0.5, 0.5))
		var object_type: String = obj.get("object_type", "tree")

		# Calculate world position
		var local_x := (cell.x - grid_dims.x / 2.0 + offset.x) * cell_size_meters
		var local_z := (cell.y - grid_dims.y / 2.0 + offset.y) * cell_size_meters

		# Apply grid rotation
		var rotated_x := local_x * cos(rotation_rad) - local_z * sin(rotation_rad)
		var rotated_z := local_x * sin(rotation_rad) + local_z * cos(rotation_rad)

		# Skip objects outside table boundaries
		if not _is_position_within_table(rotated_x, rotated_z, t_size):
			continue

		# Load model
		var model := _get_object_model(object_key, object_type)
		if not model:
			continue

		# Preserve Y from AABB correction in _get_object_model()
		model.position.x = rotated_x
		model.position.z = rotated_z
		# Random Y rotation for visual variety
		model.rotation.y = randf() * TAU
		add_child(model)
		_object_instances.append(model)


## Get a tree/container model instance, scaled to fit within one grid cell
func _get_object_model(object_key: String, object_type: String) -> Node3D:
	if not terrain_library or terrain_theme_key.is_empty():
		return null

	var theme_data = terrain_library.get_theme_data(terrain_theme_key)
	if not theme_data:
		return null

	var glb_path := ""
	var definitions: Array = []
	if object_type == "tree":
		definitions = theme_data.trees
	elif object_type == "container":
		definitions = theme_data.containers

	for def_entry in definitions:
		if def_entry["key"] == object_key:
			glb_path = def_entry["glb"]
			break

	if glb_path.is_empty() or not FileAccess.file_exists(glb_path):
		return null

	# Use wall model cache (shared cache for all GLBs)
	if not _wall_model_cache.has(glb_path):
		var loaded: Node3D = terrain_library._load_glb_model(glb_path)
		if not loaded:
			return null
		_wall_model_cache[glb_path] = loaded

	var cached: Node3D = _wall_model_cache[glb_path]
	var instance: Node3D = cached.duplicate()

	# Scale object to fit target dimensions
	var aabb: AABB = terrain_library._calculate_aabb(instance)
	if aabb.size.length() > 0.001:
		if object_type == "container":
			# Containers: 3"x6"x3" (1x2 tiles)
			var target_x := GRID_SIZE_INCHES * INCHES_TO_METERS          # 3"
			var target_z := GRID_SIZE_INCHES * 2.0 * INCHES_TO_METERS    # 6"
			var target_y := GRID_SIZE_INCHES * INCHES_TO_METERS           # 3"
			instance.scale = Vector3(
				target_x / maxf(aabb.size.x, 0.001),
				target_y / maxf(aabb.size.y, 0.001),
				target_z / maxf(aabb.size.z, 0.001),
			)
			var scaled_min_y: float = aabb.position.y * instance.scale.y
			instance.position.y = -scaled_min_y - Z_FIGHT_OFFSET
		else:
			# Trees: fit within cell footprint with variable size (60-90%)
			var cell_meters := GRID_SIZE_INCHES * INCHES_TO_METERS
			var scale_x := cell_meters / maxf(aabb.size.x, 0.001)
			var scale_z := cell_meters / maxf(aabb.size.z, 0.001)
			var uniform := minf(scale_x, scale_z) * randf_range(0.6, 0.9)
			instance.scale = Vector3(uniform, uniform, uniform)
			var scaled_min_y: float = aabb.position.y * uniform
			instance.position.y = -scaled_min_y - Z_FIGHT_OFFSET

	return instance


## Clear all placed object instances
func _clear_placed_objects() -> void:
	for instance in _object_instances:
		if is_instance_valid(instance):
			instance.queue_free()
	_object_instances.clear()


## Check if a world-space position is within the table boundaries
func _is_position_within_table(world_x: float, world_z: float, t_size: Vector2) -> bool:
	var table_width_m := t_size.x * 12.0 * INCHES_TO_METERS
	var table_depth_m := t_size.y * 12.0 * INCHES_TO_METERS
	return abs(world_x) <= table_width_m / 2.0 and abs(world_z) <= table_depth_m / 2.0
