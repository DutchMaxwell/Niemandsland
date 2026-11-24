extends GdUnitTestSuite
## The outcome toast of one plain AI volley, per seed, through the core door (`_run_ai_shooting` with the board captured): the
## sentence the player reads after a volley ("<target>: N hits -> M wounds land - <target> loses K models", singular forms
## included). It is UI, not parity text: the table and the door build it from the same `CoreActivation.volley_outcome`, and the
## three pins below are the sentences the table's own volley wrote for these seeds (step 23, epoch 75), so the door must reproduce
## them. Layout = test/parity/scenarios/shoot/plain.json (10 Att models with a Rifle 24" A1 vs 10 Def models 8" away, no rules);
## the target holds the AI seat, so its saves roll without a prompt. The battle-log wording is no longer pinned: under the parity
## ruling (D-PAR1) wording, order and labels are not compared. RED: any word changed in `volley_outcome`, or the door switched off.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SCENARIO := "res://test/parity/scenarios/shoot/plain.json"

## seed -> the outcome toast (found over seeds 0-399 at epoch 75).
const PINNED := {
	0: "Def: 7 hits → 5 wounds land — Def loses 5 models",   # plural counts, half strength, the morale test fails
	57: "Def: 7 hits → 7 wounds land — Def loses 7 models",   # no save holds, the morale test passes
	49: "Def: 1 hit → 1 wound land — Def loses 1 model",   # the singular forms: one hit, one wound, a model
}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [2])
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One seeded volley of the scenario through the core door (the board is captured first); returns the outcome toast it showed.
func _door_toast(sc: Dictionary, seed_value: int) -> String:
	var weapon: Dictionary = sc["weapon"]
	var att: GameUnit = ParityTable._make_unit(_main, sc["attacker"], weapon)
	var dfn: GameUnit = ParityTable._make_unit(_main, sc["defender"], {})
	_main.seed_tray_rng(seed_value)
	_main.solo_ai_slots = {1: true, 2: true}   # both seats AI: the saves roll without a prompt
	_main.solo_controller.ai_slot = int(sc["attacker"]["player"])
	_main.solo_controller.human_slot = int(sc["defender"]["player"])
	CoreActivation._env = 1
	var runs := CoreActivation.ai_runs
	_main._solo_core_ai_h = CoreActivation.capture(_main)
	await _main._run_ai_shooting(ActIntent.blank_report(att))
	assert_int(CoreActivation.ai_runs).override_failure_message("seed %d: the core did not take the volley (the table shot it)" % seed_value) \
		.is_equal(runs + 1)
	if _main._solo_core_ai_h != 0:
		_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
	_main._solo_core_ai_h = 0
	var got: String = _main._solo_toast.text
	for u in [att, dfn]:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			var nd: Node = (m as ModelInstance).node
			if nd != null and is_instance_valid(nd):
				nd.free()
	await _main.get_tree().process_frame
	return got


func test_a_plain_volley_shows_the_pinned_toast() -> void:
	var sc := JSON.parse_string(FileAccess.get_file_as_string(SCENARIO)) as Dictionary
	for s in PINNED:
		var got := await _door_toast(sc, int(s))
		assert_str(got).override_failure_message("seed %d: the outcome toast changed\n got %s\nwant %s" % [s, got, PINNED[s]]).is_equal(PINNED[s])
