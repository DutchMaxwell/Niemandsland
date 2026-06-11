extends GdUnitTestSuite
## Tests the main-menu diorama gating: pure tier rule, and the AUTO-mode guard that
## keeps tests/headless runs on the lightweight sky-only path (no R2-backed 3D).


func test_should_build_diorama_per_tier() -> void:
	assert_bool(MenuDiorama.should_build_diorama(GraphicsSettings.QualityPreset.PERFORMANCE)).is_false()
	assert_bool(MenuDiorama.should_build_diorama(GraphicsSettings.QualityPreset.LOW)).is_true()
	assert_bool(MenuDiorama.should_build_diorama(GraphicsSettings.QualityPreset.MEDIUM)).is_true()
	assert_bool(MenuDiorama.should_build_diorama(GraphicsSettings.QualityPreset.HIGH)).is_true()
	assert_bool(MenuDiorama.should_build_diorama(GraphicsSettings.QualityPreset.ULTRA)).is_true()


func test_auto_mode_stays_sky_only_outside_current_scene() -> void:
	var diorama := MenuDiorama.new()
	add_child(auto_free(diorama))
	await get_tree().process_frame
	# Not the current scene -> sky-only: no terrain overlay, no war ambience.
	assert_object(_find_by_script(diorama, "terrain_overlay.gd")).is_null()
	assert_object(_find_by_script(diorama, "war_ambience.gd")).is_null()
	# But the lighting controller exists in BOTH modes (menu Settings binds to it).
	assert_object(diorama.get_lighting_controller()).is_not_null()


func test_sky_only_mode_never_builds() -> void:
	var diorama := MenuDiorama.new()
	diorama.mode = MenuDiorama.Mode.SKY_ONLY
	add_child(auto_free(diorama))
	await get_tree().process_frame
	assert_object(_find_by_script(diorama, "terrain_overlay.gd")).is_null()


func _find_by_script(root: Node, script_file: String) -> Node:
	for child in root.get_children():
		var script: Script = child.get_script() as Script
		if script != null and script.resource_path.ends_with(script_file):
			return child
		var found := _find_by_script(child, script_file)
		if found != null:
			return found
	return null