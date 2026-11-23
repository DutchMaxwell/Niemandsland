extends GdUnitTestSuite
## The AI volley the rules core cannot resolve is HELD - one battle-log line names the reason and the
## census counts it (`legacy["held"]`); the table no longer resolves it (`_solo_resolve_ai_volley` has no production caller).
## Real: the main scene, NmlCore, the AI body's `_run_ai_shooting` with a board captured before the activation, the live deny file.
## Constructed: a 3-model rifle unit and a target carrying a deny-listed rule (Grounded Protection), 10" apart.
## RED (main): the table resolves the volley (the target is shot at, `legacy["ai_volley"]` +1, no held line).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 3, "defense": 4, "tough": 1, "z_step_in": 1.5, "game_system": "gf",
	"faction_folder": "soul_snatcher_cults", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 3, "count": 3, "rules": []}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	CoreActivation._env = 1
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


@warning_ignore('unused_parameter')
func test_a_volley_the_core_refuses_is_held_with_one_line(timeout := 300000, do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "no NmlCore") -> void:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Gunners", "models": 3, "x_in": 0.0}, true), RIFLE)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Shrine", "models": 5, "x_in": 10.0,
		"rules": ["Grounded Protection"]}, true), {})
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	var held0 := int((CoreActivation.legacy.get("held", {}) as Dictionary).get("_all", 0))
	var table0 := int((CoreActivation.legacy.get("ai_volley", {}) as Dictionary).get("_all", 0))
	_main.seed_tray_rng(1)
	_main._solo_core_ai_h = CoreActivation.capture(_main, true)
	await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
	if int(_main._solo_core_ai_h) != 0:
		_main.solo_controller._core_node_ready().release(int(_main._solo_core_ai_h))
	_main._solo_core_ai_h = 0
	_main.battle_log.entry_added.disconnect(tap)
	var text := "\n".join(lines)
	assert_int(int((CoreActivation.legacy.get("held", {}) as Dictionary).get("_all", 0)) - held0) \
		.override_failure_message("the census counts the held volley:\n%s" % text).is_equal(1)
	assert_int(int((CoreActivation.legacy.get("ai_volley", {}) as Dictionary).get("_all", 0)) - table0) \
		.override_failure_message("no table volley:\n%s" % text).is_equal(0)
	assert_str(text).override_failure_message("one line names the hold and its reason:\n%s" % text) \
		.contains("Gunners: no volley — the rules core cannot resolve this volley (").contains("Grounded Protection")
	assert_int(foe.get_alive_count()).override_failure_message("the held volley hurt nobody").is_equal(5)
