extends GdUnitTestSuite
## NML-1010 C3a: the deterministic drop uses the carrier's base edge.

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
	_main.terrain_overlay.update_objectives([Vector3.ZERO])
	SoloController.mission_markers = [{"carry": true, "carried_by": "carrier"}]


func after_test() -> void:
	SoloController.mission_reset("end", {})
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_drop_lands_one_inch_from_base_edge_toward_nearest_opponent() -> void:
	var carrier := E2EBoot.make_unit(_main, 1, "Carrier", [Vector3.ZERO])
	carrier.unit_id = "carrier"
	var opponent := E2EBoot.make_unit(_main, 2, "Opponent", [Vector3(0.5, 0, 0)])
	_main.opr_army_manager.game_units[carrier.unit_id] = carrier
	_main.opr_army_manager.game_units[opponent.unit_id] = opponent
	var radius := SoloController.model_base_radius_m(carrier.models[0] as ModelInstance)
	_main._solo_drop_carried(carrier, "shaken")
	var pos: Vector3 = _main.terrain_overlay.get_objectives()[0]
	assert_float(pos.x).is_equal_approx(radius + 0.0254, 0.0001)
	assert_float(pos.z).is_equal_approx(0.0, 0.0001)
	assert_str(str(_main.battle_log.entries().back().get("text", ""))).contains("placed by P2")


## D14.5: a marker that carries its own `drop_in` (Rescue: 6") lands that far past the base edge, and the
## placer's click ring (the queued entry's reach) follows it; without it the drop stays one inch.
func test_a_marker_with_drop_in_six_lands_six_inches_past_the_base_edge() -> void:
	SoloController.mission_markers = [{"carry": true, "carried_by": "carrier", "drop_in": 6.0}]
	var carrier := E2EBoot.make_unit(_main, 1, "Carrier", [Vector3.ZERO])
	carrier.unit_id = "carrier"
	var opponent := E2EBoot.make_unit(_main, 2, "Opponent", [Vector3(0.5, 0, 0)])
	_main.opr_army_manager.game_units[carrier.unit_id] = carrier
	_main.opr_army_manager.game_units[opponent.unit_id] = opponent
	var radius := SoloController.model_base_radius_m(carrier.models[0] as ModelInstance)
	_main._solo_drop_carried(carrier, "shaken")
	var pos: Vector3 = _main.terrain_overlay.get_objectives()[0]
	assert_float(pos.x).is_equal_approx(radius + 6.0 * 0.0254, 0.0001)


func test_the_catalog_spec_writes_drop_in_into_the_carry_marker_and_the_pure_point_takes_it() -> void:
	var spec := {"count": 1, "carry": true, "drop_in": 6}
	var markers: Array = SoloController.marker_metadata(spec)
	assert_float(float((markers[0] as Dictionary)["drop_in"])).is_equal(6.0)
	assert_bool((SoloController.marker_metadata({"count": 1, "carry": true})[0] as Dictionary).has("drop_in")).is_false()
	var carrier := E2EBoot.make_unit(_main, 1, "C2", [Vector3.ZERO])
	var opponent := E2EBoot.make_unit(_main, 2, "O2", [Vector3(1.0, 0, 0)])
	var p1 := SoloController.drop_point(carrier, [opponent])
	var p6 := SoloController.drop_point(carrier, [opponent], 6.0)
	assert_float(p6.x - p1.x).is_equal_approx(5.0 * 0.0254, 0.0001)
