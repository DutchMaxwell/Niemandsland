extends GdUnitTestSuite
## Tests for the AAA startup menu: button set (incl. conditional CONTINUE), focus
## chain, version binding and the diorama safety guards (sky-only under tests, no
## AtmosphereController so user://atmosphere.cfg is never touched by the menu).

const STARTUP_MENU_SCENE := "res://scenes/startup_menu.tscn"

var _runner: GdUnitSceneRunner
var _menu: Control


func before_test() -> void:
	_runner = scene_runner(STARTUP_MENU_SCENE)
	_menu = _runner.scene()


func after_test() -> void:
	_runner = null
	_menu = null


## ===== Button Count =====

func test_menu_has_expected_buttons() -> void:
	var menu_buttons := _menu.find_child("MenuButtons", true, false) as VBoxContainer
	assert_that(menu_buttons).is_not_null()

	var buttons: Array[Button] = []
	for child in menu_buttons.get_children():
		if child is Button:
			buttons.append(child)

	# Continue/Start/Tutorial/Host/Join/Browse/Load/ReportProblem/Credits/Exit; CONTINUE may be hidden.
	assert_that(buttons.size()).is_equal(10)


func test_continue_button_hidden_without_save() -> void:
	var btn := _menu.find_child("ContinueBtn", true, false) as Button
	assert_that(btn).is_not_null()
	# In the test environment there may or may not be user saves; the button's
	# visibility must MATCH SaveManager.latest_save_info() exactly.
	assert_that(btn.visible).is_equal(not SaveManager.latest_save_info().is_empty())


func test_version_label_bound_to_project_config() -> void:
	var label := _menu.find_child("VersionLabel", true, false) as Label
	assert_that(label).is_not_null()
	var expected: String = "v%s" % str(ProjectSettings.get_setting("application/config/version"))
	assert_that(label.text).is_equal(expected)


func test_all_menu_buttons_are_keyboard_focusable() -> void:
	var menu_buttons := _menu.find_child("MenuButtons", true, false) as VBoxContainer
	for child in menu_buttons.get_children():
		if child is Button:
			assert_that((child as Button).focus_mode).is_equal(Control.FOCUS_ALL)


func test_menu_never_contains_atmosphere_controller() -> void:
	# AtmosphereController persists to user://atmosphere.cfg on every change — the
	# menu must never instantiate it (the diorama composes lighting directly).
	assert_that(_find_by_script(_menu, "atmosphere_controller.gd")).is_null()


func test_diorama_stays_sky_only_under_tests() -> void:
	# gdUnit adds the scene under /root (not as current_scene); AUTO mode must keep
	# the heavyweight 3D diorama (terrain overlay) off and never fetch from R2.
	assert_that(_find_by_script(_menu, "terrain_overlay.gd")).is_null()


func _find_by_script(root: Node, script_file: String) -> Node:
	for child in root.get_children():
		var script: Script = child.get_script() as Script
		if script != null and script.resource_path.ends_with(script_file):
			return child
		var found := _find_by_script(child, script_file)
		if found != null:
			return found
	return null


## ===== Button Labels =====

func test_start_battle_button_label() -> void:
	var btn := _menu.find_child("StartBattleBtn", true, false) as Button
	assert_that(btn).is_not_null()
	assert_that(btn.text).contains("START NEW BATTLE")


func test_load_battle_button_label() -> void:
	var btn := _menu.find_child("LoadBattleBtn", true, false) as Button
	assert_that(btn).is_not_null()
	assert_that(btn.text).contains("LOAD BATTLE")


func test_exit_game_button_label() -> void:
	var btn := _menu.find_child("ExitGameBtn", true, false) as Button
	assert_that(btn).is_not_null()
	assert_that(btn.text).contains("EXIT GAME")


func test_credits_button_label_and_handler() -> void:
	var btn := _menu.find_child("CreditsBtn", true, false) as Button
	assert_that(btn).is_not_null()
	assert_that(btn.text).contains("CREDITS")
	assert_that(_menu.has_method("_on_credits_pressed")).is_true()
	assert_that(btn.pressed.is_connected(_menu._on_credits_pressed)).is_true()


## ===== No Multiplayer =====

func test_no_multiplayer_button_exists() -> void:
	var multiplayer_btn := _menu.find_child("MultiplayerBtn", true, false)
	assert_that(multiplayer_btn).is_null()


func test_no_multiplayer_handler_exists() -> void:
	assert_that(_menu.has_method("_on_multiplayer_pressed")).is_false()


## ===== Handler Methods Exist =====

func test_start_battle_handler_exists() -> void:
	assert_that(_menu.has_method("_on_start_battle_pressed")).is_true()


func test_load_battle_handler_exists() -> void:
	assert_that(_menu.has_method("_on_load_battle_pressed")).is_true()


func test_exit_handler_exists() -> void:
	assert_that(_menu.has_method("_on_exit_pressed")).is_true()


func test_transition_to_game_exists() -> void:
	assert_that(_menu.has_method("_transition_to_game")).is_true()


## ===== Signal Connections =====

func test_start_battle_button_is_connected() -> void:
	var btn := _menu.find_child("StartBattleBtn", true, false) as Button
	assert_that(btn).is_not_null()
	assert_that(btn.pressed.is_connected(_menu._on_start_battle_pressed)).is_true()


func test_load_battle_button_is_connected() -> void:
	var btn := _menu.find_child("LoadBattleBtn", true, false) as Button
	assert_that(btn).is_not_null()
	assert_that(btn.pressed.is_connected(_menu._on_load_battle_pressed)).is_true()


func test_exit_button_is_connected() -> void:
	var btn := _menu.find_child("ExitGameBtn", true, false) as Button
	assert_that(btn).is_not_null()
	assert_that(btn.pressed.is_connected(_menu._on_exit_pressed)).is_true()


## ===== Load Battle FileDialog =====

func test_load_battle_opens_file_dialog() -> void:
	_menu._on_load_battle_pressed()
	await _runner.simulate_frames(2)

	var dialog_found := false
	for child in _menu.get_children():
		if child is FileDialog:
			dialog_found = true
			break
	assert_that(dialog_found).is_true()


## ===== Hover Effects =====

func test_hover_effects_on_all_buttons() -> void:
	var menu_buttons := _menu.find_child("MenuButtons", true, false) as VBoxContainer
	var buttons: Array[Button] = []
	for child in menu_buttons.get_children():
		if child is Button:
			buttons.append(child)

	for btn in buttons:
		assert_that(btn.mouse_entered.get_connections().size()).is_greater(0)


func test_focus_chain_loops_first_to_last() -> void:
	var first := _menu.find_child("StartBattleBtn", true, false) as Button
	var last := _menu.find_child("ExitGameBtn", true, false) as Button
	# With no save, StartBattle is the first VISIBLE button: up from it lands on Exit.
	if not (_menu.find_child("ContinueBtn", true, false) as Button).visible:
		assert_that(first.get_node(first.focus_neighbor_top)).is_equal(last)
		assert_that(last.get_node(last.focus_neighbor_bottom)).is_equal(first)


## ===== Online dialogs (regression: the content node must resolve) =====
## The net dialog's intermediate MarginContainer gets a runtime auto-name, so a
## fixed get_node path resolved to null and adding content crashed — "Host Online"
## opened nothing. These guard that the host/join/browse dialogs build fully.

func test_host_online_dialog_builds() -> void:
	_menu._on_host_online_pressed()
	await _runner.simulate_frames(3)
	assert_that(_menu._host_name_input).is_not_null()
	assert_that(_menu._host_public_check).is_not_null()
	assert_that(_menu._relay_url_input).is_not_null()
	assert_that(_menu._host_popup.visible).is_true()


func test_join_online_dialog_builds() -> void:
	_menu._on_join_online_pressed()
	await _runner.simulate_frames(3)
	assert_that(_menu._join_name_input).is_not_null()
	assert_that(_menu._join_code_input).is_not_null()
	assert_that(_menu._join_popup.visible).is_true()


func test_browse_online_dialog_builds() -> void:
	_menu._on_browse_online_pressed()
	await _runner.simulate_frames(3)
	assert_that(_menu._browse_rooms_vbox).is_not_null()
	assert_that(_menu._browse_lobby).is_not_null()
	assert_that(_menu._browse_popup.visible).is_true()


## ===== Live quality-switch rebuild cover =====
## Switching Performance -> higher rebuilds the whole diorama live; without a
## loading cover the heavy build froze the visible menu with no feedback.

func test_diorama_rebuild_shows_loading_overlay() -> void:
	await _runner.simulate_frames(3)
	# After startup the initial overlay is gone (or absent in tests) — force the
	# rebuild signal like a live Performance -> higher switch would.
	_menu._loading_overlay = null
	_menu._on_diorama_rebuild_started()
	assert_that(_menu._loading_overlay).is_not_null()
	assert_that(is_instance_valid(_menu._loading_overlay)).is_true()
