extends GdUnitTestSuite
## E2E - Automodus rework step 2.1: ObjectManager.preview_drop_landing() asks the drop's own
## resolver where a drop would leave the dragged bases, without moving anything or emitting.
## Step 2.2: while a model drag runs in the PLAYING phase, LandingPreview shows one ghost base per
## model at that landing; the drop and Esc clear it, deployment shows none.

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
	_unit_of_all([node], uid, player)


func _unit_of_all(nodes: Array, uid: String, player: int) -> void:
	var unit := GameUnit.new()
	unit.unit_id = uid
	unit.unit_properties = {"player_id": player, "name": uid, "quality": 4, "defense": 4}
	for node in nodes:
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


## Step 2.2 fixture: a 3-model unit picked up through the real drag path and dragged 4" (+z), in
## `phase`. An enemy waits 0.3" outside contact of the third model's end spot, so that model's
## landing is the resolver's snap, not the cursor position. Returns the three model nodes.
func _drag_three(phase: int) -> Array[Node3D]:
	var om: Object = _main.object_manager
	_main.get_node("OPRArmyManager").call("set_game_phase", phase)
	var models: Array[Node3D] = []
	for i in 3:
		models.append(om.call("spawn_miniature", Vector3(0.05 * i, 0.0, 0.0), false))
	_unit_of_all(models, "am22_mover", 1)
	var end_z := 0.1016
	var enemy: Node3D = om.call("spawn_miniature", Vector3(0.1, 0.0, end_z + 0.032 + 0.00762), false)
	_unit_of(enemy, "am22_enemy", 2)
	om.call("select_objects", models)
	var cam := _main.get_viewport().get_camera_3d()
	om.call("_start_dragging", cam.unproject_position(models[0].global_position))
	om.set("_coherency_update_timer", 1.0)  # the next _update_drag runs the throttled tick
	om.call("_update_drag", cam.unproject_position(models[0].global_position + Vector3(0.0, -_drag_lift(), end_z)))
	return models


func _drag_lift() -> float:
	return float(_main.object_manager.get("drag_lift_height"))


func _ghost_xz() -> Array:
	var out: Array = []
	var root: Node = _main.landing_preview.get_node_or_null("LandingPreviewRoot")
	if root != null:
		for disc in root.get_children():
			out.append(Vector2((disc as Node3D).global_position.x, (disc as Node3D).global_position.z))
	return out


func test_ghosts_follow_a_drag() -> void:
	assert_object(_main.object_manager.get("landing_preview")).is_same(_main.landing_preview)
	var models := _drag_three(OPRArmyManager.GamePhase.PLAYING)
	assert_int(_main.landing_preview.ghost_count()).is_equal(3)
	var ghosts := _ghost_xz()
	var cursor_xz := Vector2(models[2].global_position.x, models[2].global_position.z)

	_main.object_manager.call("_stop_dragging")
	assert_int(_main.landing_preview.ghost_count()).is_equal(0)
	for m in models:
		var landed := Vector2(m.global_position.x, m.global_position.z)
		var nearest := INF
		for g in ghosts:
			nearest = minf(nearest, landed.distance_to(g))
		assert_float(nearest).override_failure_message("no ghost within 1 mm of %s" % m.name).is_less_equal(0.001)
	assert_float(Vector2(models[2].global_position.x, models[2].global_position.z).distance_to(cursor_xz)) \
		.override_failure_message("the 0.3 inch near miss should have been snapped, else this test proves nothing") \
		.is_greater(0.001)


func test_esc_clears_the_ghosts() -> void:
	_drag_three(OPRArmyManager.GamePhase.PLAYING)
	assert_int(_main.landing_preview.ghost_count()).is_equal(3)
	_main.object_manager.call("_cancel_drag")
	assert_int(_main.landing_preview.ghost_count()).is_equal(0)


func test_no_ghosts_in_deployment() -> void:
	_drag_three(OPRArmyManager.GamePhase.DEPLOYMENT)
	assert_bool(bool(_main.object_manager.get("_is_dragging"))).is_true()
	assert_int(_main.landing_preview.ghost_count()).is_equal(0)
