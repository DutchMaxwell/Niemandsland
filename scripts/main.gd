extends Node3D
## Main scene controller for OpenTTS
## Handles initialization and connects UI signals

@onready var object_manager: Node3D = $ObjectManager
@onready var table: StaticBody3D = $Table
@onready var camera_pivot: Node3D = $CameraPivot
@onready var directional_light: DirectionalLight3D = $DirectionalLight3D
@onready var world_environment: WorldEnvironment = $WorldEnvironment

# Tron Intro
var tron_intro: TronIntro
var _intro_finished: bool = false

# Lighting Controller
var lighting_controller: Node
var lighting_panel: Window

# Group rotation state
var _is_group_rotating: bool = false
const GROUP_ROTATION_SPEED: float = 90.0  # degrees per second
@onready var dice_result_label: Label = $UI/HUD/DiceResult
@onready var distance_label: Label = $UI/HUD/DistanceLabel
@onready var clear_all_btn: Button = %ClearAll
@onready var performance_label: Label = %PerformanceLabel

# Table size UI elements
@onready var table_size_option: OptionButton = %TableSizeOption
@onready var custom_size_container: VBoxContainer = %CustomSizeContainer
@onready var unit_option: OptionButton = %UnitOption
@onready var width_input: SpinBox = %WidthInput
@onready var length_input: SpinBox = %LengthInput
@onready var apply_custom_btn: Button = %ApplyCustomBtn

# Dice Roller Plugin UI
@onready var dice_roller_control = %DiceRollerControl
@onready var roll_button: Button = %RollButton
@onready var quick_roll_button: Button = %QuickRollButton
@onready var roller_result_label: Label = %RollerResultLabel
@onready var dice_count_spinner: SpinBox = %DiceCountSpinner
@onready var current_dice_label: Label = %CurrentDiceLabel

# Network UI elements
@onready var network_manager = %NetworkManager
@onready var network_status_label: Label = %StatusLabel
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var disconnect_button: Button = %DisconnectButton
@onready var address_input: LineEdit = %AddressInput

# Model loader UI
@onready var load_model_btn: Button = %LoadModel
@onready var model_file_dialog: FileDialog = %ModelFileDialog

# TTS Import UI
@onready var import_tts_btn: Button = %ImportTTS
@onready var import_tts_online_btn: Button = %ImportTTSOnline
@onready var tts_json_dialog: FileDialog = %TTSJsonDialog
@onready var tts_models_dialog: FileDialog = %TTSModelsDialog
@onready var tts_images_dialog: FileDialog = %TTSImagesDialog

# Save/Load UI
@onready var save_manager = %SaveManager
@onready var save_game_btn: Button = %SaveGameBtn
@onready var load_game_btn: Button = %LoadGameBtn
@onready var save_game_dialog: FileDialog = %SaveGameDialog
@onready var load_game_dialog: FileDialog = %LoadGameDialog

# Graphics Settings UI
@onready var graphics_quality_option: OptionButton = %GraphicsQualityOption

# Terrain Browser UI
@onready var terrain_library = %TerrainLibrary
@onready var terrain_browser_btn: Button = %TerrainBrowser
@onready var terrain_browser_popup: Window = %TerrainBrowserPopup
@onready var terrain_category_option: OptionButton = %CategoryOption
@onready var terrain_list: ItemList = %TerrainList

# OPR Army Integration
@onready var import_opr_btn: Button = %ImportOPRArmy
var opr_army_manager: OPRArmyManager
var opr_import_dialog: OPRImportDialog
var opr_stats_tooltip: OPRStatsTooltip
var _hovered_model: Node3D = null

# WGS (Wargaming Simulator) Integration
@onready var import_wgs_btn: Button = %ImportWGS
var wgs_game_manager: WGSGameManager
var wgs_import_dialog: WGSImportDialog

# TTS Import state
var _tts_json_path: String = ""
var _tts_models_dir: String = ""
var _tts_import_mode: String = "local"  # "local" or "online"

const INCHES_TO_FEET: float = 1.0 / 12.0
const CM_TO_FEET: float = 1.0 / 30.48


func _ready() -> void:
	print("OpenTTS Prototype v0.2 - Initializing...")

	# Connect UI buttons
	load_model_btn.pressed.connect(_on_load_model)
	model_file_dialog.file_selected.connect(_on_model_file_selected)
	clear_all_btn.pressed.connect(_on_clear_all)

	# Connect TTS Import UI
	import_tts_btn.pressed.connect(_on_import_tts)
	import_tts_online_btn.pressed.connect(_on_import_tts_online)
	tts_json_dialog.file_selected.connect(_on_tts_json_selected)
	tts_models_dialog.dir_selected.connect(_on_tts_models_dir_selected)
	tts_images_dialog.dir_selected.connect(_on_tts_images_dir_selected)
	object_manager.tts_online_import_completed.connect(_on_tts_online_import_completed)
	object_manager.tts_download_progress.connect(_on_tts_download_progress)

	# Connect table size UI
	table_size_option.item_selected.connect(_on_table_size_selected)
	apply_custom_btn.pressed.connect(_on_apply_custom_size)
	unit_option.item_selected.connect(_on_unit_changed)

	# Connect to object manager signals
	object_manager.dice_rolled.connect(_on_dice_rolled)
	object_manager.distance_changed.connect(_on_distance_changed)
	object_manager.measurement_finished.connect(_on_measurement_finished)
	object_manager.drag_ended.connect(_on_drag_ended)

	# Hide distance label initially
	distance_label.text = ""

	# Connect Dice Roller Plugin
	roll_button.pressed.connect(_on_roll_button_pressed)
	quick_roll_button.pressed.connect(_on_quick_roll_button_pressed)
	dice_roller_control.roll_finnished.connect(_on_roller_finished)
	dice_roller_control.roll_started.connect(_on_roller_started)
	dice_count_spinner.value_changed.connect(_on_dice_count_changed)

	# Initialize dice roller with default count
	_update_dice_set(int(dice_count_spinner.value))

	# Connect network UI
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)

	# Connect network manager signals
	network_manager.connected_to_server.connect(_on_network_connected)
	network_manager.connection_failed.connect(_on_network_failed)
	network_manager.server_disconnected.connect(_on_network_disconnected)
	network_manager.player_connected.connect(_on_player_joined)
	network_manager.player_disconnected.connect(_on_player_left)

	# Connect Save/Load UI
	save_game_btn.pressed.connect(_on_save_game)
	load_game_btn.pressed.connect(_on_load_game)
	save_game_dialog.file_selected.connect(_on_save_file_selected)
	load_game_dialog.file_selected.connect(_on_load_file_selected)
	save_manager.save_completed.connect(_on_save_completed)
	save_manager.load_completed.connect(_on_load_completed)
	save_manager.load_failed.connect(_on_load_failed)

	# Initialize SaveManager references
	save_manager.object_manager = object_manager
	save_manager.table = table

	# Connect Graphics Settings UI
	graphics_quality_option.item_selected.connect(_on_graphics_quality_changed)
	# Set initial selection based on current preset (map enum to UI index)
	# Enum: ULTRA=0, HIGH=1, MEDIUM=2, LOW=3 -> UI: Low=0, Medium=1, High=2, Ultra=3
	graphics_quality_option.selected = 3 - GraphicsSettings.current_preset

	# Connect Terrain Browser UI
	terrain_library.object_manager = object_manager
	terrain_browser_btn.pressed.connect(_on_terrain_browser_pressed)

	# Terrain browser buttons are in a Window, so we need to get them differently
	var spawn_btn = terrain_browser_popup.get_node("MarginContainer/VBox/ButtonRow/SpawnTerrainBtn")
	var close_btn = terrain_browser_popup.get_node("MarginContainer/VBox/ButtonRow/CloseTerrainBtn")

	terrain_category_option.item_selected.connect(_on_terrain_category_selected)
	terrain_list.item_activated.connect(_on_terrain_item_activated)
	spawn_btn.pressed.connect(_on_spawn_terrain_pressed)
	close_btn.pressed.connect(_on_close_terrain_browser)
	terrain_browser_popup.close_requested.connect(_on_close_terrain_browser)
	terrain_library.library_loaded.connect(_on_terrain_library_loaded)

	# Initialize table with default size (6x4 feet = 72x48 inches, landscape)
	# Long side (72") faces the viewer (X-axis), short side (48") is depth (Z-axis)
	table.setup_table(Vector2(6, 4))
	_adjust_camera_for_table_size(Vector2(6, 4))
	table_size_option.selected = 1  # Select 72x48 option

	# Initialize Lighting Controller
	lighting_controller = Node.new()
	lighting_controller.set_script(load("res://scripts/lighting_controller.gd"))
	add_child(lighting_controller)
	lighting_controller.initialize(directional_light, world_environment)

	# Initialize Lighting Panel UI
	lighting_panel = Window.new()
	lighting_panel.set_script(load("res://scripts/lighting_panel.gd"))
	get_tree().root.add_child(lighting_panel)
	lighting_panel.initialize(lighting_controller)
	lighting_panel.hide()  # Start hidden

	# Apply Kenney UI theme to HUD
	_apply_kenney_theme()
	ThemeManager.theme_changed.connect(_on_theme_changed)

	# Initialize OPR Army Manager
	opr_army_manager = OPRArmyManager.new()
	opr_army_manager.object_manager = object_manager
	opr_army_manager.table = table
	add_child(opr_army_manager)

	# Initialize OPR Import Dialog
	opr_import_dialog = OPRImportDialog.new()
	get_tree().root.add_child(opr_import_dialog)
	opr_import_dialog.army_imported.connect(_on_opr_army_imported)
	opr_import_dialog.hide()

	# Initialize OPR Stats Tooltip
	var tooltip_scene = load("res://scenes/opr_stats_tooltip.tscn")
	opr_stats_tooltip = tooltip_scene.instantiate()
	opr_stats_tooltip.army_manager = opr_army_manager
	$UI.add_child(opr_stats_tooltip)

	# Connect OPR import button
	import_opr_btn.pressed.connect(_on_import_opr_army)

	# Initialize WGS Game Manager
	wgs_game_manager = WGSGameManager.new()
	wgs_game_manager.object_manager = object_manager
	add_child(wgs_game_manager)

	# Initialize WGS Import Dialog
	wgs_import_dialog = WGSImportDialog.new()
	get_tree().root.add_child(wgs_import_dialog)
	wgs_import_dialog.game_imported.connect(_on_wgs_game_imported)
	wgs_import_dialog.hide()

	# Connect WGS import button (if it exists in UI)
	if import_wgs_btn:
		import_wgs_btn.pressed.connect(_on_import_wgs_game)

	# Initialize and play Tron intro
	_start_tron_intro()

	print("OpenTTS ready!")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		# Handle key release for continuous actions
		if not event.pressed:
			# Stop group rotation when R or Shift is released
			if event.keycode == KEY_R or event.keycode == KEY_SHIFT:
				_is_group_rotating = false
			return

		# Get cursor position on table for all operations
		var cursor_pos = object_manager.get_cursor_table_position()

		# Arrangement keys (1-9) - arrange selected in N rows at cursor
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var rows = event.keycode - KEY_0
			object_manager.arrange_selected_in_rows(rows, cursor_pos)
			get_viewport().set_input_as_handled()
		# Arrow formation (Shift+A) at cursor
		elif event.keycode == KEY_A and event.shift_pressed and not event.ctrl_pressed:
			object_manager.arrange_selected_arrow(cursor_pos)
			get_viewport().set_input_as_handled()
		# Copy to clipboard (Ctrl+C)
		elif event.keycode == KEY_C and event.ctrl_pressed:
			object_manager.copy_to_clipboard()
			get_viewport().set_input_as_handled()
		# Paste from clipboard at cursor (Ctrl+V)
		elif event.keycode == KEY_V and event.ctrl_pressed:
			object_manager.paste_from_clipboard(cursor_pos)
			get_viewport().set_input_as_handled()
		# Duplicate (Ctrl+D) - copy + paste immediately
		elif event.keycode == KEY_D and event.ctrl_pressed:
			object_manager.copy_to_clipboard()
			object_manager.paste_from_clipboard(cursor_pos)
			get_viewport().set_input_as_handled()
		# Lock/Unlock selected objects (L key)
		elif event.keycode == KEY_L and not event.ctrl_pressed:
			object_manager.toggle_lock_selected()
			get_viewport().set_input_as_handled()
		# Rotate selected group around first object (Shift+R) - continuous rotation
		elif event.keycode == KEY_R and event.shift_pressed:
			_is_group_rotating = true
			get_viewport().set_input_as_handled()
		# Lighting Presets (F1-F5)
		elif event.keycode == KEY_F1:
			lighting_controller.apply_preset("Default")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F2:
			lighting_controller.apply_preset("Warm Sunset")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F3:
			lighting_controller.apply_preset("Bright Studio")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F4:
			lighting_controller.apply_preset("Dramatic")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F5:
			lighting_controller.apply_preset("Cool Overcast")
			get_viewport().set_input_as_handled()
		# Print current lighting settings (F6)
		elif event.keycode == KEY_F6:
			lighting_controller.print_current_settings()
			get_viewport().set_input_as_handled()
		# Toggle Lighting Panel (F7)
		elif event.keycode == KEY_F7:
			if lighting_panel.visible:
				lighting_panel.hide()
			else:
				lighting_panel.show()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# Handle continuous group rotation (Shift+R held)
	if _is_group_rotating:
		var rotation_amount = GROUP_ROTATION_SPEED * delta
		object_manager.rotate_selected_group(rotation_amount)

	# Update performance label
	var fps = Engine.get_frames_per_second()
	var object_count = object_manager.get_child_count()

	# Color FPS based on performance
	var fps_color: Color
	if fps >= 55:
		fps_color = Color.GREEN
	elif fps >= 30:
		fps_color = Color.YELLOW
	else:
		fps_color = Color.RED

	performance_label.add_theme_color_override("font_color", fps_color)
	performance_label.text = "FPS: %d | Objects: %d" % [fps, object_count]

	# Handle OPR unit hover detection
	_update_opr_hover()


func _on_spawn_miniature() -> void:
	var spawn_pos = _get_random_table_position()
	object_manager.spawn_miniature(spawn_pos)


func _on_spawn_dice() -> void:
	var spawn_pos = _get_random_table_position()
	spawn_pos.y = 0.5  # Drop from reasonable height above table
	object_manager.spawn_dice(spawn_pos)


func _on_spawn_terrain() -> void:
	var spawn_pos = _get_random_table_position()
	object_manager.spawn_terrain(spawn_pos)


## Open file dialog to load a 3D model
func _on_load_model() -> void:
	model_file_dialog.popup_centered()


## Handle selected model file
func _on_model_file_selected(path: String) -> void:
	print("Loading model: %s" % path)
	var spawn_pos = _get_random_table_position()
	var model = object_manager.spawn_custom_model(path, spawn_pos)
	if model:
		print("Model loaded successfully!")
	else:
		push_error("Failed to load model: %s" % path)


## Performance test: Spawn 200 miniatures in a grid
func _on_spawn_200() -> void:
	print("=== PERFORMANCE TEST: Spawning 200 miniatures ===")
	var start_time = Time.get_ticks_msec()

	# Clear existing objects first
	object_manager.clear_all_objects()

	# Calculate grid layout (20 columns x 10 rows = 200)
	var cols = 20
	var rows = 10

	# Table size in meters
	var size_meters = table.table_size * 0.3048  # FEET_TO_METERS
	var margin = 0.05  # 5cm margin from edges

	# Calculate spacing
	var usable_width = size_meters.x - (margin * 2)
	var usable_depth = size_meters.y - (margin * 2)
	var spacing_x = usable_width / (cols - 1)
	var spacing_z = usable_depth / (rows - 1)

	# Start position (top-left corner)
	var start_x = -size_meters.x / 2 + margin
	var start_z = -size_meters.y / 2 + margin

	# Spawn miniatures in grid
	var count = 0
	for row in range(rows):
		for col in range(cols):
			var pos = Vector3(
				start_x + col * spacing_x,
				0,
				start_z + row * spacing_z
			)
			object_manager.spawn_miniature(pos)
			count += 1

	var end_time = Time.get_ticks_msec()
	var spawn_duration = end_time - start_time

	print("Spawned %d miniatures in %d ms" % [count, spawn_duration])
	print("Grid: %dx%d, Spacing: %.3fm x %.3fm" % [cols, rows, spacing_x, spacing_z])
	print("=== Monitor FPS for performance test ===")


## Performance test: Spawn 500 miniatures
func _on_spawn_500() -> void:
	_spawn_grid(500, 25, 20)


## Performance test: Spawn 1000 miniatures
func _on_spawn_1000() -> void:
	_spawn_grid(1000, 40, 25)


## Performance test: Spawn 100 complex terrain objects
func _on_spawn_complex() -> void:
	print("=== PERFORMANCE TEST: Spawning 100 complex terrain objects ===")
	var start_time = Time.get_ticks_msec()

	object_manager.clear_all_objects()

	var cols = 10
	var rows = 10
	var size_meters = table.table_size * 0.3048
	var margin = 0.1

	var usable_width = size_meters.x - (margin * 2)
	var usable_depth = size_meters.y - (margin * 2)
	var spacing_x = usable_width / (cols - 1)
	var spacing_z = usable_depth / (rows - 1)

	var start_x = -size_meters.x / 2 + margin
	var start_z = -size_meters.y / 2 + margin

	var count = 0
	for row in range(rows):
		for col in range(cols):
			var pos = Vector3(
				start_x + col * spacing_x,
				0,
				start_z + row * spacing_z
			)
			object_manager.spawn_terrain(pos)
			count += 1

	var end_time = Time.get_ticks_msec()
	print("Spawned %d terrain objects in %d ms" % [count, end_time - start_time])


## Helper function to spawn miniatures in a grid
func _spawn_grid(total: int, cols: int, rows: int) -> void:
	print("=== PERFORMANCE TEST: Spawning %d miniatures ===" % total)
	var start_time = Time.get_ticks_msec()

	object_manager.clear_all_objects()

	var size_meters = table.table_size * 0.3048
	var margin = 0.03  # Smaller margin for more objects

	var usable_width = size_meters.x - (margin * 2)
	var usable_depth = size_meters.y - (margin * 2)
	var spacing_x = usable_width / (cols - 1)
	var spacing_z = usable_depth / (rows - 1)

	var start_x = -size_meters.x / 2 + margin
	var start_z = -size_meters.y / 2 + margin

	var count = 0
	for row in range(rows):
		for col in range(cols):
			if count >= total:
				break
			var pos = Vector3(
				start_x + col * spacing_x,
				0,
				start_z + row * spacing_z
			)
			object_manager.spawn_miniature(pos)
			count += 1
		if count >= total:
			break

	var end_time = Time.get_ticks_msec()
	print("Spawned %d miniatures in %d ms" % [count, end_time - start_time])
	print("=== Monitor FPS for performance test ===")


func _on_clear_all() -> void:
	object_manager.clear_all_objects()
	dice_result_label.text = ""


func _on_dice_rolled(total: int, results: Array) -> void:
	var result_text = "Dice: %s = %d" % [str(results), total]
	dice_result_label.text = result_text

	# Fade out after 5 seconds
	var tween = create_tween()
	tween.tween_interval(5.0)
	tween.tween_property(dice_result_label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func():
		dice_result_label.text = ""
		dice_result_label.modulate.a = 1.0
	)


## Display distance while dragging or measuring
func _on_distance_changed(distance_inches: float, _from_pos: Vector3, _to_pos: Vector3) -> void:
	distance_label.text = "%.1f\"" % distance_inches


## Clear distance display after measurement finishes
func _on_measurement_finished(distance_inches: float) -> void:
	distance_label.text = "%.1f\"" % distance_inches
	# Fade out after 2 seconds
	var tween = create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(distance_label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func():
		distance_label.text = ""
		distance_label.modulate.a = 1.0
	)


## Clear distance display after drag ends
func _on_drag_ended() -> void:
	# Fade out after 1 second
	var tween = create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(distance_label, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func():
		distance_label.text = ""
		distance_label.modulate.a = 1.0
	)


## Dice Roller Plugin handlers
func _on_roll_button_pressed() -> void:
	dice_roller_control.roll()


func _on_quick_roll_button_pressed() -> void:
	dice_roller_control.quick_roll()


func _on_roller_started() -> void:
	roller_result_label.text = "Rolling..."


func _on_roller_finished(result: int) -> void:
	var per_dice = dice_roller_control.per_dice_result()
	roller_result_label.text = _format_dice_results(per_dice, result)


func _on_dice_count_changed(new_value: float) -> void:
	_update_dice_set(int(new_value))


## Update the dice set with the specified number of D6 dice
func _update_dice_set(count: int) -> void:
	var dice_set: Array[DiceDef] = []
	for i in range(count):
		var dice_def = DiceDef.new()
		dice_def.name = "D6_%d" % (i + 1)
		dice_def.color = Color.WHITE
		dice_def.shape = DiceShape.new("D6")
		dice_set.append(dice_def)

	dice_roller_control.dice_set = dice_set
	current_dice_label.text = "In box: %d D6" % count

	# Adjust roller size based on dice count
	var size_factor = sqrt(count / 6.0)
	dice_roller_control.roller_size = Vector3(
		max(12, 18 * size_factor),
		15,
		max(8, 12 * size_factor)
	)


## Format dice results as "x times 6, x times 5, ..." stacked vertically
func _format_dice_results(per_dice: Dictionary, _total: int) -> String:
	# Count occurrences of each face value
	var counts = {6: 0, 5: 0, 4: 0, 3: 0, 2: 0, 1: 0}
	for dice_name in per_dice:
		var value = per_dice[dice_name]
		if value in counts:
			counts[value] += 1

	# Build result string (no total, just face counts)
	var lines: Array[String] = []
	for face in [6, 5, 4, 3, 2, 1]:
		if counts[face] > 0:
			lines.append("%d× %d" % [counts[face], face])

	return "\n".join(lines)


func _get_random_table_position() -> Vector3:
	# Table size is in feet, convert to meters for positioning
	var size_meters = table.table_size * 0.3048  # FEET_TO_METERS
	var margin = 0.15  # Stay away from edges
	var x = randf_range(-size_meters.x / 2 + margin, size_meters.x / 2 - margin)
	var z = randf_range(-size_meters.y / 2 + margin, size_meters.y / 2 - margin)
	return Vector3(x, 0, z)  # Spawn at table surface (y=0)


## Handle table size preset selection
func _on_table_size_selected(index: int) -> void:
	match index:
		0:  # 48x48 inches (4x4 feet) - square
			custom_size_container.visible = false
			_set_table_size(Vector2(4, 4))
		1:  # 72x48 inches (6x4 feet) - landscape, standard wargaming
			custom_size_container.visible = false
			_set_table_size(Vector2(6, 4))
		2:  # Custom
			custom_size_container.visible = true


## Apply custom table size
func _on_apply_custom_size() -> void:
	var width = width_input.value
	var length = length_input.value

	# Convert to feet based on selected unit
	var size_feet: Vector2
	if unit_option.selected == 0:  # Inches
		size_feet = Vector2(width * INCHES_TO_FEET, length * INCHES_TO_FEET)
	else:  # Centimeters
		size_feet = Vector2(width * CM_TO_FEET, length * CM_TO_FEET)

	_set_table_size(size_feet)


## Update input fields when unit changes
func _on_unit_changed(index: int) -> void:
	if index == 0:  # Inches
		width_input.max_value = 240.0  # 20 feet max
		length_input.max_value = 240.0
		width_input.suffix = " in"
		length_input.suffix = " in"
	else:  # Centimeters
		width_input.max_value = 600.0  # ~20 feet max
		length_input.max_value = 600.0
		width_input.suffix = " cm"
		length_input.suffix = " cm"


## Set table to specific size and clear objects
func _set_table_size(size_feet: Vector2) -> void:
	# Clear existing objects
	object_manager.clear_all_objects()
	dice_result_label.text = ""

	# Rebuild table
	table.setup_table(size_feet)

	# Adjust camera view
	_adjust_camera_for_table_size(size_feet)

	print("Table resized to %.1fx%.1f feet" % [size_feet.x, size_feet.y])


## Adjust camera zoom based on table size
func _adjust_camera_for_table_size(size_feet: Vector2) -> void:
	# Calculate appropriate zoom based on table diagonal
	var diagonal = sqrt(size_feet.x * size_feet.x + size_feet.y * size_feet.y)
	var target_zoom = diagonal * 0.4  # Scale factor for good view

	# Reset camera view with appropriate zoom
	if camera_pivot.has_method("reset_view"):
		camera_pivot.reset_view()
	camera_pivot._current_zoom = clamp(target_zoom, camera_pivot.min_zoom, camera_pivot.max_zoom)
	camera_pivot._update_camera_transform()


## Network UI handlers
func _on_host_pressed() -> void:
	var error = network_manager.host_game()
	if error == OK:
		_update_network_ui(true, true)
		network_status_label.text = "Hosting on port 7777"
		network_status_label.add_theme_color_override("font_color", Color.GREEN)


func _on_join_pressed() -> void:
	var address = address_input.text.strip_edges()
	if address.is_empty():
		address = "localhost"

	var error = network_manager.join_game(address)
	if error == OK:
		network_status_label.text = "Connecting..."
		network_status_label.add_theme_color_override("font_color", Color.YELLOW)
		host_button.disabled = true
		join_button.disabled = true


func _on_disconnect_pressed() -> void:
	network_manager.disconnect_game()
	_update_network_ui(false, false)
	network_status_label.text = "Offline"
	network_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))


func _on_network_connected() -> void:
	_update_network_ui(true, false)
	network_status_label.text = "Connected (Peer %d)" % network_manager.get_my_peer_id()
	network_status_label.add_theme_color_override("font_color", Color.GREEN)


func _on_network_failed() -> void:
	_update_network_ui(false, false)
	network_status_label.text = "Connection failed!"
	network_status_label.add_theme_color_override("font_color", Color.RED)


func _on_network_disconnected() -> void:
	_update_network_ui(false, false)
	network_status_label.text = "Server disconnected"
	network_status_label.add_theme_color_override("font_color", Color.RED)


func _on_player_joined(peer_id: int) -> void:
	var player_count = network_manager.connected_peers.size()
	if network_manager.is_host:
		network_status_label.text = "Hosting (%d players)" % player_count
	print("Player %d joined! Total: %d" % [peer_id, player_count])


func _on_player_left(peer_id: int) -> void:
	var player_count = network_manager.connected_peers.size()
	if network_manager.is_host:
		network_status_label.text = "Hosting (%d players)" % player_count
	print("Player %d left! Total: %d" % [peer_id, player_count])


## Update network UI visibility based on connection state
func _update_network_ui(connected: bool, _is_host: bool) -> void:
	host_button.visible = !connected
	host_button.disabled = false
	join_button.visible = !connected
	join_button.disabled = false
	address_input.visible = !connected
	disconnect_button.visible = connected


## ============================================================================
## TTS (Tabletop Simulator) Import Functions
## ============================================================================

## Start TTS import workflow (local cache) - first select JSON file
func _on_import_tts() -> void:
	_tts_json_path = ""
	_tts_models_dir = ""
	_tts_import_mode = "local"
	tts_json_dialog.popup_centered()


## Start TTS online import - only need JSON file
func _on_import_tts_online() -> void:
	print("=== TTS Online Import Button Pressed ===")
	_tts_json_path = ""
	_tts_models_dir = ""
	_tts_import_mode = "online"
	print("Set import mode to: %s" % _tts_import_mode)
	tts_json_dialog.popup_centered()


## JSON file selected - branch based on import mode
func _on_tts_json_selected(path: String) -> void:
	_tts_json_path = path
	print("TTS Save selected: %s" % path.get_file())
	print("Import mode: %s" % _tts_import_mode)

	# Hide dialog
	tts_json_dialog.hide()

	if _tts_import_mode == "online":
		# Online mode: Start download and import immediately
		print("=== Starting TTS Online Import ===")
		print("JSON: %s" % _tts_json_path)
		import_tts_online_btn.disabled = true
		import_tts_online_btn.text = "Downloading..."
		object_manager.import_tts_save_online(_tts_json_path)
	else:
		# Local mode: Continue with directory selection
		var tts_cache_base = _detect_tts_cache_dir()
		if not tts_cache_base.is_empty():
			tts_models_dialog.current_dir = tts_cache_base.path_join("Models")
			tts_images_dialog.current_dir = tts_cache_base.path_join("Images")
		tts_models_dialog.popup_centered()


## Handle online import completion
func _on_tts_online_import_completed(success_count: int, fail_count: int) -> void:
	import_tts_online_btn.disabled = false
	import_tts_online_btn.text = "Import TTS (Online)..."
	print("TTS Online Import finished: %d imported, %d failed" % [success_count, fail_count])


## Handle download progress updates
func _on_tts_download_progress(current: int, total: int, _url: String) -> void:
	import_tts_online_btn.text = "Downloading %d/%d..." % [current, total]


## Models directory selected - next select Images directory
func _on_tts_models_dir_selected(path: String) -> void:
	_tts_models_dir = path
	print("TTS Models dir selected: %s" % path)

	# Hide previous dialog before opening next
	tts_models_dialog.hide()

	tts_images_dialog.popup_centered()


## Images directory selected - now perform the import
func _on_tts_images_dir_selected(path: String) -> void:
	var images_dir = path
	print("TTS Images dir selected: %s" % path)

	# Validate paths
	if _tts_json_path.is_empty() or _tts_models_dir.is_empty():
		push_error("TTS Import: Missing required paths")
		return

	# Perform import
	print("=== Starting TTS Import ===")
	print("JSON: %s" % _tts_json_path)
	print("Models: %s" % _tts_models_dir)
	print("Images: %s" % images_dir)

	var imported = object_manager.import_tts_save(_tts_json_path, _tts_models_dir, images_dir)
	print("Imported %d models from TTS save" % imported.size())


## Try to detect TTS cache directory based on OS
func _detect_tts_cache_dir() -> String:
	var os_name = OS.get_name()

	# Common TTS mod cache locations
	var possible_paths: Array[String] = []

	match os_name:
		"macOS":
			var home = OS.get_environment("HOME")
			possible_paths.append(home + "/Library/Tabletop Simulator/Mods")
		"Windows":
			var docs = OS.get_environment("USERPROFILE") + "/Documents"
			possible_paths.append(docs + "/My Games/Tabletop Simulator/Mods")
		"Linux":
			var home = OS.get_environment("HOME")
			possible_paths.append(home + "/.local/share/Tabletop Simulator/Mods")

	for path in possible_paths:
		if DirAccess.dir_exists_absolute(path):
			print("Auto-detected TTS cache: %s" % path)
			return path

	return ""


## ============================================================================
## Save / Load Functions
## ============================================================================

## Open save dialog
func _on_save_game() -> void:
	# Set default directory
	save_game_dialog.current_dir = SaveManager.get_default_save_dir()
	save_game_dialog.current_file = "game_%s.otts" % Time.get_datetime_string_from_system().replace(":", "-")
	save_game_dialog.popup_centered()


## Open load dialog
func _on_load_game() -> void:
	load_game_dialog.current_dir = SaveManager.get_default_save_dir()
	load_game_dialog.popup_centered()


## Save file selected
func _on_save_file_selected(path: String) -> void:
	# Ensure .otts extension
	if not path.ends_with(".otts"):
		path += ".otts"

	var error = save_manager.save_game(path)
	if error != OK:
		push_error("Failed to save game: %d" % error)


## Load file selected
func _on_load_file_selected(path: String) -> void:
	var error = save_manager.load_game(path)
	if error != OK:
		push_error("Failed to load game: %d" % error)


## Save completed callback
func _on_save_completed(path: String) -> void:
	print("Game saved successfully: %s" % path.get_file())
	# Could show a toast notification here


## Load completed callback
func _on_load_completed(object_count: int) -> void:
	print("Game loaded: %d objects" % object_count)

	# Sync to multiplayer clients if hosting
	if network_manager.is_host and network_manager.connected_peers.size() > 0:
		_sync_loaded_state_to_clients()


## Load failed callback
func _on_load_failed(error: String) -> void:
	push_error("Load failed: %s" % error)


## Sync loaded state to all connected clients
func _sync_loaded_state_to_clients() -> void:
	if not network_manager.is_host:
		return

	print("Syncing loaded state to %d clients..." % network_manager.connected_peers.size())

	# Get current state and broadcast to all clients
	var state = save_manager.serialize_game_state()
	_rpc_sync_game_state.rpc(state)


## RPC to sync game state to clients
@rpc("authority", "call_remote", "reliable")
func _rpc_sync_game_state(state: Dictionary) -> void:
	print("Received game state from host, loading...")

	# Clear current objects
	object_manager.clear_all_objects()

	# Deserialize table
	var table_data = state.get("table", {})
	var size = table_data.get("size_feet", [6, 4])
	if size is Array and size.size() >= 2:
		table.setup_table(Vector2(size[0], size[1]))
		_adjust_camera_for_table_size(Vector2(size[0], size[1]))

	# Deserialize objects (using save_manager helper, async for TTS downloads)
	var objects_data = state.get("objects", [])
	var loaded_count = await save_manager._deserialize_objects(objects_data)

	print("Synced %d objects from host" % loaded_count)


## ============================================================================
## Terrain Browser Functions
## ============================================================================

## Open terrain browser popup
func _on_terrain_browser_pressed() -> void:
	terrain_browser_popup.popup_centered()


## Close terrain browser popup
func _on_close_terrain_browser() -> void:
	terrain_browser_popup.hide()


## Called when terrain library finishes loading
func _on_terrain_library_loaded(categories: Array) -> void:
	terrain_category_option.clear()

	if categories.is_empty():
		terrain_category_option.add_item("No terrain found")
		return

	for category in categories:
		terrain_category_option.add_item(category)

	# Select first category and populate list
	terrain_category_option.select(0)
	_on_terrain_category_selected(0)


## Category selection changed
func _on_terrain_category_selected(index: int) -> void:
	terrain_list.clear()

	var category_name = terrain_category_option.get_item_text(index)
	var pieces = terrain_library.get_pieces_in_category(category_name)

	for piece in pieces:
		var display_name = piece.name
		if not piece.description.is_empty():
			display_name += " - " + piece.description.left(50)
		terrain_list.add_item(display_name)
		# Store piece ID in metadata
		terrain_list.set_item_metadata(terrain_list.item_count - 1, piece.id)


## Double-click on terrain item to spawn immediately
func _on_terrain_item_activated(index: int) -> void:
	_spawn_selected_terrain(index)


## Spawn button pressed
func _on_spawn_terrain_pressed() -> void:
	var selected = terrain_list.get_selected_items()
	if selected.is_empty():
		return
	_spawn_selected_terrain(selected[0])


## Spawn the selected terrain piece at cursor position
func _spawn_selected_terrain(index: int) -> void:
	var piece_id = terrain_list.get_item_metadata(index)
	var piece = terrain_library.get_piece_by_id(piece_id)

	if not piece:
		push_error("Terrain piece not found: %s" % piece_id)
		return

	var cursor_pos = object_manager.get_cursor_table_position()
	terrain_library.spawn_terrain_piece(piece, cursor_pos)

	# Keep browser open for placing multiple pieces
	print("Spawning terrain: %s at cursor" % piece.name)


## ============================================================================
## Kenney UI Theme System
## ============================================================================

## Apply Kenney UI theme to the HUD and dialogs
func _apply_kenney_theme() -> void:
	var current_theme = ThemeManager.get_current_theme()

	# Apply to HUD
	var hud = $UI/HUD
	hud.theme = current_theme

	# Apply to all file dialogs
	model_file_dialog.theme = current_theme
	tts_json_dialog.theme = current_theme
	tts_models_dialog.theme = current_theme
	tts_images_dialog.theme = current_theme
	save_game_dialog.theme = current_theme
	load_game_dialog.theme = current_theme
	terrain_browser_popup.theme = current_theme

	print("Applied Kenney UI theme: %s" % ThemeManager.get_current_theme_name())


## Handle theme changes from ThemeManager
func _on_theme_changed(new_theme: Theme) -> void:
	# Re-apply theme to all UI elements
	var hud = $UI/HUD
	hud.theme = new_theme

	# Update all dialogs
	model_file_dialog.theme = new_theme
	tts_json_dialog.theme = new_theme
	tts_models_dialog.theme = new_theme
	tts_images_dialog.theme = new_theme
	save_game_dialog.theme = new_theme
	load_game_dialog.theme = new_theme
	terrain_browser_popup.theme = new_theme

	print("Main scene theme updated to: %s" % ThemeManager.get_current_theme_name())


## ============================================================================
## OPR Army Forge Integration
## ============================================================================

## Open OPR import dialog
func _on_import_opr_army() -> void:
	opr_import_dialog.popup_centered()


## Handle army imported from dialog
func _on_opr_army_imported(army: OPRApiClient.OPRArmy, player_id: int) -> void:
	print("Importing army '%s' for Player %d" % [army.name, player_id])

	# Store army
	opr_army_manager.armies[player_id] = army

	# Spawn the army on tray (position determined by player ID)
	var spawned = opr_army_manager.spawn_army(army)
	print("Spawned %d models for army '%s' on Player %d's tray" % [spawned.size(), army.name, player_id])


## Update OPR unit hover detection
func _update_opr_hover() -> void:
	if not opr_stats_tooltip:
		return

	var camera = camera_pivot.get_node("Camera3D") as Camera3D
	if not camera:
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 100.0

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # Default layer
	var result = space_state.intersect_ray(query)

	if result and result.collider:
		var collider = result.collider
		# Check if this is an OPR unit
		if collider.is_in_group("opr_unit"):
			if _hovered_model != collider:
				_hovered_model = collider
				var unit = opr_army_manager.get_unit_for_model(collider)
				if unit:
					opr_stats_tooltip.show_unit(unit, collider)
		else:
			_clear_opr_hover()
	else:
		_clear_opr_hover()


## Clear OPR hover state
func _clear_opr_hover() -> void:
	if _hovered_model != null:
		_hovered_model = null
		if opr_stats_tooltip:
			opr_stats_tooltip.hide_tooltip()


## ============================================================================
## WGS (Wargaming Simulator) Integration
## ============================================================================

## Open WGS import dialog
func _on_import_wgs_game() -> void:
	wgs_import_dialog.popup_centered()


## Handle game imported from WGS dialog
func _on_wgs_game_imported(game: WGSClient.WGSGame) -> void:
	print("Importing WGS game '%s' with %d units" % [game.game_id, game.get_unit_count()])

	# Store the game
	wgs_game_manager.current_game = game

	# Set table size from WGS game
	var wgs_table_size = game.get_table_size_feet()
	print("Setting table size to %.0fx%.0f ft (from WGS)" % [wgs_table_size.x, wgs_table_size.y])
	table.setup_table(wgs_table_size)
	_adjust_camera_for_table_size(wgs_table_size)

	# Calculate offset: WGS uses top-left (0,0), OpenTTS uses center
	var table_meters = game.get_table_size_meters()
	var offset = Vector3(-table_meters.x / 2, 0, -table_meters.y / 2)

	# Spawn all units
	var spawned = wgs_game_manager.spawn_game(offset)
	print("Spawned %d models from WGS game '%s'" % [spawned.size(), game.game_id])


## ============================================================================
## Tron Intro Animation
## ============================================================================

## Start the Tron-style intro animation
func _start_tron_intro() -> void:
	# Create intro node
	tron_intro = TronIntro.new()
	tron_intro.name = "TronIntro"
	add_child(tron_intro)

	# Connect signals
	tron_intro.intro_finished.connect(_on_intro_finished)
	tron_intro.intro_skipped.connect(_on_intro_finished)

	# Hide UI during intro
	$UI.visible = false

	# Start the intro
	tron_intro.play_intro(self)


## Called when intro finishes or is skipped
func _on_intro_finished() -> void:
	_intro_finished = true

	# Show UI
	$UI.visible = true

	# Clean up intro after a delay
	if tron_intro:
		await get_tree().create_timer(1.0).timeout
		if is_instance_valid(tron_intro):
			tron_intro.queue_free()
			tron_intro = null

	print("Tron intro finished - welcome to OpenTTS!")


## ============================================================================
## Graphics Settings
## ============================================================================

## Handle graphics quality selection change
## UI order: Low=0, Medium=1, High=2, Ultra=3
## Enum order: ULTRA=0, HIGH=1, MEDIUM=2, LOW=3
func _on_graphics_quality_changed(index: int) -> void:
	var preset: GraphicsSettings.QualityPreset
	var preset_name: String

	match index:
		0:  # Low
			preset = GraphicsSettings.QualityPreset.LOW
			preset_name = "Low"
		1:  # Medium
			preset = GraphicsSettings.QualityPreset.MEDIUM
			preset_name = "Medium"
		2:  # High
			preset = GraphicsSettings.QualityPreset.HIGH
			preset_name = "High"
		3:  # Ultra
			preset = GraphicsSettings.QualityPreset.ULTRA
			preset_name = "Ultra"
		_:
			preset = GraphicsSettings.QualityPreset.MEDIUM
			preset_name = "Medium"

	GraphicsSettings.apply_preset(preset)
	print("Graphics quality set to: %s" % preset_name)
