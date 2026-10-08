extends GdUnitTestSuite
## E2E walk of Game School chapter 5 (S-05, Shooting) over the real scenes/main.tscn:
## present alpha's card, shoot the in-range squad through the radial's Shoot id + a real targeting
## click, read the log, try the squad behind the building and press Continue — the four steps complete
## the chapter, and an idle boot stays on step 0 and uncompleted.
##
## The refusals are driven through the SAME handler main._unhandled_input feeds, so a "blocked" target
## is proven refused by the real shooting gate (per-model range + line of sight) rather than by calling
## the validator or _run_human_attack, which does not validate at all.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const TEST_CFG := "user://test_game_school_ch5.cfg"
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
	ProjectSettings.set_setting("niemandsland/scenario_path", Spielschule.chapter("S-05").scenario)
	ProjectSettings.set_setting("niemandsland/scenario_chapter", "S-05")
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


func _alive_nodes(unit: GameUnit) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for model in unit.models:
		var mi := model as ModelInstance
		if mi != null and mi.is_alive and is_instance_valid(mi.node):
			out.append(mi.node)
	return out


func _wait_index(target: int) -> bool:
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if _lesson.current_index() == target:
			return true
		await get_tree().process_frame
	return false


func _wait_free(unit: GameUnit) -> bool:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if not unit.is_activated:
			return true
		await get_tree().process_frame
	return false


## The lesson counter (the same snapshot a step check reads) — used to prove a refused pick fired no shot.
func _counter(key: String) -> int:
	return int((_lesson._facts.snapshot().get("counters", {}) as Dictionary).get(key, 0))


func _log_text() -> String:
	var texts := ""
	for entry in _main.battle_log.entries():
		texts += String((entry as Dictionary).get("text", "")) + "\n"
	return texts


## Canvas point (what Camera3D.unproject_position speaks) over a live model of `unit` that the REAL
## pick ray resolves back to that unit — scanned like e2e_mp_los_line.
func _pick_point(unit: GameUnit) -> Vector2:
	var cam: Camera3D = _main.get_viewport().get_camera_3d()
	if cam == null:
		return Vector2.INF
	for node in _alive_nodes(unit):
		for dy in [0.016, 0.03, 0.0]:
			var pt: Vector2 = cam.unproject_position(node.global_position + Vector3(0.0, dy, 0.0))
			if _main._solo_pick_unit_at(pt) == unit:
				return pt
	return Vector2.INF


## The player's targeting click: a real left-button InputEventMouseButton through the SAME handler
## main._unhandled_input feeds.
func _click_target(pt: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pt
	ev.global_position = pt
	await _main._solo_targeting_input(ev)


## The radial wheel's own dispatch (the id the button emits).
func _press(action_id: String, unit: GameUnit) -> void:
	_main.radial_menu_controller._on_action_selected(action_id, {"game_unit": unit})


func _wait_armed(key: String) -> bool:
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if _main._solo_target_mode.has(key):
			return true
		await get_tree().process_frame
	return false


func test_s05_four_steps_complete(timeout := 120000) -> void:
	assert_int(_lesson.current_index()).is_equal(0)
	var alpha := _find("alpha")
	assert_object(alpha).is_not_null()

	_main.unit_dock.present_unit(alpha)
	assert_bool(await _wait_index(1)).is_true()   # card presented

	var far := _find("far")
	assert_object(far).is_not_null()
	var target := _find("target")
	assert_object(target).is_not_null()
	var blocked := _find("blocked")
	assert_object(blocked).is_not_null()

	# Step "shoot": arm through the radial's own "solo_shoot" id, then click. A WRONG pick first — the
	# further Warriors squad is over 24" away, so the real targeting gate refuses it and fires no shot.
	_press("solo_shoot", alpha)
	assert_bool(await _wait_armed("unit")).is_true()
	var before := _counter("shoot:alpha")
	var far_pt := _pick_point(far)
	assert_vector(far_pt).override_failure_message("fixture: no clickable far-squad point").is_not_equal(Vector2.INF)
	await _click_target(far_pt)
	assert_str(_log_text()).override_failure_message("the far squad must be refused as out of range:\n%s" % _log_text()) \
		.contains("out of range")
	assert_int(_counter("shoot:alpha")) \
		.override_failure_message("a refused far pick must not count as a shot") \
		.is_equal(before)
	assert_int(_lesson.current_index()).is_equal(1)   # the refused far shot advanced nothing

	# The right pick stays in the armed window (a refusal swallows the click) — this one fires.
	var target_pt := _pick_point(target)
	assert_vector(target_pt).override_failure_message("fixture: no clickable near-squad point").is_not_equal(Vector2.INF)
	await _click_target(target_pt)
	assert_bool(await _wait_index(2)).is_true()   # shot resolved
	assert_int(_counter("shoot:alpha")).is_greater(before)

	# The read_log step is still active at index 2, so press Continue to reach the blocked step.
	(_main.get_node("UI/LessonCard") as LessonCard).continue_pressed.emit()
	assert_bool(await _wait_index(3)).is_true()   # read_log done, blocked step active

	# Step "blocked": Alpha is free again after the AI's automatic reply turns the round; arm Shoot and
	# click the Guardians behind the building — the real gate refuses for want of line of sight.
	assert_bool(await _wait_free(alpha)) \
		.override_failure_message("Alpha stays activated — the round never advanced, so the blocked attempt cannot be made") \
		.is_true()
	_press("solo_shoot", alpha)
	assert_bool(await _wait_armed("unit")).is_true()
	var shot_before := _counter("shoot:alpha")
	var blocked_pt := _pick_point(blocked)
	assert_vector(blocked_pt).override_failure_message("fixture: no clickable blocked-squad point").is_not_equal(Vector2.INF)
	await _click_target(blocked_pt)
	assert_str(_log_text().to_lower()).override_failure_message("the blocked squad must be refused for want of line of sight:\n%s" % _log_text()) \
		.contains("line of sight")
	assert_int(_counter("shoot:alpha")) \
		.override_failure_message("the blocked pick must not count as a shot") \
		.is_equal(shot_before)

	var progress := SpielschuleProgress.new(TEST_CFG)
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		progress.load_from_disk()
		if progress.is_completed("S-05"):
			break
		await get_tree().process_frame
	assert_bool(progress.is_completed("S-05")) \
		.override_failure_message("S-05 not completed: index=%d" % _lesson.current_index()) \
		.is_true()
	await Boot.settle(get_tree())


func test_idle_s05_stays_unfinished(timeout := 60000) -> void:
	await get_tree().create_timer(3.0).timeout
	var progress := SpielschuleProgress.new(TEST_CFG)
	progress.load_from_disk()
	assert_int(_lesson.current_index()).is_equal(0)
	assert_bool(progress.is_completed("S-05")).is_false()
	await Boot.settle(get_tree())
