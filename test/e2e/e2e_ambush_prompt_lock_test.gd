extends GdUnitTestSuite
## NML-1085 — while the Ambush arrival prompt stands ("place ONE reserve unit from the tray"), only
## the reserve units may be touched. The prompt is a small draggable panel, not a modal backdrop, so
## the table stayed fully live under it: the maintainer could walk his OTHER units around during the
## arrival step — a free move outside any activation, indistinguishable from a placement to the ✓
## check. Drives the REAL prompt on the real main.tscn and asks the real selection gate.

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


func _unit(name: String, at: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, name, [at])
	(u.models[0] as ModelInstance).model_index = 0
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func test_only_the_reserve_unit_is_touchable_while_the_prompt_stands() -> void:
	var held := _unit("HeldGuard", Vector3(5.0, 0, 0))       # on the tray, waiting in Ambush
	held.unit_properties["ambush_reserve"] = true
	var onboard := _unit("Riflemen", Vector3(0.2, 0, -0.3))  # already on the table
	var held_node: Node3D = (held.models[0] as ModelInstance).node
	var onboard_node: Node3D = (onboard.models[0] as ModelInstance).node
	var om = _main.object_manager
	assert_bool(om.is_object_locked(onboard_node)).is_false()   # normal state: everything touchable

	# Open the REAL prompt. It runs until its first await (the button wait), so by the time this
	# returns the panel is up and the lock, if any, is installed.
	_main._solo_ambush_human_turn(2, [held])
	await _runner.simulate_frames(2)
	assert_bool(om.is_object_locked(onboard_node)) \
		.override_failure_message("a NON-ambush unit is still selectable while the Ambush prompt stands") \
		.is_true()
	assert_bool(om.is_object_locked(held_node)) \
		.override_failure_message("the reserve unit itself must stay placeable") \
		.is_false()

	# "None this round — keep waiting" closes the prompt; the table is free again.
	_main._solo_deploy_ui_btn2.pressed.emit()
	await _runner.simulate_frames(4)
	assert_bool(om.is_object_locked(onboard_node)) \
		.override_failure_message("the placement lock outlived the prompt") \
		.is_false()
	await E2EBoot.settle(get_tree())
