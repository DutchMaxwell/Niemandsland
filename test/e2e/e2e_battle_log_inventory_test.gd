extends GdUnitTestSuite
## E2E — the Battle Log panel's body, row 8 of the UI inventory (uiprompts step 6a). Opened the way the
## player opens it (the top bar's Battle Log button), then every control of TODAY's panel is found by its
## words and clicked for real: the filter dropdown (All / Combat / Movement / AI) narrows the list, Export
## writes the whole game and names the file, Copy puts it on the clipboard, a line that carries reasoning
## unfolds and folds on a click (and shows the reasoning as its tooltip), AI lines are told apart from the
## player's, the list follows the newest entry and keeps at most 200 lines, the header folds the panel.
## Opening / closing from the bar stays pinned by e2e_top_bar_test.
## test_the_inventory_check_names_a_removed_control proves the control check can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const REASON := "Closest enemy in 18\"; Guards hold the objective"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _exported: Array = []


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_exported.clear()


func after_test() -> void:
	for path: String in _exported:   # the export writes into user:// — never leave files behind
		DirAccess.remove_absolute(path)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


# === helpers ==================================================================================

func _panel() -> BattleLogPanel:
	return _main.battle_log_panel


func _log() -> BattleLog:
	return _main.battle_log


## Opens the panel with the top bar's Battle Log button (a real click).
func _open() -> void:
	await _click(_main._top_bar.items()["log"])
	await _runner.simulate_frames(2)


func _click(c: Control) -> void:
	if c == null:
		fail("the control to click is missing")
		return
	var vp := _main.get_viewport()
	var at := c.get_global_rect().get_center()
	E2EBoot.motion_canvas(vp, at)
	var under := vp.gui_get_hovered_control()
	assert_bool(under == c or (under != null and c.is_ancestor_of(under))).override_failure_message(
		"'%s' is covered at %s by %s" % [c.name, at, under.get_path() if under != null else "nothing"]).is_true()
	E2EBoot.click_canvas(vp, at, true)
	E2EBoot.click_canvas(vp, at, false)
	await _runner.simulate_frames(3)


func _button(text: String) -> Button:
	for n: Node in _panel().find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and not (b is OptionButton) and b.text.contains(text):
			return b
	return null


func _filter() -> OptionButton:
	var found := _panel().find_children("*", "OptionButton", true, false)
	return found[0] as OptionButton if not found.is_empty() else null


## The visible log lines, in order (an unfolded reasoning line included).
func _lines() -> Array:
	var out: Array = []
	for n: Node in _panel().find_children("*", "Label", true, false):
		var l := n as Label
		if l.is_visible_in_tree() and not n.is_queued_for_deletion():
			out.append(l)
	return out


func _line(fragment: String) -> Label:
	for l: Label in _lines():
		if l.text.contains(fragment):
			return l
	return null


func _texts() -> String:
	var t := ""
	for l: Label in _lines():
		t += l.text + "\n"
	return t


## Today's panel controls it no longer shows; empty = all there.
func _missing() -> Array:
	var out: Array = []
	for t: String in ["Battle Log", "Export", "Copy"]:
		if _button(t) == null:
			out.append("button: %s" % t)
	var f := _filter()
	if f == null or not f.is_visible_in_tree():
		out.append("dropdown: filter")
	else:
		for i in f.item_count:
			if f.get_item_text(i) != ["All", "Combat", "Movement", "AI"][i]:
				out.append("filter item %d: %s" % [i, f.get_item_text(i)])
	return out


## Picks `index` in the filter dropdown the way the player does (press, choose, release).
func _pick(index: int) -> void:
	var f := _filter()
	await _click(f)
	f.get_popup().index_pressed.emit(index)
	f.get_popup().hide()
	await _runner.simulate_frames(3)


func _fill() -> void:
	_log().log_event(BattleLog.Category.COMBAT, "Guards shoot Raiders: 2 wounds")
	_log().log_event(BattleLog.Category.MOVEMENT, "Guards advance 6\"")
	_log().log_event(BattleLog.Category.COMBAT, "NACHTMAHR: Raiders charge Guards", true, REASON)
	await _runner.simulate_frames(3)


# === the controls =============================================================================

func test_the_open_panel_shows_every_control_and_the_lines(timeout := 120000) -> void:
	await _fill()
	await _open()
	assert_array(_missing()).override_failure_message("today's log controls missing: %s" % [_missing()]).is_empty()
	for t: String in ["Guards shoot Raiders: 2 wounds", "Guards advance 6\"", "NACHTMAHR: Raiders charge Guards"]:
		assert_object(_line(t)).override_failure_message("line '%s' missing:\n%s" % [t, _texts()]).is_not_null()
	# AI lines are told apart from the player's (a different ink).
	var ai := _line("NACHTMAHR: Raiders charge Guards")
	var own := _line("Guards shoot Raiders")
	assert_object(ai.get_theme_color(&"font_color")).is_not_equal(own.get_theme_color(&"font_color"))


func test_the_filter_narrows_the_list(timeout := 120000) -> void:
	await _fill()
	await _open()
	await _pick(2)   # Movement
	assert_str(_texts()).contains("Guards advance 6\"")
	assert_str(_texts()).not_contains("Guards shoot Raiders")
	await _pick(3)   # AI
	assert_str(_texts()).contains("NACHTMAHR: Raiders charge Guards")
	assert_str(_texts()).not_contains("Guards advance")
	await _pick(1)   # Combat
	assert_str(_texts()).contains("Guards shoot Raiders")
	assert_str(_texts()).contains("NACHTMAHR: Raiders charge Guards")
	assert_str(_texts()).not_contains("Guards advance")
	await _pick(0)   # All
	assert_str(_texts()).contains("Guards advance 6\"")


func test_a_reasoning_line_unfolds_and_folds_on_a_click(timeout := 120000) -> void:
	await _fill()
	await _open()
	var line := _line("NACHTMAHR: Raiders charge Guards")
	assert_str(line.tooltip_text).is_equal(REASON)
	assert_object(_line(REASON)).override_failure_message("the reasoning shows before the click").is_null()
	var folded := line.text
	await _click(line)
	assert_object(_line(REASON)).override_failure_message("a click did not unfold the reasoning").is_not_null()
	assert_str(line.text).is_not_equal(folded)
	await _click(line)
	assert_object(_line(REASON)).override_failure_message("a second click did not fold it").is_null()
	assert_str(line.text).is_equal(folded)


func test_export_writes_the_game_and_copy_fills_the_clipboard(timeout := 120000) -> void:
	await _fill()
	await _open()
	await _click(_button("Export"))
	var toast: Label = _main._solo_toast
	assert_str(toast.text).starts_with("Battle Log exported → ")
	var path := toast.text.trim_prefix("Battle Log exported → ")
	_exported.append(path)
	assert_bool(FileAccess.file_exists(path)).is_true()
	assert_str(FileAccess.get_file_as_string(path)).contains("Guards advance 6\"")
	await _click(_button("Copy"))
	assert_str(_main._solo_toast.text).is_equal("Battle Log copied to clipboard")


func test_the_list_follows_the_newest_line_and_keeps_two_hundred(timeout := 120000) -> void:
	await _open()
	for i in 230:
		_log().log_event(BattleLog.Category.GENERAL, "Entry %03d" % i)
	await _runner.simulate_frames(4)
	var scroll := _panel().find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
	assert_int(scroll.scroll_vertical).override_failure_message("the list does not follow the newest line") \
		.is_greater_equal(int(scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page) - 2)
	var shown := 0
	for l: Label in _lines():
		if l.text.contains("Entry "):
			shown += 1
	assert_int(shown).is_equal(BattleLogPanel.MAX_VISIBLE)
	assert_object(_line("Entry 229")).is_not_null()
	assert_object(_line("Entry 000")).is_null()


func test_the_header_folds_the_panel(timeout := 120000) -> void:
	await _open()
	assert_bool(_panel().is_open()).is_true()
	await _click(_button("Battle Log"))
	assert_bool(_panel().is_open()).is_false()
	assert_bool(_panel().is_visible_in_tree()).is_false()


# === the check itself =========================================================================

func test_the_inventory_check_names_a_removed_control(timeout := 120000) -> void:
	await _open()
	assert_array(_missing()).is_empty()
	var copy := _button("Copy")
	if copy == null:
		fail("no Copy button to remove")
		return
	copy.hide()
	assert_array(_missing()).contains_exactly(["button: Copy"])
