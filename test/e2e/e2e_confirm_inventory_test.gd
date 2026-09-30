extends GdUnitTestSuite
## E2E — the confirm questions, row 22 of the UI inventory (uimenus step 10): Clear Table, Sort Table, Next Round
## (names the round it moves ONTO and warns that the final solo round ends the game) and End Battle. Each asks
## first with its title, its words and a named OK; OK runs today's action, cancel runs nothing. Real main.tscn.
## test_inventory_check_names_a_missing_line proves the presence check can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


# === how today's question is read and answered (the one place that knows the window kind) =========

## The open question for `kind` ("action" = Clear / Sort / Next Round, "end" = End Battle), or {}.
func _asked(kind: String) -> Dictionary:
	var d: ConfirmationDialog = _main._action_confirm_dialog if kind == "action" else _main.end_battle_confirm_dialog
	if d == null or not d.visible:
		return {}
	return {"title": d.title, "text": d.dialog_text, "ok": d.ok_button_text,
		"press_ok": func() -> void:
			d.confirmed.emit()
			d.hide(),
		"press_cancel": func() -> void:
			d.canceled.emit()
			d.hide()}


## Whether confirming End Battle goes back to the main menu (pressing it would leave the scene).
func _end_battle_is_wired() -> bool:
	return _main.end_battle_confirm_dialog.confirmed.is_connected(Callable(_main, &"_on_end_battle_confirmed"))


func _missing(q: Dictionary, title: String, words: String, ok: String) -> Array:
	var missing: Array = []
	if q.is_empty():
		return ["question"]
	if q["title"] != title:
		missing.append("title: %s" % title)
	if not str(q["text"]).contains(words):
		missing.append("line: %s" % words)
	if q["ok"] != ok:
		missing.append("button: %s" % ok)
	return missing


# === tests ======================================================================================

func test_clear_table_asks_first_and_clears_only_on_ok() -> void:
	var unit := E2EBoot.make_unit(_main.object_manager, 1, "Victim", [Vector3.ZERO])
	var node: Node = (unit.models[0] as ModelInstance).node
	_main._on_clear_all()
	await _runner.simulate_frames(2)
	var q := _asked("action")
	assert_array(_missing(q, "Clear Table", "Remove ALL objects from the table?", "Clear Table")).is_empty()
	assert_bool(str(q["text"]).contains("cannot be undone")).is_true()
	q["press_cancel"].call()
	await _runner.simulate_frames(2)
	assert_bool(is_instance_valid(node) and not node.is_queued_for_deletion()).override_failure_message("cancel cleared the table").is_true()
	_main._on_clear_all()
	await _runner.simulate_frames(2)
	_asked("action")["press_ok"].call()
	await _runner.simulate_frames(3)
	assert_bool(not is_instance_valid(node) or node.is_queued_for_deletion()).override_failure_message("OK did not clear the table").is_true()


func test_sort_table_asks_first_and_runs_the_sort_on_ok() -> void:
	_main._on_sort_table()
	await _runner.simulate_frames(2)
	var q := _asked("action")
	assert_array(_missing(q, "Sort Table", "Sort the whole table?", "Sort Table")).is_empty()
	assert_bool(str(q["text"]).contains("starting positions")).is_true()
	assert_bool(_main._pending_confirm_action == Callable(_main, &"_do_sort_table")).override_failure_message("OK does not run the sort").is_true()
	q["press_cancel"].call()


func test_next_round_names_the_round_it_moves_onto_and_advances_on_ok() -> void:
	var before: int = _main.opr_army_manager.current_round
	var label: String = _main.next_round_button_label(before, false)
	_main._on_next_round()
	await _runner.simulate_frames(2)
	var q := _asked("action")
	assert_array(_missing(q, label, _main.next_round_confirm_body(before, false), label)).is_empty()
	q["press_cancel"].call()
	await _runner.simulate_frames(2)
	assert_int(_main.opr_army_manager.current_round).override_failure_message("cancel advanced the round").is_equal(before)
	_main._on_next_round()
	await _runner.simulate_frames(2)
	_asked("action")["press_ok"].call()
	await _runner.simulate_frames(4)
	assert_int(_main.opr_army_manager.current_round).is_equal(before + 1)


func test_final_solo_round_says_plainly_that_advancing_ends_the_game() -> void:
	var body: String = _main.next_round_confirm_body(4, true)
	assert_str(body).is_not_equal(_main.next_round_confirm_body(4, false))
	assert_bool(body.to_lower().contains("game")).is_true()


func test_end_battle_asks_first_and_goes_back_to_the_main_menu_on_ok() -> void:
	_main._on_end_battle_pressed()
	await _runner.simulate_frames(2)
	var q := _asked("end")
	assert_array(_missing(q, "End Battle", "Really quit to main menu?", "Yes, Exit")).is_empty()
	assert_bool(str(q["text"]).contains("All unsaved progress will be lost.")).is_true()
	assert_bool(_end_battle_is_wired()).override_failure_message("confirming End Battle no longer returns to the main menu").is_true()
	q["press_cancel"].call()


func test_inventory_check_names_a_missing_line() -> void:
	_main._on_sort_table()
	await _runner.simulate_frames(2)
	var q := _asked("action")
	assert_array(_missing(q, "Sort Table", "Sort the whole table?", "Sort Table")).is_empty()
	assert_array(_missing(q, "Sort Table", "Sort the whole table?", "Do it")).contains_exactly(["button: Do it"])
	q["press_cancel"].call()
