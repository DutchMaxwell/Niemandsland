extends GdUnitTestSuite
## E2E - Automodus rework step 2.1: ObjectManager.preview_drop_landing() asks the drop's own
## resolver where a drop would leave the dragged bases, without moving anything or emitting.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const TOL := 1e-4

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _separated_count := 0


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(10)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit_of(node: Node3D, uid: String, player: int) -> void:
	var unit := GameUnit.new()
	unit.unit_id = uid
	unit.unit_properties = {"player_id": player, "name": uid, "quality": 4, "defense": 4}
	var mi := ModelInstance.new()
	mi.is_alive = true
	mi.unit = unit
	mi.node = node
	unit.models.append(mi)
	node.set_meta("game_unit", unit)
	node.set_meta("model_instance", mi)
	_main.get_node("OPRArmyManager").game_units[uid] = unit


func test_preview_matches_the_drop() -> void:
	var om: Object = _main.object_manager
	var mover: Node3D = om.call("spawn_miniature", Vector3(0.0, 0.0, 0.0), false)
	# 0.3" (7.6 mm) outside base contact for the default 32 mm round base.
	var enemy: Node3D = om.call("spawn_miniature", Vector3(0.032 + 0.00762, 0.0, 0.0), false)
	_unit_of(mover, "am21_mover", 1)
	_unit_of(enemy, "am21_enemy", 2)
	om.set("_selected_objects", [mover] as Array[Node3D])
	om.set("_is_dragging", true)
	om.connect("drop_separated", func(_applied: bool) -> void: _separated_count += 1)
	var start := mover.global_position

	var preview: Dictionary = om.call("preview_drop_landing")

	assert_bool(preview.has(mover)).is_true()
	assert_vector(mover.global_position).is_equal(start)
	assert_int(_separated_count).is_equal(0)
	var landing: Vector3 = preview[mover]
	assert_float(Vector2(landing.x, landing.z).distance_to(Vector2(start.x, start.z))) \
		.override_failure_message("the 0.3 inch near miss should have been snapped, else this test proves nothing") \
		.is_greater(0.001)

	om.call("_stop_dragging")
	assert_float(mover.global_position.x).is_equal_approx(landing.x, TOL)
	assert_float(mover.global_position.z).is_equal_approx(landing.z, TOL)
	assert_int(_separated_count).is_equal(1)
