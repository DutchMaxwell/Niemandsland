extends Node
## Dev tool: render the TableSizeDialog content to renders/dialog_preview.png so the
## startup chooser layout (incl. the biome row) can be verified headlessly. Not shipped.

const OUT := "res://renders/dialog_preview.png"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	var dlg: Window = load("res://scripts/table_size_dialog.gd").new()
	get_tree().root.add_child(dlg)  # _ready builds the UI
	await get_tree().process_frame
	dlg.set_biomes(
		["temperate_grassland", "arid_desert", "frozen_tundra", "volcanic_ash", "alien_jungle", "urban_ruins"],
		"temperate_grassland")
	await get_tree().process_frame

	var win_size: Vector2i = dlg.size
	var content := dlg.get_child(0) as Control  # bg_panel (PRESET_FULL_RECT)
	dlg.remove_child(content)

	var vp := SubViewport.new()
	vp.size = win_size
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(vp)
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(content)

	var scroll := dlg.find_children("*", "ScrollContainer", true, false)
	var vb: Control = (scroll[0].get_child(0) as Control) if scroll.size() > 0 else null
	print("DLG win=", win_size, " content_min_h=", (vb.get_combined_minimum_size().y if vb else -1.0))

	for _i in range(8):
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders"))
	vp.get_texture().get_image().save_png(OUT)
	print("DIALOG_RENDERED")
	get_tree().quit()
