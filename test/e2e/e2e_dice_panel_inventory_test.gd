extends GdUnitTestSuite
## E2E — the dice window's FUNCTION INVENTORY. The dice window is the house-style prototype
## (maintainer decision 23.09.2026): the mockup's look, TODAY'S full function set — "das Mockup
## reduziert zu viel". So every control the panel had before the restyle (origin/main 9a736c80) must
## still be there, visible, inside the window, reachable by a REAL click through the viewport, and
## drive the same effect it drove before. The readouts (per-face tally, "In box" line, result line,
## dice log, roll purpose) and the per-die colour-tag click on a die in the tray are driven as well.
##
## Real: scenes/main.tscn with its real _ready(), E2EBoot.click_canvas (push_input through the GUI,
## canvas -> screen conversion), the real DiceTray, ObjectManager movement cap and DiceRules evaluation.
## test_inventory_check_reports_a_removed_control proves the presence check can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

## Today's controls: [row it lives in now, the text a player reads on it, what it is]. The step
## minus is typographic in the house style ("−10", "−") and reads as "-10" / "-" here.
const INVENTORY := [
	["MovementCapRow", "Off", "movement Off"],
	["MovementCapRow", "Advance", "movement Advance"],
	["MovementCapRow", "Rush", "movement Rush"],
	["MovementCapRow", "Charge", "movement Charge"],
	["DiceCountSelector", "1", "quick pick 1"],
	["DiceCountSelector", "2", "quick pick 2"],
	["DiceCountSelector", "3", "quick pick 3"],
	["DiceCountSelector", "4", "quick pick 4"],
	["DiceCountSelector", "5", "quick pick 5"],
	["DiceCountSelector", "6", "quick pick 6"],
	["DiceCountSelector", "7", "quick pick 7"],
	["DiceCountSelector", "8", "quick pick 8"],
	["DiceCountSelector", "9", "quick pick 9"],
	["DiceCountSelector", "10", "quick pick 10"],
	["DiceCountSelector", "-10", "count step -10"],
	["DiceCountSelector", "-5", "count step -5"],
	["DiceCountSelector", "-1", "count step -1"],
	["DiceCountSelector", "+1", "count step +1"],
	["DiceCountSelector", "+5", "count step +5"],
	["DiceCountSelector", "+10", "count step +10"],
	["SuccessRow", "–", "success none (–)"],
	["SuccessRow", "2+", "success 2+"],
	["SuccessRow", "3+", "success 3+"],
	["SuccessRow", "4+", "success 4+"],
	["SuccessRow", "5+", "success 5+"],
	["SuccessRow", "6+", "success 6+"],
	["ModifierRow", "-", "modifier -"],
	["ModifierRow", "+", "modifier +"],
	["ButtonRow", "Roll", "Roll"],
	["ButtonRow", "Quick", "Quick"],
	["RerollRow", "Fails", "re-roll Fails"],
	["RerollRow", "1s", "re-roll 1s"],
	["RerollRow", "6s", "re-roll 6s"],
	["RerollRow", "All", "re-roll All"],
]

## Every glyph the rebuilt window draws beyond plain ASCII: step minus, collapse / expand, the
## "none" dash, ±0, the tally ×N, the success ✓, the log's re-roll ↻ and the result line's ·.
const GLYPHS := "−▼▲–±×✓↻·"

## Today's dice panel at rest, measured on the real display (1920x1080 base, 23.09.): 420 x 702 px,
## and it widened to 474 px once a re-roll line reached the log. The rebuilt window may not cover more.
const TODAY_W := 420.0
const TODAY_H := 702.0

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
	_main = null
	_runner = null


# === helpers ==================================================================================

func _panel() -> Control:
	return _main.get_node("UI/HUD/DiceRollerPanel") as Control


static func _norm(text: String) -> String:
	return text.replace("−", "-")


## The button reading `text` inside the panel's section `row_name`, or null.
func _find(row_name: String, text: String) -> Button:
	var row := _panel().find_child(row_name, true, false)
	if row == null:
		return null
	for b: Node in row.find_children("*", "Button", true, false):
		if _norm((b as Button).text) == text:
			return b as Button
	return null


## Every INVENTORY control that is missing, hidden or not inside the window — [] when all are there.
func _missing_controls() -> Array:
	var missing: Array = []
	var window := _panel().get_global_rect().grow(1.0)
	for entry: Array in INVENTORY:
		var b := _find(entry[0], entry[1])
		if b == null or not b.is_visible_in_tree() or not window.encloses(b.get_global_rect()):
			missing.append(entry[2])
	return missing


## A real left click on the control's centre, through the viewport's GUI pipeline. A missing
## control fails the test by name instead of crashing the run on a null call.
func _click(c: Control) -> void:
	if c == null:
		fail("the control to click is missing from the dice window")
		return
	var vp := c.get_viewport()
	var at := c.get_global_rect().get_center()
	E2EBoot.motion_canvas(vp, at)
	E2EBoot.click_canvas(vp, at, true)
	E2EBoot.click_canvas(vp, at, false)
	await _runner.simulate_frames(1)


func _wait_until(pred: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not bool(pred.call()):
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().process_frame
	return true


## The texts of every label in the newest dice-log entry, joined.
func _last_log_text() -> String:
	var log_box: Node = _main._dice_log_vbox
	if log_box.get_child_count() == 0:
		return ""
	var parts: PackedStringArray = []
	for l: Node in log_box.get_child(log_box.get_child_count() - 1).find_children("*", "Label", true, false):
		parts.append((l as Label).text)
	return " ".join(parts)


## The per-face tally ("×N" for faces 6..1) in the current-roll column.
func _tally() -> PackedStringArray:
	var out: PackedStringArray = []
	for l: Node in _main._current_roll_column.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("×") and not l.is_queued_for_deletion():
			out.append((l as Label).text)
	return out


## A local, known roll through the tray's own result seam (the Quick/remote path).
func _show(faces: Array[int]) -> void:
	_main.dice_roller_control.show_faces(faces)
	await _runner.simulate_frames(2)


# === tests ====================================================================================

func test_every_control_of_todays_panel_is_in_the_rebuilt_window(timeout := 120000) -> void:
	assert_array(_missing_controls()).override_failure_message(
		"today's dice controls missing/hidden in the rebuilt window: %s" % str(_missing_controls())).is_empty()
	# The readouts of today's panel.
	var box: Label = _main.current_dice_label
	assert_bool(box.is_visible_in_tree()).is_true()
	assert_str(box.text).is_equal("In box: 6 D6")
	assert_bool((_main._current_roll_column as Control).is_visible_in_tree()).is_true()
	assert_bool((_main._dice_log_scroll as Control).is_visible_in_tree()).is_true()
	assert_bool((_main.dice_roller_control as Control).is_visible_in_tree()).is_true()
	# Every glyph the window draws exists in the font that draws it (Font.has_char, not by eye).
	var font: Font = (_main.roll_button as Control).get_theme_font(&"font")
	for i: int in GLYPHS.length():
		assert_bool(font.has_char(GLYPHS.unicode_at(i))) \
			.override_failure_message("house font lacks '%s'" % GLYPHS[i]).is_true()
	# Not covering the field more than today.
	var size := _panel().size
	assert_float(size.x).override_failure_message("window %s wider than today's %d" % [size, TODAY_W]) \
		.is_less_equal(TODAY_W + 0.5)
	assert_float(size.y).override_failure_message("window %s taller than today's %d" % [size, TODAY_H]) \
		.is_less_equal(TODAY_H + 0.5)
	# No per-window colour: the selected state is a house-style variant, not a modulate tint.
	var six: Button = _find("DiceCountSelector", "6")
	assert_bool(HouseStyle.is_selected(six)).is_true()
	assert_that(six.modulate).is_equal(Color.WHITE)


func test_inventory_check_reports_a_removed_control(timeout := 120000) -> void:
	# Prove the presence check can fail: take one real control out and it must be named.
	assert_array(_missing_controls()).is_empty()
	var sixes := _find("RerollRow", "6s")
	_main._reroll_buttons.erase(DiceRules.RerollMode.SIXES)
	sixes.get_parent().remove_child(sixes)
	sixes.free()
	assert_array(_missing_controls()).contains_exactly(["re-roll 6s"])


func test_selectors_drive_their_effects(timeout := 120000) -> void:
	var om: Node = _main.object_manager
	var modes := {"Off": ObjectManager.MovementCap.OFF, "Advance": ObjectManager.MovementCap.ADVANCE,
		"Rush": ObjectManager.MovementCap.RUSH, "Charge": ObjectManager.MovementCap.CHARGE}
	for text: String in ["Advance", "Rush", "Charge", "Off"]:
		var b := _find("MovementCapRow", text)
		await _click(b)
		assert_int(int(om.get("_movement_cap"))).override_failure_message("movement " + text).is_equal(modes[text])
		assert_bool(HouseStyle.is_selected(b)).is_true()

	for n: int in range(1, 11):
		var pick := _find("DiceCountSelector", str(n))
		await _click(pick)
		assert_int(_main._dice_count).override_failure_message("quick pick %d" % n).is_equal(n)
		assert_int(_main.dice_roller_control.dice_count).is_equal(n)
		assert_str(_main.current_dice_label.text).is_equal("In box: %d D6" % n)
		assert_bool(HouseStyle.is_selected(pick)).is_true()

	# From 10: a squad-sized walk up to 26 and back down with every step.
	var expected := 10
	for step: int in [10, 5, 1, -1, -5, -10]:
		await _click(_find("DiceCountSelector", "%+d" % step))
		expected += step
		assert_int(_main._dice_count).override_failure_message("count step %+d" % step).is_equal(expected)
		assert_str(_main._dice_count_value_label.text).is_equal(str(expected))
		assert_str(_main.current_dice_label.text).is_equal("In box: %d D6" % expected)

	var targets := {"–": DiceRules.TARGET_NONE, "2+": 2, "3+": 3, "4+": 4, "5+": 5, "6+": 6}
	for text: String in ["2+", "3+", "4+", "5+", "6+", "–"]:
		var t := _find("SuccessRow", text)
		await _click(t)
		assert_int(_main._success_target).override_failure_message("success " + text).is_equal(targets[text])
		assert_bool(HouseStyle.is_selected(t)).is_true()

	await _click(_find("ModifierRow", "+"))
	assert_int(_main._success_modifier).is_equal(1)
	assert_str(_main._modifier_value_label.text).is_equal("+1")
	await _click(_find("ModifierRow", "-"))
	await _click(_find("ModifierRow", "-"))
	assert_int(_main._success_modifier).is_equal(-1)
	assert_str(_main._modifier_value_label.text).is_equal("-1")
	await _click(_find("ModifierRow", "+"))
	assert_str(_main._modifier_value_label.text).is_equal("±0")


func test_rolls_tally_result_log_and_rerolls(timeout := 180000) -> void:
	await _click(_find("SuccessRow", "4+"))
	var log_before: int = _main._dice_log_vbox.get_child_count()

	# Quick: an instant roll of the chosen count, logged.
	await _click(_find("DiceCountSelector", "8"))
	await _click(_find("ButtonRow", "Quick"))
	assert_int(_main._last_faces.size()).is_equal(8)
	assert_int(_main._dice_log_vbox.get_child_count()).is_equal(log_before + 1)
	assert_str(_last_log_text()).contains("You (8d6 vs 4+)")

	# Roll: the physics roll starts ("Rolling...") and lands.
	var roll := _find("ButtonRow", "Roll")
	await _click(roll)
	assert_str(_main.roll_button.text).is_equal("Rolling...")
	var landed := await _wait_until(func() -> bool: return _main.roll_button.text == "Roll", 20000)
	assert_bool(landed).override_failure_message("physics roll never landed").is_true()
	assert_int(_main._dice_log_vbox.get_child_count()).is_equal(log_before + 2)

	# Per-face tally, result line and "In box" for a known roll: 6 6 5 3 1 1 vs 4+.
	var known: Array[int] = [6, 6, 5, 3, 1, 1]
	await _show(known)
	assert_array(Array(_tally())).contains_exactly(["×2", "×1", "×0", "×1", "×0", "×2"])
	assert_str(_main._dice_result_label.text).is_equal("total 22 · 3 successes")
	# "In box" names the player's chosen count (8), as it did before — not the shown roll's size.
	assert_str(_main.current_dice_label.text).is_equal("In box: 8 D6")
	var hits := false
	for l: Node in _main._current_roll_column.find_children("*", "Label", true, false):
		hits = hits or ((l as Label).text == "✓ 3" and not l.is_queued_for_deletion())
	assert_bool(hits).override_failure_message("no '✓ 3' success line in the tally").is_true()
	# No tally jump: a re-evaluation swaps the rows in place in the same frame — the old rows may
	# not linger (queued for deletion) beside the new ones and double the column for a frame.
	_main._on_success_target_pressed(5)
	var rows: int = _main._current_roll_column.get_child_count()
	assert_int(rows).override_failure_message("tally column holds %d rows mid-re-evaluation (6 faces + ✓)" % rows) \
		.is_equal(7)
	_main._on_success_target_pressed(4)

	# Re-rolls: each chip re-tosses exactly its dice of 6 5 4 3 2 1 vs 4+ and logs "↻N <label>".
	var modes := {"Fails": 3, "1s": 1, "6s": 1, "All": 6}
	for text: String in ["Fails", "1s", "6s", "All"]:
		var ladder: Array[int] = [6, 5, 4, 3, 2, 1]
		await _show(ladder)
		var chip := _find("RerollRow", text)
		assert_bool(chip.disabled).override_failure_message(text + " disabled on a fresh roll").is_false()
		await _click(chip)
		assert_int(_main._pending_reroll_count).override_failure_message("re-roll " + text).is_equal(modes[text])
		var done := await _wait_until(func() -> bool: return _main.roll_button.text == "Roll", 20000)
		assert_bool(done).override_failure_message("re-roll %s never landed" % text).is_true()
		assert_str(_last_log_text()).contains("↻%d %s" % [modes[text], DiceRules.reroll_mode_label(
			{"Fails": DiceRules.RerollMode.FAILURES, "1s": DiceRules.RerollMode.ONES,
			"6s": DiceRules.RerollMode.SIXES, "All": DiceRules.RerollMode.ALL}[text])])

	# The log follows new rolls: after a mixed-colour roll (the tallest entry) the newest line is in
	# view, as it was before the restyle — its wrapped rows settle their height a few frames late.
	var mixed: Array[int] = [6, 2, 4]
	_main.dice_roller_control.show_faces(mixed, [1, 0, 2])
	await _runner.simulate_frames(10)
	var bar: VScrollBar = _main._dice_log_scroll.get_v_scroll_bar()
	assert_float(bar.max_value).override_failure_message("log never overflowed — the check proves nothing") \
		.is_greater(bar.page)
	assert_float(float(_main._dice_log_scroll.scroll_vertical)) \
		.override_failure_message("newest log entry below the fold: scroll %d of %d" % [
			_main._dice_log_scroll.scroll_vertical, bar.max_value - bar.page]) \
		.is_greater_equal(bar.max_value - bar.page - 1.0)
	# A selector change re-evaluates the last roll and rebuilds the tally; the log stays on the newest.
	await _click(_find("SuccessRow", "5+"))
	await _click(_find("ModifierRow", "+"))
	await _runner.simulate_frames(10)
	assert_float(float(_main._dice_log_scroll.scroll_vertical)) \
		.override_failure_message("a selector change scrolled the log off the newest roll: %d of %d" % [
			_main._dice_log_scroll.scroll_vertical, bar.max_value - bar.page]) \
		.is_greater_equal(bar.max_value - bar.page - 1.0)

	# The log wraps inside its card: the window never widens past today's width — not even when one roll
	# uses all four colour tags (five tally columns beside the tray).
	assert_float(_panel().size.x).is_less_equal(TODAY_W + 0.5)
	var all_tags: Array[int] = [6, 5, 4, 3, 2, 1]
	_main.dice_roller_control.show_faces(all_tags, [1, 1, 2, 3, 4, 0])
	await _runner.simulate_frames(10)
	assert_float(_panel().size.x).override_failure_message("five colour groups widened the window to %d" % _panel().size.x) \
		.is_less_equal(TODAY_W + 0.5)
	await E2EBoot.settle(get_tree())   # let the log's auto-scroll await finish before teardown


func test_colour_tag_click_on_a_die(timeout := 120000) -> void:
	var faces: Array[int] = [2, 3, 4]
	await _show(faces)
	var tray: DiceTray = _main.dice_roller_control
	var die: Node3D = tray._dice[0]
	var px: Vector2 = tray._camera.unproject_position(die.global_position)
	var vp_size := Vector2(tray._viewport.size)
	var r := tray.get_global_rect()
	var at := r.position + Vector2(px.x / vp_size.x * r.size.x, px.y / vp_size.y * r.size.y)
	var tagged := [-1, -1]
	tray.color_tag_changed.connect(func(index: int, tag: int) -> void:
		tagged[0] = index
		tagged[1] = tag)
	E2EBoot.click_canvas(tray.get_viewport(), at, true)
	E2EBoot.click_canvas(tray.get_viewport(), at, false)
	await _runner.simulate_frames(1)
	assert_array(tagged).override_failure_message("click on die 0 at %s tagged nothing" % at).is_equal([0, 1])
	assert_int(tray.get_color_tags()[0]).is_equal(1)
	await E2EBoot.settle(get_tree())


func test_collapse_folds_to_the_header_and_a_roll_unfolds_it(timeout := 120000) -> void:
	var panel := _panel()
	var open_rect := panel.get_global_rect()
	var fold := panel.find_child("CollapseButton", true, false) as Button
	assert_object(fold).is_not_null()
	assert_str(fold.text).is_equal(HouseStyle.GLYPH_COLLAPSE)

	await _click(fold)
	await _runner.simulate_frames(2)
	assert_bool(_main._dice_collapsed).is_true()
	assert_bool((_main._dice_controls as Control).is_visible_in_tree()).is_false()
	assert_bool((_main.dice_roller_control as Control).is_visible_in_tree()).is_false()
	var folded := panel.get_global_rect()
	assert_float(folded.size.y).override_failure_message("folded window %s" % folded).is_less(80.0)
	assert_float(folded.end.y).is_equal_approx(open_rect.end.y, 1.0)   # keeps its bottom-right corner
	assert_str(fold.text).is_equal(HouseStyle.GLYPH_EXPAND)
	# A purpose set while folded waits for the unfold.
	_main._set_roll_purpose("Rending shots")
	assert_bool((_main.roll_purpose_label as Control).visible).is_false()

	await _click(fold)
	await _runner.simulate_frames(2)
	assert_bool(_main._dice_collapsed).is_false()
	assert_bool((_main.roll_purpose_label as Control).visible).is_true()
	_main._set_roll_purpose("")
	await _runner.simulate_frames(2)
	assert_that(panel.get_global_rect()).is_equal(open_rect)

	# Folded again, any roll (AI, scripted, remote) unfolds the window so its dice are seen.
	await _click(fold)
	var faces: Array[int] = [5, 5]
	await _show(faces)
	assert_bool(_main._dice_collapsed).is_false()
	assert_bool((_main.dice_roller_control as Control).is_visible_in_tree()).is_true()
	await E2EBoot.settle(get_tree())
