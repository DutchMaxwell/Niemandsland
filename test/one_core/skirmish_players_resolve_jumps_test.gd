extends GdUnitTestSuite
## Plan step 28a: only the core rolls a skirmish jump or fall (the table's JumpRules branch is gone). Where the core does
## not run, the battle log says the players resolve it: once at battle start on a skirmish table without the core
## (Manual), and at the activation start of a human unit the core slice refuses (with the refusal).
## Real: the main scene, the battle-start phase seam, the activation Start door, the core slice.
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const MANUAL := "Jumping and falling: Manual table, resolved by the players"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _lines: Array = []


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_lines = []
	_main.battle_log.entry_added.connect(_tap)


func after_test() -> void:
	_main.battle_log.entry_added.disconnect(_tap)
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _tap(e: Dictionary) -> void:
	_lines.append(str(e["text"]))


func _unit(system: String, rules: Array) -> GameUnit:
	return ParityTable._make_unit(_main, {"player": 1, "name": "Leaper", "models": 3, "x_in": 0.0, "z_step_in": 0.0,
		"quality": 4, "defense": 4, "tough": 1, "game_system": system, "faction_folder": "robot_legions", "rules": rules},
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 3, "rules": []})


func test_a_manual_skirmish_table_says_once_that_the_players_resolve_jumps() -> void:
	_unit("gff", [])
	_main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.PLAYING)
	assert_int(_lines.count(MANUAL)).override_failure_message("the Manual line: %s" % [_lines]).is_equal(1)


func test_no_manual_line_off_skirmish_or_where_the_core_runs() -> void:
	_unit("gf", [])
	_main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.PLAYING)
	assert_int(_lines.count(MANUAL)).override_failure_message("gf has no jumps").is_equal(0)
	_main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.DEPLOYMENT)
	_unit("gff", [])
	SoloHarness.start(_main, [2], 1)
	_main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.PLAYING)
	assert_int(_lines.count(MANUAL)).override_failure_message("the core runs here: %s" % [_lines]).is_equal(0)


@warning_ignore('unused_parameter')
func test_a_refused_unit_says_at_its_start_that_the_players_resolve_jumps(
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	SoloHarness.start(_main, [2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.lesson_paused(_main)
	CoreActivation._env = 1
	var refused := _unit("gff", ["Grounded Protection"])
	assert_bool(_main.core_activation_start(refused)).override_failure_message("no Start (refused)").is_true()
	CoreActivation.reset_all(_main)
	refused.unit_properties["special_rules"] = []   # the same unit, now one the core takes
	for m in refused.models:
		(m as ModelInstance).properties["special_rules"] = []
	assert_bool(_main.core_activation_start(refused)).override_failure_message("no Start (plain)").is_true()
	var said: Array = _lines.filter(func(l: String) -> bool: return l.contains("jumping and falling resolved by the players"))
	assert_array(said).override_failure_message("one line, the refused start's: %s" % [_lines]) \
		.contains_exactly(["Leaper: jumping and falling resolved by the players (unit_rule:Grounded Protection)"])
