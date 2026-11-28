extends GdUnitTestSuite
## E2E — the Import OPR Army window, row 20 of the UI inventory (uimenus step 8): the share-link field with
## its example, FROM CLIPBOARD, LOAD ARMY, the link status, ASSIGN PLAYER (pre-set to the caller's slot),
## "AI-controlled (Solo)", the PREVIEW well with its empty state, CANCEL, IMPORT ARMY (disabled until an army
## is loaded), Esc = cancel. No test here fetches from the Army Forge API: a loaded army is set directly.
## test_inventory_check_names_a_removed_control proves the presence check can fail.

const WORDS := ["From clipboard", "Load army", "Cancel", "Import army"]
const LABELS := ["ARMY IMPORT", "Army Forge share link or list ID", "e.g. https://army-forge.onepagerules.com/share?id=XXX",
	"Assign player", "Preview"]

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
	_button("Load army").pressed.emit()
	assert_str(_dlg.link_status_label.text).is_equal("No link entered")
	assert_bool(_dlg.import_btn.disabled).is_true()


func test_import_army_emits_the_army_slot_and_ai_flag_then_hides_and_resets() -> void:
	_dlg.show()
	var army := _load_fake_army()
	_dlg.set_player(2)
	_dlg.ai_check.button_pressed = true
	_dlg.share_link_input.text = "https://example.invalid/x"
	_button("Import army").pressed.emit()
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
	_button("Cancel").pressed.emit()
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
	var texts: Array = _dlg.army_preview.find_children("*", "Label", true, false).map(func(l: Node) -> String: return (l as Label).text)
	assert_array(texts).contains(["Test Army", "Grimdark Future", "1000 PTS · 0 UNITS"])


func test_the_x_cancels_and_the_sheet_is_house_style_and_owns_its_clicks() -> void:
	var root := _dlg.get_child(0) as Control
	assert_int(root.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_object(root.theme).is_same(HouseStyle.menu_theme())   # sheet 04's scale (step 85)
	assert_str(String(_button("Import army").theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
	assert_str(String(_button("Load army").theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
	assert_str(String(_button("Cancel").theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	_dlg.show()
	_dlg.share_link_input.text = "abc"
	(_dlg.find_child("CloseButton", true, false) as Button).pressed.emit()
	assert_bool(_dlg.visible).is_false()
	assert_str(_dlg.share_link_input.text).is_empty()


func test_inventory_check_names_a_removed_control() -> void:
	assert_array(_missing()).is_empty()
	var cancel := _button("Cancel")
	var parent := cancel.get_parent()
	parent.remove_child(cancel)
	var missing := _missing()
	parent.add_child(cancel)
	assert_array(missing).contains_exactly(["button: Cancel"])


## The window loses the old layer's marks: no "///" line, sentence-case captions and buttons, the empty state in the body
## and caption styles instead of the wordmark font (sheet 04; red on main: "/// NODE-01", capitals, the wordmark font).
func test_the_window_has_no_old_layer_marks() -> void:
	for l: Node in _dlg.find_children("*", "Label", true, false):
		assert_bool((l as Label).text.begins_with("///")).override_failure_message("old mark: %s" % (l as Label).text).is_false()
	var headline: Label = _dlg.state_panel._headline
	assert_str(headline.text).is_equal("No army loaded")
	assert_str(String(headline.theme_type_variation)).is_equal(String(HouseStyle.BODY))
	assert_bool(headline.has_theme_font_override("font")).override_failure_message("the headline still wears the wordmark font").is_false()
	assert_str(String(_dlg.state_panel._detail.theme_type_variation)).is_equal(String(HouseStyle.CAPTION))


func _visible_segments() -> Array:
	var row := _dlg.find_child("PlayerSegments", true, false)
	return [] if row == null else row.get_children().filter(func(b: Node) -> bool: return (b as Button).visible)


## Step 86, maintainer 27.11.: Assign player is a segment pair "Player 1 (Blue) | Player 2 (Red)" driving the same
## value; the hidden dropdown stays in sync (red on main: a four-item dropdown).
func test_assign_player_is_a_pair_of_segments() -> void:
	var segments := _visible_segments()
	assert_array(segments.map(func(b: Button) -> String: return b.text)).is_equal(["Player 1 (Blue)", "Player 2 (Red)"])
	assert_bool(_dlg.player_option.visible).is_false()
	if segments.size() < 2:
		return
	(segments[1] as Button).pressed.emit()
	assert_int(_dlg.player_option.get_selected_id()).is_equal(2)
	assert_bool(HouseStyle.is_selected(segments[1])).is_true()
	assert_bool(HouseStyle.is_selected(segments[0])).is_false()


## A room hands a third or fourth guest seat 3 or 4: the window still pre-selects that seat and imports for it.
func test_a_third_seat_keeps_its_own_segment() -> void:
	_dlg.set_player(3)
	var texts: Array = _visible_segments().map(func(b: Button) -> String: return b.text)
	assert_array(texts).is_equal(["Player 1 (Blue)", "Player 2 (Red)", "Player 3 (Green)"])
	_load_fake_army()
	_dlg.import_btn.pressed.emit()
	assert_int(int(_imported[0][1])).is_equal(3)


## Step 50 (sheet 04): the preview is a header and one row per unit - the name with quality, defense and weapons under
## it, the model count and the points in mono gold (red before: one rich-text block of bullet lines).
func test_the_preview_is_one_row_per_unit() -> void:
	var army := _load_fake_army()
	army.game_system = "gf"
	army.points = 590
	for spec: Array in [["Command Squad", 5, 310, 4, 4], ["Line Infantry", 10, 280, 5, 5]]:
		var unit := OPRApiClient.OPRUnit.new()
		unit.name = spec[0]
		unit.size = spec[1]
		unit.cost = spec[2]
		unit.quality = spec[3]
		unit.defense = spec[4]
		army.units.append(unit)
	_dlg._show_loaded()
	_dlg._update_preview()
	var texts: Array = _dlg.army_preview.find_children("*", "Label", true, false).map(func(l: Node) -> String: return (l as Label).text)
	assert_array(texts).contains(["Command Squad", "× 5", "310", "Line Infantry", "× 10", "280", "Q4+ D4+", "590 PTS · 2 UNITS"])
	var cost: Label = _dlg.army_preview.find_children("*", "Label", true, false).filter(
		func(l: Node) -> bool: return (l as Label).text == "310")[0]
	assert_object(cost.get_theme_font("font")).is_same(HouseStyle.mono())


## Step 85 (sheet 04): in a wide window the import is one 1320 px sheet titled "Bring your army." with the inputs left
## and the preview right, Cancel and Import army under the preview; a narrow window stacks them as before (red before:
## one 620 px column).
func test_a_wide_window_shows_two_columns() -> void:
	_dlg._fit_to(Vector2(1920, 1080))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_object(_label("Bring your army.")).override_failure_message("no title").is_not_null()
	var sheet := _dlg.find_child("Sheet", true, false) as Control
	assert_float(sheet.size.x).is_greater_equal(1300.0)
	var link := _dlg.share_link_input.get_global_rect()
	var preview: Rect2 = (_dlg.army_preview.get_parent() as Control).get_global_rect()
	assert_float(preview.position.x).override_failure_message("the preview is not right of the link").is_greater(link.end.x)
	assert_float(_button("Import army").get_global_rect().position.x).is_greater(link.end.x)
	_dlg._fit_to(Vector2(1024, 768))
	for _i in 2:
		await get_tree().process_frame
	assert_float(_dlg.army_preview.get_parent().get_global_rect().position.y).is_greater(_dlg.share_link_input.get_global_rect().end.y)
