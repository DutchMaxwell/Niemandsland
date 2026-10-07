extends GdUnitTestSuite

const Facts := preload("res://scripts/lesson_facts.gd")

class FakeObjects extends Node:
	signal measurement_finished(distance_inches: float)
	var selected: Array[Node3D] = []
	func get_selected_objects() -> Array[Node3D]:
		return selected

class FakeArmy extends Node:
	var units: Array[GameUnit] = []
	var game_phase := 0
	func get_all_game_units() -> Array[GameUnit]:
		return units
	func get_game_units_for_player(player_id: int) -> Array[GameUnit]:
		return units if player_id == 1 else []

class FakeTable extends Node:
	var table_size := Vector2(4, 4)
	var biome := "temperate_grassland"

class FakeLayout extends Node:
	var placed_pieces: Array = []
	var deployment_type := 0


func _unit(tag: String, positions: Array[Vector3]) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_properties["lesson_tag"] = tag
	for pos in positions:
		var model := ModelInstance.new()
		model.node = auto_free(Node3D.new())
		add_child(model.node)
		model.node.position = pos
		unit.models.append(model)
	return unit


func test_snapshot_tracks_camera_selection_and_centroid() -> void:
	var pivot: Node3D = auto_free(Node3D.new())
	add_child(pivot)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	pivot.add_child(camera)
	pivot.rotation.y = 0.5
	pivot.position = Vector3(0.2, 0, 0.3)
	camera.position = Vector3(0, 0, 10)
	var objects: FakeObjects = auto_free(FakeObjects.new())
	var army: FakeArmy = auto_free(FakeArmy.new())
	var unit := _unit("alpha", [Vector3(0.0254, 0, 0.0508), Vector3(0.0762, 0, 0.0508)])
	army.units = [unit, _unit("", [Vector3.ZERO])]
	var facts := Facts.new()
	facts.setup({"camera_pivot": pivot, "object_manager": objects, "army_manager": army})
	var first: Dictionary = facts.snapshot()
	assert_float(first.yaw).is_equal_approx(0.5, 0.001)
	assert_float(first.cam_dist).is_equal_approx(10.0, 0.001)
	assert_vector(first.pivot).is_equal(pivot.global_position)
	var alpha: Dictionary = first.tags.get("alpha", {})
	assert_bool(alpha.get("selected_whole", false)).is_false()
	assert_vector(alpha.get("centroid_in", Vector2.ZERO)).is_equal_approx(Vector2(2, 2), Vector2(0.001, 0.001))
	assert_int(alpha.get("alive", 0)).is_equal(2)
	assert_int(first.tags.size()).is_equal(1)
	objects.selected = [unit.models[0].node, unit.models[1].node]
	assert_bool(facts.snapshot().tags.get("alpha", {}).get("selected_whole", false)).is_true()
	unit.models[1].is_alive = false
	objects.selected = [unit.models[0].node]
	assert_bool(facts.snapshot().tags.get("alpha", {}).get("selected_whole", false)).is_true()
	assert_int(facts.snapshot().tags.get("alpha", {}).get("alive", 0)).is_equal(1)


func test_counters_only_grow_after_bump_or_measurement() -> void:
	var objects: FakeObjects = auto_free(FakeObjects.new())
	var facts := Facts.new()
	facts.setup({"object_manager": objects})
	var initial: Dictionary = facts.snapshot()
	assert_int(initial.counters.get("measure", 0)).is_equal(0)
	facts.bump("continue")
	objects.measurement_finished.emit(5.0)
	assert_int(facts.snapshot().counters.get("continue", 0)).is_equal(1)
	assert_int(facts.snapshot().counters.get("measure", 0)).is_equal(1)
	assert_int(initial.counters.get("measure", 0)).is_equal(0)


func test_missing_refs_are_safe_and_empty_unit_is_not_selected() -> void:
	var facts := Facts.new()
	facts.setup({})
	var empty: Dictionary = facts.snapshot()
	assert_bool(empty.has("yaw") and empty.has("cam_dist") and empty.has("pivot") and empty.has("counters") and empty.has("tags")).is_true()
	assert_dict(empty.tags).is_empty()
	var army: FakeArmy = auto_free(FakeArmy.new())
	army.units = [_unit("empty", [])]
	facts.setup({"army_manager": army})
	assert_bool(facts.snapshot().tags.get("empty", {}).get("selected_whole", false)).is_false()


func test_snapshot_reads_table_layout_and_menu() -> void:
	var table: FakeTable = auto_free(FakeTable.new())
	add_child(table)
	var layout: FakeLayout = auto_free(FakeLayout.new())
	add_child(layout)
	var panel: Control = auto_free(Control.new())
	add_child(panel)
	panel.visible = false
	var terrain: Node3D = auto_free(Node3D.new())
	add_child(terrain)
	terrain.add_to_group("terrain")
	var non_terrain: Node3D = auto_free(Node3D.new())
	add_child(non_terrain)
	var objects: FakeObjects = auto_free(FakeObjects.new())
	add_child(objects)
	var facts := Facts.new()
	facts.setup({"table": table, "map_layout": layout, "left_panel": panel,
		"object_manager": objects})
	var snap: Dictionary = facts.snapshot()
	assert_vector(snap.get("table_size", Vector2.ZERO)).is_equal(Vector2(4, 4))
	assert_str(String(snap.get("biome", ""))).is_equal("temperate_grassland")
	assert_int(snap.get("terrain_pieces", -1)).is_equal(1)
	assert_int(snap.get("layout_pieces", -1)).is_equal(0)
	assert_int(snap.get("deploy_type", -1)).is_equal(0)
	assert_bool(snap.get("menu_open", true)).is_false()
	layout.placed_pieces = [{"a": 1}, {"b": 2}]
	layout.deployment_type = 1
	panel.visible = true
	var changed: Dictionary = facts.snapshot()
	assert_int(changed.get("layout_pieces", -1)).is_equal(2)
	assert_int(changed.get("deploy_type", -1)).is_equal(1)
	assert_bool(changed.get("menu_open", false)).is_true()


func test_missing_scene_refs_report_safe_defaults() -> void:
	var facts := Facts.new()
	facts.setup({})
	var snap: Dictionary = facts.snapshot()
	assert_vector(snap.get("table_size", Vector2(-1, -1))).is_equal(Vector2.ZERO)
	assert_str(String(snap.get("biome", "x"))).is_equal("")
	assert_int(snap.get("terrain_pieces", -1)).is_equal(0)
	assert_int(snap.get("layout_pieces", -1)).is_equal(0)
	assert_bool(snap.get("menu_open", true)).is_false()


func test_player_one_units_zone_and_phase() -> void:
	var objects: FakeObjects = auto_free(FakeObjects.new())
	add_child(objects)
	var army: FakeArmy = auto_free(FakeArmy.new())
	add_child(army)
	var facts := Facts.new()
	facts.setup({"army_manager": army, "object_manager": objects})
	var empty: Dictionary = facts.snapshot()
	assert_int(empty.get("units_p1", -1)).is_equal(0)
	assert_bool(empty.get("p1_all_in_zone", true)).is_false()
	assert_int(empty.get("phase", -1)).is_equal(0)
	var unit := _unit("alpha", [Vector3(0.0, 0.0, -18.0 * 0.0254)])
	army.units = [unit]
	var inside: Dictionary = facts.snapshot()
	assert_int(inside.get("units_p1", -1)).is_equal(1)
	assert_bool(inside.get("p1_all_in_zone", false)).is_true()
	unit.models[0].node.position = Vector3.ZERO
	assert_bool(facts.snapshot().get("p1_all_in_zone", true)).is_false()
	army.game_phase = 1
	assert_int(facts.snapshot().get("phase", -1)).is_equal(1)
