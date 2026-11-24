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
	SoloHarness.start(_main, [1, 2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	SoloHarness.auto_saves(_main)
	SoloHarness.fast(_main)
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


## Plan E-25: an AI charge at a HUMAN defender is the door's too: the core asks the strike-back (E-24) and `drive` answers it with
## the table's own prompt, asked once; `strike` and `hold` both land, the one line is said once. RED: the `human_defender`
## clause back in `charge_refusals`, or no probe in `pending_choices` -> no prompt, the charger always struck back.
func test_a_human_defender_answers_the_strike_back_once() -> void:
	_main.solo_ai_slots = {2: true}
	for answer in [true, false]:
		var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 5, "x_in": 0.0}, true), BLADE.merged({"count": 5}, true))
		var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 8, "x_in": 7.0}, true), BLADE.merged({"count": 8, "attacks": 1}, true))
		att.unit_properties["moved_round"] = 1   # the AI body stamps it before the hand-over (roster sweep)
		var report := {"unit": att, "target": foe, "action": AiDecision.Action.CHARGE, "moved": true}
		assert_array(CoreActivation.charge_refusals(_main, att, report)).override_failure_message("a human defender is the door's").is_empty()
		var n: int = _main.battle_log.entries().size()
		var alive_before := att.get_alive_models().size()
		CoreActivation.reset_all(_main)
		var h := CoreActivation.capture(_main)
		_main._solo_core_ai_h = h
		var out: Array = []
		(func() -> void: out.append(await CoreActivation.run_ai_charge(_main, att, report))).call()
		var asked := 0
		for _i in 600:
			if not out.is_empty():
				break
			for node: Node in _main.get_tree().root.find_children("*", "", true, false):
				if node is PromptCard and not node.is_queued_for_deletion() and (node as PromptCard)._outcome.is_empty():
					asked += 1
					(node as PromptCard).resolve(answer)
			await get_tree().process_frame
		assert_bool(not out.is_empty() and bool(out[0])).override_failure_message("the door did not resolve the charge").is_true()
		assert_int(asked).override_failure_message("the strike-back prompt must come up exactly once").is_equal(1)
		var text := ""
		for i in range(n, _main.battle_log.entries().size()):
			text += str((_main.battle_log.entries()[i] as Dictionary)["text"]) + "\n"
		var line := "Def strikes back" if answer else "Def holds — no strike back"
		assert_int(text.count(line)).override_failure_message("'%s' once in:\n%s" % [line, text]).is_equal(1)
		if not answer:
			assert_int(att.get_alive_models().size()).override_failure_message("a held strike-back kills nobody").is_equal(alive_before)
		_main._solo_core_ai_h = 0
		_main.solo_controller._core_node_ready().release(h)
		RosterSweep.free_units(_main, [att, foe])
