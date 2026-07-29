extends GdUnitTestSuite
## E2E — #191: "i move 4", back to start, forward 4" — that counts as 12"". The retrace
## refund EXISTED but its 0.25" pixel band never matched a human hand, so corrections cost
## triple. The fix widens the eraser to the anchor's own ribbon half-width at the DRAG CALL
## SITE (ObjectManager._update_drag → MoveLedger.retrace) — this suite drives that real
## pipeline: real main.tscn, real ObjectManager drag state, cursor positions pushed through
## the real camera projection. test/move_ledger_test.gd pins the pure tolerance semantics;
## this pins the wiring (the widened band actually reaching the drag).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

## Out 4", hand-walk back with ~0.3" wobble, out 4" again (inches, world XZ).
const HAND_RETURN := [Vector2(1, 0), Vector2(2, 0), Vector2(3, 0), Vector2(4, 0),
		Vector2(3.4, 0.3), Vector2(2.7, -0.3), Vector2(2.2, 0.3), Vector2(1.6, -0.3),
		Vector2(1.1, 0.3), Vector2(0.4, -0.2), Vector2(0.1, 0.05),
		Vector2(1, 0), Vector2(2, 0), Vector2(3, 0), Vector2(4, 0)]

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


## Screen point whose y=0 table-plane ray hit is exactly (wx, wz) — what _update_drag
## re-derives internally, so pushing cursor positions this way is projection-exact.
func _screen(wx: float, wz: float) -> Vector2:
	var cam: Camera3D = _main.get_viewport().get_camera_3d()
	return cam.unproject_position(Vector3(wx, 0.0, wz))


func test_hand_walked_correction_refunds_in_the_real_drag(timeout := 120000) -> void:
	var u := E2EBoot.make_unit(_main, 1, "Corrector", [Vector3.ZERO])
	var model := u.models[0] as ModelInstance
	var body := model.node as Node3D
	# Real spawned models carry their ModelInstance as node meta (the trail radius and
	# ownership checks read it) — the fixture matches production.
	body.set_meta("model_instance", model)

	var om: Node3D = _main.object_manager
	om._selected_objects.append(body)
	om._start_dragging(_screen(0.0, 0.0))
	assert_bool(om._is_dragging).is_true()
	# The widened eraser band must be the anchor's ribbon half-width, not the pixel floor.
	assert_float(om._retrace_tolerance_m()).is_greater(MoveLedger.RETRACE_TOLERANCE_M)

	for p in HAND_RETURN:
		om._update_drag(_screen((p as Vector2).x * INCH, (p as Vector2).y * INCH))
		await _runner.simulate_frames(1)

	var net_in: float = MoveLedger.length_inches(om._drag_path_points)
	om._stop_dragging()
	assert_float(net_in) \
		.override_failure_message("#191 — the hand-walked correction did NOT refund: the real drag measured %.1f\" for a net 4\" move (the 'counts as 12 instead of 4' report)" % net_in) \
		.is_less(6.5)
