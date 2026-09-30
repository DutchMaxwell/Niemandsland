extends GdUnitTestSuite
## E2E — the AI's voice, rows 12, 13 and 15 of the UI inventory (uiprompts step 5): the top status lanes
## (the "NACHTMAHR is taking its turn…" banner, the action toast and the sticky AI explanation, the plain
## fading toast, the peer-loading banner), the centred "NACHTMAHR dreams…" overlay, and the Combat Stage
## card. Pins TODAY's function set before the restyle: every piece is raised by the function that raises
## it in play and found by its words (the stage's buttons by their tooltips — their glyphs are not the
## house font's), clickable parts get REAL clicks, and each does what it does today: the lanes stack top-
## centre and never take the mouse, a plain toast fades, a newer toast is never blanked by an older timer,
## an explanation sticks and a click on it dismisses it AND reaches the table (#364), the dream overlay
## breathes and lets every click through, the stage holds a phase, pauses (button and SPACE), browses the
## running activation, advances on a click and fades after the activation.
## test_the_inventory_check_names_a_removed_control proves the control check can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const PREV_TIP := "Previous phase of this activation"
const PAUSE_TIP := "Pause the beat to read (SPACE)"
const NEXT_TIP := "Next phase / back to live"
const STAGE_HINT := "click = next · SPACE = pause · drag to move"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _explain_before: bool
var _spy: Node = null


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_explain_before = GraphicsSettings.ai_explain_persistent
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	GraphicsSettings.ai_explain_persistent = _explain_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_spy = null
	_main = null
	_runner = null


# === helpers ==================================================================================

func _vp_size() -> Vector2:
	return _main.get_viewport().get_visible_rect().size


## A Label under the HUD that shows `text` now (the plain toast has no handle of its own).
func _ui_label(text: String) -> Label:
	for n: Node in _main.get_node("UI").find_children("*", "Label", true, false):
		if (n as Label).text == text and (n as Label).is_visible_in_tree() and not n.is_queued_for_deletion():
			return n as Label
	return null


## Counts left presses that reach the unhandled-input stage — i.e. the table's pick. Added last under
## /root, so it sees every unhandled event first and consumes none.
func _arm_spy() -> Node:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar presses := 0\nfunc _unhandled_input(e: InputEvent) -> void:\n" \
		+ "\tif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:\n\t\tpresses += 1\n"
	s.reload()
	_spy = Node.new()
	_spy.set_script(s)
	get_tree().root.add_child(_spy)
	return _spy


func _press_at(at: Vector2) -> void:
	var vp := _main.get_viewport()
	E2EBoot.motion_canvas(vp, at)
	E2EBoot.click_canvas(vp, at, true)
	E2EBoot.click_canvas(vp, at, false)
	await _runner.simulate_frames(3)


## A real click at the centre of `c`; the pointer must be ON it.
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


func _key(code: Key) -> void:
	var vp := _main.get_viewport()
	for down: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		vp.push_input(ev)
	await _runner.simulate_frames(2)


func _stage() -> CombatStage:
	return _main.combat_stage


func _card() -> Control:
	return _stage().find_child("CombatStageCard", true, false) as Control


func _stage_button(tip: String) -> Button:
	if _card() == null:
		return null
	for n: Node in _card().find_children("*", "Button", true, false):
		if (n as Button).tooltip_text == tip and (n as Button).is_visible_in_tree():
			return n as Button
	return null


func _stage_text() -> String:
	var text := ""
	for n: Node in _card().find_children("*", "Label", true, false):
		text += (n as Label).text + "\n"
	return text


## Today's stage controls the card no longer shows ("button: <tooltip>" / "hint"); empty = all there.
func _stage_missing() -> Array:
	var out: Array = []
	for tip: String in [PREV_TIP, PAUSE_TIP, NEXT_TIP]:
		if _stage_button(tip) == null:
			out.append("button: %s" % tip)
	if not _stage_text().contains(STAGE_HINT):
		out.append("hint: %s" % STAGE_HINT)
	return out


## Opens an activation on the forced stage and closes one phase card, which then HOLDS; `held` gets a
## 1 once the hold ends.
func _stage_phase(title: String, lines: Array, held: Array) -> void:
	for l: Variant in lines:
		_stage().collect(str(l))
	(func() -> void:
		await _stage().phase(title)
		held.append(1)).call()
	await _runner.simulate_frames(3)


func _open_stage() -> void:
	_stage().force_for_tests = true
	_stage().hold_s = 60.0
	_stage().activation_begin("Raiders shoot Guards")


# === row 12: the status lanes =================================================================

## The AI-turn banner, the action toast and the peer-loading banner stack at the top in that order (the
## action toast centred), and none of them takes the mouse.
func test_the_three_status_lanes_stack_top_centre(timeout := 120000) -> void:
	_main._show_solo_ai_banner()
	_main._solo_show_toast("Raiders advance 6\"", 0.0)
	_main._on_session_busy_changed(true)
	await _runner.simulate_frames(3)
	var banner: Label = _main._solo_ai_banner
	var toast: Label = _main._solo_toast
	var peer: Label = _main._peer_busy_banner
	assert_str(banner.text).is_equal("NACHTMAHR is taking its turn…")
	assert_str(toast.text).is_equal("Raiders advance 6\"")
	assert_str(peer.text).is_equal("Waiting for another player to finish loading…")
	assert_float(toast.get_global_rect().get_center().x).is_equal_approx(_vp_size().x * 0.5, 2.0)
	for l: Label in [banner, toast, peer]:
		assert_float(l.global_position.y).is_less(200.0)
		assert_int(l.mouse_filter).override_failure_message("'%s' takes the mouse" % l.text) \
			.is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_float(banner.global_position.y).is_less(toast.global_position.y)
	assert_float(toast.global_position.y).is_less(peer.global_position.y)
	_main._hide_solo_ai_banner()
	_main._on_session_busy_changed(false)
	await _runner.simulate_frames(2)
	assert_bool(is_instance_valid(_main._solo_ai_banner) and _main._solo_ai_banner.is_visible_in_tree()).is_false()
	assert_object(_main._peer_busy_banner).is_null()


## A plain notice fades on its own; a newer toast is never blanked by the older one's timer.
func test_a_toast_fades_and_a_newer_one_survives_the_old_timer(timeout := 120000) -> void:
	_main._solo_show_toast("Autosaved", 0.3)
	await _runner.simulate_frames(2)
	assert_bool(_main._solo_toast.visible).is_true()
	await get_tree().create_timer(0.6).timeout
	assert_bool(_main._solo_toast.visible).override_failure_message("the notice never faded").is_false()
	_main._solo_show_toast("Old notice", 0.3)
	_main._solo_show_toast("New notice", 5.0)
	await get_tree().create_timer(0.6).timeout
	assert_bool(_main._solo_toast.visible).override_failure_message("the old timer blanked the new toast").is_true()
	assert_str(_main._solo_toast.text).is_equal("New notice")


## NML-955 / #364: an AI explanation sticks (a phase-boundary clear leaves it), a click on it dismisses
## it — and the same click still reaches the table underneath.
func test_an_explanation_sticks_and_a_click_dismisses_it_and_reaches_the_table(timeout := 120000) -> void:
	GraphicsSettings.ai_explain_persistent = true
	_main._solo_show_explain("Raiders: 4 hits → 2 wounds land — Guards lose 1 model")
	await _runner.simulate_frames(3)
	var toast: Label = _main._solo_toast
	assert_bool(toast.visible).is_true()
	assert_str(toast.tooltip_text).is_equal("NACHTMAHR's reasoning — click to dismiss")
	_main._solo_hide_toast()
	assert_bool(toast.visible).override_failure_message("a plain clear took the explanation down").is_true()
	var spy := _arm_spy()
	await _click(toast)
	assert_bool(toast.visible).override_failure_message("the click did not dismiss the explanation").is_false()
	assert_int(spy.get("presses")).override_failure_message("the dismissing click never reached the table") \
		.is_equal(1)


## The plain fading toast (room code copied, bug report saved): at the top, gone after about 3.7 s.
func test_the_plain_toast_fades_out_and_leaves(timeout := 120000) -> void:
	_main._show_toast("Room code copied")
	await _runner.simulate_frames(2)
	var l := _ui_label("Room code copied")
	assert_object(l).is_not_null()
	assert_float(l.global_position.y).is_less(200.0)
	await get_tree().create_timer(4.2).timeout
	assert_object(_ui_label("Room code copied")).override_failure_message("the toast never left").is_null()


# === row 13: the dream overlay ================================================================

## Centred spinner + words while the AI computes; it breathes, lets every click through, and a batch
## sweep never shows it.
func test_the_dream_overlay_breathes_centred_and_lets_clicks_through(timeout := 120000) -> void:
	_main._solo_batch = true
	_main._show_dream_overlay()
	assert_object(_main._solo_dream_overlay).override_failure_message("a batch sweep showed the overlay").is_null()
	_main._solo_batch = false
	_main._show_dream_overlay()
	await _runner.simulate_frames(3)
	var overlay: Control = _main._solo_dream_overlay
	assert_object(_ui_label("NACHTMAHR dreams…")).is_not_null()
	assert_int(overlay.find_children("*", "DreamSpinner", true, false).size()).is_equal(1)
	var panel := overlay.find_children("*", "PanelContainer", true, false)[0] as Control
	assert_vector(panel.get_global_rect().get_center()).is_equal_approx(_vp_size() * 0.5, Vector2(2, 2))
	var grabbing: Array = []
	for n: Node in [overlay] + overlay.find_children("*", "Control", true, false):
		if (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			grabbing.append(n.name)
	assert_array(grabbing).override_failure_message("these take the mouse: %s" % [grabbing]).is_empty()
	var spy := _arm_spy()
	await _press_at(panel.get_global_rect().get_center())
	assert_int(spy.get("presses")).override_failure_message("a click on the overlay missed the table").is_equal(1)
	var alphas: Array = []
	for _i in 8:
		await get_tree().create_timer(0.12).timeout
		alphas.append(overlay.modulate.a)
	assert_float(alphas.min()).override_failure_message("no breathing: %s" % [alphas]).is_less(0.95)
	_main._hide_dream_overlay()
	await _runner.simulate_frames(2)
	assert_object(_ui_label("NACHTMAHR dreams…")).is_null()


# === row 15: the Combat Stage =================================================================

## The card: headline, phase title with its count, the rule lines, ◂ / ⏸ / ▸ and the hint; top-centre
## under the turn banner. Pause (button and SPACE) holds the beat; a click on the card advances.
func test_the_stage_card_holds_pauses_and_advances(timeout := 120000) -> void:
	_open_stage()
	var held: Array = []
	await _stage_phase("To hit", ["Rifle: 3 hits"], held)
	var card := _card()
	assert_bool(card != null and card.is_visible_in_tree()).is_true()
	assert_array(_stage_missing()).override_failure_message("today's stage controls missing: %s" % [
		_stage_missing()]).is_empty()
	assert_str(_stage_text()).contains("Raiders shoot Guards")
	assert_str(_stage_text()).contains("To hit  (1/1)")
	assert_str(_stage_text()).contains("· Rifle: 3 hits")
	assert_float(card.get_global_rect().get_center().x).is_equal_approx(_vp_size().x * 0.5, 2.0)
	assert_float(card.global_position.y).is_equal_approx(64.0, 1.0)
	await _key(KEY_SPACE)
	assert_bool(_stage()._paused).override_failure_message("SPACE did not pause").is_true()
	await _key(KEY_SPACE)
	assert_bool(_stage()._paused).override_failure_message("SPACE did not resume").is_false()
	await _click(_stage_button(PAUSE_TIP))
	assert_bool(_stage()._paused).is_true()
	await _click(_stage_button(PAUSE_TIP))
	assert_bool(_stage()._paused).is_false()
	assert_array(held).override_failure_message("the phase stopped holding by itself").is_empty()
	await _press_at(_card().get_global_rect().position + Vector2(20, 20))
	await _runner.simulate_frames(3)
	assert_array(held).override_failure_message("a click on the card did not advance").is_equal([1])


## ◂ / ▸ browse the running activation ("— browsing"), ▸ on the newest is live again; after the activation
## the card fades. (The drag is not drivable headless: the card reads the DisplayServer's mouse position,
## which a headless run pins at 0,0.)
func test_the_stage_browses_and_fades(timeout := 120000) -> void:
	_open_stage()
	var held: Array = []
	await _stage_phase("To hit", ["Rifle: 3 hits"], held)
	await _press_at(_card().get_global_rect().position + Vector2(20, 20))
	await _stage_phase("Saves", ["Guards save 1 of 3"], held)
	assert_str(_stage_text()).contains("Saves  (2/2)")
	await _click(_stage_button(PREV_TIP))
	assert_str(_stage_text()).contains("To hit  (1/2)  — browsing")
	assert_str(_stage_text()).contains("· Rifle: 3 hits")
	await _click(_stage_button(NEXT_TIP))
	assert_str(_stage_text()).contains("Saves  (2/2)")
	assert_bool(_stage_text().contains("browsing")).is_false()
	var card := _card()
	await _press_at(card.get_global_rect().position + Vector2(20, 20))
	assert_array(held).is_equal([1, 1])
	_stage().hold_s = 0.2
	_stage().activation_end()
	await get_tree().create_timer(1.8).timeout
	assert_float(card.modulate.a).override_failure_message("the card never faded").is_less(0.05)


# === the house look (restyle) =================================================================

## Controls under `root` (itself included) that set a colour, font size, outline or tint of their own.
func _own_look(root: Control) -> Array:
	var out: Array = []
	for n: Node in [root] + root.find_children("*", "Control", true, false):
		var c := n as Control
		if c.has_theme_color_override(&"font_color") or c.has_theme_font_size_override(&"font_size") \
				or c.has_theme_constant_override(&"outline_size") or c.has_theme_stylebox_override(&"panel") \
				or c.modulate != Color.WHITE:
			out.append(c.name)
	return out


## Glyphs of `text` the control's own font does not carry.
func _lacking(c: Control, text: String) -> Array:
	var font := c.get_theme_font(&"font")
	var out: Array = []
	for i in text.length():
		if text[i] != " " and not font.has_char(text.unicode_at(i)):
			out.append("U+%04X in '%s'" % [text.unicode_at(i), text])
	return out


## Every status line is the same house plate (one look for one job, not three text colours with an
## outline), sits centred, and the three lanes no longer overlap.
func test_every_status_line_is_a_centred_house_plate(timeout := 120000) -> void:
	_main._show_solo_ai_banner()
	_main._solo_show_toast("Raiders advance 6\"", 0.0)
	_main._on_session_busy_changed(true)
	await _runner.simulate_frames(3)
	var lanes: Array = [_main._solo_ai_banner, _main._solo_toast, _main._peer_busy_banner]
	_main._solo_hide_toast(true)
	_main._show_toast("Room code copied")
	await _runner.simulate_frames(3)
	var mid := _vp_size().x * 0.5
	for l: Label in lanes + [_ui_label("Room code copied")]:
		assert_str(String(l.theme_type_variation)).override_failure_message("'%s' is not a house status line" % l.text) \
			.is_equal(String(HouseStyle.STATUS))
		assert_object(l.theme).is_same(HouseStyle.theme())
		assert_array(_own_look(l)).override_failure_message("'%s' dresses itself" % l.text).is_empty()
		assert_float(l.get_global_rect().get_center().x).override_failure_message("'%s' is %d px off centre" % [
			l.text, l.get_global_rect().get_center().x - mid]).is_equal_approx(mid, 2.0)
	for i in 2:
		assert_float((lanes[i] as Label).get_global_rect().end.y).override_failure_message("lane %d overlaps lane %d" % [
			i, i + 1]).is_less_equal((lanes[i + 1] as Label).global_position.y)


## The dream overlay: a house sheet, the words in the AI's gold voice, the spinner in the same gold.
func test_the_dream_overlay_wears_the_house_sheet(timeout := 120000) -> void:
	_main._solo_batch = false
	_main._show_dream_overlay()
	await _runner.simulate_frames(3)
	var overlay: Control = _main._solo_dream_overlay
	var panel := overlay.find_children("*", "PanelContainer", true, false)[0] as PanelContainer
	assert_object(overlay.theme).is_same(HouseStyle.theme())
	assert_str(String(panel.theme_type_variation)).is_equal(String(HouseStyle.SHEET))
	assert_str(String(_ui_label("NACHTMAHR dreams…").theme_type_variation)).is_equal(String(HouseStyle.VOICE))
	assert_array(_own_look(panel)).is_empty()
	var spinner := overlay.find_children("*", "DreamSpinner", true, false)[0] as DreamSpinner
	assert_object(spinner.arc_color).is_equal(HouseStyle.GOLD)
	assert_array(_lacking(_ui_label("NACHTMAHR dreams…"), "NACHTMAHR dreams…")).is_empty()
	_main._hide_dream_overlay()


## The stage card in the house roles, and every glyph on its buttons (paused too) in their font.
func test_the_stage_card_wears_the_house_style_and_its_glyphs_draw(timeout := 120000) -> void:
	_open_stage()
	var held: Array = []
	await _stage_phase("To hit", ["Rifle: 3 hits"], held)
	var card := _card()
	assert_object(card.theme).is_same(HouseStyle.theme())
	assert_str(String(card.theme_type_variation)).is_equal(String(HouseStyle.PANEL_VARIANT))
	assert_array(_own_look(card)).override_failure_message("own look on %s" % [_own_look(card)]).is_empty()
	var roles := {"Raiders shoot Guards": HouseStyle.EYEBROW, "To hit  (1/1)": HouseStyle.NOTE,
		"· Rifle: 3 hits": HouseStyle.BODY, STAGE_HINT: HouseStyle.CAPTION}
	for n: Node in card.find_children("*", "Label", true, false):
		var l := n as Label
		if roles.has(l.text):
			assert_str(String(l.theme_type_variation)).override_failure_message("'%s' has the wrong role" % l.text) \
				.is_equal(String(roles[l.text]))
			roles.erase(l.text)
	assert_array(roles.keys()).override_failure_message("labels not found: %s" % [roles.keys()]).is_empty()
	var lacking: Array = []
	for tip: String in [PREV_TIP, PAUSE_TIP, NEXT_TIP]:
		assert_str(String(_stage_button(tip).theme_type_variation)).is_equal(String(HouseStyle.ICON))
		lacking.append_array(_lacking(_stage_button(tip), _stage_button(tip).text))
	_stage().toggle_pause()
	lacking.append_array(_lacking(_stage_button(PAUSE_TIP), _stage_button(PAUSE_TIP).text))
	_stage().toggle_pause()
	assert_array(lacking).override_failure_message("the stage buttons' font lacks %s" % [lacking]).is_empty()
	_stage().skip()


## A clicked pause button must not keep the keyboard: SPACE still resumes afterwards.
func test_space_resumes_after_the_pause_button_was_clicked(timeout := 120000) -> void:
	_open_stage()
	var held: Array = []
	await _stage_phase("To hit", ["Rifle: 3 hits"], held)
	await _click(_stage_button(PAUSE_TIP))
	assert_bool(_stage()._paused).is_true()
	await _key(KEY_SPACE)
	assert_bool(_stage()._paused).override_failure_message("SPACE did not resume after a click on the pause button") \
		.is_false()
	_stage().skip()


# === the check itself =========================================================================

## The control check names a stage control that went missing (the pause button hidden).
func test_the_inventory_check_names_a_removed_control(timeout := 120000) -> void:
	_open_stage()
	var held: Array = []
	await _stage_phase("To hit", ["Rifle: 3 hits"], held)
	assert_array(_stage_missing()).is_empty()
	_stage_button(PAUSE_TIP).hide()
	assert_array(_stage_missing()).contains_exactly(["button: %s" % PAUSE_TIP])
	_stage().skip()
	await _runner.simulate_frames(2)
