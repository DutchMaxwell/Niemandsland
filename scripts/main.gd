extends Node3D
## Main scene controller for OpenTTS
##
## Handles initialization, UI management, and coordinates various subsystems
## including networking, terrain, lighting, graphics, and save/load functionality.
##
## @tutorial: See PROJECT_STATUS.md for complete feature documentation

# ==============================================================================
# CONSTANTS
# ==============================================================================

## Default table dimensions
const DEFAULT_TABLE_SIZE_FEET := Vector2(6, 4)  # 72x48 inches (landscape)
const TABLE_SIZE_4X4_FEET := Vector2(4, 4)      # 48x48 inches (square)

## UI indices for predefined table sizes
const TABLE_SIZE_INDEX_4X4 := 0
const TABLE_SIZE_INDEX_6X4 := 1
const TABLE_SIZE_INDEX_CUSTOM := 2

## Graphics quality mapping (UI index to enum)
const GRAPHICS_QUALITY_UI_MAX := 3  # Maps UI (Low=0, Medium=1, High=2, Ultra=3) to enum

## Group rotation
const GROUP_ROTATION_SPEED: float = 90.0  # degrees per second

## Unit conversion constants
const INCHES_TO_FEET: float = 1.0 / 12.0
const CM_TO_FEET: float = 1.0 / 30.48

# ==============================================================================
# NODE REFERENCES
# ==============================================================================

@onready var object_manager: Node3D = $ObjectManager
@onready var table: StaticBody3D = $Table
@onready var camera_pivot: Node3D = $CameraPivot
@onready var directional_light: DirectionalLight3D = $DirectionalLight3D
@onready var world_environment: WorldEnvironment = $WorldEnvironment

# Tron Intro
var tron_intro: TronIntro = null
var _intro_finished: bool = false

# Lighting Controller
var lighting_controller: Node = null
var lighting_panel: Window = null

# Group rotation state
var _is_group_rotating: bool = false

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
@onready var dice_roller_control: Control = %DiceRollerControl
@onready var roll_button: Button = %RollButton
@onready var quick_roll_button: Button = %QuickRollButton
@onready var roller_result_label: Label = %RollerResultLabel
@onready var dice_count_spinner: SpinBox = %DiceCountSpinner
@onready var current_dice_label: Label = %CurrentDiceLabel

# Network UI elements
@onready var network_manager: Node = %NetworkManager
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
@onready var save_manager: Node = %SaveManager
@onready var save_game_btn: Button = %SaveGameBtn
@onready var load_game_btn: Button = %LoadGameBtn
@onready var save_game_dialog: FileDialog = %SaveGameDialog
@onready var load_game_dialog: FileDialog = %LoadGameDialog

# Graphics Settings UI
@onready var graphics_quality_option: OptionButton = %GraphicsQualityOption

# Terrain Browser UI
@onready var terrain_library: Node = %TerrainLibrary
@onready var terrain_browser_btn: Button = %TerrainBrowser
@onready var terrain_browser_popup: Window = %TerrainBrowserPopup
@onready var terrain_category_option: OptionButton = %CategoryOption
@onready var terrain_list: ItemList = %TerrainList

# OPR Army Integration
@onready var import_opr_btn: Button = %ImportOPRArmy
var opr_army_manager: OPRArmyManager = null
var opr_import_dialog: OPRImportDialog = null
var opr_stats_tooltip: OPRStatsTooltip = null
var _hovered_model: Node3D = null

# WGS (Wargaming Simulator) Integration
@onready var import_wgs_btn: Button = %ImportWGS
var wgs_game_manager: WGSGameManager = null
var wgs_import_dialog: WGSImportDialog = null

# Map Layout Editor
@onready var map_layout_btn: Button = %MapLayoutBtn
var map_layout_editor: Control = null
var terrain_overlay: Node3D = null

# Atmospheric Effects
var atmospheric_clouds: Node3D = null

# Battle Simulator
var battle_simulator: BattleSimulator = null
var battle_simulator_ui: BattleSimulatorUI = null
var battle_sim_btn: Button = null

# Radial Menu
var radial_menu_controller: RadialMenuController = null
var coherency_visualizer: CoherencyVisualizer = null

# Deployment Zones UI (visibility only - editing is in Map Tool)
var deployment_zone_check: CheckBox = null
var deployment_mode_check: CheckBox = null
var is_deployment_mode: bool = false

# TTS Import state
var _tts_json_path: String = ""
var _tts_models_dir: String = ""
var _tts_import_mode: String = "local"  # "local" or "online"


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
	graphics_quality_option.selected = GRAPHICS_QUALITY_UI_MAX - GraphicsSettings.current_preset

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
	table.setup_table(DEFAULT_TABLE_SIZE_FEET)
	_adjust_camera_for_table_size(DEFAULT_TABLE_SIZE_FEET)
	table_size_option.selected = TABLE_SIZE_INDEX_6X4

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

	# Apply UI theme to HUD
	_apply_ui_theme()

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

	# Initialize Map Layout Editor
	var map_layout_scene = load("res://scenes/map_layout.tscn")
	map_layout_editor = map_layout_scene.instantiate()
	map_layout_editor.visible = false
	$UI.add_child(map_layout_editor)
	map_layout_editor.layout_closed.connect(_on_map_layout_closed)
	map_layout_editor.layout_updated.connect(_on_map_layout_updated)
	map_layout_editor.deployment_type_changed.connect(_on_deployment_type_changed)
	map_layout_btn.pressed.connect(_on_map_layout_pressed)

	# Initialize Terrain Overlay (on the 3D table)
	var overlay_script = load("res://scripts/terrain_overlay.gd")
	terrain_overlay = Node3D.new()
	terrain_overlay.set_script(overlay_script)
	terrain_overlay.name = "TerrainOverlay"
	terrain_overlay.visible = true  # Ensure it's visible
	table.add_child(terrain_overlay)
	print("TerrainOverlay initialized and added to table")

	# Give object_manager reference to terrain_overlay for terrain hints
	object_manager.terrain_overlay = terrain_overlay

	# Connect object_manager signals for deployment checking
	object_manager.drag_ended.connect(_on_unit_moved)

	# Initialize Atmospheric Clouds (RTS-style drifting clouds at high zoom)
	_init_atmospheric_clouds()

	# Initialize Deployment Zones UI
	_init_deployment_zones_ui()

	# Initialize Scout/Ambush Panel
	_init_scout_ambush_panel()

	# Initialize Battle Simulator
	_init_battle_simulator()

	# Initialize Radial Menu
	_init_radial_menu()

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
		TABLE_SIZE_INDEX_4X4:  # 48x48 inches (4x4 feet) - square
			custom_size_container.visible = false
			_set_table_size(TABLE_SIZE_4X4_FEET)
		TABLE_SIZE_INDEX_6X4:  # 72x48 inches (6x4 feet) - landscape, standard wargaming
			custom_size_container.visible = false
			_set_table_size(DEFAULT_TABLE_SIZE_FEET)
		TABLE_SIZE_INDEX_CUSTOM:  # Custom
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

	# Update terrain overlay with new table size (if it exists and has terrain data)
	# Note: Map Layout Editor clears terrain when table size changes (see set_table_size)
	if terrain_overlay and map_layout_editor and map_layout_editor.has_method("get_current_layout"):
		var layout_data = map_layout_editor.get_current_layout()
		if layout_data and not layout_data.grid_cells.is_empty():
			terrain_overlay.update_overlay(
				layout_data.grid_cells,
				size_feet,
				layout_data.rotation
			)

	# Adjust camera view
	_adjust_camera_for_table_size(size_feet)

	print("Table resized to %.1fx%.1f feet" % [size_feet.x, size_feet.y])


## Adjust camera zoom based on table size
func _adjust_camera_for_table_size(size_feet: Vector2) -> void:
	# Reset camera view first
	if camera_pivot.has_method("reset_view"):
		camera_pivot.reset_view()

	# Adjust zoom for table size using public API
	if camera_pivot.has_method("adjust_for_table_size"):
		camera_pivot.adjust_for_table_size(size_feet)


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
## UI Theme System
## ============================================================================

## Apply UI theme to the HUD and dialogs
func _apply_ui_theme() -> void:
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

	print("Applied UI theme: Glassmorphism")


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

	# Update battle simulator UI if open (so Start Battle button enables)
	if battle_simulator_ui:
		battle_simulator_ui.on_armies_loaded()


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


## ============================================================================
## Map Layout Editor
## ============================================================================

## Open Map Layout Editor
func _on_map_layout_pressed() -> void:
	if map_layout_editor:
		map_layout_editor.set_table_size(table.table_size)
		map_layout_editor.visible = true
		$UI/HUD.visible = false  # Hide main HUD while in layout mode


## Close Map Layout Editor
func _on_map_layout_closed() -> void:
	$UI/HUD.visible = true  # Show main HUD again


## Handle deployment type change from Map Tool
func _on_deployment_type_changed(deployment_type: int) -> void:
	if not terrain_overlay or not terrain_overlay.has_method("set_deployment_zones"):
		return

	# For custom zones, pass the zone data to terrain_overlay
	if deployment_type == 2 and map_layout_editor:  # CUSTOM
		var zone_data = map_layout_editor.get_custom_zone_data()
		if terrain_overlay.has_method("set_custom_zones"):
			terrain_overlay.set_custom_zones(zone_data.player1_world, zone_data.player2_world)
			print("Custom zones set: P1=%d vertices, P2=%d vertices" % [
				zone_data.player1_world.size(), zone_data.player2_world.size()
			])

	terrain_overlay.set_deployment_zones(deployment_type)
	print("Deployment zone type set from Map Tool: %d" % deployment_type)

	# Auto-show deployment zones when a type is selected
	if deployment_type > 0:
		terrain_overlay.set_deployment_zones_visible(true)
		if deployment_zone_check:
			deployment_zone_check.button_pressed = true


## Update terrain overlay when map layout changes
func _on_map_layout_updated(grid_cells: Dictionary, table_size: Vector2, grid_rotation: float) -> void:
	# This may be called during initialization before terrain_overlay exists
	if not terrain_overlay:
		return  # Silently ignore - will be updated when user closes map layout

	if not terrain_overlay.has_method("update_overlay"):
		push_warning("TerrainOverlay missing update_overlay method")
		return

	terrain_overlay.update_overlay(grid_cells, table_size, grid_rotation)


## ============================================================================
## Deployment Zones (Visibility Only - Editing is in Map Tool)
## ============================================================================

## Initialize deployment zones UI (simplified - only visibility toggle)
## NOTE: Deployment zone type selection and custom zone editing is now in Map Tool.
## This ensures a single point of truth for deployment zone configuration.
func _init_deployment_zones_ui() -> void:
	# Get the left panel VBox to add UI elements
	var left_panel_vbox = $UI/HUD/LeftPanelScroll/LeftPanelVBox
	if not left_panel_vbox:
		push_error("Could not find LeftPanelVBox for deployment zones UI")
		return

	# Create a VBoxContainer for deployment zones
	var deployment_panel = VBoxContainer.new()
	deployment_panel.name = "DeploymentPanel"
	left_panel_vbox.add_child(deployment_panel)

	# Add label with Glassmorphism styling
	var label = Label.new()
	label.text = "Deployment Zones:"
	label.add_theme_color_override("font_color", Color(0.85, 0.87, 0.92, 1.0))
	deployment_panel.add_child(label)

	# Info label explaining where to edit
	var info_label = Label.new()
	info_label.text = "(Configure in Map Tool)"
	info_label.add_theme_font_size_override("font_size", 11)
	info_label.add_theme_color_override("font_color", Color(0.6, 0.63, 0.7, 1.0))
	deployment_panel.add_child(info_label)

	# Create CheckBox for visibility toggle
	deployment_zone_check = CheckBox.new()
	deployment_zone_check.text = "Show Deployment Zones"
	deployment_zone_check.button_pressed = false
	deployment_zone_check.add_theme_color_override("font_color", Color(0.85, 0.87, 0.92, 1.0))
	deployment_zone_check.toggled.connect(_on_deployment_zones_visibility_toggled)
	deployment_panel.add_child(deployment_zone_check)

	# Create CheckBox for Deployment Mode (check units in zones)
	deployment_mode_check = CheckBox.new()
	deployment_mode_check.text = "Check Unit Placement"
	deployment_mode_check.button_pressed = false
	deployment_mode_check.add_theme_color_override("font_color", Color(0.85, 0.87, 0.92, 1.0))
	deployment_mode_check.toggled.connect(_on_deployment_mode_toggled)
	deployment_panel.add_child(deployment_mode_check)


## Handle deployment zone visibility toggle
func _on_deployment_zones_visibility_toggled(show_zones: bool) -> void:
	if not terrain_overlay or not terrain_overlay.has_method("set_deployment_zones_visible"):
		return

	terrain_overlay.set_deployment_zones_visible(show_zones)
	print("Deployment zones visibility: %s" % ("visible" if show_zones else "hidden"))


## Handle deployment mode toggle
func _on_deployment_mode_toggled(is_active: bool) -> void:
	is_deployment_mode = is_active
	_check_all_units_deployment()
	print("Deployment mode: %s" % ("active" if is_active else "inactive"))


## ============================================================================
## Atmospheric Effects
## ============================================================================

## Initialize atmospheric clouds that appear at high zoom levels
## Creates RTS-style drifting cloud layers (like Victoria, EU4, etc.)
func _init_atmospheric_clouds() -> void:
	var clouds_script = load("res://scripts/atmospheric_clouds.gd")
	if not clouds_script:
		push_warning("Could not load atmospheric_clouds.gd - clouds disabled")
		return

	atmospheric_clouds = Node3D.new()
	atmospheric_clouds.set_script(clouds_script)
	atmospheric_clouds.name = "AtmosphericClouds"

	# Add to root so clouds are above everything
	add_child(atmospheric_clouds)

	# Give reference to camera controller for zoom-based visibility
	if camera_pivot:
		atmospheric_clouds.camera_controller = camera_pivot

	print("Atmospheric clouds initialized")


## Initialize Scout/Ambush Panel UI
func _init_scout_ambush_panel() -> void:
	# Get the left panel VBox to add UI elements
	var left_panel_vbox = $UI/HUD/LeftPanelScroll/LeftPanelVBox
	if not left_panel_vbox:
		push_error("Could not find LeftPanelVBox for scout/ambush panel")
		return

	# Create a VBoxContainer for scout/ambush units
	var scout_panel = VBoxContainer.new()
	scout_panel.name = "ScoutAmbushPanel"
	left_panel_vbox.add_child(scout_panel)

	# Add label
	var label = Label.new()
	label.text = "Scout/Ambush Units:"
	label.add_theme_color_override("font_color", Color.CYAN)
	scout_panel.add_child(label)

	# Create a ScrollContainer for the unit list
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(180, 100)
	scout_panel.add_child(scroll)

	# Create ItemList for units
	var unit_list = ItemList.new()
	unit_list.name = "ScoutAmbushList"
	unit_list.custom_minimum_size = Vector2(180, 100)
	scroll.add_child(unit_list)

	# Add example text (will be populated when units are added)
	unit_list.add_item("(No scout/ambush units)")

	# Add info label
	var info_label = Label.new()
	info_label.text = "Units with Scout or Ambush\ndeploy outside normal zones"
	info_label.add_theme_font_size_override("font_size", 10)
	info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	scout_panel.add_child(info_label)


## Handle unit movement (re-check deployment and coherency)
func _on_unit_moved() -> void:
	if is_deployment_mode:
		_check_all_units_deployment()

	# Auto-check coherency for any selected units after movement
	_check_coherency_for_selected_units()


## Check coherency for all currently selected units
func _check_coherency_for_selected_units() -> void:
	if not coherency_visualizer or not object_manager:
		return

	# Get selected objects
	var selected = object_manager.get_selected_objects()
	if selected.is_empty():
		return

	# Find unique game units from selection
	var checked_units: Array = []
	for obj in selected:
		if not obj.has_meta("game_unit"):
			continue
		var game_unit = obj.get_meta("game_unit") as GameUnit
		if game_unit and game_unit not in checked_units:
			checked_units.append(game_unit)
			# Show coherency visualization for this unit
			coherency_visualizer.show_coherency(game_unit)


## Check all units for deployment zone compliance
func _check_all_units_deployment() -> void:
	if not terrain_overlay or not terrain_overlay.has_method("is_position_in_deployment_zone"):
		return

	# Get all miniatures
	var miniatures = get_tree().get_nodes_in_group("miniature")

	for miniature in miniatures:
		if not is_instance_valid(miniature):
			continue

		# Check if miniature has a deployment warning label
		var warning_label = miniature.get_node_or_null("DeploymentWarning")

		if is_deployment_mode:
			# Check if unit is in a deployment zone
			var zone_info = terrain_overlay.is_position_in_deployment_zone(miniature.global_position)

			if not zone_info["in_zone"]:
				# Unit is outside deployment zone - show warning
				if not warning_label:
					warning_label = Label3D.new()
					warning_label.name = "DeploymentWarning"
					warning_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
					warning_label.no_depth_test = true
					warning_label.font_size = 64
					warning_label.text = "⚠️"
					warning_label.modulate = Color.ORANGE
					warning_label.position = Vector3(0, 0.1, 0)  # 10cm above unit
					miniature.add_child(warning_label)
				warning_label.visible = true
			else:
				# Unit is in deployment zone - hide warning
				if warning_label:
					warning_label.visible = false
		else:
			# Deployment mode inactive - hide all warnings
			if warning_label:
				warning_label.visible = false


## ============================================================================
## Battle Simulator (AI vs AI)
## ============================================================================

## Initialize Battle Simulator
func _init_battle_simulator() -> void:
	# Get the left panel VBox to add UI elements
	var left_panel_vbox = $UI/HUD/LeftPanelScroll/LeftPanelVBox
	if not left_panel_vbox:
		push_error("Could not find LeftPanelVBox for battle simulator button")
		return

	# Create a separator
	var separator = HSeparator.new()
	left_panel_vbox.add_child(separator)

	# Create the battle simulator button
	battle_sim_btn = Button.new()
	battle_sim_btn.text = "Battle Simulator"
	battle_sim_btn.tooltip_text = "AI vs AI step-by-step battle simulation"
	battle_sim_btn.pressed.connect(_on_battle_simulator_pressed)
	left_panel_vbox.add_child(battle_sim_btn)

	# Create the Battle Simulator instance
	battle_simulator = BattleSimulator.new()
	battle_simulator.name = "BattleSimulator"
	add_child(battle_simulator)
	battle_simulator.initialize(opr_army_manager)

	# Create the Battle Simulator UI
	battle_simulator_ui = BattleSimulatorUI.new()
	battle_simulator_ui.name = "BattleSimulatorUI"
	battle_simulator_ui.visible = false
	$UI.add_child(battle_simulator_ui)
	battle_simulator_ui.initialize(battle_simulator, opr_army_manager)

	# Connect UI signals
	battle_simulator_ui.army_load_requested.connect(_on_battle_sim_army_load_requested)
	battle_simulator_ui.close_requested.connect(_on_battle_sim_close)

	# Connect simulator signals for visual feedback
	battle_simulator.unit_highlighted.connect(_on_battle_sim_unit_highlighted)
	battle_simulator.highlight_cleared.connect(_on_battle_sim_highlight_cleared)


## Open Battle Simulator UI
func _on_battle_simulator_pressed() -> void:
	if battle_simulator_ui:
		$UI/HUD.visible = false
		battle_simulator_ui.show_ui()


## Close Battle Simulator UI
func _on_battle_sim_close() -> void:
	if battle_simulator_ui:
		battle_simulator_ui.hide_ui()
		$UI/HUD.visible = true


## Handle army load request from battle simulator
func _on_battle_sim_army_load_requested(player: int) -> void:
	# Store which player we're loading for
	battle_simulator.set_meta("loading_for_player", player)

	# Pre-select the correct player in the import dialog
	opr_import_dialog.set_player(player)

	# Use the existing OPR import dialog
	opr_import_dialog.popup_centered()

	# Temporarily reconnect the signal to handle battle sim import
	if opr_import_dialog.army_imported.is_connected(_on_opr_army_imported):
		opr_import_dialog.army_imported.disconnect(_on_opr_army_imported)
	opr_import_dialog.army_imported.connect(_on_battle_sim_army_imported, CONNECT_ONE_SHOT)


## Handle army imported for battle simulator
func _on_battle_sim_army_imported(army: OPRApiClient.OPRArmy, _player_id: int) -> void:
	# Get the player we're loading for
	var target_player = battle_simulator.get_meta("loading_for_player", 1)

	print("Battle Sim: Importing army '%s' for Player %d" % [army.name, target_player])

	# Store army
	opr_army_manager.armies[target_player] = army

	# Spawn the army on tray
	var spawned = opr_army_manager.spawn_army(army)
	print("Battle Sim: Spawned %d models for army '%s'" % [spawned.size(), army.name])

	# Update battle simulator UI
	if battle_simulator_ui:
		battle_simulator_ui.on_armies_loaded()

	# Reconnect normal import handler
	if not opr_import_dialog.army_imported.is_connected(_on_opr_army_imported):
		opr_import_dialog.army_imported.connect(_on_opr_army_imported)


## Highlight a unit during battle simulation
func _on_battle_sim_unit_highlighted(unit: GameUnit, highlight_type: String) -> void:
	if not unit:
		return

	var color: Color
	match highlight_type:
		"active":
			color = Color(0.2, 1.0, 0.2, 0.5)  # Green for active unit
		"target":
			color = Color(1.0, 0.2, 0.2, 0.5)  # Red for target
		_:
			color = Color(1.0, 1.0, 0.2, 0.5)  # Yellow default

	# Highlight all models in the unit
	for model in unit.models:
		if model.is_alive and model.node:
			_apply_highlight_to_model(model.node, color)


## Clear all highlights
func _on_battle_sim_highlight_cleared() -> void:
	# Clear highlights from all models
	for player_id in [1, 2]:
		var units = opr_army_manager.get_game_units_for_player(player_id)
		for unit in units:
			for model in unit.models:
				if model.node:
					_clear_highlight_from_model(model.node)


## Apply highlight effect to a model
func _apply_highlight_to_model(model: Node3D, color: Color) -> void:
	# Find or create highlight ring
	var highlight = model.get_node_or_null("BattleHighlight")
	if not highlight:
		highlight = MeshInstance3D.new()
		highlight.name = "BattleHighlight"

		var torus_mesh = TorusMesh.new()
		torus_mesh.inner_radius = 0.015
		torus_mesh.outer_radius = 0.025
		highlight.mesh = torus_mesh
		highlight.position.y = 0.005

		model.add_child(highlight)

	# Set color
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	highlight.material_override = material
	highlight.visible = true


## Clear highlight effect from a model
func _clear_highlight_from_model(model: Node3D) -> void:
	var highlight = model.get_node_or_null("BattleHighlight")
	if highlight:
		highlight.visible = false


## ============================================================================
## Radial Menu
## ============================================================================

func _init_radial_menu() -> void:
	radial_menu_controller = RadialMenuController.new()
	radial_menu_controller.name = "RadialMenuController"
	add_child(radial_menu_controller)
	radial_menu_controller.initialize(object_manager, opr_army_manager)

	# Pass stats tooltip reference for displaying unit stats
	radial_menu_controller.stats_tooltip = opr_stats_tooltip

	# Create and pass coherency visualizer
	coherency_visualizer = CoherencyVisualizer.new()
	coherency_visualizer.name = "CoherencyVisualizer"
	add_child(coherency_visualizer)
	radial_menu_controller.coherency_visualizer = coherency_visualizer

	# Connect object manager's right-click signal to open the menu
	object_manager.context_menu_requested.connect(_on_context_menu_requested)


## Handle context menu request from object manager
func _on_context_menu_requested(screen_pos: Vector2, selected_objects: Array) -> void:
	if radial_menu_controller:
		radial_menu_controller.open_menu(screen_pos, selected_objects)


## Check if radial menu is currently open
func is_radial_menu_open() -> bool:
	return radial_menu_controller and radial_menu_controller.is_menu_open()
