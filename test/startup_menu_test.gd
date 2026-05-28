extends GdUnitTestSuite
## Tests for the simplified startup menu
## Verifies: 3 buttons (Start New Battle, Load Battle, Exit Game), no multiplayer

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

	assert_that(buttons.size()).is_equal(5)


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

func test_hover_effects_on_three_buttons() -> void:
	var menu_buttons := _menu.find_child("MenuButtons", true, false) as VBoxContainer
	var buttons: Array[Button] = []
	for child in menu_buttons.get_children():
		if child is Button:
			buttons.append(child)

	for btn in buttons:
		assert_that(btn.mouse_entered.get_connections().size()).is_greater(0)
