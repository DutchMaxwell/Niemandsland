extends GdUnitTestSuite
## TDD Tests for Save/Load system
## Verifies: GameUnit serialization, OPR unit deserialization, army_manager wiring, full round-trip


# ===== GameUnit Serialization =====

func test_game_unit_to_dict_contains_all_fields() -> void:
	var unit = _create_test_game_unit()

	var data = unit.to_dict()

	assert_that(data.has("unit_id")).is_true()
	assert_that(data.has("source_type")).is_true()
	assert_that(data.has("unit_properties")).is_true()
	assert_that(data.has("is_activated")).is_true()
	assert_that(data.has("activation_round")).is_true()
	assert_that(data.has("is_fatigued")).is_true()
	assert_that(data.has("is_shaken")).is_true()
	assert_that(data.has("casts_current")).is_true()
	assert_that(data.has("casts_per_round")).is_true()
	assert_that(data.has("models")).is_true()
	assert_that(data.models).is_instance_of(TYPE_ARRAY)


func test_model_instance_to_dict_contains_wounds_and_markers() -> void:
	var model = _create_test_model_instance()

	var data = model.to_dict()

	assert_that(data.has("model_index")).is_true()
	assert_that(data.has("wounds_current")).is_true()
	assert_that(data.has("wounds_max")).is_true()
	assert_that(data.has("is_alive")).is_true()
	assert_that(data.has("markers")).is_true()
	assert_that(data.has("properties")).is_true()
	assert_that(data.wounds_current).is_equal(2)
	assert_that(data.wounds_max).is_equal(3)
	assert_that(data.markers).contains(["Activated", "Shaken"])


func test_game_unit_round_trip() -> void:
	var original = _create_test_game_unit()
	original.is_activated = true
	original.activation_round = 3
	original.is_fatigued = true
	original.is_shaken = true
	original.casts_current = 4
	original.casts_per_round = 2

	var data = original.to_dict()
	var restored = GameUnit.from_dict(data)

	assert_that(restored.unit_id).is_equal(original.unit_id)
	assert_that(restored.source_type).is_equal("opr")
	assert_that(restored.is_activated).is_true()
	assert_that(restored.activation_round).is_equal(3)
	assert_that(restored.is_fatigued).is_true()
	assert_that(restored.is_shaken).is_true()
	assert_that(restored.casts_current).is_equal(4)
	assert_that(restored.casts_per_round).is_equal(2)
	assert_that(restored.unit_properties.get("name")).is_equal("Test Warriors")
	assert_that(restored.unit_properties.get("quality")).is_equal(4)
	assert_that(restored.unit_properties.get("defense")).is_equal(4)
	assert_that(restored.models.size()).is_equal(2)


func test_model_instance_round_trip() -> void:
	var original = _create_test_model_instance()

	var data = original.to_dict()
	var restored = ModelInstance.from_dict(data)

	assert_that(restored.model_index).is_equal(0)
	assert_that(restored.wounds_current).is_equal(2)
	assert_that(restored.wounds_max).is_equal(3)
	assert_that(restored.is_alive).is_true()
	assert_that(restored.markers).contains(["Activated", "Shaken"])
	assert_that(restored.properties.get("weapons")).is_not_null()
	assert_that(restored.import_position).is_equal(Vector3(1.5, 0.0, 2.0))
	assert_that(restored.import_rotation).is_equal(Vector3(0.0, 45.0, 0.0))


# ===== SaveManager OPR Unit Deserialization =====

func test_deserialize_object_handles_opr_unit_type() -> void:
	var save_manager = SaveManager.new()
	add_child(save_manager)

	# Create a mock army manager
	var army_manager = OPRArmyManager.new()
	army_manager.object_manager = Node3D.new()
	add_child(army_manager.object_manager)
	add_child(army_manager)
	save_manager.army_manager = army_manager
	save_manager.object_manager = army_manager.object_manager

	# Pre-load a GameUnit into the cache
	var game_unit = _create_test_game_unit()
	save_manager._loaded_game_units[game_unit.unit_id] = {
		"game_unit": game_unit,
		"model_positions": [
			{"position": [1.0, 0.0, 2.0], "rotation": [0.0, 90.0, 0.0], "visible": true}
		]
	}

	# Attempt to deserialize an opr_unit object
	var obj_data = {
		"type": "opr_unit",
		"name": "OPR_Test_Warriors",
		"network_id": 1,
		"position": [1.0, 0.0, 2.0],
		"rotation": [0.0, 90.0, 0.0],
		"game_unit_id": game_unit.unit_id,
		"model_index": 0
	}

	# This should NOT trigger "Unknown object type" warning
	var success = await save_manager._deserialize_object(obj_data)
	assert_that(success).is_true()

	# Cleanup
	save_manager.queue_free()
	army_manager.object_manager.queue_free()
	army_manager.queue_free()


func test_deserialize_opr_unit_restores_position() -> void:
	var save_manager = SaveManager.new()
	add_child(save_manager)

	var army_manager = OPRArmyManager.new()
	army_manager.object_manager = Node3D.new()
	add_child(army_manager.object_manager)
	add_child(army_manager)
	save_manager.army_manager = army_manager
	save_manager.object_manager = army_manager.object_manager

	var game_unit = _create_test_game_unit()
	save_manager._loaded_game_units[game_unit.unit_id] = {
		"game_unit": game_unit,
		"model_positions": [
			{"position": [3.5, 0.0, -1.2], "rotation": [0.0, 180.0, 0.0], "visible": true}
		]
	}

	var obj_data = {
		"type": "opr_unit",
		"name": "OPR_Test_Warriors",
		"network_id": 1,
		"position": [3.5, 0.0, -1.2],
		"rotation": [0.0, 180.0, 0.0],
		"game_unit_id": game_unit.unit_id,
		"model_index": 0
	}

	await save_manager._deserialize_object(obj_data)

	# Find spawned model in object_manager children
	var found_model: Node3D = null
	for child in army_manager.object_manager.get_children():
		if child is StaticBody3D and child.is_in_group("opr_unit"):
			found_model = child
			break

	assert_that(found_model).is_not_null()
	if found_model:
		# Check position is approximately correct (floating point tolerance)
		assert_that(found_model.global_position.x).is_equal_approx(3.5, 0.01)
		assert_that(found_model.global_position.z).is_equal_approx(-1.2, 0.01)
		assert_that(found_model.rotation_degrees.y).is_equal_approx(180.0, 0.01)

	# Cleanup
	save_manager.queue_free()
	army_manager.object_manager.queue_free()
	army_manager.queue_free()


func test_deserialize_opr_unit_links_game_unit() -> void:
	var save_manager = SaveManager.new()
	add_child(save_manager)

	var army_manager = OPRArmyManager.new()
	army_manager.object_manager = Node3D.new()
	add_child(army_manager.object_manager)
	add_child(army_manager)
	save_manager.army_manager = army_manager
	save_manager.object_manager = army_manager.object_manager

	var game_unit = _create_test_game_unit()
	save_manager._loaded_game_units[game_unit.unit_id] = {
		"game_unit": game_unit,
		"model_positions": [
			{"position": [1.0, 0.0, 1.0], "rotation": [0.0, 0.0, 0.0], "visible": true}
		]
	}

	var obj_data = {
		"type": "opr_unit",
		"name": "OPR_Test_Warriors",
		"network_id": 1,
		"position": [1.0, 0.0, 1.0],
		"rotation": [0.0, 0.0, 0.0],
		"game_unit_id": game_unit.unit_id,
		"model_index": 0
	}

	await save_manager._deserialize_object(obj_data)

	# Find spawned model
	var found_model: Node3D = null
	for child in army_manager.object_manager.get_children():
		if child is StaticBody3D and child.is_in_group("opr_unit"):
			found_model = child
			break

	assert_that(found_model).is_not_null()
	if found_model:
		assert_that(found_model.has_meta("game_unit")).is_true()
		assert_that(found_model.has_meta("model_instance")).is_true()
		assert_that(found_model.has_meta("model_index")).is_true()
		assert_that(found_model.get_meta("model_index")).is_equal(0)

	# Cleanup
	save_manager.queue_free()
	army_manager.object_manager.queue_free()
	army_manager.queue_free()


# ===== Integration Tests =====

func test_serialize_game_units_returns_data_when_army_exists() -> void:
	var save_manager = SaveManager.new()
	add_child(save_manager)

	# Without army_manager, should return empty
	var empty_result = save_manager._serialize_game_units()
	assert_that(empty_result).is_empty()

	# Create army manager with a GameUnit
	var army_manager = OPRArmyManager.new()
	add_child(army_manager)
	save_manager.army_manager = army_manager

	var game_unit = _create_test_game_unit()
	army_manager.game_units[game_unit.unit_id] = game_unit

	var result = save_manager._serialize_game_units()
	assert_that(result.size()).is_greater(0)
	assert_that(result[0].has("unit_id")).is_true()
	assert_that(result[0].unit_id).is_equal(game_unit.unit_id)

	# Cleanup
	save_manager.queue_free()
	army_manager.queue_free()


# ===== Map Layout Serialization Tests =====

func test_serialize_table_includes_grid_cells() -> void:
	var save_manager = SaveManager.new()
	add_child(save_manager)

	# Create a mock map_layout_editor with terrain data
	var mock_editor = _create_mock_map_layout_editor()
	add_child(mock_editor)
	save_manager.map_layout_editor = mock_editor

	# Create a mock table
	var mock_table = _create_mock_table(Vector2(6, 4))
	add_child(mock_table)
	save_manager.table = mock_table

	var table_data = save_manager._serialize_table()

	assert_that(table_data.has("grid_cells")).is_true()
	assert_that(table_data.has("grid_rotation")).is_true()
	assert_that(table_data.has("deployment_type")).is_true()
	assert_that(table_data.grid_rotation).is_equal(15.0)
	assert_that(table_data.deployment_type).is_equal(1)

	# Grid cells should be serialized with string keys
	assert_that(table_data.grid_cells.has("5,5")).is_true()
	assert_that(table_data.grid_cells["5,5"]).is_equal(1)  # RUINS
	assert_that(table_data.grid_cells.has("7,7")).is_true()
	assert_that(table_data.grid_cells["7,7"]).is_equal(2)  # FOREST

	save_manager.queue_free()
	mock_editor.queue_free()
	mock_table.queue_free()


func test_serialize_table_includes_custom_zones() -> void:
	var save_manager = SaveManager.new()
	add_child(save_manager)

	var mock_editor = _create_mock_map_layout_editor()
	mock_editor.set("deployment_type", 2)  # CUSTOM
	mock_editor.set("custom_zone_vertices_p1", [Vector2(0, 0), Vector2(10, 0), Vector2(10, 5)] as Array[Vector2])
	mock_editor.set("custom_zone_vertices_p2", [Vector2(0, 20), Vector2(10, 20), Vector2(10, 15)] as Array[Vector2])
	add_child(mock_editor)
	save_manager.map_layout_editor = mock_editor

	var mock_table = _create_mock_table(Vector2(6, 4))
	add_child(mock_table)
	save_manager.table = mock_table

	var table_data = save_manager._serialize_table()

	assert_that(table_data.has("custom_zones")).is_true()
	assert_that(table_data.custom_zones.player1.size()).is_equal(3)
	assert_that(table_data.custom_zones.player2.size()).is_equal(3)
	assert_that(table_data.custom_zones.player1[0].x).is_equal(0.0)
	assert_that(table_data.custom_zones.player1[1].x).is_equal(10.0)

	save_manager.queue_free()
	mock_editor.queue_free()
	mock_table.queue_free()


func test_serialize_table_includes_objectives() -> void:
	var save_manager = SaveManager.new()
	add_child(save_manager)

	var mock_editor = _create_mock_map_layout_editor()
	mock_editor.set("mission_objectives", [Vector2(12, 8), Vector2(24, 16)] as Array[Vector2])
	add_child(mock_editor)
	save_manager.map_layout_editor = mock_editor

	var mock_table = _create_mock_table(Vector2(6, 4))
	add_child(mock_table)
	save_manager.table = mock_table

	var table_data = save_manager._serialize_table()

	assert_that(table_data.has("mission_objectives")).is_true()
	assert_that(table_data.mission_objectives.size()).is_equal(2)
	assert_that(table_data.mission_objectives[0].x).is_equal(12.0)
	assert_that(table_data.mission_objectives[0].y).is_equal(8.0)

	save_manager.queue_free()
	mock_editor.queue_free()
	mock_table.queue_free()


func test_serialize_table_without_editor_has_size_only() -> void:
	var save_manager = SaveManager.new()
	add_child(save_manager)

	var mock_table = _create_mock_table(Vector2(4, 4))
	add_child(mock_table)
	save_manager.table = mock_table

	var table_data = save_manager._serialize_table()

	assert_that(table_data.has("size_feet")).is_true()
	assert_that(table_data.has("grid_cells")).is_false()

	save_manager.queue_free()
	mock_table.queue_free()


func test_deserialize_map_layout_restores_grid_cells() -> void:
	var save_manager = SaveManager.new()
	add_child(save_manager)

	var mock_editor = _create_mock_map_layout_editor()
	# Clear the editor first
	mock_editor.set("grid_cells", {})
	mock_editor.set("grid_rotation_degrees", 0.0)
	mock_editor.set("deployment_type", 0)
	add_child(mock_editor)
	save_manager.map_layout_editor = mock_editor

	# Simulate saved data
	var table_data = {
		"size_feet": [6, 4],
		"grid_cells": {"5,5": 1, "7,7": 2, "10,10": 3},
		"grid_rotation": 30.0,
		"deployment_type": 1
	}

	save_manager._deserialize_map_layout(table_data, Vector2(6, 4))

	# Verify editor state was restored
	var editor_cells = mock_editor.get("grid_cells") as Dictionary
	assert_that(editor_cells.size()).is_equal(3)
	assert_that(editor_cells.has(Vector2i(5, 5))).is_true()
	assert_that(editor_cells[Vector2i(5, 5)]).is_equal(1)
	assert_that(float(mock_editor.get("grid_rotation_degrees"))).is_equal(30.0)
	assert_that(int(mock_editor.get("deployment_type"))).is_equal(1)

	save_manager.queue_free()
	mock_editor.queue_free()


func test_deserialize_map_layout_restores_custom_zones() -> void:
	var save_manager = SaveManager.new()
	add_child(save_manager)

	var mock_editor = _create_mock_map_layout_editor()
	mock_editor.set("custom_zone_vertices_p1", [] as Array[Vector2])
	mock_editor.set("custom_zone_vertices_p2", [] as Array[Vector2])
	add_child(mock_editor)
	save_manager.map_layout_editor = mock_editor

	var table_data = {
		"size_feet": [6, 4],
		"deployment_type": 2,
		"custom_zones": {
			"player1": [{"x": 0, "y": 0}, {"x": 10, "y": 0}, {"x": 10, "y": 5}],
			"player2": [{"x": 0, "y": 20}, {"x": 10, "y": 20}, {"x": 10, "y": 15}]
		}
	}

	save_manager._deserialize_map_layout(table_data, Vector2(6, 4))

	var p1 = mock_editor.get("custom_zone_vertices_p1") as Array
	var p2 = mock_editor.get("custom_zone_vertices_p2") as Array
	assert_that(p1.size()).is_equal(3)
	assert_that(p2.size()).is_equal(3)
	assert_that(p1[0]).is_equal(Vector2(0, 0))
	assert_that(p1[1]).is_equal(Vector2(10, 0))

	save_manager.queue_free()
	mock_editor.queue_free()


func test_deserialize_map_layout_restores_objectives() -> void:
	var save_manager = SaveManager.new()
	add_child(save_manager)

	var mock_editor = _create_mock_map_layout_editor()
	mock_editor.set("mission_objectives", [] as Array[Vector2])
	add_child(mock_editor)
	save_manager.map_layout_editor = mock_editor

	var table_data = {
		"size_feet": [6, 4],
		"mission_objectives": [{"x": 12, "y": 8}, {"x": 24, "y": 16}]
	}

	save_manager._deserialize_map_layout(table_data, Vector2(6, 4))

	var objectives = mock_editor.get("mission_objectives") as Array
	assert_that(objectives.size()).is_equal(2)
	assert_that(objectives[0]).is_equal(Vector2(12, 8))
	assert_that(objectives[1]).is_equal(Vector2(24, 16))

	save_manager.queue_free()
	mock_editor.queue_free()


func test_map_layout_round_trip_via_json() -> void:
	var save_manager = SaveManager.new()
	add_child(save_manager)

	# Setup source editor with data
	var mock_editor = _create_mock_map_layout_editor()
	mock_editor.set("mission_objectives", [Vector2(12, 8), Vector2(24, 16)] as Array[Vector2])
	mock_editor.set("custom_zone_vertices_p1", [Vector2(0, 0), Vector2(10, 0)] as Array[Vector2])
	mock_editor.set("custom_zone_vertices_p2", [Vector2(0, 20), Vector2(10, 20)] as Array[Vector2])
	add_child(mock_editor)
	save_manager.map_layout_editor = mock_editor

	var mock_table = _create_mock_table(Vector2(6, 4))
	add_child(mock_table)
	save_manager.table = mock_table

	# Serialize
	var table_data = save_manager._serialize_table()

	# Convert to JSON and back (simulates actual save/load)
	var json_string = JSON.stringify(table_data)
	var json = JSON.new()
	json.parse(json_string)
	var restored_data = json.data as Dictionary

	# Clear editor state
	mock_editor.set("grid_cells", {})
	mock_editor.set("grid_rotation_degrees", 0.0)
	mock_editor.set("deployment_type", 0)
	mock_editor.set("mission_objectives", [] as Array[Vector2])
	mock_editor.set("custom_zone_vertices_p1", [] as Array[Vector2])
	mock_editor.set("custom_zone_vertices_p2", [] as Array[Vector2])

	# Deserialize
	save_manager._deserialize_map_layout(restored_data, Vector2(6, 4))

	# Verify round-trip
	var editor_cells = mock_editor.get("grid_cells") as Dictionary
	assert_that(editor_cells.size()).is_equal(2)
	assert_that(editor_cells.has(Vector2i(5, 5))).is_true()
	assert_that(float(mock_editor.get("grid_rotation_degrees"))).is_equal(15.0)
	assert_that(int(mock_editor.get("deployment_type"))).is_equal(1)
	var objectives = mock_editor.get("mission_objectives") as Array
	assert_that(objectives.size()).is_equal(2)
	var zones_p1 = mock_editor.get("custom_zone_vertices_p1") as Array
	assert_that(zones_p1.size()).is_equal(2)

	save_manager.queue_free()
	mock_editor.queue_free()
	mock_table.queue_free()


# ===== Marker Restoration Tests =====

func test_restore_markers_calls_without_crash() -> void:
	# Verify _restore_markers_after_load doesn't crash when references are null
	var save_manager = SaveManager.new()
	add_child(save_manager)

	# Should not crash with null radial_menu_controller
	save_manager._restore_markers_after_load()

	save_manager.queue_free()


# ===== Test Helpers =====

func _create_test_game_unit() -> GameUnit:
	var unit = GameUnit.new()
	unit.unit_id = "test_unit_123_456"
	unit.source_type = "opr"
	unit.unit_properties = {
		"name": "Test Warriors",
		"custom_name": "",
		"size": 2,
		"quality": 4,
		"defense": 4,
		"cost": 200,
		"special_rules": ["Tough(3)", "Fearless"],
		"base_size_round": 32,
		"base_is_oval": false,
		"base_width_mm": 32,
		"base_depth_mm": 32,
		"player_id": 1,
		"faction_folder": "alien_hives",
		"display_suffix": "",
		"attached_heroes": [],
		"attached_to": null,
	}

	# Add two model instances
	var model1 = _create_test_model_instance()
	model1.unit = unit
	model1.model_index = 0
	unit.models.append(model1)

	var model2 = ModelInstance.new()
	model2.unit = unit
	model2.model_index = 1
	model2.wounds_current = 3
	model2.wounds_max = 3
	model2.is_alive = true
	model2.properties = {"weapons": [], "equipment": [], "special_rules": ["Tough(3)"]}
	unit.models.append(model2)

	return unit


func _create_test_model_instance() -> ModelInstance:
	var model = ModelInstance.new()
	model.model_index = 0
	model.wounds_current = 2
	model.wounds_max = 3
	model.is_alive = true
	model.markers = ["Activated", "Shaken"]
	model.properties = {
		"weapons": [{"name": "CCW", "attacks": 2}],
		"equipment": ["Banner"],
		"special_rules": ["Tough(3)", "Fearless"],
	}
	model.import_position = Vector3(1.5, 0.0, 2.0)
	model.import_rotation = Vector3(0.0, 45.0, 0.0)
	return model


func _create_mock_map_layout_editor() -> Control:
	## Creates a mock map layout editor with terrain data for testing.
	var script = GDScript.new()
	script.source_code = "extends Control\n" + \
		"var grid_cells = {}\n" + \
		"var grid_rotation_degrees := 0.0\n" + \
		"var deployment_type := 0\n" + \
		"var table_size_feet := Vector2(6, 4)\n" + \
		"var custom_zone_vertices_p1: Array[Vector2] = []\n" + \
		"var custom_zone_vertices_p2: Array[Vector2] = []\n" + \
		"var mission_objectives: Array[Vector2] = []\n"
	script.reload()
	var editor = Control.new()
	editor.set_script(script)
	editor.grid_cells = {Vector2i(5, 5): 1, Vector2i(7, 7): 2}  # RUINS, FOREST
	editor.grid_rotation_degrees = 15.0
	editor.deployment_type = 1  # FRONT_LINE
	return editor


func _create_mock_table(size: Vector2) -> Node3D:
	## Creates a mock table node with table_size property.
	var script = GDScript.new()
	script.source_code = "extends Node3D\nvar table_size := Vector2(6, 4)\n"
	script.reload()
	var t = Node3D.new()
	t.set_script(script)
	t.table_size = size
	return t
