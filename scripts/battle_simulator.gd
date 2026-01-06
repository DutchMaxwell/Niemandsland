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
var terrain_overlay: Node3D = null  ## Reference to TerrainOverlay for AI terrain integration


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

## Tracks deployed unit positions for collision detection
## Each entry: { "center": Vector3, "radius": float }
var _deployed_positions: Array[Dictionary] = []

## The player who won the deployment roll-off (and takes first turn in round 1)
## Per OPR rules: "the player that won the deployment roll-off takes the first turn"
var _deployment_winner: int = 1

## The player who finished activating first last round (goes first next round)
## Per OPR rules: "On each new round the player that finished activating first
## on the last round gets to activate first."
var _last_round_first_finisher: int = 1

## 3D objective markers
var _objective_markers: Array[Node3D] = []

## Table dimensions (set via setup_mission)
var _table_bounds: Rect2 = Rect2(-0.6096, -0.6096, 1.2192, 1.2192)  # 4x4 feet default


func _ready() -> void:
	state = BattleState.new()


# ===== Setup =====

## Initializes the simulator with references.
func initialize(p_army_manager: OPRArmyManager) -> void:
	if p_army_manager == null:
		push_error("BattleSimulator: army_manager is null")
		return

	army_manager = p_army_manager

	# Create AI manager instance
	ai_manager = AIManager.new()
	add_child(ai_manager)
	ai_manager.ai_enabled = true

	# Connect AI signals for logging
	if ai_manager.has_signal("action_log"):
		ai_manager.action_log.connect(_on_ai_log)
	if ai_manager.has_signal("combat_result"):
		ai_manager.combat_result.connect(_on_combat_result)
	if ai_manager.has_signal("morale_test"):
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


## Sets the terrain overlay reference for AI terrain integration.
## Call this before setup_mission() to enable terrain mechanics in combat.
##
## @param overlay: The TerrainOverlay node from the main scene
func set_terrain_overlay(overlay: Node3D) -> void:
	terrain_overlay = overlay


## Sets up the mission with objectives and terrain.
func setup_mission(table_bounds: Rect2) -> void:
	if ai_manager == null:
		push_error("BattleSimulator: ai_manager not initialized")
		return

	_table_bounds = table_bounds
	ai_manager.setup_mission(table_bounds)
	mission = ai_manager.mission_state

	if mission == null:
		push_error("BattleSimulator: mission_state is null after setup")
		return

	# Setup terrain for AI combat system
	_setup_terrain_for_ai()

	# Create 3D objective markers
	_create_objective_markers()

	_log("Mission: %d objectives, %d rounds" % [
		mission.objectives.size(),
		mission.max_rounds
	], "info")


## Transfers terrain data from TerrainOverlay to AIManager for combat calculations.
## This enables cover bonuses, difficult terrain movement limits, and dangerous terrain tests.
func _setup_terrain_for_ai() -> void:
	if ai_manager == null:
		return

	if terrain_overlay == null:
		_log("Terrain: No terrain overlay set, combat will not use terrain bonuses", "info")
		return

	if not terrain_overlay.has_method("get_terrain_pieces_for_ai"):
		_log("Terrain: terrain_overlay missing get_terrain_pieces_for_ai method", "info")
		return

	var pieces: Array[AITerrain.TerrainPiece] = terrain_overlay.get_terrain_pieces_for_ai()
	ai_manager.set_terrain(pieces)

	# Count terrain types for logging
	var cover_count := 0
	var difficult_count := 0
	var dangerous_count := 0

	for piece in pieces:
		if piece.is_cover():
			cover_count += 1
		if piece.is_difficult():
			difficult_count += 1
		if piece.is_dangerous():
			dangerous_count += 1

	_log("Terrain: %d pieces (%d cover, %d difficult, %d dangerous)" % [
		pieces.size(), cover_count, difficult_count, dangerous_count
	], "info")


## Creates 3D objective markers on the table.
func _create_objective_markers() -> void:
	# Clear existing markers
	_clear_objective_markers()

	if mission == null or mission.objectives.is_empty():
		return

	# Get table reference from army_manager
	var parent = army_manager.table if army_manager and army_manager.table else self

	# Create markers for each objective
	for obj in mission.objectives:
		var marker = _create_single_objective_marker(obj.id, obj.position)
		if marker:
			parent.add_child(marker)
			_objective_markers.append(marker)


## Creates a single objective marker with number label.
func _create_single_objective_marker(obj_id: int, position: Vector3) -> Node3D:
	var marker = Node3D.new()
	marker.name = "Objective_%d" % obj_id

	# Objective marker (40mm base, golden ring)
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.018  # ~36mm inner
	torus.outer_radius = 0.022  # ~44mm outer
	ring.mesh = torus
	ring.rotation_degrees.x = 90  # Lay flat

	var ring_mat = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.85, 0.0)  # Gold
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.85, 0.0)
	ring_mat.emission_energy_multiplier = 0.5
	ring.material_override = ring_mat
	marker.add_child(ring)

	# Center disc
	var disc = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.018
	cylinder.bottom_radius = 0.018
	cylinder.height = 0.002
	disc.mesh = cylinder

	var disc_mat = StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.2, 0.2, 0.2, 0.8)
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.material_override = disc_mat
	marker.add_child(disc)

	# Number label
	var label = Label3D.new()
	label.text = str(obj_id)
	label.font_size = 64
	label.position.y = 0.02
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.85, 0.0)
	marker.add_child(label)

	marker.position = position
	marker.position.y = 0.005  # Slightly above table

	return marker


## Clears all objective markers from the scene.
func _clear_objective_markers() -> void:
	for marker in _objective_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_objective_markers.clear()


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
	_deployed_positions.clear()  # Reset collision tracking

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
	_clear_objective_markers()
	_log("Battle stopped", "info")


# ===== Step Generation =====

## Generates deployment steps for both armies.
## Alternates between players: P1, P2, P1, P2...
## Per OPR: "Players roll-off to determine who places first, highest winner picks."
## "The player that won the deployment roll-off takes the first turn."
func _generate_deployment_steps() -> void:
	state.phase = Phase.DEPLOYMENT
	state_changed.emit(state)

	_log("--- DEPLOYMENT PHASE ---", "phase")

	# Deployment roll-off: random winner deploys first and takes first turn
	_deployment_winner = 1 if randf() < 0.5 else 2
	_log("Player %d wins deployment roll-off (deploys first, takes first turn)" % _deployment_winner, "roll")

	# Interleave deployment: winner first, then alternate
	var p1_queue = player1_units.duplicate()
	var p2_queue = player2_units.duplicate()
	var p1_idx = 0
	var p2_idx = 0
	var current_player = _deployment_winner  # Roll-off winner deploys first

	while p1_idx < p1_queue.size() or p2_idx < p2_queue.size():
		if current_player == 1 and p1_idx < p1_queue.size():
			var unit = p1_queue[p1_idx]
			var step = _create_step("deploy", unit)
			step.description = "Deploy %s" % unit.get_name()
			step.details = "Player 1 deploys unit to their deployment zone"
			step.action_data["player"] = 1
			step_queue.append(step)
			p1_idx += 1
		elif current_player == 2 and p2_idx < p2_queue.size():
			var unit = p2_queue[p2_idx]
			var step = _create_step("deploy", unit)
			step.description = "Deploy %s" % unit.get_name()
			step.details = "Player 2 deploys unit to their deployment zone"
			step.action_data["player"] = 2
			step_queue.append(step)
			p2_idx += 1
		elif p1_idx < p1_queue.size():
			# P2 has no more units, continue with P1
			var unit = p1_queue[p1_idx]
			var step = _create_step("deploy", unit)
			step.description = "Deploy %s" % unit.get_name()
			step.details = "Player 1 deploys unit to their deployment zone"
			step.action_data["player"] = 1
			step_queue.append(step)
			p1_idx += 1
		elif p2_idx < p2_queue.size():
			# P1 has no more units, continue with P2
			var unit = p2_queue[p2_idx]
			var step = _create_step("deploy", unit)
			step.description = "Deploy %s" % unit.get_name()
			step.details = "Player 2 deploys unit to their deployment zone"
			step.action_data["player"] = 2
			step_queue.append(step)
			p2_idx += 1

		current_player = 3 - current_player  # Toggle 1<->2

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
	# Round 1: deployment winner goes first
	# Round 2+: player who finished activating first last round goes first
	var activation_order: Array[GameUnit] = []
	var p1_idx = 0
	var p2_idx = 0
	var current_player: int
	if round_num == 1:
		current_player = _deployment_winner
		_log("Deployment winner (Player %d) activates first" % current_player, "turn")
	else:
		current_player = _last_round_first_finisher
		_log("Player %d finished first last round, activates first" % current_player, "turn")

	# Track who finishes first (runs out of units to activate)
	var first_finisher: int = 0

	while p1_idx < p1_queue.size() or p2_idx < p2_queue.size():
		if current_player == 1 and p1_idx < p1_queue.size():
			activation_order.append(p1_queue[p1_idx])
			p1_idx += 1
		elif current_player == 2 and p2_idx < p2_queue.size():
			activation_order.append(p2_queue[p2_idx])
			p2_idx += 1
		elif p1_idx < p1_queue.size():
			# P2 finished first (no more P2 units)
			if first_finisher == 0:
				first_finisher = 2
			activation_order.append(p1_queue[p1_idx])
			p1_idx += 1
		elif p2_idx < p2_queue.size():
			# P1 finished first (no more P1 units)
			if first_finisher == 0:
				first_finisher = 1
			activation_order.append(p2_queue[p2_idx])
			p2_idx += 1

		current_player = 3 - current_player  # Toggle 1<->2

	# If equal units, the one who activated last finishes first (other player still had units)
	if first_finisher == 0:
		# Both finished at the same time (equal units), last activator finished first
		first_finisher = 3 - current_player

	_last_round_first_finisher = first_finisher
	_log("Player %d finished activating first (goes first next round)" % first_finisher, "turn")

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

	# Check if unit is Shaken - must go Idle to remove Shaken
	# Per OPR: "Shaken units must stay idle (can't take any actions),
	# which stops them being Shaken at the end of the activation."
	if AIMorale.is_shaken(unit):
		var idle_step = _create_step("shaken_idle", unit)
		idle_step.description = "%s is Shaken - goes Idle" % unit.get_name()
		idle_step.details = "Shaken units must stay idle to recover"
		idle_step.action_data["player"] = player_id
		step_queue.append(idle_step)
		return

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
		"shaken_idle":
			_execute_shaken_idle(current_step)
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
	if unit == null:
		push_error("BattleSimulator: _execute_deploy called with null unit")
		step.result_text = "Error: null unit"
		return

	var player_id = step.action_data.get("player", 1)

	# Get unit dimensions for collision detection
	var unit_radius = _get_unit_footprint_radius(unit)

	# Calculate deployment position with collision avoidance
	var deploy_pos = _get_deployment_position(unit, player_id, unit_radius)

	# Move unit models to deployment position with proper formation
	_move_unit_to_position(unit, deploy_pos, player_id)

	# Track this position for future collision detection
	_deployed_positions.append({
		"center": deploy_pos,
		"radius": unit_radius,
		"player": player_id
	})

	step.result_text = "Deployed at (%.2fm, %.2fm)" % [deploy_pos.x, deploy_pos.z]
	_log("  %s deployed" % unit.get_name(), "action")


## Executes round start step.
func _execute_round_start(step: BattleStep) -> void:
	var round_num = step.action_data.get("round", 1)
	state.current_round = round_num
	state.phase = Phase.ROUND_START

	# Reset activations and combat state for all units
	for unit in player1_units:
		unit.reset_activation()
		unit.unit_properties["fought_this_round"] = false
		unit.unit_properties["moved_this_turn"] = false
	for unit in player2_units:
		unit.reset_activation()
		unit.unit_properties["fought_this_round"] = false
		unit.unit_properties["moved_this_turn"] = false

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

	if unit == null:
		push_error("BattleSimulator: _execute_movement called with null unit")
		return

	state.phase = Phase.MOVEMENT
	state_changed.emit(state)

	# Determine facing: towards target unit (charge) or movement direction
	var facing_target: Vector3 = target
	if step.target_unit and not step.target_unit.is_destroyed():
		facing_target = _get_unit_center(step.target_unit)

	# Animate movement with proper facing
	await _animate_unit_movement(unit, target, facing_target)

	var distance = step.path_start.distance_to(target)
	step.result_text = "Moved %.1f\"" % (distance / 0.0254)  # Convert to inches
	_log("  Moved %.1f\"" % (distance / 0.0254), "action")


## Executes hold/idle step.
func _execute_hold(step: BattleStep) -> void:
	step.result_text = "Holding position"
	_log("  Holding position", "action")


## Executes Shaken unit idle step.
## Per OPR: "When activated, Shaken units must spend their activation being idle,
## which stops them being Shaken at the end of the activation."
func _execute_shaken_idle(step: BattleStep) -> void:
	var unit = step.unit
	if unit == null:
		push_error("BattleSimulator: _execute_shaken_idle called with null unit")
		step.result_text = "Error: null unit"
		return

	# Remove Shaken status
	AIMorale.remove_shaken(unit)
	unit.is_activated = true

	step.result_text = "Recovered from Shaken - idle"
	_log("  %s recovers from Shaken (idle activation)" % unit.get_name(), "morale")


## Executes a shooting step.
func _execute_shooting(step: BattleStep) -> void:
	var attacker = step.unit
	var defender = step.target_unit

	if attacker == null:
		push_error("BattleSimulator: _execute_shooting called with null attacker")
		step.result_text = "Error: null attacker"
		return

	if defender == null or defender.is_destroyed():
		step.result_text = "No valid target"
		_log("  No valid target for shooting", "action")
		return

	state.phase = Phase.SHOOTING
	state_changed.emit(state)

	# Setup context
	var attacker_player_id = attacker.unit_properties.get("player_id", 1)
	if attacker_player_id == 1:
		ai_manager.context.ai_units = [attacker]
		ai_manager.context.enemy_units.assign(player2_units)
	else:
		ai_manager.context.ai_units = [attacker]
		ai_manager.context.enemy_units.assign(player1_units)

	# Resolve shooting
	var result = AICombat.resolve_shooting(attacker, defender, ai_manager.context)

	step.casualties = result.casualties.size()
	step.result_text = "Attacks: %d, Hits: %d, Wounds: %d, Kills: %d" % [
		result.total_attacks,
		result.hits,
		result.wounds,
		result.casualties.size()
	]

	_log("  Shooting: %d attacks, %d hits, %d wounds, %d kills" % [
		result.total_attacks, result.hits, result.wounds, result.casualties.size()
	], "combat")

	# Update kill count - attacker inflicted these casualties
	if result.casualties.size() > 0:
		if attacker_player_id == 1:
			state.player1_kills += result.casualties.size()
		else:
			state.player2_kills += result.casualties.size()

	# Check morale - defender takes test if they took wounds
	if not defender.is_destroyed() and AIMorale.needs_morale_test(defender, result.wounds):
		_queue_morale_step(defender, "shooting", false, false)


## Executes a melee step.
func _execute_melee(step: BattleStep) -> void:
	var attacker = step.unit
	var defender = step.target_unit

	if attacker == null:
		push_error("BattleSimulator: _execute_melee called with null attacker")
		step.result_text = "Error: null attacker"
		return

	if defender == null or defender.is_destroyed():
		step.result_text = "No valid target"
		_log("  No valid target for melee", "action")
		return

	state.phase = Phase.MELEE
	state_changed.emit(state)

	# Setup context
	var attacker_player_id = attacker.unit_properties.get("player_id", 1)

	if attacker_player_id == 1:
		ai_manager.context.ai_units = [attacker]
		ai_manager.context.enemy_units.assign(player2_units)
	else:
		ai_manager.context.ai_units = [attacker]
		ai_manager.context.enemy_units.assign(player1_units)

	# Resolve melee (includes attacker strikes AND defender strike-backs)
	var is_fatigued = attacker.unit_properties.get("fought_this_round", false)
	var result = AICombat.resolve_melee(attacker, defender, ai_manager.context, is_fatigued)

	# Note: fought_this_round is already set by AICombat.resolve_melee for both units

	# Casualties inflicted BY attacker ON defender
	var attacker_inflicted = result.casualties.size()
	# Casualties inflicted BY defender ON attacker (from strike-backs and Counter)
	var defender_inflicted = result.attacker_casualties.size()

	step.casualties = attacker_inflicted
	step.result_text = "Attacker deals %d wounds (%d kills), Defender strikes back for %d wounds (%d kills)" % [
		result.defender_wounds,
		attacker_inflicted,
		result.attacker_wounds,
		defender_inflicted
	]

	var winner_text = "Tie"
	if result.winner:
		winner_text = result.winner.get_name() + " wins"

	_log("  Melee: %s deals %d wounds (%d kills), %s strikes back for %d wounds (%d kills) - %s" % [
		attacker.get_name(),
		result.defender_wounds,
		attacker_inflicted,
		defender.get_name(),
		result.attacker_wounds,
		defender_inflicted,
		winner_text
	], "combat")

	# Update kill counts - track who inflicted kills
	# Attacker's kills (casualties on defender)
	if attacker_inflicted > 0:
		if attacker_player_id == 1:
			state.player1_kills += attacker_inflicted
		else:
			state.player2_kills += attacker_inflicted

	# Defender's kills (casualties on attacker from strike-backs and Counter)
	# Per OPR: "When two units fight, both fight, and the side that dealt most wounds wins."
	if defender_inflicted > 0:
		var defender_player_id = defender.unit_properties.get("player_id", 2)
		if defender_player_id == 1:
			state.player1_kills += defender_inflicted
		else:
			state.player2_kills += defender_inflicted

	# Check morale - BOTH sides test if they took casualties
	# Per OPR: "After a unit takes casualties from an attack, it must take a morale test."

	# 1. Loser always tests (from losing melee)
	if result.winner != null:
		var loser = defender if result.winner == attacker else attacker
		if not loser.is_destroyed():
			_queue_morale_step(loser, "melee", true, true)

		# 2. Winner tests if they took casualties (from counter-attack)
		var winner = result.winner
		if not winner.is_destroyed():
			var winner_casualties = 0
			if winner == attacker:
				winner_casualties = defender_inflicted
			else:
				winner_casualties = attacker_inflicted

			# Winner tests if they took any casualties
			if winner_casualties > 0:
				_queue_morale_step(winner, "melee_counter", false, false)
	else:
		# Tie - both test if they took casualties
		if not attacker.is_destroyed() and defender_inflicted > 0:
			_queue_morale_step(attacker, "melee", true, false)
		if not defender.is_destroyed() and attacker_inflicted > 0:
			_queue_morale_step(defender, "melee", true, false)

	# Consolidation moves (per OPR rules)
	# "If one of the two units was destroyed, then the other unit may move by up to 3"."
	# "If neither of the units was destroyed, then the charging unit must move back by 1"."
	if defender.is_destroyed():
		_consolidation_move(attacker, 3.0, "forward")
		_log("  %s consolidates 3\" (defender destroyed)" % attacker.get_name(), "movement")
	elif attacker.is_destroyed():
		_consolidation_move(defender, 3.0, "forward")
		_log("  %s consolidates 3\" (attacker destroyed)" % defender.get_name(), "movement")
	else:
		# Neither destroyed - charger moves back 1"
		_consolidation_move(attacker, 1.0, "back")
		_log("  %s moves back 1\" (disengage)" % attacker.get_name(), "movement")


## Executes a morale step.
func _execute_morale(step: BattleStep) -> void:
	var unit = step.unit
	var trigger_context = step.action_data.get("context", "combat")
	var is_melee = step.action_data.get("is_melee", false)
	var lost_melee = step.action_data.get("lost_melee", false)

	if unit == null:
		push_error("BattleSimulator: _execute_morale called with null unit")
		step.result_text = "Error: null unit"
		return

	if unit.is_destroyed():
		step.result_text = "Unit already destroyed"
		_log("  %s already destroyed, skipping morale" % unit.get_name(), "morale")
		return

	state.phase = Phase.MORALE
	state_changed.emit(state)

	# Take morale test with proper melee parameters
	var outcome = AIMorale.take_morale_test(unit, is_melee, lost_melee)
	AIMorale.apply_morale_outcome(unit, outcome)

	var unit_name = unit.get_name()
	match outcome.result:
		AIMorale.MoraleResult.PASSED:
			step.result_text = "Morale test PASSED (rolled %d vs %d+)" % [outcome.roll, outcome.quality]
			_log("  %s passes morale (rolled %d vs %d+)" % [unit_name, outcome.roll, outcome.quality], "morale")
		AIMorale.MoraleResult.SHAKEN:
			step.result_text = "Morale test FAILED - SHAKEN! (rolled %d vs %d+)" % [outcome.roll, outcome.quality]
			_log("  %s is SHAKEN! (rolled %d vs %d+)" % [unit_name, outcome.roll, outcome.quality], "morale")
		AIMorale.MoraleResult.ROUTED:
			step.result_text = "Morale test FAILED - ROUTED! (rolled %d vs %d+)" % [outcome.roll, outcome.quality]
			_log("  %s has ROUTED and is destroyed! (rolled %d vs %d+)" % [unit_name, outcome.roll, outcome.quality], "morale")


## Queues a morale step for a unit.
## @param unit: The unit taking the morale test
## @param context: Context string for logging (e.g., "shooting", "melee", "melee_counter")
## @param is_melee: Whether this is from melee combat (affects Shaken vs Routed outcome)
## @param lost_melee: Whether the unit lost the melee (only relevant if is_melee=true)
func _queue_morale_step(unit: GameUnit, context: String, is_melee: bool = false, lost_melee: bool = false) -> void:
	if unit == null:
		push_error("BattleSimulator: _queue_morale_step called with null unit")
		return

	var step = _create_step("morale", unit)
	step.description = "%s takes morale test" % unit.get_name()
	step.details = "Triggered by %s casualties" % context
	step.action_data["context"] = context
	step.action_data["is_melee"] = is_melee
	step.action_data["lost_melee"] = lost_melee

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


## Gets unit footprint radius (for collision detection).
## Takes into account unit size and base dimensions.
func _get_unit_footprint_radius(unit: GameUnit) -> float:
	var base_diameter = _get_unit_base_diameter(unit)
	var model_count = unit.get_alive_count()
	if model_count == 0:
		model_count = unit.models.size()

	# Calculate line formation width
	var spacing = base_diameter * 1.25  # 25% gap between models
	var formation_width = base_diameter + (model_count - 1) * spacing

	# Return radius (half of diagonal for safety margin)
	return formation_width / 2.0 + base_diameter / 2.0


## Gets the base diameter for a unit in meters.
func _get_unit_base_diameter(unit: GameUnit) -> float:
	# Try to get from unit_properties (set during import)
	var base_mm = unit.unit_properties.get("base_size_round", 0)
	if base_mm <= 0:
		base_mm = unit.unit_properties.get("base_width_mm", 32)
	if base_mm <= 0:
		base_mm = 32  # Default 32mm

	return base_mm * 0.001  # Convert mm to meters


## Gets deployment position for a unit with collision avoidance.
func _get_deployment_position(unit: GameUnit, player_id: int, unit_radius: float) -> Vector3:
	# Use stored table bounds
	var table_width = _table_bounds.size.x
	var table_depth = _table_bounds.size.y
	var deployment_depth = 0.3048  # 12 inches in meters

	# Define deployment zone
	var min_x = _table_bounds.position.x + unit_radius + 0.05
	var max_x = _table_bounds.position.x + table_width - unit_radius - 0.05
	var z_base: float
	var z_range: float

	if player_id == 1:
		# Player 1: bottom edge (negative Z)
		z_base = _table_bounds.position.y + unit_radius + 0.02
		z_range = deployment_depth - unit_radius * 2
	else:
		# Player 2: top edge (positive Z)
		z_base = _table_bounds.position.y + table_depth - deployment_depth + unit_radius + 0.02
		z_range = deployment_depth - unit_radius * 2

	# Try to find non-colliding position (max 50 attempts)
	var best_pos = Vector3.ZERO
	var best_min_distance = -1.0
	var attempts = 0
	var max_attempts = 50

	while attempts < max_attempts:
		var test_x = randf_range(min_x, max_x)
		var test_z = z_base + randf_range(0, max(z_range, 0.01))
		var test_pos = Vector3(test_x, 0, test_z)

		# Check collision with already deployed units
		var min_distance = _get_min_distance_to_deployed(test_pos, player_id)

		# If no collision, use this position
		if min_distance < 0 or min_distance > unit_radius * 2:
			return test_pos

		# Track best position found so far
		if min_distance > best_min_distance:
			best_min_distance = min_distance
			best_pos = test_pos

		attempts += 1

	# Return best position found (may have some overlap)
	if best_min_distance >= 0:
		push_warning("BattleSimulator: Could not find collision-free deployment for %s" % unit.get_name())
		return best_pos

	# Fallback: return center of deployment zone
	return Vector3((min_x + max_x) / 2, 0, z_base + z_range / 2)


## Returns minimum distance to any deployed unit of the same player.
func _get_min_distance_to_deployed(pos: Vector3, player_id: int) -> float:
	var min_dist = -1.0

	for deployed in _deployed_positions:
		# Only check same player (units on same side shouldn't overlap)
		if deployed.player != player_id:
			continue

		var dist = pos.distance_to(deployed.center) - deployed.radius
		if min_dist < 0 or dist < min_dist:
			min_dist = dist

	return min_dist


## Moves a unit to a position with proper formation and facing.
func _move_unit_to_position(unit: GameUnit, target: Vector3, player_id: int) -> void:
	var base_diameter = _get_unit_base_diameter(unit)
	var spacing = base_diameter * 1.25  # 25% gap between models
	var alive_models = unit.get_alive_models()
	var model_count = alive_models.size()

	if model_count == 0:
		return

	# Calculate formation: line formation centered on target
	var formation_width = (model_count - 1) * spacing
	var start_x = target.x - formation_width / 2

	# Determine facing direction (towards enemy)
	var facing_angle: float
	if player_id == 1:
		facing_angle = 0.0  # Face positive Z (towards P2)
	else:
		facing_angle = PI   # Face negative Z (towards P1)

	# Position each model
	for i in range(alive_models.size()):
		var model = alive_models[i]
		if model.node:
			var model_x = start_x + i * spacing
			var model_pos = Vector3(model_x, 0, target.z)
			model.node.global_position = model_pos

			# Rotate to face enemy
			model.node.rotation.y = facing_angle


## Moves a unit instantly to a position (legacy, used for non-deployment moves).
func _move_unit_instantly(unit: GameUnit, target: Vector3) -> void:
	var base_diameter = _get_unit_base_diameter(unit)
	var spacing = base_diameter * 1.25
	var alive_models = unit.get_alive_models()

	if alive_models.is_empty():
		return

	var formation_width = (alive_models.size() - 1) * spacing
	var start_x = target.x - formation_width / 2

	for i in range(alive_models.size()):
		var model = alive_models[i]
		if model.node:
			var model_x = start_x + i * spacing
			model.node.global_position = Vector3(model_x, 0, target.z)


## Performs consolidation move after melee.
## @param unit: The unit to move
## @param distance_inches: Distance in inches to move
## @param direction: "forward" (toward enemy) or "back" (away from enemy)
func _consolidation_move(unit: GameUnit, distance_inches: float, direction: String) -> void:
	if unit == null or unit.is_destroyed():
		return

	var distance_meters = distance_inches * 0.0254  # Convert inches to meters
	var player_id = unit.unit_properties.get("player_id", 1)
	var unit_center = _get_unit_center(unit)

	# Determine movement direction based on player and consolidation type
	var move_direction: float
	if player_id == 1:
		# P1 faces positive Z
		move_direction = 1.0 if direction == "forward" else -1.0
	else:
		# P2 faces negative Z
		move_direction = -1.0 if direction == "forward" else 1.0

	var new_z = unit_center.z + (distance_meters * move_direction)

	# Move all models
	for model in unit.models:
		if model.is_alive and model.node:
			var current_pos = model.node.global_position
			model.node.global_position = Vector3(current_pos.x, current_pos.y, new_z + (current_pos.z - unit_center.z))


## Animates unit movement to target position with proper facing.
## facing_target: Position to face towards after movement (enemy unit or movement direction).
func _animate_unit_movement(unit: GameUnit, target: Vector3, facing_target: Vector3 = Vector3.ZERO) -> void:
	if unit == null:
		push_error("BattleSimulator: _animate_unit_movement called with null unit")
		return

	var alive_models = unit.get_alive_models()
	if alive_models.is_empty():
		return

	var start_pos = _get_unit_center(unit)
	var distance = start_pos.distance_to(target)
	var duration = distance / 0.15  # Speed: 0.15 m/s
	duration = clampf(duration, 0.5, 3.0)

	# Calculate proper formation at target
	var base_diameter = _get_unit_base_diameter(unit)
	var spacing = base_diameter * 1.25
	var formation_width = (alive_models.size() - 1) * spacing
	var start_x = target.x - formation_width / 2

	# Calculate facing angle
	var facing_angle = 0.0
	if facing_target != Vector3.ZERO:
		var direction = facing_target - target
		if direction.length_squared() > 0.001:
			facing_angle = atan2(direction.x, direction.z)

	# Animate each model
	for i in range(alive_models.size()):
		var model = alive_models[i]
		if model.node:
			var model_x = start_x + i * spacing
			var target_pos = Vector3(model_x, 0, target.z)

			var tween = create_tween()
			tween.set_parallel(true)

			# Move position
			tween.tween_property(
				model.node,
				"global_position",
				target_pos,
				duration
			).set_ease(Tween.EASE_IN_OUT)

			# Rotate to face target
			tween.tween_property(
				model.node,
				"rotation:y",
				facing_angle,
				duration * 0.5
			).set_ease(Tween.EASE_OUT)

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
