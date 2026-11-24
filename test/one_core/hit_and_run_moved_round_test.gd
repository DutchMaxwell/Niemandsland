extends GdUnitTestSuite
## DS-HR1: a unit that steps away under Hit & Run has MOVED this round. The core stamps `moved_round` on an actual
## step (sim.rs `tray_hit_and_run`), so the table must too: after a Harassing unit holds and shoots a target that
## survives, its post-shot step runs and the ledger names the round. The activation tail is the body's own pair of
## calls (`_run_ai_shooting` then `solo_controller.hit_and_run_move`, main.gd `_solo_activate_one_ai_body`), driven
## here without the planner's pick so the HOLD + shoot is fixed.
## Real: the main scene, the table's volley, the tray, the Hit & Run step and `AiActRecorder._ledger_of`.
## Constructed: parity units (ParityTable), the seats and the batch settings the sweep arms.
## RED: without the `moved_round` stamp the ledger has no key (the core exports `moved_round` = the round).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "aof",
	"faction_folder": "dark_elves", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 3, "rules": []}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [1, 2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	SoloHarness.auto_saves(_main)
	CoreActivation._env = 0


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A Harassing shooter holds and shoots a target that survives, then takes its post-shot step (the body's tail).
func _hold_shoot_and_step(s: int) -> Dictionary:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 3, "x_in": -7.0,
		"rules": ["Harassing"]}, true), RIFLE)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 20, "x_in": 7.0}, true), {})
	_main.seed_tray_rng(s)
	_main._solo_core_ai_h = 0
	await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
	var survivors := foe.get_alive_count()
	var stepped: bool = _main.solo_controller.hit_and_run_move(att, true)
	var ledger := AiActRecorder._ledger_of(att)
	var out := {"survivors": survivors, "stepped": stepped, "ledger": ledger,
		"moved_round": int(ledger.get("moved_round", -1)),
		"round": _main.opr_army_manager.current_round,
		"hit_and_run_round": int((att.unit_properties as Dictionary).get("hit_and_run_round", -1))}
	_main.opr_army_manager.game_units.erase(att.unit_id)
	_main.opr_army_manager.game_units.erase(foe.unit_id)
	for u in [att, foe]:
		for m in (u as GameUnit).models:
			var nd: Node = (m as ModelInstance).node
			if nd != null and is_instance_valid(nd):
				nd.free()
	await get_tree().process_frame
	return out


func test_a_harassing_step_after_a_surviving_volley_stamps_moved_round() -> void:
	var r := await _hold_shoot_and_step(3)
	assert_int(int(r["survivors"])).override_failure_message("the target must survive the volley").is_greater(0)
	assert_bool(bool(r["stepped"])).override_failure_message("the Harassing unit did not step").is_true()
	assert_int(int(r["hit_and_run_round"])).override_failure_message("the once-per-round stamp").is_equal(int(r["round"]))
	assert_int(int(r["moved_round"])) \
		.override_failure_message("DS-HR1: a unit that stepped away under Hit & Run has moved this round, the ledger says -1") \
		.is_equal(int(r["round"]))
