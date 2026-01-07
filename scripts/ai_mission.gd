class_name AIMission
extends RefCounted
## Handles mission objectives and game structure for AI.
## Based on OPR Grimdark Future v3.5.1 mission rules.
## Standard mission: D3+2 objectives, seize within 3", 4 rounds, most objectives wins.


## Objective marker data
class Objective:
	var id: int = 0
	var position: Vector3 = Vector3.ZERO
	var controller: int = 0  # 0=neutral, 1=player, 2=AI
	var player_units_nearby: int = 0
	var ai_units_nearby: int = 0
	var last_seized_round: int = 0
	var node: Node3D = null

	func is_neutral() -> bool:
		return controller == 0

	func is_player_controlled() -> bool:
		return controller == 1

	func is_ai_controlled() -> bool:
		return controller == 2

	func is_contested() -> bool:
		return player_units_nearby > 0 and ai_units_nearby > 0


## Game state
class MissionState:
	var current_round: int = 1
	var max_rounds: int = 4
	var objectives: Array[Objective] = []
	var player_score: int = 0
	var ai_score: int = 0
	var is_game_over: bool = false
	var winner: int = 0  # 0=tie, 1=player, 2=AI


## Unit conversion: 1 inch = 0.0254 meters
const INCHES_TO_METERS: float = 0.0254

## Objective seizure radius: 3" per OPR rules (in METERS)
const SEIZE_RADIUS_INCHES: float = 3.0
const SEIZE_RADIUS: float = SEIZE_RADIUS_INCHES * INCHES_TO_METERS  # ~0.0762m

## Minimum distance between objectives: 9" per OPR rules (in METERS)
const MIN_OBJECTIVE_DISTANCE_INCHES: float = 9.0
const MIN_OBJECTIVE_DISTANCE: float = MIN_OBJECTIVE_DISTANCE_INCHES * INCHES_TO_METERS  # ~0.2286m

## Standard deployment zone depth: 12" per OPR rules (in METERS)
const DEPLOYMENT_DEPTH_INCHES: float = 12.0
const DEPLOYMENT_DEPTH: float = DEPLOYMENT_DEPTH_INCHES * INCHES_TO_METERS  # ~0.3048m

## Minimum distance from table edge for objectives: 6" (in METERS)
const MIN_EDGE_DISTANCE_INCHES: float = 6.0
const MIN_EDGE_DISTANCE: float = MIN_EDGE_DISTANCE_INCHES * INCHES_TO_METERS


signal objective_seized(objective: Objective, new_controller: int)
signal objective_contested(objective: Objective)
signal round_started(round_number: int)
signal round_ended(round_number: int, state: MissionState)
signal game_ended(state: MissionState)


# ===== Mission Setup =====

## Sets up objectives for the mission using OPR standard rules.
## OPR Rule: "Place D3+2 objectives. Players roll-off to go first, then alternate
## placing one marker each outside of deployment zones, over 9" away from each other."
## @param table_bounds: Table boundaries as Rect2 (in METERS)
## @param deployment_zone_depth_meters: Depth of deployment zones (in METERS), defaults to 12"
static func setup_objectives(
	table_bounds: Rect2,
	deployment_zone_depth_meters: float = DEPLOYMENT_DEPTH
) -> Array[Objective]:
	var objectives: Array[Objective] = []

	# D3+2 = 3-5 objectives (roll D3 and add 2)
	var num_objectives = (randi() % 3) + 3

	# Calculate valid placement area (outside deployment zones, with edge buffer)
	var edge_buffer = MIN_EDGE_DISTANCE
	var valid_area = Rect2(
		table_bounds.position.x + edge_buffer,
		table_bounds.position.y + deployment_zone_depth_meters + edge_buffer,
		table_bounds.size.x - 2 * edge_buffer,
		table_bounds.size.y - 2 * deployment_zone_depth_meters - 2 * edge_buffer
	)

	# Ensure valid area has positive dimensions
	if valid_area.size.x <= 0 or valid_area.size.y <= 0:
		push_warning("AIMission: Table too small for proper objective placement!")
		valid_area = Rect2(
			table_bounds.position.x + table_bounds.size.x * 0.25,
			table_bounds.position.y + table_bounds.size.y * 0.25,
			table_bounds.size.x * 0.5,
			table_bounds.size.y * 0.5
		)

	var placed_positions: Array[Vector3] = []

	# OPR Rule: Roll-off to determine who places first
	var first_player = (randi() % 2) + 1  # 1 or 2

	# Alternate placing objectives between players
	for i in range(num_objectives):
		var obj = Objective.new()
		obj.id = i + 1

		# Determine which player places this objective (alternating)
		var placing_player: int
		if i % 2 == 0:
			placing_player = first_player
		else:
			placing_player = 3 - first_player  # Swap: 1->2, 2->1

		# Find strategic position for this player
		var valid_pos = _find_objective_position_for_player(
			valid_area,
			placed_positions,
			MIN_OBJECTIVE_DISTANCE,
			placing_player,
			table_bounds
		)

		obj.position = valid_pos
		placed_positions.append(valid_pos)
		objectives.append(obj)

	return objectives


## Finds a valid objective position with strategic bias for the placing player.
## Player 1 prefers positions closer to their edge (lower Z / "south").
## Player 2 prefers positions closer to their edge (higher Z / "north").
static func _find_objective_position_for_player(
	valid_area: Rect2,
	existing: Array[Vector3],
	min_distance: float,
	placing_player: int,
	table_bounds: Rect2
) -> Vector3:
	var max_attempts = 50
	var best_pos = Vector3.ZERO
	var best_score = -INF

	# Calculate center line and player preference zones
	var table_center_z = table_bounds.position.y + table_bounds.size.y / 2.0

	for attempt in range(max_attempts):
		# Generate random position within valid area
		var test_x = valid_area.position.x + randf() * valid_area.size.x
		var test_z = valid_area.position.y + randf() * valid_area.size.y
		var test_pos = Vector3(test_x, 0, test_z)

		# Check minimum distance from existing objectives
		var too_close = false
		for existing_pos in existing:
			if test_pos.distance_to(existing_pos) < min_distance:
				too_close = true
				break

		if too_close:
			continue

		# Calculate strategic score for this player
		var score = 0.0

		# Player 1 prefers southern positions (closer to their deployment)
		# Player 2 prefers northern positions (closer to their deployment)
		var z_preference: float
		if placing_player == 1:
			# Lower Z is better for Player 1
			z_preference = table_center_z - test_z
		else:
			# Higher Z is better for Player 2
			z_preference = test_z - table_center_z

		score += z_preference * 10.0

		# Bonus for being spread out from existing objectives (better coverage)
		for existing_pos in existing:
			var dist = test_pos.distance_to(existing_pos)
			score += dist * 0.5

		# Small randomization to avoid predictable patterns
		score += randf() * 0.05

		if score > best_score:
			best_score = score
			best_pos = test_pos

	# If no valid position found, use center fallback
	if best_pos == Vector3.ZERO:
		best_pos = Vector3(
			valid_area.position.x + valid_area.size.x / 2.0,
			0,
			valid_area.position.y + valid_area.size.y / 2.0
		)

	return best_pos


## Finds a valid position for an objective using grid-based distribution.
## Ensures objectives are spread across the battlefield, not clustered.
static func _find_valid_objective_position_distributed(
	valid_area: Rect2,
	existing: Array[Vector3],
	min_distance: float,
	objective_index: int,
	total_objectives: int
) -> Vector3:
	# Calculate grid-based target position for even distribution
	# For 3-5 objectives, use patterns that spread them across the table
	var target_x: float
	var target_z: float

	match total_objectives:
		3:
			# Triangle pattern: center, left-back, right-back
			match objective_index:
				0: target_x = 0.5; target_z = 0.5  # Center
				1: target_x = 0.2; target_z = 0.3  # Left-front
				2: target_x = 0.8; target_z = 0.7  # Right-back
		4:
			# Diamond pattern
			match objective_index:
				0: target_x = 0.5; target_z = 0.2  # Center-front
				1: target_x = 0.2; target_z = 0.5  # Left-center
				2: target_x = 0.8; target_z = 0.5  # Right-center
				3: target_x = 0.5; target_z = 0.8  # Center-back
		5, _:
			# X pattern with center
			match objective_index:
				0: target_x = 0.5; target_z = 0.5  # Center
				1: target_x = 0.2; target_z = 0.2  # Front-left
				2: target_x = 0.8; target_z = 0.2  # Front-right
				3: target_x = 0.2; target_z = 0.8  # Back-left
				4: target_x = 0.8; target_z = 0.8  # Back-right
				_: target_x = randf(); target_z = randf()

	# Convert to actual position with some randomization
	var base_x = valid_area.position.x + valid_area.size.x * target_x
	var base_z = valid_area.position.y + valid_area.size.y * target_z

	# Try the target position first, then nearby positions
	var max_attempts = 30
	var jitter_range = min(valid_area.size.x, valid_area.size.y) * 0.15  # 15% jitter

	for attempt in range(max_attempts):
		var jitter_x = randf_range(-jitter_range, jitter_range) * (attempt / float(max_attempts))
		var jitter_z = randf_range(-jitter_range, jitter_range) * (attempt / float(max_attempts))

		var test_x = clampf(base_x + jitter_x, valid_area.position.x, valid_area.position.x + valid_area.size.x)
		var test_z = clampf(base_z + jitter_z, valid_area.position.y, valid_area.position.y + valid_area.size.y)
		var pos = Vector3(test_x, 0, test_z)

		# Check distance from existing objectives
		var too_close = false
		for existing_pos in existing:
			if pos.distance_to(existing_pos) < min_distance:
				too_close = true
				break

		if not too_close:
			return pos

	# Fallback: return target position anyway (better than clustering)
	return Vector3(base_x, 0, base_z)


## Legacy function for random placement (kept for compatibility).
static func _find_valid_objective_position(
	valid_area: Rect2,
	existing: Array[Vector3],
	min_distance: float
) -> Vector3:
	var max_attempts = 50

	for attempt in range(max_attempts):
		var x = valid_area.position.x + randf() * valid_area.size.x
		var z = valid_area.position.y + randf() * valid_area.size.y
		var pos = Vector3(x, 0, z)

		# Check distance from existing objectives
		var too_close = false
		for existing_pos in existing:
			if pos.distance_to(existing_pos) < min_distance:
				too_close = true
				break

		if not too_close:
			return pos

	# Fallback: return center of valid area
	return Vector3(
		valid_area.position.x + valid_area.size.x / 2,
		0,
		valid_area.position.y + valid_area.size.y / 2
	)


# ===== Objective Control =====

## Updates objective control at end of round.
## "If a unit is within 3" of a marker whilst no enemies are, it's seized"
static func update_objective_control(
	objectives: Array[Objective],
	player_units: Array[GameUnit],
	ai_units: Array[GameUnit],
	current_round: int
) -> Array[Objective]:
	for obj in objectives:
		obj.player_units_nearby = 0
		obj.ai_units_nearby = 0

		# Count player units within 3"
		for unit in player_units:
			if unit.is_destroyed():
				continue
			if _is_unit_near_objective(unit, obj):
				obj.player_units_nearby += 1

		# Count AI units within 3"
		for unit in ai_units:
			if unit.is_destroyed():
				continue
			# Shaken units can't seize or contest
			if _is_unit_shaken(unit):
				continue
			if _is_unit_near_objective(unit, obj):
				obj.ai_units_nearby += 1

		# Determine control
		var old_controller = obj.controller

		if obj.player_units_nearby > 0 and obj.ai_units_nearby == 0:
			# Player seizes
			obj.controller = 1
			obj.last_seized_round = current_round
		elif obj.ai_units_nearby > 0 and obj.player_units_nearby == 0:
			# AI seizes
			obj.controller = 2
			obj.last_seized_round = current_round
		elif obj.player_units_nearby > 0 and obj.ai_units_nearby > 0:
			# Contested - becomes neutral
			obj.controller = 0
		# else: no units nearby - control stays with current owner

	return objectives


## Checks if a unit is near an objective.
static func _is_unit_near_objective(unit: GameUnit, objective: Objective) -> bool:
	for model in unit.models:
		if not model.is_alive:
			continue
		if model.node:
			var distance = model.node.global_position.distance_to(objective.position)
			if distance <= SEIZE_RADIUS:
				return true
	return false


## Checks if a unit is shaken.
static func _is_unit_shaken(unit: GameUnit) -> bool:
	for model in unit.models:
		if model.has_marker("Shaken"):
			return true
	return false


# ===== Score Calculation =====

## Calculates current score.
static func calculate_scores(objectives: Array[Objective]) -> Dictionary:
	var player_objectives = 0
	var ai_objectives = 0

	for obj in objectives:
		match obj.controller:
			1:
				player_objectives += 1
			2:
				ai_objectives += 1

	return {
		"player": player_objectives,
		"ai": ai_objectives
	}


## Checks if game should end.
## "After 4 rounds, player with most objectives wins"
static func check_game_end(state: MissionState) -> MissionState:
	if state.current_round > state.max_rounds:
		state.is_game_over = true

		var scores = calculate_scores(state.objectives)
		state.player_score = scores.player
		state.ai_score = scores.ai

		if scores.player > scores.ai:
			state.winner = 1
		elif scores.ai > scores.player:
			state.winner = 2
		else:
			state.winner = 0  # Tie

	return state


# ===== AI Objective Priority =====

## Gets priority value for an objective from AI perspective.
## Higher value = more important to capture.
static func get_objective_priority(
	objective: Objective,
	ai_pos: Vector3,
	player_units: Array[GameUnit]
) -> float:
	var priority = 0.0

	# Base priority: distance (closer = higher priority)
	var distance = ai_pos.distance_to(objective.position)
	priority += 100.0 - distance

	# Uncontrolled objectives are higher priority
	if objective.is_neutral():
		priority += 50.0
	elif objective.is_player_controlled():
		priority += 75.0  # Capture from player!
	elif objective.is_ai_controlled():
		priority -= 25.0  # Already ours

	# Consider enemy presence
	if objective.player_units_nearby > 0:
		# Need to fight for it
		priority += 10.0 * objective.player_units_nearby

	# Consider AI presence
	if objective.ai_units_nearby > 0:
		# Already covered
		priority -= 15.0 * objective.ai_units_nearby

	return priority


## Gets the best objective for an AI unit to target.
static func get_best_objective(
	unit: GameUnit,
	objectives: Array[Objective],
	player_units: Array[GameUnit]
) -> Objective:
	var unit_pos = _get_unit_center(unit)
	var best_obj: Objective = null
	var best_priority = -INF

	for obj in objectives:
		# Skip objectives we already control with enough units
		if obj.is_ai_controlled() and obj.ai_units_nearby >= 2:
			continue

		var priority = get_objective_priority(obj, unit_pos, player_units)

		if priority > best_priority:
			best_priority = priority
			best_obj = obj

	return best_obj


# ===== Round Management =====

## Starts a new round.
static func start_round(state: MissionState) -> MissionState:
	# Reset unit activations
	# (handled by game manager)
	return state


## Ends the current round.
static func end_round(
	state: MissionState,
	player_units: Array[GameUnit],
	ai_units: Array[GameUnit]
) -> MissionState:
	# Update objective control
	state.objectives = update_objective_control(
		state.objectives,
		player_units,
		ai_units,
		state.current_round
	)

	# Calculate scores
	var scores = calculate_scores(state.objectives)
	state.player_score = scores.player
	state.ai_score = scores.ai

	# Advance round
	state.current_round += 1

	# Check for game end
	state = check_game_end(state)

	return state


# ===== Deployment =====

## Gets deployment zone.
## "Deploy fully within 12" of table edge"
static func get_deployment_zone(
	table_bounds: Rect2,
	is_ai: bool,
	deployment_depth: float = 12.0
) -> Rect2:
	if is_ai:
		# AI deploys on far edge
		return Rect2(
			table_bounds.position.x,
			table_bounds.position.y + table_bounds.size.y - deployment_depth,
			table_bounds.size.x,
			deployment_depth
		)
	else:
		# Player deploys on near edge
		return Rect2(
			table_bounds.position.x,
			table_bounds.position.y,
			table_bounds.size.x,
			deployment_depth
		)


## Checks if a unit is within deployment zone.
static func is_in_deployment_zone(
	unit: GameUnit,
	deployment_zone: Rect2
) -> bool:
	for model in unit.models:
		if not model.is_alive:
			continue
		if model.node:
			var pos = model.node.global_position
			var pos_2d = Vector2(pos.x, pos.z)
			if not deployment_zone.has_point(pos_2d):
				return false
	return true


# ===== AI Strategic Decisions =====

## Determines if AI should focus on offense or defense.
static func get_strategic_stance(state: MissionState) -> String:
	var scores = calculate_scores(state.objectives)
	var rounds_remaining = state.max_rounds - state.current_round

	# If winning and few rounds left, defend
	if scores.ai > scores.player and rounds_remaining <= 1:
		return "defensive"

	# If losing badly, aggressive attack
	if scores.player > scores.ai + 1:
		return "aggressive"

	# Default: balanced
	return "balanced"


## Gets units that should defend objectives vs attack.
static func assign_unit_roles(
	ai_units: Array[GameUnit],
	objectives: Array[Objective],
	stance: String
) -> Dictionary:
	var assignments = {
		"defenders": [],
		"attackers": []
	}

	# Count how many units we need to defend
	var ai_controlled = objectives.filter(func(o): return o.is_ai_controlled())
	var defenders_needed = ai_controlled.size()

	if stance == "defensive":
		defenders_needed = min(ai_units.size() - 1, defenders_needed + 2)
	elif stance == "aggressive":
		defenders_needed = max(0, defenders_needed - 1)

	# Assign defenders (prefer shooting units)
	var available = ai_units.duplicate()
	for i in range(defenders_needed):
		if available.is_empty():
			break

		var best_defender: GameUnit = null
		var best_score = -INF

		for unit in available:
			var unit_type = AIUnitClassifier.classify(unit)
			var score = 0.0

			# Shooting units make better defenders
			if unit_type == AIUnitClassifier.UnitType.SHOOTING:
				score += 10.0
			elif unit_type == AIUnitClassifier.UnitType.HYBRID:
				score += 5.0

			if score > best_score:
				best_score = score
				best_defender = unit

		if best_defender:
			assignments.defenders.append(best_defender)
			available.erase(best_defender)

	# Rest are attackers
	assignments.attackers = available

	return assignments


# ===== Unit Coherency Check =====

## Checks if unit maintains coherency around objective.
## "Within 3" of objective, maintain 1" coherency"
static func check_objective_coherency(
	unit: GameUnit,
	objective: Objective
) -> bool:
	var models_near_objective = 0

	for model in unit.models:
		if not model.is_alive:
			continue
		if model.node:
			var distance = model.node.global_position.distance_to(objective.position)
			if distance <= SEIZE_RADIUS:
				models_near_objective += 1

	# At least one model must be near objective to seize it
	return models_near_objective > 0


# ===== Helper Methods =====

static func _get_unit_center(game_unit: GameUnit) -> Vector3:
	var sum = Vector3.ZERO
	var count = 0
	for model in game_unit.models:
		if model.is_alive and model.node:
			sum += model.node.global_position
			count += 1
	if count > 0:
		return sum / count
	return Vector3.ZERO
