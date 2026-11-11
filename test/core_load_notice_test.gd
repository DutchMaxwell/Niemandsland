extends GdUnitTestSuite
## CoreLoadNotice (one-core phase 1, step 9): the pure part of the boot notice. The boot line says
## whether NmlCore loaded; the warning dialog shows only on an exported build without the core.
## No scene, no dialog, no ClassDB — the caller passes the two facts in.


func test_boot_line_when_the_core_loaded() -> void:
	assert_str(CoreLoadNotice.boot_line(true)).is_equal("core: NmlCore loaded")


func test_boot_line_when_the_core_is_missing() -> void:
	assert_str(CoreLoadNotice.boot_line(false)).is_equal(
		"core: NmlCore NOT loaded - the decision tree plays; reinstall the game")


func test_should_show_only_on_an_exported_build_without_the_core() -> void:
	assert_bool(CoreLoadNotice.should_show(true, false)).is_true()


func test_should_not_show_on_an_exported_build_with_the_core() -> void:
	assert_bool(CoreLoadNotice.should_show(true, true)).is_false()


func test_should_not_show_in_the_editor_without_the_core() -> void:
	assert_bool(CoreLoadNotice.should_show(false, false)).is_false()


func test_should_not_show_in_the_editor_with_the_core() -> void:
	assert_bool(CoreLoadNotice.should_show(false, true)).is_false()


func test_dialog_texts_are_set() -> void:
	assert_str(CoreLoadNotice.TITLE).is_equal("Rules core missing")
	assert_str(CoreLoadNotice.TEXT).contains("rules core library")
	assert_str(CoreLoadNotice.TEXT).contains("releases page")
