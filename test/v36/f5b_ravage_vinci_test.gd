extends GdUnitTestSuite
## W31-F5b (release 0.3.15): Ravage in aof duchies_of_vinci. The Rust core reads the rating by name off the unit's own
## rules, so an arena game already rolls it; the table's strike phase asks the registry per book
## (`RulesRegistry.unit_rule_active`) and dropped it where the book has no row, so a real table game played a
## different fight. Drives the real strike phase over main.tscn (the MEL-11 shape): the Ravage pool is rolled and its
## battle-log line names the book rule. Control book: aof beastmen, which has its row. Rust twin:
## `core/nml-core/src/tests/unit/v36_data_rows/f5b_ravage.rs`.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	RulesRegistry.reset_cache()
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	await E2EBoot.settle(get_tree())
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	AiActRecorder.rules_epoch = _epoch0
	RulesRegistry.reset_cache()


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## One Ravage(1) model of `faction` with a plain melee weapon strikes a ten-model foe; returns the battle log.
func _strike_log(faction: String) -> String:
	var u := E2EBoot.make_unit(_main, 1, "Scouts", [Vector3.ZERO])
	(u.models[0] as ModelInstance).model_index = 0
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Club"
	w.range_value = 0
	w.attacks = 1
	w.count = 1
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	u.source_type = "opr"
	u.source_data = src
	u.unit_properties["game_system"] = "aof"
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = ["Ravage(1)"]
	_main.opr_army_manager.game_units[u.unit_id] = u
	var spots: Array = []
	for i in range(10):
		spots.append(Vector3((0.5 + i) * INCH, 0, 0.5 * INCH))
	var foe := E2EBoot.make_unit(_main, 2, "Grunts", spots)
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	await _main._solo_melee_strike_phase(u, foe, false, 0)   # 0 = SoloStrike.ALL
	return _log_text()


func test_ravage_control_beastmen_rolls_its_pool() -> void:
	assert_str(await _strike_log("beastmen")).contains("Ravage(1): Scouts rolls")


func test_ravage_rolls_its_pool_in_duchies_of_vinci() -> void:
	var text: String = await _strike_log("duchies_of_vinci")
	assert_str(text).override_failure_message("aof/duchies_of_vinci: Ravage silently dropped by the table (log: %s)" % text) \
		.contains("Ravage(1): Scouts rolls")
