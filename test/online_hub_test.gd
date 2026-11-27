extends GdUnitTestSuite
## The online hub of the main menu (step 47.1): one page with the player's name and "Create a room". Red before the step: there is no res://scripts/online_hub.gd.

const SCRIPT := "res://scripts/online_hub.gd"


func _hub() -> Control:
	assert_bool(ResourceLoader.exists(SCRIPT)).override_failure_message("no online hub").is_true()
	if not ResourceLoader.exists(SCRIPT):
		return null
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1920, 1080)
	add_child(host)
	var hub: Control = (load(SCRIPT) as GDScript).new()
	host.add_child(hub)
	hub.size = host.size
	await get_tree().process_frame
	return hub


func _settings_on_prepare(hub: Control) -> Dictionary:
	var got: Array = []
	hub.connect("host_requested", func(settings: Dictionary) -> void: got.append(settings))
	(hub.get("prepare_button") as Button).pressed.emit()
	return got[0] if not got.is_empty() else {}


func test_prepare_table_hands_over_the_name_the_relay_and_the_public_check() -> void:
	var hub := await _hub()
	if hub == null:
		return
	(hub.get("name_field") as LineEdit).text = "  Ashfall  "
	(hub.get("public_check") as CheckBox).button_pressed = true
	var settings := _settings_on_prepare(hub)
	assert_bool(bool(settings.get("niemandsland/pending_internet_lobby", false))).is_true()
	assert_bool(bool(settings.get("niemandsland/internet_is_host", false))).is_true()
	assert_str(str(settings.get("niemandsland/player_name", ""))).is_equal(PlayerIdentity.sanitize("  Ashfall  "))
	assert_str(str(settings.get("niemandsland/internet_relay_url", ""))).is_equal(InternetLobby.DEFAULT_RELAY_URL)
	assert_bool(bool(settings.get("niemandsland/internet_public", false))).is_true()


func test_enter_in_the_name_field_prepares_the_table() -> void:
	var hub := await _hub()
	if hub == null:
		return
	var got: Array = []
	hub.connect("host_requested", func(settings: Dictionary) -> void: got.append(settings))
	var name_field := hub.get("name_field") as LineEdit
	name_field.text_submitted.emit(name_field.text)
	assert_int(got.size()).is_equal(1)


## Step 47.1b: one folded relay line for every function of the page; an emptied field gives the default address.
func test_the_relay_field_stays_folded_until_its_line_is_pressed() -> void:
	var hub := await _hub()
	if hub == null:
		return
	var field := hub.get("relay_field") as LineEdit
	assert_object(field).override_failure_message("no relay field").is_not_null()
	if field == null:
		return
	assert_bool(field.is_visible_in_tree()).is_false()
	(hub.get("relay_line") as Button).pressed.emit()
	assert_bool(field.is_visible_in_tree()).is_true()
	field.text = "wss://example.invalid"
	assert_str(str(_settings_on_prepare(hub).get("niemandsland/internet_relay_url", ""))).is_equal(
		"wss://example.invalid")


func test_an_emptied_relay_field_gives_the_default_address() -> void:
	var hub := await _hub()
	if hub == null or hub.get("relay_field") == null:
		fail("no relay field")
		return
	(hub.get("relay_field") as LineEdit).text = "   "
	var settings := _settings_on_prepare(hub)
	assert_str(str(settings.get("niemandsland/internet_relay_url", ""))).is_equal(InternetLobby.DEFAULT_RELAY_URL)
