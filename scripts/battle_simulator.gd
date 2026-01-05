class_name BattleSimulator
extends Node
## AI vs AI Battle Simulator with Step-by-Step Control.
## Allows two army lists to fight using AI rules with manual step advancement.
## Each action (deploy, move, shoot, etc.) requires user confirmation.

# ===== Signals =====

## Emitted when a new step is ready for user confirmation
signal step_ready(step: BattleStep)

## Emitted when a step has been executed
signal step_executed(step: BattleStep)

## Emitted when the battle state changes
signal state_changed(state: BattleState)

## Emitted for UI logging
signal battle_log(message: String, type: String)

## Emitted when battle starts
signal battle_started(army1_name: String, army2_name: String)

## Emitted when battle ends
signal battle_ended(winner: int, final_state: BattleState)

## Emitted when a unit is highlighted (for visual feedback)
signal unit_highlighted(unit: GameUnit, highlight_type: String)

## Emitted when highlight should be cleared
signal highlight_cleared()


# ===== Enums =====

enum Phase {
	SETUP,           ## Initial setup phase
	DEPLOYMENT,      ## Deploying units
	ROUND_START,     ## Start of a round
	PLAYER_TURN,     ## Player 1 or 2's turn
	ACTIVATION,      ## Unit activation
	MOVEMENT,        ## Movement step
	SHOOTING,        ## Shooting step
	MELEE,           ## Melee combat step
	MORALE,          ## Morale test step
	ROUND_END,       ## End of round
	GAME_OVER        ## Battle complete
}


# ===== Battle State =====

class BattleState extends RefCounted:
	var phase: Phase = Phase.SETUP
	var current_round: int = 0
	var max_rounds: int = 4
	var current_player: int = 0  ## 1 or 2
	var current_unit: GameUnit = null
	var pending_units: Array[GameUnit] = []
	var completed_units: Array[GameUnit] = []

	## Score tracking
	var player1_objectives: int = 0
	var player2_objectives: int = 0
	var player1_kills: int = 0
	var player2_kills: int = 0

	## Winner: 0 = ongoing, 1 = player 1, 2 = player 2, -1 = tie
	var winner: int = 0

	func duplicate_state() -> BattleState:
		var copy = BattleState.new()
		copy.phase = phase
		copy.current_round = current_round
		copy.max_rounds = max_rounds
		copy.current_player = current_player
		copy.current_unit = current_unit
		copy.pending_units = pending_units.duplicate()
		copy.completed_units = completed_units.duplicate()
		copy.player1_objectives = player1_objectives
		copy.player2_objectives = player2_objectives
		copy.player1_kills = player1_kills
		copy.player2_kills = player2_kills
		copy.winner = winner
		return copy


# ===== Battle Step =====

class BattleStep extends RefCounted:
	var id: int = 0
	var type: String = ""  ## "deploy", "move", "shoot", "melee", "morale", etc.
	var description: String = ""
	var details: String = ""
	var unit: GameUnit = null
	var target_unit: GameUnit = null
	var target_position: Vector3 = Vector3.ZERO
	var action_data: Dictionary = {}  ## Additional data for execution

	## Visual data
	var highlight_units: Array[GameUnit] = []
	var show_path: bool = false
	var path_start: Vector3 = Vector3.ZERO
	var path_end: Vector3 = Vector3.ZERO

	## Results (filled after execution)
	var executed: bool = false
	var result_text: String = ""
	var dice_results: Array[int] = []
	var casualties: int = 0


# ===== Configuration =====

@export var auto_advance: bool = false
@export var auto_advance_delay: float = 1.5


# ===== References =====

var army_manager: OPRArmyManager = null
var ai_manager: AIManager = null
var mission: AIMission.MissionState = null


# ===== State =====

var state: BattleState = null
var current_step: BattleStep = null
var step_queue: Array[BattleStep] = []
var step_counter: int = 0

var player1_units: Array[GameUnit] = []
var player2_units: Array[GameUnit] = []
var player1_army_name: String = "Army 1"
var player2_army_name: String = "Army 2"

var _is_running: bool = false
var _waiting_for_input: bool = false


func _ready() -> void:
	state = BattleState.new()


# ===== Setup =====

## Initializes the simulator with references.
func initialize(p_army_manager: OPRArmyManager) -> void:
	army_manager = p_army_manager

	# Create AI manager instance
	ai_manager = AIManager.new()
	add_child(ai_manager)
	ai_manager.ai_enabled = true

	# Connect AI signals for logging
	ai_manager.action_log.connect(_on_ai_log)
	ai_manager.combat_result.connect(_on_combat_result)
	ai_manager.morale_test.connect(_on_morale_test)


## Loads armies for both players from file paths.
func load_armies(army1_path: String, army2_path: String) -> bool:
	_log("Loading armies...", "info")

	# Clear existing
	army_manager.clear_all()
	player1_units.clear()
	player2_units.clear()

	# Load army 1
	await army_manager.import_army_for_player(army1_path, 1)
	var army1 = army_manager.get_army(1)
	if not army1:
		_log("Failed to load Army 1", "error")
		return false
	player1_army_name = army1.name

	# Load army 2
	await army_manager.import_army_for_player(army2_path, 2)
	var army2 = army_manager.get_army(2)
	if not army2:
		_log("Failed to load Army 2", "error")
		return false
	player2_army_name = army2.name

	_log("Loaded: %s vs %s" % [player1_army_name, player2_army_name], "info")
	return true


## Sets up armies that are already loaded in the army manager.
func setup_loaded_armies() -> void:
	player1_units = army_manager.get_game_units_for_player(1)
	player2_units = army_manager.get_game_units_for_player(2)

	var army1 = army_manager.get_army(1)
	var army2 = army_manager.get_army(2)

	if army1:
		player1_army_name = army1.name
	if army2:
		player2_army_name = army2.name

	_log("Setup: %d units vs %d units" % [player1_units.size(), player2_units.size()], "info")


## Sets up the mission with objectives.
func setup_mission(table_bounds: Rect2) -> void:
	ai_manager.setup_mission(table_bounds)
	mission = ai_manager.mission_state

	_log("Mission: %d objectives, %d rounds" % [
		mission.objectives.size(),
		mission.max_rounds
	], "info")


# ===== Battle Control =====

## Starts the battle simulation.
func start_battle() -> void:
	if player1_units.is_empty() or player2_units.is_empty():
		_log("Cannot start: armies not loaded", "error")
		return

	_is_running = true
	state = BattleState.new()
	state.phase = Phase.SETUP
	state.max_rounds = 4
	step_queue.clear()
	step_counter = 0

	# Setup AI contexts
	ai_manager.context.ai_units.clear()
	ai_manager.context.enemy_units.clear()

	# Record starting sizes for morale
	ai_manager.record_starting_sizes()

	battle_started.emit(player1_army_name, player2_army_name)
	_log("=== BATTLE START: %s vs %s ===" % [player1_army_name, player2_army_name], "header")

	# Generate deployment steps
	_generate_deployment_steps()

	# Start processing
	_process_next_step()


## Advances to the next step (called by UI on click).
func advance_step() -> void:
	if not _waiting_for_input:
		return

	_waiting_for_input = false

	if current_step and not current_step.executed:
		_execute_current_step()
	else:
		_process_next_step()


## Skips to a specific phase.
func skip_to_phase(phase: Phase) -> void:
	# Clear pending steps until we reach the target phase
	while not step_queue.is_empty():
		var next_step = step_queue[0]
		# Check if this step is from the target phase
		if _step_matches_phase(next_step, phase):
			break
		step_queue.pop_front()

	_process_next_step()


## Toggles auto-advance mode.
func toggle_auto_advance() -> void:
	auto_advance = not auto_advance
	if auto_advance and _waiting_for_input:
		advance_step()


## Stops the battle.
func stop_battle() -> void:
	_is_running = false
	_waiting_for_input = false
	step_queue.clear()
	_log("Battle stopped", "info")


# ===== Step Generation =====

## Generates deployment steps for both armies.
func _generate_deployment_steps() -> void:
	state.phase = Phase.DEPLOYMENT
	state_changed.emit(state)

	_log("--- DEPLOYMENT PHASE ---", "phase")

	# Player 1 deployment
	for unit in player1_units:
		var step = _create_step("deploy", unit)
		step.description = "Deploy %s" % unit.get_name()
		step.details = "Player 1 deploys unit to their deployment zone"
		step.action_data["player"] = 1
		step_queue.append(step)

	# Player 2 deployment
	for unit in player2_units:
		var step = _create_step("deploy", unit)
		step.description = "Deploy %s" % unit.get_name()
		step.details = "Player 2 deploys unit to their deployment zone"
		step.action_data["player"] = 2
		step_queue.append(step)

	# Add round start step
	var round_step = _create_step("round_start", null)
	round_step.description = "Start Round 1"
	round_step.details = "Begin the first round of battle"
	round_step.action_data["round"] = 1
	step_queue.append(round_step)


## Generates steps for a round.
func _generate_round_steps(round_num: int) -> void:
	state.current_round = round_num
	state.phase = Phase.ROUND_START
	state_changed.emit(state)

	_log("--- ROUND %d ---" % round_num, "phase")

	# Determine activation order
	var all_units: Array[GameUnit] = []
	all_units.append_array(player1_units)
	all_units.append_array(player2_units)

	# Shuffle for random order (alternating would be more accurate to rules)
	all_units.shuffle()

	# Sort by player to alternate: P1, P2, P1, P2...
	var p1_queue: Array[GameUnit] = []
	var p2_queue: Array[GameUnit] = []

	for unit in player1_units:
		if not unit.is_destroyed() and not unit.is_activated:
			p1_queue.append(unit)

	for unit in player2_units:
		if not unit.is_destroyed() and not unit.is_activated:
			p2_queue.append(unit)

	p1_queue.shuffle()
	p2_queue.shuffle()

	# Interleave activations
	var activation_order: Array[GameUnit] = []
	var p1_idx = 0
	var p2_idx = 0
	var current_player = 1 if randf() < 0.5 else 2  # Random first player

	while p1_idx < p1_queue.size() or p2_idx < p2_queue.size():
		if current_player == 1 and p1_idx < p1_queue.size():
			activation_order.append(p1_queue[p1_idx])
			p1_idx += 1
		elif current_player == 2 and p2_idx < p2_queue.size():
			activation_order.append(p2_queue[p2_idx])
			p2_idx += 1
		elif p1_idx < p1_queue.size():
			activation_order.append(p1_queue[p1_idx])
			p1_idx += 1
		elif p2_idx < p2_queue.size():
			activation_order.append(p2_queue[p2_idx])
			p2_idx += 1

		current_player = 3 - current_player  # Toggle 1<->2

	# Generate activation steps for each unit
	for unit in activation_order:
		_generate_unit_activation_steps(unit)

	# Add round end step
	var end_step = _create_step("round_end", null)
	end_step.description = "End Round %d" % round_num
	end_step.details = "Check objectives and prepare for next round"
	end_step.action_data["round"] = round_num
	step_queue.append(end_step)


## Generates activation steps for a single unit.
func _generate_unit_activation_steps(unit: GameUnit) -> void:
	var player_id = unit.unit_properties.get("player_id", 1)
	var is_player1 = player_id == 1

	# Setup AI context
	if is_player1:
		ai_manager.context.ai_units = [unit]
		ai_manager.context.enemy_units.assign(player2_units)
	else:
		ai_manager.context.ai_units = [unit]
		ai_manager.context.enemy_units.assign(player1_units)

	# Get AI decision
	var action = AIDecisionTree.evaluate(unit, ai_manager.context)

	# Activation start step
	var start_step = _create_step("activation_start", unit)
	start_step.description = "%s activates" % unit.get_name()
	start_step.details = "Player %d unit begins activation" % player_id
	start_step.action_data["player"] = player_id
	start_step.action_data["action_type"] = AIDecisionTree.action_to_string(action.action)
	step_queue.append(start_step)

	# Movement step (if any movement)
	match action.action:
		AIDecisionTree.Action.CHARGE:
			var move_step = _create_step("charge", unit)
			move_step.description = "%s charges!" % unit.get_name()
			move_step.target_unit = action.charge_target
			move_step.target_position = action.target_position
			move_step.details = "Charging %s (12\" move + melee)" % (
				action.charge_target.get_name() if action.charge_target else "enemy"
			)
			move_step.show_path = true
			move_step.path_start = _get_unit_center(unit)
			move_step.path_end = action.target_position
			move_step.action_data["action"] = action
			step_queue.append(move_step)

			# Melee step
			if action.charge_target:
				var melee_step = _create_step("melee", unit)
				melee_step.description = "Melee Combat"
				melee_step.target_unit = action.charge_target
				melee_step.details = "%s vs %s" % [unit.get_name(), action.charge_target.get_name()]
				melee_step.highlight_units = [unit, action.charge_target]
				melee_step.action_data["action"] = action
				step_queue.append(melee_step)

		AIDecisionTree.Action.RUSH_OBJECTIVE, AIDecisionTree.Action.RUSH_ENEMY:
			var move_step = _create_step("rush", unit)
			move_step.description = "%s rushes!" % unit.get_name()
			move_step.target_position = action.target_position
			move_step.details = "Rush move (12\", no shooting)"
			move_step.show_path = true
			move_step.path_start = _get_unit_center(unit)
			move_step.path_end = action.target_position
			move_step.action_data["action"] = action
			step_queue.append(move_step)

		AIDecisionTree.Action.ADVANCE_SHOOT:
			var move_step = _create_step("advance", unit)
			move_step.description = "%s advances" % unit.get_name()
			move_step.target_position = action.target_position
			move_step.details = "Advance move (6\", can shoot)"
			move_step.show_path = true
			move_step.path_start = _get_unit_center(unit)
			move_step.path_end = action.target_position
			move_step.action_data["action"] = action
			step_queue.append(move_step)

			# Shooting step
			if action.shoot_target:
				var shoot_step = _create_step("shoot", unit)
				shoot_step.description = "%s shoots" % unit.get_name()
				shoot_step.target_unit = action.shoot_target
				shoot_step.details = "Shooting at %s" % action.shoot_target.get_name()
				shoot_step.highlight_units = [unit, action.shoot_target]
				shoot_step.action_data["action"] = action
				step_queue.append(shoot_step)

		AIDecisionTree.Action.ADVANCE_OBJECTIVE:
			var move_step = _create_step("advance", unit)
			move_step.description = "%s advances" % unit.get_name()
			move_step.target_position = action.target_position
			move_step.details = "Advance toward objective"
			move_step.show_path = true
			move_step.path_start = _get_unit_center(unit)
			move_step.path_end = action.target_position
			move_step.action_data["action"] = action
			step_queue.append(move_step)

		AIDecisionTree.Action.HOLD_SHOOT:
			var hold_step = _create_step("hold", unit)
			hold_step.description = "%s holds position" % unit.get_name()
			hold_step.details = "No movement, shooting only"
			hold_step.action_data["action"] = action
			step_queue.append(hold_step)

			if action.shoot_target:
				var shoot_step = _create_step("shoot", unit)
				shoot_step.description = "%s shoots" % unit.get_name()
				shoot_step.target_unit = action.shoot_target
				shoot_step.details = "Shooting at %s" % action.shoot_target.get_name()
				shoot_step.highlight_units = [unit, action.shoot_target]
				shoot_step.action_data["action"] = action
				step_queue.append(shoot_step)

		AIDecisionTree.Action.IDLE:
			var idle_step = _create_step("idle", unit)
			idle_step.description = "%s goes idle" % unit.get_name()
			idle_step.details = "No action this turn"
			idle_step.action_data["action"] = action
			step_queue.append(idle_step)

	# Activation end step
	var end_step = _create_step("activation_end", unit)
	end_step.description = "%s activation complete" % unit.get_name()
	end_step.details = "Unit has finished its turn"
	end_step.action_data["player"] = player_id
	step_queue.append(end_step)


# ===== Step Execution =====

## Processes the next step in the queue.
func _process_next_step() -> void:
	if not _is_running:
		return

	highlight_cleared.emit()

	if step_queue.is_empty():
		_check_battle_end()
		return

	current_step = step_queue.pop_front()
	state.current_unit = current_step.unit

	# Emit step ready signal
	step_ready.emit(current_step)

	# Highlight relevant units
	if current_step.unit:
		unit_highlighted.emit(current_step.unit, "active")
	if current_step.target_unit:
		unit_highlighted.emit(current_step.target_unit, "target")

	_waiting_for_input = true

	# Auto-advance if enabled
	if auto_advance:
		await get_tree().create_timer(auto_advance_delay).timeout
		if _waiting_for_input:
			advance_step()


## Executes the current step.
func _execute_current_step() -> void:
	if current_step == null:
		return

	match current_step.type:
		"deploy":
			_execute_deploy(current_step)
		"round_start":
			_execute_round_start(current_step)
		"round_end":
			_execute_round_end(current_step)
		"activation_start":
			_execute_activation_start(current_step)
		"activation_end":
			_execute_activation_end(current_step)
		"charge", "rush", "advance":
			await _execute_movement(current_step)
		"hold", "idle":
			_execute_hold(current_step)
		"shoot":
			_execute_shooting(current_step)
		"melee":
			_execute_melee(current_step)
		"morale":
			_execute_morale(current_step)

	current_step.executed = true
	step_executed.emit(current_step)

	# Continue to next step
	_process_next_step()


## Executes a deployment step.
func _execute_deploy(step: BattleStep) -> void:
	var unit = step.unit
	var player_id = step.action_data.get("player", 1)

	# Calculate deployment position
	var deploy_pos = _get_deployment_position(unit, player_id)

	# Move unit models to deployment position
	_move_unit_instantly(unit, deploy_pos)

	step.result_text = "Deployed at (%.1f, %.1f)" % [deploy_pos.x, deploy_pos.z]
	_log("  %s deployed" % unit.get_name(), "action")


## Executes round start step.
func _execute_round_start(step: BattleStep) -> void:
	var round_num = step.action_data.get("round", 1)
	state.current_round = round_num
	state.phase = Phase.ROUND_START

	# Reset activations
	for unit in player1_units:
		unit.reset_activation()
	for unit in player2_units:
		unit.reset_activation()

	state_changed.emit(state)
	step.result_text = "Round %d begins" % round_num

	# Generate round steps
	_generate_round_steps(round_num)


## Executes round end step.
func _execute_round_end(step: BattleStep) -> void:
	var round_num = step.action_data.get("round", 1)

	# Update objectives
	_update_objective_control()

	step.result_text = "Round %d complete. P1: %d objectives, P2: %d objectives" % [
		round_num,
		state.player1_objectives,
		state.player2_objectives
	]

	_log("Round %d ended - P1: %d obj, P2: %d obj" % [
		round_num, state.player1_objectives, state.player2_objectives
	], "phase")

	# Check if game should end
	if round_num >= state.max_rounds:
		_end_battle()
	else:
		# Queue next round start
		var next_round_step = _create_step("round_start", null)
		next_round_step.description = "Start Round %d" % (round_num + 1)
		next_round_step.details = "Begin the next round of battle"
		next_round_step.action_data["round"] = round_num + 1
		step_queue.push_front(next_round_step)


## Executes activation start step.
func _execute_activation_start(step: BattleStep) -> void:
	var unit = step.unit
	state.current_unit = unit
	state.phase = Phase.ACTIVATION
	state_changed.emit(state)

	var action_type = step.action_data.get("action_type", "Unknown")
	step.result_text = "Activating: %s" % action_type
	_log("%s activates (%s)" % [unit.get_name(), action_type], "action")


## Executes activation end step.
func _execute_activation_end(step: BattleStep) -> void:
	var unit = step.unit
	unit.activate(state.current_round)

	step.result_text = "Activation complete"


## Executes a movement step.
func _execute_movement(step: BattleStep) -> void:
	var unit = step.unit
	var target = step.target_position

	state.phase = Phase.MOVEMENT
	state_changed.emit(state)

	# Animate movement
	await _animate_unit_movement(unit, target)

	var distance = step.path_start.distance_to(target)
	step.result_text = "Moved %.1f\"" % (distance / 0.0254)  # Convert to inches
	_log("  Moved %.1f\"" % (distance / 0.0254), "action")


## Executes hold/idle step.
func _execute_hold(step: BattleStep) -> void:
	step.result_text = "Holding position"
	_log("  Holding position", "action")


## Executes a shooting step.
func _execute_shooting(step: BattleStep) -> void:
	var attacker = step.unit
	var defender = step.target_unit

	if not defender or defender.is_destroyed():
		step.result_text = "No valid target"
		return

	state.phase = Phase.SHOOTING
	state_changed.emit(state)

	# Setup context
	var player_id = attacker.unit_properties.get("player_id", 1)
	if player_id == 1:
		ai_manager.context.ai_units = [attacker]
		ai_manager.context.enemy_units.assign(player2_units)
	else:
		ai_manager.context.ai_units = [attacker]
		ai_manager.context.enemy_units.assign(player1_units)

	# Resolve shooting
	var result = AICombat.resolve_shooting(attacker, defender, ai_manager.context)

	step.dice_results = []  # Would need to capture from combat
	step.casualties = result.casualties.size()
	step.result_text = "Hits: %d, Wounds: %d, Casualties: %d" % [
		result.hits,
		result.wounds,
		result.casualties.size()
	]

	_log("  Shooting: %d attacks, %d hits, %d wounds, %d casualties" % [
		result.total_attacks, result.hits, result.wounds, result.casualties.size()
	], "combat")

	# Update kill count
	if result.casualties.size() > 0:
		if player_id == 1:
			state.player1_kills += result.casualties.size()
		else:
			state.player2_kills += result.casualties.size()

	# Check morale
	if AIMorale.needs_morale_test(defender, result.wounds):
		_queue_morale_step(defender, "shooting")


## Executes a melee step.
func _execute_melee(step: BattleStep) -> void:
	var attacker = step.unit
	var defender = step.target_unit

	if not defender or defender.is_destroyed():
		step.result_text = "No valid target"
		return

	state.phase = Phase.MELEE
	state_changed.emit(state)

	# Setup context
	var player_id = attacker.unit_properties.get("player_id", 1)
	if player_id == 1:
		ai_manager.context.ai_units = [attacker]
		ai_manager.context.enemy_units.assign(player2_units)
	else:
		ai_manager.context.ai_units = [attacker]
		ai_manager.context.enemy_units.assign(player1_units)

	# Resolve melee
	var is_fatigued = attacker.unit_properties.get("fought_this_round", false)
	var result = AICombat.resolve_melee(attacker, defender, ai_manager.context, is_fatigued)

	attacker.unit_properties["fought_this_round"] = true

	step.casualties = result.casualties.size()
	step.result_text = "Hits: %d, Wounds: %d, Casualties: %d" % [
		result.hits,
		result.wounds,
		result.casualties.size()
	]

	var winner_text = "Tie"
	if result.winner:
		winner_text = result.winner.get_name() + " wins"

	_log("  Melee: %d attacks, %d hits, %d wounds - %s" % [
		result.total_attacks, result.hits, result.wounds, winner_text
	], "combat")

	# Update kill count
	if result.casualties.size() > 0:
		if player_id == 1:
			state.player1_kills += result.casualties.size()
		else:
			state.player2_kills += result.casualties.size()

	# Check morale
	if result.winner and result.winner != defender:
		if not defender.is_destroyed():
			_queue_morale_step(defender, "melee")


## Executes a morale step.
func _execute_morale(step: BattleStep) -> void:
	var unit = step.unit
	var context = step.action_data.get("context", "")

	state.phase = Phase.MORALE
	state_changed.emit(state)

	var outcome = AIMorale.take_morale_test(unit)
	AIMorale.apply_morale_outcome(unit, outcome)

	match outcome.result:
		AIMorale.MoraleResult.PASSED:
			step.result_text = "Morale test PASSED (rolled %d)" % outcome.roll
			_log("  %s passes morale (rolled %d)" % [unit.get_name(), outcome.roll], "morale")
		AIMorale.MoraleResult.SHAKEN:
			step.result_text = "Morale test FAILED - SHAKEN! (rolled %d)" % outcome.roll
			_log("  %s is SHAKEN! (rolled %d)" % [unit.get_name(), outcome.roll], "morale")
		AIMorale.MoraleResult.ROUTED:
			step.result_text = "Morale test FAILED - ROUTED! (rolled %d)" % outcome.roll
			_log("  %s has ROUTED! (rolled %d)" % [unit.get_name(), outcome.roll], "morale")


## Queues a morale step for a unit.
func _queue_morale_step(unit: GameUnit, context: String) -> void:
	var step = _create_step("morale", unit)
	step.description = "%s takes morale test" % unit.get_name()
	step.details = "Triggered by %s casualties" % context
	step.action_data["context"] = context

	# Insert at front to execute immediately
	step_queue.push_front(step)


# ===== Helper Methods =====

## Creates a new battle step.
func _create_step(type: String, unit: GameUnit) -> BattleStep:
	var step = BattleStep.new()
	step.id = step_counter
	step_counter += 1
	step.type = type
	step.unit = unit
	return step


## Gets the center position of a unit.
func _get_unit_center(unit: GameUnit) -> Vector3:
	if unit == null:
		return Vector3.ZERO

	var sum = Vector3.ZERO
	var count = 0

	for model in unit.models:
		if model.is_alive and model.node:
			sum += model.node.global_position
			count += 1

	if count > 0:
		return sum / count
	return Vector3.ZERO


## Gets deployment position for a unit.
func _get_deployment_position(unit: GameUnit, player_id: int) -> Vector3:
	# Get table dimensions (assume 4x4 feet)
	var table_width = 1.2192  # 4 feet in meters
	var table_depth = 1.2192
	var deployment_depth = 0.3048  # 12 inches

	# Random position within deployment zone
	var x = randf_range(-table_width / 2 + 0.1, table_width / 2 - 0.1)
	var z: float

	if player_id == 1:
		z = randf_range(-table_depth / 2, -table_depth / 2 + deployment_depth)
	else:
		z = randf_range(table_depth / 2 - deployment_depth, table_depth / 2)

	return Vector3(x, 0, z)


## Moves a unit instantly to a position.
func _move_unit_instantly(unit: GameUnit, target: Vector3) -> void:
	var offset = Vector3.ZERO
	var base_diameter = 0.032  # Default 32mm

	for i in range(unit.models.size()):
		var model = unit.models[i]
		if model.is_alive and model.node:
			# Arrange in line formation
			var model_offset = Vector3(i * base_diameter * 1.25, 0, 0)
			model.node.global_position = target + model_offset


## Animates unit movement to target position.
func _animate_unit_movement(unit: GameUnit, target: Vector3) -> void:
	var start_pos = _get_unit_center(unit)
	var distance = start_pos.distance_to(target)
	var duration = distance / 0.15  # Speed: 0.15 m/s
	duration = clampf(duration, 0.5, 3.0)

	for model in unit.models:
		if model.is_alive and model.node:
			var offset = model.node.global_position - start_pos
			var target_pos = target + offset

			var tween = create_tween()
			tween.tween_property(
				model.node,
				"global_position",
				target_pos,
				duration
			)

	await get_tree().create_timer(duration).timeout


## Updates objective control based on unit positions.
func _update_objective_control() -> void:
	if not mission:
		return

	state.player1_objectives = 0
	state.player2_objectives = 0

	for obj in mission.objectives:
		var p1_count = _count_units_near_objective(obj.position, player1_units)
		var p2_count = _count_units_near_objective(obj.position, player2_units)

		if p1_count > 0 and p2_count == 0:
			obj.controller = 1
			state.player1_objectives += 1
		elif p2_count > 0 and p1_count == 0:
			obj.controller = 2
			state.player2_objectives += 1
		else:
			obj.controller = 0  # Contested or unclaimed


## Counts units within 3" of an objective.
func _count_units_near_objective(obj_pos: Vector3, units: Array[GameUnit]) -> int:
	var count = 0
	var seize_range = 0.0762  # 3 inches in meters

	for unit in units:
		if unit.is_destroyed():
			continue
		var unit_pos = _get_unit_center(unit)
		if unit_pos.distance_to(obj_pos) <= seize_range:
			count += 1

	return count


## Checks if a step matches a phase.
func _step_matches_phase(step: BattleStep, phase: Phase) -> bool:
	match phase:
		Phase.DEPLOYMENT:
			return step.type == "deploy"
		Phase.ROUND_START:
			return step.type == "round_start"
		Phase.ROUND_END:
			return step.type == "round_end"
		Phase.MOVEMENT:
			return step.type in ["charge", "rush", "advance"]
		Phase.SHOOTING:
			return step.type == "shoot"
		Phase.MELEE:
			return step.type == "melee"
		Phase.MORALE:
			return step.type == "morale"
		_:
			return false


## Checks if the battle should end.
func _check_battle_end() -> void:
	# Check if all units of one side are destroyed
	var p1_alive = player1_units.any(func(u): return not u.is_destroyed())
	var p2_alive = player2_units.any(func(u): return not u.is_destroyed())

	if not p1_alive:
		state.winner = 2
		_end_battle()
	elif not p2_alive:
		state.winner = 1
		_end_battle()


## Ends the battle.
func _end_battle() -> void:
	state.phase = Phase.GAME_OVER
	_is_running = false

	# Determine winner
	if state.winner == 0:
		if state.player1_objectives > state.player2_objectives:
			state.winner = 1
		elif state.player2_objectives > state.player1_objectives:
			state.winner = 2
		else:
			state.winner = -1  # Tie

	var winner_text = "TIE"
	if state.winner == 1:
		winner_text = player1_army_name
	elif state.winner == 2:
		winner_text = player2_army_name

	_log("=== BATTLE OVER ===", "header")
	_log("Winner: %s" % winner_text, "header")
	_log("Final Score - P1: %d objectives, P2: %d objectives" % [
		state.player1_objectives, state.player2_objectives
	], "info")
	_log("Casualties - P1 inflicted: %d, P2 inflicted: %d" % [
		state.player1_kills, state.player2_kills
	], "info")

	battle_ended.emit(state.winner, state)
	state_changed.emit(state)


## Logs a message.
func _log(message: String, type: String = "info") -> void:
	battle_log.emit(message, type)
	print("[Battle] " + message)


## Handler for AI log messages.
func _on_ai_log(message: String) -> void:
	_log(message, "ai")


## Handler for combat results.
func _on_combat_result(result: AICombat.CombatResult) -> void:
	pass  # Handled in step execution


## Handler for morale tests.
func _on_morale_test(unit: GameUnit, outcome: AIMorale.MoraleOutcome) -> void:
	pass  # Handled in step execution


# ===== Public Getters =====

## Gets the current battle state.
func get_state() -> BattleState:
	return state


## Gets the current step.
func get_current_step() -> BattleStep:
	return current_step


## Checks if waiting for user input.
func is_waiting() -> bool:
	return _waiting_for_input


## Checks if battle is running.
func is_running() -> bool:
	return _is_running


## Gets the step queue size.
func get_pending_steps() -> int:
	return step_queue.size()
