extends Control
## Native menu over a live biome vignette. This controller owns existing save,
## teaching and network routes; StartupMenuView handles grouping and layout.

# === Constants ===

const MUSIC_VOLUME_DB := -12.0
const MUSIC_FADE_IN_S := 2.5
## While a sheet is open the music sits lower (the sheet is what the player listens to); it ends in silence
## over this long when the menu hands over to the table instead of being cut.
const MUSIC_SHEET_DB := -18.0
const MUSIC_BOW_OUT_S := 0.6
const MUSIC_RAMP_DB_PER_S := 30.0

## Trial by Fire: the width (px) every wrapping label of the list is given, and the least size (px) of the
## scrolling list. Without a width floor the labels wrap at one letter and the window grows past the screen.


# === Native menu view and preserved game routes ===
const MenuView = preload("res://scripts/startup_menu_view.gd")
@onready var diorama: MenuDiorama = %Diorama
var view: Control
var _settings: CanvasLayer
var _table_setup: TableSizeDialog
var _transitioning := false
var continue_btn: Button
var start_battle_btn: Button
var online_hub_lists := true   # false: the online hub asks the relay only on refresh (tests)
var setup_lists := true   # false: the setup never asks the CDN for NACHTMAHR's lists (tests)
var _ai_lists: AiLists
var load_battle_btn: Button
var report_problem_btn: Button
var credits_btn: Button
var exit_game_btn: Button

# === Private variables ===

var _save_browser: SaveBrowser
var _exit_card: PromptCard
var _continue_path := ""
var _music_player: AudioStreamPlayer = null
var _music_tween: Tween
var _whats_new: WhatsNewDialog

# === Lifecycle ===

func _ready() -> void:
	# Keep Godot's built-in dialog controls in the game's English UI language too.
	TranslationServer.set_locale("en")
	print("[Boot] Niemandsland %s build %s" % [ProjectSettings.get_setting("application/config/version","?"),ProjectSettings.get_setting("application/config/build_hash","local-dev")])
	var file_to_open := _get_save_from_cmdline()
	if not file_to_open.is_empty():
		ProjectSettings.set_setting("niemandsland/pending_load_path",file_to_open)
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return
	theme = ThemeManager.get_current_theme()
	view = MenuView.new()
	view.name = "SafeArea"
	add_child(view)
	_add_boot_cover()
	continue_btn = view.buttons.ContinueBtn
	start_battle_btn = view.buttons.StartBattleBtn
	load_battle_btn = view.buttons.LoadBattleBtn
	report_problem_btn = view.buttons.ReportProblemBtn
	credits_btn = view.buttons.CreditsBtn
	exit_game_btn = view.buttons.ExitGameBtn
	var save := SaveManager.latest_save_info()
	_continue_path = str(save.get("path",""))
	view.set_save(save)
	view.version.text = "Fan project for OnePageRules     " + version_string()
	continue_btn.pressed.connect(_on_continue_pressed)
	start_battle_btn.pressed.connect(_on_start_battle_pressed)
	view.buttons.LearnBtn.pressed.connect(_open_learn_page.bind(false))
	view.buttons.OnlineBtn.pressed.connect(_open_online_hub)
	load_battle_btn.pressed.connect(_on_load_battle_pressed)
	report_problem_btn.pressed.connect(_on_report_problem_pressed)
	credits_btn.pressed.connect(_on_credits_pressed)
	exit_game_btn.pressed.connect(_on_exit_pressed)
	view.buttons.SettingsBtn.pressed.connect(_on_settings_pressed)
	view.buttons.HelpTutorialBtn.pressed.connect(_on_tutorial_pressed)
	view.buttons.WhatsNewBtn.pressed.connect(_show_whats_new)
	view.news_card.pressed.connect(_show_whats_new)
	diorama.first_frame_rendered.connect(_on_first_frame_rendered, CONNECT_ONE_SHOT)
	diorama.loading_progress.connect(_on_diorama_loading)
	diorama.diorama_ready.connect(_on_diorama_ready)
	diorama.rebuild_started.connect(_on_diorama_rebuild_started)
	diorama.lighting_changed.connect(func(controller: Node) -> void:
		if is_instance_valid(_settings):
			_settings.lighting_controller = controller)
	_start_menu_music()
	child_entered_tree.connect(func(node: Node) -> void:
		if node is Window:
			node.visibility_changed.connect(_duck_music_for_sheets))
	_maybe_check_for_updates()
	_maybe_warn_core_missing()
	if get_tree().current_scene == self:
		(continue_btn if continue_btn.visible else start_battle_btn).grab_focus.call_deferred()
	if ProjectSettings.get_setting("niemandsland/open_game_school", false):
		ProjectSettings.set_setting("niemandsland/open_game_school", false)
		_open_learn_page.call_deferred(true)
	_maybe_show_whats_new.call_deferred()


func _maybe_show_whats_new() -> void:
	if get_tree().current_scene != self or not WhatsNewContent.should_show():
		return
	if _is_fresh_profile():
		WhatsNewContent.mark_seen()
		return
	# Let another startup dialog (for example the chapter picker) finish first.
	for child in get_children():
		if child is Window and child.visible:
			await child.visibility_changed
			_maybe_show_whats_new.call_deferred()
			return
	_show_whats_new()


func _is_fresh_profile() -> bool:
	return WhatsNewContent.is_fresh_profile()


func _show_whats_new() -> void:
	view.close_route()
	if not is_instance_valid(_whats_new):
		_whats_new = WhatsNewDialog.new()
		add_child(_whats_new)
		MenuDialog.attach_scrim(_whats_new)
	_whats_new.open()


## The menu arrives once the backdrop has put its first frame up; tests mounting the menu stay still.
func _on_first_frame_rendered() -> void:
	if get_tree().current_scene == self:
		view.play_arrival()


## The boot splash is the house sheet colour: a full-screen cover of that colour stands between the backdrop and
## the menu until the backdrop's first frame, then fades off, so boot and menu share one colour.
func _add_boot_cover() -> void:
	var cover := ColorRect.new()
	cover.name = "BootCover"
	cover.color = HouseStyle.SHEET_FILL
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cover)
	move_child(cover,view.get_index())
	diorama.first_frame_rendered.connect(func() -> void:
		var fade := create_tween()
		fade.tween_property(cover,"color:a",0.0,MenuDiorama.REVEAL_FADE_S)
		fade.tween_callback(cover.queue_free),CONNECT_ONE_SHOT)


func _on_diorama_loading(label: String, ratio: float) -> void:
	view.status.text = "%s … %d %%" % [label,roundi(ratio*100)]


func _on_diorama_rebuild_started() -> void:
	view.status.text = "Preparing background …"


func _on_diorama_ready() -> void:
	var biome := TableSizeDialog.table_biome(diorama.biome)
	view.status.text = "ON THE TABLE · %s · NIGHT" % str(TableSizeDialog.BIOMES.get(biome,[diorama.biome])[0]).to_upper()
	if is_instance_valid(_settings):
		_settings.lighting_controller = diorama.get_lighting_controller()
		_settings._sync_ui_from_controller()


func _on_settings_pressed() -> void:
	view.close_route()
	if not is_instance_valid(_settings):
		_settings = load("res://scripts/lighting_panel.gd").new()
		add_child(_settings)
		_settings.initialize(diorama.get_lighting_controller())
		_settings.set_modal(true)   # in the menu the sheet is modal with the scrim; at the table it stays see-through
		var label := Label.new()
		label.text = "Menu background"
		_settings._page("Display").add_child(label)
		var choices := OptionButton.new()
		for title in ["Urban ruins","Alien jungle","Grassland","Arid desert","Frozen tundra","Volcanic ash"]:
			choices.add_item(title)
		choices.select(MenuDiorama.Battlefield.BIOMES.find(diorama.biome))
		_settings._page("Display").add_child(choices)
		choices.item_selected.connect(func(index: int) -> void:
			diorama.set_biome(MenuDiorama.Battlefield.BIOMES[index])
			var config := ConfigFile.new()
			config.set_value("menu","biome",diorama.biome)
			config.save("user://menu.cfg"))
	_settings.show()


# === Button handlers ===

func _on_continue_pressed() -> void:
	if _continue_path.is_empty():
		return
	ProjectSettings.set_setting("niemandsland/pending_load_path", _continue_path)
	await _commit_beat(continue_btn)
	_transition_to_game()


## The commit beat (motion table): the commit tone, then a fill sweeps across the pressed button over
## HudTokens.DUR_COMMIT (ease-in) before the screen changes. With Reduce Motion only the tone.
func _commit_beat(button: Control) -> void:
	UiFeedback.play_commit()
	if UiMotion.reduced() or not is_instance_valid(button) or not button.is_visible_in_tree():
		return
	var sweep := ColorRect.new()
	sweep.name = "CommitSweep"
	sweep.color = Color(HouseStyle.INK, HouseStyle.PRESS_ALPHA)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sweep.size = Vector2(0.0, button.size.y)
	button.add_child(sweep)
	var tween := button.create_tween()
	tween.tween_property(sweep, "size:x", button.size.x, HudTokens.DUR_COMMIT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tween.finished


func _on_start_battle_pressed() -> void:
	_show_table_setup()


func _show_table_setup(host_settings: Dictionary = {}) -> void:
	if is_instance_valid(_table_setup):
		return
	_table_setup = TableSizeDialog.new()
	_table_setup.online = not host_settings.is_empty()   # Create room: online stays Manual
	_table_setup.layout_step = true   # step 04, "Lay out the table"
	_table_setup.selected_system = GameSystem.default_pick()   # the last pick; the dialog applies it in _ready
	add_child(_table_setup)
	_table_setup.set_biomes(MenuDiorama.Battlefield.BIOMES,diorama.biome)
	if not host_settings.is_empty():
		_table_setup.opponent.choose_who("online")   # from the hub: the online room
	if setup_lists:
		_load_setup_lists(_table_setup.opponent)
	_table_setup.size_chosen.connect(_on_table_setup_chosen.bind(host_settings))
	_table_setup.cancelled.connect(_on_table_setup_cancelled)
	view.hide()
	_table_setup.popup()
	_fade_setup(_table_setup, 0.0, 1.0)


## The setup page fades in from the menu and out to the table (its content, over the screen time), as the
## table's own chooser does in main.gd. Instant with Reduce Motion. `free_after` frees the dialog at the end.
func _fade_setup(dialog: Window, from: float, to: float, free_after := false) -> void:
	var content := dialog.get_child(0) as Control
	if UiMotion.reduced() or content == null:
		if free_after:
			dialog.queue_free()
		return
	content.modulate.a = from
	var tween := dialog.create_tween()
	tween.tween_property(content, "modulate:a", to, HudTokens.DUR_SCREEN).set_trans(Tween.TRANS_SINE)
	if free_after:
		tween.tween_callback(dialog.queue_free)


func _on_table_setup_chosen(size_feet: Vector2, host_settings: Dictionary) -> void:
	ProjectSettings.set_setting("niemandsland/pending_table_setup",{"size":size_feet,"biome":_table_setup.selected_biome,"rules":_table_setup.selected_rules,"system":_table_setup.selected_system})
	GameSystem.remember_pick(_table_setup.selected_system)
	if RulesAutomation.ui_enabled() and not _table_setup.online:   # the card, not the opener
		RulesAutomation.remember_pick(_table_setup.selected_rules)
	if _table_setup.opponent.who == "online":   # the hub's settings, or a private room under the saved name
		if host_settings.is_empty():
			host_settings = OnlineHub.host_settings(PlayerIdentity.load_saved_name(), InternetLobby.DEFAULT_RELAY_URL, false)
		for key in host_settings:
			ProjectSettings.set_setting(key,host_settings[key])
	_table_setup.layout.commit()   # the chosen layout travels to the table (PendingLayout)
	_table_setup.opponent.commit()   # and who is at the table (PendingOpponent)
	var setup := _table_setup
	_table_setup = null
	await _commit_beat(setup._create)
	if UiMotion.reduced():
		setup.hide()
	_fade_setup(setup, 1.0, 0.0, true)   # fades out under the loading picture's fade-in
	_transition_to_game()


## NACHTMAHR's list index for step 04 of the setup (bundle, CDN, cache); the Solo card waits for it.
func _load_setup_lists(opponent: SetupOpponent) -> void:
	if _ai_lists == null:
		_ai_lists = AiLists.new()
		add_child(_ai_lists)
	opponent.loading = true
	opponent.set_manifest(await _ai_lists.manifest())


func _on_table_setup_cancelled() -> void:
	_table_setup.queue_free()
	_table_setup = null
	view.show()
	var hub := view.page_open as OnlineHub   # "Back to main menu" of an online setup returns to the hub
	(hub.prepare_button if hub != null else start_battle_btn).grab_focus()



## "Learn the controls" (Help): the lesson page, as "Learn to play".
func _on_tutorial_pressed() -> void:
	_open_learn_page(false)


## The lesson page in place of the menu's list; `returned` after a lesson (Trial by Fire is selected then).
func _open_learn_page(returned: bool) -> void:
	var tutorial := TutorialProgress.new()
	tutorial.load_from_disk()
	var trial := SpielschuleProgress.new()
	trial.load_from_disk()
	var page := LearnPage.new().setup(tutorial, trial, returned)
	page.tutorial_requested.connect(_launch_tutorial)
	page.scenario_requested.connect(_launch_scenario)
	view.open_page(page)


## Arm the runtime-only tutorial flags that main.gd reads in _ready(). Split out of
## _launch_tutorial so the entry contract (which flags, which values) is testable
## without the scene swap. Never persisted to project.godot, mirroring harness_mode.
func _arm_tutorial_flags(lesson_id: String) -> void:
	ProjectSettings.set_setting("niemandsland/tutorial_mode", true)
	ProjectSettings.set_setting("niemandsland/tutorial_lesson", lesson_id)


## Open the prepared table for a guided tutorial run. An empty lesson id means "resume":
## the director runs assessment/first-incomplete logic itself.
func _launch_tutorial(lesson_id: String) -> void:
	_arm_tutorial_flags(lesson_id)
	_transition_to_game()


## Hand the picked chapter's bundled scenario to the game scene through the SAME runtime-only
## ProjectSettings seam the tutorial uses (never persisted to project.godot). main.gd feeds
## scenario_path into the NORMAL pending-load path (= same load path as a save-load), pauses autosave
## and marks the chapter done. See main.gd _ready().
func _launch_scenario(chapter: Dictionary) -> void:
	ProjectSettings.set_setting("niemandsland/scenario_mode", true)
	ProjectSettings.set_setting("niemandsland/scenario_path", String(chapter.get("scenario", "")))
	ProjectSettings.set_setting("niemandsland/scenario_chapter", String(chapter.get("id", "")))
	_transition_to_game()


func _on_load_battle_pressed() -> void:
	_save_browser = SaveBrowser.new()
	_save_browser.load_requested.connect(_on_save_chosen)
	_save_browser.closed.connect(load_battle_btn.grab_focus)
	_save_browser.open(self)


## A row's Load plays the commit beat on its button; a file picked through "Browse files…" loads at once.
func _on_save_chosen(path: String, button: Button) -> void:
	if button != null:
		await _commit_beat(button)
	_on_load_file_selected(path)


## Export an ANONYMISED diagnostics bundle (system info + scrubbed recent log) to the
## Desktop and open the folder, so a player can review and attach it to a bug report.
func _on_report_problem_pressed() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := DiagnosticsReporter.export_report(stamp)
	if path.is_empty():
		_show_notice("Report a problem", "Could not write the diagnostics file.\nThe log lives at user://logs/niemandsland.log.")
	else:
		_report_saved(_show_report_saved(path), path)


## The report card: the path in a mono well, "Open folder" beside OK, the privacy line in the caption style.
func _show_report_saved(path: String) -> PromptCard:
	var card := PromptCard.new("Report a problem", "Saved an anonymised diagnostics file to:", "OK", "")
	card.animate = true
	card.menu_scale = true
	var well := HouseStyle.label(path, HouseStyle.BODY)
	well.add_theme_font_override("font", HouseStyle.mono())
	well.add_theme_font_size_override("font_size", 14)
	well.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	well.custom_minimum_size.x = PromptCard.WIDTH - 2 * HouseStyle.MENU_PAD_PANEL - 2 * HouseStyle.PAD_CARD_X
	card.rows.add_child(HouseStyle.card(well))
	var privacy := HouseStyle.label("Attach it to a bug report — it carries no player names, room codes or your username.", HouseStyle.CAPTION)
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy.custom_minimum_size.x = PromptCard.WIDTH - 2 * HouseStyle.MENU_PAD_PANEL
	card.rows.add_child(privacy)
	card.add_action("Open folder", "folder")
	add_child(card)
	return card


## Waits for the report card; "Open folder" shows the file in the system's file manager.
func _report_saved(card: PromptCard, path: String) -> void:
	if await card.answer() == "folder":
		OS.shell_show_in_file_manager(ProjectSettings.globalize_path(path))


## In-app credits / license summary, so the model attribution (CC-BY-SA) is visible to players,
## not only in the repo docs. Full text lives in THIRD_PARTY.md.
func _on_credits_pressed() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Credits & licenses"
	# As plain dialog_text these ~12 licence lines size the window themselves, with nothing
	# stopping it (and its OK button) from growing past a small screen. A scrolled body with a
	# FIXED viewport is the clamp here: an AcceptDialog wraps its contents (wrap_controls), so
	# its window size is always the contents' minimum — an outer keep_window_reachable() would
	# be overruled the moment it pops up (measured: clamped to 520x400, popped up at 452x317).
	var scroll := ScrollContainer.new()
	# 520 x 420 shows whole lines; never larger than the window leaves room for.
	var room := get_viewport().get_visible_rect().size - Vector2(160, 220)
	scroll.custom_minimum_size = Vector2(minf(520.0, room.x), minf(420.0, room.y))
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var head := Label.new()
	head.autowrap_mode = TextServer.AUTOWRAP_WORD
	head.text = "Niemandsland — © the Niemandsland project."
	var body := Label.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.text = "OnePageRules army data is loaded at runtime via the Army Forge API; it is not bundled.\n\n" \
		+ "Full details: THIRD_PARTY.md in the project repository.\n\n" \
		+ "Niemandsland is a free, non-profit, open-source fan project (MIT code, CC-BY-SA generated assets). It is not affiliated with, endorsed by, or sponsored by OnePageRules. It bundles no OPR rules text, files, art or marks; the rules are OPR's, available free at onepagerules.com, and army lists come from OPR's Army Forge. Responsible: Andreas Kesberg, privacy@niemandsland.xyz."
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", HouseStyle.GAP_SECTION)
	column.add_child(head)
	column.add_child(_licence_rows())
	column.add_child(body)
	scroll.add_child(column)
	var content := VBoxContainer.new()
	content.add_child(scroll)
	MenuDialog.add_header(dialog, content)
	dialog.add_child(content)
	MenuDialog.style(dialog)
	# MenuDialog.open takes the wrapped size FIRST: popup_centered() centres whatever size the window
	# carries at that moment, and the wrap to the contents happens afterwards.
	MenuDialog.open(self, dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


## The five licence lines as a table (credits): the name muted at the left, the licence at the right, 36 px rows with
## a hairline between them.
func _licence_rows() -> VBoxContainer:
	var rows := VBoxContainer.new()
	rows.name = "LicenceRows"
	rows.add_theme_constant_override("separation", 0)
	var lines := [["Game code", "MIT License"], ["3D miniatures & terrain", "generated project assets, CC-BY-SA 4.0"],
			["Fonts", "SIL Open Font License"], ["UI icons", "Phosphor Icons (MIT)"], ["Engine", "Godot Engine (MIT)"]]
	for i in lines.size():
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 36
		var name_label := HouseStyle.label(lines[i][0], HouseStyle.CAPTION)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var licence := HouseStyle.label(lines[i][1], HouseStyle.BODY)
		licence.add_theme_font_size_override("font_size", HouseStyle.MENU_FONT_CAPTION)
		licence.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(name_label)
		row.add_child(licence)
		rows.add_child(row)
		if i < lines.size() - 1:
			var rule := ColorRect.new()
			rule.color = HouseStyle.LINE
			rule.custom_minimum_size.y = 1
			rows.add_child(rule)
	return rows


## EXIT GAME / ESC ask first. Everywhere else in the project ESC only closes a surface, so
## quitting the process on a single stray keypress was the hardest break in the interaction
## language — and unrecoverable (a CONTINUE save one keypress away is not the same thing).
func _on_exit_pressed() -> void:
	# is_instance_valid still reports true for the rest of the frame after queue_free, so the
	# very ESC that closes this card cannot immediately open a second one. The card takes every key
	# while it stands (Enter = Quit, Esc = Back), so the menu's own Esc handler never sees them.
	if is_instance_valid(_exit_card):
		return
	_exit_card = PromptCard.new("Quit Niemandsland", "Are you sure you want to quit Niemandsland?", "Quit", "Back")
	_exit_card.animate = true
	_exit_card.menu_scale = true
	add_child(_exit_card)
	# CANCEL is the safe answer, so it — not QUIT — starts focused, and Enter takes it.
	_exit_card.cancel_button.focus_mode = Control.FOCUS_ALL
	_exit_card.cancel_button.grab_focus()
	if await _exit_card.answer():
		get_tree().quit()

# === Update check =====

## Asks UpdateChecker whether a newer release exists and, on a hit, shows the prompt.
## Guarded so it only runs for the live main scene — gdUnit's scene_runner adds the
## menu under /root directly (not as current_scene), so tests never hit the network.
func _maybe_check_for_updates() -> void:
	if get_tree().current_scene != self:
		return
	if OS.has_feature("web"):
		# Web/itch builds are always the latest deploy — nothing to update.
		return
	if not UpdateChecker.update_available.is_connected(_on_update_available):
		UpdateChecker.update_available.connect(_on_update_available)
	UpdateChecker.check_for_updates()


## One-core phase 1: an exported build that lost its rules core says so once per start. Warn only
## (the game stays playable on the decision tree). Same live-scene guard as the update check, so
## tests stay silent. _maybe_show_whats_new waits for any visible child Window, so the two never overlap.
func _maybe_warn_core_missing() -> void:
	if get_tree().current_scene != self:
		return
	if not CoreLoadNotice.should_show(OS.has_feature("template"), ClassDB.class_exists("NmlCore")):
		return
	if is_instance_valid(_whats_new) and _whats_new.visible:
		await _whats_new.visibility_changed
		await get_tree().process_frame  # Native modal ownership clears after the hide signal.
	_show_core_missing_dialog()


func _show_core_missing_dialog() -> PromptCard:
	# The closing instruction stands in its own paragraph (the same words).
	var text := CoreLoadNotice.TEXT.replace(" Download the full game", "\n\nDownload the full game")
	return _show_notice(CoreLoadNotice.TITLE, text)


## A plain notice: one house card with an OK (Enter or Esc closes it); it wraps at the card's own width and
## frees itself once answered.
func _show_notice(title: String, text: String) -> PromptCard:
	var card := PromptCard.new(title, text, "OK", "")
	card.animate = true
	card.menu_scale = true
	add_child(card)
	card.answer()
	return card


func _on_update_available(latest_version: String, release_url: String, release_notes: String) -> void:
	if is_instance_valid(_whats_new) and _whats_new.visible:
		await _whats_new.visibility_changed
		await get_tree().process_frame  # Native modal ownership clears after the hide signal.
	var prompt := UpdatePrompt.new()
	prompt.setup(UpdateChecker.get_current_version(), latest_version, release_url, release_notes)
	prompt.confirmed.connect(_on_update_prompt_closed.bind(prompt, true))
	prompt.canceled.connect(_on_update_prompt_closed.bind(prompt, false))
	MenuDialog.open(self, prompt)
	# Keep the dialog (and its buttons) on screen even on small displays / long changelogs.
	UiPolish.keep_window_reachable(prompt, Vector2i(480, 460))


func _on_update_prompt_closed(prompt: UpdatePrompt, download: bool) -> void:
	if prompt.is_skip_checked():
		UpdateChecker.set_skip_version(prompt.latest_version)
	var url := prompt.release_url
	prompt.queue_free()
	if download:
		_start_self_update(url)


## Download + install the update in place, then relaunch. Any failure — or a non-zip release URL
## (e.g. the release page when no matching asset was found) — falls back to opening the URL in a
## browser, so the in-game update is never worse than the old manual download flow.
func _start_self_update(url: String) -> void:
	if not url.ends_with(".zip"):
		OS.shell_open(url)
		return
	var dialog := UpdateProgressDialog.new()
	add_child(dialog)
	dialog.popup_centered()
	var updater := SelfUpdater.new()
	add_child(updater)
	updater.progress.connect(_on_update_progress.bind(dialog))
	updater.restarting.connect(_on_update_restarting.bind(dialog, updater))
	updater.update_failed.connect(_on_update_failed.bind(dialog, updater, url))
	updater.install(url)


func _on_update_progress(stage: String, ratio: float, dialog: AcceptDialog) -> void:
	if is_instance_valid(dialog):
		(dialog as UpdateProgressDialog).show_progress(stage, ratio)


## Files are staged, the relaunch is starting. Clean up like the failure path does: the
## success path used to be the one branch that left the (button-less, unclosable) progress
## dialog and the updater in the tree — harmless only for as long as SelfUpdater really
## quits right after emitting this.
func _on_update_restarting(dialog: AcceptDialog, updater: SelfUpdater) -> void:
	if is_instance_valid(dialog):
		dialog.dialog_text = "Restarting…"
		dialog.queue_free()
	if is_instance_valid(updater):
		updater.queue_free()


func _on_update_failed(reason: String, dialog: AcceptDialog, updater: SelfUpdater, url: String) -> void:
	if is_instance_valid(updater):
		updater.queue_free()
	if is_instance_valid(dialog):
		dialog.queue_free()
	_show_notice("Auto-update unavailable", "Couldn't auto-update (%s).\nThe download page has opened — unzip it over your Niemandsland folder." % reason)
	# Open the browser only AFTER the message is up: shell_open raises the browser over the
	# game window, so a dialog shown afterwards is hidden behind it and never read.
	OS.shell_open(url)  # fallback: the player downloads + unzips manually

# ===== Online Multiplayer =====

## "Play online": the online hub in place of the menu's list. Create hands its settings to the table setup (the
## hub stays open under it); a join plays the commit beat on its button, then joins.
func _open_online_hub() -> void:
	var hub := OnlineHub.new()
	hub.lists_on_open = online_hub_lists
	hub.host_requested.connect(_show_table_setup)
	hub.join_requested.connect(_on_hub_join)
	view.open_page(hub)


func _on_hub_join(code: String, url: String, player_name: String, button: Button) -> void:
	await _commit_beat(button)
	_join_room_and_transition(code, url, player_name)


## Persists the name, hands the join settings to the main scene and transitions.
## Shared by the Join dialog and the room browser (the connection happens in main).
func _join_room_and_transition(code: String, url: String, player_name: String) -> void:
	PlayerIdentity.save_name(player_name)
	ProjectSettings.set_setting("niemandsland/pending_internet_lobby", true)
	ProjectSettings.set_setting("niemandsland/internet_is_host", false)
	ProjectSettings.set_setting("niemandsland/internet_relay_url", url)
	ProjectSettings.set_setting("niemandsland/internet_room_code", code)
	ProjectSettings.set_setting("niemandsland/player_name", player_name)
	_transition_to_game()


# ===== Shared =====

## A new table (the setup just stored it; continue, load and join keep the plain overlay): the overlay names it -
## "Urban ruins", "Grimdark Future · 6 × 4 ft" - over the biome's picture (sheet 06).
func _name_the_table(overlay: LoadingOverlay) -> void:
	var setup: Variant = ProjectSettings.get_setting("niemandsland/pending_table_setup", null)
	var loading := not str(ProjectSettings.get_setting("niemandsland/pending_load_path", "")).is_empty()
	if loading or not setup is Dictionary or not (setup as Dictionary).has("biome"):
		return
	var biome := str(setup.biome)
	var feet: Vector2 = setup.get("size", Vector2(6, 4))
	overlay.set_label("PREPARING YOUR TABLE")
	overlay.set_title(TableSizeDialog.BIOMES.get(biome, [biome])[0])
	overlay.set_subtitle("%s · %s × %s ft" % [GameSystem.label(str(setup.get("system", GameSystem.DEFAULT_ID))),
		TableSizeDialog.number(feet.x), TableSizeDialog.number(feet.y)])
	overlay.set_backdrop(load(TableSizeDialog._preview_path(biome)) as Texture2D)


func _transition_to_game() -> void:
	if _transitioning:
		return
	_transitioning = true
	view.hide()
	_hand_over_music()
	const GAME_SCENE := "res://scenes/main.tscn"
	# Black loading overlay added to the SceneTree root so it survives the scene swap
	# (no grey flash). The game scene takes a few seconds to load; show the bar against
	# the threaded load's real progress, then hand over to the loaded scene. main.gd
	# dismisses the overlay once its own backdrop is up.
	var overlay := LoadingOverlay.new()
	overlay.add_to_group("transition_overlay")
	get_tree().root.add_child(overlay)
	overlay.set_label("LOADING")
	_name_the_table(overlay)

	if ResourceLoader.load_threaded_request(GAME_SCENE) != OK:
		get_tree().change_scene_to_file(GAME_SCENE)  # fallback: no progress, but works
		return
	var progress: Array = []
	while true:
		var status := ResourceLoader.load_threaded_get_status(GAME_SCENE, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			overlay.set_progress(1.0)
			get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(GAME_SCENE))
			return
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			get_tree().change_scene_to_file(GAME_SCENE)  # failed/invalid -> fallback
			return
		overlay.set_progress(progress[0] if progress.size() > 0 else 0.0)
		await get_tree().process_frame


func _on_load_file_selected(path: String) -> void:
	ProjectSettings.set_setting("niemandsland/pending_load_path", path)
	_transition_to_game()


## Check command-line arguments for an .nml file path.
## This handles the case where the user double-clicks an .nml file in the OS file manager
## or drags a file onto the application executable.
func _get_save_from_cmdline() -> String:
	# OS.get_cmdline_user_args() returns args after "--" separator (Godot convention)
	for arg in OS.get_cmdline_user_args():
		if arg.ends_with(".nml") and FileAccess.file_exists(arg):
			return arg

	# Also check regular args (some OS pass file path as first arg directly)
	for arg in OS.get_cmdline_args():
		if arg.begins_with("-"):
			continue
		if arg.ends_with(".nml") and FileAccess.file_exists(arg):
			return arg

	return ""


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or _transitioning:
		return
	for child in get_children():
		if child is Window and child.visible:
			return
	if event.keycode == KEY_ESCAPE:
		if view.page_open != null:
			view.close_page()
		elif view.route_panel.visible:
			view.close_route()
		else:
			_on_exit_pressed()
		get_viewport().set_input_as_handled()


# ===== Static (testable) =====

## Version string for the footer: the game version from the project config plus the rules version
## the maps declare (major.minor). An unreadable map leaves today's text unchanged.
static func version_string() -> String:
	var version := "v%s" % ProjectSettings.get_setting("application/config/version", "?")
	var rules := OPRApiClient._major_minor(OPRApiClient.rules_core_version("gf"))
	if rules.is_empty():
		return version
	return "%s · rules %s" % [version, rules]

func _start_menu_music() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = AudioManager.BUS_MUSIC
	_music_player.volume_db = -80.0
	add_child(_music_player)

	var library := AmbienceLibrary.new()
	add_child(library)
	var stream: AudioStream = library.get_stream("menu_drone")
	if stream == null:
		_music_player.stream = AmbienceSynth.make_menu_drone_pad()
		# Fetch the real recording in the background (live menu only — never in tests)
		# and hot-swap once cached.
		if get_tree().current_scene == self and not OS.has_feature("web"):
			_fetch_menu_drone(library)
	else:
		_music_player.stream = stream
	_music_player.play()
	_ramp_music(MUSIC_VOLUME_DB, MUSIC_FADE_IN_S)


## The music moves to `target_db` over `seconds` (by default at MUSIC_RAMP_DB_PER_S, at least 200 ms); a ramp in
## progress is replaced from where it stands.
func _ramp_music(target_db: float, seconds: float = -1.0) -> void:
	if _music_player == null or not is_instance_valid(_music_player):
		return
	if _music_tween != null:
		_music_tween.kill()
	if seconds < 0.0:
		seconds = maxf(0.2, absf(target_db - _music_player.volume_db) / MUSIC_RAMP_DB_PER_S)
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", target_db, seconds)


## A sheet (a menu window) open -> the music sits at MUSIC_SHEET_DB, closed -> back at the bed.
func _duck_music_for_sheets() -> void:
	var sheet_open := get_children().any(func(n: Node) -> bool: return n is Window and (n as Window).visible)
	_ramp_music(MUSIC_SHEET_DB if sheet_open else MUSIC_VOLUME_DB)


## The music bows out into the hand-over: its player moves to the root (it must outlive this scene) and fades
## to silence, then frees itself.
func _hand_over_music() -> void:
	if _music_player == null or not is_instance_valid(_music_player):
		return
	var player := _music_player
	_music_player = null
	if _music_tween != null:
		_music_tween.kill()
	player.reparent(get_tree().root)
	var bow := player.create_tween()
	bow.tween_property(player, "volume_db", -80.0, MUSIC_BOW_OUT_S)
	bow.tween_callback(player.queue_free)


func _fetch_menu_drone(library: AmbienceLibrary) -> void:
	var ok: bool = await library.ensure_all_sounds()
	if not ok or _music_player == null or not is_instance_valid(_music_player):
		return
	var stream: AudioStream = library.get_stream("menu_drone")
	if stream == null:
		return
	_music_player.stop()
	_music_player.stream = stream
	_music_player.play()
