extends GdUnitTestSuite
## E2E walk of Game School chapter 10 (S-10, the finale) over the real scenes/main.tscn:
## boot the live-AI finale, assert the gentlest grade and a playing (not holding) AI, then run the
## real game-end path — the single step completes the chapter, and an idle boot stays unfinished.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const TEST_CFG := "user://test_game_school_ch10.cfg"
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
	ProjectSettings.set_setting("niemandsland/scenario_path", Spielschule.chapter("S-10").scenario)
	ProjectSettings.set_setting("niemandsland/scenario_chapter", "S-10")
	ProjectSettings.set_setting("niemandsland/pending_load_path", "")
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	_main._lesson_progress_path = TEST_CFG
	await _main.save_manager.load_completed
	_lesson = _main.get_node("LessonRunner") as LessonRunner
	_main._solo_fast = true
	_main._solo_batch = true


func after_test() -> void:
	for flag in FLAGS:
		ProjectSettings.set_setting(flag, _saved[flag])
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))
	Boot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _wait_index(target: int) -> bool:
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if _lesson.current_index() == target:
			return true
		await get_tree().process_frame
	return false


func test_s10_one_step_completes(timeout := 120000) -> void:
	assert_int(_lesson.current_index()).is_equal(0)
	assert_str(_main._solo_interactive_grade).is_equal("daemmerung")
	assert_object(_main.solo_controller).is_not_null()
	assert_bool(_main.solo_controller.lesson_hold).override_failure_message(
		"the finale must play for real, not hold").is_false()

	# The real game-end path the 4th round end takes: the buzzer sounds, the summary runs and
	# _solo_game_finished flips — the single lesson step gates on exactly that.
	_main.opr_army_manager.current_round = _main._solo_total_rounds()
	_main._solo_end_round()
	assert_bool(_main._solo_game_finished).is_true()

	var progress := SpielschuleProgress.new(TEST_CFG)
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		progress.load_from_disk()
		if progress.is_completed("S-10"):
			break
		await get_tree().process_frame
	assert_bool(progress.is_completed("S-10")) \
		.override_failure_message("S-10 not completed: index=%d" % _lesson.current_index()) \
		.is_true()
	await Boot.settle(get_tree())


func test_idle_s10_stays_unfinished(timeout := 60000) -> void:
	await get_tree().create_timer(3.0).timeout
	var progress := SpielschuleProgress.new(TEST_CFG)
	progress.load_from_disk()
	assert_array(SpielschuleLessons.steps_for("S-10")).is_not_empty()
	assert_bool(progress.is_completed("S-10")).is_false()
	await Boot.settle(get_tree())
