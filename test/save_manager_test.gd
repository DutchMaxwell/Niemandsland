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
