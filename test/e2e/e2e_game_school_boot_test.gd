extends GdUnitTestSuite

const Boot := preload("res://test/e2e/e2e_boot.gd")
const TEST_CFG := "user://test_game_school_boot.cfg"
const FLAGS := ["niemandsland/scenario_mode", "niemandsland/scenario_path",
	"niemandsland/scenario_chapter", "niemandsland/pending_load_path"]

var _saved: Dictionary = {}
var _root_before: Array = []
var _runner: GdUnitSceneRunner
var _main: Node


func before_test() -> void:
	_root_before = Boot.root_children(get_tree())
	for flag in FLAGS:
		_saved[flag] = ProjectSettings.get_setting(flag)
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))


func after_test() -> void:
	for flag in FLAGS:
		ProjectSettings.set_setting(flag, _saved[flag])
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))
	Boot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_s01_starts_at_step_zero_without_completion(timeout := 60000) -> void:
	ProjectSettings.set_setting("niemandsland/scenario_mode", true)
	ProjectSettings.set_setting("niemandsland/scenario_path",
		Spielschule.chapter("S-01").scenario)
	ProjectSettings.set_setting("niemandsland/scenario_chapter", "S-01")
	ProjectSettings.set_setting("niemandsland/pending_load_path", "")
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	var progress_path := SpielschuleProgress.DEFAULT_PATH
	for property in _main.get_property_list():
		if property.name == "_lesson_progress_path":
			_main.set("_lesson_progress_path", TEST_CFG)
			progress_path = TEST_CFG
			break
	await _main.save_manager.load_completed
	var progress := SpielschuleProgress.new(progress_path)
	progress.load_from_disk()
	assert_bool(progress.is_completed("S-01")).is_false()
	var lesson_runner := _main.get_node_or_null("LessonRunner") as LessonRunner
	assert_object(lesson_runner).is_not_null()
	if lesson_runner != null:
		assert_int(lesson_runner.current_index()).is_equal(0)
	var card := _main.get_node_or_null("UI/LessonCard") as LessonCard
	assert_object(card).is_not_null()
	if card != null:
		assert_str(card.get_node("Content/Header").get_child(0).text).contains("FIRST STEPS")
	assert_str(Spielschule.chapter("S-01").title).is_equal("First Steps")
	await Boot.settle(get_tree())
