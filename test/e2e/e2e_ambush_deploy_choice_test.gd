extends GdUnitTestSuite
## #187 — Ambush is the OWNER'S choice ("MAY be set aside", GF/AoF v3.5.1 p.13): a
## reserve-flagged unit physically placed on the table during the deployment hand-over
## clears its hold and COUNTS as newly placed (the TC-039 dead-end fix); one left on
## the tray keeps its reserve untouched.

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
	_main._ensure_solo_controller()


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_deploying_an_ambush_unit_is_choosing_not_to_ambush() -> void:
	# ON the table, reserve-flagged (the auto set-aside): deploying IS the choice.
	var tank := E2EBoot.make_unit(_main, 1, "BurrowerTank", [Vector3(0.2, 0, -0.3)])
	(tank.models[0] as ModelInstance).model_index = 0
	tank.unit_properties["ambush_reserve"] = true
	_main.opr_army_manager.game_units[tank.unit_id] = tank
	# On the TRAY (far off-table): the reserve must survive the hand-over untouched.
	var held := E2EBoot.make_unit(_main, 1, "HeldGuard", [Vector3(5.0, 0, 0)])
	(held.models[0] as ModelInstance).model_index = 0
	held.unit_properties["ambush_reserve"] = true
	_main.opr_army_manager.game_units[held.unit_id] = held
	var placed: Array = _main._solo_deploy_newly_placed_human()
	assert_bool(placed.has(tank)).is_true()
	assert_bool(bool(tank.unit_properties.get("ambush_reserve", true))).is_false()
	assert_bool(placed.has(held)).is_false()
	assert_bool(bool(held.unit_properties.get("ambush_reserve", false))).is_true()
