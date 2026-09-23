extends GdUnitTestSuite
## Bug lane C2 — the tutorial table is a hotseat table, never a NACHTMAHR game.
## RULES_AUTOMATION_PLAN §2 B1: with no AI designation, main._solo_is_ai_unit's implicit
## "no designation -> player 2 is the AI" branch answers true, so on the tutorial board (two
## armies, no designation) player 1's radial offers solo Shoot/Fight and the first click builds the
## SoloController, which then activates player 2 as NACHTMAHR. The tutorial-only opt-out
## (`_solo_hotseat`, set by the tutorial start) switches the IMPLICIT branch off for that table;
## an explicit designation still wins, and the flag lives on the Main instance, so leaving through
## the main menu (a scene change) starts every later game without it.
##
## Real: scenes/main.tscn, the real _start_tutorial (director + overlay; no bundled board load —
## `_tutorial_board_pending` stays false, so the director runs on the constructed units), the real
## radial gate solo_combat_available and the real "solo_shoot" entry solo_begin_targeting.
## Plan B1 itself (hotseat outside the tutorial) stays RED in e2e_local_table_no_implicit_ai_test.gd.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	if _main != null and is_instance_valid(_main._tutorial_director):
		_main._tutorial_director.queue_free()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _register(main: Node, pid: int, unit_name: String, at: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(main, pid, unit_name, [at, at + Vector3(0.03, 0.0, 0.0)])
	main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _tutorial_table() -> Array:
	var p1 := _register(_main, 1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p2 := _register(_main, 2, "Raiders", Vector3(0.3, 0.0, 0.0))
	_main._tutorial_mode = true
	await _main._start_tutorial()
	assert_bool(is_instance_valid(_main._tutorial_director)).override_failure_message("fixture: the tutorial director did not start").is_true()
	assert_bool(_main.solo_ai_slots.is_empty()).override_failure_message("fixture: the tutorial board carries no designation").is_true()
	return [p1, p2]


func test_the_tutorial_table_offers_no_solo_combat_and_summons_no_nachtmahr(timeout := 120000) -> void:
	var pair: Array = await _tutorial_table()
	var p1 := pair[0] as GameUnit
	var p2 := pair[1] as GameUnit
	assert_bool(_main._solo_is_ai_unit(p2)) \
		.override_failure_message("C2 — on the tutorial table player 2 is the second human, not NACHTMAHR") \
		.is_false()
	assert_bool(_main.solo_combat_available(p1)) \
		.override_failure_message("C2 — player 1's radial must offer no solo Shoot/Fight on the tutorial table") \
		.is_false()
	await _main.solo_begin_targeting(p1, false)   # the radial's "solo_shoot" entry, e.g. from a stale menu
	assert_object(_main.solo_controller) \
		.override_failure_message("C2 — a Shoot attempt on the tutorial table built the SoloController (arms the pump)") \
		.is_null()
	assert_bool(_main._solo_alternation_active()).is_false()


## An explicit designation on the tutorial table (ticking P2's NACHTMAHR box) still gets the AI —
## the opt-out only retires the implicit default.
func test_an_explicit_designation_on_the_tutorial_table_still_gets_nachtmahr(timeout := 120000) -> void:
	var pair: Array = await _tutorial_table()
	_main.solo_ai_slots = {2: true}
	assert_bool(_main._solo_is_ai_unit(pair[1])).is_true()
	assert_bool(_main.solo_combat_available(pair[0])).is_true()
	_main._ensure_solo_controller()
	assert_object(_main.solo_controller).is_not_null()


## No leak: tutorial -> main menu -> a solo game. The main menu is a scene change, so the next
## game runs on a NEW Main instance; it gets NACHTMAHR both by designation and by the implicit
## solo default, exactly as before this change.
func test_a_solo_game_after_the_tutorial_still_gets_nachtmahr(timeout := 120000) -> void:
	await _tutorial_table()
	assert_bool(_main._solo_hotseat).override_failure_message("fixture: the tutorial start sets the opt-out").is_true()
	if is_instance_valid(_main._tutorial_director):
		_main._tutorial_director.queue_free()
	var runner2 := scene_runner(E2EBoot.MAIN_SCENE)   # what the main menu's change_scene_to_file does
	var main2: Node = runner2.scene()
	await runner2.simulate_frames(4)
	assert_bool(main2._solo_hotseat).override_failure_message("the tutorial opt-out leaked into the next game").is_false()
	var q1 := _register(main2, 1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var q2 := _register(main2, 2, "Raiders", Vector3(0.3, 0.0, 0.0))
	assert_bool(main2._solo_is_ai_unit(q2)).override_failure_message("the implicit solo default must stand in the next game").is_true()
	main2.solo_ai_slots = {2: true}   # what the Solo quick start's AI-list import writes
	assert_bool(main2._solo_is_ai_unit(q2)).is_true()
	assert_bool(main2.solo_combat_available(q1)).is_true()
	main2._ensure_solo_controller()
	assert_object(main2.solo_controller).override_failure_message("the solo game after the tutorial got no NACHTMAHR").is_not_null()
