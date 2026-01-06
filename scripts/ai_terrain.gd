class_name AITerrain
extends RefCounted
## Handles terrain interactions for AI units.
## Based on OPR Grimdark Future v3.5.1 terrain rules.
## Terrain types: Open, Impassable, Blocking, Cover, Difficult, Dangerous, Elevated
##
## UNIT CONVENTION:
## - All public API distances are in INCHES (Wargaming standard)
## - Internal calculations use METERS (Godot standard)
## - Base sizes are in MILLIMETERS
## - Use INCHES_TO_METERS for conversions


# ==============================================================================
# CONSTANTS
# ==============================================================================

## Conversion: 1 inch = 0.0254 meters
const INCHES_TO_METERS: float = 0.0254

## Conversion: 1 millimeter = 0.001 meters (for base sizes)
const MM_TO_METERS: float = 0.001

## Terrain height threshold for "elevated" classification (in inches)
const ELEVATED_HEIGHT_THRESHOLD_INCHES: float = 3.0

## Standard movement limits (in inches)
const DIFFICULT_TERRAIN_MAX_MOVEMENT_INCHES: float = 6.0

## Cover search radius default (in inches)
const DEFAULT_COVER_SEARCH_RADIUS_INCHES: float = 6.0

## Standard coherency distances (in inches)
const STANDARD_COHERENCY_INCHES: float = 1.0
const ELEVATED_COHERENCY_INCHES: float = 3.0


# ==============================================================================
# DATA STRUCTURES
# ==============================================================================

## Terrain piece data
class TerrainPiece:
	var id: String = ""
	var bounds: AABB = AABB()           ## Bounds in METERS (for Godot collision)
	var position: Vector3 = Vector3.ZERO ## Position in METERS (Godot world space)
	var types: Array[String] = []        ## ["cover", "difficult", "dangerous", "blocking", "impassable"]
	var height: float = 0.0              ## Height in INCHES (for rules calculations)
	var node: Node3D = null              ## Optional reference to visual node

	func is_cover() -> bool:
		return "cover" in types

	func is_difficult() -> bool:
		return "difficult" in types

	func is_dangerous() -> bool:
		return "dangerous" in types

	func is_impassable() -> bool:
		return "impassable" in types

	func is_blocking() -> bool:
		return "blocking" in types

	func is_elevated() -> bool:
		return height > ELEVATED_HEIGHT_THRESHOLD_INCHES


## Terrain query result
class TerrainCheck:
	var is_in_cover: bool = false
	var is_in_difficult: bool = false
	var is_in_dangerous: bool = false
	var is_on_elevated: bool = false
	var cover_piece: TerrainPiece = null
	var blocking_los: bool = false


# ===== Terrain Analysis =====

## Checks terrain at a position.
static func check_terrain_at(pos: Vector3, terrain_pieces: Array[TerrainPiece]) -> TerrainCheck:
	var result = TerrainCheck.new()

	for piece in terrain_pieces:
		if piece.bounds.has_point(pos):
			if piece.is_cover():
				result.is_in_cover = true
				result.cover_piece = piece
			if piece.is_difficult():
				result.is_in_difficult = true
			if piece.is_dangerous():
				result.is_in_dangerous = true
			if piece.is_elevated():
				result.is_on_elevated = true

	return result


## Checks if a path crosses difficult terrain.
static func path_crosses_difficult(
	from_pos: Vector3,
	to_pos: Vector3,
	terrain_pieces: Array[TerrainPiece]
) -> bool:
	for piece in terrain_pieces:
		if not piece.is_difficult():
			continue
		if _path_intersects_aabb(from_pos, to_pos, piece.bounds):
			return true
	return false


## Checks if a path crosses dangerous terrain.
static func path_crosses_dangerous(
	from_pos: Vector3,
	to_pos: Vector3,
	terrain_pieces: Array[TerrainPiece]
) -> bool:
	for piece in terrain_pieces:
		if not piece.is_dangerous():
			continue
		if _path_intersects_aabb(from_pos, to_pos, piece.bounds):
			return true
	return false


## Checks if line of sight is blocked by terrain.
static func is_los_blocked(
	from_pos: Vector3,
	to_pos: Vector3,
	terrain_pieces: Array[TerrainPiece]
) -> bool:
	for piece in terrain_pieces:
		if not piece.is_blocking():
			continue
		if _path_intersects_aabb(from_pos, to_pos, piece.bounds):
			return true
	return false


## Finds cover terrain near a position that provides cover from a threat.
## @param pos: Current position (METERS, Godot world space)
## @param threat_pos: Threat position (METERS, Godot world space)
## @param terrain_pieces: Array of terrain pieces to search
## @param max_distance_inches: Maximum search radius in INCHES (default: 6")
## @return: Best cover position (METERS, Godot world space)
static func find_cover_near(
	pos: Vector3,
	threat_pos: Vector3,
	terrain_pieces: Array[TerrainPiece],
	max_distance_inches: float = DEFAULT_COVER_SEARCH_RADIUS_INCHES
) -> Vector3:
	var best_cover = pos
	var best_score = -INF
	var max_distance_meters := max_distance_inches * INCHES_TO_METERS

	for piece in terrain_pieces:
		if not piece.is_cover():
			continue

		var piece_pos = piece.position
		var distance = pos.distance_to(piece_pos)

		if distance > max_distance_meters:
			continue

		# Score: prefer cover between us and threat
		var to_threat = (threat_pos - pos).normalized()
		var to_cover = (piece_pos - pos).normalized()
		var alignment = to_threat.dot(to_cover)

		# Prefer cover that's closer and more aligned with threat direction
		var score = alignment * 10 - distance

		if score > best_score:
			best_score = score
			best_cover = piece_pos

	return best_cover


## Gets safe path avoiding dangerous terrain.
static func get_safe_path(
	from_pos: Vector3,
	to_pos: Vector3,
	terrain_pieces: Array[TerrainPiece],
	unit: GameUnit
) -> Array[Vector3]:
	var path: Array[Vector3] = [from_pos]

	# Check if unit ignores terrain
	if unit.has_special_rule("Flying"):
		path.append(to_pos)
		return path

	var ignores_difficult = unit.has_special_rule("Strider") or unit.has_special_rule("Flying")

	# Find dangerous terrain in path
	var obstacles: Array[TerrainPiece] = []
	for piece in terrain_pieces:
		if piece.is_dangerous() or (piece.is_difficult() and not ignores_difficult):
			if _path_intersects_aabb(from_pos, to_pos, piece.bounds):
				obstacles.append(piece)

	if obstacles.is_empty():
		path.append(to_pos)
		return path

	# Simple avoidance: go around obstacles
	for obstacle in obstacles:
		# Find point to go around
		var avoid_point = _find_avoidance_point(from_pos, to_pos, obstacle)
		path.append(avoid_point)

	path.append(to_pos)
	return path


# ==============================================================================
# DANGEROUS TERRAIN TESTS
# ==============================================================================

## Takes a dangerous terrain test for a unit.
## Per OPR rules: "Roll one die for each model, for each roll of 1 the model takes 1 wound."
## Note: Each model can only take 1 wound from dangerous terrain, regardless of Tough value.
##
## @param unit: The unit taking the dangerous terrain test
## @return: Total number of wounds taken by the unit
static func take_dangerous_terrain_test(unit: GameUnit) -> int:
	if unit == null:
		return 0

	var total_wounds := 0

	for model in unit.models:
		if model == null or not model.is_alive:
			continue

		# Per OPR: Roll 1 die per model, on a 1 the model takes 1 wound
		var roll := randi() % 6 + 1
		if roll == 1:
			total_wounds += 1

	return total_wounds


# ===== AI Terrain Behavior =====

## Determines if AI should enter terrain.
## Based on OPR Solo & Co-Op rules.
static func should_enter_terrain(
	unit: GameUnit,
	terrain: TerrainPiece,
	is_objective_inside: bool,
	is_enemy_in_charge_range: bool
) -> bool:
	# Flying ignores all terrain
	if unit.has_special_rule("Flying"):
		return true

	# Dangerous terrain
	if terrain.is_dangerous():
		if is_objective_inside:
			return true
		return false

	# Difficult terrain
	if terrain.is_difficult():
		if unit.has_special_rule("Strider"):
			return true
		if is_objective_inside:
			return true
		if is_enemy_in_charge_range:
			return true
		return false

	# Cover terrain - always enter if not also difficult
	if terrain.is_cover() and not terrain.is_difficult():
		return true

	return true


## Gets movement limit when crossing difficult terrain.
## Per OPR: "Units may not move more than 6" when crossing difficult terrain"
##
## @param unit: The unit attempting to move
## @param crosses_difficult: Whether the path crosses difficult terrain
## @param base_movement_inches: Base movement distance in INCHES
## @return: Adjusted movement distance in INCHES
static func get_movement_limit(
	unit: GameUnit,
	crosses_difficult: bool,
	base_movement_inches: float
) -> float:
	if not crosses_difficult:
		return base_movement_inches

	if unit == null:
		return minf(DIFFICULT_TERRAIN_MAX_MOVEMENT_INCHES, base_movement_inches)

	if unit.has_special_rule("Strider") or unit.has_special_rule("Flying"):
		return base_movement_inches

	return minf(DIFFICULT_TERRAIN_MAX_MOVEMENT_INCHES, base_movement_inches)


# ===== Cover Rules =====

## Checks if a unit gets cover bonus.
## Per OPR: "Majority of models fully inside cover or behind sight blocker"
## Note: A model is counted as "in cover" if EITHER in cover terrain OR behind blocking terrain,
## but only counted once even if both conditions are met.
##
## @param unit: The defending unit
## @param terrain_pieces: Array of terrain pieces
## @param attacker_pos: Position of the attacker (METERS, Godot world space)
## @return: True if majority of models are in cover
static func unit_has_cover(
	unit: GameUnit,
	terrain_pieces: Array[TerrainPiece],
	attacker_pos: Vector3
) -> bool:
	if unit == null:
		return false

	var in_cover := 0
	var total := 0

	for model in unit.models:
		if model == null or not model.is_alive:
			continue

		total += 1

		if model.node == null:
			continue

		var model_pos := model.node.global_position
		var model_has_cover := false

		# Check if in cover terrain
		for piece in terrain_pieces:
			if piece.is_cover() and piece.bounds.has_point(model_pos):
				model_has_cover = true
				break

		# Only check blocking terrain if not already in cover
		if not model_has_cover:
			for piece in terrain_pieces:
				if piece.is_blocking() and _is_behind_cover(model_pos, attacker_pos, piece):
					model_has_cover = true
					break

		if model_has_cover:
			in_cover += 1

	# Majority = more than half (explicit float division for clarity)
	return total > 0 and in_cover > (total / 2.0)


## Checks if a position is behind cover relative to attacker.
static func _is_behind_cover(
	defender_pos: Vector3,
	attacker_pos: Vector3,
	cover: TerrainPiece
) -> bool:
	# Cover must be between attacker and defender
	var to_defender = (defender_pos - attacker_pos).normalized()
	var to_cover = (cover.position - attacker_pos).normalized()

	# Check if cover is roughly in the direction of defender
	var alignment = to_defender.dot(to_cover)
	if alignment < 0.5:
		return false

	# Check if cover is closer than defender
	var cover_dist = attacker_pos.distance_to(cover.position)
	var defender_dist = attacker_pos.distance_to(defender_pos)

	return cover_dist < defender_dist


# ===== Elevated Terrain =====

## Gets coherency distance for a unit based on elevation.
## Per OPR: "If not all models can fit on elevation, 3" coherency is allowed"
##
## @param unit: The unit to check
## @param terrain_pieces: Array of terrain pieces
## @return: Required coherency distance in INCHES
static func get_coherency_distance(
	unit: GameUnit,
	terrain_pieces: Array[TerrainPiece]
) -> float:
	if unit == null:
		return STANDARD_COHERENCY_INCHES

	var has_elevated := false
	var has_ground := false

	for model in unit.models:
		if model == null or not model.is_alive or model.node == null:
			continue

		var pos := model.node.global_position
		var on_elevated := false

		for piece in terrain_pieces:
			if piece.is_elevated() and piece.bounds.has_point(pos):
				on_elevated = true
				break

		if on_elevated:
			has_elevated = true
		else:
			has_ground = true

	# If models at different elevations, allow extended coherency
	if has_elevated and has_ground:
		return ELEVATED_COHERENCY_INCHES

	return STANDARD_COHERENCY_INCHES


# ===== Artillery Deployment =====

## Finds best deployment position for Artillery.
## "Deploy in highest position with most LOS"
static func find_artillery_position(
	deployment_zone: Rect2,
	terrain_pieces: Array[TerrainPiece],
	enemy_units: Array[GameUnit]
) -> Vector3:
	var best_pos = Vector3(
		deployment_zone.position.x + deployment_zone.size.x / 2,
		0,
		deployment_zone.position.y + deployment_zone.size.y / 2
	)
	var best_score = -INF

	# Check elevated terrain in deployment zone
	for piece in terrain_pieces:
		if not piece.is_elevated():
			continue

		var piece_center = piece.position
		var pos_2d = Vector2(piece_center.x, piece_center.z)

		if not deployment_zone.has_point(pos_2d):
			continue

		# Score: height + LOS to enemies
		var score = piece.height * 10

		# Count enemies visible from this position
		for enemy in enemy_units:
			var enemy_pos = _get_unit_center(enemy)
			if not is_los_blocked(piece_center, enemy_pos, terrain_pieces):
				score += 5

		if score > best_score:
			best_score = score
			best_pos = piece_center

	return best_pos


# ===== Helper Methods =====

static func _path_intersects_aabb(from_pos: Vector3, to_pos: Vector3, aabb: AABB) -> bool:
	var direction = to_pos - from_pos
	var length = direction.length()
	if length < 0.001:
		return aabb.has_point(from_pos)

	direction = direction.normalized()

	# Ray-AABB intersection test
	var t_min = 0.0
	var t_max = length

	for i in range(3):
		var inv_d = 1.0 / direction[i] if abs(direction[i]) > 0.0001 else INF
		var t0 = (aabb.position[i] - from_pos[i]) * inv_d
		var t1 = (aabb.position[i] + aabb.size[i] - from_pos[i]) * inv_d

		if t0 > t1:
			var temp = t0
			t0 = t1
			t1 = temp

		t_min = max(t_min, t0)
		t_max = min(t_max, t1)

		if t_max < t_min:
			return false

	return true


static func _find_avoidance_point(
	from_pos: Vector3,
	to_pos: Vector3,
	obstacle: TerrainPiece
) -> Vector3:
	# Simple avoidance: go around the side of the obstacle
	var obstacle_center = obstacle.position
	var path_dir = (to_pos - from_pos).normalized()

	# Perpendicular direction
	var perp = Vector3(-path_dir.z, 0, path_dir.x)

	# Choose side based on which is closer to our path
	var side1 = obstacle_center + perp * (obstacle.bounds.size.x / 2 + 1)
	var side2 = obstacle_center - perp * (obstacle.bounds.size.x / 2 + 1)

	var dist1 = from_pos.distance_to(side1) + side1.distance_to(to_pos)
	var dist2 = from_pos.distance_to(side2) + side2.distance_to(to_pos)

	return side1 if dist1 < dist2 else side2


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
