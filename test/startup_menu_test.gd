extends GdUnitTestSuite
## Native routes, focus ownership and real-save state. Tests mount outside the live
## scene so the decorative 3D assets and update check never delay or network here.
var _runner: GdUnitSceneRunner
var _menu: Control

var _menu_cfg: Variant = null   # the profile's menu config: a Create table remembers the opponent there


func before_test() -> void:
	_menu_cfg = FileAccess.get_file_as_string(SetupOpponent.MENU_CFG) if FileAccess.file_exists(SetupOpponent.MENU_CFG) else null
	_runner = scene_runner("res://scenes/startup_menu.tscn")
	_menu = _runner.scene()
	_menu.setup_lists = false   # the setup never asks the CDN for NACHTMAHR's lists here

func after_test() -> void:
	if _menu_cfg == null:
		DirAccess.remove_absolute(SetupOpponent.MENU_CFG)
	else:
		FileAccess.open(SetupOpponent.MENU_CFG, FileAccess.WRITE).store_string(_menu_cfg)
	_menu = null
	_runner = null

func test_primary_routes_are_grouped() -> void:
	var actions := _menu.find_child("MenuButtons",true,false)
	assert_int(actions.get_child_count()).is_equal(5)
	_menu.online_hub_lists = false
	_menu.view.buttons.OnlineBtn.pressed.emit()
	assert_bool(_menu.view.page_open is OnlineHub).is_true()

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
	var news: Control = _menu.view.news_card   # the news card joins the chain after Quit
	assert_object(_menu.start_battle_btn.get_node(_menu.start_battle_btn.focus_neighbor_top)).is_same(news)
	assert_object(_menu.exit_game_btn.get_node(_menu.exit_game_btn.focus_neighbor_bottom)).is_same(news)
	assert_object(news.get_node(news.focus_neighbor_bottom)).is_same(_menu.start_battle_btn)
	for button in _menu.view.main_buttons():
		assert_int(button.focus_mode).is_equal(Control.FOCUS_ALL)

func test_escape_closes_group_without_quit_dialog() -> void:
	_menu.view.buttons.LearnBtn.grab_focus()
	_menu.view.buttons.LearnBtn.pressed.emit()
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	_menu._unhandled_key_input(event)
	if _menu.view.route_panel.visible:
		await _menu.view.route_closed
	assert_bool(_menu.view.route_panel.visible).is_false()
	assert_object(_menu._exit_card).is_null()
	assert_bool(_menu.view.buttons.LearnBtn.has_focus()).is_true()

func test_group_focus_cycles_inside_group() -> void:
	_menu.view.show_route("help")
	var report: Button = _menu.view.buttons.ReportProblemBtn
	assert_object(report.get_node(report.focus_next)).is_same(_menu.view.route_back)
	assert_object(_menu.view.route_back.get_node(_menu.view.route_back.focus_next)).is_same(_menu.view.buttons.HelpTutorialBtn)

func test_existing_routes_keep_their_own_handlers() -> void:
	for pair in [[_menu.start_battle_btn,_menu._on_start_battle_pressed],[_menu.continue_btn,_menu._on_continue_pressed],
		[_menu.load_battle_btn,_menu._on_load_battle_pressed],[_menu.credits_btn,_menu._on_credits_pressed]]:
		assert_bool(pair[0].pressed.is_connected(pair[1])).is_true()

## Enter in the host's name field is "Prepare table" (red on main: nothing happened).
func test_enter_in_the_host_name_field_prepares_the_table() -> void:
	_menu.online_hub_lists = false
	_menu._open_online_hub()
	assert_object(_menu._table_setup).is_null()
	var hub: OnlineHub = _menu.view.page_open
	hub.name_field.text_submitted.emit(hub.name_field.text)
	assert_object(_menu._table_setup).is_not_null()
	_menu._table_setup._on_close()   # "Back to main menu" of the setup returns to the hub's Prepare table
	assert_bool(hub.prepare_button.has_focus()).is_true()


func test_load_opens_real_nml_file_dialog() -> void:
	_menu.load_battle_btn.pressed.emit()
	assert_object(_menu._save_browser).is_not_null()
	_menu._save_browser.browse_button.pressed.emit()
	assert_int(_menu._save_browser.file_dialog.file_mode).is_equal(FileDialog.FILE_MODE_OPEN_FILE)
	assert_bool(_menu._save_browser.file_dialog.visible).is_true()
	_menu._save_browser.file_dialog.hide()

func test_tutorial_entry_arms_existing_runtime_flags() -> void:
	var mode = ProjectSettings.get_setting("niemandsland/tutorial_mode",false)
	var lesson = ProjectSettings.get_setting("niemandsland/tutorial_lesson","")
	_menu._arm_tutorial_flags("T-04")
	var result = ProjectSettings.get_setting("niemandsland/tutorial_lesson")
	ProjectSettings.set_setting("niemandsland/tutorial_mode",mode)
	ProjectSettings.set_setting("niemandsland/tutorial_lesson",lesson)
	assert_str(result).is_equal("T-04")


func test_return_from_lesson_opens_chapter_picker_and_clears_flag() -> void:
	var key := "niemandsland/open_game_school"
	var previous: Variant = ProjectSettings.get_setting(key, false)
	ProjectSettings.set_setting(key, true)
	var menu: Control = auto_free(load("res://scenes/startup_menu.tscn").instantiate())
	add_child(menu)
	await get_tree().process_frame
	var found: bool = menu.view.page_open is LearnPage   # the lesson page, not a window
	var cleared: bool = not ProjectSettings.get_setting(key, false)
	ProjectSettings.set_setting(key, previous)
	assert_bool(found).is_true()
	assert_bool(cleared).is_true()


func test_normal_menu_boot_does_not_open_chapter_picker() -> void:
	var key := "niemandsland/open_game_school"
	var previous: Variant = ProjectSettings.get_setting(key, false)
	ProjectSettings.set_setting(key, false)
	var menu: Control = auto_free(load("res://scenes/startup_menu.tscn").instantiate())
	add_child(menu)
	await get_tree().process_frame
	var found: bool = menu.view.page_open != null
	ProjectSettings.set_setting(key, previous)
	assert_bool(found).is_false()

func test_menu_never_creates_game_or_atmosphere_controllers() -> void:
	assert_object(_menu.find_child("NetworkManager",true,false)).is_null()
	assert_object(_menu.find_child("AtmosphereController",true,false)).is_null()
	assert_bool(_menu.diorama._diorama_built).is_false()

## Step 44: from the menu the settings sheet is modal with the scrim (red on main: no scrim, clicks pass through to the
## menu behind it). The table keeps it see-through (e2e_settings_inventory_test).
func test_settings_from_the_menu_are_modal_with_the_scrim() -> void:
	_menu._on_settings_pressed()
	var root := _menu._settings.get_child(0) as Control
	assert_bool((root.get_node("Scrim") as ColorRect).visible).override_failure_message("no scrim in the menu").is_true()
	assert_int(root.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	_menu._settings.hide()

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
	probe.setup_lists = false
	probe.online_hub_lists = false
	probe._open_online_hub()
	var hub: OnlineHub = probe.view.page_open
	hub.public_check.button_pressed = true
	hub.prepare_button.pressed.emit()
	var started_early: bool = probe.entered_game
	probe._table_setup._select_biome("arid_desert")
	probe._table_setup._select_size("square")
	probe._table_setup._confirm()
	await get_tree().create_timer(HudTokens.DUR_COMMIT + 0.1).timeout   # the commit beat, then the screen change
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

func test_grassland_card_hands_main_a_table_biome_id() -> void:
	# The chooser's selection reaches table.set_biome unchanged (main.gd), which rejects ids outside
	# table.gd BIOMES — the Grassland card used to send "grassland" ("Unknown biome", table unchanged).
	var previous = ProjectSettings.get_setting("niemandsland/pending_table_setup",null)
	var probe = auto_free(load("res://scenes/startup_menu.tscn").instantiate())
	probe.set_script(MenuTransitionProbe)
	add_child(probe)
	probe.setup_lists = false
	probe._on_start_battle_pressed()
	var card: Button = null
	for key in probe._table_setup._biome_buttons:
		if probe._table_setup._biome_buttons[key].text == "Grassland":
			card = probe._table_setup._biome_buttons[key]
	assert_object(card).is_not_null()
	if card == null:
		return
	card.pressed.emit()
	probe._table_setup._confirm()
	var setup = ProjectSettings.get_setting("niemandsland/pending_table_setup",{})
	ProjectSettings.set_setting("niemandsland/pending_table_setup",previous)
	assert_str(setup.biome).is_equal("temperate_grassland")
	assert_bool(preload("res://scripts/table.gd").BIOMES.has(setup.biome)).is_true()

func test_core_missing_dialog_shows_the_notice_and_frees_itself() -> void:
	var card: Variant = _menu._show_core_missing_dialog()
	assert_bool(card is PromptCard).override_failure_message("the core notice is not a prompt card").is_true()
	if card is not PromptCard:
		return
	assert_bool(card.get_parent() == _menu).is_true()
	assert_str(card.title).is_equal(CoreLoadNotice.TITLE)
	assert_str(card.ok_button.text).is_equal("OK")
	assert_object(card.cancel_button).is_null()
	var words := _label_texts(card).filter(func(t: String) -> bool: return CoreLoadNotice.TEXT.contains(t))
	assert_str(" ".join(words)).is_equal(CoreLoadNotice.TEXT)   # the same words, in two paragraphs
	card.ok_button.pressed.emit()
	await get_tree().create_timer(0.45).timeout  # the card fades out first
	assert_bool(not is_instance_valid(card) or card.is_queued_for_deletion()).is_true()

func test_core_missing_warning_stays_silent_outside_the_live_scene() -> void:
	var before := _menu.get_children().filter(func(n: Node) -> bool: return n is AcceptDialog or n is PromptCard).size()
	_menu._maybe_warn_core_missing()
	var after := _menu.get_children().filter(func(n: Node) -> bool: return n is AcceptDialog or n is PromptCard).size()
	assert_int(after).is_equal(before)

## The report card: the saved path in a mono well, "Open folder" beside OK (sheet 08; red on main: one text with the path).
func test_the_report_card_shows_the_path_in_a_well_with_an_open_folder_action() -> void:
	var card: Variant = _menu._show_report_saved("/home/x/niemandsland_report_2026-11-26.zip")
	assert_bool(card is PromptCard).override_failure_message("no report card").is_true()
	if card is not PromptCard:
		return
	await get_tree().process_frame
	var well: Label = null
	for label: Node in card.find_children("*", "Label", true, false):
		if (label as Label).text.ends_with("niemandsland_report_2026-11-26.zip"):
			well = label as Label
	assert_object(well).is_not_null()
	if well != null:
		assert_object(well.get_theme_font("font")).is_same(HouseStyle.mono())
		assert_str(String(well.get_parent().theme_type_variation)).is_equal(String(HouseStyle.CARD))
	var actions: Array = card.ok_button.get_parent().get_children()
	assert_str((actions[0] as Button).text).is_equal("Open folder")
	assert_str((actions[1] as Button).text).is_equal("OK")
	(actions[0] as Button).pressed.emit()
	assert_str(str(await card.answer())).is_equal("folder")


## The one-line notice made a window as wide as its text (1,489 px); the card wraps at its own width.
func test_core_missing_notice_wraps_its_line() -> void:
	var card: Variant = _menu._show_core_missing_dialog()
	assert_bool(card is PromptCard).override_failure_message("the core notice is not a prompt card").is_true()
	if card is not PromptCard:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = card.find_child("Card", true, false)
	assert_float(panel.size.x).override_failure_message("the notice card is %s px wide" % panel.size.x).is_less(700.0)
	for label: Node in card.find_children("*", "Label", true, false):
		if CoreLoadNotice.TEXT.contains((label as Label).text):
			assert_bool((label as Label).autowrap_mode != TextServer.AUTOWRAP_OFF).is_true()
	card.ok_button.pressed.emit()


## Auto-update unavailable and Report a problem are the same OK-only card; the helper is what they call.
func test_notice_is_an_ok_only_card_that_frees_itself() -> void:
	assert_bool(_menu.has_method("_show_notice")).override_failure_message("no notice helper").is_true()
	if not _menu.has_method("_show_notice"):
		return
	var card: PromptCard = _menu.call("_show_notice", "Report a problem", "Saved an anonymised diagnostics file to:\nx")
	assert_str(card.title).is_equal("Report a problem")
	assert_object(card.cancel_button).is_null()
	card.ok_button.pressed.emit()
	await get_tree().create_timer(0.45).timeout  # the card fades out first
	assert_bool(not is_instance_valid(card) or card.is_queued_for_deletion()).is_true()


func _label_texts(root: Node) -> Array[String]:
	var texts: Array[String] = []
	for label: Node in root.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return texts


## Footer links lost letters on hover ("Help & feedba"): only the resting state had the 10 px box, the theme's
## own hover box is wider and left the text less room. RED on main (hover and pressed differ), GREEN with one box.
func test_footer_links_keep_one_box_for_every_state() -> void:
	for id: String in ["HelpBtn","CreditsBtn","ExitGameBtn"]:
		var link: Button = _menu.view.buttons[id]
		var rest := link.get_theme_stylebox("normal").get_minimum_size()
		for state: String in ["hover","pressed"]:
			var box := link.get_theme_stylebox(state).get_minimum_size()
			assert_vector(box).override_failure_message("%s: the %s box needs %s, the resting box %s" % [id,state,box,rest]).is_equal(rest)

## Step 61: the setup fades in from the menu and out to the table over the screen time (red on main: it pops in
## at full opacity and is gone at once). Reduce Motion stays off here (the test profile's default).
func test_the_table_setup_fades_in_and_out() -> void:
	var previous = ProjectSettings.get_setting("niemandsland/pending_table_setup", null)
	var probe = auto_free(load("res://scenes/startup_menu.tscn").instantiate())
	probe.set_script(MenuTransitionProbe)
	add_child(probe)
	probe.setup_lists = false
	probe._on_start_battle_pressed()
	var dialog: Window = probe._table_setup
	var content := dialog.get_child(0) as Control
	assert_float(content.modulate.a).override_failure_message("the setup pops in").is_less(0.5)
	await get_tree().create_timer(HudTokens.DUR_SCREEN + 0.15).timeout
	assert_float(content.modulate.a).is_equal_approx(1.0, 0.01)
	dialog._confirm()
	await get_tree().create_timer(HudTokens.DUR_COMMIT + 0.05).timeout   # the commit beat (step 62) comes first
	assert_bool(probe.entered_game).is_true()
	assert_bool(is_instance_valid(dialog) and dialog.visible).override_failure_message("the setup is gone at once").is_true()
	await get_tree().create_timer(HudTokens.DUR_SCREEN + 0.15).timeout
	ProjectSettings.set_setting("niemandsland/pending_table_setup", previous)
	assert_bool(is_instance_valid(dialog)).override_failure_message("the faded setup is not freed").is_false()

## Boot and menu share one colour: a cover in the sheet colour stands over the backdrop and fades off after the
## backdrop's first frame. RED on main: no cover.
func test_boot_cover_has_the_sheet_colour_and_fades_off() -> void:
	var cover := _menu.find_child("BootCover", true, false) as ColorRect
	assert_object(cover).override_failure_message("the menu has no boot cover").is_not_null()
	if cover == null:
		return
	assert_vector(Vector3(cover.color.r, cover.color.g, cover.color.b)).is_equal_approx(
		Vector3(HouseStyle.SHEET_FILL.r, HouseStyle.SHEET_FILL.g, HouseStyle.SHEET_FILL.b), Vector3.ONE * 0.001)
	assert_int(cover.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(cover.get_index()).is_less(_menu.view.get_index())
	await get_tree().create_timer(1.2).timeout
	assert_bool(not is_instance_valid(cover) or cover.is_queued_for_deletion()).override_failure_message(
		"the cover stayed over the menu").is_true()

## Step 29: a new table's loading picture names it - biome, system and size over the biome's picture; a load keeps
## the plain overlay (red on main: the overlay only says LOADING).
func test_the_loading_picture_names_a_new_table() -> void:
	var previous = ProjectSettings.get_setting("niemandsland/pending_table_setup", null)
	ProjectSettings.set_setting("niemandsland/pending_table_setup", {"size": Vector2(6, 4), "biome": "urban_ruins", "system": "gf"})
	var overlay: LoadingOverlay = auto_free(LoadingOverlay.new())
	add_child(overlay)
	if _menu.has_method("_name_the_table"):
		_menu._name_the_table(overlay)
	ProjectSettings.set_setting("niemandsland/pending_table_setup", null)   # the plain case below: no setup pending
	assert_str(overlay._title.text).override_failure_message("the overlay does not name the table").is_equal("Urban ruins")
	assert_str(overlay._subtitle.text if overlay.get("_subtitle") != null else "").is_equal("Grimdark Future · 6 × 4 ft")
	assert_object(overlay.find_child("Backdrop", true, false)).override_failure_message("no biome picture").is_not_null()
	var plain: LoadingOverlay = auto_free(LoadingOverlay.new())
	add_child(plain)
	if _menu.has_method("_name_the_table"):
		_menu._name_the_table(plain)   # no pending setup any more: the plain overlay
	ProjectSettings.set_setting("niemandsland/pending_table_setup", previous)
	assert_bool(plain._title.visible).override_failure_message("a load must keep the plain overlay").is_false()

## The music bows out: its player moves to the root, outlives the menu's scene change and ends in silence
## instead of being cut. RED on main: nothing hands the player over.
func test_music_bows_out_to_silence_on_the_root() -> void:
	assert_bool(_menu.has_method("_hand_over_music")).override_failure_message("no hand-over of the music").is_true()
	if not _menu.has_method("_hand_over_music") or _menu._music_player == null:
		return
	var player: AudioStreamPlayer = _menu._music_player
	player.volume_db = -12.0
	_menu.call("_hand_over_music")
	assert_bool(player.get_parent() == get_tree().root).is_true()
	_menu.queue_free()
	await get_tree().create_timer(0.35).timeout
	assert_bool(is_instance_valid(player)).override_failure_message("the player did not outlive the menu").is_true()
	var last := 0.0
	var deadline := Time.get_ticks_msec() + 1500
	while is_instance_valid(player) and Time.get_ticks_msec() < deadline:
		last = player.volume_db
		await get_tree().process_frame
	assert_bool(is_instance_valid(player)).override_failure_message("the player never went away").is_false()
	assert_float(last).override_failure_message("the music was not silent at the end: %s dB" % last).is_less(-60.0)


## While a sheet is open the music sits at -18 dB and returns to the bed when it closes. RED on main: no ducking.
func test_music_sits_lower_while_a_sheet_is_open() -> void:
	var player: AudioStreamPlayer = _menu._music_player
	if player == null:
		return
	player.volume_db = -12.0
	_menu._on_credits_pressed()
	await get_tree().create_timer(0.5).timeout
	assert_float(player.volume_db).override_failure_message("the music stayed at %s dB" % player.volume_db).is_equal_approx(-18.0, 0.5)
	for child: Node in _menu.get_children():
		if child is AcceptDialog:
			(child as AcceptDialog).hide()
	await get_tree().create_timer(0.5).timeout
	assert_float(player.volume_db).is_equal_approx(-12.0, 0.5)



## Step 62, the commit beat: Create table sweeps a fill across its button over DUR_COMMIT and plays the commit tone,
## and only then does the screen change (red on main: the screen changes at once, no sweep).
func test_create_table_commits_with_a_sweep_before_the_screen_changes() -> void:
	var probe = auto_free(load("res://scenes/startup_menu.tscn").instantiate())
	probe.set_script(MenuTransitionProbe)
	add_child(probe)
	probe.setup_lists = false
	probe._on_start_battle_pressed()
	var create: Button = probe._table_setup._create
	probe._table_setup._confirm()
	assert_bool(probe.entered_game).override_failure_message("the screen changed before the beat").is_false()
	assert_object(create.find_child("CommitSweep", false, false)).override_failure_message("no sweep on Create table").is_not_null()
	await get_tree().create_timer(HudTokens.DUR_COMMIT + 0.1).timeout
	assert_bool(probe.entered_game).is_true()
	assert_bool(UiFeedback.has_method("play_commit")).override_failure_message("no commit tone").is_true()


## Spec 97 (step 97.11): Create table carries who is at the table. Solo stores NACHTMAHR's list and no online key;
## the online room from "Start battle" is a private room under the saved name; a hub start switched to Solo is no
## room; the online card locks the Automatic rules pick (red before: no opponent in the setup's hand-over).
const OPP_KEY := "niemandsland/pending_table_opponent"
const HOST_KEYS := ["niemandsland/pending_internet_lobby", "niemandsland/internet_is_host",
	"niemandsland/internet_relay_url", "niemandsland/player_name", "niemandsland/internet_public"]
const MANIFEST := {"alien_hives": {"name": "Alien Hives", "lists": [{"points": 3000, "file": "alien_hives_3000.json"}]}}


func _create_with(who: String, host_settings: Dictionary = {}) -> Dictionary:
	var keys: Array = HOST_KEYS + [OPP_KEY, "niemandsland/pending_table_setup", "niemandsland/pending_table_layout"]
	var previous := {}
	for key: String in keys:
		previous[key] = ProjectSettings.get_setting(key, null)
		ProjectSettings.set_setting(key, null)
	var probe = auto_free(load("res://scenes/startup_menu.tscn").instantiate())
	probe.set_script(MenuTransitionProbe)
	add_child(probe)
	probe.setup_lists = false
	probe._show_table_setup(host_settings)
	var opponent: SetupOpponent = probe._table_setup.get("opponent")
	if opponent == null:
		for key: String in keys:
			ProjectSettings.set_setting(key, previous[key])
		return {}
	opponent.set_manifest(MANIFEST)
	opponent.choose_who(who)
	probe._table_setup._confirm()
	await get_tree().create_timer(HudTokens.DUR_COMMIT + 0.1).timeout
	var result := {}
	for key: String in keys:
		result[key] = ProjectSettings.get_setting(key, null)
		ProjectSettings.set_setting(key, previous[key])
	return result


func test_solo_hands_nachtmahrs_list_over_and_no_room() -> void:
	var result := await _create_with("solo")
	assert_dict(result).override_failure_message("no opponent in the setup").is_not_empty()
	if result.is_empty():
		return
	assert_dict(result[OPP_KEY]).is_equal({"who": "solo", "file": "alien_hives_3000.json", "slot": 2,
		"label": "NACHTMAHR · Alien Hives · 3000"})
	assert_object(result["niemandsland/pending_internet_lobby"]).is_null()


func test_an_online_room_from_start_battle_is_private_under_the_saved_name() -> void:
	var result := await _create_with("online")
	if result.is_empty():
		fail("no opponent in the setup")
		return
	assert_bool(result["niemandsland/pending_internet_lobby"]).is_true()
	assert_bool(result["niemandsland/internet_is_host"]).is_true()
	assert_bool(result["niemandsland/internet_public"]).is_false()
	assert_str(str(result["niemandsland/internet_relay_url"])).is_equal(InternetLobby.DEFAULT_RELAY_URL)
	assert_str(str(result["niemandsland/player_name"])).is_equal(PlayerIdentity.load_saved_name())
	assert_str(str(result[OPP_KEY].who)).is_equal("online")


func test_a_hub_start_switched_to_solo_opens_no_room() -> void:
	var hub := OnlineHub.host_settings("Ashfall", InternetLobby.DEFAULT_RELAY_URL, true)
	var result := await _create_with("solo", hub)
	if result.is_empty():
		fail("no opponent in the setup")
		return
	for key: String in HOST_KEYS:
		assert_object(result[key]).override_failure_message(key).is_null()


func test_the_online_card_locks_automatic_rules() -> void:
	var probe = auto_free(load("res://scenes/startup_menu.tscn").instantiate())
	probe.set_script(MenuTransitionProbe)
	add_child(probe)
	probe.setup_lists = false
	probe._show_table_setup()
	var dialog: TableSizeDialog = probe._table_setup
	dialog.selected_rules = RulesAutomation.Level.AUTOMATIC
	var opponent: SetupOpponent = dialog.get("opponent")
	if opponent == null:
		fail("no opponent in the setup")
		return
	opponent.choose_who("online")
	assert_int(dialog.selected_rules).is_equal(RulesAutomation.Level.MANUAL)
	assert_bool(dialog.online).is_true()
	dialog._on_close()


## Spec 97 (step 97.12): Create table remembers the opponent; the next setup opens on it (a hub start does not).
func test_the_next_setup_opens_on_the_remembered_opponent() -> void:
	await _create_with("local")
	var probe = auto_free(load("res://scenes/startup_menu.tscn").instantiate())
	probe.set_script(MenuTransitionProbe)
	add_child(probe)
	probe.setup_lists = false
	probe._show_table_setup()
	assert_str(probe._table_setup.opponent.who).is_equal("local")
	probe._table_setup._on_close()


## Sheet 08 / 01: the core notice is a warning, its title gold; the version line has its dot (red before: accent title,
## no dot).
func test_the_core_notice_title_is_gold_and_the_version_line_has_its_dot() -> void:
	var card: PromptCard = _menu._show_core_missing_dialog()
	var title := card.get("_title_label") as Label
	assert_str(title.get_theme_color("font_color").to_html(false)).is_equal(HouseStyle.GOLD.to_html(false))
	card.ok_button.pressed.emit()
	assert_str(_menu.view.version.text).contains("OnePageRules  ·  ")
