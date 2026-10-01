extends GdUnitTestSuite
## F7 (Map editor plan): Clear in the Deployment tab must also clear the zones on the 3D table. Before, it only
## emptied the editor's own lists, so confirmed zones stayed on the 3D table until the next Confirm.

const SCENE := preload("res://scenes/map_layout.tscn")


func test_clear_pushes_the_empty_zones_to_the_3d_table() -> void:
	var ed: Control = auto_free(SCENE.instantiate())
	add_child(ed)
	await get_tree().process_frame
	ed.deployment_type = ed.DeploymentType.CUSTOM
	ed.custom_zone_vertices_p1.assign([Vector2(20, 30), Vector2(40, 30), Vector2(40, 50)])
	ed.custom_zone_vertices_p2.assign([Vector2(60, 50), Vector2(40, 50), Vector2(40, 30)])
	var seen: Array = []
	ed.deployment_type_changed.connect(func(t): seen.append([t, ed.get_custom_zone_data()["player1_world"].size()]))
	ed._on_custom_zone_clear()
	assert_int(seen.size()).override_failure_message("F7 — Clear did not tell the 3D table").is_equal(1)
	if seen.size() == 1:
		assert_int(seen[0][0]).is_equal(ed.DeploymentType.CUSTOM)
		assert_int(seen[0][1]).is_equal(0)
