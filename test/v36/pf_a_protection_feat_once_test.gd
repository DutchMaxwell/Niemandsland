extends GdUnitTestSuite
## Rules 3.6, fix PF-a: "Protection Feat" (army-book rule, Robot Legions / Saurian Starhosts / Saurians 3.6.0) is
## usable ONCE PER GAME: when the unit takes wounds and most of its models have the rule, roll one die per wound,
## each 5+ ignores it. The registry entry carries `uses_per_game: 1`; the ignore-wounds path now reads it from
## EPOCH_73_V36 (the spent flag lives on the bearer's props, like the Precision Feat's latch). Every use and every
## refusal writes a battle log line; epoch 72 replays the unlimited roll.
## Driven through the real AI volley (_run_ai_shooting) over main.tscn, twice at the same Protection Feat unit.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const FEAT_ROLL := "Protection Feat di"
const FEAT_SPENT := "Protection Feat: Warriors spends its once-per-game ignore roll"
const FEAT_REFUSED := "Protection Feat: Warriors already used it this game — no ignore roll"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
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
	RulesRegistry.reset_cache()


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	RulesRegistry.reset_cache()


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _gunners() -> GameUnit:
	var u := E2EBoot.make_unit(_main, 2, "Gunners", [Vector3.ZERO, Vector3(0.02, 0.0, 0.0)])
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["special_rules"] = []
	u.unit_properties["quality"] = 2
	var rifle := OPRApiClient.OPRWeapon.new()
	rifle.name = "Rifle"
	rifle.range_value = 24
	rifle.attacks = 30
	rifle.count = 1
	var opr := OPRApiClient.OPRUnit.new()
	opr.weapons.append(rifle)
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A five-model Robot Legions squad 10" away; every model carries Protection Feat, nobody can die in two volleys.
func _feat_squad() -> GameUnit:
	var pos: Array = []
	for i in 5:
		pos.append(Vector3((10.0 + 1.2 * i) * INCH, 0.0, 0.0))
	var u := E2EBoot.make_unit(_main, 1, "Warriors", pos)
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "robot_legions"
	u.unit_properties["special_rules"] = ["Protection Feat"]
	u.unit_properties["defense"] = 6
	for m in u.models:
		(m as ModelInstance).wounds_max = 200
		(m as ModelInstance).wounds_current = 200
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _feat_rolls(text: String) -> int:
	return text.count(FEAT_ROLL)


## Two wounding volleys at the Feat unit; returns [first volley log, second volley log].
func _two_volleys(epoch: int) -> Array:
	AiActRecorder.rules_epoch = epoch
	var gunners := _gunners()
	_feat_squad()
	_main._tray_rng.seed = 11
	await _main._run_ai_shooting(ActIntent.blank_report(gunners))
	var first := _log_text()
	_main.opr_army_manager.current_round = 2
	_main._tray_rng.seed = 12
	await _main._run_ai_shooting(ActIntent.blank_report(gunners))
	return [first, _log_text().substr(first.length())]


## PF-a: the first wounding volley uses the Feat (one roll at 5+, and says it is spent); a second wounding volley
## later in the same game finds it spent - at most ONE Protection Feat roll over the whole game - and says so.
func test_pf_a_protection_feat_rolls_at_most_once_per_game(timeout := 90000) -> void:
	var logs := await _two_volleys(AiActRecorder.EPOCH_73_V36)
	var first: String = logs[0]
	var second: String = logs[1]
	assert_int(_feat_rolls(first)) \
		.override_failure_message("fixture: the first volley must wound and roll the Feat once (log: %s)" % first) \
		.is_equal(1)
	assert_str(first).override_failure_message("the Feat ignores on 5+ (log: %s)" % first).contains("(5+)")
	assert_str(first).override_failure_message("the first use is not logged as spent (log: %s)" % first) \
		.contains(FEAT_SPENT)
	assert_str(second).override_failure_message("fixture: the second volley must wound too (log: %s)" % second) \
		.contains("Warriors takes")
	assert_int(_feat_rolls(first + second)) \
		.override_failure_message("PF-a: Protection Feat rolled %d times in one game (second volley log: %s)" % [
			_feat_rolls(first + second), second]) \
		.is_less_equal(1)
	assert_str(second).override_failure_message("PF-a: the refused second use is not logged (log: %s)" % second) \
		.contains(FEAT_REFUSED)
	assert_str(second).override_failure_message("a refused Feat must not also spend (log: %s)" % second) \
		.not_contains(FEAT_SPENT)
	await E2EBoot.settle(get_tree())


## Epoch 72 replays the unlimited Feat: both volleys roll it, and nothing is logged as spent or refused.
func test_pf_a_epoch_72_keeps_the_unlimited_feat(timeout := 90000) -> void:
	var logs := await _two_volleys(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	assert_int(_feat_rolls(logs[0] + logs[1])).override_failure_message("epoch 72 changed the Feat (log: %s)" % logs[1]) \
		.is_equal(2)
	assert_str(logs[0] + logs[1]).not_contains(FEAT_SPENT).not_contains(FEAT_REFUSED)
	await E2EBoot.settle(get_tree())
