extends GdUnitTestSuite
## E2E — Automodus PR 3 (NML-202): Rush through the shared executor. A plain unit closes up to its
## 12" Rush band toward the enemy with no volley; a Quick Shot bearer keeps its shot after the Rush
## (the executor's post-move can_shoot re-gate, army-book) — both complete the activation and book
## the AI's reply (pattern: e2e_auto_advance_test.gd).

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
	MovementPlanner.fast_planner = false   # deterministic geometry — see e2e_auto_advance_test.gd
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_fast = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, pos: Vector3, range_in: int, rules: Array = []) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	u.unit_properties["special_rules"] = rules
	if range_in > 0:
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
	_unit(1, "Reserves", Vector3(50.0 * INCH, 0, 0), 0)
	_unit(2, "Watchers", Vector3(-50.0 * INCH, 0, 0), 0)


func test_plain_rush_closes_the_band_with_no_volley(timeout := 60000) -> void:
	_bystanders()
	var runner := _unit(1, "Runners", Vector3.ZERO, 0)
	var enemy := _unit(2, "Foe", Vector3(20.0 * INCH, 0, 0), 0)
	enemy.is_activated = true   # stays put — Watchers is the AI's eligible reply, not Foe itself
	await _main._run_player_intent(runner, AiDecision.Action.RUSH, enemy)
	# _solo_animate_move glides on a real SceneTreeTimer (wall-clock, not frame-based) — under this
	# shared box's CPU pressure gdUnit's scheduler occasionally needs more than 4 frames to catch an
	# already-fired timeout (see e2e_auto_advance_test.gd, same fix).
	await E2EBoot.settle(get_tree(), 30)
	assert_float(_dist_in(runner, enemy)).is_equal_approx(8.0, 0.5)   # 20" - the 12" Rush band
	var text := _log_text()
	assert_str(text).contains("Auto:")
	assert_str(text).contains("rushes")
	assert_str(text).not_contains("fires")
	assert_bool(runner.is_activated).is_true()
	assert_int(_main._solo_pending_replies) \
		.override_failure_message("the AI's answering activation was never booked/resolved") \
		.is_equal(0)


func test_quick_shot_bearer_fires_after_its_rush(timeout := 60000) -> void:
	_bystanders()
	var runner := _unit(1, "Skirmishers", Vector3.ZERO, 12, ["Quick Shot"])
	# RulesRegistry.unit_rule_active needs a faction where "Quick Shot" is a defined primitive
	# (it is faction-scoped in the gf rules mechanics map, not a common rule).
	runner.unit_properties["faction_folder"] = "goblin_reclaimers"
	var enemy := _unit(2, "Foe", Vector3(20.0 * INCH, 0, 0), 0)
	enemy.is_activated = true   # stays put — Watchers is the AI's eligible reply, not Foe itself
	await _main._run_player_intent(runner, AiDecision.Action.RUSH, enemy)
	await E2EBoot.settle(get_tree(), 30)
	assert_float(_dist_in(runner, enemy)).is_equal_approx(8.0, 0.5)
	var text := _log_text()
	assert_str(text).contains("rushes")
	assert_str(text) \
		.override_failure_message("no Quick Shot note in the log (log: %s)" % text.strip_edges()) \
		.contains("Quick Shot")
	assert_str(text) \
		.override_failure_message("Quick Shot bearer never fired after its Rush (log: %s)" % text.strip_edges()) \
		.contains("fires")
	assert_bool(runner.is_activated).is_true()
