extends GdUnitTestSuite
## E2E walk of Game School chapter 7 (S-07, Morale) over the real scenes/main.tscn:
## the pre-Shaken squad idles to recover, then Alpha shoots the half-strength enemy and the morale
## outcome is read — the four steps complete the chapter, and an idle boot stays on step 0.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const TEST_CFG := "user://test_game_school_ch7.cfg"
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
	ProjectSettings.set_setting("niemandsland/scenario_path", Spielschule.chapter("S-07").scenario)
	ProjectSettings.set_setting("niemandsland/scenario_chapter", "S-07")
	ProjectSettings.set_setting("niemandsland/pending_load_path", "")
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	_main._lesson_progress_path = TEST_CFG
	await _main.save_manager.load_completed
	_lesson = _main.get_node("LessonRunner") as LessonRunner
	_main._solo_fast = true


func after_test() -> void:
	for flag in FLAGS:
		ProjectSettings.set_setting(flag, _saved[flag])
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))
	Boot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _find(tag: String) -> GameUnit:
	for unit in _main.opr_army_manager.get_all_game_units():
		if unit is GameUnit and String(unit.unit_properties.get("lesson_tag", "")) == tag:
			return unit
	return null


func _wait_index(target: int) -> bool:
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if _lesson.current_index() == target:
			return true
		await get_tree().process_frame
	return false


func test_s07_four_steps_complete(timeout := 60000) -> void:
	assert_int(_lesson.current_index()).is_equal(0)

	var shaken := _find("shaken")
	assert_object(shaken).is_not_null()
	assert_bool(shaken.is_shaken).is_true()   # the table starts it Shaken

	var target := _find("target")
	assert_object(target).is_not_null()
	var target_alive := 0
	for model in target.models:
		if (model as ModelInstance).is_alive:
			target_alive += 1
	assert_int(target_alive).is_equal(5)   # half of the 10-model formation is parked dead

	var tough := _find("tough")
	assert_object(tough).is_not_null()
	assert_int((tough.models[0] as ModelInstance).wounds_current).is_equal(1)   # Tough(3) with 2 wounds

	var card := _main.get_node("UI/LessonCard") as LessonCard

	card.continue_pressed.emit()
	assert_bool(await _wait_index(1)).is_true()   # read the S token

	_main.unit_dock.present_unit(tough)
	card.continue_pressed.emit()
	assert_bool(await _wait_index(2)).is_true()   # read the half-strength Tough model card

	_main.radial_menu_controller.card_toggle_activation(shaken)
	if shaken.is_shaken:
		_main.radial_menu_controller.card_toggle_shaken(shaken)
	card.continue_pressed.emit()
	assert_bool(await _wait_index(3)).is_true()   # idled, activated and recovered

	var alpha := _find("alpha")
	assert_object(alpha).is_not_null()
	await _main._run_human_attack(alpha, target, false)
	assert_bool(await _wait_index(4)).is_true()   # the volley forced the morale test

	card.continue_pressed.emit()
	var progress := SpielschuleProgress.new(TEST_CFG)
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		progress.load_from_disk()
		if progress.is_completed("S-07"):
			break
		await get_tree().process_frame
	assert_bool(progress.is_completed("S-07")) \
		.override_failure_message("S-07 not completed: index=%d" % _lesson.current_index()) \
		.is_true()
	# The step gate is the SHOT, not the morale outcome: the volley may wipe the half-strength squad
	# (no morale test) or miss, and the chapter must still complete for every dice outcome.
	await Boot.settle(get_tree())


func test_idle_s07_stays_unfinished(timeout := 60000) -> void:
	await get_tree().create_timer(3.0).timeout
	var progress := SpielschuleProgress.new(TEST_CFG)
	progress.load_from_disk()
	assert_array(SpielschuleLessons.steps_for("S-07")).is_not_empty()
	assert_int(_lesson.current_index()).is_equal(0)
	assert_bool(progress.is_completed("S-07")).is_false()
	await Boot.settle(get_tree())
