extends GdUnitTestSuite
## One core P4.0-4a: the (b) rows of the state-delta inventory are red on purpose.
##
## `buffs` is the one (b) row: a plain activation spends the once record in the core
## (`sim.rs:10594`, `spend_exchange_wounded`), but the live capture never sends the ledger
## (`plain.rs:493`) and the table's own spend (`main.gd:6161`, `_solo_spend_once_mods`) is not
## called on the core path. The record therefore survives, and the next table volley applies the
## once buff a second time. This case fails on current main; it is committed skipped
## (`skip_reason := "P4.0-4 defect, red on purpose"`) until the split is fixed.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main.solo_ai_slots = {}
	CoreActivation._env = 1   # the flag ON for every case


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## The fixture of core_activation_test.gd: one plain 10-model shooter and one plain 5-model target.
func _volley_units() -> Array:
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main._solo_batch = true
	_main._solo_auto_saves = true
	var side := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
		"faction_folder": "robot_legions", "rules": []}
	var att := ParityTable._make_unit(_main, side.merged({"player": 2, "name": "Att", "models": 10, "x_in": 0.0}),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []})
	var foe := ParityTable._make_unit(_main, side.merged({"player": 1, "name": "Def", "models": 5, "x_in": 12.0}), {})
	return [att, foe]


func test_red_a_once_buff_is_not_spent_by_the_core_activation(do_skip := true,
		skip_reason := "P4.0-4 defect, red on purpose") -> void:
	var units := _volley_units()
	var att: GameUnit = units[0]
	var foe: GameUnit = units[1]
	var rec := {"spell": "Fury", "duration": "once", "hit_mod": 1, "scope": "shooting"}
	_main._solo_spell_mods[att.get_instance_id()] = [rec]
	_main.seed_tray_rng(7)
	var t: Array = [{"t": "begin"}, {"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": foe.unit_id}]
	var r: Dictionary = await CoreActivation.drive(_main, CoreActivation.capture(_main), att, t, true)
	assert_str(str(r["step"])).override_failure_message("the core's answer: %s" % r).is_equal("done")
	assert_array(_main._solo_spell_mods.get(att.get_instance_id(), [])) \
		.override_failure_message("the once buff was spent on the core path").is_empty()
