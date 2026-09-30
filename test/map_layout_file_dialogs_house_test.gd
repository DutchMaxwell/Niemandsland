extends GdUnitTestSuite
## A11 (Map editor plan): the Save / Load file dialogs carry the house theme; titles are English and the
## modes stay pinned by map_layout_dialogs_test.gd.

const SCENE := preload("res://scenes/map_layout.tscn")


func test_a11_file_dialogs_wear_the_house_theme() -> void:
	var ed: Control = auto_free(SCENE.instantiate())
	add_child(ed)
	await get_tree().process_frame
	for n in ["SaveFileDialog", "LoadFileDialog"]:
		var d := ed.get_node(n) as FileDialog
		assert_bool(d.theme == HouseStyle.theme()).override_failure_message("A11 — %s has no house theme" % n).is_true()
	assert_str((ed.get_node("SaveFileDialog") as FileDialog).title).is_equal("Save Terrain Layout")
	assert_str((ed.get_node("LoadFileDialog") as FileDialog).title).is_equal("Load Terrain Layout")
	assert_int((ed.get_node("LoadFileDialog") as FileDialog).file_mode).is_equal(FileDialog.FILE_MODE_OPEN_FILE)
