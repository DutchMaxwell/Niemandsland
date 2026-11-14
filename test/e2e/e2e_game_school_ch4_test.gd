extends GdUnitTestSuite
## E2E walk of Game School chapter 4 (S-04, Activate & Move) over the real scenes/main.tscn:
## show the movement bands, advance and activate alpha, let the held AI answer, rush and activate
## bravo, then advance the round — the five steps complete the chapter.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const Flow := preload("res://test/e2e/school_flow.gd")
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
	CoreActivation._env = 1   # the explicit activation (the lesson teaches it); the kill switch is not under test here
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
	CoreActivation._env = -1
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


func _wait_activated(unit: GameUnit) -> bool:
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		if unit.is_activated:
			return true
		await get_tree().process_frame
	return false


func _wait_round(target: int) -> bool:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if int(_main.opr_army_manager.current_round) == target:
			return true
		await get_tree().process_frame
	return false


func test_s04_eight_steps_complete(timeout := 180000) -> void:
	assert_int(_lesson.current_index()).is_equal(0)
	var alpha := _find("alpha")
	assert_object(alpha).is_not_null()
	var nodes: Array = []
	for model in alpha.models:
		nodes.append(model.node)
	_main.movement_range_controller.toggle(nodes)
	assert_bool(await _wait_index(1)).is_true()   # bands shown

	# Activate: the card's button opens the activation.
	Flow.select(_main, alpha)
	assert_bool(Flow.press(_main, "Activate")).override_failure_message("no Activate button on Alpha's card").is_true()
	assert_bool(await _wait_index(2)).override_failure_message("index=%d" % _lesson.current_index()).is_true()
	# Advance: the Movement row's Advance, then a real drag moves the unit.
	Flow.set_mode(_main, ObjectManager.MovementCap.ADVANCE)
	await Flow.drag(_main, get_tree(), alpha, 5.0, 0.0)
	assert_bool(await _wait_index(3)).override_failure_message("index=%d" % _lesson.current_index()).is_true()
	# Cancel: the unit is back at its start, the activation is closed.
	var at: Vector3 = (alpha.models[0] as ModelInstance).node.global_position
	assert_bool(Flow.press(_main, "Cancel")).override_failure_message("no Cancel button").is_true()
	assert_bool(await _wait_index(4)).override_failure_message("index=%d" % _lesson.current_index()).is_true()
	assert_float((alpha.models[0] as ModelInstance).node.global_position.distance_to(at)).is_greater(0.05)
	# Activate again, move, End activation: the unit has acted and the held AI answers.
	Flow.select(_main, alpha)
	assert_bool(Flow.press(_main, "Activate")).is_true()
	Flow.set_mode(_main, ObjectManager.MovementCap.ADVANCE)
	await Flow.drag(_main, get_tree(), alpha, 5.0, 0.0)
	assert_bool(Flow.press(_main, "End activation")).override_failure_message("no End activation button").is_true()
	assert_bool(await _wait_activated(alpha)).is_true()
	assert_bool(await _wait_index(6)).override_failure_message("ai turn: index=%d" % _lesson.current_index()).is_true()

	# Rush: Bravo, Rush in the Movement row, more than 6" - End activation ends the last unit, so round 2 begins.
	var bravo := _find("bravo")
	assert_object(bravo).is_not_null()
	Flow.select(_main, bravo)
	assert_bool(Flow.press(_main, "Activate")).is_true()
	Flow.set_mode(_main, ObjectManager.MovementCap.RUSH)
	await Flow.drag(_main, get_tree(), bravo, 0.0, 9.0)
	assert_bool(Flow.press(_main, "End activation")).is_true()
	# Activating the LAST unit ends round 1 in the same pump — no Next Round press. The round is the
	# persistent signal (bravo's own activated flag resets with the round).
	assert_bool(await _wait_round(2)) \
		.override_failure_message("round 2 not reached: index=%d round=%d bravo_activated=%s" % [
			_lesson.current_index(), _main.opr_army_manager.current_round, str(bravo.is_activated)]) \
		.is_true()
	var reached := await _wait_index(7)
	assert_bool(reached) \
		.override_failure_message("index 7 (round advanced) not reached: index=%d round=%d" % [
			_lesson.current_index(), _main.opr_army_manager.current_round]) \
		.is_true()

	(_main.get_node("UI/LessonCard") as LessonCard).continue_pressed.emit()
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
