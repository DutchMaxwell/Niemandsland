extends Control
## Native menu over a live biome vignette. This controller owns existing save,
## teaching and network routes; StartupMenuView handles grouping and layout.

# === Constants ===

const MUSIC_VOLUME_DB := -12.0
const MUSIC_FADE_IN_S := 2.5

## Fail the room-list request if neither rooms nor an error arrive in this time
## (safety net for a relay that accepts the socket but never replies).
const BROWSE_TIMEOUT_S := 8.0
## Room-code length the relay hands out (CODE_LENGTH in relay_server.py). Only used to
## reject input the relay could never accept before the dialog closes on it.
const JOIN_CODE_LEN := 6


# === Native menu view and preserved game routes ===
const MenuView = preload("res://scripts/startup_menu_view.gd")
@onready var diorama: MenuDiorama = %Diorama
var view: Control
var _settings: Window
var _transitioning := false
var continue_btn: Button
var start_battle_btn: Button
var tutorial_btn: Button
var spielschule_btn: Button
var host_online_btn: Button
var join_online_btn: Button
var browse_online_btn: Button
var load_battle_btn: Button
var report_problem_btn: Button
var credits_btn: Button
var exit_game_btn: Button

# === Private variables ===

var _load_dialog: FileDialog
var _host_popup: AcceptDialog
var _join_popup: AcceptDialog
var _browse_popup: AcceptDialog
var _exit_confirm: ConfirmationDialog
var _relay_url_input: LineEdit
var _host_name_input: LineEdit
var _host_public_check: CheckBox
var _join_code_input: LineEdit
var _join_relay_url_input: LineEdit
var _join_name_input: LineEdit
var _join_error_label: Label
var _browse_name_input: LineEdit
var _browse_url_input: LineEdit
var _browse_rooms_vbox: VBoxContainer
var _browse_lobby: InternetLobby
var _browse_request_gen: int = 0  # invalidates a stale request's timeout/reply
var _continue_path := ""
var _music_player: AudioStreamPlayer = null

# === Lifecycle ===

func _ready() -> void:
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
	continue_btn = view.buttons.ContinueBtn
	start_battle_btn = view.buttons.StartBattleBtn
	tutorial_btn = view.buttons.TutorialBtn
	spielschule_btn = view.buttons.SpielschuleBtn
	host_online_btn = view.buttons.HostOnlineBtn
	join_online_btn = view.buttons.JoinOnlineBtn
	browse_online_btn = view.buttons.BrowseOnlineBtn
	load_battle_btn = view.buttons.LoadBattleBtn
	report_problem_btn = view.buttons.ReportProblemBtn
	credits_btn = view.buttons.CreditsBtn
	exit_game_btn = view.buttons.ExitGameBtn
	var save := SaveManager.latest_save_info()
	_continue_path = str(save.get("path",""))
	view.set_save(save)
	view.version.text = "Fanprojekt für OnePageRules     " + version_string()
	continue_btn.pressed.connect(_on_continue_pressed)
	start_battle_btn.pressed.connect(_on_start_battle_pressed)
	tutorial_btn.pressed.connect(_on_tutorial_pressed)
	spielschule_btn.pressed.connect(_on_spielschule_pressed)
	host_online_btn.pressed.connect(_on_host_online_pressed)
	join_online_btn.pressed.connect(_on_join_online_pressed)
	browse_online_btn.pressed.connect(_on_browse_online_pressed)
	load_battle_btn.pressed.connect(_on_load_battle_pressed)
	report_problem_btn.pressed.connect(_on_report_problem_pressed)
	credits_btn.pressed.connect(_on_credits_pressed)
	exit_game_btn.pressed.connect(_on_exit_pressed)
	view.buttons.SettingsBtn.pressed.connect(_on_settings_pressed)
	view.buttons.HelpTutorialBtn.pressed.connect(_on_tutorial_pressed)
	diorama.loading_progress.connect(_on_diorama_loading)
	diorama.diorama_ready.connect(_on_diorama_ready)
	diorama.rebuild_started.connect(_on_diorama_rebuild_started)
	diorama.lighting_changed.connect(func(controller: Node) -> void:
		if is_instance_valid(_settings):
			_settings.lighting_controller = controller)
	_start_menu_music()
	_maybe_check_for_updates()
	if get_tree().current_scene == self:
		(continue_btn if continue_btn.visible else start_battle_btn).grab_focus.call_deferred()


func _on_diorama_loading(label: String, ratio: float) -> void:
	view.status.text = "%s … %d %%" % [label,roundi(ratio*100)]


func _on_diorama_rebuild_started() -> void:
	view.status.text = "Kulisse wird vorbereitet …"


func _on_diorama_ready() -> void:
	view.status.text = ""
	if is_instance_valid(_settings):
		_settings.lighting_controller = diorama.get_lighting_controller()
		_settings._sync_ui_from_controller()


func _on_settings_pressed() -> void:
	view.close_route()
	if not is_instance_valid(_settings):
		_settings = Window.new()
		_settings.set_script(load("res://scripts/lighting_panel.gd"))
		add_child(_settings)
		_settings.initialize(diorama.get_lighting_controller())
		_settings.title = "Einstellungen"
		var label := Label.new()
		label.text = "Menükulisse"
		_settings._main_vbox.add_child(label)
		var choices := OptionButton.new()
		for title in ["Stadtruinen","Dschungel","Grasland","Wüste","Tundra","Vulkanasche"]:
			choices.add_item(title)
		choices.select(MenuDiorama.Battlefield.BIOMES.find(diorama.biome))
		_settings._main_vbox.add_child(choices)
		choices.item_selected.connect(func(index: int) -> void:
			diorama.set_biome(MenuDiorama.Battlefield.BIOMES[index])
			var config := ConfigFile.new()
			config.set_value("menu","biome",diorama.biome)
			config.save("user://menu.cfg"))
	_settings.popup_centered()


# === Button handlers ===

func _on_continue_pressed() -> void:
	if _continue_path.is_empty():
		return
	ProjectSettings.set_setting("niemandsland/pending_load_path", _continue_path)
	_transition_to_game()


func _on_start_battle_pressed() -> void:
	_transition_to_game()


## TUTORIAL pressed: first-timers go straight in (assessment + full track); once any
## chapter is completed, a chapter picker offers resume / per-lesson replay / reset.
func _on_tutorial_pressed() -> void:
	var progress := TutorialProgress.new()
	progress.load_from_disk()
	var track := TutorialFlow.build_tool_track()
	if not progress.any_completed(TutorialFlow.ids(track)):
		_launch_tutorial("")
		return
	_show_tutorial_picker(progress, track)


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


## The chapter picker: RESUME on top, then one button per lesson (checkmarked when
## completed — everything stays replayable, MTG-Arena model), plus a progress reset.
func _show_tutorial_picker(progress: TutorialProgress, track: Array) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Tutorial"
	dialog.ok_button_text = "Schließen"
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", HudTokens.SECTION_SEP)

	var lesson_ids := TutorialFlow.ids(track)
	var next_id := progress.first_incomplete(lesson_ids)
	var resume_btn := Button.new()
	if next_id.is_empty():
		resume_btn.text = "ALL CHAPTERS DONE — PICK ONE TO REPLAY"
		resume_btn.disabled = true
	else:
		resume_btn.text = "RESUME — NEXT: %s · %s" % [next_id, TutorialFlow.title_of(track, next_id).to_upper()]
		resume_btn.pressed.connect(func() -> void:
			dialog.queue_free()
			_launch_tutorial(""))
	vbox.add_child(resume_btn)
	vbox.add_child(HSeparator.new())

	for lesson in track:
		var lesson_id := String(lesson.get("id", ""))
		var done := progress.is_lesson_completed(lesson_id)
		var btn := Button.new()
		btn.text = "%s  %s · %s" % [("✓" if done else "•"), lesson_id, String(lesson.get("title", "")).to_upper()]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(func() -> void:
			dialog.queue_free()
			_launch_tutorial(lesson_id))
		vbox.add_child(btn)

	vbox.add_child(HSeparator.new())
	var reset_btn := Button.new()
	reset_btn.text = "RESET TUTORIAL PROGRESS"
	reset_btn.add_theme_color_override("font_color", HudTokens.DANGER)
	reset_btn.pressed.connect(func() -> void:
		progress.reset()
		dialog.queue_free())
	vbox.add_child(reset_btn)

	dialog.add_child(vbox)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


## GAME SCHOOL (working name "Spielschule") pressed: open the chapter list. The full game-school
## track — ten isolated, repeatable lessons, each loading its own prepared scene, plus the reserved
## spell slot. Chapters without a bundled scenario yet stay disabled ("scenario coming soon").
func _on_spielschule_pressed() -> void:
	var progress := SpielschuleProgress.new()
	progress.load_from_disk()

	var dialog := AcceptDialog.new()
	dialog.title = "FEUERTAUFE"
	dialog.ok_button_text = "Schließen"

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", HudTokens.SECTION_SEP)

	var intro := Label.new()
	intro.text = "Ten short lessons — play them in any order, replay any time."
	intro.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(intro)
	vbox.add_child(HSeparator.new())

	for chapter in Spielschule.chapters():
		_add_chapter_row(vbox, chapter, progress, dialog)

	dialog.add_child(vbox)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	# Keep the ten-row list (and its CLOSE button) reachable on small displays.
	UiPolish.keep_window_reachable(dialog, Vector2i(520, 560))


## One chapter row: a title Button (checkmarked when completed — everything stays replayable) with a
## muted one-line goal beneath it. Playable rows launch the scenario; unbundled/reserved rows are
## disabled and say why.
func _add_chapter_row(vbox: VBoxContainer, chapter: Dictionary, progress: SpielschuleProgress, dialog: AcceptDialog) -> void:
	var id := String(chapter.get("id", ""))
	var title := String(chapter.get("title", ""))
	var available := Spielschule.is_available(chapter)
	var reserved := bool(chapter.get("reserved", false))
	var done := progress.is_completed(id)

	var btn := Button.new()
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var glyph := "✓" if done else "•"
	var suffix := ""
	if reserved:
		suffix = "   —   coming with the spell wave"
	elif not available:
		suffix = "   —   scenario coming soon"
	btn.text = "%s  %s · %s%s" % [glyph, id, title.to_upper(), suffix]
	btn.disabled = not available
	if available:
		btn.pressed.connect(func() -> void:
			dialog.queue_free()
			_launch_scenario(chapter))
	vbox.add_child(btn)

	var goal := Label.new()
	goal.text = "      " + String(chapter.get("goal", ""))
	goal.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(goal)


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
	_open_load_battle_dialog()


## Export an ANONYMISED diagnostics bundle (system info + scrubbed recent log) to the
## Desktop and open the folder, so a player can review and attach it to a bug report.
func _on_report_problem_pressed() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := DiagnosticsReporter.export_report(stamp)
	var dialog := AcceptDialog.new()
	dialog.title = "Problem melden"
	if path.is_empty():
		dialog.dialog_text = "Could not write the diagnostics file.\nThe log lives at user://logs/niemandsland.log."
	else:
		dialog.dialog_text = "Saved an anonymised diagnostics file to:\n%s\n\nAttach it to a bug report — it carries no player names, room codes or your username." % path
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


## In-app credits / license summary, so the model attribution (CC-BY-SA) is visible to players,
## not only in the repo docs. Full text lives in THIRD_PARTY.md.
func _on_credits_pressed() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Credits & Lizenzen"
	# As plain dialog_text these ~12 licence lines size the window themselves, with nothing
	# stopping it (and its OK button) from growing past a small screen. A scrolled body with a
	# FIXED viewport is the clamp here: an AcceptDialog wraps its contents (wrap_controls), so
	# its window size is always the contents' minimum — an outer keep_window_reachable() would
	# be overruled the moment it pops up (measured: clamped to 520x400, popped up at 452x317).
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body := Label.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.text = "Niemandsland — © the Niemandsland project.\n\n" \
		+ "Game code: MIT License.\n" \
		+ "3D miniatures & terrain: generated project assets, CC-BY-SA 4.0.\n" \
		+ "Fonts: SIL Open Font License.\n" \
		+ "UI icons: Phosphor Icons (MIT).\n" \
		+ "Engine: Godot Engine (MIT).\n\n" \
		+ "OnePageRules army data is loaded at runtime via the Army Forge API; it is not bundled.\n\n" \
		+ "Full details: THIRD_PARTY.md in the project repository.\n\n" \
		+ "Niemandsland is a free, non-profit, open-source fan project (MIT code, CC-BY-SA generated assets). It is not affiliated with, endorsed by, or sponsored by OnePageRules. It bundles no OPR rules text, files, art or marks; the rules are OPR's, available free at onepagerules.com, and army lists come from OPR's Army Forge. Responsible: Andreas Kesberg, privacy@niemandsland.xyz."
	scroll.add_child(body)
	dialog.add_child(scroll)
	add_child(dialog)
	# popup_centered() centres whatever size the window carries at that moment, and the wrap to
	# the contents happens afterwards — so take the wrapped size FIRST or the window opens off
	# centre by half the difference.
	dialog.reset_size()
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


## EXIT GAME / ESC ask first. Everywhere else in the project ESC only closes a surface, so
## quitting the process on a single stray keypress was the hardest break in the interaction
## language — and unrecoverable (a CONTINUE save one keypress away is not the same thing).
func _on_exit_pressed() -> void:
	# is_instance_valid still reports true for the rest of the frame after queue_free, so the
	# very ESC that closes this dialog cannot immediately open a second one.
	if is_instance_valid(_exit_confirm):
		return
	_exit_confirm = ConfirmationDialog.new()
	_exit_confirm.title = "Niemandsland beenden"
	_exit_confirm.dialog_text = "Möchtest du Niemandsland beenden?"
	_exit_confirm.ok_button_text = "Beenden"
	_exit_confirm.cancel_button_text = "Zurück"
	_exit_confirm.confirmed.connect(func() -> void: get_tree().quit())
	_exit_confirm.canceled.connect(_exit_confirm.queue_free)
	add_child(_exit_confirm)
	_exit_confirm.popup_centered()
	# CANCEL is the safe answer, so it — not QUIT — starts focused.
	_exit_confirm.get_cancel_button().grab_focus()

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


func _on_update_available(latest_version: String, release_url: String, release_notes: String) -> void:
	var prompt := UpdatePrompt.new()
	prompt.setup(UpdateChecker.get_current_version(), latest_version, release_url, release_notes)
	prompt.confirmed.connect(_on_update_prompt_closed.bind(prompt, true))
	prompt.canceled.connect(_on_update_prompt_closed.bind(prompt, false))
	add_child(prompt)
	prompt.popup_centered()
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
	var dialog := AcceptDialog.new()
	dialog.title = "Updating Niemandsland"
	dialog.dialog_text = "Starting…"
	dialog.get_ok_button().hide()
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
		dialog.dialog_text = ("%s… %d%%" % [stage, int(ratio * 100.0)]) if ratio >= 0.0 else ("%s…" % stage)


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
	var msg := AcceptDialog.new()
	msg.title = "Auto-update unavailable"
	msg.dialog_text = "Couldn't auto-update (%s).\nThe download page has opened — unzip it over your Niemandsland folder." % reason
	# An AcceptDialog only HIDES itself on OK — without both close paths freeing it, the
	# node stays in the tree for the rest of the session.
	msg.confirmed.connect(msg.queue_free)
	msg.canceled.connect(msg.queue_free)
	add_child(msg)
	msg.popup_centered()
	# Open the browser only AFTER the message is up: shell_open raises the browser over the
	# game window, so a dialog shown afterwards is hidden behind it and never read.
	OS.shell_open(url)  # fallback: the player downloads + unzips manually

# ===== Online Multiplayer =====

func _on_host_online_pressed() -> void:
	_show_host_popup()


func _on_join_online_pressed() -> void:
	_show_join_popup()


func _show_host_popup() -> void:
	if _host_popup:
		_host_popup.queue_free()
	_host_popup = NetDialog.build("Raum erstellen", "NET-01", "Tisch vorbereiten")

	var content := NetDialog.content(_host_popup)
	content.add_child(NetDialog.label("Dein Name:"))
	_host_name_input = NetDialog.line_edit(PlayerIdentity.load_saved_name(), "Spielername")
	_host_name_input.max_length = PlayerIdentity.MAX_NAME_LEN
	content.add_child(_host_name_input)
	content.add_child(NetDialog.label("Verbindungsserver:"))
	_relay_url_input = NetDialog.line_edit(InternetLobby.DEFAULT_RELAY_URL, "wss://niemandsland-relay.fly.dev")
	content.add_child(_relay_url_input)
	_host_public_check = CheckBox.new()
	_host_public_check.text = "Raum öffentlich anzeigen"
	_host_public_check.focus_mode = Control.FOCUS_ALL
	content.add_child(_host_public_check)
	var info := NetDialog.label("Den Einladungscode erhältst du nach dem Verbinden am Tisch.")
	info.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	content.add_child(info)

	_host_popup.confirmed.connect(_on_host_confirmed)
	add_child(_host_popup)
	_host_popup.popup_centered()
	UiPolish.keep_window_reachable(_host_popup, Vector2i(460, 300))
	_host_name_input.grab_focus()


func _on_host_confirmed() -> void:
	var url = _relay_url_input.text.strip_edges()
	if url.is_empty():
		url = InternetLobby.DEFAULT_RELAY_URL

	var player_name := PlayerIdentity.sanitize(_host_name_input.text)
	PlayerIdentity.save_name(player_name)

	# Pass settings to main scene — connection happens there
	ProjectSettings.set_setting("niemandsland/pending_internet_lobby", true)
	ProjectSettings.set_setting("niemandsland/internet_is_host", true)
	ProjectSettings.set_setting("niemandsland/internet_relay_url", url)
	ProjectSettings.set_setting("niemandsland/player_name", player_name)
	ProjectSettings.set_setting("niemandsland/internet_public", _host_public_check.button_pressed)
	_transition_to_game()


func _show_join_popup() -> void:
	if _join_popup:
		_join_popup.queue_free()
	_join_popup = NetDialog.build("Mit Code beitreten", "NET-02", "Beitreten")

	var content := NetDialog.content(_join_popup)
	content.add_child(NetDialog.label("Dein Name:"))
	_join_name_input = NetDialog.line_edit(PlayerIdentity.load_saved_name(), "Spielername")
	_join_name_input.max_length = PlayerIdentity.MAX_NAME_LEN
	content.add_child(_join_name_input)
	content.add_child(NetDialog.label("Einladungscode:"))
	_join_code_input = NetDialog.line_edit("", "ABC-123")
	_join_code_input.max_length = 7  # 6 chars + optional hyphen
	_join_code_input.add_theme_font_size_override("font_size", 24)
	_join_code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_join_code_input)
	# Validation feedback right under the field it belongs to; hidden until Join is
	# pressed with an unusable code (see _on_join_confirmed).
	_join_error_label = NetDialog.label("")
	_join_error_label.add_theme_color_override("font_color", HudTokens.DANGER)
	_join_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_join_error_label.visible = false
	content.add_child(_join_error_label)
	# Editing the code is the fix for the message, so the message must not outlive the edit.
	_join_code_input.text_changed.connect(func(_new_text: String) -> void:
		_join_error_label.visible = false)
	content.add_child(NetDialog.label("Verbindungsserver:"))
	_join_relay_url_input = NetDialog.line_edit(InternetLobby.DEFAULT_RELAY_URL, "wss://niemandsland-relay.fly.dev")
	content.add_child(_join_relay_url_input)

	# The dialog must NOT close itself on OK: an unusable room code has to leave the mask
	# open with its reason on screen (a window that just vanishes and does nothing reads
	# like a crash). _on_join_confirmed hides it once the input is good.
	_join_popup.dialog_hide_on_ok = false
	_join_popup.confirmed.connect(_on_join_confirmed)
	add_child(_join_popup)
	_join_popup.popup_centered()
	UiPolish.keep_window_reachable(_join_popup, Vector2i(460, 340))
	_join_code_input.grab_focus()


## Join pressed. Anything the relay cannot possibly accept (relay: 6 characters) is
## rejected HERE, with the mask staying open and the caret back in the code field —
## previously this returned silently while the dialog closed anyway, so a typo looked
## exactly like the game crashing on Join.
func _on_join_confirmed() -> void:
	var code = _join_code_input.text.strip_edges().replace("-", "").to_upper()
	if code.is_empty():
		_show_join_error("Gib den Einladungscode deiner Spielrunde ein.")
		return
	if code.length() != JOIN_CODE_LEN:
		_show_join_error("Ein Einladungscode hat %d Zeichen, zum Beispiel ABC-123." % JOIN_CODE_LEN)
		return
	var url = _join_relay_url_input.text.strip_edges()
	if url.is_empty():
		url = InternetLobby.DEFAULT_RELAY_URL
	# We took the close over from the dialog (dialog_hide_on_ok), so hide it before the
	# scene swap — an embedded dialog would otherwise sit on top of the loading overlay.
	_join_popup.hide()
	_join_room_and_transition(code, url, PlayerIdentity.sanitize(_join_name_input.text))


## Shows a rejection under the room-code field and returns the caret to it.
func _show_join_error(message: String) -> void:
	if not is_instance_valid(_join_error_label):
		return
	_join_error_label.text = message
	_join_error_label.visible = true
	_join_code_input.grab_focus()


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


# ===== Room browser (NET-03) =====

func _on_browse_online_pressed() -> void:
	_show_browse_popup()


func _show_browse_popup() -> void:
	if _browse_popup:
		_browse_popup.queue_free()
	_browse_popup = NetDialog.build("Öffentliche Tische", "NET-03", "Schließen")

	var content := NetDialog.content(_browse_popup)
	content.add_child(NetDialog.label("Dein Name:"))
	_browse_name_input = NetDialog.line_edit(PlayerIdentity.load_saved_name(), "Spielername")
	_browse_name_input.max_length = PlayerIdentity.MAX_NAME_LEN
	content.add_child(_browse_name_input)
	content.add_child(NetDialog.label("Verbindungsserver:"))
	_browse_url_input = NetDialog.line_edit(InternetLobby.DEFAULT_RELAY_URL, "wss://niemandsland-relay.fly.dev")
	content.add_child(_browse_url_input)

	var refresh_btn := Button.new()
	refresh_btn.text = "Liste aktualisieren"
	refresh_btn.focus_mode = Control.FOCUS_ALL
	refresh_btn.pressed.connect(_refresh_browse_list)
	content.add_child(refresh_btn)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_browse_rooms_vbox = VBoxContainer.new()
	_browse_rooms_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browse_rooms_vbox.add_theme_constant_override("separation", HudTokens.SPACE_4)
	scroll.add_child(_browse_rooms_vbox)

	# A reusable lobby just for listing (its _process polls the relay socket).
	_browse_lobby = InternetLobby.new()
	add_child(_browse_lobby)
	_browse_lobby.rooms_list_received.connect(_on_browse_rooms_received)
	_browse_lobby.rooms_list_failed.connect(_on_browse_failed)

	_browse_popup.confirmed.connect(_on_browse_closed)
	_browse_popup.canceled.connect(_on_browse_closed)
	add_child(_browse_popup)
	_browse_popup.popup_centered()
	UiPolish.keep_window_reachable(_browse_popup, Vector2i(460, 460))
	_refresh_browse_list()


func _refresh_browse_list() -> void:
	if not _browse_lobby:
		return
	_set_browse_status("Loading rooms…")
	var url := _browse_url_input.text.strip_edges()
	if url.is_empty():
		url = InternetLobby.DEFAULT_RELAY_URL
	_browse_request_gen += 1
	var gen := _browse_request_gen
	_browse_lobby.list_rooms(url)
	# Safety net: a relay that never replies leaves the list spinning forever.
	get_tree().create_timer(BROWSE_TIMEOUT_S).timeout.connect(
		func() -> void:
			if gen == _browse_request_gen and _browse_rooms_vbox:
				_set_browse_status("Could not reach the relay (timed out)."))


func _on_browse_rooms_received(rooms: Array) -> void:
	_browse_request_gen += 1  # a reply arrived; void the pending timeout
	for child in _browse_rooms_vbox.get_children():
		child.queue_free()
	if rooms.is_empty():
		_set_browse_status("0 games online right now.")
		return
	# Count line above the rows, mirroring the explicit 0-state.
	var count_label := Label.new()
	count_label.text = "%d game%s online:" % [rooms.size(), "" if rooms.size() == 1 else "s"]
	count_label.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
	_browse_rooms_vbox.add_child(count_label)
	for room: Variant in rooms:
		var code := str(room.get("code", ""))
		var players := int(room.get("players", 0))
		if code.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", HudTokens.SPACE_8)
		var label := Label.new()
		label.text = "%s   %d/%d" % [InternetLobby._format_code(code), players, InternetLobby.MAX_ROOM_PLAYERS]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var join_btn := Button.new()
		join_btn.text = "Beitreten"
		join_btn.focus_mode = Control.FOCUS_NONE
		join_btn.pressed.connect(_on_browse_join.bind(code))
		row.add_child(join_btn)
		_browse_rooms_vbox.add_child(row)


## The relay was unreachable or rejected list_rooms (e.g. not yet redeployed).
func _on_browse_failed(reason: String) -> void:
	_browse_request_gen += 1  # an error arrived; void the pending timeout
	_set_browse_status(reason)


func _on_browse_join(code: String) -> void:
	var url := _browse_url_input.text.strip_edges()
	if url.is_empty():
		url = InternetLobby.DEFAULT_RELAY_URL
	_cleanup_browse_lobby()
	_join_room_and_transition(code, url, PlayerIdentity.sanitize(_browse_name_input.text))


func _on_browse_closed() -> void:
	_cleanup_browse_lobby()


## Frees the listing lobby (and any open socket) when the browser closes/joins.
func _cleanup_browse_lobby() -> void:
	if _browse_lobby:
		_browse_lobby.disconnect_internet_game()
		_browse_lobby.queue_free()
		_browse_lobby = null


## Shows a single status line in the room list (loading / empty / error).
func _set_browse_status(text: String) -> void:
	if not _browse_rooms_vbox:
		return
	for child in _browse_rooms_vbox.get_children():
		child.queue_free()
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
	_browse_rooms_vbox.add_child(label)



# ===== Shared =====

func _transition_to_game() -> void:
	if _transitioning:
		return
	_transitioning = true
	view.hide()
	const GAME_SCENE := "res://scenes/main.tscn"
	# Black loading overlay added to the SceneTree root so it survives the scene swap
	# (no grey flash). The game scene takes a few seconds to load; show the bar against
	# the threaded load's real progress, then hand over to the loaded scene. main.gd
	# dismisses the overlay once its own backdrop is up.
	var overlay := LoadingOverlay.new()
	overlay.add_to_group("transition_overlay")
	get_tree().root.add_child(overlay)
	overlay.set_label("LOADING")

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


func _open_load_battle_dialog() -> void:
	if _load_dialog == null:
		_load_dialog = FileDialog.new()
		_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_load_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_load_dialog.filters = PackedStringArray(["*.nml ; Niemandsland Save Files"])
		_load_dialog.title = "Spielstand laden"
		# FileDialog derives its OK label from file_mode and takes both button labels from
		# Godot's own translations, i.e. from the SYSTEM language — on a German Windows the
		# only English-only UI in the game would suddenly read "Öffnen"/"Abbrechen". Pin them
		# explicitly, AFTER file_mode (set_file_mode rewrites ok_button_text).
		_load_dialog.ok_button_text = "Öffnen"
		_load_dialog.cancel_button_text = "Abbrechen"
		_load_dialog.file_selected.connect(_on_load_file_selected)
		add_child(_load_dialog)
		# A hard 800x600 is nearly full-screen on a 1366x768 laptop; clamp to the host
		# window instead (and re-clamp when it is resized).
		UiPolish.keep_window_reachable(_load_dialog, Vector2i(800, 600))

	_load_dialog.current_dir = SaveManager.get_default_save_dir()
	_load_dialog.popup_centered()


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
		if view.route_panel.visible:
			view.close_route()
		else:
			_on_exit_pressed()
		get_viewport().set_input_as_handled()


# ===== Static (testable) =====

## Version string for the footer, bound to the project config (single source).
static func version_string() -> String:
	return "v%s" % ProjectSettings.get_setting("application/config/version", "?")

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
	var fade := create_tween()
	fade.tween_property(_music_player, "volume_db", MUSIC_VOLUME_DB, MUSIC_FADE_IN_S)


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
