extends GdUnitTestSuite

const BUILDER_PATH := "res://scripts/privacy/shared_record_builder.gd"
const STORE_PATH := "res://scripts/privacy/consent_store.gd"
const MENU_SCENE := "res://scenes/privacy/privacy_menu.tscn"
const FIXTURE_PATH := "res://test/fixtures/privacy/example_record.json"
const GOLDEN_PATH := "res://test/fixtures/privacy/example_record.canonical.json"
const TEST_STORE := "user://test_privacy_m10/privacy.json"
const TEST_EXPORT := "user://test_shared_records/example.json"


func before_test() -> void:
	_remove_file(TEST_STORE)
	_remove_file(TEST_EXPORT)


func after_test() -> void:
	_remove_file(TEST_STORE)
	_remove_file(TEST_EXPORT)


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
	for path in [BUILDER_PATH, STORE_PATH, "res://scripts/privacy/privacy_menu.gd"]:
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
