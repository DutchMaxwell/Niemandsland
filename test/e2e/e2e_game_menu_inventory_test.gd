extends GdUnitTestSuite
## E2E — the ☰ game menu, rows 1-4 of the UI inventory (uimenu PR 1: the slide-out shell, "Table and
## army", "Save / Load / Graphics / End Battle"; PR 2: "Multiplayer" + the room code; mockup LOOK,
## today's FULL function set). Every control of today's menu is found in the open column by the words the
## player reads, is reached by a REAL click and does what it does today. The solo / deployment sections
## (rows 5, 6) are PR 3 and are not checked here.
## test_inventory_check_names_a_removed_control proves the presence check can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

## Rows 2 and 4: every button by its text ("Next Round" by prefix: its label names the round).
const BUTTONS := ["Import OPR Army...", "AI Opponent", "Map Layout...", "Terrain Mode", "Clear Table",
	"Sort Table", "Next Round", "Settings", "Save Game...", "Load Game...", "End Battle - To Main Menu"]
## Row 3 while offline (Disconnect shows once connected).
const MP_BUTTONS := ["Host Online Game", "Join Online Game"]
## The section labels.
const LABELS := ["Import / Load:", "Multiplayer:", "Save / Load:", "Graphics:"]
## Row 3's status line: [handler, its arguments, today's text, the tone it reads in]. Only the handlers
## that touch no socket and send no RPC. Not here: "Reconnect failed (…)" — _on_relay_reconnect_failed
## tears the relay down, which emits internet_disconnected, which writes "Offline" over it at once.
const STATES := [
	[&"_on_internet_disconnected", [], "Offline", "muted"],
	[&"_on_guest_reconnected", [], "Reconnected", "ok"],
	[&"_on_relay_reconnecting", [], "Reconnecting…", "warn"],
	[&"_on_host_paused", [], "Host disconnected — waiting for reconnect…", "warn"],
	[&"_on_internet_failed", ["relay unreachable"], "Online failed: relay unreachable", "danger"],
	[&"_on_network_failed", [], "Connection failed!", "danger"],
	[&"_on_network_disconnected", [], "Server disconnected", "danger"],
	[&"_on_version_rejected", ["0.3.14.0", "0.3.13.0"],
		"Version mismatch: host 0.3.14.0, you 0.3.13.0 — update to match", "danger"],
]
## The graphics quality dropdown, in GraphicsSettings.QualityPreset order.
const GRAPHICS := ["Performance", "Low", "Medium", "High", "Ultra"]
## Buttons that explain themselves on hover.
const TOOLTIPS := ["Sort Table", "Next Round", "Settings", "AI Opponent"]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _peer_before: MultiplayerPeer


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_peer_before = get_tree().get_multiplayer().multiplayer_peer
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	# Disconnect (network_manager.disconnect_game) sets the TREE's peer to null — the whole test process
	# shares it, so every later suite logged "No multiplayer peer is assigned" and the card suite's AI
	# seat read differently (measured: 131 errors over 15 suites). Put the offline peer back.
	get_tree().get_multiplayer().multiplayer_peer = _peer_before
	_main = null
	_runner = null


# === helpers ==================================================================================

func _scroll() -> ScrollContainer:
	return _main.left_panel_scroll


## Opens the menu with the ☰ button and waits out the 0.2 s fade-in (the column is IGNORE until solid).
func _open_menu() -> void:
	if _scroll().visible:
		return
	await _click(_main.hamburger_button)
	await get_tree().create_timer(0.35).timeout
	await _runner.simulate_frames(2)


## A real click at the centre of `c`; a control inside the column is scrolled into view first.
func _click(c: Control) -> void:
	if c == null:
		fail("the control to click is missing")
		return
	if _scroll().is_ancestor_of(c):
		_scroll().ensure_control_visible(c)
		await _runner.simulate_frames(2)
		assert_bool(_scroll().get_global_rect().has_point(c.get_global_rect().get_center())) \
			.override_failure_message("%s is not inside the open menu" % c.name).is_true()
	var vp := c.get_viewport()
	var at := c.get_global_rect().get_center()
	E2EBoot.motion_canvas(vp, at)
	E2EBoot.click_canvas(vp, at, true)
	E2EBoot.click_canvas(vp, at, false)
	await _runner.simulate_frames(3)


func _button(text: String) -> Button:
	for n: Node in _scroll().find_children("*", "Button", true, false):
		var b := n as Button
		if not (b is OptionButton) and (b.text == text or (text == "Next Round" and b.text.begins_with(text))):
			return b
	return null


func _label(text: String) -> Label:
	for n: Node in _scroll().find_children("*", "Label", true, false):
		if (n as Label).text == text:
			return n as Label
	return null


func _graphics() -> OptionButton:
	for n: Node in _scroll().find_children("*", "OptionButton", true, false):
		var o := n as OptionButton
		var items: Array = []
		for i in o.item_count:
			items.append(o.get_item_text(i))
		if items == GRAPHICS:
			return o
	return null


## True when `c` shows in the open menu and lies across the column's width (not cut at its sides).
func _shown(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var col := _scroll().get_global_rect().grow(1.0)
	var r := c.get_global_rect()
	return r.size.x > 0.0 and r.position.x >= col.position.x and r.end.x <= col.end.x


## Every inventory control that is missing or not shown in the open menu — [] when all are there.
func _missing_controls() -> Array:
	await _open_menu()
	var missing: Array = []
	for t: String in BUTTONS + MP_BUTTONS:
		if not _shown(_button(t)):
			missing.append("button: " + t)
	if not _shown(_main.network_status_label) or _main.network_status_label.text != "Offline":
		missing.append("status: Offline")
	for t: String in LABELS:
		if not _shown(_label(t)):
			missing.append("label: " + t)
	if not _shown(_graphics()):
		missing.append("dropdown: Graphics quality")
	return missing


## Runs one STATES handler and returns the status line's colour.
func _show_state(state: Array) -> Color:
	_main.callv(state[0], state[1])
	await _runner.simulate_frames(1)
	return _main.network_status_label.get_theme_color(&"font_color")


## The tone a status colour reads as: grey, green, amber / yellow or red ("" = none of them).
func _tone_of(c: Color) -> String:
	if maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)) < 0.15:
		return "muted"
	if c.g > c.r and c.g > c.b:
		return "ok"
	if c.r > c.b + 0.3 and c.g > c.b + 0.2:
		return "warn"
	if c.r > c.g + 0.3 and c.r > c.b + 0.3:
		return "danger"
	return ""


## The house-style ink of a tone (the danger text lifted as on End Battle).
func _tone_ink(tone: String) -> Color:
	match tone:
		"ok":
			return HouseStyle.OK
		"warn":
			return HouseStyle.WARN
		"danger":
			return HouseStyle.DANGER.lightened(HouseStyle.DANGER_INK_LIFT)
	return HouseStyle.MUTED


# === tests ====================================================================================

func test_the_menu_button_opens_and_closes_the_column(timeout := 120000) -> void:
	var menu: Button = _main.hamburger_button
	assert_bool(_scroll().visible).is_false()
	assert_str(menu.text).is_equal("☰")
	await _click(menu)
	assert_bool(_scroll().visible).override_failure_message("☰ did not open the game menu").is_true()
	assert_str(menu.text).is_equal("×")
	# Fading in: not yet a surface — an invisible column over the table must not eat clicks.
	assert_int(_scroll().mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	await get_tree().create_timer(0.35).timeout
	await _runner.simulate_frames(2)
	assert_float(_scroll().modulate.a).is_equal_approx(1.0, 0.01)
	assert_int(_scroll().mouse_filter).override_failure_message("the open menu does not own its clicks") \
		.is_equal(Control.MOUSE_FILTER_STOP)
	# The column opens under the menu button, at the left edge.
	assert_float(_scroll().get_global_rect().position.y).is_greater_equal(menu.get_global_rect().end.y)
	assert_float(_scroll().get_global_rect().position.x).is_less_equal(menu.get_global_rect().position.x)
	# The column keeps the width the scene gives it: no menu line pushes it wider.
	var width: float = _scroll().offset_right - _scroll().offset_left
	assert_float(_scroll().get_combined_minimum_size().x).override_failure_message(
		"a menu line needs %d px, the column has %d" % [_scroll().get_combined_minimum_size().x, width]).is_less_equal(width)
	assert_float(_scroll().size.x).is_equal_approx(width, 0.5)
	await _click(menu)
	assert_str(menu.text).is_equal("☰")
	assert_int(_scroll().mouse_filter).override_failure_message("the closing menu dropped its clicks early") \
		.is_equal(Control.MOUSE_FILTER_STOP)
	await get_tree().create_timer(0.3).timeout
	await _runner.simulate_frames(2)
	assert_bool(_scroll().visible).override_failure_message("× did not close the game menu").is_false()


func test_every_control_of_rows_2_to_4_is_in_the_open_menu(timeout := 120000) -> void:
	var missing: Array = await _missing_controls()
	assert_array(missing).override_failure_message("today's menu controls missing: %s" % str(missing)).is_empty()
	for t: String in TOOLTIPS:
		if _button(t) != null:   # a missing one is named above
			assert_str(_button(t).tooltip_text).override_failure_message("%s lost its tooltip" % t).is_not_empty()
	# End Battle reads as the dangerous one: its text is red.
	var red: Color = _button("End Battle - To Main Menu").get_theme_color(&"font_color")
	assert_bool(red.r > red.g + 0.3 and red.r > red.b + 0.3).override_failure_message("End Battle is not red: %s" % red).is_true()


func test_rows_2_to_4_wear_the_house_style_and_the_other_sections_keep_theirs(timeout := 120000) -> void:
	await _open_menu()
	for t: String in BUTTONS + MP_BUTTONS + ["Disconnect"]:
		var want: StringName = HouseStyle.DANGER_BUTTON if t.begins_with("End Battle") else HouseStyle.BUTTON
		assert_str(String(_button(t).theme_type_variation)).override_failure_message("%s is not a house-style line" % t) \
			.is_equal(String(want))
		assert_object((_button(t).get_parent() as Control).theme).override_failure_message("%s's section is not in the house theme" % t) \
			.is_same(HouseStyle.theme())
	assert_str(String(_graphics().theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	for t: String in LABELS:
		assert_str(String(_label(t).theme_type_variation)).is_equal(String(HouseStyle.EYEBROW))
	# The room code sits above the sections, in the column itself: a house-style line in the "online" ink.
	var room: Button = _main._room_code_button
	assert_str(String(room.theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	assert_object(room.theme).is_same(HouseStyle.theme())
	assert_that(room.get_theme_color(&"font_color")).is_equal(HouseStyle.OK)
	# PR 3: solo and deployment keep today's look — no house style reaches them.
	for section: String in ["DeploymentPanel"]:
		var box := _scroll().get_node("LeftPanelVBox/" + section) as Control
		for n: Node in [box] + box.find_children("*", "Control", true, false):
			assert_str(String((n as Control).theme_type_variation)).override_failure_message("%s/%s was restyled" % [section, n.name]).is_empty()
			assert_object((n as Control).theme).override_failure_message("%s/%s wears the house theme" % [section, n.name]) \
				.is_not_same(HouseStyle.theme())


func test_inventory_check_names_a_removed_control(timeout := 120000) -> void:
	var missing: Array = await _missing_controls()
	assert_array(missing).is_empty()
	var save := _button("Save Game...")
	var parent := save.get_parent()
	var at := save.get_index()
	parent.remove_child(save)
	missing = await _missing_controls()
	parent.add_child(save)
	parent.move_child(save, at)
	assert_array(missing).contains_exactly(["button: Save Game..."])


func test_table_and_army_buttons_do_what_they_do_today(timeout := 120000) -> void:
	await _open_menu()
	await _click(_button("Import OPR Army..."))
	assert_bool(_main.opr_import_dialog.visible).override_failure_message("Import OPR Army... did not open the import window").is_true()
	_main.opr_import_dialog.hide()

	# AI Opponent fetches the list manifest from the CDN (no bundle in the repo): the click is proven to
	# reach the button and today's handler is proven wired to it, without a network call in the suite.
	var ai := _button("AI Opponent")
	if ai == null:
		fail("AI Opponent is missing from the menu")
		return
	var handler := Callable(_main, &"_open_ai_opponent_dialog")
	assert_bool(ai.pressed.is_connected(handler)).override_failure_message("AI Opponent no longer opens its dialog").is_true()
	ai.pressed.disconnect(handler)
	var presses := [0]
	var spy := func() -> void: presses[0] += 1
	ai.pressed.connect(spy)
	await _click(ai)
	ai.pressed.disconnect(spy)
	ai.pressed.connect(handler)
	assert_int(presses[0]).override_failure_message("a click on AI Opponent did not press it").is_equal(1)

	var om: Node = _main.object_manager
	var terrain := _button("Terrain Mode")
	await _click(terrain)
	assert_bool(om.is_terrain_edit_mode()).override_failure_message("Terrain Mode did not switch terrain editing on").is_true()
	assert_bool(_main._sandbox_shelf.visible).override_failure_message("Terrain Mode did not open the terrain shelf").is_true()
	assert_bool(terrain.button_pressed).is_true()
	await _click(terrain)
	assert_bool(om.is_terrain_edit_mode()).is_false()
	assert_bool(_main._sandbox_shelf.visible).is_false()

	await _click(_button("Clear Table"))
	var confirm: ConfirmationDialog = _main._action_confirm_dialog
	assert_bool(confirm != null and confirm.visible and confirm.title == "Clear Table").override_failure_message("Clear Table did not ask first").is_true()
	confirm.hide()
	await _click(_button("Sort Table"))
	assert_bool(confirm.visible and confirm.title == "Sort Table").override_failure_message("Sort Table did not ask first").is_true()
	confirm.hide()
	var next := _button("Next Round")
	var before: int = _main.opr_army_manager.current_round
	assert_str(next.text).is_equal(_main.next_round_button_label(before, false))
	await _click(next)
	assert_bool(confirm.visible and confirm.title == next.text).override_failure_message("Next Round did not ask first").is_true()
	confirm.confirmed.emit()
	confirm.hide()
	await _runner.simulate_frames(4)
	assert_int(_main.opr_army_manager.current_round).is_equal(before + 1)
	assert_str(next.text).override_failure_message("Next Round does not name the next round").is_equal(_main.next_round_button_label(before + 1, false))

	var settings: Window = _main.lighting_panel
	var shown: bool = settings.visible
	await _click(_button("Settings"))
	assert_bool(settings.visible).override_failure_message("Settings did not toggle the settings window").is_equal(not shown)
	await _click(_button("Settings"))
	assert_bool(settings.visible).is_equal(shown)

	# Last: the map editor hides the whole HUD, menu included, until it is closed.
	await _click(_button("Map Layout..."))
	assert_bool(_main.map_layout_editor.visible).override_failure_message("Map Layout... did not open the map editor").is_true()
	assert_bool((_main.get_node("UI/HUD") as Control).visible).is_false()
	_main.map_layout_editor.layout_closed.emit()
	await _runner.simulate_frames(2)
	assert_bool((_main.get_node("UI/HUD") as Control).visible).is_true()
	await E2EBoot.settle(get_tree())


func test_save_load_graphics_and_end_battle_do_what_they_do_today(timeout := 120000) -> void:
	await _open_menu()
	await _click(_button("Save Game..."))
	var save: FileDialog = _main.save_game_dialog
	assert_bool(save.visible).override_failure_message("Save Game... did not open the save dialog").is_true()
	assert_bool(save.current_file.begins_with("game_") and save.current_file.ends_with(".nml")).is_true()
	save.hide()
	await _click(_button("Load Game..."))
	assert_bool(_main.load_game_dialog.visible).override_failure_message("Load Game... did not open the load dialog").is_true()
	_main.load_game_dialog.hide()

	# Graphics: shows the current preset; picking an entry in its list applies that preset.
	var gfx := _graphics()
	var kept: int = GraphicsSettings.current_preset
	assert_int(gfx.selected).is_equal(kept)
	await _click(gfx)
	assert_bool(gfx.get_popup().visible).override_failure_message("the graphics dropdown did not open its list").is_true()
	var pick := (kept + 1) % GRAPHICS.size()
	gfx.get_popup().index_pressed.emit(pick)
	gfx.get_popup().hide()
	await _runner.simulate_frames(2)
	assert_int(gfx.selected).is_equal(pick)
	assert_int(GraphicsSettings.current_preset).override_failure_message("picking %s did not apply it" % GRAPHICS[pick]).is_equal(pick)
	gfx.select(kept)
	gfx.item_selected.emit(kept)   # back to the preset the machine had (it is saved to user://)
	assert_int(GraphicsSettings.current_preset).is_equal(kept)

	await _click(_button("End Battle - To Main Menu"))
	var end: ConfirmationDialog = _main.end_battle_confirm_dialog
	assert_bool(end.visible).override_failure_message("End Battle did not ask first").is_true()
	assert_bool(end.confirmed.is_connected(Callable(_main, &"_on_end_battle_confirmed"))) \
		.override_failure_message("confirming End Battle no longer returns to the main menu").is_true()
	end.hide()
	await E2EBoot.settle(get_tree())


func test_host_and_join_open_the_online_dialogs(timeout := 120000) -> void:
	await _open_menu()
	await _click(_button("Host Online Game"))
	var host: Window = _main._net_host_popup
	assert_bool(host != null and host.visible).override_failure_message("Host Online Game did not open its dialog").is_true()
	if host != null:
		host.hide()
	await _click(_button("Join Online Game"))
	var join: Window = _main._net_join_popup
	assert_bool(join != null and join.visible).override_failure_message("Join Online Game did not open its dialog").is_true()
	if join != null:
		join.hide()
	await E2EBoot.settle(get_tree())


func test_connection_states_read_apart_in_the_status_line(timeout := 120000) -> void:
	await _open_menu()
	var first := {}   # tone -> the first colour seen in it
	for state: Array in STATES:
		var ink: Color = await _show_state(state)
		assert_str(_main.network_status_label.text).is_equal(state[2])
		assert_str(_tone_of(ink)).override_failure_message("\"%s\" reads as \"%s\", not %s (%s)" % [
			state[2], _tone_of(ink), state[3], ink]).is_equal(state[3])
		if first.has(state[3]):
			assert_that(ink).override_failure_message("two %s states in two colours" % state[3]).is_equal(first[state[3]])
		first[state[3]] = ink
	assert_int(first.size()).is_equal(4)
	await E2EBoot.settle(get_tree())


func test_room_code_copies_and_logs_once_and_disconnect_ends_the_session(timeout := 120000) -> void:
	await _open_menu()
	var room: Button = _main._room_code_button
	var logged := func() -> int:
		return _main.battle_log.entries().filter(func(e: Dictionary) -> bool: return e["text"] == "Room code: ABC-123").size()
	_main._update_network_ui(true, true)   # a live session: Disconnect instead of Host / Join
	_main._set_room_code_display("ABC123")
	await _runner.simulate_frames(2)
	assert_bool(room.is_visible_in_tree()).override_failure_message("the room code does not show").is_true()
	assert_str(room.text).is_equal("Room: ABC-123")
	assert_object(room.get_parent()).is_same(_scroll().get_node("LeftPanelVBox"))
	assert_int(room.get_index()).override_failure_message("the room code is not at the top of the column").is_equal(0)
	assert_str(_tone_of(room.get_theme_color(&"font_color"))).override_failure_message("the room code is not green").is_equal("ok")
	assert_int(logged.call()).is_equal(1)
	await _click(room)
	assert_str(_main._solo_toast.text).override_failure_message("a click did not say the code was copied").is_equal("Room code copied")
	assert_int(logged.call()).override_failure_message("a copy click wrote to the battle log").is_equal(1)
	for t: String in MP_BUTTONS:
		assert_bool(_button(t).visible).override_failure_message("%s shows in a live session" % t).is_false()
	var bye := _button("Disconnect")
	assert_bool(bye != null and bye.is_visible_in_tree()).override_failure_message("Disconnect is missing in a live session").is_true()
	await _click(bye)
	assert_str(_main.network_status_label.text).is_equal("Offline")
	assert_str(_tone_of(_main.network_status_label.get_theme_color(&"font_color"))).is_equal("muted")
	assert_bool(bye.visible).is_false()
	assert_bool(room.visible).override_failure_message("the room code outlived the session").is_false()
	for t: String in MP_BUTTONS:
		assert_bool(_button(t).is_visible_in_tree()).override_failure_message("%s did not come back" % t).is_true()
	await E2EBoot.settle(get_tree())


func test_the_status_line_wears_house_tokens_and_wraps_inside_the_column(timeout := 120000) -> void:
	await _open_menu()
	var status: Label = _main.network_status_label
	assert_str(String(status.theme_type_variation)).is_equal(String(HouseStyle.BODY))
	var width: float = _scroll().offset_right - _scroll().offset_left
	for state: Array in STATES:
		var ink: Color = await _show_state(state)
		assert_that(ink).override_failure_message("\"%s\" is not in the house %s ink (%s)" % [state[2], state[3], ink]) \
			.is_equal(_tone_ink(state[3]))
		assert_float(_scroll().get_combined_minimum_size().x).override_failure_message("\"%s\" widens the column to %d px" % [
			state[2], _scroll().get_combined_minimum_size().x]).is_less_equal(width)
		var font := status.get_theme_font(&"font")
		for i in status.text.length():
			assert_bool(status.text.unicode_at(i) <= 0x20 or font.has_char(status.text.unicode_at(i))) \
				.override_failure_message("the status font lacks \"%s\"" % status.text[i]).is_true()
	await E2EBoot.settle(get_tree())
