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
const RangeRingControllerScript = preload("res://scripts/range_ring_controller.gd")
const MovementRangeControllerScript = preload("res://scripts/movement_range_controller.gd")
const PinnedRulersScript = preload("res://scripts/pinned_rulers.gd")
const MoveTrailsScript = preload("res://scripts/move_trails.gd")

# ==============================================================================
# CONSTANTS
# ==============================================================================

## Default table dimensions
const DEFAULT_TABLE_SIZE_FEET := Vector2(6, 4)  # 72x48 inches (landscape)

## Graphics quality mapping (UI index matches enum directly)
## UI: Performance=0, Low=1, Medium=2, High=3, Ultra=4

## Group rotation
const GROUP_ROTATION_SPEED: float = 90.0  # degrees per second

## Keycodes handled in _unhandled_key_input that MOVE/EDIT objects (arrange, copy/paste,
## duplicate, lock, regiment-arc toggle, group-rotate, undo/redo, delete). These are swallowed
## while a remote peer is loading (the non-loading player is held back). The non-edit panels
## (F6/F7) are intentionally NOT in this set, so settings stay reachable mid-load.
const _OBJECT_EDIT_KEYS: Array[int] = [
	KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9,
	KEY_A, KEY_C, KEY_V, KEY_D, KEY_L, KEY_F, KEY_R, KEY_Z, KEY_Y,
	KEY_DELETE, KEY_BACKSPACE,
]

## Unit conversion constants
const FEET_TO_METERS: float = 0.3048

## Debug mode (set to false for production builds)

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
# Guard while applying a peer's mirrored cup composition, so mirroring it doesn't re-broadcast.
var _is_mirroring_dice: bool = false
var _group_rotation_broadcast_timer: float = 0.0
const GROUP_ROTATION_BROADCAST_INTERVAL: float = 0.1  # 10 Hz

@onready var distance_label: Label = $UI/HUD/DistanceLabel
@onready var clear_all_btn: Button = %ClearAll
@onready var sort_table_btn: Button = %SortTableBtn
@onready var next_round_btn: Button = %NextRoundBtn
@onready var settings_btn: Button = %SettingsBtn
@onready var performance_label: Label = %PerformanceLabel

# Hamburger menu
@onready var hamburger_button: Button = %HamburgerButton
@onready var left_panel_scroll: ScrollContainer = $UI/HUD/LeftPanelScroll

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
const DICE_BUTTON_HEIGHT: int = 26
const ACTIVE_DICE_BUTTON_TINT := Color(0.55, 0.85, 1.0)
const DICE_CAPTION_FONT_SIZE: int = 12       # row captions + success tag in the log
const DICE_CAPTION_MIN_WIDTH: int = 56       # caption column width on the option rows
const MODIFIER_VALUE_MIN_WIDTH: int = 44     # modifier value readout width
const SUCCESS_SUMMARY_FONT_SIZE: int = 16    # "✔ N" total under the success column
const NO_DICE_TINT := Color(0, 0, 0, 0)      # sentinel: no colour-tag tint on a result count (#77)
var _dice_count: int = DEFAULT_DICE_COUNT
var _dice_preset_buttons: Array[Button] = []
var _dice_count_value_label: Label = null
var _current_roll_column: VBoxContainer = null
var _movement_cap_buttons: Dictionary = {}  # MovementCap mode -> Button (the "Movement" cap row)

# Success evaluation + rerolls (display-only aids; the rules live in DiceRules).
var _success_target: int = DiceRules.TARGET_NONE
var _success_modifier: int = 0
var _target_buttons: Array[Button] = []
var _modifier_value_label: Label = null
var _reroll_buttons: Dictionary = {}  # Dictionary[DiceRules.RerollMode, Button]
var _last_faces: Array[int] = []
var _last_color_tags: Array[int] = []  # per-die colour tags of _last_faces (issue #77)
var _last_roll_local: bool = false
var _pending_reroll_mode: int = DiceRules.REROLL_NONE
var _pending_reroll_count: int = 0
var _remote_roll_context: Dictionary = {}

# Network UI elements
@onready var network_manager: Node = %NetworkManager
@onready var network_status_label: Label = %StatusLabel
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var disconnect_button: Button = %DisconnectButton

# Internet multiplayer
var internet_lobby: InternetLobby = null

# The local player's chosen display name (empty -> "Player N" fallback). Set from
# the startup-menu Host/Join dialog, otherwise loaded from the saved profile.
var _local_player_name: String = ""

# In-game online Host/Join dialogs (same NetDialog chrome as the startup menu).
var _net_host_popup: AcceptDialog = null
var _net_join_popup: AcceptDialog = null
var _net_host_name_input: LineEdit = null
var _net_host_url_input: LineEdit = null
var _net_host_public_check: CheckBox = null
var _net_join_name_input: LineEdit = null
var _net_join_code_input: LineEdit = null
var _net_join_url_input: LineEdit = null

# In-game chat + roster (built at runtime; visible only during a session).
const CHAT_PANEL_SMALL_FONT: int = 12
var _chat_panel: PanelContainer = null
var _chat_log_scroll: ScrollContainer = null
var _chat_log_vbox: VBoxContainer = null
var _chat_input: LineEdit = null
var _roster_vbox: VBoxContainer = null

# Non-blocking banner shown while a remote peer is loading (their move/edit is gated).
var _peer_busy_banner: Label = null

# Save/Load UI
@onready var save_manager: Node = %SaveManager
@onready var save_game_btn: Button = %SaveGameBtn
@onready var load_game_btn: Button = %LoadGameBtn
@onready var save_game_dialog: FileDialog = %SaveGameDialog
@onready var load_game_dialog: FileDialog = %LoadGameDialog

# Graphics Settings UI
@onready var graphics_quality_option: OptionButton = %GraphicsQualityOption

## Casual sandbox terrain shelf (code-built), created in _setup_sandbox_shelf().
var _sandbox_shelf: SandboxTerrainShelf = null
## Toolbar toggle for terrain edit mode (unlocks terrain + opens the shelf).
var _terrain_mode_btn: Button = null

# OPR Army Integration
@onready var import_opr_btn: Button = %ImportOPRArmy
var opr_army_manager: OPRArmyManager = null
var opr_import_dialog: OPRImportDialog = null
var opr_stats_tooltip: OPRStatsTooltip = null
var unit_card: UnitCard = null
var unit_dock: UnitDock = null
var battle_log: BattleLog = null              # narrative event log (collector)
var battle_log_panel: BattleLogPanel = null   # collapsible HUD panel (top-centre, collapsed by default)
var _host_free_move_check: CheckButton = null   # "Move all models" — host-operated, session-wide
var _room_code_button: Button = null          # permanent room-code display in the left bar (click = copy)
var _session_room_code: String = ""
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
## Full-screen "LOADING ARMY" overlay shown for the whole import (so it is never hidden
## behind the import window and is visible even when the models are already cached).
var _army_loading_overlay: LoadingOverlay = null

# Atmospheric Effects
var atmospheric_clouds: Node3D = null

# Radial Menu
var radial_menu_controller: RadialMenuController = null
var coherency_visualizer: CoherencyVisualizer = null
## 1" unit-separation proximity hint (OPR GF/AoF Advanced Rules v3.5.1 p.7: no model
## within 1" of models from OTHER units — friendly included — unless charging).
## Renders the warning; SeparationChecker does the base-edge distance math. Local only.
var separation_visualizer: SeparationVisualizer = null
## Cache of every alive OPR unit's member base shapes for the proximity-hint scan,
## grouped per (effective) unit so each foreign unit's WALL is built from its whole
## footprint. Rebuilt lazily on selection change (non-selected units stay put during
## the local drag, so their shapes stay valid) and refreshed on drop. Keyed by unit
## instance id; each entry: {unit: GameUnit, player_id: int, shapes: Array[BaseShape],
## centroid: Vector2, radius: float (centroid -> farthest member edge), signature:
## float (member-position hash for the visualizer's mesh cache)}.
var _separation_units_cache: Dictionary = {}
var _separation_cache_valid: bool = false
var unit_boundary_visualizer: Node3D = null  # UnitBoundaryVisualizer
var range_ring_controller: Node = null  # RangeRingController (base-anchored range auras)
var movement_range_controller: Node = null  # MovementRangeController (Advance/Rush reach)
var pinned_rulers: Node = null  # PinnedRulers (persistent shared measurements)
var move_trails: Node = null  # MoveTrails (path painting: chalk trails + move ledger)
## Persistent blood/oil stains left where models were removed (issue #60). Lives outside
## ObjectManager so it survives model cleanup; decorative, not saved.
var battlefield_stains: BattlefieldStains = null

# Deployment Zones UI (visibility toggle only - editing is in Map Tool;
# unit-placement compliance is verified manually by the players)
var deployment_zone_check: CheckBox = null
var deployment_flip_check: CheckBox = null

# Game-phase (deployment -> playing) gate UI: the Start-Game / Ready button + its MP status line.
var _start_game_button: Button = null
var _game_phase_status_label: Label = null

# Player Presence System
var _remote_cursors: Dictionary = {}  # peer_id -> RemoteCursor node
var _player_avatars: Dictionary = {}  # peer_id -> PlayerAvatar node
var _cursor_broadcast_timer: float = 0.0
var _camera_broadcast_timer: float = 0.0
const CURSOR_BROADCAST_INTERVAL: float = 0.066  # ~15 Hz
const CAMERA_BROADCAST_INTERVAL: float = 0.2  # 5 Hz

## True while army batches are being sent OR a remote army is being received — suppresses
## presence broadcasts so the heavy sync doesn't add to the relay message rate (the army
## burst + 15/5 Hz cursor/camera together can trip the relay rate limit -> a drop cascade).
var _is_army_syncing: bool = false
## True from the moment the relay link drops until we are reconnected (or the session ends).
## While set, presence broadcasts are paused so we don't flood a half-dead/rebuilding link
## with RPCs that fail and log "ID X not found in cache" (which only feeds the rate limit).
var _is_reconnecting: bool = false
## Buffers an incoming remote army between its header and complete RPCs, so all units are
## built in ONE pass (download every model with a single ensure_models call — the download
## manager has one shared HTTPRequest, so per-unit concurrent downloads collide). Keyed by
## player_id -> { army_name, units: Array, objects: Array }.
var _incoming_armies: Dictionary = {}


func _ready() -> void:
	# Debanding dithers the final frame, smoothing the dark space gradient so it shows
	# no banding "segments".
	get_viewport().use_debanding = true

	# Stamp the running version onto the HUD shortcuts label so it can never go stale — the version
	# lives ONLY in application/config/version (single source of truth; see also startup_menu).
	_apply_version_to_info_label()

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
	clear_all_btn.pressed.connect(_on_clear_all)
	sort_table_btn.pressed.connect(_on_sort_table)
	next_round_btn.pressed.connect(_on_next_round)
	settings_btn.pressed.connect(_toggle_settings_panel)
	_update_round_button()

	# Connect to object manager signals
	object_manager.distance_changed.connect(_on_distance_changed)
	object_manager.measurement_finished.connect(_on_measurement_finished)
	object_manager.drag_ended.connect(_on_drag_ended)
	object_manager.drag_updated.connect(_check_coherency_for_selected_units)
	# Proactive during drag: nearby foreign units fade their wall in (~3"); violations pulse.
	object_manager.drag_updated.connect(_check_separation_for_selected_units.bind(true))
	object_manager.selection_changed.connect(_on_selection_changed_update_card)
	object_manager.selection_changed.connect(_on_selection_changed_for_separation)

	# Hide distance label initially
	distance_label.text = ""

	# Connect Dice Roller Plugin
	roll_button.pressed.connect(_on_roll_button_pressed)
	quick_roll_button.pressed.connect(_on_quick_roll_button_pressed)
	dice_roller_control.roll_finnished.connect(_on_roller_finished)
	dice_roller_control.roll_started.connect(_on_roller_started)
	# A local die-colour click → mirror it live to the opponent's tray.
	dice_roller_control.color_tag_changed.connect(_on_local_die_color_changed)

	# Build the click-based dice count selector, the success readout column and
	# the success/reroll controls, then initialise the dice set with the default
	# count.
	_build_dice_count_selector()
	_build_current_roll_column()
	_build_success_controls()
	_build_reroll_row()
	_build_movement_cap_row()
	_set_dice_count(DEFAULT_DICE_COUNT)

	# Build the multiplayer chat + roster panel (hidden until a session is active).
	_build_chat_panel()

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
	network_manager.command_received.connect(_on_network_command)
	network_manager.peer_version_validated.connect(_on_peer_version_validated)
	network_manager.version_rejected.connect(_on_version_rejected)
	network_manager.peer_remapped.connect(_on_peer_remapped)
	network_manager.slot_table_synced.connect(_on_slot_table_synced)
	network_manager.session_busy_changed.connect(_on_session_busy_changed)

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
	network_manager.remote_dice_composition.connect(_on_remote_dice_composition)
	network_manager.remote_dice_color_tag.connect(_on_remote_dice_color_tag)
	network_manager.remote_player_name_updated.connect(_on_remote_player_name_updated)
	network_manager.remote_chat_message.connect(_on_remote_chat_message)
	network_manager.remote_table_settings_changed.connect(_on_remote_table_settings_changed)
	# Deployment ready-sync: the host's authoritative deployment->playing transition + the ready tally.
	network_manager.remote_game_phase_changed.connect(_on_remote_game_phase_changed)
	network_manager.ready_state_changed.connect(_on_ready_state_changed)
	network_manager.remote_army_header_received.connect(_on_remote_army_header)
	network_manager.remote_army_unit_received.connect(_on_remote_army_unit)
	network_manager.remote_army_complete_received.connect(_on_remote_army_complete)
	network_manager.remote_sort_table_received.connect(_on_remote_sort_table)
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
	internet_lobby.relay_reconnected.connect(_on_guest_reconnected)
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

	# Casual sandbox terrain shelf (free 3D-table terrain placement). The legacy TTS
	# terrain browser it superseded has been removed.
	_setup_sandbox_shelf()

	# Initialize table with default size (6x4 feet = 72x48 inches, landscape)
	# Long side (72") faces the viewer (X-axis), short side (48") is depth (Z-axis)
	table.setup_table(DEFAULT_TABLE_SIZE_FEET)
	_adjust_camera_for_table_size(DEFAULT_TABLE_SIZE_FEET)

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
	opr_army_manager.network_manager = network_manager
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
	# Per-unit spawn progress drives the second half of the army loading bar.
	opr_army_manager.spawn_progress.connect(_on_army_spawn_progress)
	# Game phase (deployment -> playing): one seam for the trail-chalk gate + the Start-Game/Ready UI.
	opr_army_manager.game_phase_changed.connect(_on_game_phase_changed)

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

	# The old detail UnitCard is RETIRED (bus 033): the dock's presented card now carries its rules/spell
	# hover tooltips + spell-range ring, so there is no Info button and no separate detail card. The
	# UnitCard script is kept only for its unit test; `unit_card` stays null.

	# Bottom-edge unit-card dock (whole-army overview + quick selector + the presented focus card).
	unit_dock = UnitDock.new()
	$UI/HUD.add_child(unit_dock)
	unit_dock.setup(opr_army_manager, object_manager, network_manager, camera_pivot, null)

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

	# Start-Game / Ready button (deployment -> playing gate)
	_init_game_phase_ui()

	# Host tools: the free-move toggle (lift the ownership lock — community feedback for solo play).
	_init_host_tools_ui()

	# Room-code display (maintainer): the code must stay visible for the whole session — players could
	# not rejoin because it was shown only once and every status update overwrote it.
	_init_room_code_display()

	# Initialize Radial Menu
	_init_radial_menu()

	# Set save_manager references for terrain/layout and marker restoration
	save_manager.map_layout_editor = map_layout_editor
	save_manager.terrain_overlay = terrain_overlay
	save_manager.radial_menu_controller = radial_menu_controller

	# Battle Log — after the managers + radial controller exist, wire the collector to the central seams.
	_setup_battle_log()

	# The intro is started AFTER the table size is chosen (on dialog confirm, see below),
	# so the size chooser never overlaps the cinematic. Loaded/joined games skip the
	# chooser and start the intro directly.

	# Check if a saved battle should be loaded (from startup menu)
	var pending_load := ProjectSettings.get_setting("niemandsland/pending_load_path", "") as String
	if not pending_load.is_empty():
		ProjectSettings.set_setting("niemandsland/pending_load_path", "")
		call_deferred("_load_pending_battle", pending_load)

	# Resolve the local player name: the startup-menu dialog passes it through, but
	# the in-game NetworkPanel Host/Join path does not, so fall back to the saved
	# profile. Empty stays empty -> the "Player N" display fallback.
	_local_player_name = PlayerIdentity.sanitize(ProjectSettings.get_setting("niemandsland/player_name", ""))
	if _local_player_name.is_empty():
		_local_player_name = PlayerIdentity.load_saved_name()

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
	# data, so they skip the chooser.
	var joining_client: bool = pending_internet and not ProjectSettings.get_setting("niemandsland/internet_is_host", false)
	# Headless MP test harness (test/mp/): skip the interactive table-size chooser AND the
	# cinematic intro and drop straight onto a live, RPC-capable table. Inert in normal play.
	var harness_mode: bool = ProjectSettings.get_setting("niemandsland/harness_mode", false)
	if harness_mode:
		if not joining_client:
			_set_table_size(DEFAULT_TABLE_SIZE_FEET)
		call_deferred("_on_intro_finished")
	elif pending_load.is_empty() and not joining_client:
		# Choose the table size FIRST on a black backdrop, then dissolve into the intro —
		# the chooser must never overlap the cinematic. UI stays hidden until the intro ends.
		$UI.visible = false
		_show_prompt_black()
		call_deferred("_prompt_table_size")
	else:
		# Loaded battle / joining client: size comes from the saved/host data, so there is
		# no chooser — go straight into the intro.
		_start_cinematic_intro()
	# Our own black backdrop (chooser prompt or intro) is up now — fade out the menu's
	# transition loading overlay so the hand-off stays black, never grey.
	_dismiss_transition_overlay()


## Fade out + free the menu->game loading overlay (added to the SceneTree root by
## startup_menu so it survives the scene swap). No-op if there is none.
func _dismiss_transition_overlay() -> void:
	for node in get_tree().get_nodes_in_group("transition_overlay"):
		if node.has_method("fade_and_free"):
			node.fade_and_free()


## F12 in-game: grab the current view + bundle an anonymised report (recent log + this
## screenshot) into a zip on the Desktop. Player names / room code / OS username are scrubbed.
## The natural capture for visual glitches (a mini clipping terrain, wrong scale, a misplaced
## model) that raise no error and so never reach the log on their own.
func _capture_bug_report() -> void:
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var tex: ViewportTexture = get_viewport().get_texture()
	var image: Image = tex.get_image() if tex else null
	if image != null and image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)  # PNG-safe (the viewport may be an HDR format)
	var names: Array = network_manager.player_names.values() if network_manager else []
	var room: String = internet_lobby.room_code if internet_lobby else ""
	var path: String = DiagnosticsReporter.export_report_with_screenshot(stamp, image, names, room)
	if path.is_empty():
		_show_toast("⚠ Bug report could not be saved")
	else:
		_show_toast("📸 Bug report saved to your Desktop: %s" % path.get_file())


## Brief, non-blocking on-screen message that auto-fades (there was no toast system before).
func _show_toast(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 48)
	$UI.add_child(label)
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(label, "modulate:a", 0.0, 0.7)
	tw.tween_callback(label.queue_free)


## A remote peer started/finished loading. While busy, show a persistent non-blocking banner
## ("Waiting for <player> to finish loading…") and the object move/edit gate is active (handled
## in object_manager / _unhandled_key_input). Camera/pan/zoom/chat stay usable throughout.
func _on_session_busy_changed(busy: bool) -> void:
	if busy:
		_show_peer_busy_banner()
	else:
		_hide_peer_busy_banner()


## The display name of the (first) remote peer that is currently loading, for the banner text.
func _busy_peer_display_name() -> String:
	if network_manager == null:
		return "another player"
	for peer_id: int in network_manager.busy_remote_peers:
		return _peer_display_name(peer_id)
	return "another player"


## Show (or refresh) the persistent "waiting for load" banner at the top of the screen.
func _show_peer_busy_banner() -> void:
	var text := "Waiting for %s to finish loading…" % _busy_peer_display_name()
	if is_instance_valid(_peer_busy_banner):
		_peer_busy_banner.text = text
		return
	_peer_busy_banner = Label.new()
	_peer_busy_banner.name = "PeerBusyBanner"
	_peer_busy_banner.text = text
	_peer_busy_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never blocks clicks/camera
	_peer_busy_banner.add_theme_font_size_override("font_size", 18)
	_peer_busy_banner.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_peer_busy_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_peer_busy_banner.add_theme_constant_override("outline_size", 4)
	_peer_busy_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	$UI.add_child(_peer_busy_banner)


## Remove the "waiting for load" banner (the remote peer finished / disconnected).
func _hide_peer_busy_banner() -> void:
	if is_instance_valid(_peer_busy_banner):
		_peer_busy_banner.queue_free()
	_peer_busy_banner = null


# --- Low-FPS instability advisory (multiplayer only) ---
# A sustained low framerate degrades heartbeat cadence and backs up the send queue — a known
# cause of online instability. When it persists during a live session, advise the player ONCE
# to lower Graphics Quality (show, don't decide: a one-click action, never auto-applied).
const FPS_ADVISORY_THRESHOLD := 18.0
const FPS_ADVISORY_SUSTAIN_MS := 8000
var _fps_advised := false
var _fps_low_since_ms := 0


func _check_fps_advisory() -> void:
	if _fps_advised or not network_manager or not network_manager.is_multiplayer_active():
		return
	var fps := Engine.get_frames_per_second()
	var now := Time.get_ticks_msec()
	if fps > 0.0 and fps < FPS_ADVISORY_THRESHOLD:
		if _fps_low_since_ms == 0:
			_fps_low_since_ms = now
		elif now - _fps_low_since_ms >= FPS_ADVISORY_SUSTAIN_MS:
			_fps_advised = true
			_show_fps_advisory()
	else:
		_fps_low_since_ms = 0


## One-shot, non-blocking banner: warns that low FPS may be destabilising the online connection
## and offers a one-click drop to the next-lower Graphics Quality tier.
func _show_fps_advisory() -> void:
	print("[FPS] low-framerate advisory shown")  # parseable signal for the MP soak harness
	var panel := PanelContainer.new()
	panel.name = "FpsAdvisory"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 90)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var label := Label.new()
	label.text = "Low framerate may be destabilising your online connection."
	row.add_child(label)
	var lower := Button.new()
	lower.text = "Lower Graphics Quality"
	lower.pressed.connect(_on_fps_advisory_lower.bind(panel))
	row.add_child(lower)
	var dismiss := Button.new()
	dismiss.text = "Dismiss"
	dismiss.pressed.connect(_free_if_valid.bind(panel))
	row.add_child(dismiss)
	$UI.add_child(panel)
	var t := create_tween()
	t.tween_interval(20.0)
	t.tween_callback(_free_if_valid.bind(panel))


func _on_fps_advisory_lower(panel: Node) -> void:
	var tier: int = GraphicsSettings.current_preset
	GraphicsSettings.apply_preset(maxi(0, tier - 1))
	_show_toast("Graphics Quality lowered to %s" % GraphicsSettings.get_current_preset_name())
	_free_if_valid(panel)


func _free_if_valid(n: Node) -> void:
	if is_instance_valid(n):
		n.queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	# F12: capture a bug report (current view screenshot + scrubbed log) to the Desktop,
	# regardless of focus, so an in-game visual glitch ships WITH the report.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		_capture_bug_report()
		get_viewport().set_input_as_handled()
		return
	# While a text field (e.g. the chat input) is focused, no game shortcut may
	# fire — especially Delete/Backspace (deletes objects) and the number keys.
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	# Enter focuses the chat input during a live session (Esc inside it returns).
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER] \
			and _chat_panel and _chat_panel.visible and _chat_input:
		_chat_input.grab_focus()
		get_viewport().set_input_as_handled()
		return
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

		# While a remote peer is loading, block object move/edit shortcuts (arrange, copy/paste,
		# duplicate, delete, lock, group-rotate, undo/redo) — but leave the non-edit panels
		# (F6 lighting print, F7 settings) reachable below. Camera/pan/zoom/chat are unaffected.
		var edits_locked: bool = network_manager != null and network_manager.is_any_remote_peer_busy()

		# Arrangement keys (1-9) - arrange selected in N rows, centred on the unit's current centre
		if edits_locked and event.keycode in _OBJECT_EDIT_KEYS:
			get_viewport().set_input_as_handled()  # swallow the edit key so it can't act
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var rows = event.keycode - KEY_0
			object_manager.arrange_selected_in_rows(rows)
			get_viewport().set_input_as_handled()
		# Arrow formation (Shift+A), centred on the unit's current centre
		elif event.keycode == KEY_A and event.shift_pressed and not event.ctrl_pressed:
			object_manager.arrange_selected_arrow()
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
		# Toggle 45° arc quadrants on the SELECTED regiment tray(s) only (F key) -
		# facing display aid (AoF:R v3.5.1 p.5, no rule). Showing only the selection
		# keeps the table uncluttered (was: toggle every regiment at once).
		elif event.keycode == KEY_F and not event.ctrl_pressed and not event.shift_pressed:
			if opr_army_manager:
				opr_army_manager.toggle_selected_regiment_arcs(object_manager.get_selected_objects())
			get_viewport().set_input_as_handled()
		# Cycle regiment frontage (Shift+F) - reform to the next width in the cycle
		# (5 -> 4 -> 3 -> 2 -> 1 -> 5). AoF:R v3.5.1 p.6 "Unit Formations". Only
		# selected RegimentTray blocks are affected; loose models are ignored.
		elif event.keycode == KEY_F and event.shift_pressed and not event.ctrl_pressed:
			if opr_army_manager:
				opr_army_manager.cycle_selected_regiment_frontage(object_manager.get_selected_objects())
			get_viewport().set_input_as_handled()
		# Rotate selected group around first object (Shift+R) - continuous rotation
		elif event.keycode == KEY_R and event.shift_pressed:
			if not _is_group_rotating:
				object_manager.begin_rotation_capture()
			_is_group_rotating = true
			get_viewport().set_input_as_handled()
		# Snap selected regiment trays to the nearest 90° facing (Ctrl+R). AoF:R
		# v3.5.1 p.8 "Pivoting" — the four cardinal facings are the natural snap
		# targets (Hold may pivot up to 180°, Move actions up to 90°). The player
		# decides whether the snap is a legal pivot; this is a quick-alignment aid.
		elif event.keycode == KEY_R and event.ctrl_pressed and not event.shift_pressed:
			object_manager.begin_rotation_capture()
			var snapped: int = 0
			for obj in object_manager.get_selected_objects():
				if obj is RegimentTray and is_instance_valid(obj):
					obj.rotation.y = RegimentTray.nearest_quarter_turn(obj.rotation.y)
					snapped += 1
			object_manager.commit_rotation_capture()
			if snapped > 0:
				AudioManager.play_sfx(AudioManager.SFXType.MODEL_PLACE)
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
		# Lighting moods are chosen through the ATMOSPHERE section in Settings (F7) only;
		# the old F1-F5 standalone lighting presets were a parallel system and removed.
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


## Replace the HUD shortcuts label's first line with "Niemandsland v<config/version>", so the
## displayed version is derived from the single source of truth and never needs a manual edit.
func _apply_version_to_info_label() -> void:
	var info := get_node_or_null("UI/HUD/InfoLabel") as Label
	if info == null:
		return
	var version := str(ProjectSettings.get_setting("application/config/version", "?"))
	var lines := info.text.split("\n")
	if lines.is_empty():
		return
	lines[0] = "Niemandsland v%s" % version
	info.text = "\n".join(lines)


func _process(delta: float) -> void:
	_check_fps_advisory()
	# Handle continuous group rotation (Shift+R held; add Ctrl to reverse).
	# Regiment movement-tray blocks rotate by MOUSE control (cursor-follow), not a
	# continuous spin — object_manager._rotate_regiments_to_cursor handles that path.
	if _is_group_rotating:
		if object_manager.is_selection_regiment_only():
			object_manager.step_regiment_cursor_rotation(delta)
		else:
			var group_rotation_dir := -1.0 if Input.is_key_pressed(KEY_CTRL) else 1.0
			var rotation_amount = GROUP_ROTATION_SPEED * delta * group_rotation_dir
			object_manager.rotate_selected_group(rotation_amount)
			# Live cumulative-degrees readout above the pivot object.
			object_manager.update_rotation_label(rotation_amount)

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
	_clear_dice_log()
	_update_round_button()  # clear_all_objects() resets the round to 1


func _on_sort_table() -> void:
	_show_action_confirm(
		"Sort Table",
		"Sort the whole table?\nEvery unit is reset to its import state and all models return to their starting positions.",
		"Sort Table", _do_sort_table)


func _do_sort_table() -> void:
	object_manager.sort_table()


## A remote peer ran Sort Table — re-run the reset locally WITHOUT re-broadcasting (no echo loop).
func _on_remote_sort_table() -> void:
	object_manager.sort_table(false)


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
	# Round advance ends every activation — the painted move trails sweep clean.
	if move_trails:
		move_trails.on_round_advance()
	if network_manager:
		network_manager.broadcast_round_advance()


## A remote peer advanced the round (the RPC already advanced our state).
func _on_remote_round_advanced() -> void:
	_refresh_round_visuals()
	if move_trails:
		move_trails.on_round_advance()


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
	for mode: int in _reroll_buttons:
		(_reroll_buttons[mode] as Button).disabled = true
	AudioManager.play_sfx(AudioManager.SFXType.DICE_ROLL)


func _on_roller_finished(_total: int) -> void:
	roll_button.text = "Roll"
	roll_button.disabled = false
	AudioManager.play_sfx(AudioManager.SFXType.DICE_IMPACT)

	var faces: Array[int] = _faces_in_order(dice_roller_control.per_dice_result())
	# Per-die colour tags ride alongside the faces so the readouts can group by colour
	# (issue #77). For a remote roll the tray was already retagged via show_faces().
	var color_tags: Array[int] = dice_roller_control.get_color_tags()
	_last_faces = faces
	_last_color_tags = color_tags
	_last_roll_local = not _is_showing_remote_roll
	# Always update the success column for the most recent roll (local or remote);
	# remote rolls are evaluated under the SENDER's target/modifier context.
	var context: Dictionary = _remote_roll_context if _is_showing_remote_roll else _current_roll_context()
	_populate_current_roll_column(faces, context)
	_update_reroll_buttons()

	# Skip logging/broadcast when showing a remote player's roll: the remote
	# handler already logged it, and re-broadcasting would cause a ping-pong loop.
	if _is_showing_remote_roll:
		_is_showing_remote_roll = false
		return

	_add_dice_log_entry("You", faces, context, color_tags)

	# Broadcast dice roll (faces + evaluation context + per-die colour tags) to remote players,
	# so the mirrored result keeps the sender's colours.
	if network_manager.is_multiplayer_active():
		network_manager.broadcast_dice_roll(faces, context, dice_roller_control.get_color_tags())

	_pending_reroll_mode = DiceRules.REROLL_NONE
	_pending_reroll_count = 0


## Face values of a tray result in stable die order ("die_0".."die_N" keys).
func _faces_in_order(per_dice: Dictionary) -> Array[int]:
	var faces: Array[int] = []
	for i: int in per_dice.size():
		faces.append(int(per_dice.get("die_%d" % i, 1)))
	return faces


## Roll-context Dictionary (DiceRules.CTX_* keys) describing the local success
## selectors and any pending reroll — attached to the success column, the dice
## log and the multiplayer broadcast so all clients render the same evaluation.
func _current_roll_context() -> Dictionary:
	return {
		DiceRules.CTX_TARGET: _success_target,
		DiceRules.CTX_MODIFIER: _success_modifier,
		DiceRules.CTX_REROLL_MODE: _pending_reroll_mode,
		DiceRules.CTX_REROLL_COUNT: _pending_reroll_count,
	}


## Builds the "Movement" cap row above the dice interface: pick Off / Advance / Rush-Charge and
## the selected model/unit can then only be dragged that far (enforced in ObjectManager).
func _build_movement_cap_row() -> void:
	var row := HBoxContainer.new()
	row.name = "MovementCapRow"
	row.add_theme_constant_override("separation", 4)

	var label := Label.new()
	label.text = "Movement:"
	label.add_theme_font_size_override("font_size", DICE_CAPTION_FONT_SIZE)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	_movement_cap_buttons.clear()
	var specs := [
		[ObjectManager.MovementCap.OFF, "Off"],
		[ObjectManager.MovementCap.ADVANCE, "Advance"],
		[ObjectManager.MovementCap.RUSH, "Rush/Charge"],
	]
	for spec in specs:
		var btn := Button.new()
		btn.text = spec[1]
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, DICE_BUTTON_HEIGHT)
		btn.pressed.connect(_on_movement_cap_pressed.bind(int(spec[0])))
		row.add_child(btn)
		_movement_cap_buttons[int(spec[0])] = btn

	_dice_vbox.add_child(row)
	_dice_vbox.move_child(row, 0)  # above the dice-roller title
	_update_movement_cap_display()


func _on_movement_cap_pressed(mode: int) -> void:
	if object_manager and object_manager.has_method("set_movement_cap"):
		object_manager.set_movement_cap(mode)
	_update_movement_cap_display()


## Highlight the active movement-cap button.
func _update_movement_cap_display() -> void:
	var active: int = object_manager.get("_movement_cap") if object_manager else ObjectManager.MovementCap.OFF
	for mode in _movement_cap_buttons:
		(_movement_cap_buttons[mode] as Button).modulate = ACTIVE_DICE_BUTTON_TINT if mode == active else Color.WHITE


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
		btn.custom_minimum_size = Vector2(0, DICE_BUTTON_HEIGHT)
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
	btn.custom_minimum_size = Vector2(0, DICE_BUTTON_HEIGHT)
	btn.pressed.connect(_on_dice_delta_pressed.bind(delta))
	return btn


func _on_dice_preset_pressed(count: int) -> void:
	_set_dice_count(count)


func _on_dice_delta_pressed(delta: int) -> void:
	_set_dice_count(_dice_count + delta)


## Sets the dice count (clamped), rebuilds the dice set and refreshes the display. Changing the
## count respawns fresh (untagged) dice, so the cup is broadcast as count + the now-empty tags;
## the opponent's tray mirrors the same composition live. Suppressed while mirroring a peer.
func _set_dice_count(count: int) -> void:
	_dice_count = clampi(count, MIN_DICE, MAX_DICE)
	_update_dice_set(_dice_count)
	_update_dice_count_display()
	if not _is_mirroring_dice and network_manager.is_multiplayer_active():
		network_manager.broadcast_dice_composition(_dice_count, dice_roller_control.get_color_tags())


## Updates the big count label and highlights the matching preset button.
func _update_dice_count_display() -> void:
	if _dice_count_value_label:
		_dice_count_value_label.text = str(_dice_count)
	for i: int in _dice_preset_buttons.size():
		var is_active: bool = (i + 1) == _dice_count
		_dice_preset_buttons[i].modulate = ACTIVE_DICE_BUTTON_TINT if is_active else Color.WHITE


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


## Builds the success-evaluation controls — a target row ("vs" –/2+..6+) and a
## modifier stepper — inserted directly above the "In box" label. Display-only
## aid: the tool counts successes, the players apply the rules (OPR GF/AoF Core
## Rules v3.5.1, p.1 "Quality Tests" / "Shooting").
func _build_success_controls() -> void:
	var section := VBoxContainer.new()
	section.name = "SuccessControls"
	section.add_theme_constant_override("separation", 4)

	# Target row: no-target ("–") plus 2+..6+.
	var target_row := HBoxContainer.new()
	target_row.add_theme_constant_override("separation", 2)
	target_row.add_child(_make_dice_caption("Success"))
	_target_buttons.clear()
	var targets: Array[int] = [DiceRules.TARGET_NONE]
	for target: int in range(DiceRules.TARGET_MIN, DiceRules.TARGET_MAX + 1):
		targets.append(target)
	for target: int in targets:
		var btn := _make_dice_option_button("–" if target == DiceRules.TARGET_NONE else "%d+" % target)
		btn.tooltip_text = "No success counting" if target == DiceRules.TARGET_NONE \
			else "Count rolls of %d+ as successes (OPR Quality/Defense tests)" % target
		btn.pressed.connect(_on_success_target_pressed.bind(target))
		target_row.add_child(btn)
		_target_buttons.append(btn)
	section.add_child(target_row)

	# Modifier stepper. OPR has no modifier cap; natural 6/1 is the only valve
	# (OPR GF/AoF Core Rules v3.5.1, p.1 "Modifiers").
	var modifier_row := HBoxContainer.new()
	modifier_row.add_theme_constant_override("separation", 2)
	modifier_row.add_child(_make_dice_caption("Modifier"))
	var minus := _make_dice_option_button("-")
	minus.pressed.connect(_on_modifier_delta_pressed.bind(-1))
	modifier_row.add_child(minus)
	_modifier_value_label = Label.new()
	_modifier_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modifier_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_modifier_value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modifier_value_label.custom_minimum_size = Vector2(MODIFIER_VALUE_MIN_WIDTH, 0)
	_modifier_value_label.tooltip_text = "Applied to every die. Natural 6 always succeeds," \
		+ " natural 1 always fails (OPR Core Rules v3.5.1)."
	modifier_row.add_child(_modifier_value_label)
	var plus := _make_dice_option_button("+")
	plus.pressed.connect(_on_modifier_delta_pressed.bind(1))
	modifier_row.add_child(plus)
	section.add_child(modifier_row)

	_dice_vbox.add_child(section)
	_dice_vbox.move_child(section, current_dice_label.get_index())
	_update_success_controls_display()


## Builds the reroll row (Fails / 1s / 6s / All) right below the Roll buttons.
## Buttons enable only when the matching dice exist in the last LOCAL roll.
func _build_reroll_row() -> void:
	var row := HBoxContainer.new()
	row.name = "RerollRow"
	row.add_theme_constant_override("separation", 2)
	row.add_child(_make_dice_caption("Re-roll"))

	var options: Array = [
		[DiceRules.RerollMode.FAILURES, "Fails", "Re-roll every die that failed the success target"],
		[DiceRules.RerollMode.ONES, "1s", "Re-roll all natural 1s"],
		[DiceRules.RerollMode.SIXES, "6s",
			"Re-roll all natural 6s (OPR \"Bane\", v3.5.1: the target must re-roll unmodified Defense rolls of 6)"],
		[DiceRules.RerollMode.ALL, "All", "Re-roll every die"],
	]
	_reroll_buttons.clear()
	for option: Array in options:
		var mode: int = option[0]
		var btn := _make_dice_option_button(option[1])
		btn.tooltip_text = option[2]
		btn.disabled = true
		btn.pressed.connect(_on_reroll_pressed.bind(mode))
		row.add_child(btn)
		_reroll_buttons[mode] = btn

	_dice_vbox.add_child(row)
	_dice_vbox.move_child(row, roll_button.get_parent().get_index() + 1)


## Small muted caption label for the dice option rows.
func _make_dice_caption(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", DICE_CAPTION_FONT_SIZE)
	lbl.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
	lbl.custom_minimum_size = Vector2(DICE_CAPTION_MIN_WIDTH, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl


## One equally-sized, focus-less option button for the dice panel rows.
func _make_dice_option_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, DICE_BUTTON_HEIGHT)
	return btn


func _on_success_target_pressed(target: int) -> void:
	_success_target = target
	_update_success_controls_display()
	_refresh_roll_evaluation()


func _on_modifier_delta_pressed(delta: int) -> void:
	_success_modifier = clampi(_success_modifier + delta, DiceRules.MODIFIER_MIN, DiceRules.MODIFIER_MAX)
	_update_success_controls_display()
	_refresh_roll_evaluation()


## Highlights the active target button and renders the modifier value.
func _update_success_controls_display() -> void:
	for i: int in _target_buttons.size():
		# Button order matches [TARGET_NONE, TARGET_MIN..TARGET_MAX].
		var button_target: int = DiceRules.TARGET_NONE if i == 0 else DiceRules.TARGET_MIN + i - 1
		_target_buttons[i].modulate = ACTIVE_DICE_BUTTON_TINT if button_target == _success_target else Color.WHITE
	if _modifier_value_label:
		_modifier_value_label.text = "±0" if _success_modifier == 0 else "%+d" % _success_modifier


## Re-renders the success column + reroll buttons after a selector change. The
## last LOCAL roll is re-evaluated live under the new target/modifier; a remote
## roll keeps its sender's context.
func _refresh_roll_evaluation() -> void:
	if not _last_faces.is_empty():
		var context: Dictionary = _current_roll_context() if _last_roll_local else _remote_roll_context
		_populate_current_roll_column(_last_faces, context)
	_update_reroll_buttons()


func _on_reroll_pressed(mode: int) -> void:
	if _last_faces.is_empty() or not _last_roll_local:
		return
	var indices: Array[int] = DiceRules.reroll_indices(_last_faces, mode, _success_target, _success_modifier)
	if indices.is_empty():
		return
	_pending_reroll_mode = mode
	_pending_reroll_count = indices.size()
	# Deliberately NOT calling _update_dice_set here: the dice_count/roller_size
	# setters rebuild the tray and would wipe the kept dice.
	dice_roller_control.reroll(indices)


## Enables exactly the reroll buttons that would re-toss at least one die of
## the last LOCAL roll (remote rolls are not ours to reroll).
func _update_reroll_buttons() -> void:
	for mode: int in _reroll_buttons:
		var btn: Button = _reroll_buttons[mode]
		btn.disabled = not _last_roll_local or _last_faces.is_empty() \
			or DiceRules.reroll_indices(_last_faces, mode, _success_target, _success_modifier).is_empty()


## Battle Log (M1): create the collector + its top-left HUD panel and wire it to the CENTRAL seams —
## one source of truth, local + remote, no call-site sprinkling. Solo-AI (a separate branch) emits its
## own lines into battle_log.on_unit_moved(..., ai=true) / on_unit_activated(..., ai=true) later.
func _setup_battle_log() -> void:
	battle_log = BattleLog.new()
	battle_log.name = "BattleLog"
	add_child(battle_log)
	if opr_army_manager != null:
		battle_log.current_round = opr_army_manager.current_round
	battle_log_panel = BattleLogPanel.new()
	$UI/HUD.add_child(battle_log_panel)
	# Top-CENTRE, hugging the top edge; collapsed to a tab by default, expands downward (maintainer req).
	battle_log_panel.anchor_left = 0.5
	battle_log_panel.anchor_right = 0.5
	battle_log_panel.anchor_top = 0.0
	battle_log_panel.anchor_bottom = 0.0
	battle_log_panel.offset_left = -170.0
	battle_log_panel.offset_right = 170.0
	battle_log_panel.offset_top = 6.0
	battle_log_panel.offset_bottom = 6.0
	battle_log_panel.grow_vertical = Control.GROW_DIRECTION_END
	battle_log_panel.bind(battle_log)
	battle_log.on_game_started()
	# Central seams (fewest hooks that cover local + remote):
	if opr_army_manager != null:
		opr_army_manager.round_advanced.connect(battle_log.on_round_advanced)
		opr_army_manager.loose_model_dead_changed.connect(_on_battle_log_dead)
		opr_army_manager.regiment_wounds_applied.connect(_on_battle_log_regiment_wounds)
	if object_manager != null:
		object_manager.selection_dropped.connect(_on_battle_log_dropped)
	if network_manager != null:
		if network_manager.has_signal("remote_move_log_received"):
			network_manager.remote_move_log_received.connect(_log_move_summaries)
		if network_manager.has_signal("remote_round_advanced"):
			network_manager.remote_round_advanced.connect(
				func() -> void: battle_log.on_round_advanced(opr_army_manager.current_round))
		if network_manager.has_signal("remote_activation_updated"):
			network_manager.remote_activation_updated.connect(func(gu) -> void: _log_battle_activation(gu, true))
		# NOTE: no remote_dice_rolled hook here — remote rolls reach _add_dice_log_entry (with the peer's
		# display name) via _on_remote_dice_rolled, which feeds _log_battle_dice; a second hook double-logged.
	if radial_menu_controller != null and radial_menu_controller.has_signal("unit_activated"):
		radial_menu_controller.unit_activated.connect(func(gu) -> void: _log_battle_activation(gu, false))


func _log_battle_activation(gu, _remote: bool) -> void:
	if battle_log == null or gu == null:
		return
	var pid: int = int(gu.unit_properties.get("player_id", 0))
	var is_ai: bool = pid == 2   # M1: player 2 is the Solo-AI slot
	battle_log.on_unit_activated(gu.get_name(), ("AI" if is_ai else "you"), is_ai)


func _on_battle_log_dead(node, dead: bool) -> void:
	if battle_log == null:
		return
	# Resolve the model's unit for a real line ("X loses a model (7/10)" / "X destroyed") instead of the
	# old generic "a unit was wiped out" that fired for EVERY single model kill.
	var gu: GameUnit = node.get_meta("game_unit", null) if (node != null and node.has_meta("game_unit")) else null
	if gu == null:
		battle_log.log_event(BattleLog.Category.COMBAT if dead else BattleLog.Category.GENERAL,
			"A model was killed" if dead else "A model returns")
		return
	var alive: int = gu.get_alive_count()
	var total: int = gu.models.size()
	if dead:
		if alive == 0:
			battle_log.on_unit_destroyed(gu.get_name())
		else:
			battle_log.log_event(BattleLog.Category.COMBAT, "%s loses a model (%d/%d)" % [gu.get_name(), alive, total])
	else:
		battle_log.on_unit_revived(gu.get_name())


## Pooled regiment wounds (single seam in apply_regiment_wounds — covers radial, card and remote edits).
func _on_battle_log_regiment_wounds(unit_name: String, delta: int, remaining: int, pool: int) -> void:
	if battle_log == null:
		return
	if delta > 0:
		battle_log.on_wounds(unit_name, delta, remaining, pool)
	else:
		battle_log.log_event(BattleLog.Category.GENERAL, "%s heals %d wound%s (%d/%d)" % [unit_name, -delta, ("" if delta == -1 else "s"), remaining, pool])


## A drag moved objects: log ONE line per unit — the whole unit ("X moves 5\"") or, when only part of it
## moved, which share ("X: 2 of 10 models move 3\"") — so multi-unit drags and single-model nudges read
## correctly (maintainer). A regiment moves as its tray = always the whole unit. Terrain/props stay
## unlogged. The seam's from→to coordinates are not displayed (noise) — they exist for the future
## replay journal (ROADMAP: Game replay).
func _on_battle_log_dropped(moves: Array) -> void:
	if battle_log == null:
		return
	var per_unit := {}   # unit name -> {count, max_in, alive, whole}
	for mv in moves:
		var node: Node3D = mv.get("node")
		var unit_name := _battle_log_unit_name(node)
		if unit_name.is_empty():
			continue
		if not per_unit.has(unit_name):
			per_unit[unit_name] = {"count": 0, "max_in": 0.0, "alive": _battle_log_unit_alive(node), "whole": false}
		var e: Dictionary = per_unit[unit_name]
		e["count"] = int(e["count"]) + 1
		# Movement distance = the ACTUAL traveled arc (the ledger's measured net path),
		# NOT crow-flight — one source of truth with the trail stamp / HUD / ruler. Falls
		# back to the straight from→to only for a mover with no recorded path.
		e["max_in"] = maxf(float(e["max_in"]), float(mv.get("arc_in", mv.get("inches", 0.0))))
		if node is RegimentTray:
			e["whole"] = true
	var summaries: Array = []
	for unit_name in per_unit:
		var e: Dictionary = per_unit[unit_name]
		summaries.append({"unit": unit_name, "count": int(e["count"]), "alive": int(e["alive"]),
			"max_in": float(e["max_in"]), "whole": bool(e["whole"])})
	_log_move_summaries(summaries)
	# The move STREAM is unreliable + continuous (drag), so the other side cannot know when a drop
	# happened — ship the finished per-unit summary reliably; every peer logs identical lines
	# (release-test finding C3: only own movements were logged).
	if network_manager != null and network_manager.is_multiplayer_active():
		network_manager.broadcast_move_log(summaries)


## Write per-unit movement summaries into the battle log — same lines for local and remote movers.
func _log_move_summaries(summaries: Array) -> void:
	if battle_log == null:
		return
	for entry in summaries:
		var e: Dictionary = entry as Dictionary
		if e == null or e.is_empty():
			continue
		var unit_name: String = str(e.get("unit", ""))
		if unit_name.is_empty():
			continue
		var alive: int = int(e.get("alive", 0))
		var count: int = int(e.get("count", 0))
		var max_in: float = float(e.get("max_in", 0.0))
		if bool(e.get("whole", false)) or count >= alive or alive <= 1:
			battle_log.on_unit_moved(unit_name, max_in)
		else:
			battle_log.log_event(BattleLog.Category.MOVEMENT,
				"%s: %d of %d models move %.0f\"" % [unit_name, count, alive, max_in])


## Path painting: a drag dropped — commit each moved model's traversed path as a visible
## trail + ledger entry (MoveTrails), and replicate the proof to the other players as
## small additive polyline messages (the host-authoritative move path is untouched).
## ONE drop_id groups everything in this drop — locally AND in the MP messages — so a
## multi-unit drop never fades its own trails on either side.
func _on_trails_dropped(moves: Array) -> void:
	if move_trails == null:
		return
	var round_num: int = opr_army_manager.current_round if opr_army_manager != null else 0
	var drop_id: int = Time.get_ticks_msec()
	var per_unit: Dictionary = {}   # unit_id -> {"owner", "name", "batch": Array}
	for mv in moves:
		var node: Node3D = mv.get("node")
		var path: PackedVector2Array = mv.get("path", PackedVector2Array())
		var radius: float = float(mv.get("radius_m", 0.0))
		if node == null or not is_instance_valid(node) or path.size() < 2 or radius <= 0.0:
			continue
		var gu: GameUnit = _trail_unit_of(node)
		if gu == null:
			continue
		var owner: int = int(gu.unit_properties.get("player_id", 0))
		var model_id: int = int(node.get_meta("network_id")) if node.has_meta("network_id") else 0
		move_trails.commit_trail(owner, gu.unit_id, gu.get_name(), model_id, path,
				radius, round_num, drop_id)
		if network_manager != null and network_manager.is_multiplayer_active():
			var entry: Dictionary = per_unit.get(gu.unit_id, {})
			if entry.is_empty():
				entry = {"owner": owner, "name": gu.get_name(), "batch": []}
				per_unit[gu.unit_id] = entry
			var batch: Array = entry["batch"]
			batch.append(model_id)
			batch.append(radius)
			batch.append(path.size())
			for p in path:
				batch.append(p.x)
				batch.append(p.y)
	for unit_id in per_unit:
		var e: Dictionary = per_unit[unit_id]
		network_manager.broadcast_move_trails(int(e["owner"]), str(unit_id),
				str(e["name"]), round_num, drop_id, e["batch"])


## The GameUnit behind a dragged battlefield piece (model node or regiment tray) — the
## trail's unit identity. Mirrors _battle_log_unit_name's resolution; null = no unit
## (terrain / dice / props — they paint no trails).
func _trail_unit_of(node: Node3D) -> GameUnit:
	if node == null or not is_instance_valid(node):
		return null
	if node.has_meta("game_unit"):
		return node.get_meta("game_unit") as GameUnit
	if node is RegimentTray and opr_army_manager != null:
		for reg in opr_army_manager.regiments.values():
			if reg != null and reg.tray == node and reg.game_unit != null:
				return reg.game_unit
	return null


## Alive model count of the unit a node belongs to (denominator for partial-move lines).
func _battle_log_unit_alive(node: Node3D) -> int:
	if node != null and node.has_meta("game_unit"):
		var gu = node.get_meta("game_unit")
		if gu != null:
			return gu.get_alive_count()
	return 1


func _battle_log_unit_name(node: Node3D) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	if node.has_meta("game_unit"):
		var gu = node.get_meta("game_unit")
		if gu != null:
			return gu.get_name()
	if node is RegimentTray and opr_army_manager != null:
		for reg in opr_army_manager.regiments.values():
			if reg != null and reg.tray == node and reg.game_unit != null:
				return reg.game_unit.get_name()
	return ""


## Battle-Log line for a roll: WHO + the face results (+ hits when a success target is set). Local and
## remote both funnel through _add_dice_log_entry, which carries the right player name ("You" locally,
## the peer's display name remotely) — so this is the single dice-log seam.
func _log_battle_dice(player_name: String, faces: Array, context: Dictionary) -> void:
	if battle_log == null or faces.is_empty():
		return
	var target: int = int(context.get(DiceRules.CTX_TARGET, DiceRules.TARGET_NONE))
	if target == DiceRules.TARGET_NONE or target <= 0:
		battle_log.on_dice_rolled(faces.size(), 0, 0, player_name, faces)
		return
	var modifier: int = int(context.get(DiceRules.CTX_MODIFIER, 0))
	battle_log.on_dice_rolled(faces.size(), DiceRules.count_successes(faces, target, modifier), target, player_name, faces)


## Adds a visual dice-roll entry to the log: a header (time, player, formula,
## reroll tag), a per-face icon strip (6 down to 1) and, when a success target
## is set, the success count.
func _add_dice_log_entry(player_name: String, faces: Array[int], context: Dictionary, tags: Array[int]) -> void:
	_log_battle_dice(player_name, faces, context)   # Battle Log: who + faces (+ hits) — local AND remote
	var target: int = context.get(DiceRules.CTX_TARGET, DiceRules.TARGET_NONE)
	var modifier: int = context.get(DiceRules.CTX_MODIFIER, 0)
	var reroll_mode: int = context.get(DiceRules.CTX_REROLL_MODE, DiceRules.REROLL_NONE)
	var time_str: String = Time.get_time_string_from_system().substr(0, 5)

	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 4)

	var formula := "%dd6" % faces.size()
	if target != DiceRules.TARGET_NONE:
		formula += " vs %d+" % target
		if modifier != 0:
			formula += " %+d" % modifier
	var head_text := "%s %s (%s)" % [time_str, player_name, formula]
	if reroll_mode != DiceRules.REROLL_NONE:
		head_text = "%s %s ↻%d %s (%s)" % [time_str, player_name,
			context.get(DiceRules.CTX_REROLL_COUNT, 0), DiceRules.reroll_mode_label(reroll_mode), formula]

	var head := Label.new()
	head.text = head_text
	head.add_theme_font_size_override("font_size", 12)
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	entry.add_child(head)

	var groups: Dictionary = _faces_grouped_by_color(faces, tags)
	var tags_present: Array[int] = _ordered_color_groups(groups.keys())
	if tags_present.size() <= 1:
		# Single colour (or all untagged): compact inline face strip, tinted if it's a tag.
		var tint := _tint_for_tag(tags_present[0] if not tags_present.is_empty() else 0)
		var counts: Dictionary = _count_faces(faces)
		for face: int in [6, 5, 4, 3, 2, 1]:
			entry.add_child(_make_success_row(face, counts.get(face, 0), DICE_LOG_ICON_SIZE,
				DiceRules.is_success(face, target, modifier), tint))
		if target != DiceRules.TARGET_NONE:
			entry.add_child(_make_log_success_tag(DiceRules.count_successes(faces, target, modifier)))
		_dice_log_vbox.add_child(entry)
	else:
		# Mixed colours: header on its own line, then ONE HORIZONTAL strip per colour stacked
		# vertically beneath it (issue #77b). The whole entry becomes a vertical block.
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 2)
		block.add_child(entry)  # the header row
		for tag: int in tags_present:
			block.add_child(_build_color_group_row(tag, groups[tag], target, modifier, DICE_LOG_ICON_SIZE))
		_dice_log_vbox.add_child(block)

	# Auto-scroll to the newest entry. Wait TWO frames: a multi-line (multi-colour) entry needs a
	# second layout pass before the scroll container's max_value reflects its full height, otherwise
	# the newest roll sometimes lands just below the fold (the reported "not live-scrolled" case).
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_dice_log_scroll):
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

	_populate_current_roll_column([], {})


## Fills the current-roll column with one row per face (6 down to 1); faces with
## no hits are dimmed so the actual results stand out. With a success target in
## the context, success faces are tinted and a success-count line is appended.
func _populate_current_roll_column(faces: Array[int], context: Dictionary) -> void:
	if not _current_roll_column:
		return
	for child: Node in _current_roll_column.get_children():
		child.queue_free()
	var target: int = context.get(DiceRules.CTX_TARGET, DiceRules.TARGET_NONE)
	var modifier: int = context.get(DiceRules.CTX_MODIFIER, 0)
	var groups: Dictionary = _faces_grouped_by_color(faces, _last_color_tags)
	var tags_present: Array[int] = _ordered_color_groups(groups.keys())
	if tags_present.size() <= 1:
		# Single colour (or all untagged): compact single-column readout, tinted if it's a tag.
		var tint := _tint_for_tag(tags_present[0] if not tags_present.is_empty() else 0)
		var counts: Dictionary = _count_faces(faces)
		for face: int in [6, 5, 4, 3, 2, 1]:
			_current_roll_column.add_child(_make_success_row(face, counts.get(face, 0),
				CURRENT_ROLL_ICON_SIZE, DiceRules.is_success(face, target, modifier), tint))
		if target != DiceRules.TARGET_NONE:
			_current_roll_column.add_child(_make_success_summary(
				DiceRules.count_successes(faces, target, modifier)))
		return
	# Mixed colours: one sub-column per colour, side by side (issue #77).
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for tag: int in tags_present:
		row.add_child(_build_color_group_column(tag, groups[tag], target, modifier, CURRENT_ROLL_ICON_SIZE))
	_current_roll_column.add_child(row)


## One "die icon + xN" row; dimmed when the count is zero. The ×N count is shown in the die's
## colour-tag colour when `tint` is set (a tagged result), else tinted cyan when the face passes
## the active success target — so coloured dice read in their own colour (issue #77).
func _make_success_row(face: int, count: int, icon_size: int, highlight: bool, tint: Color = NO_DICE_TINT) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.modulate.a = 1.0 if count > 0 else 0.32

	var icon := DieFaceIcon.new()
	icon.face = face
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Paint the die body in its colour-tag colour (with contrast-picked pips) so the result/log
	# dice read in the same colour as the physical dice (issue #77a).
	if tint.a > 0.0:
		icon.body_color = tint
		icon.pip_color = DiceD6._pip_color_for_body(tint)
	row.add_child(icon)

	var lbl := Label.new()
	lbl.text = "×%d" % count
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", maxi(12, icon_size - 10))
	if tint.a > 0.0:
		lbl.add_theme_color_override("font_color", tint)
	elif highlight:
		lbl.add_theme_color_override("font_color", HudTokens.CYAN)
	row.add_child(lbl)
	return row


## The colour-tag tint for a result group: the die's body colour for a tagged group (1..N),
## or NO_DICE_TINT for the untagged group (0) so it keeps the neutral/cyan styling.
func _tint_for_tag(tag: int) -> Color:
	return DiceD6.body_color_for_tag(tag) if tag > 0 else NO_DICE_TINT


## Counts how many dice show each face (1-6) from an ordered face list.
func _count_faces(faces: Array[int]) -> Dictionary:
	var counts: Dictionary = {6: 0, 5: 0, 4: 0, 3: 0, 2: 0, 1: 0}
	for face: int in faces:
		if face in counts:
			counts[face] += 1
	return counts


## Groups a roll's faces by per-die colour tag (issue #77). Returns
## {tag: {"counts": {face:int}, "faces": Array[int]}}; untagged dice fall under tag 0.
## `faces[i]` pairs with `tags[i]`; a missing tag (shorter array) is treated as untagged.
func _faces_grouped_by_color(faces: Array[int], tags: Array[int]) -> Dictionary:
	var groups: Dictionary = {}
	for i: int in faces.size():
		var tag: int = int(tags[i]) if i < tags.size() else DiceD6.DEFAULT_COLOR_TAG
		if not groups.has(tag):
			var bucket_faces: Array[int] = []
			groups[tag] = {"counts": {6: 0, 5: 0, 4: 0, 3: 0, 2: 0, 1: 0}, "faces": bucket_faces}
		var face: int = faces[i]
		if face in groups[tag]["counts"]:
			groups[tag]["counts"][face] += 1
		groups[tag]["faces"].append(face)
	return groups


## Distinct colour tags present in a roll, ordered untagged-first then ascending
## (0 = untagged/free, 1 = red, 2 = blue, …) so the grouped readout reads left→right.
func _ordered_color_groups(present: Array) -> Array[int]:
	var ordered: Array[int] = []
	for t: Variant in present:
		ordered.append(int(t))
	ordered.sort()  # ascending; untagged (0) naturally lands first
	return ordered


## The "✔ N" success summary line used at the bottom of a current-roll column.
func _make_success_summary(count: int) -> Label:
	var summary := Label.new()
	summary.text = "✔ %d" % count
	summary.add_theme_font_size_override("font_size", SUCCESS_SUMMARY_FONT_SIZE)
	summary.add_theme_color_override("font_color", HudTokens.CYAN)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return summary


## The compact "✔N" success tag used inline in a dice-log entry.
func _make_log_success_tag(count: int) -> Label:
	var tag := Label.new()
	tag.text = "✔%d" % count
	tag.add_theme_font_size_override("font_size", DICE_CAPTION_FONT_SIZE)
	tag.add_theme_color_override("font_color", HudTokens.CYAN)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return tag


## A vertical readout for ONE colour group: a colour swatch header, the per-face
## rows (6→1) and, with a success target set, that group's success count. Used when
## a roll mixes colour tags so each colour reads as its own column (issue #77).
func _build_color_group_column(tag: int, group: Dictionary, target: int, modifier: int, icon_size: int) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.add_child(_make_color_swatch(tag, icon_size))
	var tint := _tint_for_tag(tag)
	var counts: Dictionary = group["counts"]
	for face: int in [6, 5, 4, 3, 2, 1]:
		col.add_child(_make_success_row(face, counts.get(face, 0), icon_size,
			DiceRules.is_success(face, target, modifier), tint))
	if target != DiceRules.TARGET_NONE:
		var group_faces: Array[int] = group["faces"]
		col.add_child(_make_success_summary(DiceRules.count_successes(group_faces, target, modifier)))
	return col


## A HORIZONTAL readout for ONE colour group, for the dice log: a leading colour swatch, the
## per-face "icon ×N" rows laid out left→right, then that group's success count. Mixed-colour log
## entries stack one of these per colour vertically (issue #77b).
func _build_color_group_row(tag: int, group: Dictionary, target: int, modifier: int, icon_size: int) -> HBoxContainer:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 4)
	strip.add_child(_make_color_swatch(tag, icon_size))
	var tint := _tint_for_tag(tag)
	var counts: Dictionary = group["counts"]
	for face: int in [6, 5, 4, 3, 2, 1]:
		strip.add_child(_make_success_row(face, counts.get(face, 0), icon_size,
			DiceRules.is_success(face, target, modifier), tint))
	if target != DiceRules.TARGET_NONE:
		var group_faces: Array[int] = group["faces"]
		strip.add_child(_make_log_success_tag(DiceRules.count_successes(group_faces, target, modifier)))
	return strip


## A small colour swatch marking which dice colour a result group belongs to.
func _make_color_swatch(tag: int, icon_size: int) -> Control:
	var swatch := ColorRect.new()
	swatch.color = DiceD6.body_color_for_tag(tag)
	swatch.custom_minimum_size = Vector2(icon_size, maxi(4, int(icon_size * 0.28)))
	swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return swatch


func _get_random_table_position() -> Vector3:
	# Table size is in feet, convert to meters for positioning
	var size_meters = table.table_size * FEET_TO_METERS  # FEET_TO_METERS
	var margin = 0.15  # Stay away from edges
	var x = randf_range(-size_meters.x / 2 + margin, size_meters.x / 2 - margin)
	var z = randf_range(-size_meters.y / 2 + margin, size_meters.y / 2 - margin)
	return Vector3(x, 0, z)  # Spawn at table surface (y=0)


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
		# Sync the biome to other players (host-authoritative, via the table-settings RPC).
		if network_manager.is_multiplayer_active():
			network_manager.broadcast_table_settings({"biome": td.selected_biome})
	var content := dialog.get_child(0) as Control
	var t := create_tween()
	if content:
		t.tween_property(content, "modulate:a", 0.0, 0.8).set_trans(Tween.TRANS_SINE)
	else:
		t.tween_interval(0.4)
	t.tween_callback(func() -> void:
		dialog.queue_free()
		# Start the intro (its own opaque black covers the screen). Keep our black backdrop
		# up a few frames longer so the hand-off stays black -> never a grey flash if the
		# intro's overlay isn't covering on the very first frame.
		_start_cinematic_intro())
	t.tween_interval(0.2)
	t.tween_callback(func() -> void:
		if is_instance_valid(_prompt_overlay):
			_prompt_overlay.queue_free()
			_prompt_overlay = null)


## Set table to specific size and clear objects
func _set_table_size(size_feet: Vector2) -> void:
	# Clear existing objects
	object_manager.clear_all_objects()

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


## Network UI handlers — the in-game Host/Join buttons open the SAME online
## relay dialogs as the startup menu (shared NetDialog chrome); the connection
## then runs through internet_lobby, exactly like a menu-launched online game.
func _on_host_pressed() -> void:
	if _net_host_popup:
		_net_host_popup.queue_free()
	_net_host_popup = NetDialog.build("HOST ONLINE GAME", "NET-01", "Start Hosting")
	var content := NetDialog.content(_net_host_popup)
	content.add_child(NetDialog.label("Player Name:"))
	_net_host_name_input = NetDialog.line_edit(PlayerIdentity.load_saved_name(), "Your name")
	_net_host_name_input.max_length = PlayerIdentity.MAX_NAME_LEN
	content.add_child(_net_host_name_input)
	content.add_child(NetDialog.label("Relay Server URL:"))
	_net_host_url_input = NetDialog.line_edit(InternetLobby.DEFAULT_RELAY_URL, "wss://niemandsland-relay.fly.dev")
	content.add_child(_net_host_url_input)
	_net_host_public_check = CheckBox.new()
	_net_host_public_check.text = "List this room publicly (Browse Online Games)"
	_net_host_public_check.focus_mode = Control.FOCUS_NONE
	content.add_child(_net_host_public_check)
	_net_host_popup.confirmed.connect(_on_net_host_confirmed)
	add_child(_net_host_popup)
	_net_host_popup.popup_centered()
	_net_host_name_input.grab_focus()


func _on_net_host_confirmed() -> void:
	var url := _net_host_url_input.text.strip_edges()
	if url.is_empty():
		url = InternetLobby.DEFAULT_RELAY_URL
	_local_player_name = PlayerIdentity.sanitize(_net_host_name_input.text)
	PlayerIdentity.save_name(_local_player_name)
	internet_lobby.host_internet_game(url, _net_host_public_check.button_pressed)


func _on_join_pressed() -> void:
	if _net_join_popup:
		_net_join_popup.queue_free()
	_net_join_popup = NetDialog.build("JOIN ONLINE GAME", "NET-02", "Join")
	var content := NetDialog.content(_net_join_popup)
	content.add_child(NetDialog.label("Player Name:"))
	_net_join_name_input = NetDialog.line_edit(PlayerIdentity.load_saved_name(), "Your name")
	_net_join_name_input.max_length = PlayerIdentity.MAX_NAME_LEN
	content.add_child(_net_join_name_input)
	content.add_child(NetDialog.label("Room Code:"))
	_net_join_code_input = NetDialog.line_edit("", "ABC-123")
	_net_join_code_input.max_length = 7  # 6 chars + optional hyphen
	content.add_child(_net_join_code_input)
	content.add_child(NetDialog.label("Relay Server URL:"))
	_net_join_url_input = NetDialog.line_edit(InternetLobby.DEFAULT_RELAY_URL, "wss://niemandsland-relay.fly.dev")
	content.add_child(_net_join_url_input)
	_net_join_popup.confirmed.connect(_on_net_join_confirmed)
	add_child(_net_join_popup)
	_net_join_popup.popup_centered()
	_net_join_code_input.grab_focus()


func _on_net_join_confirmed() -> void:
	var code := _net_join_code_input.text.strip_edges().replace("-", "").to_upper()
	if code.is_empty():
		return
	var url := _net_join_url_input.text.strip_edges()
	if url.is_empty():
		url = InternetLobby.DEFAULT_RELAY_URL
	_local_player_name = PlayerIdentity.sanitize(_net_join_name_input.text)
	PlayerIdentity.save_name(_local_player_name)
	internet_lobby.join_internet_game(code, url)


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
	_register_local_name()


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
	_rebuild_roster()


## Host: the joining peer's game version matches ours — now push full state.
## This fires after SceneMultiplayer has registered the peer, so rpc_id() works.
func _on_peer_version_validated(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	network_status_label.text = "Hosting (peer %d joined)" % peer_id
	_sync_state_to_peer(peer_id)
	# The peer is registered and validated — hand it the full name roster so it
	# immediately knows everyone already at the table (including the host).
	network_manager.push_roster_to_peer(peer_id)
	# Hand it the whole peer→slot table too, so in a 3+-player game it agrees on everyone's slot (hence
	# colour) immediately, without needing to have witnessed each incremental remap broadcast (bus 036).
	network_manager.push_slot_table_to_peer(peer_id)
	# If anyone is CURRENTLY loading, tell the late joiner so it gates + shows the banner too.
	network_manager.push_busy_state_to_peer(peer_id)
	# Hand the joining peer the current biome (host-authoritative table state — the biome
	# is not part of the serialized .nml game state, so it must be pushed separately).
	if table != null:
		network_manager.broadcast_table_settings({"biome": table.biome})
	# Late joiners also need the session's free-move state (host-operated, applies to everyone).
	if object_manager != null and object_manager.host_free_move:
		network_manager.broadcast_table_settings({"free_move": true})
	# Replay the current pinned rulers so the late-joiner sees existing measurements
	# (session-only state, not part of the .nml save).
	network_manager.sync_rulers_to_peer(peer_id)


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
	# Always clean THIS transport id's presence. A stale late close AFTER a rebind is a
	# no-op here, because _on_peer_remapped already freed the old id's avatar/cursor and
	# re-keyed presence to the new id; a genuine departure is cleaned correctly. (The
	# earlier slot-keyed guard mis-indexed slot_to_peer with a peer-id value — review MF3.)
	_cleanup_peer_presence(peer_id)
	_rebuild_roster()
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
	_set_room_code_display(code)   # permanent readout in the left bar + battle-log line
	# Host seeds its identity HERE: the host flow goes room_created -> room_code_ready and
	# never reaches _on_internet_connected, so this is where the host claims slot 1.
	if network_manager and multiplayer.is_server():
		network_manager.is_host = multiplayer.is_server()
		network_manager.seed_host_identity()
	_register_local_name()


func _on_internet_connected(peer_id: int) -> void:
	_is_reconnecting = false  # (re)connected — resume presence broadcasts (Fix A)
	# Mirror the server role onto network_manager.is_host: only the ENet host_game()
	# set it before, so every role-gated host check read false for internet sessions
	# (RC7). multiplayer.is_server() is backed by the relay peer (_my_peer_id == 1).
	if network_manager:
		network_manager.is_host = multiplayer.is_server()
	_update_network_ui(true, false)
	network_status_label.text = "Online (Peer %d)" % peer_id
	network_status_label.add_theme_color_override("font_color", Color.GREEN)
	# The guest keeps the room code visible too (it typed it once, then it was gone — no rejoin).
	if internet_lobby != null and not internet_lobby.room_code.is_empty():
		_set_room_code_display(internet_lobby.room_code)
	# Announce our version to the host; on a match the host pushes full state
	# (gated on the handshake) once SceneMultiplayer has registered the peer.
	network_manager.announce_version_to_host()
	_register_local_name()


## Registers the local player's name once a session is live: the host seeds its
## own roster entry, a guest announces its name to the host. No-op without a name
## (everyone then shows the "Player N" fallback).
func _register_local_name() -> void:
	if _local_player_name.is_empty():
		return
	if multiplayer.is_server():
		network_manager.set_host_name(_local_player_name)
	else:
		network_manager.broadcast_player_name(_local_player_name)


## Display name for a remote peer: its synced name, or the "Player N" fallback.
func _peer_display_name(peer_id: int) -> String:
	return PlayerIdentity.display_name(network_manager.player_names.get(peer_id, ""), peer_id)


# ===== Multiplayer chat + roster panel =====

## Builds the in-game chat panel (HudTokens glass + corner brackets), docked
## bottom-left. Header → connected-player roster → scrollable log → input row.
## Hidden until a multiplayer session is active.
func _build_chat_panel() -> void:
	_chat_panel = PanelContainer.new()
	_chat_panel.name = "ChatPanel"
	_chat_panel.add_theme_stylebox_override("panel", HudTokens.panel_style())
	# Docked bottom, just right of the LeftPanelScroll column (x ends at 210) and
	# left of the bottom-right DiceRollerPanel, so it overlaps neither.
	_chat_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_panel.anchor_top = 1.0
	_chat_panel.anchor_bottom = 1.0
	_chat_panel.offset_left = 220
	_chat_panel.offset_top = -310
	_chat_panel.offset_right = 560
	_chat_panel.offset_bottom = -10
	_chat_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_chat_panel.visible = false

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", HudTokens.SPACE_4)
	_chat_panel.add_child(vbox)

	vbox.add_child(HudTokens.header("CHAT", "NET-04"))

	# Connected-player roster (filled in _rebuild_roster).
	_roster_vbox = VBoxContainer.new()
	_roster_vbox.name = "RosterVBox"
	_roster_vbox.add_theme_constant_override("separation", 2)
	vbox.add_child(_roster_vbox)

	# Scrollable message log (same pattern as the dice log).
	_chat_log_scroll = ScrollContainer.new()
	_chat_log_scroll.custom_minimum_size = Vector2(0, 160)
	_chat_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_chat_log_scroll)
	_chat_log_vbox = VBoxContainer.new()
	_chat_log_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_log_scroll.add_child(_chat_log_vbox)

	# Input row: a focusable LineEdit (the ONE exception to the FOCUS_NONE rule).
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Enter: chat · Esc: back to game"
	# Length is clamped authoritatively in NetworkManager._clean_chat on send/receive.
	_chat_input.focus_mode = Control.FOCUS_ALL
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.text_submitted.connect(_on_chat_submitted)
	_chat_input.gui_input.connect(_on_chat_input_gui_input)
	vbox.add_child(_chat_input)

	_chat_panel.add_child(HudFrame.new())
	$UI/HUD.add_child(_chat_panel)


## Show/hide the chat panel and refresh the roster on a session transition.
func _set_chat_visible(is_visible: bool) -> void:
	if not _chat_panel:
		return
	_chat_panel.visible = is_visible
	if is_visible:
		_rebuild_roster()
	else:
		if _chat_input:
			_chat_input.release_focus()
		if _chat_log_vbox:
			for child: Node in _chat_log_vbox.get_children():
				child.queue_free()


## Sends the typed message, echoes it locally and keeps focus for the next line.
## The echo uses the same cleaned text the broadcast sends, so it matches peers.
func _on_chat_submitted(text: String) -> void:
	var cleaned: String = network_manager.broadcast_chat_message(text)
	if not cleaned.is_empty():
		_add_chat_entry(network_manager.get_my_peer_id(), cleaned)
	_chat_input.clear()
	_chat_input.grab_focus()


## Esc inside the chat field returns control to the game (releases focus).
func _on_chat_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_chat_input.release_focus()
		get_viewport().set_input_as_handled()


## A remote chat message arrived — append it to the log.
func _on_remote_chat_message(peer_id: int, text: String) -> void:
	_add_chat_entry(peer_id, text)


## Appends one "<name>: <text>" line, the name tinted with the player's color.
func _add_chat_entry(peer_id: int, text: String) -> void:
	if not _chat_log_vbox:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var name_lbl := Label.new()
	name_lbl.text = "%s:" % _peer_display_name(peer_id)
	name_lbl.add_theme_font_size_override("font_size", CHAT_PANEL_SMALL_FONT)
	name_lbl.add_theme_color_override("font_color", _get_player_color(peer_id))
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	row.add_child(name_lbl)

	var text_lbl := Label.new()
	text_lbl.text = text
	text_lbl.add_theme_font_size_override("font_size", CHAT_PANEL_SMALL_FONT)
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_lbl)

	_chat_log_vbox.add_child(row)
	await get_tree().process_frame
	_chat_log_scroll.scroll_vertical = int(_chat_log_scroll.get_v_scroll_bar().max_value)


## Rebuilds the connected-player roster: one colored dot + name per peer, the
## local player tagged "(you)" and the host "(host)".
func _rebuild_roster() -> void:
	if not _roster_vbox:
		return
	for child: Node in _roster_vbox.get_children():
		child.queue_free()

	var my_id: int = network_manager.get_my_peer_id()
	var ids: Array[int] = [my_id]
	for id: int in network_manager.connected_peers:
		if not ids.has(id):
			ids.append(id)
	ids.sort()  # host (1) first

	for id: int in ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", HudTokens.SPACE_4)

		var dot := ColorRect.new()
		dot.color = _get_player_color(id)
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)

		var label := Label.new()
		var suffix := ""
		if id == my_id:
			suffix = " (you)"
		elif id == 1:
			suffix = " (host)"
		label.text = "%s%s" % [_peer_display_name(id), suffix]
		label.add_theme_font_size_override("font_size", CHAT_PANEL_SMALL_FONT)
		label.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
		row.add_child(label)

		_roster_vbox.add_child(row)


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
	_is_reconnecting = true  # pause presence broadcasts until we're back (Fix A)
	if save_manager:
		save_manager.reset_restore_lock()  # a drop can strand an in-flight restore; don't deadlock the re-sync
	# Clear our own busy flag so a drop mid-load doesn't leave us marked busy to a late joiner
	# after we rejoin (the re-sync sets it true→false anyway; this is belt-and-braces, offline-safe).
	network_manager.broadcast_peer_busy(false)
	var role := "host" if network_manager.is_host else "guest"
	push_warning("[Network] Connection lost — attempting to rejoin the room (%s)…" % role)
	network_status_label.text = "Connection lost — reconnecting…"
	network_status_label.add_theme_color_override("font_color", Color.YELLOW)
	internet_lobby.reconnect_to_room()


func _on_relay_reconnecting() -> void:
	_is_reconnecting = true
	network_status_label.text = "Reconnecting…"
	network_status_label.add_theme_color_override("font_color", Color.YELLOW)


## Rejoin failed (relay unreachable or the room is gone, e.g. host left). End the
## session cleanly with a clear message.
func _on_relay_reconnect_failed(reason: String) -> void:
	_is_reconnecting = false
	push_warning("[Network] Reconnect failed: %s" % reason)
	network_status_label.text = "Reconnect failed (%s)" % reason
	network_status_label.add_theme_color_override("font_color", Color.RED)
	# Tear the dead relay peer down cleanly (RC4): close + null the socket, drop the
	# multiplayer peer, and reset the roster dicts so a later Host/Join starts from a
	# known-clean state instead of layering over a half-alive session.
	if internet_lobby and internet_lobby.has_method("disconnect_internet_game"):
		internet_lobby.disconnect_internet_game()
	if network_manager:
		network_manager.disconnect_game()
		network_manager.player_names.clear()
	_update_network_ui(false, false)
	_cleanup_all_presence()


## Guest side: the host dropped but the room is preserved. Wait for it to return (the
## host reclaims peer id 1 and re-syncs) instead of treating it as a full disconnect.
func _on_host_paused() -> void:
	network_status_label.text = "Host disconnected — waiting for reconnect…"
	network_status_label.add_theme_color_override("font_color", Color.YELLOW)


## Guest side: OUR OWN connection was restored after a drop (fresh peer id). Godot's
## connected_to_server — which normally re-announces our version+token via _on_network_connected —
## does NOT re-fire on the reused MultiplayerPeer, so re-announce here. Without this the host never
## receives our announce and kicks us on the version-handshake timeout, causing a reconnect cascade.
## The announce makes the host re-validate, rebuild our token->slot (remap), and re-push full state.
func _on_guest_reconnected() -> void:
	_is_reconnecting = false  # link restored — resume presence broadcasts
	# Re-announce our version+token: connected_to_server (which normally re-announces via
	# _on_network_connected) does NOT re-fire on the reused MultiplayerPeer after our own drop.
	# NOTE: this fixes the REUSED-peer-id reconnect; when the relay hands out a NEW peer id the
	# RPC still doesn't route (stale SceneMultiplayer unique-id) — see ROADMAP "graceful guest
	# reconnect". Harmless + correct on its own (idempotent announce).
	network_status_label.text = "Reconnected"
	network_status_label.add_theme_color_override("font_color", Color.GREEN)
	if network_manager:
		network_manager.is_host = multiplayer.is_server()
		# NOTE: the re-announce is driven by the room_joined -> internet_connected path on every
		# (re)join (reliable over the command channel now), so we must NOT announce again here —
		# a second announce makes the host re-validate + re-push full state twice per reconnect,
		# racing the clear+rebuild. We only reset our reconnect UI state.


## The host is present again (we rejoined as host, or our host returned). The full
## state re-sync runs over the restored peer link; clear the warning.
func _on_host_rejoined() -> void:
	_is_reconnecting = false  # link restored — resume presence broadcasts (Fix A)
	if network_manager:
		# Restore the host role flag for role-gated logic (RC7).
		network_manager.is_host = multiplayer.is_server()
		if multiplayer.is_server():
			# We reclaimed peer id 1: restore our own slot-1 identity binding (RC8).
			network_manager.seed_host_identity()
		else:
			# Guest: re-announce token+version so the (possibly stale) rehosted host
			# rebuilds its token->slot for us and re-issues a remap only if our peer_id
			# actually changed; then re-register our name. Self-heals the stale-view +
			# missing-resync gap after a host rehost.
			network_manager.announce_version_to_host()
			_register_local_name()
	network_status_label.text = "Reconnected"
	network_status_label.add_theme_color_override("font_color", Color.GREEN)


# ============================================================================
# Model caching (R2 download) progress
# ============================================================================

## An imported army needs models that aren't cached yet — show a progress overlay.
func _on_model_caching_started(total: int) -> void:
	# Army-import overlay: switch from the "LOADING ARMY" parse phase to the 3D-model
	# download phase with an n/x counter (issue #56).
	if is_instance_valid(_army_loading_overlay):
		_army_loading_overlay.set_label("LOADING 3D MODELS  0/%d" % maxi(1, total))
		_army_loading_overlay.set_progress(0.0)
		return
	_ensure_cache_progress_ui()
	_kill_cache_tween()
	_cache_progress_bar.max_value = maxi(1, total)
	_cache_progress_bar.value = 0
	_cache_progress_label.text = "LOADING ARMY"
	_cache_progress_panel.visible = true


func _on_model_caching_progress(done: int, total: int) -> void:
	# Feed the army-import overlay's bar when it's up — downloads are the FIRST half of
	# the bar (the spawn that follows fills the second half).
	if is_instance_valid(_army_loading_overlay):
		_army_loading_overlay.set_label("LOADING 3D MODELS  %d/%d" % [done, maxi(1, total)])
		_army_loading_overlay.set_progress(0.5 * float(done) / float(maxi(1, total)))
		return
	if not _cache_progress_panel:
		return
	_cache_progress_bar.max_value = maxi(1, total)
	# Glide smoothly to the new value instead of snapping (no "blob-blob" stepping).
	_kill_cache_tween()
	_cache_progress_tween = create_tween()
	_cache_progress_tween.tween_property(_cache_progress_bar, "value", float(done), 0.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_cache_progress_label.text = "LOADING ARMY"


## Per-unit spawn progress fills the SECOND half of the army loading bar (downloads, if
## any, filled the first half via _on_model_caching_progress).
func _on_army_spawn_progress(done: int, total: int) -> void:
	if is_instance_valid(_army_loading_overlay):
		_army_loading_overlay.set_label("PLACING ARMY  %d/%d" % [done, maxi(1, total)])
		_army_loading_overlay.set_progress(0.5 + 0.5 * float(done) / float(maxi(1, total)))


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
	if _is_army_syncing or _is_reconnecting:
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
			var _zoom: float = camera_pivot.get_zoom() if camera_pivot.has_method("get_zoom") else 10.0
			network_manager.broadcast_camera_direction(
				camera_pivot._yaw, camera_pivot._pitch, _zoom)
			var _cam := camera_pivot.get_node("Camera3D") as Camera3D
			if _cam:
				network_manager.broadcast_camera_position(_cam.global_position)


## Called when a remote player's cursor position is received. NEVER render a "remote" cursor
## for ourselves: after a reconnect/remap a stray self-id update would otherwise spawn a
## cursor that tracks our OWN mouse.
func _on_remote_cursor_updated(peer_id: int, pos_x: float, pos_z: float) -> void:
	if network_manager and peer_id == network_manager.get_my_peer_id():
		return
	if not _remote_cursors.has(peer_id):
		_spawn_remote_cursor(peer_id)
	_remote_cursors[peer_id].update_position(pos_x, pos_z)


## Called when a remote player's camera direction is received (self-id ignored).
func _on_remote_camera_updated(peer_id: int, yaw: float, pitch: float, zoom: float) -> void:
	if network_manager and peer_id == network_manager.get_my_peer_id():
		return
	if _player_avatars.has(peer_id):
		_player_avatars[peer_id].update_look_direction(yaw, pitch)
		# Fade the avatar as its owner zooms in, so it stops hiding the spot they're inspecting.
		if _player_avatars[peer_id].has_method("update_zoom"):
			_player_avatars[peer_id].update_zoom(zoom)


## Called when a remote player rolls dice. The context carries the sender's
## success target/modifier and reroll info so the log and success column render
## the roll exactly as the sender saw it. `tags` carries the per-die colour tags so the
## mirrored result keeps the sender's colours.
func _on_remote_dice_rolled(peer_id: int, results: Array, context: Dictionary, tags: Array) -> void:
	var faces: Array[int] = []
	for v: Variant in results:
		faces.append(int(v))
	var color_tags: Array[int] = []
	for v: Variant in tags:
		color_tags.append(int(v))

	_add_dice_log_entry(_peer_display_name(peer_id), faces, context, color_tags)

	# Show 3D dice visualization for remote roll. The 3D tray is shared between
	# local and remote rolls, so show_faces() respawns the dice and preempts any
	# in-flight LOCAL physics roll/reroll: that local roll is then dropped (not
	# logged, not broadcast). Intentional priority — a remote roll is already
	# part of the shared game state, an un-broadcast local roll is not. Rare
	# (needs both players rolling within the same ~2.5 s window); see PROJECT_STATUS.
	# Guard prevents roll_finnished from re-logging/re-broadcasting.
	_is_showing_remote_roll = true
	_remote_roll_context = context
	_pending_reroll_mode = DiceRules.REROLL_NONE
	_pending_reroll_count = 0
	# Mirror guard: _update_dice_set → dice_count setter must not re-broadcast composition.
	_is_mirroring_dice = true
	_update_dice_set(faces.size())
	dice_roller_control.show_faces(faces, tags)
	_is_mirroring_dice = false

	# Play avatar dice roll animation
	if _player_avatars.has(peer_id):
		_player_avatars[peer_id].play_dice_roll_animation()


## A local die was clicked to change its colour — mirror the single change to the opponent.
func _on_local_die_color_changed(index: int, tag: int) -> void:
	if not _is_mirroring_dice and network_manager.is_multiplayer_active():
		network_manager.broadcast_dice_color_tag(index, tag)


## A peer changed its cup composition (dice count + per-die colour tags): mirror it onto our
## tray so we see the same dice + colours live. Guarded so applying it doesn't re-broadcast,
## and so the dice_count setter / colour-tag application don't echo back.
func _on_remote_dice_composition(peer_id: int, count: int, tags: Array) -> void:
	if network_manager and peer_id == network_manager.get_my_peer_id():
		return
	_is_mirroring_dice = true
	_set_dice_count(count)            # rebuilds the resting tray to `count` fresh dice
	dice_roller_control.apply_color_tags(tags)
	_update_dice_count_display()
	_is_mirroring_dice = false


## A peer cycled one die's colour: recolour the same die on our mirrored tray live.
func _on_remote_dice_color_tag(peer_id: int, index: int, tag: int) -> void:
	if network_manager and peer_id == network_manager.get_my_peer_id():
		return
	_is_mirroring_dice = true
	dice_roller_control.set_die_color_tag(index, tag)
	_is_mirroring_dice = false


## Spawn a remote cursor visualization for a peer
func _spawn_remote_cursor(peer_id: int) -> void:
	# Remote cursors are for OTHER players only — never spawn one for our own id (a stray
	# self-id update after a remap must not create a cursor tracking our own mouse).
	if network_manager and peer_id == network_manager.get_my_peer_id():
		return
	# Free any existing cursor for this peer first — a relay reconnect/rehost
	# replay can re-fire peer_connected; overwriting the dict without freeing
	# leaks an orphan node (RC2).
	if _remote_cursors.has(peer_id):
		if is_instance_valid(_remote_cursors[peer_id]):
			_remote_cursors[peer_id].queue_free()
		_remote_cursors.erase(peer_id)
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
	# Avatars are REMOTE players only — never one for ourselves. The remap broadcast reaches
	# the returning guest too (new_peer == our own id); without this guard _on_peer_remapped
	# would create a stationary self-phantom that no cleanup path ever frees (review MF1).
	if network_manager and peer_id == network_manager.get_my_peer_id():
		return
	# Free any existing avatar for this peer first — a relay reconnect/rehost
	# replay can re-fire peer_connected; overwriting the dict without freeing
	# leaks an orphan avatar (the phantom 3rd player) in the scene (RC2).
	if _player_avatars.has(peer_id):
		if is_instance_valid(_player_avatars[peer_id]):
			_player_avatars[peer_id].queue_free()
		_player_avatars.erase(peer_id)
	var avatar_script = load("res://scripts/player_avatar.gd")
	var avatar = Node3D.new()
	avatar.set_script(avatar_script)
	avatar.name = "PlayerAvatar_%d" % peer_id
	add_child(avatar)
	var slot: int = network_manager.slot_for_peer(peer_id) if network_manager else peer_id
	avatar.setup(peer_id, slot, table.table_size)
	# Seed the name label if this peer's name is already known (roster may arrive
	# before or after the avatar spawns).
	if avatar.has_method("set_player_name"):
		avatar.set_player_name(_peer_display_name(peer_id))
	_player_avatars[peer_id] = avatar
	print("[Presence] Spawned avatar for peer %d at table edge" % peer_id)


## A peer's name became known/changed: refresh its avatar label and the roster.
func _on_remote_player_name_updated(peer_id: int, _player_name: String) -> void:
	if _player_avatars.has(peer_id):
		var avatar: Node3D = _player_avatars[peer_id]
		if is_instance_valid(avatar) and avatar.has_method("set_player_name"):
			avatar.set_player_name(_peer_display_name(peer_id))
	if _chat_panel and _chat_panel.visible:
		_rebuild_roster()


## Remove presence nodes for a disconnected peer
func _cleanup_peer_presence(peer_id: int) -> void:
	if _remote_cursors.has(peer_id):
		_remote_cursors[peer_id].queue_free()
		_remote_cursors.erase(peer_id)
	if _player_avatars.has(peer_id):
		_player_avatars[peer_id].queue_free()
		_player_avatars.erase(peer_id)


## A returning identity token rebound its slot from old_peer to new_peer. EVICT BOTH the
## stale old-id presence AND any new-id presence the relay's eager peer_connected already
## spawned, then spawn exactly ONE avatar under new_peer (the cursor lazy-spawns on the
## next remote-cursor packet). Order-independent + idempotent. Color resolves off the
## slot now, so the returning player keeps its colour.
func _on_peer_remapped(old_peer: int, new_peer: int, _slot: int) -> void:
	if old_peer == new_peer:
		return
	_cleanup_peer_presence(old_peer)
	_cleanup_peer_presence(new_peer)
	_spawn_player_avatar(new_peer)
	_rebuild_roster()


## A guest just adopted the host's full peer→slot table (bus 036): recolour every existing avatar +
## cursor, since some may have been spawned with a stale slot (their raw peer_id) before the table
## arrived, giving the wrong colour in a 3+-player game.
func _on_slot_table_synced() -> void:
	for pid in _player_avatars:
		var av = _player_avatars[pid]
		if is_instance_valid(av) and av.has_method("set_player_color"):
			av.set_player_color(_get_player_color(pid))
	for pid in _remote_cursors:
		var cur = _remote_cursors[pid]
		if is_instance_valid(cur) and cur.has_method("set_player_color"):
			cur.set_player_color(_get_player_color(pid))


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


## Get a player's color from their stable SLOT (not the transport peer_id), so a
## reconnected guest whose peer_id changed keeps its colour. Modulo wraps a high
## monotonic slot back into the four-colour table (and slot 0 / pending -> colour 1),
## so nobody ever flickers to WHITE.
func _get_player_color(peer_id: int) -> Color:
	var slot := peer_id
	if network_manager:
		slot = network_manager.slot_for_peer(peer_id)
	return PlayerPalette.color_for_slot(slot)   # shared slot→palette (matches army bases, bus 036)


## ============================================================================
## Table Settings Synchronization (Phase 3)
## ============================================================================

## Broadcast a table-settings change to all peers. Any participant may edit the
## table (deployment, objectives, terrain layout, biome), so this is no longer
## host-only — guest edits propagate too.
func _broadcast_table_settings_update(setting_key: String, value) -> void:
	if not network_manager.is_multiplayer_active():
		return
	var settings = {setting_key: value}
	network_manager.broadcast_table_settings(settings)


## Receive table settings from host (client only)
func _on_remote_table_settings_changed(settings: Dictionary) -> void:
	print("[Settings] Received table settings: %s" % str(settings))

	# Session-wide free-move (host-operated): apply + mirror into the (read-only for guests) checkbox.
	if settings.has("free_move"):
		_apply_free_move(bool(settings["free_move"]))

	if settings.has("table_size"):
		var ts = settings["table_size"]
		if ts is Array and ts.size() >= 2:
			var size_feet = Vector2(ts[0], ts[1])
			table.setup_table(size_feet)
			_adjust_camera_for_table_size(size_feet)
			print("[Settings] Table resized to %.1fx%.1f feet" % [size_feet.x, size_feet.y])

	if settings.has("biome") and table.has_method("set_biome"):
		table.set_biome(settings["biome"])
		print("[Settings] Biome set to %s" % str(settings["biome"]))

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

	# (Deployment-zone type/visibility no longer drives the trail chalk — the formal game phase does.)

	if settings.has("deployment_flipped"):
		var flipped = bool(settings["deployment_flipped"])
		if terrain_overlay and terrain_overlay.has_method("set_deployment_colors_flipped"):
			terrain_overlay.set_deployment_colors_flipped(flipped)
			if deployment_flip_check:
				deployment_flip_check.button_pressed = flipped

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
## Permanent room-code readout at the TOP of the left bar (maintainer: without it nobody can rejoin —
## the code was shown once and every status update overwrote it). Click copies the code; also logged to
## the battle log on host/join so it survives in the session record.
func _init_room_code_display() -> void:
	var left_panel_vbox = $UI/HUD/LeftPanelScroll/LeftPanelVBox
	if not left_panel_vbox:
		return
	_room_code_button = Button.new()
	_room_code_button.visible = false
	_room_code_button.focus_mode = Control.FOCUS_NONE
	_room_code_button.tooltip_text = "The session's room code — click to copy"
	_room_code_button.add_theme_color_override("font_color", Color(0.4, 0.95, 0.55))
	_room_code_button.pressed.connect(func() -> void:
		if not _session_room_code.is_empty():
			DisplayServer.clipboard_set(_session_room_code)
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.GENERAL, "Room code copied to clipboard"))
	left_panel_vbox.add_child(_room_code_button)
	left_panel_vbox.move_child(_room_code_button, 0)


## Show/refresh (non-empty code) or hide (empty) the permanent room-code readout + log it once.
func _set_room_code_display(code: String) -> void:
	_session_room_code = code
	if _room_code_button == null:
		return
	if code.is_empty():
		_room_code_button.visible = false
		return
	_room_code_button.text = "Room: %s" % InternetLobby._format_code(code)
	_room_code_button.visible = true
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL, "Room code: %s" % InternetLobby._format_code(code))


func _update_network_ui(connected: bool, _is_host: bool) -> void:
	if not connected:
		_set_room_code_display("")   # session over — hide the room-code readout
	host_button.visible = !connected
	host_button.disabled = false
	join_button.visible = !connected
	join_button.disabled = false
	disconnect_button.visible = connected
	# Chat + roster are only meaningful in a live session (central toggle — every
	# connect/disconnect path routes through here).
	_set_chat_visible(connected)
	# The Start-Game / Ready button label depends on MP state (single-player "Start Game" vs the MP
	# ready toggle) — refresh it on every connect/disconnect.
	_update_game_phase_ui()


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
	# Restored game phase drives the trail chalk + the Start-Game/Ready UI (a mid-play save resumes in
	# PLAYING with trails live; a setup save resumes in DEPLOYMENT).
	_sync_move_trails_deployment()
	_update_game_phase_ui()

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
		var public: bool = ProjectSettings.get_setting("niemandsland/internet_public", false)
		print("Starting internet host via %s (public=%s)" % [relay_url, public])
		internet_lobby.host_internet_game(relay_url, public)
	else:
		print("Joining internet room %s via %s" % [room_code_to_join, relay_url])
		internet_lobby.join_internet_game(room_code_to_join, relay_url)


## Dispatch for main-owned commands over the hand-rolled protocol (below @rpc, reconnect-safe).
## network_manager handles its own former-@rpc methods; main handles the full-state push.
func _on_network_command(type: String, payload: Variant, _from_peer: int) -> void:
	if type == "sync_game_state" and payload is Dictionary:
		_rpc_sync_game_state(payload.get("state", {}))


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
	var state = save_manager.serialize_game_state()  # includes army_names (for tray rebuild)
	state["_host_version"] = network_manager.get_game_version()
	var obj_count = state.get("objects", []).size()
	var unit_count = state.get("game_units", []).size()
	print("[StateSync] Sending state to peer %d: %d objects, %d game_units" % [peer_id, obj_count, unit_count])
	network_manager.send_command("sync_game_state", {"state": state}, peer_id)


## Sync loaded state to all connected clients
func _sync_loaded_state_to_clients() -> void:
	if not network_manager.is_host:
		return

	print("Syncing loaded state to %d clients..." % network_manager.connected_peers.size())

	# Get current state and broadcast to all clients
	var state = save_manager.serialize_game_state()  # includes army_names (for tray rebuild)
	state["_host_version"] = network_manager.get_game_version()
	network_manager.send_command("sync_game_state", {"state": state}, 0)


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

	# Show the same loading overlay as a self-import while we rebuild the table + download models.
	if not is_instance_valid(_army_loading_overlay):
		_army_loading_overlay = LoadingOverlay.new()
		_army_loading_overlay.compact = true
		get_tree().root.add_child(_army_loading_overlay)
		_army_loading_overlay.set_label("JOINING — LOADING TABLE")
		_army_loading_overlay.set_indeterminate()

	# Tell other peers we are loading so their object move/edit input is gated while we rebuild
	# the table (mirrors begin_restore/end_restore; cleared after end_restore below).
	network_manager.broadcast_peer_busy(true)

	# Serialize against the per-army broadcast restore: both clear _loaded_game_units, and an
	# interleave (host imports while we join) wipes it mid-restore. Released below before return.
	await save_manager.begin_restore()

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
	if opr_army_manager and opr_army_manager.has_method("merge_player_spells"):
		opr_army_manager.merge_player_spells(state.get("player_spells", {}))

	# Restore game units (OPR units with wounds, status, model positions)
	save_manager._deserialize_game_units(state.get("game_units", []))

	# Download every army's models up front in ONE batch (like the live army-complete path)
	# so a late-joiner sees real 3D models, not placeholder bodies.
	if opr_army_manager != null and opr_army_manager.model_library != null:
		var join_specs: Array = []
		for ud in state.get("game_units", []):
			var jp: Dictionary = ud.get("unit_properties", {})
			var jf: String = jp.get("faction_folder", "")
			var jn: String = jp.get("name", "")
			if jf != "" and jn != "":
				join_specs.append({"faction": jf, "unit_name": jn})
		if not join_specs.is_empty():
			await opr_army_manager.model_library.ensure_models(join_specs)

	# Deserialize objects (async for TTS downloads)
	var objects_data = state.get("objects", [])
	var loaded_count = await save_manager._deserialize_objects(objects_data)

	# Sync object counter so subsequent spawns don't conflict with existing IDs
	var synced_counter = int(state.get("object_counter", 0))
	if synced_counter > 0:
		object_manager._object_counter = synced_counter

	# Restore game state (round, current player, game phase). The phase rides the same serializer, so
	# a guest that joins/reconnects mid-play lands in PLAYING (trails live), not DEPLOYMENT.
	save_manager._deserialize_game_state(state.get("game_state", {}))
	_sync_move_trails_deployment()
	_update_game_phase_ui()

	# Restore marker visualizations (fatigue, shaken, wounds) + AoF:R regiment trays.
	save_manager._restore_hero_attachments_after_load()
	save_manager._restore_markers_after_load()
	save_manager._restore_regiments_after_load()

	# Recreate each army's tray (the platform it stands on) — the join state carries units +
	# models but not the tray, so a late-joiner would otherwise see floating models with no
	# tableau under them (shared with the .nml-load path).
	save_manager.restore_army_trays_after_load(state.get("army_names", {}))

	# Re-park loose models the host had killed (needs the trays above), so a late-joiner sees the
	# same greyed casualties on the tray, not live draggable models (G4).
	save_manager._restore_dead_parking_after_load()

	save_manager.end_restore()
	network_manager.broadcast_peer_busy(false)  # join load done — release the other peers' gate

	if is_instance_valid(_army_loading_overlay):
		_army_loading_overlay.complete_and_free()
		_army_loading_overlay = null

	print("Synced %d objects from host (counter=%d)" % [loaded_count, object_manager._object_counter])


## ============================================================================
## Casual Sandbox Terrain Shelf
## ============================================================================

## Casual sandbox terrain shelf: a code-built browser window + a toolbar button to open it.
## Spawns free-placed, draggable terrain pieces on the 3D table (grassland ruins first).
func _setup_sandbox_shelf() -> void:
	_sandbox_shelf = SandboxTerrainShelf.new()
	$UI.add_child(_sandbox_shelf)
	_sandbox_shelf.setup(object_manager)
	_sandbox_shelf.closed.connect(_on_sandbox_shelf_closed)

	# A toggle next to the map-layout button: it opens/closes the terrain placement shelf.
	# Terrain locking is manual + per-piece (select a piece + L); the toggle no longer
	# locks/unlocks terrain, so a just-placed piece stays draggable until the player locks it.
	_terrain_mode_btn = Button.new()
	_terrain_mode_btn.toggle_mode = true
	_terrain_mode_btn.text = "Terrain Mode"
	_terrain_mode_btn.toggled.connect(_on_terrain_mode_toggled)
	var parent := map_layout_btn.get_parent()
	if parent:
		parent.add_child(_terrain_mode_btn)
		parent.move_child(_terrain_mode_btn, map_layout_btn.get_index() + 1)


func _on_terrain_mode_toggled(pressed: bool) -> void:
	object_manager.set_terrain_edit_mode(pressed)
	if pressed:
		_sandbox_shelf.open()
	else:
		_sandbox_shelf.hide()


## Shelf closed by the user (X / Close) → un-press the toggle so it reflects the closed shelf
## (no terrain locking happens — placed pieces stay draggable until manually locked).
func _on_sandbox_shelf_closed() -> void:
	if _terrain_mode_btn and _terrain_mode_btn.button_pressed:
		_terrain_mode_btn.button_pressed = false


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
	save_game_dialog.theme = current_theme
	load_game_dialog.theme = current_theme


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
	# Pre-select the player assignment to the slot you joined as (e.g. 2nd player
	# -> Player 2 / red), so an imported army is owned by the right player by default.
	var slot := 1
	if network_manager and network_manager.is_multiplayer_active():
		# In an active session, NEVER stamp an army with a provisional peer_id slot:
		# if assignment is still pending (slot 0, sub-second window after connect), wait
		# for the host's slot assignment so the army's opr_player_id matches our durable
		# slot. (The host is always slot 1 and never pends.)
		if network_manager.get_my_player_slot() <= 0:
			await network_manager.slot_assigned
		slot = maxi(1, network_manager.get_my_player_slot())
	opr_import_dialog.set_player(slot)
	opr_import_dialog.popup_centered()


## Handle army imported from dialog
func _on_opr_army_imported(army: OPRApiClient.OPRArmy, player_id: int) -> void:
	print("Importing army '%s' for Player %d" % [army.name, player_id])

	# Full-screen loading overlay for the whole import — visible above the (now hidden)
	# import window and present even when the models are already cached. Model caching,
	# if any, drives its bar (see _on_model_caching_progress); otherwise it creeps.
	_army_loading_overlay = LoadingOverlay.new()
	_army_loading_overlay.compact = true  # small centred window, not a full-screen black
	get_tree().root.add_child(_army_loading_overlay)
	_army_loading_overlay.set_label("LOADING ARMY")
	_army_loading_overlay.set_indeterminate()
	# Tell other peers we are loading so their object move/edit input is gated meanwhile
	# (mirrors begin_restore/end_restore; cleared on every exit below).
	network_manager.broadcast_peer_busy(true)
	# Let the overlay render BEFORE the (synchronous) spawn blocks the main thread, so it
	# is visible from the start instead of only appearing once loading is done.
	await get_tree().process_frame
	await get_tree().process_frame

	# Store army
	opr_army_manager.armies[player_id] = army

	# Spawn the army on tray (position determined by player ID).
	# Awaitable: on-demand models are downloaded up front before spawning.
	# Serialize against a concurrently-arriving REMOTE army: a local import AND an incoming army
	# both mutate the shared object_manager._object_counter + save_manager._loaded_game_units, so
	# two simultaneous mid-session imports would clobber each other's network_ids and lose models
	# (the headless stress-test finding). The restore-lock makes the two builds mutually exclusive.
	await save_manager.begin_restore()
	var spawned = await opr_army_manager.spawn_army(army)
	save_manager.end_restore()
	network_manager.broadcast_peer_busy(false)  # load done — release the other peer's gate
	print("Spawned %d models for army '%s' on Player %d's tray" % [spawned.size(), army.name, player_id])

	if is_instance_valid(_army_loading_overlay):
		_army_loading_overlay.complete_and_free()
		_army_loading_overlay = null

	# Auto-create buff tokens for the army's special rules (auras / re-rolls / +1-−1), synced.
	_auto_create_buff_tokens(army)

	# Sync to other peers if in multiplayer
	if network_manager.is_multiplayer_active():
		_broadcast_army_import(army, spawned)


## Scan a freshly imported army's special rules and auto-define the matching buff tokens so a
## player doesn't have to create them by hand. Only the IMPORTING peer scans + defines + broadcasts;
## remote peers receive the definition via remote_token_defined (and a late-joiner via the synced
## token_library), so every peer converges without double-definition. Idempotent via has().
func _auto_create_buff_tokens(army: OPRApiClient.OPRArmy) -> void:
	if radial_menu_controller == null or radial_menu_controller.token_library == null:
		return
	var lib = radial_menu_controller.token_library
	var rules: Array = []
	for unit in army.units:
		for r in unit.special_rules:
			rules.append(r)
	var rule_desc: Dictionary = opr_army_manager.get_all_rule_descriptions() if opr_army_manager else {}
	var tokens: Array = OPRArmyManager.buff_tokens_from_rules(rules, rule_desc)
	var created := 0
	for t in tokens:
		if lib.has(t.name):
			continue
		lib.define(t.name, t.color, t.is_counter, t.effect)
		created += 1
		if network_manager and network_manager.is_multiplayer_active():
			network_manager.broadcast_token_define(t.name, t.color, t.is_counter, t.effect)
	if created > 0:
		print("[Tokens] Auto-created %d buff token(s) from special rules" % created)


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
		# AoF:R — include the movement-tray block so the peer can rebuild the regiment
		# (game_unit.to_dict() omits it; mirrors save_manager._serialize_game_units).
		if opr_army_manager.regiments.has(game_unit.unit_id):
			var reg = opr_army_manager.regiments[game_unit.unit_id]
			if reg and is_instance_valid(reg.tray):
				unit_dict["regiment"] = reg.to_dict()
		units_data.append(unit_dict)
		objects_per_unit.append(unit_objects)

	# Ship the army's special-rule descriptions with the broadcast so remote tooltips resolve
	# (e.g. "Bloodborn") — the late-join state-sync already carries them; this is the mid-session
	# import path. get_all_rule_descriptions() unions the session cache + every army's rules.
	var rule_descs: Dictionary = {}
	if opr_army_manager and opr_army_manager.has_method("get_all_rule_descriptions"):
		rule_descs = opr_army_manager.get_all_rule_descriptions()
	print("[ArmySync] Broadcasting army in batches: %d units (player_id=%d, army='%s', %d rule descriptions)" % [units_data.size(), army.player_id, army.name, rule_descs.size()])
	_is_army_syncing = true
	await network_manager.broadcast_army_batched(units_data, objects_per_unit, army.player_id, army.name, rule_descs)
	_is_army_syncing = false


## Receive an army header from a remote peer — make the tray, open the same loading overlay
## as a self-import, and start buffering the incoming units (built all at once on complete).
func _on_remote_army_header(player_id: int, army_name: String, unit_count: int) -> void:
	_is_army_syncing = true  # pause our presence broadcasts while we build the incoming army (Fix A)
	print("[ArmySync] Header: '%s' — expecting %d units (player_id=%d)" % [army_name, unit_count, player_id])
	var player_color: Color = OPRArmyManager.army_color(player_id, Color.GRAY)
	opr_army_manager._create_army_tray(player_id, army_name, player_color)
	_incoming_armies[player_id] = {"army_name": army_name, "units": [], "objects": []}
	# Same overlay as a self-import, so receiving an army looks identical to loading one.
	if not is_instance_valid(_army_loading_overlay):
		_army_loading_overlay = LoadingOverlay.new()
		_army_loading_overlay.compact = true
		get_tree().root.add_child(_army_loading_overlay)
		_army_loading_overlay.set_label("LOADING ARMY")
		_army_loading_overlay.set_indeterminate()


## Receive a single unit — BUFFER it. We do not download/spawn per unit: the model
## download manager has one shared HTTPRequest, so concurrent per-unit downloads collide
## (only the first finished, leaving the army with a single unit).
func _on_remote_army_unit(unit_data: Dictionary, objects_data: Array, player_id: int) -> void:
	var buf: Dictionary = _incoming_armies.get(player_id, {})
	if buf.is_empty():
		buf = {"army_name": "Army", "units": [], "objects": []}
		_incoming_armies[player_id] = buf
	buf["units"].append(unit_data)
	buf["objects"].append(objects_data)


## All units received — build the whole army in ONE pass: rebuild the units, download every
## model with a single ensure_models call (feeds the loading bar like a self-import), spawn
## all model objects, then restore markers / heroes / regiment trays.
func _on_remote_army_complete(player_id: int, rule_descriptions: Dictionary) -> void:
	# Merge rule descriptions FIRST (before building units) so tooltips like "Bloodborn" resolve.
	if opr_army_manager and opr_army_manager.has_method("merge_rule_descriptions"):
		opr_army_manager.merge_rule_descriptions(rule_descriptions)
	var buf: Dictionary = _incoming_armies.get(player_id, {})
	_incoming_armies.erase(player_id)
	var units: Array = buf.get("units", [])
	var object_groups: Array = buf.get("objects", [])
	print("[ArmySync] Complete: building %d units (player_id=%d)" % [units.size(), player_id])

	# Tell other peers we are loading so their object move/edit input is gated while we build
	# the incoming army (mirrors begin_restore/end_restore; cleared after end_restore below).
	network_manager.broadcast_peer_busy(true)

	# Serialize against the join state-sync restore: both clear _loaded_game_units. Released below.
	await save_manager.begin_restore()

	# 1. Rebuild all GameUnits at once (deserialize clears + repopulates _loaded_game_units).
	save_manager._deserialize_game_units(units)

	# 2. Download EVERY model in one batch (single shared HTTPRequest — no per-unit collision).
	if opr_army_manager != null and opr_army_manager.model_library != null:
		var specs: Array = []
		var seen_keys: Dictionary = {}
		var unit_faction: Dictionary = {}   # game_unit_id -> faction (for per-object variant keys)
		for ud in units:
			var p: Dictionary = ud.get("unit_properties", {})
			var fac: String = p.get("faction_folder", "")
			var un: String = p.get("name", "")
			unit_faction[str(ud.get("unit_id", ""))] = fac
			if fac != "" and un != "" and not seen_keys.has(fac + "/" + un):
				seen_keys[fac + "/" + un] = true
				specs.append({"faction": fac, "unit_name": un})
		# Variant-reworked factions have VARIANT-ONLY manifest entries: the per-object RESOLVED
		# keys (loadout variant / mount, stamped at import) must download too, or the models
		# fall back to placeholders (RC3 field-test bug).
		for group in object_groups:
			for od in group:
				if od is Dictionary and (od as Dictionary).has("glb_name"):
					var od_d: Dictionary = od as Dictionary
					var fac2: String = str(unit_faction.get(str(od_d.get("game_unit_id", "")), ""))
					var key: String = str(od_d.get("glb_name", ""))
					if fac2 != "" and key != "" and not seen_keys.has(fac2 + "/" + key):
						seen_keys[fac2 + "/" + key] = true
						specs.append({"faction": fac2, "unit_name": key})
		if not specs.is_empty():
			await opr_army_manager.model_library.ensure_models(specs)

	# 3. Spawn all model objects (GLBs now cached -> real models, not placeholders).
	# Reconcile the BARE low counter, not the slot-prefixed id: OPR network_ids are
	# slot*STRIDE + counter, so taking the raw max would poison _object_counter into a
	# slot's namespace and break the +10000..+50000 non-OPR offset bands. Strip the slot.
	var all_objects: Array = []
	var max_counter: int = object_manager._object_counter
	for group in object_groups:
		for obj_data in group:
			all_objects.append(obj_data)
			if obj_data is Dictionary:
				var nid := int(obj_data.get("network_id", 0))
				var c := (nid % OPRArmyManager.OPR_NET_ID_SLOT_STRIDE) if nid >= OPRArmyManager.OPR_NET_ID_SLOT_STRIDE else nid
				if c > max_counter:
					max_counter = c
	object_manager._object_counter = max_counter
	await save_manager._deserialize_objects(all_objects)

	# 4. Restore markers / hero attachments / regiment trays now that the models exist.
	save_manager._restore_hero_attachments_after_load()
	save_manager._restore_markers_after_load()
	save_manager._restore_regiments_after_load()

	save_manager.end_restore()
	network_manager.broadcast_peer_busy(false)  # army built — release the other peers' gate

	# 5. Close the loading overlay.
	if is_instance_valid(_army_loading_overlay):
		_army_loading_overlay.complete_and_free()
		_army_loading_overlay = null
	_is_army_syncing = false  # army built — resume presence broadcasts (Fix A)
	print("[ArmySync] Army built for player_id=%d (%d units)" % [player_id, units.size()])


## Receive TTS terrain spawn from a remote peer
func _on_remote_tts_terrain_spawned(mesh_url: String, diffuse_url: String,
	sx: float, sy: float, sz: float,
	px: float, py: float, pz: float, tname: String) -> void:
	print("[TerrainSync] Received remote TTS terrain: %s" % tname)
	await object_manager.spawn_tts_terrain(mesh_url, diffuse_url,
		Vector3(sx, sy, sz), Vector3(px, py, pz), tname)


## Receive remote camera position update
func _on_remote_camera_position_updated(peer_id: int, pos_x: float, pos_y: float, pos_z: float) -> void:
	if network_manager and peer_id == network_manager.get_my_peer_id():
		return
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
## Presents the first selected unit's card via the new animated dock card (replacing the old detail
## UnitCard); clears it for empty/non-unit selections.
func _on_selection_changed_update_card(selected_objects: Array[Node3D]) -> void:
	if unit_card:
		unit_card.clear()   # retired as the on-selection readout — the dock card presents it now
	if unit_dock == null:
		return

	if selected_objects.is_empty():
		unit_dock.present_unit(null)
		return

	var units := UnitUtils.get_unique_units(selected_objects)
	if units.is_empty():
		unit_dock.present_unit(null)
		return

	# Prefer a host unit (not a joined Hero) as the card subject, so its attached
	# Hero shows as part of it rather than as a separate "+1".
	var primary: GameUnit = units[0]
	for unit in units:
		if not unit.is_attached():
			primary = unit
			break

	unit_dock.present_unit(primary)


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
## Host tools (community feedback): a left-panel toggle that lets the HOST move ALL models — lifts the
## MP ownership lock for fully solo / self-refereed games run from a hosted session. Guests never see an
## effect (the lock check is host-gated); the toggle logs to the battle log for transparency.
func _init_host_tools_ui() -> void:
	var left_panel_vbox = $UI/HUD/LeftPanelScroll/LeftPanelVBox
	if not left_panel_vbox:
		return
	var box := VBoxContainer.new()
	box.name = "HostToolsPanel"
	left_panel_vbox.add_child(box)
	var label := Label.new()
	label.text = "Host tools:"
	label.add_theme_color_override("font_color", Color(0.85, 0.87, 0.92, 1.0))
	box.add_child(label)
	_host_free_move_check = CheckButton.new()
	_host_free_move_check.text = "Move all models"
	_host_free_move_check.tooltip_text = "Lift the ownership lock for EVERYONE at the table (solo / refereeing). Only the host can switch this."
	_host_free_move_check.focus_mode = Control.FOCUS_NONE
	_host_free_move_check.add_theme_font_size_override("font_size", 12)
	_host_free_move_check.toggled.connect(_on_host_free_move_toggled)
	box.add_child(_host_free_move_check)


## Session-wide free-move: HOST-operated, applies to everyone (guests may then move the host's army too
## — they just cannot flip the switch themselves).
func _on_host_free_move_toggled(pressed: bool) -> void:
	if network_manager != null and network_manager.is_multiplayer_active() and not network_manager.is_host:
		# A guest flipped the switch: revert silently — the state belongs to the host.
		_host_free_move_check.set_pressed_no_signal(object_manager.host_free_move if object_manager != null else false)
		return
	_apply_free_move(pressed)
	_broadcast_table_settings_update("free_move", pressed)


func _apply_free_move(enabled: bool) -> void:
	if object_manager != null:
		object_manager.host_free_move = enabled
	if _host_free_move_check != null:
		_host_free_move_check.set_pressed_no_signal(enabled)
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL, "Free-move %s (everyone may move all models)" % ("enabled" if enabled else "disabled"))


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

	# Swap the two zone colours — for an asymmetric map when a player takes the other table edge.
	deployment_flip_check = CheckBox.new()
	deployment_flip_check.text = "Flip Zone Colours"
	deployment_flip_check.button_pressed = false
	deployment_flip_check.add_theme_color_override("font_color", Color(0.85, 0.87, 0.92, 1.0))
	deployment_flip_check.toggled.connect(_on_deployment_flip_toggled)
	deployment_panel.add_child(deployment_flip_check)


## Handle deployment zone visibility toggle
func _on_deployment_zones_visibility_toggled(show_zones: bool) -> void:
	if not terrain_overlay or not terrain_overlay.has_method("set_deployment_zones_visible"):
		return

	terrain_overlay.set_deployment_zones_visible(show_zones)

	# NOTE: zone visibility no longer drives the move-trail chalk — that follows the formal game
	# phase now (see _sync_move_trails_deployment). Toggling zones during play keeps trails visible.

	# Sync visibility to remote clients
	_broadcast_table_settings_update("deployment_visible", show_zones)


## Push the current GAME PHASE to the move-trail chalk: during DEPLOYMENT players are placing
## armies (not proving movement), so the trails auto-hide; once play begins the chalk resumes.
## This now keys off the FORMAL game phase (OPRArmyManager.game_phase), NOT the deployment-zone
## visibility — so leaving the zones shown during play no longer suppresses trails (the old caveat).
## The move LEDGER keeps recording throughout — only the visible chalk follows the phase.
func _sync_move_trails_deployment() -> void:
	if move_trails == null:
		return
	var deploying := opr_army_manager != null and opr_army_manager.is_deployment_phase()
	move_trails.set_deployment_active(deploying)


## Handle the deployment-zone colour flip (asymmetric-map side choice).
func _on_deployment_flip_toggled(flipped: bool) -> void:
	if not terrain_overlay or not terrain_overlay.has_method("set_deployment_colors_flipped"):
		return
	terrain_overlay.set_deployment_colors_flipped(flipped)
	_broadcast_table_settings_update("deployment_flipped", flipped)


## ============================================================================
## Game Phase Gate (Deployment -> Playing)
## ============================================================================

## Tiny DE/EN picker for the phase-gate labels (the app has no i18n infra; German maintainer/community
## wanted these strings localised). German on a `de*` OS locale, English otherwise.
func _phase_tr(en: String, de: String) -> String:
	return de if str(OS.get_locale()).begins_with("de") else en


## Build the Start-Game / Ready control: a discoverable button in the left panel that flips the game
## from DEPLOYMENT to PLAYING. In single-player it starts the game immediately; in multiplayer it is a
## per-player ready toggle (host starts play only once BOTH players are ready). A status line under it
## shows the MP waiting state. Built programmatically to match the deployment/host-tools panels and
## keep main.tscn churn-free.
func _init_game_phase_ui() -> void:
	var left_panel_vbox = $UI/HUD/LeftPanelScroll/LeftPanelVBox
	if not left_panel_vbox:
		return
	var panel := VBoxContainer.new()
	panel.name = "GamePhasePanel"
	left_panel_vbox.add_child(panel)

	_start_game_button = Button.new()
	_start_game_button.name = "StartGameButton"
	_start_game_button.focus_mode = Control.FOCUS_NONE
	_start_game_button.add_theme_color_override("font_color", Color(0.4, 0.95, 0.55))
	_start_game_button.pressed.connect(_on_start_game_pressed)
	panel.add_child(_start_game_button)

	_game_phase_status_label = Label.new()
	_game_phase_status_label.name = "GamePhaseStatus"
	_game_phase_status_label.add_theme_font_size_override("font_size", 11)
	_game_phase_status_label.add_theme_color_override("font_color", Color(0.6, 0.63, 0.7, 1.0))
	_game_phase_status_label.visible = false
	panel.add_child(_game_phase_status_label)

	_update_game_phase_ui()


## Start-Game / Ready button pressed. Single-player: start play now. Multiplayer: toggle THIS player's
## ready flag and report it to the host — the host's both-ready gate fires the authoritative transition.
func _on_start_game_pressed() -> void:
	if network_manager != null and network_manager.is_multiplayer_active():
		network_manager.set_local_ready(not network_manager.is_local_ready())
		_update_game_phase_ui()
	elif opr_army_manager != null:
		opr_army_manager.start_game()  # emits game_phase_changed -> _on_game_phase_changed


## The game phase changed locally (single-player start, MP transition applied, or save/load). Re-derive
## the trail-chalk gate and refresh the button/status.
func _on_game_phase_changed(_phase: int) -> void:
	_sync_move_trails_deployment()
	_update_game_phase_ui()


## The host broadcast the authoritative game phase (host applies it here too). Apply it to the army
## manager; the game_phase_changed seam then updates the trails + UI on this peer.
func _on_remote_game_phase_changed(phase: int) -> void:
	if opr_army_manager != null:
		opr_army_manager.set_game_phase(phase)


## Host-side ready tally changed (a player readied/un-readied). Refresh the waiting readout.
func _on_ready_state_changed(_all_ready: bool, _count: int, _total: int) -> void:
	_update_game_phase_ui()


## Refresh the Start-Game / Ready button label + the MP status line from the current phase and MP
## ready state. Hidden once play has begun.
func _update_game_phase_ui() -> void:
	if _start_game_button == null:
		return
	var playing := opr_army_manager != null and not opr_army_manager.is_deployment_phase()
	if playing:
		_start_game_button.visible = false
		if _game_phase_status_label != null:
			_game_phase_status_label.visible = false
		return
	_start_game_button.visible = true
	# network_manager is typed as Node here, so its bool method returns need explicit typing (no :=).
	var in_mp: bool = network_manager != null and network_manager.is_multiplayer_active()
	if in_mp:
		var ready: bool = network_manager.is_local_ready()
		_start_game_button.text = _phase_tr("Cancel Ready", "Bereit abbrechen") if ready \
				else _phase_tr("Ready", "Fertig aufgestellt")
		_start_game_button.tooltip_text = _phase_tr(
				"Signal you have finished deploying. Play begins when both players are ready.",
				"Signalisiere, dass du fertig aufgestellt hast. Das Spiel startet, wenn beide Spieler bereit sind.")
		if _game_phase_status_label != null:
			if ready and network_manager.is_host:
				# Host sees the live tally (it tracks both sides); a guest just knows it is waiting.
				_game_phase_status_label.text = _phase_tr(
						"Waiting for other player (%d/%d)" % [network_manager.ready_count(), network_manager.seated_slots().size()],
						"Warte auf Mitspieler (%d/%d)" % [network_manager.ready_count(), network_manager.seated_slots().size()])
				_game_phase_status_label.visible = true
			elif ready:
				_game_phase_status_label.text = _phase_tr("Waiting for other player…", "Warte auf Mitspieler…")
				_game_phase_status_label.visible = true
			else:
				_game_phase_status_label.visible = false
	else:
		_start_game_button.text = _phase_tr("Start Game", "Spiel starten")
		_start_game_button.tooltip_text = _phase_tr(
				"Begin round 1 — deployment is done.",
				"Runde 1 beginnen — die Aufstellung ist abgeschlossen.")
		if _game_phase_status_label != null:
			_game_phase_status_label.visible = false


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
	# Re-evaluate the 1" unit-separation hint on drop (fades out if now compliant).
	# Refresh the shape cache first so a drop of a multi-unit selection measures
	# every base at its final position (the drag-time cache holds pre-drag spots).
	# proactive=false: on drop only VIOLATING units keep their wall (persist); merely
	# nearby walls fade out.
	_separation_cache_valid = false
	_check_separation_for_selected_units(false)


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
		# Skirmish coherency (1"/9") does not apply to Regiments — they form tight
		# ranked blocks instead. Skip the check/visualization for regiment units.
		if game_unit.unit_properties.get("regiment_mode", false):
			continue
		if game_unit not in checked_units:
			checked_units.append(game_unit)
			# Show coherency visualization for this unit. animate=false: this runs
			# live (~15 Hz) while dragging, so re-running the fade/pulse each frame
			# would make the lines flicker.
			coherency_visualizer.show_coherency(game_unit, CoherencyChecker.is_skirmish_system(game_unit), false)


## ============================================================================
## 1" Unit-Separation Zone Walls
## ============================================================================
## OPR rule (GF/AoF Advanced Rules v3.5.1, p.7 "General Movement"): "Models may never
## be within 1” of models from other units, unless they are taking a Charge action" —
## ANY other unit, friendly included. While a model / regiment tray is dragged, every
## nearby foreign UNIT is wrapped in a translucent ground WALL (SeparationVisualizer):
## a 1"-wide band hugging the merged outline of that unit's bases — its no-go area.
## RED = enemy unit (base contact is exempt — a Charge into melee), ORANGE/AMBER =
## friendly unit (no legal contact). A wall fades IN proactively when the dragged base
## comes within SEPARATION_PROACTIVE_INCHES of the unit; an actual sub-1" violation
## intensifies and pulses. On a compliant drop the merely-nearby walls fade out; a
## violating unit's wall persists. Same-unit bases are exempt (coherency governs INSIDE
## a unit); a joined Hero folds into its host. Strictly local render (no RPCs); works
## identically in single-player, hotseat and multiplayer.
##
## Coverage: local drag (~15 Hz via drag_updated, proactive) + local drop (via
## _on_unit_moved, violation-only). Undo/redo and remote-peer moves are NOT
## re-evaluated (neither is coherency) — the drag+drop path is the must-have.

## A dragged base's wall fades in once it comes within this of a foreign unit's edge
## (proactive display). Beyond it the unit shows no wall.
const SEPARATION_PROACTIVE_INCHES := 3.0

## Invalidate the other-units shape cache on any selection change; clear the walls if
## the selection emptied (nothing is being moved any more).
func _on_selection_changed_for_separation(selected: Array) -> void:
	_separation_cache_valid = false
	if selected.is_empty() and separation_visualizer:
		separation_visualizer.clear_retreat_ruler()
		separation_visualizer.show_zones([])


## Rebuild the per-unit base-shape cache (all units, both armies), grouped by effective
## unit so each foreign unit's wall is built from its whole footprint. A joined Hero's
## models fold into its host's entry. Each entry also carries a centroid/radius (for the
## per-unit quick reject) and a member-position signature (the visualizer's mesh cache
## key). Non-selected units stay put during the local drag, so the cache stays valid.
func _rebuild_separation_cache() -> void:
	_separation_units_cache.clear()
	if opr_army_manager == null:
		_separation_cache_valid = true
		return
	for game_unit in opr_army_manager.get_all_game_units():
		if game_unit == null:
			continue
		# A joined Hero resolves to its host unit — coherency requires the hero within
		# 1" of the host, so hero and host must read as the SAME unit (one shared wall).
		var eff_unit: GameUnit = SeparationChecker.effective_unit(game_unit)
		if eff_unit == null or eff_unit.unit_properties == null:
			continue
		var key: int = eff_unit.get_instance_id()
		for model in game_unit.get_alive_models():
			if model == null or model.node == null or not is_instance_valid(model.node):
				continue
			var shape := SeparationChecker.shape_for_model(model)
			if shape == null:
				continue
			var entry: Dictionary = _separation_units_cache.get(key, {})
			if entry.is_empty():
				entry = {
					"unit": eff_unit,
					"player_id": int(eff_unit.unit_properties.get("player_id", 0)),
					"shapes": [],
				}
				_separation_units_cache[key] = entry
			(entry["shapes"] as Array).append(shape)
	# Finalise per-unit centroid / bounding radius / member signature.
	for key in _separation_units_cache:
		var entry: Dictionary = _separation_units_cache[key]
		var shapes: Array = entry["shapes"]
		var centroid := Vector2.ZERO
		for s in shapes:
			centroid += s.center
		centroid /= float(shapes.size())
		var radius := 0.0
		var signature := 0.0
		for s in shapes:
			radius = maxf(radius, centroid.distance_to(s.center) + s.bounding_radius())
			signature += s.center.x * 131.0 + s.center.y * 197.0 + s.yaw * 17.0 + s.bounding_radius() * 7.0
		entry["centroid"] = centroid
		entry["radius"] = radius
		entry["signature"] = signature
	_separation_cache_valid = true


## Collects the models currently being moved (loose model nodes AND regiment-tray
## members), each with a FRESH base shape at its current position. Returns an Array of
## {model, shape, unit, player_id, center, bound}.
func _collect_moved_separation_models(selected: Array) -> Array:
	var moved: Array = []
	for obj in selected:
		if obj == null or not is_instance_valid(obj):
			continue
		if obj is RegimentTray or obj.is_in_group(RegimentTray.GROUP):
			for child in obj.get_children():
				_append_moved_separation_model(child, moved)
		else:
			_append_moved_separation_model(obj, moved)
	return moved


## Appends one moved model (if the node is a live, non-parked OPR model) to `moved`.
func _append_moved_separation_model(node: Node3D, moved: Array) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not node.has_meta("model_instance"):
		return
	if node.get_meta("deleted", false):
		return  # parked casualty — not on the battlefield
	var model := node.get_meta("model_instance") as ModelInstance
	if model == null or not model.is_alive:
		return
	var shape := SeparationChecker.shape_for_model(model)
	if shape == null:
		return
	# Unit identity is the rule's seam; a model without a resolvable unit cannot be
	# classified against "other units" -> skip (no warning over a false one).
	var eff_unit: GameUnit = SeparationChecker.effective_unit(model.unit as GameUnit)
	if eff_unit == null:
		return
	moved.append({
		"model": model,
		"shape": shape,
		"unit": eff_unit,
		"player_id": int(eff_unit.unit_properties.get("player_id", 0)),
		"center": shape.center,
		"bound": shape.bounding_radius(),
	})


## Evaluates the 1" unit-separation walls for the current selection and drives the
## visualizer. For each foreign unit it aggregates the min edge gap to the moved bases,
## whether any pair actually violates (per the exception matrix), and the wall colour,
## then emits one ZoneSpec per unit to show. Pre-filtered per unit (footprint reject)
## and per pair (distance_squared) so only nearby bases run the exact edge test.
## @param proactive: true on drag — a unit within SEPARATION_PROACTIVE_INCHES shows its
##   wall even without a violation; false on drop — only violating units keep a wall.
func _check_separation_for_selected_units(proactive: bool = false) -> void:
	if separation_visualizer == null or object_manager == null or opr_army_manager == null:
		return

	# object_manager is typed Node3D, so its return type isn't inferable here — use an
	# untyped assignment (matches _check_coherency_for_selected_units).
	var selected = object_manager.get_selected_objects()
	if selected.is_empty():
		separation_visualizer.clear_retreat_ruler()
		separation_visualizer.show_zones([])
		return

	var moved := _collect_moved_separation_models(selected)
	if moved.is_empty():
		separation_visualizer.clear_retreat_ruler()
		separation_visualizer.show_zones([])
		return

	if not _separation_cache_valid:
		_rebuild_separation_cache()

	# Moved aggregate (effective-unit ids + centroid/radius) for a per-unit quick reject.
	var moved_unit_ids: Dictionary = {}
	var moved_centroid := Vector2.ZERO
	for mv in moved:
		moved_unit_ids[(mv["unit"] as GameUnit).get_instance_id()] = true
		moved_centroid += mv["center"]
	moved_centroid /= float(moved.size())
	var moved_radius := 0.0
	for mv in moved:
		moved_radius = maxf(moved_radius, moved_centroid.distance_to(mv["center"]) + float(mv["bound"]))

	var proactive_m: float = SEPARATION_PROACTIVE_INCHES * SeparationChecker.INCHES_TO_METERS
	var sep_inches: float = SeparationChecker.SEPARATION_DISTANCE_INCHES
	var contact_eps: float = SeparationChecker.BASE_CONTACT_EPSILON_INCHES

	# Track the globally NEAREST violating base pair (min edge gap) across all foreign
	# units, so the retreat ruler measures the deepest incursion — the pair the player
	# most needs to back away from.
	var worst_gap := INF
	var worst_a: SeparationChecker.BaseShape = null
	var worst_b: SeparationChecker.BaseShape = null
	var worst_friendly := false

	var zones: Array = []
	for unit_id in _separation_units_cache:
		if moved_unit_ids.has(unit_id):
			continue  # never wall the unit(s) being moved
		var entry: Dictionary = _separation_units_cache[unit_id]
		# Per-unit quick reject: whole footprint beyond proactive reach of the moved set.
		var reach_unit: float = proactive_m + float(entry["radius"]) + moved_radius
		if moved_centroid.distance_squared_to(entry["centroid"]) > reach_unit * reach_unit:
			continue

		var unit_player: int = int(entry["player_id"])
		var entry_shapes: Array = entry["shapes"]
		var min_gap := INF
		var is_violation := false
		var color_is_friendly := true
		for cs in entry_shapes:
			var cs_center: Vector2 = cs.center
			var cs_bound: float = cs.bounding_radius()
			for mv in moved:
				var reach: float = proactive_m + float(mv["bound"]) + cs_bound
				if (mv["center"] as Vector2).distance_squared_to(cs_center) > reach * reach:
					continue
				var mv_player: int = mv["player_id"]
				var pair_friendly: bool = mv_player > 0 and unit_player > 0 and mv_player == unit_player
				# Any near enemy/unknown pair makes the whole wall red; amber needs all
				# near pairs to be known same-army.
				if not pair_friendly:
					color_is_friendly = false
				var gap := SeparationChecker.edge_distance(mv["shape"], cs)
				min_gap = minf(min_gap, gap)
				var pair_violation := false
				if gap < sep_inches:
					if pair_friendly:
						pair_violation = true  # friendly: any sub-1" including contact warns
					elif gap > contact_eps:
						pair_violation = true  # enemy/unknown: sub-1" but not base contact
					# enemy/unknown base contact = intentional Charge into melee -> exempt
				if pair_violation:
					is_violation = true
					if gap < worst_gap:
						worst_gap = gap
						worst_a = mv["shape"]
						worst_b = cs
						worst_friendly = pair_friendly
		if min_gap == INF:
			continue  # no member pair within even the proactive reach

		if proactive:
			if min_gap > SEPARATION_PROACTIVE_INCHES and not is_violation:
				continue
		elif not is_violation:
			continue  # drop: only violating units keep their wall

		zones.append(SeparationVisualizer.ZoneSpec.new(
			unit_id, entry_shapes, color_is_friendly, is_violation, float(entry["signature"])))

	separation_visualizer.show_zones(zones)

	# Retreat aid: while a violation is live, draw a measured ruler between the nearest
	# offending base edges, labelled with the actual gap and the 1" target, so the player
	# sees how deep they are inside the zone and which way to back out. Cleared otherwise.
	if worst_a != null and worst_b != null:
		var pts := SeparationChecker.nearest_edge_points(worst_a, worst_b)
		separation_visualizer.set_retreat_ruler(pts["from"], pts["to"], worst_gap, worst_friendly)
	else:
		separation_visualizer.clear_retreat_ruler()


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
	opr_army_manager.undo_manager = undo_manager

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

	# Create the 1" enemy-separation proximity hint visualizer (local-only render).
	separation_visualizer = SeparationVisualizer.new()
	separation_visualizer.name = "SeparationVisualizer"
	add_child(separation_visualizer)

	# Base-anchored range rings ("auras"): per-model range circles toggled with G on the
	# selection (local-only display aid). Owns the rings under /root/Main.
	range_ring_controller = RangeRingControllerScript.new()
	range_ring_controller.name = "RangeRingController"
	add_child(range_ring_controller)
	object_manager.range_ring_controller = range_ring_controller
	if unit_dock:
		unit_dock.set_range_ring_controller(range_ring_controller)  # spell-range hover preview on the card

	# Movement reach indicator: Advance + Rush/Charge bands toggled with M on the selection
	# (local-only display aid, OPR Fast/Slow aware). Owns the rings under /root/Main.
	movement_range_controller = MovementRangeControllerScript.new()
	movement_range_controller.name = "MovementRangeController"
	add_child(movement_range_controller)
	object_manager.movement_range_controller = movement_range_controller

	# Persistent shared rulers: pinned measurements that stay on the table and replicate
	# to every player in the owner's colour (session-only, like remote cursors).
	pinned_rulers = PinnedRulersScript.new()
	pinned_rulers.name = "PinnedRulers"
	add_child(pinned_rulers)
	object_manager.pinned_rulers = pinned_rulers

	# Path painting (P1+P2): the model is the brush — drags paint chalk trails as wide
	# as the base, every executed move lands in the ledger with its measured arc, trails
	# persist until the unit's activation ends and replicate to the opponent (the
	# proof-of-movement layer). T hides them, Shift+T clears, click a trail for proof.
	move_trails = MoveTrailsScript.new()
	move_trails.name = "MoveTrails"
	add_child(move_trails)
	object_manager.move_trails = move_trails
	object_manager.selection_dropped.connect(_on_trails_dropped)
	# A unit marked Activated is DONE for the round — its trail's job ends with it.
	if radial_menu_controller.has_signal("unit_activated"):
		radial_menu_controller.unit_activated.connect(func(gu) -> void:
			if gu != null and move_trails != null:
				move_trails.on_activation_done(gu.unit_id))
	# Auto-suppress chalk while the game is in the deployment phase (deployment isn't
	# movement-proof) — seed from the current formal game phase.
	_sync_move_trails_deployment()

	# Create unit boundary visualizer (shows which models belong to which unit)
	unit_boundary_visualizer = UnitBoundaryVisualizerScript.new()
	unit_boundary_visualizer.name = "UnitBoundaryVisualizer"
	unit_boundary_visualizer.army_manager = opr_army_manager
	# Per-token ground raycast (boundary tokens ride the terrain under each token).
	unit_boundary_visualizer.object_manager = object_manager
	add_child(unit_boundary_visualizer)
	radial_menu_controller.boundary_visualizer = unit_boundary_visualizer
	# A wiped unit drops its status tokens; on revive (undo) re-create them from its state (issue #78).
	unit_boundary_visualizer.unit_tokens_revived.connect(radial_menu_controller.initialize_status_markers_for_unit)
	opr_army_manager.radial_menu_controller = radial_menu_controller
	if unit_dock != null:
		unit_dock.set_radial_controller(radial_menu_controller)

	# Battlefield stains: leave a blood pool (or oil + fire for vehicles) where a model is
	# removed (issue #60). Hooked off model/unit removal, local + remote.
	battlefield_stains = BattlefieldStains.new()
	battlefield_stains.name = "BattlefieldStains"
	add_child(battlefield_stains)
	radial_menu_controller.model_deleted.connect(_on_model_removed_stain)
	radial_menu_controller.unit_deleted.connect(_on_unit_removed_stain)

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

	# Refresh the bottom unit-card dock with the newly spawned army.
	if unit_dock != null:
		unit_dock.rebuild()


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
			_spawn_stain_for_model(model)  # blood/oil where the model fell (issue #60)
		elif model.is_alive and model.node and is_instance_valid(model.node):
			model.node.set_meta("deleted", false)


## A model was removed locally (radial Delete / Delete key / wounds → 0): leave a stain.
func _on_model_removed_stain(model: ModelInstance) -> void:
	_spawn_stain_for_model(model)


## A whole unit was deleted (local or, via unit_deleted re-emit, remote): stain each model.
func _on_unit_removed_stain(game_unit: GameUnit) -> void:
	if game_unit == null:
		return
	for model in game_unit.models:
		_spawn_stain_for_model(model)


## Leave a blood pool (infantry) or oil pool + fires (vehicle) where `model` stood, sized to
## its base. Idempotent per model (a "stained" meta guards against a double stain from the
## local + remote paths both firing).
func _spawn_stain_for_model(model: ModelInstance) -> void:
	if model == null or battlefield_stains == null:
		return
	var node := model.node
	if node == null or not is_instance_valid(node) or node.has_meta("stained"):
		return
	node.set_meta("stained", true)
	var props: Dictionary = model.unit.unit_properties if model.unit else {}
	# A dead LOOSE model is parked on the army tray, so its node has already moved there — stain the
	# spot where it FELL (its stored pre-park transform), not the tray. revive_transform is set on
	# both host and guest from the same synced position, so the stain + its seed match on peers.
	var pos := node.global_position
	if node.has_meta("revive_transform"):
		pos = (node.get_meta("revive_transform") as Transform3D).origin
	# Deterministic seed from the (synced) table position so the fire scatter matches on peers.
	var seed_val := int(pos.x * 1000.0) * 73856093 ^ int(pos.z * 1000.0) * 19349663
	battlefield_stains.add_stain(pos, _stain_base_radius_m(props), _stain_is_vehicle(props), seed_val, node)


## Base radius (metres) of a removed model: half the round base, or half the oval's long axis.
func _stain_base_radius_m(props: Dictionary) -> float:
	if props.get("base_is_oval", false):
		var w: float = float(props.get("base_width_mm", 32))
		var d: float = float(props.get("base_depth_mm", 32))
		return maxf(w, d) / 2.0 * 0.001
	return float(props.get("base_size_round", 32)) / 2.0 * 0.001


## A removed model is a vehicle (-> oil + fire, not blood) if its unit is Tough(6+), the OPR
## convention for vehicles/large monsters.
func _stain_is_vehicle(props: Dictionary) -> bool:
	if opr_army_manager == null:
		return false
	return opr_army_manager._get_tough_value_from_rules(props.get("special_rules", [])) >= 6


## Called when a remote peer changes unit activation
func _on_remote_activation_updated(game_unit: GameUnit) -> void:
	if radial_menu_controller:
		radial_menu_controller._update_activated_markers(game_unit)
	# Marked Activated remotely = that unit's activation is done — its trails fade
	# (same rule as the local toggle, so both tables stay in step).
	if move_trails != null and game_unit != null and game_unit.is_activated:
		move_trails.on_activation_done(game_unit.unit_id)


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
			if move_trails != null and add:
				move_trails.on_activation_done(game_unit.unit_id)
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
