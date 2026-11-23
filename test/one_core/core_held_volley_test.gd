extends GdUnitTestSuite
## The AI volley the rules core cannot resolve is HELD - one battle-log line names the reason and the
## census counts it (`legacy["held"]`); the table no longer resolves it (`_solo_resolve_ai_volley` has no AI caller).
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
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	CoreActivation._env = 1
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests
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


func _bearer(pid: int, unit_name: String, x_in: float) -> GameUnit:
	var gun := {"name": "Drop Bombs", "range_in": 0, "attacks": 4, "count": 3, "rules": ["Crossing Strike"]}
	return ParityTable._make_unit(_main, SIDE.merged({"player": pid, "name": unit_name, "models": 3, "x_in": x_in}, true), gun)


func _legs(from_in: float, to_in: float) -> Array:
	var legs: Array = []
	for i in 3:
		legs.append({"path": [Vector3(from_in * 0.0254, 0.0, 1.2 * 0.0254 * i), Vector3(to_in * 0.0254, 0.0, 1.2 * 0.0254 * i)]})
	return legs


## The AI's move-through strike the core did not take is held, and the line names the real reason: no rule of the pair is
## refused, so the core declined the activation itself (not "the table paid ...").
@warning_ignore('unused_parameter')
func test_an_ai_strike_the_core_did_not_take_is_held_with_its_reason(timeout := 300000, do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "no NmlCore") -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_main.solo_ai_slots = {2: true}
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	var bird := _bearer(2, "Zeppelins", 11.0)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Warriors", "models": 5, "x_in": 6.0}, true), {})
	_main.solo_controller.last_move_paths = _legs(0.0, 11.0)
	var from: int = _main.battle_log.entries().size()
	var rng0: int = _main._tray_rng.state
	await _main._solo_apply_strafing(bird)
	var text := "\n".join(_main.battle_log.entries().slice(from).map(func(e: Dictionary) -> String: return str(e["text"])))
	assert_str(text).override_failure_message(text).contains("Crossing Strike: Zeppelins passes over Warriors — the rules core cannot resolve this attack (the rules core did not take this activation), it is held")
	assert_str(text).not_contains("the table paid")
	assert_int(_main._tray_rng.state).override_failure_message("a die was rolled for a held strike").is_equal(rng0)
	assert_int(foe.get_alive_count()).is_equal(5)


## A PLAYER's bearer moved over an enemy still attacks: the player's own mandatory strike stays on the table until the human side
## moves to the rules core. RED: hold the strike for every bearer (no `_solo_is_ai_unit` check).
@warning_ignore('unused_parameter')
func test_a_players_bearer_moved_over_an_enemy_still_attacks(timeout := 300000, do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "no NmlCore") -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_main.solo_ai_slots = {2: true}
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	var bird := _bearer(1, "Zeppelins", 11.0)
	ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Warriors", "models": 5, "x_in": 6.0}, true), {})
	var from: int = _main.battle_log.entries().size()
	_main.seed_tray_rng(7)
	var rng0: int = _main._tray_rng.state
	var trails: Array = _legs(0.0, 11.0).map(func(l: Dictionary) -> Array: return l["path"])
	await _main._solo_apply_strafing(bird, trails)
	var text := "\n".join(_main.battle_log.entries().slice(from).map(func(e: Dictionary) -> String: return str(e["text"])))
	assert_str(text).override_failure_message(text).contains("Crossing Strike: Zeppelins passes over Warriors — attacks it as if shooting")
	assert_str(text).not_contains("it is held")
	assert_int(_main._tray_rng.state).override_failure_message("the player's strike rolled no die:\n%s" % text).is_not_equal(rng0)
