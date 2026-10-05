extends GdUnitTestSuite
## E2E — the deployment / action strip, row 14 of the UI inventory (uiprompts step 4). ONE bottom strip
## with a status line and up to two buttons, raised from 12 call sites through _solo_deploy_ui_show and
## _solo_board_prompt (roll-off side pick, placement hand-over, reanimation, takedown pick, consolidation,
## split fire declared, ambush reserve, wound allocation). Pins TODAY's function set before the restyle:
## the controls are found by the words the player reads, the buttons get REAL clicks and fire their
## callback (the board prompt answers with the button's index), a dead callback says so and closes the
## strip, the drag hint is there, a real pointer drag on the strip moves it and the spot survives the
## next text, and a long foreign name wraps instead of stretching the strip. The drag clamp and the
## unit-dock clearance stay pinned by e2e_deploy_box_drag_test.
## test_the_inventory_check_names_a_removed_control proves the control check can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const SIDE_TEXT := "Roll-off 5:3 — YOU win and deploy first.\nWhich deployment zone do you take?"
const HINT := "•  drag to move"

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

func _strip() -> Node:
	return _main._solo_deploy_ui


func _shown() -> bool:
	return _strip() != null and is_instance_valid(_strip()) and (_strip() as CanvasLayer).visible


func _buttons() -> Array:
	var out: Array = []
	for n: Node in _strip().find_children("*", "Button", true, false):
		if (n as Button).is_visible_in_tree():
			out.append(n)
	return out


func _button(text: String) -> Button:
	for b: Button in _buttons():
		if b.text == text:
			return b
	fail("the strip has no button '%s' (it has %s)" % [text, _buttons().map(func(b: Button) -> String: return b.text)])
	return null


func _label(text: String) -> Label:
	for n: Node in _strip().find_children("*", "Label", true, false):
		if (n as Label).text == text and (n as Label).is_visible_in_tree():
			return n as Label
	return null


## Today's controls the strip no longer shows ("button: <text>" / "label: <text>"); empty = all there.
func _missing(buttons: Array, labels: Array = []) -> Array:
	var out: Array = []
	var have: Array = []
	for b: Button in _buttons():
		have.append(b.text)
	for t: Variant in buttons:
		if not have.has(str(t)):
			out.append("button: %s" % t)
	for t: Variant in labels:
		if _label(str(t)) == null:
			out.append("label: %s" % t)
	return out


## Shows the strip with the roll-off side pick's words and waits out the deferred relayout.
func _show_side_pick(hits: Array) -> void:
	_main._solo_deploy_ui_show(SIDE_TEXT, "Keep my zone", func() -> void: hits.append("keep"),
		"Take the other zone", func() -> void: hits.append("swap"))
	await _runner.simulate_frames(3)


## A real click at the centre of `c`; the pointer must be ON it (nothing covers the strip).
func _click(c: Control) -> void:
	if c == null:
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


# === the controls =============================================================================

## Status line, two buttons, the drag hint; each button fires its own callback.
func test_the_side_pick_shows_its_line_and_both_buttons_fire(timeout := 120000) -> void:
	var hits: Array = []
	await _show_side_pick(hits)
	assert_bool(_shown()).is_true()
	assert_array(_missing(["Keep my zone", "Take the other zone"], [SIDE_TEXT, HINT])).override_failure_message(
		"today's strip controls missing: %s" % [_missing(["Keep my zone", "Take the other zone"], [SIDE_TEXT, HINT])]) \
		.is_empty()
	await _click(_button("Take the other zone"))
	assert_array(hits).contains_exactly(["swap"])
	await _click(_button("Keep my zone"))
	assert_array(hits).contains_exactly(["swap", "keep"])


## One button: the second one is not shown at all.
func test_a_one_button_hand_over_hides_the_second(timeout := 120000) -> void:
	var hits: Array = []
	await _show_side_pick([])
	_main._solo_deploy_ui_show("Your turn: place Guards on your side, then hand over.\n(NACHTMAHR has 2 left.)",
		"Unit placed", func() -> void: hits.append("placed"))
	await _runner.simulate_frames(3)
	assert_array(_missing(["Unit placed"], [HINT])).is_empty()
	assert_int(_buttons().size()).override_failure_message("buttons shown: %s" % [_buttons()]).is_equal(1)
	await _click(_button("Unit placed"))
	assert_array(hits).contains_exactly(["placed"])


## A button whose action is gone says so in the log and closes the strip (never a hung game).
func test_a_dead_button_logs_and_closes_the_strip(timeout := 120000) -> void:
	_main._solo_deploy_ui_show("Deploy a unit", "OK", Callable())
	await _runner.simulate_frames(3)
	var n: int = _main.battle_log.entries().size()
	await _click(_button("OK"))
	var text := ""
	for e: Variant in _main.battle_log.entries().slice(n):
		text += str((e as Dictionary)["text"]) + "\n"
	assert_str(text).contains("Prompt button 1 has no action left — closing the prompt (please report this)")
	assert_bool(_shown()).is_false()


## The board prompt: the strip for questions answered by using the board; it answers with the index
## of the clicked button and hides again.
func test_the_board_prompt_answers_with_the_clicked_index(timeout := 120000) -> void:
	var out: Array = []
	(func() -> void: out.append(await _main._solo_board_prompt("Consolidate: drag the models, then confirm.",
		"Done", "Skip"))).call()
	await _runner.simulate_frames(3)
	assert_array(_missing(["Done", "Skip"], ["Consolidate: drag the models, then confirm."])).is_empty()
	await _click(_button("Skip"))
	await _runner.simulate_frames(2)
	assert_array(out).contains_exactly([1])
	assert_bool(_shown()).is_false()
	out.clear()
	(func() -> void: out.append(await _main._solo_board_prompt("Pick the model to take down.", "Recommended"))).call()
	await _runner.simulate_frames(3)
	await _click(_button("Recommended"))
	await _runner.simulate_frames(2)
	assert_array(out).contains_exactly([0])


## A real pointer drag on the strip's text moves it; the moved spot survives the next text.
func test_a_pointer_drag_moves_the_strip_and_the_spot_stays(timeout := 120000) -> void:
	await _show_side_pick([])
	var panel: Control = _main._solo_deploy_ui_panel
	var vp := _main.get_viewport()
	var before := panel.position
	var grab := _label(SIDE_TEXT).get_global_rect().get_center()
	var step := Vector2(-120, -200)
	E2EBoot.motion_canvas(vp, grab)
	E2EBoot.click_canvas(vp, grab, true)
	E2EBoot.motion_canvas(vp, grab + step, vp.get_screen_transform().basis_xform(step))
	E2EBoot.click_canvas(vp, grab + step, false)
	await _runner.simulate_frames(2)
	assert_float(panel.position.x).is_equal_approx(before.x + step.x, 2.0)
	assert_float(panel.position.y).is_equal_approx(before.y + step.y, 2.0)
	var moved := panel.position
	_main._solo_deploy_ui_show("NACHTMAHR is done — place your remaining units.\nThen close the phase.",
		"All placed", func() -> void: pass)
	await _runner.simulate_frames(3)
	assert_vector(panel.position).is_equal_approx(moved, Vector2(2, 2))


## Foreign unit names wrap (UI audit B-6): a very long name never stretches the strip off the screen.
func test_a_long_name_wraps_inside_the_screen(timeout := 120000) -> void:
	var long_name := "Grand Exalted Warlord of the Seventeen Burning Thrones and his Retinue of Sworn Blades"
	_main._solo_deploy_ui_show("Ambush — round 2: place ONE reserve unit from the tray (>9\" from enemies), then hand over.\nIn reserve: %s" % long_name,
		"Unit placed", func() -> void: pass, "Keep waiting", func() -> void: pass)
	await _runner.simulate_frames(3)
	var panel: Control = _main._solo_deploy_ui_panel
	var vp: Vector2 = _main.get_viewport().get_visible_rect().size
	assert_float(panel.size.x).override_failure_message("the strip is %d px wide on a %d px screen" % [
		panel.size.x, vp.x]).is_less(vp.x * 0.6)
	assert_bool(Rect2(Vector2.ZERO, vp).encloses(panel.get_global_rect())).is_true()


# === the house look (restyle) =================================================================

## The strip wears the house style alone: a house window (no HudTokens box, no corner brackets), the
## status line in body text, button 1 the gold primary, button 2 a ghost button, the hint a muted
## caption, no control with a colour, font size or tint of its own — and the glyphs the call sites put
## on the buttons are in the font they draw with.
func test_the_strip_wears_the_house_style(timeout := 120000) -> void:
	await _show_side_pick([])
	var panel: PanelContainer = _main._solo_deploy_ui_panel
	assert_object(panel.theme).is_same(HouseStyle.theme())
	assert_str(String(panel.theme_type_variation)).is_equal(String(HouseStyle.PANEL_VARIANT))
	assert_bool(panel.has_theme_stylebox_override(&"panel")).is_false()
	assert_object(panel.get_node_or_null("HudFrame")).override_failure_message("corner brackets").is_null()
	assert_str(String(_label(SIDE_TEXT).theme_type_variation)).is_equal(String(HouseStyle.BODY))
	assert_str(String(_button("Keep my zone").theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
	assert_str(String(_button("Take the other zone").theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	assert_str(String(_label(HINT).theme_type_variation)).is_equal(String(HouseStyle.CAPTION))
	var own: Array = []
	for n: Node in panel.find_children("*", "Control", true, false):
		var c := n as Control
		if c.has_theme_color_override(&"font_color") or c.has_theme_font_size_override(&"font_size") \
				or c.modulate != Color.WHITE:
			own.append(c.name)
	assert_array(own).override_failure_message("own colour / size / tint on %s" % [own]).is_empty()
	# The call sites' words.
	var font: Font = _button("Keep my zone").get_theme_font(&"font")
	var lacking: Array = []
	for t: String in ["✓ Unit placed", "✓ Done — close the phase", "Fire!", "× Cancel attack", "None this round — keep waiting"]:
		for i in t.length():
			if t[i] != " " and not font.has_char(t.unicode_at(i)):
				lacking.append("U+%04X in '%s'" % [t.unicode_at(i), t])
	assert_array(lacking).override_failure_message("the button font lacks %s" % [lacking]).is_empty()


# === the check itself =========================================================================

## The control check names a control that went missing (the second button hidden).
func test_the_inventory_check_names_a_removed_control(timeout := 120000) -> void:
	await _show_side_pick([])
	assert_array(_missing(["Keep my zone", "Take the other zone"], [HINT])).is_empty()
	_button("Take the other zone").hide()
	assert_array(_missing(["Keep my zone", "Take the other zone"], [HINT])) \
		.contains_exactly(["button: Take the other zone"])
