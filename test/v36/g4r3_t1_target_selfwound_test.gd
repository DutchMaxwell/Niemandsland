extends GdUnitTestSuite
## AI-G4 round 3, row R3-T1 (rules 3.6, EPOCH_73_V36): the melee tally adds the TARGET's own pre-melee wounds
## ("self-inflicted") to the charger's score. The table read the target's ACTIVATION counter after the strikes;
## a target that already acted this round keeps its snapshot, so the fight's own wounds counted a second time
## and flipped the verdict (a draw read as a win, a morale die the core never rolls). The charge now takes the
## target's wound baseline at the charger's move and reads the delta BEFORE the strikes.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

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
	_main.solo_ai_slots = {1: true, 2: true}   # both seats AI: the target's saves auto-roll, no dialog
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2           # pid 2 is the charger's seat: its unit activates next
	_main.solo_controller.human_slot = 1        # and pid 1 is its enemy
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, x_in: float, attacks: int = 0) -> GameUnit:
	var unit := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x_in * INCH, 0, 0)])
	var model := unit.models[0] as ModelInstance
	model.model_index = 0
	model.wounds_max = 10
	model.wounds_current = 10
	var source := OPRApiClient.OPRUnit.new()
	if attacks > 0:
		var weapon := OPRApiClient.OPRWeapon.new()
		weapon.name = "Club"
		weapon.range_value = 0
		weapon.attacks = attacks
		source.weapons = [weapon]
	unit.source_type = "opr"
	unit.source_data = source
	_main.opr_army_manager.game_units[unit.unit_id] = unit
	return unit


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The REAL charge: the planner picks the AI unit's action, the table walks the move (the target's baseline
## is taken there), resolves the strikes and the result line. The target acted earlier this round (its
## activation snapshot is open) and has lost nothing since, so every wound it loses in the fight is the
## charger's strike, never its own.
func _real_charge(epoch: int) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	var charger := _unit(2, "Charger", 0.0, 10)   # a real Club profile
	var target := _unit(1, "Target", 8.0)         # inside the 12" charge reach, unarmed (no strike-back)
	await _main.begin_activation(target)          # "acted earlier": the snapshot stays open all round
	_main.seed_tray_rng(7)
	await _main._solo_activate_one_ai()
	var lost: int = 10 - (target.models[0] as ModelInstance).wounds_current
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	return {"text": text, "lost": lost}


func test_a_target_that_acted_earlier_takes_only_the_strike_wounds_at_epoch_73(timeout := 60000) -> void:
	var r: Dictionary = await _real_charge(AiActRecorder.EPOCH_73_V36)
	var text := str(r["text"])
	assert_str(text).contains("Melee result:")   # the charge really reached combat
	assert_int(int(r["lost"])).is_greater(0)      # the scenario bites: the strikes did wound the target
	assert_str(text).contains("Target took %d — " % int(r["lost"]))
	assert_str(text).not_contains("self-inflicted")


## Below 73 the comparison stays dealt-only, so the result line is the old one (byte-identical).
func test_the_result_line_is_unchanged_at_epoch_72() -> void:
	var r: Dictionary = await _real_charge(AiActRecorder.EPOCH_73_V36 - 1)
	assert_int(int(r["lost"])).is_greater(0)
	assert_str(str(r["text"])).contains("Melee result: Charger dealt %d, Target dealt 0" % int(r["lost"]))


## Control: a wound the target takes AFTER the charger's move and BEFORE the strikes (a spell) is still the
## target's pre-melee wound and keeps its "(self-inflicted: 1)" reading. The baseline rides on the charge report
## the activation fills at the move; here it is set to the target's wounds at that moment.
func test_a_wound_taken_between_the_move_and_the_strikes_still_counts_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var charger := _unit(2, "Charger", 0.0)
	var target := _unit(1, "Target", 1.0)
	await _main.begin_activation(target)
	var baseline: int = (target.models[0] as ModelInstance).wounds_current
	(target.models[0] as ModelInstance).wounds_current -= 1   # the spell lands before the strikes
	_main.seed_tray_rng(7)
	await _main._run_ai_melee({"unit": charger, "target": target, "charge_from_in": 1.0,
		"dangerous_wounds_taken": 0, "target_wounds_start": baseline})
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	assert_str(text).contains("Target took 1 (self-inflicted: 1)")
