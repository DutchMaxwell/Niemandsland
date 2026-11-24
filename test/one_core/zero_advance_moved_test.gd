extends GdUnitTestSuite
## gaps3 item 4: an AI Advance that left every model where it stood did not move. `execute_intent` reported `moved = true` for it (the
## action is not a Hold), while the core reads "not moving is Hold" from the placement (`activation::effective_kind`, the human drop floor
## 0.1 in) and volleys held: the table's volley took the moved reading (the "did not Hold" Indirect note, the per-model sight waiver and the
## overlay pick's `held` flag) that the core's did not. `execute_intent` now reports a no-move Advance / Rush as not moved, so both sides
## read the same. Real: the main scene, NmlCore, `execute_intent`, the AI volley body. Constructed: two plain units, the shooter on its own
## objective (a goal at its own centre makes the planner's Advance zero inches long).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf", "faction_folder": "robot_legions", "rules": []}
const GUN := {"name": "Rifle", "range_in": 24, "attacks": 3, "count": 5, "rules": ["Indirect"]}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.start(_main, [1, 2], 1)
	SoloHarness.instant(_main)


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One Advance of the shooter planned by `execute_intent` (`walk` = the goal is 8 in away, else the shooter's own centre), then its
## volley at the foe through the table (`door` false) or the core (`door` true). Returns the planner's `moved` and the volley's lines.
func _advance(walk: bool, door: bool, seed: int) -> Dictionary:
	CoreActivation.reset_all(_main)
	CoreActivation._env = 1 if door else 0
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 5, "x_in": -6.0}, true), GUN)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 5, "x_in": 6.0}, true), {})
	var sc: SoloController = _main.solo_controller
	_main._solo_core_ai_h = CoreActivation.capture(_main)
	var goal: Vector3 = sc.unit_centre(att) + (Vector3(8.0 * 0.0254, 0.0, 0.0) if walk else Vector3.ZERO)
	var report := {"unit": att, "action": AiDecision.Action.ADVANCE, "can_shoot": true}
	sc.execute_intent({"unit": att, "action": AiDecision.Action.ADVANCE, "target": foe, "goal": goal, "band_in": 6.0, "to_objective": true,
		"enemy_dist_in": 12.0, "shoot_range_in": 24.0, "shoot": true, "source": "ai"}, report)
	var lines: Array = []
	var tap := Harness._line_tap(lines)
	_main.battle_log.entry_added.connect(tap)
	_main.seed_tray_rng(seed)
	await _main._run_ai_shooting(report)
	_main.battle_log.entry_added.disconnect(tap)
	var out := {"moved": bool(report["moved"]), "lines": lines, "paths": sc.last_move_paths.size()}
	if int(_main._solo_core_ai_h) != 0:
		sc._core_node_ready().release(int(_main._solo_core_ai_h))
		_main._solo_core_ai_h = 0
	Harness._free_units(_main, [att, foe])
	await get_tree().process_frame
	return out


func _said(r: Dictionary, needle: String) -> bool:
	return (r["lines"] as Array).any(func(l: Variant) -> bool: return str(l).contains(needle))


## RED before the fix: the planner calls a zero-inch Advance moved, and the volley says the unit "did not Hold" (a false sentence for a unit
## that stood still). Green: not moved, no such line, and the core's volley reads the same lines as the table's. Control: a real 8 in Advance is
## moved on both sides and still says it.
@warning_ignore('unused_parameter')
func test_an_advance_that_left_every_model_in_place_is_not_moved_on_either_side(timeout := 300000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	for seed in [3, 4, 5]:
		var table := await _advance(false, false, seed)
		var core := await _advance(false, true, seed)
		assert_int(int(table["paths"])).override_failure_message("the fixture must plan a zero move: %s" % str(table)).is_equal(0)
		assert_bool(bool(table["moved"])).override_failure_message("seed %d: the planner calls a zero Advance moved" % seed).is_false()
		assert_bool(_said(table, "did not Hold")).override_failure_message("seed %d: a unit that stood still did not Hold: %s" % [seed, str(table["lines"])]).is_false()
		assert_array(table["lines"]).override_failure_message("seed %d: table and core volley lines differ" % seed).is_equal(core["lines"])
		assert_bool(_said(core, "Att fires Rifle at Def")).override_failure_message("seed %d: the core's volley fired: %s" % [seed, str(core["lines"])]).is_true()
	var walked := await _advance(true, false, 3)
	assert_bool(bool(walked["moved"])).override_failure_message("control: an Advance that walked is moved").is_true()
	assert_int(int(walked["paths"])).is_greater(0)
	assert_bool(_said(walked, "did not Hold")).override_failure_message("control: a moved Indirect unit says it did not Hold").is_true()
