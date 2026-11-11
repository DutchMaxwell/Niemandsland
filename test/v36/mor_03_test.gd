extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-03: Stealth and its "most models" aliases (Changebound here) count MOST living models
## of a joined unit (ruling D-MOST), a joined hero being one model and an exact half being off. Below
## EPOCH_73_V36 every model must carry the rule, as before. The core's twin is
## core/nml-core/src/tests/dice/v36_morale.rs.

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


## A gf unit of player `pid` with `models` models carrying `rules`; every model carries the unit's rules too,
## the way the import hands them out.
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


## Host `unit_name` of `models` models with one joined hero carrying `hero_rules`.
func _joined(unit_name: String, faction: String, host_rules: Array, models: int, hero_rules: Array) -> GameUnit:
	var squad := _unit(2, unit_name, faction, host_rules, models)
	var hero := _unit(2, unit_name + " Captain", faction, hero_rules, 1)
	hero.unit_properties["attached_to"] = squad
	squad.unit_properties["attached_heroes"] = [hero]
	return squad


## [to-hit modifier, battle-log note] of one plain shot at `target` from `dist_in` inches.
func _shot(target: GameUnit, dist_in: float) -> Array:
	var gun := _unit(1, "Gunner", "robot_legions", [], 1)
	var info: Dictionary = _main._solo_hit_mod_info(gun, target, dist_in, false)
	return [int(info["mod"]), str(info["note"])]


func test_a_stealth_squad_keeps_its_minus_one_with_a_joined_hero_without_it_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var squad := _joined("Sneak Squad", "robot_legions", ["Stealth"], 3, ["Hero"])
	var far := _shot(squad, 14.0)
	assert_int(int(far[0])).override_failure_message("3 of 4 models carry Stealth: -1 past 9\"").is_equal(-1)
	assert_str(str(far[1])).contains("Stealth -1")
	assert_str(str(far[1])).override_failure_message("the note names the most-models read: '%s'" % far[1]) \
		.contains("most models")
	assert_bool(bool(AiEv.ctx_for(squad)["stealth"])).override_failure_message("the EV snapshot agrees").is_true()
	# One Stealth model plus the hero is an exact half: off in both engines.
	var tie := _joined("Sneak Pair", "robot_legions", ["Stealth"], 1, ["Hero"])
	assert_int(int(_shot(tie, 14.0)[0])).is_equal(0)
	assert_bool(bool(AiEv.ctx_for(tie)["stealth"])).is_false()
	# Every model carrying Stealth keeps the plain note.
	var all := _unit(2, "Sneak Team", "robot_legions", ["Stealth"], 3)
	var all_far := _shot(all, 14.0)
	assert_int(int(all_far[0])).is_equal(-1)
	assert_str(str(all_far[1])).not_contains("most models")


func test_a_stealth_squad_loses_its_minus_one_with_a_joined_hero_without_it_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var squad := _joined("Sneak Squad", "robot_legions", ["Stealth"], 3, ["Hero"])
	var far := _shot(squad, 14.0)
	assert_int(int(far[0])).is_equal(0)
	assert_str(str(far[1])).not_contains("Stealth -1")
	assert_bool(bool(AiEv.ctx_for(squad)["stealth"])).is_false()


func test_changebound_keeps_its_minus_one_with_a_joined_hero_without_it_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var squad := _joined("Change Squad", "change_disciples", ["Changebound"], 3, ["Hero"])
	var far := _shot(squad, 14.0)
	assert_int(int(far[0])).override_failure_message("3 of 4 models carry Changebound").is_equal(-1)
	assert_str(str(far[1])).contains("Changebound -1")


func test_changebound_loses_its_minus_one_with_a_joined_hero_without_it_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var squad := _joined("Change Squad", "change_disciples", ["Changebound"], 3, ["Hero"])
	assert_int(int(_shot(squad, 14.0)[0])).is_equal(0)
