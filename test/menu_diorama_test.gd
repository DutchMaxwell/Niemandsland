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


## The backdrop breathes: 0.012 m sideways along the camera's right vector on a 40 s sine, plus a 2 % push-in
## over 60 s and back; at rest at t = 0 and with Reduce Motion. RED on main: no such path.
func test_camera_drifts_sideways_and_pushes_in_and_rests_at_zero() -> void:
	var script: GDScript = load("res://scripts/menu_diorama.gd")
	assert_bool(script.has_method("camera_position")).override_failure_message(
		"the backdrop camera has no breathing path").is_true()
	if not script.has_method("camera_position"):
		return
	var rest: Vector3 = MenuDiorama.CAMERA_REST
	var look: Vector3 = MenuDiorama.CAMERA_LOOK
	var ahead := look - rest
	var right := ahead.normalized().cross(Vector3.UP).normalized()
	assert_vector(script.call("camera_position", 0.0, false)).is_equal_approx(rest, Vector3.ONE * 0.000001)
	var quarter: Vector3 = script.call("camera_position", 10.0, false)
	assert_float((quarter - rest).dot(right)).is_equal_approx(0.012, 0.000001)
	var deepest: Vector3 = script.call("camera_position", 60.0, false)
	assert_float(deepest.distance_to(rest)).is_equal_approx(0.02 * ahead.length(), 0.00001)
	assert_vector(script.call("camera_position", 33.0, true)).is_equal(rest)

