extends GdUnitTestSuite
## E2E — NML-971: the measure line's LOS verdict must agree with the RESOLUTION about
## elevation. A model standing ON a container (real y ≈ 0.0635 m) sees over its own box —
## the NML-965 roof exemption — and its cast/shot resolves; but the ruler flattened both
## endpoints to table level (y = 0.02) before asking, so the drawn line stayed red while
## the spell executed. The verdict must read the measured objects' REAL heights.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const OverlayScript := preload("res://scripts/terrain_overlay.gd")

const BOX_C := Vector2(0.3, 0.0)          # container centre on the table (metres, XZ)
const BOX_HE := Vector2(0.0762, 0.0381)   # half-extents of the 6"x3" box
const ROOF_Y := 0.0635                    # container height 2.5" = 0.0635 m
const FLAT_Y := 0.02                      # the ruler's display flattening

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
	_main.object_manager._measure_start_object = null
	_main.object_manager._measure_end_object = null
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A map-layout container records BOTH truths (NML-965): the exact OBB and its painted
## footprint cells — the verdict has to survive the pair, not just the box.
func _with_container() -> void:
	var o = _main.terrain_overlay
	o._blocker_obbs.append({"c": BOX_C, "he": BOX_HE, "yaw": 0.0})
	var steps := 12
	for i in range(steps + 1):
		var x := BOX_C.x - BOX_HE.x + (2.0 * BOX_HE.x) * float(i) / float(steps)
		o.grid_cells[o.world_to_cell(Vector3(x, 0, 0))] = OverlayScript.TerrainType.CONTAINER


func test_a_roof_measure_is_not_judged_blocked() -> void:
	_with_container()
	var roof: Node3D = auto_free(Node3D.new())
	_main.add_child(roof)
	roof.global_position = Vector3(BOX_C.x, ROOF_Y, 0)
	_main.object_manager._measure_start_object = roof
	_main.object_manager._measure_end_object = null
	var blocked: bool = _main.object_manager._measure_los_blocked(
		Vector3(BOX_C.x, FLAT_Y, 0), Vector3(0.75, FLAT_Y, 0))
	assert_bool(blocked) \
		.override_failure_message("NML-971 — the resolution sees over the box (NML-965 roof exemption) but the ruler still paints red: the verdict must read the measured object's real height, not the display flattening") \
		.is_false()


func test_a_ground_measure_through_the_container_stays_blocked() -> void:
	# The counter-probe that keeps the fix a RULE and not an always-open gate: on the
	# ground, the same box still blocks the same line.
	_with_container()
	_main.object_manager._measure_start_object = null
	_main.object_manager._measure_end_object = null
	var blocked: bool = _main.object_manager._measure_los_blocked(
		Vector3(0.0, FLAT_Y, 0), Vector3(0.75, FLAT_Y, 0))
	assert_bool(blocked) \
		.override_failure_message("fixture broken: a ground-to-ground line through a container must stay blocked") \
		.is_true()
