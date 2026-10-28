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
