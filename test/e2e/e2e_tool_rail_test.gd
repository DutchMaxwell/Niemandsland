extends GdUnitTestSuite
## E2E — the tool rail (uirail, maintainer 23.09.: "Werkzeugleiste"; mockup LOOK, today's FULL function
## set). Dice / Measure / Terrain / View in one rail, exactly one panel open, the always-on key wall
## replaced by "? Controls". Every function the table has today for measuring, viewing and terrain is
## found in its panel, is reachable by a REAL click, and does what the key or menu button does today:
## a clickable key cap presses that very key; a Terrain line runs Main's own menu handler.
## test_inventory_check_reports_a_removed_control proves the presence check can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

## [tool, the line's name, clickable key caps, hint caps] — today's functions per panel.
const INVENTORY := [
	[&"measure", "Ruler", [], ["Shift", "drag"]],
	[&"measure", "Pin ruler (while measuring)", [], ["P"]],
	[&"measure", "Remove one ruler", [], ["Right-click it"]],
	[&"measure", "Clear rulers", ["K", "Shift+K"], []],
	[&"measure", "Move bands", ["M", "Shift+M"], []],
	[&"view", "Range ring", ["G", "Shift+G"], []],
	[&"view", "Sight / range fan", ["F"], []],
	[&"view", "Regiment frontage", ["Shift+F"], []],
	[&"view", "Move trails", ["T", "Shift+T"], []],
	[&"view", "Rotate to cursor", [], ["R", "hold"]],
	[&"view", "Rotate group", [], ["Shift", "R", "hold"]],
	[&"terrain", "Lock / unlock a piece", [], ["L"]],
]
## Terrain's menu actions (buttons that run Main's own handlers).
const TERRAIN_ACTIONS := ["Map layout…", "Terrain mode", "Clear table…", "Sort table…",
	"Show deployment zones", "Flip zone colours"]

## The always-on key wall as it stood on main (96af498a, scenes/main.tscn UI/HUD/InfoLabel) — every
## binding's keys must be in the Controls overlay.
const WALL_TODAY := ["WASD", "Q/E", "Scroll", "Left Click", "Alt + Click", "Shift + Click", "R (hold)",
	"Shift+R", "1-9", "Shift+A", "Ctrl+C/V/D", "L", "G / Shift+G", "F / Shift+F", "M / Shift+M", "P",
	"K / Shift+K", "T / Shift+T"]

## Today's dice panel on main at rest (1920x1080 base): 420 x 702. Rail + an open panel may not cover more.
const TODAY_DICE_AREA := 420.0 * 702.0

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

func _rail() -> ToolRail:
	return _main._tool_rail


func _click(c: Control) -> void:
	if c == null:
		fail("the control to click is missing")
		return
	var vp := c.get_viewport()
	var at := c.get_global_rect().get_center()
	E2EBoot.motion_canvas(vp, at)
	E2EBoot.click_canvas(vp, at, true)
	E2EBoot.click_canvas(vp, at, false)
	await _runner.simulate_frames(3)   # a key cap's key press runs deferred


## The tool line named `text` in `tool`'s panel (its first BODY label), or null.
func _line(tool: StringName, text: String) -> PanelContainer:
	for n: Node in _rail().panel(tool).find_children("*", "PanelContainer", true, false):
		var p := n as PanelContainer
		if p.theme_type_variation != HouseStyle.TOOL_LINE:
			continue
		for l: Node in p.find_children("*", "Label", true, false):
			if (l as Label).theme_type_variation == HouseStyle.BODY and (l as Label).text == text:
				return p
	return null


func _cap(line: Control, text: String, clickable: bool) -> Control:
	if line == null:
		return null
	for n: Node in line.find_children("*", "", true, false):
		if clickable and n is Button and (n as Button).text == text:
			return n as Control
		if not clickable and n is Label and (n as Label).theme_type_variation == HouseStyle.KEYCAP and (n as Label).text == text:
			return n as Control
	return null


func _action(text: String) -> Button:
	for n: Node in _rail().panel(&"terrain").find_children("*", "Button", true, false):
		if (n as Button).text == text:
			return n as Button
	return null


## Every inventory control missing or not inside its panel when that panel is open — [] when all there.
func _missing_controls() -> Array:
	var missing: Array = []
	for tool: StringName in [&"measure", &"view", &"terrain"]:
		_rail().set_open(tool, true)
		var box := _rail().panel(tool).get_global_rect().grow(1.0)
		for entry: Array in INVENTORY:
			if entry[0] != tool:
				continue
			var line := _line(tool, entry[1])
			if line == null or not line.is_visible_in_tree() or not box.encloses(line.get_global_rect()):
				missing.append("%s: %s" % [tool, entry[1]])
				continue
			for k: String in entry[2]:
				if _cap(line, k, true) == null:
					missing.append("%s: %s [%s]" % [tool, entry[1], k])
			for k: String in entry[3]:
				if _cap(line, k, false) == null:
					missing.append("%s: %s (%s)" % [tool, entry[1], k])
		if tool == &"terrain":
			for text: String in TERRAIN_ACTIONS:
				var b := _action(text)
				if b == null or not b.is_visible_in_tree() or not box.encloses(b.get_global_rect()):
					missing.append("terrain: " + text)
	_rail().set_open(&"dice", true)
	return missing


## Two plain models of one unit, in the "miniature" group and selected.
func _select_a_unit() -> Array:
	var u := E2EBoot.make_unit(_main, 1, "railunit", [Vector3(0.1, 0.0, 0.1), Vector3(0.14, 0.0, 0.1)])
	var nodes: Array = []
	for m in u.models:
		var n: Node3D = (m as ModelInstance).node
		n.add_to_group("miniature")
		nodes.append(n)
	_main.object_manager.select_objects(nodes)
	return nodes


# === tests ====================================================================================

func test_the_rail_has_four_tools_and_opens_exactly_one(timeout := 120000) -> void:
	var rail := _rail()
	assert_object(rail).is_not_null()
	assert_that(rail.active_tool()).is_equal(&"dice")   # the dice window opens as it always stood open
	for tool: StringName in [&"measure", &"terrain", &"view", &"dice"]:   # dice last: it starts open
		var b := rail.button(tool)
		assert_bool(b.is_visible_in_tree()).override_failure_message("rail button %s" % tool).is_true()
		await _click(b)
		assert_that(rail.active_tool()).is_equal(tool)
		for other: StringName in ToolRail.TOOLS:
			assert_bool(rail.panel(other).visible).override_failure_message("%s open with %s" % [other, tool]) \
				.is_equal(other == tool)
			assert_bool(HouseStyle.is_selected(rail.button(other))).is_equal(other == tool)
		# The panel sits beside the rail, not over it.
		assert_bool(rail.panel(tool).get_global_rect().intersects(b.get_global_rect())).is_false()
	# A click on the open tool closes it; the × of a panel too.
	await _click(rail.button(&"dice"))
	assert_that(rail.active_tool()).is_equal(&"")
	await _click(rail.button(&"measure"))
	await _click(rail.panel(&"measure").find_child("CloseButton", true, false) as Button)
	assert_that(rail.active_tool()).is_equal(&"")
	for tool: StringName in ToolRail.TOOLS:
		assert_bool(rail.panel(tool).visible).is_false()


func test_every_measure_view_and_terrain_function_is_in_its_panel(timeout := 120000) -> void:
	assert_array(_missing_controls()).override_failure_message(
		"today's functions missing in the rail panels: %s" % str(_missing_controls())).is_empty()


func test_inventory_check_reports_a_removed_control(timeout := 120000) -> void:
	assert_array(_missing_controls()).is_empty()
	var cap := _cap(_line(&"view", "Range ring"), "Shift+G", true)
	if cap == null:
		fail("the Shift+G cap to remove is missing already")
		return
	cap.get_parent().remove_child(cap)
	cap.free()
	assert_array(_missing_controls()).contains_exactly(["view: Range ring [Shift+G]"])


func test_measure_keys_do_what_the_keyboard_does(timeout := 120000) -> void:
	var rail := _rail()
	await _click(rail.button(&"measure"))
	var rulers: Node = _main.pinned_rulers
	rulers.add_ruler(9001, 1, Vector3(0, 0, 0), Vector3(0.3, 0, 0), 11.8, false)
	rulers.add_ruler(9002, 1, Vector3(0, 0, 0.1), Vector3(0.3, 0, 0.1), 11.8, false)
	rulers.add_ruler(9003, 2, Vector3(0, 0, 0.2), Vector3(0.3, 0, 0.2), 11.8, false)
	var line := _line(&"measure", "Clear rulers")
	await _click(_cap(line, "K", true))
	assert_int(rulers.ruler_count()).override_failure_message("K should clear only my two rulers").is_equal(1)
	await _click(_cap(line, "Shift+K", true))
	assert_int(rulers.ruler_count()).override_failure_message("Shift+K should clear every ruler").is_equal(0)

	_select_a_unit()
	var bands: Node = _main.movement_range_controller
	line = _line(&"measure", "Move bands")
	await _click(_cap(line, "M", true))
	assert_int(bands.active_count()).override_failure_message("M should show the selected unit's bands").is_greater(0)
	await _click(_cap(line, "Shift+M", true))
	assert_int(bands.active_count()).is_equal(0)
	await E2EBoot.settle(get_tree())


func test_view_keys_do_what_the_keyboard_does(timeout := 120000) -> void:
	var rail := _rail()
	await _click(rail.button(&"view"))
	_select_a_unit()
	var rings: Node = _main.range_ring_controller
	var line := _line(&"view", "Range ring")
	await _click(_cap(line, "G", true))
	assert_int(rings.active_count()).override_failure_message("G should ring the selected unit").is_greater(0)
	await _click(_cap(line, "Shift+G", true))
	assert_int(rings.active_count()).is_equal(0)

	# F with nothing selected toggles the regiment arcs — the keyboard's own branch in Main.
	_main.object_manager.select_objects([])
	var arcs_before: bool = _main.opr_army_manager._regiment_arcs_visible
	await _click(_cap(_line(&"view", "Sight / range fan"), "F", true))
	assert_bool(_main.opr_army_manager._regiment_arcs_visible).is_equal(not arcs_before)

	var trails: Node = _main.move_trails
	var shown_before: bool = trails.user_show_trails
	line = _line(&"view", "Move trails")
	await _click(_cap(line, "T", true))
	assert_bool(trails.user_show_trails).is_equal(not shown_before)
	await _click(_cap(line, "T", true))
	assert_bool(trails.user_show_trails).is_equal(shown_before)   # back as the user had it
	trails.set_deployment_active(false)
	trails.set_user_show_trails(true)
	trails.commit_trail(1, "railunit", "Rail Unit", 1, PackedVector2Array([Vector2.ZERO, Vector2(0.2, 0.0)]),
		0.02, 1, 1)
	assert_int(trails._trails.size()).override_failure_message("no trail to clear — the check proves nothing").is_greater(0)
	await _click(_cap(line, "Shift+T", true))
	assert_int(trails._trails.size()).is_equal(0)
	trails.set_user_show_trails(shown_before)
	await E2EBoot.settle(get_tree())


func test_terrain_lines_run_the_menus_own_handlers(timeout := 120000) -> void:
	var rail := _rail()
	await _click(rail.button(&"terrain"))
	var om: Node = _main.object_manager

	var mode := _action("Terrain mode")
	await _click(mode)
	assert_bool(om.is_terrain_edit_mode()).is_true()
	assert_bool((_main._terrain_mode_btn as BaseButton).button_pressed).is_true()
	assert_bool(HouseStyle.is_selected(mode)).is_true()
	assert_str((mode.get_node("Trailing") as Label).text).is_equal("On")
	await _click(mode)
	assert_bool(om.is_terrain_edit_mode()).is_false()
	assert_bool(HouseStyle.is_selected(mode)).is_false()
	assert_str((mode.get_node("Trailing") as Label).text).is_equal("Off")

	var zones := _action("Show deployment zones")
	var before: bool = (_main.deployment_zone_check as BaseButton).button_pressed
	await _click(zones)
	assert_bool((_main.deployment_zone_check as BaseButton).button_pressed).is_equal(not before)
	assert_bool(_main.terrain_overlay.deployment_zones_visible).is_equal(not before)
	assert_bool(HouseStyle.is_selected(zones)).is_equal(not before)
	var flip := _action("Flip zone colours")
	var flipped: bool = _main.terrain_overlay.deployment_colors_flipped
	await _click(flip)
	assert_bool(_main.terrain_overlay.deployment_colors_flipped).is_equal(not flipped)

	await _click(_action("Clear table…"))
	var confirm: ConfirmationDialog = _main._action_confirm_dialog
	assert_bool(confirm != null and confirm.visible and confirm.title == "Clear Table").is_true()
	confirm.hide()
	await _click(_action("Sort table…"))
	assert_bool(confirm.visible and confirm.title == "Sort Table").is_true()
	confirm.hide()

	await _click(_action("Map layout…"))
	assert_bool(_main.map_layout_editor.visible).is_true()
	assert_bool((_main.get_node("UI/HUD") as Control).visible).is_false()
	_main.map_layout_editor.layout_closed.emit()
	await _runner.simulate_frames(2)
	assert_bool((_main.get_node("UI/HUD") as Control).visible).is_true()
	await E2EBoot.settle(get_tree())


func test_keyboard_shortcuts_are_unchanged(timeout := 120000) -> void:
	_select_a_unit()
	var vp: Viewport = _main.get_viewport()
	for keycode: Key in [KEY_G, KEY_M]:
		for pressed: bool in [true, false]:
			var ev := InputEventKey.new()
			ev.keycode = keycode
			ev.physical_keycode = keycode
			ev.pressed = pressed
			vp.push_input(ev)
		await _runner.simulate_frames(2)
	assert_int(_main.range_ring_controller.active_count()).override_failure_message("G on the keyboard").is_greater(0)
	assert_int(_main.movement_range_controller.active_count()).override_failure_message("M on the keyboard").is_greater(0)
	await E2EBoot.settle(get_tree())


func test_controls_overlay_lists_every_binding_of_the_old_wall(timeout := 120000) -> void:
	var wall := _main.get_node("UI/HUD/InfoLabel") as Label
	assert_bool(wall.visible).override_failure_message("the always-on key wall should be gone from the table").is_false()
	await _click(_rail().help_button())
	var overlay := _rail().overlay()
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
	await _click(_rail().help_button())
	# The sheet fits the screen (a wrapping label once blew it up to ~4,800 px, × off screen).
	var sheet := overlay.root.find_child("Sheet", true, false) as Control
	assert_bool((_main.get_node("UI/HUD") as Control).get_global_rect().encloses(sheet.get_global_rect())) \
		.override_failure_message("the Controls sheet %s does not fit the screen" % sheet.get_global_rect()).is_true()
	await _click(overlay.root.find_child("CloseButton", true, false) as Button)
	assert_bool(overlay.is_open()).is_false()


func test_rail_and_an_open_panel_cover_no_more_than_todays_dice_panel(timeout := 120000) -> void:
	var rail := _rail()
	var rail_rect := (rail.get_node("Rail") as Control).get_global_rect()
	for tool: StringName in ToolRail.TOOLS:
		rail.set_open(tool, true)
		await _runner.simulate_frames(2)
		var p := rail.panel(tool).get_global_rect()
		var covered := rail_rect.get_area() + p.get_area()
		assert_float(covered).override_failure_message("%s: rail %s + panel %s = %d px² > today's dice panel %d px²" % [
			tool, rail_rect.size, p.size, covered, TODAY_DICE_AREA]).is_less_equal(TODAY_DICE_AREA)
	rail.set_open(&"dice", true)
