extends GdUnitTestSuite
## RULES_AUTOMATION_PLAN §2 B1 (plan step 2.2, the retired default): on a plain local table
## (two armies, no AI designation, no network session) nobody is NACHTMAHR any more — "no tick,
## no AI". Step 0.2 pinned the old implicit "player 2 is NACHTMAHR"; this suite is its inversion.
##
## Real: scenes/main.tscn, the real radial gate solo_combat_available and the real "solo_shoot"
## entry solo_begin_targeting (which no longer summons the SoloController without a designation).

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
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _register(pid: int, unit_name: String, at: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [at, at + Vector3(0.03, 0.0, 0.0)])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func test_local_table_has_no_implicit_player_2_nachtmahr(timeout := 120000) -> void:
	var p1 := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p2 := _register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	# Fixture: this is a plain local table with no designation.
	assert_bool(_main.solo_ai_slots.is_empty()).override_failure_message("fixture: the table carries no designation").is_true()
	# The retired default: player 2 is a human army like any other.
	assert_bool(_main._solo_is_ai_unit(p2)) \
		.override_failure_message("B1 — player 2 is still NACHTMAHR without a tick (step 2.2 not applied)") \
		.is_false()
	assert_bool(_main._solo_is_ai_unit(p1)).is_false()
	# Nothing is an enemy under the engine yet (step 2.3 re-cuts the combat gate): no solo entries.
	assert_bool(_main.solo_combat_available(p1)) \
		.override_failure_message("B1 — player 1 got a solo Shoot/Fight entry against an undesignated player 2") \
		.is_false()
	assert_bool(_main.solo_combat_available(p2)).is_false()
	# A player-1 solo Shoot does not start an alternation or summon a controller.
	await _main.solo_begin_targeting(p1, false)
	assert_bool(_main._solo_alternation_active()) \
		.override_failure_message("B1 — a player-1 solo Shoot started the alternation without a tick") \
		.is_false()
	assert_object(_main.solo_controller).is_null()
