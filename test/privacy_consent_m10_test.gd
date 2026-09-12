extends GdUnitTestSuite

const BUILDER_PATH := "res://scripts/privacy/shared_record_builder.gd"
const STORE_PATH := "res://scripts/privacy/consent_store.gd"
const MENU_SCENE := "res://scenes/privacy/privacy_menu.tscn"
const FIXTURE_PATH := "res://assets/privacy/example_record.json"
const GOLDEN_PATH := "res://test/fixtures/privacy/example_record.canonical.json"
const TEST_STORE := "user://test_privacy_m10/privacy.json"
const TEST_EXPORT := "user://test_shared_records/example.json"
const CARD_PATH := "res://scripts/privacy/after_game_card.gd"
const COLLECTOR_PATH := "res://scripts/privacy/game_record_collector.gd"
const TEST_LAST_EXPORT := "user://test_shared_records/last_game.json"


func before_test() -> void:
	_remove_file(TEST_STORE)
	_remove_file(TEST_EXPORT)
	_remove_file(TEST_LAST_EXPORT)


func after_test() -> void:
	_remove_file(TEST_STORE)
	_remove_file(TEST_EXPORT)
	_remove_file(TEST_LAST_EXPORT)


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _require(path: String) -> bool:
	var exists := FileAccess.file_exists(path)
	assert_bool(exists).override_failure_message("Required M10 implementation is missing: %s" % path).is_true()
	return exists


func test_builder_matches_checked_in_golden_bytes() -> void:
	if not _require(BUILDER_PATH) or not _require(GOLDEN_PATH):
		return
	var builder = load(BUILDER_PATH)
	var expected := FileAccess.get_file_as_string(GOLDEN_PATH).strip_edges().to_utf8_buffer()
	assert_array(builder.build(_load_json(FIXTURE_PATH))).is_equal(expected)


func test_allowlisted_change_changes_bytes_and_hash() -> void:
	if not _require(BUILDER_PATH):
		return
	var builder = load(BUILDER_PATH)
	var record := _load_json(FIXTURE_PATH)
	var changed := record.duplicate(true)
	changed["rounds"] = int(changed["rounds"]) + 1
	var bytes_before: PackedByteArray = builder.build(record)
	var bytes_after: PackedByteArray = builder.build(changed)
	assert_array(bytes_after).is_not_equal(bytes_before)
	var before_json: Dictionary = JSON.parse_string(bytes_before.get_string_from_utf8())
	var after_json: Dictionary = JSON.parse_string(bytes_after.get_string_from_utf8())
	assert_str(str(after_json["payload_sha256"])).is_not_equal(str(before_json["payload_sha256"]))


func test_forbidden_keys_and_values_are_dropped() -> void:
	if not _require(BUILDER_PATH):
		return
	var builder = load(BUILDER_PATH)
	var forbidden := ["player_name", "army_name", "unit_display_name", "chat", "room_code", "identity_token", "path", "hostname", "notes"]
	for key: String in forbidden:
		var record := _load_json(FIXTURE_PATH)
		var marker := "private-marker-%s" % key
		record[key] = marker
		(record["armies"][0] as Dictionary)[key] = marker
		var text: String = builder.build(record).get_string_from_utf8()
		assert_str(text).not_contains(key)
		assert_str(text).not_contains(marker)


func test_consent_defaults_and_withdrawal_persist() -> void:
	if not _require(STORE_PATH):
		return
	var store_script = load(STORE_PATH)
	var store = store_script.new(TEST_STORE)
	store.load_from_disk()
	assert_bool(store.evaluation_sharing).is_false()
	assert_bool(store.training_use).is_false()
	assert_bool(store.prompt_seen).is_false()
	assert_int(store.deletion_code.length()).is_equal(32)
	store.set_consent(true, true)
	var reloaded = store_script.new(TEST_STORE)
	reloaded.load_from_disk()
	assert_bool(reloaded.evaluation_sharing).is_true()
	assert_bool(reloaded.training_use).is_true()
	assert_str(reloaded.deletion_code).is_equal(store.deletion_code)
	reloaded.withdraw()
	var withdrawn = store_script.new(TEST_STORE)
	withdrawn.load_from_disk()
	assert_bool(withdrawn.evaluation_sharing).is_false()
	assert_bool(withdrawn.training_use).is_false()
	assert_bool(withdrawn.prompt_seen).is_true()
	var stale := _load_json(TEST_STORE)
	stale["consent_schema_version"] = 0
	stale["evaluation_sharing"] = true
	var stale_file := FileAccess.open(TEST_STORE, FileAccess.WRITE)
	stale_file.store_string(JSON.stringify(stale))
	stale_file.close()
	var invalidated = store_script.new(TEST_STORE)
	invalidated.load_from_disk()
	assert_bool(invalidated.evaluation_sharing).is_false()
	assert_bool(invalidated.prompt_seen).is_false()


func test_preview_equals_local_export_bytes() -> void:
	if not _require(MENU_SCENE):
		return
	var menu = load(MENU_SCENE).instantiate()
	add_child(menu)
	menu.set_store_path_for_tests(TEST_STORE)
	var preview: PackedByteArray = menu.example_bytes()
	assert_str(menu.save_example_locally(TEST_EXPORT)).is_equal(TEST_EXPORT)
	assert_array(FileAccess.get_file_as_bytes(TEST_EXPORT)).is_equal(preview)
	assert_bool(menu.maybe_prompt_after_completed_game()).is_true()
	assert_bool(menu.maybe_prompt_after_completed_game()).is_false()
	var data := _load_json(TEST_STORE)
	assert_bool(data["prompt_seen"]).is_true()
	assert_bool(data["evaluation_sharing"]).is_false()
	assert_bool(data["training_use"]).is_false()
	menu.queue_free()


func test_menu_open_and_save_create_no_transport_nodes() -> void:
	if not _require(MENU_SCENE):
		return
	var menu = load(MENU_SCENE).instantiate()
	add_child(menu)
	menu.set_store_path_for_tests(TEST_STORE)
	menu.open_settings()
	menu.save_example_locally(TEST_EXPORT)
	var forbidden_classes := ["HTTPRequest", "HTTPClient", "StreamPeer", "WebSocketPeer", "ENetMultiplayerPeer"]
	assert_array(_find_classes(menu, forbidden_classes)).is_empty()
	menu.queue_free()


func _find_classes(node: Node, class_names: Array) -> Array:
	var found: Array = []
	if class_names.has(node.get_class()):
		found.append(node.get_class())
	for child in node.get_children():
		found.append_array(_find_classes(child, class_names))
	return found


func test_privacy_scripts_contain_no_transport_apis() -> void:
	if not _require(BUILDER_PATH) or not _require(STORE_PATH):
		return
	var forbidden := ["HTTP" + "Request", "HTTP" + "Client", "Stream" + "Peer", "Web" + "Socket", "ENet", "Network" + "Manager"]
	for path in [BUILDER_PATH, STORE_PATH, "res://scripts/privacy/privacy_menu.gd", CARD_PATH, COLLECTOR_PATH]:
		if not _require(path):
			continue
		var source := FileAccess.get_file_as_string(path)
		for token: String in forbidden:
			assert_str(source).not_contains(token)


func test_required_english_and_german_wording() -> void:
	if not _require("res://scripts/privacy/privacy_menu.gd"):
		return
	var menu_script = load("res://scripts/privacy/privacy_menu.gd")
	assert_str(menu_script.text_for("en", "review_exact")).is_equal(
		"Review the exact fields and an example of exactly what we would send")
	assert_str(menu_script.text_for("de", "review_exact")).is_equal(
		"Prüfe vor deiner Entscheidung alle Felder und ein Beispiel dessen, was genau gesendet würde")
	assert_str(menu_script.text_for("en", "settings_section")).is_equal("PRIVACY & DATA:")
	assert_str(menu_script.text_for("de", "settings_section")).is_equal("DATENSCHUTZ & DATEN:")
	assert_str(menu_script.text_for("en", "deletion_code")).is_equal("Deletion code")
	assert_str(menu_script.text_for("de", "deletion_code")).is_equal("Löschcode")
	assert_str(FileAccess.get_file_as_string("res://scripts/privacy/privacy_menu.gd")).not_contains("Share this game")


func test_example_is_shipped_and_preview_is_nonempty() -> void:
	var shipped_path := "res://assets/privacy/example_record.json"
	assert_bool(FileAccess.file_exists(shipped_path)).is_true()
	var presets := ConfigFile.new()
	assert_int(presets.load("res://export_presets.cfg")).is_equal(OK)
	var checked := 0
	for section in presets.get_sections():
		if not presets.has_section_key(section, "export_filter"):
			continue
		checked += 1
		var included := false
		for pattern in str(presets.get_value(section, "include_filter")).split(","):
			included = included or shipped_path.trim_prefix("res://").match(pattern.strip_edges())
		assert_bool(included).override_failure_message("Example missing from %s include_filter" % section).is_true()
		for pattern in str(presets.get_value(section, "exclude_filter")).split(","):
			assert_bool(shipped_path.trim_prefix("res://").match(pattern.strip_edges())).is_false()
	assert_int(checked).is_equal(3)
	var menu = load(MENU_SCENE).instantiate()
	add_child(menu)
	menu.set_store_path_for_tests(TEST_STORE)
	assert_str(menu.FIXTURE_PATH).is_equal(shipped_path)
	menu._show_details()
	var preview := menu.find_child("ExamplePreview", true, false) as TextEdit
	assert_str(preview.text).is_not_empty()
	assert_str(preview.text).is_equal(menu.example_bytes().get_string_from_utf8())
	assert_str(menu.save_example_locally(TEST_EXPORT)).is_equal(TEST_EXPORT)
	assert_array(FileAccess.get_file_as_bytes(TEST_EXPORT)).is_equal(preview.text.to_utf8_buffer())
	menu.queue_free()


func test_german_maintainer_placeholders_are_localized() -> void:
	var menu_script = load("res://scripts/privacy/privacy_menu.gd")
	for key in ["destination", "controller", "processor", "recipients", "retention", "withdrawal", "contact"]:
		assert_str(menu_script.text_for("de", key)).contains("wird vom Betreiber veröffentlicht")
		assert_str(menu_script.text_for("de", key)).not_contains("to be published by the maintainer")
		assert_str(menu_script.text_for("en", key)).contains("to be published by the maintainer")


func test_press_review_details_keeps_button_alive_for_feedback() -> void:
	var menu = load(MENU_SCENE).instantiate()
	add_child(menu)
	menu.set_store_path_for_tests(TEST_STORE)
	menu.open_settings()
	await get_tree().process_frame
	var review: Button
	for node in menu.find_children("*", "Button", true, false):
		if node.text == menu.localized_text("review"):
			review = node
	assert_bool(is_instance_valid(review)).is_true()
	assert_bool(has_node("/root/UiFeedback")).is_true()
	assert_bool(review.has_meta("_ui_feedback_wired")).is_true()
	# Emit the real signal: the menu handler and the autoload feedback must both run.
	review.pressed.emit()
	assert_bool(is_instance_valid(review)).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(is_instance_valid(review)).is_false()
	assert_bool(menu.find_child("ExamplePreview", true, false) is TextEdit).is_true()
	assert_bool(_load_json(TEST_STORE).get("prompt_seen", false)).is_true()
	menu.queue_free()


func _missing_methods(object: Object, methods: Array) -> Array:
	var missing: Array = []
	for method: String in methods:
		if not object.has_method(method):
			missing.append(method)
	return missing


## PR B2: the real last game's preview must be built by the SAME allowlist path as the example and
## export exactly the bytes it shows. The in-place reset() of the collector (main.gd hands the
## record over and resets right after) must not empty the menu's copy.
func test_last_game_preview_equals_local_export_bytes() -> void:
	if not _require(MENU_SCENE):
		return
	var menu = load(MENU_SCENE).instantiate()
	add_child(menu)
	menu.set_store_path_for_tests(TEST_STORE)
	var missing := _missing_methods(menu, ["set_last_game_record", "has_last_game_record", "last_game_bytes", "save_last_game_locally"])
	assert_array(missing).override_failure_message("privacy_menu.gd is missing %s" % str(missing)).is_empty()
	if not missing.is_empty():
		menu.queue_free()
		return
	var record := _load_json(FIXTURE_PATH)
	menu.set_last_game_record(record)
	assert_bool(menu.has_last_game_record()).is_true()
	var preview: PackedByteArray = menu.last_game_bytes()
	assert_bool(preview.is_empty()).is_false()
	menu._show_details()
	var shown := menu.find_child("LastGamePreview", true, false) as TextEdit
	assert_that(shown).override_failure_message("details page is missing LastGamePreview").is_not_null()
	if shown != null:
		assert_str(shown.text).is_equal(preview.get_string_from_utf8())
	assert_str(menu.save_last_game_locally(TEST_LAST_EXPORT)).is_equal(TEST_LAST_EXPORT)
	assert_array(FileAccess.get_file_as_bytes(TEST_LAST_EXPORT)).is_equal(preview)
	(record["actions"] as Array).clear()
	assert_array(menu.last_game_bytes()).override_failure_message(
		"last game bytes followed the collector's in-place reset").is_equal(preview)
	menu.queue_free()


func test_last_game_wording_and_details_require_a_record() -> void:
	if not _require(MENU_SCENE):
		return
	var menu_script = load("res://scripts/privacy/privacy_menu.gd")
	assert_str(menu_script.text_for("en", "last_game")).is_equal("Your last game's data")
	assert_str(menu_script.text_for("de", "last_game")).is_equal("Daten deiner letzten Partie")
	assert_str(menu_script.text_for("en", "save_last")).is_equal("Save last game locally")
	assert_str(menu_script.text_for("de", "save_last")).is_equal("Letzte Partie lokal speichern")
	assert_str(menu_script.text_for("en", "saved_last")).is_equal("Saved your last game's exact bytes to %s")
	assert_str(menu_script.text_for("de", "saved_last")).is_equal("Die exakten Daten deiner letzten Partie wurden unter %s gespeichert")
	var menu = load(MENU_SCENE).instantiate()
	add_child(menu)
	menu.set_store_path_for_tests(TEST_STORE)
	menu._show_details()
	assert_that(menu.find_child("LastGamePreview", true, false)).override_failure_message(
		"without a record the details page must not show a last game").is_null()
	var example := menu.find_child("ExamplePreview", true, false) as TextEdit
	assert_that(example).is_not_null()
	if example != null:
		assert_str(example.text).is_equal(menu.example_bytes().get_string_from_utf8())
	if not menu.has_method("set_last_game_record"):
		menu.queue_free()
		return
	menu.set_last_game_record(_load_json(FIXTURE_PATH))
	menu._show_details()
	assert_that(menu.find_child("LastGamePreview", true, false)).override_failure_message(
		"with a record the details page must show LastGamePreview").is_not_null()
	var heading := false
	var expected: String = menu.localized_text("last_game")
	for label in menu.find_children("*", "Label", true, false):
		if (label as Label).text == expected:
			heading = true
	assert_bool(heading).override_failure_message("details page lacks the %s heading" % expected).is_true()
	menu.queue_free()


func test_after_game_card_wording() -> void:
	if not _require(CARD_PATH):
		return
	var card_script = load(CARD_PATH)
	assert_str(card_script.text_for("en", "card_title")).is_equal("Share this game?")
	assert_str(card_script.text_for("de", "card_title")).is_equal("Diese Partie teilen?")
	assert_str(card_script.text_for("en", "keep_private")).is_equal("Keep private")
	assert_str(card_script.text_for("de", "keep_private")).is_equal("Privat behalten")
	assert_str(card_script.text_for("en", "preview")).is_equal("Preview")
	assert_str(card_script.text_for("de", "preview")).is_equal("Vorschau")
	assert_str(card_script.text_for("en", "save_locally")).is_equal("Save locally")
	assert_str(card_script.text_for("de", "save_locally")).is_equal("Lokal speichern")


func test_after_game_card_waits_for_consent_and_a_record() -> void:
	if not _require(MENU_SCENE) or not _require(CARD_PATH):
		return
	var menu = load(MENU_SCENE).instantiate()
	add_child(menu)
	menu.set_store_path_for_tests(TEST_STORE)
	var missing := _missing_methods(menu, ["set_last_game_record", "has_last_game_record", "evaluation_sharing_enabled", "last_game_bytes"])
	assert_array(missing).override_failure_message("privacy_menu.gd is missing %s" % str(missing)).is_empty()
	if not missing.is_empty():
		menu.queue_free()
		return
	menu.set_last_game_record(_load_json(FIXTURE_PATH))
	assert_bool(menu.evaluation_sharing_enabled() and menu.has_last_game_record()).override_failure_message(
		"card must not be offered while evaluation sharing is off").is_false()
	var store = load(STORE_PATH).new(TEST_STORE)
	store.load_from_disk()
	store.set_consent(true, false)
	menu.set_store_path_for_tests(TEST_STORE)
	assert_bool(menu.evaluation_sharing_enabled() and menu.has_last_game_record()).override_failure_message(
		"card must be offered when sharing is on and a record exists").is_true()
	var card = load(CARD_PATH).new()
	add_child(card)
	assert_bool(card.has_method("open_for")).override_failure_message("after_game_card.gd is missing open_for()").is_true()
	if not card.has_method("open_for"):
		menu.queue_free()
		card.queue_free()
		return
	card.export_path = TEST_LAST_EXPORT
	card.open_for(menu)
	assert_bool(card.visible).is_true()
	var keep := card.find_child("KeepPrivateButton", true, false) as Button
	assert_that(keep).override_failure_message("card is missing KeepPrivateButton").is_not_null()
	if keep != null:
		assert_bool(keep.has_focus()).override_failure_message("Keep private must have focus when the card opens").is_true()
	for node in card.find_children("*", "Button", true, false):
		assert_str((node as Button).text).override_failure_message("the card must have no Share button (M12)").not_contains("Share")
	# Keep private and closing the window write nothing to the export directory.
	if keep != null:
		keep.pressed.emit()
	assert_bool(card.visible).is_false()
	assert_bool(FileAccess.file_exists(TEST_LAST_EXPORT)).override_failure_message(
		"dismissing the card must not write any file").is_false()
	card.open_for(menu)
	card.close_requested.emit()
	assert_bool(card.visible).is_false()
	assert_bool(FileAccess.file_exists(TEST_LAST_EXPORT)).is_false()
	# Save locally writes exactly the previewed bytes and names the path.
	card.open_for(menu)
	var save_button := card.find_child("SaveLocallyButton", true, false) as Button
	assert_that(save_button).is_not_null()
	if save_button != null:
		save_button.pressed.emit()
	assert_bool(FileAccess.file_exists(TEST_LAST_EXPORT)).is_true()
	assert_array(FileAccess.get_file_as_bytes(TEST_LAST_EXPORT)).is_equal(menu.last_game_bytes())
	var status := card.find_child("CardStatus", true, false) as Label
	assert_that(status).is_not_null()
	if status != null:
		assert_str(status.text).contains(TEST_LAST_EXPORT)
	# Preview hands over to the details page and gets out of the way.
	card.open_for(menu)
	var preview_button := card.find_child("PreviewButton", true, false) as Button
	if preview_button != null:
		preview_button.pressed.emit()
	assert_bool(card.visible).is_false()
	assert_bool(menu.visible).is_true()
	var forbidden_classes := ["HTTPRequest", "HTTPClient", "StreamPeer", "WebSocketPeer", "ENetMultiplayerPeer"]
	assert_array(_find_classes(card, forbidden_classes)).is_empty()
	assert_array(_find_classes(menu, forbidden_classes)).is_empty()
	menu.queue_free()
	card.queue_free()
