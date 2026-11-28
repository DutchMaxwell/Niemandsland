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
	assert_object(dialog.theme).is_same(HouseStyle.menu_theme())
	assert_int(dialog._cards.get_child_count()).is_equal(5)
	for card: PanelContainer in dialog._cards.get_children():
		assert_str(card.theme_type_variation).is_equal(HouseStyle.CARD)
		# Title and body only: the 0.3.15 cards carry no picture.
		assert_int(card.get_child(0).get_child_count()).is_equal(2)
	dialog._locale = "en"
	dialog._language_button.pressed.emit()
	assert_str(dialog.title).is_equal("Neu in %s" % _version)
	dialog.open()
	assert_str(dialog.get_ok_button().text).is_equal("Schließen")
	dialog.open(false, true)
	assert_str(dialog.get_ok_button().text).is_equal("Zurück zum Spieltisch")
	assert_str(dialog._cards.get_child(0).get_child(0).get_child(0).text).is_equal("Regeln 3.6 auf deinem Tisch")



## Release notes as drawn (sheet 08): an English | Deutsch segment pair in the header row, a full-width Close with its Esc
## cap, a card with a picture is a row (150 x 84), a card without one is the text alone and no placeholder is drawn
## (red on main: one switch button, a 760 x 650 window, a placeholder slot).
func test_release_notes_have_the_language_pair_a_full_width_close_and_no_placeholder() -> void:
	var dialog = auto_free(load(SCRIPT).new())
	dialog.state_path = STATE
	add_child(dialog)
	dialog._locale = "en"
	dialog.open()
	await get_tree().process_frame
	assert_that(dialog.DIALOG_SIZE).is_equal(Vector2i(708, 884))
	var close: Node = dialog.find_child("CloseButton", true, false)
	var pair: Node = close.get_parent().get_child(close.get_index() - 1)
	var names: Array = pair.get_children().map(func(b: Node) -> String: return (b as Button).text)
	assert_array(names).is_equal(["English", "Deutsch"])
	assert_bool(HouseStyle.is_selected(pair.get_child(0) as Button)).is_true()
	dialog._language_button.pressed.emit()
	assert_bool(HouseStyle.is_selected(pair.get_child(1) as Button)).is_true()
	assert_bool(HouseStyle.is_selected(pair.get_child(0) as Button)).is_false()
	var closer: Button = dialog._close_button
	assert_str(closer.text).is_equal("Schließen")
	assert_float(closer.size.y).is_equal(float(HouseStyle.MENU_H_ACTION))
	assert_float(closer.size.x).is_greater(500.0)
	assert_str((closer.get_child(0) as Label).text).is_equal("Esc")
	assert_bool(dialog.get_ok_button().visible).is_false()
	for l: Node in dialog.find_children("*", "Label", true, false):
		assert_bool((l as Label).text in ["Image coming soon", "Bild folgt"]).is_false()
	assert_object(dialog._picture("")).is_null()
	assert_object(dialog._picture("res://nowhere.png")).is_null()
	var picture: TextureRect = dialog._picture(TableSizeDialog.preview_path("urban_ruins"))
	assert_object(picture).is_not_null()
	if picture != null:
		assert_that(picture.custom_minimum_size).is_equal(Vector2(150, 84))
		picture.free()


## Gap review 28.11. (sheet 08): the release notes sheet takes the height its cards need instead of leaving the lower
## half of an 884 px sheet empty (red before: the list ended far above the Close row).
func test_the_release_notes_sheet_fits_its_cards() -> void:
	get_tree().root.size = Vector2i(1920, 1080)
	var dialog = auto_free(load(SCRIPT).new())
	dialog.state_path = STATE
	add_child(dialog)
	dialog._locale = "en"
	dialog.open()
	await get_tree().process_frame
	dialog.size = dialog.DIALOG_SIZE   # the menu's size: a headless run wraps the window to its controls
	if dialog.has_method("_fit_to_cards"):
		dialog.call("_fit_to_cards")
	for _i in 3:
		await get_tree().process_frame
	var scroll := dialog._cards.get_parent() as Control
	var spare: float = scroll.size.y - dialog._cards.size.y
	assert_float(spare).override_failure_message("%d px empty under the cards of a %d px sheet" % [int(spare), dialog.size.y]
		).is_less_equal(2.0)
	assert_int(dialog.size.y).is_less_equal(884)
