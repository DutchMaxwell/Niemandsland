extends GdUnitTestSuite
## E2E — #192 (grilled 2026-07-30): "you can move, then change formation which can give you
## several inches of movement." A reform IS movement (OPR knows no separate formation
## change), so in a running solo game NO model may end closer to any enemy than it stood.
## Offenders are clamped back along their reform path (grill: clamp, not block); sandbox
## play stays free. Drives the REAL arrange tool on main.tscn.

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


## A P1 unit spread along X (one trailing model) + a P2 foe ahead at +X, selection armed.
func _spread_unit_vs_foe() -> Array:
	var u := E2EBoot.make_unit(_main, 1, "Reformers",
		[Vector3.ZERO, Vector3(0.05, 0, 0), Vector3(0.30, 0, 0)])
	for m in u.models:
		(m as ModelInstance).node.set_meta("model_instance", m)
	var foe := E2EBoot.make_unit(_main, 2, "Foe", [Vector3(0.60, 0, 0)])
	for x in [u, foe]:
		_main.opr_army_manager.game_units[x.unit_id] = x
	for m in u.models:
		_main.object_manager._selected_objects.append((m as ModelInstance).node)
	return [u, foe]


func _gap_to_foe(node: Node3D, foe: GameUnit) -> float:
	return node.global_position.distance_to((foe.models[0] as ModelInstance).node.global_position)


func test_solo_reform_never_gains_ground(timeout := 120000) -> void:
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	var uf := _spread_unit_vs_foe()
	var rear := ((uf[0] as GameUnit).models[0] as ModelInstance).node as Node3D
	var gap_before := _gap_to_foe(rear, uf[1])
	_main.object_manager.arrange_selected_in_rows(1)
	assert_float(_gap_to_foe(rear, uf[1])) \
		.override_failure_message("#192 — the reform pulled the rear model %.3f m closer to the enemy: free inches" % (gap_before - _gap_to_foe(rear, uf[1]))) \
		.is_greater_equal(gap_before - 0.002)
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	assert_str(text).contains("no free inches")


func test_sandbox_reform_stays_free(timeout := 120000) -> void:
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	var uf := _spread_unit_vs_foe()
	var rear := ((uf[0] as GameUnit).models[0] as ModelInstance).node as Node3D
	var gap_before := _gap_to_foe(rear, uf[1])
	_main.object_manager.arrange_selected_in_rows(1)
	# The centred single row legitimately pulls the trailing anchor forward — sandbox is free.
	assert_float(_gap_to_foe(rear, uf[1])).is_less(gap_before)
