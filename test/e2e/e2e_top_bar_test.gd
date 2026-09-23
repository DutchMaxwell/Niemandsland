extends GdUnitTestSuite
## E2E — the top bar (uitop, maintainer 23.09.: "? Controls" belongs in the "Obere Leiste"; mockup LOOK,
## today's FULL function set). Every item that sat at the top of the screen is still there and still does
## what it did — the menu button opens the menu, Battle Log opens the log, the FPS line reads, the ruler
## readout stays readable — round and phase / turn are shown, "? Controls" moved here from the rail, and
## Next Round runs the menu's own Next Round. All clicks are REAL clicks on the real main.tscn.
## test_inventory_check_reports_a_removed_item proves the presence check can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

## Every item of the top strip after the change: today's (menu button, FPS line, the log tab = "log")
## plus the bar's own.
const ITEMS := ["menu", "round", "state", "fps", "log", "controls", "next"]
## The bar's row lies inside this band (the tool rail starts at 60).
const TOP_STRIP := 56.0

## The always-on key wall as it stood on main (96af498a, scenes/main.tscn UI/HUD/InfoLabel) — every
## binding's keys must be in the Controls overlay.
const WALL_TODAY := ["WASD", "Q/E", "Scroll", "Left Click", "Alt + Click", "Shift + Click", "R (hold)",
	"Shift+R", "1-9", "Shift+A", "Ctrl+C/V/D", "L", "G / Shift+G", "F / Shift+F", "M / Shift+M", "P",
	"K / Shift+K", "T / Shift+T"]

## Today's top strip on 9751d768 (capture_top.gd on the autosave, 1920x1080, canvas px): the menu button
## 53x51 + the Battle Log tab 340x41 + the FPS line 247x40 = 26,083-26,523 px² (the FPS text's width
## moves it), 90 px deep. The smaller number is the bar's budget.
const TODAY_TOP_AREA := 26083.0
const TODAY_TOP_DEPTH := 90.0

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

func _bar() -> TopBar:
	return _main._top_bar


func _click(c: Control) -> void:
	if c == null:
		fail("the control to click is missing")
		return
	var vp := c.get_viewport()
	var at := c.get_global_rect().get_center()
	E2EBoot.motion_canvas(vp, at)
	E2EBoot.click_canvas(vp, at, true)
	E2EBoot.click_canvas(vp, at, false)
	await _runner.simulate_frames(3)


## The top strip's items by name.
func _items() -> Dictionary:
	var items := {"menu": _main.hamburger_button, "fps": _main.performance_label}
	items.merge(_bar().items())
	return items


## Every item missing, hidden or outside the top strip — [] when all there.
func _missing_items() -> Array:
	var strip := Rect2(0.0, 0.0, (_main.get_node("UI/HUD") as Control).size.x, TOP_STRIP)
	var missing: Array = []
	var items := _items()
	for k: String in ITEMS:
		var c: Control = items.get(k)
		if c == null or not is_instance_valid(c) or not c.is_visible_in_tree() or not strip.encloses(c.get_global_rect()):
			missing.append(k)
	return missing


## Area and depth of the painted top-strip items.
func _covered() -> Vector2:
	var area := 0.0
	var depth := 0.0
	for c: Control in _items().values():
		if c.is_visible_in_tree():
			area += c.get_global_rect().get_area()
			depth = maxf(depth, c.get_global_rect().end.y)
	return Vector2(area, depth)


# === tests ====================================================================================

func test_every_top_item_is_in_the_bar_and_none_overlaps(timeout := 120000) -> void:
	assert_array(_missing_items()).override_failure_message("missing from the top bar: %s" % str(_missing_items())).is_empty()
	var items := _items()
	var rail := (_main._tool_rail.get_node("Rail") as Control).get_global_rect()
	for a: String in ITEMS:
		var ra: Rect2 = (items[a] as Control).get_global_rect()
		assert_bool(ra.intersects(rail)).override_failure_message("%s %s lies on the tool rail" % [a, ra]).is_false()
		for b: String in ITEMS:
			if a < b:
				var rb: Rect2 = (items[b] as Control).get_global_rect()
				assert_bool(ra.intersects(rb)).override_failure_message("%s %s overlaps %s %s" % [a, ra, b, rb]).is_false()
	# "? Controls" moved out of the rail.
	assert_object(_main._tool_rail.find_child("Tool_help", true, false)).is_null()


func test_inventory_check_reports_a_removed_item(timeout := 120000) -> void:
	var controls: Control = _bar().items()["controls"]
	controls.visible = false
	assert_array(_missing_items()).contains(["controls"])
	controls.visible = true
	assert_array(_missing_items()).is_empty()


func test_the_menu_button_still_opens_the_menu(timeout := 120000) -> void:
	assert_bool(_main.left_panel_scroll.visible).is_false()
	await _click(_main.hamburger_button)
	await _runner.simulate_frames(10)
	assert_bool(_main.left_panel_scroll.visible).override_failure_message("☰ no longer opens the game menu").is_true()


func test_battle_log_opens_below_the_bar_and_closes_again(timeout := 120000) -> void:
	var log_panel: BattleLogPanel = _main.battle_log_panel
	var btn: Button = _bar().items()["log"]
	assert_bool(log_panel.is_visible_in_tree()).override_failure_message("the log shows before it is opened").is_false()
	await _click(btn)
	assert_bool(log_panel.is_open() and log_panel.is_visible_in_tree()).override_failure_message("Battle Log did not open the log").is_true()
	assert_bool(HouseStyle.is_selected(btn)).is_true()
	assert_float(log_panel.get_global_rect().position.y).override_failure_message("the log opens under the bar") \
		.is_greater_equal(btn.get_global_rect().end.y)
	# Its own header (▲) folds it away again; the bar button follows.
	await _click(log_panel.get("_header") as Button)
	assert_bool(log_panel.is_visible_in_tree()).is_false()
	assert_bool(HouseStyle.is_selected(btn)).is_false()
	await _click(btn)
	await _click(btn)
	assert_bool(log_panel.is_open() or log_panel.is_visible_in_tree()).is_false()


func test_round_and_phase_or_turn_are_shown(timeout := 120000) -> void:
	var round_chip: PanelContainer = _bar().items()["round"]
	var state: PanelContainer = _bar().items()["state"]
	var text := func(c: PanelContainer) -> String: return (c.get_node("Row/Text") as Label).text
	assert_str(text.call(round_chip)).is_equal("ROUND %d" % _main.opr_army_manager.current_round)
	assert_str(text.call(state)).is_equal("DEPLOYMENT")
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	await _runner.simulate_frames(2)
	assert_str(text.call(state)).is_equal("PLAYING")
	# Solo: whose turn it is (the AI's activation chain running = NACHTMAHR's turn).
	_main.solo_ai_slots = {2: true}
	await _runner.simulate_frames(2)
	assert_str(text.call(state)).is_equal("YOUR TURN")
	assert_str(String(state.theme_type_variation)).is_equal(String(HouseStyle.CHIP_TURN))
	_main._solo_ai_busy = true
	await _runner.simulate_frames(2)
	assert_str(text.call(state)).is_equal("NACHTMAHR'S TURN")
	assert_str(String(state.theme_type_variation)).is_equal(String(HouseStyle.CHIP_ENEMY))
	_main._solo_ai_busy = false
	_main.solo_ai_slots = {}
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.DEPLOYMENT
	await _runner.simulate_frames(2)


func test_next_round_runs_the_menus_next_round(timeout := 120000) -> void:
	var next: Button = _bar().items()["next"]
	# From the first frame the label names the round it moves ONTO (#161) — the menu showed the
	# scene's stale "Next Round (1)" until the first advance, and the bar mirrors the menu.
	assert_str(_main.next_round_btn.text).is_equal(_main.next_round_button_label(_main.opr_army_manager.current_round, false))
	assert_str(next.text).is_equal(_main.next_round_btn.text)
	var before: int = _main.opr_army_manager.current_round
	await _click(next)
	var dialog: ConfirmationDialog = _main._action_confirm_dialog
	assert_bool(dialog != null and dialog.visible).override_failure_message("Next Round did not ask as the menu's button does").is_true()
	assert_str(dialog.title).is_equal(_main.next_round_btn.text)
	dialog.confirmed.emit()
	dialog.hide()
	await _runner.simulate_frames(4)
	assert_int(_main.opr_army_manager.current_round).is_equal(before + 1)
	assert_str((_bar().items()["round"].get_node("Row/Text") as Label).text).is_equal("ROUND %d" % (before + 1))
	assert_str(next.text).is_equal(_main.next_round_btn.text)
	# The arrow in "Next Round → n" exists in the bar's font.
	assert_bool(next.get_theme_font(&"font").has_char("→".unicode_at(0))).override_failure_message("the bar font lacks →").is_true()


func test_controls_overlay_lists_every_binding_of_the_old_wall(timeout := 120000) -> void:
	var wall := _main.get_node("UI/HUD/InfoLabel") as Label
	assert_bool(wall.visible).override_failure_message("the always-on key wall should be gone from the table").is_false()
	var help: Button = _bar().items()["controls"]
	await _click(help)
	var overlay := _bar().overlay()
	assert_bool(overlay.is_open()).is_true()
	var shown: Array = []
	for r: Node in overlay.root.find_children("*", "HBoxContainer", true, false):
		if r.has_meta(&"keys"):
			shown.append(String(r.get_meta(&"keys")))
	for keys: String in WALL_TODAY:
		assert_bool(keys in shown).override_failure_message("'%s' is missing from the Controls overlay %s" % [keys, str(shown)]).is_true()
	# Every line of the list, not only the old ones, and the version line from the one source.
	assert_int(shown.size()).is_equal(ControlsOverlay.parse(wall.text).size())
	var version := overlay.root.find_child("Version", true, false) as Label
	assert_str(version.text).is_equal("Niemandsland v%s" % ProjectSettings.get_setting("application/config/version"))
	# Glyphs the overlay draws exist in its font.
	var font: Font = version.get_theme_font(&"font")
	for ch: String in ["×", "/", "…", "›"]:
		assert_bool(font.has_char(ch.unicode_at(0))).override_failure_message("font lacks " + ch).is_true()
	# Esc closes it; the × too.
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	_main.get_viewport().push_input(esc)
	await _runner.simulate_frames(2)
	assert_bool(overlay.is_open()).is_false()
	await _click(help)
	# The sheet fits the screen (a wrapping label once blew it up to ~4,800 px, × off screen).
	var sheet := overlay.root.find_child("Sheet", true, false) as Control
	assert_bool((_main.get_node("UI/HUD") as Control).get_global_rect().encloses(sheet.get_global_rect())) \
		.override_failure_message("the Controls sheet %s does not fit the screen" % sheet.get_global_rect()).is_true()
	await _click(overlay.root.find_child("CloseButton", true, false) as Button)
	assert_bool(overlay.is_open()).is_false()


func test_the_ruler_readout_stays_readable(timeout := 120000) -> void:
	_main._on_distance_changed(30.4, Vector3.ZERO, Vector3(0.772, 0.0, 0.0))
	await _runner.simulate_frames(2)
	var label: Label = _main.distance_label
	assert_str(label.text).is_equal("30.4\"")
	assert_bool(label.is_visible_in_tree()).is_true()
	var items := _items()
	for k: String in ITEMS:
		var r: Rect2 = (items[k] as Control).get_global_rect()
		assert_bool(label.get_global_rect().intersects(r)).override_failure_message("the ruler readout %s lies under %s %s" % [
			label.get_global_rect(), k, r]).is_false()
	_main.battle_log_panel.set_open(true)
	await _runner.simulate_frames(2)
	assert_bool(label.get_global_rect().intersects(_main.battle_log_panel.get_global_rect())).override_failure_message(
		"the ruler readout lies under the opened battle log").is_false()
	_main.battle_log_panel.set_open(false)


func test_the_bar_covers_no_more_than_todays_top_items(timeout := 120000) -> void:
	var now := _covered()
	assert_float(now.x).override_failure_message("top items cover %d px² > today's %d px²" % [now.x, TODAY_TOP_AREA]) \
		.is_less_equal(TODAY_TOP_AREA)
	assert_float(now.y).override_failure_message("the bar reaches %d px down, today's items %d" % [now.y, TODAY_TOP_DEPTH]) \
		.is_less_equal(TODAY_TOP_DEPTH)
	# The widest state the bar can show: a two-digit round, NACHTMAHR's turn, a two-digit Next Round.
	_bar().show_state(10, false, TopBar.Turn.OPPONENT)
	(_bar().items()["next"] as Button).text = "Next Round → 11"
	await _runner.simulate_frames(2)
	var widest := _covered()
	assert_float(widest.x).override_failure_message("the widest state covers %d px² > today's %d px²" % [widest.x, TODAY_TOP_AREA]) \
		.is_less_equal(TODAY_TOP_AREA)
	assert_array(_missing_items()).is_empty()
