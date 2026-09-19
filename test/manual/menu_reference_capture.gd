extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(1920,1080)
	root.get_node("GraphicsSettings").apply_preset(2)
	change_scene_to_file("res://scenes/startup_menu.tscn")
	await create_timer(18.0).timeout
	for popup in current_scene.find_children("*","Window",true,false):
		popup.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0])
	print("MENU_CAPTURE_DONE")
	current_scene.queue_free()
	await process_frame
	await process_frame
	quit()
