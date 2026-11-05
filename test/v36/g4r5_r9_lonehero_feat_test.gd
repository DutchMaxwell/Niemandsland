extends GdUnitTestSuite
## G4R5 R9 (PARITY_DIAG_1105_R4 2.9, lead ruling D1, gf_1000_net_035 act 16): a joined hero whose host models are all dead
## IS the unit now, so its own ignore-wounds Feat (Protection Feat) counts: "most models carry it" is decided over the
## LIVING chain models, which is the hero alone. The core rolled the hero's Feat; the table read the rule list of the
## dead host, found no Feat and rolled nothing. From EPOCH_73_V36 the table reads the rule off the living hero.
## Driven through the real AI volley (`_run_ai_shooting`) over main.tscn: a real rifle profile fired at a lone hero
## built the way the game builds it (faction book, rule list, dead host). Below 73 the old silence stands.

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


## The AI's coherent gun line: a heavy rifle volley that wounds a Def 6+ hero for certain.
func _gunners() -> GameUnit:
	var u := E2EBoot.make_unit(_main, 2, "Gunners", [Vector3.ZERO, Vector3(0.02, 0.0, 0.0)])
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["special_rules"] = []
	u.unit_properties["quality"] = 2
	var rifle := OPRApiClient.OPRWeapon.new()
	rifle.name = "Rifle"
	rifle.range_value = REACH
	rifle.attacks = 30
	rifle.count = 1
	var opr := OPRApiClient.OPRUnit.new()
	opr.weapons.append(rifle)
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A human chain 10" away: the host's only model is dead, the joined hero lives and carries the Feat on its own list.
func _lone_hero_chain() -> void:
	var host := E2EBoot.make_unit(_main, 1, "Cultists", [Vector3(10.0 * INCH, 0.0, 0.0)])
	(host.models[0] as ModelInstance).is_alive = false
	var hero := E2EBoot.make_unit(_main, 1, "Champion", [Vector3(10.5 * INCH, 0.0, 0.0)])
	hero.unit_properties["defense"] = 6
	hero.models[0].wounds_max = 30
	hero.models[0].wounds_current = 30
	for u in [host, hero]:
		(u as GameUnit).unit_properties["game_system"] = "gf"
		(u as GameUnit).unit_properties["faction_folder"] = "saurian_starhosts"
		_main.opr_army_manager.game_units[(u as GameUnit).unit_id] = u
	host.unit_properties["special_rules"] = []
	hero.unit_properties["special_rules"] = ["Hero", "Protection Feat"]
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host


func test_a_lone_heros_own_protection_feat_rolls_at_73(timeout := 60000) -> void:
	var gunners := _gunners()
	_lone_hero_chain()
	_main._tray_rng.seed = 11
	await _main._run_ai_shooting(ActIntent.blank_report(gunners))
	var text := _log_text()
	assert_str(text).override_failure_message("the volley must wound the hero for the test to bite (log: %s)" % text.strip_edges()) \
		.contains("Hero: Champion is the unit now")
	assert_str(text) \
		.override_failure_message("rules-must-log: the lone hero's own Feat rolls and names itself (log: %s)" % text.strip_edges()) \
		.contains("Protection Feat di")
	await E2EBoot.settle(get_tree())


## Control: below 73 the recorded corpus keeps the dead host's rule list - no Feat die.
func test_the_epoch_72_control_rolls_no_feat(timeout := 60000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var gunners := _gunners()
	_lone_hero_chain()
	_main._tray_rng.seed = 11
	await _main._run_ai_shooting(ActIntent.blank_report(gunners))
	assert_str(_log_text()).not_contains("Protection Feat di")
	await E2EBoot.settle(get_tree())
