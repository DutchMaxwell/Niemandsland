extends GdUnitTestSuite
## E2E — the Game over summary, row 28 of the UI inventory (uimenus step 9): "N rounds played", the
## objectives block (or the "no markers" line), the mission VP block on a VP mission, the verdict line, and
## OK / dismissal handing over to the evaluation-sharing prompt. Real main.tscn, the real summary function.
## test_inventory_check_names_a_missing_line proves the presence check can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const MARKERS := [Vector3(-0.3, 0.0, 0.1), Vector3(0.0, 0.0, -0.2), Vector3(0.3, 0.0, 0.2)]

class StubPrivacy extends PrivacyMenu:
	var asked := 0
	func maybe_prompt_after_completed_game() -> bool:
		asked += 1
		return true

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _stub: StubPrivacy


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_stub = StubPrivacy.new()
	_main.privacy_menu = _stub
	_main._solo_both_ai = false
	_main.solo_ai_slots = {2: true}


func after_test() -> void:
	SoloController.mission_reset("end", {})
	_main.privacy_menu = null
	_stub.free()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


## The summary window the player sees (today an AcceptDialog on the main node).
func _summary() -> Node:
	for c in _main.get_children():
		if c is AcceptDialog and (c as AcceptDialog).title == "Game over" and not c.is_queued_for_deletion():
			return c
	return null


func _text() -> String:
	var s := _summary()
	return (s as AcceptDialog).dialog_text if s != null else "<no summary>"


func _missing(want: Array) -> Array:
	var missing: Array = []
	for line: String in want:
		if not _text().contains(line):
			missing.append("line: %s" % line)
	return missing


func _show() -> void:
	_main._solo_show_game_summary()
	await _runner.simulate_frames(2)


func test_face_off_summary_has_rounds_objectives_and_verdict() -> void:
	_main.terrain_overlay.update_objectives(MARKERS, [1, 2, 0])
	SoloController.mission_reset("end", {})
	await _show()
	assert_object(_summary()).is_not_null()
	var want := ["%d rounds played." % _main.SOLO_GAME_ROUNDS, "Objectives held:", "You: 1", "NACHTMAHR: 1", "Neutral: 1"]
	assert_array(_missing(want)).override_failure_message("summary lines missing: %s" % str(_missing(want))).is_empty()
	assert_bool(_text().contains("Mission VP")).is_false()
	assert_str(_text().substr(_text().rfind("\n") + 1)).is_equal("Draw")


func test_vp_mission_shows_the_ledger_block() -> void:
	_main.terrain_overlay.update_objectives(MARKERS, [1, 2, 2])
	SoloController.mission_reset("round_vp", {"majority": "end"})
	SoloController.mission_vp = [6, 5]
	await _show()
	assert_array(_missing(["Mission VP (decides):", "You: 6", "NACHTMAHR: 5", "You win"])).is_empty()


func test_no_markers_line_when_the_table_has_none() -> void:
	_main.terrain_overlay.update_objectives([], [])
	SoloController.mission_reset("end", {})
	await _show()
	assert_bool(_text().contains("No objective markers were on the table.")).is_true()


func test_ok_closes_the_summary_and_hands_over_to_the_sharing_prompt() -> void:
	await _show()
	assert_int(_stub.asked).is_equal(0)
	(_summary() as AcceptDialog).confirmed.emit()
	await _runner.simulate_frames(2)
	assert_object(_summary()).override_failure_message("OK did not close the summary").is_null()
	assert_int(_stub.asked).is_equal(1)


func test_dismissal_hands_over_too() -> void:
	await _show()
	(_summary() as AcceptDialog).canceled.emit()
	await _runner.simulate_frames(2)
	assert_object(_summary()).is_null()
	assert_int(_stub.asked).is_equal(1)


func test_inventory_check_names_a_missing_line() -> void:
	_main.terrain_overlay.update_objectives(MARKERS, [1, 2, 0])
	SoloController.mission_reset("end", {})
	await _show()
	assert_array(_missing(["Objectives held:"])).is_empty()
	assert_array(_missing(["Objectives held:", "Mission VP (decides):"])).contains_exactly(["line: Mission VP (decides):"])
