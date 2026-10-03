extends GdUnitTestSuite
## Esc with nothing to close opens the ☰ game menu, and Esc again closes it (maintainer 03.10.2026, Esc = A): a
## LAST fallback in main's _unhandled_input. The Esc handlers that already exist keep the key: a prompt card, the
## radial menu and a placement ghost consume it; a drag, the Settings panel and the chat field act on it without
## consuming it, so main has to see that they owned the press and stay out.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const OPEN_AT := Vector2(960, 520)

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A key down and up, pushed through the table's viewport the way the engine delivers it.
func _key(code: Key) -> void:
	var vp := _main.get_viewport()
	for down: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		vp.push_input(ev)
	await _runner.simulate_frames(2)


## The menu is open once its column shows (the fade-in starts at once; the fade-out hides it after 0.15 s).
func _menu_open() -> bool:
	await get_tree().create_timer(0.3).timeout
	return (_main.left_panel_scroll as Control).visible


func _assert_menu_shut(why: String) -> void:
	assert_bool(await _menu_open()).override_failure_message("Esc opened the game menu while %s" % why).is_false()


func test_esc_with_nothing_open_opens_and_closes_the_menu(timeout := 120000) -> void:
	assert_bool(await _menu_open()).is_false()
	await _key(KEY_ESCAPE)
	assert_bool(await _menu_open()).override_failure_message("Esc with nothing open left the menu shut").is_true()
	await _key(KEY_ESCAPE)
	assert_bool(await _menu_open()).override_failure_message("a second Esc did not close the menu").is_false()


func test_a_prompt_card_keeps_its_esc(timeout := 120000) -> void:
	var asked: Array = []
	_main._show_action_confirm("Clear Table", "Remove every object?", "Clear", func() -> void: asked.append(true))
	await _runner.simulate_frames(2)
	await _key(KEY_ESCAPE)
	assert_array(asked).is_empty()
	await _assert_menu_shut("a prompt card answered it")


func test_the_radial_menu_keeps_its_esc(timeout := 120000) -> void:
	var u := E2EBoot.make_unit(_main, 1, "Guards", [Vector3.ZERO, Vector3(0.05, 0, 0)])
	_main.opr_army_manager.game_units[u.unit_id] = u
	var nodes: Array = []
	for m in u.models:
		(m as ModelInstance).node.set_meta("model_instance", m)
		nodes.append((m as ModelInstance).node)
	_main.object_manager.context_menu_requested.emit(OPEN_AT, nodes)
	await get_tree().create_timer(0.2).timeout
	assert_bool(_main.radial_menu_controller.radial_menu.is_open()).is_true()
	await _key(KEY_ESCAPE)
	assert_bool(_main.radial_menu_controller.radial_menu.is_open()).is_false()
	await _assert_menu_shut("the radial menu closed on it")


func test_a_placement_ghost_keeps_its_esc(timeout := 120000) -> void:
	var ended: Array = []
	var ghost := PlacementGhost.new()
	_main.radial_menu_controller.add_child(ghost)
	ghost.begin([{"r": 0.0125, "off": Vector2.ZERO}], PlacementGhost.circle_zone(Vector3.ZERO, 0.15), [],
		Rect2(-0.9, -0.6, 1.8, 1.2), func(_spots: Variant) -> void: ended.append("commit"),
		func() -> void: ended.append("cancel"))
	await _runner.simulate_frames(2)
	await _key(KEY_ESCAPE)
	assert_array(ended).is_not_empty()
	await _assert_menu_shut("a placement ghost ended on it")


func test_a_drag_keeps_its_esc(timeout := 120000) -> void:
	_main.object_manager._is_dragging = true   # a drag in progress (no objects: the cancel restores nothing)
	await _key(KEY_ESCAPE)
	assert_bool(_main.object_manager._is_dragging).is_false()
	await _assert_menu_shut("it cancelled a drag")


func test_the_settings_panel_keeps_its_esc(timeout := 120000) -> void:
	_main._toggle_settings_panel()
	await _runner.simulate_frames(2)
	assert_bool(_main.lighting_panel.visible).is_true()
	await _key(KEY_ESCAPE)
	assert_bool(_main.lighting_panel.visible).is_false()
	await _assert_menu_shut("it closed the Settings panel")


func test_esc_in_the_chat_field_only_releases_focus(timeout := 120000) -> void:
	_main._set_chat_visible(true)
	(_main._chat_input as LineEdit).grab_focus()
	await _runner.simulate_frames(2)
	await _key(KEY_ESCAPE)
	assert_object(_main.get_viewport().gui_get_focus_owner()).is_null()
	await _assert_menu_shut("it released the chat field")
