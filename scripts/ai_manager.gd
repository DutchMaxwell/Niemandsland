class_name AIManager
extends Node
## Central manager for AI opponent behavior.
## Based on OPR Solo & Co-Op Rules v3.5.0 + Grimdark Future v3.5.1.
## Handles activation order, decision making, combat, and action execution.


## Emitted when AI starts its turn
signal ai_turn_started

## Emitted when a unit is about to activate (for UI updates)
signal unit_activating(unit: GameUnit, action: AIDecisionTree.ActionResult)

## Emitted when a unit completes its activation
signal unit_activated(unit: GameUnit)

## Emitted when AI turn ends
signal ai_turn_ended

## Emitted for UI logging
signal action_log(message: String)

## Combat signals
signal combat_started(attacker: GameUnit, defender: GameUnit, is_melee: bool)
signal combat_result(result: AICombat.CombatResult)
signal dice_rolled(description: String, dice: Array, successes: int)
signal morale_test(unit: GameUnit, outcome: AIMorale.MoraleOutcome)

## Mission signals
signal objective_seized(objective: AIMission.Objective, new_controller: int)
signal round_ended(state: AIMission.MissionState)
signal game_over(state: AIMission.MissionState)


# ===== Configuration =====

## Enable/disable AI
@export var ai_enabled: bool = true

## AI player ID (usually 2)
@export var ai_player_id: int = 2

## Enable challenge bonus
@export var challenge_bonus: bool = false

## Delay between activations (seconds) for visual feedback
@export var activation_delay: float = 1.0

## Movement speed for AI units (units per second)
@export var movement_speed: float = 6.0

## Delay before combat resolution (seconds)
@export var combat_delay: float = 0.5


# ===== References =====

var army_manager: Node = null  # OPRArmyManager reference
var context: AIContext = null
var mission_state: AIMission.MissionState = null
var terrain_pieces: Array[AITerrain.TerrainPiece] = []


# ===== State =====

var _is_ai_turn: bool = false
var _pending_activations: Array[GameUnit] = []
var _current_unit: GameUnit = null
var _combat_log: Array[String] = []


func _ready() -> void:
	context = AIContext.new()
	context.ai_player_id = ai_player_id
	context.challenge_bonus_enabled = challenge_bonus
	mission_state = AIMission.MissionState.new()


## Initializes the AI manager with references.
func initialize(p_army_manager: Node) -> void:
	army_manager = p_army_manager


## Sets up the mission (objectives, rounds).
func setup_mission(table_bounds: Rect2, deployment_depth: float = 12.0) -> void:
	mission_state.objectives = AIMission.setup_objectives(table_bounds, deployment_depth)
	mission_state.current_round = 1
	mission_state.max_rounds = 4

	# Sync objectives to context
	context.objectives.clear()
	for obj in mission_state.objectives:
		var ctx_obj = AIContext.ObjectiveData.new()
		ctx_obj.index = obj.id
		ctx_obj.position = obj.position
		context.objectives.append(ctx_obj)

	_log("Mission setup: %d objectives placed" % mission_state.objectives.size())


## Sets terrain pieces for AI terrain awareness.
func set_terrain(pieces: Array[AITerrain.TerrainPiece]) -> void:
	terrain_pieces = pieces

	# Sync to context
	context.cover_areas.clear()
	context.difficult_terrain.clear()
	context.dangerous_terrain.clear()

	for piece in pieces:
		if piece.is_cover():
			context.cover_areas.append(piece.bounds)
		if piece.is_difficult():
			context.difficult_terrain.append(piece.bounds)
		if piece.is_dangerous():
			context.dangerous_terrain.append(piece.bounds)


## Sets up AI units at game start.
## Call this after armies are deployed.
func setup_ai_army(units: Array[GameUnit]) -> void:
	context.ai_units.clear()
	for unit in units:
		context.ai_units.append(unit)
		# Classify unit and store type
		var unit_type = AIUnitClassifier.classify(unit)
		unit.unit_properties["ai_type"] = AIUnitClassifier.type_to_string(unit_type)

	_log("AI army setup complete: %d units" % units.size())


## Sets player units (enemies for AI).
func set_enemy_units(units: Array[GameUnit]) -> void:
	context.enemy_units.clear()
	for unit in units:
		context.enemy_units.append(unit)


## Sets objective positions.
func set_objectives(positions: Array[Vector3]) -> void:
	context.objectives.clear()
	for i in range(positions.size()):
		var obj = AIContext.ObjectiveData.new()
		obj.index = i
		obj.position = positions[i]
		context.objectives.append(obj)


## Sets table dimensions for section-based activation.
func set_table_dimensions(width: float, depth: float) -> void:
	context.setup_table_sections(width, depth)


## Starts the AI turn.
func start_ai_turn(round_number: int) -> void:
	if not ai_enabled:
		ai_turn_ended.emit()
		return

	_is_ai_turn = true
	context.current_round = round_number

	# Update game state
	context.update_objective_control()
	context.calculate_challenge_bonus()

	if context.challenge_bonus_enabled:
		_log("Challenge Bonus: +%d to hit, +%d to defense" % [
			context.ai_hit_bonus,
			context.ai_defense_bonus
		])

	ai_turn_started.emit()

	# Build activation queue
	_build_activation_queue()

	# Start processing activations
	_process_next_activation()


## Builds the activation queue based on section-based order.
func _build_activation_queue() -> void:
	_pending_activations.clear()

	# First: all non-shaken units in section order
	var eligible = context.get_eligible_units()

	# Sort by section (roll D3 for each activation in actual play)
	# For simplicity, we process section 1, then 2, then 3
	for section in range(1, 4):
		var units_in_section = context.get_ai_units_in_section(section)
		units_in_section.shuffle()  # Random order within section
		for unit in units_in_section:
			if unit in eligible:
				_pending_activations.append(unit)

	# Last: shaken units (they go Idle to remove Shaken)
	var shaken = context.get_shaken_units()
	for unit in shaken:
		_pending_activations.append(unit)


## Processes the next unit activation.
func _process_next_activation() -> void:
	if _pending_activations.is_empty():
		_end_ai_turn()
		return

	_current_unit = _pending_activations.pop_front()

	if _current_unit.is_destroyed():
		# Skip destroyed units
		_process_next_activation()
		return

	# Check if shaken - just go Idle
	if _is_unit_shaken(_current_unit):
		_log("%s is Shaken - going Idle" % _current_unit.get_name())
		_remove_shaken_marker(_current_unit)
		_complete_activation()
		return

	# Evaluate decision tree
	var action = AIDecisionTree.evaluate(_current_unit, context)

	_log("%s: %s" % [
		_current_unit.get_name(),
		AIDecisionTree.action_to_string(action.action)
	])

	unit_activating.emit(_current_unit, action)

	# Execute the action
	await _execute_action(_current_unit, action)

	_complete_activation()


## Executes an AI action for a unit.
func _execute_action(unit: GameUnit, action: AIDecisionTree.ActionResult) -> void:
	match action.action:
		AIDecisionTree.Action.CHARGE:
			await _execute_charge(unit, action)

		AIDecisionTree.Action.RUSH_OBJECTIVE, AIDecisionTree.Action.RUSH_ENEMY:
			await _execute_rush(unit, action)

		AIDecisionTree.Action.ADVANCE_SHOOT:
			await _execute_advance_shoot(unit, action)

		AIDecisionTree.Action.ADVANCE_OBJECTIVE:
			await _execute_advance(unit, action)

		AIDecisionTree.Action.HOLD_SHOOT:
			await _execute_hold_shoot(unit, action)

		AIDecisionTree.Action.IDLE:
			pass  # Do nothing


## Executes a charge action with full combat resolution.
func _execute_charge(unit: GameUnit, action: AIDecisionTree.ActionResult) -> void:
	if action.charge_target == null:
		return

	var target_pos = action.target_position

	# Move toward target (up to charge range)
	await _move_unit_toward(unit, target_pos, context.charge_range)

	_log("  -> Charging %s" % action.charge_target.get_name())

	unit.unit_properties["last_action"] = "charge"
	unit.unit_properties["moved_this_turn"] = true

	# Resolve melee combat
	var defender = action.charge_target
	var is_fatigued = unit.unit_properties.get("fought_this_round", false)

	combat_started.emit(unit, defender, true)

	if combat_delay > 0:
		await get_tree().create_timer(combat_delay).timeout

	var result = AICombat.resolve_melee(unit, defender, context, is_fatigued)

	# Log combat results
	_log("    Attacks: %d, Hits: %d, Blocked: %d, Wounds: %d" % [
		result.total_attacks, result.hits, result.blocked, result.wounds
	])

	if result.casualties.size() > 0:
		_log("    Casualties: %d models" % result.casualties.size())

	combat_result.emit(result)

	# Handle morale
	await _handle_melee_morale(result)

	# Consolidation move
	if defender.is_destroyed():
		await _consolidation_move(unit)
	else:
		# Move back 1" to separate
		await _separate_from_combat(unit, defender)


## Executes a rush action.
func _execute_rush(unit: GameUnit, action: AIDecisionTree.ActionResult) -> void:
	var target_pos = action.target_position
	target_pos = _apply_terrain_avoidance(unit, target_pos)

	# Rush = advance distance x2
	await _move_unit_toward(unit, target_pos, context.rush_distance)

	unit.unit_properties["last_action"] = "rush"


## Executes an advance + shoot action with full combat resolution.
func _execute_advance_shoot(unit: GameUnit, action: AIDecisionTree.ActionResult) -> void:
	var target_pos = action.target_position
	target_pos = _apply_terrain_avoidance(unit, target_pos)
	target_pos = _apply_shooting_positioning(unit, target_pos, action)

	# Advance
	await _move_unit_toward(unit, target_pos, context.advance_distance)

	unit.unit_properties["moved_this_turn"] = true

	# Shoot
	if action.shoot_target != null:
		await _resolve_shooting(unit, action.shoot_target)

	unit.unit_properties["last_action"] = "advance_shoot"


## Executes an advance action (no shooting).
func _execute_advance(unit: GameUnit, action: AIDecisionTree.ActionResult) -> void:
	var target_pos = action.target_position
	target_pos = _apply_terrain_avoidance(unit, target_pos)

	await _move_unit_toward(unit, target_pos, context.advance_distance)

	unit.unit_properties["last_action"] = "advance"


## Executes a hold + shoot action (for Artillery, Indirect, Relentless).
func _execute_hold_shoot(unit: GameUnit, action: AIDecisionTree.ActionResult) -> void:
	if action.shoot_target != null:
		await _resolve_shooting(unit, action.shoot_target)

	unit.unit_properties["last_action"] = "hold_shoot"


# ===== Combat Resolution =====

## Resolves a shooting attack.
func _resolve_shooting(attacker: GameUnit, defender: GameUnit) -> void:
	_log("  -> Shooting at %s" % defender.get_name())

	combat_started.emit(attacker, defender, false)

	if combat_delay > 0:
		await get_tree().create_timer(combat_delay).timeout

	var result = AICombat.resolve_shooting(attacker, defender, context)

	# Log results
	_log("    Attacks: %d, Hits: %d, Blocked: %d, Wounds: %d" % [
		result.total_attacks, result.hits, result.blocked, result.wounds
	])

	if result.casualties.size() > 0:
		_log("    Casualties: %d models" % result.casualties.size())

	combat_result.emit(result)

	# Check for morale test
	if AIMorale.needs_morale_test(defender, result.wounds):
		var outcome = AIMorale.take_morale_test(defender)
		AIMorale.apply_morale_outcome(defender, outcome)

		morale_test.emit(defender, outcome)

		match outcome.result:
			AIMorale.MoraleResult.SHAKEN:
				_log("    %s is Shaken!" % defender.get_name())
			AIMorale.MoraleResult.ROUTED:
				_log("    %s has Routed!" % defender.get_name())


## Handles morale after melee combat.
func _handle_melee_morale(result: AICombat.CombatResult) -> void:
	if result.winner == null:
		_log("    Melee is a tie - no morale test")
		return

	var loser = result.defender if result.winner == result.attacker else result.attacker

	if loser.is_destroyed():
		_log("    %s destroyed - no morale test needed" % loser.get_name())
		return

	var outcome = AIMorale.handle_melee_morale(result.winner, loser)

	morale_test.emit(loser, outcome)

	match outcome.result:
		AIMorale.MoraleResult.PASSED:
			_log("    %s passed morale test" % loser.get_name())
		AIMorale.MoraleResult.SHAKEN:
			_log("    %s is Shaken!" % loser.get_name())
		AIMorale.MoraleResult.ROUTED:
			_log("    %s has Routed!" % loser.get_name())


## 3" consolidation move after destroying enemy in melee.
func _consolidation_move(unit: GameUnit) -> void:
	# Find nearest objective or enemy
	var unit_pos = _get_unit_center(unit)
	var nearest_obj = context.get_nearest_uncontrolled_objective(unit_pos)
	var target = nearest_obj.position if nearest_obj else unit_pos

	await _move_unit_toward(unit, target, 3.0)


## Move back 1" to separate from combat.
func _separate_from_combat(attacker: GameUnit, defender: GameUnit) -> void:
	var attacker_pos = _get_unit_center(attacker)
	var defender_pos = _get_unit_center(defender)
	var direction = (attacker_pos - defender_pos).normalized()

	await _move_unit_toward(attacker, attacker_pos + direction * 1.0, 1.0)


## Moves a unit toward a target position.
func _move_unit_toward(unit: GameUnit, target: Vector3, max_distance: float) -> void:
	var current_pos = _get_unit_center(unit)
	var direction = (target - current_pos).normalized()
	var distance = min(current_pos.distance_to(target), max_distance)
	var new_pos = current_pos + direction * distance

	# Apply movement to all models in formation
	for model in unit.models:
		if model.is_alive and model.node:
			var offset = model.node.global_position - current_pos
			var target_model_pos = new_pos + offset

			# Animate movement (simple lerp)
			var tween = create_tween()
			tween.tween_property(
				model.node,
				"global_position",
				target_model_pos,
				distance / movement_speed
			)
			await tween.finished


## Applies terrain avoidance to target position.
## AI units avoid difficult/dangerous terrain unless necessary.
func _apply_terrain_avoidance(unit: GameUnit, target: Vector3) -> Vector3:
	# Check for special rules that ignore terrain
	if unit.has_special_rule("Flying"):
		return target
	if unit.has_special_rule("Strider"):
		# Strider ignores difficult terrain
		if not context.is_in_dangerous_terrain(target):
			return target

	# TODO: Pathfinding around terrain
	# For now, return target as-is
	return target


## Applies positioning rules for shooting units.
## "Shooting and Hybrid AI units must try to stay as far from enemy attack range as possible"
func _apply_shooting_positioning(
	unit: GameUnit,
	target: Vector3,
	action: AIDecisionTree.ActionResult
) -> Vector3:
	var unit_type = AIUnitClassifier.classify(unit)

	if unit_type == AIUnitClassifier.UnitType.MELEE:
		return target

	# If not moving to objective, try to stay at max weapon range
	if action.objective_index < 0 and action.shoot_target != null:
		var max_range = _get_max_weapon_range(unit)
		var enemy_pos = _get_unit_center(action.shoot_target)
		var unit_pos = _get_unit_center(unit)

		# Move to just within max range
		var direction = (enemy_pos - unit_pos).normalized()
		var ideal_distance = max_range - 1.0  # Stay 1" inside max range
		var current_distance = unit_pos.distance_to(enemy_pos)

		if current_distance < ideal_distance:
			# Too close - move away slightly
			var new_pos = enemy_pos - direction * ideal_distance
			return new_pos

	return target


## Completes the current unit's activation.
func _complete_activation() -> void:
	if _current_unit:
		_current_unit.activate(context.current_round)
		unit_activated.emit(_current_unit)

	_current_unit = null

	# Delay before next activation
	if activation_delay > 0:
		await get_tree().create_timer(activation_delay).timeout

	_process_next_activation()


## Ends the AI turn.
func _end_ai_turn() -> void:
	_is_ai_turn = false
	_log("AI turn complete")
	ai_turn_ended.emit()


# ===== Helper Methods =====

func _is_unit_shaken(unit: GameUnit) -> bool:
	for model in unit.models:
		if model.has_marker("Shaken"):
			return true
	return false


func _remove_shaken_marker(unit: GameUnit) -> void:
	for model in unit.models:
		model.remove_marker("Shaken")


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


func _get_max_weapon_range(unit: GameUnit) -> float:
	var max_range = 0.0
	for model in unit.models:
		var weapons = model.get_weapons()
		for weapon in weapons:
			if weapon is Dictionary:
				var range_val = weapon.get("range", 0)
				if range_val > max_range:
					max_range = range_val
	return max_range


func _log(message: String) -> void:
	action_log.emit("[AI] " + message)
	print("[AI] " + message)


# ===== AI Deployment =====

## Deploys AI units following Solo & Co-Op rules.
## Units divided into 3 groups, deployed in sections toward objectives.
func deploy_ai_units(units: Array[GameUnit], deployment_zone: Rect2) -> void:
	if units.is_empty():
		return

	# Divide units into 3 groups
	var groups: Array[Array] = [[], [], []]
	var shuffled = units.duplicate()
	shuffled.shuffle()

	for i in range(shuffled.size()):
		groups[i % 3].append(shuffled[i])

	# Roll for sections (ensuring not all in same section)
	var section_assignments = _roll_section_assignments()

	# Deploy each group
	for i in range(3):
		var section = section_assignments[i]
		var section_rect = _get_deployment_section(deployment_zone, section)

		for unit in groups[i]:
			_deploy_unit_in_section(unit, section_rect)

	_log("AI deployment complete")


func _roll_section_assignments() -> Array[int]:
	var assignments: Array[int] = []
	var all_same = true

	while all_same:
		assignments.clear()
		for i in range(3):
			assignments.append(randi() % 3 + 1)

		# Check if all same
		all_same = (assignments[0] == assignments[1] and assignments[1] == assignments[2])

	return assignments


func _get_deployment_section(zone: Rect2, section: int) -> Rect2:
	var section_width = zone.size.x / 3.0
	return Rect2(
		zone.position.x + (section - 1) * section_width,
		zone.position.y,
		section_width,
		zone.size.y
	)


func _deploy_unit_in_section(unit: GameUnit, section: Rect2) -> void:
	# Find nearest objective
	var section_center = Vector3(
		section.position.x + section.size.x / 2,
		0,
		section.position.y + section.size.y / 2
	)

	var nearest_obj = context.get_nearest_uncontrolled_objective(section_center)
	var target_pos = nearest_obj.position if nearest_obj else section_center

	# Clamp to section bounds
	target_pos.x = clamp(target_pos.x, section.position.x, section.position.x + section.size.x)
	target_pos.z = clamp(target_pos.z, section.position.y, section.position.y + section.size.y)

	# TODO: Avoid difficult/dangerous terrain unless unit has Strider/Flying
	# TODO: Actually move the unit models to target_pos
	# This depends on how models are spawned in the game

	_log("Deploying %s at (%0.1f, %0.1f)" % [unit.get_name(), target_pos.x, target_pos.z])


# ===== Special Rule Handlers =====

## Handles units with Ambush - deploy at start of round 2.
func handle_ambush_units(round_number: int) -> void:
	if round_number != 2:
		return

	var ambush_units: Array[GameUnit] = []
	for unit in context.ai_units:
		if unit.has_special_rule("Ambush"):
			if unit.unit_properties.get("in_reserve", false):
				ambush_units.append(unit)

	if ambush_units.is_empty():
		return

	_log("Deploying %d Ambush units" % ambush_units.size())

	# Get deployment zone
	# TODO: Get actual AI deployment zone
	var deployment_zone = Rect2(0, 0, 48, 12)  # Placeholder
	deploy_ai_units(ambush_units, deployment_zone)

	for unit in ambush_units:
		unit.unit_properties["in_reserve"] = false


## Handles units with Scout - deploy after all other units.
func get_scout_units() -> Array[GameUnit]:
	var scouts: Array[GameUnit] = []
	for unit in context.ai_units:
		if unit.has_special_rule("Scout"):
			scouts.append(unit)
	return scouts


## Handles units with Counter - activate after other units in section.
func should_delay_activation(unit: GameUnit) -> bool:
	return unit.has_special_rule("Counter")


## Handles Transport units - activate before cargo on round 1.
func handle_transports(round_number: int) -> void:
	if round_number != 1:
		return

	# Transports activate first
	var transports: Array[GameUnit] = []
	for unit in context.ai_units:
		if unit.has_special_rule("Transport"):
			transports.append(unit)

	# Move transports to front of activation queue
	for transport in transports:
		var idx = _pending_activations.find(transport)
		if idx > 0:
			_pending_activations.erase(transport)
			_pending_activations.push_front(transport)


# ===== Round & Mission Management =====

## Ends the current round and updates objectives.
func end_round() -> void:
	# Reset unit states for new round
	for unit in context.ai_units:
		unit.reset_activation()
		unit.unit_properties["fought_this_round"] = false
		unit.unit_properties["moved_this_turn"] = false

	for unit in context.enemy_units:
		unit.reset_activation()
		unit.unit_properties["fought_this_round"] = false
		unit.unit_properties["moved_this_turn"] = false

	# Update mission state
	mission_state = AIMission.end_round(
		mission_state,
		context.enemy_units,
		context.ai_units
	)

	# Log objective status
	var scores = AIMission.calculate_scores(mission_state.objectives)
	_log("Round %d ended - Player: %d objectives, AI: %d objectives" % [
		mission_state.current_round - 1,
		scores.player,
		scores.ai
	])

	round_ended.emit(mission_state)

	# Check for game over
	if mission_state.is_game_over:
		_handle_game_over()


## Handles game over.
func _handle_game_over() -> void:
	var winner_text = "Tie!"
	if mission_state.winner == 1:
		winner_text = "Player wins!"
	elif mission_state.winner == 2:
		winner_text = "AI wins!"

	_log("GAME OVER - %s (Player: %d, AI: %d)" % [
		winner_text,
		mission_state.player_score,
		mission_state.ai_score
	])

	game_over.emit(mission_state)


## Gets current mission status.
func get_mission_status() -> Dictionary:
	var scores = AIMission.calculate_scores(mission_state.objectives)
	return {
		"current_round": mission_state.current_round,
		"max_rounds": mission_state.max_rounds,
		"player_objectives": scores.player,
		"ai_objectives": scores.ai,
		"total_objectives": mission_state.objectives.size(),
		"is_game_over": mission_state.is_game_over,
		"winner": mission_state.winner
	}


## Gets objective markers for visualization.
func get_objective_markers() -> Array[AIMission.Objective]:
	return mission_state.objectives


# ===== Terrain Integration =====

## Checks if target position requires terrain test.
func _check_dangerous_terrain(unit: GameUnit, target_pos: Vector3) -> void:
	var current_pos = _get_unit_center(unit)

	if AITerrain.path_crosses_dangerous(current_pos, target_pos, terrain_pieces):
		if not unit.has_special_rule("Flying"):
			var wounds = AITerrain.take_dangerous_terrain_test(unit)
			if wounds > 0:
				_log("    Dangerous terrain: %d wounds!" % wounds)

				# Check morale if needed
				if AIMorale.needs_morale_test(unit, wounds):
					var outcome = AIMorale.take_morale_test(unit)
					AIMorale.apply_morale_outcome(unit, outcome)


## Gets adjusted movement distance considering terrain.
func _get_terrain_adjusted_movement(unit: GameUnit, base_move: float, target: Vector3) -> float:
	var current_pos = _get_unit_center(unit)
	var crosses_difficult = AITerrain.path_crosses_difficult(current_pos, target, terrain_pieces)

	return AITerrain.get_movement_limit(unit, crosses_difficult, base_move)


# ===== AI Strategic Decisions =====

## Gets strategic stance for this round.
func get_strategic_stance() -> String:
	return AIMission.get_strategic_stance(mission_state)


## Assigns units to defender/attacker roles.
func assign_unit_roles() -> Dictionary:
	var stance = get_strategic_stance()
	return AIMission.assign_unit_roles(context.ai_units, mission_state.objectives, stance)


# ===== Full Game Loop Helper =====

## Runs a complete AI turn (for testing/automation).
func run_full_ai_turn() -> void:
	if mission_state.is_game_over:
		_log("Game is already over!")
		return

	_log("=== AI Turn - Round %d ===" % mission_state.current_round)

	# Handle start of round special rules
	handle_ambush_units(mission_state.current_round)
	handle_transports(mission_state.current_round)

	# Start AI turn
	start_ai_turn(mission_state.current_round)

	# Wait for turn to complete
	await ai_turn_ended


## Records starting unit sizes for morale calculations.
func record_starting_sizes() -> void:
	for unit in context.ai_units:
		unit.unit_properties["starting_size"] = unit.get_alive_count()
		# Record starting tough for single models
		if unit.get_alive_count() == 1:
			var total_tough = 0
			for model in unit.models:
				total_tough += model.wounds_max
			unit.unit_properties["starting_tough"] = total_tough

	for unit in context.enemy_units:
		unit.unit_properties["starting_size"] = unit.get_alive_count()
		if unit.get_alive_count() == 1:
			var total_tough = 0
			for model in unit.models:
				total_tough += model.wounds_max
			unit.unit_properties["starting_tough"] = total_tough
