extends GdUnitTestSuite
## E2E walk of Game School chapter 6 (S-06, Melee) over the real scenes/main.tscn:
## move alpha into contact, resolve the melee (the defender piles in, strikes back and consolidates)
## — the five steps complete the chapter, and an idle boot stays on step 0 and uncompleted.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const TEST_CFG := "user://test_game_school_ch6.cfg"
const FLAGS := ["niemandsland/scenario_mode", "niemandsland/scenario_path",
	"niemandsland/scenario_chapter", "niemandsland/pending_load_path"]

var _saved: Dictionary = {}
var _root_before: Array
var _runner: GdUnitSceneRunner
var _main: Node
var _lesson: LessonRunner
var _pump: Timer


func before_test() -> void:
	_root_before = Boot.root_children(get_tree())
	for flag in FLAGS:
		_saved[flag] = ProjectSettings.get_setting(flag)
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))
	ProjectSettings.set_setting("niemandsland/scenario_mode", true)
	ProjectSettings.set_setting("niemandsland/scenario_path", Spielschule.chapter("S-06").scenario)
	ProjectSettings.set_setting("niemandsland/scenario_chapter", "S-06")
	ProjectSettings.set_setting("niemandsland/pending_load_path", "")
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	_main._lesson_progress_path = TEST_CFG
	await _main.save_manager.load_completed
	_lesson = _main.get_node("LessonRunner") as LessonRunner
	_main._solo_fast = true
	_main._solo_batch = true   # headless melee: instant fair dice + the consolidation board prompt auto-answered
	_arm_save_pump()


func after_test() -> void:
	for flag in FLAGS:
		ProjectSettings.set_setting(flag, _saved[flag])
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))
	Boot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## _run_human_melee awaits the human's OWN save confirmation for the AI's strike-back ("Incoming
## fire!" PromptCard) — no headless run can click it, so a repeating timer answers it.
func _arm_save_pump() -> void:
	_pump = Timer.new()
	_pump.name = "MeleeSavePump"
	_pump.wait_time = 0.02
	_pump.one_shot = false
	get_tree().root.add_child(_pump)
	_pump.timeout.connect(_answer_save_prompt)
	_pump.start()


func _answer_save_prompt() -> void:
	if _main == null or not is_instance_valid(_main):
		return
	for c in _main.get_children():
		var card := c as PromptCard
		if card != null and card.title == "Incoming fire!":
			card.ok_button.pressed.emit()


func _find(tag: String) -> GameUnit:
	for unit in _main.opr_army_manager.get_all_game_units():
		if unit is GameUnit and String(unit.unit_properties.get("lesson_tag", "")) == tag:
			return unit
	return null


func _unit_centre_in(unit: GameUnit) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for model in unit.models:
		if is_instance_valid(model.node):
			sum += Vector2(model.node.global_position.x, model.node.global_position.z)
			n += 1
	return sum / float(n) / INCH if n > 0 else Vector2.ZERO


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


func test_s06_five_steps_complete(timeout := 60000) -> void:
	assert_int(_lesson.current_index()).is_equal(0)
	var alpha := _find("alpha")
	assert_object(alpha).is_not_null()
	var target := _find("target")
	assert_object(target).is_not_null()

	var spot := Vector3(_unit_centre_in(target).x * INCH, 0.0, _unit_centre_in(target).y * INCH + 2.0 * INCH)
	_move_unit_to(alpha, spot)
	assert_bool(await _wait_index(1)).is_true()   # charge reached contact

	await _main._run_human_attack(alpha, target, true)

	var progress := SpielschuleProgress.new(TEST_CFG)
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		progress.load_from_disk()
		if progress.is_completed("S-06"):
			break
		await get_tree().process_frame
	assert_bool(progress.is_completed("S-06")) \
		.override_failure_message("S-06 not completed: index=%d" % _lesson.current_index()) \
		.is_true()
	await Boot.settle(get_tree())


func test_idle_s06_stays_unfinished(timeout := 60000) -> void:
	await get_tree().create_timer(3.0).timeout
	var progress := SpielschuleProgress.new(TEST_CFG)
	progress.load_from_disk()
	assert_int(_lesson.current_index()).is_equal(0)
	assert_bool(progress.is_completed("S-06")).is_false()
	await Boot.settle(get_tree())
