extends Node3D
## Main scene controller for Niemandsland
##
## Handles initialization, UI management, and coordinates various subsystems
## including networking, terrain, lighting, graphics, and save/load functionality.
##
## @tutorial: See PROJECT_STATUS.md for complete feature documentation

# ==============================================================================
# PRELOADS
# ==============================================================================
const UnitBoundaryVisualizerScript = preload("res://scripts/unit_boundary_visualizer.gd")

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

## Graphics quality mapping (UI index matches enum directly)
## UI: Performance=0, Low=1, Medium=2, High=3, Ultra=4

## Group rotation
const GROUP_ROTATION_SPEED: float = 90.0  # degrees per second

## Unit conversion constants
const FEET_TO_METERS: float = 0.3048
const INCHES_TO_FEET: float = 1.0 / 12.0
const CM_TO_FEET: float = 1.0 / 30.48

## Debug mode (set to false for production builds)
const DEBUG_MODE: bool = false

# ==============================================================================
# NODE REFERENCES
# ==============================================================================

@onready var object_manager: Node3D = $ObjectManager
## Undo/redo history for table actions (created in _init_radial_menu).
var undo_manager: UndoManager = null
@onready var table: StaticBody3D = $Table
@onready var camera_pivot: Node3D = $CameraPivot
@onready var directional_light: DirectionalLight3D = $DirectionalLight3D
@onready var fill_light: DirectionalLight3D = $FillLight
@onready var world_environment: WorldEnvironment = $WorldEnvironment

# Cinematic Intro
var cinematic_intro: CinematicIntro = null
## Opaque black backdrop shown behind the table-size chooser, so selection happens on
## black and dissolves cleanly into the intro (freed once the intro's own black is up).
var _prompt_overlay: CanvasLayer = null

# Lighting Controller
var lighting_controller: Node = null
var lighting_panel: Window = null
var atmosphere_controller: AtmosphereController = null

# Group rotation state
var _is_group_rotating: bool = false
# Guard to prevent re-broadcasting remote dice rolls (avoids ping-pong loop)
var _is_showing_remote_roll: bool = false
var _group_rotation_broadcast_timer: float = 0.0
const GROUP_ROTATION_BROADCAST_INTERVAL: float = 0.1  # 10 Hz

@onready var dice_result_label: Label = $UI/HUD/DiceResult
@onready var distance_label: Label = $UI/HUD/DistanceLabel
@onready var clear_all_btn: Button = %ClearAll
@onready var sort_table_btn: Button = %SortTableBtn
@onready var next_round_btn: Button = %NextRoundBtn
@onready var settings_btn: Button = %SettingsBtn
@onready var performance_label: Label = %PerformanceLabel

# Hamburger menu
@onready var hamburger_button: Button = %HamburgerButton
@onready var left_panel_scroll: ScrollContainer = $UI/HUD/LeftPanelScroll

# Table size UI elements
@onready var table_size_option: OptionButton = %TableSizeOption
@onready var custom_size_container: VBoxContainer = %CustomSizeContainer
@onready var unit_option: OptionButton = %UnitOption
@onready var width_input: SpinBox = %WidthInput
@onready var length_input: SpinBox = %LengthInput
@onready var apply_custom_btn: Button = %ApplyCustomBtn

# Dice Roller Plugin UI
@onready var dice_roller_control: DiceTray = %DiceRollerControl
@onready var roll_button: Button = %RollButton
@onready var quick_roll_button: Button = %QuickRollButton
@onready var _dice_log_scroll: ScrollContainer = %DiceLogScroll
@onready var _dice_log_vbox: VBoxContainer = %DiceLogVBox
@onready var current_dice_label: Label = %CurrentDiceLabel
@onready var _dice_vbox: VBoxContainer = $UI/HUD/DiceRollerPanel/VBox

# Dice count selection (click-based; replaces the old SpinBox so keyboard focus
# never leaves the table and WASD always reaches the camera).
const MIN_DICE: int = 1
const MAX_DICE: int = 50
const DICE_PRESET_MAX: int = 10
const DEFAULT_DICE_COUNT: int = 6
const CURRENT_ROLL_ICON_SIZE: int = 26
const DICE_LOG_ICON_SIZE: int = 16
var _dice_count: int = DEFAULT_DICE_COUNT
var _dice_preset_buttons: Array[Button] = []
var _dice_count_value_label: Label = null
var _current_roll_column: VBoxContainer = null

# Network UI elements
@onready var network_manager: Node = %NetworkManager
@onready var network_status_label: Label = %StatusLabel
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var disconnect_button: Button = %DisconnectButton
@onready var address_input: LineEdit = %AddressInput

# Internet multiplayer
var internet_lobby: InternetLobby = null

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
var unit_card: UnitCard = null
var _hovered_model: Node3D = null

# WGS (Wargaming Simulator) Integration
@onready var import_wgs_btn: Button = %ImportWGS
var wgs_game_manager: WGSGameManager = null
var wgs_import_dialog: WGSImportDialog = null

# Map Layout Editor
@onready var map_layout_btn: Button = %MapLayoutBtn
var map_layout_editor: Control = null
var terrain_overlay: Node3D = null

# End Battle / Main Menu
@onready var end_battle_btn: Button = %EndBattleBtn
@onready var end_battle_confirm_dialog: ConfirmationDialog = %EndBattleConfirmDialog

# Reusable confirmation dialog for destructive table actions (Clear / Sort / Next Round)
var _action_confirm_dialog: ConfirmationDialog = null
var _pending_confirm_action: Callable = Callable()

# Overlay shown while an army's 3D models are downloaded from R2 (first time only).
var _cache_progress_panel: PanelContainer = null
var _cache_progress_label: Label = null
var _cache_progress_bar: ProgressBar = null
var _cache_progress_tween: Tween = null

# Atmospheric Effects
var atmospheric_clouds: Node3D = null

# Radial Menu
var radial_menu_controller: RadialMenuController = null
var coherency_visualizer: CoherencyVisualizer = null
var unit_boundary_visualizer: Node3D = null  # UnitBoundaryVisualizer

# Deployment Zones UI (visibility toggle only - editing is in Map Tool;
# unit-placement compliance is verified manually by the players)
var deployment_zone_check: CheckBox = null

# TTS Import state
var _tts_json_path: String = ""
var _tts_models_dir: String = ""
var _tts_import_mode: String = "local"  # "local" or "online"

# Player Presence System
var _remote_cursors: Dictionary = {}  # peer_id -> RemoteCursor node
var _player_avatars: Dictionary = {}  # peer_id -> PlayerAvatar node
var _cursor_broadcast_timer: float = 0.0
var _camera_broadcast_timer: float = 0.0
const CURSOR_BROADCAST_INTERVAL: float = 0.066  # ~15 Hz
const CAMERA_BROADCAST_INTERVAL: float = 0.2  # 5 Hz

## True while army batches are being sent — suppresses presence broadcasts
var _is_army_syncing: bool = false


func _ready() -> void:
	# Debanding dithers the final frame, smoothing the dark space gradient so it shows
	# no banding "segments".
	get_viewport().use_debanding = true

	# Connect hamburger menu toggle
	hamburger_button.pressed.connect(_on_hamburger_pressed)

	# AAA-style the slide-out game menu (under the hamburger): glassmorphism theme on its
	# buttons/labels + a glass panel background, matching the rest of the UI.
	if has_node("/root/ThemeManager"):
		left_panel_scroll.theme = get_node("/root/ThemeManager").get_current_theme()
	left_panel_scroll.add_theme_stylebox_override("panel", HudTokens.panel_style())

	# Connect End Battle button and confirmation dialog
	end_battle_btn.pressed.connect(_on_end_battle_pressed)
	end_battle_confirm_dialog.confirmed.connect(_on_end_battle_confirmed)
	if has_node("/root/ThemeManager"):
		end_battle_confirm_dialog.theme = get_node("/root/ThemeManager").get_current_theme()

	# Connect UI buttons
	load_model_btn.pressed.connect(_on_load_model)
	model_file_dialog.file_selected.connect(_on_model_file_selected)
	clear_all_btn.pressed.connect(_on_clear_all)
	sort_table_btn.pressed.connect(_on_sort_table)
	next_round_btn.pressed.connect(_on_next_round)
	settings_btn.pressed.connect(_toggle_settings_panel)
	_update_round_button()

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
	object_manager.distance_changed.connect(_on_distance_changed)
	object_manager.measurement_finished.connect(_on_measurement_finished)
	object_manager.drag_ended.connect(_on_drag_ended)
	object_manager.drag_updated.connect(_check_coherency_for_selected_units)
	object_manager.selection_changed.connect(_on_selection_changed_update_card)

	# Hide distance label initially
	distance_label.text = ""

	# Connect Dice Roller Plugin
	roll_button.pressed.connect(_on_roll_button_pressed)
	quick_roll_button.pressed.connect(_on_quick_roll_button_pressed)
	dice_roller_control.roll_finnished.connect(_on_roller_finished)
	dice_roller_control.roll_started.connect(_on_roller_started)

	# Build the click-based dice count selector and the success readout column,
	# then initialise the dice set with the default count.
	_build_dice_count_selector()
	_build_current_roll_column()
	_set_dice_count(DEFAULT_DICE_COUNT)

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
	network_manager.peer_version_validated.connect(_on_peer_version_validated)
	network_manager.version_rejected.connect(_on_version_rejected)

	# Connect game state sync signals (remote wounds, activation, markers, casts, delete)
	network_manager.remote_wounds_updated.connect(_on_remote_wounds_updated)
	network_manager.remote_activation_updated.connect(_on_remote_activation_updated)
	network_manager.remote_unit_marker_updated.connect(_on_remote_unit_marker_updated)
	network_manager.remote_model_marker_updated.connect(_on_remote_model_marker_updated)
	network_manager.remote_unit_marker_value_updated.connect(_on_remote_unit_marker_value_updated)
	network_manager.remote_model_marker_value_updated.connect(_on_remote_model_marker_value_updated)
	network_manager.remote_objective_owner_updated.connect(_on_remote_objective_owner_updated)
	network_manager.remote_token_defined.connect(_on_remote_token_defined)
	network_manager.remote_token_edited.connect(_on_remote_token_edited)
	network_manager.remote_casts_updated.connect(_on_remote_casts_updated)
	network_manager.remote_unit_deleted.connect(_on_remote_unit_deleted)
	network_manager.remote_round_advanced.connect(_on_remote_round_advanced)

	# Connect presence signals
	network_manager.remote_cursor_updated.connect(_on_remote_cursor_updated)
	network_manager.remote_camera_updated.connect(_on_remote_camera_updated)
	network_manager.remote_dice_rolled.connect(_on_remote_dice_rolled)
	network_manager.remote_table_settings_changed.connect(_on_remote_table_settings_changed)
	network_manager.remote_army_header_received.connect(_on_remote_army_header)
	network_manager.remote_army_unit_received.connect(_on_remote_army_unit)
	network_manager.remote_army_complete_received.connect(_on_remote_army_complete)
	network_manager.remote_tts_terrain_spawned.connect(_on_remote_tts_terrain_spawned)
	network_manager.remote_camera_position_updated.connect(_on_remote_camera_position_updated)

	# Initialize Internet Lobby for online multiplayer
	internet_lobby = InternetLobby.new()
	add_child(internet_lobby)
	internet_lobby.room_code_ready.connect(_on_internet_room_ready)
	internet_lobby.internet_connected.connect(_on_internet_connected)
	internet_lobby.internet_connection_failed.connect(_on_internet_failed)
	internet_lobby.internet_disconnected.connect(_on_internet_disconnected)
	internet_lobby.relay_connection_lost.connect(_on_relay_connection_lost)
	internet_lobby.relay_reconnecting.connect(_on_relay_reconnecting)
	internet_lobby.relay_reconnect_failed.connect(_on_relay_reconnect_failed)
	internet_lobby.host_paused.connect(_on_host_paused)
	internet_lobby.host_rejoined.connect(_on_host_rejoined)
	# Peer join/leave for internet relay is handled through the built-in
	# MultiplayerPeer.peer_connected signal (same path as ENet):
	# relay emits peer_connected → network_manager._on_peer_connected → _on_player_joined

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
	# Set initial selection based on current preset (UI index matches enum directly)
	graphics_quality_option.selected = GraphicsSettings.current_preset

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
	# Legacy TTS terrain browser: superseded by the map-editor prefab palette. Hidden
	# (no pre-loaded library pieces) but kept wired for ad-hoc TTS terrain imports.
	terrain_browser_btn.hide()
	# Removed from the in-game menu (no longer needed): direct 3D model load + TTS import.
	load_model_btn.hide()
	import_tts_btn.hide()
	import_tts_online_btn.hide()

	# Initialize table with default size (6x4 feet = 72x48 inches, landscape)
	# Long side (72") faces the viewer (X-axis), short side (48") is depth (Z-axis)
	table.setup_table(DEFAULT_TABLE_SIZE_FEET)
	_adjust_camera_for_table_size(DEFAULT_TABLE_SIZE_FEET)
	table_size_option.selected = TABLE_SIZE_INDEX_6X4

	# Initialize Lighting Controller
	lighting_controller = Node.new()
	lighting_controller.set_script(load("res://scripts/lighting_controller.gd"))
	add_child(lighting_controller)
	lighting_controller.initialize(directional_light, world_environment, fill_light)

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
	# Name the node explicitly: ObjectManager.clear_all_objects() and
	# UnitBoundaryVisualizer both resolve it via "/root/Main/OPRArmyManager".
	# Without this, add_child() auto-names it "@Node@N" and those lookups fail.
	opr_army_manager.name = "OPRArmyManager"
	opr_army_manager.table = table
	add_child(opr_army_manager)

	# Model caching (R2 download) progress — model_library is created in the manager's
	# _ready above, so it exists now.
	if opr_army_manager.model_library:
		opr_army_manager.model_library.caching_started.connect(_on_model_caching_started)
		opr_army_manager.model_library.caching_progress.connect(_on_model_caching_progress)
		opr_army_manager.model_library.caching_finished.connect(_on_model_caching_finished)

	# Set army_manager reference on SaveManager for GameUnit serialization
	save_manager.army_manager = opr_army_manager

	# Set army_manager reference on NetworkManager for unit state sync
	network_manager.army_manager = opr_army_manager

	# Initialize OPR Import Dialog
	opr_import_dialog = OPRImportDialog.new()
	get_tree().root.add_child(opr_import_dialog)
	opr_import_dialog.army_imported.connect(_on_opr_army_imported)
	opr_import_dialog.hide()

	# Initialize OPR Stats Tooltip
	var tooltip_scene = load("res://scenes/opr_stats_tooltip.tscn")
	opr_stats_tooltip = tooltip_scene.instantiate()
	$UI.add_child(opr_stats_tooltip)

	# Initialize Unit Card (docked, live battle state for the selected unit)
	var unit_card_scene = load("res://scenes/unit_card.tscn")
	unit_card = unit_card_scene.instantiate()
	unit_card.army_manager = opr_army_manager
	$UI.add_child(unit_card)

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
	map_layout_editor.objectives_changed.connect(_on_objectives_changed)
	map_layout_btn.pressed.connect(_on_map_layout_pressed)

	# Initialize Terrain Overlay (on the 3D table)
	var overlay_script = load("res://scripts/terrain_overlay.gd")
	terrain_overlay = Node3D.new()
	terrain_overlay.set_script(overlay_script)
	terrain_overlay.name = "TerrainOverlay"
	terrain_overlay.visible = true  # Ensure it's visible
	table.add_child(terrain_overlay)

	# Give object_manager reference to terrain_overlay for terrain hints
	object_manager.terrain_overlay = terrain_overlay

	# Connect object_manager signals for deployment checking
	object_manager.drag_ended.connect(_on_unit_moved)

	# Initialize Atmospheric Clouds (RTS-style drifting clouds at high zoom)
	_init_atmospheric_clouds()

	# Atmosphere orchestrator: one-click presets (day/sunset/night/overcast/rain),
	# war-torn ruin fires and the procedural battlefield ambience.
	atmosphere_controller = AtmosphereController.new()
	atmosphere_controller.name = "AtmosphereController"
	add_child(atmosphere_controller)
	atmosphere_controller.initialize(lighting_controller, world_environment,
			atmospheric_clouds, terrain_overlay)
	# Apply the startup mood (default: Sunset) NOW, synchronously, right after the
	# lighting controller set its synchronous baseline — so the table is in its final
	# mood from the first rendered frame, through the whole intro fly-in, with no
	# mid-intro lighting snap. (restore_saved() post-intro re-applies it + enables the
	# table-dependent fire/war-sound layers.)
	atmosphere_controller.apply_saved_lighting()
	lighting_panel.set_atmosphere_controller(atmosphere_controller)

	# Initialize Deployment Zones UI
	_init_deployment_zones_ui()

	# Initialize Radial Menu
	_init_radial_menu()

	# Set save_manager references for terrain/layout and marker restoration
	save_manager.map_layout_editor = map_layout_editor
	save_manager.terrain_overlay = terrain_overlay
	save_manager.radial_menu_controller = radial_menu_controller

	# The intro is started AFTER the table size is chosen (on dialog confirm, see below),
	# so the size chooser never overlaps the cinematic. Loaded/joined games skip the
	# chooser and start the intro directly.

	# Check if a saved battle should be loaded (from startup menu)
	var pending_load := ProjectSettings.get_setting("niemandsland/pending_load_path", "") as String
	if not pending_load.is_empty():
		ProjectSettings.set_setting("niemandsland/pending_load_path", "")
		call_deferred("_load_pending_battle", pending_load)

	# Check if internet game should be started (from startup menu)
	var pending_internet = ProjectSettings.get_setting("niemandsland/pending_internet_lobby", false)
	if pending_internet:
		ProjectSettings.set_setting("niemandsland/pending_internet_lobby", false)
		var is_internet_host = ProjectSettings.get_setting("niemandsland/internet_is_host", false)
		var pending_relay_url = ProjectSettings.get_setting("niemandsland/internet_relay_url", "")
		var pending_room_code = ProjectSettings.get_setting("niemandsland/internet_room_code", "")
		call_deferred("_start_pending_internet_game", is_internet_host, pending_relay_url, pending_room_code)

	# Table size is chosen ONCE up front, then locked — changing it later wipes the
	# built layout. Loads and multiplayer clients inherit the size from the saved/host
	# data, so they skip the chooser. The in-game size panel is hidden in every case.
	if table_size_option:
		table_size_option.get_parent().visible = false
	var joining_client: bool = pending_internet and not ProjectSettings.get_setting("niemandsland/internet_is_host", false)
	if pending_load.is_empty() and not joining_client:
		# Choose the table size FIRST on a black backdrop, then dissolve into the intro —
		# the chooser must never overlap the cinematic. UI stays hidden until the intro ends.
		$UI.visible = false
		_show_prompt_black()
		call_deferred("_prompt_table_size")
	else:
		# Loaded battle / joining client: size comes from the saved/host data, so there is
		# no chooser — go straight into the intro.
		_start_cinematic_intro()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		# Handle key release for continuous actions
		if not event.pressed:
			# Stop group rotation when R or Shift is released
			if event.keycode == KEY_R or event.keycode == KEY_SHIFT:
				if _is_group_rotating:
					object_manager.commit_rotation_capture()
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
			if not _is_group_rotating:
				object_manager.begin_rotation_capture()
			_is_group_rotating = true
			get_viewport().set_input_as_handled()
		# Undo (Ctrl+Z)
		elif event.keycode == KEY_Z and event.ctrl_pressed and not event.shift_pressed:
			_undo()
			get_viewport().set_input_as_handled()
		# Redo (Ctrl+Shift+Z or Ctrl+Y)
		elif (event.keycode == KEY_Z and event.ctrl_pressed and event.shift_pressed) or (event.keycode == KEY_Y and event.ctrl_pressed):
			_redo()
			get_viewport().set_input_as_handled()
		# Delete selected objects (Delete / Backspace)
		elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			_delete_selected_objects()
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
			_toggle_settings_panel()
			get_viewport().set_input_as_handled()


## Reverts the most recent undoable action OWNED BY THIS PLAYER (Ctrl+Z). In
## multiplayer each player only undoes their own actions, never a peer's.
func _undo() -> void:
	if not undo_manager:
		return
	var my_peer: int = network_manager.get_my_peer_id() if network_manager else 0
	if undo_manager.can_undo_for(my_peer):
		undo_manager.undo_for(my_peer)


## Re-applies the most recently undone action OWNED BY THIS PLAYER (Ctrl+Y / Ctrl+Shift+Z).
func _redo() -> void:
	if not undo_manager:
		return
	var my_peer: int = network_manager.get_my_peer_id() if network_manager else 0
	if undo_manager.can_redo_for(my_peer):
		undo_manager.redo_for(my_peer)


## Deletes every currently selected object as one undoable action (Delete key).
func _delete_selected_objects() -> void:
	if not object_manager or not radial_menu_controller:
		return
	var selected: Array[Node3D] = object_manager.get_selected_objects()
	if selected.is_empty():
		return
	radial_menu_controller.delete_objects(selected.duplicate())
	object_manager.deselect_all()


func _process(delta: float) -> void:
	# Handle continuous group rotation (Shift+R held)
	if _is_group_rotating:
		var rotation_amount = GROUP_ROTATION_SPEED * delta
		object_manager.rotate_selected_group(rotation_amount)

		# Throttled batch broadcast of positions + rotations to remote peers
		_group_rotation_broadcast_timer += delta
		if _group_rotation_broadcast_timer >= GROUP_ROTATION_BROADCAST_INTERVAL and network_manager.is_multiplayer_active():
			_group_rotation_broadcast_timer = 0.0
			var selected: Array[Node3D] = object_manager.get_selected_objects()
			var move_batch: Array = []
			var rot_batch: Array = []
			for obj: Node3D in selected:
				if is_instance_valid(obj) and obj.has_meta("network_id"):
					var net_id: int = obj.get_meta("network_id")
					move_batch.append(net_id)
					move_batch.append(obj.global_position.x)
					move_batch.append(obj.global_position.y)
					move_batch.append(obj.global_position.z)
					rot_batch.append(net_id)
					rot_batch.append(obj.rotation.y)
			if move_batch.size() > 0:
				network_manager.broadcast_move_batch(move_batch)
			if rot_batch.size() > 0:
				network_manager.broadcast_rotation_batch(rot_batch)
	else:
		_group_rotation_broadcast_timer = 0.0

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

	# Get zoom level from camera
	var zoom_text = ""
	if camera_pivot and camera_pivot.has_method("get_zoom"):
		var zoom = camera_pivot.get_zoom()
		zoom_text = " | Zoom: %.1f" % zoom

	performance_label.text = "FPS: %d | Objects: %d%s" % [fps, object_count, zoom_text]

	# Handle OPR unit hover detection
	_update_opr_hover()

	# Broadcast presence data to remote players
	_broadcast_presence(delta)


func _on_spawn_miniature() -> void:
	var spawn_pos = _get_random_table_position()
	object_manager.spawn_miniature(spawn_pos)


func _on_spawn_terrain() -> void:
	var spawn_pos = _get_random_table_position()
	object_manager.spawn_terrain(spawn_pos)


## Open file dialog to load a 3D model
func _on_load_model() -> void:
	model_file_dialog.popup_centered()


## Handle selected model file
func _on_model_file_selected(path: String) -> void:
	var spawn_pos = _get_random_table_position()
	var model = object_manager.spawn_custom_model(path, spawn_pos)
	if not model:
		push_error("Failed to load model: %s" % path)


## Performance test: Spawn 200 miniatures in a grid
func _on_spawn_200() -> void:
	# Clear existing objects first
	object_manager.clear_all_objects()

	# Calculate grid layout (20 columns x 10 rows = 200)
	var cols = 20
	var rows = 10

	# Table size in meters
	var size_meters = table.table_size * FEET_TO_METERS  # FEET_TO_METERS
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


## Performance test: Spawn 500 miniatures
func _on_spawn_500() -> void:
	_spawn_grid(500, 25, 20)


## Performance test: Spawn 1000 miniatures
func _on_spawn_1000() -> void:
	_spawn_grid(1000, 40, 25)


## Performance test: Spawn 100 complex terrain objects
func _on_spawn_complex() -> void:
	object_manager.clear_all_objects()

	var cols = 10
	var rows = 10
	var size_meters = table.table_size * FEET_TO_METERS
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


## Helper function to spawn miniatures in a grid
func _spawn_grid(total: int, cols: int, rows: int) -> void:
	object_manager.clear_all_objects()

	var size_meters = table.table_size * FEET_TO_METERS
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


## Shows a warning + confirmation before running a destructive table action, so a
## stray click can't wipe / rearrange / advance the whole table. Reuses one dialog.
func _show_action_confirm(title: String, message: String, ok_text: String, action: Callable) -> void:
	if not _action_confirm_dialog:
		_action_confirm_dialog = ConfirmationDialog.new()
		# Match the app's glassmorphism look instead of the default grey Godot dialog.
		if has_node("/root/ThemeManager"):
			_action_confirm_dialog.theme = get_node("/root/ThemeManager").get_current_theme()
		add_child(_action_confirm_dialog)
		_action_confirm_dialog.confirmed.connect(_on_action_confirmed)
	_action_confirm_dialog.title = title
	_action_confirm_dialog.dialog_text = message
	_action_confirm_dialog.ok_button_text = ok_text
	_pending_confirm_action = action
	_action_confirm_dialog.popup_centered()


func _on_action_confirmed() -> void:
	if _pending_confirm_action.is_valid():
		_pending_confirm_action.call()
	_pending_confirm_action = Callable()


func _on_clear_all() -> void:
	_show_action_confirm(
		"Clear Table",
		"Remove ALL objects from the table?\nThis clears every model, army and terrain piece and cannot be undone.",
		"Clear Table", _do_clear_all)


func _do_clear_all() -> void:
	object_manager.clear_all_objects()
	dice_result_label.text = ""
	_clear_dice_log()
	_update_round_button()  # clear_all_objects() resets the round to 1


func _on_sort_table() -> void:
	_show_action_confirm(
		"Sort Table",
		"Sort the whole table?\nEvery unit is reset to its import state and all models return to their starting positions.",
		"Sort Table", _do_sort_table)


func _do_sort_table() -> void:
	object_manager.sort_table()


## Advances the game round after confirmation.
func _on_next_round() -> void:
	_show_action_confirm(
		"Next Round",
		"Advance to the next round?\nAll activation tokens are cleared — no unit stays activated.",
		"Next Round", _do_next_round)


## Advances the game round (OPR bookkeeping; clears all activations), refreshes
## visuals, and syncs to remote peers so everyone shares the same round.
func _do_next_round() -> void:
	if opr_army_manager:
		opr_army_manager.advance_round()
	_refresh_round_visuals()
	if network_manager:
		network_manager.broadcast_round_advance()


## A remote peer advanced the round (the RPC already advanced our state).
func _on_remote_round_advanced() -> void:
	_refresh_round_visuals()


## Refreshes everything advance_round() affects: the button label plus the
## activation and caster tokens (reset_activation / add_round_caster_points
## changed is_activated and casts_current on every unit).
func _refresh_round_visuals() -> void:
	if radial_menu_controller and opr_army_manager:
		for game_unit in opr_army_manager.game_units.values():
			if game_unit:
				radial_menu_controller._update_activated_markers(game_unit)
				radial_menu_controller._update_caster_marker(game_unit)
	_update_round_button()


## Updates the Next Round button to show the current round.
func _update_round_button() -> void:
	if next_round_btn and opr_army_manager:
		next_round_btn.text = "Next Round (%d)" % opr_army_manager.current_round


## Toggle the left panel menu visibility with slide animation
func _on_hamburger_pressed() -> void:
	var is_opening = not left_panel_scroll.visible

	if is_opening:
		# Show panel and animate in
		left_panel_scroll.visible = true
		left_panel_scroll.modulate.a = 0.0
		var tween = create_tween()
		tween.tween_property(left_panel_scroll, "modulate:a", 1.0, 0.2)
		hamburger_button.text = "✕"
	else:
		# Animate out then hide
		var tween = create_tween()
		tween.tween_property(left_panel_scroll, "modulate:a", 0.0, 0.15)
		tween.tween_callback(func(): left_panel_scroll.visible = false)
		hamburger_button.text = "☰"


## Show confirmation dialog before ending battle
func _on_end_battle_pressed() -> void:
	end_battle_confirm_dialog.popup_centered()


## Confirmed: End Battle and return to Main Menu
func _on_end_battle_confirmed() -> void:
	get_tree().change_scene_to_file("res://scenes/startup_menu.tscn")


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
	_update_dice_set(_dice_count)
	dice_roller_control.roll()


func _on_quick_roll_button_pressed() -> void:
	_update_dice_set(_dice_count)
	dice_roller_control.quick_roll()


func _on_roller_started() -> void:
	roll_button.text = "Rolling..."
	roll_button.disabled = true
	AudioManager.play_sfx(AudioManager.SFXType.DICE_ROLL)


func _on_roller_finished(result: int) -> void:
	roll_button.text = "Roll"
	roll_button.disabled = false
	AudioManager.play_sfx(AudioManager.SFXType.DICE_IMPACT)

	var per_dice: Dictionary = dice_roller_control.per_dice_result()
	var counts: Dictionary = _count_faces(per_dice)
	# Always update the success column for the most recent roll (local or remote).
	_populate_current_roll_column(counts)

	# Skip logging/broadcast when showing a remote player's roll: the remote
	# handler already logged it, and re-broadcasting would cause a ping-pong loop.
	if _is_showing_remote_roll:
		_is_showing_remote_roll = false
		return

	_add_dice_log_entry("Du", per_dice.size(), counts)

	# Broadcast dice roll to remote players
	if network_manager.is_multiplayer_active():
		var values: Array[int] = []
		for dice_name: String in per_dice:
			values.append(int(per_dice[dice_name]))
		network_manager.broadcast_dice_roll(values.size(), values, result)


## Builds the click-based dice count selector (preset buttons 1..N plus
## increment buttons) and inserts it right below the panel title.
func _build_dice_count_selector() -> void:
	var selector := VBoxContainer.new()
	selector.name = "DiceCountSelector"
	selector.add_theme_constant_override("separation", 4)

	# Preset buttons 1..DICE_PRESET_MAX in a 5-column grid.
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	_dice_preset_buttons.clear()
	for n: int in range(1, DICE_PRESET_MAX + 1):
		var btn := Button.new()
		btn.text = str(n)
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 26)
		btn.pressed.connect(_on_dice_preset_pressed.bind(n))
		grid.add_child(btn)
		_dice_preset_buttons.append(btn)
	selector.add_child(grid)

	# Increment row: -10 -5 -1 [count] +1 +5 +10
	var inc_row := HBoxContainer.new()
	inc_row.add_theme_constant_override("separation", 2)
	for delta: int in [-10, -5, -1]:
		inc_row.add_child(_make_dice_delta_button(delta))
	_dice_count_value_label = Label.new()
	_dice_count_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dice_count_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dice_count_value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dice_count_value_label.custom_minimum_size = Vector2(44, 0)
	_dice_count_value_label.add_theme_font_size_override("font_size", 20)
	inc_row.add_child(_dice_count_value_label)
	for delta: int in [1, 5, 10]:
		inc_row.add_child(_make_dice_delta_button(delta))
	selector.add_child(inc_row)

	_dice_vbox.add_child(selector)
	_dice_vbox.move_child(selector, 1)  # directly below the "Dice Roller" title


## Creates one +N / -N increment button for the dice selector.
func _make_dice_delta_button(delta: int) -> Button:
	var btn := Button.new()
	btn.text = "+%d" % delta if delta > 0 else str(delta)
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 26)
	btn.pressed.connect(_on_dice_delta_pressed.bind(delta))
	return btn


func _on_dice_preset_pressed(count: int) -> void:
	_set_dice_count(count)


func _on_dice_delta_pressed(delta: int) -> void:
	_set_dice_count(_dice_count + delta)


## Sets the dice count (clamped), rebuilds the dice set and refreshes the display.
func _set_dice_count(count: int) -> void:
	_dice_count = clampi(count, MIN_DICE, MAX_DICE)
	_update_dice_set(_dice_count)
	_update_dice_count_display()


## Updates the big count label and highlights the matching preset button.
func _update_dice_count_display() -> void:
	if _dice_count_value_label:
		_dice_count_value_label.text = str(_dice_count)
	for i: int in _dice_preset_buttons.size():
		var is_active: bool = (i + 1) == _dice_count
		_dice_preset_buttons[i].modulate = Color(0.55, 0.85, 1.0) if is_active else Color.WHITE


## Update the dice set with the specified number of D6 dice
func _update_dice_set(count: int) -> void:
	dice_roller_control.dice_count = count
	current_dice_label.text = "In box: %d D6" % count

	# Adjust roller size based on dice count
	var size_factor = sqrt(count / 6.0)
	dice_roller_control.roller_size = Vector3(
		max(12, 18 * size_factor),
		15,
		max(8, 12 * size_factor)
	)


## Adds a visual dice-roll entry to the log: a horizontal strip showing each
## face (6 down to 1) as a die icon followed by its count.
func _add_dice_log_entry(player_name: String, dice_count: int, counts: Dictionary) -> void:
	var time_str: String = Time.get_time_string_from_system().substr(0, 5)

	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 4)

	var head := Label.new()
	head.text = "%s %s (%dd6)" % [time_str, player_name, dice_count]
	head.add_theme_font_size_override("font_size", 12)
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	entry.add_child(head)

	for face: int in [6, 5, 4, 3, 2, 1]:
		entry.add_child(_make_success_row(face, counts.get(face, 0), DICE_LOG_ICON_SIZE))

	_dice_log_vbox.add_child(entry)

	# Auto-scroll to bottom
	await get_tree().process_frame
	_dice_log_scroll.scroll_vertical = int(_dice_log_scroll.get_v_scroll_bar().max_value)


## Clear all entries from the dice log
func _clear_dice_log() -> void:
	for child: Node in _dice_log_vbox.get_children():
		child.queue_free()


## Builds the success readout column to the left of the dice box by reparenting
## the dice control into a horizontal row: [success column | dice box].
func _build_current_roll_column() -> void:
	var box: Control = dice_roller_control
	var parent: Node = box.get_parent()
	var idx: int = box.get_index()

	var row := HBoxContainer.new()
	row.name = "DiceBoxRow"
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)

	_current_roll_column = VBoxContainer.new()
	_current_roll_column.name = "CurrentRollColumn"
	# Fill the dice box's height and centre the stacked die-icons vertically within it,
	# so the success column lines up with the dice box instead of clinging to the top.
	_current_roll_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_current_roll_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_current_roll_column.add_theme_constant_override("separation", 2)

	parent.remove_child(box)
	parent.add_child(row)
	parent.move_child(row, idx)
	row.add_child(_current_roll_column)
	row.add_child(box)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_populate_current_roll_column({})


## Fills the current-roll column with one row per face (6 down to 1); faces with
## no hits are dimmed so the actual results stand out.
func _populate_current_roll_column(counts: Dictionary) -> void:
	if not _current_roll_column:
		return
	for child: Node in _current_roll_column.get_children():
		child.queue_free()
	for face: int in [6, 5, 4, 3, 2, 1]:
		_current_roll_column.add_child(_make_success_row(face, counts.get(face, 0), CURRENT_ROLL_ICON_SIZE))


## One "die icon + xN" row; dimmed when the count is zero.
func _make_success_row(face: int, count: int, icon_size: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.modulate.a = 1.0 if count > 0 else 0.32

	var icon := DieFaceIcon.new()
	icon.face = face
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var lbl := Label.new()
	lbl.text = "×%d" % count
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", maxi(12, icon_size - 10))
	row.add_child(lbl)
	return row


## Counts how many dice show each face (1-6) from a name->value result map.
func _count_faces(per_dice: Dictionary) -> Dictionary:
	var counts: Dictionary = {6: 0, 5: 0, 4: 0, 3: 0, 2: 0, 1: 0}
	for dice_name: String in per_dice:
		var value: int = int(per_dice[dice_name])
		if value in counts:
			counts[value] += 1
	return counts


func _get_random_table_position() -> Vector3:
	# Table size is in feet, convert to meters for positioning
	var size_meters = table.table_size * FEET_TO_METERS  # FEET_TO_METERS
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
	# Force SpinBoxes to apply any pending text input
	# (otherwise clicking Apply without pressing Enter first would use old values)
	width_input.apply()
	length_input.apply()

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


## Show the one-time table-size chooser at the start of a fresh game.
## Opaque black backdrop behind the chooser (3D scene hidden), on its own layer below the
## intro's overlay so the intro can cover and then reveal through it seamlessly.
func _show_prompt_black() -> void:
	_prompt_overlay = CanvasLayer.new()
	_prompt_overlay.layer = 95
	add_child(_prompt_overlay)
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_overlay.add_child(rect)


func _prompt_table_size() -> void:
	var dialog := TableSizeDialog.new()
	add_child(dialog)
	if table and table.has_method("get_biomes"):
		dialog.set_biomes(table.get_biomes(), table.biome)
	dialog.size_chosen.connect(_on_table_size_chosen.bind(dialog))
	dialog.popup_centered()
	# Gently fade the chooser in over the black backdrop.
	var content := dialog.get_child(0) as Control
	if content:
		content.modulate.a = 0.0
		var fade_in := create_tween()
		fade_in.tween_property(content, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)


## Apply the chosen table size, dissolve the chooser into black, then play the intro.
func _on_table_size_chosen(size_feet: Vector2, dialog: Window) -> void:
	_set_table_size(size_feet)
	# Apply the biome chosen in the dialog.
	var td := dialog as TableSizeDialog
	if td and td.selected_biome != "" and table.has_method("set_biome"):
		table.set_biome(td.selected_biome)
	var content := dialog.get_child(0) as Control
	var t := create_tween()
	if content:
		t.tween_property(content, "modulate:a", 0.0, 0.8).set_trans(Tween.TRANS_SINE)
	else:
		t.tween_interval(0.4)
	t.tween_callback(func() -> void:
		dialog.queue_free()
		# Start the intro (its own opaque black covers the screen), then drop our backdrop
		# so the intro fades in from black.
		_start_cinematic_intro()
		if is_instance_valid(_prompt_overlay):
			_prompt_overlay.queue_free()
			_prompt_overlay = null
	)


## Set table to specific size and clear objects
func _set_table_size(size_feet: Vector2) -> void:
	# Clear existing objects
	object_manager.clear_all_objects()
	dice_result_label.text = ""

	# Rebuild table (the ground mist resizes via the table_resized signal)
	table.setup_table(size_feet)

	# Update map layout editor with new table size (this clears terrain/objectives data)
	if map_layout_editor and map_layout_editor.has_method("set_table_size"):
		map_layout_editor.set_table_size(size_feet)

	# Clear and update terrain overlay (must always update, even with empty data)
	if terrain_overlay:
		# Clear all overlays since table size changed
		if terrain_overlay.has_method("update_overlay"):
			terrain_overlay.update_overlay({}, size_feet, 0.0)
		if terrain_overlay.has_method("update_wall_models"):
			terrain_overlay.update_wall_models([], size_feet, 0.0)
		if terrain_overlay.has_method("update_placed_objects"):
			terrain_overlay.update_placed_objects([], size_feet, 0.0)
		if terrain_overlay.has_method("update_objectives"):
			terrain_overlay.update_objectives([])
		if terrain_overlay.has_method("set_deployment_zones"):
			terrain_overlay.set_deployment_zones(0)  # NONE

	# Adjust camera view
	_adjust_camera_for_table_size(size_feet)

	# Sync table size to remote peers
	_broadcast_table_settings_update("table_size", [size_feet.x, size_feet.y])

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
	# Announce our version so the host can validate us; on a match it then pushes
	# the full state (gated on the handshake). No explicit state request needed.
	network_manager.announce_version_to_host()


func _on_network_failed() -> void:
	_update_network_ui(false, false)
	network_status_label.text = "Connection failed!"
	network_status_label.add_theme_color_override("font_color", Color.RED)


func _on_network_disconnected() -> void:
	_update_network_ui(false, false)
	network_status_label.text = "Server disconnected"
	network_status_label.add_theme_color_override("font_color", Color.RED)


func _on_player_joined(peer_id: int) -> void:
	print("Player %d joined! Peers: %s" % [peer_id, str(multiplayer.get_peers())])
	if multiplayer.is_server():
		network_status_label.text = "Hosting (peer %d connecting…)" % peer_id
		# Do NOT push state yet: wait for the peer to announce a matching version
		# (network_manager → peer_version_validated → _on_peer_version_validated).
		# The host-side handshake timeout that kicks a silent/old client is armed
		# inside network_manager._on_peer_connected.

	# Spawn avatar for the remote player at the table edge
	_spawn_player_avatar(peer_id)


## Host: the joining peer's game version matches ours — now push full state.
## This fires after SceneMultiplayer has registered the peer, so rpc_id() works.
func _on_peer_version_validated(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	network_status_label.text = "Hosting (peer %d joined)" % peer_id
	_sync_state_to_peer(peer_id)


## Client: the host refused us because our game versions differ. Leave the
## session and tell the player to match versions before trying again.
func _on_version_rejected(host_version: String, my_version: String) -> void:
	push_warning("[Network] Version mismatch — host=%s, us=%s. Disconnecting." % [host_version, my_version])
	network_manager.disconnect_game()
	_update_network_ui(false, false)
	network_status_label.text = "Version mismatch: host %s, you %s — update to match" % [host_version, my_version]
	network_status_label.add_theme_color_override("font_color", Color.RED)


func _on_player_left(peer_id: int) -> void:
	var player_count = network_manager.connected_peers.size()
	if network_manager.is_host:
		network_status_label.text = "Hosting (%d players)" % player_count
	_cleanup_peer_presence(peer_id)
	print("Player %d left! Total: %d" % [peer_id, player_count])


## Internet multiplayer handlers
func _on_internet_room_ready(code: String) -> void:
	_update_network_ui(true, true)
	var display_code = InternetLobby._format_code(code)
	network_status_label.text = "Online: %s" % display_code
	network_status_label.add_theme_color_override("font_color", Color.GREEN)
	# Copy code to clipboard for easy sharing
	DisplayServer.clipboard_set(code)
	print("Room code %s copied to clipboard" % display_code)


func _on_internet_connected(peer_id: int) -> void:
	_update_network_ui(true, false)
	network_status_label.text = "Online (Peer %d)" % peer_id
	network_status_label.add_theme_color_override("font_color", Color.GREEN)
	# Announce our version to the host; on a match the host pushes full state
	# (gated on the handshake) once SceneMultiplayer has registered the peer.
	network_manager.announce_version_to_host()


func _on_internet_failed(reason: String) -> void:
	_update_network_ui(false, false)
	network_status_label.text = "Online failed: %s" % reason
	network_status_label.add_theme_color_override("font_color", Color.RED)


func _on_internet_disconnected() -> void:
	_update_network_ui(false, false)
	network_status_label.text = "Offline"
	network_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	# Clean up presence nodes
	_cleanup_all_presence()


## The relay link dropped unexpectedly. Both host and guest now auto-rejoin the same
## room: the relay preserves a host-dropped room for a short window so the host can
## reclaim peer id 1 and re-sync state, instead of ending everyone's game on a Wi-Fi blip.
func _on_relay_connection_lost() -> void:
	var role := "host" if network_manager.is_host else "guest"
	push_warning("[Network] Connection lost — attempting to rejoin the room (%s)…" % role)
	network_status_label.text = "Connection lost — reconnecting…"
	network_status_label.add_theme_color_override("font_color", Color.YELLOW)
	internet_lobby.reconnect_to_room()


func _on_relay_reconnecting() -> void:
	network_status_label.text = "Reconnecting…"
	network_status_label.add_theme_color_override("font_color", Color.YELLOW)


## Rejoin failed (relay unreachable or the room is gone, e.g. host left). End the
## session cleanly with a clear message.
func _on_relay_reconnect_failed(reason: String) -> void:
	push_warning("[Network] Reconnect failed: %s" % reason)
	network_status_label.text = "Reconnect failed (%s)" % reason
	network_status_label.add_theme_color_override("font_color", Color.RED)
	_update_network_ui(false, false)
	_cleanup_all_presence()


## Guest side: the host dropped but the room is preserved. Wait for it to return (the
## host reclaims peer id 1 and re-syncs) instead of treating it as a full disconnect.
func _on_host_paused() -> void:
	network_status_label.text = "Host disconnected — waiting for reconnect…"
	network_status_label.add_theme_color_override("font_color", Color.YELLOW)


## The host is present again (we rejoined as host, or our host returned). The full
## state re-sync runs over the restored peer link; clear the warning.
func _on_host_rejoined() -> void:
	network_status_label.text = "Reconnected"
	network_status_label.add_theme_color_override("font_color", Color.GREEN)


# ============================================================================
# Model caching (R2 download) progress
# ============================================================================

## An imported army needs models that aren't cached yet — show a progress overlay.
func _on_model_caching_started(total: int) -> void:
	_ensure_cache_progress_ui()
	_kill_cache_tween()
	_cache_progress_bar.max_value = maxi(1, total)
	_cache_progress_bar.value = 0
	_cache_progress_label.text = "Lade 3D-Modelle … 0/%d" % total
	_cache_progress_panel.visible = true


func _on_model_caching_progress(done: int, total: int) -> void:
	if not _cache_progress_panel:
		return
	_cache_progress_bar.max_value = maxi(1, total)
	# Glide smoothly to the new value instead of snapping (no "blob-blob" stepping).
	_kill_cache_tween()
	_cache_progress_tween = create_tween()
	_cache_progress_tween.tween_property(_cache_progress_bar, "value", float(done), 0.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_cache_progress_label.text = "Lade 3D-Modelle … %d/%d" % [done, total]


func _kill_cache_tween() -> void:
	if _cache_progress_tween and _cache_progress_tween.is_valid():
		_cache_progress_tween.kill()
	_cache_progress_tween = null


func _on_model_caching_finished() -> void:
	if _cache_progress_panel:
		_cache_progress_panel.visible = false


## Lazily builds the centered top "downloading models" overlay (created once).
func _ensure_cache_progress_ui() -> void:
	if _cache_progress_panel:
		return
	_cache_progress_panel = PanelContainer.new()
	# Fully centred on screen (both axes).
	_cache_progress_panel.anchor_left = 0.5
	_cache_progress_panel.anchor_right = 0.5
	_cache_progress_panel.anchor_top = 0.5
	_cache_progress_panel.anchor_bottom = 0.5
	_cache_progress_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_cache_progress_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_cache_progress_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cache_progress_panel.add_theme_stylebox_override("panel", HudTokens.panel_style())
	_cache_progress_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_cache_progress_panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)
	_cache_progress_label = Label.new()
	_cache_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_cache_progress_label)
	_cache_progress_bar = ProgressBar.new()
	_cache_progress_bar.custom_minimum_size = Vector2(320, 18)
	_cache_progress_bar.show_percentage = false
	vb.add_child(_cache_progress_bar)
	$UI.add_child(_cache_progress_panel)


## ============================================================================
## Player Presence System
## ============================================================================

## Broadcast cursor and camera positions to remote players
func _broadcast_presence(delta: float) -> void:
	if not network_manager.is_multiplayer_active():
		return
	if _is_army_syncing:
		return

	# Broadcast cursor position at ~15 Hz
	_cursor_broadcast_timer += delta
	if _cursor_broadcast_timer >= CURSOR_BROADCAST_INTERVAL:
		_cursor_broadcast_timer = 0.0
		var cursor_pos = object_manager.get_cursor_table_position()
		if cursor_pos != Vector3.ZERO:
			network_manager.broadcast_cursor_position(cursor_pos)

	# Broadcast camera direction at ~5 Hz
	_camera_broadcast_timer += delta
	if _camera_broadcast_timer >= CAMERA_BROADCAST_INTERVAL:
		_camera_broadcast_timer = 0.0
		if camera_pivot:
			network_manager.broadcast_camera_direction(
				camera_pivot._yaw, camera_pivot._pitch)
			var _cam := camera_pivot.get_node("Camera3D") as Camera3D
			if _cam:
				network_manager.broadcast_camera_position(_cam.global_position)


## Called when a remote player's cursor position is received
func _on_remote_cursor_updated(peer_id: int, pos_x: float, pos_z: float) -> void:
	if not _remote_cursors.has(peer_id):
		_spawn_remote_cursor(peer_id)
	_remote_cursors[peer_id].update_position(pos_x, pos_z)


## Called when a remote player's camera direction is received
func _on_remote_camera_updated(peer_id: int, yaw: float, pitch: float) -> void:
	if _player_avatars.has(peer_id):
		_player_avatars[peer_id].update_look_direction(yaw, pitch)


## Called when a remote player rolls dice
func _on_remote_dice_rolled(peer_id: int, dice_count: int, results: Array, total: int) -> void:
	# Build per-dice dictionary for log entry
	var per_dice: Dictionary = {}
	for i: int in range(results.size()):
		per_dice["D6_%d" % (i + 1)] = int(results[i])

	_add_dice_log_entry("Player %d" % peer_id, dice_count, _count_faces(per_dice))

	# Show 3D dice visualization for remote roll
	# Guard prevents roll_finnished from re-broadcasting
	_is_showing_remote_roll = true
	_update_dice_set(dice_count)
	var int_results: Array[int] = []
	for v: Variant in results:
		int_results.append(int(v))
	dice_roller_control.show_faces(int_results)

	# Play avatar dice roll animation
	if _player_avatars.has(peer_id):
		_player_avatars[peer_id].play_dice_roll_animation()


## Spawn a remote cursor visualization for a peer
func _spawn_remote_cursor(peer_id: int) -> void:
	var cursor_script = load("res://scripts/remote_cursor.gd")
	var cursor = Node3D.new()
	cursor.set_script(cursor_script)
	cursor.name = "RemoteCursor_%d" % peer_id
	var color = _get_player_color(peer_id)
	add_child(cursor)
	cursor.setup(peer_id, color)
	_remote_cursors[peer_id] = cursor
	print("[Presence] Spawned remote cursor for peer %d" % peer_id)


## Spawn a player avatar for a peer
func _spawn_player_avatar(peer_id: int) -> void:
	var avatar_script = load("res://scripts/player_avatar.gd")
	var avatar = Node3D.new()
	avatar.set_script(avatar_script)
	avatar.name = "PlayerAvatar_%d" % peer_id
	add_child(avatar)
	avatar.setup(peer_id, table.table_size)
	_player_avatars[peer_id] = avatar
	print("[Presence] Spawned avatar for peer %d at table edge" % peer_id)


## Remove presence nodes for a disconnected peer
func _cleanup_peer_presence(peer_id: int) -> void:
	if _remote_cursors.has(peer_id):
		_remote_cursors[peer_id].queue_free()
		_remote_cursors.erase(peer_id)
	if _player_avatars.has(peer_id):
		_player_avatars[peer_id].queue_free()
		_player_avatars.erase(peer_id)


## Remove all presence nodes (on disconnect)
func _cleanup_all_presence() -> void:
	for cursor in _remote_cursors.values():
		if is_instance_valid(cursor):
			cursor.queue_free()
	_remote_cursors.clear()
	for avatar in _player_avatars.values():
		if is_instance_valid(avatar):
			avatar.queue_free()
	_player_avatars.clear()


## Get player color for a peer ID
func _get_player_color(peer_id: int) -> Color:
	const COLORS := {
		1: Color(0.2, 0.4, 0.9),  # Blue
		2: Color(0.9, 0.2, 0.2),  # Red
		3: Color(0.2, 0.8, 0.3),  # Green
		4: Color(0.9, 0.7, 0.1),  # Yellow
	}
	return COLORS.get(peer_id, Color.WHITE)


## ============================================================================
## Table Settings Synchronization (Phase 3)
## ============================================================================

## Broadcast current table settings to all clients (host only)
func _broadcast_table_settings_update(setting_key: String, value) -> void:
	if not network_manager.is_multiplayer_active() or not multiplayer.is_server():
		return
	var settings = {setting_key: value}
	network_manager.broadcast_table_settings(settings)


## Receive table settings from host (client only)
func _on_remote_table_settings_changed(settings: Dictionary) -> void:
	print("[Settings] Received table settings: %s" % str(settings))

	if settings.has("table_size"):
		var ts = settings["table_size"]
		if ts is Array and ts.size() >= 2:
			var size_feet = Vector2(ts[0], ts[1])
			table.setup_table(size_feet)
			_adjust_camera_for_table_size(size_feet)
			print("[Settings] Table resized to %.1fx%.1f feet" % [size_feet.x, size_feet.y])

	if settings.has("deployment_type"):
		var dtype = int(settings["deployment_type"])
		if terrain_overlay and terrain_overlay.has_method("set_deployment_zones"):
			terrain_overlay.set_deployment_zones(dtype)
			if dtype > 0:
				terrain_overlay.set_deployment_zones_visible(true)
				if deployment_zone_check:
					deployment_zone_check.button_pressed = true

	if settings.has("deployment_visible"):
		var vis = bool(settings["deployment_visible"])
		if terrain_overlay and terrain_overlay.has_method("set_deployment_zones_visible"):
			terrain_overlay.set_deployment_zones_visible(vis)
			if deployment_zone_check:
				deployment_zone_check.button_pressed = vis

	if settings.has("objectives"):
		var objectives = settings["objectives"]
		if terrain_overlay and terrain_overlay.has_method("update_objectives"):
			var world_objs: Array[Vector3] = []
			var owners: Array[int] = []
			for obj in objectives:
				if obj is Array and obj.size() >= 3:
					world_objs.append(Vector3(obj[0], obj[1], obj[2]))
					owners.append(int(obj[3]) if obj.size() >= 4 else 0)
			terrain_overlay.update_objectives(world_objs, owners)

	if settings.has("terrain_layout"):
		var layout = settings["terrain_layout"]
		var cells_data = layout.get("grid_cells", {})
		var grid_cells: Dictionary = {}
		for key in cells_data:
			var coords = str(key).split(",")
			if coords.size() == 2:
				grid_cells[Vector2i(int(coords[0]), int(coords[1]))] = int(cells_data[key])
		var ts = layout.get("table_size", [6, 4])
		var table_sz = Vector2(ts[0], ts[1])
		var rot = float(layout.get("grid_rotation", 0.0))
		if terrain_overlay and terrain_overlay.has_method("update_overlay"):
			terrain_overlay.update_overlay(grid_cells, table_sz, rot)
		# Also update local map_layout_editor data
		if map_layout_editor:
			map_layout_editor.grid_cells = grid_cells
			map_layout_editor.grid_rotation_degrees = rot

		# Deserialize and apply wall segments (role/taper_dir drive the ruin shell
		# walls; defaults keep peers on older layout payloads rendering "full" panels)
		var wall_segments: Array[Dictionary] = []
		for w in layout.get("wall_segments", []):
			if w is Dictionary:
				wall_segments.append({
					"edge_cell": Vector2i(int(w.get("edge_cell_x", 0)), int(w.get("edge_cell_y", 0))),
					"edge_side": int(w.get("edge_side", 0)),
					"wall_key": str(w.get("wall_key", "")),
					"length_inches": float(w.get("length_inches", 3.0)),
					"sub_position": int(w.get("sub_position", 0)),
					"role": str(w.get("role", "full")),
					"taper_dir": int(w.get("taper_dir", -1)),
				})
		if map_layout_editor:
			map_layout_editor.wall_segments = wall_segments
		if terrain_overlay and terrain_overlay.has_method("update_wall_models"):
			terrain_overlay.update_wall_models(wall_segments, table_sz, rot)

		# Deserialize and apply placed objects
		var placed_objects: Array[Dictionary] = []
		for o in layout.get("placed_objects", []):
			if o is Dictionary:
				placed_objects.append({
					"object_key": str(o.get("object_key", "")),
					"cell": Vector2i(int(o.get("cell_x", 0)), int(o.get("cell_y", 0))),
					"offset": Vector2(float(o.get("offset_x", 0.5)), float(o.get("offset_y", 0.5))),
					"object_type": str(o.get("object_type", "tree")),
				})
		if map_layout_editor:
			map_layout_editor.placed_objects = placed_objects
		if terrain_overlay and terrain_overlay.has_method("update_placed_objects"):
			terrain_overlay.update_placed_objects(placed_objects, table_sz, rot)

		print("[Settings] Terrain layout received: %d cells, %d walls, %d objects" % [
			grid_cells.size(), wall_segments.size(), placed_objects.size()])


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
	_tts_json_path = ""
	_tts_models_dir = ""
	_tts_import_mode = "online"
	tts_json_dialog.popup_centered()


## JSON file selected - branch based on import mode
func _on_tts_json_selected(path: String) -> void:
	_tts_json_path = path

	# Hide dialog
	tts_json_dialog.hide()

	if _tts_import_mode == "online":
		# Online mode: Start download and import immediately
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

	# Hide previous dialog before opening next
	tts_models_dialog.hide()

	tts_images_dialog.popup_centered()


## Images directory selected - now perform the import
func _on_tts_images_dir_selected(path: String) -> void:
	var images_dir = path

	# Validate paths
	if _tts_json_path.is_empty() or _tts_models_dir.is_empty():
		push_error("TTS Import: Missing required paths")
		return

	# Perform import
	object_manager.import_tts_save(_tts_json_path, _tts_models_dir, images_dir)


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
	save_game_dialog.current_file = "game_%s.nml" % Time.get_datetime_string_from_system().replace(":", "-")
	save_game_dialog.popup_centered()


## Open load dialog
func _on_load_game() -> void:
	load_game_dialog.current_dir = SaveManager.get_default_save_dir()
	load_game_dialog.popup_centered()


## Save file selected
func _on_save_file_selected(path: String) -> void:
	# Ensure .nml extension
	if not path.ends_with(".nml"):
		path += ".nml"

	var error = save_manager.save_game(path)
	if error != OK:
		push_error("Failed to save game: %d" % error)


## Load file selected
func _on_load_file_selected(path: String) -> void:
	var error = await save_manager.load_game(path)
	if error != OK:
		push_error("Failed to load game: %d" % error)


## Save completed callback
func _on_save_completed(path: String) -> void:
	print("Game saved successfully: %s" % path.get_file())
	# Could show a toast notification here


## Load completed callback
func _on_load_completed(object_count: int) -> void:
	print("Game loaded: %d objects" % object_count)
	_update_round_button()  # restored round may differ from 1

	# Sync to multiplayer clients if hosting
	if network_manager.is_host and network_manager.connected_peers.size() > 0:
		_sync_loaded_state_to_clients()


## Load failed callback
func _on_load_failed(error: String) -> void:
	push_error("Load failed: %s" % error)


## Load a battle from a path passed via the startup menu
func _load_pending_battle(path: String) -> void:
	print("Loading pending battle from startup menu: %s" % path.get_file())
	var error = await save_manager.load_game(path)
	if error != OK:
		push_error("Failed to load pending battle: %d" % error)


## Start an internet game from settings passed by the startup menu
func _start_pending_internet_game(is_internet_host: bool, relay_url: String, room_code_to_join: String) -> void:
	if is_internet_host:
		print("Starting internet host via %s" % relay_url)
		internet_lobby.host_internet_game(relay_url)
	else:
		print("Joining internet room %s via %s" % [room_code_to_join, relay_url])
		internet_lobby.join_internet_game(room_code_to_join, relay_url)


## Called on the host when a client requests the current game state.
## The client's binary packet also makes Godot's SceneMultiplayer detect
## the peer, which is required for all subsequent RPCs to work.
@rpc("any_peer", "call_remote", "reliable")
func _request_game_state() -> void:
	var sender = multiplayer.get_remote_sender_id()
	print("Peer %d requested game state" % sender)
	if multiplayer.is_server():
		# Never hand state to a peer that hasn't passed the version handshake.
		if not network_manager.is_peer_validated(sender):
			push_warning("[StateSync] Ignoring state request from unvalidated peer %d" % sender)
			return
		_sync_state_to_peer(sender)


## Sync full game state to a specific peer
func _sync_state_to_peer(peer_id: int) -> void:
	var state = save_manager.serialize_game_state()
	state["_host_version"] = network_manager.get_game_version()
	var obj_count = state.get("objects", []).size()
	var unit_count = state.get("game_units", []).size()
	print("[StateSync] Sending state to peer %d: %d objects, %d game_units" % [peer_id, obj_count, unit_count])
	_rpc_sync_game_state.rpc_id(peer_id, state)


## Sync loaded state to all connected clients
func _sync_loaded_state_to_clients() -> void:
	if not network_manager.is_host:
		return

	print("Syncing loaded state to %d clients..." % network_manager.connected_peers.size())

	# Get current state and broadcast to all clients
	var state = save_manager.serialize_game_state()
	state["_host_version"] = network_manager.get_game_version()
	_rpc_sync_game_state.rpc(state)


## RPC to sync game state to clients (mirrors save_manager.load_game() deserialization)
@rpc("authority", "call_remote", "reliable")
func _rpc_sync_game_state(state: Dictionary) -> void:
	# Belt-and-suspenders: if the host runs a different version (e.g. an old host
	# without the join-time handshake), refuse its state and leave the session.
	var host_version := str(state.get("_host_version", "unknown"))
	var my_version: String = network_manager.get_game_version()
	if host_version != my_version:
		push_warning("[StateSync] Host version %s != ours %s — refusing state" % [host_version, my_version])
		_on_version_rejected(host_version, my_version)
		return

	var obj_count = state.get("objects", []).size()
	var unit_count = state.get("game_units", []).size()
	print("[StateSync] Received game state from host: %d objects, %d game_units" % [obj_count, unit_count])

	# Clear current objects (broadcast=false to avoid clearing host's objects)
	object_manager.clear_all_objects(false)

	# Full table deserialization (size + map layout: grid, deployment zones, objectives)
	var table_data = state.get("table", {})
	save_manager._deserialize_table(table_data)
	var size = table_data.get("size_feet", [6, 4])
	if size is Array and size.size() >= 2:
		_adjust_camera_for_table_size(Vector2(size[0], size[1]))

	# Adopt the host's OPR special-rule descriptions so this peer can show enemy rules.
	if opr_army_manager and opr_army_manager.has_method("merge_rule_descriptions"):
		opr_army_manager.merge_rule_descriptions(state.get("rule_descriptions", {}))

	# Restore game units (OPR units with wounds, status, model positions)
	save_manager._deserialize_game_units(state.get("game_units", []))

	# Deserialize objects (async for TTS downloads)
	var objects_data = state.get("objects", [])
	var loaded_count = await save_manager._deserialize_objects(objects_data)

	# Sync object counter so subsequent spawns don't conflict with existing IDs
	var synced_counter = int(state.get("object_counter", 0))
	if synced_counter > 0:
		object_manager._object_counter = synced_counter

	# Restore game state (round, current player)
	save_manager._deserialize_game_state(state.get("game_state", {}))

	# Restore marker visualizations (fatigue, shaken, wounds)
	save_manager._restore_hero_attachments_after_load()
	save_manager._restore_markers_after_load()

	print("Synced %d objects from host (counter=%d)" % [loaded_count, object_manager._object_counter])


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


## ============================================================================
## UI Theme System
## ============================================================================

## Apply UI theme to the HUD and dialogs
func _apply_ui_theme() -> void:
	var current_theme = ThemeManager.get_current_theme()

	# Apply to HUD
	var hud = $UI/HUD
	hud.theme = current_theme

	# Tactical corner-bracket chrome on the main HUD panels (additive, mouse-ignore).
	_add_hud_frame($UI/HUD/DiceRollerPanel)

	# Apply to all file dialogs
	model_file_dialog.theme = current_theme
	tts_json_dialog.theme = current_theme
	tts_models_dialog.theme = current_theme
	tts_images_dialog.theme = current_theme
	save_game_dialog.theme = current_theme
	load_game_dialog.theme = current_theme
	terrain_browser_popup.theme = current_theme


## Adds a corner-bracket HudFrame overlay to a HUD PanelContainer (idempotent).
func _add_hud_frame(panel: Control) -> void:
	if panel and not panel.has_node("HudFrame"):
		var f := HudFrame.new()
		f.name = "HudFrame"
		panel.add_child(f)


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

	# Spawn the army on tray (position determined by player ID).
	# Awaitable: on-demand models are downloaded up front before spawning.
	var spawned = await opr_army_manager.spawn_army(army)
	print("Spawned %d models for army '%s' on Player %d's tray" % [spawned.size(), army.name, player_id])

	# Sync to other peers if in multiplayer
	if network_manager.is_multiplayer_active():
		_broadcast_army_import(army, spawned)


## Broadcast a newly imported army to all remote peers (batched to avoid rate limits)
func _broadcast_army_import(army: OPRApiClient.OPRArmy, spawned_models: Array[Node3D]) -> void:
	# Build per-unit data: one Dictionary + one objects Array per unit
	var units_data: Array[Dictionary] = []
	var objects_per_unit: Array[Array] = []

	# Build a lookup: network_id -> serialized object data
	var model_to_obj: Dictionary = {}
	for model in spawned_models:
		var obj_data: Dictionary = save_manager._serialize_object(model)
		if not obj_data.is_empty():
			var net_id := int(obj_data.get("network_id", 0))
			model_to_obj[net_id] = obj_data

	for unit in army.units:
		var game_unit := opr_army_manager.get_game_unit(unit)
		if not game_unit:
			continue

		var unit_dict := game_unit.to_dict()
		# Add model positions
		var model_positions: Array = []
		var unit_objects: Array = []
		for model in game_unit.models:
			if model.node and is_instance_valid(model.node):
				model_positions.append({
					"position": [model.node.global_position.x, 0.0, model.node.global_position.z],
					"rotation": [model.node.rotation_degrees.x, model.node.rotation_degrees.y, model.node.rotation_degrees.z],
					"visible": model.node.visible
				})
				# Collect serialized object for this model
				var net_id := int(model.node.get_meta("network_id", 0))
				if model_to_obj.has(net_id):
					unit_objects.append(model_to_obj[net_id])
			else:
				model_positions.append(null)

		unit_dict["model_positions"] = model_positions
		units_data.append(unit_dict)
		objects_per_unit.append(unit_objects)

	print("[ArmySync] Broadcasting army in batches: %d units (player_id=%d, army='%s')" % [units_data.size(), army.player_id, army.name])
	_is_army_syncing = true
	await network_manager.broadcast_army_batched(units_data, objects_per_unit, army.player_id, army.name)
	_is_army_syncing = false


## Receive army header from a remote peer — prepare for incoming units
func _on_remote_army_header(player_id: int, army_name: String, unit_count: int) -> void:
	print("[ArmySync] Header: '%s' — expecting %d units (player_id=%d)" % [army_name, unit_count, player_id])
	# Create army tray on remote side
	var player_color: Color = OPRArmyManager.PLAYER_COLORS.get(player_id, Color.GRAY)
	opr_army_manager._create_army_tray(player_id, army_name, player_color)


## Receive a single unit + its objects from a remote peer
func _on_remote_army_unit(unit_data: Dictionary, objects_data: Array, player_id: int) -> void:
	var unit_name: String = unit_data.get("unit_properties", {}).get("name", "?")
	print("[ArmySync] Unit received: '%s' (%d objects, player_id=%d)" % [unit_name, objects_data.size(), player_id])
	save_manager._deserialize_game_units([unit_data])
	await save_manager._deserialize_objects(objects_data)

	# Sync object counter per unit
	for obj_data in objects_data:
		if obj_data is Dictionary:
			var net_id := int(obj_data.get("network_id", 0))
			if net_id > object_manager._object_counter:
				object_manager._object_counter = net_id


## Receive army-complete signal — all units sent, restore markers
func _on_remote_army_complete(player_id: int) -> void:
	print("[ArmySync] Complete: all units received (player_id=%d)" % player_id)
	save_manager._restore_hero_attachments_after_load()
	save_manager._restore_markers_after_load()


## Receive TTS terrain spawn from a remote peer
func _on_remote_tts_terrain_spawned(mesh_url: String, diffuse_url: String,
	sx: float, sy: float, sz: float,
	px: float, py: float, pz: float, tname: String) -> void:
	print("[TerrainSync] Received remote TTS terrain: %s" % tname)
	await object_manager.spawn_tts_terrain(mesh_url, diffuse_url,
		Vector3(sx, sy, sz), Vector3(px, py, pz), tname)


## Receive remote camera position update
func _on_remote_camera_position_updated(peer_id: int, pos_x: float, pos_y: float, pos_z: float) -> void:
	if _player_avatars.has(peer_id):
		_player_avatars[peer_id].update_position(pos_x, pos_y, pos_z)


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


## Update the docked unit card when the selection changes.
## Shows the first selected unit's card; hides it for empty/non-unit selections.
func _on_selection_changed_update_card(selected_objects: Array[Node3D]) -> void:
	if not unit_card:
		return

	if selected_objects.is_empty():
		unit_card.clear()
		return

	var units := UnitUtils.get_unique_units(selected_objects)
	if units.is_empty():
		unit_card.clear()
		return

	# Prefer a host unit (not a joined Hero) as the card subject, so its attached
	# Hero shows as part of it rather than as a separate "+1".
	var primary: GameUnit = units[0]
	for unit in units:
		if not unit.is_attached():
			primary = unit
			break

	# Count other distinct units, excluding Heroes that are attached to the primary
	# (those are shown as part of it).
	var extra_units := 0
	for unit in units:
		if unit == primary:
			continue
		if unit.is_attached() and unit.get_attached_to() == primary:
			continue
		extra_units += 1

	unit_card.show_unit(primary, extra_units)


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

	# Calculate offset: WGS uses top-left (0,0), Niemandsland uses center
	var table_meters = game.get_table_size_meters()
	var offset = Vector3(-table_meters.x / 2, 0, -table_meters.y / 2)

	# Spawn all units
	var spawned = wgs_game_manager.spawn_game(offset)
	print("Spawned %d models from WGS game '%s'" % [spawned.size(), game.game_id])


## ============================================================================
## Cinematic Intro Animation
## ============================================================================

## Start the cinematic intro animation
func _start_cinematic_intro() -> void:
	# Create intro node
	cinematic_intro = CinematicIntro.new()
	cinematic_intro.name = "CinematicIntro"
	add_child(cinematic_intro)

	# Connect signals
	cinematic_intro.intro_finished.connect(_on_intro_finished)
	cinematic_intro.intro_skipped.connect(_on_intro_finished)

	# Hide UI during intro
	$UI.visible = false

	# Start the intro
	cinematic_intro.play_intro(self)


## Toggle the Settings window (lighting / atmosphere / audio) — left-panel button + F7.
func _toggle_settings_panel() -> void:
	if lighting_panel.visible:
		lighting_panel.hide()
	else:
		lighting_panel.show()


## Called when intro finishes or is skipped
func _on_intro_finished() -> void:
	# Slowly bring in the ground mist now that the table is built (hidden during the intro).
	if atmospheric_clouds and atmospheric_clouds.has_method("fade_in"):
		atmospheric_clouds.fade_in()

	# Reveal the gameplay UI only now that the intro is fully built — fade it in gently
	# so the panels don't pop in during the build.
	$UI.visible = true
	var hud := $UI.get_node_or_null("HUD") as Control
	if hud:
		hud.modulate.a = 0.0
		var ui_fade := create_tween()
		ui_fade.tween_property(hud, "modulate:a", 1.0, 1.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Restore the player's persisted atmosphere (preset + war-torn/war-sound toggles) —
	# after the UI reveal, so an atmosphere hiccup can never leave the screen stuck.
	if atmosphere_controller:
		atmosphere_controller.restore_saved()

	# Clean up intro after a delay
	if cinematic_intro:
		await get_tree().create_timer(1.0).timeout
		if is_instance_valid(cinematic_intro):
			cinematic_intro.queue_free()
			cinematic_intro = null


## ============================================================================
## Graphics Settings
## ============================================================================

## Handle graphics quality selection change
## UI order matches enum: Performance=0, Low=1, Medium=2, High=3, Ultra=4
func _on_graphics_quality_changed(index: int) -> void:
	var preset: GraphicsSettings.QualityPreset

	match index:
		0:  # Performance
			preset = GraphicsSettings.QualityPreset.PERFORMANCE
		1:  # Low
			preset = GraphicsSettings.QualityPreset.LOW
		2:  # Medium
			preset = GraphicsSettings.QualityPreset.MEDIUM
		3:  # High
			preset = GraphicsSettings.QualityPreset.HIGH
		4:  # Ultra
			preset = GraphicsSettings.QualityPreset.ULTRA
		_:
			preset = GraphicsSettings.QualityPreset.MEDIUM

	GraphicsSettings.apply_preset(preset)


## ============================================================================
## Map Layout Editor
## ============================================================================

## Open Map Layout Editor
func _on_map_layout_pressed() -> void:
	if map_layout_editor:
		map_layout_editor.set_table_size(table.table_size)
		map_layout_editor.visible = true
		$UI/HUD.visible = false  # Hide main HUD while in layout mode
		# Disable object selection while in map layout mode
		if object_manager:
			object_manager.selection_enabled = false


## Close Map Layout Editor
func _on_map_layout_closed() -> void:
	$UI/HUD.visible = true  # Show main HUD again
	# Re-enable object selection when leaving map layout mode
	if object_manager:
		object_manager.selection_enabled = true
	# Reset zoom when closing map layout editor
	if map_layout_editor and map_layout_editor.has_method("reset_zoom"):
		map_layout_editor.reset_zoom()
	# Update objectives on 3D terrain when closing
	if map_layout_editor and map_layout_editor.has_method("get_objectives_for_overlay"):
		var world_objectives = map_layout_editor.get_objectives_for_overlay()
		if terrain_overlay and terrain_overlay.has_method("update_objectives"):
			terrain_overlay.update_objectives(world_objectives)

	# Broadcast terrain layout to remote clients when map editor closes
	if network_manager.is_multiplayer_active() and map_layout_editor:
		var cells_serialized = {}
		for cell_pos in map_layout_editor.grid_cells:
			cells_serialized["%d,%d" % [cell_pos.x, cell_pos.y]] = map_layout_editor.grid_cells[cell_pos]

		# Serialize wall segments for network
		var walls_serialized = []
		for wall in map_layout_editor.wall_segments:
			walls_serialized.append({
				"edge_cell_x": wall.get("edge_cell", Vector2i.ZERO).x,
				"edge_cell_y": wall.get("edge_cell", Vector2i.ZERO).y,
				"edge_side": wall.get("edge_side", 0),
				"wall_key": wall.get("wall_key", ""),
				"length_inches": wall.get("length_inches", 3.0),
				"sub_position": wall.get("sub_position", 0),
				"role": wall.get("role", "full"),
				"taper_dir": wall.get("taper_dir", -1),
			})

		# Serialize placed objects for network
		var objects_serialized = []
		for obj in map_layout_editor.placed_objects:
			objects_serialized.append({
				"object_key": obj.get("object_key", ""),
				"cell_x": obj.get("cell", Vector2i.ZERO).x,
				"cell_y": obj.get("cell", Vector2i.ZERO).y,
				"offset_x": obj.get("offset", Vector2(0.5, 0.5)).x,
				"offset_y": obj.get("offset", Vector2(0.5, 0.5)).y,
				"object_type": obj.get("object_type", "tree"),
			})

		_broadcast_table_settings_update("terrain_layout", {
			"grid_cells": cells_serialized,
			"table_size": [map_layout_editor.table_size_feet.x, map_layout_editor.table_size_feet.y],
			"grid_rotation": map_layout_editor.grid_rotation_degrees,
			"wall_segments": walls_serialized,
			"placed_objects": objects_serialized,
		})


## Handle deployment type change from Map Tool
func _on_deployment_type_changed(deployment_type: int) -> void:
	if not terrain_overlay or not terrain_overlay.has_method("set_deployment_zones"):
		return

	# For custom zones, pass the zone data to terrain_overlay
	if deployment_type == 2 and map_layout_editor:  # CUSTOM
		var zone_data = map_layout_editor.get_custom_zone_data()
		if terrain_overlay.has_method("set_custom_zones"):
			terrain_overlay.set_custom_zones(zone_data.player1_world, zone_data.player2_world)

	terrain_overlay.set_deployment_zones(deployment_type)

	# Auto-show deployment zones when a type is selected
	if deployment_type > 0:
		terrain_overlay.set_deployment_zones_visible(true)
		if deployment_zone_check:
			deployment_zone_check.button_pressed = true

	# Sync deployment type to remote clients
	_broadcast_table_settings_update("deployment_type", deployment_type)


## Handle objectives change from Map Tool
func _on_objectives_changed(objectives: Array) -> void:
	if not terrain_overlay or not terrain_overlay.has_method("update_objectives"):
		return

	# Convert 2D inch positions to 3D world positions
	var world_objectives: Array[Vector3] = []
	if map_layout_editor and map_layout_editor.has_method("get_objectives_for_overlay"):
		world_objectives = map_layout_editor.get_objectives_for_overlay()

	terrain_overlay.update_objectives(world_objectives)

	# Sync objectives to remote clients (4th element = owner, 0 = neutral)
	var obj_owners: Array = terrain_overlay.get_objective_owners() if terrain_overlay.has_method("get_objective_owners") else []
	var obj_data := []
	for i in range(world_objectives.size()):
		var obj = world_objectives[i]
		var owner_id := int(obj_owners[i]) if i < obj_owners.size() else 0
		obj_data.append([obj.x, obj.y, obj.z, owner_id])
	_broadcast_table_settings_update("objectives", obj_data)


## Update terrain overlay when map layout changes
func _on_map_layout_updated(grid_cells: Dictionary, table_size: Vector2,
		grid_rotation: float, wall_segments: Array, placed_objects: Array) -> void:
	# This may be called during initialization before terrain_overlay exists
	if not terrain_overlay:
		return  # Silently ignore - will be updated when user closes map layout

	if not terrain_overlay.has_method("update_overlay"):
		push_warning("TerrainOverlay missing update_overlay method")
		return

	terrain_overlay.update_overlay(grid_cells, table_size, grid_rotation)

	# Update wall models in 3D
	if terrain_overlay.has_method("update_wall_models"):
		terrain_overlay.update_wall_models(wall_segments, table_size, grid_rotation)

	# Update placed objects (trees, containers) in 3D
	if terrain_overlay.has_method("update_placed_objects"):
		terrain_overlay.update_placed_objects(placed_objects, table_size, grid_rotation)


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


## Handle deployment zone visibility toggle
func _on_deployment_zones_visibility_toggled(show_zones: bool) -> void:
	if not terrain_overlay or not terrain_overlay.has_method("set_deployment_zones_visible"):
		return

	terrain_overlay.set_deployment_zones_visible(show_zones)

	# Sync visibility to remote clients
	_broadcast_table_settings_update("deployment_visible", show_zones)


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

	# Track the play-field extent on EVERY resize path (size dialog, save load, network
	# sync, WGS import) — sizing the mist only in _set_table_size left it hanging past
	# the table boundaries after loading a save. Apply the current size immediately:
	# the table is built before the clouds exist.
	table.table_resized.connect(_on_table_resized)
	_on_table_resized(table.table_size)


## Keep the ground mist matched to the table extent (feet -> metres).
func _on_table_resized(size_feet: Vector2) -> void:
	if atmospheric_clouds and atmospheric_clouds.has_method("set_table_size"):
		atmospheric_clouds.set_table_size(size_feet * FEET_TO_METERS)
	if atmosphere_controller:
		atmosphere_controller.set_table_size(size_feet * FEET_TO_METERS)


## Handle unit movement (re-check coherency)
func _on_unit_moved() -> void:
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
		if not game_unit:
			continue
		# A joined Hero is checked as part of its host unit.
		if game_unit.is_attached() and game_unit.get_attached_to() is GameUnit:
			game_unit = game_unit.get_attached_to()
		if game_unit not in checked_units:
			checked_units.append(game_unit)
			# Show coherency visualization for this unit. animate=false: this runs
			# live (~15 Hz) while dragging, so re-running the fade/pulse each frame
			# would make the lines flicker.
			coherency_visualizer.show_coherency(game_unit, false, false)


## ============================================================================
## Radial Menu
## ============================================================================

func _init_radial_menu() -> void:
	radial_menu_controller = RadialMenuController.new()
	radial_menu_controller.name = "RadialMenuController"
	add_child(radial_menu_controller)
	radial_menu_controller.initialize(object_manager, opr_army_manager)

	# Pass network manager reference for broadcasting state changes
	radial_menu_controller.network_manager = network_manager

	# Pass terrain overlay reference for objective capture / recolor
	radial_menu_controller.terrain_overlay = terrain_overlay

	# Create the shared undo/redo history and wire it to the systems that record
	# actions: object manager (move/rotate gestures) and radial controller (delete).
	undo_manager = UndoManager.new()
	undo_manager.name = "UndoManager"
	add_child(undo_manager)
	object_manager.undo_manager = undo_manager
	radial_menu_controller.undo_manager = undo_manager

	# Pass stats tooltip reference for displaying unit stats
	radial_menu_controller.stats_tooltip = opr_stats_tooltip

	# Share the custom-token library with the hover tooltip (for token effects)
	if opr_stats_tooltip:
		opr_stats_tooltip.token_library = radial_menu_controller.token_library

	# Create and pass coherency visualizer
	coherency_visualizer = CoherencyVisualizer.new()
	coherency_visualizer.name = "CoherencyVisualizer"
	add_child(coherency_visualizer)
	radial_menu_controller.coherency_visualizer = coherency_visualizer

	# Create unit boundary visualizer (shows which models belong to which unit)
	unit_boundary_visualizer = UnitBoundaryVisualizerScript.new()
	unit_boundary_visualizer.name = "UnitBoundaryVisualizer"
	unit_boundary_visualizer.army_manager = opr_army_manager
	add_child(unit_boundary_visualizer)
	radial_menu_controller.boundary_visualizer = unit_boundary_visualizer

	# Connect object manager's right-click signal to open the menu
	object_manager.context_menu_requested.connect(_on_context_menu_requested)

	# Connect army_spawned signal to initialize caster markers for imported units
	opr_army_manager.army_spawned.connect(_on_army_spawned_init_caster_markers)


## Handle context menu request from object manager
func _on_context_menu_requested(screen_pos: Vector2, selected_objects: Array) -> void:
	if radial_menu_controller:
		radial_menu_controller.open_menu(screen_pos, selected_objects)


## Check if radial menu is currently open
func is_radial_menu_open() -> bool:
	return radial_menu_controller and radial_menu_controller.is_menu_open()


## Initialize caster and status markers for all units when an army is spawned
func _on_army_spawned_init_caster_markers(army: OPRApiClient.OPRArmy, _models: Array[Node3D]) -> void:
	if not radial_menu_controller:
		return

	# Get all game units for this army and initialize markers
	for unit in army.units:
		var game_unit = opr_army_manager.get_game_unit(unit)
		if game_unit:
			radial_menu_controller.initialize_caster_marker_for_unit(game_unit)
			radial_menu_controller.initialize_status_markers_for_unit(game_unit)
			radial_menu_controller.initialize_special_weapon_rings_for_unit(game_unit)


## ============================================================================
## Remote Game State Sync Handlers (visual updates on receiving side)
## ============================================================================

## Called when a remote peer changes model wounds
func _on_remote_wounds_updated(model: ModelInstance) -> void:
	if radial_menu_controller:
		radial_menu_controller._update_wound_marker(model)

		# Handle model death/revival visibility
		if not model.is_alive and model.node and is_instance_valid(model.node):
			model.node.set_meta("deleted", true)
		elif model.is_alive and model.node and is_instance_valid(model.node):
			model.node.set_meta("deleted", false)


## Called when a remote peer changes unit activation
func _on_remote_activation_updated(game_unit: GameUnit) -> void:
	if radial_menu_controller:
		radial_menu_controller._update_activated_markers(game_unit)


## Called when a remote peer changes a unit marker (Fatigued, Shaken, etc.)
func _on_remote_unit_marker_updated(game_unit: GameUnit, marker_name: String, add: bool, color: Color, value: int) -> void:
	if not radial_menu_controller:
		return

	# Update the boolean state and visual markers for known marker types
	match marker_name:
		"FatiguedMarker":
			game_unit.is_fatigued = add
			radial_menu_controller._update_fatigued_markers(game_unit)
		"ShakenMarker":
			game_unit.is_shaken = add
			radial_menu_controller._update_shaken_markers(game_unit)
		"ActivatedMarker":
			game_unit.is_activated = add
			radial_menu_controller._update_activated_markers(game_unit)
		_:
			# Dialog marker (Pinned, Stunned, custom, counter, ...) - render its token
			radial_menu_controller.set_unit_marker_token(game_unit, marker_name, add, color, value)


## Called when a remote peer changes a single model's dialog marker.
func _on_remote_model_marker_updated(model: ModelInstance, marker_name: String, add: bool, color: Color, value: int) -> void:
	if radial_menu_controller and model:
		radial_menu_controller.set_model_marker_token(model, marker_name, add, color, value)


## Called when a remote peer changes a unit-wide counter marker's value.
func _on_remote_unit_marker_value_updated(game_unit: GameUnit, marker_name: String, value: int) -> void:
	if radial_menu_controller:
		radial_menu_controller.set_unit_marker_value(game_unit, marker_name, value)


## Called when a remote peer changes a single model's counter marker value.
func _on_remote_model_marker_value_updated(model: ModelInstance, marker_name: String, value: int) -> void:
	if radial_menu_controller and model:
		radial_menu_controller.set_model_marker_value(model, marker_name, value)


## Called when a remote peer captures/recolors a mission objective.
func _on_remote_objective_owner_updated(index: int, owner_id: int) -> void:
	if terrain_overlay and terrain_overlay.has_method("set_objective_owner"):
		terrain_overlay.set_objective_owner(index, owner_id)


## Called when a remote peer defines/updates a custom token in the library.
func _on_remote_token_defined(token_name: String, color: Color, is_counter: bool, effect: String) -> void:
	if radial_menu_controller:
		radial_menu_controller.receive_token_define(token_name, color, is_counter, effect)


## Called when a remote peer edits a custom token (rename / color / effect).
func _on_remote_token_edited(old_name: String, new_name: String, color: Color, effect: String) -> void:
	if radial_menu_controller:
		radial_menu_controller.apply_token_edit(old_name, new_name, color, effect, false)


## Called when a remote peer changes caster points
func _on_remote_casts_updated(game_unit: GameUnit) -> void:
	if radial_menu_controller:
		radial_menu_controller._update_caster_marker(game_unit)


## Called when a remote peer deletes an entire unit
func _on_remote_unit_deleted(game_unit: GameUnit) -> void:
	if radial_menu_controller:
		radial_menu_controller.unit_deleted.emit(game_unit)
