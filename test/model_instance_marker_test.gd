extends GdUnitTestSuite
## Tests ModelInstance marker persistence: marker names and custom marker colors
## survive a to_dict/from_dict roundtrip; standard markers store no color.


func test_marker_colors_survive_serialization_roundtrip() -> void:
	var model := ModelInstance.new()
	model.add_marker("Pinned")
	model.add_marker("MyCustom")
	model.marker_colors["MyCustom"] = Color(0.1, 0.2, 0.3, 1.0)

	var restored := ModelInstance.from_dict(model.to_dict())

	assert_array(restored.markers).contains(["Pinned"])
	assert_array(restored.markers).contains(["MyCustom"])
	assert_bool(restored.marker_colors.has("MyCustom")).is_true()
	var color: Color = restored.marker_colors["MyCustom"]
	assert_float(color.r).is_equal_approx(0.1, 0.001)
	assert_float(color.g).is_equal_approx(0.2, 0.001)
	assert_float(color.b).is_equal_approx(0.3, 0.001)


func test_standard_marker_stores_no_color() -> void:
	var model := ModelInstance.new()
	model.add_marker("Shaken")  # standard marker -> color derivable from its name
	var restored := ModelInstance.from_dict(model.to_dict())

	assert_int(restored.marker_colors.size()).is_equal(0)
	assert_array(restored.markers).contains(["Shaken"])


func test_counter_value_survives_serialization_roundtrip() -> void:
	var model := ModelInstance.new()
	model.add_marker("Havoc")
	model.set_marker_value("Havoc", 3)

	var restored := ModelInstance.from_dict(model.to_dict())

	assert_bool(restored.is_counter_marker("Havoc")).is_true()
	assert_int(restored.get_marker_value("Havoc")).is_equal(3)


func test_status_marker_is_not_a_counter() -> void:
	var model := ModelInstance.new()
	model.add_marker("Pinned")  # no value set -> status token, not a counter
	assert_bool(model.is_counter_marker("Pinned")).is_false()
	assert_int(model.get_marker_value("Pinned")).is_equal(0)


func test_set_marker_value_clamps_to_non_negative() -> void:
	var model := ModelInstance.new()
	model.add_marker("Fury")
	model.set_marker_value("Fury", -5)
	assert_int(model.get_marker_value("Fury")).is_equal(0)


func test_remove_marker_clears_its_counter_value() -> void:
	var model := ModelInstance.new()
	model.add_marker("Havoc")
	model.set_marker_value("Havoc", 4)
	model.remove_marker("Havoc")
	assert_bool(model.is_counter_marker("Havoc")).is_false()


func test_clear_markers_clears_all_counter_values() -> void:
	var model := ModelInstance.new()
	model.add_marker("Havoc")
	model.set_marker_value("Havoc", 2)
	model.clear_markers()
	assert_int(model.marker_values.size()).is_equal(0)
