class_name AITargetSelector
extends RefCounted
## Selects targets for AI units based on OPR Solo & Co-Op Rules.
## Handles priority rules for different weapon types and special rules.
## NOTE: All distances should be in METERS for consistency with positions.


## Conversion constant: 1 inch = 0.0254 meters
const INCHES_TO_METERS: float = 0.0254


## Target selection result
class TargetResult:
	var target: GameUnit = null
	var target_model: ModelInstance = null
	var distance: float = 0.0
	var is_in_cover: bool = false
	var priority_score: float = 0.0


## Finds the best shooting target for an AI unit.
## Prioritizes: nearest valid target, units not activated, targets in open.
static func find_shooting_target(
	ai_unit: GameUnit,
	enemy_units: Array[GameUnit],
	max_range: float = 24.0 * INCHES_TO_METERS
) -> TargetResult:
	var result = TargetResult.new()
	var ai_position = _get_unit_center(ai_unit)

	var best_target: GameUnit = null
	var best_score = -INF

	for enemy in enemy_units:
		if enemy.is_destroyed():
			continue

		var enemy_pos = _get_unit_center(enemy)
		var distance = ai_position.distance_to(enemy_pos)

		if distance > max_range:
			continue

		var score = _calculate_shooting_priority(ai_unit, enemy, distance)

		if score > best_score:
			best_score = score
			best_target = enemy
			result.distance = distance

	result.target = best_target
	result.priority_score = best_score
	return result


## Finds the best charge target for an AI unit.
## Prioritizes: nearest valid target, units not activated.
static func find_charge_target(
	ai_unit: GameUnit,
	enemy_units: Array[GameUnit],
	charge_range: float = 12.0 * INCHES_TO_METERS
) -> TargetResult:
	var result = TargetResult.new()
	var ai_position = _get_unit_center(ai_unit)

	var best_target: GameUnit = null
	var best_score = -INF

	for enemy in enemy_units:
		if enemy.is_destroyed():
			continue

		var enemy_pos = _get_unit_center(enemy)
		var distance = ai_position.distance_to(enemy_pos)

		if distance > charge_range:
			continue

		var score = _calculate_melee_priority(ai_unit, enemy, distance)

		if score > best_score:
			best_score = score
			best_target = enemy
			result.distance = distance

	result.target = best_target
	result.priority_score = best_score
	return result


## Calculates shooting priority score.
## Higher score = better target.
static func _calculate_shooting_priority(
	ai_unit: GameUnit,
	enemy: GameUnit,
	distance: float
) -> float:
	var score = 0.0

	# Base: closer is better (inverse distance, scaled)
	score += (100.0 - distance) / 10.0

	# Priority: units that haven't activated yet
	if not enemy.is_activated:
		score += 5.0

	# Priority: targets in the open (not in cover)
	# TODO: Implement cover detection when terrain system is integrated
	var in_cover = _is_in_cover(enemy)
	if not in_cover:
		score += 3.0

	# Special weapon priorities
	score += _get_weapon_priority_bonus(ai_unit, enemy)

	return score


## Calculates melee priority score.
static func _calculate_melee_priority(
	ai_unit: GameUnit,
	enemy: GameUnit,
	distance: float
) -> float:
	var score = 0.0

	# Base: closer is better
	score += (100.0 - distance) / 10.0

	# Priority: units that haven't activated yet
	if not enemy.is_activated:
		score += 5.0

	# Special weapon priorities
	score += _get_weapon_priority_bonus(ai_unit, enemy)

	return score


## Gets bonus priority based on AI unit's special weapon rules.
static func _get_weapon_priority_bonus(ai_unit: GameUnit, enemy: GameUnit) -> float:
	var bonus = 0.0

	# Check weapons for special targeting rules
	for model in ai_unit.models:
		var weapons = model.get_weapons()
		for weapon in weapons:
			bonus += _check_weapon_targeting_rules(weapon, enemy)

	return bonus


## Checks weapon targeting rules against a specific enemy.
static func _check_weapon_targeting_rules(weapon: Variant, enemy: GameUnit) -> float:
	var bonus = 0.0
	var special_rules = []

	if weapon is Dictionary:
		special_rules = weapon.get("specialRules", [])

	for rule in special_rules:
		var name = _get_rule_name(rule)
		var rating = _get_rule_rating(rule)

		match name:
			"AP":
				# AP weapons target high defense units
				var defense = enemy.get_defense()
				if defense >= 4:
					bonus += rating * 0.5

			"Deadly":
				# Deadly targets single-model Tough units first
				if enemy.get_size() == 1 and enemy.has_special_rule("Tough"):
					bonus += 10.0
				elif enemy.has_special_rule("Tough"):
					# Then any Tough unit, prioritizing lowest remaining Tough
					var remaining_tough = _get_remaining_tough(enemy)
					bonus += 5.0 + (10 - remaining_tough) * 0.5

			"Takedown":
				# Takedown targets heroes first, then models with upgrades
				if enemy.is_hero():
					bonus += 15.0
				# TODO: Check for expensive upgrades

			"Unstoppable":
				# Unstoppable targets Aircraft first
				if enemy.has_special_rule("Aircraft"):
					bonus += 20.0

	return bonus


## Gets remaining tough value for an enemy unit.
static func _get_remaining_tough(enemy: GameUnit) -> int:
	var total = 0
	for model in enemy.models:
		if model.is_alive:
			total += model.wounds_current
	return total


## Checks if a unit is in cover.
## TODO: Integrate with terrain system.
static func _is_in_cover(_enemy: GameUnit) -> bool:
	# Placeholder - needs terrain integration
	return false


## Gets the center position of a unit (average of all model positions).
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


## Extracts the rule name from a rule (string or dict).
static func _get_rule_name(rule: Variant) -> String:
	if rule is String:
		var paren = rule.find("(")
		if paren > 0:
			return rule.substr(0, paren)
		return rule
	elif rule is Dictionary:
		return rule.get("name", "")
	return ""


## Extracts the rating from a rule.
static func _get_rule_rating(rule: Variant) -> int:
	if rule is String:
		var paren_start = rule.find("(")
		var paren_end = rule.find(")")
		if paren_start > 0 and paren_end > paren_start:
			var rating_str = rule.substr(paren_start + 1, paren_end - paren_start - 1)
			return rating_str.to_int()
	elif rule is Dictionary:
		return rule.get("rating", 0)
	return 0
