extends GdUnitTestSuite
## E2E walk of Game School chapter 9 (S-09, Mission Objectives) over the real scenes/main.tscn:
## park Alpha on the left marker and Bravo on the contested right marker, run the round end so the
## marker is seized, read the outcome — the four steps complete the chapter, and an idle boot stays
## on step 0.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const TEST_CFG := "user://test_game_school_ch9.cfg"
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
	ProjectSettings.set_setting("niemandsland/scenario_path", Spielschule.chapter("S-09").scenario)
	ProjectSettings.set_setting("niemandsland/scenario_chapter", "S-09")
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


func _move_unit_to(unit: GameUnit, spot: Vector3) -> void:
	var nodes: Array[Node3D] = []
	var centre := Vector3.ZERO
	for model in unit.models:
		var mi := model as ModelInstance
		if mi != null and not mi.is_alive:
			continue
		if is_instance_valid(model.node):
			nodes.append(model.node)
			centre += model.node.global_position
	if nodes.is_empty():
		return
	var delta := spot - centre / nodes.size()
	delta.y = 0.0
	for node in nodes:
		node.global_position += delta


func _wait_index(target: int) -> bool:
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if _lesson.current_index() == target:
			return true
		await get_tree().process_frame
	return false


func test_s09_four_steps_complete(timeout := 120000) -> void:
	assert_int(_lesson.current_index()).is_equal(0)
	var alpha := _find("alpha")
	var bravo := _find("bravo")
	assert_object(alpha).is_not_null()
	assert_object(bravo).is_not_null()
	var objs: Array = _main.terrain_overlay.get_objectives()
	assert_int(objs.size()).is_equal(3)

	_move_unit_to(alpha, objs[0])
	assert_bool(await _wait_index(1)).is_true()   # Alpha within 3" of the left marker

	_move_unit_to(bravo, objs[2])
	assert_bool(await _wait_index(2)).is_true()   # Bravo within 3" of the right marker

	# The round-end seam Next Round uses: only one side is near the left marker, so Alpha's side
	# seizes it; the right marker stays neutral while Bravo and the enemy are both near it.
	_main._solo_auto_seize()
	assert_int(_main.terrain_overlay.get_objective_owner(0)).is_equal(1)
	assert_int(_main.terrain_overlay.get_objective_owner(2)).is_equal(0)
	assert_bool(await _wait_index(3)).is_true()   # the marker was seized

	(_main.get_node("UI/LessonCard") as LessonCard).continue_pressed.emit()
	var progress := SpielschuleProgress.new(TEST_CFG)
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		progress.load_from_disk()
		if progress.is_completed("S-09"):
			break
		await get_tree().process_frame
	assert_bool(progress.is_completed("S-09")) \
		.override_failure_message("S-09 not completed: index=%d" % _lesson.current_index()) \
		.is_true()
	await Boot.settle(get_tree())


func test_idle_s09_stays_unfinished(timeout := 60000) -> void:
	await get_tree().create_timer(3.0).timeout
	var progress := SpielschuleProgress.new(TEST_CFG)
	progress.load_from_disk()
	assert_array(SpielschuleLessons.steps_for("S-09")).is_not_empty()
	assert_int(_lesson.current_index()).is_equal(0)
	assert_bool(progress.is_completed("S-09")).is_false()
	await Boot.settle(get_tree())
