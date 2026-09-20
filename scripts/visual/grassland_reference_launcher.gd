extends Node
## Separate preview entry point. Production startup and saved games are unchanged.

func _ready() -> void:
	ProjectSettings.set_setting("niemandsland/harness_mode",true)
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main := packed.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	var result: int = await main.save_manager.load_game("res://assets/tutorial/tutorial_board.nml")
	if result != OK:
		push_error("Unable to load the reference board.")
		return
	await get_tree().create_timer(8.0).timeout
	if not is_instance_valid(main):
		queue_free()
		return
	main.atmosphere_controller.set_fires_enabled(true)
	main.atmosphere_controller.set_war_sounds_enabled(false)
	main.terrain_overlay.set_overlay_mode(1)
	main.terrain_overlay.set_deployment_zones_visible(false)
	main.atmospheric_clouds.visible = false
	main.get_node("CameraPivot").set_zoom(1.65)
	main.atmosphere_controller.apply_atmosphere("Day",true)
	var presentation := preload("res://scripts/visual/grassland_reference.gd").new()
	presentation.biome = _chosen_biome()
	main.add_child(presentation)
	await presentation.prepare()
	if not is_instance_valid(main):
		queue_free()
		return
	presentation.apply(main)
	main.set_meta("grassland_reference_ready", true)
	print("REFERENCE_SCENE_READY")
	queue_free()


## `--biome <name>` after the `--` separator selects the profile; default grassland.
func _chosen_biome() -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--biome" and i+1 < args.size():
			return args[i+1]
	return "grassland"
