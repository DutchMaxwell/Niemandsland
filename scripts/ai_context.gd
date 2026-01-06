class_name AIContext
extends RefCounted
## Holds game state information needed for AI decision making.
## This is populated by the AIManager before each unit activation.
## NOTE: All distances are stored in METERS for consistency with Godot positions.


## Conversion constant: 1 inch = 0.0254 meters
const INCHES_TO_METERS: float = 0.0254


## Objective data structure
class ObjectiveData:
	var index: int = -1
	var position: Vector3 = Vector3.ZERO
	var is_ai_controlled: bool = false
	var ai_units_nearby: int = 0
	var player_units_nearby: int = 0


# ===== Game State =====

## All AI-controlled units
var ai_units: Array[GameUnit] = []

## All player-controlled (enemy) units
var enemy_units: Array[GameUnit] = []

## All objectives on the table
var objectives: Array[ObjectiveData] = []

## Current round number
var current_round: int = 1

## AI player ID
var ai_player_id: int = 2

## Player ID (human)
var player_id: int = 1


# ===== Movement Constants (in METERS) =====

## Standard advance distance: 6" = 0.1524m
var advance_distance: float = 6.0 * INCHES_TO_METERS

## Standard rush distance: 12" = 0.3048m
var rush_distance: float = 12.0 * INCHES_TO_METERS

## Standard charge range: 12" = 0.3048m
var charge_range: float = 12.0 * INCHES_TO_METERS

## Objective control radius: 3" = 0.0762m
var objective_radius: float = 3.0 * INCHES_TO_METERS

## "Enemies in the way" detection radius: 6" = 0.1524m
var path_detection_radius: float = 6.0 * INCHES_TO_METERS


# ===== Table Sections =====

## Table sections for activation order (1, 2, 3)
## Defined along AI's deployment zone edge
var table_sections: Array[Rect2] = []


# ===== Challenge Bonus =====

## Whether challenge bonus is enabled
var challenge_bonus_enabled: bool = false

## AI gets +1 to hit if holding >= player objectives
var ai_hit_bonus: int = 0

## AI gets +1 to defense if holding < player objectives
var ai_defense_bonus: int = 0


# ===== Terrain Data =====

## Areas of cover terrain
var cover_areas: Array[AABB] = []

## Areas of difficult terrain
var difficult_terrain: Array[AABB] = []

## Areas of dangerous terrain
var dangerous_terrain: Array[AABB] = []


# ===== Query Methods =====

## Gets the nearest uncontrolled objective from a position.
func get_nearest_uncontrolled_objective(from_pos: Vector3) -> ObjectiveData:
	var nearest: ObjectiveData = null
	var nearest_dist = INF

	for obj in objectives:
		if obj.is_ai_controlled:
			continue

		var dist = from_pos.distance_to(obj.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = obj

	return nearest


## Gets the nearest enemy unit from a position.
func get_nearest_enemy(from_pos: Vector3) -> GameUnit:
	var nearest: GameUnit = null
	var nearest_dist = INF

	for enemy in enemy_units:
		if enemy.is_destroyed():
			continue

		var enemy_pos = _get_unit_center(enemy)
		var dist = from_pos.distance_to(enemy_pos)

		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy

	return nearest


## Gets enemies within the path detection radius of a line.
## "Enemy units within 6" of the path count as being in the way"
func get_enemies_in_path(from_pos: Vector3, to_pos: Vector3) -> Array[GameUnit]:
	var result: Array[GameUnit] = []
	var path_length := from_pos.distance_to(to_pos)

	# Guard against zero-length path (division by zero)
	if path_length < 0.001:
		return result

	var path_dir := (to_pos - from_pos).normalized()

	for enemy in enemy_units:
		if enemy.is_destroyed():
			continue

		var enemy_pos = _get_unit_center(enemy)

		# Project enemy onto path line
		var to_enemy = enemy_pos - from_pos
		var projection = to_enemy.dot(path_dir)

		# Enemy must be between start and end (not behind or past)
		if projection < 0 or projection > path_length:
			continue

		# Calculate perpendicular distance
		var closest_point = from_pos + path_dir * projection
		var perp_distance = enemy_pos.distance_to(closest_point)

		if perp_distance <= path_detection_radius:
			result.append(enemy)

	return result


## Gets AI units in a specific table section (1, 2, or 3).
func get_ai_units_in_section(section: int) -> Array[GameUnit]:
	var result: Array[GameUnit] = []

	if section < 1 or section > table_sections.size():
		return result

	var section_rect = table_sections[section - 1]

	for unit in ai_units:
		if unit.is_destroyed() or unit.is_activated:
			continue

		var unit_pos = _get_unit_center(unit)
		var pos_2d = Vector2(unit_pos.x, unit_pos.z)

		if section_rect.has_point(pos_2d):
			result.append(unit)

	return result


## Gets all non-activated, non-shaken AI units.
func get_eligible_units() -> Array[GameUnit]:
	var result: Array[GameUnit] = []

	for unit in ai_units:
		if unit.is_destroyed():
			continue
		if unit.is_activated:
			continue
		# Shaken units activate last
		if _is_shaken(unit):
			continue
		result.append(unit)

	return result


## Gets all shaken AI units that haven't activated.
func get_shaken_units() -> Array[GameUnit]:
	var result: Array[GameUnit] = []

	for unit in ai_units:
		if unit.is_destroyed():
			continue
		if unit.is_activated:
			continue
		if _is_shaken(unit):
			result.append(unit)

	return result


## Checks if a unit is shaken (has Shaken marker).
func _is_shaken(unit: GameUnit) -> bool:
	for model in unit.models:
		if model.has_marker("Shaken"):
			return true
	return false


## Checks if a position is in cover terrain.
func is_in_cover(pos: Vector3) -> bool:
	for cover in cover_areas:
		if cover.has_point(pos):
			return true
	return false


## Checks if a position is in difficult terrain.
func is_in_difficult_terrain(pos: Vector3) -> bool:
	for terrain in difficult_terrain:
		if terrain.has_point(pos):
			return true
	return false


## Checks if a position is in dangerous terrain.
func is_in_dangerous_terrain(pos: Vector3) -> bool:
	for terrain in dangerous_terrain:
		if terrain.has_point(pos):
			return true
	return false


## Updates objective control status based on unit positions.
func update_objective_control() -> void:
	for obj in objectives:
		obj.ai_units_nearby = 0
		obj.player_units_nearby = 0

		# Count AI units near objective
		for unit in ai_units:
			if unit.is_destroyed():
				continue
			if _is_shaken(unit):
				continue

			var unit_pos = _get_unit_center(unit)
			if unit_pos.distance_to(obj.position) <= objective_radius:
				obj.ai_units_nearby += 1

		# Count player units near objective
		for unit in enemy_units:
			if unit.is_destroyed():
				continue

			var unit_pos = _get_unit_center(unit)
			if unit_pos.distance_to(obj.position) <= objective_radius:
				obj.player_units_nearby += 1

		# Determine control
		obj.is_ai_controlled = obj.ai_units_nearby > obj.player_units_nearby


## Calculates challenge bonus based on objective control.
func calculate_challenge_bonus() -> void:
	if not challenge_bonus_enabled:
		ai_hit_bonus = 0
		ai_defense_bonus = 0
		return

	var ai_objectives = 0
	var player_objectives = 0

	for obj in objectives:
		if obj.ai_units_nearby > obj.player_units_nearby:
			ai_objectives += 1
		elif obj.player_units_nearby > obj.ai_units_nearby:
			player_objectives += 1

	if ai_objectives >= player_objectives:
		ai_hit_bonus = 1
		ai_defense_bonus = 0
	else:
		ai_hit_bonus = 1
		ai_defense_bonus = 1


## Helper to get unit center position.
func _get_unit_center(game_unit: GameUnit) -> Vector3:
	var sum = Vector3.ZERO
	var count = 0
	for model in game_unit.models:
		if model.is_alive and model.node:
			sum += model.node.global_position
			count += 1
	if count > 0:
		return sum / count
	return Vector3.ZERO


## Initializes table sections based on table dimensions.
## Sections are numbered 1, 2, 3 from left to right along AI edge.
func setup_table_sections(table_width: float, table_depth: float) -> void:
	var section_width = table_width / 3.0

	table_sections.clear()

	for i in range(3):
		var rect = Rect2(
			i * section_width,        # X start
			0,                         # Z start (AI deployment side)
			section_width,             # Width
			table_depth                # Full table depth
		)
		table_sections.append(rect)
