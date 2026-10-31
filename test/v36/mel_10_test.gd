extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-10: from the rules 3.6 epoch (73) the melee loser is the unit that TOOK more
## wounds in the whole activation. The charger's Dangerous wounds on its charge move and Hazardous
## self-wounds count against the unit that took them; Fear(X) lifts the enemy's tally. At 72 the loser
## stays the unit that dealt fewer wounds. Both legs go through the real AI charge melee.

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
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, x: float, attacks: int, rules: Array = [], weapon_rules: Array = []) -> GameUnit:
	var unit := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x * INCH, 0, 0)])
	(unit.models[0] as ModelInstance).model_index = 0
	unit.unit_properties["special_rules"] = rules
	var source := OPRApiClient.OPRUnit.new()
	if attacks > 0:
		var weapon := OPRApiClient.OPRWeapon.new()
		weapon.name = "Club"
		weapon.range_value = 0
		weapon.attacks = attacks
		for r in weapon_rules:
			weapon.special_rules.append(str(r))
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


## The AI charge melee of two unarmed units: no die decides the strikes, so the verdict is carried by the
## self-wounds the charge move already cost the charger (`report["dangerous_wounds_taken"]`) and Fear alone.
func _unarmed_charge(epoch: int, charger_rules: Array, defender_rules: Array, dangerous_taken: int) -> String:
	AiActRecorder.rules_epoch = epoch
	var charger := _unit(2, "Charger", 0.0, 0, charger_rules)
	var defender := _unit(1, "Defender", 1.0, 0, defender_rules)
	_main.seed_tray_rng(7)
	await _main._run_ai_melee({"unit": charger, "target": defender, "charge_from_in": 1.0,
		"dangerous_wounds_taken": dangerous_taken})
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	return text


func test_dangerous_wounds_on_the_charge_move_lose_the_melee_at_epoch_73() -> void:
	var text: String = await _unarmed_charge(AiActRecorder.EPOCH_73_V36, [], [], 3)
	assert_str(text).contains("Charger took 3")
	assert_str(text).contains("Defender took 0")
	assert_str(text).contains("Charger loses the melee")


func test_dangerous_wounds_on_the_charge_move_are_ignored_at_epoch_72() -> void:
	var text: String = await _unarmed_charge(AiActRecorder.EPOCH_73_V36 - 1, [], [], 3)
	assert_str(text).contains("a draw — no morale test")
	assert_str(text).not_contains("Charger loses the melee")
	assert_str(text).not_contains("took 3")


func test_a_tie_in_wounds_taken_tests_nobody_at_epoch_73() -> void:
	# Fear(2) lifts the DEFENDER's taken to 2 and the charger took 2 from Dangerous terrain: 2 against 2.
	var text: String = await _unarmed_charge(AiActRecorder.EPOCH_73_V36, ["Fear(2)"], [], 2)
	assert_str(text).contains("a draw — no morale test")


func test_the_same_fear_charger_still_wins_on_dealt_wounds_at_epoch_72() -> void:
	var text: String = await _unarmed_charge(AiActRecorder.EPOCH_73_V36 - 1, ["Fear(2)"], [], 2)
	assert_str(text).contains("Defender loses the melee")


func test_defender_fear_still_counts_against_the_charger_at_epoch_73() -> void:
	var text: String = await _unarmed_charge(AiActRecorder.EPOCH_73_V36, [], ["Fear(2)"], 0)
	assert_str(text).contains("Charger loses the melee")


## Hazardous: every unmodified 1 to hit wounds the striker's own unit. At 73 those self-wounds are wounds the
## unit TOOK, so the enemy's score rises by them; at 72 they never entered the comparison. Driven at the
## tally itself because no die can make a Hazardous melee deterministic (hits and ones come from one roll).
func _hazard_scores(epoch: int) -> Array:
	AiActRecorder.rules_epoch = epoch
	var charger := _unit(2, "Charger", 0.0, 0)
	(charger.models[0] as ModelInstance).wounds_current = 10
	var defender := _unit(1, "Defender", 1.0, 0)
	await _main._solo_hazardous_self_wounds(charger, {"hazardous": true}, [1, 4, 1, 6])
	assert_bool(_main.has_method("_solo_melee_scores")).is_true()
	if not _main.has_method("_solo_melee_scores"):
		return [0, 0]
	return _main.call("_solo_melee_scores", charger, 0, defender, 0)


func test_hazardous_self_wounds_raise_the_enemys_score_at_epoch_73() -> void:
	var scores: Array = await _hazard_scores(AiActRecorder.EPOCH_73_V36)
	assert_array(scores).is_equal([0, 2])   # [charger, defender]: the charger took 2 of its own, the defender 0


func test_hazardous_self_wounds_are_ignored_at_epoch_72() -> void:
	var scores: Array = await _hazard_scores(AiActRecorder.EPOCH_73_V36 - 1)
	assert_array(scores).is_equal([0, 0])
