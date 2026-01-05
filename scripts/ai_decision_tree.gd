class_name AIDecisionTree
extends RefCounted
## Implements decision trees for AI unit activation.
## Based on OPR Solo & Co-Op Rules v3.5.0.


## Possible AI actions
enum Action {
	CHARGE,           # Charge toward enemy
	RUSH_OBJECTIVE,   # Rush toward objective
	RUSH_ENEMY,       # Rush toward nearest enemy
	ADVANCE_SHOOT,    # Advance and shoot
	ADVANCE_OBJECTIVE,# Advance toward objective
	HOLD_SHOOT,       # Hold position and shoot
	IDLE              # Do nothing (e.g., shaken units)
}


## Action result with details
class ActionResult:
	var action: Action = Action.IDLE
	var target_position: Vector3 = Vector3.ZERO
	var shoot_target: GameUnit = null
	var charge_target: GameUnit = null
	var objective_index: int = -1


## Evaluates the decision tree for a unit and returns the recommended action.
## @param ai_unit: The AI unit to evaluate
## @param context: AIContext with game state information
static func evaluate(ai_unit: GameUnit, context: AIContext) -> ActionResult:
	if ai_unit == null:
		push_error("AIDecisionTree: evaluate called with null unit")
		return ActionResult.new()

	if context == null:
		push_error("AIDecisionTree: evaluate called with null context")
		return ActionResult.new()

	var unit_type = AIUnitClassifier.classify(ai_unit)

	match unit_type:
		AIUnitClassifier.UnitType.HYBRID:
			return _evaluate_hybrid(ai_unit, context)
		AIUnitClassifier.UnitType.SHOOTING:
			return _evaluate_shooting(ai_unit, context)
		AIUnitClassifier.UnitType.MELEE:
			return _evaluate_melee(ai_unit, context)

	push_warning("AIDecisionTree: Unknown unit type for %s" % ai_unit.get_name())
	return ActionResult.new()


## DECISION TREE - HYBRID
## 1. Valid objectives not under AI control? -> 2, else -> 5
## 2. Enemies in the way? -> Charge/Advance+Shoot/Rush, else -> 3
## 3. Objective in Rush range but not Advance? -> Rush, else -> 4
## 4. Advance will put enemies in range? -> Advance+Shoot, else -> Rush
## 5. Enemies in Charge range? -> Charge, else -> 6
## 6. Advance will put enemies in range? -> Advance+Shoot, else -> Rush enemy
static func _evaluate_hybrid(ai_unit: GameUnit, context: AIContext) -> ActionResult:
	var result = ActionResult.new()
	var unit_pos = _get_unit_center(ai_unit)

	# Step 1: Are there valid objectives not under AI control?
	var target_objective = context.get_nearest_uncontrolled_objective(unit_pos)

	if target_objective != null:
		var obj_pos = target_objective.position
		var obj_distance = unit_pos.distance_to(obj_pos)
		result.objective_index = target_objective.index

		# Step 2: Are there enemies in the way?
		var enemies_in_way = context.get_enemies_in_path(unit_pos, obj_pos)

		if not enemies_in_way.is_empty():
			# Charge if possible
			var charge_target = _find_chargeable_enemy(ai_unit, enemies_in_way, context)
			if charge_target != null:
				result.action = Action.CHARGE
				result.charge_target = charge_target
				result.target_position = _get_unit_center(charge_target)
				return result

			# Else Advance and shoot if possible
			if _can_shoot_after_advance(ai_unit, context):
				result.action = Action.ADVANCE_SHOOT
				result.target_position = obj_pos
				result.shoot_target = _find_best_shooting_target(ai_unit, context)
				return result

			# Else Rush toward objective
			result.action = Action.RUSH_OBJECTIVE
			result.target_position = obj_pos
			return result

		# Step 3: Objective in Rush range but not Advance?
		var rush_range = context.rush_distance
		var advance_range = context.advance_distance

		if obj_distance <= rush_range and obj_distance > advance_range:
			result.action = Action.RUSH_OBJECTIVE
			result.target_position = obj_pos
			return result

		# Step 4: Will enemies be in range after Advance?
		if _will_enemies_be_in_range_after_advance(ai_unit, obj_pos, context):
			result.action = Action.ADVANCE_SHOOT
			result.target_position = obj_pos
			result.shoot_target = _find_best_shooting_target(ai_unit, context)
			return result

		# Rush toward objective
		result.action = Action.RUSH_OBJECTIVE
		result.target_position = obj_pos
		return result

	# Step 5: No valid objectives - check for charge
	var charge_target = _find_nearest_charge_target(ai_unit, context)
	if charge_target != null:
		result.action = Action.CHARGE
		result.charge_target = charge_target
		result.target_position = _get_unit_center(charge_target)
		return result

	# Step 6: Advance and shoot if possible
	var nearest_enemy = context.get_nearest_enemy(unit_pos)
	if nearest_enemy != null:
		var enemy_pos = _get_unit_center(nearest_enemy)

		if _will_enemies_be_in_range_after_advance(ai_unit, enemy_pos, context):
			result.action = Action.ADVANCE_SHOOT
			result.target_position = enemy_pos
			result.shoot_target = _find_best_shooting_target(ai_unit, context)
			return result

		# Rush toward enemy
		result.action = Action.RUSH_ENEMY
		result.target_position = enemy_pos
		return result

	return result


## DECISION TREE - SHOOTING
## 1. Valid objectives not under AI control? -> 2, else -> 3
## 2. Advance will put enemies in range? -> Advance+Shoot, else -> Rush objective
## 3. Advance will put enemies in range? -> Advance+Shoot, else -> Rush enemy
static func _evaluate_shooting(ai_unit: GameUnit, context: AIContext) -> ActionResult:
	var result = ActionResult.new()
	var unit_pos = _get_unit_center(ai_unit)

	# Check for special rules that modify behavior
	if _should_hold_and_shoot(ai_unit, context):
		result.action = Action.HOLD_SHOOT
		result.shoot_target = _find_best_shooting_target(ai_unit, context)
		return result

	# Step 1: Valid objectives not under AI control?
	var target_objective = context.get_nearest_uncontrolled_objective(unit_pos)

	if target_objective != null:
		var obj_pos = target_objective.position
		result.objective_index = target_objective.index

		# Step 2: Will enemies be in range after Advance?
		if _will_enemies_be_in_range_after_advance(ai_unit, obj_pos, context):
			result.action = Action.ADVANCE_SHOOT
			result.target_position = obj_pos
			result.shoot_target = _find_best_shooting_target(ai_unit, context)
			return result

		# Rush toward objective
		result.action = Action.RUSH_OBJECTIVE
		result.target_position = obj_pos
		return result

	# Step 3: No objectives - move toward enemy
	var nearest_enemy = context.get_nearest_enemy(unit_pos)
	if nearest_enemy != null:
		var enemy_pos = _get_unit_center(nearest_enemy)

		if _will_enemies_be_in_range_after_advance(ai_unit, enemy_pos, context):
			result.action = Action.ADVANCE_SHOOT
			result.target_position = enemy_pos
			result.shoot_target = _find_best_shooting_target(ai_unit, context)
			return result

		result.action = Action.RUSH_ENEMY
		result.target_position = enemy_pos
		return result

	return result


## DECISION TREE - MELEE
## 1. Valid objectives not under AI control? -> 2, else -> 3
## 2. Enemies in the way? -> Charge/Rush objective, else -> Rush objective
## 3. Enemies in Charge range? -> Charge, else -> Rush enemy
static func _evaluate_melee(ai_unit: GameUnit, context: AIContext) -> ActionResult:
	var result = ActionResult.new()
	var unit_pos = _get_unit_center(ai_unit)

	# Step 1: Valid objectives not under AI control?
	var target_objective = context.get_nearest_uncontrolled_objective(unit_pos)

	if target_objective != null:
		var obj_pos = target_objective.position
		result.objective_index = target_objective.index

		# Step 2: Enemies in the way?
		var enemies_in_way = context.get_enemies_in_path(unit_pos, obj_pos)

		if not enemies_in_way.is_empty():
			# Charge if possible
			var charge_target = _find_chargeable_enemy(ai_unit, enemies_in_way, context)
			if charge_target != null:
				result.action = Action.CHARGE
				result.charge_target = charge_target
				result.target_position = _get_unit_center(charge_target)
				return result

			# Else Rush toward objective
			result.action = Action.RUSH_OBJECTIVE
			result.target_position = obj_pos
			return result

		# No enemies in way - Rush objective
		result.action = Action.RUSH_OBJECTIVE
		result.target_position = obj_pos
		return result

	# Step 3: No objectives - check for charge
	var charge_target = _find_nearest_charge_target(ai_unit, context)
	if charge_target != null:
		result.action = Action.CHARGE
		result.charge_target = charge_target
		result.target_position = _get_unit_center(charge_target)
		return result

	# Rush toward nearest enemy
	var nearest_enemy = context.get_nearest_enemy(unit_pos)
	if nearest_enemy != null:
		result.action = Action.RUSH_ENEMY
		result.target_position = _get_unit_center(nearest_enemy)
		return result

	return result


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


static func _find_chargeable_enemy(ai_unit: GameUnit, candidates: Array[GameUnit], context: AIContext) -> GameUnit:
	var unit_pos = _get_unit_center(ai_unit)
	var charge_range = context.charge_range

	var best_target: GameUnit = null
	var best_distance = INF

	for enemy in candidates:
		if enemy.is_destroyed():
			continue
		var enemy_pos = _get_unit_center(enemy)
		var distance = unit_pos.distance_to(enemy_pos)

		if distance <= charge_range and distance < best_distance:
			best_distance = distance
			best_target = enemy

	return best_target


static func _find_nearest_charge_target(ai_unit: GameUnit, context: AIContext) -> GameUnit:
	var unit_pos = _get_unit_center(ai_unit)
	var result = AITargetSelector.find_charge_target(
		ai_unit,
		context.enemy_units,
		context.charge_range
	)
	return result.target


static func _can_shoot_after_advance(ai_unit: GameUnit, context: AIContext) -> bool:
	var max_range = _get_max_weapon_range(ai_unit)
	return max_range > 0


static func _will_enemies_be_in_range_after_advance(
	ai_unit: GameUnit,
	move_toward: Vector3,
	context: AIContext
) -> bool:
	var unit_pos = _get_unit_center(ai_unit)
	var direction = (move_toward - unit_pos).normalized()
	var new_pos = unit_pos + direction * context.advance_distance

	var max_range = _get_max_weapon_range(ai_unit)

	for enemy in context.enemy_units:
		if enemy.is_destroyed():
			continue
		var enemy_pos = _get_unit_center(enemy)
		if new_pos.distance_to(enemy_pos) <= max_range:
			return true

	return false


static func _get_max_weapon_range(ai_unit: GameUnit) -> float:
	var max_range = 0.0
	for model in ai_unit.models:
		var weapons = model.get_weapons()
		for weapon in weapons:
			if weapon is Dictionary:
				var range_val = weapon.get("range", 0)
				if range_val > max_range:
					max_range = range_val
	return max_range


static func _find_best_shooting_target(ai_unit: GameUnit, context: AIContext) -> GameUnit:
	var max_range = _get_max_weapon_range(ai_unit)
	var result = AITargetSelector.find_shooting_target(
		ai_unit,
		context.enemy_units,
		max_range
	)
	return result.target


static func _should_hold_and_shoot(ai_unit: GameUnit, context: AIContext) -> bool:
	# Units with Artillery, Indirect, or Relentless in range should Hold+Shoot
	if ai_unit.has_special_rule("Artillery"):
		return true
	if ai_unit.has_special_rule("Indirect"):
		if _enemies_in_current_range(ai_unit, context):
			return true
	if ai_unit.has_special_rule("Relentless"):
		if _enemies_in_current_range(ai_unit, context):
			return true
	return false


static func _enemies_in_current_range(ai_unit: GameUnit, context: AIContext) -> bool:
	var unit_pos = _get_unit_center(ai_unit)
	var max_range = _get_max_weapon_range(ai_unit)

	for enemy in context.enemy_units:
		if enemy.is_destroyed():
			continue
		var enemy_pos = _get_unit_center(enemy)
		if unit_pos.distance_to(enemy_pos) <= max_range:
			return true
	return false


## Converts action to string for display.
static func action_to_string(action: Action) -> String:
	match action:
		Action.CHARGE:
			return "Charge"
		Action.RUSH_OBJECTIVE:
			return "Rush (Objective)"
		Action.RUSH_ENEMY:
			return "Rush (Enemy)"
		Action.ADVANCE_SHOOT:
			return "Advance + Shoot"
		Action.ADVANCE_OBJECTIVE:
			return "Advance (Objective)"
		Action.HOLD_SHOOT:
			return "Hold + Shoot"
		Action.IDLE:
			return "Idle"
	return "Unknown"
