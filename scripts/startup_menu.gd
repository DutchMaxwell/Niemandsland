extends Control
## Main menu controller: command-console UI column over the live battlefield diorama
## (MenuDiorama). Owns the entrance choreography, the CONTINUE save shortcut, the
## menu Settings window, the network dialogs and the transition into the game scene.

# === Constants ===

const ORBITRON_PATH := "res://assets/ui_glassmorphism/fonts/Orbitron.ttf"
const MONO_PATH := "res://assets/ui_glassmorphism/fonts/SourceCodePro.ttf"
const WORDMARK_FONT_SIZE := 46
const WORDMARK_TRACKING_PX := 4    # Orbitron glyph tracking (editorial AAA lockup)
const KICKER_TEXT := "TACTICAL TABLETOP WARGAMING"
const RULE_TICK_W := 26.0          # amber tick, then a cyan hairline (header language)
const RULE_H := 2.0

## Entrance choreography (motion tokens).
const ENTRANCE_WORDMARK_DELAY := 0.05
const ENTRANCE_WORDMARK_S := 0.45
const ENTRANCE_BUTTONS_START := 0.30
const ENTRANCE_BUTTON_STAGGER := 0.06
const ENTRANCE_SLIDE_PX := 24.0
const ENTRANCE_FOOTER_AT := 0.60
const ENTRANCE_TICKER_AT := 1.0
const REDUCED_MOTION_FADE_S := 0.2

const MUSIC_VOLUME_DB := -12.0
const MUSIC_FADE_IN_S := 2.5

## Hover camera reactivity (degrees of FOV bias) + idle attract mode.
const FOV_BIAS_PUSH_IN := -2.0   # Continue/Start: lean toward the battlefield
const FOV_BIAS_WIDE := 2.0       # Host/Join: step back for the wider table
const ATTRACT_IDLE_S := 60.0
const ATTRACT_FADE_S := 0.2
## Fail the room-list request if neither rooms nor an error arrive in this time
## (safety net for a relay that accepts the socket but never replies).
const BROWSE_TIMEOUT_S := 8.0


# === Node references ===

@onready var diorama: MenuDiorama = %Diorama
@onready var logo_label: Label = %LogoLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var menu_buttons: VBoxContainer = %MenuButtons
@onready var continue_btn: MenuListButton = %ContinueBtn
@onready var start_battle_btn: MenuListButton = %StartBattleBtn
@onready var tutorial_btn: MenuListButton = %TutorialBtn
@onready var host_online_btn: MenuListButton = %HostOnlineBtn
@onready var join_online_btn: MenuListButton = %JoinOnlineBtn
@onready var browse_online_btn: MenuListButton = %BrowseOnlineBtn
@onready var load_battle_btn: MenuListButton = %LoadBattleBtn
@onready var report_problem_btn: MenuListButton = %ReportProblemBtn
@onready var credits_btn: MenuListButton = %CreditsBtn
@onready var exit_game_btn: MenuListButton = %ExitGameBtn
@onready var ticker: MenuTicker = %Ticker
@onready var version_label: Label = %VersionLabel
@onready var build_label: Label = %BuildLabel

# === Private variables ===

var animation_played: bool = false
var _load_dialog: FileDialog
var _host_popup: AcceptDialog
var _join_popup: AcceptDialog
var _browse_popup: AcceptDialog
var _relay_url_input: LineEdit
var _host_name_input: LineEdit
var _host_public_check: CheckBox
var _join_code_input: LineEdit
var _join_relay_url_input: LineEdit
var _join_name_input: LineEdit
var _browse_name_input: LineEdit
var _browse_url_input: LineEdit
var _browse_rooms_vbox: VBoxContainer
var _browse_lobby: InternetLobby
var _browse_request_gen: int = 0  # invalidates a stale request's timeout/reply
var _wordmark_box: HBoxContainer
var _wordmark_lockup: VBoxContainer
var _loading_overlay: LoadingOverlay = null
var _continue_path := ""
var _music_player: AudioStreamPlayer = null
var _idle_timer: Timer = null
var _attract_active := false

# === Lifecycle ===

func _ready() -> void:
	# First log line of every session: the version AND the build hash baked at export time.
	# The version string alone can be right while the packed bytecode is stale, so the hash is
	# the only way to prove the running binary matches a given commit (defaults to "local-dev"
	# for editor/source runs where no export-time hash was injected).
	print("[Boot] Niemandsland %s build %s" % [
		ProjectSettings.get_setting("application/config/version", "?"),
		ProjectSettings.get_setting("application/config/build_hash", "local-dev"),
	])

	# Check if an .nml file was passed via command-line (e.g. double-click in file manager)
	var file_to_open := _get_save_from_cmdline()
	if not file_to_open.is_empty():
		ProjectSettings.set_setting("niemandsland/pending_load_path", file_to_open)
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return

	theme = ThemeManager.get_current_theme()

	_build_wordmark()
	_style_subtitle()
	_bind_version()
	_setup_continue_button()
	_build_post_layers()

	continue_btn.pressed.connect(_on_continue_pressed)
	start_battle_btn.pressed.connect(_on_start_battle_pressed)
	tutorial_btn.pressed.connect(_on_tutorial_pressed)
	host_online_btn.pressed.connect(_on_host_online_pressed)
	join_online_btn.pressed.connect(_on_join_online_pressed)
	browse_online_btn.pressed.connect(_on_browse_online_pressed)
	load_battle_btn.pressed.connect(_on_load_battle_pressed)
	report_problem_btn.pressed.connect(_on_report_problem_pressed)
	credits_btn.pressed.connect(_on_credits_pressed)
	exit_game_btn.pressed.connect(_on_exit_pressed)
	exit_game_btn.accent_color = HudTokens.DANGER
	exit_game_btn.add_theme_color_override("font_color", HudTokens.DANGER)

	_renumber_buttons()
	_setup_focus_chain()
	_setup_camera_reactivity()
	_setup_attract_mode()
	_start_menu_music()
	_play_startup_animation()
	_maybe_check_for_updates()
	if get_tree().current_scene == self:
		start_battle_btn.grab_focus.call_deferred()

# === Entrance choreography ===

func _play_startup_animation() -> void:
	if animation_played:
		_wordmark_lockup.modulate.a = 1.0
		return
	animation_played = true

	# Black cover with a loading indicator over EVERYTHING while the diorama parses its
	# 3D models. Hold it until diorama_ready, then fade the finished scene in — nothing
	# pops or stutters in view; the bar's continuous fill communicates the app is alive.
	_loading_overlay = LoadingOverlay.new()
	add_child(_loading_overlay)
	_loading_overlay.set_label("PREPARING BATTLEFIELD")
	diorama.loading_progress.connect(_on_diorama_loading)
	diorama.diorama_ready.connect(_on_diorama_ready, CONNECT_ONE_SHOT)
	diorama.rebuild_started.connect(_on_diorama_rebuild_started)

	# Hide the to-be-revealed UI until the cover fades (so nothing shows behind it).
	_wordmark_lockup.modulate.a = 0.0
	for btn: Button in _visible_menu_buttons():
		btn.modulate.a = 0.0
	$FooterLeft.modulate.a = 0.0
	ticker.modulate.a = 0.0


## Feed the diorama's build progress into the loading bar (label stays static; the
## continuous fill conveys progress).
func _on_diorama_loading(_label: String, ratio: float) -> void:
	if is_instance_valid(_loading_overlay):
		_loading_overlay.set_progress(ratio)


## A LIVE quality switch (Performance -> higher) rebuilds the whole diorama — the
## heavy build would freeze the visible menu with no feedback. Cover it with the
## same loading overlay as the initial start, dismissed on diorama_ready.
func _on_diorama_rebuild_started() -> void:
	if is_instance_valid(_loading_overlay):
		return  # initial-start cover is already up
	_loading_overlay = LoadingOverlay.new()
	add_child(_loading_overlay)
	_loading_overlay.set_label("PREPARING BATTLEFIELD")
	diorama.diorama_ready.connect(func() -> void:
		if is_instance_valid(_loading_overlay):
			_loading_overlay.set_progress(1.0)
			_loading_overlay.fade_and_free(), CONNECT_ONE_SHOT)


func _on_diorama_ready() -> void:
	if is_instance_valid(_loading_overlay):
		_loading_overlay.set_progress(1.0)
		await get_tree().create_timer(0.35, true).timeout  # let the fill ease to full
		if is_instance_valid(_loading_overlay):
			_loading_overlay.fade_and_free()

	if GraphicsSettings.reduce_motion:
		for node in [_wordmark_lockup, $FooterLeft, ticker]:
			node.modulate.a = 1.0
		for btn: Button in _visible_menu_buttons():
			btn.modulate.a = 1.0
		ticker.start()
		return
	_play_entrance()


## The staggered reveal (wordmark, buttons, footer, ticker), played after the cover fade.
func _play_entrance() -> void:
	# Wordmark power-on (whole lockup: kicker, wordmark, rule).
	_wordmark_lockup.modulate.a = 0.0
	_wordmark_lockup.scale = Vector2(0.92, 0.92)
	var word := create_tween()
	word.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	word.tween_interval(ENTRANCE_WORDMARK_DELAY)
	word.tween_property(_wordmark_lockup, "modulate:a", 1.0, ENTRANCE_WORDMARK_S)
	word.parallel().tween_property(_wordmark_lockup, "scale", Vector2.ONE, ENTRANCE_WORDMARK_S)

	# Buttons cascade in from the left.
	var visible_buttons := _visible_menu_buttons()
	for i in visible_buttons.size():
		var btn := visible_buttons[i]
		btn.modulate.a = 0.0
		var slide := create_tween()
		slide.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		slide.tween_interval(ENTRANCE_BUTTONS_START + i * ENTRANCE_BUTTON_STAGGER)
		slide.tween_property(btn, "modulate:a", 1.0, HudTokens.DUR_PANEL_IN)
		btn.position.x = -ENTRANCE_SLIDE_PX  # containers re-layout next frame; offset via margin
		slide.parallel().tween_property(btn, "position:x", 0.0, HudTokens.DUR_PANEL_IN)

	# Footer + ticker beats.
	for footer in [$FooterLeft]:
		footer.modulate.a = 0.0
		var fade := create_tween()
		fade.tween_interval(ENTRANCE_FOOTER_AT)
		fade.tween_property(footer, "modulate:a", 1.0, HudTokens.DUR_PANEL_IN)
	ticker.modulate.a = 0.0
	var ticker_in := create_tween()
	ticker_in.tween_interval(ENTRANCE_TICKER_AT)
	ticker_in.tween_property(ticker, "modulate:a", 1.0, HudTokens.DUR_PANEL_IN)
	ticker_in.tween_callback(ticker.start)

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


## Set the runtime-only tutorial flags (read-and-cleared in main.gd, never persisted to
## project.godot, mirroring harness_mode) and open the prepared table. An empty lesson id
## means "resume": the director runs assessment/first-incomplete logic itself.
func _launch_tutorial(lesson_id: String) -> void:
	ProjectSettings.set_setting("niemandsland/tutorial_mode", true)
	ProjectSettings.set_setting("niemandsland/tutorial_lesson", lesson_id)
	_transition_to_game()


## The chapter picker: RESUME on top, then one button per lesson (checkmarked when
## completed — everything stays replayable, MTG-Arena model), plus a progress reset.
func _show_tutorial_picker(progress: TutorialProgress, track: Array) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Tutorial"
	dialog.ok_button_text = "CLOSE"
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


func _on_load_battle_pressed() -> void:
	_open_load_battle_dialog()


## Export an ANONYMISED diagnostics bundle (system info + scrubbed recent log) to the
## Desktop and open the folder, so a player can review and attach it to a bug report.
func _on_report_problem_pressed() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := DiagnosticsReporter.export_report(stamp)
	var dialog := AcceptDialog.new()
	dialog.title = "Report a problem"
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
	dialog.title = "Credits & Licenses"
	dialog.dialog_text = "Niemandsland — © the Niemandsland project.\n\n" \
		+ "Game code: MIT License.\n" \
		+ "3D miniatures & terrain: generated project assets, CC-BY-SA 4.0.\n" \
		+ "Fonts: SIL Open Font License.\n" \
		+ "UI icons: Phosphor Icons (MIT).\n" \
		+ "Engine: Godot Engine (MIT).\n\n" \
		+ "OnePageRules army data is loaded at runtime via the Army Forge API; it is not bundled.\n\n" \
		+ "Full details: THIRD_PARTY.md in the project repository."
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _on_exit_pressed() -> void:
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
	updater.restarting.connect(_on_update_restarting.bind(dialog))
	updater.update_failed.connect(_on_update_failed.bind(dialog, updater, url))
	updater.install(url)


func _on_update_progress(stage: String, ratio: float, dialog: AcceptDialog) -> void:
	if is_instance_valid(dialog):
		dialog.dialog_text = ("%s… %d%%" % [stage, int(ratio * 100.0)]) if ratio >= 0.0 else ("%s…" % stage)


func _on_update_restarting(dialog: AcceptDialog) -> void:
	if is_instance_valid(dialog):
		dialog.dialog_text = "Restarting…"


func _on_update_failed(reason: String, dialog: AcceptDialog, updater: SelfUpdater, url: String) -> void:
	if is_instance_valid(updater):
		updater.queue_free()
	if is_instance_valid(dialog):
		dialog.queue_free()
	OS.shell_open(url)  # fallback: the player downloads + unzips manually
	var msg := AcceptDialog.new()
	msg.title = "Auto-update unavailable"
	msg.dialog_text = "Couldn't auto-update (%s).\nThe download page has opened — unzip it over your Niemandsland folder." % reason
	add_child(msg)
	msg.popup_centered()

# ===== Online Multiplayer =====

func _on_host_online_pressed() -> void:
	_show_host_popup()


func _on_join_online_pressed() -> void:
	_show_join_popup()


func _show_host_popup() -> void:
	if _host_popup:
		_host_popup.queue_free()
	_host_popup = NetDialog.build("HOST ONLINE GAME", "NET-01", "Start Hosting")

	var content := NetDialog.content(_host_popup)
	content.add_child(NetDialog.label("Player Name:"))
	_host_name_input = NetDialog.line_edit(PlayerIdentity.load_saved_name(), "Your name")
	_host_name_input.max_length = PlayerIdentity.MAX_NAME_LEN
	content.add_child(_host_name_input)
	content.add_child(NetDialog.label("Relay Server URL:"))
	_relay_url_input = NetDialog.line_edit(InternetLobby.DEFAULT_RELAY_URL, "wss://niemandsland-relay.fly.dev")
	content.add_child(_relay_url_input)
	_host_public_check = CheckBox.new()
	_host_public_check.text = "List this room publicly (Browse Online Games)"
	_host_public_check.focus_mode = Control.FOCUS_NONE
	content.add_child(_host_public_check)
	var info := NetDialog.label("The room code will be shown in-game after connecting.")
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
	_join_popup = NetDialog.build("JOIN ONLINE GAME", "NET-02", "Join")

	var content := NetDialog.content(_join_popup)
	content.add_child(NetDialog.label("Player Name:"))
	_join_name_input = NetDialog.line_edit(PlayerIdentity.load_saved_name(), "Your name")
	_join_name_input.max_length = PlayerIdentity.MAX_NAME_LEN
	content.add_child(_join_name_input)
	content.add_child(NetDialog.label("Room Code:"))
	_join_code_input = NetDialog.line_edit("", "ABC-123")
	_join_code_input.max_length = 7  # 6 chars + optional hyphen
	_join_code_input.add_theme_font_size_override("font_size", 24)
	_join_code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_join_code_input)
	content.add_child(NetDialog.label("Relay Server URL:"))
	_join_relay_url_input = NetDialog.line_edit(InternetLobby.DEFAULT_RELAY_URL, "wss://niemandsland-relay.fly.dev")
	content.add_child(_join_relay_url_input)

	_join_popup.confirmed.connect(_on_join_confirmed)
	add_child(_join_popup)
	_join_popup.popup_centered()
	UiPolish.keep_window_reachable(_join_popup, Vector2i(460, 340))
	_join_code_input.grab_focus()


func _on_join_confirmed() -> void:
	var code = _join_code_input.text.strip_edges().replace("-", "").to_upper()
	if code.is_empty():
		return
	var url = _join_relay_url_input.text.strip_edges()
	if url.is_empty():
		url = InternetLobby.DEFAULT_RELAY_URL
	_join_room_and_transition(code, url, PlayerIdentity.sanitize(_join_name_input.text))


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
	_browse_popup = NetDialog.build("BROWSE ONLINE GAMES", "NET-03", "Close")

	var content := NetDialog.content(_browse_popup)
	content.add_child(NetDialog.label("Player Name:"))
	_browse_name_input = NetDialog.line_edit(PlayerIdentity.load_saved_name(), "Your name")
	_browse_name_input.max_length = PlayerIdentity.MAX_NAME_LEN
	content.add_child(_browse_name_input)
	content.add_child(NetDialog.label("Relay Server URL:"))
	_browse_url_input = NetDialog.line_edit(InternetLobby.DEFAULT_RELAY_URL, "wss://niemandsland-relay.fly.dev")
	content.add_child(_browse_url_input)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh list"
	refresh_btn.focus_mode = Control.FOCUS_NONE
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
		join_btn.text = "Join"
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
		_load_dialog.title = "Load Battle"
		_load_dialog.size = Vector2i(800, 600)
		_load_dialog.file_selected.connect(_on_load_file_selected)
		add_child(_load_dialog)

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


func _input(event: InputEvent) -> void:
	_register_activity(event)
	if event is InputEventKey and event.pressed and not event.echo:
		# Never fire menu shortcuts while a dialog text field (name / code / URL)
		# has focus — digits in a name like "Boss5" would otherwise trigger menu
		# entries and Esc would quit (same LineEdit guard used in-game).
		if get_viewport().gui_get_focus_owner() is LineEdit:
			return
		if event.keycode == KEY_ESCAPE:
			_on_exit_pressed()
			return
		# Number keys press the matching visible menu entry — bound to the live
		# on-screen index (set by _renumber_buttons), so adding/hiding entries
		# (e.g. CONTINUE, BROWSE ONLINE GAMES) keeps keys and labels in sync.
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var idx: int = event.keycode - KEY_1
			var buttons := _visible_menu_buttons()
			if idx < buttons.size():
				buttons[idx].pressed.emit()

# ===== Static (testable) =====

## Version string for the footer, bound to the project config (single source).
static func version_string() -> String:
	return "v%s" % ProjectSettings.get_setting("application/config/version", "?")

# ===== Private: build the look =====

## AAA wordmark lockup replacing the plain title label: an amber mono kicker line,
## the tracked Orbitron "NIEMANDS|LAND" wordmark, and the HudTokens header rule
## (amber tick + cyan hairline) underneath.
func _build_wordmark() -> void:
	var orbitron := FontVariation.new()
	orbitron.base_font = load(ORBITRON_PATH)
	orbitron.variation_opentype = {"wght": 700}
	orbitron.spacing_glyph = WORDMARK_TRACKING_PX

	logo_label.visible = false
	var lockup := VBoxContainer.new()
	lockup.name = "WordmarkLockup"
	lockup.add_theme_constant_override("separation", 6)
	lockup.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var kicker := Label.new()
	kicker.text = KICKER_TEXT
	var mono := FontVariation.new()
	mono.base_font = load(MONO_PATH)
	mono.spacing_glyph = 3
	kicker.add_theme_font_override("font", mono)
	kicker.add_theme_font_size_override("font_size", 11)
	kicker.add_theme_color_override("font_color", HudTokens.AMBER)
	lockup.add_child(kicker)

	_wordmark_box = HBoxContainer.new()
	_wordmark_box.name = "Wordmark"
	_wordmark_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_wordmark_box.add_theme_constant_override("separation", 2)
	_wordmark_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wordmark_box.add_child(_make_word("NIEMANDS", orbitron, HudTokens.TEXT, false))
	_wordmark_box.add_child(_make_word("LAND", orbitron, HudTokens.CYAN, true))
	lockup.add_child(_wordmark_box)

	# Header rule: amber tick -> cyan hairline (the established section language).
	var rule := HBoxContainer.new()
	rule.add_theme_constant_override("separation", 6)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tick := ColorRect.new()
	tick.color = HudTokens.AMBER
	tick.custom_minimum_size = Vector2(RULE_TICK_W, RULE_H)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.add_child(tick)
	var hairline := ColorRect.new()
	hairline.color = Color(HudTokens.CYAN.r, HudTokens.CYAN.g, HudTokens.CYAN.b, 0.45)
	hairline.custom_minimum_size = Vector2(0, 1)
	hairline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hairline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.add_child(hairline)
	lockup.add_child(rule)

	var parent := logo_label.get_parent()
	parent.add_child(lockup)
	parent.move_child(lockup, logo_label.get_index())
	_wordmark_lockup = lockup


func _make_word(word: String, font: FontVariation, color: Color, glow: bool) -> Label:
	var label := Label.new()
	label.text = word
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", WORDMARK_FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	if glow:
		# Soft "bloom" approximated with a large, offset-less shadow outline.
		label.add_theme_color_override("font_shadow_color", Color(HudTokens.CYAN.r, HudTokens.CYAN.g, HudTokens.CYAN.b, 0.85))
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 0)
		label.add_theme_constant_override("shadow_outline_size", 28)
		label.add_theme_color_override("font_outline_color", Color(HudTokens.CYAN.r, HudTokens.CYAN.g, HudTokens.CYAN.b, 0.5))
		label.add_theme_constant_override("outline_size", 2)
	else:
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
		label.add_theme_constant_override("shadow_offset_y", 3)
	return label


func _style_subtitle() -> void:
	subtitle_label.add_theme_font_size_override("font_size", 13)
	subtitle_label.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)


## Footer version/build lines, bound to the project config (never hardcoded).
func _bind_version() -> void:
	var mono := FontVariation.new()
	mono.base_font = load(MONO_PATH)
	for label: Label in [version_label, build_label]:
		label.add_theme_font_override("font", mono)
		label.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
	version_label.add_theme_font_size_override("font_size", 12)
	build_label.add_theme_font_size_override("font_size", 10)
	version_label.text = version_string()
	var engine: Dictionary = Engine.get_version_info()
	build_label.text = "GODOT %d.%d · %s" % [engine["major"], engine["minor"], OS.get_name().to_upper()]


## CONTINUE shows only when a save exists; it loads the newest one directly.
func _setup_continue_button() -> void:
	var info := SaveManager.latest_save_info()
	if info.is_empty():
		continue_btn.visible = false
		return
	_continue_path = info["path"]
	var stamp: Dictionary = Time.get_datetime_dict_from_unix_time(info["modified_unix"])
	continue_btn.text = "CONTINUE — %s · %02d.%02d.%04d" % [
		str(info["name"]).to_upper(), stamp["day"], stamp["month"], stamp["year"]]
	continue_btn.accent_color = HudTokens.AMBER
	continue_btn.add_theme_color_override("font_color", HudTokens.AMBER)
	continue_btn.visible = true


## Mono index labels ("01"...) reflect the actual visible order.
func _renumber_buttons() -> void:
	var visible_buttons := _visible_menu_buttons()
	for i in visible_buttons.size():
		visible_buttons[i].index_text = "%02d" % (i + 1)


func _visible_menu_buttons() -> Array[MenuListButton]:
	var result: Array[MenuListButton] = []
	for child in menu_buttons.get_children():
		if child is MenuListButton and child.visible:
			result.append(child)
	return result


## Vertical focus chain that loops first <-> last (linear menus loop; playbook).
func _setup_focus_chain() -> void:
	var buttons := _visible_menu_buttons()
	for i in buttons.size():
		var prev := buttons[(i - 1 + buttons.size()) % buttons.size()]
		var next := buttons[(i + 1) % buttons.size()]
		buttons[i].focus_neighbor_top = buttons[i].get_path_to(prev)
		buttons[i].focus_neighbor_bottom = buttons[i].get_path_to(next)
		buttons[i].focus_next = buttons[i].get_path_to(next)
		buttons[i].focus_previous = buttons[i].get_path_to(prev)


## Somber menu score on the Music bus: the CC0 dark-ambient loop once cached
## (fetched in the background on first run), the synth drone pad until then.
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


## Hover on key entries nudges the diorama lens (push-in toward battle, step back
## for the online/table entries) — felt rather than seen.
func _setup_camera_reactivity() -> void:
	var biases := {
		continue_btn: FOV_BIAS_PUSH_IN, start_battle_btn: FOV_BIAS_PUSH_IN,
		host_online_btn: FOV_BIAS_WIDE, join_online_btn: FOV_BIAS_WIDE,
		browse_online_btn: FOV_BIAS_WIDE,
	}
	for btn: Button in biases:
		btn.mouse_entered.connect(func() -> void: diorama.set_fov_bias(biases[btn]))
		btn.mouse_exited.connect(func() -> void: diorama.set_fov_bias(0.0))


## After 60 s without input the UI sleeps and the camera tours the battlefield;
## any input wakes the menu instantly. Skipped under Reduce Motion.
func _setup_attract_mode() -> void:
	if GraphicsSettings.reduce_motion or get_tree().current_scene != self:
		return
	_idle_timer = Timer.new()
	_idle_timer.one_shot = true
	_idle_timer.wait_time = ATTRACT_IDLE_S
	_idle_timer.timeout.connect(_enter_attract)
	add_child(_idle_timer)
	_idle_timer.start()


func _register_activity(_event: InputEvent) -> void:
	if _idle_timer == null:
		return
	if _attract_active:
		_exit_attract()
	_idle_timer.start()  # restart the idle countdown


func _enter_attract() -> void:
	_attract_active = true
	diorama.set_attract(true)
	for layer in _ui_layers():
		var fade := create_tween()
		fade.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		fade.tween_property(layer, "modulate:a", 0.0, 1.2)


func _exit_attract() -> void:
	_attract_active = false
	diorama.set_attract(false)
	for layer in _ui_layers():
		var fade := create_tween()
		fade.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		fade.tween_property(layer, "modulate:a", 1.0, ATTRACT_FADE_S)


func _ui_layers() -> Array:
	return [$SafeArea, $FooterLeft, $Scrim]


## Web-safe post layers on top: vignette + film grain (UV/TIME shaders only).
func _build_post_layers() -> void:
	_add_fullscreen_shader("Vignette", "res://shaders/menu_vignette.gdshader")
	_add_fullscreen_shader("Grain", "res://shaders/menu_grain.gdshader")


func _add_fullscreen_shader(node_name: String, shader_path: String) -> void:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	rect.material = mat
	add_child(rect)
	# Cinematic post FX belongs on the DIORAMA, not on the UI text: slot the rect
	# below SafeArea (above diorama + scrim), keeping wordmark/buttons/ticker crisp.
	move_child(rect, get_node("SafeArea").get_index())
