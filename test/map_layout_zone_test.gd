extends GdUnitTestSuite
## F2 (Map editor plan): the custom-zone drawing flow. Needs the real scene in the tree because the
## Start / Confirm / status widgets are built in code by _ready().

const SCENE := preload("res://scenes/map_layout.tscn")


func _editor() -> Control:
	var ed: Control = SCENE.instantiate()
	add_child(ed)
	auto_free(ed)
	ed.deployment_type = ed.DeploymentType.CUSTOM
	return ed


func test_confirm_needs_three_points() -> void:
	var ed := _editor()
	ed.custom_zone_symmetric = false
	ed._on_custom_zone_start()
	ed._handle_custom_zone_click(Vector2(1, 1))
	ed._handle_custom_zone_click(Vector2(5, 1))
	assert_bool(ed._custom_zone_confirm_btn.disabled) \
		.override_failure_message("F2 — Confirm must stay disabled with < 3 points") \
		.is_true()
	ed._handle_custom_zone_click(Vector2(5, 5))
	assert_bool(ed._custom_zone_confirm_btn.disabled).is_false()


func test_confirm_with_no_points_does_not_claim_zones_defined() -> void:
	var ed := _editor()
	ed.custom_zone_symmetric = false
	ed._on_custom_zone_start()
	ed._on_custom_zone_confirm()
	assert_str(ed._custom_zone_status_label.text) \
		.override_failure_message("F2 — Confirm with zero points said 'Custom zones defined!'") \
		.contains("at least 3")
	assert_bool(ed.custom_zone_editing).is_true()


func test_start_drawing_keeps_existing_zone_until_first_new_vertex() -> void:
	var ed := _editor()
	ed.custom_zone_symmetric = false
	ed.custom_zone_vertices_p1.assign([Vector2(1, 1), Vector2(5, 1), Vector2(5, 5)])
	ed._on_custom_zone_start()
	assert_int(ed.custom_zone_vertices_p1.size()) \
		.override_failure_message("F2 — Start Drawing wiped the existing zone before any new vertex") \
		.is_equal(3)
	ed._handle_custom_zone_click(Vector2(9, 9))
	assert_int(ed.custom_zone_vertices_p1.size()).is_equal(1)
