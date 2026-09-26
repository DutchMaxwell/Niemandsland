extends GdUnitTestSuite
## E2E — the click that OPENS a dropdown in the ☰ menu never picks an entry (board N15, player-facing: the
## Mission picker jumped from Duel to entry 3 on a plain click). The mouse release that ends the opening
## click lands wherever the button is; when the engine placed the list over the button, that is on an entry.
## Two ways the list ends up over the button, both covered: the button sits so low that the list does not fit
## below it (Mission, grade picker: scrolled to the bottom of the column), and a window smaller than the
## design size, where the engine opens the list inside the button's lower part (Graphics, in its usual place).
## Mission, grade picker and Graphics are each opened with a real press + release at the top, middle and
## bottom of the button, held 0 ms and 200 ms.
##
## Real: scenes/main.tscn, its real menu column, the real dropdowns and their popups. Constructed: two
## imported armies and the AI seat, so the solo section shows (the way the other menu suites do).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

## Where in the button the click lands, as a fraction of its height: top, middle, bottom.
const CLICK_AT := [0.15, 0.5, 0.85]
## How long the button stays pressed (wall time): a synthetic tap, and a slow human click.
const HOLD_MS := [0, 200]

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


func _scroll() -> ScrollContainer:
	return _main.left_panel_scroll


## The menu open with the solo section (two armies, the AI on P2), as a player who imported both armies sees it.
func _open_menu_with_solo() -> void:
	_main.opr_army_manager.armies = {1: null, 2: null}
	_main.solo_ai_slots = {2: true}
	_main._refresh_solo_panel()
	await _runner.simulate_frames(5)
	_main._on_hamburger_pressed()
	await get_tree().create_timer(0.35).timeout
	await _runner.simulate_frames(2)


func _grade_option() -> OptionButton:
	for c in _main.solo_panel_box.get_children():
		if c is OptionButton and (c as OptionButton).item_count > 0 and str((c as OptionButton).get_item_metadata(0)) == "daemmerung":
			return c
	return null


## Scrolls the menu until `c` sits as low on the screen as it can (its bottom at the window's bottom edge).
func _place_low(c: Control) -> void:
	_scroll().ensure_control_visible(c)
	await _runner.simulate_frames(2)
	var bottom := c.get_viewport().get_visible_rect().size.y - 4.0
	_scroll().scroll_vertical += int(c.get_global_rect().end.y - bottom)
	await _runner.simulate_frames(3)


## A real press at `at`, `hold_ms` of wall time, a real release at the same spot.
func _tap(vp: Viewport, at: Vector2, hold_ms: int) -> void:
	E2EBoot.motion_canvas(vp, at)
	await _runner.simulate_frames(2)
	E2EBoot.click_canvas(vp, at, true)
	if hold_ms > 0:
		await get_tree().create_timer(hold_ms / 1000.0).timeout
	await _runner.simulate_frames(2)
	E2EBoot.click_canvas(vp, at, false)
	await _runner.simulate_frames(3)


## Opens `opt` with every click point and hold time: the list opens, stays open, and nothing is picked.
func _opening_clicks_pick_nothing(opt: OptionButton, what: String) -> void:
	assert_object(opt).override_failure_message("%s: the dropdown is missing" % what).is_not_null()
	if opt == null:
		return
	var popup := opt.get_popup()
	opt.select(0)   # OptionButton emits item_selected only for a NEW entry: start on the first, so a pick anywhere else shows
	var before := opt.selected
	for frac: float in CLICK_AT:
		for hold: int in HOLD_MS:
			var r := opt.get_global_rect()
			var case := "%s, click %d%% down the button, held %d ms" % [what, int(frac * 100.0), hold]
			var picked: Array = []
			var on_pick := func(i: int) -> void: picked.append(i)
			opt.item_selected.connect(on_pick)
			await _tap(opt.get_viewport(), Vector2(r.get_center().x, r.position.y + r.size.y * frac), hold)
			var open := popup.visible
			opt.item_selected.disconnect(on_pick)
			assert_array(picked).override_failure_message("%s: the release of the opening click picked entry %s" % [case, picked]).is_empty()
			assert_int(opt.selected).override_failure_message("%s: the selection moved %d -> %d" % [case, before, opt.selected]).is_equal(before)
			assert_bool(open).override_failure_message("%s: the list is not open after the click" % case).is_true()
			popup.hide()
			opt.select(before)
			await _runner.simulate_frames(2)


## The moved list is still a working list: a second click in its middle picks that entry and closes it.
func _the_list_still_takes_a_pick(opt: OptionButton, what: String) -> void:
	var popup := opt.get_popup()
	var r := opt.get_global_rect()
	opt.select(0)   # the middle entry is then a new entry, which is what makes OptionButton emit item_selected
	await _tap(opt.get_viewport(), r.get_center(), 0)
	if not is_instance_valid(popup) or not popup.visible:   # (a pick on the opening click can rebuild the panel)
		fail("%s: the opening click did not leave the list open" % what)
		return
	var picked: Array = []
	opt.item_selected.connect(func(i: int) -> void: picked.append(i))
	await _tap(opt.get_viewport(), Vector2(popup.position) + Vector2(popup.size) / 2.0, 0)
	assert_int(picked.size()).override_failure_message("%s: a click in the middle of the list picked %s" % [what, picked]).is_equal(1)
	# A pick may rebuild the panel and free the dropdown with its list; either way the list is gone.
	assert_bool(not is_instance_valid(popup) or not popup.visible).override_failure_message("%s: the list stayed open after a pick" % what).is_true()


## The button sits so low that its list cannot fit below it (the precondition of the low-dropdown cases).
func _assert_sits_low(opt: OptionButton, what: String) -> void:
	await _place_low(opt)
	var room := opt.get_viewport().get_visible_rect().size.y
	opt.show_popup()   # only to read the list's height; the cases below open it with real clicks
	var need := opt.get_global_rect().end.y + opt.get_popup().size.y
	opt.get_popup().hide()
	assert_float(need).override_failure_message("%s does not sit low: its list would fit below (%.0f <= %.0f)" % [what, need, room]).is_greater(room)


func test_mission_dropdown_low_in_the_menu_picks_nothing_on_the_opening_click(timeout := 180000) -> void:
	await _open_menu_with_solo()
	await _assert_sits_low(_main.solo_mission_option, "Mission")
	await _opening_clicks_pick_nothing(_main.solo_mission_option, "Mission")


func test_grade_picker_low_in_the_menu_picks_nothing_on_the_opening_click(timeout := 180000) -> void:
	await _open_menu_with_solo()
	await _assert_sits_low(_grade_option(), "Grade picker")
	await _opening_clicks_pick_nothing(_grade_option(), "Grade picker")


func test_graphics_dropdown_picks_nothing_on_the_opening_click(timeout := 180000) -> void:
	await _open_menu_with_solo()
	await _opening_clicks_pick_nothing(_main.graphics_quality_option, "Graphics")


## A list taller than the room above AND below the button opens beside it (a catalogue that outgrows the
## screen): Graphics with 20 filler entries, so its list fills the window.
func test_a_list_that_fits_neither_above_nor_below_opens_beside_the_button(timeout := 180000) -> void:
	await _open_menu_with_solo()
	var opt: OptionButton = _main.graphics_quality_option
	for i in 20:
		opt.add_item("Filler entry %d" % i)
	await _runner.simulate_frames(2)
	await _opening_clicks_pick_nothing(opt, "Graphics with 25 entries")


func test_the_list_of_a_low_dropdown_still_takes_a_pick(timeout := 180000) -> void:
	await _open_menu_with_solo()
	await _place_low(_main.solo_mission_option)
	await _the_list_still_takes_a_pick(_main.solo_mission_option, "Mission")


func test_the_list_of_graphics_still_takes_a_pick(timeout := 180000) -> void:
	await _open_menu_with_solo()
	await _the_list_still_takes_a_pick(_main.graphics_quality_option, "Graphics")
