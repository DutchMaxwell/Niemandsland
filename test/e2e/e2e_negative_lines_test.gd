extends GdUnitTestSuite
## E2E — #224 (transparency wave stage 1): rules-must-log covers NON-application. The
## Artillery +1 is range-conditional (GF v3.5.1 p.13: "over 9\" away") and CORRECT — but
## silent below 9", which two testers independently reported as a missing rule. The to-hit
## note now names the does-not-apply case.

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


func test_artillery_names_the_bonus_and_its_absence(timeout := 120000) -> void:
	var gun := E2EBoot.make_unit(_main, 1, "Gun", [Vector3.ZERO])
	gun.unit_properties["special_rules"] = ["Artillery"]
	var foe := E2EBoot.make_unit(_main, 2, "Foe", [Vector3.ZERO])
	for u in [gun, foe]:
		_main.opr_army_manager.game_units[u.unit_id] = u
	# Beyond 9": the bonus applies and is named.
	var far: Dictionary = _main._solo_hit_mod_info(gun, foe, 14.0, false)
	assert_int(int(far["mod"])).is_equal(1)
	assert_str(str(far["note"])).contains("Artillery +1")
	# Within 9": no bonus — and the line SAYS so instead of staying silent (#224).
	var near: Dictionary = _main._solo_hit_mod_info(gun, foe, 6.0, false)
	assert_int(int(near["mod"])).is_equal(0)
	assert_str(str(near["note"])) \
		.override_failure_message("#224 — the within-9\" case stays silent: testers read the conditional bonus as a missing rule (note: '%s')" % str(near["note"])) \
		.contains("no +1")
