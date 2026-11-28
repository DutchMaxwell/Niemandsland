extends GdUnitTestSuite
## An army never silently replaces the army a seat already holds (maintainer 27.11.2026): the army import and
## "Bring NACHTMAHR" ask "Player N already has an army (<faction>, <pts>). Replace it?" - Replace / Keep.
## Red before: there is no question, the import replaces at once.

var _dlg: OPRImportDialog
var _manager: OPRArmyManager
var _imported: Array = []


## main.gd with the toast stubbed and a recorder list source (no CDN, no file).
class Probe extends "res://scripts/main.gd":
	var toasts: Array = []

	func _solo_show_toast(text: String, _auto_hide_s: float = 0.0, _explain: bool = false) -> void:
		toasts.append(text)


class Lists extends AiLists:
	var asked: Array = []

	func list_text(file: String) -> String:
		asked.append(file)
		return ""


func before_test() -> void:
	_imported = []
	_manager = auto_free(OPRArmyManager.new())
	_manager.armies[2] = _army("Battle Brothers", 2000)
	_dlg = OPRImportDialog.new()
	_dlg.army_manager = _manager
	add_child(_dlg)
	_dlg.army_imported.connect(func(army: OPRApiClient.OPRArmy, player: int, _ai: bool) -> void:
		_imported.append([army, player]))
	await get_tree().process_frame


func after_test() -> void:
	_dlg.queue_free()
	for card: Node in get_tree().root.get_children():
		if card is PromptCard:
			card.queue_free()


func _army(faction: String, points: int) -> OPRApiClient.OPRArmy:
	var army := OPRApiClient.OPRArmy.new()
	army.name = "My list"
	army.faction_name = faction
	army.points = points
	return army


func _card() -> PromptCard:
	for _i in 5:
		for node: Node in get_tree().root.get_children():
			if node is PromptCard and not node.is_queued_for_deletion():
				return node
		await get_tree().process_frame
	return null


func test_the_question_names_the_seat_the_faction_and_the_points() -> void:
	assert_str(ArmyReplaceConfirm.text(2, _manager.armies[2])).is_equal(
		"Player 2 already has an army (Battle Brothers, 2000 pts). Replace it?")


func test_an_import_into_an_empty_seat_asks_nothing() -> void:
	_dlg._preview_army = _army("Orc Marauders", 1500)
	_dlg.set_player(1)
	_dlg.import_btn.pressed.emit()
	assert_int(_imported.size()).is_equal(1)
	assert_object(await _card()).is_null()


func test_keep_leaves_the_seat_and_the_window_as_they_are() -> void:
	_dlg.show()
	_dlg._preview_army = _army("Orc Marauders", 1500)
	_dlg.set_player(2)
	_dlg.import_btn.pressed.emit()
	var card := await _card()
	assert_object(card).override_failure_message("no question before replacing Player 2's army").is_not_null()
	if card == null:
		return
	assert_str(card.cancel_button.text).is_equal("Keep")
	card.cancel_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_imported.size()).is_equal(0)
	assert_bool(_dlg.visible).is_true()


func test_replace_imports_into_the_held_seat() -> void:
	_dlg._preview_army = _army("Orc Marauders", 1500)
	_dlg.set_player(2)
	_dlg.import_btn.pressed.emit()
	var card := await _card()
	assert_object(card).is_not_null()
	if card == null:
		return
	assert_str(card.ok_button.text).is_equal("Replace")
	card.ok_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_imported.size()).is_equal(1)
	assert_int(int(_imported[0][1])).is_equal(2)


func test_bring_nachtmahr_into_a_held_seat_asks_and_keep_fetches_nothing() -> void:
	var probe: Node = auto_free(Probe.new())
	var lists: Lists = auto_free(Lists.new())
	probe.set("_ai_lists", lists)
	probe.set("opr_army_manager", _manager)
	var done := [false]
	var run := func() -> void:
		await probe.call("_load_ai_opponent_list", "orc_marauders_1500.json", 2)
		done[0] = true
	run.call()
	var card := await _card()
	assert_object(card).override_failure_message("no question before NACHTMAHR replaces Player 2's army").is_not_null()
	if card == null:
		return
	card.cancel_button.pressed.emit()
	for _i in 5:
		await get_tree().process_frame
	assert_bool(done[0]).is_true()
	assert_array(lists.asked).is_empty()
