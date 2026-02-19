extends Control
## Startup Menu with animations
## Handles menu navigation and transitions to game

@onready var logo_label: Label = %LogoLabel
@onready var menu_panel: PanelContainer = %MenuPanel
@onready var start_battle_btn: Button = %StartBattleBtn
@onready var host_online_btn: Button = %HostOnlineBtn
@onready var join_online_btn: Button = %JoinOnlineBtn
@onready var load_battle_btn: Button = %LoadBattleBtn
@onready var exit_game_btn: Button = %ExitGameBtn

var animation_played: bool = false
var _load_dialog: FileDialog
var _host_popup: AcceptDialog
var _join_popup: AcceptDialog
var _internet_lobby: InternetLobby = null
var _relay_url_input: LineEdit
var _room_code_label: Label
var _join_code_input: LineEdit
var _join_relay_url_input: LineEdit


func _ready() -> void:
	# Apply Glassmorphism theme
	theme = ThemeManager.get_current_theme()

	# Remove hardcoded theme overrides to allow theme to apply
	_remove_theme_overrides()

	# Hide menu initially for animation
	logo_label.modulate.a = 0.0
	menu_panel.modulate.a = 0.0

	# Connect buttons
	start_battle_btn.pressed.connect(_on_start_battle_pressed)
	host_online_btn.pressed.connect(_on_host_online_pressed)
	join_online_btn.pressed.connect(_on_join_online_pressed)
	load_battle_btn.pressed.connect(_on_load_battle_pressed)
	exit_game_btn.pressed.connect(_on_exit_pressed)

	# Setup button hover effects
	_setup_button_hover_effects()

	# Play startup animation
	_play_startup_animation()


func _setup_button_hover_effects() -> void:
	var buttons: Array[Button] = [
		start_battle_btn,
		host_online_btn,
		join_online_btn,
		load_battle_btn,
		exit_game_btn
	]

	for button in buttons:
		button.mouse_entered.connect(_on_button_hover.bind(button))
		button.mouse_exited.connect(_on_button_unhover.bind(button))


func _on_button_hover(button: Button) -> void:
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(button, "position:x", 8, 0.2)


func _on_button_unhover(button: Button) -> void:
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(button, "position:x", 0, 0.2)


func _play_startup_animation() -> void:
	if animation_played:
		# Skip animation on subsequent loads
		logo_label.modulate.a = 1.0
		menu_panel.modulate.a = 1.0
		return

	animation_played = true

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Logo fade in + scale
	logo_label.scale = Vector2(0.8, 0.8)
	tween.tween_property(logo_label, "modulate:a", 1.0, 0.8)
	tween.parallel().tween_property(logo_label, "scale", Vector2.ONE, 0.8)

	# Menu panel fade in
	tween.tween_property(menu_panel, "modulate:a", 1.0, 0.4).set_delay(0.3)

	print("Startup menu animation complete")


func _on_start_battle_pressed() -> void:
	print("Start New Battle pressed")
	_transition_to_game()


func _on_load_battle_pressed() -> void:
	print("Load Battle pressed")
	_open_load_battle_dialog()


func _on_exit_pressed() -> void:
	print("Exit Game pressed")
	get_tree().quit()


# ===== Online Multiplayer =====


func _on_host_online_pressed() -> void:
	print("Host Online Game pressed")
	_show_host_popup()


func _on_join_online_pressed() -> void:
	print("Join Online Game pressed")
	_show_join_popup()


func _show_host_popup() -> void:
	if _host_popup:
		_host_popup.queue_free()

	_host_popup = AcceptDialog.new()
	_host_popup.title = "Host Online Game"
	_host_popup.size = Vector2i(450, 280)
	_host_popup.ok_button_text = "Start Hosting"

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	# Relay URL
	var url_label = Label.new()
	url_label.text = "Relay Server URL:"
	vbox.add_child(url_label)

	_relay_url_input = LineEdit.new()
	_relay_url_input.text = InternetLobby.DEFAULT_RELAY_URL
	_relay_url_input.placeholder_text = "wss://opentts-relay.fly.dev"
	vbox.add_child(_relay_url_input)

	# Room code display (initially hidden)
	_room_code_label = Label.new()
	_room_code_label.text = ""
	_room_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_code_label.add_theme_font_size_override("font_size", 32)
	_room_code_label.add_theme_color_override("font_color", Color(0.4, 0.85, 1))
	_room_code_label.visible = false
	vbox.add_child(_room_code_label)

	# Info text
	var info = Label.new()
	info.text = "Share the room code with your opponent."
	info.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(info)

	_host_popup.add_child(vbox)
	_host_popup.confirmed.connect(_on_host_confirmed)
	add_child(_host_popup)
	_host_popup.popup_centered()


func _on_host_confirmed() -> void:
	var url = _relay_url_input.text.strip_edges()
	if url.is_empty():
		url = InternetLobby.DEFAULT_RELAY_URL

	# Create lobby and start hosting
	_internet_lobby = InternetLobby.new()
	add_child(_internet_lobby)
	_internet_lobby.room_code_ready.connect(_on_room_code_ready)
	_internet_lobby.peer_joined.connect(_on_startup_peer_joined)
	_internet_lobby.internet_connection_failed.connect(_on_startup_connection_failed)

	var err = _internet_lobby.host_internet_game(url)
	if err != OK:
		_room_code_label.text = "Connection failed!"
		_room_code_label.add_theme_color_override("font_color", Color.RED)
		_room_code_label.visible = true


func _on_room_code_ready(code: String) -> void:
	var display_code = InternetLobby._format_code(code)
	_room_code_label.text = display_code
	_room_code_label.visible = true
	DisplayServer.clipboard_set(code)
	print("Room code %s copied to clipboard" % display_code)

	# Update popup to show waiting state
	if _host_popup:
		_host_popup.ok_button_text = "Waiting for player..."
		_host_popup.get_ok_button().disabled = true


func _on_startup_peer_joined(_peer_id: int) -> void:
	# Player joined - transition to game
	print("Player joined, starting game!")
	# Store lobby reference for main scene to pick up
	ProjectSettings.set_setting("opentts/pending_internet_lobby", true)
	ProjectSettings.set_setting("opentts/internet_is_host", true)
	ProjectSettings.set_setting("opentts/internet_relay_url", _internet_lobby.relay_url)
	ProjectSettings.set_setting("opentts/internet_room_code", _internet_lobby.room_code)
	if _host_popup:
		_host_popup.hide()
	_transition_to_game()


func _on_startup_connection_failed(reason: String) -> void:
	if _room_code_label:
		_room_code_label.text = "Error: %s" % reason
		_room_code_label.add_theme_color_override("font_color", Color.RED)
		_room_code_label.visible = true


func _show_join_popup() -> void:
	if _join_popup:
		_join_popup.queue_free()

	_join_popup = AcceptDialog.new()
	_join_popup.title = "Join Online Game"
	_join_popup.size = Vector2i(450, 250)
	_join_popup.ok_button_text = "Join"

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	# Room code input
	var code_label = Label.new()
	code_label.text = "Room Code:"
	vbox.add_child(code_label)

	_join_code_input = LineEdit.new()
	_join_code_input.placeholder_text = "ABC-123"
	_join_code_input.max_length = 7  # 6 chars + optional hyphen
	_join_code_input.add_theme_font_size_override("font_size", 24)
	_join_code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_join_code_input)

	# Relay URL
	var url_label = Label.new()
	url_label.text = "Relay Server URL:"
	vbox.add_child(url_label)

	_join_relay_url_input = LineEdit.new()
	_join_relay_url_input.text = InternetLobby.DEFAULT_RELAY_URL
	_join_relay_url_input.placeholder_text = "wss://opentts-relay.fly.dev"
	vbox.add_child(_join_relay_url_input)

	_join_popup.add_child(vbox)
	_join_popup.confirmed.connect(_on_join_confirmed)
	add_child(_join_popup)
	_join_popup.popup_centered()


func _on_join_confirmed() -> void:
	var code = _join_code_input.text.strip_edges().replace("-", "").to_upper()
	if code.is_empty():
		return

	var url = _join_relay_url_input.text.strip_edges()
	if url.is_empty():
		url = InternetLobby.DEFAULT_RELAY_URL

	# Create lobby and join
	_internet_lobby = InternetLobby.new()
	add_child(_internet_lobby)
	_internet_lobby.internet_connected.connect(_on_join_success)
	_internet_lobby.internet_connection_failed.connect(_on_startup_connection_failed)

	var err = _internet_lobby.join_internet_game(code, url)
	if err != OK:
		push_error("Join failed with error: %d" % err)


func _on_join_success(_peer_id: int) -> void:
	print("Successfully joined game!")
	ProjectSettings.set_setting("opentts/pending_internet_lobby", true)
	ProjectSettings.set_setting("opentts/internet_is_host", false)
	ProjectSettings.set_setting("opentts/internet_relay_url", _internet_lobby.relay_url)
	ProjectSettings.set_setting("opentts/internet_room_code", _internet_lobby.room_code)
	if _join_popup:
		_join_popup.hide()
	_transition_to_game()


# ===== Shared =====


func _transition_to_game() -> void:
	# Fade out menu
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)

	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished

	# Load game scene
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _open_load_battle_dialog() -> void:
	if _load_dialog == null:
		_load_dialog = FileDialog.new()
		_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_load_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_load_dialog.filters = PackedStringArray(["*.otts ; OpenTTS Save Files"])
		_load_dialog.title = "Load Battle"
		_load_dialog.size = Vector2i(800, 600)
		_load_dialog.file_selected.connect(_on_load_file_selected)
		add_child(_load_dialog)

	_load_dialog.current_dir = SaveManager.get_default_save_dir()
	_load_dialog.popup_centered()


func _on_load_file_selected(path: String) -> void:
	print("Loading battle from: %s" % path.get_file())
	ProjectSettings.set_setting("opentts/pending_load_path", path)
	_transition_to_game()


func _input(event: InputEvent) -> void:
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


func _remove_theme_overrides() -> void:
	# Remove panel style override
	menu_panel.remove_theme_stylebox_override("panel")

	# Remove button overrides and make them use theme
	for button in [start_battle_btn, host_online_btn, join_online_btn, load_battle_btn]:
		button.flat = false  # Enable theme styling
		button.remove_theme_color_override("font_color")
		button.remove_theme_color_override("font_hover_color")
		button.remove_theme_font_size_override("font_size")

	# Exit button keeps red color for emphasis
	exit_game_btn.flat = false
	exit_game_btn.remove_theme_font_size_override("font_size")
	exit_game_btn.add_theme_color_override("font_color", Color(1.0, 0.35, 0.45))
	exit_game_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.5, 0.6))
