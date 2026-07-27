extends GdUnitTestSuite
## E2E — DEFECT 3: the battle-log EXPORT was truncated to the last 200 entries.
##
## What shipped broken: the panel's live view is a 200-entry ring buffer (BattleLog.CAP), and the export
## read that ring instead of the append-only archive — so a full game exported only its closing rounds
## and the maintainer's whole field-test process ran on mutilated files.
##
## test/battle_log_test.gd already pins the PURE half (export_text over an oversized archive). What no
## test covered is the WIRING: whether the paths a player actually uses — the F8 hotkey and the Battle
## Log panel's Export button — reach the archive or the capped view. main.gd owns that wiring
## (_on_battle_log_export, main.gd:8224) and nothing in test/ loads main.gd.
##
## WHAT THIS SUITE DRIVES, all on the real scenes/main.tscn after its real _ready():
##  - the real BattleLog instance main.gd built and wired,
##  - a real InputEventKey(F8) pushed through the viewport, dispatched by the engine to main.gd's real
##    _unhandled_key_input (main.gd:7350),
##  - the real Export Button inside the real BattleLogPanel main.gd created and connected (main.gd:8192),
##  - the real file write, read back off disk.
## Constructed: the log content (CAP+50 synthetic entries) — a real game's worth of events would need a
## real army and a real match.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const FIRST_MARK := "E2E-OPENING-SHOT"     # entry #0 — the one the truncated export lost
const LAST_MARK := "E2E-FINAL-BLOW"        # the last entry — present either way, so it proves the read worked

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _written: Array[String] = []           # absolute paths to remove in after_test()


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	# The export writes into user:// — a real directory on the maintainer's machine. Never leave files.
	for p in _written:
		DirAccess.remove_absolute(p)
	_written.clear()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Push a whole game's worth of entries through the REAL log the scene built, overflowing the live ring.
func _fill_log_past_the_cap() -> void:
	var log_node = _main.battle_log
	assert_that(log_node).is_not_null()
	log_node.log_event(BattleLog.Category.GENERAL, FIRST_MARK, false)
	for i in range(BattleLog.CAP + 50):
		log_node.log_event(BattleLog.Category.MOVEMENT, "filler %d" % i, false)
	log_node.log_event(BattleLog.Category.COMBAT, LAST_MARK, false)
	# Precondition that gives this suite its teeth: the opening entry is GONE from the live view.
	# If this ever stops holding the test would pass vacuously, so it is asserted, not assumed.
	var live_text := ""
	for e in log_node.entries():
		live_text += str((e as Dictionary)["text"])
	assert_str(live_text) \
		.override_failure_message("the live ring still holds the opening entry — this suite no longer overflows the cap and would pass vacuously") \
		.not_contains(FIRST_MARK)


## The absolute path main.gd echoed into the log after a successful export ("Battle Log exported → …").
func _exported_path() -> String:
	var all: Array = _main.battle_log.entries()
	for i in range(all.size() - 1, -1, -1):
		var text := str((all[i] as Dictionary)["text"])
		if text.begins_with("Battle Log exported → "):
			return text.trim_prefix("Battle Log exported → ")
	return ""


func _assert_exported_file_carries_the_whole_game() -> void:
	var path := _exported_path()
	assert_str(path) \
		.override_failure_message("main.gd reported no export path — the export did not run or it failed") \
		.is_not_empty()
	_written.append(path)
	assert_bool(FileAccess.file_exists(path)).is_true()
	var body := FileAccess.get_file_as_string(path)
	assert_str(body) \
		.override_failure_message("the exported file is missing the game's OPENING entry — the export read the 200-entry live ring instead of the archive, so the maintainer's field-test file starts mid-game") \
		.contains(FIRST_MARK)
	assert_str(body) \
		.override_failure_message("the exported file is missing the game's LAST entry — the export did not read the log at all") \
		.contains(LAST_MARK)
	# A silently truncated archive must announce itself in the header; here nothing was dropped.
	assert_str(body).not_contains("WARNING:")


func test_f8_hotkey_exports_the_whole_game(timeout := 120000) -> void:
	_fill_log_past_the_cap()

	# A real key event through the engine's own dispatch — main.gd's _unhandled_key_input decides.
	var ev := InputEventKey.new()
	ev.keycode = KEY_F8
	ev.physical_keycode = KEY_F8
	ev.pressed = true
	_main.get_viewport().push_input(ev)
	await _runner.simulate_frames(2)

	_assert_exported_file_carries_the_whole_game()


func test_battle_log_panel_export_button_exports_the_whole_game(timeout := 120000) -> void:
	_fill_log_past_the_cap()

	# The real Button inside the real panel main.gd built — pressing it runs the real
	# export_requested -> _on_battle_log_export chain.
	var btn := _find_export_button(_main.battle_log_panel)
	assert_that(btn) \
		.override_failure_message("the Battle Log panel has no Export button any more — the maintainer's field-test artefact is unreachable") \
		.is_not_null()
	btn.pressed.emit()
	await _runner.simulate_frames(2)

	_assert_exported_file_carries_the_whole_game()


func _find_export_button(node: Node) -> Button:
	if node == null:
		return null
	if node is Button and (node as Button).text == "Export":
		return node as Button
	for c in node.get_children():
		var found := _find_export_button(c)
		if found != null:
			return found
	return null
