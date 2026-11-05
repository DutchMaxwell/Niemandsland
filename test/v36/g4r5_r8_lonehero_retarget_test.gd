extends GdUnitTestSuite
## G4R5 R8 (PARITY_DIAG_1105_R4 2.11, gf_1000_net_042 act 14): a unit the casualties tore out of coherency spends
## its activation on the Regroup rule, and a Regroup may still shoot. The post-move retarget (`best_shoot_target_now`)
## skipped every destroyed host and every attached hero, so a chain whose host is dead and whose joined hero lives
## (the hero IS the unit now) was invisible to it and the Regroup fired nothing. From EPOCH_73_V36 the retarget sees
## the lone hero through its host chain, like the volley's own target scan does. Below 73 the old blindness stays.
## Driven through the real activation entry (`_solo_activate_one_ai`) over main.tscn.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const REACH := 24

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
	_main.solo_ai_slots = {1: true, 2: true}   # both seats AI: saves auto-resolve, no dialog
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


## The AI's torn gun line: two models 3.9" apart (past the 1" chain link), a 24" rifle each.
func _gunners() -> GameUnit:
	var u := E2EBoot.make_unit(_main, 2, "Gunners", [Vector3.ZERO, Vector3(0.10, 0.0, 0.0)])
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["special_rules"] = []
	var rifle := OPRApiClient.OPRWeapon.new()
	rifle.name = "Rifle"
	rifle.range_value = REACH
	rifle.attacks = 3
	rifle.count = 1
	var opr := OPRApiClient.OPRUnit.new()
	opr.weapons.append(rifle)
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A human chain 10" away whose only host model is dead and whose joined hero lives.
func _lone_hero_chain() -> GameUnit:
	var host := E2EBoot.make_unit(_main, 1, "Cultists", [Vector3(10.0 * INCH, 0.0, 0.0)])
	(host.models[0] as ModelInstance).is_alive = false
	var hero := E2EBoot.make_unit(_main, 1, "Champion", [Vector3(10.5 * INCH, 0.0, 0.0)])
	for u in [host, hero]:
		(u as GameUnit).unit_properties["game_system"] = "gf"
		(u as GameUnit).unit_properties["special_rules"] = []
		_main.opr_army_manager.game_units[(u as GameUnit).unit_id] = u
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	return host


func test_the_regroup_retarget_sees_a_lone_hero_at_73(timeout := 60000) -> void:
	var gunners := _gunners()
	var host := _lone_hero_chain()
	assert_bool(_main.solo_controller.unit_coherent_now(gunners)).is_false()
	assert_object(_main.solo_controller.best_shoot_target_now(gunners, false)) \
		.override_failure_message("the retarget returned no unit - the lone hero is invisible").is_same(host)
	var done: GameUnit = await _main._solo_activate_one_ai()
	assert_object(done).is_equal(gunners)
	var text := _log_text()
	assert_str(text).contains("Regroup: Gunners starts its activation out of coherency")
	assert_str(text) \
		.override_failure_message("the Regroup fired nothing at the lone hero (log: %s)" % text.strip_edges()) \
		.contains("Gunners fires at Cultists")
	assert_str(text) \
		.override_failure_message("rules-must-log: the shot names the Hero rule (log: %s)" % text.strip_edges()) \
		.contains("Hero: Champion is the unit now")
	await E2EBoot.settle(get_tree())


## Control: below 73 the recorded corpus keeps the blind retarget - no shot, byte for byte.
func test_the_epoch_72_control_keeps_the_blind_retarget(timeout := 60000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var gunners := _gunners()
	_lone_hero_chain()
	assert_object(_main.solo_controller.best_shoot_target_now(gunners, false)).is_null()
	var done: GameUnit = await _main._solo_activate_one_ai()
	assert_object(done).is_equal(gunners)
	assert_str(_log_text()).not_contains("Gunners fires at")
	await E2EBoot.settle(get_tree())
