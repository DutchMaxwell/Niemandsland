extends GdUnitTestSuite
## E2E walk of Game School chapter 8 (S-08, Terrain) over the real scenes/main.tscn:
## move Alpha into the forest, burn the difficult cap with a real drag, read cover, shoot the enemy
## (the log names the +1), then Rush through the dangerous ground via the real radial action — the six
## steps complete the chapter, and an idle boot stays on step 0.
##
## The cap and the dangerous test are driven through the PLAYER'S OWN paths (ObjectManager's strict
## drag cap; the radial "solo_auto_rush" id + a real targeting click), never by hand-emitted signals
## or the _run_ai_dangerous resolver — that is what this walk is here to pin.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const TEST_CFG := "user://test_game_school_ch8.cfg"
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
	ProjectSettings.set_setting("niemandsland/scenario_path", Spielschule.chapter("S-08").scenario)
	ProjectSettings.set_setting("niemandsland/scenario_chapter", "S-08")
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


func _move_unit_to(unit: GameUnit, spot: Vector3) -> void:
	var nodes := _alive_nodes(unit)
	if nodes.is_empty():
		return
	var centre := Vector3.ZERO
	for node in nodes:
		centre += node.global_position
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


func _wait_free(unit: GameUnit) -> bool:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if not unit.is_activated:
			return true
		await get_tree().process_frame
	return false


## Canvas point (what Camera3D.unproject_position speaks) over a live model of `unit` that the REAL
## pick ray resolves back to that unit — scanned like e2e_mp_los_line so camera framing cannot
## silently starve the suite. INF when nothing clickable was found (a fixture failure, asserted).
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
## main._unhandled_input feeds (main.gd:10619) — the click runs the real pick ray and hands off to
## the armed action, not an internal resolver.
func _click_target(pt: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pt
	ev.global_position = pt
	await _main._solo_targeting_input(ev)


## The radial wheel's own dispatch (the id the button emits), e.g. "solo_shoot" / "solo_auto_rush".
func _press(action_id: String, unit: GameUnit) -> void:
	_main.radial_menu_controller._on_action_selected(action_id, {"game_unit": unit})


func _wait_armed(key: String) -> bool:
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if _main._solo_target_mode.has(key):
			return true
		await get_tree().process_frame
	return false


func _screen(wx: float, wz: float) -> Vector2:
	var cam: Camera3D = _main.get_viewport().get_camera_3d()
	return cam.unproject_position(Vector3(wx, 0.0, wz))


## A real ObjectManager drag of the whole unit through world-inch offsets from its start
## (`points_in`, (x, z) inches; +z is north) — the player's hand on the models, so the strict cap and
## its movement_capped are the SHIPPED ones (never a hand-emitted signal).
func _drag_unit(unit: GameUnit, points_in: Array) -> void:
	var om: Node3D = _main.object_manager
	var nodes := _alive_nodes(unit)
	if nodes.is_empty():
		return
	var centre := Vector3.ZERO
	for node in nodes:
		centre += node.global_position
	centre /= float(nodes.size())
	om._selected_objects.clear()
	for node in nodes:
		om._selected_objects.append(node)
	om._start_dragging(_screen(centre.x, centre.z))
	assert_bool(om._is_dragging) \
		.override_failure_message("fixture: the drag never started — %d selected, %d movable (phase=%d)" % [
			om._selected_objects.size(), om._movable_selection().size(),
			int(_main.opr_army_manager.game_phase)]) \
		.is_true()
	assert_float(om._strict_cap_meters) \
		.override_failure_message("fixture: no strict cap governs the lesson drag (phase=%d)" % int(_main.opr_army_manager.game_phase)) \
		.is_greater(0.0)
	for p in points_in:
		var off: Vector2 = p
		om._update_drag(_screen(centre.x + off.x * INCH, centre.z + off.y * INCH))
		await _runner.simulate_frames(1)
	om._stop_dragging()


func _log_text() -> String:
	var texts := ""
	for entry in _main.battle_log.entries():
		texts += String((entry as Dictionary).get("text", "")) + "\n"
	return texts


func test_s08_six_steps_complete(timeout := 120000) -> void:
	assert_int(_lesson.current_index()).is_equal(0)

	var alpha := _find("alpha")
	assert_object(alpha).is_not_null()
	var target := _find("target")
	assert_object(target).is_not_null()

	_move_unit_to(alpha, Vector3(0.0, 0.0, 7.5 * INCH))
	assert_bool(await _wait_index(1)) \
		.override_failure_message("step 0: Alpha must stand in the forest (index=%d terrain=%d)" % [
			_lesson.current_index(),
			_main.terrain_overlay.get_terrain_at_world_position(_alive_nodes(alpha)[0].global_position)]) \
		.is_true()   # Alpha stands in the forest (difficult terrain)

	# Difficult terrain hard-caps a drag: the SHIPPED strict cap governs a real drag of the unit —
	# ObjectManager._update_drag fires movement_capped off its own (capped) measurement. The hand
	# pushes well past the cap and corrects back, so Alpha keeps its lane for the Rush below.
	await _drag_unit(alpha, [Vector2(0, -3), Vector2(0, -8), Vector2(0, -14), Vector2(0, -7), Vector2.ZERO])
	assert_bool(await _wait_index(2)).is_true()   # the cap was experienced

	var card := _main.get_node("UI/LessonCard") as LessonCard
	card.continue_pressed.emit()
	assert_bool(await _wait_index(3)).is_true()   # cover read

	# Shoot through the radial's own "solo_shoot" id, then a real targeting click on the enemy.
	_press("solo_shoot", alpha)
	assert_bool(await _wait_armed("unit")).is_true()
	var target_pt := _pick_point(target)
	assert_vector(target_pt).override_failure_message("fixture: no clickable enemy point found").is_not_equal(Vector2.INF)
	await _click_target(target_pt)
	assert_bool(await _wait_index(4)).is_true()   # the volley fired and logged the cover bonus
	assert_bool(_log_text().to_lower().contains("cover")) \
		.override_failure_message("no cover line in the battle log:\n%s" % _log_text()) \
		.is_true()

	# The volley consumed Alpha's activation and NACHTMAHR answered; with only these two units the
	# round turns over, which frees Alpha for the Rush the next step commands.
	assert_bool(await _wait_free(alpha)) \
		.override_failure_message("Alpha stays activated after its volley — the round never advanced, so the commanded Rush would be refused") \
		.is_true()

	# Dangerous ground: the radial's "solo_auto_rush" id + a real click on the enemy runs the ENGINE
	# rush (player_intent -> execute_intent), whose route crosses the full-width band.
	_press("solo_auto_rush", alpha)
	assert_bool(await _wait_armed("auto_verb")).is_true()
	var rush_pt := _pick_point(target)
	assert_vector(rush_pt).override_failure_message("fixture: no clickable enemy point for the Rush").is_not_equal(Vector2.INF)
	await _click_target(rush_pt)
	assert_bool(await _wait_index(5)).is_true()   # the dangerous test was rolled
	assert_bool(_log_text().to_lower().contains("dangerous terrain")) \
		.override_failure_message("the player's Rush never crossed the dangerous ground:\n%s" % _log_text()) \
		.is_true()

	card.continue_pressed.emit()
	var progress := SpielschuleProgress.new(TEST_CFG)
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		progress.load_from_disk()
		if progress.is_completed("S-08"):
			break
		await get_tree().process_frame
	assert_bool(progress.is_completed("S-08")) \
		.override_failure_message("S-08 not completed: index=%d" % _lesson.current_index()) \
		.is_true()
	await Boot.settle(get_tree())


func test_idle_s08_stays_unfinished(timeout := 60000) -> void:
	await get_tree().create_timer(3.0).timeout
	var progress := SpielschuleProgress.new(TEST_CFG)
	progress.load_from_disk()
	assert_array(SpielschuleLessons.steps_for("S-08")).is_not_empty()
	assert_int(_lesson.current_index()).is_equal(0)
	assert_bool(progress.is_completed("S-08")).is_false()
	await Boot.settle(get_tree())
