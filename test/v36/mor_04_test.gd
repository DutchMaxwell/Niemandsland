extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-04: Entrenched is a Human Defense Force rule, -1 to be hit from over 12"
## while the unit has not moved this round (it was -2 from over 9"). Below EPOCH_73_V36 every model
## must carry it; from 73 MOST models do (ruling D-MOST). The core's twin is
## core/nml-core/src/tests/dice/v36_mor_04.rs.

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


## A gf unit of player `pid` with `models` models carrying `rules`; every model carries the unit's rules too.
func _unit(pid: int, unit_name: String, faction: String, rules: Array, models: int) -> GameUnit:
	var positions: Array = []
	for i in models:
		positions.append(Vector3(i, 0, 0))
	var unit := Boot.make_unit(_main, pid, unit_name, positions)
	unit.unit_properties["game_system"] = "gf"
	unit.unit_properties["faction_folder"] = faction
	unit.unit_properties["special_rules"] = rules.duplicate()
	for m in unit.models:
		(m as ModelInstance).properties["special_rules"] = rules.duplicate()
	_main.opr_army_manager.game_units[unit.unit_id] = unit
	return unit


## Host with `models` Entrenched models and one joined hero carrying `hero_rules`.
func _joined(unit_name: String, models: int, hero_rules: Array) -> GameUnit:
	var squad := _unit(2, unit_name, "human_defense_force", ["Entrenched"], models)
	var hero := _unit(2, unit_name + " Captain", "human_defense_force", hero_rules, 1)
	hero.unit_properties["attached_to"] = squad
	squad.unit_properties["attached_heroes"] = [hero]
	return squad


## [to-hit modifier, battle-log note] of one plain shot at `target` from `dist_in` inches.
func _shot(target: GameUnit, dist_in: float) -> Array:
	var gun := _unit(1, "Gunner", "robot_legions", [], 1)
	var info: Dictionary = _main._solo_hit_mod_info(gun, target, dist_in, false)
	return [int(info["mod"]), str(info["note"])]


func test_entrenched_hdf_unit_is_minus_one_past_twelve_inches_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var squad := _unit(2, "Entrenched Squad", "human_defense_force", ["Entrenched"], 1)
	var far := _shot(squad, 13.0)
	assert_int(int(far[0])).override_failure_message("Entrenched: -1 past 12\" (note: %s)" % far[1]).is_equal(-1)
	assert_str(str(far[1])).override_failure_message("the line names Entrenched with the 12\" gate: '%s'" % far[1]) \
		.contains("Entrenched") \
		.contains("12")
	assert_int(int(_shot(squad, 11.0)[0])).override_failure_message("within 12\" Entrenched does nothing").is_equal(0)


func test_entrenched_hdf_unit_that_moved_gets_no_penalty_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var squad := _unit(2, "Moved Squad", "human_defense_force", ["Entrenched"], 1)
	squad.unit_properties["moved_round"] = _main.opr_army_manager.current_round
	var info := _shot(squad, 13.0)
	assert_int(int(info[0])).override_failure_message("moved this round: no penalty (note: %s)" % info[1]).is_equal(0)
	assert_str(str(info[1])).not_contains("Entrenched")


## Control: below 73 every model must carry Entrenched, so a joined hero without it withholds the rule.
func test_a_joined_hero_without_entrenched_withholds_it_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var squad := _joined("Entrenched Squad", 3, ["Hero"])
	var info := _shot(squad, 13.0)
	assert_int(int(info[0])).override_failure_message("at 72 the hero without Entrenched withholds it").is_equal(0)
	assert_str(str(info[1])).not_contains("Entrenched")


## 3.6 carrier test at 73: three Entrenched models with a joined hero without it are still MOST models.
func test_most_models_carrying_entrenched_keep_the_minus_one_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var squad := _joined("Entrenched Squad", 3, ["Hero"])
	assert_int(int(_shot(squad, 13.0)[0])).override_failure_message("3 of 4 models carry Entrenched").is_equal(-1)
