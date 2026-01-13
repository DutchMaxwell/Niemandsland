class_name AIObjectiveSetup
extends RefCounted
## Handles objective placement for AI according to Solo & Co-Op rules.
## "Divide objective area into 6 equal squares, roll for random square,
## place objective in center. If not valid, roll for another square."
## NOTE: All distances are in METERS internally.


## Unit conversion: 1 inch = 0.0254 meters
const INCHES_TO_METERS: float = 0.0254

## Default minimum distance between objectives: 9" (in meters)
const DEFAULT_MIN_DISTANCE: float = 9.0 * INCHES_TO_METERS  # ~0.2286m


## Result of objective placement
class ObjectivePlacement:
	var position: Vector3 = Vector3.ZERO
	var grid_index: int = -1  # 0-5 for the 6 squares
	var is_valid: bool = false


## Calculates 6 equal squares for objective placement.
## Returns array of Rect2 representing the squares.
static func calculate_objective_grid(table_bounds: Rect2) -> Array[Rect2]:
	var grid: Array[Rect2] = []

	# 6 squares arranged in 2 rows x 3 columns
	var col_width = table_bounds.size.x / 3.0
	var row_height = table_bounds.size.y / 2.0

	for row in range(2):
		for col in range(3):
			var rect = Rect2(
				table_bounds.position.x + col * col_width,
				table_bounds.position.y + row * row_height,
				col_width,
				row_height
			)
			grid.append(rect)

	return grid


## Places an objective for the AI.
## @param grid: The 6-square grid from calculate_objective_grid()
## @param existing_objectives: Already placed objectives (for collision check)
## @param min_distance: Minimum distance between objectives (in METERS)
## @param mission_rules: Optional mission-specific placement rules
static func place_objective(
	grid: Array[Rect2],
	existing_objectives: Array[Vector3],
	min_distance: float = DEFAULT_MIN_DISTANCE,
	mission_rules: Dictionary = {}
) -> ObjectivePlacement:
	var result = ObjectivePlacement.new()

	# Track which squares we've tried
	var tried_squares: Array[int] = []

	while tried_squares.size() < 6:
		# Roll D6 for random square (0-5)
		var square_index = randi() % 6

		# Skip if already tried
		if square_index in tried_squares:
			continue

		tried_squares.append(square_index)

		var square = grid[square_index]
		var center = Vector3(
			square.position.x + square.size.x / 2,
			0,  # Y is ground level
			square.position.y + square.size.y / 2
		)

		# Check if valid position
		if _is_valid_objective_position(center, existing_objectives, min_distance, mission_rules):
			result.position = center
			result.grid_index = square_index
			result.is_valid = true
			return result

		# Try to adjust position toward next valid square
		result = _try_adjust_position(
			center,
			grid,
			tried_squares,
			existing_objectives,
			min_distance,
			mission_rules
		)

		if result.is_valid:
			return result

	# Could not find valid position
	result.is_valid = false
	return result


## Checks if an objective position is valid.
static func _is_valid_objective_position(
	pos: Vector3,
	existing: Array[Vector3],
	min_distance: float,
	mission_rules: Dictionary
) -> bool:
	# Check distance from other objectives
	for obj in existing:
		if pos.distance_to(obj) < min_distance:
			return false

	# Check mission-specific rules
	if mission_rules.has("min_edge_distance"):
		var edge_dist = mission_rules["min_edge_distance"]
		# TODO: Check edge distance based on table bounds

	if mission_rules.has("max_center_distance"):
		var center_dist = mission_rules["max_center_distance"]
		# TODO: Check center distance

	return true


## Tries to adjust position toward another valid square.
static func _try_adjust_position(
	original_pos: Vector3,
	grid: Array[Rect2],
	tried_squares: Array[int],
	existing_objectives: Array[Vector3],
	min_distance: float,
	mission_rules: Dictionary
) -> ObjectivePlacement:
	var result = ObjectivePlacement.new()

	# Try remaining squares
	for i in range(6):
		if i in tried_squares:
			continue

		var target_square = grid[i]
		var target_center = Vector3(
			target_square.position.x + target_square.size.x / 2,
			0,
			target_square.position.y + target_square.size.y / 2
		)

		# Move original position toward target just enough to be valid
		var direction = (target_center - original_pos).normalized()
		var adjusted_pos = original_pos

		# Step toward target until valid or past it
		for step in range(1, 10):
			adjusted_pos = original_pos + direction * (step * 3.0)  # 3" steps

			if _is_valid_objective_position(adjusted_pos, existing_objectives, min_distance, mission_rules):
				result.position = adjusted_pos
				result.grid_index = i
				result.is_valid = true
				return result

			# Don't go past target
			if adjusted_pos.distance_to(original_pos) > original_pos.distance_to(target_center):
				break

	result.is_valid = false
	return result


## Places all AI objectives for a mission.
## @param num_objectives: Number of objectives to place
## @param table_bounds: Table boundaries as Rect2
## @param player_objectives: Already placed player objectives
static func place_all_ai_objectives(
	num_objectives: int,
	table_bounds: Rect2,
	player_objectives: Array[Vector3]
) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var grid = calculate_objective_grid(table_bounds)
	var existing = player_objectives.duplicate()

	for i in range(num_objectives):
		var placement = place_objective(grid, existing)

		if placement.is_valid:
			result.append(placement.position)
			existing.append(placement.position)
		else:
			# Fallback: place in center of random empty square with reduced min distance
			var reduced_min_distance = DEFAULT_MIN_DISTANCE * 0.66  # ~6" instead of 9"
			for j in range(6):
				var square = grid[j]
				var center = Vector3(
					square.position.x + square.size.x / 2,
					0,
					square.position.y + square.size.y / 2
				)

				var too_close = false
				for obj in existing:
					if center.distance_to(obj) < reduced_min_distance:
						too_close = true
						break

				if not too_close:
					result.append(center)
					existing.append(center)
					break

	return result


## Creates objective markers at positions.
## This is a factory method for creating the actual 3D markers.
static func create_objective_markers(
	positions: Array[Vector3],
	parent: Node3D,
	marker_scene: PackedScene = null
) -> Array[Node3D]:
	var markers: Array[Node3D] = []

	for i in range(positions.size()):
		var marker: Node3D

		if marker_scene:
			marker = marker_scene.instantiate()
		else:
			# Create simple cylinder marker
			marker = _create_default_marker(i + 1)

		marker.position = positions[i]
		parent.add_child(marker)
		markers.append(marker)

	return markers


## Creates a default objective marker (40mm yellow base with black border and number).
## Design matches OPR standard objective markers.
static func _create_default_marker(number: int) -> Node3D:
	var marker = Node3D.new()
	marker.name = "Objective_%d" % number

	# Constants for 40mm base (in meters)
	const BASE_DIAMETER_MM: float = 40.0
	const BASE_RADIUS: float = BASE_DIAMETER_MM * 0.001 / 2.0  # 0.02m
	const BASE_HEIGHT: float = 0.003  # 3mm tall base
	const BORDER_WIDTH: float = 0.002  # 2mm black border

	# Create black border ring (slightly larger cylinder underneath)
	var border_mesh = MeshInstance3D.new()
	var border_cylinder = CylinderMesh.new()
	border_cylinder.top_radius = BASE_RADIUS + BORDER_WIDTH
	border_cylinder.bottom_radius = BASE_RADIUS + BORDER_WIDTH
	border_cylinder.height = BASE_HEIGHT
	border_mesh.mesh = border_cylinder
	border_mesh.name = "Border"

	# Black material for border
	var border_material = StandardMaterial3D.new()
	border_material.albedo_color = Color(0.1, 0.1, 0.1)  # Near-black
	border_material.metallic = 0.0
	border_material.roughness = 0.8
	border_mesh.material_override = border_material

	marker.add_child(border_mesh)

	# Create yellow main base (on top of border)
	var base_mesh = MeshInstance3D.new()
	var base_cylinder = CylinderMesh.new()
	base_cylinder.top_radius = BASE_RADIUS
	base_cylinder.bottom_radius = BASE_RADIUS
	base_cylinder.height = BASE_HEIGHT + 0.001  # Slightly taller to sit above border
	base_mesh.mesh = base_cylinder
	base_mesh.position.y = 0.0005  # Raise slightly above border
	base_mesh.name = "Base"

	# Yellow material for base
	var base_material = StandardMaterial3D.new()
	base_material.albedo_color = Color(0.95, 0.85, 0.2)  # Bright yellow
	base_material.metallic = 0.1
	base_material.roughness = 0.6
	base_mesh.material_override = base_material

	marker.add_child(base_mesh)

	# Add objective number label on top of the base
	var label = Label3D.new()
	label.text = str(number)
	label.position.y = BASE_HEIGHT + 0.002  # Just barely above the base surface
	label.pixel_size = 0.0004  # ~24mm text height with font_size 60
	label.font_size = 60  # Fits nicely on 40mm base
	label.modulate = Color(0.05, 0.05, 0.05)  # Very dark text (near-black)
	label.outline_modulate = Color(1, 1, 1)  # White outline for contrast
	label.outline_size = 4  # Thinner outline
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED  # Flat on ground
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Rotate to face up (lie flat on the base)
	label.rotation_degrees.x = -90
	label.name = "Number"

	marker.add_child(label)

	return marker
