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
var _next_roll_owner: String = ""   # attribution for the next tray roll ("AI (…)"); empty = "You" (goal 001)
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
var unit_boundary_visualizer: Node3D = null  # UnitBoundaryVisualizer
var range_ring_controller: Node = null  # RangeRingController (base-anchored range auras)
var movement_range_controller: Node = null  # MovementRangeController (Advance/Rush reach)
var solo_controller: SoloController = null   # Solo/AI — drives the designated AI army (F11 = whole side)
var solo_ai_slots: Dictionary = {}           # player_id -> true: armies the Solo AI controls (goal 001)
var solo_panel_box: VBoxContainer = null     # left-panel "Solo" section (per-army AI toggles)
var _solo_target_mode: Dictionary = {}       # {unit, melee} while the player picks an attack target (P8)
var _solo_los_line: MeshInstance3D = null    # live line to the hovered target: green = clear, red = blocked
var _solo_los_label: Label3D = null          # floating "7/10 sight" count on the targeting line (per-model LOS)
var _solo_los_cache: Dictionary = {}         # {target_id, count, at} — throttles the per-model LOS recompute
# Solo P2 auto-game state (goal 003 P2): alternation queue + match end.
const SOLO_GAME_ROUNDS := 4                  # OPR standard match length (rounds)
const SOLO_AI_TAIL_DELAY_S := 1.2            # readable pause between the AI's unprompted tail activations
const SOLO_DEPLOY_WALL_CLEARANCE_M := 0.02   # a deploy sample point within 2 cm (~0.8") of a container/ruin wall is blocked (finding 1)
var _solo_pending_replies: int = 0           # human activations still owed one AI answer (alternation)
var _solo_ai_took_last_activation: bool = true  # who took the LAST activation of the current round (finding 7:
                                             # drives who OPENS the next round — the OTHER side, never back-to-back).
                                             # Init true so round 1 opens with the human (the default deployment order).
var _solo_ai_busy: bool = false              # an AI activation chain is running (guards re-entry)
var _solo_game_finished: bool = false        # summary shown after SOLO_GAME_ROUNDS — no further auto-advance
var _solo_ai_banner: Label = null            # non-blocking "AI is taking its turn…" banner during the tail
var _solo_fast: bool = false                 # fast-forward: shrink pacing holds + skip move animation
var _solo_dev: bool = false                  # developer mode: render the AI's decision records into the battle log
var _solo_toast: Label = null                # transient AI-action attribution/outcome toast
var _solo_unmodeled_logged: Dictionary = {}  # rule name -> true: once-per-session unmodeled-rule notes
# === AI ARENA — native both-AI mode + per-side difficulty (see SoloDifficulty) ===
var _solo_both_ai: bool = false              # BOTH sides are AI: combat auto-resolves, the game runs unattended
var _solo_difficulty_grades: Dictionary = {} # player-slot -> SoloDifficulty preset name (the graded arena)
var _solo_arena_seed: int = 0                # game-level base seed for the reproducible difficulty knob draws
var pinned_rulers: Node = null  # PinnedRulers (persistent shared measurements)
## Persistent blood/oil stains left where models were removed (issue #60). Lives outside
## ObjectManager so it survives model cleanup; decorative, not saved.
var battlefield_stains: BattlefieldStains = null

# Deployment Zones UI (visibility toggle only - editing is in Map Tool;
# unit-placement compliance is verified manually by the players)
var deployment_zone_check: CheckBox = null
var deployment_flip_check: CheckBox = null

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
	object_manager.selection_changed.connect(_on_selection_changed_update_card)

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

	# Solo section (goal 001): per-army AI toggles; refreshed on every army import.
	_init_solo_panel()

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
	# AI ARENA: arm native both-AI mode from the environment (no-op in normal play).
	_solo_init_arena_from_env()


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
## Solo/AI (F11, debug fallback): run the WHOLE remaining AI side — every eligible unit of the designated
## AI army activates in sequence (goal 003 P2; the normal flow is alternating activation via
## _on_solo_human_activated). The AI army is whichever slot is marked in solo_ai_slots (import checkbox /
## Solo panel); with no designation it falls back to player 2 (backward compat).
func _run_solo_ai_turn() -> void:
	if opr_army_manager == null or movement_range_controller == null:
		push_warning("[Solo/AI] not ready — import armies first")
		return
	_ensure_solo_controller()
	if _solo_ai_busy:
		return
	_solo_ai_busy = true
	var moved := 0
	while true:
		var unit: GameUnit = await _solo_activate_one_ai()
		_solo_flush_dev()
		if unit == null:
			break
		moved += 1
	_solo_ai_busy = false
	if moved == 0:
		print("[Solo/AI] AI turn complete — all player-%d units activated" % _solo_ai_slot())
	await _solo_after_activation()


## ONE full AI activation (the shared runner behind F11 and the alternating flow): pick + move via the
## SoloController (official decision tree, terrain, walls), follow with the camera, narrate to the battle
## log, then resolve Dangerous tests / shooting / melee with real tray dice. A Shaken unit idles and
## recovers instead (OPR p.10). Returns the activated unit, or null when the AI side is done.
func _solo_activate_one_ai() -> GameUnit:
	var unit: GameUnit = solo_controller.activate_next_ai_unit()
	if unit == null:
		return null
	_solo_ai_took_last_activation = true   # the AI just took an activation (finding 7: round-opener tracking)
	# PRESENTATION ORDER (field-test finding 2): the controller already applied + broadcast the FINAL model
	# positions, so the model nodes currently SHOW the end state. Return them to their route START before the
	# camera focus + announce beat, so the choreography reads (1) highlight the unit at its start, (2) show
	# the planned corridors while it is still there, (3) glide — the end state must never appear first.
	_solo_present_move_start(solo_controller.last_move_paths)
	# Camera follows the acting unit so each activation is watchable (goal 001, F1) — now framed on its START.
	_solo_focus_on_unit(unit)
	if radial_menu_controller != null:
		radial_menu_controller._update_activated_markers(unit)
	var report: Dictionary = solo_controller.last_report
	# Shaken idle (OPR p.10): the unit spends its activation idle and recovers — clear via the radial seam
	# (state + marker + MP broadcast) and skip movement narration / combat entirely.
	if bool(report.get("idle_shaken", false)):
		if unit.is_shaken and radial_menu_controller != null:
			radial_menu_controller.card_toggle_shaken(unit)
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.GENERAL, "%s spends its activation idle — recovers from Shaken" % unit.get_name(), true)
		return unit
	var target: GameUnit = report.get("target")
	if battle_log != null and target != null:
		# Narrate the TRUE move goal (field-test finding 1): an objective-seeking move used to print the enemy
		# unit's name ("rushes → Snipers") even though it was heading for a marker, masking whether the AI ever
		# contested the mission. When the tree routed toward an objective, say so; the enemy stays the combat
		# target for any shooting that follows.
		var goal_label: String = "an objective" if bool(report.get("to_objective", false)) else target.get_name()
		battle_log.log_event(BattleLog.Category.MOVEMENT, "%s %s (→ %s)" % [
			unit.get_name(), AiDecision.action_name(int(report.get("action", 0))), goal_label], true)
	_solo_log_unmodeled_rules(unit)   # once-per-session visibility of rules the automation skips
	if target != null:
		_solo_log_unmodeled_rules(target)
	# ACTIVATION CHOREOGRAPHY (field-test finding 7 — the maintainer's explicit staging): the camera has
	# focused the unit (a); hold an attention beat (b); _solo_animate_move then shows the plotted corridors
	# (c), holds a beat (d) and glides the models along them (e); a final beat (f) precedes the attack/
	# ability resolution (g). Every beat is the named PACE_ATTENTION_S, Fast-AI-compressed.
	var has_move: bool = not solo_controller.last_move_paths.is_empty()
	if has_move:
		await _solo_pace_attention()   # (b)
	# EXECUTE: replay the models along their REAL planner routes (walls visibly walked around, not through)
	# — corridors appear, an attention beat, then the models glide; the state was applied + broadcast first.
	await _solo_animate_move(solo_controller.last_move_paths)
	if has_move:
		await _solo_pace_attention()   # (f) before attacks resolve
	# Dangerous terrain crossed during the move (goal 003 P3): each such model rolls a real tray die, a 1 wounds.
	var dangerous_models: int = int(report.get("dangerous_models", 0))
	var alive_before_dangerous: int = unit.get_alive_count()
	if dangerous_models > 0:
		await _run_ai_dangerous(unit, dangerous_models)
	if unit.is_destroyed():
		return unit
	if bool(report.get("can_shoot", false)):
		await _run_ai_shooting(report)
	elif int(report.get("action", 0)) == AiDecision.Action.CHARGE:
		await _run_ai_melee(report)
	# END-of-activation morale from DANGEROUS-terrain wounds (GF/AoF v3.5.1 p.10/p.12 — field-test finding
	# 7): tested only NOW, AFTER the unit has acted, so dangerous damage never stops it shooting. A CHARGE
	# resolves through the melee comparison instead ("units in melee don't take morale tests from wounds at
	# the end of an activation"), so it is excluded here. should_test only fires on a real casualty at ≤half.
	if dangerous_models > 0 and not unit.is_destroyed() \
			and int(report.get("action", 0)) != AiDecision.Action.CHARGE:
		await _solo_shooting_morale(unit, alive_before_dangerous, _solo_owner_label(unit))
	return unit


# === Solo P2 — alternating activation + auto-game (goal 003 P2) ===

## OPR alternating activation: each time the HUMAN activates a unit (via the radial menu), the AI answers
## with exactly ONE activation (queued as a pending reply — re-entry-safe). The pump then runs the pure
## SoloController.alternation_next state machine, which also plays the OPR TAIL automatically: once the
## human side is exhausted the AI finishes its remaining activations on its own (maintainer field-test
## gap — F11 was needed before). Inert while no solo game is engaged (no Solo toggle and no F11 yet).
func _on_solo_human_activated(gu: GameUnit) -> void:
	if not _solo_alternation_ready(gu):
		return
	_solo_ai_took_last_activation = false   # the human just took an activation (finding 7: round-opener tracking)
	_solo_pending_replies += 1
	await _solo_pump()


## Drive the alternation state machine until it waits for the human or the round ends. TAIL activations
## (the AI playing out its remaining units unprompted) run with a readable pause between them and a
## non-blocking "AI is taking its turn" banner so the player stays oriented.
func _solo_pump() -> void:
	if solo_controller == null or _solo_ai_busy:
		return
	_solo_ai_busy = true
	var tail_count := 0
	while true:
		var step: int = SoloController.alternation_next(_solo_pending_replies,
			solo_controller.eligible_units_for(solo_controller.human_slot).size(),
			solo_controller.eligible_ai_units().size())
		if step == SoloController.AltStep.REPLY:
			_solo_pending_replies -= 1
			var replied: GameUnit = await _solo_activate_one_ai()
			_solo_flush_dev()
			if replied == null:
				_solo_pending_replies = 0   # AI side exhausted — no more replies owed this round
		elif step == SoloController.AltStep.TAIL:
			_show_solo_ai_banner()
			if tail_count > 0:
				await get_tree().create_timer(SOLO_AI_TAIL_DELAY_S).timeout
			tail_count += 1
			var tailed: GameUnit = await _solo_activate_one_ai()
			_solo_flush_dev()
			if tailed == null:
				break   # defensive: eligible flipped mid-activation
		else:
			break   # WAIT for the human, or END_ROUND (handled below)
	_hide_solo_ai_banner()
	_solo_ai_busy = false
	await _solo_after_activation()


## Non-blocking status banner while the AI plays out its tail activations (same widget pattern as the
## peer-busy banner: top-centre label, never intercepts the mouse).
func _show_solo_ai_banner() -> void:
	if is_instance_valid(_solo_ai_banner):
		return
	_solo_ai_banner = Label.new()
	_solo_ai_banner.name = "SoloAiBanner"
	_solo_ai_banner.text = "AI is taking its turn…"
	_solo_ai_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_solo_ai_banner.add_theme_font_size_override("font_size", 18)
	_solo_ai_banner.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_solo_ai_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_solo_ai_banner.add_theme_constant_override("outline_size", 4)
	_solo_ai_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	$UI.add_child(_solo_ai_banner)


func _hide_solo_ai_banner() -> void:
	if is_instance_valid(_solo_ai_banner):
		_solo_ai_banner.queue_free()
	_solo_ai_banner = null


## Whether a solo game is engaged (an army is marked for the AI, or F11 already built the controller).
func _solo_alternation_active() -> bool:
	return solo_controller != null or not solo_ai_slots.is_empty()


## Gate for the alternation trigger: solo engaged, managers ready, and the activated unit is the HUMAN's.
func _solo_alternation_ready(gu: GameUnit) -> bool:
	if opr_army_manager == null or movement_range_controller == null:
		return false
	if not _solo_alternation_active():
		return false
	if gu == null or _solo_is_ai_unit(gu):
		return false
	_ensure_solo_controller()
	return true


## After any activation chain: when BOTH sides are out of eligible units the round is over — auto-seize
## objectives, then advance the round (or end the game after SOLO_GAME_ROUNDS).
func _solo_after_activation() -> void:
	if solo_controller == null or _solo_ai_busy or not _solo_alternation_active():
		return
	if not solo_controller.eligible_units_for(solo_controller.human_slot).is_empty():
		return
	if not solo_controller.eligible_ai_units().is_empty():
		return
	await _solo_end_round()


# === AI ARENA — native both-AI mode + graded per-side difficulty ===

## Enable (or disable) native both-AI mode with a difficulty grade per side — the maintainer's graded-arena
## requirement (e.g. P1=Rekrut vs P2=Kriegsherr). Grades are SoloDifficulty preset names
## (rekrut/veteran/kriegsherr/albtraum). `base_seed` seeds the reproducible knob draws (same seed + same
## grades → identical decisions). This is the first-class setter the harness / a rating-ladder launcher calls;
## the env vars NML_BOTH_AI / NML_AI_P1 / NML_AI_P2 / NML_AI_SEED drive it too (_solo_init_arena_from_env).
func set_both_ai(enabled: bool, p1_grade: String = "kriegsherr", p2_grade: String = "kriegsherr", base_seed: int = 0) -> void:
	_solo_both_ai = enabled
	if enabled:
		solo_ai_slots = {1: true, 2: true}   # BOTH sides are AI units → _solo_is_ai_unit true both ways
		_solo_arena_seed = base_seed
		_solo_difficulty_grades = {1: p1_grade, 2: p2_grade}
	else:
		_solo_difficulty_grades = {}
	if solo_controller != null:
		_solo_apply_difficulty()


## Push the configured per-side difficulty presets onto the live controller (idempotent). No-op when no
## grades are configured, so the DEFAULT human-vs-AI flow keeps active_difficulty() == null (byte-identical).
func _solo_apply_difficulty() -> void:
	if solo_controller == null:
		return
	solo_controller.difficulty_seed = _solo_arena_seed
	solo_controller.difficulty_by_slot = {}
	for slot in _solo_difficulty_grades:
		var grade := str(_solo_difficulty_grades[slot])
		solo_controller.set_difficulty(int(slot), SoloDifficulty.for_grade(grade, _solo_arena_seed))


## Point the controller at `slot` as the acting AI and the OTHER slot as its enemy — main's combat helpers
## and the controller's target selection read human_slot, so both must flip together (the harness pattern).
func _solo_set_active_side(slot: int) -> void:
	if solo_controller == null:
		return
	solo_controller.ai_slot = slot
	solo_controller.human_slot = 2 if slot == 1 else 1


## Run a WHOLE both-AI match unattended to the SOLO_GAME_ROUNDS scoring end — the native driver the
## rating-ladder tooling calls after deploying both armies. Alternates activation between the two AI sides
## (OPR one-for-one, opener = the side that did NOT take the last activation), resolves each side's shooting /
## melee / morale on the SAME real dice tray (the AI defender auto-rolls — no dialogs), arrives Ambush
## reserves at the start of rounds ≥2 for both sides, seizes objectives at round end, and shows the summary.
func _solo_run_both_ai_game() -> void:
	if opr_army_manager == null or movement_range_controller == null:
		push_warning("[AI ARENA] not ready — import + deploy armies first")
		return
	_solo_both_ai = true
	_ensure_solo_controller()
	if solo_controller == null:
		return
	_solo_ai_busy = true
	_solo_game_finished = false
	var opener: int = 1   # round 1 opens with P1 (OPR: the deploying-first side; symmetric here)
	while not _solo_game_finished:
		var round_no: int = opr_army_manager.current_round
		if round_no >= 2:
			await _solo_both_ai_round_start(round_no)
		var last_side: int = await _solo_run_both_ai_round(opener)
		# The side that did NOT take the last activation opens the next round (GF/AoF v3.5.1 round-opener rule;
		# finding 7 — never back-to-back across the boundary). If the round had no activation, keep the opener.
		if last_side != 0:
			opener = 2 if last_side == 1 else 1
		_solo_auto_seize()
		if round_no >= SOLO_GAME_ROUNDS:
			if not _solo_game_finished:
				_solo_game_finished = true
				_solo_show_game_summary()
			break
		opr_army_manager.advance_round()
		_refresh_round_visuals()
		if network_manager != null:
			network_manager.broadcast_round_advance()
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.GENERAL, "Round %d begins" % opr_army_manager.current_round, true)
	_solo_ai_busy = false


## One both-AI round: alternate one activation per side (OPR one-for-one), starting with `opener`, until both
## sides are out of eligible units. A wiped/exhausted side is skipped so the other plays out its tail. Returns
## the side that took the LAST activation (0 if none acted) — the caller derives the next round's opener.
func _solo_run_both_ai_round(opener: int) -> int:
	var side: int = opener
	var last_side := 0
	var guard := 0
	const ACTIVATION_GUARD := 400   # defensive cap (a full army is far fewer activations than this)
	while guard < ACTIVATION_GUARD:
		guard += 1
		var other: int = 2 if side == 1 else 1
		var side_has := _solo_side_has_eligible(side)
		var other_has := _solo_side_has_eligible(other)
		if not side_has and not other_has:
			break
		var act: int = side if side_has else other
		_solo_set_active_side(act)
		var unit: GameUnit = await _solo_activate_one_ai()
		_solo_flush_dev()
		if unit != null:
			last_side = act
		side = 2 if act == 1 else 1   # alternate to the other side next (one-for-one)
	return last_side


## Whether player `slot` has an eligible AI unit right now (flips the controller's side to read its pool,
## then restores it — the same non-destructive probe the harness uses).
func _solo_side_has_eligible(slot: int) -> bool:
	if solo_controller == null:
		return false
	var prev_ai: int = solo_controller.ai_slot
	var prev_human: int = solo_controller.human_slot
	_solo_set_active_side(slot)
	var has: bool = not solo_controller.eligible_ai_units().is_empty()
	solo_controller.ai_slot = prev_ai
	solo_controller.human_slot = prev_human
	return has


## Both-AI round-start bookkeeping (round ≥2): Battleborn Shaken-recovery for every side, then Ambush
## reserve arrivals for each AI side (the arrival's >9" check reads the OTHER side as the enemy).
func _solo_both_ai_round_start(round_number: int) -> void:
	await _solo_battleborn_recovery()
	if round_number >= 2:
		for slot in [1, 2]:
			_solo_set_active_side(slot)
			await _solo_arrive_ambush()


## Read NML_BOTH_AI / NML_AI_P1 / NML_AI_P2 / NML_AI_SEED from the environment and, when NML_BOTH_AI is set,
## configure native both-AI mode with graded sides. Called once at startup; a no-op in normal play. The mode
## still needs armies imported + deployed before _solo_run_both_ai_game() is driven (a launcher/harness does that).
func _solo_init_arena_from_env() -> void:
	var flag := OS.get_environment("NML_BOTH_AI").strip_edges().to_lower()
	if flag == "" or flag == "0" or flag == "false":
		return
	var p1 := OS.get_environment("NML_AI_P1").strip_edges()
	var p2 := OS.get_environment("NML_AI_P2").strip_edges()
	var seed_env := OS.get_environment("NML_AI_SEED").strip_edges()
	set_both_ai(true, (p1 if p1 != "" else "kriegsherr"), (p2 if p2 != "" else "kriegsherr"),
		(int(seed_env) if seed_env.is_valid_int() else 0))
	print("[AI ARENA] both-AI mode armed via env — P1=%s P2=%s seed=%s" % [
		_solo_difficulty_grades.get(1, "?"), _solo_difficulty_grades.get(2, "?"), _solo_arena_seed])


## Round end in a solo game: objectives seize/contest at round end (official rule), then either the
## end-of-game summary (after SOLO_GAME_ROUNDS — the OPR standard match length) or the round advances
## exactly like the manual Next-Round button (bookkeeping + visuals + MP broadcast). OPR round-opener rule
## (GF/AoF Advanced Rules v3.5.1: "On each new round the player that finished activating first on the last
## round gets to activate first") — the side that did NOT take the last activation opens the next round, so
## a side can never take a round's last activation AND the next round's first (field-test finding 7: the AI
## activated back-to-back across the boundary because the old round-parity opener ignored who went last).
func _solo_end_round() -> void:
	_solo_auto_seize()
	if opr_army_manager.current_round >= SOLO_GAME_ROUNDS:
		if not _solo_game_finished:
			_solo_game_finished = true
			_solo_show_game_summary()
		return
	opr_army_manager.advance_round()
	_refresh_round_visuals()
	if network_manager != null:
		network_manager.broadcast_round_advance()
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL, "Round %d begins" % opr_army_manager.current_round, true)
	# ROUND-START sequence, AWAITED here so it completes BEFORE the new round's first activation (GF/AoF v3.5.1
	# p.13): Battleborn Shaken-recovery, then Ambush reserve arrivals (AI) + the human's reserve deployment
	# prompt. The former path ran these off the fire-and-forget round_advanced signal, CONCURRENTLY with the
	# opener pump below (field-test round 6, finding 4: the AI could open while reserves were still off-table or
	# the human ambush dialog was still open, and newly-arrived reserves were miscounted). Eligibility is read
	# AFTER, so a just-arrived reserve is counted for this round's alternation.
	await _solo_round_start(opr_army_manager.current_round)
	var human_has: bool = not solo_controller.eligible_units_for(solo_controller.human_slot).is_empty()
	var ai_has: bool = not solo_controller.eligible_ai_units().is_empty()
	# A new round owes NO carried-over AI replies (field-test finding 7): an undeliverable reply from last
	# round (the human took the round's last activation while the AI was already exhausted) used to survive
	# across the boundary and STACK onto the opener's grant, so the AI activated twice back-to-back when it
	# opened. The pending count is derived fresh from the opener decision — never incremented — so the opener
	# grants exactly one AI activation (GF/AoF v3.5.1 "Rounds, Turns & Activations": one-for-one alternation).
	var ai_opens: bool = SoloController.ai_opens_next_round(_solo_ai_took_last_activation, human_has, ai_has)
	_solo_pending_replies = SoloController.pending_replies_at_round_start(ai_opens)
	if ai_opens:
		# The AI opens this round with one activation; the pump's tail then drains an empty human side.
		await _solo_pump()
	# Otherwise the human opens — the pump waits for the human's own activation (the alternation resumes there).


## Objective control at round end (goal 003 P2, official rule): every marker with exactly ONE side's
## non-Shaken models within 3" is seized by (or stays with) that side; both sides near → contested/neutral;
## nobody near → the owner persists. Pure logic in SoloController.seize_objectives; owners write through the
## SAME seam as the manual radial pick (overlay + MP broadcast), which therefore stays a manual override.
func _solo_auto_seize() -> void:
	if terrain_overlay == null or opr_army_manager == null or solo_controller == null:
		return
	var objectives: Array = terrain_overlay.get_objectives()
	if objectives.is_empty():
		return
	var owners: Array = []
	for i in range(objectives.size()):
		owners.append(terrain_overlay.get_objective_owner(i))
	var round_no: int = opr_army_manager.current_round
	var infos: Array = []
	for u in opr_army_manager.get_all_game_units():
		var gu := u as GameUnit
		if gu == null or gu.get_alive_count() <= 0:
			continue
		# A unit that arrived from Ambush THIS round can neither seize nor contest (GF/AoF v3.5.1 p.13).
		var ambush_locked: bool = int(gu.unit_properties.get("ambush_arrived_round", -1)) == round_no
		infos.append({"player": int(gu.unit_properties.get("player_id", 0)), "shaken": gu.is_shaken,
			"ambush_locked": ambush_locked, "positions": solo_controller.alive_positions(gu)})
	var res: Dictionary = SoloController.seize_objectives(infos, objectives, owners)
	for c in res.get("changes", []):
		var idx: int = int((c as Dictionary).get("index", -1))
		var owner: int = int((c as Dictionary).get("owner", 0))
		terrain_overlay.set_objective_owner(idx, owner)
		# Emit the round-end ownership flip into the AI decision log too (field-test finding 1): the harness
		# reads the structured records, so a seize/contest event there makes "did the AI hold anything?"
		# measurable across a self-play run rather than only human-readable in the battle log.
		if solo_controller != null:
			solo_controller.record_decision({"kind": "seize", "unit": "objective %d" % (idx + 1),
				"rule": "Solo & Co-Op v3.5.0 p.2/p.6: a marker is held by the ONE side with non-Shaken models within 3\"",
				"candidates": [], "chosen": ("neutral (contested)" if owner == 0 else _solo_player_label(owner)),
				"why": "round-end seize", "data": {"index": idx, "owner": owner, "round": round_no}})
		if network_manager != null:
			network_manager.broadcast_objective_owner(idx, owner)
		if battle_log != null:
			if owner == 0:
				battle_log.log_event(BattleLog.Category.GENERAL, "Objective %d contested — goes neutral" % (idx + 1), true)
			else:
				battle_log.log_event(BattleLog.Category.GENERAL, "Objective %d seized by %s" % [idx + 1, _solo_player_label(owner)], true)


## Player label for logs/summary: "P<n> (<army>)" when the slot has an imported army, else "P<n>".
func _solo_player_label(pid: int) -> String:
	if opr_army_manager != null and opr_army_manager.armies.has(pid):
		var army = opr_army_manager.armies[pid]
		if army != null:
			return "P%d (%s)" % [pid, str(army.name)]
	return "P%d" % pid


## End-of-game summary (goal 003 P2): after SOLO_GAME_ROUNDS the match ends — objectives held per side
## decide the winner (OPR standard missions; with no markers on the table, surviving models break the tie).
## A battle-log block + a results dialog; the table stays as-is (the Next-Round button still works for
## anyone playing on).
func _solo_show_game_summary() -> void:
	var objectives: Array = terrain_overlay.get_objectives() if terrain_overlay != null else []
	var ai_slot := _solo_ai_slot()
	var ai_held := 0
	var human_held := 0
	var neutral := 0
	for i in range(objectives.size()):
		var o: int = terrain_overlay.get_objective_owner(i)
		if o == 0:
			neutral += 1
		elif o == ai_slot:
			ai_held += 1
		else:
			human_held += 1
	var verdict: String
	if objectives.is_empty():
		# No markers on the table: fall back to surviving models (documented tie-break, not an OPR mission).
		var ai_alive := _solo_side_alive(ai_slot)
		var human_alive := _solo_total_alive() - ai_alive
		verdict = "You win" if human_alive > ai_alive else ("The AI wins" if ai_alive > human_alive else "Draw")
	else:
		verdict = "You win" if human_held > ai_held else ("The AI wins" if ai_held > human_held else "Draw")
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL, "=== GAME OVER — %d rounds played ===" % SOLO_GAME_ROUNDS, true)
		if not objectives.is_empty():
			battle_log.log_event(BattleLog.Category.GENERAL, "Objectives — you: %d · AI: %d · neutral: %d" % [human_held, ai_held, neutral], true)
		battle_log.log_event(BattleLog.Category.GENERAL, verdict, true)
	var dlg := AcceptDialog.new()
	dlg.title = "Game over"
	var obj_block: String = ("Objectives held:\n  You: %d\n  AI: %d\n  Neutral: %d\n\n" % [human_held, ai_held, neutral]) \
		if not objectives.is_empty() else "No objective markers were on the table.\n\n"
	dlg.dialog_text = "%d rounds played.\n\n%s%s" % [SOLO_GAME_ROUNDS, obj_block, verdict]
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _solo_side_alive(pid: int) -> int:
	var n := 0
	for u in opr_army_manager.get_game_units_for_player(pid):
		if u != null:
			n += u.get_alive_count()
	return n


func _solo_total_alive() -> int:
	var n := 0
	for u in opr_army_manager.get_all_game_units():
		if u != null:
			n += u.get_alive_count()
	return n


## The slot the Solo AI plays: the first designated army, else player 2 (M1 default).
func _solo_ai_slot() -> int:
	for slot in solo_ai_slots:
		return int(slot)
	return 2


## (Re)build the SoloController for the currently designated AI slot (setup wires TurnManager once).
func _ensure_solo_controller() -> void:
	var ai_slot := _solo_ai_slot()
	# In native both-AI mode the driver flips solo_controller.ai_slot per activation, so a slot-mismatch is
	# EXPECTED and must NOT tear down the controller (that would lose the activation counter + decision log).
	if not _solo_both_ai and solo_controller != null and solo_controller.ai_slot != ai_slot:
		solo_controller.queue_free()
		solo_controller = null
	if solo_controller == null:
		solo_controller = SoloController.new()
		add_child(solo_controller)
		_solo_pending_replies = 0
		_solo_game_finished = false
		var human_slot: int = 1 if ai_slot != 1 else 2
		solo_controller.setup(opr_army_manager, network_manager, movement_range_controller, human_slot, ai_slot)
		# Terrain line of sight for the shooting decision (coarse unit-centre fallback for headless tests).
		solo_controller.los_checker = func(from_pos: Vector3, to_pos: Vector3) -> bool:
			if terrain_overlay == null or not terrain_overlay.has_method("has_line_of_sight"):
				return true
			return terrain_overlay.has_line_of_sight(from_pos, to_pos, 1, 1)
		# GEOMETRIC PER-MODEL line of sight for the AI's shoot decision — terrain + walls + other units'
		# bases (GF/AoF v3.5.1 p.5/p.8), the SAME truth the shooting resolution uses (findings 2/6/11). An
		# unbounded range makes this a pure LOS test; the decision gates range separately.
		solo_controller.unit_los_checker = func(s: GameUnit, t: GameUnit) -> bool:
			return _solo_sighted_count(s, t, SOLO_LOS_UNBOUNDED_RANGE_IN) > 0
		# Real terrain / walls / objectives feed the shared pure modules (decide_solo, MovementPlanner,
		# TerrainRules) — goal 003 P3. Each is a graceful no-op when the overlay is absent.
		solo_controller.terrain_type_at = func(p: Vector3) -> int:
			return terrain_overlay.get_terrain_at_world_position(p) if terrain_overlay != null else int(TerrainRules.TerrainType.NONE)
		solo_controller.walls_provider = func() -> Array:
			return terrain_overlay.get_wall_segments_world() if terrain_overlay != null and terrain_overlay.has_method("get_wall_segments_world") else []
		solo_controller.objectives_provider = func() -> Array:
			return terrain_overlay.get_objectives() if terrain_overlay != null else []
		solo_controller.objective_owner_of = func(index: int) -> int:
			return terrain_overlay.get_objective_owner(index) if terrain_overlay != null else 0
	_solo_apply_difficulty()


## "Deploy AI army" (goal 001 P2b): run the official OPR AI deployment for the designated army — the
## 12" front-line zone on the AI's table edge, objectives from the overlay, terrain classified per the
## solo rules (Forest=Difficult, Dangerous, Container=Impassable; Strider/Flying ignore the first two).
func _on_solo_deploy_pressed() -> void:
	if opr_army_manager == null or table == null:
		return
	_ensure_solo_controller()
	var w: float = table.table_size.x * 0.3048
	var d: float = table.table_size.y * 0.3048
	var depth: float = 12.0 * 0.0254
	var ai_slot := _solo_ai_slot()
	# Front-line zones: player 1 owns the -Z edge, everyone else the +Z edge (terrain_overlay layout).
	var zmin: float = (-d / 2.0) if ai_slot == 1 else (d / 2.0 - depth)
	var zone := Rect2(Vector2(-w / 2.0, zmin), Vector2(w, depth))
	var objectives: Array = []
	if terrain_overlay != null:
		for o in terrain_overlay.get_objectives():
			objectives.append(Vector2(o.x, o.z))
	# Physics probe against SOLID props (walls, containers, trees, free-placed sandbox ruins — those are
	# NOT in the map grid): a small sphere hovering above base height; anything tall it touches that is
	# not a miniature blocks the spot (field test: models deployed inside walls).
	var space := terrain_overlay.get_world_3d().direct_space_state if terrain_overlay != null else null
	var probe := PhysicsShapeQueryParameters3D.new()
	var probe_shape := SphereShape3D.new()
	probe_shape.radius = 0.02
	probe.shape = probe_shape
	probe.collide_with_areas = false
	var hits_prop := func(p: Vector2) -> bool:
		if space == null:
			return false
		probe.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, 0.07, p.y))
		for hit in space.intersect_shape(probe, 6):
			var col: Object = hit.get("collider")
			if col is Node3D and not (col as Node3D).is_in_group("miniature"):
				return true
		return false
	# Container/ruin WALL SEGMENTS (field-test round 6, finding 1): a container may be a SPAWNED object that
	# carries wall segments rather than a terrain-GRID cell, so `get_terrain_at_world_position` returns NONE and
	# the tiny physics probe can miss it — the deploy check must ALSO test the container/ruin walls. A sample
	# point within SOLO_DEPLOY_WALL_CLEARANCE_M of any wall segment is blocked; combined with the footprint's
	# base-edge sampling (AiDeployment) this rejects a base whose OUTER EDGE overlaps a container (finding 6).
	var wall_segs: Array = terrain_overlay.get_wall_segments_world() \
		if terrain_overlay != null and terrain_overlay.has_method("get_wall_segments_world") else []
	var near_wall := func(p: Vector2) -> bool:
		for wseg in wall_segs:
			if MovementPlanner.point_seg_distance(p, wseg[0], wseg[1]) < SOLO_DEPLOY_WALL_CLEARANCE_M:
				return true
		return false
	var blocked_normal := func(p: Vector2) -> bool:
		if hits_prop.call(p) or near_wall.call(p):
			return true
		if terrain_overlay == null:
			return false
		var t: int = terrain_overlay.get_terrain_at_world_position(Vector3(p.x, 0.0, p.y))
		return t == terrain_overlay.TerrainType.FOREST or t == terrain_overlay.TerrainType.DANGEROUS \
			or t == terrain_overlay.TerrainType.CONTAINER or t == terrain_overlay.TerrainType.RUINS
	var blocked_flying := func(p: Vector2) -> bool:
		if hits_prop.call(p) or near_wall.call(p):
			return true
		if terrain_overlay == null:
			return false
		var t: int = terrain_overlay.get_terrain_at_world_position(Vector3(p.x, 0.0, p.y))
		return t == terrain_overlay.TerrainType.CONTAINER or t == terrain_overlay.TerrainType.RUINS
	# Seeded for reproducibility (solo convention); the seed lands in the console + battle log.
	var seed_value: int = int(Time.get_unix_time_from_system()) % 100000
	var res: Dictionary = solo_controller.deploy_army(zone, objectives, blocked_normal, blocked_flying, seed_value)
	print("[Solo/AI] deployment: %d unit(s) placed, %d in ambush reserve (seed %d)" % [int(res.deployed), int(res.reserved), seed_value])
	if battle_log != null:
		var reserve_note: String = (" (%d in reserve)" % int(res.reserved)) if int(res.reserved) > 0 else ""
		battle_log.log_event(BattleLog.Category.GENERAL, "AI deploys %d units%s [seed %d]" % [int(res.deployed), reserve_note, seed_value], true)
	# Ambush reserve units are OFF-TABLE (GF/AoF v3.5.1 p.13): hide their models so they are neither
	# visible, targetable, nor perceived as "deployed" until they arrive (field-test finding 3). Arrival
	# reveals them (their single placement — field-test finding 4: no earlier phantom placement).
	for u in solo_controller.ambush_reserve:
		_solo_set_unit_visible(u as GameUnit, false)
	# YOUR OWN Ambush units are set aside too (GF/AoF v3.5.1 p.13 "May be set aside before deployment";
	# field-test finding 5: the maintainer's Ambush units were never asked for). They wait off-table and the
	# game PROMPTS you to bring them in from round 2 via guided placement (>9" from enemies, terrain-legal).
	var set_aside: Array = solo_controller.set_aside_human_ambush()
	for u in set_aside:
		_solo_set_unit_visible(u as GameUnit, false)
	if not set_aside.is_empty() and battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL,
			"You hold %d Ambush unit(s) in reserve — you'll be asked to deploy them from round 2 (GF/AoF p.13)." % set_aside.size(), false)
	_solo_flush_dev()   # render the per-unit deployment records when the dev toggle is on


## Show/hide every model node of a unit (incl. attached heroes). Keeps Ambush reserve units off the table
## until they arrive; the arrival step reveals them (findings 3/4).
func _solo_set_unit_visible(unit: GameUnit, vis: bool) -> void:
	if unit == null:
		return
	var members: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		members = members + unit.get_attached_heroes()
	for m in members:
		var member := m as GameUnit
		if member == null:
			continue
		for mi in member.models:
			var node: Node3D = (mi as ModelInstance).node
			if node != null and is_instance_valid(node):
				node.visible = vis


## Resolve the AI's shooting (goal 003 P3 — the sim's brain, real dice). SPLIT FIRE (OPR core p.8): each
## ranged weapon TYPE independently picks its own target under its targeting overlay (AiTargeting: AP→best
## Defense, Deadly→Tough, Takedown→hero, else nearest not-activated in the open); weapons aimed at the same
## target roll as one volley. Per volley: Cover (+1 Defense majority-in-cover), dead-model attack scaling,
## Relentless (>9" 6s add hits), Deadly (Tough-capped wound multiply), the human's saves, and the target's
## Regeneration medic — all via the shared pure modules, dice on the REAL tray.
func _run_ai_shooting(report: Dictionary) -> void:
	var unit: GameUnit = report.get("unit")
	if unit == null or dice_roller_control == null:
		return
	# Build a shot per ranged weapon of the unit + attached heroes (each keeps its member's Quality + alive/max).
	var shots: Array = []
	var members: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		members = members + unit.get_attached_heroes()
	for m in members:
		var member := m as GameUnit
		if member == null or member.get_alive_count() == 0:
			continue
		var weapons: Array = []
		if member.source_type == "opr" and member.source_data is OPRApiClient.OPRUnit:
			weapons = (member.source_data as OPRApiClient.OPRUnit).weapons
		var range_bonus: int = SoloController.shooting_range_bonus(member)   # Royal Legion +4" (wave 4)
		var member_profiles: Array = []
		for w in weapons:
			var base_range: int = int(w.range_value) if (w is Object and w.get("range_value") != null) else 0
			if base_range <= 0:
				continue   # melee weapon
			var prof_list: Array = AiShooting.profiles_in_range([w], float(base_range))
			if prof_list.is_empty():
				continue
			var prof := prof_list[0] as Dictionary
			# Wave 5: an expended Limited weapon no longer shoots (core v3.5.1: once per game); a
			# unit-level Shred grant marks every weapon profile (the weapon facet is already parsed).
			if bool(prof.get("limited", false)) and solo_controller.is_limited_used(member, prof):
				continue
			if RulesRegistry.unit_rule_active(member, "Shred"):
				prof["shred"] = true
			member_profiles.append(prof)
			# `reach` (target validity + per-model sighting) includes the unit's range bonus, so a Royal
			# Legion unit shoots targets up to +4" beyond the weapon's printed range.
			shots.append({"member": member, "quality": member.get_quality(),
				"alive": member.get_alive_count(), "max": member.models.size(),
				"reach": base_range + range_bonus, "profile": prof})
		# Wave 5 Sergeant (model-level): the member's FIRST firing profile carries the bearer's share.
		AiEv.stamp_sergeant(member_profiles, member)
	if shots.is_empty():
		return
	# Split fire: assign each shot the best target under its weapon overlay, then group shots by target.
	# Target validity is PER MODEL (GF v3.5.1 p.8): the shot's MEMBER needs a model with range+LOS.
	var groups: Dictionary = {}   # target unit_id -> {"target": GameUnit, "shots": Array}
	var order: Array = []
	for shot in shots:
		var overlay: int = AiTargeting.weapon_overlay((shot["profile"] as Dictionary).get("rules", []))
		var tgt: GameUnit = _solo_pick_overlay_target(shot["member"], overlay, float(shot["reach"]), shot["profile"] as Dictionary)
		if tgt == null:
			continue
		if not groups.has(tgt.unit_id):
			groups[tgt.unit_id] = {"target": tgt, "shots": []}
			order.append(tgt.unit_id)
		(groups[tgt.unit_id]["shots"] as Array).append(shot)
	# Indirect (wave 5): "-1 to hit rolls when shooting after moving" — the activation's action says
	# whether this unit moved before firing (HOLD = it did not).
	var moved: bool = bool(report.get("moved", false))
	for id in order:
		var g := groups[id] as Dictionary
		await _solo_resolve_ai_volley(unit, g["target"], g["shots"], moved)


## Resolve one split-fire volley (all `shots` aimed at `target`) with real tray dice + the human's saves.
## Per-model shooting (GF v3.5.1 p.8 "Who Can Shoot"): each shot's attacks scale by the member's models
## that actually have range AND line of sight to the target — not by its whole living count. `moved` is
## the activation's move state (Indirect's -1 to hit fires only when shooting after moving — wave 5).
func _solo_resolve_ai_volley(attacker: GameUnit, target: GameUnit, shots: Array, moved: bool = false) -> void:
	var alive_before: int = target.get_alive_count()
	var models_before: int = _solo_combined_alive(target)
	# Armor(X) (wave 5, army-book upgrade: "counts as having Defense X+") sets the working Defense,
	# then Shielded (+1 Defense, army-book rule) covers every hit; Cover (GF v3.5.1 p.11) is ignored
	# by Blast and by Indirect (wave 5: "ignores cover from sight obstructions").
	_solo_log_armor(target)
	var base_defense: int = _solo_shielded_defense(target)
	if base_defense != _solo_armored_defense(target) and battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT, "%s is Shielded: +1 Defense (saves on %d+)" % [
			target.get_name(), base_defense], true)
	var covered_defense: int = _solo_cover_defense(target, base_defense)   # +1 Defense if majority in cover
	var dist_in: float = MoveIntent.distance_inches(solo_controller.unit_centre(attacker), solo_controller.unit_centre(target))
	# ANNOUNCE: who shoots at whom — highlights + attack line + toast, held before any die is thrown.
	var announce := _solo_show_attack_announce(attacker, target, "fires at")
	await _solo_pace_hold(SoloController.Pace.ANNOUNCE)
	var regenable := 0
	var regen_proof := 0
	var total_hits := 0
	var total_caused := 0
	for s in shots:
		var shot := s as Dictionary
		var profile := shot["profile"] as Dictionary
		var member := shot["member"] as GameUnit
		# Reliable (GF v3.5.1) sets the Quality (2+); the to-hit roll modifiers (Stealth / Artillery /
		# Evasive, and Indirect's moved-shooting -1 — wave 5) then apply on top ("Reliable only changes
		# the Quality value", p.14).
		var mod_info: Dictionary = _solo_hit_mod_info(member, target, dist_in, false)
		if moved and bool(profile.get("indirect", false)):
			var indirect_mod: int = AiCombatMath.indirect_hit_modifier(true,
				int(RulesRegistry.unit_param(member, "Indirect", "moved_hit_penalty", AiCombatMath.INDIRECT_MOVED_HIT_PENALTY)))
			mod_info = {"mod": int(mod_info.get("mod", 0)) + indirect_mod,
				"note": _solo_join_note(str(mod_info.get("note", "")), "Indirect moved %d" % indirect_mod)}
		var to_hit: int = AiCombatMath.modified_hit_target(
			AiCombatMath.reliable_quality(int(shot["quality"]), bool(profile.get("reliable", false))), int(mod_info.get("mod", 0)))
		_solo_log_hit_mod(mod_info, target, to_hit)
		# Indirect (wave 5) targets as if in line of sight — its per-model sighting is range-only.
		var sighted: int = _solo_sighted_count(member, target, int(shot["reach"]), bool(profile.get("indirect", false)))
		var attacks: int = SoloController.effective_attacks(int(profile.get("attacks", 0)), sighted, int(shot["max"]))
		if attacks <= 0:
			continue
		var shooter_name: String = member.get_name()
		var faces: Array = await _solo_tray_roll(attacks, to_hit, "AI (%s)" % shooter_name)
		if bool(profile.get("limited", false)):
			solo_controller.mark_limited_used(member, profile)   # once per game — spent on the roll (wave 5)
		var hits: int = _solo_hits(faces, to_hit, profile, dist_in, target)
		if battle_log != null:
			var sight_note: String = "" if sighted >= member.get_alive_count() else " (%d/%d models sighted)" % [sighted, member.get_alive_count()]
			battle_log.log_event(BattleLog.Category.COMBAT, "%s fires %s at %s%s — %d hit%s" % [
				shooter_name, str(profile.get("name", "?")), target.get_name(), sight_note, hits, ("" if hits == 1 else "s")], true)
		if hits <= 0:
			continue
		total_hits += hits
		# Blast ignores cover (GF v3.5.1), and so does Indirect (wave 5: "ignores cover from sight
		# obstructions") — their saves roll against the UNCOVERED Defense. Rending/Bane (unmodified-6
		# save-step rules) resolve inside _solo_resolve_saves. Native both-AI (AI ARENA): when the
		# DEFENDER is itself AI, the saves auto-roll on the real tray (no human prompt) — the human_defends flag
		# is derived, never assumed, so an AI-vs-AI game resolves shooting unattended.
		var save_def: int = base_defense if (int(profile.get("blast", 0)) > 1 or bool(profile.get("indirect", false))) else covered_defense
		var w: int = await _solo_resolve_saves(member, target, str(profile.get("name", "?")), faces, hits, save_def, profile, not _solo_is_ai_unit(target), false)
		total_caused += w
		if _solo_ignores_regen(member, profile):
			regen_proof += w
		else:
			regenable += w
	var landed: int = await _solo_land_wounds(target, regenable, regen_proof)
	_solo_clear_announce(announce)
	# OUTCOME: one readable summary line, held on screen (toast + battle log).
	await _solo_show_outcome("%s: %d hit%s → %d wound%s land — %s loses %d model%s" % [
		target.get_name(), total_hits, ("" if total_hits == 1 else "s"),
		landed, ("" if landed == 1 else "s"), target.get_name(),
		models_before - _solo_combined_alive(target), ("" if models_before - _solo_combined_alive(target) == 1 else "s")])
	if landed > 0:
		await _solo_shooting_morale(target, alive_before, _solo_owner_label(target))


## Pick the AI's shooting target for a weapon overlay (goal 003 P3): every alive HUMAN unit in range with a
## clear line of sight, ranked by AiTargeting under `overlay`. Validity is PER MODEL (GF v3.5.1 p.8: a
## target is valid when at least one of the shooting member's models has range + LOS to one of its
## models); attached heroes are never separate targets (they are part of their host unit). Null when
## nothing is valid.
func _solo_pick_overlay_target(attacker: GameUnit, overlay: int, max_range: float, profile: Dictionary = {}) -> GameUnit:
	if opr_army_manager == null or solo_controller == null:
		return null
	var from := solo_controller.unit_centre(attacker)
	var att_ctx: Dictionary = AiEv.ctx_for(attacker)
	var cands: Array = []
	var refs: Array = []
	var evs: Array = []
	var dists: Array = []
	for h in opr_army_manager.get_game_units_for_player(solo_controller.human_slot):
		var hu := h as GameUnit
		if hu == null or _solo_combined_alive(hu) <= 0 or SoloController.unit_in_reserve(hu):
			continue   # skip empty units and any still off-table in Ambush reserve (findings 3/4)
		if hu.has_method("is_attached") and hu.is_attached():
			continue   # a joined hero is targeted through its host unit, never alone
		if _solo_sighted_count(attacker, hu, int(max_range), bool(profile.get("indirect", false))) <= 0:
			continue   # no model of the shooter has range + LOS → not a valid target (p.8; Indirect waives LOS)
		var dist := MoveIntent.distance_inches(from, solo_controller.unit_centre(hu))
		var in_cover := _solo_majority_in_cover(hu)
		var tough: int = _solo_unit_tough(hu)
		# The official key's "nearest" compares in 1" bands (SoloController.TARGET_TIE_BAND_IN — tabletop
		# measuring precision); a genuine tie is where the rules would roll a die, resolved by EV below.
		cands.append({
			"dist": floorf(dist / SoloController.TARGET_TIE_BAND_IN), "activated": hu.is_activated,
			"in_cover": in_cover,
			# Armor(X) counts as Defense X+ (wave 5) — the overlay key ranks the REAL save value.
			"defense": _solo_armored_defense(hu), "is_hero": hu.is_hero(), "has_upgrade": false, "upgrade_cost": 0,
			"single_tough": hu.models.size() == 1 and tough > 1, "has_tough": tough > 1,
			"remaining_tough": hu.get_alive_count() * tough,
		})
		refs.append(hu)
		dists.append(dist)
		# Expected wounds of THIS weapon profile vs THIS defender — every wave-1..3 rule flows through
		# the shared AiEv/AiCombatMath math (Deadly→Tough, Blast→big units, >9" Stealth devalued, …).
		evs.append(AiEv.profile_ev(profile, att_ctx, AiEv.ctx_for(hu, in_cover, 0), dist, false) if not profile.is_empty() else 0.0)
	var idx: int = AiTargeting.best_index(cands, overlay)
	if idx < 0:
		return null
	var why := "official overlay key"
	# Genuine ties under the FULL official key (overlay tier + not-activated + open + banded nearest) —
	# the hybrid policy ranks them by EV instead of the rules' die roll.
	var tied: Array = AiTargeting.tied_with_best(cands, overlay, idx)
	if tied.size() > 1 and not profile.is_empty():
		for j in tied:
			if float(evs[int(j)]) > float(evs[idx]):
				idx = int(j)
		why = "ev tie-break"
	var rec_cands: Array = []
	for i in range(refs.size()):
		rec_cands.append({"name": (refs[i] as GameUnit).get_name(), "ev": float(evs[i]),
			"key": [bool(cands[i]["activated"]), bool(cands[i]["in_cover"]), float(dists[i])]})
	solo_controller.record_decision({"kind": "target", "unit": attacker.get_name(),
		"rule": "Solo v3.5.0 p.2: nearest/not-activated/open + weapon overlay",
		"candidates": rec_cands, "chosen": (refs[idx] as GameUnit).get_name(), "why": why,
		"data": {"overlay": overlay, "weapon": str(profile.get("name", "")), "considered": refs.size()}})
	return refs[idx]


## Models of `shooter` with BOTH range and line of sight to at least one model of `target` (per-model
## shooting, GF v3.5.1 p.8) — the pure SoloController.sighted_models against the real overlay LOS. The
## target's models include its attached heroes' (they are part of the unit). `ignore_los` (wave 5,
## Indirect: "may target enemies that are not in line of sight as if in line of sight") keeps the range
## gate but waives the sight test.
func _solo_sighted_count(shooter: GameUnit, target: GameUnit, range_in: int, ignore_los: bool = false) -> int:
	if shooter == null or target == null or solo_controller == null:
		return 0
	var target_positions: Array = []
	var target_members: Array = [target]
	if target.has_method("get_attached_heroes"):
		target_members = target_members + target.get_attached_heroes()
	for tm in target_members:
		if tm != null:
			target_positions.append_array(solo_controller.alive_positions(tm))
	var los: Callable
	if ignore_los:
		los = func(_sp: Vector3, _tp: Vector3) -> bool: return true
	else:
		los = _solo_true_los_callable(shooter, target)
	return SoloController.sighted_models(solo_controller.alive_positions(shooter), target_positions,
		float(range_in) * MoveIntent.INCHES_TO_METERS, los)


## GEOMETRIC PER-MODEL line of sight for a shooter→target model pair (GF/AoF v3.5.1 p.5: "Models can't see
## through solid obstacles, including the perimeter of other units (friendly or enemy), but they can always
## see through friendly models from their own unit."; p.8 "Who Can Shoot" is PER MODEL). The sight line is
## blocked by (a) blocking terrain zones (the grid "see in/out, not through" rule — AREA terrain Forests +
## Ruins let you see INTO/OUT of them but not all the way THROUGH; solid Buildings/Containers hard-block) and
## (b) the base of ANY OTHER unit's model — never the shooter's or the target's own unit (you can always see
## the target and through your own models). Heights follow the Asgard rule: a blocker only stops the line
## when its Height ≥ BOTH endpoint units' Heights (a taller model sees over a smaller one). RUINS are AREA
## terrain (GF/AoF v3.5.1 p.12, applied per maintainer correction to field-test round-4, which over-corrected
## ruins to fully see-through): a model sees into/out of ruins but a line drawn THROUGH them to a far-side
## target is blocked — exactly like a forest. Their low walls also block MOVEMENT (the movement planner treats
## them as impassable). Blocker list + endpoint heights are built ONCE per pair; the returned Callable(sp, tp)
## is what SoloController.sighted_models runs per shooter-model × target-model pair (findings 2/6/11).
func _solo_true_los_callable(shooter: GameUnit, target: GameUnit) -> Callable:
	var overlay := terrain_overlay
	var blockers: Array[LosRules.Blocker] = _solo_los_blockers(shooter, target)
	var from_h: int = _solo_unit_los_height(shooter)
	var to_h: int = _solo_unit_los_height(target)
	return func(sp: Vector3, tp: Vector3) -> bool:
		if overlay != null and overlay.has_method("has_line_of_sight") \
				and not overlay.has_line_of_sight(sp, tp, from_h, to_h):
			return false   # (a) blocking terrain (area Forest/Ruins — see in/out, not through; Container hard-blocks)
		var a2 := Vector2(sp.x, sp.z)
		var b2 := Vector2(tp.x, tp.z)
		# Blockers already exclude the shooter's and target's own units, so no per-call exclude list is needed.
		if not blockers.is_empty() and LosRules.units_block_line(a2, b2, from_h, to_h, blockers, ([] as Array[int])):
			return false   # (b) another unit's base (perimeter of other units)
		return true


## Every OTHER unit's alive models as LOS blockers (LosRules.Blocker: base circle + Asgard Height + a
## per-unit key for the <1" gap-closure). The shooter's and the target's own units — and their attached
## heroes — are excluded (p.5: you always see through your own unit and can always see the target).
func _solo_los_blockers(exclude_a: GameUnit, exclude_b: GameUnit) -> Array[LosRules.Blocker]:
	var out: Array[LosRules.Blocker] = []
	if opr_army_manager == null:
		return out
	var excluded := {}
	for u in [exclude_a, exclude_b]:
		if u == null:
			continue
		excluded[u.get_instance_id()] = true
		if u.has_method("get_attached_heroes"):
			for h in u.get_attached_heroes():
				if h != null:
					excluded[h.get_instance_id()] = true
	for g in opr_army_manager.get_all_game_units():
		var gu := g as GameUnit
		if gu == null or excluded.has(gu.get_instance_id()) or SoloController.unit_in_reserve(gu):
			continue   # a reserve unit is off-table — it blocks no sight lines (findings 3/4)
		var key: int = gu.get_instance_id()
		for m in gu.get_alive_models():
			var node: Node3D = (m as ModelInstance).node
			if node == null or not is_instance_valid(node):
				continue
			out.append(LosRules.Blocker.new(Vector2(node.global_position.x, node.global_position.z),
				SoloController.model_base_radius_m(m), LosRules.model_height_category(m), key))
	return out


## Representative Asgard Height of a unit (the tallest of its alive models incl. attached heroes; H2
## infantry default): a taller unit sees over smaller blockers, matching LosRules.units_block_line.
func _solo_unit_los_height(unit: GameUnit) -> int:
	var h: int = LosRules.HEIGHT_INFANTRY
	if unit == null:
		return h
	var members: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		members = members + unit.get_attached_heroes()
	for mm in members:
		var member := mm as GameUnit
		if member == null:
			continue
		for m in member.get_alive_models():
			h = maxi(h, LosRules.model_height_category(m))
	return h


## Weapon groups for a combat activation: the unit's own profiles at its Quality PLUS each attached hero's
## profiles at the hero's Quality — a joined hero fights WITH its unit (field-test lock). Each profile's
## attack count is SCALED so dead models no longer attack (goal 003 P3, mirrors the sim fix): shooting scales
## by alive/max; melee (with `enemy`) scales by the models within 2" of an enemy model ("Who Can Strike", p.9).
func _solo_attack_groups(unit: GameUnit, dist_in: float, melee: bool, enemy: GameUnit = null) -> Array:
	var members: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		members = members + unit.get_attached_heroes()
	var enemy_positions: Array = solo_controller.alive_positions(enemy) if (melee and enemy != null and solo_controller != null) else []
	var groups: Array = []
	for m in members:
		var member := m as GameUnit
		if member == null or member.get_alive_count() == 0:
			continue
		var weapons: Array = []
		if member.source_type == "opr" and member.source_data is OPRApiClient.OPRUnit:
			weapons = (member.source_data as OPRApiClient.OPRUnit).weapons
		var profiles: Array = AiShooting.melee_profiles(weapons) if melee else AiShooting.profiles_in_range(weapons, dist_in)
		if profiles.is_empty():
			continue
		var max_models: int = member.models.size()
		var melee_count: int = member.get_alive_count()
		if melee and enemy != null and solo_controller != null:
			melee_count = SoloController.striking_models(solo_controller.alive_positions(member), enemy_positions)
		var scaled: Array = []
		var member_shred: bool = RulesRegistry.unit_rule_active(member, "Shred")   # unit-level grant (wave 5)
		for p in profiles:
			var prof := (p as Dictionary).duplicate()
			# Wave 5 Limited (core v3.5.1: once per game): an expended profile no longer fights.
			if bool(prof.get("limited", false)) and solo_controller != null and solo_controller.is_limited_used(member, prof):
				continue
			# Furious (GF/AoF v3.5.1 p.14) is a UNIT rule (not on the weapon), so stamp it from the member
			# onto each melee profile; _solo_hits reads it alongside the weapon's own Surge/Rending facets.
			if melee:
				prof["furious"] = member.has_special_rule("Furious")
				# Counter (p.13) is usually a weapon rule (parsed by AiShooting) but can be granted
				# unit-wide — fold the member's unit rule onto every melee profile for the strike filter.
				if member.has_special_rule("Counter"):
					prof["counter"] = true
			# Shred can be granted at unit level too (wave 5) — mark every profile of that member.
			if member_shred:
				prof["shred"] = true
			# Per-model shooting (GF v3.5.1 p.8): a ranged profile fires with the member's models that
			# have range + LOS at ITS OWN range; melee scales by the models within 2" strike reach (p.9).
			var count: int = melee_count
			if not melee:
				count = _solo_sighted_count(member, enemy, int(prof.get("range", 0)), bool(prof.get("indirect", false))) if enemy != null else member.get_alive_count()
			prof["attacks"] = SoloController.effective_attacks(int(prof.get("attacks", 0)), count, max_models)
			scaled.append(prof)
		# Wave 5 Sergeant (model-level): ONE profile per member carries the bearer's attack share.
		AiEv.stamp_sergeant(scaled, member)
		groups.append({"name": member.get_name(), "quality": member.get_quality(),
			"fatigued": member.is_fatigued, "member": member, "profiles": scaled})
	return groups


# === Solo combat facets (goal 003 P3 — shared pure-module math: cover / hits / wounds / regen / tough) ===

## The defender's save target after Cover (GF Advanced Rules v3.5.1 p.11): the majority of a target's models
## in cover terrain gives +1 Defense (a better, lower save target), floored at 2+. Shooting only. The
## arithmetic is the shared AiCombatMath.covered_defense (one truth with the EV metric).
func _solo_cover_defense(target: GameUnit, base_defense: int) -> int:
	return AiCombatMath.covered_defense(base_defense, _solo_majority_in_cover(target))


## Hits from a to-hit roll, plus the "on an unmodified 6" bonus-hit rules and Blast. Relentless (>9"
## shooting: each unmodified 6 adds a hit; `dist_in`=0 in melee yields no bonus), Surge (each unmodified 6
## adds a hit at ANY range — shooting or melee), and Furious (each unmodified 6 in melee adds a hit, but
## only for the CHARGING unit — `charging`). Those extra hits resolve BEFORE Blast(X) (GF v3.5.1: Blast
## multiplies "after resolving other special rules"), which then scales each hit ×min(X, target models).
## Every multiplication is battle-logged so it is VISIBLE. Uses the shared AiCombatMath.
func _solo_hits(faces: Array, to_hit: int, profile: Dictionary, dist_in: float, target: GameUnit = null, charging: bool = false) -> int:
	var hits: int = AiCombatMath.count_hits(faces, to_hit)
	if bool(profile.get("relentless", false)):
		hits += AiCombatMath.relentless_bonus_hits(faces, dist_in)
	if bool(profile.get("surge", false)):
		hits += AiCombatMath.surge_bonus_hits(faces)
	if bool(profile.get("furious", false)):
		hits += AiCombatMath.furious_bonus_hits(faces, charging)
	# Sergeant (wave 5, model-level: the bearer's unmodified 6s deal +1 hit — stamped onto ONE profile
	# per member by AiEv.stamp_sergeant; the bonus is capped at the bearer's own attack share).
	var sergeant_attacks: int = int(profile.get("sergeant_attacks", 0))
	if sergeant_attacks > 0:
		var sergeant_hits: int = AiCombatMath.sergeant_bonus_hits(faces, sergeant_attacks)
		if sergeant_hits > 0 and battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "Sergeant: +%d hit%s (unmodified 6s)" % [
				sergeant_hits, ("" if sergeant_hits == 1 else "s")], true)
		hits += sergeant_hits
	var blast: int = int(profile.get("blast", 0))
	if hits > 0 and blast > 1 and target != null:
		var boosted: int = AiCombatMath.blast_hits(hits, blast, _solo_combined_alive(target))
		if boosted != hits and battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "Blast(%d): %d hit%s ×%d → %d hits" % [
				blast, hits, ("" if hits == 1 else "s"), boosted / hits, boosted], true)
		hits = boosted
	return hits


## Rating X of a unit-level "Name(X)" special rule (0 if absent), e.g. Impact(3) / Fear(2) — the shared
## AiEv.unit_rating reader (one truth between the dice resolution and the EV metric).
func _solo_unit_rating(unit: GameUnit, rule_name: String) -> int:
	return AiEv.unit_rating(unit, rule_name)


## A weapon profile with Thrust's charge AP bonus folded in (GF/AoF v3.5.1 p.14: "+1 to hit rolls and
## AP(+1) in melee" when charging). The +1 to-hit is applied by the caller via AiCombatMath.thrust_to_hit;
## this folds AP(+1). Returns the profile unchanged when the weapon lacks Thrust or the unit is not
## charging, and never mutates the input.
func _solo_thrust_profile(profile: Dictionary, charging: bool) -> Dictionary:
	if not charging or not bool(profile.get("thrust", false)):
		return profile
	var eff := profile.duplicate()
	eff["ap"] = int(profile.get("ap", 0)) + AiCombatMath.THRUST_AP_BONUS
	return eff


## Wave-3 melee strike-phase filter (Counter, GF/AoF v3.5.1 p.13: "Strikes first with this weapon when
## charged"): a charged defender's Counter weapons resolve as a phase BEFORE the charger's attacks; its
## remaining weapons strike in the normal strike-back slot.
enum SoloStrike { ALL, COUNTER_ONLY, NON_COUNTER }


## Whether ALL models of a unit carry `rule` — the trigger form of Stealth / Evasive / Shielded. The
## shared AiEv.rule_on_all_models reader (one truth between the dice resolution and the EV metric).
func _solo_rule_on_all_models(unit: GameUnit, rule: String) -> bool:
	return AiEv.rule_on_all_models(unit, rule)


## The defender's Defense value after Shielded (army-book rule: "+1 to defense rolls against hits that are
## not from spells" — the solo automation has no spells, so every hit qualifies). Shared by every save site
## so the prompts/logs show the modified value. Wave 5: Armor(X) ("counts as having Defense X+") sets the
## working Defense FIRST — one seam, so shooting, melee, Impact and the EV metric all see the same value.
func _solo_shielded_defense(target: GameUnit) -> int:
	return AiCombatMath.shielded_defense(_solo_armored_defense(target), _solo_rule_on_all_models(target, "Shielded"))


## The unit's Armor(X) rating (wave 5, army-book upgrade), 0 when absent or when its book does not field
## the rule for this game system (RulesRegistry gate — never a cross-system name-only match).
func _solo_armor_rating(target: GameUnit) -> int:
	if target == null or not RulesRegistry.unit_rule_active(target, "Armor"):
		return 0
	return _solo_unit_rating(target, "Armor")


## The unit's Defense after Armor(X) ("counts as having Defense X+", best-of — AiCombatMath.armored_defense,
## the same math the EV context uses). Equals get_defense() for unarmored units.
func _solo_armored_defense(target: GameUnit) -> int:
	return AiCombatMath.armored_defense(target.get_defense(), _solo_armor_rating(target))


## Battle-log Armor(X) when it actually improves the working Defense (visible rule application, wave 5).
func _solo_log_armor(target: GameUnit) -> void:
	var armored: int = _solo_armored_defense(target)
	if armored != target.get_defense() and battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT, "%s has Armor(%d): counts as Defense %d+" % [
			target.get_name(), _solo_armor_rating(target), armored], true)


## Compose two to-hit-modifier note fragments ("Stealth -1" + "Indirect moved -1") into one log note.
static func _solo_join_note(a: String, b: String) -> String:
	if a.is_empty():
		return b
	return "%s, %s" % [a, b] if not b.is_empty() else a


## Net to-hit roll modifier for one attack + its reasons (for the battle log): Stealth (−1, shot >9"),
## Artillery (+1 shooting >9" / −2 shot at >9") and Evasive (−1, any attack) — GF/AoF v3.5.1 p.13/14 +
## the army-book Evasive text. Returns {"mod": int, "note": String}; the math is the tested
## AiCombatMath.shooting_hit_modifier / melee_hit_modifier.
func _solo_hit_mod_info(shooter_member: GameUnit, target: GameUnit, dist_in: float, melee: bool) -> Dictionary:
	var evasive: bool = _solo_rule_on_all_models(target, "Evasive")
	if melee:
		var mm: int = AiCombatMath.melee_hit_modifier(evasive)
		return {"mod": mm, "note": "Evasive -1" if mm != 0 else ""}
	var attacker_artillery: bool = shooter_member != null and shooter_member.has_special_rule("Artillery")
	var stealth: bool = _solo_rule_on_all_models(target, "Stealth")
	var target_artillery: bool = target.has_special_rule("Artillery")
	var mod: int = AiCombatMath.shooting_hit_modifier(dist_in, attacker_artillery, stealth, target_artillery, evasive)
	var notes: PackedStringArray = []
	var over_nine: bool = dist_in > AiCombatMath.LONG_RANGE_IN
	if attacker_artillery and over_nine:
		notes.append("Artillery +1")
	if stealth and over_nine:
		notes.append("Stealth -1")
	if target_artillery and over_nine:
		notes.append("Artillery target -2")
	if evasive:
		notes.append("Evasive -1")
	return {"mod": mod, "note": ", ".join(notes)}


## Battle-log line naming an applied to-hit modifier and the resulting threshold (transparency: the tray
## shows the modified target, this line explains WHY). Silent when the net modifier is zero.
func _solo_log_hit_mod(info: Dictionary, target: GameUnit, to_hit: int) -> void:
	if int(info.get("mod", 0)) == 0 or battle_log == null:
		return
	battle_log.log_event(BattleLog.Category.COMBAT, "To-hit vs %s: %s → hits on %d+" % [
		target.get_name(), str(info.get("note", "")), to_hit], true)


## Whether a unit (incl. attached heroes) fights with Counter (GF/AoF v3.5.1 p.13) — a Counter melee
## weapon or the rule granted unit-wide. Gates the strike-first phase.
func _solo_has_counter(unit: GameUnit) -> bool:
	var members: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		members = members + unit.get_attached_heroes()
	for m in members:
		var member := m as GameUnit
		if member == null or member.get_alive_count() == 0:
			continue
		var weapons: Array = []
		if member.source_type == "opr" and member.source_data is OPRApiClient.OPRUnit:
			weapons = (member.source_data as OPRApiClient.OPRUnit).weapons
		if SoloController.has_counter(AiShooting.melee_profiles(weapons), member.get_special_rules()):
			return true
	return false


## Alive models of a unit (incl. attached heroes) that fight with Counter — the shared
## SoloController.counter_models_of walk (one truth between the dice resolution and the EV metric).
func _solo_counter_models(unit: GameUnit) -> int:
	return SoloController.counter_models_of(unit)


## Resolve one side's melee strikes against `defender` and LAND the wounds (Regeneration-bucketed): the
## striker's groups (unit + attached heroes; attacks pre-scaled by the 2" reach) roll real to-hit dice,
## saves resolve via _solo_resolve_saves (prompted when the human defends, AI auto-saves otherwise).
## `charging` applies the Furious / Thrust charge bonuses; Evasive (−1 to hit) and Shielded (+1 Defense)
## modify per the defender's rules; `filter` (SoloStrike) scopes the phase for Counter strike-first.
## Fatigue (unmodified-6-only) overrides all to-hit modifiers. Returns wounds caused (melee-winner tally).
func _solo_melee_strike_phase(striker: GameUnit, defender: GameUnit, charging: bool, filter: int) -> int:
	var human_defends: bool = not _solo_is_ai_unit(defender)
	_solo_log_armor(defender)   # Armor(X) "counts as Defense X+" (wave 5) — folded into _solo_shielded_defense
	var defense: int = _solo_shielded_defense(defender)
	if defense != _solo_armored_defense(defender) and battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT, "%s is Shielded: +1 Defense (saves on %d+)" % [
			defender.get_name(), defense], true)
	var mod_info: Dictionary = _solo_hit_mod_info(striker, defender, 0.0, true)
	# Wave-4 Unpredictable Fighter (Mummified Undead army-book rule): ONE die per melee for the whole unit —
	# 1-3 → AP(+1) on its melee weapons, 4-6 → +1 to hit (fatigue's unmodified-6-only overrides the +1).
	var uf_ap := 0
	var uf_hit := 0
	if _solo_rule_on_all_models(striker, "Unpredictable Fighter"):
		var uf_owner: String = ("AI (%s)" % striker.get_name()) if _solo_is_ai_unit(striker) else "You"
		var uf_face: Array = await _solo_tray_roll(1, AiCombatMath.BEST_HIT_TARGET, uf_owner)
		if not uf_face.is_empty():
			var uf_eff: Dictionary = AiCombatMath.unpredictable_fighter_effect(int(uf_face[0]))
			uf_ap = int(uf_eff["ap"])
			uf_hit = int(uf_eff["hit"])
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "Unpredictable Fighter: %s rolls %d → %s" % [
					striker.get_name(), int(uf_face[0]), ("AP(+1)" if uf_ap > 0 else "+1 to hit")], true)
	var caused := 0
	var regenable := 0
	var regen_proof := 0
	var struck_any := false   # did ANY weapon profile actually roll? (finding 8: surface a silent no-strike)
	for grp in _solo_attack_groups(striker, 0.0, true, defender):
		var group := grp as Dictionary
		var base_quality: int = int(group.get("quality", 4))
		var fatigued: bool = bool(group.get("fatigued", false))
		for p in group.get("profiles", []):
			var profile := p as Dictionary
			if int(profile.get("attacks", 0)) <= 0:
				continue
			if filter == SoloStrike.COUNTER_ONLY and not bool(profile.get("counter", false)):
				continue
			if filter == SoloStrike.NON_COUNTER and bool(profile.get("counter", false)):
				continue
			struck_any = true
			# Reliable (GF/AoF v3.5.1 p.14: the weapon "shoots at Quality 2+") sets the base Quality FIRST —
			# it applies to a Reliable MELEE weapon exactly as it does when shooting (field-test finding 9: the
			# melee strike path dropped it, so a Reliable strike still rolled at the unit's Quality). Thrust
			# (+1 to hit on a charge), Evasive (−1) and Unpredictable Fighter's +1 then compose on top ("Reliable
			# only changes the Quality value, so the roll can still be modified", p.14); fatigue (unmodified-6-
			# only) overrides every to-hit modifier.
			var strike_quality: int = AiCombatMath.reliable_quality(base_quality, bool(profile.get("reliable", false)))
			var to_hit: int = 6 if fatigued else AiCombatMath.modified_hit_target(
				AiCombatMath.thrust_to_hit(strike_quality, bool(profile.get("thrust", false))), int(mod_info.get("mod", 0)) + uf_hit)
			if not fatigued:
				_solo_log_hit_mod(mod_info, defender, to_hit)
			var roll_owner: String = ("AI (%s)" % str(group.get("name", "?"))) if _solo_is_ai_unit(striker) else "You"
			var faces: Array = await _solo_tray_roll(int(profile.get("attacks", 0)), to_hit, roll_owner)
			if bool(profile.get("limited", false)):
				solo_controller.mark_limited_used(group.get("member"), profile)   # once per game (wave 5)
			var hits: int = _solo_hits(faces, to_hit, profile, 0.0, defender, charging)
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s strikes with %s at %s — %d hit%s" % [
					str(group.get("name", "?")), str(profile.get("name", "?")), defender.get_name(), hits, ("" if hits == 1 else "s")], true)
			if hits <= 0:
				continue
			var eff: Dictionary = _solo_thrust_profile(profile, charging)   # AP(+1) on charge
			if uf_ap > 0:   # Unpredictable Fighter 1-3 → AP(+1) melee (never mutate the source profile)
				eff = eff.duplicate()
				eff["ap"] = int(eff.get("ap", 0)) + uf_ap
			var w: int = await _solo_resolve_saves(group.get("member"), defender, str(profile.get("name", "?")), faces, hits, defense, eff, human_defends, true)
			caused += w
			if _solo_ignores_regen(group.get("member"), eff):
				regen_proof += w
			else:
				regenable += w
	if regenable + regen_proof > 0:
		await _solo_land_wounds(defender, regenable, regen_proof)
	# A charger (or full strike-back) that rolled NOTHING was silently skipped in the log, so a legitimate
	# fight looked one-sided (field-test finding 8: the walker charger's strikes never appeared — it had no
	# melee-weapon profile in reach). Surface it on the FULL strike so both combatants' resolution is shown;
	# the Counter-only / non-Counter sub-phases legitimately roll nothing when the unit lacks those weapons.
	if not struck_any and filter == SoloStrike.ALL and battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT,
			"%s has no melee weapons in reach — no strikes (GF/AoF v3.5.1 p.9)" % striker.get_name(),
			_solo_is_ai_unit(striker))
	return caused


## The defender's strike-back choice dialog. With `counter_first` the prompt explains that Counter weapons
## strike BEFORE the charger (GF/AoF v3.5.1 p.13); one choice covers the whole melee (Counter phase now,
## remaining weapons in the normal slot).
func _solo_confirm_strike_back(defender: GameUnit, charger: GameUnit, counter_first: bool) -> bool:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Strike back?"
	if counter_first:
		dlg.dialog_text = "%s charges %s.\n%s has Counter — its Counter weapons strike FIRST.\nStrike back?" % [
			charger.get_name(), defender.get_name(), defender.get_name()]
	else:
		dlg.dialog_text = "%s is in melee with %s.\nStrike back?" % [defender.get_name(), charger.get_name()]
	dlg.ok_button_text = "Strike back"
	dlg.get_cancel_button().text = "Hold"
	add_child(dlg)
	dlg.popup_centered()
	var strike := false
	dlg.confirmed.connect(func() -> void: strike = true)
	await dlg.visibility_changed   # closes on either button
	dlg.queue_free()
	return strike


## Impact(X) auto-hits on a charge (GF/AoF v3.5.1 p.13: "Roll X dice when attacking after charging, unless
## fatigued. For each 2+ the target takes one hit."). Impact is a per-model rule, so `charger` rolls X per
## alive model, MINUS one roll per defender model with Counter (p.13 Counter); the hits carry no AP/Deadly
## (Impact is not a weapon) and save at the defender's (Shielded-adjusted) Defense. Wounds are APPLIED here
## (Regeneration-bucketed by the charger's Unstoppable) and RETURNED for the melee-winner tally. Skipped
## when the charger is fatigued or has no Impact. human_defends: the human rolls saves.
func _solo_charge_impact(charger: GameUnit, defender: GameUnit, human_defends: bool) -> int:
	if charger == null or defender == null:
		return 0
	var x: int = _solo_unit_rating(charger, "Impact")
	if x <= 0 or charger.is_fatigued:
		return 0
	var counter_models: int = _solo_counter_models(defender)
	var dice: int = AiCombatMath.impact_total_dice(x, charger.get_alive_count(), counter_models)
	if counter_models > 0 and battle_log != null and x * charger.get_alive_count() > 0:
		battle_log.log_event(BattleLog.Category.COMBAT, "Counter: %s loses %d Impact roll%s" % [
			charger.get_name(), counter_models, ("" if counter_models == 1 else "s")], true)
	if dice <= 0:
		return 0
	var faces: Array = await _solo_tray_roll(dice, AiCombatMath.IMPACT_HIT_TARGET, _solo_owner_label(charger))
	var hits: int = AiCombatMath.impact_hits(faces)
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT, "%s: Impact(%d) rolls %d di%s → %d hit%s" % [
			charger.get_name(), x, dice, ("e" if dice == 1 else "ce"), hits, ("" if hits == 1 else "s")], true)
	if hits <= 0 or _solo_combined_alive(defender) <= 0:
		return 0
	var profile: Dictionary = {"name": "Impact", "ap": 0, "deadly": 0, "rules": []}
	var w: int = await _solo_resolve_saves(charger, defender, "Impact", [], hits, _solo_shielded_defense(defender), profile, human_defends, true)
	if w > 0:
		if _solo_ignores_regen(charger, profile):
			await _solo_land_wounds(defender, 0, w)
		else:
			await _solo_land_wounds(defender, w, 0)
	return w


## Apply Deadly(X) to a raw unsaved-wound count (GF v3.5.1 p.13 + p.10 clarification: each wound ×X, capped
## at the target's Tough, assigned to one model). Logged so the multiplication is visible. Shared by every
## save batch.
func _solo_deadly_wounds(w: int, profile: Dictionary, target: GameUnit) -> int:
	var deadly: int = int(profile.get("deadly", 0))
	if w > 0 and deadly > 0:
		var mult: int = AiCombatMath.deadly_multiplier(deadly, _solo_unit_tough(target))
		if mult > 1 and battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "Deadly(%d): %d unsaved ×%d → %d wounds (Tough-capped)" % [
				deadly, w, mult, w * mult], true)
		w *= mult
	return w


## Roll the defender's saves for one weapon profile's `hits` and return the wounds caused, applying the two
## "unmodified 6" weapon rules that act on the SAVE step: Rending (GF/AoF v3.5.1 p.14 — the unmodified
## 6-to-hit among `to_hit_faces` save at AP(+4), resolved as a separate harder batch) and the striker's
## Bane (p.13 — the defender re-rolls unmodified Defense 6s once). `human_defends` picks the save UX: the
## human is prompted + rolls their own dice, else the AI auto-rolls in the tray. `melee` scopes the
## conditional Bane variants. Deadly multiplies per batch. Wounds are RETURNED, not applied — the caller
## buckets Regeneration-proof vs Regeneration-able. With no Rending/Bane this is one batch, identical to the
## previous single-save-roll behaviour.
func _solo_resolve_saves(striker: GameUnit, defender: GameUnit, weapon_name: String, to_hit_faces: Array,
		hits: int, base_defense: int, profile: Dictionary, human_defends: bool, melee: bool) -> int:
	if hits <= 0:
		return 0
	var ap: int = int(profile.get("ap", 0))
	# Rending (GF/AoF v3.5.1 p.14) AND the army-book Destructive (wave 4) BOTH upgrade the unmodified-6-to-
	# hit hits to AP(+4); they share AiCombatMath.rending_ap_hits (one math). The only difference is
	# downstream: Rending bypasses Regeneration (via _solo_ignores_regen), Destructive does not.
	var ap4_label := ""
	if bool(profile.get("rending", false)):
		ap4_label = "Rending"
	elif bool(profile.get("destructive", false)):
		ap4_label = "Destructive"
	var ap4_hits: int = AiCombatMath.rending_ap_hits(to_hit_faces, hits) if not ap4_label.is_empty() else 0
	var bane: bool = _solo_striker_has_bane(striker, profile, melee)
	var total := 0
	# AP(+4)-on-6 sub-volley first; a Blast-multiplied hit-count can only shrink the count via the cap.
	if ap4_hits > 0:
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "%s: %d hit%s on a 6 → AP(+%d)" % [
				ap4_label, ap4_hits, ("" if ap4_hits == 1 else "s"), AiCombatMath.RENDING_AP_BONUS], true)
		total += await _solo_save_batch(striker, defender, "%s (%s)" % [weapon_name, ap4_label], ap4_hits,
			base_defense, ap + AiCombatMath.RENDING_AP_BONUS, profile, human_defends, bane)
	var normal: int = hits - ap4_hits
	if normal > 0:
		total += await _solo_save_batch(striker, defender, weapon_name, normal, base_defense, ap, profile, human_defends, bane)
	return total


## One save batch: `count` saves at Defense `base_defense` worsened by `ap`, on the real tray, then Deadly.
## When the striker has Bane the defender re-rolls its unmodified Defense 6s (extra tray dice) before the
## blocks are counted (GF/AoF v3.5.1 p.13). Returns wounds (Deadly-multiplied). human_defends: prompt the
## human (their dice), else the AI auto-rolls its saves.
func _solo_save_batch(striker: GameUnit, defender: GameUnit, weapon_name: String, count: int,
		base_defense: int, ap: int, profile: Dictionary, human_defends: bool, bane: bool) -> int:
	if count <= 0:
		return 0
	var save_faces: Array
	if human_defends:
		save_faces = await _solo_prompt_saves(striker, defender, weapon_name, count, base_defense, ap)
	else:
		_solo_log_save_threshold(defender, base_defense, ap)
		save_faces = await _solo_tray_roll(count, base_defense + ap, "AI (%s)" % defender.get_name())
	var blocks: int
	var reroll: Array = []
	if bane:
		var sixes: int = AiCombatMath.bane_reroll_count(save_faces)
		if sixes > 0:
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "Bane: %s re-rolls %d unmodified Defense 6%s" % [
					defender.get_name(), sixes, ("" if sixes == 1 else "s")], true)
			reroll = await _solo_tray_roll(sixes, base_defense + ap, _solo_owner_label(defender))
		blocks = AiCombatMath.blocks_with_bane(save_faces, reroll, base_defense, ap)
	else:
		blocks = AiCombatMath.count_blocks(save_faces, base_defense, ap)
	# Shred (wave 5, army-book weapon rule): every unmodified Defense 1 deals +1 wound — counted on the
	# FINAL faces (after Bane's re-rolls), NOT Deadly-multiplied (save-step wounds, documented reading).
	var shred_extra := 0
	if bool(profile.get("shred", false)):
		shred_extra = AiCombatMath.shred_bonus_wounds(save_faces, reroll)
		if shred_extra > 0 and battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "Shred: %d Defense roll%s of 1 → +%d wound%s" % [
				shred_extra, ("" if shred_extra == 1 else "s"), shred_extra, ("" if shred_extra == 1 else "s")], true)
	return _solo_deadly_wounds(maxi(0, count - blocks), profile, defender) + shred_extra


## Whether the striker carries a Bane variant that applies now (GF/AoF v3.5.1 p.13: "the target must re-roll
## unmodified Defense results of 6"). Plain "Bane" always applies; "Bane in Melee" only in melee; "Bane when
## Shooting" only when shooting. Aura variants ("... Aura") grant Bane to OTHER units, so a striker's own
## aura rule never fires here. Reads the weapon's rules AND the striker unit's own special rules.
func _solo_striker_has_bane(striker: GameUnit, profile: Dictionary, melee: bool) -> bool:
	var sources: Array = (profile.get("rules", []) as Array).duplicate()
	if striker != null:
		sources.append_array(striker.get_special_rules())
	for r in sources:
		var s := str(r).strip_edges()
		if s.ends_with("Aura") or not s.begins_with("Bane"):
			continue
		if s.begins_with("Bane in Melee"):
			if melee:
				return true
		elif s.begins_with("Bane when Shooting"):
			if not melee:
				return true
		else:
			return true   # plain "Bane"
	return false


## The target's Regeneration / medic (GF Advanced Rules v3.5.1: "When a unit where all models have this
## rule takes wounds, roll one die for each. On a 5+ it is ignored."; the Battle Brothers "Medical
## Training" item grants Regeneration Aura): roll one REAL tray die per incoming wound, each 5+ ignores
## it. AP never affects this roll (AP only modifies Defense rolls). The battle log always states the
## outcome ("rolls N regeneration dice — M ignored"), so a 0-ignore roll is still visible. Returns the
## wounds that actually land; units without the rule take full wounds (no roll).
func _solo_apply_regeneration(target: GameUnit, wounds: int) -> int:
	var regen_target: int = _solo_regen_target(target)
	if wounds <= 0 or regen_target <= 0:
		return maxi(wounds, 0)
	var faces: Array = await _solo_tray_roll(wounds, regen_target, _solo_owner_label(target))
	var ignored := 0
	for f in faces:
		if int(f) >= regen_target:
			ignored += 1
	if battle_log != null:
		var rule_name: String = "regeneration" if regen_target == 5 else "self-repair"
		battle_log.log_event(BattleLog.Category.COMBAT, "%s rolls %d %s di%s (%d+) — %d wound%s ignored" % [
			target.get_name(), wounds, rule_name, ("e" if wounds == 1 else "ce"), regen_target, ignored, ("" if ignored == 1 else "s")], true)
	return maxi(wounds - ignored, 0)


## The wound-ignore ROLL TARGET for a unit's Regeneration-family rule, or 0 when it has none:
##   • Regeneration / Medical Training (Regeneration Aura) — ignore each wound on a 5+ (GF v3.5.1),
##     triggered by ANY bearing model (incl. a per-model medic item);
##   • Self-Repair (wave-4 army-book rule, Robot Legions — official Army Forge text: "When a unit where
##     all models have this rule takes wounds, roll one die for each. On a 6+ it is ignored.") — 6+, and
##     ALL models must carry it.
## Regeneration wins when both are present (the lower, more generous target). One truth with AiEv.ctx_for.
## Wave 5: the 5+/6+ targets are DATA (RulesRegistry ignore_target for the unit's system/faction; the
## constants remain the byte-identical fallback).
func _solo_regen_target(target: GameUnit) -> int:
	if _solo_has_regeneration(target):
		return int(RulesRegistry.unit_param(target, "Regeneration", "ignore_target", 5))
	if _solo_rule_on_all_models(target, "Self-Repair"):
		return int(RulesRegistry.unit_param(target, "Self-Repair", "ignore_target", 6))
	return 0


## Banner's morale-test bonus for a unit (wave 5): +1 when the unit or an attached hero carries Banner
## AND its book fields the rule for this system (RulesRegistry gate; the bonus value is data with the
## constant fallback). 0 otherwise.
func _solo_morale_bonus(unit: GameUnit) -> int:
	var members: Array = [unit]
	if unit != null and unit.has_method("get_attached_heroes"):
		members = members + unit.get_attached_heroes()
	for m in members:
		var member := m as GameUnit
		if member == null or member.get_alive_count() == 0:
			continue
		if RulesRegistry.unit_rule_active(member, "Banner"):
			return int(RulesRegistry.unit_param(member, "Banner", "morale_bonus", AiCombatMath.BANNER_MORALE_BONUS))
	return 0


## Apply a resolved wound pair to the defender: Regeneration rolls only against the regen-able bucket
## (Bane / Rending / Lacerate / Unstoppable wounds bypass it — GF Advanced Rules v3.5.1: those rules
## "ignore Regeneration"), then everything lands through the normal wound machinery. Returns landed wounds.
func _solo_land_wounds(target: GameUnit, regenable: int, regen_proof: int) -> int:
	var landed: int = maxi(regen_proof, 0) + await _solo_apply_regeneration(target, regenable)
	if landed > 0:
		_solo_apply_wounds(target, landed)
	return landed


## Whether wounds from this attacker+profile bypass the defender's Regeneration (GF Advanced Rules
## v3.5.1: Bane, Rending and Unstoppable "ignore Regeneration"; Lacerate is the AoF sibling).
func _solo_ignores_regen(attacker: GameUnit, profile: Dictionary) -> bool:
	for r in profile.get("rules", []):
		var s := str(r).strip_edges()
		if s.begins_with("Bane") or s.begins_with("Rending") or s.begins_with("Lacerate"):
			return true
	return attacker != null and attacker.has_special_rule("Unstoppable")


## The unit's per-model Tough value (majority) parsed from its special rules; 1 when it has no Tough.
func _solo_unit_tough(unit: GameUnit) -> int:
	for r in unit.get_special_rules():
		var s := str(r).strip_edges()
		if s.begins_with("Tough(") and s.ends_with(")"):
			return maxi(int(s.substr(6, s.length() - 7).replace("+", "")), 1)
	return 1


## Whether a unit (or an attached hero, or any of their MODELS via a per-model item — e.g. a medic's
## "Medical Training" pinned to one bearer) carries a Regeneration-class wound-ignore rule. The
## maintainer's field test hit the model-level gap: the rule lived on the bearer model's equipment,
## not in the unit's own special_rules, so the ignore roll was never offered.
func _solo_has_regeneration(unit: GameUnit) -> bool:
	var members: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		members = members + unit.get_attached_heroes()
	for m in members:
		var member := m as GameUnit
		if member == null:
			continue
		for r in member.get_special_rules():
			if _solo_is_regen_rule(str(r)):
				return true
		for model in member.get_alive_models():
			var mi := model as ModelInstance
			if mi != null and (mi.has_special_rule("Regeneration") or mi.has_special_rule("Medical Training")):
				return true
	return false


static func _solo_is_regen_rule(rule: String) -> bool:
	var s := rule.strip_edges()
	return s.begins_with("Regeneration") or s.begins_with("Medical Training")


## True when the majority of a unit's alive models sit in cover terrain (TerrainRules predicate on the real
## overlay data) — the OPR +1 Defense trigger.
func _solo_majority_in_cover(unit: GameUnit) -> bool:
	if terrain_overlay == null or not terrain_overlay.has_method("get_terrain_at_world_position"):
		return false
	var models: Array = unit.get_alive_models()
	if models.is_empty():
		return false
	var n := 0
	for m in models:
		var node: Node3D = (m as ModelInstance).node
		if node == null or not is_instance_valid(node):
			continue
		if TerrainRules.gives_cover(terrain_overlay.get_terrain_at_world_position(node.global_position)):
			n += 1
	return n * 2 > models.size()


## Battle-log / dice-owner label for a unit: "AI (name)" for an AI-controlled unit, else "You".
func _solo_owner_label(unit: GameUnit) -> String:
	return ("AI (%s)" % unit.get_name()) if _solo_is_ai_unit(unit) else "You"


## Dangerous terrain (GF Advanced Rules v3.5.1 p.12): each model that crossed a Dangerous cell rolls one REAL
## tray die; a 1 is a wound to the unit. A drop to half strength or less then tests morale (goal 003 P3).
func _run_ai_dangerous(unit: GameUnit, model_count: int) -> void:
	if unit == null or dice_roller_control == null or model_count <= 0:
		return
	var faces: Array = await _solo_tray_roll(model_count, 6, "AI (%s)" % unit.get_name())
	var wounds := 0
	for f in faces:
		if int(f) == 1:
			wounds += 1
	if wounds <= 0:
		return
	_solo_apply_wounds(unit, wounds)
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT, "%s takes %d wound%s from dangerous terrain" % [
			unit.get_name(), wounds, ("" if wounds == 1 else "s")], true)
	# NOTE (field-test finding 7): the morale test from these wounds is NOT rolled here — dangerous-terrain
	# damage neither consumes the activation nor prevents shooting (GF/AoF v3.5.1 p.12). Morale is tested at
	# the END of the activation (in _solo_activate_one_ai), after the unit has acted, so a surviving unit
	# still shoots this turn.


## Alive models of the unit INCLUDING its attached heroes (a unit is destroyed only when both are gone).
func _solo_combined_alive(unit: GameUnit) -> int:
	var n: int = unit.get_alive_count()
	if unit.has_method("get_attached_heroes"):
		for h in unit.get_attached_heroes():
			if h != null:
				n += h.get_alive_count()
	return n


## One attributed roll in the real dice tray: set count + success target, roll, await, read the faces,
## then restore the player's previous tray settings.
func _solo_tray_roll(count: int, success_target: int, owner: String) -> Array:
	var prev_count := _dice_count
	var prev_target := _success_target
	var prev_modifier := _success_modifier
	_dice_count = count
	_update_dice_set(count)
	_success_target = success_target
	_success_modifier = 0
	# Reflect the roll's REAL threshold in the tray UI (maintainer finding: the target buttons kept
	# highlighting the player's old manual pick while an AP-modified save rolled — reading as "AP ignored").
	_update_success_controls_display()
	_next_roll_owner = owner
	dice_roller_control.roll()
	# RESOLVE: roll_finnished only fires once every die has been physically calm for the tray's
	# SETTLE_HOLD (or the timeout snaps teeterers flat first) — then hold a readable beat on top so the
	# player sees the faces land before the flow moves on (goal 003 pacing).
	await dice_roller_control.roll_finnished
	await _solo_pace_hold(SoloController.Pace.RESOLVE)
	var faces: Array = _faces_in_order(dice_roller_control.per_dice_result())
	_dice_count = prev_count
	_update_dice_set(prev_count)
	_success_target = prev_target
	_success_modifier = prev_modifier
	_update_success_controls_display()
	return faces


## Save prompt (locked decision: prompt + auto-roll for speed): the human confirms and their save dice
## roll in the tray, attributed to "You". Returns the rolled faces.
func _solo_prompt_saves(attacker: GameUnit, target: GameUnit, weapon_name: String, hits: int, defense: int, ap: int) -> Array:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Incoming fire!"
	var ap_note: String = (" (AP %d → save on %d+)" % [ap, defense + ap]) if ap > 0 else " (save on %d+)" % defense
	dlg.dialog_text = "%s hits %s %d time%s with %s.\nRoll your defense saves%s." % [
		attacker.get_name(), target.get_name(), hits, ("" if hits == 1 else "s"), weapon_name, ap_note]
	dlg.ok_button_text = "Roll %d save%s" % [hits, ("" if hits == 1 else "s")]
	dlg.get_cancel_button().hide()   # saves are not optional — one clear action
	add_child(dlg)
	dlg.popup_centered()
	await dlg.confirmed
	dlg.queue_free()
	# The battle log states the MODIFIED threshold (GF v3.5.1 AP(X): "targets get -X to Defense rolls"),
	# so the AP arithmetic is auditable after the fact (maintainer field-test finding).
	_solo_log_save_threshold(target, defense, ap)
	return await _solo_tray_roll(hits, defense + ap, "You")


## Battle-log line stating a defender's MODIFIED save threshold (Def + AP) before the save dice roll —
## every save site (human prompt + both AI-save directions) calls this, per the maintainer's request
## that the modified threshold is always visible.
func _solo_log_save_threshold(defender: GameUnit, defense: int, ap: int) -> void:
	if battle_log == null:
		return
	var threshold: String = ("%d+ (Def %d+, AP %d)" % [defense + ap, defense, ap]) if ap > 0 else "%d+" % defense
	battle_log.log_event(BattleLog.Category.COMBAT, "%s saves on %s" % [defender.get_name(), threshold], true)


# === AI-action presentation layer (goal 003 game-feel: announce → execute → resolve → outcome) ===

## Hold for a pacing phase (SoloController.Pace); fast-forward shrinks every fixed hold.
func _solo_pace_hold(phase: int) -> void:
	var secs: float = SoloController.pace_seconds(phase, _solo_fast)
	if secs > 0.0:
		await get_tree().create_timer(secs).timeout


## The activation-choreography attention beat (SoloController.PACE_ATTENTION_S, Fast-AI-compressed) — the
## named ~2s pause the maintainer asked for between focus → corridors → glide → attacks (finding 7). A
## zero (never, at these constants) simply doesn't await, keeping the auto-tail responsive.
func _solo_pace_attention() -> void:
	var secs: float = SoloController.pace_attention_seconds(_solo_fast)
	if secs > 0.0:
		await get_tree().create_timer(secs).timeout


## Point the camera at a unit's live model centroid (shared by every AI activation + the ambush arrivals,
## so each is watchable). No-op when there is no focusable camera or the unit has no live models.
func _solo_focus_on_unit(unit: GameUnit) -> void:
	if camera_pivot == null or not camera_pivot.has_method("focus_on") or unit == null:
		return
	var positions: Array = []
	for m in unit.models:
		if m.is_alive and m.node != null and is_instance_valid(m.node):
			positions.append((m.node as Node3D).global_position)
	if not positions.is_empty():
		camera_pivot.focus_on(MoveIntent.anchor_of(positions))


## Attack attribution: pulse rings under the shooter (amber) and the target (red), an attack line
## between them, and a toast naming both. Returns the created nodes; free via _solo_clear_announce.
func _solo_show_attack_announce(shooter: GameUnit, target: GameUnit, verb: String) -> Array:
	var nodes: Array = []
	if solo_controller == null:
		return nodes
	var from := solo_controller.unit_centre(shooter)
	var to := solo_controller.unit_centre(target)
	nodes.append(_solo_spawn_pulse_ring(from, Color(1.0, 0.75, 0.2)))
	nodes.append(_solo_spawn_pulse_ring(to, Color(0.95, 0.25, 0.2)))
	var line := MeshInstance3D.new()
	line.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	line.material_override = mat
	var im := line.mesh as ImmediateMesh
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(Color(1.0, 0.75, 0.2))
	im.surface_add_vertex(from + Vector3(0, 0.05, 0))
	im.surface_set_color(Color(0.95, 0.25, 0.2))
	im.surface_add_vertex(to + Vector3(0, 0.05, 0))
	im.surface_end()
	add_child(line)
	nodes.append(line)
	_solo_show_toast("%s %s %s" % [shooter.get_name(), verb, target.get_name()])
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT, "%s %s %s" % [shooter.get_name(), verb, target.get_name()], true)
	return nodes


## A flat unshaded ring that pulses (scale + alpha) until freed — the attention marker under a unit.
func _solo_spawn_pulse_ring(at: Vector3, color: Color) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.05
	torus.outer_radius = 0.06
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	ring.material_override = mat
	add_child(ring)
	ring.global_position = at + Vector3(0, 0.01, 0)
	var tw := ring.create_tween().set_loops()
	tw.tween_property(ring, "scale", Vector3(1.25, 1.0, 1.25), 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(ring, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_SINE)
	return ring


func _solo_clear_announce(nodes: Array) -> void:
	for n in nodes:
		if n is Node and is_instance_valid(n):
			(n as Node).queue_free()


## Transient top-centre toast for AI-action attribution/outcomes (below the AI-turn banner).
func _solo_show_toast(text: String) -> void:
	if not is_instance_valid(_solo_toast):
		_solo_toast = Label.new()
		_solo_toast.name = "SoloActionToast"
		_solo_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_solo_toast.add_theme_font_size_override("font_size", 16)
		_solo_toast.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
		_solo_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_solo_toast.add_theme_constant_override("outline_size", 4)
		_solo_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 40)
		$UI.add_child(_solo_toast)
	_solo_toast.text = text
	_solo_toast.visible = true


## OUTCOME phase: show the result summary as a toast + hold it readable, then hide.
func _solo_show_outcome(text: String) -> void:
	_solo_show_toast(text)
	await _solo_pace_hold(SoloController.Pace.OUTCOME)
	if is_instance_valid(_solo_toast):
		_solo_toast.visible = false


## EXECUTE phase for movement: the models GLIDE along their REAL planner routes (never teleport — the
## maintainer's followability guarantee; fast-forward accelerates the glide by 1/PACE_FAST_SCALE instead
## of skipping it). State was already applied + broadcast — this is a local visual replay. Each model
## drags a base-width swept CORRIDOR (its outer base edges along the path), and one label states the
## longest actual path length against the granted budget ("9.4\" / 12\"") — the distance truth made
## visible (GF v3.5.1 p.7).
## Return each moving model's NODE to its route START (path[0]) BEFORE the announce beat (field-test
## finding 2: the end state must not leak first). The logical + broadcast state is already final; this is a
## purely local visual reset that _solo_animate_move then draws the corridors from and glides back to the
## final. No-op for a HOLD / idle (no paths) and for any model whose node is gone. Uses the pure
## SoloController.presentation_start_positions truth so the start each model is shown at is unit-tested.
func _solo_present_move_start(move_paths: Array) -> void:
	if move_paths.is_empty():
		return
	var starts: Array = SoloController.presentation_start_positions(move_paths)
	var si := 0
	for entry in move_paths:
		var model := (entry as Dictionary).get("model") as ModelInstance
		var path: Array = (entry as Dictionary).get("path", [])
		if path.size() < 2:
			continue
		var start: Vector3 = starts[si]
		si += 1
		if model == null or model.node == null or not is_instance_valid(model.node):
			continue
		model.node.global_position = Vector3(start.x, model.node.global_position.y, start.z)


func _solo_animate_move(move_paths: Array) -> void:
	if move_paths.is_empty():
		return
	var speed: float = SoloController.PACE_MOVE_SPEED_M_S / (SoloController.PACE_FAST_SCALE if _solo_fast else 1.0)
	# (c) Draw every model's corridor (persistent — they stay lit through the beat + the glide) and snap
	# each model back to its route START, so the attention beat shows the plotted paths with the models
	# still at their staging positions before they move.
	var corridors: Array = []
	var longest_path: Array = []
	var longest_len := 0.0
	for entry in move_paths:
		var model := (entry as Dictionary).get("model") as ModelInstance
		var path: Array = (entry as Dictionary).get("path", [])
		if model == null or model.node == null or not is_instance_valid(model.node) or path.size() < 2:
			continue
		var node := model.node
		var y := node.global_position.y
		var body := _solo_spawn_move_corridor(path, y, float((entry as Dictionary).get("radius_m", 0.0125)), true)
		if body != null:
			corridors.append(body)
		var arc: float = MovementPlanner.polyline_length(path)
		if arc > longest_len:
			longest_len = arc
			longest_path = path
		node.global_position = Vector3((path[0] as Vector3).x, y, (path[0] as Vector3).z)
	# Distance-truth label: longest actual arc vs the granted budget, at that corridor's midpoint.
	if not longest_path.is_empty() and solo_controller != null:
		_solo_spawn_move_label(longest_path, longest_len, solo_controller.last_move_budget_in)
	# (d) Attention beat: corridors drawn, models poised at the start.
	await _solo_pace_attention()
	# (e) Glide the models ONE AT A TIME in the SEQUENTIAL FLOW ORDER (field-test round 6, finding 7):
	# move_paths is already ordered nearest-to-destination first, so the lead models visibly vacate the choke
	# and the rest FLOW after them (the maintainer's explicit staging). Each model's glide completes before the
	# next begins; not-yet-moved models wait at their route start (snapped above). Fast-AI compresses `speed`.
	for entry in move_paths:
		var model := (entry as Dictionary).get("model") as ModelInstance
		var path: Array = (entry as Dictionary).get("path", [])
		if model == null or model.node == null or not is_instance_valid(model.node) or path.size() < 2:
			continue
		var node := model.node
		var y := node.global_position.y
		var tw := node.create_tween()
		var total := 0.0
		for i in range(1, path.size()):
			var a := path[i - 1] as Vector3
			var b := path[i] as Vector3
			var leg := Vector2(b.x - a.x, b.z - a.z).length()
			if leg <= 0.0001:
				continue
			var dur := leg / speed
			tw.tween_property(node, "global_position", Vector3(b.x, y, b.z), dur)
			total += dur
		if total > 0.0:
			await get_tree().create_timer(total).timeout
		if tw.is_valid():
			tw.kill()
		# Snap onto the exact final (the tween end) so state and visuals agree to the millimetre.
		var fin := path.back() as Vector3
		node.global_position = Vector3(fin.x, node.global_position.y, fin.z)
	# The corridors fade now that the whole unit has flowed through (persisted corridors faded here, not on spawn).
	for body in corridors:
		_solo_fade_corridor(body as MeshInstance3D)


## Height offsets keeping the corridor visuals just above the table without z-fighting (metres).
const SOLO_CORRIDOR_Y_M := 0.012
const SOLO_CORRIDOR_EDGE_Y_M := 0.015
## Semicircle end-cap resolution (segments per 180°).
const SOLO_CORRIDOR_CAP_SEGS := 8
## Corner-miter width clamp — bounds the spike a hairpin corner can produce (floor of the 1/dot widen).
const SOLO_CORRIDOR_MITER_MIN := 0.35


## The base-width swept corridor for one model's route (the maintainer's guarantee: the base's OUTER
## EDGES dragged along the path — where the corridor is, the base physically travelled). One mesh, five
## surfaces: a translucent stadium fill (band + two semicircle end caps) and two brighter edge lines at
## ±radius. Fades out over PACE_TRAIL_FADE_S, then frees itself.
## `persist`: when true the corridor is NOT auto-faded — the choreography (finding 7) draws corridors,
## holds the attention beat, glides the models, THEN fades them via _solo_fade_corridor. Returns the mesh
## (null if degenerate) so the caller can fade it on its own schedule.
func _solo_spawn_move_corridor(path: Array, y: float, radius_m: float, persist: bool = false) -> MeshInstance3D:
	# Deduplicate near-identical waypoints (zero legs break the perpendicular math).
	var pts: Array = []
	for wp in path:
		var v := Vector2((wp as Vector3).x, (wp as Vector3).z)
		if pts.is_empty() or (pts.back() as Vector2).distance_to(v) > 0.0008:
			pts.append(v)
	if pts.size() < 2 or radius_m <= 0.0:
		return null
	# Per-waypoint mitred left/right offsets: the averaged perpendicular of adjacent legs, widened by
	# 1/dot (clamped) so the corridor keeps its base width through corners.
	var lefts: Array = []
	var rights: Array = []
	for i in range(pts.size()):
		var dir_in: Vector2 = ((pts[i] as Vector2) - (pts[i - 1] as Vector2)).normalized() if i > 0 else Vector2.ZERO
		var dir_out: Vector2 = ((pts[i + 1] as Vector2) - (pts[i] as Vector2)).normalized() if i < pts.size() - 1 else Vector2.ZERO
		var blend := dir_in + dir_out
		var dir := blend.normalized() if blend.length() > 0.0001 else (dir_in if dir_in != Vector2.ZERO else dir_out)
		var perp := Vector2(-dir.y, dir.x)
		var seg_dir := dir_out if dir_out != Vector2.ZERO else dir_in
		var seg_perp := Vector2(-seg_dir.y, seg_dir.x)
		var widen: float = 1.0 / maxf(SOLO_CORRIDOR_MITER_MIN, absf(perp.dot(seg_perp)))
		lefts.append((pts[i] as Vector2) + perp * radius_m * widen)
		rights.append((pts[i] as Vector2) - perp * radius_m * widen)
	var body := MeshInstance3D.new()
	body.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)   # tweened to 0 alpha — multiplies the vertex colours
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	body.material_override = mat
	var im := body.mesh as ImmediateMesh
	var fill := Color(1.0, 0.85, 0.4, 0.22)
	var edge := Color(1.0, 0.85, 0.4, 0.85)
	# Surface 1: the translucent band between the base edges.
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(pts.size()):
		im.surface_set_color(fill)
		im.surface_add_vertex(Vector3((lefts[i] as Vector2).x, y + SOLO_CORRIDOR_Y_M, (lefts[i] as Vector2).y))
		im.surface_set_color(fill)
		im.surface_add_vertex(Vector3((rights[i] as Vector2).x, y + SOLO_CORRIDOR_Y_M, (rights[i] as Vector2).y))
	im.surface_end()
	# Surfaces 2+3: semicircle end caps — the stadium shape of a base swept along the path.
	_solo_corridor_cap(im, pts[0], ((pts[1] as Vector2) - (pts[0] as Vector2)).normalized() * -1.0, radius_m, y, fill)
	_solo_corridor_cap(im, pts.back(), ((pts.back() as Vector2) - (pts[pts.size() - 2] as Vector2)).normalized(), radius_m, y, fill)
	# Surfaces 4+5: the two OUTER BASE-EDGE lines — the drawn path the maintainer asked for.
	for side in [lefts, rights]:
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for v in side:
			im.surface_set_color(edge)
			im.surface_add_vertex(Vector3((v as Vector2).x, y + SOLO_CORRIDOR_EDGE_Y_M, (v as Vector2).y))
		im.surface_end()
	add_child(body)
	if not persist:
		_solo_fade_corridor(body)
	return body


## Fade a persisted corridor out over PACE_TRAIL_FADE_S, then free it — called after the models finish
## gliding along it (the choreography keeps the corridor visible through the glide, then dissolves it).
func _solo_fade_corridor(body: MeshInstance3D) -> void:
	if not is_instance_valid(body):
		return
	var mat := body.material_override as StandardMaterial3D
	if mat == null:
		body.queue_free()
		return
	var tw := body.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, SoloController.PACE_TRAIL_FADE_S)
	tw.tween_callback(body.queue_free)


## One semicircular corridor end cap: a triangle fan around `centre`, opening in `dir` (the outward
## direction at that end of the path), sweeping half a turn from +perp to −perp.
func _solo_corridor_cap(im: ImmediateMesh, centre_v: Variant, dir: Vector2, radius_m: float, y: float, fill: Color) -> void:
	var centre := centre_v as Vector2
	if dir.length() < 0.0001:
		return
	var start := Vector2(-dir.y, dir.x)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in range(SOLO_CORRIDOR_CAP_SEGS):
		var a0 := float(s) * PI / float(SOLO_CORRIDOR_CAP_SEGS)
		var a1 := float(s + 1) * PI / float(SOLO_CORRIDOR_CAP_SEGS)
		var p0 := centre + start.rotated(-a0) * radius_m
		var p1 := centre + start.rotated(-a1) * radius_m
		im.surface_set_color(fill)
		im.surface_add_vertex(Vector3(centre.x, y + SOLO_CORRIDOR_Y_M, centre.y))
		im.surface_set_color(fill)
		im.surface_add_vertex(Vector3(p0.x, y + SOLO_CORRIDOR_Y_M, p0.y))
		im.surface_set_color(fill)
		im.surface_add_vertex(Vector3(p1.x, y + SOLO_CORRIDOR_Y_M, p1.y))
	im.surface_end()


## The corridor's distance-truth label ("9.4\" / 12\"") at the longest path's midpoint: the actual arc
## length moved vs the granted budget (band, difficult-capped) — GF v3.5.1 p.7 made visible. Fades with
## the corridor.
func _solo_spawn_move_label(path: Array, arc_m: float, budget_in: float) -> void:
	if path.size() < 2:
		return
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.0004
	label.outline_size = 8
	label.text = "%.1f\" / %.0f\"" % [arc_m / SoloController.INCHES_TO_METERS, budget_in]
	label.modulate = Color(1.0, 0.9, 0.5)
	add_child(label)
	var mid := path[path.size() >> 1] as Vector3
	label.global_position = Vector3(mid.x, mid.y + 0.06, mid.z)
	var tw := label.create_tween()
	tw.tween_property(label, "modulate:a", 0.0, SoloController.PACE_TRAIL_FADE_S)
	tw.tween_callback(label.queue_free)


## Once-per-session battle-log note for every combat-relevant special rule the solo automation does NOT
## model — the sim's unknown-rule visibility, surfaced in-game so gaps are apparent, not silent.
## WAVE 5: this constant is now the FALLBACK — at runtime the modeled set is DERIVED per game system
## from the committed mechanics maps (RulesRegistry.modeled_tokens / _solo_modeled_rules_for), so a rule
## only counts as modeled where its system's books actually field a mapped primitive. The list below is
## used when the maps are absent (tests/dev trees without assets).
const SOLO_MODELED_RULES: Array = ["AP", "Tough", "Deadly", "Takedown", "Relentless", "Blast", "Reliable",
	"Regeneration", "Medical Training", "Bane", "Rending", "Lacerate", "Unstoppable", "Hero", "Fast", "Slow",
	"Ambush", "Scout", "Strider", "Flying", "Fatigue",
	# Wave-2 combat special rules (GF/AoF Advanced Rules v3.5.1): "Fear" prefix-covers both Fearless (morale
	# re-roll) and Fear(X) (melee-winner bonus).
	"Surge", "Furious", "Impact", "Thrust", "Fearless", "Fear",
	# Wave-3: target-side modifiers (Stealth / Evasive / Shielded / Artillery), Counter (strike-first +
	# Impact reduction + activation order) and the Hold-only rules (Immobile / Artillery).
	"Stealth", "Evasive", "Shielded", "Counter", "Artillery", "Immobile",
	# Wave-4 army-book rules (official Army Forge text; the three 0.3.9 field books — Robot Legions,
	# Battle Brothers, Mummified Undead): Destructive (weapon: unmodified-6→AP(+4), no regen bypass),
	# Self-Repair (6+ wound-ignore, all models), Battleborn (round-start Shaken recovery on 4+),
	# Unpredictable Fighter (melee: 1-3 AP(+1) / 4-6 +1 to hit), Royal Legion (+4" shooting range + 2"
	# Charge via the move bands). See docs/SOLO_AI_RULES_COVERAGE.md for the per-army coverage table.
	"Destructive", "Self-Repair", "Battleborn", "Unpredictable Fighter", "Royal Legion",
	# Wave-5 top-breadth primitives (registry-derived params): Shred (save 1s → +1 wound), Indirect
	# (moved -1 / no-LOS targeting / cover-ignore / hold overlay), Banner (+1 morale), Musician (+1"
	# move), Sergeant (bearer's 6s → +1 hit), Limited (once per game), Armor(X) (counts as Defense X+).
	"Shred", "Indirect", "Banner", "Musician", "Sergeant", "Limited", "Armor"]

## The SOLO_MODELED_RULES subset that ALSO steers the AI's behaviour choices (not only the dice math):
## targeting overlays (AP/Deadly/Takedown — Solo v3.5.0 p.2), Hold overlays (Relentless/Artillery/
## Immobile), activation order (Counter), movement (Fast/Slow bands, Strider/Flying terrain, Ambush/
## Scout deployment) and every EV input of the tie-break metric (AiEv). Drives the inventory's
## "decision-aware" marker — a classification aid, not a second rule list. Like SOLO_MODELED_RULES,
## wave 5 derives the live set from the mechanics maps; this is the fallback.
const SOLO_DECISION_RULES: Array = ["AP", "Deadly", "Takedown", "Relentless", "Artillery", "Immobile",
	"Counter", "Fast", "Slow", "Strider", "Flying", "Ambush", "Scout", "Tough", "Blast", "Reliable",
	"Rending", "Bane", "Stealth", "Evasive", "Shielded", "Fear", "Furious", "Impact", "Thrust", "Hero",
	# Wave-4: Destructive/Self-Repair shape the EV, Royal Legion the shoot decision + move bands.
	"Destructive", "Self-Repair", "Royal Legion",
	# Wave-5: all seven steer decisions — Indirect (hold overlay + LOS-free targeting), Musician (move
	# bands), Banner (charge-risk EV), Sergeant/Shred/Armor (EV inputs), Limited (profile availability).
	"Shred", "Indirect", "Banner", "Musician", "Sergeant", "Limited", "Armor"]


## The modeled-rule tokens for a unit's game system — mechanics-map-derived (wave 5), constant fallback.
func _solo_modeled_rules_for(unit: GameUnit) -> Array:
	return RulesRegistry.modeled_tokens(RulesRegistry.system_of_unit(unit), SOLO_MODELED_RULES)


## The decision-relevant tokens for a unit's game system — mechanics-map-derived, constant fallback.
func _solo_decision_rules_for(unit: GameUnit) -> Array:
	return RulesRegistry.decision_tokens(RulesRegistry.system_of_unit(unit), SOLO_DECISION_RULES)


## Battle-log the AI's rule inventory at army handoff (the maintainer's no-blackbox mandate): every
## special rule the designated army carries, classified RESOLVED (mechanically implemented — derived
## from SOLO_MODELED_RULES), marked "decision-aware" when it also steers choices, or UN-AUTOMATED
## (which additionally keeps flowing through the once-per-session manual-note mechanism).
func _solo_log_rule_inventory(player_id: int) -> void:
	if battle_log == null or opr_army_manager == null:
		return
	var names: Array = []
	var first_unit: GameUnit = null
	for u in opr_army_manager.get_game_units_for_player(player_id):
		var gu := u as GameUnit
		if gu == null:
			continue
		if first_unit == null:
			first_unit = gu
		names.append_array(gu.get_special_rules())
		for w in _solo_all_weapons(gu):
			if w is Object and (w as Object).get("special_rules") != null:
				names.append_array((w as Object).special_rules)
	# Wave 5: the modeled/decision sets are DERIVED from the army's game system's mechanics map (one
	# army = one system, so the first unit carries it); the constants remain the no-map fallback.
	var inv := SoloController.classify_rule_inventory(names,
		_solo_modeled_rules_for(first_unit), _solo_decision_rules_for(first_unit))
	battle_log.log_event(BattleLog.Category.GENERAL, "AI rule inventory (P%d): %s | decision-aware: %s | NOT automated (apply manually): %s" % [
		player_id, _solo_inventory_list(inv["resolved"]), _solo_inventory_list(inv["decision"]),
		_solo_inventory_list(inv["unknown"])], true)


## "AP x23, Tough x4, …" — one inventory class as a compact, alphabetical count list ("none" when empty).
static func _solo_inventory_list(counts: Dictionary) -> String:
	if counts.is_empty():
		return "none"
	var keys := counts.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s x%d" % [str(k), int(counts[k])])
	return ", ".join(parts)


## Drain the AI's structured decision records; render them into the battle log only while the dev
## toggle is on (off = the records are discarded unformatted — zero string cost).
func _solo_flush_dev() -> void:
	if solo_controller == null:
		return
	var records: Array = solo_controller.drain_decisions()
	if not _solo_dev or battle_log == null:
		return
	for rec in records:
		battle_log.log_event(BattleLog.Category.GENERAL, SoloController.render_decision(rec as Dictionary))


func _solo_log_unmodeled_rules(unit: GameUnit) -> void:
	if unit == null or battle_log == null:
		return
	var rules: Array = unit.get_special_rules().duplicate()
	for w in _solo_all_weapons(unit):
		if w is Object and (w as Object).get("special_rules") != null:
			rules.append_array((w as Object).special_rules)
	var modeled_tokens: Array = _solo_modeled_rules_for(unit)   # system-scoped (wave 5), const fallback
	for r in rules:
		var rule_name := str(r).strip_edges().get_slice("(", 0)
		if rule_name.is_empty() or _solo_unmodeled_logged.has(rule_name):
			continue
		var modeled := false
		for known in modeled_tokens:
			if rule_name.begins_with(str(known)):
				modeled = true
				break
		_solo_unmodeled_logged[rule_name] = true
		if not modeled:
			battle_log.log_event(BattleLog.Category.GENERAL, "Note: \"%s\" is not automated in solo — apply it manually" % rule_name, true)


## Resolve a landed AI charge (goal 001 P4): the human defender's Counter weapons strike FIRST (one
## strike-back choice covers the whole melee), then Impact (Counter-reduced), then the AI's strikes
## (fatigued units hit only on 6s; the human saves per profile), then the human's remaining strike-back;
## both sides that struck become Fatigued (OPR: first melee each round); the Fear-adjusted loser tests
## morale (fail → Shaken; at/below half → Routs).
func _run_ai_melee(report: Dictionary) -> void:
	var unit: GameUnit = report.get("unit")
	var target: GameUnit = report.get("target")
	if unit == null or target == null or dice_roller_control == null:
		return
	# The charge must actually reach combat, measured base-to-base (field-test finding 5): the planner ends
	# the charge at/near base contact, so the gap between the nearest models — not the unit centres — is the
	# true reach test. Within MELEE_ENGAGE_IN it snaps to clean contact; beyond it the charge falls short.
	var gap_in: float = solo_controller.nearest_melee_gap_in(unit, target)
	if gap_in > MELEE_ENGAGE_IN:
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "%s's charge falls short (%.1f\")" % [unit.get_name(), gap_in], true)
		return
	var snapped_ai: float = solo_controller.snap_charge(unit, target)
	if snapped_ai > 0.05 and battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT,
			"%s charges into base contact (+%.1f\") — GF/AoF v3.5.1 p.8" % [unit.get_name(), snapped_ai], true)
	var ai_caused := 0
	var human_caused := 0
	var target_models_before: int = _solo_combined_alive(target)
	# ANNOUNCE: who charges whom — highlights + line + toast, held before the first strike.
	var announce := _solo_show_attack_announce(unit, target, "charges")
	await _solo_pace_hold(SoloController.Pace.ANNOUNCE)
	# — Counter (GF/AoF v3.5.1 p.13: "Strikes first with this weapon when charged"): the human defender's
	#   Counter weapons resolve BEFORE the charger's attacks (incl. Impact — Counter's Impact reduction
	#   presumes the counter-attack precedes it; the PDF pins no finer order). One strike-back choice
	#   covers the whole melee: Counter weapons now, remaining weapons in the normal slot, or neither. —
	# Native both-AI (AI ARENA): when the DEFENDER is AI, it ALWAYS strikes back (Solo & Co-Op v3.5.0 p.57:
	# "the AI always strikes back") and auto-rolls its saves — no human ConfirmationDialog. The human defender
	# still gets the one strike-back choice. `_defender_is_ai` drives both the strike-back and every save UX.
	var defender_is_ai: bool = _solo_is_ai_unit(target)
	var strike_back := -1   # -1 = not yet asked, 0 = declined, 1 = strikes
	var counter_first: bool = _solo_has_counter(target)
	if counter_first and _solo_combined_alive(target) > 0:
		strike_back = 1 if defender_is_ai or await _solo_confirm_strike_back(target, unit, true) else 0
		if strike_back == 1:
			human_caused += await _solo_melee_strike_phase(target, unit, false, SoloStrike.COUNTER_ONLY)
	# — Impact(X) auto-hits fire BEFORE the normal strikes (GF/AoF v3.5.1 p.13; reduced by Counter models);
	#   applied + tallied inside. The charger may already be wiped by Counter — nothing left to roll then.
	#   human_defends is derived (false when the AI defends → saves auto-roll on the tray). —
	if _solo_combined_alive(unit) > 0:
		ai_caused += await _solo_charge_impact(unit, target, not defender_is_ai)
	# — AI strikes (unit + attached heroes; only models within 2" strike; Deadly multiplies wounds). The AI
	#   is the charger here, so Furious/Thrust charge bonuses apply (charging = true) —
	if _solo_combined_alive(unit) > 0:
		ai_caused += await _solo_melee_strike_phase(unit, target, true, SoloStrike.ALL)
		_solo_set_fatigued(unit)
	_solo_clear_announce(announce)
	# — Strike back (the human's choice; OPR lets the defender strike back — unit + attached heroes). With
	#   Counter the choice was already made; only the NON-Counter weapons remain for this slot. —
	if _solo_combined_alive(target) > 0 and _solo_combined_alive(unit) > 0:
		if strike_back == -1:
			strike_back = 1 if defender_is_ai or await _solo_confirm_strike_back(target, unit, false) else 0
		if strike_back == 1:
			human_caused += await _solo_melee_strike_phase(target, unit, false,
				SoloStrike.NON_COUNTER if counter_first else SoloStrike.ALL)
	if strike_back == 1:
		_solo_set_fatigued(target)
	# — Morale: the side that CAUSED more wounds wins; the loser tests (tie = nobody). Fear(X) (GF/AoF
	#   v3.5.1 p.13) counts as +X dealt wounds for THIS comparison only (never changes wounds applied) —
	var ai_score: int = AiCombatMath.fear_adjusted_wounds(ai_caused, _solo_unit_rating(unit, "Fear"))
	var human_score: int = AiCombatMath.fear_adjusted_wounds(human_caused, _solo_unit_rating(target, "Fear"))
	if ai_score > human_score and _solo_combined_alive(target) > 0:
		await _solo_morale_test(target, _solo_owner_label(target))   # "You" for a human defender, "AI (…)" in both-AI
	elif human_score > ai_score and _solo_combined_alive(unit) > 0:
		await _solo_morale_test(unit, _solo_owner_label(unit))
	# — Consolidation (GF v3.5.1 p.9, after morale): neither destroyed → the CHARGER (the AI here) moves
	#   back 1" to clear the separation — visibly, via the corridor + glide replay. —
	await _solo_separate_after_melee(unit, target)
	# OUTCOME: one readable melee summary (toast + hold).
	await _solo_show_outcome("Melee: %s deals %d — takes %d back — %s loses %d model%s" % [
		unit.get_name(), ai_caused, human_caused, target.get_name(),
		target_models_before - _solo_combined_alive(target),
		("" if target_models_before - _solo_combined_alive(target) == 1 else "s")])


## Post-melee separation (GF Advanced Rules v3.5.1 p.9 "Consolidation Moves": "If neither of the units
## was destroyed, then the charging unit must move back by 1” (if possible), to keep the separation
## between units clear"). The AI charger backs off through the normal planned-move seam (state applied +
## broadcast; the corridor + glide replay make it visible); Dangerous crossings on the back-step still
## test (p.12). No-op when either side was destroyed (the "may move up to 3”" winner consolidation is a
## MAY and is not automated — flagged in docs/SOLO_AI_RULES_COVERAGE.md).
func _solo_separate_after_melee(charger: GameUnit, defender: GameUnit) -> void:
	if solo_controller == null or _solo_combined_alive(charger) <= 0 or _solo_combined_alive(defender) <= 0:
		return
	var dang: int = solo_controller.separate_from_melee(charger, solo_controller.unit_centre(defender))
	solo_controller.record_decision({"kind": "separate", "unit": charger.get_name(),
		"rule": "GF v3.5.1 p.9 consolidation: the charger moves back 1\" when neither unit was destroyed",
		"candidates": [], "chosen": "", "why": "mandatory separation", "data": {"back_in": 1.0}})
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT, "%s moves back 1\" (consolidation — GF v3.5.1 p.9)" % charger.get_name(), true)
	await _solo_animate_move(solo_controller.last_move_paths)
	if dang > 0:
		await _run_ai_dangerous(charger, dang)
	_solo_flush_dev()


## One OPR morale test with a real tray die: >= Quality passes; fail → Shaken, at/below half → Routs
## (the unit is destroyed through the existing kill flows).
## OPR rule gap (goal 003 P1): a unit that takes CASUALTIES FROM SHOOTING and is now at half strength or
## less must test morale — this trigger was missing entirely (morale only ran after melee). Compares the
## unit's own alive count before vs after the volley; `owner` attributes the tray roll (the AI rolls for
## its own units, "You" for the human's). No-op if the unit was wiped or took no casualties.
func _solo_shooting_morale(unit: GameUnit, alive_before: int, owner: String) -> void:
	if unit == null:
		return
	if AiCombatMath.should_test_shooting_morale(alive_before, unit.get_alive_count(), unit.models.size()):
		await _solo_morale_test(unit, owner)


func _solo_morale_test(unit: GameUnit, owner: String) -> void:
	var below_half := AiCombatMath.at_or_below_half(unit.get_alive_count(), unit.models.size())
	var result: int
	if unit.is_shaken:
		# A unit that is ALREADY Shaken auto-fails any further morale test (GF/AoF v3.5.1 p.10: "Shaken
		# units … always fail morale tests") — no Quality roll. At half or less this Routs it; otherwise it
		# stays Shaken (field-test finding 8: a Shaken unit was rolling — and could pass — a repeat test).
		result = AiCombatMath.morale_result_shaken(below_half)
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT,
				"%s is already Shaken — automatically fails morale (GF/AoF v3.5.1 p.10)" % unit.get_name(), true)
	else:
		# Banner (wave 5, system-scoped params via RulesRegistry: +1 to morale test rolls; the GFF/AoFS
		# picked-units variant still covers the bearer's own unit) lowers the roll target, clamped to
		# [2,6] (a natural 1 always fails). Without Banner this is the plain Quality target.
		var morale_bonus: int = _solo_morale_bonus(unit)
		var test_target: int = AiCombatMath.morale_target(unit.get_quality(), morale_bonus)
		if morale_bonus > 0 and battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "Banner: %s gets +%d to morale test rolls (passes on %d+)" % [
				unit.get_name(), morale_bonus, test_target], true)
		var faces: Array = await _solo_tray_roll(1, test_target, owner)
		if faces.is_empty():
			return
		result = AiCombatMath.morale_result(int(faces[0]), test_target, below_half)
	# Fearless (GF/AoF Advanced Rules v3.5.1 p.13): a unit where all models have this rule re-rolls a FAILED
	# morale test once; on a 4+ it counts as passed instead. Rolled visibly on the real tray. The 4+ is
	# DATA where the mechanics map carries it (RulesRegistry; constant fallback — byte-identical seam).
	if result != AiCombatMath.Morale.PASSED and unit.has_special_rule("Fearless"):
		var recover_target: int = int(RulesRegistry.unit_param(unit, "Fearless", "recover_target", AiCombatMath.FEARLESS_RECOVER_TARGET))
		var reroll: Array = await _solo_tray_roll(1, recover_target, owner)
		if not reroll.is_empty() and DiceRules.is_success(int(reroll[0]), recover_target, 0):
			result = AiCombatMath.Morale.PASSED
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s is Fearless — re-roll (4+) passes morale" % unit.get_name(), true)
		elif battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "%s is Fearless — re-roll fails" % unit.get_name(), true)
	match result:
		AiCombatMath.Morale.PASSED:
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s passes morale" % unit.get_name())
		AiCombatMath.Morale.SHAKEN:
			if not unit.is_shaken and radial_menu_controller != null:
				radial_menu_controller.card_toggle_shaken(unit)   # state + marker + MP broadcast
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s fails morale — Shaken" % unit.get_name())
		AiCombatMath.Morale.ROUT:
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s fails morale at half strength — ROUTS" % unit.get_name())
			_solo_apply_wounds(unit, unit.models.size() * 12)   # overkill wipes the unit via the normal flows


# === Solo P8: the player's own attack flow (radial "Shoot"/"Fight" → targeting mode → tray dice) ===

## Radial gate: Shoot/Fight show on units that are NOT the AI's while an AI opponent with living units
## exists (goal 001 P8).
func solo_combat_available(unit: GameUnit) -> bool:
	if unit == null or opr_army_manager == null or _solo_is_ai_unit(unit):
		return false
	for u in opr_army_manager.get_game_units_for_player(_solo_ai_slot()):
		if u != null and u.get_alive_count() > 0:
			return true
	return false


func _solo_is_ai_unit(unit: GameUnit) -> bool:
	var pid: int = int(unit.unit_properties.get("player_id", 0))
	return solo_ai_slots.has(pid) or (solo_ai_slots.is_empty() and pid == _solo_ai_slot())


## Enter targeting mode (P8): the weapon range shows as a ring, the line of sight to the hovered enemy
## draws live (green = clear, red = blocked); LMB on a valid AI unit resolves the attack, RMB/ESC cancels.
func solo_begin_targeting(unit: GameUnit, melee: bool) -> void:
	if unit == null:
		return
	_ensure_solo_controller()
	_solo_target_mode = {"unit": unit, "melee": melee}
	if not melee and range_ring_controller != null and range_ring_controller.has_method("show_spell_preview"):
		var weapons: Array = _solo_all_weapons(unit)
		var rng_in: int = AiArchetype.max_range_inches(weapons) + SoloController.shooting_range_bonus(unit)   # Royal Legion +4"
		if rng_in > 0:
			range_ring_controller.show_spell_preview(_solo_unit_nodes(unit), rng_in)
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL, "%s: pick a target (%s) — right-click cancels" % [unit.get_name(), ("melee" if melee else "shooting")])


func _solo_end_targeting() -> void:
	_solo_target_mode = {}
	if range_ring_controller != null and range_ring_controller.has_method("clear_spell_preview"):
		range_ring_controller.clear_spell_preview()
	if _solo_los_line != null and is_instance_valid(_solo_los_line):
		_solo_los_line.queue_free()
	_solo_los_line = null
	if _solo_los_label != null and is_instance_valid(_solo_los_label):
		_solo_los_label.queue_free()
	_solo_los_label = null
	_solo_los_cache = {}


## Targeting-mode input, driven by the pure SoloController.targeting_route router. Mouse events reach it
## via main._input below (object_manager defers the mouse while targeting); ESC arrives via
## _unhandled_key_input. Returns true when the event was consumed.
func _solo_targeting_input(event: InputEvent) -> bool:
	if _solo_target_mode.is_empty():
		return false
	match SoloController.targeting_route(event, _solo_over_blocking_ui()):
		SoloController.TargetingRoute.CANCEL:
			_solo_end_targeting()
			return true
		SoloController.TargetingRoute.TRACK:
			_solo_update_los_line((event as InputEventMouseMotion).position)
			return false   # motion may pass (camera etc.)
		SoloController.TargetingRoute.PICK:
			var mb := event as InputEventMouseButton
			var target := _solo_pick_unit_at(mb.position)
			var attacker: GameUnit = _solo_target_mode.get("unit")
			var melee: bool = bool(_solo_target_mode.get("melee", false))
			if target == null or not _solo_is_ai_unit(target) or _solo_combined_alive(target) <= 0 \
					or SoloController.unit_in_reserve(target):
				return true   # swallow the click; stay in targeting mode (a reserve unit is off-table)
			var verdict := _solo_validate_target(attacker, target, melee)
			if verdict != "":
				if battle_log != null:
					battle_log.log_event(BattleLog.Category.GENERAL, "%s: %s" % [target.get_name(), verdict])
				return true
			_solo_end_targeting()
			_run_human_attack(attacker, target, melee)
			return true
	return false


## True when the mouse hovers an interactive HUD control that must keep receiving its own clicks while
## targeting (same heuristic as object_manager._control_blocks_world_click — reused, not forked).
func _solo_over_blocking_ui() -> bool:
	if object_manager == null or not object_manager.has_method("_control_blocks_world_click"):
		return false
	return object_manager._control_blocks_world_click(get_viewport().gui_get_hovered_control())


## Solo P8 targeting owns the MOUSE while active — and this hook MUST live in _input:
## _unhandled_key_input only ever receives KEY events in Godot 4, so the original P8 wiring left the
## enemy click unreachable (maintainer field-test bug: clicking a target did nothing — object_manager's
## _input defers all mouse handling while targeting is active, and nobody else picked the click up).
## Keys (ESC) keep flowing through _unhandled_key_input; only mouse events are handled here.
func _input(event: InputEvent) -> void:
	if _solo_target_mode.is_empty():
		return
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if _solo_targeting_input(event):
		get_viewport().set_input_as_handled()


## "" when the target is attackable, else the human-readable reason. Shooting validity is PER MODEL
## (GF v3.5.1 p.8): the target is valid when at least ONE of the attacker's models has range + LOS.
func _solo_validate_target(attacker: GameUnit, target: GameUnit, melee: bool) -> String:
	if melee:
		# BASE-CONTACT measure (field-test finding 5): the true base-to-base gap between the nearest models,
		# not the unit-centre distance (which failed for wide/multi-model units the player had in contact).
		# Within MELEE_ENGAGE_IN of an enemy base counts as chargeable — the snap on confirm closes it to
		# clean contact (GF/AoF v3.5.1 p.9 "Who Can Strike": base contact folds into the 2" strike reach).
		var gap := solo_controller.nearest_melee_gap_in(attacker, target)
		if gap <= MELEE_ENGAGE_IN:
			return ""
		return "not in melee range (%.1f\" — move into base contact)" % gap
	var dist := MoveIntent.distance_inches(solo_controller.unit_centre(attacker), solo_controller.unit_centre(target))
	var rng_in: int = AiArchetype.max_range_inches(_solo_all_weapons(attacker)) + SoloController.shooting_range_bonus(attacker)
	if rng_in <= 0:
		return "no ranged weapons"
	if _solo_sighted_count(attacker, target, rng_in) <= 0:
		if dist > float(rng_in):
			return "out of range (%.0f\" > %d\")" % [dist, rng_in]
		return "no model has line of sight"
	return ""


func _solo_has_los(a: GameUnit, b: GameUnit) -> bool:
	if terrain_overlay == null or not terrain_overlay.has_method("has_line_of_sight"):
		return true
	return terrain_overlay.has_line_of_sight(solo_controller.unit_centre(a), solo_controller.unit_centre(b), 1, 1)


## The unit's weapons incl. attached heroes' (range ring + validation read the combined reach).
func _solo_all_weapons(unit: GameUnit) -> Array:
	var weapons: Array = []
	var members: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		members = members + unit.get_attached_heroes()
	for m in members:
		var member := m as GameUnit
		if member != null and member.source_type == "opr" and member.source_data is OPRApiClient.OPRUnit:
			weapons = weapons + (member.source_data as OPRApiClient.OPRUnit).weapons
	return weapons


func _solo_unit_nodes(unit: GameUnit) -> Array:
	var out: Array = []
	for m in unit.get_alive_models():
		var node: Node3D = (m as ModelInstance).node
		if node != null and is_instance_valid(node):
			out.append(node)
	return out


## Ray-pick the unit under the cursor (models carry meta "game_unit"; trays resolve via their regiment).
## Clicking an ATTACHED hero resolves to its HOST unit — a joined hero is part of the unit and is
## targeted through it (GF v3.5.1 "Hero"), never as its own target.
func _solo_pick_unit_at(screen_pos: Vector2) -> GameUnit:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var query := PhysicsRayQueryParameters3D.create(
		camera.project_ray_origin(screen_pos),
		camera.project_ray_origin(screen_pos) + camera.project_ray_normal(screen_pos) * 100.0)
	var hit: Dictionary = get_viewport().world_3d.direct_space_state.intersect_ray(query)
	var col: Object = hit.get("collider")
	var picked: GameUnit = null
	if col is Node and (col as Node).has_meta("game_unit"):
		picked = (col as Node).get_meta("game_unit") as GameUnit
	elif col is RegimentTray and opr_army_manager != null:
		for reg in opr_army_manager.regiments.values():
			if reg != null and reg.tray == col and reg.game_unit != null:
				picked = reg.game_unit as GameUnit
				break
	if picked != null and picked.has_method("is_attached") and picked.is_attached():
		var host: Variant = picked.get_attached_to()
		if host is GameUnit:
			return host
	return picked


const SOLO_LOS_REFRESH_MS := 150   # throttle for the per-model sighted-count recompute during hover
const SOLO_LOS_UNBOUNDED_RANGE_IN := 9999   # "range never gates" sentinel for a pure LOS query
const MELEE_ENGAGE_IN := 1.0   # base-edge gap within which the player may declare a Fight (then it snaps to contact)


## Live line of sight to the hovered enemy (goal 001 P8 + goal 003 per-model LOS): the line is green when
## at least one attacker model can fire, red when none can, and a floating "7/10 sight" label shows how
## many models actually contribute attacks (GF v3.5.1 p.8). The per-model count is model×model grid walks,
## so it is cached per hovered unit and refreshed at most every SOLO_LOS_REFRESH_MS.
func _solo_update_los_line(screen_pos: Vector2) -> void:
	var attacker: GameUnit = _solo_target_mode.get("unit")
	var hovered := _solo_pick_unit_at(screen_pos)
	if attacker == null or hovered == null or not _solo_is_ai_unit(hovered):
		if _solo_los_line != null and is_instance_valid(_solo_los_line):
			_solo_los_line.visible = false
		if _solo_los_label != null and is_instance_valid(_solo_los_label):
			_solo_los_label.visible = false
		return
	if _solo_los_line == null or not is_instance_valid(_solo_los_line):
		_solo_los_line = MeshInstance3D.new()
		_solo_los_line.mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.no_depth_test = true
		_solo_los_line.material_override = mat
		add_child(_solo_los_line)
	var melee: bool = bool(_solo_target_mode.get("melee", false))
	var sighted := 0
	var total: int = _solo_combined_alive(attacker)
	if melee:
		sighted = total if _solo_has_los(attacker, hovered) else 0   # melee keeps the simple centre check
	else:
		# Throttled per-model count (cached per hovered unit; refreshed at most every SOLO_LOS_REFRESH_MS).
		var now := Time.get_ticks_msec()
		if str(_solo_los_cache.get("target_id", "")) != hovered.unit_id \
				or now - int(_solo_los_cache.get("at", 0)) > SOLO_LOS_REFRESH_MS:
			var rng_in: int = AiArchetype.max_range_inches(_solo_all_weapons(attacker))
			_solo_los_cache = {"target_id": hovered.unit_id, "at": now,
				"count": _solo_sighted_count(attacker, hovered, rng_in)}
		sighted = int(_solo_los_cache.get("count", 0))
	var color := Color(0.2, 0.9, 0.3) if sighted > 0 else Color(0.95, 0.25, 0.2)
	var from := solo_controller.unit_centre(attacker) + Vector3(0, 0.04, 0)
	var to := solo_controller.unit_centre(hovered) + Vector3(0, 0.04, 0)
	var im := _solo_los_line.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(color)
	im.surface_add_vertex(from)
	im.surface_set_color(color)
	im.surface_add_vertex(to)
	im.surface_end()
	_solo_los_line.visible = true
	# Floating count label at the line midpoint (shooting only — melee reach is the 2" contact check).
	if not melee:
		if _solo_los_label == null or not is_instance_valid(_solo_los_label):
			_solo_los_label = Label3D.new()
			_solo_los_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_solo_los_label.no_depth_test = true
			_solo_los_label.pixel_size = 0.0004
			_solo_los_label.outline_size = 8
			add_child(_solo_los_label)
		_solo_los_label.text = "%d/%d sight" % [sighted, total]
		_solo_los_label.modulate = color
		_solo_los_label.global_position = (from + to) * 0.5 + Vector3(0, 0.05, 0)
		_solo_los_label.visible = true
	elif _solo_los_label != null and is_instance_valid(_solo_los_label):
		_solo_los_label.visible = false


## Resolve the player's declared attack — the mirror of the AI flow: your groups (unit + heroes, own
## Quality) roll REAL to-hit dice in the tray, the AI saves in the tray, wounds run through the flows.
## Melee: the AI ALWAYS strikes back (official rule) — you save via the prompt; loser tests morale.
func _run_human_attack(attacker: GameUnit, target: GameUnit, melee: bool) -> void:
	if attacker == null or target == null or dice_roller_control == null:
		return
	_solo_log_unmodeled_rules(attacker)
	_solo_log_unmodeled_rules(target)
	if melee:
		# CHARGE SNAP (field-test finding 5): before the strikes, snap the charging unit into clean base
		# contact — its nearest model touches the enemy and the rest ride forward in coherency (GF/AoF
		# v3.5.1 p.8). A small nudge (validation already required ≤ MELEE_ENGAGE_IN); logged + broadcast.
		var snapped: float = solo_controller.snap_charge(attacker, target)
		if snapped > 0.05 and battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT,
				"%s charges into base contact (+%.1f\") — the unit follows in coherency (GF/AoF v3.5.1 p.8)" % [attacker.get_name(), snapped], true)
		# The defender's pull-in is a SEPARATE rule the player applies by hand (the automation never moves
		# the opponent's models on the player's behalf): GF/AoF v3.5.1 p.9.
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT,
				"Bring-in: any of %s's models not in base contact may move up to 3\" into contact, keeping coherency (GF/AoF v3.5.1 p.9)" % target.get_name())
		await _run_human_melee(attacker, target)
	else:
		await _run_human_shooting(attacker, target)
	# Finding 5: if the human's ACTIVATING unit was WIPED during its own activation (a melee strike-back or a
	# dangerous-terrain test), it can never be marked activated via the radial toggle — so AUTO-COMPLETE it
	# here: mark it consumed and register the human activation so the AI gets its one alternating reply.
	# Otherwise the alternation stalls (the human's activation trigger never fired). A pre-toggled unit
	# (is_activated already true) is untouched and falls through to the normal pump.
	if attacker != null and SoloController.human_activation_autocompletes(attacker.is_destroyed(), attacker.is_activated):
		attacker.is_activated = true
		await _on_solo_human_activated(attacker)
	else:
		# The AI's strike-back can destroy the human's LAST eligible unit — re-check the alternation
		# state so the AI's remaining activations auto-continue (goal 003 P2 auto-tail).
		await _solo_pump()


## The player's shooting volley (goal 001 P8): per-model attack scaling, Reliable composed with the to-hit
## modifiers (Stealth / Artillery / Evasive — GF/AoF v3.5.1 p.13/14 + army-book text), Cover + Shielded on
## the AI's saves (Blast ignores cover but NOT Shielded), Rending/Bane in the save resolver, then the
## post-shooting morale trigger.
func _run_human_shooting(attacker: GameUnit, target: GameUnit) -> void:
	var dist := MoveIntent.distance_inches(solo_controller.unit_centre(attacker), solo_controller.unit_centre(target))
	var target_alive_before: int = target.get_alive_count()   # post-shooting morale (goal 003 P1)
	var regenable := 0
	var regen_proof := 0
	# Armor(X) (wave 5) sets the working Defense, then Shielded (+1 Defense, army-book rule) covers
	# every hit; Cover (+1 Defense majority-in-cover, GF v3.5.1 p.11) is shooting-only and ignored by
	# Blast and Indirect (wave 5).
	_solo_log_armor(target)
	var shielded_def: int = _solo_shielded_defense(target)
	if shielded_def != _solo_armored_defense(target) and battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT, "%s is Shielded: +1 Defense (saves on %d+)" % [
			target.get_name(), shielded_def], true)
	var covered_def: int = _solo_cover_defense(target, shielded_def)
	# Per-model shooting transparency (GF v3.5.1 p.8): tell the player how many models actually fire.
	if battle_log != null:
		var rng_in: int = AiArchetype.max_range_inches(_solo_all_weapons(attacker))
		var total := _solo_combined_alive(attacker)
		battle_log.log_event(BattleLog.Category.COMBAT, "%s: %d/%d model%s with line of sight + range" % [
			attacker.get_name(), _solo_sighted_count(attacker, target, rng_in), total, ("" if total == 1 else "s")], true)
	for grp in _solo_attack_groups(attacker, dist, false, target):
		var group := grp as Dictionary
		var base_quality: int = int(group.get("quality", 4))
		var mod_info: Dictionary = _solo_hit_mod_info(group.get("member"), target, dist, false)
		for p in group.get("profiles", []):
			var profile := p as Dictionary
			if int(profile.get("attacks", 0)) <= 0:
				continue
			# Reliable sets the Quality (2+), THEN the roll modifiers apply (GF v3.5.1 p.14: "Reliable only
			# changes the Quality value, so the roll can still be modified").
			var to_hit: int = AiCombatMath.modified_hit_target(
				AiCombatMath.reliable_quality(base_quality, bool(profile.get("reliable", false))), int(mod_info.get("mod", 0)))
			_solo_log_hit_mod(mod_info, target, to_hit)
			var faces: Array = await _solo_tray_roll(int(profile.get("attacks", 0)), to_hit, "You")
			if bool(profile.get("limited", false)):
				solo_controller.mark_limited_used(group.get("member"), profile)   # once per game (wave 5)
			var hits: int = _solo_hits(faces, to_hit, profile, dist, target)
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s fires %s at %s — %d hit%s" % [
					str(group.get("name", "?")), str(profile.get("name", "?")), target.get_name(), hits, ("" if hits == 1 else "s")])
			if hits <= 0:
				continue
			# Blast (GF v3.5.1) and Indirect (wave 5) ignore cover — saves at the Shielded (uncovered) Defense.
			var save_def: int = shielded_def if (int(profile.get("blast", 0)) > 1 or bool(profile.get("indirect", false))) else covered_def
			var w: int = await _solo_resolve_saves(group.get("member"), target, str(profile.get("name", "?")), faces, hits, save_def, profile, false, false)
			if _solo_ignores_regen(group.get("member"), profile):
				regen_proof += w
			else:
				regenable += w
	await _solo_land_wounds(target, regenable, regen_proof)
	# The AI's unit tests morale if your volley dropped it to half strength or less (goal 003 P1).
	await _solo_shooting_morale(target, target_alive_before, "AI (%s)" % target.get_name())


## The player's melee charge (goal 001 P8): the AI defender's Counter weapons strike FIRST (it must always
## strike back — solo rules p.57 — so no prompt), Impact (Counter-reduced), your strikes (charging:
## Furious/Thrust; the AI's Evasive/Shielded apply), the AI's remaining strike-back, then the Fear-adjusted
## melee-winner morale (GF/AoF v3.5.1 p.13).
func _run_human_melee(attacker: GameUnit, target: GameUnit) -> void:
	var human_caused := 0
	var ai_caused := 0
	# — Counter (GF/AoF v3.5.1 p.13 "Strikes first with this weapon when charged"): before your attacks,
	#   including Impact (Counter's Impact reduction presumes the counter-strike precedes it) —
	var ai_counter: bool = _solo_has_counter(target)
	if ai_counter:
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "Counter: %s strikes first" % target.get_name(), true)
		ai_caused += await _solo_melee_strike_phase(target, attacker, false, SoloStrike.COUNTER_ONLY)
	# — Impact(X) auto-hits on your charge (GF/AoF v3.5.1 p.13; reduced by the AI's Counter models). The
	#   counter-strike may already have wiped your unit — nothing left to roll then. —
	if _solo_combined_alive(attacker) > 0:
		human_caused += await _solo_charge_impact(attacker, target, false)
	# — Your strikes (unit + attached heroes; only models within 2" strike; charging bonuses apply) —
	if _solo_combined_alive(attacker) > 0:
		human_caused += await _solo_melee_strike_phase(attacker, target, true, SoloStrike.ALL)
		_solo_set_fatigued(attacker)
	# — The AI's strike-back with its remaining (non-Counter) weapons — mandatory (solo rules p.57) —
	var ai_struck: bool = ai_counter
	if _solo_combined_alive(target) > 0 and _solo_combined_alive(attacker) > 0:
		ai_caused += await _solo_melee_strike_phase(target, attacker, false,
			SoloStrike.NON_COUNTER if ai_counter else SoloStrike.ALL)
		ai_struck = true
	if ai_struck and _solo_combined_alive(target) > 0:
		_solo_set_fatigued(target)
	# — Morale: the side that CAUSED more wounds wins; the loser tests. Fear(X) (GF/AoF v3.5.1 p.13) adds
	#   +X to the bearer's tally for THIS comparison only. —
	var human_score: int = AiCombatMath.fear_adjusted_wounds(human_caused, _solo_unit_rating(attacker, "Fear"))
	var ai_score: int = AiCombatMath.fear_adjusted_wounds(ai_caused, _solo_unit_rating(target, "Fear"))
	if human_score > ai_score and _solo_combined_alive(target) > 0:
		await _solo_morale_test(target, "AI (%s)" % target.get_name())
	elif ai_score > human_score and _solo_combined_alive(attacker) > 0:
		await _solo_morale_test(attacker, "You")
	# — Consolidation (GF v3.5.1 p.9): the CHARGER must move back 1" — that is YOUR unit here, and the
	#   solo automation never moves the player's models, so the rule is surfaced as a reminder. —
	if _solo_combined_alive(attacker) > 0 and _solo_combined_alive(target) > 0 and battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT,
			"Consolidation: move %s back 1\" (the charger separates — GF v3.5.1 p.9)" % attacker.get_name(), true)


## Mark a unit (and its attached heroes — they fought too) Fatigued after its first melee this round
## (state + marker + broadcast via the radial seam).
func _solo_set_fatigued(unit: GameUnit) -> void:
	if unit == null or radial_menu_controller == null:
		return
	if not unit.is_fatigued:
		radial_menu_controller.card_toggle_fatigued(unit)
	if unit.has_method("get_attached_heroes"):
		for h in unit.get_attached_heroes():
			if h != null and not h.is_fatigued:
				radial_menu_controller.card_toggle_fatigued(h)


## Solo auto-game round change (goal 003 P1). Gated on an active Solo AI so manual/MP games keep managing
## their own markers by hand. Fires with the NEW round number.
func _on_solo_round_advanced(_round_number: int) -> void:
	if solo_ai_slots.is_empty():
		return
	_solo_reset_all_fatigue()
	# Battleborn recovery + Ambush arrivals + the human reserve prompt are the ROUND-START sequence, now driven
	# AND AWAITED by _solo_end_round (_solo_round_start) so they complete before the opener activates (field-test
	# round 6, finding 4). Kept OUT of this fire-and-forget signal handler so they never run concurrently with
	# the activation pump.


## The solo ROUND-START sequence (GF/AoF v3.5.1 p.13), run at the start of every new round BEFORE any
## activation and AWAITED by _solo_end_round: the AI's Battleborn Shaken-recovery (wave 4), then — from round 2
## — Ambush reserve arrivals (AI, paced) and the human's reserve deployment prompt. Sequencing it here (rather
## than off the round_advanced signal) is finding 4: reserves are on the table and the prompt resolved before
## the opener activates, and a just-arrived reserve is counted in this round's alternation.
func _solo_round_start(round_number: int) -> void:
	if solo_ai_slots.is_empty():
		return
	await _solo_battleborn_recovery()
	# Ambush arrivals happen at the start of ANY round after the first (GF/AoF v3.5.1 p.13), so a unit
	# with no clear spot in round 2 gets another chance later.
	if round_number >= 2:
		await _solo_arrive_ambush()
		await _solo_prompt_human_ambush(round_number)   # field-test finding 5: ASK the human to deploy reserves


## Wave-4 Battleborn (army-book rule, Battle Brothers — "If a unit where all models have this rule is
## Shaken at the beginning of the round, roll one die. On a 4+, it stops being Shaken."): at round start,
## every AI Shaken Battleborn unit rolls one real tray die and recovers on a 4+ (NOT spending its
## activation). The human's own Battleborn units are surfaced as a reminder (the automation never touches
## the player's markers).
func _solo_battleborn_recovery() -> void:
	if opr_army_manager == null:
		return
	for u in opr_army_manager.get_all_game_units():
		var gu := u as GameUnit
		if gu == null or not gu.is_shaken or not _solo_rule_on_all_models(gu, "Battleborn"):
			continue
		if _solo_is_ai_unit(gu):
			var face: Array = await _solo_tray_roll(1, AiCombatMath.BATTLEBORN_RECOVER_TARGET, "AI (%s)" % gu.get_name())
			var recovered: bool = not face.is_empty() and AiCombatMath.battleborn_recovers(int(face[0]))
			if recovered and radial_menu_controller != null:
				radial_menu_controller.card_toggle_shaken(gu)   # clears Shaken via the state+marker+MP seam
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "Battleborn: %s %s" % [
					gu.get_name(), ("recovers from Shaken (4+)" if recovered else "stays Shaken")], true)
		elif battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT,
				"Battleborn: roll for %s to recover from Shaken (4+)" % gu.get_name(), true)


## Prompt the human to deploy Ambush reserves at the start of a round ≥2 (field-test finding 5; GF/AoF
## v3.5.1 p.13: reserve units MAY be deployed at the start of any round after the first). A ConfirmationDialog
## lists the held units — "Deploy now" places them all via guided placement (>9" from enemies, near an
## objective, terrain-legal), "Keep waiting" holds them for a later round (they are prompted again). Only a
## GENUINE human side is ever prompted (never in AI-vs-AI self-play, where the human slot is also AI). The
## AI's world-model already counts these reserves as existing-but-off-table (unit_in_reserve everywhere), so
## nothing reads as "board complete" while they wait.
func _solo_prompt_human_ambush(round_number: int) -> void:
	if solo_controller == null or opr_army_manager == null or table == null:
		return
	if solo_ai_slots.has(solo_controller.human_slot):
		return   # the "human" slot is AI (self-play) — never prompt
	var reserves: Array = solo_controller.human_reserve_units()
	if not SoloController.should_prompt_human_ambush(round_number, reserves.size()):
		return
	var names: Array = []
	for u in reserves:
		names.append((u as GameUnit).get_name())
	var dlg := ConfirmationDialog.new()
	dlg.title = "Ambush — Round %d" % round_number
	dlg.dialog_text = "Deploy your Ambush reserve now, more than 9\" from enemies?\n\n%s\n\n“Deploy now” places them; “Keep waiting” holds them for a later round." % ", ".join(names)
	dlg.ok_button_text = "Deploy now"
	dlg.get_cancel_button().text = "Keep waiting"
	var done := [false]
	var chose_deploy := [false]
	dlg.confirmed.connect(func() -> void: chose_deploy[0] = true; done[0] = true)
	dlg.canceled.connect(func() -> void: done[0] = true)
	dlg.close_requested.connect(func() -> void: done[0] = true)
	$UI.add_child(dlg)
	dlg.popup_centered()
	while not done[0]:
		await get_tree().process_frame
	if chose_deploy[0]:
		await _solo_deploy_human_ambush(reserves)
	if is_instance_valid(dlg):
		dlg.queue_free()


## Guided deployment of the human's chosen Ambush reserves (finding 5): placed ONE at a time, >9" from every
## on-table AI unit, near an objective, terrain-legal (SoloController.arrive_human_reserve_unit — the same
## legal core the AI's arrival uses), then revealed + synced with a paced camera beat and a battle-log line,
## so a human arrival is as watchable as an AI one. A unit with no legal spot this round stays reserved and
## is prompted again next round (GF/AoF v3.5.1 p.13).
func _solo_deploy_human_ambush(reserves: Array) -> void:
	var w: float = table.table_size.x * 0.3048
	var d: float = table.table_size.y * 0.3048
	var arrival_zone := Rect2(Vector2(-w / 2.0, -d / 2.0), Vector2(w, d))
	var enemy_positions: Array = []
	for u in opr_army_manager.get_game_units_for_player(solo_controller.ai_slot):
		var gu := u as GameUnit
		if gu != null and gu.get_alive_count() > 0 and not SoloController.unit_in_reserve(gu):
			var c := solo_controller.unit_centre(gu)
			enemy_positions.append(Vector2(c.x, c.z))
	var occupied: Array = []
	var round_no: int = opr_army_manager.current_round
	for u in reserves:
		var unit := u as GameUnit
		if unit == null or unit.get_alive_count() <= 0 or not SoloController.unit_in_reserve(unit):
			continue
		if solo_controller.arrive_human_reserve_unit(unit, arrival_zone, enemy_positions, occupied, round_no):
			_solo_set_unit_visible(unit, true)
			_solo_focus_on_unit(unit)
			_solo_show_toast("%s deploys from reserve" % unit.get_name())
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.GENERAL,
					"You deploy %s from Ambush reserve (>9\" from enemies) — it may act this round" % unit.get_name(), false)
			await _solo_pace_attention()
	if is_instance_valid(_solo_toast):
		_solo_toast.visible = false
	var held: int = solo_controller.human_reserve_units().size()
	if held > 0 and battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL,
			"%d of your Ambush unit(s) had no legal spot — you'll be asked again next round." % held, false)


## OPR Ambush (GF/AoF v3.5.1 p.13; field-test findings 4 + 5): the AI's reserved units arrive at the start
## of a round after the first, >9" from your units and near the nearest objective. Each arrival is its OWN
## PACED, ANNOUNCED beat — camera attention, a battle-log line and a hold — placed ONE at a time (finding 4:
## they used to appear simultaneously and silently). Arriving does NOT consume the unit's activation
## (finding 5): its reserve flag clears, so it is eligible to act this same round.
func _solo_arrive_ambush() -> void:
	if solo_controller == null or solo_controller.ambush_reserve.is_empty() or table == null or opr_army_manager == null:
		return
	var w: float = table.table_size.x * 0.3048
	var d: float = table.table_size.y * 0.3048
	var arrival_zone := Rect2(Vector2(-w / 2.0, -d / 2.0), Vector2(w, d))
	var enemy_positions: Array = []
	for u in opr_army_manager.get_game_units_for_player(solo_controller.human_slot):
		if u != null and u.get_alive_count() > 0:
			var c := solo_controller.unit_centre(u)
			enemy_positions.append(Vector2(c.x, c.z))
	var occupied: Array = []
	var round_no: int = opr_army_manager.current_round
	while true:
		var unit: GameUnit = solo_controller.arrive_one_ambush_unit(arrival_zone, enemy_positions, occupied, round_no)
		if unit == null:
			break
		_solo_set_unit_visible(unit, true)   # reveal it — this arrival is its ONE placement (finding 4)
		# A paced, announced arrival, like every other AI action: focus the unit, name it, hold a beat.
		_solo_focus_on_unit(unit)
		_solo_show_toast("%s ambushes in from reserve" % unit.get_name())
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.GENERAL,
				"AI Ambush: %s arrives from reserve (>9\" from your units) — it may still act this round" % unit.get_name(), true)
		await _solo_pace_attention()
	if is_instance_valid(_solo_toast):
		_solo_toast.visible = false
	var held: int = solo_controller.ambush_reserve.size()
	if held > 0 and battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL, "AI Ambush: %d unit(s) held back — no clear spot (may arrive a later round)" % held, true)
	_solo_flush_dev()


## OPR: Fatigue lasts only until the end of the round — clear it from EVERY unit (both sides, heroes
## included, since get_all_game_units returns joined heroes too) at each round change. This reset was
## missing (fatigue accumulated forever). Uses the radial seam so state + marker + MP sync stay in step.
func _solo_reset_all_fatigue() -> void:
	if opr_army_manager == null or radial_menu_controller == null:
		return
	var cleared := 0
	for u in opr_army_manager.get_all_game_units():
		if u != null and u.is_fatigued:
			radial_menu_controller.card_toggle_fatigued(u)
			cleared += 1
	if cleared > 0 and battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL, "Fatigue clears — new round")


## Apply shooting wounds through the EXISTING flows so parking, battle log and MP sync keep working:
## regiments take pooled wounds; loose units lose whole models back-rank-first (defender-optimal
## default), Tough models absorb wounds before dying.
func _solo_apply_wounds(target: GameUnit, wounds: int) -> void:
	if wounds <= 0 or opr_army_manager == null:
		return
	if opr_army_manager.regiments.has(target.unit_id):
		var reg = opr_army_manager.regiments[target.unit_id]
		if reg != null:
			opr_army_manager.apply_regiment_wounds(reg, reg.wounds_taken + wounds)
			return
	var pid: int = int(target.unit_properties.get("player_id", 1))
	var remaining := _solo_wound_models(target, wounds, pid)
	# A joined hero is part of the unit and takes wounds LAST (defender-optimal, field-test lock).
	if remaining > 0 and target.has_method("get_attached_heroes"):
		for h in target.get_attached_heroes():
			if remaining <= 0:
				break
			if h != null:
				remaining = _solo_wound_models(h, remaining, pid)
	if battle_log != null:
		battle_log.on_wounds(target.get_name(), wounds, _solo_combined_alive(target), target.models.size())


## Apply up to `wounds` to a unit's models back-rank-first (Tough absorbs before dying); returns the
## wounds left over (spill into an attached hero handled by the caller). The damage core is the testable
## SoloController.apply_wounds_to_models; this wires the SAME visible seams manual play uses — the wound
## token + MP broadcast for a surviving Tough model (maintainer field-test: an AI Tough hero soaked
## wounds with no visible tick), and tray-parking on death.
func _solo_wound_models(unit: GameUnit, wounds: int, pid: int) -> int:
	var on_changed := func(m: ModelInstance) -> void:
		if radial_menu_controller != null:
			radial_menu_controller._update_wound_marker(m)
		if network_manager != null and network_manager.has_method("broadcast_model_wounds"):
			network_manager.broadcast_model_wounds(m)
	var on_died := func(m: ModelInstance) -> void:
		if m.node != null and is_instance_valid(m.node):
			opr_army_manager.set_loose_model_dead(m.node, pid, true, unit.unit_id)
		if network_manager != null and network_manager.has_method("broadcast_model_wounds"):
			network_manager.broadcast_model_wounds(m)
	return SoloController.apply_wounds_to_models(unit, wounds, on_changed, on_died)


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
	# F8: export the Battle Log to a shareable user:// text file (same as the panel's Export button).
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_on_battle_log_export()
		get_viewport().set_input_as_handled()
		return
	# Solo P8: while the player is picking an attack target, ESC cancels the mode. (KEY events only ever
	# reach _unhandled_key_input — the mouse side of targeting is hooked in _input above.)
	if not _solo_target_mode.is_empty() and _solo_targeting_input(event):
		get_viewport().set_input_as_handled()
		return
	# F11 (Solo/AI M1 debug trigger): treat player 2's army as AI-controlled and run its turn — each of
	# its un-activated units advances toward the nearest player-1 unit and is marked activated. Movement
	# only (no combat yet). This is the M1 walking-skeleton entry point until the solo-game setup UI lands.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		_run_solo_ai_turn()
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
## visuals, and syncs to remote peers so everyone shares the same round. In a solo
## game the end-of-round objective seize runs first (goal 003 P2) — the manual
## button stays a full override of the auto-advance.
func _do_next_round() -> void:
	if _solo_alternation_active():
		_ensure_solo_controller()
		_solo_auto_seize()
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

	# Solo (goal 001): an AI-triggered tray roll is attributed to the AI in the logs, not to "You".
	var roller_name := _next_roll_owner if not _next_roll_owner.is_empty() else "You"
	_next_roll_owner = ""
	_add_dice_log_entry(roller_name, faces, context, color_tags)

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
	battle_log_panel.export_requested.connect(_on_battle_log_export)
	battle_log.on_game_started()
	# Central seams (fewest hooks that cover local + remote):
	if opr_army_manager != null:
		opr_army_manager.round_advanced.connect(battle_log.on_round_advanced)
		opr_army_manager.round_advanced.connect(_on_solo_round_advanced)   # goal 003 P1: fatigue reset + ambush
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
		# Solo P2 alternating activation: the human's radial activation triggers ONE AI answer (goal 003 P2).
		radial_menu_controller.unit_activated.connect(_on_solo_human_activated)


## Export the Battle Log to a shareable user:// file (Battle Log panel Export button OR the F8 hotkey). When
## the dev "AI reasoning" toggle is on the AI's structured decision records are ALREADY interleaved into the
## log (via _solo_flush_dev); any still-buffered (not-yet-flushed) records are ALSO rendered into a trailing
## AI-decision-records section so nothing diagnostic is lost. The resolved ABSOLUTE path is printed to the
## console (findable) and echoed as a toast + a log line.
func _on_battle_log_export() -> void:
	if battle_log == null:
		return
	var decision_lines: Array = []
	if _solo_dev and solo_controller != null:
		for rec in solo_controller.decision_log:
			decision_lines.append(SoloController.render_decision(rec as Dictionary))
	var path: String = battle_log.export_to_file(decision_lines)
	if path.is_empty():
		_solo_show_toast("Battle Log export failed — see console")
		return
	battle_log.log_event(BattleLog.Category.GENERAL, "Battle Log exported → %s" % path)
	_solo_show_toast("Battle Log exported → %s" % path)


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
		e["max_in"] = maxf(float(e["max_in"]), float(mv.get("inches", 0.0)))
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

	# Restore game state (round, current player)
	save_manager._deserialize_game_state(state.get("game_state", {}))

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
func _on_opr_army_imported(army: OPRApiClient.OPRArmy, player_id: int, ai_controlled: bool = false) -> void:
	print("Importing army '%s' for Player %d%s" % [army.name, player_id, " (AI-controlled)" if ai_controlled else ""])
	# Solo (goal 001): remember the designation; the Solo panel + F11 read it. Re-importing the slot
	# without the checkbox clears a stale designation.
	if ai_controlled:
		solo_ai_slots[player_id] = true
	else:
		solo_ai_slots.erase(player_id)
	_refresh_solo_panel.call_deferred()   # deferred: the synchronous army spawn below blocks first

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

## Solo section in the left panel (goal 001, F3): one AI toggle per imported army, so the designation
## can be changed after import (the import dialog's checkbox sets it up front). F11 plays the marked army.
func _init_solo_panel() -> void:
	var left_panel_vbox = $UI/HUD/LeftPanelScroll/LeftPanelVBox
	if not left_panel_vbox:
		return
	solo_panel_box = VBoxContainer.new()
	solo_panel_box.name = "SoloPanel"
	left_panel_vbox.add_child(solo_panel_box)
	_refresh_solo_panel()


## Rebuild the Solo section: a header + one "AI plays P<n> — <army>" CheckButton per imported army.
## Hidden entirely while no armies are imported.
func _refresh_solo_panel() -> void:
	if solo_panel_box == null or opr_army_manager == null:
		return
	for c in solo_panel_box.get_children():
		c.queue_free()
	var pids: Array = opr_army_manager.armies.keys()
	pids.sort()
	solo_panel_box.visible = not pids.is_empty()
	if pids.is_empty():
		return
	var label := Label.new()
	label.text = "Solo AI:"
	label.tooltip_text = "Mark the army the AI controls. The AI answers each of your activations with one of its own (alternating activation); after %d rounds the game is scored. F11 runs the whole remaining AI side at once (debug)." % SOLO_GAME_ROUNDS
	label.mouse_filter = Control.MOUSE_FILTER_STOP   # labels ignore the mouse by default — needed for the tooltip
	label.add_theme_color_override("font_color", Color(0.85, 0.87, 0.92, 1.0))
	solo_panel_box.add_child(label)
	var fast_cb := CheckButton.new()
	fast_cb.text = "Fast AI (short pauses)"
	fast_cb.tooltip_text = "Skips the move animation and shrinks the announce/outcome pauses of AI actions."
	fast_cb.button_pressed = _solo_fast
	fast_cb.focus_mode = Control.FOCUS_NONE
	fast_cb.add_theme_font_size_override("font_size", 12)
	fast_cb.toggled.connect(func(pressed: bool) -> void: _solo_fast = pressed)
	solo_panel_box.add_child(fast_cb)
	var dev_cb := CheckButton.new()
	dev_cb.text = "AI reasoning (dev)"
	dev_cb.tooltip_text = "Log WHY the AI decides: deployment spots, activation picks, tree branches, target EV scores, move budgets. Off = zero rendering cost."
	dev_cb.button_pressed = _solo_dev
	dev_cb.focus_mode = Control.FOCUS_NONE
	dev_cb.add_theme_font_size_override("font_size", 12)
	dev_cb.toggled.connect(func(pressed: bool) -> void: _solo_dev = pressed)
	solo_panel_box.add_child(dev_cb)
	for pid in pids:
		var army = opr_army_manager.armies[pid]
		var cb := CheckButton.new()
		cb.text = "AI plays P%d — %s" % [int(pid), (str(army.name) if army != null else "Army")]
		cb.button_pressed = solo_ai_slots.has(int(pid))
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 12)
		cb.toggled.connect(_on_solo_ai_toggled.bind(int(pid)))
		solo_panel_box.add_child(cb)
	var deploy_btn := Button.new()
	deploy_btn.text = "Deploy AI army"
	deploy_btn.tooltip_text = "OPR AI deployment: 3 random groups, D3 sections, placed toward the nearest objective (F11 then runs the activations)."
	deploy_btn.focus_mode = Control.FOCUS_NONE
	deploy_btn.pressed.connect(_on_solo_deploy_pressed)
	solo_panel_box.add_child(deploy_btn)


func _on_solo_ai_toggled(pressed: bool, player_id: int) -> void:
	if pressed:
		solo_ai_slots[player_id] = true
		_solo_game_finished = false   # (re)designating an AI army starts a fresh solo match
		_solo_log_rule_inventory(player_id)   # handoff transparency: what the AI understands, black on white
	else:
		solo_ai_slots.erase(player_id)


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

	# Sync visibility to remote clients
	_broadcast_table_settings_update("deployment_visible", show_zones)


## Handle the deployment-zone colour flip (asymmetric-map side choice).
func _on_deployment_flip_toggled(flipped: bool) -> void:
	if not terrain_overlay or not terrain_overlay.has_method("set_deployment_colors_flipped"):
		return
	terrain_overlay.set_deployment_colors_flipped(flipped)
	_broadcast_table_settings_update("deployment_flipped", flipped)


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
