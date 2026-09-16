extends SceneTree
## Reproducible forest review on the bundled tutorial board. Run on a real display:
## godot --path . -s res://test/manual/biome_reference_capture.gd -- <output_directory>
## Use isolated XDG_DATA_HOME / XDG_CONFIG_HOME directories with populated asset caches.
## Animated atmosphere is hidden in both revisions to isolate the forest comparison.

var _output: String
var _presentation: Node3D = null


func _initialize() -> void:
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		printerr("A real display and an output directory are required.")
		quit(1)
		return
	_output = args[0]
	DirAccess.make_dir_recursive_absolute(_output)
	seed(20260916)
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	var main := current_scene
	main.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var graphics := root.get_node("GraphicsSettings")
	graphics.apply_preset(2)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	main.atmosphere_controller.set_fires_enabled(false)
	main.atmosphere_controller.set_war_sounds_enabled(false)
	var result: int = await main.save_manager.load_game("res://assets/tutorial/tutorial_board.nml")
	if result != OK:
		printerr("Reference board failed to load: ", result)
		quit(1)
		return
	await create_timer(8.0).timeout
	var original_volumes: Array = main.terrain_overlay.los_volumes().duplicate(true)
	var original_walls: Array = main.terrain_overlay.get_wall_segments_world().duplicate(true)
	if args.size() > 1 and args[1] == "after":
		_presentation = load("res://scripts/visual/grassland_reference.gd").new()
		main.add_child(_presentation)
		_presentation.apply(main)
		if main.terrain_overlay.los_volumes() != original_volumes or main.terrain_overlay.get_wall_segments_world() != original_walls:
			printerr("Reference changed rule geometry")
			quit(1)
			return
		print("REFERENCE_RULE_GEOMETRY_UNCHANGED")
	main.terrain_overlay.set_overlay_mode(1)
	main.terrain_overlay.set_deployment_zones_visible(false)
	main.atmospheric_clouds.visible = false
	main.get_node("UI").visible = false
	main.get_node("CameraPivot").process_mode = Node.PROCESS_MODE_DISABLED
	var camera: Camera3D = main.get_node("CameraPivot/Camera3D")
	camera.fov = 50.0
	var shots := [
		{"name": "forest", "eye": Vector3(-0.50, 0.20, 0.68), "target": Vector3(-0.78, 0.06, 0.35)},
		{"name": "overview", "eye": Vector3(0, 1.3, 1.45), "target": Vector3(0, 0, 0)},
		{"name": "miniatures", "eye": Vector3(-0.50, 0.17, 0.69), "target": Vector3(-0.61, 0.025, 0.39)},
		{"name": "terrain", "eye": Vector3(0.55, 0.45, 0.7), "target": Vector3(0.05, 0.025, 0.0)},
	]
	var report := {"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(), "resolution": "1920x1080",
		"quality": "Medium", "board": "assets/tutorial/tutorial_board.nml",
		"animated_atmosphere": false, "samples": []}
	for mood in (["Day"] if args.has("quick") else ["Day", "Sunset"]):
		main.atmosphere_controller.apply_atmosphere(mood, true)
		if _presentation != null:
			_presentation.apply_lighting(mood)
		for shot in shots:
			if args.has("quick") and shot.name != "miniatures":
				continue
			camera.global_position = shot.eye
			camera.look_at(shot.target)
			for _i in 90:
				await process_frame
			var times: Array[float] = []
			var previous := Time.get_ticks_usec()
			for _i in 180:
				await process_frame
				var now := Time.get_ticks_usec()
				times.append(float(now - previous) / 1000.0)
				previous = now
			times.sort()
			await RenderingServer.frame_post_draw
			var shot_name: String = mood.to_lower() + "_" + shot.name
			var capture := root.get_texture().get_image()
			if capture == null or capture.save_png(_output.path_join(shot_name + ".png")) != OK:
				printerr("Capture failed: ", shot_name)
				quit(1)
				return
			report.samples.append({"shot": shot_name, "median_ms": times[90],
				"p95_ms": times[171], "eye": str(shot.eye), "target": str(shot.target),
				"camera_transform": str(camera.global_transform)})
			print("GFX_CAPTURE ", shot_name, " median_ms=", times[90])
	main.get_node("UI").visible = true
	for _i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_output.path_join("game_ui.png"))
	var file := FileAccess.open(_output.path_join("metrics.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("GFX_CAPTURE_DONE")
	current_scene.queue_free()
	await process_frame
	await process_frame
	quit()
