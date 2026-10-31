extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-17a: Warding, Knightborn and Angelic Blessing are one rule. From
## EPOCH_73_V36 a non-spell wound is ignored on a 6+ only when the unit was shot from over 9" or
## charged from over 6"; a spell wound on a 2+. Below 73 the old entry stands (6+ at any distance,
## 4+ vs spells). The core's twin is core/nml-core/src/tests/dice/v36_morale.rs.

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


## A gf AI unit of `models` models carrying `rules`; every model carries the unit's rules too.
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


func _knightborn() -> GameUnit:
	return _unit("Knight Squad", "knight_brothers", ["Knightborn"], 4)


## The ignore target the table picks: `shot_in` / `charged_in` -1.0 = the distance is unknown.
func _pick(squad: GameUnit, from_spell: bool, shot_in: float = -1.0, charged_in: float = -1.0) -> int:
	return int(_main._solo_regen_pick(squad, from_spell, shot_in, charged_in).get("target", 0))


func _log_text() -> String:
	var text := ""
	for entry in _main.battle_log.entries():
		text += str(entry["text"]) + "\n"
	return text


func test_knightborn_ignores_shot_wounds_from_over_nine_inches_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_int(_pick(_knightborn(), false, 12.0)).override_failure_message("12in: the 6+ applies").is_equal(6)
	assert_int(_pick(_knightborn(), false, -1.0)).override_failure_message("unknown distance keeps today's read").is_equal(6)


func test_knightborn_rolls_no_6_ignore_when_shot_from_within_nine_inches_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_int(_pick(_knightborn(), false, 5.0)).override_failure_message("5in: the 6+ does not apply").is_equal(0)
	assert_int(_pick(_knightborn(), false, 9.0)).override_failure_message("at exactly 9in the gate is shut").is_equal(0)


func test_knightborn_ignores_shot_wounds_at_any_distance_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_int(_pick(_knightborn(), false, 5.0)).override_failure_message("72 keeps the old entry").is_equal(6)


func test_knightborn_ignores_charge_wounds_only_from_over_six_inches_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_int(_pick(_knightborn(), false, -1.0, 8.0)).override_failure_message("charged from 8in").is_equal(6)
	assert_int(_pick(_knightborn(), false, -1.0, 4.0)).override_failure_message("charged from 4in").is_equal(0)
	assert_int(_pick(_knightborn(), false, -1.0, 0.0)).override_failure_message("it did the charging").is_equal(0)


func test_knightborn_ignores_charge_wounds_at_any_distance_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_int(_pick(_knightborn(), false, -1.0, 4.0)).is_equal(6)


func test_a_spell_wound_is_ignored_on_2_at_73_and_on_4_at_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_int(_pick(_knightborn(), true)).override_failure_message("2+ vs spells from 73").is_equal(2)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_int(_pick(_knightborn(), true)).override_failure_message("4+ vs spells below 73").is_equal(4)


func test_plain_regeneration_is_unchanged_at_both_distances() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var plain := _unit("Regen Squad", "robot_legions", ["Regeneration"], 4)
	assert_int(_pick(plain, false, 5.0)).override_failure_message("5+ ignores regardless of range").is_equal(5)
	assert_int(_pick(plain, false, 12.0)).is_equal(5)


func test_the_gate_switching_the_rule_off_is_logged_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var squad := _knightborn()
	_main.seed_tray_rng(1300)
	await _main._solo_apply_regeneration(squad, 4, false, {}, 0, 5.0)
	assert_str(_log_text()).contains("Warding: no 6+ ignore, %s was shot from within 9in" % squad.get_name())
