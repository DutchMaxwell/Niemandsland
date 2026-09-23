extends SceneTree
## Renders the main menu's backdrop stills, assets/ui/menu_backdrop/<biome>.res: the live menu diorama of each
## biome, fully built (MenuDiorama in FORCED mode, diorama_ready), captured from its own viewport at the camera's
## rest position. The menu shows the still until its live scene is complete, then crossfades to it.
##
## Needs a display (headless has no renderer) and the asset caches or network, from the repo root:
##   godot --path . --audio-driver Dummy -s tools/menu_backdrop_render.gd -- [--preset=N] [biome ...]
## Re-render after any change to the menu scene (menu_battlefield.gd, its terrain, units or biome dressing).
## The still is 2560x1080, wider than common windows: the menu keeps its height and crops the sides.
## Saved as a PortableCompressedTexture2D holding lossy WebP (~200-330 KB), which exports as is: a plain .webp would
## ship as the importer's default lossless texture (~2 MB each; *.import files are not in the repo). A WebP copy
## for review goes to user://menu_backdrop_<biome>.webp.

## Loaded at run time: a -s script compiles before the autoloads the menu scripts name exist.
const DIORAMA_PATH := "res://scripts/menu_diorama.gd"
const SIZE := Vector2i(2560, 1080)
const OUT := "res://assets/ui/menu_backdrop/%s.res"
## Frames after diorama_ready: fire flicker, fog and the reveal settle.
const SETTLE_FRAMES := 120
const BUILD_TIMEOUT_MS := 240000


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var biomes: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preset="):
			root.get_node("GraphicsSettings").apply_preset(int(arg.get_slice("=", 1)))
		else:
			biomes.append(arg)
	if biomes.is_empty():
		biomes = load(DIORAMA_PATH).Battlefield.BIOMES
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var failed := 0
	for biome in biomes:
		if not await _render(str(biome)):
			failed += 1
	quit(1 if failed > 0 else 0)


func _render(biome: String) -> bool:
	var script: GDScript = load(DIORAMA_PATH)
	var diorama = script.new()
	diorama.mode = script.Mode.FORCED
	diorama.size = SIZE
	var built := [false]
	diorama.diorama_ready.connect(func() -> void: built[0] = true)
	root.add_child(diorama)
	# _ready takes the biome saved in user://menu.cfg; switch to the requested one (a rebuild).
	if diorama.biome != biome:
		diorama.set_biome(biome)
	var deadline := Time.get_ticks_msec() + BUILD_TIMEOUT_MS
	while not built[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	if not built[0]:
		printerr("MENU_BACKDROP %s: not ready after %d s" % [biome, BUILD_TIMEOUT_MS / 1000])
		diorama.queue_free()
		return false
	for _i in SETTLE_FRAMES:
		await process_frame
	diorama._drift_t = 0.0   # the rest position the live menu starts its drift from at the reveal
	await process_frame
	await RenderingServer.frame_post_draw
	var viewport: SubViewport = diorama._viewport
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	image.save_webp(OS.get_user_data_dir().path_join("menu_backdrop_%s.webp" % biome), true, 0.7)
	var still := PortableCompressedTexture2D.new()
	still.keep_compressed_buffer = true   # outside the editor the buffer is dropped, and nothing would be saved
	still.create_from_image(image, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY, false, 0.7)
	var err := ResourceSaver.save(still, OUT % biome)
	var path := ProjectSettings.globalize_path(OUT % biome)
	print("MENU_BACKDROP %s %dx%d preset=%d -> %s (%d KB) err=%d" % [biome, image.get_width(), image.get_height(),
		root.get_node("GraphicsSettings").current_preset, path, FileAccess.get_file_as_bytes(path).size() / 1024, err])
	diorama.queue_free()
	for _i in 10:
		await process_frame
	return err == OK
