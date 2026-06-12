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

## Entrance choreography (motion tokens; see docs/archive/AAA_UI_PLAYBOOK.md).
const ENTRANCE_WORDMARK_DELAY := 0.05
const ENTRANCE_WORDMARK_S := 0.45
const ENTRANCE_BUTTONS_START := 0.30
const ENTRANCE_BUTTON_STAGGER := 0.06
const ENTRANCE_SLIDE_PX := 24.0
const ENTRANCE_FOOTER_AT := 0.60
const ENTRANCE_TICKER_AT := 1.0
const REDUCED_MOTION_FADE_S := 0.2
const ENTRANCE_COVER_FADE_S := 0.8   # slow, deliberate reveal once the diorama is ready
const MONO_FONT_PATH := "res://assets/ui_glassmorphism/fonts/SourceCodePro.ttf"

const MUSIC_VOLUME_DB := -12.0
const MUSIC_FADE_IN_S := 2.5

## Hover camera reactivity (degrees of FOV bias) + idle attract mode.
const FOV_BIAS_PUSH_IN := -2.0   # Continue/Start: lean toward the battlefield
const FOV_BIAS_WIDE := 2.0       # Host/Join: step back for the wider table
const ATTRACT_IDLE_S := 60.0
const ATTRACT_FADE_S := 0.2


# === Node references ===

@onready var diorama: MenuDiorama = %Diorama
@onready var logo_label: Label = %LogoLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var menu_buttons: VBoxContainer = %MenuButtons
@onready var continue_btn: MenuListButton = %ContinueBtn
@onready var start_battle_btn: MenuListButton = %StartBattleBtn
@onready var host_online_btn: MenuListButton = %HostOnlineBtn
@onready var join_online_btn: MenuListButton = %JoinOnlineBtn
@onready var load_battle_btn: MenuListButton = %LoadBattleBtn
@onready var exit_game_btn: MenuListButton = %ExitGameBtn
@onready var ticker: MenuTicker = %Ticker
@onready var version_label: Label = %VersionLabel
@onready var build_label: Label = %BuildLabel

# === Private variables ===

var animation_played: bool = false
var _load_dialog: FileDialog
var _host_popup: AcceptDialog
var _join_popup: AcceptDialog
var _relay_url_input: LineEdit
var _join_code_input: LineEdit
var _join_relay_url_input: LineEdit
var _wordmark_box: HBoxContainer
var _wordmark_lockup: VBoxContainer
var _loading_cover: ColorRect = null
var _loading_label: Label = null
var _loading_bar: ProgressBar = null
var _continue_path := ""
var _music_player: AudioStreamPlayer = null
var _idle_timer: Timer = null
var _attract_active := false

# === Lifecycle ===

func _ready() -> void:
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
	host_online_btn.pressed.connect(_on_host_online_pressed)
	join_online_btn.pressed.connect(_on_join_online_pressed)
	load_battle_btn.pressed.connect(_on_load_battle_pressed)
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
	# pops or stutters in view; the bar communicates the app is alive during the parse.
	_build_loading_cover()
	diorama.loading_progress.connect(_on_diorama_loading)
	diorama.diorama_ready.connect(_on_diorama_ready, CONNECT_ONE_SHOT)

	# Hide the to-be-revealed UI until the cover fades (so nothing shows behind it).
	_wordmark_lockup.modulate.a = 0.0
	for btn: Button in _visible_menu_buttons():
		btn.modulate.a = 0.0
	$FooterLeft.modulate.a = 0.0
	ticker.modulate.a = 0.0


## Fade the loading cover out, then run the entrance choreography (or, under Reduce
## Motion, a single quiet fade). Called once the diorama is fully built.
func _on_diorama_ready() -> void:
	if diorama.loading_progress.is_connected(_on_diorama_loading):
		diorama.loading_progress.disconnect(_on_diorama_loading)
	if _loading_cover != null and is_instance_valid(_loading_cover):
		var cover_fade := create_tween()
		cover_fade.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		cover_fade.tween_property(_loading_cover, "modulate:a", 0.0, ENTRANCE_COVER_FADE_S)
		cover_fade.tween_callback(_loading_cover.queue_free)

	if GraphicsSettings.reduce_motion:
		for node in [_wordmark_lockup, $FooterLeft, ticker]:
			node.modulate.a = 1.0
		for btn: Button in _visible_menu_buttons():
			btn.modulate.a = 1.0
		ticker.start()
		return
	_play_entrance()


func _on_diorama_loading(label: String, ratio: float) -> void:
	if _loading_label != null and is_instance_valid(_loading_label):
		_loading_label.text = label
	if _loading_bar != null and is_instance_valid(_loading_bar):
		_loading_bar.value = ratio


## Black full-screen cover with a centred "LOADING 3D MODELS" line + a thin cyan bar,
## shown while the diorama parses its models. Added last so it sits above everything.
func _build_loading_cover() -> void:
	_loading_cover = ColorRect.new()
	_loading_cover.color = Color.BLACK
	_loading_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_cover.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow input while loading
	add_child(_loading_cover)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_cover.add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var mono := FontVariation.new()
	mono.base_font = load(MONO_FONT_PATH)
	mono.spacing_glyph = 2
	_loading_label = Label.new()
	_loading_label.text = "LOADING 3D MODELS"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_override("font", mono)
	_loading_label.add_theme_font_size_override("font_size", 13)
	_loading_label.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
	box.add_child(_loading_label)

	_loading_bar = ProgressBar.new()
	_loading_bar.custom_minimum_size = Vector2(360, 3)
	_loading_bar.min_value = 0.0
	_loading_bar.max_value = 1.0
	_loading_bar.step = 0.001
	_loading_bar.value = 0.0
	_loading_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	var fill := StyleBoxFlat.new()
	fill.bg_color = HudTokens.CYAN
	_loading_bar.add_theme_stylebox_override("background", bg)
	_loading_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_loading_bar)


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


func _on_load_battle_pressed() -> void:
	_open_load_battle_dialog()


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


func _on_update_prompt_closed(prompt: UpdatePrompt, download: bool) -> void:
	if prompt.is_skip_checked():
		UpdateChecker.set_skip_version(prompt.latest_version)
	if download:
		OS.shell_open(prompt.release_url)
	prompt.queue_free()

# ===== Online Multiplayer =====

func _on_host_online_pressed() -> void:
	_show_host_popup()


func _on_join_online_pressed() -> void:
	_show_join_popup()


func _show_host_popup() -> void:
	if _host_popup:
		_host_popup.queue_free()
	_host_popup = _build_net_dialog("HOST ONLINE GAME", "NET-01", "Start Hosting")

	var content := _net_dialog_content(_host_popup)
	content.add_child(_net_label("Relay Server URL:"))
	_relay_url_input = _net_line_edit(InternetLobby.DEFAULT_RELAY_URL, "wss://niemandsland-relay.fly.dev")
	content.add_child(_relay_url_input)
	var info := _net_label("The room code will be shown in-game after connecting.")
	info.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	content.add_child(info)

	_host_popup.confirmed.connect(_on_host_confirmed)
	add_child(_host_popup)
	_host_popup.popup_centered()
	UiPolish.keep_window_reachable(_host_popup, Vector2i(460, 240))
	_relay_url_input.grab_focus()


func _on_host_confirmed() -> void:
	var url = _relay_url_input.text.strip_edges()
	if url.is_empty():
		url = InternetLobby.DEFAULT_RELAY_URL

	# Pass settings to main scene — connection happens there
	ProjectSettings.set_setting("niemandsland/pending_internet_lobby", true)
	ProjectSettings.set_setting("niemandsland/internet_is_host", true)
	ProjectSettings.set_setting("niemandsland/internet_relay_url", url)
	_transition_to_game()


func _show_join_popup() -> void:
	if _join_popup:
		_join_popup.queue_free()
	_join_popup = _build_net_dialog("JOIN ONLINE GAME", "NET-02", "Join")

	var content := _net_dialog_content(_join_popup)
	content.add_child(_net_label("Room Code:"))
	_join_code_input = _net_line_edit("", "ABC-123")
	_join_code_input.max_length = 7  # 6 chars + optional hyphen
	_join_code_input.add_theme_font_size_override("font_size", 24)
	_join_code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_join_code_input)
	content.add_child(_net_label("Relay Server URL:"))
	_join_relay_url_input = _net_line_edit(InternetLobby.DEFAULT_RELAY_URL, "wss://niemandsland-relay.fly.dev")
	content.add_child(_join_relay_url_input)

	_join_popup.confirmed.connect(_on_join_confirmed)
	add_child(_join_popup)
	_join_popup.popup_centered()
	UiPolish.keep_window_reachable(_join_popup, Vector2i(460, 280))
	_join_code_input.grab_focus()


func _on_join_confirmed() -> void:
	var code = _join_code_input.text.strip_edges().replace("-", "").to_upper()
	if code.is_empty():
		return

	var url = _join_relay_url_input.text.strip_edges()
	if url.is_empty():
		url = InternetLobby.DEFAULT_RELAY_URL

	# Pass settings to main scene — connection happens there
	ProjectSettings.set_setting("niemandsland/pending_internet_lobby", true)
	ProjectSettings.set_setting("niemandsland/internet_is_host", false)
	ProjectSettings.set_setting("niemandsland/internet_relay_url", url)
	ProjectSettings.set_setting("niemandsland/internet_room_code", code)
	_transition_to_game()


## Shared chrome for the host/join dialogs: HudTokens glass panel + corner brackets
## + an Orbitron header with the mono net index — content goes into _net_dialog_content.
func _build_net_dialog(title_text: String, index: String, ok_text: String) -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.title = title_text.capitalize()
	dialog.ok_button_text = ok_text

	var panel := PanelContainer.new()
	panel.name = "NetPanel"
	panel.add_theme_stylebox_override("panel", HudTokens.panel_style())
	panel.add_child(HudFrame.new())

	var margin := MarginContainer.new()
	UiPolish.set_dialog_margins(margin)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "NetContent"
	vbox.add_theme_constant_override("separation", HudTokens.SPACE_12)
	vbox.add_child(HudTokens.header(title_text, index))
	margin.add_child(vbox)

	dialog.add_child(panel)
	return dialog


func _net_dialog_content(dialog: AcceptDialog) -> VBoxContainer:
	return dialog.get_node("NetPanel/MarginContainer/NetContent") as VBoxContainer


func _net_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	return label


func _net_line_edit(text_value: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text_value
	edit.placeholder_text = placeholder
	return edit

# ===== Shared =====

func _transition_to_game() -> void:
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate:a", 0.0, HudTokens.DUR_SCREEN)
	await tween.finished
	get_tree().change_scene_to_file("res://scenes/main.tscn")


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
		match event.keycode:
			KEY_ESCAPE:
				_on_exit_pressed()
			KEY_1:
				_on_start_battle_pressed()
			KEY_2:
				_on_host_online_pressed()
			KEY_3:
				_on_join_online_pressed()
			KEY_4:
				_on_load_battle_pressed()

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
