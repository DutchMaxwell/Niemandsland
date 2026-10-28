extends GdUnitTestSuite
## E2E — Automodus rework step 1.5: main's _solo_preview_for runs the player's verb through the one
## executor in its sandbox (preview_intent) and reads the shooting lines AT THE LANDING through the
## volley's own sight truth (_solo_volley_sighted). Nothing moves; a refusal comes back as is
## (boot pattern: e2e_auto_advance_test.gd).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	MovementPlanner.fast_planner = false   # deterministic precise planner (as e2e_auto_advance_test.gd)
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_fast = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## `models` models in a line across the firing lane (1.5" apart), each with one 12" rifle.
func _shooter(pid: int, unit_name: String, x_in: float, models := 1) -> GameUnit:
	var spots: Array = []
	for i in models:
		spots.append(Vector3(x_in * INCH, 0, (i - (models - 1) / 2.0) * 1.5 * INCH))
	var u := E2EBoot.make_unit(_main, pid, unit_name, spots)
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 12
	w.attacks = 1
	opr.weapons = [w]
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _board() -> Array:
	var out: Array = []
	for u in _main.opr_army_manager.game_units.values():
		out.append_array(SoloController.alive_positions(u as GameUnit))
	return out


## The N of the volley's "<unit>: N/M models with line of sight + range" log line (-1 when absent).
func _logged_sighted(unit_name: String) -> int:
	var re := RegEx.create_from_string("%s: (\\d+)/\\d+ models? with line of sight \\+ range" % unit_name)
	for e in _main.battle_log.entries():
		var hit := re.search(str((e as Dictionary)["text"]))
		if hit != null:
			return int(hit.get_string(1))
	return -1


func test_preview_shows_landing_and_shooters(timeout := 60000) -> void:
	_shooter(2, "Watchers", -50.0)   # the AI's eligible reply, far off (e2e_auto_advance_test.gd)
	var shooter := _shooter(1, "Riflemen", 0.0, 3)
	var enemy := _shooter(2, "Foe", 16.0)   # out of the 12" reach now, inside it after a 6" Advance
	enemy.is_activated = true
	assert_int(_main._solo_volley_sighted(shooter, enemy)).is_equal(0)
	var board_before := _board()
	var preview: Dictionary = _main._solo_preview_for(shooter, AiDecision.Action.ADVANCE, enemy)
	assert_array(_board()).is_equal(board_before)
	var landing: Array = preview.get("landing", [])
	assert_int(landing.size()).is_equal(shooter.get_alive_models().size())
	var lines: Array = preview.get("lines", [])
	assert_int(lines.size()).override_failure_message("no shooting line from the landing").is_greater(0)
	for line in lines:   # every line starts at a landing ghost, never at the model's current spot
		assert_bool(landing.any(func(l: Dictionary) -> bool:
			return (l["pos"] as Vector3).is_equal_approx(line["from"]))).is_true()
	await _main._run_player_intent(shooter, AiDecision.Action.ADVANCE, enemy)
	await E2EBoot.settle(get_tree())
	assert_int(lines.size()).is_equal(_logged_sighted("Riflemen"))


func test_charge_preview_has_no_lines(timeout := 60000) -> void:
	var charger := _shooter(1, "Chargers", 0.0, 3)
	var enemy := _shooter(2, "Foe", 8.0)
	var board_before := _board()
	var preview: Dictionary = _main._solo_preview_for(charger, AiDecision.Action.CHARGE, enemy)
	assert_int((preview.get("landing", []) as Array).size()).is_equal(3)
	assert_array(preview.get("lines", ["missing"])).is_empty()
	assert_array(_board()).is_equal(board_before)


func test_shaken_preview_is_refused_and_moves_nothing(timeout := 60000) -> void:
	var shaky := _shooter(1, "Shaky", 0.0, 3)
	shaky.is_shaken = true
	var enemy := _shooter(2, "Foe", 16.0)
	var board_before := _board()
	var preview: Dictionary = _main._solo_preview_for(shaky, AiDecision.Action.ADVANCE, enemy)
	assert_str(str(preview.get("refused", ""))).contains("Shaken")
	assert_bool(preview.has("landing")).is_false()
	assert_array(_board()).is_equal(board_before)


# --- Automodus step 1.7: hover shows the preview; leaving, Esc or right-click clears it ---

## A one-model rifle unit whose model is a REAL spawned miniature (StaticBody3D + collider), so the
## real pick ray can hit it (pattern: e2e_mp_los_line_test.gd).
func _pickable(pid: int, unit_name: String, x_in: float) -> GameUnit:
	var u := _shooter(pid, unit_name, x_in)
	var m := u.models[0] as ModelInstance
	var body: Node3D = (_main.object_manager as Object).call("spawn_miniature", m.node.global_position, false)
	body.set_meta("game_unit", u)
	m.node.queue_free()
	m.node = body
	return u


## A screen point the real pick ray resolves to `u` (INF when none: a fixture failure, asserted).
func _pick_point(u: GameUnit) -> Vector2:
	var cam: Camera3D = _main.get_viewport().get_camera_3d()
	var node: Node3D = (u.models[0] as ModelInstance).node
	for dy in [0.016, 0.03, 0.0]:
		var pt: Vector2 = cam.unproject_position(node.global_position + Vector3(0.0, dy, 0.0))
		if _main._solo_pick_unit_at(pt) == u:
			return pt
	return Vector2.INF


## The mouse moving over `pt` through the SAME targeting handler main._unhandled_input feeds.
func _hover(pt: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pt
	ev.global_position = pt
	await _main._solo_targeting_input(ev)


func test_hover_shows_and_clears_the_preview(timeout := 60000) -> void:
	var shooter := _shooter(1, "Riflemen", 0.0, 3)
	var foe := _pickable(2, "Foe", 16.0)   # inside the 12" rifle after a 6" Advance: lines exist
	await _runner.simulate_frames(1)   # the pick is a raycast: let physics register the fresh body
	var pt := _pick_point(foe)
	assert_bool(pt.is_finite()).override_failure_message("fixture: the pick ray never hits Foe").is_true()
	await _main.solo_begin_auto(shooter, AiDecision.Action.ADVANCE)
	var ghosts: LandingPreview = _main.landing_preview
	await _hover(pt)
	var previews: Dictionary = _main._solo_target_mode.get("auto_previews", {})
	var lines: Array = (previews.get(foe.get_instance_id(), {}) as Dictionary).get("lines", [])
	assert_int(ghosts.ghost_count()).is_equal(shooter.get_alive_models().size())
	assert_int(lines.size()).override_failure_message("fixture: no shooting line at the landing").is_greater(0)
	assert_int(ghosts.line_count()).is_equal(lines.size())
	assert_object(_main._solo_los_line).override_failure_message("auto_verb hover drew the LOS line").is_null()
	var shown := ghosts.get_child(0)
	await _hover(pt)   # the same target again: no new planner run, no rebuild
	assert_int(previews.size()).is_equal(1)
	assert_object(ghosts.get_child(0)).is_same(shown)
	_main._solo_show_auto_preview(null)   # leaving: the empty table
	assert_int(ghosts.ghost_count()).is_equal(0)
	_main._solo_show_auto_preview(shooter)   # the own unit is not a lit target
	assert_int(ghosts.ghost_count()).is_equal(0)
	# Back on Foe the CACHED preview shows (a marked entry proves the planner did not run again).
	previews[foe.get_instance_id()] = {"landing": [{"pos": Vector3.ZERO, "radius_m": 0.0125}], "lines": []}
	await _hover(pt)
	assert_int(ghosts.ghost_count()).is_equal(1)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	await _main._solo_targeting_input(right_click)
	assert_bool(_main._solo_target_mode.is_empty()).is_true()
	assert_int(ghosts.ghost_count() + ghosts.line_count()).is_equal(0)


func test_esc_clears_the_hover_preview(timeout := 60000) -> void:
	var shooter := _shooter(1, "Riflemen", 0.0, 3)
	var foe := _shooter(2, "Foe", 16.0)
	await _main.solo_begin_auto(shooter, AiDecision.Action.ADVANCE)
	_main._solo_show_auto_preview(foe)
	assert_int(_main.landing_preview.ghost_count()).is_equal(3)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	await _main._solo_targeting_input(esc)
	assert_bool(_main._solo_target_mode.is_empty()).is_true()
	assert_int(_main.landing_preview.ghost_count()).is_equal(0)


func test_a_refused_hover_shows_nothing_and_says_why_once(timeout := 60000) -> void:
	var shooter := _shooter(1, "Riflemen", 0.0, 3)
	var foe := _shooter(2, "Foe", 16.0)
	await _main.solo_begin_auto(shooter, AiDecision.Action.ADVANCE)
	shooter.is_shaken = true   # lit at entry, refused by the time it is hovered
	var board_before := _board()
	for t in [foe, null, foe]:
		_main._solo_show_auto_preview(t)
	assert_int(_main.landing_preview.ghost_count()).is_equal(0)
	assert_array(_board()).is_equal(board_before)
	var said := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).begins_with("Auto: no preview for Foe (Shaken"):
			said += 1
	assert_int(said).is_equal(1)
	_main._solo_end_targeting()
