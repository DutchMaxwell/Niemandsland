extends GdUnitTestSuite
## "No AI without its tick" (#1719), the mission state. Start Deployment (AI seat only since #1830) applies
## the picked mission into SoloController's statics: scoring, the VP ledger, the marker metadata and the
## roles. They outlived the tick and Clear Table, so a later two-human game booked a mission it never set
## up ("Mission VP after round …", "Mission VP (decides)") and a cleared table kept the last game's ledger.
## Real: scenes/main.tscn, the real tick toggle, the mission step Start Deployment runs
## (_solo_apply_mission_if_chosen), Clear Table's action and the real hotseat round end.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _saved: Dictionary


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_saved = SoloController.mission_state_to_dict("")   # the statics outlive the scene: put them back after
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main._solo_batch = true
	_main._solo_auto_saves = true
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC


func after_test() -> void:
	SoloController.mission_state_from_dict(_saved)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _reg(pid: int, unit_name: String, x_in: float, models: int = 1) -> GameUnit:
	var at: Array = []
	for i in models:
		at.append(Vector3(x_in * INCH, 0.0, 0.02 * i))
	var u := E2EBoot.make_unit(_main, pid, unit_name, at)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_from(start: int) -> String:
	var t := ""
	for e in _main.battle_log.entries().slice(start):
		t += str((e as Dictionary)["text"]) + "\n"
	return t


func _activate(unit: GameUnit) -> void:
	await _main.radial_menu_controller._toggle_activation({"game_unit": unit})
	await _runner.simulate_frames(4)
	await E2EBoot.settle(get_tree())


## A game against NACHTMAHR with a mission: P2 ticked, a round-VP mission applied the way Start Deployment
## applies it, and some VP booked.
func _ticked_mission_game() -> void:
	_main._on_solo_ai_toggled(true, 2)
	_main._ensure_solo_controller()
	_main._solo_mission_id = "domination"   # round VP, four markers
	_main._solo_apply_mission_if_chosen()
	SoloController.mission_vp = [3, 1]
	assert_str(SoloController.mission_scoring).override_failure_message("fixture: no mission applied").is_equal("round_vp")


func _assert_no_mission_state(path: String) -> void:
	var state: Dictionary = SoloController.mission_state_to_dict("")
	var why := "%s: the mission state of NACHTMAHR's game survived: %s" % [path, JSON.stringify(state)]
	assert_str(SoloController.mission_scoring).override_failure_message(why).is_equal("end")
	assert_array(SoloController.mission_vp).override_failure_message(why).is_equal([0, 0])
	assert_array(SoloController.mission_markers).override_failure_message(why).is_empty()
	assert_dict(SoloController.mission_roles).override_failure_message(why).is_empty()


func test_the_last_tick_off_drops_the_mission_state(timeout := 120000) -> void:
	_ticked_mission_game()
	var start: int = _main.battle_log.entries().size()
	_main._on_solo_ai_toggled(false, 2)
	_assert_no_mission_state("tick removed")
	# …and the two-human game that follows on this table books no mission it never set up.
	var p1 := _reg(1, "Rifles", -10.0, 3)
	var p2 := _reg(2, "Raiders", 10.0, 2)
	_main.opr_army_manager.current_round = _main._solo_total_rounds()
	_main._solo_game_finished = false
	await _activate(p1)
	await _activate(p2)   # both spent in the final round -> the summary
	var text := _log_from(start)
	assert_str(text).override_failure_message("the game did not end:\n%s" % text).contains("=== GAME OVER")
	assert_str(text).override_failure_message("a two-human game booked NACHTMAHR's mission:\n%s" % text) \
		.not_contains("Mission VP")
	assert_str(text).override_failure_message("the drop was not logged:\n%s" % text).contains("Mission state dropped")


func test_clear_table_drops_the_mission_state(timeout := 120000) -> void:
	_ticked_mission_game()
	var start: int = _main.battle_log.entries().size()
	_main._do_clear_all()
	await E2EBoot.settle(get_tree())
	_assert_no_mission_state("Clear Table")
	assert_str(_log_from(start)).override_failure_message("the drop was not logged:\n%s" % _log_from(start)) \
		.contains("Mission state dropped")
