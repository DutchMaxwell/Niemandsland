extends GdUnitTestSuite
## Spec 97 (step 97.14b): the table's "Opponent…" opens the setup's step-04 page in table mode. Bring NACHTMAHR puts
## its list into the chosen seat through the table's own loader; Two players opens the import on Player 2; Esc closes
## and changes nothing. The list index and the list come from a stub AiLists (no network); the shared rules are
## seeded, so the parse never asks the API. Red before: the game menu had no "Opponent…".

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const FIXTURE := "res://test/fixtures/setup_opponent/probe_list.json"
const MANIFEST := {"probe": {"name": "Probe", "lists": [{"points": 100, "file": "probe_list.json"}]}}


class Lists extends AiLists:
	func manifest() -> Dictionary:
		return MANIFEST

	func list_text(_file: String) -> String:
		return FileAccess.get_file_as_string(FIXTURE)


var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.api_client._common_rules_cache[2] = {"rules": [], "traits": []}   # 2 = gf: no API call
	var stub := Lists.new()
	_main.add_child(stub)
	_main._ai_lists = stub


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _open() -> Node:
	var button := _main.find_child("OpponentBtn", true, false) as Button
	assert_object(button).override_failure_message("no Opponent… in the game menu").is_not_null()
	if button == null:
		return null
	assert_str(button.text).is_equal("Opponent…")
	button.pressed.emit()
	await _runner.simulate_frames(4)
	return _main.find_child("TableOpponentLayer", false, false)


func test_bring_nachtmahr_puts_its_list_into_the_chosen_seat() -> void:
	var layer := await _open()
	if layer == null:
		return
	var page: SetupOpponentStep = layer.get("page")
	assert_bool(page.table_mode).is_true()
	(page.find_child("CreateTable", true, false) as Button).pressed.emit()
	for _i in 90:
		if _main.opr_army_manager.armies.has(2):
			break
		await _runner.simulate_frames(10, 100)
	assert_bool(_main.opr_army_manager.armies.has(2)).override_failure_message("no army in seat 2").is_true()
	assert_bool(_main.solo_ai_slots.has(2)).is_true()
	assert_object(_main.find_child("TableOpponentLayer", false, false)).is_null()


func test_two_players_open_the_import_on_player_2() -> void:
	var layer := await _open()
	if layer == null:
		return
	var page: SetupOpponentStep = layer.get("page")
	(page.find_child("Who_local", true, false) as Button).pressed.emit()
	(page.find_child("CreateTable", true, false) as Button).pressed.emit()
	await _runner.simulate_frames(2)
	assert_bool(_main.opr_import_dialog.visible).is_true()
	assert_int(_main.opr_import_dialog.player_option.get_selected_id()).is_equal(2)
	assert_bool(_main.solo_ai_slots.is_empty()).is_true()


func test_esc_closes_and_changes_nothing() -> void:
	var layer := await _open()
	if layer == null:
		return
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	layer._unhandled_key_input(esc)
	await _runner.simulate_frames(2)
	assert_object(_main.find_child("TableOpponentLayer", false, false)).is_null()
	assert_bool(_main.opr_army_manager.armies.is_empty()).is_true()
