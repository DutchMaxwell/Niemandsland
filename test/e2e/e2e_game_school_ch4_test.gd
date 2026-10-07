extends GdUnitTestSuite
## E2E walk of Game School chapter 4 (S-04, Activate & Move) over the real scenes/main.tscn:
## show the movement bands, advance and activate alpha, let the held AI answer, rush and activate
## bravo, then advance the round — the five steps complete the chapter.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const TEST_CFG := "user://test_game_school_ch4.cfg"
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
	ProjectSettings.set_setting("niemandsland/scenario_path", Spielschule.chapter("S-04").scenario)
	ProjectSettings.set_setting("niemandsland/scenario_chapter", "S-04")
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


func _find(tag: String) -> GameUnit:
	for unit in _main.opr_army_manager.get_all_game_units():
		if unit is GameUnit and String(unit.unit_properties.get("lesson_tag", "")) == tag:
			return unit
	return null


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


func _wait_index(target: int) -> bool:
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if _lesson.current_index() == target:
			return true
		await get_tree().process_frame
	return false


func _wait_activated(unit: GameUnit) -> bool:
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		if unit.is_activated:
			return true
		await get_tree().process_frame
	return false


func _activate(unit: GameUnit) -> bool:
	_main.radial_menu_controller.card_toggle_activation(unit)
	return await _wait_activated(unit)


func test_s04_five_steps_complete(timeout := 120000) -> void:
	assert_int(_lesson.current_index()).is_equal(0)
	var alpha := _find("alpha")
	assert_object(alpha).is_not_null()
	var nodes: Array = []
	for model in alpha.models:
		nodes.append(model.node)
	_main.movement_range_controller.toggle(nodes)
	assert_bool(await _wait_index(1)).is_true()   # bands shown

	_move_unit_to(alpha, Vector3(-8.0 * INCH, 0, 18.0 * INCH))
	assert_bool(await _activate(alpha)).is_true()
	var target := _find("target")
	assert_object(target).is_not_null()
	if not await _wait_activated(target):   # the held AI's owed reply
		await _main._solo_activate_one_ai()
	assert_bool(await _wait_index(3)).is_true()   # alpha advanced+activated, AI replied

	var bravo := _find("bravo")
	assert_object(bravo).is_not_null()
	_move_unit_to(bravo, Vector3(8.0 * INCH, 0, 23.0 * INCH))
	var bravo_ok := await _activate(bravo)
	assert_bool(bravo_ok) \
		.override_failure_message("bravo did not activate (index=%d)" % _lesson.current_index()) \
		.is_true()
	var reached := await _wait_index(4)
	assert_bool(reached) \
		.override_failure_message("step3 not reached: index=%d bravo_activated=%s round=%d" % [
			_lesson.current_index(), str(bravo.is_activated), _main.opr_army_manager.current_round]) \
		.is_true()   # bravo rushed+activated

	await _main._do_next_round()   # the Next Round button's action
	var progress := SpielschuleProgress.new(TEST_CFG)
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		progress.load_from_disk()
		if progress.is_completed("S-04"):
			break
		await get_tree().process_frame
	assert_bool(progress.is_completed("S-04")).is_true()
	await Boot.settle(get_tree())


func test_idle_s04_stays_unfinished(timeout := 60000) -> void:
	await get_tree().create_timer(3.0).timeout
	var progress := SpielschuleProgress.new(TEST_CFG)
	progress.load_from_disk()
	assert_int(_lesson.current_index()).is_equal(0)
	assert_bool(progress.is_completed("S-04")).is_false()
	await Boot.settle(get_tree())
