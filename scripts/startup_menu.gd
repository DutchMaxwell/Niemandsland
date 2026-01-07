extends Control
## Startup Menu with animations
## Handles menu navigation and transitions to game

@onready var logo_label: Label = %LogoLabel
@onready var menu_panel: PanelContainer = %MenuPanel
@onready var quick_battle_btn: Button = %QuickBattleBtn
@onready var multiplayer_btn: Button = %MultiplayerBtn
@onready var load_game_btn: Button = %LoadGameBtn
@onready var exit_btn: Button = %ExitBtn

var animation_played: bool = false


func _ready() -> void:
	# Apply Kenney UI theme from global ThemeManager
	theme = ThemeManager.get_current_theme()

	# Listen for theme changes
	ThemeManager.theme_changed.connect(_on_theme_changed)

	# Remove hardcoded theme overrides to allow Kenney theme to apply
	_remove_theme_overrides()

	# Hide menu initially for animation
	logo_label.modulate.a = 0.0
	menu_panel.modulate.a = 0.0

	# Connect buttons
	quick_battle_btn.pressed.connect(_on_quick_battle_pressed)
	multiplayer_btn.pressed.connect(_on_multiplayer_pressed)
	load_game_btn.pressed.connect(_on_load_game_pressed)
	exit_btn.pressed.connect(_on_exit_pressed)

	# Setup button hover effects
	_setup_button_hover_effects()

	# Play startup animation
	_play_startup_animation()


func _setup_button_hover_effects() -> void:
	"""Add hover effects to all menu buttons"""
	var buttons = [
		quick_battle_btn,
		multiplayer_btn,
		load_game_btn,
		exit_btn
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


func _on_quick_battle_pressed() -> void:
	"""Start a quick battle"""
	print("Quick Battle pressed")
	_transition_to_game()


func _on_multiplayer_pressed() -> void:
	"""Open multiplayer lobby"""
	print("Multiplayer pressed")
	# TODO: Open multiplayer lobby
	push_warning("Multiplayer lobby not yet implemented")


func _on_load_game_pressed() -> void:
	"""Open load game dialog"""
	print("Load Game pressed")
	# TODO: Open load dialog
	push_warning("Load game dialog not yet implemented")


func _on_exit_pressed() -> void:
	"""Exit the game"""
	print("Exit pressed")
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


func _input(event: InputEvent) -> void:
	"""Handle keyboard shortcuts"""
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				# ESC to exit
				_on_exit_pressed()
			KEY_1:
				_on_quick_battle_pressed()
			KEY_2:
				_on_multiplayer_pressed()
			KEY_3:
				_on_load_game_pressed()


func _remove_theme_overrides() -> void:
	"""Remove hardcoded theme overrides to allow theme to show"""
	# Remove panel style override
	menu_panel.remove_theme_stylebox_override("panel")

	# Remove button overrides and make them use theme
	for button in [quick_battle_btn, multiplayer_btn, load_game_btn]:
		button.flat = false  # Enable theme styling
		button.remove_theme_color_override("font_color")
		button.remove_theme_color_override("font_hover_color")
		button.remove_theme_font_size_override("font_size")

	# Exit button keeps red color for emphasis
	exit_btn.flat = false
	exit_btn.remove_theme_font_size_override("font_size")
	exit_btn.add_theme_color_override("font_color", Color(1.0, 0.35, 0.45))
	exit_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.5, 0.6))


func _on_theme_changed(new_theme: Theme) -> void:
	"""Handle theme changes from ThemeManager"""
	theme = new_theme
	_remove_theme_overrides()
	print("Startup menu theme updated to: %s" % ThemeManager.get_current_theme_name())
