extends GdUnitTestSuite
## #216 — the Map Tool's LOAD dialog spoke the SAVE language: "save" button verbiage and the
## overwrite confirmation. Root cause: the scene never set file_mode on LoadFileDialog, and
## Godot's FileDialog DEFAULTS to FILE_MODE_SAVE_FILE — the whole save behaviour rode in on
## the default. Scene-level pin, no tree needed (tscn property assignments happen at
## instantiate time).


func test_load_dialog_is_an_open_dialog() -> void:
	var scene := load("res://scenes/map_layout.tscn") as PackedScene
	var root := scene.instantiate()
	var dlg := root.get_node("LoadFileDialog") as FileDialog
	assert_that(dlg).is_not_null()
	assert_int(dlg.file_mode) \
		.override_failure_message("#216 — LoadFileDialog is not an OPEN dialog: Godot's SAVE default gives it the 'Save' button and the overwrite confirmation") \
		.is_equal(FileDialog.FILE_MODE_OPEN_FILE)
	var save_dlg := root.get_node("SaveFileDialog") as FileDialog
	assert_int(save_dlg.file_mode).is_equal(FileDialog.FILE_MODE_SAVE_FILE)
	root.free()
