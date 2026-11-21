extends GdUnitTestSuite
## One core P4.D-48: the AI charge door. A plain AI charge (no rule on either side, an AI defender) hands the activation to the
## core's step path instead of `_run_ai_melee`: the core lands the charge (`charge_move` from the board before the move, the snap, the pile-in), the
## strikes, the melee result, the loser's morale and the consolidation; the table lands Shaken, Fatigue and the end positions
## from the delta. Seed for seed against the table's own `_run_ai_melee` (the door off): survivors, wounds, positions (within
## 0.01"), Shaken, Fatigue, the tray RNG after and the battle-log lines in order.
## Real: the main scene, NmlCore, the planner's own charge move (`SoloController._charge_move`), `_run_ai_melee`.
## Constructed: OPR units (ParityTable) at both seats AI. NML_ONE_CORE_SEEDS overrides 16.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.3, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const BLADE := {"name": "Blade", "range_in": 0, "attacks": 2, "count": 10, "rules": []}

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
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	_main._solo_auto_saves = true
	_main._solo_fast = true
	_main._autosave_controller.set_lesson_paused(true)
	CoreActivation._env = 1
	CoreActivation._charge_env = 1
	CoreActivation.ai_charges = 0


func after_test() -> void:
	CoreActivation._charge_landing = false
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	CoreActivation._charge_env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One AI charge pair (table vs door): `Att` (seat 2, `models`) from x = 0 at `Def` (seat 1, `foe_models`) at `gap_in`.
func _pair(s: int, models: int, foe_models: int, gap_in: float, foe_attacks := 1) -> Dictionary:
	var att_fn := func() -> GameUnit:
		return ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": models, "x_in": 0.0}, true),
			BLADE.merged({"count": models}))
	var foe_fn := func() -> GameUnit:
		var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": foe_models, "x_in": gap_in, "z_step_in": 1.4}, true),
			BLADE.merged({"count": foe_models, "attacks": foe_attacks}))
		# Ties in the casualty pick break on the last float bit (table node vs core): nudge every defender by its own few thousandths.
		for i in foe.models.size():
			(foe.models[i] as ModelInstance).node.global_position.z += float((i * 7) % 5) * 0.0001
		return foe
	return await RosterSweep.charge(_main, att_fn, foe_fn, s)


func _sweep(name: String, models: int, foe_models: int, gap_in: float, foe_attacks := 1) -> void:
	var seeds := int(OS.get_environment("NML_ONE_CORE_SEEDS")) if OS.has_environment("NML_ONE_CORE_SEEDS") else 16
	var bad: Array = []
	var hurt := 0
	for s in seeds:
		var res := await _pair(s, models, foe_models, gap_in, foe_attacks)
		hurt += foe_models - int(res["core"]["alive"][1])
		if not bool(res["taken"]):
			bad.append("seed %d: the door took it %d times (table run %d)" % [s, res["core"]["core"], res["table"]["core"]])
		for d in res["diffs"]:
			bad.append("seed %d: %s" % [s, d])
	print("CHARGE_DOOR %s seeds=%d hurt=%d mismatches=%d" % [name, seeds, hurt, bad.size()])
	assert_int(hurt).override_failure_message("no seed hurt the defender: the sweep compares nothing").is_greater(0)
	assert_array(bad).override_failure_message("core vs table:\n" + "\n".join(bad.slice(0, 8))).is_empty()


## Both sides survive: the strikes, the strike back, the result, the loser's morale and the charger's 1" step back.
func test_a_plain_charge_both_sides_standing() -> void:
	await _sweep("standing", 5, 8, 7.0)


## A small defender the charge wipes out: the winner's consolidation move.
func test_a_plain_charge_that_wipes_the_defender_out() -> void:
	await _sweep("wipe", 8, 2, 6.0)


## Plan E step 20 (the melee C-19 flip): with the env unset the door is ON (`NML_ONE_CORE_CHARGE=0` / `off` is the way back for one release) and reads the
## deny file: an AP charger (the allow file refuses it) is taken. RED before the flip: the switch defaulted OFF and the slice was the allow file.
func test_an_ap_charger_is_taken_by_default_and_the_env_is_the_way_back() -> void:
	var before := OS.get_environment("NML_ONE_CORE_CHARGE")
	for case in [["", true], ["1", true], ["0", false], ["off", false], ["OFF", false]]:
		OS.set_environment("NML_ONE_CORE_CHARGE", str(case[0]))
		CoreActivation._charge_env = -1
		assert_bool(CoreActivation.charge_door_enabled()).override_failure_message("NML_ONE_CORE_CHARGE='%s'" % case[0]).is_equal(bool(case[1]))
	OS.set_environment("NML_ONE_CORE_CHARGE", "")
	CoreActivation._charge_env = -1
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 5, "x_in": 0.0}, true), BLADE.merged({"count": 5, "rules": ["AP(1)"]}, true))
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 8, "x_in": 7.0}, true), BLADE.merged({"count": 8, "attacks": 1}, true))
	_main._solo_core_ai_h = CoreActivation.capture(_main)
	var report := {"unit": att, "target": foe, "action": AiDecision.Action.CHARGE, "moved": true}
	assert_bool(CoreActivation.takes_ai_charge(_main, att, report)).override_failure_message("an AP charger is taken by default").is_true()
	_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
	_main._solo_core_ai_h = 0
	RosterSweep.free_units(_main, [att, foe])
	OS.set_environment("NML_ONE_CORE_CHARGE", before)
	CoreActivation._charge_env = -1


## A 10-model unit on either side stays on the table (`MELEE_MAX_MODELS`, the known consolidation difference of #3025): the
## door does not take it. RED: drop the size clause from `takes_ai_charge` -> the door takes it.
func test_a_ten_model_unit_stays_on_the_table() -> void:
	for sides in [[10, 2], [5, 10]]:
		var res := await _pair(0, sides[0], sides[1], 6.0)
		assert_int(int(res["core"]["core"])).override_failure_message("the door took a %d v %d charge" % sides).is_equal(0)
		assert_bool(bool(res["taken"])).is_false()
		assert_array(res["refusals"]).contains(["size"])


## A charge under a rules epoch older than 73 stays on the table: the core's result line is the 3.6 one ("took"), the table's older one says "dealt"
## (the flip's red `g4r3_t1_target_selfwound_test` > `test_the_result_line_is_unchanged_at_epoch_72`). From 73 the door takes it. RED: drop the clause -> `[]` at 72.
func test_a_charge_under_an_old_epoch_stays_on_the_table() -> void:
	var before: int = AiActRecorder.rules_epoch
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 5, "x_in": 0.0}, true), BLADE.merged({"count": 5}, true))
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 8, "x_in": 7.0}, true), BLADE.merged({"count": 8, "attacks": 1}, true))
	var report := {"unit": att, "target": foe, "action": AiDecision.Action.CHARGE, "moved": true}
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36 - 1
	assert_array(CoreActivation.charge_refusals(_main, att, report, true)).override_failure_message("epoch 72 stays on the table").is_equal(["old_epoch"])
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_array(CoreActivation.charge_refusals(_main, att, report, true)).override_failure_message("epoch 73 is the door's").is_empty()
	AiActRecorder.rules_epoch = before
	assert_array(CoreActivation.charge_refusals(_main, att, report, true)).override_failure_message("the current epoch is the door's").is_empty()
	RosterSweep.free_units(_main, [att, foe])
