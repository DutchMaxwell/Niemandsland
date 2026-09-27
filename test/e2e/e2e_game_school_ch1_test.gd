extends GdUnitTestSuite

const Boot := preload("res://test/e2e/e2e_boot.gd")
const TEST_CFG := "user://test_game_school_ch1.cfg"
const FLAGS := ["niemandsland/scenario_mode", "niemandsland/scenario_path",
	"niemandsland/scenario_chapter", "niemandsland/pending_load_path"]

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
	ProjectSettings.set_setting("niemandsland/scenario_path", Spielschule.chapter("S-01").scenario)
	ProjectSettings.set_setting("niemandsland/scenario_chapter", "S-01")
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


func test_s01_six_state_steps_complete_and_persist(timeout := 60000) -> void:
	assert_int(_lesson.current_index()).is_equal(0)
	_main.camera_pivot.rotation.y += 0.6
	assert_bool(await _wait_index(1)).is_true()
	var camera := _main.camera_pivot.get_node("Camera3D") as Camera3D
	camera.position *= 1.4
	assert_bool(await _wait_index(2)).is_true()
	_main.camera_pivot.global_position += Vector3(0.4, 0, 0)
	assert_bool(await _wait_index(3)).is_true()
	var alpha: GameUnit
	for unit in _main.opr_army_manager.get_all_game_units():
		if unit.unit_properties.get("lesson_tag") == "alpha":
			alpha = unit
	assert_object(alpha).is_not_null()
	var nodes: Array[Node3D] = []
	for model in alpha.get_alive_models():
		nodes.append(model.node)
	_main.object_manager.select_objects(nodes)
	assert_bool(await _wait_index(4)).is_true()
	for node in nodes:
		node.global_position.z -= 0.15
	assert_bool(await _wait_index(5)).is_true()
	_main.object_manager.measurement_finished.emit(5.0)
	var progress := SpielschuleProgress.new(TEST_CFG)
	var deadline := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		progress.load_from_disk()
		if progress.is_completed("S-01"):
			break
		await get_tree().process_frame
	assert_bool(progress.is_completed("S-01")).is_true()
	assert_str((_main.get_node("UI/LessonCard") as LessonCard).get_node("Content/StepText").text).contains("Chapter complete")
	await Boot.settle(get_tree())


func test_idle_s01_stays_unfinished(timeout := 60000) -> void:
	await get_tree().create_timer(3.0).timeout
	var progress := SpielschuleProgress.new(TEST_CFG)
	progress.load_from_disk()
	assert_int(_lesson.current_index()).is_equal(0)
	assert_bool(progress.is_completed("S-01")).is_false()
	await Boot.settle(get_tree())
