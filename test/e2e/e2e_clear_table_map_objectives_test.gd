extends GdUnitTestSuite
## Clear Table also resets the Map Layout objectives and who holds them. Terrain pieces, models and armies
## go with the table; the objective markers (and their captured owners) used to survive it, so the next
## game started on the last game's markers. Real: scenes/main.tscn, the Map Layout editor's own placement
## path (_toggle_objective_at_position), a seize on the overlay, and Clear Table's action.

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


func _place_and_seize() -> void:
	_main.map_layout_editor.point_symmetry_enabled = false
	_main.map_layout_editor._toggle_objective_at_position(Vector2(30.0, 24.0))
	_main.map_layout_editor._toggle_objective_at_position(Vector2(60.0, 24.0))
	assert_int(_main.terrain_overlay.get_objectives().size()) \
		.override_failure_message("fixture: the Map Layout path placed no markers on the overlay").is_equal(2)
	_main.terrain_overlay.set_objective_owner(0, 1)
	assert_array(_main.terrain_overlay.get_objective_owners()) \
		.override_failure_message("fixture: the seize did not stick").is_equal([1, 0])


func test_clear_table_removes_the_objectives_and_their_holders(timeout := 120000) -> void:
	_place_and_seize()
	var start: int = _main.battle_log.entries().size()
	_main._do_clear_all()
	await E2EBoot.settle(get_tree())
	assert_int(_main.map_layout_editor.mission_objectives.size()) \
		.override_failure_message("Clear Table left %d objectives in the Map Layout editor" % _main.map_layout_editor.mission_objectives.size()) \
		.is_equal(0)
	assert_int(_main.terrain_overlay.get_objectives().size()) \
		.override_failure_message("Clear Table left %d objective markers on the table" % _main.terrain_overlay.get_objectives().size()) \
		.is_equal(0)
	assert_int(_main.terrain_overlay.get_objective_owners().size()) \
		.override_failure_message("Clear Table kept the objective holders: %s" % str(_main.terrain_overlay.get_objective_owners())) \
		.is_equal(0)
	var text := ""
	for e in _main.battle_log.entries().slice(start):
		text += str((e as Dictionary)["text"]) + "\n"
	assert_str(text).override_failure_message("the objective reset was not logged:\n%s" % text).contains("Objectives cleared")


func test_clear_table_with_no_objectives_logs_nothing_about_them(timeout := 120000) -> void:
	var start: int = _main.battle_log.entries().size()
	_main._do_clear_all()
	await E2EBoot.settle(get_tree())
	var text := ""
	for e in _main.battle_log.entries().slice(start):
		text += str((e as Dictionary)["text"]) + "\n"
	assert_str(text).override_failure_message("an empty table logged an objective reset:\n%s" % text).not_contains("Objectives cleared")
