extends GdUnitTestSuite
## E2E — the AI Opponent dialog, row 21 of the UI inventory (uimenus step 10): "NACHTMAHR builds its own
## list.", Faction (sorted by key, shown by name), Points (per faction, the largest bracket preselected,
## refreshed when the faction changes), "AI plays as" (Player 2 first, Player 1), "Build & deploy list" / Cancel (and the x).
## OK hands the picked list file and slot to the loader; cancel hands nothing. The manifest is a fake and the
## loader a recorder: no CDN, no import. Not driven here: a slot a connected human holds is disabled
## ("— human player") — it needs a live multiplayer peer (covered by the MP suites). The no-lists toast is
## main.gd's and unchanged. test_inventory_check_names_a_missing_line proves the check can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const MANIFEST := {
	"zeta_clan": {"name": "Zeta Clan", "lists": [{"points": 500, "file": "zeta_500.json"}, {"points": 1000, "file": "zeta_1000.json"}]},
	"alpha_guard": {"name": "Alpha Guard", "lists": [{"points": 750, "file": "alpha_750.json"}, {"points": 1500, "file": "alpha_1500.json"}, {"points": 2000, "file": "alpha_2000.json"}]},
}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _loaded: Array = []


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_loaded.clear()
	_main._show_ai_opponent_dialog(MANIFEST, func(file: String, slot: int) -> void: _loaded.append([file, slot]))
	await _runner.simulate_frames(2)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


## The open dialog, read in one place: {faction, points, slot, labels, ok, press_ok, press_cancel} or {}.
func _ask() -> Dictionary:
	for c in _main.get_children():
		if c is CanvasLayer and c.name == "AiOpponentLayer" and not c.is_queued_for_deletion():
			var opts := c.find_children("*", "OptionButton", true, false)
			var labels: Array[String] = []
			for l: Node in c.find_children("*", "Label", true, false):
				labels.append((l as Label).text)
			var ok := c.find_child("OkButton", true, false) as Button
			var cancel := c.find_child("CancelButton", true, false) as Button
			return {"faction": opts[0], "points": opts[1], "slot": opts[2], "labels": labels, "ok": ok.text, "layer": c,
				"press_ok": func() -> void: ok.pressed.emit(),
				"press_cancel": func() -> void: cancel.pressed.emit()}
	return {}


func _missing(q: Dictionary) -> Array:
	if q.is_empty():
		return ["dialog"]
	var missing: Array = []
	for t: String in ["NACHTMAHR builds its own list.", "Faction:", "Points:", "AI plays as:"]:
		if not (q["labels"] as Array).has(t):
			missing.append("label: %s" % t)
	if q["ok"] != "Build & deploy list":
		missing.append("button: Build & deploy list")
	return missing


func _texts(o: OptionButton) -> Array:
	var out: Array = []
	for i in o.item_count:
		out.append(o.get_item_text(i))
	return out


func test_every_label_dropdown_and_button_is_there_with_todays_defaults() -> void:
	var q := _ask()
	assert_array(_missing(q)).override_failure_message("AI Opponent controls missing: %s" % str(_missing(q))).is_empty()
	assert_array(_texts(q["faction"])).is_equal(["Alpha Guard", "Zeta Clan"])
	assert_array(_texts(q["points"])).is_equal(["750 points", "1500 points", "2000 points"])
	assert_int((q["points"] as OptionButton).selected).override_failure_message("the largest bracket is preselected").is_equal(2)
	assert_array(_texts(q["slot"])).is_equal(["Player 2 (Red)", "Player 1 (Blue)"])
	assert_int((q["slot"] as OptionButton).get_item_id((q["slot"] as OptionButton).selected)).is_equal(2)
	q["press_cancel"].call()


func test_picking_a_faction_refreshes_the_points_and_preselects_the_largest() -> void:
	var q := _ask()
	var fac: OptionButton = q["faction"]
	fac.select(1)
	fac.item_selected.emit(1)
	assert_array(_texts(q["points"])).is_equal(["500 points", "1000 points"])
	assert_int((q["points"] as OptionButton).selected).is_equal(1)
	q["press_cancel"].call()


func test_ok_hands_the_picked_list_file_and_slot_to_the_loader() -> void:
	var q := _ask()
	(q["faction"] as OptionButton).select(1)
	(q["faction"] as OptionButton).item_selected.emit(1)
	(q["points"] as OptionButton).select(0)
	(q["slot"] as OptionButton).select(1)
	q["press_ok"].call()
	await _runner.simulate_frames(2)
	assert_array(_loaded).is_equal([["zeta_500.json", 1]])
	assert_object(_ask().get("faction")).is_null()


func test_ok_with_the_defaults_builds_the_largest_list_for_player_2() -> void:
	_ask()["press_ok"].call()
	assert_array(_loaded).is_equal([["alpha_2000.json", 2]])


func test_cancel_builds_nothing_and_closes() -> void:
	_ask()["press_cancel"].call()
	await _runner.simulate_frames(2)
	assert_array(_loaded).is_empty()
	assert_bool(_ask().is_empty()).is_true()


func test_the_dialog_is_a_house_sheet_with_a_gold_ok_and_the_x_cancels() -> void:
	var q := _ask()
	var layer: CanvasLayer = q["layer"]
	var root := layer.get_child(0) as Control
	assert_object(root.theme).is_same(HouseStyle.theme())
	assert_int(root.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_str(String((layer.find_child("OkButton", true, false) as Button).theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
	for o: String in ["faction", "points", "slot"]:
		assert_str(String((q[o] as OptionButton).theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	(layer.find_child("CloseButton", true, false) as Button).pressed.emit()
	await _runner.simulate_frames(2)
	assert_array(_loaded).is_empty()
	assert_bool(_ask().is_empty()).is_true()


func test_inventory_check_names_a_missing_line() -> void:
	var q := _ask()
	assert_array(_missing(q)).is_empty()
	q["labels"].erase("Points:")
	assert_array(_missing(q)).contains_exactly(["label: Points:"])
	q["press_cancel"].call()
