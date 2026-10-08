extends GdUnitTestSuite
## E2E walk of the Game School spell lesson (S-SPELL) over the real scenes/main.tscn:
## show a spell range preview, cast the Archivist's first affordable spell at the enemy squad, read
## the token outcome — the three steps complete the chapter, and an idle boot stays on step 0.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const TEST_CFG := "user://test_game_school_spell.cfg"
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
	ProjectSettings.set_setting("niemandsland/scenario_path", Spielschule.chapter("S-SPELL").scenario)
	ProjectSettings.set_setting("niemandsland/scenario_chapter", "S-SPELL")
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


func test_s_spell_three_steps_complete(timeout := 120000) -> void:
	assert_int(_lesson.current_index()).is_equal(0)
	var alpha := _find("alpha")
	var target := _find("target")
	assert_object(alpha).is_not_null()
	assert_object(target).is_not_null()
	assert_int(alpha.casts_current).is_greater(0)

	# The card/hover seam: a spell preview ring is on the table (fact spell_preview).
	_main.range_ring_controller.show_spell_preview(_main._solo_unit_nodes(alpha), 18)
	assert_bool(await _wait_index(1)).is_true()   # the range preview shows

	# The caster's first affordable spell, cast through the real human-cast seam. Leave exactly one
	# token so the post-spend boost pool is empty — the boost dialog is an interactive prompt that
	# cannot be answered headless, and this lesson teaches the base cast, not boosting.
	alpha.casts_current = 1
	var spells := SpellsRegistry.spells_for_unit(alpha)
	var entry: Dictionary = {}
	for sp in spells:
		if int((sp as Dictionary).get("threshold", 99)) <= alpha.casts_current:
			entry = sp as Dictionary
			break
	assert_bool(entry.is_empty()).override_failure_message(
		"the Archivist has no affordable spell").is_false()
	await _main._run_human_cast(alpha, alpha, entry, [target])
	assert_bool(await _wait_index(2)).is_true()   # the spell resolved

	(_main.get_node("UI/LessonCard") as LessonCard).continue_pressed.emit()
	var progress := SpielschuleProgress.new(TEST_CFG)
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		progress.load_from_disk()
		if progress.is_completed("S-SPELL"):
			break
		await get_tree().process_frame
	assert_bool(progress.is_completed("S-SPELL")) \
		.override_failure_message("S-SPELL not completed: index=%d" % _lesson.current_index()) \
		.is_true()
	await Boot.settle(get_tree())


func test_idle_s_spell_stays_unfinished(timeout := 60000) -> void:
	await get_tree().create_timer(3.0).timeout
	var progress := SpielschuleProgress.new(TEST_CFG)
	progress.load_from_disk()
	assert_array(SpielschuleLessons.steps_for("S-SPELL")).is_not_empty()
	assert_int(_lesson.current_index()).is_equal(0)
	assert_bool(progress.is_completed("S-SPELL")).is_false()
	await Boot.settle(get_tree())
