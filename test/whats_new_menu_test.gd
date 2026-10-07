extends GdUnitTestSuite

var _state_bytes := PackedByteArray()
var _state_existed := false

func before_test() -> void:
	_state_existed = FileAccess.file_exists(WhatsNewContent.STATE_PATH)
	if _state_existed:
		_state_bytes = FileAccess.get_file_as_bytes(WhatsNewContent.STATE_PATH)
	DirAccess.remove_absolute(WhatsNewContent.STATE_PATH)

func after_test() -> void:
	if _state_existed:
		FileAccess.open(WhatsNewContent.STATE_PATH, FileAccess.WRITE).store_buffer(_state_bytes)
	else:
		DirAccess.remove_absolute(WhatsNewContent.STATE_PATH)

func test_menu_can_reopen_dismissed_news() -> void:
	var runner := scene_runner("res://scenes/startup_menu.tscn")
	var menu := runner.scene()
	assert_bool(menu.view.buttons.has("WhatsNewBtn")).is_true()
	if not menu.view.buttons.has("WhatsNewBtn"):
		return
	menu.view.show_route("help")
	menu.view.buttons.WhatsNewBtn.pressed.emit()
	var dialog: AcceptDialog = menu.get_node("WhatsNewDialog")
	assert_bool(dialog.visible).is_true()
	assert_bool(menu.view.route_panel.visible).is_false()
	dialog.get_ok_button().pressed.emit()
	await get_tree().process_frame
	assert_bool(dialog.visible).is_false()
	menu.view.show_route("help")
	menu.view.buttons.WhatsNewBtn.pressed.emit()
	assert_bool(dialog.visible).is_true()
	assert_int(menu.find_children("WhatsNewDialog", "", false, false).size()).is_equal(1)

class OfflineMenu extends "res://scripts/startup_menu.gd":
	func _maybe_check_for_updates() -> void:
		pass
	func _start_menu_music() -> void:
		pass

func test_live_startup_shows_once_and_next_version_shows_again() -> void:
	var previous := get_tree().current_scene
	var version := WhatsNewContent.version()
	var menu := _mount_live_menu()
	await get_tree().process_frame
	assert_object(menu._whats_new).is_not_null()
	if is_instance_valid(menu._whats_new):
		assert_bool(menu._whats_new.visible).is_true()
	menu.free()
	menu = _mount_live_menu()
	await get_tree().process_frame
	assert_object(menu._whats_new).is_null()
	menu.free()
	ProjectSettings.set_setting("application/config/version", version + ".next")
	menu = _mount_live_menu()
	await get_tree().process_frame
	assert_object(menu._whats_new).is_not_null()
	menu.free()
	ProjectSettings.set_setting("application/config/version", version)
	get_tree().current_scene = previous

func test_update_offer_waits_for_news_to_close() -> void:
	var runner := scene_runner("res://scenes/startup_menu.tscn")
	var menu := runner.scene()
	menu._show_whats_new()
	menu._on_update_available("test-next", "", "Test release notes")
	assert_int(menu.find_children("*", "UpdatePrompt", false, false).size()).is_equal(0)
	menu._whats_new.hide()
	await get_tree().process_frame
	var prompts := menu.find_children("*", "UpdatePrompt", false, false)
	assert_int(prompts.size()).is_equal(1)
	assert_bool(prompts[0].visible).is_true()

func _mount_live_menu() -> Control:
	var menu: Control = load("res://scenes/startup_menu.tscn").instantiate()
	menu.set_script(OfflineMenu)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	return menu
