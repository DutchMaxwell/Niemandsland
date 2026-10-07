extends GdUnitTestSuite
## E2E walk of Game School chapter 3 (S-03, Bring Your Army) over the real scenes/main.tscn:
## the four state steps (menu, offline army import, deploy into the zone, start the game) complete
## the chapter, and an idle boot stays on step 0 and uncompleted.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const TEST_CFG := "user://test_game_school_ch3.cfg"
const FLAGS := ["niemandsland/scenario_mode", "niemandsland/scenario_path",
	"niemandsland/scenario_chapter", "niemandsland/pending_load_path"]
const PRACTICE_ARMY := "res://assets/tutorial/tutorial_army_p1.json"

var _saved: Dictionary = {}
var _root_before: Array
var _runner: GdUnitSceneRunner
var _main: Node
var _lesson: LessonRunner


func before_test() -> void:
	_root_before = Boot.root_children(get_tree())
	for flag in FLAGS:
		_saved[flag] = ProjectSettings.get_setting(flag)
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))
	ProjectSettings.set_setting("niemandsland/scenario_mode", true)
	ProjectSettings.set_setting("niemandsland/scenario_path", Spielschule.chapter("S-03").scenario)
	ProjectSettings.set_setting("niemandsland/scenario_chapter", "S-03")
	ProjectSettings.set_setting("niemandsland/pending_load_path", "")
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	_main._lesson_progress_path = TEST_CFG
	await _main.save_manager.load_completed
	_lesson = _main.get_node("LessonRunner") as LessonRunner


func after_test() -> void:
	for flag in FLAGS:
		ProjectSettings.set_setting(flag, _saved[flag])
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))
	Boot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _wait_index(target: int) -> bool:
	var deadline := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		if _lesson.current_index() == target:
			return true
		await get_tree().process_frame
	return false


func _move_unit_to(unit: GameUnit, spot: Vector3) -> void:
	var nodes: Array[Node3D] = []
	var centre := Vector3.ZERO
	for model in unit.models:
		if is_instance_valid(model.node):
			nodes.append(model.node)
			centre += model.node.global_position
	if nodes.is_empty():
		return
	var delta := spot - centre / nodes.size()
	delta.y = 0.0
	for node in nodes:
		node.global_position += delta


func test_s03_four_state_steps_complete_and_persist(timeout := 60000) -> void:
	assert_int(_lesson.current_index()).is_equal(0)
	_main.left_panel_scroll.visible = true
	assert_bool(await _wait_index(1)).is_true()
	await _main._on_lesson_action(PRACTICE_ARMY)
	assert_bool(await _wait_index(2)).is_true()
	for unit in _main.opr_army_manager.get_game_units_for_player(1):
		_move_unit_to(unit, Vector3(0.0, 0.0, -18.0 * 0.0254))
	assert_bool(await _wait_index(3)).is_true()
	_main.opr_army_manager.set_game_phase(1)
	var progress := SpielschuleProgress.new(TEST_CFG)
	var deadline := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		progress.load_from_disk()
		if progress.is_completed("S-03"):
			break
		await get_tree().process_frame
	assert_bool(progress.is_completed("S-03")).is_true()
	assert_str((_main.get_node("UI/LessonCard") as LessonCard).get_node("Content/StepText").text).contains("Chapter complete")
	await Boot.settle(get_tree())


func test_idle_s03_stays_unfinished(timeout := 60000) -> void:
	await get_tree().create_timer(3.0).timeout
	var progress := SpielschuleProgress.new(TEST_CFG)
	progress.load_from_disk()
	assert_int(_lesson.current_index()).is_equal(0)
	assert_bool(progress.is_completed("S-03")).is_false()
	await Boot.settle(get_tree())
