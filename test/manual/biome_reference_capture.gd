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
		await _presentation.prepare()
		var miniatures: Dictionary = {}
		for model in main.object_manager.get_children():
			if model is Node3D and model.is_in_group("selectable"):
				miniatures[model] = model.global_transform
		_presentation.apply(main)
		for model: Node3D in miniatures:
			if model.global_transform != miniatures[model]:
				printerr("Reference moved an existing miniature")
				quit(1)
				return
		print("REFERENCE_MINIATURE_TRANSFORMS_UNCHANGED ",miniatures.size())
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
		{"name": "detail", "eye": Vector3(-0.57,0.145,0.60), "target": Vector3(-0.68,0.030,0.38)},
		{"name": "forest", "eye": Vector3(-0.50, 0.20, 0.68), "target": Vector3(-0.78, 0.06, 0.35)},
		{"name": "overview", "eye": Vector3(0, 1.3, 1.45), "target": Vector3(0, 0, 0)},
		{"name": "miniatures", "eye": Vector3(-0.50, 0.17, 0.69), "target": Vector3(-0.61, 0.025, 0.39)},
		{"name": "terrain", "eye": Vector3(0.55, 0.45, 0.7), "target": Vector3(0.05, 0.025, 0.0)},
	]
	var report := {"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(), "resolution": "1920x1080",
		"quality": "Reference studio" if args.has("studio") else "Medium",
		"internal_scale": root.scaling_3d_scale, "board": "assets/tutorial/tutorial_board.nml",
		"animated_atmosphere": false, "samples": []}
	var moods: Array = ["Day"]
	if args.has("sunset"):
		moods = ["Sunset"]
	elif not args.has("quick"):
		moods = ["Day", "Sunset"]
	for mood in moods:
		main.atmosphere_controller.apply_atmosphere(mood, true)
		if _presentation != null:
			_presentation.apply_lighting(mood)
		if args.has("studio"):
			root.use_taa = false
			root.scaling_3d_scale = 1.25
			RenderingServer.directional_shadow_atlas_set_size(8192,true)
			var sun: DirectionalLight3D = main.get_node("DirectionalLight3D")
			sun.directional_shadow_max_distance = 3.0
			sun.directional_shadow_pancake_size = 1.0
			sun.shadow_bias = 0.015
			sun.shadow_normal_bias = 0.25
			var env: Environment = main.get_node("WorldEnvironment").environment
			env.ssao_radius = 0.035
			env.ssao_intensity = 2.0
			env.ssao_power = 1.4
		report.internal_scale = root.scaling_3d_scale
		for shot in shots:
			if args.has("quick") and shot.name not in ["miniatures","detail"]:
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
	if args.has("effects") and _presentation != null:
		camera.global_position = Vector3(-0.50,0.17,0.69)
		camera.look_at(Vector3(-0.61,0.025,0.39))
		main.get_node("WorldEnvironment").environment.volumetric_fog_temporal_reprojection_enabled = false
		Engine.time_scale = 0.0
		for _i in 60:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_output.path_join("fx_all.png"))
		# Old, too-strong tilt-shift for the "before/after of the fix" split.
		_presentation.set_tilt_shift_enabled(false)
		_presentation._dof.dof_blur_amount = 0.09
		for _i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_output.path_join("fx_tiltstrong.png"))
		_presentation.set_tilt_shift_enabled(true)
		# Old, too-thick fog for the "before/after of the fix" split.
		if _presentation._fog != null:
			var tbl: Vector2 = main.get_node("Table").table_size * 0.3048
			var sp: float = maxf(tbl.x,tbl.y)
			_presentation._fog.size = Vector3(sp,sp * 0.6,sp)
			_presentation._fog.position.y = sp * 0.30
			_presentation._fog.material.density = 0.30
			for _i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(_output.path_join("fx_fogheavy.png"))
			_presentation._fog.size = Vector3(sp,0.015,sp)
			_presentation._fog.position.y = 0.010
			_presentation._fog.material.density = 3.0
		_presentation.set_tilt_shift_enabled(false)
		for _i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_output.path_join("fx_notilt.png"))
		_presentation.set_tilt_shift_enabled(true)
		if _presentation._fog != null:
			_presentation._fog.visible = false
			for _i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(_output.path_join("fx_nofog.png"))
			_presentation._fog.visible = true
		var puddles := _presentation.find_child("Puddles",true,false)
		print("PUDDLE_NODE ",puddles != null)
		if puddles != null:
			puddles.visible = false
			for _i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(_output.path_join("fx_nopuddle.png"))
			puddles.visible = true
		Engine.time_scale = 1.0
		print("REFERENCE_EFFECTS_DONE")
	if args.has("flight"):
		var frame_directory := _output.path_join("flight_frames")
		DirAccess.make_dir_recursive_absolute(frame_directory)
		# A slow descending spiral: steady orbit around the tree group while the
		# radius and height ease down towards the surface, so lighting and wind
		# get time to read.
		var center := Vector3(-0.60,0.030,0.45)
		var frames := 1200
		var turns := 2.5 * PI
		for frame in frames:
			var t := float(frame)/float(frames-1)
			var radius := lerpf(1.35,0.26,t)
			var height := lerpf(1.30,0.16,t)
			var angle := turns * t
			camera.global_position = Vector3(center.x+radius*cos(angle),height,center.z+radius*sin(angle))
			camera.look_at(center)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(frame_directory.path_join("%04d.jpg"%frame),0.95)
		print("REFERENCE_FLIGHT_DONE")
	if args.has("orbit"):
		var frame_directory := _output.path_join("flight_frames")
		DirAccess.make_dir_recursive_absolute(frame_directory)
		for frame in 240:
			var t := float(frame)/239.0
			var eased := t*t*(3.0-2.0*t)
			camera.global_position = Vector3(-0.61,0.16,0.68).lerp(Vector3(-0.40,0.19,0.60),eased)
			camera.look_at(Vector3(-0.65,0.035,0.38))
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(frame_directory.path_join("%04d.jpg"%frame),0.95)
		print("REFERENCE_FLIGHT_DONE")
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
