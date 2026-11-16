extends GdUnitTestSuite
## CoreActivation mirrors three ObjectManager values instead of naming the class: a `-s` tool (arena_match,
## core_dormant_check) that reaches CoreActivation would otherwise compile object_manager.gd and its scene-side chain
## before the autoloads exist and die with "Identifier not found: GraphicsSettings". The mirror must never drift.


func test_movement_cap_values_match_the_selector() -> void:
	assert_int(CoreActivation.CAP_ADVANCE).is_equal(ObjectManager.MovementCap.ADVANCE)
	assert_int(CoreActivation.CAP_RUSH).is_equal(ObjectManager.MovementCap.RUSH)
	assert_int(CoreActivation.CAP_CHARGE).is_equal(ObjectManager.MovementCap.CHARGE)


func test_metre_inch_factor_matches_object_manager() -> void:
	assert_float(CoreActivation.METERS_TO_INCHES).is_equal(ObjectManager.METERS_TO_INCHES)


## The reason the mirror exists: core_activation.gd must not name the ObjectManager class in code (a comment may).
func test_core_activation_does_not_name_the_object_manager_class() -> void:
	var lines := FileAccess.get_file_as_string("res://scripts/solo/core_activation.gd").split("\n")
	var hits: Array[String] = []
	for line in lines:
		var code: String = line.split("#")[0]
		if code.contains("ObjectManager"):
			hits.append(line.strip_edges())
	assert_array(hits).is_empty()
