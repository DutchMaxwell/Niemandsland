extends Node3D
class_name UnitBoundaryVisualizer
## Visualizes unit boundaries with colored outlines.
## Shows which models belong to which unit at a glance.

signal boundary_updated(game_unit)
## Emitted when a unit that HAD a boundary drops to a single alive model, so the
## boundary (and its token rail) is gone. Listeners migrate the unit-wide status
## tokens onto the lone survivor (see RadialMenuController._on_boundary_lost).
signal boundary_lost(game_unit)
## Emitted when a unit GAINS a boundary it did not have (e.g. a revive takes it
## from one alive model back to several). Listeners migrate the unit-wide status
## tokens off the single model back onto the boundary rail — the symmetric case
## of boundary_lost (see RadialMenuController._on_boundary_gained).
signal boundary_gained(game_unit)
## Emitted when a WIPED unit (0 alive models — deleted or last casualty) regains an alive model
## (e.g. an undo). Listeners re-create the unit's status tokens from its persisted state, since a
## wipe drops them (issue #78 — an Activated/Fatigued/Shaken marker must not linger on the empty
## spot, and must come back on undo).
signal unit_tokens_revived(game_unit)

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
## Draw the unit boundary ABOVE the ground decals (blood/oil stains = render_priority 1,
## deployment zones = 2, seize rings = 3) so it stays visible over them, while remaining below
## the measuring/overlay UI (8/9). See object_manager.gd for the full transparent-draw hierarchy.
const BORDER_RENDER_PRIORITY := 4

## Cached boundary meshes per GameUnit
var _boundaries: Dictionary = {}  # GameUnit -> MeshInstance3D (border only)

## Cached token containers per GameUnit (for unit-wide tokens)
var _token_containers: Dictionary = {}  # GameUnit -> Node3D

## Units currently WIPED (0 alive models) whose status tokens we removed — tracked so a later
## revive (undo) emits unit_tokens_revived exactly once (issue #78).
var _wiped_units: Dictionary = {}  # GameUnit -> true

## Cached hull points per GameUnit (for token positioning along boundary)
var _boundary_hull_points: Dictionary = {}  # GameUnit -> PackedVector2Array

## Cached start index on hull for token positioning (closest to -45° from first model)
var _boundary_start_indices: Dictionary = {}  # GameUnit -> int

## Reference to army manager for player colors
var army_manager = null  # OPRArmyManager

## Reference to the object manager, used for the per-token ground raycast so each
## boundary token rides the terrain DIRECTLY under it (not one unit-wide average),
## and therefore never sinks under a prop taller than the models (issue: tokens
## hidden under elevated terrain). Resolved lazily, same as army_manager.
var object_manager = null  # ObjectManager

## Small lift (metres) above the sampled ground so a token rests ON a surface
## rather than z-fighting with it.
const TOKEN_SURFACE_EPSILON := 0.002  # 2mm

## Fallback token height when no ground surface can be sampled (no object_manager,
## e.g. in pure unit tests): the table top.
const TABLE_SURFACE_Y := 0.0

## Update timer for smooth updates
var _update_timer: float = 0.0
const UPDATE_INTERVAL := 0.1  # Update every 100ms


func _ready() -> void:
	# Find managers only if not already set by parent
	if not army_manager:
		army_manager = get_node_or_null("/root/Main/OPRArmyManager")
	if not object_manager:
		object_manager = get_node_or_null("/root/Main/ObjectManager")


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
			# A wiped unit (0 alive models — deleted, or its last casualty) drops its status tokens so
			# an Activated/Fatigued/Shaken marker doesn't linger on the empty spot (issue #78). On
			# revive (undo) we signal so the markers are re-created from the unit's persisted state.
			if game_unit.get_alive_count() == 0:
				if not _wiped_units.has(game_unit):
					_wiped_units[game_unit] = true
					remove_token_container(game_unit)
			elif _wiped_units.has(game_unit):
				_wiped_units.erase(game_unit)
				unit_tokens_revived.emit(game_unit)

	# Remove boundaries for units that no longer exist
	var units_to_remove: Array = []
	for unit in _boundaries.keys():
		if unit not in existing_units:
			units_to_remove.append(unit)

	for unit in units_to_remove:
		_remove_unit_boundary(unit)
		remove_token_container(unit)  # Also remove token container for deleted units
		_wiped_units.erase(unit)

	# Clean up token containers for units that no longer exist
	var containers_to_remove: Array = []
	for unit in _token_containers.keys():
		if unit not in existing_units:
			containers_to_remove.append(unit)
	for unit in containers_to_remove:
		remove_token_container(unit)


## Updates boundary for a single unit
func _update_unit_boundary(game_unit) -> void:
	# Include joined Heroes so the outline encloses them as part of the unit.
	var models = game_unit.get_alive_models_with_attached()

	# Skip units still being built/hidden — their models are invisible until the whole army
	# is revealed for the drop, so the boundary must not show during import (issue #56).
	var any_visible := false
	for m in models:
		if m.node and is_instance_valid(m.node) and m.node.is_visible_in_tree():
			any_visible = true
			break
	if not any_visible:
		_remove_unit_boundary(game_unit)
		return

	# Skip single models - the miniature IS the unit. A multi-model unit reduced to
	# its last alive model converges to this same single-model path (boundary gone,
	# tokens hand over to the survivor) so there is one consistent behaviour.
	if models.size() <= 1:
		_drop_to_single_model(game_unit)
		return

	# Get player color (shared canonical source, also used for objective owners)
	var player_id = game_unit.unit_properties.get("player_id", 1)
	var player_color = OPRArmyManager.PLAYER_COLORS.get(player_id, Color.GRAY)

	# Get model positions and per-model base radii. A joined Hero can sit on a
	# larger base than the troops, so each point is expanded by ITS OWN base.
	var positions: Array = []
	var radii: Array = []

	for model in models:
		if model.node and is_instance_valid(model.node) and model.node.is_inside_tree():
			var pos = model.node.global_position
			positions.append(Vector2(pos.x, pos.z))
			radii.append(_model_base_radius(model))

	# Don't remove boundary if unit has multiple models but they're temporarily not in tree
	# (e.g., during arrangement operations)
	if positions.size() < 2:
		# Only remove if unit actually has <= 1 models total
		if models.size() <= 1:
			_drop_to_single_model(game_unit)
		# Otherwise keep existing boundary, just don't update the mesh
		# Token container position uses cached hull data
		else:
			_update_token_container_position(game_unit)
		return

	# Calculate expanded convex hull with per-model padding
	var hull_points = _calculate_smooth_hull(positions, radii)

	if hull_points.size() < 3:
		_remove_unit_boundary(game_unit)
		return

	# Create or update mesh (border only)
	_create_boundary_mesh(game_unit, hull_points, player_color)

	# Update token container position
	_update_token_container_position(game_unit)


## Calculates a smooth convex hull, expanding each position by its own base
## radius (+ padding). positions and radii are parallel arrays.
func _calculate_smooth_hull(positions: Array, radii: Array) -> PackedVector2Array:
	if positions.size() < 2:
		return PackedVector2Array()

	# Expand each point into a circle sized to that model's base, then hull.
	var expanded_points: PackedVector2Array = []

	for i in range(positions.size()):
		var radius: float = radii[i] + BOUNDARY_PADDING
		for j in range(HULL_SMOOTHING):
			var angle = (float(j) / HULL_SMOOTHING) * TAU
			expanded_points.append(positions[i] + Vector2(cos(angle), sin(angle)) * radius)

	# Compute convex hull
	return Geometry2D.convex_hull(expanded_points)


## Base radius (metres) of a model, from its OWN unit's recommended round base. A weapon-team /
## Tough upgrade enlarges this model's base above the unit baseline so the boundary hugs it too
## (plain models: tough 1 -> no change).
func _model_base_radius(model) -> float:
	var base_mm := 32
	if model.unit and model.unit.unit_properties:
		base_mm = model.unit.unit_properties.get("base_size_round", 32)
		var model_tough := int(model.properties.get("tough", 1)) if model.properties else 1
		base_mm = OPRArmyManager.model_base_long_mm(base_mm, model_tough)
	return (base_mm / 2.0) * 0.001


## Creates the 3D mesh for the boundary (border only, no fill)
func _create_boundary_mesh(game_unit, hull_points: PackedVector2Array, color: Color) -> void:
	if hull_points.size() < 3:
		return

	# Get or create boundary entry
	var is_new_boundary: bool = game_unit not in _boundaries
	if is_new_boundary:
		var border_mesh = MeshInstance3D.new()
		border_mesh.name = "UnitBoundary"
		add_child(border_mesh)
		_boundaries[game_unit] = border_mesh

	var border_instance = _boundaries[game_unit] as MeshInstance3D

	# Store hull points for token positioning
	_boundary_hull_points[game_unit] = hull_points

	# Create border mesh (outline only)
	_create_border_mesh(border_instance, hull_points, color)

	# Calculate token start position on boundary (leftmost point)
	_calculate_token_start_index(game_unit)

	# A brand-new boundary means the unit just regained one (e.g. a revive): let
	# listeners pull the unit-wide tokens off the lone model first, so the
	# boundary_updated reposition below lays them out on the new rail.
	if is_new_boundary:
		boundary_gained.emit(game_unit)

	# Notify that boundary was updated (for token repositioning)
	boundary_updated.emit(game_unit)


## Creates the border outline mesh with smooth joins
func _create_border_mesh(mesh_instance: MeshInstance3D, hull_points: PackedVector2Array, color: Color) -> void:
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var point_count = hull_points.size()
	if point_count < 3:
		return

	var half_thickness = BORDER_THICKNESS / 2.0

	# Create thick line segments as quads
	for i in range(point_count):
		var p1 = hull_points[i]
		var p2 = hull_points[(i + 1) % point_count]

		# Direction and perpendicular vectors
		var dir1 = (p2 - p1).normalized()
		var perp1 = Vector2(-dir1.y, dir1.x) * half_thickness

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
	material.render_priority = BORDER_RENDER_PRIORITY  # above blood/oil stains (#82)
	mesh_instance.material_override = material


## Removes boundary visualization for a unit (but keeps token container!)
func _remove_unit_boundary(game_unit) -> void:
	if game_unit in _boundaries:
		var mesh = _boundaries[game_unit]
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
		_boundaries.erase(game_unit)

	# NOTE: We do NOT remove token containers here - they persist independently
	# Token containers are only removed when the unit itself is deleted
	# This prevents tokens from being deleted during temporary operations like arrangement


## Handles a unit dropping to a single alive model: remove the boundary mesh AND
## clear the stale hull cache so get_token_positions_on_boundary() can never return
## the old multi-model positions. Emits boundary_lost on the genuine multi->single
## transition so the controller migrates the unit-wide status tokens onto the lone
## survivor (the token CONTAINER itself is kept — only the unit's truly being
## deleted removes it, via remove_token_container).
func _drop_to_single_model(game_unit) -> void:
	var had_boundary: bool = game_unit in _boundaries
	_remove_unit_boundary(game_unit)

	# The hull rail no longer reflects reality; drop it so no token rides it.
	if game_unit in _boundary_hull_points:
		_boundary_hull_points.erase(game_unit)
	if game_unit in _boundary_start_indices:
		_boundary_start_indices.erase(game_unit)

	if had_boundary:
		boundary_lost.emit(game_unit)


## Removes token container for a unit (call when unit is truly deleted)
func remove_token_container(game_unit) -> void:
	if game_unit in _token_containers:
		var container = _token_containers[game_unit]
		if container and is_instance_valid(container):
			container.queue_free()
		_token_containers.erase(game_unit)
	if game_unit in _boundary_hull_points:
		_boundary_hull_points.erase(game_unit)
	if game_unit in _boundary_start_indices:
		_boundary_start_indices.erase(game_unit)


## Clears all boundary visualizations and token containers
func clear_all() -> void:
	for game_unit in _boundaries.keys():
		_remove_unit_boundary(game_unit)
	_boundaries.clear()

	# Also clear all token containers
	for game_unit in _token_containers.keys():
		var container = _token_containers[game_unit]
		if container and is_instance_valid(container):
			container.queue_free()
	_token_containers.clear()
	_boundary_hull_points.clear()
	_boundary_start_indices.clear()


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


## Finds the best starting point on the hull for tokens.
## Picks the point with the MAXIMUM minimum distance to all models.
## This ensures tokens are placed at the "most free" spot on the boundary.
func _calculate_token_start_index(game_unit) -> void:
	if game_unit not in _boundary_hull_points:
		return

	var hull_points = _boundary_hull_points[game_unit]
	if hull_points.is_empty():
		return

	# Get model positions for distance checking. Use the SAME living-model source as the hull
	# (get_alive_models_with_attached) so the activation marker doesn't anchor on a dead model's
	# vacated spot — dead models stay valid at their last position and would otherwise win the
	# "most free" slot and leave the token clinging to the corpse.
	var model_positions: Array[Vector2] = []
	for model in game_unit.get_alive_models_with_attached():
		if model and is_instance_valid(model.node):
			var pos = model.node.global_position
			model_positions.append(Vector2(pos.x, pos.z))

	if model_positions.is_empty():
		_boundary_start_indices[game_unit] = 0
		return

	var point_count = hull_points.size()
	var token_radius = 0.010  # 10mm
	var outward_offset = token_radius + 0.002  # 12mm offset

	# Find the hull point with the MAXIMUM minimum distance to any model
	var best_index = 0
	var best_min_dist = -INF

	for i in range(point_count):
		# Calculate token position at this hull point
		var seg_start = hull_points[i]
		var seg_end = hull_points[(i + 1) % point_count]
		var segment_dir = (seg_end - seg_start).normalized()
		var outward_normal = Vector2(segment_dir.y, -segment_dir.x)
		var token_pos = seg_start + outward_normal * outward_offset

		# Find the minimum distance from this token position to any model
		var min_dist = INF
		for model_pos in model_positions:
			var dist = (token_pos - model_pos).length()
			if dist < min_dist:
				min_dist = dist

		# Keep track of the point with the largest minimum distance
		if min_dist > best_min_dist:
			best_min_dist = min_dist
			best_index = i

	_boundary_start_indices[game_unit] = best_index


## Average ground height of the unit's living models. Used as a FALLBACK token
## height when the per-token ground ray can't run (no object_manager, e.g. in pure
## unit tests). The live game uses the per-token sample (see _token_surface_y).
func _unit_surface_y(game_unit) -> float:
	var sum := 0.0
	var n := 0
	for model in game_unit.get_alive_models_with_attached():
		if model and is_instance_valid(model.node):
			sum += model.node.global_position.y
			n += 1
	return (sum / n) if n > 0 else TABLE_SURFACE_Y


## Ground height for ONE token at world XZ: a downward ground-only ray (reusing
## ObjectManager._surface_y_under) so a token on a raised prop rides THAT prop, not
## the unit's average model height — which let it sink under terrain taller than the
## models. Lifted by a small epsilon so it rests on the surface without z-fighting.
## Falls back to the unit average when no object_manager is available.
func _token_surface_y(world_x: float, world_z: float, fallback_y: float) -> float:
	if object_manager == null:
		object_manager = get_node_or_null("/root/Main/ObjectManager")
	if object_manager and object_manager.has_method("_surface_y_under"):
		var ground_y: float = object_manager._surface_y_under(Vector3(world_x, 0.0, world_z))
		return ground_y + TOKEN_SURFACE_EPSILON
	return fallback_y


## Gets the anchor point on boundary at -45° from first model.
## This is where token arrangement is centered.
func get_boundary_anchor_point(game_unit) -> Vector3:
	if game_unit not in _boundary_hull_points or game_unit not in _boundary_start_indices:
		return Vector3.ZERO

	var hull_points = _boundary_hull_points[game_unit]
	if hull_points.is_empty():
		return Vector3.ZERO

	var start_index = _boundary_start_indices[game_unit]
	var point = hull_points[start_index]
	return Vector3(point.x, _token_surface_y(point.x, point.y, _unit_surface_y(game_unit)), point.y)


## Gets positions along the boundary for multiple tokens.
## Returns array of Vector3 positions starting from the leftmost point, following the boundary.
## Tokens are offset outward using the boundary normal (like tokens around a base edge).
func get_token_positions_on_boundary(game_unit, token_count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []

	if game_unit not in _boundary_hull_points or game_unit not in _boundary_start_indices:
		return positions

	var hull_points = _boundary_hull_points[game_unit]
	if hull_points.is_empty() or token_count == 0:
		return positions

	var start_index = _boundary_start_indices[game_unit]
	var point_count = hull_points.size()
	# Unit-average height, used only as a fallback for the per-token ground ray below.
	var fallback_surface_y := _unit_surface_y(game_unit)

	# Token spacing along boundary (same as single model: 2*radius + gap)
	var token_radius = 0.010  # 10mm
	var token_gap = 0.001  # 1mm
	var token_spacing = 2.0 * token_radius + token_gap  # 21mm between token centers
	var outward_offset = token_radius + 0.002  # 12mm offset from boundary line

	# Calculate cumulative distances along the boundary starting from start_index
	var cumulative_distances: Array[float] = [0.0]
	var total_length = 0.0
	for i in range(point_count):
		var idx = (start_index + i) % point_count
		var next_idx = (start_index + i + 1) % point_count
		var p1 = hull_points[idx]
		var p2 = hull_points[next_idx]
		total_length += (p2 - p1).length()
		cumulative_distances.append(total_length)

	# Place tokens along boundary rail, offset outward using line normal
	for token_idx in range(token_count):
		var target_distance = token_idx * token_spacing

		# Find which segment contains this distance
		var segment_idx = 0
		for i in range(point_count):
			if cumulative_distances[i + 1] >= target_distance:
				segment_idx = i
				break

		# Get hull indices for this segment
		var seg_start_idx = (start_index + segment_idx) % point_count
		var seg_end_idx = (start_index + segment_idx + 1) % point_count

		var segment_start = hull_points[seg_start_idx]
		var segment_end = hull_points[seg_end_idx]

		# Interpolate within segment (position on the rail)
		var segment_start_dist = cumulative_distances[segment_idx]
		var segment_length = cumulative_distances[segment_idx + 1] - segment_start_dist

		var t = 0.0
		if segment_length > 0.001:
			t = (target_distance - segment_start_dist) / segment_length
		t = clamp(t, 0.0, 1.0)

		var pos_on_rail = segment_start.lerp(segment_end, t)

		# Calculate outward normal of the boundary segment
		# For a convex hull going counter-clockwise, the outward normal is perpendicular to the right
		var segment_dir = (segment_end - segment_start).normalized()
		var outward_normal = Vector2(segment_dir.y, -segment_dir.x)  # Perpendicular, pointing outward

		# Offset position along the normal (like tokens around a base edge)
		var final_pos = pos_on_rail + outward_normal * outward_offset

		# Sample the ground directly under THIS token so it rides whatever surface
		# is beneath it (table or a raised prop), never sinking under tall terrain.
		var token_y := _token_surface_y(final_pos.x, final_pos.y, fallback_surface_y)
		positions.append(Vector3(final_pos.x, token_y, final_pos.y))

	return positions


## Updates the token container position to first token position on boundary.
func _update_token_container_position(game_unit) -> void:
	if game_unit not in _token_containers:
		return

	var container = _token_containers[game_unit]
	if not container or not is_instance_valid(container):
		return

	# Position container at the first token position on boundary
	var positions = get_token_positions_on_boundary(game_unit, 1)
	if not positions.is_empty():
		container.global_position = positions[0]


## Checks if a unit has multiple models (uses boundary visualization).
func has_boundary(game_unit) -> bool:
	return game_unit in _boundaries
