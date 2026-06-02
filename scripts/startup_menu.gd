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
var _relay_url_input: LineEdit
var _join_code_input: LineEdit
var _join_relay_url_input: LineEdit

# --- Modern menu look (built in code) ---
const ACCENT_COLOR := Color(0.0, 0.85, 1.0)
const ORBITRON_PATH := "res://assets/ui_glassmorphism/fonts/Orbitron.ttf"
const WORDMARK_FONT_SIZE := 64
## Anti-war quotes under the title; one is chosen at random each time the menu opens.
const MENU_QUOTES: Array[String] = [
	"“Comrade, I did not want to kill you.”\n— Erich Maria Remarque · All Quiet on the Western Front (1929)",
	"“I see how peoples are set against one another, and in silence, unknowingly, foolishly, obediently, innocently slay one another.”\n— Erich Maria Remarque · All Quiet on the Western Front (1929)",
	"“We are forlorn like children, and experienced like old men; we are crude and sorrowful and superficial — I believe we are lost.”\n— Erich Maria Remarque · All Quiet on the Western Front (1929)",
	"“The dead only know one thing: it is better to be alive.”\n— Joker · Full Metal Jacket (1987)",
	"“Babies — infants who belong at their mothers' breasts. You feel ancient among all these kids.”\n— The Captain · Das Boot (1981)",
	"“We did not fight the enemy; we fought ourselves — and the enemy was in us.”\n— Chris Taylor · Platoon (1986)",
	"“The enemy is anybody who's going to get you killed, no matter which side he is on.”\n— Joseph Heller · Catch-22 (1961)",
	"“Patriotism is the last refuge of a scoundrel.”\n— Col. Dax · Paths of Glory (1957)",
	"“War don't ennoble men. It turns them into dogs — poisons the soul.”\n— Pvt. Witt · The Thin Red Line (1998)",
	"“The horror… the horror.”\n— Colonel Kurtz · Apocalypse Now (1979)",
]
var _wordmark_box: HBoxContainer
var _backdrop_camera: Camera3D
var _drift: float = 0.0
var _parallax: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Check if an .nml file was passed via command-line (e.g. double-click in file manager)
	var file_to_open := _get_save_from_cmdline()
	if not file_to_open.is_empty():
		print("Opening file from command line: %s" % file_to_open)
		ProjectSettings.set_setting("niemandsland/pending_load_path", file_to_open)
		# Skip menu entirely and go straight to game
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return

	# Apply Glassmorphism theme
	theme = ThemeManager.get_current_theme()

	# Remove hardcoded theme overrides to allow theme to apply
	_remove_theme_overrides()

	# Build the modern look: live skybox backdrop, Orbitron wordmark, embers, post FX.
	_build_skybox_backdrop()
	_build_wordmark()
	_build_embers()
	_build_post_layers()
	_apply_random_quote()

	# Hide menu initially for animation
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
		_wordmark_box.modulate.a = 1.0
		menu_panel.modulate.a = 1.0
		return

	animation_played = true

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Wordmark "power-on": fade + scale up
	_wordmark_box.scale = Vector2(0.85, 0.85)
	tween.tween_property(_wordmark_box, "modulate:a", 1.0, 0.9)
	tween.parallel().tween_property(_wordmark_box, "scale", Vector2.ONE, 0.9)

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
	_host_popup.size = Vector2i(450, 200)
	_host_popup.ok_button_text = "Start Hosting"

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	# Relay URL
	var url_label = Label.new()
	url_label.text = "Relay Server URL:"
	vbox.add_child(url_label)

	_relay_url_input = LineEdit.new()
	_relay_url_input.text = InternetLobby.DEFAULT_RELAY_URL
	_relay_url_input.placeholder_text = "wss://niemandsland-relay.fly.dev"
	vbox.add_child(_relay_url_input)

	# Info text
	var info = Label.new()
	info.text = "The room code will be shown in-game after connecting."
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

	# Pass settings to main scene — connection happens there
	ProjectSettings.set_setting("niemandsland/pending_internet_lobby", true)
	ProjectSettings.set_setting("niemandsland/internet_is_host", true)
	ProjectSettings.set_setting("niemandsland/internet_relay_url", url)
	_transition_to_game()


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
	_join_relay_url_input.placeholder_text = "wss://niemandsland-relay.fly.dev"
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

	# Pass settings to main scene — connection happens there
	ProjectSettings.set_setting("niemandsland/pending_internet_lobby", true)
	ProjectSettings.set_setting("niemandsland/internet_is_host", false)
	ProjectSettings.set_setting("niemandsland/internet_relay_url", url)
	ProjectSettings.set_setting("niemandsland/internet_room_code", code)
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
		_load_dialog.filters = PackedStringArray(["*.nml ; Niemandsland Save Files"])
		_load_dialog.title = "Load Battle"
		_load_dialog.size = Vector2i(800, 600)
		_load_dialog.file_selected.connect(_on_load_file_selected)
		add_child(_load_dialog)

	_load_dialog.current_dir = SaveManager.get_default_save_dir()
	_load_dialog.popup_centered()


func _on_load_file_selected(path: String) -> void:
	print("Loading battle from: %s" % path.get_file())
	ProjectSettings.set_setting("niemandsland/pending_load_path", path)
	_transition_to_game()


## Check command-line arguments for an .nml file path.
## This handles the case where the user double-clicks an .nml file in the OS file manager
## or drags a file onto the application executable.
func _get_save_from_cmdline() -> String:
	# OS.get_cmdline_user_args() returns args after "--" separator (Godot convention)
	# OS.get_cmdline_args() returns all args including engine flags
	for arg in OS.get_cmdline_user_args():
		if arg.ends_with(".nml") and FileAccess.file_exists(arg):
			return arg

	# Also check regular args (some OS pass file path as first arg directly)
	for arg in OS.get_cmdline_args():
		# Skip Godot engine flags (start with - or --)
		if arg.begins_with("-"):
			continue
		if arg.ends_with(".nml") and FileAccess.file_exists(arg):
			return arg

	return ""


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


# ===== Modern look (built in code) =====


func _process(delta: float) -> void:
	# Slow camera drift + subtle mouse parallax on the live skybox backdrop.
	if not is_instance_valid(_backdrop_camera):
		return
	_drift += delta * 0.012
	var vp: Vector2 = get_viewport_rect().size
	var m: Vector2 = get_viewport().get_mouse_position()
	var target := Vector2(m.x / maxf(vp.x, 1.0) - 0.5, m.y / maxf(vp.y, 1.0) - 0.5)
	_parallax = _parallax.lerp(target, delta * 2.5)
	_backdrop_camera.rotation = Vector3(-_parallax.y * 0.06, _drift + _parallax.x * 0.10, 0.0)


## Live animated space backdrop (reuses materials/space_skybox.tres) behind the menu.
func _build_skybox_backdrop() -> void:
	var container := SubViewportContainer.new()
	container.name = "SkyBackdrop"
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	move_child(container, 0)

	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = load("res://materials/space_skybox.tres")
	env.sky = sky
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.12
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	_backdrop_camera = Camera3D.new()
	_backdrop_camera.fov = 70.0
	viewport.add_child(_backdrop_camera)


## Replaces the plain title label with an Orbitron "NIEMANDS" + "LAND" wordmark.
func _build_wordmark() -> void:
	var orbitron := FontVariation.new()
	orbitron.base_font = load(ORBITRON_PATH)
	orbitron.variation_opentype = {"wght": 700}

	logo_label.visible = false
	_wordmark_box = HBoxContainer.new()
	_wordmark_box.name = "Wordmark"
	_wordmark_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_wordmark_box.add_theme_constant_override("separation", 2)
	_wordmark_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wordmark_box.add_child(_make_word("NIEMANDS", orbitron, Color(0.86, 0.89, 0.94), false))
	_wordmark_box.add_child(_make_word("LAND", orbitron, ACCENT_COLOR, true))
	_wordmark_box.modulate.a = 0.0

	var parent := logo_label.get_parent()
	parent.add_child(_wordmark_box)
	parent.move_child(_wordmark_box, logo_label.get_index())


## Picks a random anti-war quote for the menu's quote line (rotates each launch).
func _apply_random_quote() -> void:
	var quote_label := get_node_or_null("LogoContainer/QuoteLabel") as Label
	if quote_label == null:
		return
	randomize()
	quote_label.text = MENU_QUOTES[randi() % MENU_QUOTES.size()]


func _make_word(text: String, font: FontVariation, color: Color, glow: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", WORDMARK_FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	if glow:
		# Soft "bloom" approximated with a large, offset-less shadow outline.
		label.add_theme_color_override("font_shadow_color", Color(ACCENT_COLOR.r, ACCENT_COLOR.g, ACCENT_COLOR.b, 0.85))
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 0)
		label.add_theme_constant_override("shadow_outline_size", 28)
		label.add_theme_color_override("font_outline_color", Color(ACCENT_COLOR.r, ACCENT_COLOR.g, ACCENT_COLOR.b, 0.5))
		label.add_theme_constant_override("outline_size", 2)
	else:
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
		label.add_theme_constant_override("shadow_offset_y", 3)
	return label


## Slow rising embers (CPUParticles2D → web-safe, unlike GPUParticles2D on web).
func _build_embers() -> void:
	var embers := CPUParticles2D.new()
	embers.name = "Embers"
	var vp: Vector2 = get_viewport_rect().size
	embers.position = Vector2(vp.x * 0.5, vp.y + 16.0)
	embers.amount = 56
	embers.lifetime = 9.0
	embers.preprocess = 9.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(vp.x * 0.55, 6.0)
	embers.direction = Vector2.UP
	embers.spread = 14.0
	embers.gravity = Vector2(0.0, -7.0)
	embers.initial_velocity_min = 14.0
	embers.initial_velocity_max = 34.0
	embers.scale_amount_min = 1.0
	embers.scale_amount_max = 2.4
	embers.color = Color(0.2, 0.75, 1.0, 0.5)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.4, 0.85, 1.0, 0.0))
	ramp.set_color(1, Color(0.1, 0.6, 1.0, 0.0))
	ramp.add_point(0.25, Color(0.5, 0.9, 1.0, 0.6))
	embers.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	embers.material = mat

	add_child(embers)
	move_child(embers, 2)  # above backdrop + overlay, behind the logo


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
	add_child(rect)  # added last → on top
