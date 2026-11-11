extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-02: the Regeneration family counts MOST living models of a joined unit (ruling
## D-MOST), a joined hero being one model and an exact half being off. Below EPOCH_73_V36 each engine keeps
## its old read: the table rolls plain Regeneration when any member carries it, the EV metric when the host
## does, and Self-Repair / the all-models aliases need every model. The core's twin is
## core/nml-core/src/tests/unit/v36_morale.rs.

const Boot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


## A gf AI unit of `models` models carrying `rules`; every model carries the unit's rules too, the way the
## import hands them out (equipment_distributor.distribute).
func _unit(unit_name: String, faction: String, rules: Array, models: int) -> GameUnit:
	var positions: Array = []
	for i in models:
		positions.append(Vector3(i, 0, 0))
	var unit := Boot.make_unit(_main, 2, unit_name, positions)
	unit.unit_properties["game_system"] = "gf"
	unit.unit_properties["faction_folder"] = faction
	unit.unit_properties["special_rules"] = rules.duplicate()
	for m in unit.models:
		(m as ModelInstance).properties["special_rules"] = rules.duplicate()
	return unit


## Host `unit_name` of `models` models with one joined hero carrying `hero_rules`.
func _joined(unit_name: String, faction: String, host_rules: Array, models: int, hero_rules: Array) -> GameUnit:
	var squad := _unit(unit_name, faction, host_rules, models)
	var hero := _unit(unit_name + " Captain", faction, hero_rules, 1)
	hero.unit_properties["attached_to"] = squad
	squad.unit_properties["attached_heroes"] = [hero]
	return squad


## [the table's ignore target, the EV metric's ignore target] for `squad`.
func _targets(squad: GameUnit) -> Array:
	return [_main._solo_regen_target(squad), AiEv._regen_target(squad)]


func _log_text() -> String:
	var text := ""
	for entry in _main.battle_log.entries():
		text += str(entry["text"]) + "\n"
	return text


func _self_repair_squad() -> GameUnit:
	return _joined("Repair Squad", "robot_legions", ["Self-Repair"], 3, ["Hero"])


## Plaguebound converts; its Boost is not a "most models" name and still needs every model.
func _plaguebound_squad() -> GameUnit:
	return _joined("Plague Squad", "plague_disciples", ["Plaguebound", "Plaguebound Boost"], 3, ["Hero"])


func test_self_repair_and_plaguebound_roll_with_a_joined_hero_without_them_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_array(_targets(_self_repair_squad())).override_failure_message("Self-Repair: 3 of 4 models").is_equal([6, 6])
	assert_array(_targets(_plaguebound_squad())).override_failure_message("Plaguebound 6+, Boost off").is_equal([6, 6])


func test_self_repair_and_plaguebound_need_every_model_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_array(_targets(_self_repair_squad())).is_equal([0, 0])
	assert_array(_targets(_plaguebound_squad())).is_equal([0, 0])


func test_a_regeneration_tie_with_a_joined_hero_is_off_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var squad := _joined("Regen Pair", "robot_legions", ["Regeneration"], 1, ["Hero"])
	assert_array(_targets(squad)).override_failure_message("1 of 2 models: an exact half").is_equal([0, 0])


func test_a_regeneration_tie_with_a_joined_hero_rolls_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_array(_targets(_joined("Regen Pair", "robot_legions", ["Regeneration"], 1, ["Hero"]))).is_equal([5, 5])


func test_regeneration_only_on_the_joined_hero_is_off_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var squad := _joined("Plain Squad", "robot_legions", [], 3, ["Hero", "Regeneration"])
	assert_array(_targets(squad)).override_failure_message("1 of 4 models carry it").is_equal([0, 0])


## Below the 3.6 epoch the two engines disagree here: the table rolls for the hero's rule, the EV metric not.
func test_regeneration_only_on_the_joined_hero_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_array(_targets(_joined("Plain Squad", "robot_legions", [], 3, ["Hero", "Regeneration"]))).is_equal([5, 0])


## A medic hero's Medical Training is not a "most models" rule: the table keeps its roll as before.
func test_a_medical_training_hero_still_gives_the_roll_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_array(_targets(_joined("Medic Squad", "robot_legions", [], 3, ["Hero", "Medical Training"]))).is_equal([5, 0])


func test_most_models_keep_regeneration_and_the_log_says_so_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var squad := _joined("Regen Squad", "robot_legions", ["Regeneration"], 3, ["Hero"])
	assert_array(_targets(squad)).is_equal([5, 5])
	_main.seed_tray_rng(1300)
	await _main._solo_apply_regeneration(squad, 4, false)
	var text := _log_text()
	assert_str(text).contains("rolls 4 regeneration dice")
	assert_str(text).contains("Regeneration: most models carry it")
