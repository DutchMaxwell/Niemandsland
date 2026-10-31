extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-10h: MEL-10 fixed the AI path (the charger's Dangerous-terrain wounds on its
## charge move count in the melee-loser comparison). This row mirrors it for the HUMAN charger: the
## activation-start wound snapshot shows the wounds the unit took before the melee, and at epoch 73 the
## enemy's taken tally rises by them. At 72 the snapshot is ignored and today's winner stands.

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
	_main.solo_ai_slots = {2: true}   # pid 1 is the human, pid 2 the AI defender
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, x: float, attacks: int = 0) -> GameUnit:
	var unit := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x * INCH, 0, 0)])
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


## The human charge's activation start snapshots the wounds, then the Dangerous-terrain move costs 2.
## Two unarmed units carry the verdict through the snapshot alone.
func _human_charge(epoch: int, move_wounds: int) -> String:
	AiActRecorder.rules_epoch = epoch
	var charger := _unit(1, "Charger", 0.0)
	var defender := _unit(2, "Defender", 1.0)
	await _main.begin_activation(charger)
	(charger.models[0] as ModelInstance).wounds_current -= move_wounds
	_main.seed_tray_rng(7)
	await _main._run_human_melee(charger, defender)
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	return text


func test_human_dangerous_wounds_on_the_charge_move_lose_the_melee_at_epoch_73() -> void:
	var text: String = await _human_charge(AiActRecorder.EPOCH_73_V36, 2)
	assert_str(text).contains("Charger took 2")
	assert_str(text).contains("Defender took 0")
	assert_str(text).contains("Charger loses the melee")


func test_human_dangerous_wounds_on_the_charge_move_are_ignored_at_epoch_72() -> void:
	var text: String = await _human_charge(AiActRecorder.EPOCH_73_V36 - 1, 2)
	assert_str(text).contains("a draw — no morale test")
	assert_str(text).not_contains("Charger loses the melee")
	assert_str(text).not_contains("took 2")


func test_a_second_activation_door_does_not_rebaseline_the_snapshot() -> void:
	# _run_player_intent opens begin_activation before the move and _run_human_attack opens it again
	# before the strikes; the second door must keep the activation-start snapshot.
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var charger := _unit(1, "Charger", 0.0)
	await _main.begin_activation(charger)
	(charger.models[0] as ModelInstance).wounds_current -= 2
	await _main.begin_activation(charger)
	assert_int(_main._solo_activation_self_wounds(charger)).is_equal(2)


## The RED scenario in words: the human deals 3 strike wounds and takes 2 back, so today it wins.
## Its own 2 Dangerous move wounds lift the enemy's taken tally to 4 at 73 — the human loses anyway.
func _scores(epoch: int) -> Array:
	AiActRecorder.rules_epoch = epoch
	var charger := _unit(1, "Charger", 0.0)
	var defender := _unit(2, "Defender", 1.0)
	await _main.begin_activation(charger)
	(charger.models[0] as ModelInstance).wounds_current -= 2
	var self_wounds: int = _main._solo_activation_self_wounds(charger)
	return _main._solo_melee_scores(charger, 3, defender, 2, self_wounds)


func test_a_charger_that_dealt_more_strikes_still_loses_with_its_move_wounds_at_epoch_73() -> void:
	var scores: Array = await _scores(AiActRecorder.EPOCH_73_V36)
	assert_array(scores).is_equal([3, 4])   # [human, AI]: the AI took 2 dealt + the human's 2 move wounds


func test_the_same_charger_still_wins_on_struck_wounds_at_epoch_72() -> void:
	var scores: Array = await _scores(AiActRecorder.EPOCH_73_V36 - 1)
	assert_array(scores).is_equal([3, 2])
