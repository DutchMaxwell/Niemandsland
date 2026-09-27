extends GdUnitTestSuite

const Facts := preload("res://scripts/lesson_facts.gd")

class FakeObjects extends Node:
	signal measurement_finished(distance_inches: float)
	var selected: Array[Node3D] = []
	func get_selected_objects() -> Array[Node3D]:
		return selected

class FakeArmy extends Node:
	var units: Array[GameUnit] = []
	func get_all_game_units() -> Array[GameUnit]:
		return units


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
