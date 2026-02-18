extends Control
## Startup Menu with animations
## Handles menu navigation and transitions to game

@onready var logo_label: Label = %LogoLabel
@onready var menu_panel: PanelContainer = %MenuPanel
@onready var start_battle_btn: Button = %StartBattleBtn
@onready var load_battle_btn: Button = %LoadBattleBtn
@onready var exit_game_btn: Button = %ExitGameBtn

var animation_played: bool = false
var _load_dialog: FileDialog


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
	load_battle_btn.pressed.connect(_on_load_battle_pressed)
	exit_game_btn.pressed.connect(_on_exit_pressed)

	# Setup button hover effects
	_setup_button_hover_effects()

	# Play startup animation
	_play_startup_animation()


func _setup_button_hover_effects() -> void:
	"""Add hover effects to all menu buttons"""
	var buttons: Array[Button] = [
		start_battle_btn,
		load_battle_btn,
		exit_game_btn
	]

	for button in buttons:
		button.mouse_entered.connect(_on_button_hover.bind(button))
		button.mouse_exited.connect(_on_button_unhover.bind(button))


func _on_button_hover(button: Button) -> void:
	"""Button hover animation"""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(button, "position:x", 8, 0.2)


func _on_button_unhover(button: Button) -> void:
	"""Button unhover animation"""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(button, "position:x", 0, 0.2)


func _play_startup_animation() -> void:
	"""Plays the startup animation sequence"""
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
	"""Start a new battle"""
	print("Start New Battle pressed")
	_transition_to_game()


func _on_load_battle_pressed() -> void:
	"""Open file dialog to load a saved battle"""
	print("Load Battle pressed")
	_open_load_battle_dialog()


func _on_exit_pressed() -> void:
	"""Exit the game"""
	print("Exit Game pressed")
	get_tree().quit()


func _transition_to_game() -> void:
	"""Transition from menu to game"""
	# Fade out menu
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)

	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished

	# Load game scene
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _open_load_battle_dialog() -> void:
	"""Show file dialog to select a saved battle file"""
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
	"""Handle selected save file and transition to main scene"""
	print("Loading battle from: %s" % path.get_file())
	ProjectSettings.set_setting("opentts/pending_load_path", path)
	_transition_to_game()


func _input(event: InputEvent) -> void:
	"""Handle keyboard shortcuts"""
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_on_exit_pressed()
			KEY_1:
				_on_start_battle_pressed()
			KEY_2:
				_on_load_battle_pressed()


func _remove_theme_overrides() -> void:
	"""Remove hardcoded theme overrides to allow theme to show"""
	# Remove panel style override
	menu_panel.remove_theme_stylebox_override("panel")

	# Remove button overrides and make them use theme
	for button in [start_battle_btn, load_battle_btn]:
		button.flat = false  # Enable theme styling
		button.remove_theme_color_override("font_color")
		button.remove_theme_color_override("font_hover_color")
		button.remove_theme_font_size_override("font_size")

	# Exit button keeps red color for emphasis
	exit_game_btn.flat = false
	exit_game_btn.remove_theme_font_size_override("font_size")
	exit_game_btn.add_theme_color_override("font_color", Color(1.0, 0.35, 0.45))
	exit_game_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.5, 0.6))
