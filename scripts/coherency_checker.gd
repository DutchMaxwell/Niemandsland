class_name CoherencyChecker
extends RefCounted
## Checks unit coherency according to OPR rules.
## - Model-to-model: 1" (or 3" if elevated)
## - Max chain length: 9" (6" for Skirmish)

# ===== Constants =====

## Standard coherency distance in inches
const COHERENCY_DISTANCE_INCHES := 1.0

## Maximum chain distance in inches (standard game)
const MAX_CHAIN_DISTANCE_INCHES := 9.0

## Maximum chain distance for Skirmish mode
const SKIRMISH_CHAIN_DISTANCE_INCHES := 6.0

## Elevated coherency distance (different heights)
const ELEVATED_COHERENCY_INCHES := 3.0

## Height difference above which models count as being at "different elevation"
## (OPR: elevated terrain is >3" tall). Must stay clearly above ObjectManager's
## drag_lift_height (0.05m) so a model that is briefly lifted while being dragged
## is NOT mistaken for standing on elevated terrain - that false positive made
## the 3" elevation allowance trigger and showed models >1" apart as coherent.
const ELEVATION_THRESHOLD := 0.0762  # 3 inches

## Inches to meters conversion
const INCHES_TO_METERS := 0.0254


# ===== Issue Types =====

enum IssueType {
	ISOLATED,           # Model has no neighbor within coherency
	CHAIN_TOO_LONG,     # Unit spread exceeds max chain distance
}


# ===== Check Result =====

class CoherencyResult:
	var valid: bool = true
	var issues: Array = []  # Array of issue dictionaries

	func add_issue(type: IssueType, model: ModelInstance, message: String, extra: Dictionary = {}) -> void:
		var issue = {
			"type": type,
			"model": model,
			"message": message
		}
		issue.merge(extra)
		issues.append(issue)
		valid = false


# ===== Main Check Method =====

## Checks coherency for a GameUnit per OPR rules (GF Advanced Rules v3.5.0):
## models must form an uninterrupted chain in 1" coherency (3" across different
## elevation) AND stay within 9" (6" Skirmish) of all other models.
## @param game_unit: The unit to check
## @param is_skirmish: If true, uses 6" max spread instead of 9"
## @returns: CoherencyResult with valid flag and issues array
static func check_unit_coherency(game_unit: GameUnit, is_skirmish: bool = false) -> CoherencyResult:
	var result = CoherencyResult.new()
	var models = game_unit.get_alive_models()

	# Single model or no models = always coherent
	if models.size() <= 1:
		return result

	# Check 1: The 1" adjacency graph must be a single connected chain.
	# Any model not reachable from the main chain is out of coherency.
	var components = _connected_components(models)
	if components.size() > 1:
		var main_component := _largest_component(components)
		var main_models := _models_for_indices(models, main_component)
		for component in components:
			if component == main_component:
				continue
			for index in component:
				var model: ModelInstance = models[index]
				var nearest := _nearest_in_set(model, main_models)
				var dist := _distance_between_models(model, nearest) if nearest else INF
				result.add_issue(
					IssueType.ISOLATED,
					model,
					"Model %d is out of coherency (nearest unit model: %.1f\")" % [
						model.model_index + 1, dist
					],
					{"nearest_distance": dist, "nearest_model": nearest}
				)

	# Check 2: Every model must stay within the max spread of all others.
	var max_chain = SKIRMISH_CHAIN_DISTANCE_INCHES if is_skirmish else MAX_CHAIN_DISTANCE_INCHES
	var spread := _get_max_spread_pair(models)
	if spread.distance > max_chain:
		result.add_issue(
			IssueType.CHAIN_TOO_LONG,
			null,
			"Unit spread exceeds %.0f\" (%.1f\")" % [max_chain, spread.distance],
			{
				"chain_distance": spread.distance,
				"max_allowed": max_chain,
				"model_a": spread.model_a,
				"model_b": spread.model_b,
			}
		)

	return result


# ===== Helper Methods =====

## Returns true if two models are close enough to count as a coherency link
## (1", or 3" when they sit at clearly different elevations).
static func _are_linked(model_a: ModelInstance, model_b: ModelInstance) -> bool:
	var coherency_dist := COHERENCY_DISTANCE_INCHES
	if _is_elevated_different(model_a, model_b):
		coherency_dist = ELEVATED_COHERENCY_INCHES
	return _distance_between_models(model_a, model_b) <= coherency_dist


## Splits models into connected components of the 1" coherency graph (BFS).
## Each component is an Array of indices into the models array.
static func _connected_components(models: Array[ModelInstance]) -> Array:
	var count := models.size()
	var visited: Array[bool] = []
	visited.resize(count)
	visited.fill(false)

	var components: Array = []
	for start in range(count):
		if visited[start]:
			continue

		var component: Array[int] = []
		var queue: Array[int] = [start]
		visited[start] = true

		while not queue.is_empty():
			var current: int = queue.pop_back()
			component.append(current)
			for other in range(count):
				if visited[other] or other == current:
					continue
				if _are_linked(models[current], models[other]):
					visited[other] = true
					queue.append(other)

		components.append(component)

	return components


## Returns the component with the most models (lowest first index breaks ties).
static func _largest_component(components: Array) -> Array:
	var best: Array = components[0]
	for component in components:
		if component.size() > best.size():
			best = component
	return best


## Maps an array of indices back to their ModelInstances.
static func _models_for_indices(models: Array[ModelInstance], indices: Array) -> Array[ModelInstance]:
	var result: Array[ModelInstance] = []
	for index in indices:
		result.append(models[index])
	return result


## Gets the nearest model to a given model within a set of candidates.
static func _nearest_in_set(model: ModelInstance, candidates: Array[ModelInstance]) -> ModelInstance:
	var nearest: ModelInstance = null
	var min_dist := INF

	for other in candidates:
		if model == other:
			continue

		var dist = _distance_between_models(model, other)
		if dist < min_dist:
			min_dist = dist
			nearest = other

	return nearest


## Calculates distance between two models in inches (edge-to-edge, not center-to-center).
## For oval bases, calculates actual edge distance in the direction between models.
static func _distance_between_models(model_a: ModelInstance, model_b: ModelInstance) -> float:
	if not model_a.node or not model_b.node:
		return INF
	if not is_instance_valid(model_a.node) or not is_instance_valid(model_b.node):
		return INF

	var pos_a = model_a.node.global_position
	var pos_b = model_b.node.global_position

	# 2D positions (ignore Y)
	var pos_a_2d = Vector2(pos_a.x, pos_a.z)
	var pos_b_2d = Vector2(pos_b.x, pos_b.z)
	var dist_2d = pos_a_2d.distance_to(pos_b_2d)

	if dist_2d < 0.001:
		return 0.0  # Models at same position

	# Direction from A to B (normalized)
	var dir = (pos_b_2d - pos_a_2d).normalized()

	# Get edge distance from each model's center in the direction of the other
	var edge_dist_a = _get_edge_distance_in_direction(model_a, dir.x, dir.y)
	var edge_dist_b = _get_edge_distance_in_direction(model_b, -dir.x, -dir.y)

	var edge_to_edge = dist_2d - edge_dist_a - edge_dist_b

	# Ensure non-negative (bases can overlap)
	edge_to_edge = maxf(0.0, edge_to_edge)

	# Convert meters to inches
	return edge_to_edge / INCHES_TO_METERS


## Gets the edge distance from center in a specific direction for a model.
## For oval bases, calculates actual ellipse edge distance.
static func _get_edge_distance_in_direction(model: ModelInstance, dir_x: float, dir_z: float) -> float:
	if not model.unit:
		return 0.016  # Default 32mm diameter

	var game_unit = model.unit as GameUnit
	if not game_unit or not game_unit.unit_properties:
		return 0.016

	var props = game_unit.unit_properties

	if props.get("base_is_oval", false):
		# Oval base - calculate actual ellipse edge distance
		var width_mm = props.get("base_width_mm", 32)
		var depth_mm = props.get("base_depth_mm", 32)
		var a = (width_mm / 2.0) * 0.001  # Semi-axis X (width/2) in meters
		var b = (depth_mm / 2.0) * 0.001  # Semi-axis Z (depth/2) in meters

		# Distance to ellipse edge in direction (dir_x, dir_z):
		# r = (a * b) / sqrt(b² * dir_x² + a² * dir_z²)
		var denominator = sqrt(b * b * dir_x * dir_x + a * a * dir_z * dir_z)
		if denominator < 0.0001:
			return (a + b) / 2.0  # Fallback to average
		return (a * b) / denominator
	else:
		# Round base - simple radius
		var base_mm = props.get("base_size_round", 32)
		return (base_mm / 2.0) * 0.001


## Returns the point on a model's base edge facing another world position,
## projected onto the table surface (fixed height). Used to draw measurement
## lines base-edge to base-edge - matching the in-game measurement tool - so the
## visible line equals the base-to-base gap instead of connecting centers.
static func get_ground_edge_point(model: ModelInstance, toward: Vector3, ground_y: float = 0.02) -> Vector3:
	if not model.node or not is_instance_valid(model.node):
		return toward

	var center = model.node.global_position
	var dir := Vector2(toward.x - center.x, toward.z - center.z)
	if dir.length() < 0.001:
		dir = Vector2(1.0, 0.0)
	else:
		dir = dir.normalized()

	var edge = _get_edge_distance_in_direction(model, dir.x, dir.y)
	return Vector3(center.x + dir.x * edge, ground_y, center.z + dir.y * edge)


## Checks if two models are at significantly different heights.
static func _is_elevated_different(model_a: ModelInstance, model_b: ModelInstance) -> bool:
	if not model_a.node or not model_b.node:
		return false

	var height_diff = abs(model_a.node.global_position.y - model_b.node.global_position.y)
	return height_diff > ELEVATION_THRESHOLD


## Finds the furthest-apart pair of models (the unit's spread).
## Returns {distance, model_a, model_b}.
static func _get_max_spread_pair(models: Array[ModelInstance]) -> Dictionary:
	var result := {"distance": 0.0, "model_a": null, "model_b": null}

	for i in range(models.size()):
		for j in range(i + 1, models.size()):
			var dist = _distance_between_models(models[i], models[j])
			if dist > result.distance:
				result.distance = dist
				result.model_a = models[i]
				result.model_b = models[j]

	return result


# ===== Visualization =====

## Creates a visual representation of coherency lines.
## Green lines = OK, Red lines = too far
## @param game_unit: The unit to visualize
## @param parent: Parent node for the visualization
## @returns: Node3D containing the visualization (caller must free it)
static func create_coherency_visualization(game_unit: GameUnit, parent: Node3D) -> Node3D:
	var viz = Node3D.new()
	viz.name = "CoherencyVisualization"

	var models = game_unit.get_alive_models()
	if models.size() <= 1:
		parent.add_child(viz)
		return viz

	# Create lines between adjacent models
	for i in range(models.size()):
		for j in range(i + 1, models.size()):
			var model_a = models[i]
			var model_b = models[j]

			if not model_a.node or not model_b.node:
				continue

			var dist = _distance_between_models(model_a, model_b)
			var coherency_dist = COHERENCY_DISTANCE_INCHES
			if _is_elevated_different(model_a, model_b):
				coherency_dist = ELEVATED_COHERENCY_INCHES

			# Only draw lines for nearby models (within 2x coherency)
			if dist > coherency_dist * 2:
				continue

			var color = Color.GREEN if dist <= coherency_dist else Color.RED
			var line = _create_line(model_a.node.global_position, model_b.node.global_position, color)
			viz.add_child(line)

	parent.add_child(viz)
	return viz


## Creates a 3D line between two points.
static func _create_line(from: Vector3, to: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	# Create immediate geometry for line
	var immediate_mesh = ImmediateMesh.new()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_set_color(color)
	immediate_mesh.surface_add_vertex(from + Vector3(0, 0.02, 0))  # Slightly above ground
	immediate_mesh.surface_add_vertex(to + Vector3(0, 0.02, 0))
	immediate_mesh.surface_end()

	mesh_instance.mesh = immediate_mesh

	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh_instance.material_override = material

	return mesh_instance


# ===== Auto-Fix Suggestions =====

## Suggests positions to fix coherency issues.
## @param game_unit: The unit with coherency issues
## @returns: Dictionary mapping model_index to suggested Vector3 position
static func suggest_fixes(game_unit: GameUnit) -> Dictionary:
	var suggestions: Dictionary = {}
	var result = check_unit_coherency(game_unit)

	if result.valid:
		return suggestions

	for issue in result.issues:
		if issue.type == IssueType.ISOLATED and issue.model:
			var model = issue.model as ModelInstance
			var nearest = issue.get("nearest_model") as ModelInstance

			if nearest and nearest.node and model.node:
				# Suggest moving toward the nearest model
				var from_pos = model.node.global_position
				var to_pos = nearest.node.global_position

				var direction = (to_pos - from_pos).normalized()
				var target_dist = COHERENCY_DISTANCE_INCHES * INCHES_TO_METERS * 0.9  # 90% of coherency

				var current_dist = from_pos.distance_to(to_pos)
				var move_dist = current_dist - target_dist

				var suggested_pos = from_pos + direction * move_dist
				suggested_pos.y = 0  # Keep on ground

				suggestions[model.model_index] = suggested_pos

	return suggestions
