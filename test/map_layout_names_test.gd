extends GdUnitTestSuite
## A1 (Map editor plan): no German words reach the player or the node tree of the Map editor.
## Prefab KEYS (saved in map files) stay as they are; only display names and node names change.

const SCENE := preload("res://scenes/map_layout.tscn")


func test_no_prefab_display_name_is_german() -> void:
	for key: String in TerrainPrefabs.keys():
		var shown: String = TerrainPrefabs.display_name(key)
		assert_bool(shown.contains("Ruine") or shown.contains("Wald")) \
			.override_failure_message("A1 — German display name reaches the player: %s -> %s" % [key, shown]) \
			.is_false()
	assert_str(TerrainPrefabs.display_name("ruine_9x9")).is_equal("Ruin 9×9")
	assert_str(TerrainPrefabs.display_name("ruine_9x6")).is_equal("Ruin 9×6")
	assert_str(TerrainPrefabs.display_name("wald_9x9")).is_equal("Forest 9×9")
	assert_str(TerrainPrefabs.display_name("blocker_6x3")).is_equal("Blocker 6×3")


func test_editor_tab_nodes_have_english_names() -> void:
	var ed: Control = SCENE.instantiate()
	add_child(ed)
	auto_free(ed)
	for bad in ["TabGelaende", "TabZiele", "TabAufstellung"]:
		assert_object(ed.find_child(bad, true, false)) \
			.override_failure_message("A1 — German node name %s still in the editor" % bad).is_null()
	for good in ["TabTerrain", "TabObjectives", "TabDeployment"]:
		assert_object(ed.find_child(good, true, false)).is_not_null()
