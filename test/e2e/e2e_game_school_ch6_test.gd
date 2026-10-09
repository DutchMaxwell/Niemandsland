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
		var mi := model as ModelInstance
		if mi != null and not mi.is_alive:
			continue   # parked casualties sit on the dead tray, far from the fight
		if is_instance_valid(model.node):
			sum += Vector2(model.node.global_position.x, model.node.global_position.z)
			n += 1
	return sum / float(n) / INCH if n > 0 else Vector2.ZERO


func _move_unit_to(unit: GameUnit, spot: Vector3) -> void:
	var nodes: Array[Node3D] = []
	var centre := Vector3.ZERO
	for model in unit.models:
		var mi := model as ModelInstance
		if mi != null and not mi.is_alive:
			continue   # parked casualties sit on the dead tray, far from the fight
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


## Emit one Continue press and wait (bounded) until the runner leaves `from_index` — either it advanced
## or the chapter completed. Never fire two Continue presses back-to-back without this wait.
func _continue_and_wait(from_index: int) -> bool:
	var card := _main.get_node("UI/LessonCard") as LessonCard
	card.continue_pressed.emit()
	var progress := SpielschuleProgress.new(TEST_CFG)
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if _lesson.current_index() > from_index:
			return true
		progress.load_from_disk()
		if progress.is_completed("S-06"):
			return true
		await get_tree().process_frame
	return false


## Battle-log lines that mention a consolidation (the S-06 marker `log:consolidate` reads the same text).
func _consolidation_lines() -> int:
	var n := 0
	for entry in _main.battle_log.entries():
		if String(entry.get("text", "")).to_lower().contains("consolidat"):
			n += 1
	return n


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

	# The whole melee resolves inside that one call: pile-in, strike-back and consolidation all
	# happened, so the last three steps (each "then press Continue") need three Continue presses.
	# Each press waits (bounded) for the runner to leave the step, so no two land back-to-back.
	assert_bool(await _wait_index(2)).is_true()   # the fight resolved, pile-in step is current
	assert_bool(await _continue_and_wait(2)).is_true()   # pile-in read
	assert_bool(await _continue_and_wait(3)).is_true()   # strike-back read
	assert_bool(await _continue_and_wait(4)).is_true()   # the last read; the chapter completes

	var progress := SpielschuleProgress.new(TEST_CFG)
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		progress.load_from_disk()
		if progress.is_completed("S-06"):
			break
		await get_tree().process_frame
	assert_bool(progress.is_completed("S-06")) \
		.override_failure_message("S-06 not completed: index=%d counters=%s base=%s" % [
			_lesson.current_index(), _lesson._facts.snapshot().counters, _lesson._base.get("counters", {})]) \
		.is_true()
	await Boot.settle(get_tree())


## The ch6 flake: when the strike-back wipes Alpha, the AI survivor (the enemy squad) often has
## nowhere to consolidate, and `_solo_consolidate_melee` logged NOTHING on that empty-move branch —
## so `log:consolidate` never fired and S-06 step 4 could never pass. The rule is applied even with
## an empty move, so it must still log (house rule: every applied rule logs).
func test_ai_survivor_without_a_move_still_logs_consolidation(timeout := 60000) -> void:
	var alpha := _find("alpha")
	var target := _find("target")
	assert_object(alpha).is_not_null()
	assert_object(target).is_not_null()
	for model in alpha.models:
		(model as ModelInstance).is_alive = false   # simulate the strike-back wiping Alpha
	assert_bool(alpha.is_destroyed()).is_true()

	var before := _consolidation_lines()
	await _main._solo_consolidate_melee(alpha, target)   # the AI survivor has no enemy and no objective

	assert_int(_consolidation_lines()) \
		.override_failure_message("the held-ground AI survivor must still log a consolidation line") \
		.is_greater(before)
	await Boot.settle(get_tree())


func test_idle_s06_stays_unfinished(timeout := 60000) -> void:
	await get_tree().create_timer(3.0).timeout
	var progress := SpielschuleProgress.new(TEST_CFG)
	progress.load_from_disk()
	assert_array(SpielschuleLessons.steps_for("S-06")).is_not_empty()
	assert_int(_lesson.current_index()).is_equal(0)
	assert_bool(progress.is_completed("S-06")).is_false()
	await Boot.settle(get_tree())
