extends GdUnitTestSuite
## E2E — Automodus PR 3 (NML-202): Advance & Shoot through the shared executor. An out-of-range
## Advance closes in and fires; an already-in-range Advance kites back to the range edge and still
## fires; a blocked line of sight completes the activation with the "no shot" rule note instead of a
## volley (patterns: e2e_speed_feat_radial_test.gd, e2e_los_refusal_detail_test.gd for the LOS block).

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
	# Pin the movement-planner statics AFTER _ensure_solo_controller (which flips fast_planner to
	# true) — the precise planner keeps the kite/advance geometry this suite measures deterministic
	# (solo_controller_test.gd's own lesson about this process-wide static leaking between suites).
	MovementPlanner.fast_planner = false
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_fast = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _shooter(pid: int, unit_name: String, pos: Vector3, range_in: int) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = range_in
	w.attacks = 1
	opr.weapons = [w]
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _dist_in(a: GameUnit, b: GameUnit) -> float:
	return MoveIntent.distance_inches(_main.solo_controller.unit_centre(a), _main.solo_controller.unit_centre(b))


## Bystanders so the AI's one owed reply doesn't exhaust both sides at once — a 1v1 fixture's round
## would auto-advance a frame later and reset is_activated before the test can read it.
func _bystanders() -> void:
	_shooter(1, "Reserves", Vector3(50.0 * INCH, 0, 0), 12)
	_shooter(2, "Watchers", Vector3(-50.0 * INCH, 0, 0), 12)


func test_advance_out_of_range_closes_in_and_fires(timeout := 60000) -> void:
	_bystanders()
	var shooter := _shooter(1, "Riflemen", Vector3.ZERO, 12)
	var enemy := _shooter(2, "Foe", Vector3(14.0 * INCH, 0, 0), 12)
	enemy.is_activated = true   # stays put — Watchers is the AI's eligible reply, not Foe itself
	await _main._run_player_intent(shooter, AiDecision.Action.ADVANCE, enemy)
	await E2EBoot.settle(get_tree())
	assert_float(_dist_in(shooter, enemy)).is_less_equal(12.0)
	var text := _log_text()
	assert_str(text).contains("Auto:")
	assert_str(text) \
		.override_failure_message("no volley after the advance closed into range (log: %s)" % text.strip_edges()) \
		.contains("fires")
	assert_bool(shooter.is_activated).is_true()


func test_advance_already_in_range_kites_back_and_still_fires(timeout := 60000) -> void:
	_bystanders()
	var shooter := _shooter(1, "Riflemen", Vector3.ZERO, 12)
	var enemy := _shooter(2, "Foe", Vector3(5.0 * INCH, 0, 0), 12)
	enemy.is_activated = true   # stays put — Watchers is the AI's eligible reply, not Foe itself
	await _main._run_player_intent(shooter, AiDecision.Action.ADVANCE, enemy)
	# _solo_animate_move glides the kite step on a REAL SceneTreeTimer (measured wall-clock, not
	# frame-based) — under CPU pressure from other lanes on this shared box, gdUnit's own coroutine
	# scheduler occasionally needs more than the standard 4-frame settle to catch the already-fired
	# timeout and apply the model's final position. More frames, not a fixed sleep, keeps this a
	# real-condition wait rather than a guessed duration.
	await E2EBoot.settle(get_tree(), 30)
	var dist := _dist_in(shooter, enemy)
	assert_float(dist) \
		.override_failure_message("the kite did not step the shooter away (dist=%.2f\")" % dist) \
		.is_greater(5.0)
	assert_float(dist).is_less_equal(12.0)
	assert_str(_log_text()).contains("fires")


func test_advance_with_blocked_los_completes_with_no_shot_note(timeout := 60000) -> void:
	_bystanders()
	var shooter := _shooter(1, "Riflemen", Vector3.ZERO, 12)
	var enemy := _shooter(2, "Foe", Vector3(14.0 * INCH, 0, 0), 12)
	enemy.is_activated = true   # stays put — Watchers is the AI's eligible reply, not Foe itself
	# A blocker planted right in front of the target, not the shooter's starting spot: the Advance
	# moves the shooter itself, so a wall fixed near the origin would end up behind it instead of on
	# the lane. Same trick as e2e_los_refusal_detail_test.gd ("OTHER units, friendly or enemy, block").
	var wall := _shooter(2, "Wall", Vector3(13.0 * INCH, 0, 0), 12)
	wall.is_activated = true
	await _main._run_player_intent(shooter, AiDecision.Action.ADVANCE, enemy)
	await E2EBoot.settle(get_tree())
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("no 'no shot' rule note in the log (log: %s)" % text.strip_edges()) \
		.contains("no shot")
	assert_str(text).not_contains("fires")
	assert_bool(shooter.is_activated).is_true()
