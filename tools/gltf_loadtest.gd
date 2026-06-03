extends SceneTree
## Dev check: load a GLB through the runtime glTF path (GLTFDocument.append_from_file),
## exactly as downloaded models are loaded in-game, to confirm an optimized GLB (e.g.
## with WebP textures via EXT_texture_webp) actually loads. Pass the path as the last arg:
##   godot --headless -s tools/gltf_loadtest.gd -- /tmp/opt_test.glb


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "/tmp/opt_test.glb"
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		print("LOADTEST FAIL append err=", err, " path=", path)
		quit(1)
		return
	var scene := doc.generate_scene(state)
	if scene == null:
		print("LOADTEST FAIL generate_scene null")
		quit(1)
		return
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	print("LOADTEST OK path=", path, " meshes=", meshes.size(),
		" images=", state.get_images().size())
	scene.free()
	quit(0)
