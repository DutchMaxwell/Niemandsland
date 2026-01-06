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

## Height difference threshold for "elevated" check (in meters)
const ELEVATION_THRESHOLD := 0.05  # 5cm

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

## Checks coherency for a GameUnit.
## @param game_unit: The unit to check
## @param is_skirmish: If true, uses 6" max chain instead of 9"
## @returns: CoherencyResult with valid flag and issues array
static func check_unit_coherency(game_unit: GameUnit, is_skirmish: bool = false) -> CoherencyResult:
	var result = CoherencyResult.new()
	var models = game_unit.get_alive_models()

	# Single model or no models = always coherent
	if models.size() <= 1:
		return result

	# Check 1: Each model must be within coherency of at least one other
	for model in models:
		if not _has_coherent_neighbor(model, models):
			var nearest = _get_nearest_model(model, models)
			var dist = _distance_between_models(model, nearest)
			result.add_issue(
				IssueType.ISOLATED,
				model,
				"Model %d is out of coherency (nearest: %.1f\")" % [model.model_index + 1, dist],
				{"nearest_distance": dist, "nearest_model": nearest}
			)

	# Check 2: Max chain length
	var max_chain = SKIRMISH_CHAIN_DISTANCE_INCHES if is_skirmish else MAX_CHAIN_DISTANCE_INCHES
	var chain_dist = _get_max_chain_distance(models)
	if chain_dist > max_chain:
		result.add_issue(
			IssueType.CHAIN_TOO_LONG,
			null,
			"Unit chain exceeds %.0f\" (%.1f\")" % [max_chain, chain_dist],
			{"chain_distance": chain_dist, "max_allowed": max_chain}
		)

	return result


# ===== Helper Methods =====

## Checks if a model has at least one neighbor within coherency.
static func _has_coherent_neighbor(model: ModelInstance, all_models: Array[ModelInstance]) -> bool:
	for other in all_models:
		if model == other:
			continue

		var dist = _distance_between_models(model, other)
		var coherency_dist = COHERENCY_DISTANCE_INCHES

		# Use elevated coherency if height difference is significant
		if _is_elevated_different(model, other):
			coherency_dist = ELEVATED_COHERENCY_INCHES

		if dist <= coherency_dist:
			return true

	return false


## Gets the nearest model to a given model.
static func _get_nearest_model(model: ModelInstance, all_models: Array[ModelInstance]) -> ModelInstance:
	var nearest: ModelInstance = null
	var min_dist := INF

	for other in all_models:
		if model == other:
			continue

		var dist = _distance_between_models(model, other)
		if dist < min_dist:
			min_dist = dist
			nearest = other

	return nearest


## Calculates distance between two models in inches (edge-to-edge, not center-to-center).
static func _distance_between_models(model_a: ModelInstance, model_b: ModelInstance) -> float:
	if not model_a.node or not model_b.node:
		return INF
	if not is_instance_valid(model_a.node) or not is_instance_valid(model_b.node):
		return INF

	var pos_a = model_a.node.global_position
	var pos_b = model_b.node.global_position

	# 2D distance (ignore Y for base measurement)
	var dist_2d = Vector2(pos_a.x, pos_a.z).distance_to(Vector2(pos_b.x, pos_b.z))

	# Get base radii and subtract them to get edge-to-edge distance
	var radius_a = _get_base_radius_meters(model_a)
	var radius_b = _get_base_radius_meters(model_b)
	var edge_to_edge = dist_2d - radius_a - radius_b

	# Ensure non-negative (bases can overlap)
	edge_to_edge = maxf(0.0, edge_to_edge)

	# Convert meters to inches
	return edge_to_edge / INCHES_TO_METERS


## Gets the base radius in meters for a model.
## For oval bases, uses the smaller dimension to be conservative (avoids false positives).
static func _get_base_radius_meters(model: ModelInstance) -> float:
	# Try to get from the unit's properties
	if model.unit:
		var game_unit = model.unit as GameUnit
		if game_unit and game_unit.unit_properties:
			var props = game_unit.unit_properties
			# Check for oval bases - use smaller dimension to be conservative
			if props.get("base_is_oval", false):
				var width_mm = props.get("base_width_mm", 32)
				var depth_mm = props.get("base_depth_mm", 32)
				# Use minimum dimension for edge-to-edge (conservative)
				var min_dim = mini(width_mm, depth_mm)
				return (min_dim / 2.0) * 0.001  # mm to meters
			else:
				var base_mm = props.get("base_size_round", 32)
				return (base_mm / 2.0) * 0.001  # mm to meters
	# Default: 32mm base = 16mm radius
	return 0.016


## Checks if two models are at significantly different heights.
static func _is_elevated_different(model_a: ModelInstance, model_b: ModelInstance) -> bool:
	if not model_a.node or not model_b.node:
		return false

	var height_diff = abs(model_a.node.global_position.y - model_b.node.global_position.y)
	return height_diff > ELEVATION_THRESHOLD


## Calculates the maximum chain distance (furthest two models apart).
static func _get_max_chain_distance(models: Array[ModelInstance]) -> float:
	var max_dist := 0.0

	for i in range(models.size()):
		for j in range(i + 1, models.size()):
			var dist = _distance_between_models(models[i], models[j])
			if dist > max_dist:
				max_dist = dist

	return max_dist


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
