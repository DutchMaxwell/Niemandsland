extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 7 over the real scenes/main.tscn: a list of another game system than the table's is refused at
## the real import handler (nothing stored, nothing spawned, one log line), a list of the table's own system imports.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _army(abbrev: String, army_name: String) -> OPRApiClient.OPRArmy:
	var a := OPRApiClient.OPRArmy.new()
	a.name = army_name
	a.game_system_abbrev = abbrev
	return a


func _refusals() -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).begins_with("Import refused: "):
			n += 1
	return n


func test_a_gf_list_is_refused_on_an_aofs_table_and_an_aofs_list_imports() -> void:
	assert_bool(_main.set_table_system("aofs", "P1")).is_true()
	var minis_before := get_tree().get_nodes_in_group("miniature").size()
	await _main._on_opr_army_imported(_army("gf", "Grim List"), 1, false)
	await E2EBoot.settle(get_tree())
	assert_bool(_main.opr_army_manager.armies.has(1)).override_failure_message("the refused list was stored").is_false()
	assert_int(get_tree().get_nodes_in_group("miniature").size()).is_equal(minis_before)
	assert_int(_refusals()).is_equal(1)
	assert_str(_main.opr_army_manager.table_system).is_equal("aofs")
	await _main._on_opr_army_imported(_army("aofs", "Skirmish List"), 1, false)
	await E2EBoot.settle(get_tree())
	assert_bool(_main.opr_army_manager.armies.has(1)).override_failure_message("the table's own system was refused").is_true()
	assert_int(_refusals()).is_equal(1)
