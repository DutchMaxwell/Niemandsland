extends GdUnitTestSuite

const SCRIPT := "res://scripts/whats_new_dialog.gd"
const STATE := "user://whats_new_dialog_test.cfg"
var _version: String

func before_test() -> void:
	_version = WhatsNewContent.version()
	DirAccess.remove_absolute(STATE)

func after_test() -> void:
	ProjectSettings.set_setting("application/config/version", _version)
	DirAccess.remove_absolute(STATE)

func test_automatic_open_once_and_manual_reopen_after_escape() -> void:
	assert_bool(FileAccess.file_exists(SCRIPT)).is_true()
	if not FileAccess.file_exists(SCRIPT):
		return
	var dialog = auto_free(load(SCRIPT).new())
	dialog.state_path = STATE
	add_child(dialog)
	assert_bool(dialog.open(true)).is_true()
	assert_bool(dialog.visible).is_true()
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	dialog._input(event)
	assert_bool(dialog.visible).is_false()
	assert_bool(dialog.open(true)).is_false()
	assert_bool(dialog.visible).is_false()
	assert_bool(dialog.open()).is_true()
	dialog.hide()
	var restarted = auto_free(load(SCRIPT).new())
	restarted.state_path = STATE
	add_child(restarted)
	assert_bool(restarted.open(true)).is_false()
	ProjectSettings.set_setting("application/config/version", _version + ".next")
	assert_bool(restarted.open(true)).is_true()
	assert_str(restarted.title).contains(_version + ".next")

func test_cards_use_house_style_and_can_switch_to_german() -> void:
	assert_bool(FileAccess.file_exists(SCRIPT)).is_true()
	if not FileAccess.file_exists(SCRIPT):
		return
	var dialog = auto_free(load(SCRIPT).new())
	dialog.state_path = STATE
	add_child(dialog)
	dialog.open()
	assert_object(dialog.theme).is_same(HouseStyle.theme())
	assert_int(dialog._cards.get_child_count()).is_equal(5)
	for card: PanelContainer in dialog._cards.get_children():
		assert_str(card.theme_type_variation).is_equal(HouseStyle.CARD)
		assert_int(card.get_child(0).get_child_count()).is_equal(3)
	dialog._locale = "en"
	dialog._language_button.pressed.emit()
	assert_str(dialog.title).is_equal("Neu in %s" % _version)
	dialog.open()
	assert_str(dialog.get_ok_button().text).is_equal("Schließen")
	dialog.open(false, true)
	assert_str(dialog.get_ok_button().text).is_equal("Zurück zum Spieltisch")
	assert_str(dialog._cards.get_child(0).get_child(0).get_child(0).text).is_equal("Zwei neue Armeen")

