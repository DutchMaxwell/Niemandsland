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
	if menu.view.route_panel.visible:
		await menu.view.route_closed
	assert_bool(menu.view.route_panel.visible).is_false()
	dialog.get_ok_button().pressed.emit()
	await get_tree().process_frame
	assert_bool(dialog.visible).is_false()
	menu.view.show_route("help")
	menu.view.buttons.WhatsNewBtn.pressed.emit()
	assert_bool(dialog.visible).is_true()
	assert_int(menu.find_children("WhatsNewDialog", "", false, false).size()).is_equal(1)

class OfflineMenu extends "res://scripts/startup_menu.gd":
	var fresh_profile := false
	func _is_fresh_profile() -> bool:
		return fresh_profile
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

func _mount_live_menu(fresh_profile := false) -> Control:
	var menu: Control = load("res://scenes/startup_menu.tscn").instantiate()
	menu.set_script(OfflineMenu)
	menu.fresh_profile = fresh_profile
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	return menu


## The marks of a first launch (D2), each on its own: no recorded version, no menu.cfg, no
## player_identity.cfg, no save. RED on main: the rule does not exist.
func test_fresh_profile_needs_all_four_marks_absent() -> void:
	var script: GDScript = load("res://scripts/whats_new_content.gd")
	assert_bool(script.has_method("is_fresh_profile")).override_failure_message(
		"no rule for a first launch").is_true()
	if not script.has_method("is_fresh_profile"):
		return
	var dir := "user://whats_new_fresh_test"
	var saves := dir.path_join("saves")
	var menu_cfg := dir.path_join("menu.cfg")
	var identity := dir.path_join("player_identity.cfg")
	var state := dir.path_join("whats_new.cfg")
	DirAccess.make_dir_recursive_absolute(saves)
	var fresh := func() -> bool:
		return script.call("is_fresh_profile", menu_cfg, identity, saves, state)
	assert_bool(fresh.call()).is_true()
	for mark: String in [menu_cfg, identity, saves.path_join("a.nml")]:
		FileAccess.open(mark, FileAccess.WRITE).store_string("x")
		assert_bool(fresh.call()).override_failure_message(
			"%s did not end the first launch" % mark).is_false()
		DirAccess.remove_absolute(mark)
	var record := ConfigFile.new()
	record.set_value("news", "last_seen_version", "0.0.1")
	record.save(state)
	assert_bool(fresh.call()).override_failure_message(
		"a recorded version did not end the first launch").is_false()
	DirAccess.remove_absolute(state)
	DirAccess.remove_absolute(saves)
	DirAccess.remove_absolute(dir)


## RED on main: the first launch opened the release notes before the player had seen the menu.
func test_fresh_profile_opens_on_the_menu_and_records_the_version() -> void:
	var previous := get_tree().current_scene
	var menu := _mount_live_menu(true)
	await get_tree().process_frame
	assert_object(menu._whats_new).override_failure_message(
		"the first launch opened the release notes").is_null()
	assert_bool(WhatsNewContent.should_show()).override_failure_message(
		"the version was not recorded").is_false()
	menu.free()
	get_tree().current_scene = previous


## A profile that has prepared a table before but never recorded a version (an install from before
## the sheet existed) still gets the sheet.
func test_profile_with_a_menu_cfg_and_no_record_still_gets_the_sheet() -> void:
	var previous := get_tree().current_scene
	var menu := _mount_live_menu(false)
	await get_tree().process_frame
	assert_object(menu._whats_new).is_not_null()
	menu.free()
	get_tree().current_scene = previous


## The news card at the right edge shows the first highlight, opens the release notes, steps
## aside for a route panel and is not there without notes (sheet 01; red on main: no card).
func test_the_news_card_shows_the_first_title_and_opens_the_notes() -> void:
	var runner := scene_runner("res://scenes/startup_menu.tscn")
	var menu := runner.scene()
	var card: Button = menu.view.get("news_card")
	assert_object(card).override_failure_message("the menu has no news card").is_not_null()
	if card == null:
		return
	var first: Dictionary = WhatsNewContent.new().cards()[0]
	var texts: Dictionary = first[WhatsNewContent.language(TranslationServer.get_locale())]
	var words: Array[String] = []
	for l: Node in card.find_children("*", "Label", true, false):
		words.append((l as Label).text)
	assert_bool(card.visible).is_true()
	assert_bool(words.has(str(texts.title))) \
		.override_failure_message("card words: %s" % str(words)).is_true()
	var count := WhatsNewContent.new().cards().size()
	assert_bool(words.has("%d highlights" % count)).is_true()
	# sheet 01: the release in three parts ("0.3.15", not "0.3.15.0-ALPHA"),
	# and "Read ›" right after the count
	var eyebrow := (menu.view.get("_news_eyebrow") as Label).text
	var parts := WhatsNewContent.version().get_slice("-", 0).split(".").slice(0, 3)
	var release := ".".join(parts).to_upper()
	assert_bool(eyebrow.ends_with(release)).override_failure_message(eyebrow).is_true()
	var count_label := menu.view.get("_news_count") as Label
	await get_tree().process_frame
	var reads := card.find_children("*", "Label", true, false).filter(
		func(l: Node) -> bool: return (l as Label).text == "Read")
	var read := reads[0] as Label
	var gap := read.get_global_rect().position.x - count_label.get_global_rect().end.x
	assert_float(gap).is_less(30.0)
	menu.view.show_route("help")
	assert_bool(card.visible) \
		.override_failure_message("the card stays over an open route panel").is_false()
	menu.view.close_route()
	await menu.view.route_closed
	assert_bool(card.visible).is_true()
	card.pressed.emit()
	assert_bool((menu.get_node("WhatsNewDialog") as AcceptDialog).visible).is_true()
	menu.view.set_news([])
	assert_bool(card.visible).override_failure_message("a card without notes").is_false()
