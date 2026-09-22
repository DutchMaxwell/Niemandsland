extends GdUnitTestSuite
## Native routes, focus ownership and real-save state. Tests mount outside the live
## scene so the decorative 3D assets and update check never delay or network here.
var _runner: GdUnitSceneRunner
var _menu: Control

func before_test() -> void:
	_runner = scene_runner("res://scenes/startup_menu.tscn")
	_menu = _runner.scene()

func after_test() -> void:
	_menu = null
	_runner = null

func test_primary_routes_are_grouped() -> void:
	var actions := _menu.find_child("MenuButtons",true,false)
	assert_int(actions.get_child_count()).is_equal(4)
	assert_bool(_menu.host_online_btn.is_visible_in_tree()).is_false()
	assert_bool(_menu.tutorial_btn.is_visible_in_tree()).is_false()
	_menu.view.buttons.OnlineBtn.pressed.emit()
	assert_bool(_menu.host_online_btn.is_visible_in_tree()).is_true()
	assert_bool(_menu.join_online_btn.is_visible_in_tree()).is_true()
	assert_bool(_menu.browse_online_btn.is_visible_in_tree()).is_true()
	assert_bool(_menu.tutorial_btn.is_visible_in_tree()).is_false()

func test_continue_matches_actual_save_lookup() -> void:
	assert_bool(_menu.continue_btn.visible).is_equal(not SaveManager.latest_save_info().is_empty())
	assert_str(_menu._continue_path).is_equal(str(SaveManager.latest_save_info().get("path","")))

func test_first_visit_promotes_new_table_and_hides_save() -> void:
	_menu.view.set_save({})
	assert_bool(_menu.view.resume.visible).is_false()
	assert_bool(_menu.continue_btn.is_visible_in_tree()).is_false()
	assert_bool(_menu.start_battle_btn.primary).is_true()
	assert_str(_menu.view.welcome.text).is_equal("Your first table awaits.")

func test_saved_title_is_not_replaced_with_mockup_data() -> void:
	_menu.view.set_save({"name":"Meine eigene Runde","modified_unix":1727000000})
	assert_str(_menu.view.save_name.text).is_equal("Meine eigene Runde")
	assert_bool(_menu.start_battle_btn.primary).is_false()

func test_visible_focus_chain_loops_and_skips_hidden_routes() -> void:
	_menu.view.set_save({})
	assert_object(_menu.start_battle_btn.get_node(_menu.start_battle_btn.focus_neighbor_top)).is_same(_menu.exit_game_btn)
	assert_object(_menu.exit_game_btn.get_node(_menu.exit_game_btn.focus_neighbor_bottom)).is_same(_menu.start_battle_btn)
	for button in _menu.view.main_buttons():
		assert_int(button.focus_mode).is_equal(Control.FOCUS_ALL)

func test_escape_closes_group_without_quit_dialog() -> void:
	_menu.view.buttons.LearnBtn.grab_focus()
	_menu.view.buttons.LearnBtn.pressed.emit()
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	_menu._unhandled_key_input(event)
	assert_bool(_menu.view.route_panel.visible).is_false()
	assert_object(_menu._exit_confirm).is_null()
	assert_bool(_menu.view.buttons.LearnBtn.has_focus()).is_true()

func test_group_focus_cycles_inside_group() -> void:
	_menu.view.show_route("online")
	assert_object(_menu.browse_online_btn.get_node(_menu.browse_online_btn.focus_next)).is_same(_menu.view.route_back)
	assert_object(_menu.view.route_back.get_node(_menu.view.route_back.focus_next)).is_same(_menu.host_online_btn)

func test_existing_routes_keep_their_own_handlers() -> void:
	for pair in [[_menu.start_battle_btn,_menu._on_start_battle_pressed],[_menu.continue_btn,_menu._on_continue_pressed],
		[_menu.load_battle_btn,_menu._on_load_battle_pressed],[_menu.tutorial_btn,_menu._on_tutorial_pressed],
		[_menu.spielschule_btn,_menu._on_spielschule_pressed],[_menu.credits_btn,_menu._on_credits_pressed]]:
		assert_bool(pair[0].pressed.is_connected(pair[1])).is_true()
	assert_bool(_menu.tutorial_btn.pressed.is_connected(_menu._on_spielschule_pressed)).is_false()

func test_host_route_opens_existing_dialog_and_keeps_public_checkbox_focusable() -> void:
	_menu.view.show_route("online")
	_menu.host_online_btn.pressed.emit()
	assert_bool(_menu.view.route_panel.visible).is_false()
	assert_bool(_menu._host_popup.visible).is_true()
	assert_object(_menu._relay_url_input).is_not_null()
	assert_int(_menu._host_public_check.focus_mode).is_equal(Control.FOCUS_ALL)

func test_join_invalid_code_keeps_dialog_open_and_does_not_transition() -> void:
	_menu._on_join_online_pressed()
	_menu._join_code_input.text = "AB"
	_menu._on_join_confirmed()
	assert_bool(_menu._join_popup.visible).is_true()
	assert_bool(_menu._join_error_label.visible).is_true()
	assert_bool(_menu._transitioning).is_false()

func test_load_opens_real_nml_file_dialog() -> void:
	_menu.load_battle_btn.pressed.emit()
	assert_object(_menu._load_dialog).is_not_null()
	assert_int(_menu._load_dialog.file_mode).is_equal(FileDialog.FILE_MODE_OPEN_FILE)
	assert_bool(_menu._load_dialog.visible).is_true()

func test_tutorial_entry_arms_existing_runtime_flags() -> void:
	var mode = ProjectSettings.get_setting("niemandsland/tutorial_mode",false)
	var lesson = ProjectSettings.get_setting("niemandsland/tutorial_lesson","")
	_menu._arm_tutorial_flags("T-04")
	var result = ProjectSettings.get_setting("niemandsland/tutorial_lesson")
	ProjectSettings.set_setting("niemandsland/tutorial_mode",mode)
	ProjectSettings.set_setting("niemandsland/tutorial_lesson",lesson)
	assert_str(result).is_equal("T-04")

func test_menu_never_creates_game_or_atmosphere_controllers() -> void:
	assert_object(_menu.find_child("NetworkManager",true,false)).is_null()
	assert_object(_menu.find_child("AtmosphereController",true,false)).is_null()
	assert_bool(_menu.diorama._diorama_built).is_false()

func test_rebuild_keeps_main_actions_usable() -> void:
	_menu._on_diorama_rebuild_started()
	assert_bool(_menu.start_battle_btn.is_visible_in_tree()).is_true()
	assert_bool(_menu.start_battle_btn.disabled).is_false()
	assert_str(_menu.view.status.text).contains("Preparing background")

func test_new_table_configuration_can_cancel_without_leaving_menu() -> void:
	_menu.start_battle_btn.pressed.emit()
	assert_object(_menu._table_setup).is_not_null()
	assert_bool(_menu._transitioning).is_false()
	assert_bool(_menu.view.visible).is_false()
	_menu._table_setup._on_close()
	assert_bool(_menu.view.visible).is_true()
	assert_object(_menu._table_setup).is_null()
	assert_bool(_menu._transitioning).is_false()

func test_host_setup_cancel_does_not_arm_network_or_table_state() -> void:
	var pending = ProjectSettings.get_setting("niemandsland/pending_internet_lobby",false)
	var setup = ProjectSettings.get_setting("niemandsland/pending_table_setup",{})
	_menu._show_table_setup({"niemandsland/pending_internet_lobby":true})
	_menu._table_setup._on_close()
	assert_bool(ProjectSettings.get_setting("niemandsland/pending_internet_lobby",false)).is_equal(pending)
	assert_dict(ProjectSettings.get_setting("niemandsland/pending_table_setup",{})).is_equal(setup)

class MenuTransitionProbe extends "res://scripts/startup_menu.gd":
	var entered_game := false
	func _transition_to_game() -> void:
		entered_game = true

func test_host_creation_commits_selected_table_and_network_settings_together() -> void:
	var keys := ["niemandsland/pending_table_setup","niemandsland/pending_internet_lobby","niemandsland/internet_is_host","niemandsland/internet_relay_url","niemandsland/player_name","niemandsland/internet_public"]
	var previous := {}
	for key in keys:
		previous[key] = ProjectSettings.get_setting(key,null)
	var probe = auto_free(load("res://scenes/startup_menu.tscn").instantiate())
	probe.set_script(MenuTransitionProbe)
	add_child(probe)
	probe._on_host_online_pressed()
	probe._host_public_check.button_pressed = true
	probe._on_host_confirmed()
	var started_early: bool = probe.entered_game
	probe._table_setup._select_biome("arid_desert")
	probe._table_setup._select_size("square")
	probe._table_setup._confirm()
	var result := {}
	for key in keys:
		result[key] = ProjectSettings.get_setting(key,null)
		ProjectSettings.set_setting(key,previous[key])
	assert_bool(started_early).is_false()
	assert_bool(probe.entered_game).is_true()
	assert_vector(result["niemandsland/pending_table_setup"].size).is_equal(Vector2(4,4))
	assert_str(result["niemandsland/pending_table_setup"].biome).is_equal("arid_desert")
	assert_bool(result["niemandsland/pending_internet_lobby"]).is_true()
	assert_bool(result["niemandsland/internet_is_host"]).is_true()
	assert_bool(result["niemandsland/internet_public"]).is_true()
