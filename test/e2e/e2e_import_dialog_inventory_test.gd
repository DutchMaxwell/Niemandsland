extends GdUnitTestSuite
## E2E — the Import OPR Army window, row 20 of the UI inventory (uimenus step 8): the share-link field with
## its example, FROM CLIPBOARD, LOAD ARMY, the link status, ASSIGN PLAYER (pre-set to the caller's slot),
## "AI-controlled (Solo)", the PREVIEW well with its empty state, CANCEL, IMPORT ARMY (disabled until an army
## is loaded), Esc = cancel. No test here fetches from the Army Forge API: a loaded army is set directly.
## test_inventory_check_names_a_removed_control proves the presence check can fail.

const WORDS := ["FROM CLIPBOARD", "LOAD ARMY", "CANCEL", "IMPORT ARMY"]
const LABELS := ["ARMY IMPORT", "ENTER ARMY FORGE SHARE LINK / LIST ID", "e.g. https://army-forge.onepagerules.com/share?id=XXX",
	"ASSIGN PLAYER", "PREVIEW"]

var _dlg: OPRImportDialog
var _imported: Array = []


func before_test() -> void:
	_imported = []
	_dlg = OPRImportDialog.new()
	add_child(_dlg)
	_dlg.army_imported.connect(func(army: OPRApiClient.OPRArmy, player: int, ai: bool) -> void:
		_imported.append([army, player, ai]))
	await get_tree().process_frame


func after_test() -> void:
	_dlg.queue_free()


func _button(text: String) -> Button:
	for n: Node in _dlg.find_children("*", "Button", true, false):
		if (n as Button).text == text and not n is CheckBox and not n.is_queued_for_deletion():
			return n as Button
	return null


func _label(text: String) -> Label:
	for n: Node in _dlg.find_children("*", "Label", true, false):
		if (n as Label).text == text or (text == "ARMY IMPORT" and (n as Label).text.to_upper() == "ARMY IMPORT"):
			return n as Label
	return null


func _missing() -> Array:
	var missing: Array = []
	for t: String in WORDS:
		if _button(t) == null:
			missing.append("button: %s" % t)
	for t: String in LABELS:
		if _label(t) == null:
			missing.append("label: %s" % t)
	if _dlg.share_link_input == null or _dlg.share_link_input.placeholder_text != "Paste a share link or list ID here...":
		missing.append("field: share link")
	if _dlg.ai_check == null or _dlg.ai_check.text != "AI-controlled (Solo)":
		missing.append("checkbox: AI-controlled (Solo)")
	return missing


func _load_fake_army() -> OPRApiClient.OPRArmy:
	var army := OPRApiClient.OPRArmy.new()
	army.name = "Test Army"
	_dlg._preview_army = army
	_dlg.import_btn.disabled = false
	return army


func test_every_control_of_row_20_is_in_the_window() -> void:
	assert_array(_missing()).override_failure_message("import window controls missing: %s" % str(_missing())).is_empty()
	assert_bool(_dlg.import_btn.disabled).override_failure_message("IMPORT ARMY must wait for a loaded army").is_true()
	assert_int(_dlg.player_option.item_count).is_equal(4)
	assert_int(_dlg.player_option.get_selected_id()).is_equal(1)
	assert_bool(_dlg.ai_check.button_pressed).is_false()
	assert_str(_dlg.ai_check.tooltip_text).is_not_empty()
	assert_bool(_dlg.state_panel.visible).is_true()
	assert_bool(_dlg.army_preview.visible).is_false()


func test_set_player_preselects_the_callers_slot() -> void:
	_dlg.set_player(3)
	assert_int(_dlg.player_option.get_selected_id()).is_equal(3)


func test_load_army_without_a_link_says_so_and_touches_nothing() -> void:
	_button("LOAD ARMY").pressed.emit()
	assert_str(_dlg.link_status_label.text).is_equal("No link entered")
	assert_bool(_dlg.import_btn.disabled).is_true()


func test_import_army_emits_the_army_slot_and_ai_flag_then_hides_and_resets() -> void:
	_dlg.show()
	var army := _load_fake_army()
	_dlg.set_player(2)
	_dlg.ai_check.button_pressed = true
	_dlg.share_link_input.text = "https://example.invalid/x"
	_button("IMPORT ARMY").pressed.emit()
	assert_int(_imported.size()).override_failure_message("IMPORT ARMY did not emit army_imported").is_equal(1)
	if _imported.is_empty():
		return
	assert_object(_imported[0][0]).is_same(army)
	assert_int(_imported[0][1]).is_equal(2)
	assert_bool(_imported[0][2]).is_true()
	assert_bool(_dlg.visible).is_false()
	assert_str(_dlg.share_link_input.text).is_empty()
	assert_bool(_dlg.import_btn.disabled).is_true()
	assert_bool(_dlg.ai_check.button_pressed).is_false()


func test_cancel_and_escape_hide_and_reset_without_importing() -> void:
	_dlg.show()
	_dlg.share_link_input.text = "abc"
	_button("CANCEL").pressed.emit()
	assert_bool(_dlg.visible).is_false()
	assert_str(_dlg.share_link_input.text).is_empty()
	_dlg.show()
	_dlg.share_link_input.text = "abc"
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	_dlg._unhandled_key_input(esc)
	assert_bool(_dlg.visible).is_false()
	assert_str(_dlg.share_link_input.text).is_empty()
	assert_int(_imported.size()).is_equal(0)


func test_preview_shows_the_army_name_and_totals() -> void:
	var army := _load_fake_army()
	army.game_system = "gf"
	army.points = 1000
	_dlg._show_loaded()
	_dlg._update_preview()
	assert_str(_dlg.army_preview.text).contains("Test Army")
	assert_str(_dlg.army_preview.text).contains("[b]Points:[/b] 1000")


func test_the_x_cancels_and_the_sheet_is_house_style_and_owns_its_clicks() -> void:
	var root := _dlg.get_child(0) as Control
	assert_int(root.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_object(root.theme).is_same(HouseStyle.theme())
	assert_str(String(_button("IMPORT ARMY").theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
	assert_str(String(_button("LOAD ARMY").theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
	assert_str(String(_button("CANCEL").theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	_dlg.show()
	_dlg.share_link_input.text = "abc"
	(_dlg.find_child("CloseButton", true, false) as Button).pressed.emit()
	assert_bool(_dlg.visible).is_false()
	assert_str(_dlg.share_link_input.text).is_empty()


func test_inventory_check_names_a_removed_control() -> void:
	assert_array(_missing()).is_empty()
	var cancel := _button("CANCEL")
	var parent := cancel.get_parent()
	parent.remove_child(cancel)
	var missing := _missing()
	parent.add_child(cancel)
	assert_array(missing).contains_exactly(["button: CANCEL"])
