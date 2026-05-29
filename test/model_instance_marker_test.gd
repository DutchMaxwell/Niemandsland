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
