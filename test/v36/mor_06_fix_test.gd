extends GdUnitTestSuite
## MOR-06-fix: the Stealth-family "most models" list must carry Empyrean Spirit and Grounded Evasion
## from rules 3.6 on, the same names the core's STEALTH_MOST_MODELS twin already holds. Below the
## epoch the list stays out of the read and every alias answers the all-models way.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_epoch_before = AiActRecorder.rules_epoch
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RulesRegistry.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A squad of `models` carriers of `rule` with one joined hero that carries none of it.
func _squad_with_plain_hero(rule: String, models: int) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(Vector3(0.2 + 0.03 * i, 0.0, 0.2))
	var squad := E2EBoot.make_unit(_main, 1, "Squad", positions)
	_main.opr_army_manager.game_units[squad.unit_id] = squad
	for i in range(squad.models.size()):
		(squad.models[i] as ModelInstance).model_index = i
	squad.unit_properties["special_rules"] = [rule]
	squad.unit_properties["game_system"] = "gf"
	squad.unit_properties["faction_folder"] = ""
	var hero := E2EBoot.make_unit(_main, 1, "Hero", [Vector3(0.4, 0.0, 0.2)])
	_main.opr_army_manager.game_units[hero.unit_id] = hero
	hero.unit_properties["special_rules"] = ["Hero"]
	hero.unit_properties["game_system"] = "gf"
	hero.unit_properties["faction_folder"] = ""
	hero.unit_properties["attached_to"] = squad
	squad.unit_properties["attached_heroes"] = [hero]
	return squad


func _set_epoch(epoch: int) -> void:
	AiActRecorder.rules_epoch = epoch


func test_empyrean_spirit_keeps_with_a_plain_joined_hero_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _squad_with_plain_hero("Empyrean Spirit", 5)
	assert_bool(_main._solo_stealth_family_on(squad, "Empyrean Spirit")) \
		.override_failure_message("five of six models carry Empyrean Spirit: most models, the squad keeps it").is_true()


func test_grounded_evasion_keeps_with_a_plain_joined_hero_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _squad_with_plain_hero("Grounded Evasion", 5)
	assert_bool(_main._solo_stealth_family_on(squad, "Grounded Evasion")) \
		.override_failure_message("five of six models carry Grounded Evasion: most models, the squad keeps it").is_true()


func test_empyrean_spirit_loses_it_with_a_plain_joined_hero_at_epoch_72() -> void:
	_set_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var squad := _squad_with_plain_hero("Empyrean Spirit", 5)
	assert_bool(_main._solo_stealth_family_on(squad, "Empyrean Spirit")) \
		.override_failure_message("below the epoch the all-models read still strips it").is_false()


func test_grounded_evasion_loses_it_with_a_plain_joined_hero_at_epoch_72() -> void:
	_set_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var squad := _squad_with_plain_hero("Grounded Evasion", 5)
	assert_bool(_main._solo_stealth_family_on(squad, "Grounded Evasion")) \
		.override_failure_message("below the epoch the all-models read still strips it").is_false()
