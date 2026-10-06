extends SceneTree
## GPU capture lane only. Boots main.tscn, uses the production restore/model factory and
## local manifest cache. NML_IDLE_TAKE_KIND=before|after|clip; NML_IDLE_CAPTURE_OUT=directory.
## For video run Godot Movie Maker --fixed-fps 30 --write-movie /path/take.avi;
## trim to the IDLE_TAKE_BEGIN/END drawn-frame indices (240 frames = eight seconds).

var _out := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Use the laptop GPU capture lane, not the headless renderer")
		quit(2)
		return
	var idle_script: GDScript = load("res://scripts/visual/bone_texture_idle.gd")
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	_out = OS.get_environment("NML_IDLE_CAPTURE_OUT")
	DirAccess.make_dir_recursive_absolute(_out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var manager: Node = main.opr_army_manager
	var library: Node = manager.model_library
	var manifest := FileAccess.get_file_as_string(OS.get_environment("NML_IDLE_MANIFEST"))
	library.apply_manifest_text(manifest)
	var settings := root.get_node("GraphicsSettings")
	settings.apply_preset(2)
	settings.idle_motion = true
	settings.reduce_motion = false
	var mode := OS.get_environment("NML_IDLE_TAKE_KIND")
	RenderingServer.global_shader_parameter_set("idle_freeze_time", 0.0)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.near = 0.003
	camera.fov = 38
	camera.current = true
	var center: Vector2 = main._table_rect().get_center()
	var floor_y: float = main.object_manager._surface_y_under(Vector3(center.x, 0, center.y))
	camera.position = Vector3(center.x, floor_y + 0.065, center.y + 0.32)
	camera.look_at(Vector3(center.x, floor_y + 0.025, center.y))
	var models: Array[Node3D] = []
	var active := 0
	var forms := ["warriors", "warriors#spear", "warriors#banner+halberd"]
	for column in 2:
		for row in 3:
			var key: String = forms[row]
			var entry: Dictionary = library._models["ratmen/" + key]
			var payload: Variant = entry.get("idle")
			if column == 0 or mode == "before":
				entry.erase("idle")
			var model: Node3D = manager.create_model_from_properties({"name": "Warriors", "faction_folder": "ratmen",
				"base_size_round": 25, "base_width_mm": 25, "base_depth_mm": 25, "size": 1, "player_id": 1}, 1, key)
			if payload != null:
				entry["idle"] = payload
			main.object_manager.add_child(model)
			model.position = Vector3(center.x + (column - 0.5) * 0.12 + (row-1)*0.032,
				floor_y, center.y + (row-1)*0.01)
			for idle in model.find_children("BoneTextureIdle", "Node3D", true, false):
				if idle.get_script() == idle_script:
					active += 1
					idle._visual.set_instance_shader_parameter("idle_phase", idle_script.phase_for(key + str(row)))
					idle.refresh()
			models.append(model)
	for layer: CanvasLayer in root.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	var labels := CanvasLayer.new()
	root.add_child(labels)
	for pair in [["Static", 0.21], ["Real idle payload", 0.66]]:
		var label := Label.new()
		label.text = pair[0]
		label.position = Vector2(root.size.x * pair[1], 35)
		label.add_theme_font_size_override("font_size", 28)
		labels.add_child(label)
	for i in 60:
		await process_frame
	if mode != "before" and active != 3:
		push_error("Expected three payload models; check isolated model_cache and manifest")
		quit(1)
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(mode + "_start.png"))
	var begin := Engine.get_frames_drawn()
	print("IDLE_TAKE_BEGIN ", begin)
	for f in 240:
		RenderingServer.global_shader_parameter_set("idle_freeze_time", f / 30.0 if mode == "clip" else 0.0)
		await process_frame
		if f == 120:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(_out.path_join(mode + "_middle.png"))
	print("IDLE_TAKE_END ", Engine.get_frames_drawn(), " payload_models=", active)
	RenderingServer.global_shader_parameter_set("idle_freeze_time", -1.0)
	quit()
