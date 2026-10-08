extends GdUnitTestSuite
## Characterization of RULES_AUTOMATION_PLAN §2 B1 (plan step 0.2): on a plain local table
## (two armies, no AI designation, no network session, NOT the tutorial) the implicit
## "no designation -> player 2 is NACHTMAHR" default still stands today. Step 2.2 will invert
## this on purpose; until then this pins the current behaviour and must stay GREEN on main.
##
## Real: scenes/main.tscn, the real radial gate solo_combat_available and the real "solo_shoot"
## entry solo_begin_targeting (which summons the SoloController and arms the alternation pump).

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


func test_local_table_pins_the_implicit_player_2_nachtmahr(timeout := 120000) -> void:
	var p1 := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p2 := _register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	# Fixture: this is a plain local table, not the tutorial and not a network session.
	assert_bool(_main._solo_hotseat).override_failure_message("fixture: the table must not be the tutorial").is_false()
	assert_bool(_main.solo_ai_slots.is_empty()).override_failure_message("fixture: the table carries no designation").is_true()
	# Today's implicit default: player 2 is NACHTMAHR, player 1 gets the solo Shoot/Fight entries.
	assert_bool(_main._solo_is_ai_unit(p2)) \
		.override_failure_message("B1 — the implicit default no longer makes player 2 NACHTMAHR on a local table (step 2.2 flip?)") \
		.is_true()
	assert_bool(_main.solo_combat_available(p1)) \
		.override_failure_message("B1 — player 1's radial lost the solo Shoot/Fight entry on a local table") \
		.is_true()
	assert_bool(_main.solo_combat_available(p2)) \
		.override_failure_message("B1 — player 2 (the implicit NACHTMAHR) must not get solo combat for itself") \
		.is_false()
	# One player-1 attack through the solo Shoot entry arms the alternation pump.
	await _main.solo_begin_targeting(p1, false)
	assert_bool(_main._solo_alternation_active()) \
		.override_failure_message("B1 — a player-1 solo Shoot no longer activates the alternation") \
		.is_true()
