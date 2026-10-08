extends SceneTree
## Calm mode before/after review (GH #1634). Same camera, same board, same selection:
##   calm_off.png / calm_on.png   - the table with a rainy mood and a picked unit
##   combat_off.png / combat_on.png - a volley fired, Calm OFF vs ON
## Run on a real display:
##   godot --path . -s res://test/manual/calm_mode_capture.gd -- <output_directory>

var _output: String


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
	seed(20261007)
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
		printerr("Board failed to load: ", result)
		quit(1)
		return
	await create_timer(8.0).timeout

	main.get_node("UI").visible = false
	main.atmospheric_clouds.visible = false
	main.get_node("CameraPivot").process_mode = Node.PROCESS_MODE_DISABLED
	var camera: Camera3D = main.get_node("CameraPivot/Camera3D")
	camera.fov = 50.0
	camera.global_position = Vector3(0.0, 1.15, 1.30)
	camera.look_at(Vector3(0.0, 0.0, 0.0))

	# A rainy mood so weather particles read in the still.
	main.atmosphere_controller.apply_atmosphere("Rain", true)

	# Pick a couple of miniatures so the selection aids (glow, ring) read.
	var picks: Array = []
	for model in main.object_manager.get_children():
		if model is Node3D and model.is_in_group("selectable"):
			picks.append(model)
			if picks.size() >= 2:
				break
	if not picks.is_empty():
		main.object_manager.select_objects(picks)
	var pair: Array = _volley_pair(picks)

	graphics.set_calm_mode(false)
	await _settle(120)
	await _save("calm_off.png")

	if not pair.is_empty():
		main.shot_show.volley([pair], 1, 20261007, 0, 0.0)
		await create_timer(0.7).timeout
		await _save("combat_off.png")
	await _settle(120)

	graphics.set_calm_mode(true)
	await _settle(120)
	await _save("calm_on.png")

	if not pair.is_empty():
		main.shot_show.volley([pair], 1, 20261007, 0, 0.0)
		await create_timer(0.7).timeout
		await _save("combat_on.png")

	print("CALM_CAPTURE_DONE ", _output)
	current_scene.queue_free()
	await process_frame
	quit()


func _volley_pair(picks: Array) -> Array:
	if picks.size() < 2:
		return []
	var a: Vector3 = (picks[0] as Node3D).global_position + Vector3.UP * 0.03
	var b: Vector3 = (picks[1] as Node3D).global_position + Vector3.UP * 0.03
	return [a, b]


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.save_png(_output.path_join(name)) != OK:
		printerr("Capture failed: ", name)
		quit(1)
		return
	print("CALM_CAPTURE ", name)
