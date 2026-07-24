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
## Wave-2 tutorial seam (toolstrack spec §14): ONE consolidated edge for the dice-control rows —
## count / success / modifier / reroll / movecap. The tutorial director gates T-05 steps on it;
## display-consumers only, no game logic reads it back.
signal dice_controls_changed(kind: StringName, value: int)

var _dice_count: int = DEFAULT_DICE_COUNT
var _dice_preset_buttons: Array[Button] = []
var _dice_count_value_label: Label = null
var _current_roll_column: VBoxContainer = null
var _movement_cap_buttons: Dictionary = {}  # MovementCap mode -> Button (the "Movement" cap row)

# Success evaluation + rerolls (display-only aids; the rules live in DiceRules).
var _success_target: int = DiceRules.TARGET_NONE
var _success_modifier: int = 0
var _next_roll_owner: String = ""   # attribution for the next tray roll ("AI (…)"); empty = "You" (goal 001)
var _next_roll_kind: String = "attack"   # Bug 16: "defense" words the dice-log line as "defends … blocks"
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
var _tutorial_mode: bool = false              # guided tutorial: set from the startup-menu flag, drives _start_tutorial
var _tutorial_director: TutorialDirector = null
var _tutorial_start_lesson: String = ""       # chapter-picker lesson id ("" = assessment/resume flow)
var _tutorial_board_pending: bool = false     # the bundled tutorial board was queued on the pending-load path
var _tutorial_board_loaded: bool = false      # its load finished (load_completed/load_failed fired)
var _host_free_move_check: CheckButton = null   # "Move all models" — host-operated, session-wide
var _room_code_button: Button = null          # permanent room-code display in the left bar (click = copy)
var _session_room_code: String = ""
var _hovered_model: Node3D = null

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
var sight_fan_controller: Node = null   # SightFanController (summed sight+range fan, F on selection)
var _sight_fan_unit: GameUnit = null     # unit whose fan is currently shown (F toggles)
var movement_range_controller: Node = null  # MovementRangeController (Advance/Rush reach)
var solo_controller: SoloController = null   # Solo/AI — drives the designated AI army (F11 = whole side)
var solo_ai_slots: Dictionary = {}           # player_id -> true: armies the Solo AI controls (goal 001)
var _solo_interactive_grade: String = "nachtmahr"  # the ONE grade (NML-211): NACHTMAHR, every knob at
                                                  # its ceiling. WITHOUT a grade active_difficulty()==null
                                                  # → the naive baseline AI (no position solver, no knobs).
var solo_panel_box: VBoxContainer = null     # left-panel "Solo" section (per-army AI toggles)
var _solo_target_mode: Dictionary = {}       # {unit, melee} while the player picks an attack target (P8)
var _solo_model_pick: Dictionary = {}        # B5: {unit, recommended, outcome} while a Takedown pick awaits a model click
var _solo_deploy_fsm: Dictionary = {}        # click-driven deployment machine (side/main/scout/done — maintainer flow 2026-07-23)
var _solo_deploy_ui: CanvasLayer = null      # the deployment hand-over panel (label + up to two buttons)
var _solo_deploy_ui_label: Label = null
var _solo_deploy_ui_btn1: Button = null
var _solo_deploy_ui_btn2: Button = null
var _solo_los_line: MeshInstance3D = null    # live line to the hovered target: green = clear, red = blocked
var _solo_los_label: Label3D = null          # floating "7/10 sight" count on the targeting line (per-model LOS)
var _solo_los_cache: Dictionary = {}         # {target_id, count, at} — throttles the per-model LOS recompute
# Solo P2 auto-game state (goal 003 P2): alternation queue + match end.
const SOLO_GAME_ROUNDS := 4                  # OPR standard match length (rounds)
const SOLO_AI_TAIL_DELAY_S := 1.2            # readable pause between the AI's unprompted tail activations
const SOLO_DEPLOY_WALL_CLEARANCE_M := 0.02   # a deploy sample point within 2 cm (~0.8") of a container/ruin wall is blocked (finding 1)
var _solo_pending_replies: int = 0           # human activations still owed one AI answer (alternation)
var _solo_replied_ids: Dictionary = {}       # unit instance ids whose activation already earned the AI's reply
                                             # THIS round (round 7, finding 5: re-toggling a unit's activation
                                             # marker must never grant the AI a second answer)
var _solo_ai_took_last_activation: bool = true  # who took the LAST activation of the current round (finding 7:
                                             # drives who OPENS the next round — the OTHER side, never back-to-back).
                                             # Init true so round 1 opens with the human (the default deployment order).
var _solo_ai_busy: bool = false              # an AI activation chain is running (guards re-entry)
var _solo_game_finished: bool = false        # summary shown after SOLO_GAME_ROUNDS — no further auto-advance
var _solo_ai_banner: Label = null            # non-blocking "AI is taking its turn…" banner during the tail
var _solo_dream_overlay: Control = null      # centred "NACHTMAHR dreams…" + spinner while the AI computes
var _ai_opponent_btn: Button = null          # "KI-Gegner (eigene Liste)" — NACHTMAHR builds its own army
const AI_LISTS_DIR := "res://assets/ai_lists"          # dev/arena bundle — NEVER in the public repo
const AI_LISTS_CDN_PATH := "ai_lists"                   # <AssetCdn.HOST>/ai_lists/… (S6 runtime delivery)
const AI_LISTS_CACHE_DIR := "user://ai_lists_cache"     # offline replay of fetched lists
var _solo_fast: bool = false                 # fast-forward: shrink pacing holds + skip move animation
var _solo_batch: bool = false                # headless sweeps: instant (non-physics) dice + zero pacing holds (implies fast)
var _solo_dev: bool = false                  # developer mode: render the AI's decision records into the battle log
## Per-activation stderr trace of the both-AI arena loop (env NML_AI_TRACE=1) — the ladder tooling's
## progress/stall diagnostic for long unattended headless matches. Off by default: zero output in normal play.
var _solo_arena_trace: bool = OS.get_environment("NML_AI_TRACE") == "1"
var _solo_toast: Label = null                # transient AI-action attribution/outcome toast
var _solo_unmodeled_logged: Dictionary = {}  # rule name -> true: once-per-session unmodeled-rule notes
# === AI ARENA — native both-AI mode + per-side difficulty (see SoloDifficulty) ===
var _solo_both_ai: bool = false              # BOTH sides are AI: combat auto-resolves, the game runs unattended
var _solo_spell_tokens_active: Array = []    # spell tokens placed this round [{unit, token}] — expire at round end
var _solo_spell_mods := {}                   # instance_id -> [{spell, hit_mod, def_mod, scope}] — MECHANICAL token effects (wave: spells F3)
var _solo_difficulty_grades: Dictionary = {} # player-slot -> SoloDifficulty preset name (the graded arena)
var _solo_arena_seed: int = 0                # game-level base seed for the reproducible difficulty knob draws
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
## Inactivity window (seconds) a guest waits between remote army-import RPCs before it gives up.
## The host paces unit batches ~250 ms apart (ARMY_BATCH_DELAY_MS), so even a large army never
## has a multi-second gap; this generous silence budget only trips when the host truly went away
## (dropped / relay lost the complete). On trip we abort the wait and recover (see below).
const IMPORT_AWAIT_TIMEOUT_SEC: float = 75.0
## Liveness guard for the above — header + each unit bump the player's generation, and a fired
## timer only aborts if its captured generation is still current (nothing arrived since).
var _import_await_guard := ImportAwaitGuard.new()


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
	object_manager.movement_capped.connect(_on_movement_capped)
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

	# Autosave (ROADMAP "Now" follow-up): periodic + round-start rotating snapshots into the save dir
	# (autosave_1..3.nml — the menu's CONTINUE + load dialog see them with no extra UI). Host-only in
	# MP, restore-lock aware, empty-table silent; details in autosave_controller.gd.
	var autosave := AutosaveController.new()
	autosave.name = "AutosaveController"
	add_child(autosave)
	autosave.setup(save_manager, opr_army_manager, object_manager, network_manager)
	autosave.autosaved.connect(func(path: String) -> void:
		_show_toast("Autosaved — %s" % path.get_file())
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.GENERAL, "Autosaved (%s)" % path.get_file(), true))

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

	# AI-opponent setup (maintainer): next to the import button, a "let NACHTMAHR bring its own list"
	# entry. The alternative — hand the AI YOUR imported list — is the existing per-slot AI checkbox.
	_ai_opponent_btn = Button.new()
	_ai_opponent_btn.name = "AiOpponentBtn"
	_ai_opponent_btn.text = "KI-Gegner (eigene Liste)"
	_ai_opponent_btn.tooltip_text = "NACHTMAHR baut sich selbst eine Liste: Fraktion + Punkte wählen. (Alternativ deiner KI eine importierte Liste geben: Häkchen beim Import.)"
	_ai_opponent_btn.pressed.connect(_open_ai_opponent_dialog)
	if import_opr_btn.get_parent() != null:
		import_opr_btn.get_parent().add_child(_ai_opponent_btn)
		import_opr_btn.get_parent().move_child(_ai_opponent_btn, import_opr_btn.get_index() + 1)

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

	# Guided tutorial (startup menu -> TUTORIAL): read-and-clear the runtime-only flags
	# FIRST, so the bundled tutorial board can ride the normal pending-load path below.
	# Never persisted to project.godot — exactly like harness_mode.
	var tutorial_mode: bool = ProjectSettings.get_setting("niemandsland/tutorial_mode", false)
	if tutorial_mode:
		ProjectSettings.set_setting("niemandsland/tutorial_mode", false)
		_tutorial_mode = true
		_tutorial_start_lesson = str(ProjectSettings.get_setting("niemandsland/tutorial_lesson", ""))
		ProjectSettings.set_setting("niemandsland/tutorial_lesson", "")
		if str(ProjectSettings.get_setting("niemandsland/pending_load_path", "")).is_empty() \
				and FileAccess.file_exists(TutorialDirector.BOARD_PATH):
			ProjectSettings.set_setting("niemandsland/pending_load_path", TutorialDirector.BOARD_PATH)
			_tutorial_board_pending = true
			# Race-free load gate: the director must only start once the board finished
			# deserializing (units exist), success or failure alike.
			save_manager.load_completed.connect(
				func(_object_count: int) -> void: _tutorial_board_loaded = true, CONNECT_ONE_SHOT)
			save_manager.load_failed.connect(
				func(_error: String) -> void: _tutorial_board_loaded = true, CONNECT_ONE_SHOT)

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
	# The tutorial reuses the harness seam: skip the chooser + intro, open a prepared table
	# (its board load — queued above — provides the table size), then run the director.
	if harness_mode or _tutorial_mode:
		if not joining_client and pending_load.is_empty():
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
	_solo_ensure_playing_phase()
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
	# Maintainer policy (2026-07-19): every applied special rule surfaces in the battle log —
	# the controller collects the notes, this is the one printing point.
	if battle_log != null:
		for note in report.get("rule_notes", []):
			battle_log.log_event(BattleLog.Category.COMBAT, str(note), true)
	# Shaken idle (OPR p.10): the unit spends its activation idle and recovers — clear via the radial seam
	# (state + marker + MP broadcast) and skip movement narration / combat entirely. An AIRCRAFT's
	# mandatory straight move still happened (GF v3.5.1: it flies even Shaken and still recovers) — show
	# the flight, then the recovery.
	if bool(report.get("idle_shaken", false)):
		if bool(report.get("aircraft", false)) and not solo_controller.last_move_paths.is_empty():
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.MOVEMENT,
					"%s makes its mandatory %d\" flight (Aircraft)" % [unit.get_name(), int(solo_controller.last_move_budget_in)], true)
			await _solo_animate_move(solo_controller.last_move_paths)
		if unit.is_shaken and radial_menu_controller != null:
			radial_menu_controller.card_toggle_shaken(unit)
			_solo_mirror_shaken(unit)
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.GENERAL, "%s spends its activation idle — recovers from Shaken" % unit.get_name(), true)
		return unit
	var target: GameUnit = report.get("target")
	if battle_log != null and bool(report.get("aircraft", false)):
		# Aircraft narration (GF v3.5.1): the move is a straight strafing lane, never a ground walk —
		# logged even with no target left (the flight is mandatory).
		var strafe_label: String = ("(→ %s)" % target.get_name()) if target != null else "(no target in reach)"
		battle_log.log_event(BattleLog.Category.MOVEMENT, "%s flies %d\" in a straight line %s" % [
			unit.get_name(), int(solo_controller.last_move_budget_in), strafe_label], true)
	elif battle_log != null and target != null:
		# Narrate the TRUE move goal (field-test finding 1): an objective-seeking move used to print the enemy
		# unit's name ("rushes → Snipers") even though it was heading for a marker, masking whether the AI ever
		# contested the mission. When the tree routed toward an objective, say so; the enemy stays the combat
		# target for any shooting that follows.
		var goal_label: String = "an objective" if bool(report.get("to_objective", false)) else target.get_name()
		if int(report.get("action", 0)) == AiDecision.Action.HOLD:
			# A HOLD has no move goal — the arrow printed the TREE's target while the weapon overlay could
			# still retarget the volley ("holds (→ Battle Brothers)" then "fires at Destroyers", Windows
			# playtest bug 7). The shot line right after names the real target; narrate the hold plainly.
			battle_log.log_event(BattleLog.Category.MOVEMENT, "%s holds its position" % unit.get_name(), true)
		else:
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
		_solo_spend_once_kind(unit, ["speed"])   # NML-006: speed once-mods are spent by the executed move
	# Dangerous terrain (goal 003 P3 + Bug 23): every affected model — crossed OR activated in it —
	# rolls its TOUGH value in dice (GF v3.5.1 p.12); each 1 wounds the unit.
	var dangerous_models: int = int(report.get("dangerous_models", 0))
	var dangerous_dice: int = int(report.get("dangerous_dice", dangerous_models))
	var alive_before_dangerous: int = unit.get_alive_count()
	var wounds_before_dangerous: int = _solo_unit_wounds_now(unit)
	if dangerous_dice > 0:
		await _run_ai_dangerous(unit, dangerous_dice)
	if unit.is_destroyed():
		return unit
	# Wave 6 — Caster(X): resolve the activation's planned casts BEFORE the attack (v3.5.1: "at any
	# point before attacking"; the official solo procedure casts after moving). The tokens were spent
	# at plan time (the attempt's cost); here the 4+ cast die rolls on the real tray and the effect
	# lands (spell damage saves reuse the shooting save path — no Shielded, no Cover against spells).
	if not (report.get("casts", []) as Array).is_empty():
		await _solo_resolve_ai_casts(report)
	if unit.is_destroyed():
		return unit
	# Mend + Breath Attack (army-book, grill round 2 cut A): once per activation, BEFORE attacking —
	# same slot the Caster resolution uses ("at any point before attacking").
	await _solo_apply_mend(unit)
	await _solo_apply_breath_attack(unit)
	# Coverage wave: the Utility-Buff family + Mind Control + Piercing Tag share the same
	# once-per-activation before-attacking slot (data-driven via the primitive layer).
	await _solo_apply_utility_buffs(unit)
	await _solo_apply_mind_control(unit)
	_solo_apply_piercing_tag(unit)
	await _solo_apply_reckless_piercing(unit)
	await _solo_apply_storm_attack(unit)
	if unit.is_destroyed():
		return unit
	# NML-002 Strafing (official text: "Once per activation, when this model moves through enemy
	# units, pick one of them and attack it with this weapon as if it was shooting. This weapon may
	# only be used in this way."): the trigger fires on the EXECUTED trails — independent of the
	# normal shoot decision (the weapon is excluded from every regular volley).
	await _solo_apply_strafing(unit)
	await _solo_apply_crossing_attack(unit)
	var hnr_attacked: bool = bool(report.get("can_shoot", false)) \
		or int(report.get("action", 0)) == AiDecision.Action.CHARGE
	if bool(report.get("can_shoot", false)):
		await _run_ai_shooting(report)
	elif int(report.get("action", 0)) == AiDecision.Action.CHARGE:
		await _run_ai_melee(report)
	# Hit & Run (grill round 2 cut C; Shooter/Fighter halves 2026-07-19): after shooting or being in
	# melee — the once-per-round 3" step, EV-scored in the controller. The trigger says which half
	# qualifies (shoot vs charge).
	if hnr_attacked and not unit.is_destroyed() \
			and solo_controller.hit_and_run_move(unit, bool(report.get("can_shoot", false))):
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.MOVEMENT, "Hit & Run: %s steps up to 3\" after its attack" % unit.get_name(), true)
		if not bool(report.get("can_shoot", false)):
			await _solo_retreating_strike(unit)   # resolver wave A: the post-MELEE step may lash out
	# END-of-activation morale from DANGEROUS-terrain wounds (GF/AoF v3.5.1 p.10/p.12 — field-test finding
	# 7): tested only NOW, AFTER the unit has acted, so dangerous damage never stops it shooting. A CHARGE
	# resolves through the melee comparison instead ("units in melee don't take morale tests from wounds at
	# the end of an activation"), so it is excluded here. should_test only fires on a real casualty at ≤half.
	if dangerous_models > 0 and not unit.is_destroyed() \
			and int(report.get("action", 0)) != AiDecision.Action.CHARGE:
		await _solo_shooting_morale(unit, alive_before_dangerous, _solo_owner_label(unit), wounds_before_dangerous)
	return unit


# === Solo P2 — alternating activation + auto-game (goal 003 P2) ===

## OPR alternating activation: each time the HUMAN activates a unit (via the radial menu), the AI answers
## with exactly ONE activation (queued as a pending reply — re-entry-safe). The pump then runs the pure
## SoloController.alternation_next state machine, which also plays the OPR TAIL automatically: once the
## human side is exhausted the AI finishes its remaining activations on its own (maintainer field-test
## gap — F11 was needed before). Inert while no solo game is engaged (no Solo toggle and no F11 yet).
## Solo auto-start (maintainer 2026-07-22, chalk-trail finding): the first solo activation IS the
## game start — flip the formal GamePhase to PLAYING so every phase-gated feature (path-painting
## chalk from #131, movement limits, phase UI) behaves. Idempotent; has_method-guarded so the call
## is inert on checkouts that predate the phase gate.
func _solo_ensure_playing_phase() -> void:
	# Safety fill-up: the game is starting while the AI still has queued deployments (the human
	# began fighting mid-deployment) — the remainder deploys at once, logged, panel closed.
	if solo_controller != null and (solo_controller.deploy_pending() > 0 or solo_controller.deploy_scouts_pending() > 0):
		solo_controller.deploy_remaining()
		_solo_deploy_fsm["phase"] = "done"
		_solo_deploy_ui_hide()
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.GENERAL,
				"The battle begins — NACHTMAHR deploys its remaining units", true)
	if opr_army_manager != null and opr_army_manager.has_method("start_game") \
			and "game_phase" in opr_army_manager and int(opr_army_manager.game_phase) == 0:
		opr_army_manager.start_game()
		_solo_run_redeployment()


## Re-Deployment at the game-start transition (wave 7): the AI counter-deploys up to two
## carriers now that the human's arrangement is final; human carriers get a rules reminder.
func _solo_run_redeployment() -> void:
	if solo_controller == null:
		return
	for r in solo_controller.redeployment_pass():
		var rd := r as Dictionary
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.MOVEMENT,
				"Re-Deployment: %s is removed and deployed again (%.1f\" nearer a marker) — GF v3.5.1" % [
				(rd["unit"] as GameUnit).get_name(), float(rd["gain_in"])], true)
	if battle_log != null and opr_army_manager != null:
		var yours: PackedStringArray = []
		for u in opr_army_manager.get_game_units_for_player(solo_controller.human_slot):
			var gu := u as GameUnit
			if gu != null and gu.get_alive_count() > 0 and RulesRegistry.unit_rule_active(gu, "Re-Deployment") \
					and not (gu.has_method("is_attached") and gu.is_attached()):
				yours.append(gu.get_name())
		if not yours.is_empty():
			battle_log.log_event(BattleLog.Category.GENERAL,
				"Re-Deployment: you may remove up to two of yours and deploy them again now (%s)" % ", ".join(yours), false)


func _on_solo_human_activated(gu: GameUnit) -> void:
	_solo_ensure_playing_phase()
	if not _solo_alternation_ready(gu):
		return
	# ONE reply per unit per round (round 7, finding 5): the radial activation marker is a TOGGLE, so
	# un-marking and re-marking a unit (a mis-click fix, or re-marking after an attack) re-emitted
	# unit_activated and queued the AI a SECOND answer for the same activation — the alternation then ran
	# ahead of the human ("unrecognized activations"). The pump still runs so the state machine drains.
	if _solo_replied_ids.has(gu.get_instance_id()):
		await _solo_pump()
		return
	_solo_replied_ids[gu.get_instance_id()] = true
	# Resolver wave A — Reckless Piercing: YOUR unit's activation roll fires here (auto-opt-in with
	# its log line, the Unpredictable precedent: resolution-integrated, both sides automatic).
	await _solo_apply_reckless_piercing(gu)
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
	_show_dream_overlay()   # centred "NACHTMAHR dreams…" for the WHOLE AI compute phase (maintainer)
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
	_hide_dream_overlay()
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


## The centred "NACHTMAHR dreams…" overlay (maintainer: middle of the screen — a top banner is missed)
## with the animated idle spinner, shown for the whole AI compute phase so the wait is transparent. A
## dark rounded panel, the amber persona palette; never intercepts the mouse. Skipped in headless/batch.
func _show_dream_overlay() -> void:
	if is_instance_valid(_solo_dream_overlay) or _solo_batch:
		return
	var centre := CenterContainer.new()
	centre.name = "DreamOverlay"
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.82)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(26)
	sb.border_color = Color(1.0, 0.78, 0.30, 0.35)
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var spinner := DreamSpinner.new()
	spinner.custom_minimum_size = Vector2(44, 44)
	spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spinner)

	var label := Label.new()
	label.text = "NACHTMAHR dreams…"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.62))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	row.add_child(label)

	panel.add_child(row)
	centre.add_child(panel)
	$UI.add_child(centre)
	_solo_dream_overlay = centre
	# A gentle breathing fade so the panel doesn't sit flatly static during the awaited holds.
	var tw := centre.create_tween().set_loops()
	tw.tween_property(centre, "modulate:a", 0.72, 0.9).from(1.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(centre, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)


func _hide_dream_overlay() -> void:
	if is_instance_valid(_solo_dream_overlay):
		_solo_dream_overlay.queue_free()
	_solo_dream_overlay = null


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
	# Coverage wave — Second Wind (Inquisitorial Agent / Martial Prowess): before the round closes,
	# a carrier may buy a SECOND activation (once per game, 1/3-of-carriers cap per round).
	var sw := solo_controller.second_wind_candidate()
	if sw != null:
		var sw_rule := solo_controller.spend_second_wind(sw)
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.GENERAL,
				"%s: %s activates a SECOND time this round (once per game — fatigue cleared)" % [sw_rule, sw.get_name()], true)
		await _solo_pump()
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


## Push the difficulty presets onto the live controller (idempotent). Arena grades (set_both_ai) win;
## otherwise every AI-marked slot gets the Solo-panel grade (default veteran) — without a grade the position
## solver + every knob stays off, which is the naive baseline the live playtest exposed. This is the ONE
## application point: it runs at the end of _ensure_solo_controller, so a lazily-created or torn-down-and-
## recreated controller always ends up graded (xhigh review find: the earlier import/toggle-time sync hit a
## null controller, and this function's unconditional reset then wiped any grade that DID land — the
## difficulty selector was a silent no-op in play).
func _solo_apply_difficulty() -> void:
	if solo_controller == null:
		return
	# Wave 6: in native both-AI mode the DEFENDING AI auto-plans its cast interference (no dialogs);
	# in human-vs-AI the flag stays false and the human gets the resist prompt at resolution instead.
	solo_controller.auto_interference = _solo_both_ai
	solo_controller.difficulty_seed = _solo_arena_seed
	solo_controller.difficulty_by_slot = {}
	if not _solo_difficulty_grades.is_empty():
		for slot in _solo_difficulty_grades:
			var grade := str(_solo_difficulty_grades[slot])
			solo_controller.set_difficulty(int(slot), SoloDifficulty.for_grade(grade, _solo_arena_seed))
		return
	for pid in solo_ai_slots:   # interactive human-vs-AI: Solo-panel grade for every AI-marked army
		solo_controller.set_difficulty(int(pid), SoloDifficulty.for_grade(_solo_interactive_grade, _solo_arena_seed))


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
## `first_opener` is the ROUND-1 opener: the official rule (GF/AoF Advanced v3.5.1) hands round 1's first
## turn to whoever won the deployment roll-off, so the launcher performs SoloController.roll_off() before
## deploying and passes the winner here. The default 1 keeps legacy callers running (they behave as if P1
## won the roll-off).
func _solo_run_both_ai_game(first_opener: int = 1) -> void:
	if opr_army_manager == null or movement_range_controller == null:
		push_warning("[AI ARENA] not ready — import + deploy armies first")
		return
	_solo_both_ai = true
	_ensure_solo_controller()
	if solo_controller == null:
		return
	_solo_ai_busy = true
	_solo_game_finished = false
	var opener: int = first_opener if (first_opener == 1 or first_opener == 2) else 1
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
		if _solo_arena_trace:
			printerr("[ARENA] R%d act#%d side P%d …" % [opr_army_manager.current_round, guard, act])
		var unit: GameUnit = await _solo_activate_one_ai()
		_solo_flush_dev()
		if unit != null:
			last_side = act
			if _solo_arena_trace:
				printerr("[ARENA] R%d act#%d side P%d = %s done" % [
					opr_army_manager.current_round, guard, act, unit.get_name()])
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
			# The alternator degrades to AI-only arrivals here (the "human" slot is AI → no prompts).
			await _solo_alternate_ambush_arrivals(round_number)


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
	_solo_replied_ids.clear()   # a new round: every unit's activation owes the AI one fresh reply (finding 5)
	if ai_opens:
		# The AI opens this round with one activation; the pump's tail then drains an empty human side.
		await _solo_pump()
	# Otherwise the human opens — the pump waits for the human's own activation (the alternation resumes there).


## Objective control at round end (goal 003 P2, official rule): every marker with exactly ONE side's
## non-Shaken models within 3" is seized by (or stays with) that side; both sides near → contested/neutral;
## nobody near → the owner persists. Pure logic in SoloController.seize_objectives; owners write through the
## SAME seam as the manual radial pick (overlay + MP broadcast), which therefore stays a manual override.
## Base radii (metres) of a unit's alive models, aligned with alive_positions — the seize check measures
## from the BASE EDGE (bug 11: OPR measures from the closest point; a 25mm model with centre at 3.4" and
## edge at ~2.9" legally holds a marker).
func _solo_alive_radii(gu: GameUnit) -> Array:
	var out: Array = []
	for m in gu.get_alive_models():
		out.append(SoloController.model_base_radius_m(m as ModelInstance))
	return out


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
		# A unit that arrived from Ambush THIS round can neither seize nor contest (GF/AoF v3.5.1 p.13);
		# an Aircraft never can at all (GF v3.5.1 Aircraft, system-scoped via the mechanics maps).
		var ambush_locked: bool = int(gu.unit_properties.get("ambush_arrived_round", -1)) == round_no
		infos.append({"player": int(gu.unit_properties.get("player_id", 0)), "shaken": gu.is_shaken,
			"ambush_locked": ambush_locked, "aircraft": SoloController.is_aircraft(gu),
			"positions": solo_controller.alive_positions(gu),
			"radii": _solo_alive_radii(gu)})
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
	var human_slot: int = 2 if ai_slot == 1 else 1
	for i in range(objectives.size()):
		var o: int = terrain_overlay.get_objective_owner(i)
		if o == 0:
			neutral += 1
		elif o == ai_slot:
			ai_held += 1
		else:
			human_held += 1
	# In native both-AI mode there is no "you" — the summary names P1/P2 (with their army names) and
	# declares the ACTUAL winner (showcase finding: a both-AI log ended "you: 0 · AI: 1 · The AI wins").
	# Slot orientation: human_slot/ai_slot are the controller's two sides in either mode.
	# NACHTMAHR is the solo AI's persona (maintainer decision 2026-07-16) — the human-facing verdict
	# carries the name; the kill-screen line is the release identity ("Dark Souls for OPR").
	var side_a_label: String = _solo_player_label(human_slot) if _solo_both_ai else "you"
	var side_b_label: String = _solo_player_label(ai_slot) if _solo_both_ai else "NACHTMAHR"
	var win_a: String = "%s wins" % side_a_label if _solo_both_ai else "You win — NACHTMAHR yields."
	var win_b: String = "%s wins" % side_b_label if _solo_both_ai else "NACHTMAHR claims the field."
	var verdict: String
	if objectives.is_empty():
		# No markers on the table: fall back to surviving models (documented tie-break, not an OPR mission).
		var ai_alive := _solo_side_alive(ai_slot)
		var human_alive := _solo_total_alive() - ai_alive
		verdict = win_a if human_alive > ai_alive else (win_b if ai_alive > human_alive else "Draw")
	else:
		verdict = win_a if human_held > ai_held else (win_b if ai_held > human_held else "Draw")
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL, "=== GAME OVER — %d rounds played ===" % SOLO_GAME_ROUNDS, true)
		if not objectives.is_empty():
			battle_log.log_event(BattleLog.Category.GENERAL, "Objectives — %s: %d · %s: %d · neutral: %d" % [
				side_a_label, human_held, side_b_label, ai_held, neutral], true)
		battle_log.log_event(BattleLog.Category.GENERAL, verdict, true)
	var dlg := AcceptDialog.new()
	dlg.title = "Game over"
	var obj_block: String = ("Objectives held:\n  %s: %d\n  %s: %d\n  Neutral: %d\n\n" % [
		(side_a_label.capitalize() if not _solo_both_ai else side_a_label), human_held, side_b_label, ai_held, neutral]) \
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
		# Bound the per-model any-angle search (see MovementPlanner.fast_planner). The UNBOUNDED planner
		# floods ~1000 cells per blocked search over an O(V²) open list → interactive AI turns took MINUTES
		# on 2000pt boards (field report "dauert Ewigkeiten"). The bound is the ~11× headless win with a
		# negligible path change, so the INTERACTIVE game bounds it too (arena keeps _solo_batch control for
		# its byte-identical batch=0 mode; interactive = no arena grades → always bound).
		MovementPlanner.fast_planner = _solo_batch or _solo_difficulty_grades.is_empty()
		# One tight cap for arena AND interactive: the "route into Dangerous" bug was the planner's soft-cost
		# blindness (fixed algorithmically — path-integral costs + cost-aware relaxation), NOT the cap. A
		# valid guard measurement (same seed, env seam AFTER this reset) showed the cap dominates runtime:
		# 320→88s vs 2400→456s per arena game — a raised interactive cap would bring the "AI turns take
		# minutes" complaint right back. Detour-finding under the 320 cap is proven by the planner test.
		MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD
		# (difficulty is applied by the _solo_apply_difficulty() call at the end of this function — the ONE
		# application point, so a recreated controller can never lose its grades.)
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
		# NML-001: das Overlay bekommt die frei platzierten Shelf-Stücke als typed OBBs
		# (frame-gecacht — Stücke sind draggable, der Scan läuft max. 1x pro Frame).
		if terrain_overlay != null and "sandbox_shapes_provider" in terrain_overlay:
			terrain_overlay.sandbox_shapes_provider = _sandbox_terrain_shapes
		solo_controller.terrain_type_at = func(p: Vector3) -> int:
			return terrain_overlay.get_terrain_at_world_position(p) if terrain_overlay != null else int(TerrainRules.TerrainType.NONE)
		solo_controller.walls_provider = func() -> Array:
			var w: Array = terrain_overlay.get_wall_segments_world() \
				if terrain_overlay != null and terrain_overlay.has_method("get_wall_segments_world") else []
			# NML-005 step 5: free-placed shelf ruins contribute their two L outer walls to the
			# MOVEMENT channel (the AI may not slide through them; sight stays area-semantics).
			for n in get_tree().get_nodes_in_group("sandbox_terrain"):
				if n is SandboxTerrainProp and is_instance_valid(n):
					w.append_array((n as SandboxTerrainProp).wall_segments_world())
			return w
		solo_controller.objectives_provider = func() -> Array:
			return terrain_overlay.get_objectives() if terrain_overlay != null else []
		solo_controller.objective_owner_of = func(index: int) -> int:
			return terrain_overlay.get_objective_owner(index) if terrain_overlay != null else 0
		# Round awareness for the final-round objective urgency (AI plausibility wave 1): the controller
		# learns which round is the match's last; without a scored match length it never fires.
		solo_controller.round_provider = func() -> int:
			return int(opr_army_manager.current_round) if opr_army_manager != null else 0
		solo_controller.game_rounds = SOLO_GAME_ROUNDS
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
	# The AI's zone edge is chosen AFTER the roll-off (winner picks a side — GF v3.5.1 p.6);
	# _solo_deploy_begin_side builds the zone from the choice.
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
		# Deploy doctrine (maintainer + five-game study T1): FOREST and RUIN floors are LEGAL deploy spots —
		# cover placement is good play ("nicht falsch, in Deckung zu platzieren"), and blanket-blocking them
		# forced mid-zone open-ground deploys. Walls still block via near_wall; DANGEROUS (first move pays
		# tests) and solid CONTAINER stay blocked.
		var t: int = terrain_overlay.get_terrain_at_world_position(Vector3(p.x, 0.0, p.y))
		return t == terrain_overlay.TerrainType.DANGEROUS or t == terrain_overlay.TerrainType.CONTAINER
	var blocked_flying := func(p: Vector2) -> bool:
		if hits_prop.call(p) or near_wall.call(p):
			return true
		if terrain_overlay == null:
			return false
		var t: int = terrain_overlay.get_terrain_at_world_position(Vector3(p.x, 0.0, p.y))
		return t == terrain_overlay.TerrainType.CONTAINER or t == terrain_overlay.TerrainType.RUINS
	# Seeded for reproducibility (solo convention); the seed lands in the console + battle log.
	var seed_value: int = int(Time.get_unix_time_from_system()) % 100000
	# "Start Deployment" (maintainer flow 2026-07-23, GF v3.5.1 p.6 verbatim): roll-off → the WINNER
	# picks a long table edge and MUST deploy first → players alternate one unit each, every human
	# placement handed over by CLICK ("Einheit aufgestellt") — no drop guessing. "Keine Einheiten
	# mehr" lets the opponent deploy its rest. Then the SCOUT phase (same procedure, 12" band),
	# then the game starts with the roll-off winner taking round 1's first turn (p.7).
	if not _solo_deploy_fsm.is_empty() and str(_solo_deploy_fsm.get("phase", "")) != "done":
		return   # deployment already running — the panel drives it
	var ro := RandomNumberGenerator.new()
	ro.seed = seed_value + 7
	var you_roll := ro.randi_range(1, 6)
	var ai_roll := ro.randi_range(1, 6)
	while you_roll == ai_roll:
		you_roll = ro.randi_range(1, 6)
		ai_roll = ro.randi_range(1, 6)
	_solo_deploy_fsm = {"phase": "side", "winner_is_ai": ai_roll > you_roll, "human_turn": false,
		"human_out": false, "objectives": objectives, "blocked_normal": blocked_normal,
		"blocked_flying": blocked_flying, "seed": seed_value, "w": w, "d": d, "depth": depth,
		"outcome": []}
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL,
			"Deployment roll-off: you %d — NACHTMAHR %d. The winner picks a table edge and deploys first (GF v3.5.1) [seed %d]" % [
			you_roll, ai_roll, seed_value], false)
	if ai_roll > you_roll:
		# NACHTMAHR picks its edge (v1 heuristic: opposite the human's army tray — the natural
		# setup; objectives sit centre-line, so the edges are near-symmetric) and deploys first.
		var ai_neg_z := not _solo_human_tray_neg_z()
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.GENERAL,
				"NACHTMAHR wins %d:%d — it picks the %s edge and deploys first" % [
				ai_roll, you_roll, ("far" if ai_neg_z != _solo_human_tray_neg_z() else "near")], true)
		await _solo_deploy_begin_side(ai_neg_z)
	else:
		# YOU win: choose your edge — NACHTMAHR takes the opposite one.
		_solo_deploy_ui_show("Roll-off %d:%d — YOU win and deploy first.\nPick your table edge:" % [you_roll, ai_roll],
			"Keep tray side", func() -> void: _solo_deploy_begin_side(not _solo_human_tray_neg_z()),
			"Switch sides", func() -> void: _solo_deploy_begin_side(_solo_human_tray_neg_z()))
## The deployment hand-over panel (maintainer flow): ONE persistent bottom-centre panel with a
## status line and up to two buttons — every human placement is handed over by CLICK, never by
## drop guessing. Buttons dispatch through the fsm so the panel is rebuilt-free between states.
func _solo_deploy_ui_show(text: String, b1: String, cb1: Callable, b2: String = "", cb2: Callable = Callable()) -> void:
	if _solo_deploy_ui == null or not is_instance_valid(_solo_deploy_ui):
		_solo_deploy_ui = CanvasLayer.new()
		_solo_deploy_ui.layer = 85
		var panel := PanelContainer.new()
		panel.anchor_left = 0.5
		panel.anchor_right = 0.5
		panel.anchor_top = 1.0
		panel.anchor_bottom = 1.0
		panel.offset_bottom = -18.0
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_solo_deploy_ui.add_child(panel)
		var margin := MarginContainer.new()
		for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			margin.add_theme_constant_override(side, 12)
		panel.add_child(margin)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		margin.add_child(box)
		_solo_deploy_ui_label = Label.new()
		_solo_deploy_ui_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_solo_deploy_ui_label.add_theme_font_size_override("font_size", 15)
		box.add_child(_solo_deploy_ui_label)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_child(row)
		_solo_deploy_ui_btn1 = Button.new()
		_solo_deploy_ui_btn1.custom_minimum_size = Vector2(280, 38)
		_solo_deploy_ui_btn1.pressed.connect(func() -> void:
			var cb: Callable = _solo_deploy_fsm.get("cb1", Callable())
			if cb.is_valid():
				cb.call())
		row.add_child(_solo_deploy_ui_btn1)
		_solo_deploy_ui_btn2 = Button.new()
		_solo_deploy_ui_btn2.custom_minimum_size = Vector2(280, 38)
		_solo_deploy_ui_btn2.pressed.connect(func() -> void:
			var cb: Callable = _solo_deploy_fsm.get("cb2", Callable())
			if cb.is_valid():
				cb.call())
		row.add_child(_solo_deploy_ui_btn2)
		add_child(_solo_deploy_ui)
	_solo_deploy_ui_label.text = text
	_solo_deploy_ui_btn1.text = b1
	_solo_deploy_fsm["cb1"] = cb1
	_solo_deploy_ui_btn2.visible = not b2.is_empty()
	_solo_deploy_ui_btn2.text = b2
	_solo_deploy_fsm["cb2"] = cb2
	_solo_deploy_ui.visible = true


func _solo_deploy_ui_hide() -> void:
	if _solo_deploy_ui != null and is_instance_valid(_solo_deploy_ui):
		_solo_deploy_ui.visible = false


## The HUMAN's army tray side: true when it stands on the -Z half (the side pick's reference).
func _solo_human_tray_neg_z() -> bool:
	var hslot: int = solo_controller.human_slot if solo_controller != null else 1
	for n in get_tree().get_nodes_in_group("army_tray"):
		var t := n as Node3D
		if t != null and int(t.get_meta("player_id", 0)) == hslot:
			return t.global_position.z < 0.0
	return true


## Build the zones from the chosen AI edge, queue the AI army (main + scout queues), set the
## reserves aside on BOTH sides, and start the MAIN phase with the roll-off winner's placement.
func _solo_deploy_begin_side(ai_neg_z: bool) -> void:
	var w: float = float(_solo_deploy_fsm.get("w", 0.0))
	var d: float = float(_solo_deploy_fsm.get("d", 0.0))
	var depth: float = float(_solo_deploy_fsm.get("depth", 0.3048))
	var zmin: float = (-d / 2.0) if ai_neg_z else (d / 2.0 - depth)
	var zone := Rect2(Vector2(-w / 2.0, zmin), Vector2(w, depth))
	var queued: int = solo_controller.deploy_begin(zone, _solo_deploy_fsm.get("objectives", []),
		_solo_deploy_fsm.get("blocked_normal", Callable()), _solo_deploy_fsm.get("blocked_flying", Callable()),
		int(_solo_deploy_fsm.get("seed", 0)))
	print("[Solo/AI] deployment queued: %d AI unit(s) (%d scouts held for the scout phase)" % [
		queued, solo_controller.deploy_scouts_pending()])
	# Ambush reserves on BOTH sides (GF/AoF v3.5.1 p.13 "May be set aside before deployment") —
	# they stay VISIBLE on the trays (finding 1) and arrive via the round-2+ alternation.
	if not solo_controller.ambush_reserve.is_empty() and battle_log != null:
		var reserve_names: PackedStringArray = []
		for u in solo_controller.ambush_reserve:
			reserve_names.append((u as GameUnit).get_name())
		battle_log.log_event(BattleLog.Category.GENERAL,
			"AI Ambush reserve (stays on the tray until it arrives): %s" % ", ".join(reserve_names), true)
	var set_aside: Array = solo_controller.set_aside_human_ambush()
	if not set_aside.is_empty() and battle_log != null:
		var aside_names: PackedStringArray = []
		for u in set_aside:
			aside_names.append((u as GameUnit).get_name())
		battle_log.log_event(BattleLog.Category.GENERAL,
			"You hold %d Ambush unit(s) in reserve on your tray (%s) — placement alternates from round 2 (GF/AoF p.13)." % [
				set_aside.size(), ", ".join(aside_names)], false)
	# The player's SCOUT units are set aside for the scout phase (p.14: "May be set aside before
	# deployment. After all other units are deployed …") — named so he keeps them on the tray.
	var human_scouts: PackedStringArray = []
	for u in opr_army_manager.get_game_units_for_player(solo_controller.human_slot):
		var gu := u as GameUnit
		if gu != null and gu.get_alive_count() > 0 and SoloController.unit_has_scout(gu) \
				and not (gu.has_method("is_attached") and gu.is_attached()) and not SoloController.unit_in_reserve(gu):
			human_scouts.append(gu.get_name())
	if not human_scouts.is_empty() and battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL,
			"Scout phase later: keep %s on the tray — scouts deploy AFTER all other units (GF v3.5.1)" % ", ".join(human_scouts), false)
	_solo_deploy_fsm["human_scouts"] = human_scouts
	_solo_deploy_fsm["phase"] = "main"
	_solo_deploy_fsm["human_out"] = false
	_solo_flush_dev()
	if bool(_solo_deploy_fsm.get("winner_is_ai", false)):
		await _solo_deploy_ai_turn()
	else:
		_solo_deploy_show_human_turn()


## The human's MAIN/SCOUT-phase turn panel: place ONE unit, then hand over by click.
func _solo_deploy_show_human_turn() -> void:
	_solo_deploy_fsm["human_turn"] = true
	var phase := str(_solo_deploy_fsm.get("phase", "main"))
	var ai_left: int = solo_controller.deploy_pending() if phase == "main" else solo_controller.deploy_scouts_pending()
	var what := "one unit" if phase == "main" else "one SCOUT unit (up to 12\" ahead of your zone)"
	if ai_left > 0:
		_solo_deploy_ui_show("Your turn: place %s on your side, then hand over.\n(NACHTMAHR has %d left.)" % [what, ai_left],
			"✔ Unit placed — NACHTMAHR's turn", func() -> void: _solo_deploy_human_done_one(),
			"No units left — NACHTMAHR deploys the rest", func() -> void: _solo_deploy_human_out())
	else:
		_solo_deploy_ui_show("NACHTMAHR is done — place your remaining %s.\nThen close the phase." % ("units" if phase == "main" else "scouts"),
			"✔ Done — close the phase", func() -> void: _solo_deploy_human_out())


func _solo_deploy_human_done_one() -> void:
	if not bool(_solo_deploy_fsm.get("human_turn", false)):
		return
	_solo_deploy_fsm["human_turn"] = false
	_solo_deploy_ai_turn()


func _solo_deploy_human_out() -> void:
	_solo_deploy_fsm["human_turn"] = false
	_solo_deploy_fsm["human_out"] = true
	_solo_deploy_ai_turn()


## One AI deployment turn of the CURRENT phase — or the phase's rest when the human is out.
func _solo_deploy_ai_turn() -> void:
	var phase := str(_solo_deploy_fsm.get("phase", "main"))
	if bool(_solo_deploy_fsm.get("human_out", false)):
		var n: int = solo_controller.deploy_remaining_main() if phase == "main" else solo_controller.deploy_remaining_scouts()
		if n > 0 and battle_log != null:
			battle_log.log_event(BattleLog.Category.GENERAL,
				"NACHTMAHR deploys its remaining %d unit(s)%s" % [n, (" (scouts)" if phase == "scout" else "")], true)
		_solo_deploy_phase_advance()
		return
	var unit: GameUnit = solo_controller.deploy_next_one() if phase == "main" else solo_controller.deploy_next_scout()
	if unit == null:
		# The AI is out for this phase — the human keeps placing until he closes the phase.
		_solo_deploy_show_human_turn()
		return
	_solo_focus_on_unit(unit)
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL, "NACHTMAHR deploys %s — your turn" % unit.get_name(), true)
	_solo_show_toast("NACHTMAHR deploys %s — your turn" % unit.get_name())
	_solo_deploy_show_human_turn()


## Phase advance: MAIN → SCOUT (same procedure, roll-off winner starts — "the player that
## activates next") → DONE (battle begins; the roll-off winner takes round 1's first turn, p.7).
func _solo_deploy_phase_advance() -> void:
	var phase := str(_solo_deploy_fsm.get("phase", "main"))
	if phase == "main":
		var ai_scouts: int = solo_controller.deploy_scouts_pending()
		var human_scouts: PackedStringArray = _solo_deploy_fsm.get("human_scouts", PackedStringArray())
		if ai_scouts > 0 or not human_scouts.is_empty():
			_solo_deploy_fsm["phase"] = "scout"
			_solo_deploy_fsm["human_out"] = human_scouts.is_empty()
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.GENERAL,
					"SCOUT phase: players alternate placing scouts up to 12\" ahead of their zone (GF v3.5.1)", false)
			if bool(_solo_deploy_fsm.get("winner_is_ai", false)) or human_scouts.is_empty():
				_solo_deploy_ai_turn()
			else:
				_solo_deploy_show_human_turn()
			return
	if phase != "done":
		_solo_deploy_fsm["phase"] = "done"
		_solo_deploy_ui_hide()
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.GENERAL, "Deployment complete — the battle begins", true)
		_solo_ensure_playing_phase()
		# GF v3.5.1 p.7: "the player that won the deployment roll-off takes the first turn."
		if bool(_solo_deploy_fsm.get("winner_is_ai", false)):
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.GENERAL,
					"NACHTMAHR won the roll-off — it takes the first turn", true)
			_solo_pending_replies = maxi(_solo_pending_replies, 1)
			_solo_pump()


var _sandbox_shapes_cache := {"frame": -1, "shapes": []}


## NML-001: live shapes of every free-placed shelf piece (SandboxTerrainProp = Regal-Ruine,
## TerrainGroupBase = Wald/Gefahrenfeld) as typed OBBs in world XZ metres. Frame-cached.
func _sandbox_terrain_shapes() -> Array:
	var f := Engine.get_process_frames()
	if int(_sandbox_shapes_cache["frame"]) == f:
		return _sandbox_shapes_cache["shapes"]
	var shapes: Array = []
	var in2m := 0.0254
	for n in get_tree().get_nodes_in_group("sandbox_terrain") + get_tree().get_nodes_in_group("terrain_group_base"):
		var node := n as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var fp: Vector2 = node.get("footprint_inches") if node.get("footprint_inches") != null else Vector2.ZERO
		if fp == Vector2.ZERO:
			continue
		var kind := int(node.get("prop_kind")) if node.get("prop_kind") != null else -1
		var ttype := TerrainRules.TerrainType.NONE
		if node.is_in_group("sandbox_terrain"):
			ttype = TerrainRules.TerrainType.RUINS   # Regal-Ruine: Cover + Area-LoS (Innenwände v1 unmodelliert)
		elif kind == ObjectManager.SandboxPropKind.FOREST:
			ttype = TerrainRules.TerrainType.FOREST
		elif kind == ObjectManager.SandboxPropKind.HAZARD_CLUSTER:
			ttype = TerrainRules.TerrainType.DANGEROUS
		if ttype == TerrainRules.TerrainType.NONE:
			continue
		shapes.append({"type": int(ttype), "c": Vector2(node.global_position.x, node.global_position.z),
			"he": fp * in2m * 0.5, "yaw": node.global_rotation.y})
	_sandbox_shapes_cache = {"frame": f, "shapes": shapes}
	return shapes


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
## NML-002 — Strafing resolution: if the unit (incl. joined heroes) carries a Strafing weapon and
## this activation's move passed over an enemy unit's bases, pick ONE crossed enemy (nearest) and
## fire ONLY the Strafing profiles at it, through the shared volley resolver. Once per activation.
func _solo_apply_strafing(unit: GameUnit) -> void:
	if unit == null or solo_controller == null or solo_controller.last_move_paths.is_empty():
		return
	var members: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		members = members + unit.get_attached_heroes()
	var shots: Array = []
	for m in members:
		var member := m as GameUnit
		if member == null or member.get_alive_count() == 0:
			continue
		var weapons: Array = []
		if member.source_type == "opr" and member.source_data is OPRApiClient.OPRUnit:
			weapons = (member.source_data as OPRApiClient.OPRUnit).weapons
		for prof in AiShooting.strafing_profiles(weapons):
			shots.append({"member": member, "quality": member.get_quality(),
				"alive": member.get_alive_count(), "max": member.models.size(),
				"reach": int(prof.get("range", 0)) if prof.has("range") else 0, "profile": prof})
	if shots.is_empty():
		return
	# Trails of THIS activation vs every enemy unit's bases — collect crossed enemies, take the nearest.
	var trails: Array = []
	for mp in solo_controller.last_move_paths:
		trails.append((mp as Dictionary).get("path", []))
	var crossed: Array = []
	for e in opr_army_manager.get_game_units_for_player(solo_controller.human_slot):
		var eu := e as GameUnit
		if eu == null or eu.get_alive_count() <= 0 or SoloController.unit_in_reserve(eu):
			continue
		if eu.has_method("is_attached") and eu.is_attached():
			continue
		if SoloController.trails_cross_unit_bases(trails, eu.models):
			crossed.append(eu)
	if crossed.is_empty():
		return
	crossed.sort_custom(func(a, b) -> bool:
		return MoveIntent.distance_inches(solo_controller.unit_centre(unit), solo_controller.unit_centre(a)) \
			< MoveIntent.distance_inches(solo_controller.unit_centre(unit), solo_controller.unit_centre(b)))
	var target := crossed[0] as GameUnit
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT,
			"Strafing: %s passes over %s — attacks it as if shooting (once per activation)" % [
			unit.get_name(), target.get_name()], true)
	await _solo_resolve_ai_volley(unit, target, shots, true)


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
			if RulesRegistry.unit_rule_active(member, "Shred") \
					or not RulesRegistry.unit_rules_of_primitive(member, "Shred").is_empty():
				prof["shred"] = true
			member_profiles.append(prof)
			# `reach` (target validity + per-model sighting) includes the unit's range bonus, so a Royal
			# Legion unit shoots targets up to +4" beyond the weapon's printed range.
			shots.append({"member": member, "quality": member.get_quality(),
				"alive": member.get_alive_count(), "max": member.models.size(),
				"reach": base_range + range_bonus, "profile": prof})
		# Wave 5 Sergeant (model-level): the member's FIRST firing profile carries the bearer's share.
		AiEv.stamp_sergeant(member_profiles, member)
		AiEv.stamp_conditional_ap(member_profiles, member)   # value Shatter/Tear/Melee Slayer/Disintegrate AP
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


## Resolve-first priority of a shot (GF v3.5.1 p.14): Takedown before Deadly before the rest. sort_custom
## is not guaranteed stable, but equal-priority shots (same tier) are interchangeable for the rule.
func _solo_shot_priority(shot: Dictionary) -> int:
	var p := shot.get("profile", {}) as Dictionary
	if bool(p.get("takedown", false)):
		return 2
	if int(p.get("deadly", 0)) > 0:
		return 1
	return 0


## Resolve one split-fire volley (all `shots` aimed at `target`) with real tray dice + the human's saves.
## Per-model shooting (GF v3.5.1 p.8 "Who Can Shoot"): each shot's attacks scale by the member's models
## that actually have range AND line of sight to the target — not by its whole living count. `moved` is
## the activation's move state (Indirect's -1 to hit fires only when shooting after moving — wave 5).
func _solo_resolve_ai_volley(attacker: GameUnit, target: GameUnit, shots: Array, moved: bool = false) -> void:
	# RESOLVE-FIRST ORDER (GF v3.5.1 p.14): "Takedown attacks must be resolved before other weapons" and
	# "Hits from Deadly must be resolved first." With no-carry-over + the single-model Takedown pick, the
	# order changes which models die, so sort each volley: Takedown, then Deadly, then the rest (stable).
	shots = shots.duplicate()
	# Resolver wave A — Takedown Shot: the once-per-game extra attack joins this volley as its own
	# single-model shot (own Quality; the priority sort pulls it to the front with Takedown).
	if not shots.is_empty():
		for tg in _solo_takedown_bonus_groups(attacker, false):
			var tgd := tg as Dictionary
			for tp in tgd.get("profiles", []):
				shots.append({"member": tgd["member"], "quality": int(tgd.get("quality", 2)),
					"alive": 1, "max": 1, "reach": 9999.0, "profile": tp})
	shots.sort_custom(func(a, b) -> bool:
		return _solo_shot_priority(a as Dictionary) > _solo_shot_priority(b as Dictionary))
	var alive_before: int = target.get_alive_count()
	var wounds_before: int = _solo_unit_wounds_now(target)
	var models_before: int = _solo_combined_alive(target)
	# Armor(X) (wave 5, army-book upgrade: "counts as having Defense X+") sets the working Defense,
	# then Shielded (+1 Defense, army-book rule) covers every hit; Cover (GF v3.5.1 p.11) is ignored
	# by Blast and by Indirect (wave 5: "ignores cover from sight obstructions").
	_solo_log_armor(target)
	var dist_in: float = MoveIntent.distance_inches(solo_controller.unit_centre(attacker), solo_controller.unit_centre(target))
	var base_defense: int = _solo_shielded_defense(target)
	if base_defense != _solo_armored_defense(target) and battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT, "%s is Shielded: +1 Defense (saves on %d+)" % [
			target.get_name(), base_defense], true)
	# Guarded / Versatile Defense's def-half ("+1 to defense rolls" when shot from over 9" away) folds
	# into the base Defense every shot of this volley saves at; Cover then stacks on top (floored 2+).
	var over9_rule := _solo_over9_defense_rule(target)
	if not over9_rule.is_empty() and dist_in > AiCombatMath.LONG_RANGE_IN:
		base_defense = AiCombatMath.guarded_defense(base_defense, true)
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "%s (%s): shot from over 9\" — +1 Defense (saves on %d+)" % [
				target.get_name(), over9_rule, base_defense], true)
	var covered_defense: int = _solo_cover_defense(target, base_defense)   # +1 Defense if majority in cover
	# Resolver wave A — vs-target Marks: the bearer's pick lands on THIS volley's target.
	_solo_apply_vs_marks(attacker, target, dist_in)
	# Coverage wave — Piercing Tag: friendly attackers spend the markers for +AP on this volley.
	# Resolver wave A — Reckless Piercing: the round-scoped AP stamps (buff on the attacker,
	# backfire on the target) ride the same profile-AP merge.
	var tag_ap := _solo_spend_piercing_tag(target) + _solo_reckless_ap(attacker, target)
	if tag_ap > 0:
		shots = shots.duplicate()
		for si in range(shots.size()):
			var sd := (shots[si] as Dictionary).duplicate()
			var sprof := (sd.get("profile", {}) as Dictionary).duplicate()
			sprof["ap"] = int(sprof.get("ap", 0)) + tag_ap
			sd["profile"] = sprof
			shots[si] = sd
	# ANNOUNCE: who shoots at whom — highlights + attack line + toast, held before any die is thrown.
	var announce := _solo_show_attack_announce(attacker, target, "fires at")
	_solo_show_fan_for_unit(attacker)   # Bug 17: the volley fan appears automatically — the shot is traceable
	await _solo_pace_hold(SoloController.Pace.ANNOUNCE)
	var regenable := 0
	var regen_proof := 0
	var total_hits := 0
	var total_caused := 0
	# Unpredictable (generic army-book rule — "when attacking": the SHOOTING leg; the wave-4 melee-only
	# Unpredictable Fighter lives in the melee path): ONE die per volley for the whole unit —
	# 1-3 → AP(+1), 4-6 → +1 to hit on every profile it fires (same arithmetic, same visible tray).
	var upr_ap := 0
	var upr_hit := 0
	var upr_name := _solo_unpredictable_rule(attacker, false)
	if not upr_name.is_empty():
		var upr_face: Array = await _solo_tray_roll(1, AiCombatMath.BEST_HIT_TARGET, "AI (%s)" % attacker.get_name())
		if not upr_face.is_empty():
			var upr_eff: Dictionary = AiCombatMath.unpredictable_fighter_effect(int(upr_face[0]))
			upr_ap = int(upr_eff["ap"])
			upr_hit = int(upr_eff["hit"])
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s: %s rolls %d → %s" % [
					upr_name, attacker.get_name(), int(upr_face[0]), ("AP(+1)" if upr_ap > 0 else "+1 to hit")], true)
	for s in shots:
		var shot := s as Dictionary
		var member := shot["member"] as GameUnit
		var profile := _solo_bridge_granted_flags(member, shot["profile"] as Dictionary)
		# Reliable (GF v3.5.1) sets the Quality (2+); the to-hit roll modifiers (Stealth / Artillery /
		# Evasive, and Indirect's moved-shooting -1 — wave 5) then apply on top ("Reliable only changes
		# the Quality value", p.14).
		var mod_info: Dictionary = _solo_hit_mod_info(member, target, dist_in, false)
		if moved and bool(profile.get("indirect", false)) \
				and not bool(RulesRegistry.best_primitive_param(member, "Indirect", "no_moved_penalty", false)):
			# Quick Readjustment (coverage wave): the bearer ignores the Indirect moved-penalty.
			var indirect_mod: int = AiCombatMath.indirect_hit_modifier(true,
				int(RulesRegistry.unit_param(member, "Indirect", "moved_hit_penalty", AiCombatMath.INDIRECT_MOVED_HIT_PENALTY)))
			mod_info = {"mod": int(mod_info.get("mod", 0)) + indirect_mod,
				"note": _solo_join_note(str(mod_info.get("note", "")), "Indirect moved %d" % indirect_mod)}
		var to_hit: int = AiCombatMath.modified_hit_target(
			AiCombatMath.reliable_quality(int(shot["quality"]), bool(profile.get("reliable", false))),
			int(mod_info.get("mod", 0)) + upr_hit)
		if upr_ap > 0:
			profile = profile.duplicate()
			profile["ap"] = int(profile.get("ap", 0)) + upr_ap   # Unpredictable AP(+1) leg (never mutate source)
		# Versatile Attack (army-book): over 9" apply the EV-better of +1 to hit or AP(+1) for this volley
		# — the SAME chooser AiEv.profile_ev uses, so the AI's plan and the real dice pick the same mode.
		# Shooting facet only (the melee/charge >9" facet needs the pre-charge distance — tracked follow-up).
		if bool(profile.get("versatile_attack", false)) and dist_in > AiCombatMath.LONG_RANGE_IN:
			var vm: Dictionary = AiEv.versatile_best_mode(to_hit, base_defense, int(profile.get("ap", 0)), bool(profile.get("bane", false)))
			to_hit = AiCombatMath.modified_hit_target(to_hit, int(vm.get("hit_mod", 0)))
			if int(vm.get("ap", 0)) > 0:
				profile = profile.duplicate()
				profile["ap"] = int(profile.get("ap", 0)) + int(vm.get("ap", 0))
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "Versatile Attack: %s at long range" % [
					"AP(+1)" if int(vm.get("ap", 0)) > 0 else "+1 to hit"], true)
		_solo_log_hit_mod(mod_info, target, to_hit)
		# Indirect (wave 5) targets as if in line of sight — its per-model sighting is range-only.
		# The Aircraft target penalty (-12") and Ranged Shrouding (-6" min 6") shorten the reach here too.
		var sighted: int = _solo_sighted_count(member, target,
			int(SoloController.effective_shoot_reach_in(float(shot["reach"]), target)),
			bool(profile.get("indirect", false)))
		var attacks: int = SoloController.effective_attacks(int(profile.get("attacks", 0)), sighted, int(shot["max"]))
		if attacks <= 0:
			continue
		var shooter_name: String = member.get_name()
		var faces: Array = await _solo_tray_roll(attacks, to_hit, "AI (%s)" % shooter_name)
		if bool(profile.get("limited", false)):
			solo_controller.mark_limited_used(member, profile)   # once per game — spent on the roll (wave 5)
		await _solo_hazardous_self_wounds(attacker, profile, faces)   # resolver wave A: natural 1s wound the firer
		var hits: int = await _solo_hits(faces, to_hit, profile, dist_in, target, false, "AI (%s)" % attacker.get_name())
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
		var save_def: int = base_defense if (int(profile.get("blast", 0)) > 1 or bool(profile.get("indirect", false)) or bool(profile.get("ignores_cover", false))) else covered_defense
		var is_deadly: bool = int(profile.get("deadly", 0)) > 0
		var is_takedown: bool = bool(profile.get("takedown", false))
		# Deadly/Takedown weapons return RAW unsaved (apply_deadly=false) so their wounds land per-model
		# instead of the pooled defender-optimal removal — Deadly's "no carry-over" and Takedown's
		# "unit of [1]" are both per-model rules.
		var w: int = await _solo_resolve_saves(member, target, str(profile.get("name", "?")), faces, hits, save_def, profile, not _solo_is_ai_unit(target), false, not (is_deadly or is_takedown), false, dist_in)
		total_caused += w
		if is_takedown and w > 0:
			# Takedown (GF v3.5.1 p.14, Bug 25): resolved as a unit of [1] against ONE chosen model.
			# Resolver wave A: a Takedown weapon's Deadly multiplies on that model (p.14) — this also
			# fixes book weapons carrying both (the multiply was silently dropped before).
			var td_w: int = w * maxi(int(profile.get("deadly", 0)), 1)
			if _solo_ignores_regen(member, profile):
				await _solo_land_takedown_wounds(member, target, str(profile.get("name", "?")), 0, td_w)
			else:
				await _solo_land_takedown_wounds(member, target, str(profile.get("name", "?")), td_w, 0)
		elif is_deadly and w > 0:
			# Deadly (GF v3.5.1 p.14): each unsaved wound ×X on one model, no carry-over.
			if _solo_ignores_regen(member, profile):
				await _solo_land_deadly_wounds(target, str(profile.get("name", "?")), int(profile.get("deadly", 0)), 0, w)
			else:
				await _solo_land_deadly_wounds(target, str(profile.get("name", "?")), int(profile.get("deadly", 0)), w, 0)
		elif _solo_ignores_regen(member, profile):
			regen_proof += w
		else:
			regenable += w
	var landed: int = await _solo_land_wounds(target, regenable, regen_proof)
	if _solo_combined_alive(target) <= 0:
		_solo_growth_on_kill(attacker)   # Defensive Frenzy: volley kill credit
		_solo_vengeance_on_destroyed(target, attacker)
	_solo_clear_announce(announce)
	_solo_clear_auto_fan()   # Bug 17: the volley is resolved — the fan leaves with the announce
	# OUTCOME: one readable summary line, held on screen (toast + battle log).
	await _solo_show_outcome("%s: %d hit%s → %d wound%s land — %s loses %d model%s" % [
		target.get_name(), total_hits, ("" if total_hits == 1 else "s"),
		landed, ("" if landed == 1 else "s"), target.get_name(),
		models_before - _solo_combined_alive(target), ("" if models_before - _solo_combined_alive(target) == 1 else "s")])
	if landed > 0:
		await _solo_shooting_morale(target, alive_before, _solo_owner_label(target), wounds_before)
	_solo_consume_once_mods(attacker, target, false)   # F4: once-mods spent by this exchange


# === Wave 6 — Caster(X) cast resolution (official Solo v3.5.0 procedure; real tray dice) ===

## Resolve every cast the controller planned for this activation: announce → (human resist prompt) →
## the 4+ cast roll on the real tray → the effect. Damage spells reuse the shooting SAVE path with two
## rule-mandated differences: Shielded does NOT apply ("+1 to defense rolls against hits that are not
## from spells") and Cover does NOT apply (it is granted "against shooting"); there is NO to-hit roll
## (spells deal fixed hits). Buff/debuff/utility spells announce their effect (the live spell text) and
## stay manually applied — the honest wave-6 boundary, mirrored in docs/SOLO_AI_RULES_COVERAGE.md.
func _solo_resolve_ai_casts(report: Dictionary) -> void:
	if dice_roller_control == null or solo_controller == null:
		return
	for c in report.get("casts", []):
		var cast := c as Dictionary
		var caster: GameUnit = cast.get("caster")
		if caster == null or caster.get_alive_count() == 0:
			continue   # the caster died to a Dangerous-terrain test before the cast resolved
		await _solo_resolve_one_cast(cast)
	_solo_refresh_caster_markers()


## One cast: the announced spell, the boost/interference-adjusted target number, one real tray die.
func _solo_resolve_one_cast(cast: Dictionary) -> void:
	var caster: GameUnit = cast["caster"]
	var caster_unit: GameUnit = cast.get("caster_unit", caster)
	var entry: Dictionary = cast.get("spell", {})
	var effect: Dictionary = entry.get("effect", {})
	var spell_name := str(cast.get("name", "?"))
	var targets: Array = []
	for t in cast.get("targets", []):
		var tu := t as GameUnit
		if tu != null and not tu.is_destroyed():
			targets.append(tu)
	if targets.is_empty():
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT,
				"%s's %s fizzles — no target remains" % [caster.get_name(), spell_name], true)
		return
	var boost := int(cast.get("boost", 0))
	var interference := int(cast.get("interference", 0))
	var base_target := int(cast.get("base_target", AiSpell.CAST_BASE_TARGET))
	# NML-006 casting_mod: active tokens like "-3 to casting rolls" (Burn the Heretic) shift the
	# caster's roll target — applied BEFORE announce/boost/interference so every preview shows the
	# true number; [2,6] clamp (a 1 always fails, a 6 always casts). Spent right after the cast die.
	var casting_mod := 0
	var cast_mod_notes: PackedStringArray = []
	for crd in AiSpell.mods_for(_solo_mods_of_chain(caster), "casting", false):
		casting_mod += int((crd as Dictionary).get("casting_mod", 0))
		cast_mod_notes.append("%s %+d" % [str((crd as Dictionary).get("spell", "")),
			int((crd as Dictionary).get("casting_mod", 0))])
	# Coverage wave — Spell Conduit: a friendly non-Shaken conduit within its range gives +1 to
	# casting rolls (the position-proxy half is a registry-noted approximation).
	if solo_controller != null and opr_army_manager != null:
		var cpid := int(caster.unit_properties.get("player_id", 0))
		for u in opr_army_manager.get_game_units_for_player(cpid):
			var cu := u as GameUnit
			if cu == null or cu == caster or cu.get_alive_count() == 0 or cu.is_shaken or SoloController.unit_in_reserve(cu):
				continue
			var found := false
			for e in RulesRegistry.unit_rules_of_primitive(cu, "Spell Conduit"):
				var sp: Dictionary = (e as Dictionary).get("params", {})
				var d := MoveIntent.distance_inches(solo_controller.unit_centre(cu), solo_controller.unit_centre(caster))
				if d <= float(sp.get("range_in", 12.0)):
					casting_mod += int(sp.get("casting_mod", 1))
					cast_mod_notes.append("%s %+d" % [str((e as Dictionary)["name"]), int(sp.get("casting_mod", 1))])
					found = true
					break
			if found:
				break
	if casting_mod != 0:
		base_target = clampi(base_target - casting_mod, 2, 6)
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "%+d to casting rolls (%s) — %s's base target is %d+" % [
				casting_mod, ", ".join(cast_mod_notes), caster.get_name(), base_target], true)
	# ANNOUNCE (announce → resist? → roll → saves → effect): attribution highlights + one log line
	# stating cost, boost/interference and the needed roll BEFORE any die is thrown.
	var announce := _solo_show_attack_announce(caster_unit, targets[0], "casts %s at" % spell_name)
	if battle_log != null:
		var token_note := "%d token%s" % [int(cast.get("threshold", 0)), ("" if int(cast.get("threshold", 0)) == 1 else "s")]
		if boost > 0:
			token_note += ", +%d boost" % boost
		if interference > 0:
			token_note += ", -%d interference" % interference
		battle_log.log_event(BattleLog.Category.COMBAT, "%s casts %s at %s — needs %d+ (%s)" % [
			caster.get_name(), spell_name, _solo_cast_target_label(targets),
			AiSpell.cast_target(boost, interference, base_target), token_note], true)
	await _solo_pace_hold(SoloController.Pace.ANNOUNCE)
	# RESIST (v3.5.1: enemy models with tokens within 18" LoS may spend for -1 each): in a human-vs-AI
	# game the human is prompted; in native both-AI the controller already planned + spent this.
	if bool(cast.get("interference_open", false)) and not _solo_both_ai:
		interference += await _solo_prompt_interference(caster, caster_unit, spell_name,
			base_target, boost, _solo_cast_target_label(targets))
	var target_num := AiSpell.cast_target(boost, interference, base_target)
	# THE CAST ROLL — one visible die on the real tray (no hidden RNG).
	var roll_owner := str(cast.get("owner_label", "AI (%s)" % caster.get_name()))
	var faces: Array = await _solo_tray_roll(1, target_num, roll_owner)
	var success: bool = not faces.is_empty() and DiceRules.is_success(int(faces[0]), target_num, 0)
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT, "%s: cast roll %d vs %d+ — %s" % [
			spell_name, (int(faces[0]) if not faces.is_empty() else 0), target_num,
			("SUCCESS" if success else "FAILED")], true)
	_solo_spend_once_kind(caster, ["casting"])   # NML-006: the casting once-mod is spent by this roll
	if not success:
		_solo_clear_announce(announce)
		await _solo_show_outcome("%s fails to cast %s" % [caster.get_name(), spell_name])
		return
	if str(effect.get("kind", "")) == "damage":
		for tu in targets:
			await _solo_resolve_spell_damage(caster, caster_unit, spell_name, entry, tu)
	else:
		_solo_announce_spell_effect(caster, spell_name, effect, targets)
		_solo_place_spell_tokens(spell_name, targets, effect)
	_solo_clear_announce(announce)
	await _solo_show_outcome("%s resolves %s" % [caster.get_name(), spell_name])


## The damage-spell resolution against ONE target: fixed hits (no to-hit roll), the optional trigger
## roll for the on-6/on-1 facets ("Roll as many dice as hits …"), Blast fan-out, then the SHARED save
## machinery (_solo_save_batch: real tray saves, Bane re-rolls, Deadly, Shred) at the Armor-adjusted
## Defense — deliberately NOT Shielded-adjusted and NOT Cover-adjusted (spell hits, see the callers).
func _solo_resolve_spell_damage(caster: GameUnit, caster_unit: GameUnit, spell_name: String,
		entry: Dictionary, target: GameUnit) -> void:
	var effect: Dictionary = entry.get("effect", {})
	var facets: Dictionary = AiSpell.spell_facets(effect.get("weapon_rules", []))
	var hits := int(effect.get("hits", 0))
	if hits <= 0:
		return
	var alive_before: int = target.get_alive_count()
	var wounds_before: int = _solo_unit_wounds_now(target)
	var models_before: int = _solo_combined_alive(target)
	var hazardous: bool = _solo_spell_has_rule(effect, "Hazardous")
	# Trigger roll (the spell text's "Roll as many dice as hits to see if on-6/on-1 effects trigger"):
	# one die per printed hit; 6s feed Surge (+1 hit each) / Crack/Destructive (AP-upgraded sub-batch),
	# 1s feed Hazardous (the caster's unit takes one wound each).
	var trigger_sixes := 0
	var trigger_ones := 0
	if bool(facets.get("surge", false)) or int(facets.get("on6_ap", 0)) > 0 or hazardous:
		var trigger_faces: Array = await _solo_tray_roll(hits, AiCombatMath.UNMODIFIED_SIX, "AI (%s)" % caster.get_name())
		trigger_sixes = AiCombatMath.unmodified_sixes(trigger_faces)
		for f in trigger_faces:
			if int(f) == AiCombatMath.UNMODIFIED_ONE:
				trigger_ones += 1
	var total_hits := hits
	if bool(facets.get("surge", false)):
		total_hits += trigger_sixes
	# Blast ×min(X, models) — a "model"-targeted spell resolves as a unit of 1 (no fan-out).
	var fanout_models: int = 1 if str((entry.get("target", {}) as Dictionary).get("kind", "")) == "model" else _solo_combined_alive(target)
	total_hits = AiCombatMath.blast_hits(total_hits, int(facets.get("blast", 0)), maxi(fanout_models, 1))
	# Saves at the Armor-adjusted Defense — Shielded and Cover are EXCLUDED against spells.
	_solo_log_armor(target)
	var base_defense: int = _solo_armored_defense(target)
	var def_ctx := {"defense": base_defense, "tough": _solo_unit_tough(target)}
	var ap := AiSpell.effective_ap(facets, def_ctx)
	var bane := bool(facets.get("bane", false))
	var profile := {"name": spell_name, "ap": ap, "deadly": int(facets.get("deadly", 0)),
		"shred": bool(facets.get("shred", false)), "rules": effect.get("weapon_rules", [])}
	var human_defends: bool = not _solo_is_ai_unit(target)
	var upgraded: int = mini(trigger_sixes if int(facets.get("on6_ap", 0)) > 0 else 0, total_hits)
	var caused := 0
	if upgraded > 0:
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "%s: %d hit%s on a 6 → AP(+%d)" % [
				spell_name, upgraded, ("" if upgraded == 1 else "s"), int(facets.get("on6_ap", 0))], true)
		caused += await _solo_save_batch(caster, target, "%s (on-6)" % spell_name, upgraded,
			base_defense, ap + int(facets.get("on6_ap", 0)), profile, human_defends, bane)
	if total_hits - upgraded > 0:
		caused += await _solo_save_batch(caster, target, spell_name, total_hits - upgraded,
			base_defense, ap, profile, human_defends, bane)
	# Regeneration: only Bane / Lacerate / Disintegrate wounds bypass it (the facets carry this).
	var landed: int
	if bane or bool(facets.get("ignores_regen", false)):
		landed = await _solo_land_wounds(target, 0, caused)
	else:
		# from_spell=true: a unit with Resistance ignores THESE (spell) wounds on 2+, not 6+.
		landed = await _solo_land_wounds(target, caused, 0, true)
	await _solo_show_outcome("%s: %d hit%s → %d wound%s land — %s loses %d model%s" % [
		spell_name, total_hits, ("" if total_hits == 1 else "s"), landed, ("" if landed == 1 else "s"),
		target.get_name(), models_before - _solo_combined_alive(target),
		("" if models_before - _solo_combined_alive(target) == 1 else "s")])
	# Hazardous (army-book rule: "this model's unit takes one wound on unmodified rolls of 1").
	if trigger_ones > 0 and hazardous:
		_solo_apply_wounds(caster_unit, trigger_ones)
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "%s: %d trigger roll%s of 1 — %s takes %d wound%s" % [
				spell_name, trigger_ones, ("" if trigger_ones == 1 else "s"), caster_unit.get_name(),
				trigger_ones, ("" if trigger_ones == 1 else "s")], true)
	if landed > 0 and not target.is_destroyed():
		await _solo_shooting_morale(target, alive_before, _solo_owner_label(target), wounds_before)


## Whether a spell's weapon-rule token list carries `rule_name` (facet gate for the dice path).
func _solo_spell_has_rule(effect: Dictionary, rule_name: String) -> bool:
	for r in effect.get("weapon_rules", []):
		if str(r).strip_edges().begins_with(rule_name):
			return true
	return false


## Announce a successful buff/debuff/utility spell: the effect stays MANUALLY applied (exactly like
## every other unautomated rule — the once-per-session log convention), but the human sees WHAT the
## spell does: the live army-book spell text (runtime data from the import — never committed).
func _solo_announce_spell_effect(caster: GameUnit, spell_name: String, effect: Dictionary, targets: Array) -> void:
	if battle_log == null:
		return
	var names: PackedStringArray = []
	for t in targets:
		names.append((t as GameUnit).get_name())
	var effect_text := ""
	if opr_army_manager != null and opr_army_manager.has_method("get_spells_for_unit"):
		for sp in opr_army_manager.get_spells_for_unit(caster):
			if str((sp as Dictionary).get("name", "")) == spell_name:
				effect_text = str((sp as Dictionary).get("effect", ""))
				break
	if effect_text.is_empty():
		var grant := str(effect.get("grants_rule", ""))
		effect_text = ("grants %s (once)" % grant) if not grant.is_empty() else "see the faction's spell list"
	battle_log.log_event(BattleLog.Category.COMBAT, "%s takes effect on %s: %s" % [
		spell_name, ", ".join(names), effect_text], true)
	# When the spell has a derived library token, _solo_place_spell_tokens applies it right after
	# this announce — only spells WITHOUT a token still need the manual-application note.
	var has_token: bool = radial_menu_controller != null \
			and radial_menu_controller.token_library != null \
			and radial_menu_controller.token_library.has(spell_name)
	if not has_token:
		battle_log.log_event(BattleLog.Category.GENERAL,
			"Note: spell effects other than damage are not auto-applied — apply \"%s\" manually" % spell_name, true)


## Wave 6b — a successful lingering-effect cast PLACES the derived library token on every target
## (green buff / red debuff). NML-206 (maintainer live test: a successful buff produced NO token
## and NO effect): the token library only knows spells derived at army import — a missing entry
## is now DEFINED at runtime (green buff / red debuff, effect summary as tooltip), and the
## MECHANICAL record is never gated on the visual token again: the dice truth always lands.
## Auto-removed at the end of the round (GF/AoF v3.5.1), so the board never shows stale buffs.
func _solo_place_spell_tokens(spell_name: String, targets: Array, effect: Dictionary = {}) -> void:
	if radial_menu_controller == null:
		return
	if radial_menu_controller.token_library != null and not radial_menu_controller.token_library.has(spell_name):
		var kind := str(effect.get("kind", "buff"))
		var col := Color(0.35, 0.8, 0.35) if kind != "debuff" else Color(0.85, 0.3, 0.25)
		var summary := str(effect.get("grants_rule", ""))
		if summary.is_empty():
			summary = "spell effect — see battle log"
		radial_menu_controller.token_library.define(spell_name, col, false, summary)
	for t in targets:
		var tu := t as GameUnit
		if tu == null or tu.is_destroyed():
			continue
		if radial_menu_controller.apply_library_token(tu, spell_name):
			_solo_spell_tokens_active.append({"unit": tu, "token": spell_name})
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.GENERAL,
					"\"%s\" token placed on %s (expires at the end of the round)" % [spell_name, tu.get_name()], true)
		_solo_record_spell_mod(tu, spell_name, effect)


## MECHANICAL token effect (maintainer 2026-07-22: buff/debuff tokens were decoration — the real
## dice never read them). A placed token with modifier data now registers hit_mod/def_mod on the
## unit; the hit path (_solo_hit_mod_info) and the defense seam (_solo_shielded_defense) read it,
## each application logs (rules-must-log). Cleared with the tokens at round end.
func _solo_record_spell_mod(tu: GameUnit, spell_name: String, effect: Dictionary) -> void:
	var modifier: Dictionary = effect.get("modifier", {})
	var grants := str(effect.get("grants_rule", ""))
	if modifier.is_empty() and grants.is_empty():
		return
	var rec := {"spell": spell_name, "hit_mod": int(modifier.get("hit_mod", 0)),
		"def_mod": int(modifier.get("def_mod", 0)),
		"casting_mod": int(modifier.get("casting_mod", 0)),
		"morale_mod": int(modifier.get("morale_mod", 0)),
		"range_in": int(modifier.get("range_in", 0)),
		"advance_in": int(modifier.get("advance_in", 0)),
		"rush_in": int(modifier.get("rush_in", 0)),
		"grants_rule": grants, "scope": str(effect.get("scope", "")),
		"beneficiary": str(effect.get("beneficiary", "")), "duration": str(effect.get("duration", "round"))}
	if rec["hit_mod"] == 0 and rec["def_mod"] == 0 and rec["casting_mod"] == 0 \
			and rec["morale_mod"] == 0 and rec["range_in"] == 0 and rec["advance_in"] == 0 \
			and rec["rush_in"] == 0 and grants.is_empty():
		return
	var key := tu.get_instance_id()
	if not _solo_spell_mods.has(key):
		_solo_spell_mods[key] = []
	(_solo_spell_mods[key] as Array).append(rec)
	# NML-006 side effects: a granted rule goes onto the LIVE special_rules overlay, speed/range
	# deltas onto the props stamps — every existing engine read then honours them.
	_solo_apply_grant(tu, rec)
	_solo_refresh_spell_stamps(tu)
	if battle_log != null:
		var hd: PackedStringArray = []
		if rec["hit_mod"] != 0:
			hd.append("%+d to hit" % rec["hit_mod"])
		if rec["def_mod"] != 0:
			hd.append("%+d to defense" % rec["def_mod"])
		var parts: PackedStringArray = []
		if not hd.is_empty():
			parts.append(("attackers get %s against it" % ", ".join(hd)) \
				if str(rec["beneficiary"]) == "attackers" else ", ".join(hd))
		if rec["casting_mod"] != 0:
			parts.append("%+d to casting rolls" % rec["casting_mod"])
		if rec["morale_mod"] != 0:
			parts.append("%+d to morale test rolls" % rec["morale_mod"])
		if rec["range_in"] != 0:
			parts.append("%+d\" shooting range" % rec["range_in"])
		if rec["advance_in"] != 0 or rec["rush_in"] != 0:
			parts.append("%+d\" advance / %+d\" rush" % [rec["advance_in"], rec["rush_in"]])
		if not grants.is_empty():
			parts.append("grants %s" % grants)
		battle_log.log_event(BattleLog.Category.COMBAT, "%s on %s is ACTIVE: %s%s — %s" % [
			spell_name, tu.get_name(), ", ".join(parts),
			(" (%s only)" % rec["scope"]) if not str(rec["scope"]).is_empty() else "",
			("applies ONCE" if str(rec["duration"]) == "once" else "until end of round")], true)


## NML-006 — the live joined-unit chain of a token bearer (bearer + host + joined heroes, deduped):
## a spell on any part of a joined unit affects the WHOLE unit (p.14 join semantics), so grant
## overlays and props stamps land on every member GameUnit of the chain.
func _solo_joined_chain(tu: GameUnit) -> Array:
	var out: Array = []
	if tu == null:
		return out
	var cands: Array = [tu]
	if tu.has_method("get_attached_to"):
		cands.append(tu.get_attached_to())
	if tu.has_method("get_attached_heroes"):
		cands.append_array(tu.get_attached_heroes())
	for c in cands:
		var u := c as GameUnit
		if u != null and is_instance_valid(u) and not out.has(u):
			out.append(u)
	return out


## NML-006 — grants_rule side effect: the granted rule is appended to the LIVE special_rules of the
## whole joined chain (suffix-marked, see SOLO_SPELL_GRANT_SUFFIX), so every existing rule check —
## unit_rule_active (registry-gated), _solo_striker_has_bane's shooting/melee variants, the
## Furious/Counter/Fearless reads and the move-band name fallbacks (Swift, Rapid Rush, ...) — honours
## the grant with ZERO per-rule wiring. has_special_rule's begins_with matching sees through the
## suffix; base-name scans strip it at the "(". Only units that did NOT already carry the rule are
## recorded in rec.granted_to, so revoking never strips a printed rule.
const SOLO_SPELL_GRANT_SUFFIX := " (spell)"
func _solo_apply_grant(tu: GameUnit, rec: Dictionary) -> void:
	var rule := str(rec.get("grants_rule", ""))
	if rule.is_empty():
		return
	var granted_to: Array = []
	for u in _solo_joined_chain(tu):
		var gu := u as GameUnit
		if gu.has_special_rule(RulesRegistry.base_rule_name(rule)):
			continue
		var rules: Array = gu.unit_properties.get("special_rules", [])
		rules.append(rule + SOLO_SPELL_GRANT_SUFFIX)
		gu.unit_properties["special_rules"] = rules
		granted_to.append(gu.get_instance_id())
	rec["granted_to"] = granted_to


## NML-006 — undo one record's rule grant (consumption/expiry): removes the exact suffix-marked
## string from exactly the units it was added to.
func _solo_revoke_grant(rec: Dictionary) -> void:
	var rule := str(rec.get("grants_rule", ""))
	if rule.is_empty():
		return
	for id in rec.get("granted_to", []):
		var gu := instance_from_id(int(id)) as GameUnit
		if gu != null and is_instance_valid(gu):
			(gu.unit_properties.get("special_rules", []) as Array).erase(rule + SOLO_SPELL_GRANT_SUFFIX)


## NML-006 — speed/range props stamps: unit_properties carries the NET active spell movement/range
## deltas ("spell_move_mod": {advance, rush} and "spell_range_mod": int) so the PURE readers —
## move_bands_for_props (AI bands AND the human's move rings/charge reach) and shooting_range_bonus
## (every volley/fan/plan site) — apply them with no new plumbing. The nets are computed over the
## UNION of the joined chain's records (a token on the hero speeds the whole unit and vice versa)
## and restamped on every member; recomputed on record, consumption and expiry, keys erased at zero.
func _solo_refresh_spell_stamps(tu: GameUnit) -> void:
	var chain := _solo_joined_chain(tu)
	var records: Array = []
	for u in chain:
		records.append_array(_solo_spell_mods.get((u as GameUnit).get_instance_id(), []))
	var adv := 0
	var rush := 0
	var rng := 0
	for rd in AiSpell.mods_for(records, "speed", false):
		adv += int((rd as Dictionary).get("advance_in", 0))
		rush += int((rd as Dictionary).get("rush_in", 0))
	for rd in AiSpell.mods_for(records, "range", false):
		rng += int((rd as Dictionary).get("range_in", 0))
	for u in chain:
		var gu := u as GameUnit
		if adv == 0 and rush == 0:
			gu.unit_properties.erase("spell_move_mod")
		else:
			gu.unit_properties["spell_move_mod"] = {"advance": adv, "rush": rush}
		if rng == 0:
			gu.unit_properties.erase("spell_range_mod")
		else:
			gu.unit_properties["spell_range_mod"] = rng


## Active spell hit-modifier for a striking member (its own tokens + its host's — a joined hero
## shares the unit's buffs). scope-filtered; "charging"-scoped spells are skipped here (v1: the
## composer does not know the charge state — noted limitation).
func _solo_spell_hit_mod(member: GameUnit, melee: bool) -> Dictionary:
	var total := 0
	var names: PackedStringArray = []
	for rd in AiSpell.mods_for(_solo_mods_of_chain(member), "attacker_own", melee):
		total += int(rd.get("hit_mod", 0))
		names.append("%s %+d" % [str(rd.get("spell")), int(rd.get("hit_mod", 0))])
	return {"mod": total, "note": ", ".join(names)}


## F4: attackers-beneficiary mods ON the target — every unit striking the token bearer gets them
## (exporter encoding: "friendly units get +1 ... against" — e.g. Raiding Drugs, Eagle-Eyed Focus).
func _solo_spell_hit_mod_vs(target: GameUnit, melee: bool) -> Dictionary:
	var total := 0
	var names: PackedStringArray = []
	for rd in AiSpell.mods_for(_solo_mods_of_chain(target), "vs_target", melee):
		total += int(rd.get("hit_mod", 0))
		names.append("%s %+d vs target" % [str(rd.get("spell")), int(rd.get("hit_mod", 0))])
	return {"mod": total, "note": ", ".join(names)}


## The active mod records of a unit AND its host (a joined hero shares the unit's tokens).
func _solo_mods_of_chain(member: GameUnit) -> Array:
	var out: Array = []
	for u in [member, member.get_attached_to() if (member != null and member.has_method("get_attached_to")) else null]:
		var uu := u as GameUnit
		if uu != null:
			out.append_array(_solo_spell_mods.get(uu.get_instance_id(), []))
	return out


## Active spell defense-modifier on a defending unit (+ its host for a joined hero).
func _solo_spell_def_mod(target: GameUnit) -> int:
	var total := 0
	for rd in AiSpell.mods_for(_solo_mods_of_chain(target), "defense", false):
		total += int(rd.get("def_mod", 0))
	return total


## F4 — "once" consumption (book wording: the modifier applies to ONE attack exchange): after a
## resolved exchange, spend every once-mod that was AVAILABLE to it — the attacker's own hit mods,
## the defender's attackers-beneficiary mods and the defender's def mods (role- and scope-matched).
## The paired library token comes off with it, with a log line (rules-must-log).
func _solo_consume_once_mods(attacker: GameUnit, defender: GameUnit, melee: bool) -> void:
	# NML-006: the exchange also spends rule GRANTS on both sides (the "gets X, once" wording — the
	# next fight the unit takes part in) and, on a shooting exchange, the attacker's range once-mod.
	var att_roles: Array = ["attacker_own", "grant"]
	if not melee:
		att_roles.append("range")
	for pair in [[attacker, att_roles], [defender, ["vs_target", "defense", "grant"]]]:
		var unit := pair[0] as GameUnit
		if unit == null:
			continue
		for u in [unit, unit.get_attached_to() if unit.has_method("get_attached_to") else null]:
			var uu := u as GameUnit
			if uu != null:
				_solo_spend_once_mods(uu, pair[1] as Array, melee)


## F4/NML-006 — spend every once-record on ONE unit that matches `roles` (role- and scope-filtered
## exactly like the reads). Reverts the NML-006 side effects (grant overlay off, props stamps
## recomputed), removes the paired library token and logs each spend (rules-must-log).
func _solo_spend_once_mods(uu: GameUnit, roles: Array, melee: bool) -> void:
	var key := uu.get_instance_id()
	var records: Array = _solo_spell_mods.get(key, [])
	if records.is_empty():
		return
	var spent: Array = []
	for role in roles:
		for rd in AiSpell.mods_for(records, str(role), melee):
			if str((rd as Dictionary).get("duration", "")) == "once" and not spent.has(rd):
				spent.append(rd)
	if spent.is_empty():
		return
	for rd in spent:
		records.erase(rd)
		_solo_revoke_grant(rd as Dictionary)
		var spell := str((rd as Dictionary).get("spell", ""))
		if radial_menu_controller != null:
			radial_menu_controller.remove_library_token(uu, spell)
		for e in _solo_spell_tokens_active.duplicate():
			if (e as Dictionary).get("unit") == uu and str((e as Dictionary).get("token")) == spell:
				_solo_spell_tokens_active.erase(e)
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT,
				"\"%s\" on %s is consumed (applies once)" % [spell, uu.get_name()], true)
	if records.is_empty():
		_solo_spell_mods.erase(key)
	_solo_refresh_spell_stamps(uu)   # NML-006: stamps follow the surviving records


## NML-006 — the event-specific once-consumers (casting after the cast die, morale after the test
## die, speed after the executed move): spend the given roles on a member AND its host.
func _solo_spend_once_kind(member: GameUnit, roles: Array) -> void:
	if member == null:
		return
	for u in [member, member.get_attached_to() if member.has_method("get_attached_to") else null]:
		var uu := u as GameUnit
		if uu != null:
			_solo_spend_once_mods(uu, roles, false)


## Round boundary: every spell token placed this round comes off again (and syncs the removal).
func _solo_expire_spell_tokens() -> void:
	# NML-006: revert the mechanical side effects FIRST (grant overlays off, props stamps erased) —
	# also on the no-controller path, so headless/batch rounds never leak a granted rule or stamp.
	var affected: Array = []
	for key in _solo_spell_mods.keys():
		for rd in (_solo_spell_mods[key] as Array):
			_solo_revoke_grant(rd as Dictionary)
		var u := instance_from_id(int(key)) as GameUnit
		if u != null and is_instance_valid(u):
			for cu in _solo_joined_chain(u):
				if not affected.has(cu):
					affected.append(cu)
	_solo_spell_mods.clear()   # mechanical effects end with their tokens
	for cu in affected:
		(cu as GameUnit).unit_properties.erase("spell_move_mod")
		(cu as GameUnit).unit_properties.erase("spell_range_mod")
	if radial_menu_controller == null:
		_solo_spell_tokens_active.clear()
		return
	for e in _solo_spell_tokens_active:
		var tu: GameUnit = (e as Dictionary).get("unit")
		if tu != null and is_instance_valid(tu) and not tu.is_destroyed():
			radial_menu_controller.remove_library_token(tu, str((e as Dictionary).get("token")))
	_solo_spell_tokens_active.clear()


## The human's resist prompt (v3.5.1 interference: enemy models with tokens within 18" LoS of the
## caster's unit spend any number for -1 each). Iterative and optional: one token per confirm, cancel
## keeps the rest — the wave-6 "basic prompt" (full counter-casting UX is a later wave). Returns the
## interference total; the tokens are spent from the nearest eligible caster and MP-synced.
func _solo_prompt_interference(caster: GameUnit, caster_unit: GameUnit, spell_name: String,
		base_target: int = AiSpell.CAST_BASE_TARGET, boost: int = 0, target_label: String = "") -> int:
	var helpers: Array = solo_controller._aura_casters(solo_controller.human_slot, caster_unit, null)
	if helpers.is_empty():
		return 0
	var pool := 0
	for h in helpers:
		pool += int((h as Dictionary)["tokens"])
	# ONE tableau (maintainer 2026-07-22): +/- token count with a LIVE cast-roll preview, instead of
	# one ConfirmationDialog per token.
	var dlg := InterferenceDialog.new()
	add_child(dlg)
	var spent: int = await dlg.ask(caster.get_name(), spell_name, target_label, base_target, boost, pool)
	if spent <= 0:
		return 0
	# Spend across the eligible helpers nearest-first (the old loop hard-coded helpers[0]).
	var payers: PackedStringArray = []
	for d in SoloController._draw_aura_tokens(helpers, spent):
		var dd := d as Dictionary
		var payer := dd["unit"] as GameUnit
		var take := int(dd["tokens"])
		for i in range(take):
			payer.spend_caster_points(1)
		if network_manager != null and network_manager.has_method("broadcast_unit_casts"):
			network_manager.broadcast_unit_casts(payer)
		payers.append("%s ×%d" % [payer.get_name(), take])
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT,
			"Interference: %s spend%s %d token%s — the cast roll worsens to %d+" % [
			", ".join(payers), ("s" if payers.size() == 1 else ""), spent, ("" if spent == 1 else "s"),
			AiSpell.cast_target(boost, spent, base_target)], true)
	return spent


## The joined display label of a cast's target list.
func _solo_cast_target_label(targets: Array) -> String:
	var names: PackedStringArray = []
	for t in targets:
		names.append((t as GameUnit).get_name())
	return ", ".join(names)


## Refresh every caster's purple token disc after the AI's token spends (plan-time spends included:
## boost helpers and interference sources are known only to the controller, so refresh all).
func _solo_refresh_caster_markers() -> void:
	if radial_menu_controller == null or opr_army_manager == null:
		return
	for game_unit in opr_army_manager.game_units.values():
		var gu := game_unit as GameUnit
		if gu != null and gu.is_caster():
			radial_menu_controller._update_caster_marker(gu)


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
		# Targeting an Aircraft costs -12" of range (GF v3.5.1, system-scoped) and Ranged Shrouding
		# -6" floored at 6" — per CANDIDATE, so a ground target stays reachable while the aircraft
		# or shrouded unit next to it may not be.
		var eff_range: int = int(SoloController.effective_shoot_reach_in(max_range, hu))
		if _solo_sighted_count(attacker, hu, eff_range, bool(profile.get("indirect", false))) <= 0:
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
		# An aircraft candidate's -12" folds into the EV distance so its range gates see the effective reach.
		evs.append(AiEv.profile_ev(profile, att_ctx, AiEv.ctx_for(hu, in_cover, 0),
			dist + SoloController.target_range_penalty_in(hu), false) if not profile.is_empty() else 0.0)
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
	# B11 (test game 2): range is measured base-EDGE to base-edge like the ruler (GF v3.5.1 p.4
	# "measure from the closest point"), not model-centre to centre — the centre gate refused shots
	# the ruler showed in range (~5" off between large bases). Extending the range by both units'
	# base radii is the centre-space equivalent of subtracting them from every pair distance.
	var edge_slack_m: float = _solo_unit_base_radius_m(shooter) + _solo_unit_base_radius_m(target)
	return SoloController.sighted_models(solo_controller.alive_positions(shooter), target_positions,
		float(range_in) * MoveIntent.INCHES_TO_METERS + edge_slack_m, los)


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
	var from_r: float = _solo_unit_base_radius_m(shooter)   # base-aware terrain zones (precise perimeter test in
	var to_r: float = _solo_unit_base_radius_m(target)      # _zone_for_base): an edge-standing model sees in/out
	return func(sp: Vector3, tp: Vector3) -> bool:
		if overlay != null and overlay.has_method("has_line_of_sight") \
				and not overlay.has_line_of_sight(sp, tp, from_h, to_h, from_r, to_r):
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
		if SoloController.is_aircraft(gu):
			continue   # an Aircraft flies high — only the model counts; its base blocks no line of sight (GF v3.5.1)
		var key: int = gu.get_instance_id()
		for m in gu.get_alive_models():
			var node: Node3D = (m as ModelInstance).node
			if node == null or not is_instance_valid(node):
				continue
			out.append(LosRules.Blocker.new(Vector2(node.global_position.x, node.global_position.z),
				SoloController.model_base_radius_m(m), LosRules.model_height_category(m), key))
	return out


## Representative base radius (metres) of a unit — the LARGEST of its alive models — for the base-aware
## terrain-zone LOS test (GF/AoF v3.5.1: a model is IN terrain its base overlaps, so an edge-standing model
## still sees in/out). Max, so a big model straddling a forest edge is caught. terrain_overlay._zone_for_base
## does the PRECISE perimeter-overlap test (the earlier coarse version over-granted; reverted 888c66e).
func _solo_unit_base_radius_m(unit: GameUnit) -> float:
	if unit == null:
		return 0.0
	var r := 0.0
	for m in unit.get_alive_models():
		r = maxf(r, SoloController.model_base_radius_m(m))
	return r


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
	var groups: Array = []
	for m in members:
		var member := m as GameUnit
		if member == null or member.get_alive_count() == 0:
			continue
		var weapons: Array = []
		if member.source_type == "opr" and member.source_data is OPRApiClient.OPRUnit:
			weapons = (member.source_data as OPRApiClient.OPRUnit).weapons
		# Range is measured MODEL to MODEL (GF v3.5.1 p.8), so the in-range gate uses the NEAREST model pair,
		# not the unit-centre distance (field-test round 7, finding 5: a spread unit whose CENTRE was out of
		# range rolled NOTHING — silently — while its forward models were sighted and in range). Per-profile
		# scaling by the per-model sighted count below still zeroes any profile no model can actually reach.
		var member_dist: float = dist_in
		if not melee and enemy != null and solo_controller != null:
			member_dist = _solo_nearest_model_gap_in(member, enemy, dist_in)
		var profiles: Array = AiShooting.melee_profiles(weapons) if melee else AiShooting.profiles_in_range(weapons, member_dist)
		# Ranged Shrouding (quick-win wave): the target's "-6\" range to a min. of 6\"" denial re-gates
		# each profile at the SAME nearest-model distance the plain range gate used — covers the human's
		# volleys and the AI's alike (both build their strikes here).
		if not melee and enemy != null:
			profiles = profiles.filter(func(p) -> bool:
				return SoloController.ranged_shroud_reach_in(float((p as Dictionary).get("range", 0)), enemy) >= member_dist)
		if profiles.is_empty():
			continue
		var max_models: int = member.models.size()
		var melee_count: int = member.get_alive_count()
		if melee and enemy != null and solo_controller != null:
			# BASE-EDGE strike reach (round 7, finding 3): the old centre-space count excluded big bases
			# (walker/vehicle) from their own melee — the charger rolled nothing, only the defender struck.
			melee_count = solo_controller.striking_models_for(member, enemy)
		var scaled: Array = []
		var growth_ap := int(_solo_growth_attack_bonus(member).get("ap", 0))   # Piercing Growth
		# Unit-level grant (wave 5); coverage wave: DATA aliases (Warbound, Infected) via the
		# generic primitive layer — same facet, same dice.
		var member_shred: bool = RulesRegistry.unit_rule_active(member, "Shred") \
			or not RulesRegistry.unit_rules_of_primitive(member, "Shred").is_empty()
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
			if growth_ap > 0:
				prof["ap"] = int(prof.get("ap", 0)) + growth_ap
			# Per-model shooting (GF v3.5.1 p.8): a ranged profile fires with the member's models that
			# have range + LOS at ITS OWN range; melee scales by the models within 2" strike reach (p.9).
			var count: int = melee_count
			if not melee:
				count = _solo_sighted_count(member, enemy, int(prof.get("range", 0)), bool(prof.get("indirect", false))) if enemy != null else member.get_alive_count()
			# X2 (test game 2, B15): a dead bearer's weapon dies with it. Special weapons (fewer copies
			# than models) are pinned to specific models by EquipmentDistributor — fire per-copy attacks
			# × LIVING bearers (capped by the reach/sight count) instead of the unit-wide alive/max
			# ratio, which let the last survivor swing every dead specialist's fist. Base weapons (a
			# copy per model) and units without per-model loadout data keep the ratio scaling.
			var copies: int = maxi(int(prof.get("count", 1)), 1)
			var bearers: int = SoloController.alive_bearers_of(member, str(prof.get("name", ""))) if copies < max_models else -1
			if bearers >= 0:
				var per_copy: int = maxi(int(prof.get("attacks", 0)) / copies, 0)
				prof["attacks"] = per_copy * mini(bearers, count)
			else:
				prof["attacks"] = SoloController.effective_attacks(int(prof.get("attacks", 0)), count, max_models)
			scaled.append(prof)
		# Wave 5 Sergeant (model-level): ONE profile per member carries the bearer's attack share.
		AiEv.stamp_sergeant(scaled, member)
		AiEv.stamp_conditional_ap(scaled, member)   # value Shatter/Tear/Melee Slayer/Disintegrate AP
		groups.append({"name": member.get_name(), "quality": member.get_quality(),
			"fatigued": member.is_fatigued, "member": member, "profiles": scaled})
	return groups


## The NEAREST alive-model-to-alive-model distance (inches, table plane) between a member and the enemy —
## the model-to-model range measure of GF v3.5.1 p.8 (round 7, finding 5). Falls back to the caller's
## unit-centre distance when either side has no live model positions.
func _solo_nearest_model_gap_in(member: GameUnit, enemy: GameUnit, fallback_in: float) -> float:
	if solo_controller == null:
		return fallback_in
	var own: Array = solo_controller.alive_positions(member)
	var theirs: Array = solo_controller.alive_positions(enemy)
	if own.is_empty() or theirs.is_empty():
		return fallback_in
	var best := INF
	for a in own:
		for b in theirs:
			best = minf(best, MoveIntent.distance_inches(a as Vector3, b as Vector3))
	# B11: the profile range gate measures base-EDGE to base-edge like the ruler and the sighted
	# gate — one measuring truth (GF v3.5.1 p.4 "measure from the closest point").
	var edge_slack_in: float = (_solo_unit_base_radius_m(member) + _solo_unit_base_radius_m(enemy)) / MoveIntent.INCHES_TO_METERS
	return maxf(best - edge_slack_in, 0.0)


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
func _solo_hits(faces: Array, to_hit: int, profile: Dictionary, dist_in: float, target: GameUnit = null, charging: bool = false, roller: String = "") -> int:
	if bool(profile.get("precise", false)):   # Precise: flat +1 to hit — one choke point for every attack path
		to_hit = AiCombatMath.modified_hit_target(to_hit, 1)
	var hits: int = AiCombatMath.count_hits(faces, to_hit)
	if bool(profile.get("relentless", false)):
		var rel_bonus: int = AiCombatMath.relentless_bonus_hits(faces, dist_in)
		if rel_bonus > 0 and battle_log != null:
			# Rules-must-log (wave A): the bonus used to land silently — a "1 hit" line that reads
			# "2 hits" without explanation looks broken, not Relentless.
			battle_log.log_event(BattleLog.Category.COMBAT, "Relentless: +%d hit%s (unmodified 6s)" % [
				rel_bonus, ("" if rel_bonus == 1 else "s")], true)
		hits += rel_bonus
	if bool(profile.get("surge", false)):
		# Coverage wave: Surge-family gates — within_in (Point-Blank Surge: only within 12") and the
		# Devout-Boost upgrade (successful unmodified 5s count too when engaging from over 9").
		var within := float(profile.get("surge_within_in", 0.0))
		if within <= 0.0 or dist_in <= within:
			var bonus: int = AiCombatMath.surge_bonus_hits(faces)
			if int(profile.get("surge_low", 6)) < 6 and dist_in > float(profile.get("surge_over_in", 0.0)):
				for f in faces:
					if int(f) == 5 and 5 >= to_hit:
						bonus += 1
			hits += bonus
	# Coverage wave: the extra-ATTACK form (Bloodborn/Clan Warrior/Primal/Predator Fighter — "for
	# each unmodified 6 to hit, roll +1 attack; doesn't apply to newly generated attacks"): the
	# extra dice are ROLLED (visible tray), not auto-hits, and never re-trigger.
	if bool(profile.get("surge_attack", false)):
		var sixes: int = AiCombatMath.surge_bonus_hits(faces)
		# Primal Boost upgrade: successful unmodified 5s spawn attacks too.
		if int(profile.get("surge_attack_low", 6)) < 6:
			for f in faces:
				if int(f) == 5 and 5 >= to_hit:
					sixes += 1
		if sixes > 0:
			var extra_faces: Array = await _solo_tray_roll(sixes, to_hit, roller if not roller.is_empty() else "AI")
			var extra_hits: int = AiCombatMath.count_hits(extra_faces, to_hit)
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s: %d extra attack%s from unmodified 6s — %d hit%s" % [
					str(profile.get("surge_attack_rule", "Extra attacks")), sixes, ("" if sixes == 1 else "s"),
					extra_hits, ("" if extra_hits == 1 else "s")], true)
			hits += extra_hits
	if bool(profile.get("furious", false)):
		var fur_bonus: int = AiCombatMath.furious_bonus_hits(faces, charging)
		if fur_bonus > 0 and battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "Furious: +%d hit%s on the charge (unmodified 6s)" % [
				fur_bonus, ("" if fur_bonus == 1 else "s")], true)
		hits += fur_bonus
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


## The over-9" +1-defense rule a target projects ("" when none): Guarded (unconditional), or a
## Versatile Defense unit (wahl-effect wave — official text: "pick one effect: when shot or charged
## from over 9\" away, the unit either gets +1 to defense rolls, or enemy units get -1 to hit rolls
## against it"). V1 plays the +1-defense half CONSISTENTLY (documented default — it reuses the whole
## Guarded machinery; the -1-to-hit half is a future EV-driven switch). Registry-gated.
func _solo_over9_defense_rule(target: GameUnit) -> String:
	if _solo_rule_on_all_models(target, "Guarded"):
		return "Guarded"
	if _solo_rule_on_all_models(target, "Versatile Defense") and RulesRegistry.unit_rule_active(target, "Versatile Defense"):
		return "Versatile Defense"
	# Coverage wave: DATA aliases of the Guarded family (Sturdy, …) — "shot or charged from over 9\"
	# away → +1 to defense rolls", resolved via the generic primitive layer (all-models rules).
	for e in RulesRegistry.unit_rules_of_primitive(target, "Guarded"):
		var n := str((e as Dictionary)["name"])
		if n != "Guarded" and _solo_rule_on_all_models(target, n):
			return n
	return ""


## Mend (army-book, grill round 2 cut A — official text: "Once per activation, before attacking, pick
## one friendly model within 3\" with Tough, and remove D3 wounds from it."): the AI heals the WOUNDED
## Tough model (wounds_max > 1 — Tough(1) regiment pools are excluded by the rule's wording) with the
## most wounds lost within 3" of the bearer's unit, hero tiebreak; one visible tray die is the D3
## (1-2→1, 3-4→2, 5-6→3); the heal runs through the same wound-marker + MP seams the damage paths use.
## Distances are model-centre reads (documented simplification — slightly conservative for the AI).
## Human bearers apply the rule manually (their normal wound-token workflow). No-op without Mend.
func _solo_apply_mend(unit: GameUnit) -> void:
	if unit == null or opr_army_manager == null or not _solo_is_ai_unit(unit):
		return
	var bearers: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		bearers = bearers + unit.get_attached_heroes()
	var has_mend := false
	for b in bearers:
		var bu := b as GameUnit
		if bu != null and bu.get_alive_count() > 0 and RulesRegistry.unit_rule_active(bu, "Mend"):
			has_mend = true
			break
	if not has_mend:
		return
	var patient := _solo_mend_pick(unit, bearers)
	if patient == null:
		return
	var face: Array = await _solo_tray_roll(1, 1, "AI (%s)" % unit.get_name())   # a pure D3 value roll
	if face.is_empty():
		return
	var d3: int = (int(face[0]) + 1) / 2
	var lost: int = maxi(patient.wounds_max - patient.wounds_current, 0)
	var healed: int = mini(d3, lost)
	if healed <= 0:
		return
	patient.heal(healed)
	if radial_menu_controller != null:
		radial_menu_controller._update_wound_marker(patient)
	if network_manager != null and network_manager.has_method("broadcast_model_wounds"):
		network_manager.broadcast_model_wounds(patient)
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT, "Mend: %s heals %d wound%s (D3 rolled %d) — patient now %d/%d" % [
			unit.get_name(), healed, ("" if healed == 1 else "s"), int(face[0]), patient.wounds_current, patient.wounds_max], true)


## Breath Attack (army-book, grill round 2 cut A — official text: "Once per activation, before
## attacking, roll one die. On a 2+ one enemy unit within 6\" in line of sight takes 1 hit with
## Blast(3) and AP(1)."): one breath per AI unit activation (documented simplification, however many
## bearers). The AI picks the enemy in range + LOS worth the most expected wounds — Blast(3) counts
## min(3, models) hits, saved at the Shielded/Armor Defense with AP(1); Blast ignores Cover, and the
## 6" range can never trip Guarded's over-9 gate. Resolves through the normal save + wound-landing
## path (Regeneration applies), then the post-shooting morale trigger. Human bearers apply the rule
## manually. Registry-gated + parameter-tuned; no-op without the rule.
func _solo_apply_breath_attack(unit: GameUnit) -> void:
	if unit == null or opr_army_manager == null or solo_controller == null or not _solo_is_ai_unit(unit):
		return
	var bearers: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		bearers = bearers + unit.get_attached_heroes()
	var active := false
	for b in bearers:
		var bu := b as GameUnit
		if bu != null and bu.get_alive_count() > 0 and RulesRegistry.unit_rule_active(bu, "Breath Attack"):
			active = true
			break
	if not active:
		return
	var range_in: float = float(RulesRegistry.unit_param(unit, "Breath Attack", "range_in", 6.0))
	var blast_x: int = int(RulesRegistry.unit_param(unit, "Breath Attack", "blast", 3))
	var b_ap: int = int(RulesRegistry.unit_param(unit, "Breath Attack", "ap", 1))
	var trigger: int = int(RulesRegistry.unit_param(unit, "Breath Attack", "trigger_target", 2))
	var btarget: GameUnit = null
	var best := 0.0
	for h in opr_army_manager.get_game_units_for_player(solo_controller.human_slot):
		var hu := h as GameUnit
		if hu == null or _solo_combined_alive(hu) <= 0 or SoloController.unit_in_reserve(hu):
			continue
		if hu.has_method("is_attached") and hu.is_attached():
			continue
		if _solo_nearest_model_gap_in(unit, hu, INF) > range_in or not _solo_has_los(unit, hu):
			continue
		var score: float = float(mini(blast_x, _solo_combined_alive(hu))) \
			* (1.0 - AiEv.block_chance(_solo_shielded_defense(hu), b_ap, false))
		if score > best:
			best = score
			btarget = hu
	if btarget == null:
		return
	var face: Array = await _solo_tray_roll(1, trigger, "AI (%s)" % unit.get_name())
	if face.is_empty() or not DiceRules.is_success(int(face[0]), trigger, 0):
		if battle_log != null and not face.is_empty():
			battle_log.log_event(BattleLog.Category.COMBAT, "Breath Attack: %s rolls %d — fizzles (needs %d+)" % [
				unit.get_name(), int(face[0]), trigger], true)
		return
	var alive_before: int = btarget.get_alive_count()
	var wounds_before: int = _solo_unit_wounds_now(btarget)
	var bhits: int = maxi(mini(blast_x, _solo_combined_alive(btarget)), 1)
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT, "Breath Attack: %s breathes on %s — %d hit%s (Blast(%d), AP(%d))" % [
			unit.get_name(), btarget.get_name(), bhits, ("" if bhits == 1 else "s"), blast_x, b_ap], true)
	var bprofile: Dictionary = {"name": "Breath Attack", "ap": b_ap, "deadly": 0, "blast": blast_x, "rules": []}
	var w: int = await _solo_resolve_saves(unit, btarget, "Breath Attack", [], bhits,
		_solo_shielded_defense(btarget), bprofile, not _solo_is_ai_unit(btarget), false)
	if w > 0:
		await _solo_land_wounds(btarget, w, 0)
	await _solo_shooting_morale(btarget, alive_before, _solo_owner_label(btarget), wounds_before)
	_solo_consume_once_mods(unit, btarget, false)   # F4: once-mods spent by this exchange


## The Mend patient: the most-wounded alive Tough model (wounds_max > 1) within 3" of any alive model
## of the bearer's unit/heroes — friendly units of the same player, attached heroes included; ties
## prefer heroes. Null when nobody qualifies (then Mend simply does not fire this activation).
func _solo_mend_pick(unit: GameUnit, bearers: Array) -> ModelInstance:
	var bearer_positions: Array = []
	for b in bearers:
		var bu := b as GameUnit
		if bu == null:
			continue
		for m in bu.get_alive_models():
			var mi := m as ModelInstance
			if mi.node != null and is_instance_valid(mi.node):
				bearer_positions.append(mi.node.global_position)
	if bearer_positions.is_empty():
		return null
	var pid: int = int(unit.unit_properties.get("player_id", 0))
	var best: ModelInstance = null
	var best_key: int = -1
	for u in opr_army_manager.get_game_units_for_player(pid):
		var fu := u as GameUnit
		if fu == null:
			continue
		for m in fu.get_alive_models():
			var mi := m as ModelInstance
			if mi.wounds_max <= 1 or mi.wounds_current >= mi.wounds_max:
				continue
			if mi.node == null or not is_instance_valid(mi.node):
				continue
			var in_reach := false
			for bp in bearer_positions:
				if MoveIntent.distance_inches(bp, mi.node.global_position) <= 3.0:
					in_reach = true
					break
			if not in_reach:
				continue
			var key: int = (mi.wounds_max - mi.wounds_current) * 2 + (1 if fu.is_hero() else 0)
			if key > best_key:
				best_key = key
				best = mi
	return best


## The attack-die rule a striker benefits from ("" when none): the wave-4 MELEE-ONLY Unpredictable
## Fighter (Mummified) or the generic army-book Unpredictable ("when attacking" — shooting and melee,
## registry-gated the wave-5 way). Exact-match so neither rule fires the other, and never both.
func _solo_unpredictable_rule(striker: GameUnit, melee: bool) -> String:
	if melee and _solo_rule_on_all_models(striker, "Unpredictable Fighter"):
		return "Unpredictable Fighter"
	if AiEv.has_exact_rule(striker, "Unpredictable") and RulesRegistry.unit_rule_active(striker, "Unpredictable"):
		return "Unpredictable"
	# Unpredictable Shooter (autonomous wave 2026-07-19): the SHOOTING-only half of the same die.
	if not melee and AiEv.has_exact_rule(striker, "Unpredictable Shooter") \
			and RulesRegistry.unit_rule_active(striker, "Unpredictable Shooter"):
		return "Unpredictable Shooter"
	return ""


## The defender's Defense value after Shielded (army-book rule: "+1 to defense rolls against hits that are
## not from spells" — the solo automation has no spells, so every hit qualifies). Shared by every save site
## so the prompts/logs show the modified value. Wave 5: Armor(X) ("counts as having Defense X+") sets the
## working Defense FIRST — one seam, so shooting, melee, Impact and the EV metric all see the same value.
func _solo_shielded_defense(target: GameUnit) -> int:
	var base := AiCombatMath.shielded_defense(_solo_armored_defense(target), _solo_rule_on_all_models(target, "Shielded"))
	# Coverage wave: Shielded-family DATA aliases (Grounded Reinforcement — terrain-conditional
	# +1 defense; majority-in-cover approximation) via the generic primitive layer.
	if base == _solo_armored_defense(target):
		for e in RulesRegistry.unit_rules_of_primitive(target, "Shielded"):
			var ed := e as Dictionary
			var n := str(ed["name"])
			if n == "Shielded" or not _solo_rule_on_all_models(target, n):
				continue
			var sp: Dictionary = ed.get("params", {})
			if float(sp.get("terrain_within_in", 0.0)) > 0.0 and not _solo_majority_in_cover(target):
				continue
			# "Defense(X)": the bonus is the rule's RATING (coverage-wave no-text pass).
			var dbonus := int(ed.get("rating", 0)) if bool(sp.get("defense_bonus_from_rating", false)) else int(sp.get("defense_bonus", 1))
			base = clampi(base - maxi(dbonus, 0), 2, 6)
			break
	# Coverage wave — growth markers (Defensive Frenzy): +1 Defense per marker.
	var gb := _solo_growth_defense_bonus(target)
	if gb > 0:
		base = clampi(base - gb, 2, 6)
	# Spell def_mod (F3): +1 to defense = save one better (lower target), clamped 2..6.
	var dm := _solo_spell_def_mod(target)
	if dm != 0:
		base = clampi(base - dm, 2, 6)
	return base


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
	if not evasive:
		# Coverage wave (resolver audit): Evasive DATA aliases (Changebound Boost & kin — "enemies
		# attacking them ALWAYS get -1", the ungated upgrade of the Stealth-family bases).
		for ev_e in RulesRegistry.unit_rules_of_primitive(target, "Evasive"):
			var ev_n := str((ev_e as Dictionary)["name"])
			if ev_n != "Evasive" and _solo_rule_on_all_models(target, ev_n):
				evasive = true
				break
	# Coverage wave: the Stealth-family DATA alias that applies to THIS attack — Changebound /
	# Machine-Fog ("shot or charged from over 9\"" → applies_charged), Grounded Stealth (terrain-
	# conditional; majority-in-cover approximation). At most one alias fires (rule effects of one
	# family don't stack with Stealth's own -1 — best single penalty).
	var alias_pen := 0
	var alias_name := ""
	for e in RulesRegistry.unit_rules_of_primitive(target, "Stealth"):
		var ed := e as Dictionary
		var n := str(ed["name"])
		if n == "Stealth" or not _solo_rule_on_all_models(target, n):
			continue
		var p2: Dictionary = ed.get("params", {})
		var terr_in := float(p2.get("terrain_within_in", 0.0))
		if terr_in > 0.0 and not _solo_majority_in_cover(target):
			continue
		# Entrenched-family: only while the unit has NOT moved this round (moved_round stamp).
		if bool(p2.get("requires_stationary", false)) \
				and int(target.unit_properties.get("moved_round", -1)) == opr_army_manager.current_round:
			continue
		var gate := float(p2.get("over_in", 0.0))
		var charged_ok := bool(p2.get("applies_charged", false)) and melee and dist_in > gate
		var shot_ok := not melee and (gate <= 0.0 or dist_in > gate)
		if shot_ok or charged_ok:
			alias_pen = maxi(alias_pen, int(p2.get("hit_penalty", 0)))
			alias_name = n
	if melee:
		var melee_evasion: bool = _solo_rule_on_all_models(target, "Melee Evasion")
		if not melee_evasion:
			for me_e in RulesRegistry.unit_rules_of_primitive(target, "Melee Evasion"):
				var me_n := str((me_e as Dictionary)["name"])
				if me_n != "Melee Evasion" and _solo_rule_on_all_models(target, me_n):
					melee_evasion = true
					break
		var mm: int = AiCombatMath.melee_hit_modifier(evasive, melee_evasion)
		var base_note: String = ("Melee Evasion -1" if melee_evasion and not evasive else "Evasive -1") if mm != 0 else ""
		if alias_pen > 0 and mm == 0:
			mm = -alias_pen
			base_note = "%s -%d" % [alias_name, alias_pen]
		# Coverage wave: all-attacks Shot Modifiers (Grounded Precision) reach melee too.
		if shooter_member != null:
			for e in RulesRegistry.unit_rules_of_primitive(shooter_member, "Shot Modifier"):
				var sp3: Dictionary = (e as Dictionary).get("params", {})
				if not bool(sp3.get("all_attacks", false)):
					continue
				if float(sp3.get("terrain_within_in", 0.0)) > 0.0 and not _solo_majority_in_cover(shooter_member):
					continue
				mm += int(sp3.get("hit_bonus", 0))
				base_note = _solo_join_note(base_note, "%s %+d" % [str((e as Dictionary)["name"]), int(sp3.get("hit_bonus", 0))])
		var sm := _solo_spell_hit_mod(shooter_member, true)
		var vt := _solo_spell_hit_mod_vs(target, true)
		var vg := _solo_vengeance_bonus(target)
		if vg > 0:
			mm += vg
			base_note = _solo_join_note(base_note, "Vengeance +%d" % vg)
		var inst_m := _solo_instinctive_mod(shooter_member, target)
		if int(inst_m.get("mod", 0)) != 0:
			mm += int(inst_m["mod"])
			base_note = _solo_join_note(base_note, str(inst_m.get("note", "")))
		return {"mod": mm + int(sm.get("mod", 0)) + int(vt.get("mod", 0)),
			"note": _solo_join_note(_solo_join_note(base_note, str(sm.get("note", ""))), str(vt.get("note", "")))}
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
	if alias_pen > 0 and not (stealth and over_nine):
		mod -= alias_pen
		notes.append("%s -%d" % [alias_name, alias_pen])
	if target_artillery and over_nine:
		notes.append("Artillery target -2")
	if evasive:
		notes.append("Evasive -1")
	# Coverage wave — growth markers (Precision Growth): +1 to hit per two markers.
	if shooter_member != null:
		var gab := _solo_growth_attack_bonus(shooter_member)
		if int(gab.get("hit", 0)) != 0:
			mod += int(gab["hit"])
			notes.append("Growth %+d" % int(gab["hit"]))
	# Coverage wave: attacker-side Shot-Modifier family (Good Shot +1 / Bad Shot -1 / Targeting
	# Visor +1 over 9" / Grounded Precision terrain-conditional) — data-driven via the layer.
	if shooter_member != null:
		for e in RulesRegistry.unit_rules_of_primitive(shooter_member, "Shot Modifier"):
			var sp2: Dictionary = (e as Dictionary).get("params", {})
			var gate2 := float(sp2.get("over_in", 0.0))
			if gate2 > 0.0 and dist_in <= gate2:
				continue
			if float(sp2.get("terrain_within_in", 0.0)) > 0.0 and not _solo_majority_in_cover(shooter_member):
				continue
			if bool(sp2.get("requires_stationary", false)) \
					and int(shooter_member.unit_properties.get("moved_round", -1)) == opr_army_manager.current_round:
				continue
			var hb := int(sp2.get("hit_bonus", 0))
			if hb != 0:
				mod += hb
				notes.append("%s %+d" % [str((e as Dictionary)["name"]), hb])
	var sm := _solo_spell_hit_mod(shooter_member, false)
	if int(sm.get("mod", 0)) != 0:
		notes.append(str(sm.get("note", "")))
	var vt := _solo_spell_hit_mod_vs(target, false)
	if int(vt.get("mod", 0)) != 0:
		notes.append(str(vt.get("note", "")))
	var vg2 := _solo_vengeance_bonus(target)
	if vg2 > 0:
		mod += vg2
		notes.append("Vengeance +%d" % vg2)
	var inst2 := _solo_instinctive_mod(shooter_member, target)
	if int(inst2.get("mod", 0)) != 0:
		mod += int(inst2["mod"])
		notes.append(str(inst2.get("note", "")))
	return {"mod": mod + int(sm.get("mod", 0)) + int(vt.get("mod", 0)), "note": ", ".join(notes)}


## Vengeance (resolver wave A — "friendly units get +X to hit rolls when attacking that unit,
## where X is the number of markers on it"): markers land on the DESTROYER when a Vengeance unit
## dies (_solo_vengeance_on_destroyed); with two sides, every attacker of a marked unit is friendly
## to the fallen, so the marker count applies unconditionally.
func _solo_vengeance_bonus(target: GameUnit) -> int:
	if target == null:
		return 0
	var markers := 0
	for m in _solo_joined_chain(target):
		markers = maxi(markers, int((m as GameUnit).unit_properties.get("vengeance_markers", 0)))
	return markers


## Instinctive (resolver wave A — "must immediately attack the closest valid target and gets +1 to
## hit rolls for that attack"): the bonus applies exactly when the attacked unit IS the closest
## enemy (half-inch tie band). The AI's official targeting key is already nearest-first; the
## human's target choice stays free — attacking someone else simply forfeits the +1 (logged).
func _solo_instinctive_mod(shooter_member: GameUnit, target: GameUnit) -> Dictionary:
	if shooter_member == null or target == null or solo_controller == null or opr_army_manager == null:
		return {}
	var ent: Array = RulesRegistry.unit_rules_of_primitive(shooter_member, "Instinctive")
	if ent.is_empty():
		return {}
	var n := str((ent[0] as Dictionary)["name"])
	var bonus := int(((ent[0] as Dictionary).get("params", {}) as Dictionary).get("hit_bonus", 1))
	var from := solo_controller.unit_centre(shooter_member)
	var td := MoveIntent.distance_inches(from, solo_controller.unit_centre(target))
	for e in opr_army_manager.get_game_units_for_player(solo_controller.enemy_slot_of(shooter_member)):
		var eu := e as GameUnit
		if eu == null or eu == target or eu.is_destroyed() or solo_controller.unit_in_reserve(eu):
			continue
		if eu.has_method("is_attached") and eu.is_attached():
			continue
		if MoveIntent.distance_inches(from, solo_controller.unit_centre(eu)) < td - 0.5:
			return {}   # a closer valid target exists — no bonus for this attack
	return {"mod": bonus, "note": "%s +%d (closest target)" % [n, bonus]}


## Retreating Strike (resolver wave A — "once per round, when this unit ends its move within 3\"
## of enemy units after being in melee, pick one of them and roll X dice for each model with this
## rule in this unit; for each 6+ the target takes one wound"): fires on the automated post-melee
## Hit-&-Run step (the human's manual post-melee drag is untracked — the Versatile precedent).
func _solo_retreating_strike(unit: GameUnit) -> void:
	if unit == null or solo_controller == null or opr_army_manager == null:
		return
	for m in _solo_joined_chain(unit):
		var member := m as GameUnit
		if member.get_alive_count() == 0:
			continue
		for e in RulesRegistry.unit_rules_of_primitive(member, "Ravage"):
			var ed := e as Dictionary
			if str((ed.get("params", {}) as Dictionary).get("trigger", "")) != "post_melee_move":
				continue
			var n := str(ed["name"])
			if int(member.unit_properties.get("retreating_strike_round", -1)) == opr_army_manager.current_round:
				continue
			var tgt := solo_controller.nearest_human_unit(unit)
			if tgt == null or solo_controller.nearest_melee_gap_in(unit, tgt) > 3.0:
				continue
			member.unit_properties["retreating_strike_round"] = opr_army_manager.current_round
			var x := maxi(int(ed.get("rating", 0)), 1)
			var dice := x * member.get_alive_count()
			var owner_lbl: String = ("AI (%s)" % member.get_name()) if _solo_is_ai_unit(unit) else "You"
			var rs_faces: Array = await _solo_tray_roll(dice, AiCombatMath.RAVAGE_WOUND_TARGET, owner_lbl)
			var wounds: int = AiCombatMath.ravage_wounds(rs_faces)
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT,
					"%s: %s strikes while retreating — %d dice → %d wound%s on %s (no save)" % [
					n, member.get_name(), dice, wounds, ("" if wounds == 1 else "s"), tgt.get_name()], true)
			if wounds > 0:
				await _solo_land_wounds(tgt, wounds, 0)


## Vengeance placement ("when this unit is fully destroyed, place as many Vengeance markers on the
## unit that destroyed it as models with this rule in this unit at the beginning of the game"):
## fires at the three shared kill seams (both volley paths + melee consolidation). Marker count =
## the START size of every chain member carrying the rule (unit-level rules put it on all models).
func _solo_vengeance_on_destroyed(dead: GameUnit, destroyer: GameUnit) -> void:
	if dead == null or destroyer == null or not is_instance_valid(destroyer):
		return
	var markers := 0
	var rule_name := ""
	for m in _solo_joined_chain(dead):
		var member := m as GameUnit
		for e in RulesRegistry.unit_rules_of_primitive(member, "Vengeance"):
			rule_name = str((e as Dictionary)["name"])
			markers += maxi(member.get_size(), 1)
			break
	if markers <= 0:
		return
	var host := _solo_joined_chain(destroyer)[0] as GameUnit
	host.unit_properties["vengeance_markers"] = int(host.unit_properties.get("vengeance_markers", 0)) + markers
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT,
			"%s: %s falls — %d Vengeance marker%s on %s (its enemies get +1 to hit per marker)" % [
			rule_name, dead.get_name(), markers, ("" if markers == 1 else "s"), destroyer.get_name()], true)


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
		# Coverage wave (resolver audit): Counter DATA aliases (Counter-Attack, Counter in Melee).
		for e in RulesRegistry.unit_rules_of_primitive(member, "Counter"):
			if str((e as Dictionary)["name"]) != "Counter":
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
var _solo_retaliate_credit := 0   # Retaliate wounds of the LAST strike phase — the defender's tally credit
var _solo_last_save_ones := 0   # resolver wave A: unmodified Defense 1s of the LAST save batch (Bloodthirsty Fighter)


## Collect (and reset) the retaliation wounds of the last strike phase — the caller adds them to
## the DEFENDING side's melee tally (caused by the defender, inside the striker's phase).
func _solo_take_retaliate_credit() -> int:
	var c := _solo_retaliate_credit
	_solo_retaliate_credit = 0
	return c


func _solo_melee_strike_phase(striker: GameUnit, defender: GameUnit, charging: bool, filter: int, charge_from_in: float = 0.0) -> int:
	var human_defends: bool = not _solo_is_ai_unit(defender)
	_solo_log_armor(defender)   # Armor(X) "counts as Defense X+" (wave 5) — folded into _solo_shielded_defense
	var defense: int = _solo_shielded_defense(defender)
	if defense != _solo_armored_defense(defender) and battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT, "%s is Shielded: +1 Defense (saves on %d+)" % [
			defender.get_name(), defense], true)
	# Guarded / Versatile Defense's def-half: charged from over 9" away → +1 Defense for this melee's
	# saves. Fires where the charge distance is KNOWN (AI charges pass their pre-charge gap); the
	# human's manual charge distance is untracked (charge_from_in stays 0), the Versatile precedent.
	var m_over9 := _solo_over9_defense_rule(defender)
	if charging and not m_over9.is_empty() and charge_from_in > AiCombatMath.LONG_RANGE_IN:
		defense = AiCombatMath.guarded_defense(defense, true)
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "%s (%s): charged from over 9\" — +1 Defense (saves on %d+)" % [
				defender.get_name(), m_over9, defense], true)
	var mod_info: Dictionary = _solo_hit_mod_info(striker, defender, 0.0, true)
	# Wave-4 Unpredictable Fighter (Mummified, melee-only) and the generic Unpredictable ("when
	# attacking" — the same die, shooting AND melee): ONE die per melee for the whole unit —
	# 1-3 → AP(+1) on its melee weapons, 4-6 → +1 to hit (fatigue's unmodified-6-only overrides the +1).
	var uf_ap := 0
	var uf_hit := 0
	var upr_rule := _solo_unpredictable_rule(striker, true)
	if not upr_rule.is_empty():
		var uf_owner: String = ("AI (%s)" % striker.get_name()) if _solo_is_ai_unit(striker) else "You"
		var uf_face: Array = await _solo_tray_roll(1, AiCombatMath.BEST_HIT_TARGET, uf_owner)
		if not uf_face.is_empty():
			var uf_eff: Dictionary = AiCombatMath.unpredictable_fighter_effect(int(uf_face[0]))
			uf_ap = int(uf_eff["ap"])
			uf_hit = int(uf_eff["hit"])
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s: %s rolls %d → %s" % [
					upr_rule, striker.get_name(), int(uf_face[0]), ("AP(+1)" if uf_ap > 0 else "+1 to hit")], true)
	var caused := 0
	var regenable := 0
	var regen_proof := 0
	var struck_any := false   # did ANY weapon profile actually roll? (finding 8: surface a silent no-strike)
	# Resolver wave A — Reckless Piercing's round stamps add AP to every strike of this phase;
	# Deathstrike/Self-Destruct need the per-member alive counts BEFORE this phase's casualties.
	var extra_ap := _solo_reckless_ap(striker, defender)
	var alive_before_phase: Dictionary = {}
	for abm in _solo_joined_chain(defender):
		alive_before_phase[(abm as GameUnit).get_instance_id()] = (abm as GameUnit).get_alive_count()
	# Ravage(X) (army-book, grill round 2 cut A): on this unit's melee turn, X dice per alive bearer —
	# each 6+ is one DIRECT wound ("takes one wound", not "a hit": no hit roll, no save; Regeneration
	# still applies — no ignore clause). Per MEMBER so a Ravage hero in a plain unit rolls only its own.
	# Gated off the Counter-only split: the defender's two-phase strike-back must not roll it twice.
	if filter != SoloStrike.COUNTER_ONLY:
		var rv_members: Array = [striker]
		if striker.has_method("get_attached_heroes"):
			rv_members = rv_members + striker.get_attached_heroes()
		for rm in rv_members:
			var rv := rm as GameUnit
			if rv == null or rv.get_alive_count() <= 0:
				continue
			var rx: int = _solo_unit_rating(rv, "Ravage")
			if rx <= 0 or not RulesRegistry.unit_rule_active(rv, "Ravage"):
				continue
			var rv_dice: int = rx * rv.get_alive_count()
			var rv_owner: String = ("AI (%s)" % rv.get_name()) if _solo_is_ai_unit(striker) else "You"
			var rv_faces: Array = await _solo_tray_roll(rv_dice, AiCombatMath.RAVAGE_WOUND_TARGET, rv_owner)
			var rv_wounds: int = AiCombatMath.ravage_wounds(rv_faces)
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "Ravage(%d): %s rolls %d dice → %d wound%s (no save)" % [
					rx, rv.get_name(), rv_dice, rv_wounds, ("" if rv_wounds == 1 else "s")], true)
			if rv_wounds > 0:
				struck_any = true
				caused += rv_wounds   # pre-Regeneration, same basis as the weapon strikes' tally
				await _solo_land_wounds(defender, rv_wounds, 0)
	# Resolver wave A — Takedown Strike: the once-per-game extra attack joins the striker's own
	# turn (never the Counter-only pre-phase; strike-back counts — "its turn to attack in melee").
	var m_groups: Array = _solo_attack_groups(striker, 0.0, true, defender)
	if filter != SoloStrike.COUNTER_ONLY and not m_groups.is_empty():
		m_groups = m_groups + _solo_takedown_bonus_groups(striker, true)
	for grp in m_groups:
		var group := grp as Dictionary
		var base_quality: int = int(group.get("quality", 4))
		var fatigued: bool = bool(group.get("fatigued", false))
		for p in group.get("profiles", []):
			var profile := _solo_bridge_granted_flags(group.get("member"), p as Dictionary)
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
			# Versatile Attack (army-book): on a charge from over 9" the AI picks the EV-better of +1 to hit
			# or AP(+1) for this weapon — the SAME chooser as the shooting facet + the EV metric. Fatigue
			# (unmodified-6-only) overrides the +1-to-hit part; the AP(+1) part still folds in below.
			var v_ap := 0
			if bool(profile.get("versatile_attack", false)) and charging and charge_from_in > AiCombatMath.LONG_RANGE_IN:
				var vm: Dictionary = AiEv.versatile_best_mode(to_hit, _solo_shielded_defense(defender), int(profile.get("ap", 0)), bool(profile.get("bane", false)))
				if not fatigued:
					to_hit = AiCombatMath.modified_hit_target(to_hit, int(vm.get("hit_mod", 0)))
				v_ap = int(vm.get("ap", 0))
				if battle_log != null:
					battle_log.log_event(BattleLog.Category.COMBAT, "Versatile Attack: %s on the charge" % [
						"AP(+1)" if v_ap > 0 else "+1 to hit"], true)
			if not fatigued:
				_solo_log_hit_mod(mod_info, defender, to_hit)
			var roll_owner: String = ("AI (%s)" % str(group.get("name", "?"))) if _solo_is_ai_unit(striker) else "You"
			var faces: Array = await _solo_tray_roll(int(profile.get("attacks", 0)), to_hit, roll_owner)
			if bool(profile.get("limited", false)):
				solo_controller.mark_limited_used(group.get("member"), profile)   # once per game (wave 5)
			await _solo_hazardous_self_wounds(striker, profile, faces)   # resolver wave A: natural 1s wound the striker
			var hits: int = await _solo_hits(faces, to_hit, profile, 0.0, defender, charging, _solo_owner_label(striker))
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s strikes with %s at %s — %d hit%s" % [
					str(group.get("name", "?")), str(profile.get("name", "?")), defender.get_name(), hits, ("" if hits == 1 else "s")], true)
			if hits <= 0:
				continue
			var eff: Dictionary = _solo_thrust_profile(profile, charging)   # AP(+1) on charge
			if uf_ap > 0 or v_ap > 0 or extra_ap > 0:   # Unpredictable Fighter / Versatile / Reckless AP (never mutate source)
				eff = eff.duplicate()
				eff["ap"] = int(eff.get("ap", 0)) + uf_ap + v_ap + extra_ap
			var m_deadly: bool = int(eff.get("deadly", 0)) > 0
			var m_takedown: bool = bool(eff.get("takedown", false))
			_solo_last_save_ones = 0   # resolver wave A: count only THIS batch's blocked 1s
			var w: int = await _solo_resolve_saves(group.get("member"), defender, str(profile.get("name", "?")), faces, hits, defense, eff, human_defends, true, not (m_deadly or m_takedown), charging)
			if m_takedown and w > 0:
				# Takedown Strike (resolver wave A): wounds go to the CHOSEN model (AI picks, the
				# human clicks — the B5 flow), multiplied by the profile's Deadly.
				var td_w: int = w * maxi(int(eff.get("deadly", 0)), 1)
				var td_dealt: int
				if _solo_ignores_regen(group.get("member"), eff):
					td_dealt = await _solo_land_takedown_wounds(group.get("member"), defender, str(profile.get("name", "?")), 0, td_w)
				else:
					td_dealt = await _solo_land_takedown_wounds(group.get("member"), defender, str(profile.get("name", "?")), td_w, 0)
				caused += td_dealt
			elif m_deadly and w > 0:
				# Deadly (GF v3.5.1 p.14, no carry-over): each unsaved wound ×X on one model; the DEALT
				# wounds feed the melee wound-comparison so the multiply still decides who wins.
				var dealt: int
				if _solo_ignores_regen(group.get("member"), eff):
					dealt = await _solo_land_deadly_wounds(defender, str(profile.get("name", "?")), int(eff.get("deadly", 0)), 0, w)
				else:
					dealt = await _solo_land_deadly_wounds(defender, str(profile.get("name", "?")), int(eff.get("deadly", 0)), w, 0)
				caused += dealt
			else:
				caused += w
				if _solo_ignores_regen(group.get("member"), eff):
					regen_proof += w
				else:
					regenable += w
			# Bloodthirsty Fighter (resolver wave A — "for each unmodified 1 that enemies roll when
			# blocking hits from this model's weapons in melee, this model may roll +1 attack with
			# that weapon; doesn't apply to newly generated attacks"): consume this batch's 1s once.
			var bt_ones := _solo_last_save_ones
			_solo_last_save_ones = 0
			if bt_ones > 0 and hits > 0:
				var bt_name := ""
				for bte in RulesRegistry.unit_rules_of_primitive(group.get("member"), "Bloodthirsty Fighter"):
					bt_name = str((bte as Dictionary)["name"])
					break
				if not bt_name.is_empty():
					if battle_log != null:
						battle_log.log_event(BattleLog.Category.COMBAT,
							"%s: %d blocked 1%s — %s rolls %d extra attack%s with %s" % [
							bt_name, bt_ones, ("" if bt_ones == 1 else "s"), str(group.get("name", "?")),
							bt_ones, ("" if bt_ones == 1 else "s"), str(profile.get("name", "?"))], true)
					var bt_faces: Array = await _solo_tray_roll(bt_ones, to_hit, roll_owner)
					var bt_hits: int = await _solo_hits(bt_faces, to_hit, profile, 0.0, defender, charging, _solo_owner_label(striker))
					if bt_hits > 0:
						# Extra attacks resolve pooled (no Deadly/Takedown special-casing — the aof
						# bearers carry plain weapons) and NEVER chain (counter reset right after).
						var bt_w: int = await _solo_resolve_saves(group.get("member"), defender, str(profile.get("name", "?")), bt_faces, bt_hits, defense, eff, human_defends, true, true, charging)
						_solo_last_save_ones = 0
						caused += bt_w
						if _solo_ignores_regen(group.get("member"), eff):
							regen_proof += bt_w
						else:
							regenable += bt_w
	var landed_on_defender := 0
	if regenable + regen_proof > 0:
		landed_on_defender = await _solo_land_wounds(defender, regenable, regen_proof)
	# Retaliate(X) — wave 7 (official text: "When this model takes wounds in melee, the attacker
	# takes X hits per wound taken."): reactive hits AFTER the wounds landed (post-Regeneration =
	# wounds actually TAKEN), saved at the striker's Shielded-adjusted Defense, no AP (not a
	# weapon), NON-chaining (retaliation wounds never trigger the striker's own Retaliate). The
	# wounds credit the DEFENDER's melee tally via _solo_take_retaliate_credit (caller collects).
	if landed_on_defender > 0 and _solo_combined_alive(striker) > 0 \
			and RulesRegistry.unit_rule_active(defender, "Retaliate"):
		var rx: int = maxi(1, _solo_unit_rating(defender, "Retaliate"))
		var rhits: int = rx * landed_on_defender
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT,
				"Retaliate(%d): %s lashes back — %d hit%s (%d per wound taken)" % [
				rx, defender.get_name(), rhits, ("" if rhits == 1 else "s"), rx], true)
		var rprofile: Dictionary = {"name": "Retaliate", "ap": 0, "deadly": 0, "rules": []}
		var rw: int = await _solo_resolve_saves(defender, striker, "Retaliate", [], rhits,
			_solo_shielded_defense(striker), rprofile, not _solo_is_ai_unit(striker), true)
		if rw > 0:
			await _solo_land_wounds(striker, rw, 0)
			_solo_retaliate_credit += rw
	# Resolver wave A — Deathstrike / Self-Destruct death-half: models killed by THIS phase's
	# strikes lash out at the striker (X hits per fallen carrier, Retaliate-style saves).
	await _solo_deathstrike_hits(defender, striker, alive_before_phase)
	# A charger (or full strike-back) that rolled NOTHING was silently skipped in the log, so a legitimate
	# fight looked one-sided (field-test finding 8: the walker charger's strikes never appeared — it had no
	# melee-weapon profile in reach). Surface it on the FULL strike so both combatants' resolution is shown;
	# the Counter-only / non-Counter sub-phases legitimately roll nothing when the unit lacks those weapons.
	if not struck_any and filter == SoloStrike.ALL and battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT,
			"%s has no melee weapons in reach — no strikes (GF/AoF v3.5.1 p.9)" % striker.get_name(),
			_solo_is_ai_unit(striker))
	if struck_any:
		_solo_consume_once_mods(striker, defender, true)   # F4: once-mods spent by this strike phase
	return caused


## Await a ConfirmationDialog's outcome WITHOUT the visibility race: Godot's AcceptDialog hides itself
## BEFORE emitting `confirmed`, so an `await dlg.visibility_changed` resumed with the choice still unset and
## an OK click read as "No" — the strike-back that never rolled and the spell interference that never spent
## a token (Windows playtest bug 3; invisible headless, where the AI defender skips the dialog). Polling the
## two outcome signals is order-proof; a dialog hidden by code without either signal counts as "No".
func _solo_await_confirm(dlg: AcceptDialog, keep_exclusive: bool = true) -> bool:
	var outcome: Array = []
	dlg.confirmed.connect(func() -> void: outcome.append(true))
	dlg.canceled.connect(func() -> void: outcome.append(false))
	# B3 (test game 1, High Sister): EXCLUSIVE by default — a stray click outside used to close the
	# popup with NEITHER signal, which read as "No": the strike-back never rolled, the melee was
	# lost 0:X and the unit routed on morale. WAIT-style dialogs (consolidation: the player drags
	# models WHILE the dialog stands) pass keep_exclusive=false so the board stays interactive.
	# If it still hides without a choice (window-manager path), RE-ASK a bounded number of times
	# instead of guessing "No"; only then default to the safe refusal.
	dlg.exclusive = keep_exclusive
	dlg.popup_centered()
	var reasks := 0
	while outcome.is_empty() and is_instance_valid(dlg):
		if not dlg.visible:
			if reasks >= 3:
				break
			reasks += 1
			dlg.popup_centered()
		await get_tree().process_frame
	return false if outcome.is_empty() else bool(outcome[0])


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
	var strike: bool = await _solo_await_confirm(dlg)   # order-proof (see _solo_await_confirm)
	dlg.queue_free()
	# B3: the choice ALWAYS gets its log line — a silent "Hold" read like a swallowed input.
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT,
			("%s strikes back" % defender.get_name()) if strike else
			("%s holds — no strike back" % defender.get_name()), false)
	return strike


## Impact(X) auto-hits on a charge (GF/AoF v3.5.1 p.13: "Roll X dice when attacking after charging, unless
## fatigued. For each 2+ the target takes one hit."). Impact is a per-model rule, so `charger` rolls X per
## alive model, MINUS one roll per defender model with Counter (p.13 Counter); the hits carry no AP/Deadly
## (Impact is not a weapon) and save at the defender's (Shielded-adjusted) Defense — Guarded's +1 also
## covers Impact when the charge came from over 9" (`charge_from_in`; 0 = unknown, e.g. a human charge).
## Wounds are APPLIED here (Regeneration-bucketed by the charger's Unstoppable) and RETURNED for the
## melee-winner tally. Skipped when the charger is fatigued or has no Impact. human_defends: the human
## rolls saves.
func _solo_charge_impact(charger: GameUnit, defender: GameUnit, human_defends: bool, charge_from_in: float = 0.0) -> int:
	if charger == null or defender == null:
		return 0
	var x: int = _solo_unit_rating(charger, "Impact")
	# Heavy Impact (autonomous wave 2026-07-19 — "Counts as having Impact(X) with hits that have
	# AP(1)."): a SECOND impact pool whose hits save at AP(1). unit_rating's "<name>(" prefix keeps
	# the two ratings apart. Counter's roll denial strips the HEAVY dice first (defender-optimal,
	# the codebase's removal convention).
	var hx: int = _solo_unit_rating(charger, "Heavy Impact")
	var heavy_ap: int = int(RulesRegistry.unit_param(charger, "Heavy Impact", "ap", 1))
	if (x <= 0 and hx <= 0) or charger.is_fatigued:
		return 0
	var models: int = charger.get_alive_count()
	var counter_models: int = _solo_counter_models(defender)
	var heavy_cut: int = mini(counter_models, hx * models)
	var heavy_dice: int = hx * models - heavy_cut
	var dice: int = AiCombatMath.impact_total_dice(x, models, counter_models - heavy_cut)
	if counter_models > 0 and battle_log != null and (x + hx) * models > 0:
		battle_log.log_event(BattleLog.Category.COMBAT, "Counter: %s loses %d Impact roll%s" % [
			charger.get_name(), counter_models, ("" if counter_models == 1 else "s")], true)
	var impact_defense: int = AiCombatMath.guarded_defense(_solo_shielded_defense(defender),
		not _solo_over9_defense_rule(defender).is_empty() and charge_from_in > AiCombatMath.LONG_RANGE_IN)
	var caused: int = 0
	for pool in [{"label": "Impact", "rating": x, "dice": dice, "ap": 0},
			{"label": "Heavy Impact", "rating": hx, "dice": heavy_dice, "ap": heavy_ap}]:
		var p := pool as Dictionary
		if int(p["dice"]) <= 0 or _solo_combined_alive(defender) <= 0:
			continue
		var faces: Array = await _solo_tray_roll(int(p["dice"]), AiCombatMath.IMPACT_HIT_TARGET, _solo_owner_label(charger))
		var hits: int = AiCombatMath.impact_hits(faces)
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "%s: %s(%d) rolls %d di%s → %d hit%s" % [
				charger.get_name(), str(p["label"]), int(p["rating"]), int(p["dice"]),
				("e" if int(p["dice"]) == 1 else "ce"), hits, ("" if hits == 1 else "s")], true)
		if hits <= 0:
			continue
		var profile: Dictionary = {"name": str(p["label"]), "ap": int(p["ap"]), "deadly": 0, "rules": []}
		var w: int = await _solo_resolve_saves(charger, defender, str(p["label"]), [], hits, impact_defense, profile, human_defends, true)
		if w > 0:
			if _solo_ignores_regen(charger, profile):
				await _solo_land_wounds(defender, 0, w)
			else:
				await _solo_land_wounds(defender, w, 0)
			caused += w
	return caused


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
		hits: int, base_defense: int, profile: Dictionary, human_defends: bool, melee: bool,
		apply_deadly: bool = true, charging: bool = false, dist_in: float = -1.0) -> int:
	if hits <= 0:
		return 0
	# Base AP plus any conditional AP (Shatter/Tear/Melee Slayer/Disintegrate; range-gated Slayer/
	# Piercing Hunter need `dist_in` — -1 = unknown, their ranged leg then stays off, conservative)
	# this weapon gets against THIS defender — registry-driven, system-scoped.
	var cond_parts: Array = _solo_conditional_ap_parts(profile, striker, defender, charging, dist_in, melee)
	var cond_ap := 0
	for cp in cond_parts:
		cond_ap += int((cp as Dictionary)["bonus"])
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "%s: AP(+%d) against %s" % [
				str((cp as Dictionary)["name"]), int((cp as Dictionary)["bonus"]), defender.get_name()], true)
	var ap: int = int(profile.get("ap", 0)) + cond_ap
	# Rending (GF/AoF v3.5.1 p.14) AND the army-book Destructive (wave 4) BOTH upgrade the unmodified-6-to-
	# hit hits to AP(+4); they share AiCombatMath.rending_ap_hits (one math). The only difference is
	# downstream: Rending bypasses Regeneration (via _solo_ignores_regen), Destructive does not.
	var on6_bonus: int = _solo_on6_ap_bonus(profile, striker)
	var ap4_label := ""
	if bool(profile.get("rending", false)):
		ap4_label = "Rending"
	elif bool(profile.get("destructive", false)):
		ap4_label = "Destructive"
	elif on6_bonus > 0:
		ap4_label = "Crack"
	var ap4_hits: int = AiCombatMath.rending_ap_hits(to_hit_faces, hits) if on6_bonus > 0 else 0
	var bane: bool = _solo_striker_has_bane(striker, profile, melee)
	var total := 0
	# AP-on-6 sub-volley first; a Blast-multiplied hit-count can only shrink the count via the cap.
	if ap4_hits > 0:
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "%s: %d hit%s on a 6 → AP(+%d)" % [
				ap4_label, ap4_hits, ("" if ap4_hits == 1 else "s"), on6_bonus], true)
		total += await _solo_save_batch(striker, defender, "%s (%s)" % [weapon_name, ap4_label], ap4_hits,
			base_defense, ap + on6_bonus, profile, human_defends, bane, apply_deadly, dist_in > AiCombatMath.LONG_RANGE_IN)
	var normal: int = hits - ap4_hits
	if normal > 0:
		total += await _solo_save_batch(striker, defender, weapon_name, normal, base_defense, ap, profile, human_defends, bane, apply_deadly, dist_in > AiCombatMath.LONG_RANGE_IN)
	return total


## One save batch: `count` saves at Defense `base_defense` worsened by `ap`, on the real tray, then Deadly.
## When the striker has Bane the defender re-rolls its unmodified Defense 6s (extra tray dice) before the
## blocks are counted (GF/AoF v3.5.1 p.13). Returns wounds (Deadly-multiplied). human_defends: prompt the
## human (their dice), else the AI auto-rolls its saves.
func _solo_save_batch(striker: GameUnit, defender: GameUnit, weapon_name: String, count: int,
		base_defense: int, ap: int, profile: Dictionary, human_defends: bool, bane: bool,
		apply_deadly: bool = true, over9: bool = false) -> int:
	if count <= 0:
		return 0
	# Fortified (defender): incoming hits count as AP(-1), to a min. of AP(0).
	if _solo_rule_on_all_models(defender, "Fortified"):
		var ap_before := ap
		ap = AiCombatMath.fortified_ap(ap, true)
		# Maintainer live-test finding: the silent reduction read as "rule not working" — say it
		# whenever it actually changes the save target.
		if ap < ap_before and battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "Fortified: %s takes the hits at AP(%d) instead of AP(%d) — saves on %d+" % [
				defender.get_name(), ap, ap_before, base_defense + ap], true)
	else:
		# Coverage wave: Fortified-family DATA aliases (Guardian, Primeborn — the over-9"-gated
		# form: "shot or charged from over 9\" away → hits count as AP(-1), min AP(0)").
		for e in RulesRegistry.unit_rules_of_primitive(defender, "Fortified"):
			var ed := e as Dictionary
			var n := str(ed["name"])
			if n == "Fortified":
				continue
			var gate_in := float((ed.get("params", {}) as Dictionary).get("over_in", 0.0))
			if gate_in > 0.0 and not over9:
				continue
			if not _solo_rule_on_all_models(defender, n):
				continue
			var apb := ap
			ap = AiCombatMath.fortified_ap(ap, true)
			if ap < apb and battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s: %s takes the hits at AP(%d) instead of AP(%d) — saves on %d+" % [
					n, defender.get_name(), ap, apb, base_defense + ap], true)
			break
	var save_faces: Array
	if human_defends:
		save_faces = await _solo_prompt_saves(striker, defender, weapon_name, count, base_defense, ap)
	else:
		_solo_log_save_threshold(defender, base_defense, ap)
		save_faces = await _solo_tray_roll(count, base_defense + ap, "AI (%s)" % defender.get_name(), "defense")
	# Resolver wave A — Bloodthirsty Fighter reads the blocker's unmodified 1s of this batch (the
	# melee strike loop resets the counter before its resolve and consumes it right after).
	for sf in save_faces:
		if int(sf) == 1:
			_solo_last_save_ones += 1
	var blocks: int
	var reroll: Array = []
	if bane:
		var sixes: int = AiCombatMath.bane_reroll_count(save_faces)
		if sixes > 0:
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "Bane: %s re-rolls %d unmodified Defense 6%s" % [
					defender.get_name(), sixes, ("" if sixes == 1 else "s")], true)
			reroll = await _solo_tray_roll(sixes, base_defense + ap, _solo_owner_label(defender), "defense")
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
	var unsaved := maxi(0, count - blocks)
	# apply_deadly=false (Bug: Deadly no-carry-over): return the RAW unsaved count so the caller can
	# apply Deadly per-model (each ×X, capped at one model, no spill). The pooled deadly_multiplier path
	# below stays for spells and every non-Deadly weapon (identical to before). Shred rides the pool.
	if not apply_deadly and bool(profile.get("deadly", 0) != 0) and int(profile.get("deadly", 0)) > 0:
		return unsaved + shred_extra
	return _solo_deadly_wounds(unsaved, profile, defender) + shred_extra


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
		if s.ends_with("Aura"):
			continue
		# Lacerate (AoF Advanced v3.5.1) is a straight data-alias of plain Bane — identical wording
		# ("when attacking the target must re-roll unmodified Defense results of 6"), no melee/shooting
		# qualifier — so any non-Aura Lacerate always applies. See special-rules-coverage-plan.
		if s.begins_with("Lacerate"):
			return true
		if not s.begins_with("Bane"):
			continue
		if s.begins_with("Bane in Melee"):
			if melee:
				return true
		elif s.begins_with("Bane when Shooting"):
			if not melee:
				return true
		else:
			return true   # plain "Bane"
	# Coverage wave: DATA aliases of the Bane primitive (Mischievous, Scrapper — "targets must
	# re-roll unmodified Defense results of 6 when blocking hits from this model's weapons").
	# bypass_regen stays per-alias data (_solo_ignores_regen reads it), so a no-bypass alias
	# re-rolls the sixes without cutting through Regeneration.
	if striker != null:
		for e in RulesRegistry.unit_rules_of_primitive(striker, "Bane"):
			var n := str((e as Dictionary)["name"])
			if not n.begins_with("Bane") and not n.ends_with("Aura") \
					and bool(((e as Dictionary).get("params", {}) as Dictionary).get("reroll_save_sixes", false)):
				return true
	return false


## The target's Regeneration / medic (GF Advanced Rules v3.5.1: "When a unit where all models have this
## rule takes wounds, roll one die for each. On a 5+ it is ignored."; the Battle Brothers "Medical
## Training" item grants Regeneration Aura): roll one REAL tray die per incoming wound, each 5+ ignores
## it. AP never affects this roll (AP only modifies Defense rolls). The battle log always states the
## outcome ("rolls N regeneration dice — M ignored"), so a 0-ignore roll is still visible. Returns the
## wounds that actually land; units without the rule take full wounds (no roll).
func _solo_apply_regeneration(target: GameUnit, wounds: int, from_spell: bool = false) -> int:
	var pick := _solo_regen_pick(target, from_spell)
	var regen_target: int = int(pick.get("target", 0))
	if wounds <= 0 or regen_target <= 0:
		return maxi(wounds, 0)
	var faces: Array = await _solo_tray_roll(wounds, regen_target, _solo_owner_label(target))
	var ignored := 0
	for f in faces:
		if int(f) >= regen_target:
			ignored += 1
	if battle_log != null:
		# Rules-must-log: the line names the ACTUAL family rule — aliases (Plaguebound, Knightborn,
		# Protected, …) included, not just the three named forms.
		var rule_name: String = str(pick.get("name", "regeneration"))
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
func _solo_regen_target(target: GameUnit, from_spell: bool = false) -> int:
	return int(_solo_regen_pick(target, from_spell).get("target", 0))


## The winning Regeneration-family pick — {target: int (0 = none), name: String} — shared by the
## roll and its log line (rules-must-log: the line names the ACTUAL rule, aliases included).
func _solo_regen_pick(target: GameUnit, from_spell: bool = false) -> Dictionary:
	var best := 0   # the most generous (lowest) ignore target the unit fields; 0 = none
	var best_name := ""
	if _solo_has_regeneration(target):
		best = int(RulesRegistry.unit_param(target, "Regeneration", "ignore_target", 5))
		best_name = "regeneration"
	if _solo_rule_on_all_models(target, "Self-Repair"):
		var sr := int(RulesRegistry.unit_param(target, "Self-Repair", "ignore_target", 6))
		if best == 0 or sr < best:
			best = sr
			best_name = "self-repair"
	# Resistance (wave-5): Regeneration family that ignores normal wounds on 6+, but SPELL wounds on a
	# far more generous 2+ (official text). from_spell picks the threshold; the min keeps the most
	# generous rule binding when a unit somehow fields several.
	if _solo_rule_on_all_models(target, "Resistance"):
		var key := "ignore_target_spell" if from_spell else "ignore_target"
		var rs := int(RulesRegistry.unit_param(target, "Resistance", key, 2 if from_spell else 6))
		if best == 0 or rs < best:
			best = rs
			best_name = "resistance"
	# Coverage wave (2026-07-23): DATA aliases of the family (Plaguebound/Protected 6+, Knightborn
	# 6+/4+ vs spells, …) via the generic primitive layer — all_models entries require the whole
	# unit to carry the rule, exactly like Self-Repair.
	for e in RulesRegistry.unit_rules_of_primitive(target, "Regeneration"):
		var ed := e as Dictionary
		var n := str(ed["name"])
		if n == "Regeneration" or n == "Self-Repair" or n == "Resistance":
			continue   # the named forms above stay the one truth
		var params: Dictionary = ed.get("params", {})
		if bool(params.get("all_models", false)) and not _solo_rule_on_all_models(target, n):
			continue
		var key2 := "ignore_target_spell" if from_spell else "ignore_target"
		var tgt := int(params.get(key2, params.get("ignore_target", 0)))
		if tgt > 0 and (best == 0 or tgt < best):
			best = tgt
			best_name = n
	return {"target": best, "name": best_name}


## Banner's morale-test bonus for a unit (wave 5): +1 when the unit or an attached hero carries Banner
## AND its book fields the rule for this system (RulesRegistry gate; the bonus value is data with the
## constant fallback). Coverage wave: DATA aliases of the family (Courage Aura, Hold the Line, Hive
## Bond, …) resolve through the generic primitive layer — the strongest single bonus applies (rule
## effects of the same name never stack; different names are one family here, best-of keeps it sane).
func _solo_morale_bonus(unit: GameUnit) -> int:
	var best := 0
	var members: Array = [unit]
	if unit != null and unit.has_method("get_attached_heroes"):
		members = members + unit.get_attached_heroes()
	for m in members:
		var member := m as GameUnit
		if member == null or member.get_alive_count() == 0:
			continue
		if RulesRegistry.unit_rule_active(member, "Banner"):
			best = maxi(best, int(RulesRegistry.unit_param(member, "Banner", "morale_bonus", AiCombatMath.BANNER_MORALE_BONUS)))
		for e in RulesRegistry.unit_rules_of_primitive(member, "Banner"):
			var ed := e as Dictionary
			if str(ed["name"]) == "Banner":
				continue
			best = maxi(best, int((ed.get("params", {}) as Dictionary).get("morale_bonus", 0)))
	return best


## Apply a resolved wound pair to the defender: Regeneration rolls only against the regen-able bucket
## (Bane / Rending / Lacerate / Unstoppable wounds bypass it — GF Advanced Rules v3.5.1: those rules
## "ignore Regeneration"), then everything lands through the normal wound machinery. Returns landed wounds.
func _solo_land_wounds(target: GameUnit, regenable: int, regen_proof: int, from_spell: bool = false) -> int:
	var landed: int = maxi(regen_proof, 0) + await _solo_apply_regeneration(target, regenable, from_spell)
	if landed > 0:
		_solo_apply_wounds(target, landed)
	return landed


## Deadly(X) landing (GF v3.5.1 p.14, no carry-over): each unsaved wound deals X to the alive model with
## the most remaining wounds (defender's casualty-minimising spread), capped at that model — excess lost.
## Regeneration rolls on the RAW unsaved wounds first (before the ×X), then the survivors multiply. Returns
## the wounds actually dealt (the melee comparison + summary). Own models only (hero spill = documented edge).
func _solo_land_deadly_wounds(target: GameUnit, weapon_name: String, deadly_x: int,
		regenable_unsaved: int, regen_proof_unsaved: int) -> int:
	var surviving: int = maxi(regen_proof_unsaved, 0) + await _solo_apply_regeneration(target, regenable_unsaved)
	if surviving <= 0:
		return 0
	var pid: int = int(target.unit_properties.get("player_id", 1))
	var on_changed := func(m: ModelInstance) -> void:
		if radial_menu_controller != null:
			radial_menu_controller._update_wound_marker(m)
		if network_manager != null and network_manager.has_method("broadcast_model_wounds"):
			network_manager.broadcast_model_wounds(m)
	var on_died := func(m: ModelInstance) -> void:
		if m.node != null and is_instance_valid(m.node):
			opr_army_manager.set_loose_model_dead(m.node, pid, true, target.unit_id)
		if network_manager != null and network_manager.has_method("broadcast_model_wounds"):
			network_manager.broadcast_model_wounds(m)
	var dealt: int = SoloController.apply_deadly_wounds(target, surviving, deadly_x, on_changed, on_died)
	if battle_log != null and dealt > 0:
		battle_log.log_event(BattleLog.Category.COMBAT, "Deadly(%d): %d unsaved ×%d, no carry-over → %d wound%s dealt" % [
			deadly_x, surviving, deadly_x, dealt, ("" if dealt == 1 else "s")], true)
	return dealt


## Bug 25 — land Takedown wounds on ONE chosen model (resolved as a unit of [1]): the AI attacker
## auto-picks the highest-value model; a human attacker is asked. Overkill past that model is lost
## (a unit of [1] has nowhere to spill). Returns the wounds that actually landed on the pool.
func _solo_land_takedown_wounds(attacker: GameUnit, target: GameUnit, weapon_name: String,
		regenable: int, regen_proof: int) -> int:
	var landed: int = maxi(regen_proof, 0) + await _solo_apply_regeneration(target, regenable)
	if landed <= 0:
		return 0
	var idx: int = SoloController.attacker_pick_model(target)
	if idx < 0:
		return 0
	if not _solo_is_ai_unit(attacker):
		idx = await _solo_prompt_takedown_model(target, weapon_name, idx)
	var pid: int = int(target.unit_properties.get("player_id", 1))
	var before: int = _solo_combined_alive(target)
	var on_changed := func(m: ModelInstance) -> void:
		if radial_menu_controller != null:
			radial_menu_controller._update_wound_marker(m)
		if network_manager != null and network_manager.has_method("broadcast_model_wounds"):
			network_manager.broadcast_model_wounds(m)
	var on_died := func(m: ModelInstance) -> void:
		if m.node != null and is_instance_valid(m.node):
			opr_army_manager.set_loose_model_dead(m.node, pid, true, target.unit_id)
		if network_manager != null and network_manager.has_method("broadcast_model_wounds"):
			network_manager.broadcast_model_wounds(m)
	SoloController.apply_wounds_to_model(target, idx, landed, on_changed, on_died)
	if battle_log != null:
		var killed: int = before - _solo_combined_alive(target)
		battle_log.log_event(BattleLog.Category.COMBAT, "Takedown (%s): snipes 1 model — %s" % [
			weapon_name, ("killed" if killed > 0 else "wounded")], true)
	return landed


## The human's Takedown model pick (GF v3.5.1 p.14) — B5 (test game 2, decided): a real CLICK on the
## model in the target unit (hero / upgrade bearer), not a two-option dialog. Right-click takes the
## EV-recommended model; the choice always gets its log line. Returns a model index.
func _solo_prompt_takedown_model(target: GameUnit, weapon_name: String, recommended: int) -> int:
	var alive: Array = []
	for i in range(target.models.size()):
		var m: ModelInstance = target.models[i]
		if m != null and m.is_alive:
			alive.append(i)
	if alive.size() <= 1:
		return recommended
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT,
			"Takedown (%s): CLICK the model in %s to snipe — right-click takes the recommended %s" % [
			weapon_name, target.get_name(), _solo_model_label(target, recommended)], false)
	_solo_model_pick = {"unit": target, "recommended": recommended, "outcome": []}
	var outcome: Array = _solo_model_pick["outcome"]
	while outcome.is_empty() and not _solo_model_pick.is_empty():
		await get_tree().process_frame
	_solo_model_pick = {}
	var idx: int = recommended if outcome.is_empty() or int(outcome[0]) < 0 else int(outcome[0])
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT, "Takedown (%s): snipes the %s in %s" % [
			weapon_name, _solo_model_label(target, idx), target.get_name()], false)
	return idx


## A short loadout label for a model (its distinctive weapon/equipment, else "trooper") — the Takedown
## picker's human-readable option text.
func _solo_model_label(unit: GameUnit, idx: int) -> String:
	if idx < 0 or idx >= unit.models.size():
		return "model"
	var m: ModelInstance = unit.models[idx]
	var weps: Array = m.properties.get("weapons", [])
	var equip: Array = m.properties.get("equipment", [])
	if int(m.wounds_max) > 1:
		return "Tough(%d) model" % int(m.wounds_max)
	if weps.size() > 1:
		return str((weps[weps.size() - 1] as Dictionary).get("name", "special weapon"))
	if not equip.is_empty():
		return str(equip[0])
	return "trooper"


## Whether wounds from this attacker+profile bypass the defender's Regeneration (GF Advanced Rules
## v3.5.1: Bane, Rending and Unstoppable "ignore Regeneration"; Lacerate is the AoF sibling).
## Conditional-AP weapon rules (Shatter/Tear/Melee Slayer/Disintegrate): the extra AP this weapon gets
## against THIS defender, summed over every such rule it carries. Fully registry-driven + system-scoped
## (params from the striker's book) so one reader serves them all; 0 when the weapon has none or the
## target fails the condition. Melee Slayer's charge gate reads `charging`.
func _solo_conditional_ap(profile: Dictionary, striker: GameUnit, defender: GameUnit, charging: bool,
		dist_in: float = -1.0, melee: bool = false) -> int:
	var bonus := 0
	for part in _solo_conditional_ap_parts(profile, striker, defender, charging, dist_in, melee):
		bonus += int((part as Dictionary)["bonus"])
	return bonus


## The NAMED contributions of the conditional-AP family against THIS defender — [{name, bonus}] with
## only the rules whose condition actually fired. One truth for the sum AND the transparency log
## (maintainer live-test lesson: a silent AP jump reads as a bug; see the Fortified line).
func _solo_conditional_ap_parts(profile: Dictionary, striker: GameUnit, defender: GameUnit, charging: bool,
		dist_in: float = -1.0, melee: bool = false) -> Array:
	if striker == null or defender == null:
		return []
	var system := RulesRegistry.system_of_unit(striker)
	var faction := RulesRegistry.faction_of_unit(striker)
	var d_tough := _solo_unit_tough(defender)
	var d_defense := int(defender.unit_properties.get("defense", 4))
	var parts: Array = []
	var seen := {}
	for r in profile.get("rules", []):
		var base := RulesRegistry.base_rule_name(str(r))
		seen[base] = true
		var params: Dictionary = RulesRegistry.lookup(system, faction, base).get("params", {})
		if params.has("condition"):
			var b := AiCombatMath.conditional_ap_bonus(params, d_tough, d_defense, charging, dist_in, melee)
			if b > 0:
				parts.append({"name": base, "bonus": b})
	# MODEL-level family members (Slayer / Piercing Hunter: "when this model shoots…") sit on the UNIT,
	# not the weapon — apply them once per profile too (deduped against the weapon's own rules).
	for r in striker.get_special_rules():
		var base := RulesRegistry.base_rule_name(str((r as Dictionary).get("name", "")) if r is Dictionary else str(r))
		if seen.has(base):
			continue
		seen[base] = true
		var params: Dictionary = RulesRegistry.lookup(system, faction, base).get("params", {})
		if params.has("condition"):
			var b := AiCombatMath.conditional_ap_bonus(params, d_tough, d_defense, charging, dist_in, melee)
			if b > 0:
				parts.append({"name": base, "bonus": b})
	return parts


## The on-6-to-hit AP bonus a weapon grants (the hits that roll an unmodified 6 save at a worse AP).
## Rending / Destructive use the fixed +4 (byte-identical fallback); the army-book Crack is a per-weapon
## value (+2) from the registry, system-scoped. 0 when the weapon has no on-6 AP rule.
func _solo_on6_ap_bonus(profile: Dictionary, striker: GameUnit) -> int:
	if bool(profile.get("rending", false)) or bool(profile.get("destructive", false)):
		return AiCombatMath.RENDING_AP_BONUS
	var system := RulesRegistry.system_of_unit(striker)
	var faction := RulesRegistry.faction_of_unit(striker)
	for r in profile.get("rules", []):
		var on6: int = int(RulesRegistry.lookup(system, faction, RulesRegistry.base_rule_name(str(r))).get("params", {}).get("on6_ap", 0))
		if on6 > 0:
			return on6
	return 0


func _solo_ignores_regen(attacker: GameUnit, profile: Dictionary) -> bool:
	var system := RulesRegistry.system_of_unit(attacker)
	var faction := RulesRegistry.faction_of_unit(attacker)
	for r in profile.get("rules", []):
		var s := str(r).strip_edges()
		if s.begins_with("Bane") or s.begins_with("Rending") or s.begins_with("Lacerate"):
			return true
		# Registry-driven Regeneration bypass (e.g. Disintegrate "Ignores Regeneration"), system-scoped;
		# the explicit name checks above remain the byte-identical fallback when the map is absent.
		# Coverage wave (skeptic flag): melee_only bypass entries ("Ignores Regeneration in Melee")
		# never fire on ranged profiles.
		var bp: Dictionary = RulesRegistry.lookup(system, faction, RulesRegistry.base_rule_name(s)).get("params", {})
		if bool(bp.get("bypass_regen", false)):
			if bool(bp.get("melee_only", false)) and int(profile.get("range", 0)) > 0:
				continue
			return true
	# Coverage wave: unit-level bypass aliases via the primitive layer ("Ignores Regeneration in
	# Melee" sits on the MODEL, not the weapon) — melee_only respected per profile.
	if attacker != null:
		for e in RulesRegistry.unit_rules_of_primitive(attacker, "Lacerate"):
			var ed := e as Dictionary
			if str(ed["name"]).begins_with("Lacerate"):
				continue
			var p2: Dictionary = ed.get("params", {})
			if bool(p2.get("bypass_regen", false)):
				if bool(p2.get("melee_only", false)) and int(profile.get("range", 0)) > 0:
					continue
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
## Shared truth in SoloController.combined_alive — the battle log's destroyed-check counts the SAME pool.
func _solo_combined_alive(unit: GameUnit) -> int:
	return SoloController.combined_alive(unit)


## One attributed roll in the real dice tray: set count + success target, roll, await, read the faces,
## then restore the player's previous tray settings.
func _solo_tray_roll(count: int, success_target: int, owner: String, roll_kind: String = "attack") -> Array:
	_next_roll_kind = roll_kind   # Bug 16: the dice-log line words saves as "defends … blocks"
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
	if _solo_batch:
		# Headless sweeps: skip the physics settle entirely. Draw fair faces from the SAME global RNG
		# stream that seeds the physics tray (seed(dice_seed), set post-deploy by the arena), then push
		# them through show_faces() — which fills per_dice_result() and emits roll_finnished synchronously.
		# ~20× faster at 2000pts, identical uniform 1-6 distribution, deterministic per dice_seed.
		var _inst: Array[int] = []
		for _di in maxi(1, count):
			_inst.append(randi_range(1, 6))
		dice_roller_control.show_faces(_inst)
	else:
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
	return await _solo_tray_roll(hits, defense + ap, "You", "defense")


## The unit's summed sight+range fan (the same one F toggles) — shared by the F-toggle and the
## automatic volley display (Bug 17). No-op headless (_solo_batch) and for weaponless units.
func _solo_show_fan_for_unit(fan_unit: GameUnit) -> void:
	if sight_fan_controller == null or fan_unit == null or _solo_batch or table == null:
		return
	var bonus_in: int = SoloController.shooting_range_bonus(fan_unit)
	var fan_ranges: Array = []
	for wpn in _solo_all_weapons(fan_unit):
		var r_in: int = AiArchetype.max_range_inches([wpn]) + bonus_in
		if r_in > bonus_in and not fan_ranges.has(r_in):
			fan_ranges.append(r_in)
	if fan_ranges.is_empty():
		return
	var half_w: float = table.table_size.x * 0.3048 / 2.0
	var half_d: float = table.table_size.y * 0.3048 / 2.0
	sight_fan_controller.show_fan_for(fan_unit, terrain_overlay, fan_ranges,
		Rect2(Vector2(-half_w, -half_d), Vector2(half_w * 2.0, half_d * 2.0)))
	_sight_fan_unit = fan_unit


## Clears the automatically shown volley fan (Bug 17) — a player-toggled fan (F) is cleared too;
## pressing F again brings it back, which beats a stale fan lingering over the next activation.
func _solo_clear_auto_fan() -> void:
	if sight_fan_controller != null and _sight_fan_unit != null:
		sight_fan_controller.clear_fan()
		_sight_fan_unit = null


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
	if _solo_batch:
		return
	var secs: float = SoloController.pace_seconds(phase, _solo_fast)
	if secs > 0.0:
		await get_tree().create_timer(secs).timeout


## The activation-choreography attention beat (SoloController.PACE_ATTENTION_S, Fast-AI-compressed) — the
## named ~2s pause the maintainer asked for between focus → corridors → glide → attacks (finding 7). A
## zero (never, at these constants) simply doesn't await, keeping the auto-tail responsive.
func _solo_pace_attention() -> void:
	if _solo_batch:
		return
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
	# Entrenched-family bookkeeping: any executed move stamps the unit's moved_round (the
	# stationary gate reads it; pile-in/consolidation count as moving per the rule's wording).
	if opr_army_manager != null:
		for mv0 in move_paths:
			var mi0 := (mv0 as Dictionary).get("model") as ModelInstance
			if mi0 != null and mi0.unit is GameUnit:
				(mi0.unit as GameUnit).unit_properties["moved_round"] = opr_army_manager.current_round
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
	"Shred", "Indirect", "Banner", "Musician", "Sergeant", "Limited", "Armor",
	# Army-book: Versatile Attack (>9" shooting — the AI picks the EV-better of AP(+1) or +1-to-hit via
	# AiEv.versatile_best_mode, one truth for the EV metric + the dice). Melee/charge facet is a follow-up.
	"Versatile Attack"]

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
	"Shred", "Indirect", "Banner", "Musician", "Sergeant", "Limited", "Armor",
	"Versatile Attack"]   # >9" AP(+1)/+1-to-hit mode choice steers the shoot EV


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
	# The snap spends REMAINING budget (maintainer 2026-07-22: path 6.0" + snap 0.9" = illegal 6.9").
	var snapped_ai: float = solo_controller.snap_charge(unit, target, solo_controller.last_move_remaining_in())
	if snapped_ai < 0.0:
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT,
				"%s's charge falls short (%.1f\" gap, move budget spent) — GF v3.5.1 p.8 'as close as possible'" % [unit.get_name(), -snapped_ai], true)
		return
	if snapped_ai > 0.05 and battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT,
			"%s charges into base contact (+%.1f\") — GF/AoF v3.5.1 p.8" % [unit.get_name(), snapped_ai], true)
	# PILE-IN (GF v3.5.1 p.9, live-test Bug 18 + NML-208): once the chargers stand, every defender
	# model without base contact MUST move up to 3" into contact — mandatory, so automated for both
	# sides, VISIBLY (the models glide; a teleport read as "nothing happened" in the live test).
	# Silent-correct reads as broken: a multi-model defender with nothing to do says so in the log.
	var pile_moves: Array = solo_controller.pile_in(target, unit)
	if not pile_moves.is_empty():
		await _solo_animate_move(pile_moves)
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT,
				"%s: %d model%s pile in up to 3\" (GF v3.5.1 p.9)" % [target.get_name(), pile_moves.size(), ("" if pile_moves.size() == 1 else "s")], true)
	elif _solo_combined_alive(target) > 1 and battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT,
			"%s: all models already in base contact — no pile-in needed (GF v3.5.1 p.9)" % target.get_name(), true)
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
			ai_caused += _solo_take_retaliate_credit()
	# — Impact(X) auto-hits fire BEFORE the normal strikes (GF/AoF v3.5.1 p.13; reduced by Counter models);
	#   applied + tallied inside. The charger may already be wiped by Counter — nothing left to roll then.
	#   human_defends is derived (false when the AI defends → saves auto-roll on the tray). —
	if _solo_combined_alive(unit) > 0:
		ai_caused += await _solo_charge_impact(unit, target, not defender_is_ai, float(report.get("charge_from_in", 0.0)))
	# Resolver wave A — vs-target Marks: the charger's pre-attack pick lands on this melee's defender.
	_solo_apply_vs_marks(unit, target, 0.0)
	# Unwieldy (resolver wave A — "strikes last when charging"): the CHARGER's strikes swap behind
	# the defender's strike-back; Counter and Impact keep their slots.
	var charger_last: bool = _solo_unit_has_unwieldy(unit)
	if charger_last and battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT, "Unwieldy: %s strikes last on the charge" % unit.get_name(), true)
	for phase_slot in range(2):
		if (phase_slot == 0) != charger_last:
			# — AI strikes (unit + attached heroes; only models within 2" strike; Deadly multiplies wounds). The AI
			#   is the charger here, so Furious/Thrust charge bonuses apply (charging = true) —
			if _solo_combined_alive(unit) > 0 and _solo_combined_alive(target) > 0:
				ai_caused += await _solo_melee_strike_phase(unit, target, true, SoloStrike.ALL, float(report.get("charge_from_in", 0.0)))
				human_caused += _solo_take_retaliate_credit()
				_solo_set_fatigued(unit)
		else:
			# — Strike back (the human's choice; OPR lets the defender strike back — unit + attached heroes). With
			#   Counter the choice was already made; only the NON-Counter weapons remain for this slot. —
			if _solo_combined_alive(target) > 0 and _solo_combined_alive(unit) > 0:
				if strike_back == -1:
					# B14 (test game 2): a defender with NO melee weapons cannot strike back — GF v3.5.1 has
					# no CCW fallback. No dialog, no phantom fatigue; the rule gets its log line instead.
					if _solo_attack_groups(target, 0.0, true, unit).is_empty():
						strike_back = 0
						if battle_log != null:
							battle_log.log_event(BattleLog.Category.COMBAT,
								"%s has no melee weapons — cannot strike back (GF v3.5.1)" % target.get_name(), defender_is_ai)
					else:
						strike_back = 1 if defender_is_ai or await _solo_confirm_strike_back(target, unit, false) else 0
				if strike_back == 1:
					human_caused += await _solo_melee_strike_phase(target, unit, false,
						SoloStrike.NON_COUNTER if counter_first else SoloStrike.ALL)
					ai_caused += _solo_take_retaliate_credit()
					_solo_set_fatigued(target)
	_solo_clear_announce(announce)
	# Resolver wave A — Self-Destruct survival half: "after both sides have finished attacking".
	await _solo_self_destruct_post_melee(unit, target)
	await _solo_self_destruct_post_melee(target, unit)
	# — Morale: the side that CAUSED more wounds wins; the loser tests (tie = nobody). Fear(X) (GF/AoF
	#   v3.5.1 p.13) counts as +X dealt wounds for THIS comparison only (never changes wounds applied) —
	var ai_score: int = AiCombatMath.fear_adjusted_wounds(ai_caused, _solo_unit_rating(unit, "Fear"))
	var human_score: int = AiCombatMath.fear_adjusted_wounds(human_caused, _solo_unit_rating(target, "Fear"))
	if ai_score > human_score and _solo_combined_alive(target) > 0:
		await _solo_morale_test(target, _solo_owner_label(target), true)   # MELEE loser — rout possible at half
	elif human_score > ai_score and _solo_combined_alive(unit) > 0:
		await _solo_morale_test(unit, _solo_owner_label(unit), true)   # MELEE loser
	# — Consolidation (GF v3.5.1 p.9, after morale): neither destroyed → the CHARGER (the AI here) moves
	#   back 1"; one side destroyed → the survivor consolidates up to 3" (round 7, finding 4) —
	await _solo_consolidate_melee(unit, target)
	# OUTCOME: one readable melee summary (toast + hold).
	await _solo_show_outcome("Melee: %s deals %d — takes %d back — %s loses %d model%s" % [
		unit.get_name(), ai_caused, human_caused, target.get_name(),
		target_models_before - _solo_combined_alive(target),
		("" if target_models_before - _solo_combined_alive(target) == 1 else "s")])


## Consolidation Moves (GF Advanced Rules v3.5.1 p.9 — wording verified in the official rulebook; the
## values are identical across GF/AoF/AoFS/GFF/AoFR v3.5.1, so no system scoping):
##   · NEITHER unit destroyed → the CHARGING unit must move back 1" (if possible) — the separation;
##   · ONE unit destroyed     → the OTHER unit may move by up to 3" — the winner consolidation.
## Round 7, finding 4: the winner consolidation was missing entirely. AI units take their move
## automatically (the 1" back-step is mandatory; the 3" "may" is EV-aware — toward an uncontrolled
## objective, else the next target — via consolidate_after_melee_win). The HUMAN's units are OFFERED the
## move instead (battle log + toast), consistent with the solo convention that the automation never moves
## the player's models; the player drags the models through the normal move flow.
func _solo_consolidate_melee(charger: GameUnit, defender: GameUnit) -> void:
	if solo_controller == null:
		return
	var charger_alive: bool = _solo_combined_alive(charger) > 0
	var defender_alive: bool = _solo_combined_alive(defender) > 0
	# Coverage wave — Defensive Frenzy: the survivor of a wiping melee earns its kill marker here
	# (every melee flow funnels through consolidation, so this is the one shared truth).
	if charger_alive and not defender_alive:
		_solo_growth_on_kill(charger)
		_solo_vengeance_on_destroyed(defender, charger)
	elif defender_alive and not charger_alive:
		_solo_growth_on_kill(defender)
		_solo_vengeance_on_destroyed(charger, defender)
	if charger_alive and defender_alive:
		if not _solo_is_ai_unit(charger):
			# The human charged: the mandatory 1" back-step is HIS move and the game WAITS for it
			# (field find 2026-07-23: the next activation used to start instantly — the step was
			# impossible). Non-exclusive: the board stays interactive while the dialog stands.
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT,
					"Consolidation: move %s back 1\" (the charger separates — GF v3.5.1 p.9)" % charger.get_name(), true)
			var dlg1 := AcceptDialog.new()
			dlg1.title = "Consolidation"
			dlg1.dialog_text = "%s: move the charger back 1\" now (GF v3.5.1 p.9).\nDrag the models, then click OK — the game waits." % charger.get_name()
			dlg1.exclusive = false
			add_child(dlg1)
			await _solo_await_confirm(dlg1, false)
			dlg1.queue_free()
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
		return
	if charger_alive == defender_alive:
		return   # both sides wiped — nobody left to consolidate
	var survivor: GameUnit = charger if charger_alive else defender
	if _solo_is_ai_unit(survivor):
		var dang2: int = solo_controller.consolidate_after_melee_win(survivor)
		if not solo_controller.last_move_paths.is_empty():
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT,
					"%s consolidates up to 3\" (enemy destroyed — GF v3.5.1 p.9)" % survivor.get_name(), true)
			await _solo_animate_move(solo_controller.last_move_paths)
		if dang2 > 0:
			await _run_ai_dangerous(survivor, dang2)
		_solo_flush_dev()
		return
	# The human's unit survived a melee that destroyed the enemy: the flow WAITS here (live-test
	# Bug 21 — "ich muss mich erst bewegen, dann darf er weitermachen"). Non-exclusive dialog: the
	# player drags his models up to 3" while it is open, then confirms; only then does the game go on.
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT,
			"Consolidation: %s may move up to 3\" (enemy destroyed — GF v3.5.1 p.9)" % survivor.get_name(), false)
	var dlg := AcceptDialog.new()
	dlg.title = "Consolidation"
	dlg.dialog_text = "%s destroyed the enemy in melee.\nYou may move the unit up to 3\" now (GF v3.5.1 p.9).\nClick OK when you are done — the game waits." % survivor.get_name()
	dlg.exclusive = false   # the board stays interactive: drag the models, then confirm
	add_child(dlg)
	await _solo_await_confirm(dlg, false)   # order-proof; NON-exclusive — the drag must stay possible
	dlg.queue_free()


## One OPR morale test with a real tray die: >= Quality passes; fail → Shaken, at/below half → Routs
## (the unit is destroyed through the existing kill flows).
## OPR rule gap (goal 003 P1): a unit that takes CASUALTIES FROM SHOOTING and is now at half strength or
## less must test morale — this trigger was missing entirely (morale only ran after melee). Compares the
## unit's own alive count before vs after the volley; `owner` attributes the tray roll (the AI rolls for
## its own units, "You" for the human's). No-op if the unit was wiped or took no casualties.
func _solo_shooting_morale(unit: GameUnit, alive_before: int, owner: String, wounds_before: int = -1) -> void:
	if unit == null:
		return
	# Single-model units measure morale in TOUGH WOUNDS, not models (GF v3.5.1 p.10: "...half or less
	# of its starting size or tough value (for units with a single model)" — maintainer 2026-07-22:
	# a wounded Tough single model never tested because only model DEATH triggered).
	if SoloController.combined_total(unit) == 1 and unit.get_alive_count() > 0:
		var wounds_now := _solo_unit_wounds_now(unit)
		if wounds_before >= 0 and wounds_now < wounds_before \
				and AiCombatMath.at_or_below_half(wounds_now, _solo_unit_wounds_start(unit)):
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT,
					"%s is at half its tough value (%d/%d) — morale test (GF v3.5.1 p.10)" % [
					unit.get_name(), wounds_now, _solo_unit_wounds_start(unit)], true)
			await _solo_morale_test(unit, owner)
		return
	if AiCombatMath.should_test_shooting_morale(alive_before, unit.get_alive_count(), unit.models.size()):
		await _solo_morale_test(unit, owner)


## Combined CURRENT wounds of a unit's alive models incl. joined heroes (the p.10 tough-value scale).
func _solo_unit_wounds_now(unit: GameUnit) -> int:
	var total := 0
	for m in unit.models:
		var mi := m as ModelInstance
		if mi != null and mi.is_alive:
			total += mi.wounds_current
	if unit.has_method("get_attached_heroes"):
		for h in unit.get_attached_heroes():
			var hu := h as GameUnit
			if hu != null:
				for m in hu.models:
					var mi := m as ModelInstance
					if mi != null and mi.is_alive:
						total += mi.wounds_current
	return total


## The unit's STARTING wounds pool (sum of wounds_max over all models incl. joined heroes) — p.10
## "starting size is counted at the beginning of the game".
func _solo_unit_wounds_start(unit: GameUnit) -> int:
	var total := 0
	for m in unit.models:
		var mi := m as ModelInstance
		if mi != null:
			total += mi.wounds_max
	if unit.has_method("get_attached_heroes"):
		for h in unit.get_attached_heroes():
			var hu := h as GameUnit
			if hu != null:
				for m in hu.models:
					var mi := m as ModelInstance
					if mi != null:
						total += mi.wounds_max
	return total


## Half-strength predicate for morale outcomes: single-model units measure in tough WOUNDS (p.10);
## multi-model units count MODELS — the COMBINED size of the joined unit (GF/AoF v3.5.1 p.14: a unit
## with an attached hero measures half strength over unit + hero together, not its own models —
## NML-008: the own-models count wrongly Routed a unit whose hero still stood, and vice versa).
func _solo_below_half_strength(unit: GameUnit) -> bool:
	if SoloController.combined_total(unit) == 1:
		return AiCombatMath.at_or_below_half(_solo_unit_wounds_now(unit), _solo_unit_wounds_start(unit))
	return AiCombatMath.at_or_below_half(SoloController.combined_alive(unit), SoloController.combined_total(unit))


## `melee`: ROUT exists ONLY in melee morale tests (GF v3.5.1, PDF-verified — Windows playtest bug 9:
## "If the test is failed, the unit is Shaken" for GENERAL tests; only the MELEE section adds "and the
## unit only has half or less … then the unit Routs". A shooting-caused failure at half strength wrongly
## wiped whole units before).
func _solo_morale_test(unit: GameUnit, owner: String, melee: bool = false) -> void:
	var below_half := _solo_below_half_strength(unit)   # single models: tough-wounds scale (p.10)
	var result: int
	if unit.is_shaken:
		# A unit that is ALREADY Shaken auto-fails any further morale test (GF/AoF v3.5.1 p.10: "Shaken
		# units … always fail morale tests") — no Quality roll. At half or less this Routs it; otherwise it
		# stays Shaken (field-test finding 8: a Shaken unit was rolling — and could pass — a repeat test).
		result = AiCombatMath.morale_result_shaken(below_half and melee)
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT,
				"%s is already Shaken — automatically fails morale (GF/AoF v3.5.1 p.10)" % unit.get_name(), true)
	else:
		# Banner (wave 5, system-scoped params via RulesRegistry: +1 to morale test rolls; the GFF/AoFS
		# picked-units variant still covers the bearer's own unit) lowers the roll target, clamped to
		# [2,6] (a natural 1 always fails). Without Banner this is the plain Quality target.
		var morale_bonus: int = _solo_morale_bonus(unit)
		# NML-006 morale_mod: active spell tokens ("+1/-1 to morale test rolls", once) join the
		# Banner bonus in the [2,6]-clamped target; spent right after the test die (rules-must-log).
		var spell_morale := 0
		var morale_notes: PackedStringArray = []
		for mrd in AiSpell.mods_for(_solo_mods_of_chain(unit), "morale", melee):
			spell_morale += int((mrd as Dictionary).get("morale_mod", 0))
			morale_notes.append("%s %+d" % [str((mrd as Dictionary).get("spell", "")),
				int((mrd as Dictionary).get("morale_mod", 0))])
		var test_target: int = AiCombatMath.morale_target(unit.get_quality(), morale_bonus + spell_morale)
		if morale_bonus > 0 and battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "Banner: %s gets +%d to morale test rolls (passes on %d+)" % [
				unit.get_name(), morale_bonus, test_target], true)
		if spell_morale != 0 and battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "%s: %+d to morale test rolls — %s passes on %d+" % [
				", ".join(morale_notes), spell_morale, unit.get_name(), test_target], true)
		var faces: Array = await _solo_tray_roll(1, test_target, owner)
		_solo_spend_once_kind(unit, ["morale"])   # NML-006: spent by this test
		if faces.is_empty():
			return
		result = AiCombatMath.morale_result(int(faces[0]), test_target, below_half and melee)
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
	# No Retreat (quick-win batch; official text: a failed morale test that causes Shaken/Rout "counts
	# as passed instead. Then, roll as many dice as the number of wounds it would take to fully destroy
	# it, and for each result of 1-3 the unit takes one wound, which can't be ignored."): the pass is
	# paid in self-wounds rolled visibly on the real tray (a 4+ is "safe", so the tray highlights the
	# harmless faces); the wounds land via _solo_apply_wounds DIRECTLY — Regeneration/Resistance never
	# roll ("can't be ignored"). Checked AFTER Fearless (the free rescue first, the paid one only if
	# still failed); registry-gated the wave-5 way so it only fires where the unit's book fields it.
	if result != AiCombatMath.Morale.PASSED and RulesRegistry.unit_rule_active(unit, "No Retreat"):
		var wound_max: int = int(RulesRegistry.unit_param(unit, "No Retreat", "self_wound_max", AiCombatMath.NO_RETREAT_SELF_WOUND_MAX))
		var dice_n: int = maxi(1, SoloController.wounds_to_destroy(unit))
		var nr_faces: Array = await _solo_tray_roll(dice_n, wound_max + 1, owner)
		var self_wounds: int = AiCombatMath.no_retreat_wounds(nr_faces, wound_max)
		result = AiCombatMath.Morale.PASSED
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "%s has No Retreat — the test counts as passed; %d self-wound%s (1-%d on %d dice, can't be ignored)" % [
				unit.get_name(), self_wounds, ("" if self_wounds == 1 else "s"), wound_max, dice_n], true)
		if self_wounds > 0:
			_solo_apply_wounds(unit, self_wounds)
	match result:
		AiCombatMath.Morale.PASSED:
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s passes morale" % unit.get_name())
		AiCombatMath.Morale.SHAKEN:
			if not unit.is_shaken and radial_menu_controller != null:
				radial_menu_controller.card_toggle_shaken(unit)   # state + marker + MP broadcast
				_solo_mirror_shaken(unit)   # the joined hero shares the unit's state (p.14), no 2nd token
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s fails morale — Shaken" % unit.get_name())
		AiCombatMath.Morale.ROUT:
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s fails morale at half strength — ROUTS" % unit.get_name())
			_solo_apply_wounds(unit, unit.models.size() * 12)   # overkill wipes the unit via the normal flows


# === Solo P8: the player's own attack flow (radial "Shoot"/"Fight" → targeting mode → tray dice) ===

## Radial gate: Shoot/Fight show on units that are NOT the AI's while an AI opponent with living units
## exists (goal 001 P8). X1 (test game 2): an ACTIVATED unit gets no combat entries — one activation
## per round is the alternation's whole currency, and the open radial was the double-shoot exploit.
func solo_combat_available(unit: GameUnit) -> bool:
	var u := _solo_combat_unit(unit)
	if u == null or opr_army_manager == null or _solo_is_ai_unit(u):
		return false
	if u.is_activated:
		return false
	for au in opr_army_manager.get_game_units_for_player(_solo_ai_slot()):
		if au != null and au.get_alive_count() > 0:
			return true
	return false


## The pre-attack cast-window ask (decision "Vorfrage"): true → the player casts first. Asked at
## most once per unit per round, and only when the unit's caster can actually afford a spell.
var _solo_cast_asked: Dictionary = {}   # instance_id → round the ask happened


func _solo_confirm_cast_first(unit: GameUnit) -> bool:
	if opr_army_manager == null:
		return false
	var rnd: int = opr_army_manager.current_round
	if int(_solo_cast_asked.get(unit.get_instance_id(), -1)) == rnd:
		return false
	var member := RadialMenu._caster_member_of(unit)
	if member == null:
		return false
	var spells: Array = SpellsRegistry.spells_for_unit(member)
	if spells.is_empty():
		spells = SpellsRegistry.spells_for_unit(unit)
	var affordable := false
	for sp in spells:
		if int((sp as Dictionary).get("threshold", 99)) <= member.casts_current:
			affordable = true
			break
	if not affordable:
		return false
	_solo_cast_asked[unit.get_instance_id()] = rnd
	var dlg := ConfirmationDialog.new()
	dlg.title = "Cast window"
	dlg.dialog_text = "%s can still cast (%d token%s left).\nSpells must be cast BEFORE attacking (GF v3.5.1) — after this attack the window is gone." % [
		member.get_name(), member.casts_current, ("" if member.casts_current == 1 else "s")]
	dlg.ok_button_text = "Cast first"
	dlg.get_cancel_button().text = "Attack without casting"
	add_child(dlg)
	var cast_first: bool = await _solo_await_confirm(dlg)
	dlg.queue_free()
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL,
			("%s casts before attacking" if cast_first else "%s attacks — cast window passed") % unit.get_name(), false)
	return cast_first


## X1: combat intents from an attached hero resolve to its HOST — the joined unit fights as ONE
## (GF v3.5.1 "Hero"). The hero's model menu handed the hero's OWN GameUnit to the combat flow, so it
## fired alone and then AGAIN inside the unit's volley (test game 2, B16). Same resolution as
## _solo_pick_unit_at uses for targets.
func _solo_combat_unit(unit: GameUnit) -> GameUnit:
	if unit != null and unit.has_method("is_attached") and unit.is_attached():
		var host: Variant = unit.get_attached_to()
		if host is GameUnit:
			return host
	return unit


func _solo_is_ai_unit(unit: GameUnit) -> bool:
	var pid: int = int(unit.unit_properties.get("player_id", 0))
	return solo_ai_slots.has(pid) or (solo_ai_slots.is_empty() and pid == _solo_ai_slot())


## Enter targeting mode (P8): the weapon range shows as a ring, the line of sight to the hovered enemy
## draws live (green = clear, red = blocked); LMB on a valid AI unit resolves the attack, RMB/ESC cancels.
func solo_begin_targeting(unit: GameUnit, melee: bool) -> void:
	unit = _solo_combat_unit(unit)   # X1: a joined hero's intent belongs to its host unit
	if unit == null:
		return
	# X1 belt-and-braces for a stale radial: the menu may have been built before the unit activated.
	if unit.is_activated:
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.GENERAL,
				"%s has already activated this round — one activation per unit (GF v3.5.1)" % unit.get_name())
		return
	# Cast-window guard (maintainer decision "Vorfrage" 2026-07-23): spells go BEFORE the attack
	# ("at any point before attacking" — GF v3.5.1 Caster(X)) and the attack COMPLETES the
	# activation (X1), so a shoot click would silently burn the cast window. ONE ask per unit per
	# round, only when a spell is actually affordable; "Cast first" opens the spell flow — the
	# attack stays available afterwards (click Shoot/Fight again).
	if await _solo_confirm_cast_first(unit):
		solo_begin_cast(unit)
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


## Spell wave F2 — the human cast flow entry (radial "Cast"): spell picker (live army-book text,
## affordability-gated) -> targeting mode "cast" with the LEGAL candidates precomputed -> click a
## target -> boost tableau -> AI counter-interference (shown AFTER commit, rules-sequential) ->
## the shared cast resolver rolls on the real tray and auto-applies damage/tokens.
func solo_begin_cast(unit: GameUnit) -> void:
	unit = _solo_combat_unit(unit)   # X1: a joined caster hero casts as part of its host unit
	if unit == null or _solo_is_ai_unit(unit):
		return
	if unit.is_activated:
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.GENERAL,
				"%s has already activated this round — one activation per unit (GF v3.5.1)" % unit.get_name())
		return
	_ensure_solo_controller()
	var member := RadialMenu._caster_member_of(unit)
	if member == null:
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.GENERAL, "%s has no caster with spell tokens" % unit.get_name())
		return
	var spells: Array = SpellsRegistry.spells_for_unit(member)
	if spells.is_empty():
		spells = SpellsRegistry.spells_for_unit(unit)
	if spells.is_empty():
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.GENERAL,
				"%s: no spell data for this faction yet — cast manually" % unit.get_name())
		return
	# Live army-book effect text per spell (runtime import data — never committed).
	var live_text := {}
	if opr_army_manager != null and opr_army_manager.has_method("get_spells_for_unit"):
		for sp in opr_army_manager.get_spells_for_unit(member):
			live_text[str((sp as Dictionary).get("name", ""))] = str((sp as Dictionary).get("effect", ""))
	var entries: Array = []
	for sp in spells:
		var e := sp as Dictionary
		entries.append({"entry": e, "text": str(live_text.get(str(e.get("name", "")), "")),
			"enabled": member.casts_current >= int(e.get("threshold", 1))})
	var picker := SpellPickerDialog.new()
	add_child(picker)
	var entry: Dictionary = await picker.pick(member.get_name(), member.casts_current, entries)
	if entry.is_empty():
		return
	var cands: Array = solo_controller.spell_candidates(unit, entry,
		solo_controller.human_slot, solo_controller.ai_slot)
	if cands.is_empty():
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.GENERAL, "%s: no legal target for %s in %s\" + line of sight" % [
				unit.get_name(), str(entry.get("name", "?")), str(entry.get("range_in", 0))])
		return
	# NML-206 (maintainer live test: "ich konnte keine legitimen Ziele auswählen" — the promised
	# SHOW of legal targets was missing): every candidate gets a looping pulse ring while the
	# targeting mode is active — green for friendly buffs, amber for enemy targets. Freed with the
	# targeting mode (_solo_end_targeting).
	var side := str((entry.get("target", {}) as Dictionary).get("side", "enemy"))
	var ring_col := Color(0.3, 0.9, 0.4) if side == "friendly" else Color(1.0, 0.7, 0.2)
	var cand_rings: Array = []
	for cu in cands:
		cand_rings.append(_solo_spawn_pulse_ring(solo_controller.unit_centre(cu), ring_col))
	_solo_target_mode = {"unit": unit, "cast_entry": entry, "cast_member": member,
		"cast_valid": cands, "cast_rings": cand_rings}
	if range_ring_controller != null and range_ring_controller.has_method("show_spell_preview"):
		range_ring_controller.show_spell_preview(_solo_unit_nodes(unit), float(entry.get("range_in", 0)))
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL, "%s: pick a %s target for %s (%d marked in range) — right-click cancels" % [
			unit.get_name(), side, str(entry.get("name", "?")), cands.size()])


## Execute the picked human cast (async; fired from the targeting click).
func _run_human_cast(unit: GameUnit, member: GameUnit, entry: Dictionary, first_target: GameUnit) -> void:
	var spell_name := str(entry.get("name", "?"))
	var threshold := int(entry.get("threshold", 1))
	if not member.spend_caster_points(threshold):
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.GENERAL, "%s: not enough tokens for %s" % [member.get_name(), spell_name])
		return
	if network_manager != null and network_manager.has_method("broadcast_unit_casts"):
		network_manager.broadcast_unit_casts(member)
	# Multi-target spells: the player picked the FIRST target; the rest auto-fill nearest-first
	# from the legal set (v1 simplification — logged so the choice is visible).
	var targets: Array = [first_target]
	var count := maxi(int((entry.get("target", {}) as Dictionary).get("count", 1)), 1)
	if count > 1:
		var rest: Array = []
		for cu in solo_controller.spell_candidates(unit, entry, solo_controller.human_slot, solo_controller.ai_slot):
			if cu != first_target:
				rest.append(cu)
		var from := solo_controller.unit_centre(first_target)
		rest.sort_custom(func(a, b) -> bool:
			return MoveIntent.distance_inches(from, solo_controller.unit_centre(a)) 				< MoveIntent.distance_inches(from, solo_controller.unit_centre(b)))
		for cu in rest.slice(0, count - 1):
			targets.append(cu)
		if targets.size() > 1 and battle_log != null:
			battle_log.log_event(BattleLog.Category.GENERAL, "%s hits %d targets: %s" % [
				spell_name, targets.size(), _solo_cast_target_label(targets)])
	# BOOST tableau (own helpers in 18" LoS; the member's remaining tokens count via the pool).
	var boost := 0
	var helpers: Array = solo_controller._aura_casters(solo_controller.human_slot, unit, null)
	var pool := 0
	for h in helpers:
		pool += int((h as Dictionary)["tokens"])
	if pool > 0:
		var dlg := InterferenceDialog.new()
		add_child(dlg)
		boost = await dlg.ask(member.get_name(), spell_name, _solo_cast_target_label(targets),
			AiSpell.CAST_BASE_TARGET, 0, pool, "boost")
		if boost > 0:
			for d in SoloController._draw_aura_tokens(helpers, boost):
				var dd := d as Dictionary
				var payer := dd["unit"] as GameUnit
				for i in range(int(dd["tokens"])):
					payer.spend_caster_points(1)
				if network_manager != null and network_manager.has_method("broadcast_unit_casts"):
					network_manager.broadcast_unit_casts(payer)
	# AI COUNTER-INTERFERENCE (decided default: shown AFTER the player commits — rules-sequential,
	# no leak): the AI's 18"-LoS pool spends per the marginal calculus, value-proxied by the cost.
	var interference := 0
	var ai_helpers: Array = solo_controller._aura_casters(solo_controller.ai_slot, unit, null)
	var ai_pool := 0
	for h in ai_helpers:
		ai_pool += int((h as Dictionary)["tokens"])
	if ai_pool > 0:
		interference = AiSpell.plan_interference(float(threshold), ai_pool, boost)
		if interference > 0:
			for d in SoloController._draw_aura_tokens(ai_helpers, interference):
				var dd := d as Dictionary
				var payer := dd["unit"] as GameUnit
				for i in range(int(dd["tokens"])):
					payer.spend_caster_points(1)
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT,
					"NACHTMAHR interferes with %d token%s — your cast roll worsens to %d+" % [
					interference, ("" if interference == 1 else "s"),
					AiSpell.cast_target(boost, interference, AiSpell.CAST_BASE_TARGET)], true)
	_solo_refresh_caster_markers()
	await _solo_resolve_one_cast({"caster": member, "caster_unit": unit, "spell": entry,
		"name": spell_name, "targets": targets, "boost": boost, "interference": interference,
		"base_target": AiSpell.CAST_BASE_TARGET, "threshold": threshold,
		"owner_label": "You", "human_cast": true})


func _solo_end_targeting() -> void:
	_solo_clear_announce(_solo_target_mode.get("cast_rings", []))   # NML-206 candidate markers off
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
			# Spell wave F2: cast mode accepts any unit from the precomputed LEGAL set (friendly-side
			# spells target OWN units — the attack-path AI-only filter below must not run).
			if _solo_target_mode.has("cast_entry"):
				if target == null:
					return true
				var cvalid: Array = _solo_target_mode.get("cast_valid", [])
				if not cvalid.has(target):
					if battle_log != null:
						battle_log.log_event(BattleLog.Category.GENERAL,
							"%s is not a legal target (side, range or line of sight)" % target.get_name())
					return true
				var centry: Dictionary = _solo_target_mode.get("cast_entry", {})
				var cmember: GameUnit = _solo_target_mode.get("cast_member")
				_solo_end_targeting()
				_run_human_cast(attacker, cmember, centry, target)
				return true
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
	# B5: an active Takedown model pick owns the mouse first — one click chooses the sniped model.
	if not _solo_model_pick.is_empty():
		if _solo_model_pick_input(event):
			get_viewport().set_input_as_handled()
		return
	if _solo_target_mode.is_empty():
		return
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if _solo_targeting_input(event):
		get_viewport().set_input_as_handled()


## B5 (test game 2, decided: Ziel-MODELL-Pick): while a Takedown pick is active, LMB on an alive
## model of the pick's unit chooses IT; right-click takes the recommended model. Returns true when
## the event was consumed (every mouse press is, so a stray click can't fall through to the table).
func _solo_model_pick_input(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return false
	var outcome: Array = _solo_model_pick.get("outcome", [])
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		outcome.append(int(_solo_model_pick.get("recommended", -1)))
		return true
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return false
	var unit := _solo_model_pick.get("unit") as GameUnit
	var camera := get_viewport().get_camera_3d()
	if unit == null or camera == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(
		camera.project_ray_origin(mb.position),
		camera.project_ray_origin(mb.position) + camera.project_ray_normal(mb.position) * 100.0)
	var hit: Dictionary = get_viewport().world_3d.direct_space_state.intersect_ray(query)
	var col: Object = hit.get("collider")
	if col is Node and (col as Node).has_meta("model_instance"):
		var mi := (col as Node).get_meta("model_instance") as ModelInstance
		if mi != null and mi.is_alive and mi.unit == unit:
			outcome.append(mi.model_index)
	return true


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
	# B11 (test game 2): the refusal message measures base-EDGE to base-edge between the NEAREST
	# model pair — the same figure the ruler shows (the old unit-centre distance disagreed with the
	# player's own measurement by both base radii, ~5" on large bases).
	var dist := solo_controller.nearest_melee_gap_in(attacker, target)
	if dist == INF:
		dist = MoveIntent.distance_inches(solo_controller.unit_centre(attacker), solo_controller.unit_centre(target))
	var rng_in: int = AiArchetype.max_range_inches(_solo_all_weapons(attacker)) + SoloController.shooting_range_bonus(attacker)
	if rng_in <= 0:
		return "no ranged weapons"
	# Aircraft (-12") and Ranged Shrouding (-6" min 6") shorten the reach against THIS target — the
	# validity message names the shrunk figure AND the rule that shrank it (B11: no hidden penalty).
	var raw_rng: int = rng_in
	rng_in = int(SoloController.effective_shoot_reach_in(float(rng_in), target))
	if rng_in <= 0 or _solo_sighted_count(attacker, target, rng_in) <= 0:
		if dist > float(rng_in):
			var why := ""
			if rng_in < raw_rng:
				var causes: PackedStringArray = []
				if SoloController.target_range_penalty_in(target) > 0.0:
					causes.append("Aircraft -12\"")
				if AiEv.rule_on_all_models(target, "Ranged Shrouding"):
					causes.append("Ranged Shrouding")
				why = " — %s" % ", ".join(causes)
			return "out of range (%.1f\" edge to edge > %d\"%s)" % [dist, rng_in, why]
		return "no model has line of sight"
	return ""


func _solo_has_los(a: GameUnit, b: GameUnit) -> bool:
	if terrain_overlay == null or not terrain_overlay.has_method("has_line_of_sight"):
		return true
	# NML-005 step 3: the REAL unit height categories (same source as the shooting path) instead
	# of the old hardcoded 1/1 — melee display and breath targeting now judge like the dice do
	# (a tall walker sees over what a trooper cannot, and vice versa).
	return terrain_overlay.has_line_of_sight(solo_controller.unit_centre(a), solo_controller.unit_centre(b),
		_solo_unit_los_height(a), _solo_unit_los_height(b))


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
		# PILE-IN (GF v3.5.1 p.9, live-test Bug 18 + NML-208): the defender here is the AI's unit — its
		# mandatory 3" pile-in is automated and now GLIDES visibly (teleport read as "nothing happened").
		var pile_moves: Array = solo_controller.pile_in(target, attacker)
		if not pile_moves.is_empty():
			await _solo_animate_move(pile_moves)
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT,
					"%s: %d model%s pile in up to 3\" (GF v3.5.1 p.9)" % [target.get_name(), pile_moves.size(), ("" if pile_moves.size() == 1 else "s")], true)
		elif _solo_combined_alive(target) > 1 and battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT,
				"%s: all models already in base contact — no pile-in needed (GF v3.5.1 p.9)" % target.get_name(), true)
		await _run_human_melee(attacker, target)
		# Hit & Run (cut C): "being in melee" covers the DEFENDER too — the AI's charged unit may take
		# its once-per-round 3" step after the melee resolves (the human's own bearers move manually).
		# after_shoot=false: the melee leg (covers the Fighter half, never the Shooter half).
		if target != null and not target.is_destroyed() and solo_controller.hit_and_run_move(target, false):
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.MOVEMENT, "Hit & Run: %s steps up to 3\" out of the melee" % target.get_name(), true)
			await _solo_retreating_strike(target)   # resolver wave A: the post-melee step may lash out
	else:
		await _run_human_shooting(attacker, target)
	# X1 (test game 2, double-shoot exploit): a resolved attack IS the unit's activation — it completes
	# for SURVIVORS and wiped units alike. The old rule auto-completed only wiped attackers (finding 5);
	# a surviving shooter stayed un-activated and the radial happily offered a second volley. The card
	# toggle path does the full job (GameUnit.activate marks host + heroes, marker, MP broadcast, log,
	# alternation reply via unit_activated). A pre-toggled unit falls through to the normal pump so a
	# mis-click fix never queues a second AI answer.
	if attacker != null and SoloController.human_attack_completes_activation(attacker.is_activated):
		if radial_menu_controller != null:
			radial_menu_controller.card_toggle_activation(attacker)   # state + heroes + marker + MP + reply
			await _solo_pump()
		else:
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
## Bug 13 — the Versatile mode dialog for the player's own volley: OK/Enter takes the EV-recommended
## mode, the cancel button holds the other one, so a quick confirm never plays worse than the old
## auto-pick but the CHOICE is the player's (Versatile is "pick one", not an engine decision).
func _solo_prompt_versatile(weapon_name: String, recommended: Dictionary) -> Dictionary:
	var rec_ap := int(recommended.get("ap", 0)) > 0
	var dlg := ConfirmationDialog.new()
	dlg.title = "Versatile Attack"
	dlg.dialog_text = "%s is Versatile (target over 9\").\nChoose the mode for this volley:" % weapon_name
	dlg.ok_button_text = ("AP(+1)  — recommended" if rec_ap else "+1 to hit  — recommended")
	dlg.get_cancel_button().text = ("+1 to hit" if rec_ap else "AP(+1)")
	add_child(dlg)
	var take_recommended: bool = await _solo_await_confirm(dlg)   # order-proof (see _solo_await_confirm)
	dlg.queue_free()
	if take_recommended:
		return recommended
	return {"ap": 0, "hit_mod": 1} if rec_ap else {"ap": 1, "hit_mod": 0}


func _run_human_shooting(attacker: GameUnit, target: GameUnit) -> void:
	# B11: ONE measuring truth — the shot distance (feeding the >9" Versatile/Guarded gates and the
	# profile range gate's fallback) is the base-EDGE gap of the nearest model pair, like the ruler.
	var dist := solo_controller.nearest_melee_gap_in(attacker, target)
	if dist == INF:
		dist = MoveIntent.distance_inches(solo_controller.unit_centre(attacker), solo_controller.unit_centre(target))
	# B11: range penalties against THIS target are NAMED, never silently folded into the gate.
	if battle_log != null and SoloController.target_range_penalty_in(target) > 0.0:
		battle_log.log_event(BattleLog.Category.COMBAT,
			"%s is an Aircraft: weapon ranges count -12\" against it (GF v3.5.1)" % target.get_name(), true)
	if battle_log != null and AiEv.rule_on_all_models(target, "Ranged Shrouding"):
		battle_log.log_event(BattleLog.Category.COMBAT,
			"%s has Ranged Shrouding: weapon ranges -6\" (min 6\") against it" % target.get_name(), true)
	var target_alive_before: int = target.get_alive_count()   # post-shooting morale (goal 003 P1)
	var target_wounds_before: int = _solo_unit_wounds_now(target)
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
	# Guarded / Versatile Defense's def-half: the human shooting from over 9" honours the +1 Defense
	# too — both directions read the same rule (the shot distance is known here).
	var h_over9 := _solo_over9_defense_rule(target)
	if not h_over9.is_empty() and dist > AiCombatMath.LONG_RANGE_IN:
		shielded_def = AiCombatMath.guarded_defense(shielded_def, true)
		if battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT, "%s (%s): shot from over 9\" — +1 Defense (saves on %d+)" % [
				target.get_name(), h_over9, shielded_def], true)
	var covered_def: int = _solo_cover_defense(target, shielded_def)
	# Resolver wave A parity: your volley places vs-target Marks, SPENDS Piercing-Tag markers and
	# honours the Reckless-Piercing AP stamps — the AI path had these seams, yours silently didn't.
	_solo_apply_vs_marks(attacker, target, dist)
	var extra_ap := _solo_spend_piercing_tag(target) + _solo_reckless_ap(attacker, target)
	# Per-model shooting transparency (GF v3.5.1 p.8): tell the player how many models actually fire.
	if battle_log != null:
		var rng_in: int = AiArchetype.max_range_inches(_solo_all_weapons(attacker))
		var total := _solo_combined_alive(attacker)
		battle_log.log_event(BattleLog.Category.COMBAT, "%s: %d/%d model%s with line of sight + range" % [
			attacker.get_name(), _solo_sighted_count(attacker, target, rng_in), total, ("" if total == 1 else "s")], true)
	var fired_any := false   # round 7, finding 5: a volley that rolls NOTHING must say so, never end silently
	var chosen_versatile: Dictionary = {}   # Bug 13: per-weapon Versatile choice, asked once per volley
	# Unpredictable (generic, "when attacking"): the HUMAN's volley rolls the same visible die —
	# 1-3 → AP(+1), 4-6 → +1 to hit on every profile (resolution-integrated, both sides automatic).
	var upr_ap := 0
	var upr_hit := 0
	var upr_name := _solo_unpredictable_rule(attacker, false)
	if not upr_name.is_empty():
		var upr_face: Array = await _solo_tray_roll(1, AiCombatMath.BEST_HIT_TARGET, "You")
		if not upr_face.is_empty():
			var upr_eff: Dictionary = AiCombatMath.unpredictable_fighter_effect(int(upr_face[0]))
			upr_ap = int(upr_eff["ap"])
			upr_hit = int(upr_eff["hit"])
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s: %s rolls %d → %s" % [
					upr_name, attacker.get_name(), int(upr_face[0]), ("AP(+1)" if upr_ap > 0 else "+1 to hit")], true)
	# Resolver wave A — Takedown Shot: your once-per-game extra attack joins the volley too.
	var h_groups: Array = _solo_attack_groups(attacker, dist, false, target)
	if not h_groups.is_empty():
		h_groups = h_groups + _solo_takedown_bonus_groups(attacker, false)
	for grp in h_groups:
		var group := grp as Dictionary
		var base_quality: int = int(group.get("quality", 4))
		var mod_info: Dictionary = _solo_hit_mod_info(group.get("member"), target, dist, false)
		for p in group.get("profiles", []):
			var profile := _solo_bridge_granted_flags(group.get("member"), p as Dictionary)
			if int(profile.get("attacks", 0)) <= 0:
				continue
			fired_any = true
			# Reliable sets the Quality (2+), THEN the roll modifiers apply (GF v3.5.1 p.14: "Reliable only
			# changes the Quality value, so the roll can still be modified").
			var to_hit: int = AiCombatMath.modified_hit_target(
				AiCombatMath.reliable_quality(base_quality, bool(profile.get("reliable", false))),
				int(mod_info.get("mod", 0)) + upr_hit)
			if upr_ap + extra_ap > 0:
				profile = profile.duplicate()
				profile["ap"] = int(profile.get("ap", 0)) + upr_ap + extra_ap   # Unpredictable + Tag/Reckless AP
			# Versatile Attack applies to the HUMAN's volley too (xhigh review find: the profiles are stamped
			# and every other modeled rule auto-applies here, but this path never read the flag — the player's
			# own Versatile units were cheated of their buff). Bug 13 (field test): the mode is the PLAYER's
			# choice — the EV pick only pre-labels the recommended button; asked once per weapon per volley.
			if bool(profile.get("versatile_attack", false)) and dist > AiCombatMath.LONG_RANGE_IN:
				var pname := str(profile.get("name", "?"))
				if not chosen_versatile.has(pname):
					var rec: Dictionary = AiEv.versatile_best_mode(to_hit, shielded_def, int(profile.get("ap", 0)), bool(profile.get("bane", false)))
					chosen_versatile[pname] = await _solo_prompt_versatile(pname, rec)
				var vm: Dictionary = chosen_versatile[pname]
				to_hit = AiCombatMath.modified_hit_target(to_hit, int(vm.get("hit_mod", 0)))
				if int(vm.get("ap", 0)) > 0:
					profile = profile.duplicate()
					profile["ap"] = int(profile.get("ap", 0)) + int(vm.get("ap", 0))
				if battle_log != null:
					battle_log.log_event(BattleLog.Category.COMBAT, "Versatile Attack: %s at long range" % [
						"AP(+1)" if int(vm.get("ap", 0)) > 0 else "+1 to hit"], true)
			_solo_log_hit_mod(mod_info, target, to_hit)
			var faces: Array = await _solo_tray_roll(int(profile.get("attacks", 0)), to_hit, "You")
			if bool(profile.get("limited", false)):
				solo_controller.mark_limited_used(group.get("member"), profile)   # once per game (wave 5)
			await _solo_hazardous_self_wounds(attacker, profile, faces)   # resolver wave A: natural 1s wound the firer
			var hits: int = await _solo_hits(faces, to_hit, profile, dist, target, false, "You")
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s fires %s at %s — %d hit%s" % [
					str(group.get("name", "?")), str(profile.get("name", "?")), target.get_name(), hits, ("" if hits == 1 else "s")])
			if hits <= 0:
				continue
			# Blast (GF v3.5.1) and Indirect (wave 5) ignore cover — saves at the Shielded (uncovered) Defense.
			var save_def: int = shielded_def if (int(profile.get("blast", 0)) > 1 or bool(profile.get("indirect", false)) or bool(profile.get("ignores_cover", false))) else covered_def
			# B5 (test game 2): the HUMAN volley now mirrors the AI's per-model landing — Takedown
			# wounds go to the model the PLAYER picks (click), Deadly lands ×X on one model with no
			# carry-over. Both previously pooled into the defender-optimal removal, so the player's
			# Takedown visibly "did nothing".
			var is_deadly: bool = int(profile.get("deadly", 0)) > 0
			var is_takedown: bool = bool(profile.get("takedown", false))
			var w: int = await _solo_resolve_saves(group.get("member"), target, str(profile.get("name", "?")), faces, hits, save_def, profile, false, false, not (is_deadly or is_takedown), false, dist)
			if is_takedown and w > 0:
				# Resolver wave A: Deadly multiplies on the picked model (see the AI branch).
				var td_w: int = w * maxi(int(profile.get("deadly", 0)), 1)
				if _solo_ignores_regen(group.get("member"), profile):
					await _solo_land_takedown_wounds(group.get("member"), target, str(profile.get("name", "?")), 0, td_w)
				else:
					await _solo_land_takedown_wounds(group.get("member"), target, str(profile.get("name", "?")), td_w, 0)
			elif is_deadly and w > 0:
				if _solo_ignores_regen(group.get("member"), profile):
					await _solo_land_deadly_wounds(target, str(profile.get("name", "?")), int(profile.get("deadly", 0)), 0, w)
				else:
					await _solo_land_deadly_wounds(target, str(profile.get("name", "?")), int(profile.get("deadly", 0)), w, 0)
			elif _solo_ignores_regen(group.get("member"), profile):
				regen_proof += w
			else:
				regenable += w
	# A volley where every profile scaled to zero (or none was in range) used to end SILENTLY — the player's
	# click looked ignored and he retried in vain (round 7, finding 5: the "unrecognized" shooting attempts).
	if not fired_any and battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT,
			"%s has no weapon in range of %s — no shots" % [attacker.get_name(), target.get_name()], true)
	await _solo_land_wounds(target, regenable, regen_proof)
	if _solo_combined_alive(target) <= 0:
		_solo_growth_on_kill(attacker)   # Defensive Frenzy: your volley kill counts too (symmetry)
		_solo_vengeance_on_destroyed(target, attacker)
	# The AI's unit tests morale if your volley dropped it to half strength or less (goal 003 P1).
	await _solo_shooting_morale(target, target_alive_before, "AI (%s)" % target.get_name(), target_wounds_before)
	_solo_consume_once_mods(attacker, target, false)   # F4: once-mods spent by this exchange


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
		human_caused += _solo_take_retaliate_credit()
	# — Impact(X) auto-hits on your charge (GF/AoF v3.5.1 p.13; reduced by the AI's Counter models). The
	#   counter-strike may already have wiped your unit — nothing left to roll then. —
	if _solo_combined_alive(attacker) > 0:
		human_caused += await _solo_charge_impact(attacker, target, false)
	# Resolver wave A — vs-target Marks: your charger's pre-attack pick lands on the defender.
	_solo_apply_vs_marks(attacker, target, 0.0)
	# Unwieldy (resolver wave A): a charging Unwieldy unit strikes LAST — the AI's strike-back
	# resolves first; Counter and Impact keep their slots.
	var h_charger_last: bool = _solo_unit_has_unwieldy(attacker)
	if h_charger_last and battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT, "Unwieldy: %s strikes last on the charge" % attacker.get_name(), true)
	var ai_struck: bool = ai_counter
	for phase_slot in range(2):
		if (phase_slot == 0) != h_charger_last:
			# — Your strikes (unit + attached heroes; only models within 2" strike; charging bonuses apply) —
			if _solo_combined_alive(attacker) > 0 and _solo_combined_alive(target) > 0:
				human_caused += await _solo_melee_strike_phase(attacker, target, true, SoloStrike.ALL)
				ai_caused += _solo_take_retaliate_credit()
				_solo_set_fatigued(attacker)
		else:
			# — The AI's strike-back with its remaining (non-Counter) weapons — mandatory (solo rules p.57) —
			if _solo_combined_alive(target) > 0 and _solo_combined_alive(attacker) > 0:
				ai_caused += await _solo_melee_strike_phase(target, attacker, false,
					SoloStrike.NON_COUNTER if ai_counter else SoloStrike.ALL)
				human_caused += _solo_take_retaliate_credit()
				ai_struck = true
	if ai_struck and _solo_combined_alive(target) > 0:
		_solo_set_fatigued(target)
	# Resolver wave A — Self-Destruct survival half: "after both sides have finished attacking".
	await _solo_self_destruct_post_melee(attacker, target)
	await _solo_self_destruct_post_melee(target, attacker)
	# — Morale: the side that CAUSED more wounds wins; the loser tests. Fear(X) (GF/AoF v3.5.1 p.13) adds
	#   +X to the bearer's tally for THIS comparison only. —
	var human_score: int = AiCombatMath.fear_adjusted_wounds(human_caused, _solo_unit_rating(attacker, "Fear"))
	var ai_score: int = AiCombatMath.fear_adjusted_wounds(ai_caused, _solo_unit_rating(target, "Fear"))
	if human_score > ai_score and _solo_combined_alive(target) > 0:
		await _solo_morale_test(target, "AI (%s)" % target.get_name(), true)   # MELEE loser
	elif ai_score > human_score and _solo_combined_alive(attacker) > 0:
		await _solo_morale_test(attacker, "You", true)   # MELEE loser
	# — Consolidation (GF v3.5.1 p.9, round 7 finding 4): neither destroyed → the human charger's 1"
	#   back-step is surfaced as a reminder; one side destroyed → the survivor consolidates up to 3"
	#   (your unit gets the move OFFERED; a surviving AI defender takes it automatically, EV-aware). —
	await _solo_consolidate_melee(attacker, target)


## Mark a unit (and its attached heroes — they fought too) Fatigued after its first melee this round
## (state + marker + broadcast via the radial seam).
## Mirror a Shaken toggle onto the unit's attached heroes (p.14: the hero IS part of the unit —
## one state, no separate token; the marker updater suppresses the hero's visible duplicate).
func _solo_mirror_shaken(unit: GameUnit) -> void:
	if unit == null or radial_menu_controller == null or not unit.has_method("get_attached_heroes"):
		return
	for h in unit.get_attached_heroes():
		var hu := h as GameUnit
		if hu != null and hu.is_shaken != unit.is_shaken:
			radial_menu_controller.card_toggle_shaken(hu)


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
	_solo_expire_spell_tokens()   # v3.5.1: spell effects end with the round — clear the placed tokens
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
	if solo_controller != null:
		solo_controller.reset_round_claims()   # albtraum v2: the overkill ledger never outlives a round
	_solo_growth_round_start()   # coverage wave: per-round growth markers tick before anyone acts
	await _solo_battleborn_recovery()
	# Ambush arrivals happen at the start of ANY round after the first (GF/AoF v3.5.1 p.13), so a unit
	# with no clear spot in round 2 gets another chance later. B12: players ALTERNATE placing them.
	if round_number >= 2:
		await _solo_alternate_ambush_arrivals(round_number)


## Round-start Shaken recovery — wave-4 Battleborn (army-book rule, Battle Brothers) and the quick-win
## Steadfast, whose official texts are byte-identical: "If a unit where all models have this rule is
## Shaken at the beginning of the round, roll one die. On a 4+, it stops being Shaken." At round start,
## every AI Shaken unit with such a rule rolls one real tray die and recovers at the (registry-tuned)
## target (NOT spending its activation). The human's own units are surfaced as a reminder (the
## automation never touches the player's markers).
func _solo_battleborn_recovery() -> void:
	if opr_army_manager == null:
		return
	for u in opr_army_manager.get_all_game_units():
		var gu := u as GameUnit
		if gu == null or not gu.is_shaken:
			continue
		var rule := _solo_round_start_recovery_rule(gu)
		if rule.is_empty():
			continue
		var target: int = int(RulesRegistry.unit_param(gu, rule, "recover_target", AiCombatMath.BATTLEBORN_RECOVER_TARGET))
		if _solo_is_ai_unit(gu):
			var face: Array = await _solo_tray_roll(1, target, "AI (%s)" % gu.get_name())
			var recovered: bool = not face.is_empty() and AiCombatMath.battleborn_recovers(int(face[0]), target)
			if recovered and radial_menu_controller != null:
				radial_menu_controller.card_toggle_shaken(gu)   # clears Shaken via the state+marker+MP seam
				_solo_mirror_shaken(gu)
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s: %s %s" % [
					rule, gu.get_name(), ("recovers from Shaken (%d+)" % target if recovered else "stays Shaken")], true)
		elif battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT,
				"%s: roll for %s to recover from Shaken (%d+)" % [rule, gu.get_name(), target], true)


## The round-start Shaken-recovery rule a unit benefits from ("" when none). Battleborn keeps its wave-4
## plain-rule check; Steadfast is gated the wave-5 way (fires only where the unit's book fields it).
## Coverage wave: DATA aliases (Honor Code, …) resolve through the generic primitive layer.
func _solo_round_start_recovery_rule(gu: GameUnit) -> String:
	if _solo_rule_on_all_models(gu, "Battleborn"):
		return "Battleborn"
	if _solo_rule_on_all_models(gu, "Steadfast") and RulesRegistry.unit_rule_active(gu, "Steadfast"):
		return "Steadfast"
	for e in RulesRegistry.unit_rules_of_primitive(gu, "Battleborn"):
		var n := str((e as Dictionary)["name"])
		if n != "Battleborn" and n != "Steadfast" and _solo_rule_on_all_models(gu, n):
			return n
	return ""


## B12 (GF v3.5.1 p.13, verified in the PDF): "Players alternate in placing Ambushers, starting with
## the player that activates next." One unit per turn — the AI's arrival keeps its paced, announced
## beat; the human is asked PER UNIT ("Deploy now" / "Keep waiting", race-proof via
## _solo_await_confirm — the old all-at-once dialog could be closed by a stray click and read as a
## silent "Keep waiting", which is why the prompt "never fired" in test game 2). B8: every placement
## searches around ALL standing bases (both sides), so a reserve can no longer land on its own army.
func _solo_alternate_ambush_arrivals(round_number: int) -> void:
	if solo_controller == null or table == null or opr_army_manager == null:
		return
	var human_is_ai: bool = solo_ai_slots.has(solo_controller.human_slot)
	var w: float = table.table_size.x * 0.3048
	var d: float = table.table_size.y * 0.3048
	var arrival_zone := Rect2(Vector2(-w / 2.0, -d / 2.0), Vector2(w, d))
	var occupied: Array = solo_controller.occupied_from_live_bases()   # B8: both sides' live bases
	var ai_enemies: Array = _solo_ambush_enemy_positions(solo_controller.human_slot)
	var ai_turn: bool = not _solo_ai_took_last_activation   # "the player that activates next" starts
	var human_waiting: Dictionary = {}   # instance_id → true ("Keep waiting" — not re-asked this round)
	var ai_stuck := false                # no legal spot for any AI reserve right now
	while true:
		var ai_has: bool = not ai_stuck and not solo_controller.ambush_reserve.is_empty()
		var human_pool: Array = []
		if not human_is_ai:
			for u in solo_controller.human_reserve_units():
				if not human_waiting.has((u as GameUnit).get_instance_id()):
					human_pool.append(u)
		if not ai_has and human_pool.is_empty():
			break
		if ai_turn and ai_has:
			var unit: GameUnit = solo_controller.arrive_one_ambush_unit(arrival_zone, ai_enemies, occupied, round_number)
			if unit == null:
				ai_stuck = true
			else:
				_solo_set_unit_visible(unit, true)   # reveal — this arrival is its ONE placement (finding 4)
				_solo_focus_on_unit(unit)
				_solo_show_toast("%s ambushes in from reserve" % unit.get_name())
				if battle_log != null:
					battle_log.log_event(BattleLog.Category.GENERAL,
						"AI Ambush: %s arrives — near an objective, >9\" from your units, clear of all standing bases" % unit.get_name(), true)
				await _solo_pace_attention()
		elif not ai_turn and not human_pool.is_empty():
			var placed: Array = await _solo_ambush_human_turn(round_number, human_pool)
			if placed.is_empty():
				for u in human_pool:
					human_waiting[(u as GameUnit).get_instance_id()] = true   # "keine mehr" — wait this round
			else:
				for g in placed:
					occupied.append({"pos": Vector2(solo_controller.unit_centre(g as GameUnit).x,
						solo_controller.unit_centre(g as GameUnit).z), "radius": 0.05})
		ai_turn = not ai_turn
	if is_instance_valid(_solo_toast):
		_solo_toast.visible = false
	var held_ai: int = solo_controller.ambush_reserve.size()
	if held_ai > 0 and battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL,
			"AI Ambush: %d unit(s) held back — no clear spot (may arrive a later round)" % held_ai, true)
	var held_h: int = solo_controller.human_reserve_units().size()
	if held_h > 0 and not human_is_ai and battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL,
			"%d of your Ambush unit(s) stay in reserve — you'll be asked again next round." % held_h, false)
	_solo_flush_dev()


## The enemy no-go entries of `enemy_slot`'s standing units — PER MODEL, base-edge-true (maintainer
## field find: the old unit-CENTRE ring let a wide enemy's forward models stand well inside the 9" —
## the rule measures closest point to closest point, like every distance). Each entry carries the
## enemy model's base radius as pad_m; Repel Ambushers pushes min_dist_m to 12". Reserved units
## cast no ring. Shared by both sides' reserve arrivals.
func _solo_ambush_enemy_positions(enemy_slot: int) -> Array:
	var out: Array = []
	for u in opr_army_manager.get_game_units_for_player(enemy_slot):
		var gu := u as GameUnit
		if gu == null or gu.get_alive_count() <= 0 or SoloController.unit_in_reserve(gu):
			continue
		var repel_m := SoloController.repel_ambush_dist_m(gu)
		for m in gu.get_alive_models():
			var mi := m as ModelInstance
			if mi != null and mi.node != null and is_instance_valid(mi.node):
				var p := mi.node.global_position
				out.append({"pos": Vector2(p.x, p.z), "min_dist_m": repel_m,
					"pad_m": SoloController.model_base_radius_m(mi)})
	return out


## The human's Ambush turn (maintainer flow: SAME hand-over procedure as deployment): he places
## ONE reserve unit HIMSELF (drag from the tray, >9" from enemies — his measure) and hands over by
## click; "Keine mehr" keeps the rest waiting this round. The ✔ click detects which reserve units
## newly stand on the table and clears their flags. Returns the placed units ([] = waiting).
func _solo_ambush_human_turn(round_number: int, pool: Array) -> Array:
	var names: PackedStringArray = []
	for u in pool:
		names.append((u as GameUnit).get_name())
	var outcome: Array = []
	_solo_deploy_ui_show("Ambush — round %d: place ONE reserve unit from the tray (>9\" from enemies), then hand over.\nIn reserve: %s" % [round_number, ", ".join(names)],
		"✔ Unit placed", func() -> void: outcome.append("placed"),
		"None this round — keep waiting", func() -> void: outcome.append("wait"))
	while outcome.is_empty():
		await get_tree().process_frame
	var placed: Array = []
	if str(outcome[0]) == "placed":
		placed = _solo_newly_tabled_reserves()
		if placed.is_empty():
			_solo_show_toast("No new reserve unit detected on the table — place it first, then ✔")
			_solo_deploy_ui_hide()
			return await _solo_ambush_human_turn(round_number, pool)
		for g in placed:
			var gu := g as GameUnit
			gu.unit_properties["ambush_reserve"] = false
			gu.unit_properties["ambush_arrived_round"] = opr_army_manager.current_round
			_solo_set_unit_visible(gu, true)
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.GENERAL,
					"You deploy %s from Ambush reserve (>9\" from enemies) — it may act this round, no seizing (GF v3.5.1 p.13)" % gu.get_name(), false)
	elif battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL, "Your Ambush reserve keeps waiting this round", false)
	_solo_deploy_ui_hide()
	return placed


## Human reserve units whose centre NOW stands on the table plane (dragged off the tray) — the
## Ambush ✔ click's detection. The tray stands outside the table rect, so it never false-counts.
func _solo_newly_tabled_reserves() -> Array:
	var out: Array = []
	if table == null or solo_controller == null:
		return out
	var w: float = table.table_size.x * 0.3048
	var d: float = table.table_size.y * 0.3048
	var trect := Rect2(Vector2(-w / 2.0, -d / 2.0), Vector2(w, d))
	for u in solo_controller.human_reserve_units():
		var gu := u as GameUnit
		var c := solo_controller.unit_centre(gu)
		if trect.has_point(Vector2(c.x, c.z)):
			out.append(gu)
	return out


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
		# Combined alive AND combined total: with a joined hero both numbers must count the same pool
		# (the old own-models total printed impossible "(4/3)" shapes once the hero soaked the spill).
		# Log the wounds that actually LANDED, not the requested amount — the rout wipe passes an overkill
		# figure and printed "takes 120 wounds" (Windows playtest bug 6); spill past the pool is no wound.
		battle_log.on_wounds(target.get_name(), maxi(0, wounds - remaining), _solo_combined_alive(target), SoloController.combined_total(target))
	_solo_hero_carries_on(target)


## When a unit's own models are all dead but a joined hero survives, the hero carries the UNIT's
## state onward (p.14 example: the hero keeps testing as the unit): Shaken/Fatigued transfer to the
## hero (his suppressed marker becomes visible via the marker refresh) and the rule is logged.
func _solo_hero_carries_on(target: GameUnit) -> void:
	if target == null or target.get_alive_count() > 0 or not target.has_method("get_attached_heroes"):
		return
	for h in target.get_attached_heroes():
		var hu := h as GameUnit
		if hu == null or hu.get_alive_count() <= 0:
			continue
		# Flags are already mirrored; the refresh un-suppresses the hero's own marker now that the
		# host fields no models.
		if radial_menu_controller != null:
			if hu.is_shaken:
				radial_menu_controller._update_shaken_markers(hu)
			if hu.is_fatigued:
				radial_menu_controller._update_fatigued_markers(hu)
		if (hu.is_shaken or hu.is_fatigued) and battle_log != null:
			battle_log.log_event(BattleLog.Category.COMBAT,
				"%s fights on alone — carries the unit's %s (GF v3.5.1 p.14)" % [hu.get_name(),
				("Shaken + Fatigue" if hu.is_shaken and hu.is_fatigued else ("Shaken" if hu.is_shaken else "Fatigue"))], true)


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
		# Snap the WHOLE selection to the nearest 90° facing (Ctrl+R). Born as the AoF:R
		# regiment pivot aid (v3.5.1 p.8 "Pivoting" — the four cardinal facings are the
		# natural snap targets); extended to every selectable (maintainer 2026-07-20:
		# units, single models and terrain want the same quick alignment). The player
		# decides whether a snap is a legal pivot; this is a quick-alignment aid.
		elif event.keycode == KEY_R and event.ctrl_pressed and not event.shift_pressed:
			object_manager.begin_rotation_capture()
			var snapped: int = 0
			for obj in object_manager.get_selected_objects():
				if obj is Node3D and is_instance_valid(obj):
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
## Bug 30 (Linux test 2026-07-19): in a SOLO game the manual button now runs the SAME
## end-of-round truth as the auto-advance — seize, advance, the ROUND-START sequence
## (Steadfast/Battleborn recovery, Ambush arrivals + prompt) and the alternation reset.
## The old direct advance_round() skipped all of it, so manually staged states (a
## hand-marked Shaken unit) never saw their round-start rolls — which also made the
## button useless as a TESTING lever for round-gated rules (maintainer request).
func _do_next_round() -> void:
	if _solo_alternation_active():
		_ensure_solo_controller()
		await _solo_end_round()
		return
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


## STRICT "dry brush" HUD readout: during a movement-budget-capped drag, show consumed vs the
## model's max legal band ("6.0/6.0″") and colour it amber → red the moment the brush runs dry,
## so the cap reads unmistakably. Emitted after _on_distance_changed, so it wins the label.
func _on_movement_capped(consumed_inches: float, cap_inches: float, dry: bool) -> void:
	distance_label.text = "%.1f/%.1f\"" % [consumed_inches, cap_inches]
	distance_label.add_theme_color_override("font_color",
			Color(1.0, 0.35, 0.3) if dry else Color(1.0, 0.78, 0.25))


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
	# Clear any strict-cap colour so the next plain measurement reads in the default colour.
	distance_label.remove_theme_color_override("font_color")
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
	dice_controls_changed.emit(&"movecap", mode)


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
	dice_controls_changed.emit(&"count", _dice_count)
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
	dice_controls_changed.emit(&"success", target)


func _on_modifier_delta_pressed(delta: int) -> void:
	_success_modifier = clampi(_success_modifier + delta, DiceRules.MODIFIER_MIN, DiceRules.MODIFIER_MAX)
	dice_controls_changed.emit(&"modifier", _success_modifier)
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
	dice_controls_changed.emit(&"reroll", mode)
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
	if radial_menu_controller != null:
		# NML-105: embark/disembark are rule actions and log their line (rules-must-log). Wired
		# here — _init_radial_menu runs before this setup, so the earlier wiring spot saw null.
		radial_menu_controller.battle_log = battle_log
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
	battle_log_panel.copy_requested.connect(_on_battle_log_copy)
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


## Copy the full battle log to the system clipboard (maintainer request: paste-ready
## hand-off during live testing; same text the file export writes).
func _on_battle_log_copy() -> void:
	if battle_log == null:
		return
	var decision_lines: Array = []
	if _solo_dev and solo_controller != null:
		for rec in solo_controller.decision_log:
			decision_lines.append(SoloController.render_decision(rec as Dictionary))
	DisplayServer.clipboard_set(battle_log.export_as_text(decision_lines))
	_solo_show_toast("Battle Log copied to clipboard")


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
	# A JOINED HERO is part of the unit (GF/AoF v3.5.1 "Heroes"): the unit is destroyed only when the
	# hero's models are gone TOO. Counting only gu.models declared "X destroyed" while the attached hero
	# still fought on (showcase finding: the log killed Support Brothers a full activation early).
	var alive: int = SoloController.combined_alive(gu)
	var total: int = SoloController.combined_total(gu)
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
	var kind := _next_roll_kind   # consume-on-log (Bug 16): exactly ONE line carries the save wording
	_next_roll_kind = "attack"
	var target: int = int(context.get(DiceRules.CTX_TARGET, DiceRules.TARGET_NONE))
	if target == DiceRules.TARGET_NONE or target <= 0:
		battle_log.on_dice_rolled(faces.size(), 0, 0, player_name, faces, kind)
		return
	var modifier: int = int(context.get(DiceRules.CTX_MODIFIER, 0))
	battle_log.on_dice_rolled(faces.size(), DiceRules.count_successes(faces, target, modifier), target, player_name, faces, kind)


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
	if is_instance_valid(_tutorial_director):
		_tutorial_director.late_bind_terrain_shelf(_sandbox_shelf)   # the shelf is lazy — bind the T-09a seam now
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


## The AI-opponent dialog (maintainer request): NACHTMAHR builds its own list — pick faction + points,
## the game loads the matching pre-built AI list into the chosen slot as an AI army. Delivery
## (solo rollout S6): dev/arena builds read the local bundle (assets/ai_lists — NEVER in the public
## repo); public builds fetch index + list from the CDN at runtime with a user:// cache for offline
## replay. No source at all → toast; the own-army import with the AI checkbox stays the fallback.
func _open_ai_opponent_dialog() -> void:
	var manifest := await _load_ai_list_manifest()
	if manifest.is_empty():
		_solo_show_toast("No AI lists available (no connection yet?) — import any list with the AI checkbox instead")
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "AI Opponent — NACHTMAHR builds its list"
	dlg.min_size = Vector2i(420, 220)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	box.add_child(_dialog_label("Faction:"))
	var fac_opt := OptionButton.new()
	var fac_keys: Array = manifest.keys()
	fac_keys.sort()
	for i in fac_keys.size():
		var fk: String = fac_keys[i]
		fac_opt.add_item(str((manifest[fk] as Dictionary).get("name", fk)), i)
	box.add_child(fac_opt)

	box.add_child(_dialog_label("Points:"))
	var pts_opt := OptionButton.new()
	box.add_child(pts_opt)
	var refresh_points := func() -> void:
		pts_opt.clear()
		var fk: String = fac_keys[maxi(0, fac_opt.selected)]
		var lists: Array = (manifest[fk] as Dictionary).get("lists", [])
		for j in lists.size():
			pts_opt.add_item("%d points" % int((lists[j] as Dictionary).get("points", 0)), j)
		pts_opt.select(mini(lists.size() - 1, lists.size() - 1))   # default: the largest bracket
	refresh_points.call()
	fac_opt.item_selected.connect(func(_i: int) -> void: refresh_points.call())

	box.add_child(_dialog_label("AI plays as:"))
	var slot_opt := OptionButton.new()
	slot_opt.add_item("Player 2 (Red)", 2)
	slot_opt.add_item("Player 1 (Blue)", 1)
	box.add_child(slot_opt)

	dlg.add_child(box)
	dlg.get_ok_button().text = "Build & deploy list"
	dlg.confirmed.connect(func() -> void:
		var fk: String = fac_keys[maxi(0, fac_opt.selected)]
		var lists: Array = (manifest[fk] as Dictionary).get("lists", [])
		if pts_opt.selected < 0 or pts_opt.selected >= lists.size():
			return
		var file: String = str((lists[pts_opt.selected] as Dictionary).get("file", ""))
		var slot: int = slot_opt.get_item_id(slot_opt.selected)
		_load_ai_opponent_list(file, slot))
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _dialog_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	return l


## Load + parse an AI list (bundle → user-cache → CDN, in that order) and route it through the
## normal import path as an AI army.
func _load_ai_opponent_list(file: String, slot: int) -> void:
	var text := _ai_lists_local_text(file)
	if text.is_empty():
		text = await _fetch_cdn_text("%s/%s" % [AI_LISTS_CDN_PATH, file])
		if not text.is_empty():
			_ai_lists_cache_write(file, text)
	if text.is_empty():
		_solo_show_toast("AI list not found: %s (no bundle, no cache, no connection)" % file)
		return
	var army = await opr_army_manager.api_client._parse_tts_api_response(text)
	if army == null or army.units.is_empty():
		_solo_show_toast("AI list failed to load (network needed for the army book?)")
		return
	army.player_id = slot
	# Same path an imported army takes, flagged AI-controlled → the AI slot + difficulty wire up.
	await _on_opr_army_imported(army, slot, true)
	_solo_show_toast("NACHTMAHR: %s ready (player %d)" % [army.name, slot])


## Local sources for an AI-list file: the dev/arena bundle first, then the user cache of earlier
## CDN downloads (offline replay). "" when neither exists.
func _ai_lists_local_text(file: String) -> String:
	var text := FileAccess.get_file_as_string("%s/%s" % [AI_LISTS_DIR, file])
	if not text.is_empty():
		return text
	return FileAccess.get_file_as_string("%s/%s" % [AI_LISTS_CACHE_DIR, file])


func _ai_lists_cache_write(file: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(AI_LISTS_CACHE_DIR)
	var f := FileAccess.open("%s/%s" % [AI_LISTS_CACHE_DIR, file], FileAccess.WRITE)
	if f != null:
		f.store_string(text)


## One-shot CDN text fetch (browser UA — the R2 host rejects bare clients). "" on any failure;
## callers fall back to bundle/cache/toast.
func _fetch_cdn_text(rel_path: String) -> String:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	var err := http.request("%s/%s" % [AssetCDN.HOST, rel_path],
		["User-Agent: Mozilla/5.0 (X11; Linux x86_64) Niemandsland"])
	if err != OK:
		http.queue_free()
		return ""
	var res: Array = await http.request_completed
	http.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return ""
	return (res[3] as PackedByteArray).get_string_from_utf8()


## Read the bundled AI-list manifest (faction → display name + point-bracket files). {} when absent.
## AI-list index: bundle → CDN (fresh) → user cache (offline). The CDN copy wins over a stale
## cache; a successful fetch refreshes the cache for the next offline session.
func _load_ai_list_manifest() -> Dictionary:
	var text := FileAccess.get_file_as_string("%s/_manifest.json" % AI_LISTS_DIR)
	if text.is_empty():
		text = await _fetch_cdn_text("%s/_manifest.json" % AI_LISTS_CDN_PATH)
		if not text.is_empty():
			_ai_lists_cache_write("_manifest.json", text)
		else:
			text = FileAccess.get_file_as_string("%s/_manifest.json" % AI_LISTS_CACHE_DIR)
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## Handle army imported from dialog
func _on_opr_army_imported(army: OPRApiClient.OPRArmy, player_id: int, ai_controlled: bool = false) -> void:
	print("Importing army '%s' for Player %d%s" % [army.name, player_id, " (AI-controlled)" if ai_controlled else ""])
	# Solo (goal 001): remember the designation; the Solo panel + F11 read it. Re-importing the slot
	# without the checkbox clears a stale designation.
	if ai_controlled:
		solo_ai_slots[player_id] = true
	else:
		solo_ai_slots.erase(player_id)
	_solo_sync_difficulty()   # give the AI slot its grade → position solver + knobs run (not the naive baseline)
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
	# SPELL buffs/debuffs (maintainer request): the army book's spells (OPR Army Forge API) whose effect
	# reads as a modifier become assignable tokens too — the radial Token menu then offers exactly the
	# buffs/debuffs the lists actually field, colour-coded (green = buff, red = debuff), for MP and solo
	# alike. Same idempotent define+broadcast path as the rule tokens.
	for sp in army.spells:
		var s_name := str(sp.get("name", "")).strip_edges()
		var s_eff := str(sp.get("effect", ""))
		if s_name.is_empty():
			continue
		var el := s_eff.to_lower()
		if not ("+1" in s_eff or "-1" in s_eff or "+2" in s_eff or "-2" in s_eff 				or "re-roll" in el or "reroll" in el or "shaken" in el or "slow" in el or "fast" in el):
			continue   # damage spells resolve as dice, not as a lingering state — no token
		var is_debuff := ("-1" in s_eff or "-2" in s_eff or "shaken" in el or "slow" in el)
		tokens.append({"name": s_name, "color": Color.html("b85050" if is_debuff else "50a860"),
			"is_counter": false, "effect": s_eff})
	var created := 0
	for t in tokens:
		if lib.has(t.name):
			continue
		lib.define(t.name, t.color, t.is_counter, t.effect)
		created += 1
		if network_manager and network_manager.is_multiplayer_active():
			network_manager.broadcast_token_define(t.name, t.color, t.is_counter, t.effect)
	if created > 0:
		print("[Tokens] Auto-created %d buff token(s) from special rules + spells" % created)


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
	# Arm the inactivity timeout: if the host goes silent before the complete RPC, the guest
	# must not wait on this overlay forever — it aborts and recovers (host can re-import).
	_arm_import_await_timeout(player_id, _import_await_guard.bump(player_id))


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
	# Progress arrived — push the inactivity deadline out (a slow but live import must not abort).
	_arm_import_await_timeout(player_id, _import_await_guard.bump(player_id))


## All units received — build the whole army in ONE pass: rebuild the units, download every
## model with a single ensure_models call (feeds the loading bar like a self-import), spawn
## all model objects, then restore markers / heroes / regiment trays.
func _on_remote_army_complete(player_id: int, rule_descriptions: Dictionary) -> void:
	# The stream finished — cancel the inactivity timeout so it can't abort the build below.
	_import_await_guard.clear(player_id)
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


## Arm (or re-arm) the guest's inactivity timeout for an in-flight remote army import. `gen` is
## the liveness token captured at arm time; the fired timer aborts only if it is still current
## (no header/unit/complete arrived since), so a healthy stream keeps superseding its own timers.
func _arm_import_await_timeout(player_id: int, gen: int) -> void:
	await get_tree().create_timer(IMPORT_AWAIT_TIMEOUT_SEC).timeout
	# Superseded by later progress or already resolved/aborted → this timer is a no-op.
	if not _import_await_guard.is_current(player_id, gen):
		return
	# Nothing arrived within the window AND the buffer is still pending → the host went silent.
	if not _incoming_armies.has(player_id):
		return
	_abort_import_await(player_id)


## Abort a stalled remote army import and return the session to a recoverable state. We undo ONLY
## what _on_remote_army_header set — the partial buffer (a host re-import cleanly overwrites it via
## a fresh header), the presence-suppression flag, and the shared loading overlay. We deliberately
## do NOT build the partial army: the stream may be missing units and its network_ids would then
## collide with the host's re-import — so a clean re-import is the recovery.
##
## Crucially we must NOT touch the global restore lock or the busy gate here. Both are acquired only
## in _on_remote_army_complete (begin_restore + broadcast_peer_busy(true)), whose very first act —
## _import_await_guard.clear() — makes this abort unreachable once it runs. So a stalled import
## provably never held either; force-releasing them would clobber a *concurrent* legitimate restore
## / busy state (another player's join or import), reintroducing the interleave the lock guards.
func _abort_import_await(player_id: int) -> void:
	push_warning("[ArmySync] Import from player_id=%d timed out after %.0fs — aborting, session recoverable" % [player_id, IMPORT_AWAIT_TIMEOUT_SEC])
	_import_await_guard.clear(player_id)
	_incoming_armies.erase(player_id)
	# Only settle the shared presence flag + overlay when no OTHER remote army is still buffering,
	# so a concurrent second import keeps its "loading" indicator and presence suppression.
	if _incoming_armies.is_empty():
		_is_army_syncing = false  # resume presence broadcasts (Fix A) — nothing else is loading
		if is_instance_valid(_army_loading_overlay):
			_army_loading_overlay.complete_and_free()
			_army_loading_overlay = null
	_show_toast("⚠ Army import from another player timed out — ask them to import again")


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

	# Guided tutorial: the UI is now revealed, so start the director on the live table.
	if _tutorial_mode:
		call_deferred("_start_tutorial")


## ============================================================================
## Guided Tutorial (T1 tool track)
## ============================================================================

## How long to wait for the bundled tutorial board to produce units before running
## the tutorial degraded (banner-only spotlights, no unit target). Generous: the very
## first tutorial launch may download both factions' models (54 minis) from the CDN.
const TUTORIAL_BOARD_TIMEOUT_S := 120.0

## Wait for the bundled board (queued on the pending-load path), then hand control to
## the TutorialDirector, which runs the event-gated W1-W6 tool track on the live table.
func _start_tutorial() -> void:
	if is_instance_valid(_tutorial_director):
		return  # already running (guard against a double call_deferred)
	# The board .nml deserializes asynchronously (unit-by-unit): wait for its
	# load_completed/load_failed gate, with a hard timeout so a broken board never
	# hangs the tutorial (it then runs degraded: banner spotlights, no unit target).
	if _tutorial_board_pending:
		var waited := 0.0
		while not _tutorial_board_loaded and waited < TUTORIAL_BOARD_TIMEOUT_S:
			await get_tree().create_timer(0.25).timeout
			waited += 0.25
		if opr_army_manager == null or opr_army_manager.game_units.is_empty():
			push_warning("Tutorial: board produced no units after %.1fs — running degraded" % waited)
	var progress := TutorialProgress.new()
	progress.load_from_disk()
	_tutorial_director = TutorialDirector.new()
	_tutorial_director.name = "TutorialDirector"
	add_child(_tutorial_director)
	_tutorial_director.lesson_completed.connect(_on_tutorial_lesson_completed)
	_tutorial_director.tutorial_finished.connect(_on_tutorial_finished)
	_tutorial_director.setup({
		"object_manager": object_manager,
		"camera_pivot": camera_pivot,
		"dice_tray": dice_roller_control,
		"dice_panel": $UI/HUD/DiceRollerPanel as Control,
		"hamburger": hamburger_button,
		"left_panel": left_panel_scroll,
		"import_button": import_opr_btn,
		"import_dialog": opr_import_dialog,
		"unit_dock": unit_dock,
		"radial_controller": radial_menu_controller,
		"army_manager": opr_army_manager,
		"undo_manager": undo_manager,
		"start_game_button": _start_game_button,
		"pinned_rulers": pinned_rulers,
		"range_rings": range_ring_controller,
		"dice_controls_source": self,
		"quick_roll_button": quick_roll_button,
		"radial_menu": radial_menu_controller.radial_menu,
		"wounds_dialog": radial_menu_controller.wounds_dialog,
		"casts_dialog": radial_menu_controller.casts_dialog,
		"marker_dialog": radial_menu_controller.marker_dialog,
		"table": table,
		"map_layout": map_layout_editor,
		"terrain_shelf": _sandbox_shelf,   # usually still null here — late-bound on first Terrain Mode
		"terrain_mode_btn": _terrain_mode_btn,
	})
	_tutorial_director.begin(progress, _tutorial_start_lesson)


## A lesson finished (played through or skipped) — quick, non-blocking confirmation.
func _on_tutorial_lesson_completed(lesson_id: String) -> void:
	_show_toast("✓ Lesson %s complete" % lesson_id)


## The tutorial ended (track completed, or the player ended it). Celebrate on a clean
## finish, then free the director (which frees its overlay) — the player stays on the
## live table either way.
func _on_tutorial_finished(completed: bool) -> void:
	if completed:
		_show_toast("🎉 Tutorial complete — the table is yours. Play on!")
	_tutorial_mode = false
	if is_instance_valid(_tutorial_director):
		_tutorial_director.queue_free()
	_tutorial_director = null


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
		map_layout_editor.editor_opened.emit()
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
	# Difficulty selector REMOVED (maintainer 2026-07-17): while we train NACHTMAHR to be as strong as
	# possible it always plays at maximum (Albtraum) — no grade picker to clutter the panel. The grade is
	# pinned to _solo_interactive_grade ("albtraum"); the selector + downshift return in a later release.
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
	deploy_btn.text = "Start Deployment"
	deploy_btn.tooltip_text = "GF v3.5.1: roll-off, the winner picks a table edge and deploys first; then alternate one unit each (hand-over by click), then the Scout phase. The roll-off winner takes round 1's first turn."
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
	_solo_sync_difficulty()


## Re-apply the difficulty after an AI designation or Solo-panel grade change. Thin alias of
## _solo_apply_difficulty (the ONE application point, also run whenever the controller is (re)created) —
## harmlessly a no-op while the controller does not exist yet.
func _solo_sync_difficulty() -> void:
	_solo_apply_difficulty()


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

## Phase-gate label picker. The app has no i18n infra and its UI is English-only, so this always
## returns English; the `_de` arg at each call site preserves a German translation for a future
## real localization pass (see body).
func _phase_tr(en: String, _de: String) -> String:
	# The UI is English-only (no TranslationServer / .po localization), so the phase-gate strings must
	# be English too — a German OS locale otherwise left these buttons the ONLY German text in an English
	# game. The `_de` args are kept at the call sites for a future real localization pass.
	return en


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
				else _phase_tr("Ready", "Bereit")
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
	# sync) — sizing the mist only in _set_table_size left it hanging past
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
	# Entrenched-family bookkeeping: a human drag stamps moved_round on the dragged units (the
	# stationary -2-to-hit gate reads it; deployment drags before round 1 stamp round 0 or 1
	# harmlessly — Entrenched only compares against the CURRENT round).
	if opr_army_manager != null and object_manager != null:
		for obj in object_manager.get_selected_objects():
			var gu := UnitUtils.get_game_unit(obj)
			if gu != null:
				gu.unit_properties["moved_round"] = opr_army_manager.current_round


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

	# Sight+range fan (maintainer sketch 2026-07-16): the unit's summed visible+shootable region, toggled
	# with F on the selection — the "what is a legitimate target" overlay. Base-edge rays, exact wall
	# shadows, see-INTO-not-THROUGH area terrain (SightFan mirrors the engine LOS — one truth). Local-only.
	sight_fan_controller = SightFanController.new()
	sight_fan_controller.name = "SightFanController"
	add_child(sight_fan_controller)
	object_manager.sight_fan_toggle = func(model_nodes: Array, clear_all: bool) -> void:
		if clear_all or model_nodes.is_empty():
			sight_fan_controller.clear_fan()
			_sight_fan_unit = null
			return
		var fan_unit: GameUnit = null
		for mn in model_nodes:
			if (mn as Node).has_meta("model_instance"):
				var mi_meta = (mn as Node).get_meta("model_instance")
				if mi_meta is ModelInstance and (mi_meta as ModelInstance).unit != null:
					fan_unit = (mi_meta as ModelInstance).unit
					break
		if fan_unit == null:
			return
		if _sight_fan_unit == fan_unit:
			sight_fan_controller.clear_fan()
			_sight_fan_unit = null
			return
		_solo_show_fan_for_unit(fan_unit)

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
	# Measure-on-pickup ghost (ROADMAP UX polish): translucent origin silhouettes while dragging —
	# shows what ESC snaps back to and where the measured arc starts. Local display aid.
	var pickup_ghosts := PickupGhostController.new()
	pickup_ghosts.name = "PickupGhostController"
	add_child(pickup_ghosts)
	object_manager.pickup_ghosts = pickup_ghosts
	# Contextual control hints (ROADMAP UX polish): hover an object → its verified hotkeys in a
	# small dimmed bottom line (dwell-delayed, hides on hover end / drag start). Local display aid.
	var control_hints := ControlHintsController.new()
	control_hints.name = "ControlHintsController"
	add_child(control_hints)
	object_manager.hover_changed.connect(control_hints.on_hover_changed)
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


# === Coverage wave (2026-07-23): the Utility-Buff family — "once per activation, before attacking" ===

## Best legal target for a utility buff/debuff. kind: "friendly" / "friendly_caster" /
## "friendly_artillery" / "enemy". Value proxy: the biggest unit benefits (or suffers) most.
func _solo_utility_target(bearer: GameUnit, kind: String, range_in: float, needs_los: bool) -> GameUnit:
	if solo_controller == null or opr_army_manager == null:
		return null
	var own_slot := int(bearer.unit_properties.get("player_id", solo_controller.ai_slot))
	var enemy := kind == "enemy"
	var slot: int = own_slot
	if enemy:
		slot = solo_controller.human_slot if own_slot == solo_controller.ai_slot else solo_controller.ai_slot
	var best: GameUnit = null
	var best_v := -1.0
	for u in opr_army_manager.get_game_units_for_player(slot):
		var gu := u as GameUnit
		if gu == null or gu.get_alive_count() == 0 or SoloController.unit_in_reserve(gu):
			continue
		if gu.has_method("is_attached") and gu.is_attached():
			continue
		if kind == "friendly_caster" and RadialMenu._caster_member_of(gu) == null:
			continue
		if kind == "friendly_artillery" and not gu.has_special_rule("Artillery"):
			continue
		var d := MoveIntent.distance_inches(solo_controller.unit_centre(bearer), solo_controller.unit_centre(gu))
		if d > range_in:
			continue
		if needs_los and not _solo_has_los(bearer, gu):
			continue
		var v := float(gu.get_alive_count()) + float(_solo_unit_tough(gu))
		if v > best_v:
			best_v = v
			best = gu
	return best


## Apply every Utility-Buff rule the activating unit (incl. heroes) carries: the effect lands as an
## F4 once-mod record (the SAME machinery spell tokens use — hit/casting/morale readers + consume
## + logs, one truth). Re-Position Artillery instead shifts a friendly Artillery unit without LOS.
func _solo_apply_utility_buffs(unit: GameUnit) -> void:
	if solo_controller == null or opr_army_manager == null or unit == null or not _solo_is_ai_unit(unit):
		return
	var members: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		members = members + unit.get_attached_heroes()
	for m in members:
		var member := m as GameUnit
		if member == null or member.get_alive_count() == 0:
			continue
		for e in RulesRegistry.unit_rules_of_primitive(member, "Utility Buff"):
			var ed := e as Dictionary
			var n := str(ed["name"])
			var sp: Dictionary = ed.get("params", {})
			# Resolver wave A: vs-target Marks ("... Mark") are ENEMY-side picks consumed at the
			# attack seam (_solo_apply_vs_marks) — not friendly buffs; skip them here.
			if bool(sp.get("vs_target", false)):
				continue
			var range_in := float(sp.get("range_in", 12.0))
			# Re-Position Artillery: a friendly Artillery model may immediately move up to 9".
			if float(sp.get("reposition_in", 0.0)) > 0.0:
				var arty := _solo_utility_target(member, "friendly_artillery", range_in, false)
				if arty != null and solo_controller.best_shoot_target_now(arty) == null:
					var to_enemy := solo_controller.nearest_human_unit(arty)
					if to_enemy != null:
						var a := solo_controller.unit_centre(arty)
						var b := solo_controller.unit_centre(to_enemy)
						var moved := solo_controller.forced_straight_move(arty,
							Vector2(b.x - a.x, b.z - a.z), float(sp.get("reposition_in", 9.0)))
						if moved > 0.0 and battle_log != null:
							battle_log.log_event(BattleLog.Category.MOVEMENT,
								"%s: %s re-positions %s up to %.0f\" (no firing lane)" % [n, member.get_name(), arty.get_name(), moved], true)
				continue
			var kind := str(sp.get("target", "friendly"))
			var tgt := _solo_utility_target(member, kind, range_in, bool(sp.get("needs_los", false)))
			if tgt == null:
				continue
			var modifier := {"hit_mod": int(sp.get("hit_mod", 0)), "casting_mod": int(sp.get("casting_mod", 0)),
				"morale_mod": int(sp.get("morale_mod", 0))}
			_solo_record_spell_mod(tgt, n, {"modifier": modifier,
				"grants_rule": str(sp.get("grants_rule", "")), "scope": "", "beneficiary": "",
				"duration": ("once" if bool(sp.get("once", true)) else "round")})
			if battle_log != null:
				var bits: PackedStringArray = []
				if modifier["hit_mod"] != 0: bits.append("%+d to hit" % modifier["hit_mod"])
				if modifier["casting_mod"] != 0: bits.append("%+d casting" % modifier["casting_mod"])
				if modifier["morale_mod"] != 0: bits.append("%+d morale" % modifier["morale_mod"])
				if not str(sp.get("grants_rule", "")).is_empty(): bits.append("grants %s" % str(sp.get("grants_rule", "")))
				battle_log.log_event(BattleLog.Category.COMBAT, "%s: %s → %s (%s, once)" % [
					n, member.get_name(), tgt.get_name(), ", ".join(bits)], true)


## Bridge unit-level rule GRANTS (spell/mark overlays, NML-006) onto a weapon profile's parsed
## flags: a unit granted Relentless/Furious/Rending fights as if its weapons carried the rule —
## the hit/save readers are profile-flag based, the overlay is unit-level. No double counting
## (bridged only when the flag is not already set); the readers' own gates (charging, range,
## unmodified 6s) still decide whether anything fires.
func _solo_bridge_granted_flags(unit: GameUnit, profile: Dictionary) -> Dictionary:
	if unit == null:
		return profile
	var out := profile
	for flag in ["relentless", "furious", "rending"]:
		var rule: String = flag.capitalize()
		if not bool(out.get(flag, false)) and unit.has_special_rule(rule):
			if out == profile:
				out = profile.duplicate()
			out[flag] = true
	return out


## Takedown Shot / Takedown Strike (resolver wave A — "once per game, when this model shoots /
## when it's this model's turn to attack in melee, it may make one extra attack at Quality 2+
## with AP(2), Deadly(3), and Takedown"): appended as its OWN synthetic group so it rolls at its
## own Quality and never scales with the unit; the existing Takedown/Deadly landing (incl. the
## human's model-pick, B5) resolves it. `melee` selects the "… Strike" vs "… Shot" family member;
## the once-per-game flag lives on the bearer's props (uses_per_game pattern).
func _solo_takedown_bonus_groups(unit: GameUnit, melee: bool) -> Array:
	var out: Array = []
	if unit == null:
		return out
	for m in _solo_joined_chain(unit):
		var member := m as GameUnit
		if member.get_alive_count() == 0:
			continue
		for e in RulesRegistry.unit_rules_of_primitive(member, "Takedown"):
			var ed := e as Dictionary
			var n := str(ed["name"])
			if melee != n.ends_with("Strike"):
				continue
			var flag := "takedown_bonus_used_%s" % n
			if bool(member.unit_properties.get(flag, false)):
				continue
			member.unit_properties[flag] = true
			var sp: Dictionary = ed.get("params", {})
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT,
					"%s: %s makes one extra attack at Quality %d+ with AP(%d), Deadly(3), Takedown (once per game)" % [
					n, member.get_name(), int(sp.get("extra_attack_q", 2)), int(sp.get("ap", 2))], true)
			out.append({"name": member.get_name(), "quality": int(sp.get("extra_attack_q", 2)),
				"fatigued": member.is_fatigued, "member": member,
				"profiles": [{"name": n, "attacks": 1, "count": 1, "ap": int(sp.get("ap", 2)),
					"deadly": int(sp.get("deadly", 3)), "takedown": true, "range": 0, "rules": []}]})
			break   # one bonus attack per member even if books duplicate the rule
	return out


## Hazardous self-wound half (resolver wave A): every unmodified 1 rolled to hit with a Hazardous
## weapon wounds the FIRER's unit ("this model's unit takes one wound on unmodified rolls of 1 to
## hit"). Direct wounds — no save, same as Dangerous terrain; fires at all three hit-roll seams.
func _solo_hazardous_self_wounds(owner_unit: GameUnit, profile: Dictionary, faces: Array) -> void:
	if owner_unit == null or not bool(profile.get("hazardous", false)):
		return
	var ones := 0
	for f in faces:
		if int(f) == 1:
			ones += 1
	if ones <= 0:
		return
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT,
			"Hazardous: %s rolls %d unmodified 1%s to hit — takes %d wound%s" % [
			owner_unit.get_name(), ones, ("" if ones == 1 else "s"), ones, ("" if ones == 1 else "s")], true)
	_solo_apply_wounds(owner_unit, ones)


## Unwieldy (resolver wave A — "strikes last when charging"): any chain member carrying the rule
## makes the whole charging unit resolve its strikes AFTER the defender's strike-back.
func _solo_unit_has_unwieldy(unit: GameUnit) -> bool:
	if unit == null:
		return false
	for m in _solo_joined_chain(unit):
		if not RulesRegistry.unit_rules_of_primitive(m as GameUnit, "Unwieldy").is_empty():
			return true
	return false


## Deathstrike + Self-Destruct death-half (resolver wave A — "if this model is killed in melee,
## the attacking unit takes X hits"): fires after a strike phase's wounds landed. Per chain member:
## a unit-level Self-Destruct pays X hits per model killed this phase; an upgrade-level Deathstrike
## pays X once when its member just emptied (the casualty order keeps special models alive longest,
## so the carrier is the LAST to fall). Hits save at the striker's Shielded Defense, no AP
## (the Retaliate pattern), and never chain.
func _solo_deathstrike_hits(defender: GameUnit, striker: GameUnit, alive_before: Dictionary) -> void:
	if defender == null or striker == null or _solo_combined_alive(striker) <= 0:
		return
	var total_hits := 0
	var rule_name := ""
	for m in _solo_joined_chain(defender):
		var member := m as GameUnit
		var before := int(alive_before.get(member.get_instance_id(), member.get_alive_count()))
		var killed := before - member.get_alive_count()
		if killed <= 0:
			continue
		for e in RulesRegistry.unit_rules_of_primitive(member, "Deathstrike"):
			var ed := e as Dictionary
			rule_name = str(ed["name"])
			var x := maxi(int(ed.get("rating", 0)), 1)
			total_hits += x * killed
			break
		for e2 in RulesRegistry.unit_rules_of_primitive(member, "Self-Destruct"):
			var ed2 := e2 as Dictionary
			rule_name = str(ed2["name"])
			var x2 := maxi(int(ed2.get("rating", 0)), 1)
			total_hits += x2 * killed
			break
	if total_hits <= 0:
		return
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT,
			"%s: %s's dying models lash out — %s takes %d hit%s" % [
			rule_name, defender.get_name(), striker.get_name(), total_hits, ("" if total_hits == 1 else "s")], true)
	var dprofile: Dictionary = {"name": rule_name, "ap": 0, "deadly": 0, "rules": []}
	var dw: int = await _solo_resolve_saves(defender, striker, rule_name, [], total_hits,
		_solo_shielded_defense(striker), dprofile, not _solo_is_ai_unit(striker), true)
	if dw > 0:
		await _solo_land_wounds(striker, dw, 0)


## Self-Destruct survival half (resolver wave A — "if this model survives melee, after both sides
## have finished attacking, it is immediately killed, and the enemy unit takes X hits"): runs once
## per melee for BOTH combatants, before morale. The detonation kills every surviving carrier.
func _solo_self_destruct_post_melee(unit: GameUnit, enemy: GameUnit) -> void:
	if unit == null or enemy == null:
		return
	for m in _solo_joined_chain(unit):
		var member := m as GameUnit
		var alive := member.get_alive_count()
		if alive <= 0:
			continue
		for e in RulesRegistry.unit_rules_of_primitive(member, "Self-Destruct"):
			var ed := e as Dictionary
			var n := str(ed["name"])
			var x := maxi(int(ed.get("rating", 0)), 1)
			var hits := x * alive
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT,
					"%s: %s detonates after the melee — destroyed; %s takes %d hit%s" % [
					n, member.get_name(), enemy.get_name(), hits, ("" if hits == 1 else "s")], true)
			_solo_apply_wounds(member, 9999)   # "it is immediately killed" — all surviving carriers
			if _solo_combined_alive(enemy) > 0:
				var sprofile: Dictionary = {"name": n, "ap": 0, "deadly": 0, "rules": []}
				var sw: int = await _solo_resolve_saves(member, enemy, n, [], hits,
					_solo_shielded_defense(enemy), sprofile, not _solo_is_ai_unit(enemy), true)
				if sw > 0:
					await _solo_land_wounds(enemy, sw, 0)
			break


## vs-target Marks (resolver wave A — "once per activation, before attacking, pick one enemy unit
## within 18\" in line of sight, which friendly units gets <Rule> against once"): the pick IS the
## attack target (the one enemy the bearer is about to fight — the rule's natural use), and the
## mark is consumed by this very attack: the base rule ("<Name> Mark" minus " Mark") lands on the
## attacker as a once-grant through the NML-006 overlay, so every existing reader honours it and
## the once-mod consumption revokes it after the exchange. Symmetric: both volley paths + melee.
func _solo_apply_vs_marks(attacker: GameUnit, target: GameUnit, dist_in: float) -> void:
	if attacker == null or target == null or opr_army_manager == null:
		return
	for m in _solo_joined_chain(attacker):
		var member := m as GameUnit
		if member.get_alive_count() == 0:
			continue
		for e in RulesRegistry.unit_rules_of_primitive(member, "Utility Buff"):
			var ed := e as Dictionary
			var sp: Dictionary = ed.get("params", {})
			if not bool(sp.get("vs_target", false)):
				continue
			var n := str(ed["name"])
			if int(member.unit_properties.get("vs_mark_round", -1)) == opr_army_manager.current_round:
				continue   # once per activation — at most one activation per round (Second Wind aside)
			if dist_in > float(sp.get("range_in", 18.0)):
				continue
			member.unit_properties["vs_mark_round"] = opr_army_manager.current_round
			var base := n.trim_suffix(" Mark")
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s: %s marks %s — %s applies to this attack" % [
					n, member.get_name(), target.get_name(), base], true)
			_solo_record_spell_mod(attacker, n, {"grants_rule": base, "scope": "", "beneficiary": "",
				"duration": "once"})


## Reckless Piercing (resolver wave A — "when activated, you may roll one die. On a 2+ their
## weapons get AP(+1) when attacking until the end of the round, but on a 1 enemy units get AP(+1)
## when attacking them instead"): one real tray die at the before-attacking slot; the outcome is a
## round-scoped props stamp read by _solo_reckless_ap at every AP seam. The AI always opts in — the
## 5-in-6 upside dwarfs the backfire.
func _solo_apply_reckless_piercing(unit: GameUnit) -> void:
	if opr_army_manager == null or unit == null:
		return
	for e in RulesRegistry.unit_rules_of_primitive(unit, "Reckless Piercing"):
		var ed := e as Dictionary
		var n := str(ed["name"])
		var sp: Dictionary = ed.get("params", {})
		if int(unit.unit_properties.get("reckless_rolled_round", -1)) == opr_army_manager.current_round:
			break
		unit.unit_properties["reckless_rolled_round"] = opr_army_manager.current_round
		var tgt_v := int(sp.get("roll_target", 2))
		var who := "AI (%s)" % unit.get_name() if _solo_is_ai_unit(unit) else unit.get_name()
		var faces: Array = await _solo_tray_roll(1, tgt_v, who)
		var face: int = int(faces[0]) if not faces.is_empty() else 1
		if face >= tgt_v:
			for cm in _solo_joined_chain(unit):
				(cm as GameUnit).unit_properties["reckless_ap_round"] = opr_army_manager.current_round
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT,
					"%s: %s rolls %d — weapons get AP(+1) until the end of the round" % [n, unit.get_name(), face], true)
		else:
			for cm in _solo_joined_chain(unit):
				(cm as GameUnit).unit_properties["reckless_backfire_round"] = opr_army_manager.current_round
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT,
					"%s: %s rolls a 1 — enemies get AP(+1) against it until the end of the round" % [n, unit.get_name()], true)
		break


## Net Reckless-Piercing AP bonus for one attack: +1 when the ATTACKER's chain carries this round's
## buff stamp, +1 more when the TARGET's chain carries this round's backfire stamp.
func _solo_reckless_ap(attacker: GameUnit, target: GameUnit) -> int:
	if opr_army_manager == null:
		return 0
	var r := opr_army_manager.current_round
	var bonus := 0
	if attacker != null:
		for u in _solo_joined_chain(attacker):
			if int((u as GameUnit).unit_properties.get("reckless_ap_round", -1)) == r:
				bonus += 1
				break
	if target != null:
		for u in _solo_joined_chain(target):
			if int((u as GameUnit).unit_properties.get("reckless_backfire_round", -1)) == r:
				bonus += 1
				break
	return bonus


## Mind Control ("pick one enemy within 18\" in LOS, it takes a morale test; if failed you may move
## it up to 6\" in a straight line"): the AI pulls the holder OFF the marker it defends — denial by
## displacement. One real tray die vs Quality; the shift is the shared forced straight move.
func _solo_apply_mind_control(unit: GameUnit) -> void:
	if solo_controller == null or unit == null or not _solo_is_ai_unit(unit):
		return
	var members: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		members = members + unit.get_attached_heroes()
	for m in members:
		var member := m as GameUnit
		if member == null or member.get_alive_count() == 0:
			continue
		for e in RulesRegistry.unit_rules_of_primitive(member, "Mind Control"):
			var ed := e as Dictionary
			var n := str(ed["name"])
			var sp: Dictionary = ed.get("params", {})
			var tgt := _solo_utility_target(member, "enemy", float(sp.get("range_in", 18.0)), bool(sp.get("needs_los", true)))
			if tgt == null:
				continue
			var q := tgt.get_quality()
			var faces: Array = await _solo_tray_roll(1, q, "AI (%s)" % member.get_name())
			var passed: bool = not faces.is_empty() and int(faces[0]) >= q
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s: %s forces a morale test on %s — %s" % [
					n, member.get_name(), tgt.get_name(), ("passed" if passed else "FAILED")], true)
			if passed:
				continue
			# Fatigue Debuff (resolver wave A): the failed test fatigues instead of displacing —
			# the target strikes on unmodified 6s in melee until it next activates.
			if str(sp.get("effect", "")) == "fatigue":
				for cm in _solo_joined_chain(tgt):
					(cm as GameUnit).is_fatigued = true
				if battle_log != null:
					battle_log.log_event(BattleLog.Category.COMBAT,
						"%s: %s is FATIGUED (melee hits only on unmodified 6s)" % [n, tgt.get_name()], true)
				continue
			# Displace away from the marker the target is nearest to (denial), else away from us.
			var c := solo_controller.unit_centre(tgt)
			var away := Vector2(c.x - solo_controller.unit_centre(member).x, c.z - solo_controller.unit_centre(member).z)
			var obj := solo_controller._nearest_uncontrolled_objective(c, null)
			if obj != SoloController.NO_OBJECTIVE:
				away = Vector2(c.x - obj.x, c.z - obj.z)
			var moved := solo_controller.forced_straight_move(tgt, away, float(sp.get("move_in", 6.0)))
			if moved > 0.0 and battle_log != null:
				battle_log.log_event(BattleLog.Category.MOVEMENT,
					"%s: %s is moved %.0f\" in a straight line (away from the marker)" % [n, tgt.get_name(), moved], true)


## Piercing Tag ("once per game … place X markers on an enemy within 24\"/LOS; attackers remove
## markers before rolling to block for +AP(Y)"): the AI tags the TOUGHEST enemy; the next friendly
## volley against it spends every marker (+AP per marker) — see _solo_spend_piercing_tag.
func _solo_apply_piercing_tag(unit: GameUnit) -> void:
	if solo_controller == null or unit == null or not _solo_is_ai_unit(unit):
		return
	var members: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		members = members + unit.get_attached_heroes()
	for m in members:
		var member := m as GameUnit
		if member == null or member.get_alive_count() == 0:
			continue
		for e in RulesRegistry.unit_rules_of_primitive(member, "Piercing Tag"):
			var ed := e as Dictionary
			var n := str(ed["name"])
			if bool(member.unit_properties.get("piercing_tag_used", false)):
				continue
			var sp: Dictionary = ed.get("params", {})
			var tgt := _solo_utility_target(member, "enemy", float(sp.get("range_in", 24.0)), bool(sp.get("needs_los", true)))
			if tgt == null:
				continue
			member.unit_properties["piercing_tag_used"] = true
			var markers: int = maxi(int((e as Dictionary).get("rating", 0)), 1)
			tgt.unit_properties["piercing_tag_markers"] = int(tgt.unit_properties.get("piercing_tag_markers", 0)) + markers
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT,
					"%s: %s places %d marker%s on %s — friendly attackers may spend them for +AP" % [
					n, member.get_name(), markers, ("" if markers == 1 else "s"), tgt.get_name()], true)


## Spend every Piercing-Tag marker on the target for +AP(markers) on THIS volley (the AI spends all
## at once — markers are a shared resource and the first big volley is the best use). Returns bonus.
func _solo_spend_piercing_tag(target: GameUnit) -> int:
	if target == null:
		return 0
	var markers := int(target.unit_properties.get("piercing_tag_markers", 0))
	if markers <= 0:
		return 0
	target.unit_properties["piercing_tag_markers"] = 0
	if battle_log != null:
		battle_log.log_event(BattleLog.Category.COMBAT,
			"Piercing Tag: %d marker%s spent — +AP(%d) on this volley" % [markers, ("" if markers == 1 else "s"), markers], true)
	return markers


## Coverage wave — Crossing Attack(X) ("once per activation, when this model moves through enemy
## units, pick one of them and roll X dice; each 6+ = one wound"): the Strafing trigger seam —
## trails vs enemy bases, nearest crossed enemy, direct wounds (no hit roll, no save; Regeneration
## applies — no ignore clause in the text).
func _solo_apply_crossing_attack(unit: GameUnit) -> void:
	if unit == null or solo_controller == null or not _solo_is_ai_unit(unit) \
			or solo_controller.last_move_paths.is_empty():
		return
	var members: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		members = members + unit.get_attached_heroes()
	for m in members:
		var member := m as GameUnit
		if member == null or member.get_alive_count() == 0:
			continue
		for e in RulesRegistry.unit_rules_of_primitive(member, "Crossing Attack"):
			var ed := e as Dictionary
			var n := str(ed["name"])
			var dice: int = maxi(int(ed.get("rating", 0)), 1)
			var wound_target := int((ed.get("params", {}) as Dictionary).get("wound_target", 6))
			var trails: Array = []
			for mp in solo_controller.last_move_paths:
				trails.append((mp as Dictionary).get("path", []))
			var crossed: Array = []
			for eo in opr_army_manager.get_game_units_for_player(solo_controller.enemy_slot_of(member)):
				var eu := eo as GameUnit
				if eu == null or eu.get_alive_count() <= 0 or SoloController.unit_in_reserve(eu):
					continue
				if eu.has_method("is_attached") and eu.is_attached():
					continue
				if SoloController.trails_cross_unit_bases(trails, eu.models):
					crossed.append(eu)
			if crossed.is_empty():
				return
			crossed.sort_custom(func(a, b) -> bool:
				return MoveIntent.distance_inches(solo_controller.unit_centre(unit), solo_controller.unit_centre(a)) \
					< MoveIntent.distance_inches(solo_controller.unit_centre(unit), solo_controller.unit_centre(b)))
			var target := crossed[0] as GameUnit
			var faces: Array = await _solo_tray_roll(dice, wound_target, "AI (%s)" % member.get_name())
			var wounds := 0
			for f in faces:
				if int(f) >= wound_target:
					wounds += 1
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT,
					"%s(%d): %s moves through %s — %d wound%s (no save)" % [
					n, dice, member.get_name(), target.get_name(), wounds, ("" if wounds == 1 else "s")], true)
			if wounds > 0:
				await _solo_land_wounds(target, wounds, 0)
			return   # once per activation


# === Coverage wave: the Growth-Marker family (Defensive Frenzy / Piercing Growth / Precision Growth) ===

## Marker count for one growth rule (state: unit_properties["growth_<rule>"], capped by the rule).
func _solo_growth_markers(unit: GameUnit, rule_name: String) -> int:
	return int(unit.unit_properties.get("growth_%s" % rule_name.to_snake_case(), 0))


## Round-start accrual: +1 marker per per_round growth rule while the unit stands and isn't Shaken
## (both sides — the state is deterministic bookkeeping; the log names every tick).
func _solo_growth_round_start() -> void:
	if opr_army_manager == null:
		return
	for u in opr_army_manager.get_all_game_units():
		var gu := u as GameUnit
		if gu == null or gu.get_alive_count() == 0 or gu.is_shaken or SoloController.unit_in_reserve(gu):
			continue
		if gu.has_method("is_attached") and gu.is_attached():
			continue
		for e in RulesRegistry.unit_rules_of_primitive(gu, "Growth Markers"):
			var ed := e as Dictionary
			var sp: Dictionary = ed.get("params", {})
			if not bool(sp.get("per_round", false)):
				continue
			var n := str(ed["name"])
			var key := "growth_%s" % n.to_snake_case()
			var cur := int(gu.unit_properties.get(key, 0))
			var cap := int(sp.get("max_markers", 4))
			if cur < cap:
				gu.unit_properties[key] = cur + 1
				if battle_log != null:
					battle_log.log_event(BattleLog.Category.GENERAL, "%s: %s gains a marker (%d/%d)" % [
						n, gu.get_name(), cur + 1, cap], _solo_is_ai_unit(gu))


## On-kill accrual (Defensive Frenzy: "place one marker when it fully destroys an enemy unit").
func _solo_growth_on_kill(attacker: GameUnit) -> void:
	if attacker == null:
		return
	for e in RulesRegistry.unit_rules_of_primitive(attacker, "Growth Markers"):
		var ed := e as Dictionary
		var sp: Dictionary = ed.get("params", {})
		if not bool(sp.get("on_kill", false)):
			continue
		var n := str(ed["name"])
		var key := "growth_%s" % n.to_snake_case()
		var cur := int(attacker.unit_properties.get(key, 0))
		var cap := int(sp.get("max_markers", 2))
		if cur < cap:
			attacker.unit_properties[key] = cur + 1
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s: %s gains a marker for the kill (%d/%d)" % [
					n, attacker.get_name(), cur + 1, cap], _solo_is_ai_unit(attacker))


## Defense bonus from growth markers (Defensive Frenzy: +1 Defense per marker).
func _solo_growth_defense_bonus(unit: GameUnit) -> int:
	var bonus := 0
	for e in RulesRegistry.unit_rules_of_primitive(unit, "Growth Markers"):
		var ed := e as Dictionary
		var sp: Dictionary = ed.get("params", {})
		var per := int(sp.get("defense_per_marker", 0))
		if per > 0:
			bonus += per * _solo_growth_markers(unit, str(ed["name"]))
	return bonus


## Attack-side growth bonuses: {"ap": int, "hit": int} (Piercing/Precision Growth: per two markers).
func _solo_growth_attack_bonus(unit: GameUnit) -> Dictionary:
	var out := {"ap": 0, "hit": 0}
	for e in RulesRegistry.unit_rules_of_primitive(unit, "Growth Markers"):
		var ed := e as Dictionary
		var sp: Dictionary = ed.get("params", {})
		var pairs: int = _solo_growth_markers(unit, str(ed["name"])) / 2
		out["ap"] += int(sp.get("ap_per_two", 0)) * pairs
		out["hit"] += int(sp.get("hit_per_two", 0)) * pairs
	return out


## Coverage wave — Storm Attack family (chaos "Storm of X": "Once per game, when this model is
## activated, before attacking, roll 3 dice. For each 2+ one enemy unit within 12\" takes 3 hits
## with <facet>."): generic resolver, facet-parameterised (surge = extra hit on 6 per hit die,
## shred / bane ride the save batch, ap1 = AP(1)). Once per game per bearer; AI-side automation
## (human bearers keep their manual workflow, like Mend/Breath).
func _solo_apply_storm_attack(unit: GameUnit) -> void:
	if unit == null or opr_army_manager == null or solo_controller == null or not _solo_is_ai_unit(unit):
		return
	var bearers: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		bearers = bearers + unit.get_attached_heroes()
	for b in bearers:
		var bu := b as GameUnit
		if bu == null or bu.get_alive_count() == 0:
			continue
		for e in RulesRegistry.unit_rules_of_primitive(bu, "Storm Attack"):
			var ed := e as Dictionary
			var n := str(ed["name"])
			var flag := "storm_used_%s" % n.to_snake_case()
			if bool(bu.unit_properties.get(flag, false)):
				continue
			var sp: Dictionary = ed.get("params", {})
			var range_in := float(sp.get("range_in", 12.0))
			# Fire only when at least one enemy is in reach (don't waste the once-per-game).
			var targets_in_reach: Array = []
			for h in opr_army_manager.get_game_units_for_player(solo_controller.enemy_slot_of(bu)):
				var hu := h as GameUnit
				if hu == null or _solo_combined_alive(hu) <= 0 or SoloController.unit_in_reserve(hu):
					continue
				if hu.has_method("is_attached") and hu.is_attached():
					continue
				if _solo_nearest_model_gap_in(unit, hu, INF) <= range_in:
					targets_in_reach.append(hu)
			if targets_in_reach.is_empty():
				continue
			bu.unit_properties[flag] = true
			var dice := int(sp.get("dice", 3))
			var trigger := int(sp.get("trigger_target", 2))
			var faces: Array = await _solo_tray_roll(dice, trigger, "AI (%s)" % bu.get_name())
			var successes := 0
			for f in faces:
				if int(f) >= trigger:
					successes += 1
			if battle_log != null:
				battle_log.log_event(BattleLog.Category.COMBAT, "%s: %s unleashes the storm — %d of %d dice hit (once per game)" % [
					n, bu.get_name(), successes, dice], true)
			var facet := str(sp.get("facet", "ap1"))
			var profile := {"name": n, "attacks": int(sp.get("hits", 3)),
				"ap": (1 if facet == "ap1" else 0), "shred": facet == "shred", "rules": []}
			var bane: bool = facet == "bane"
			for _i in range(successes):
				# Best target per success (repeatable — the text allows stacking the same unit).
				targets_in_reach.sort_custom(func(a, b) -> bool:
					return _solo_combined_alive(a as GameUnit) > _solo_combined_alive(b as GameUnit))
				var tgt := targets_in_reach[0] as GameUnit
				var hits := int(sp.get("hits", 3))
				if facet == "surge":
					var s_faces: Array = await _solo_tray_roll(hits, 6, "AI (%s)" % bu.get_name())
					for sf in s_faces:
						if int(sf) == 6:
							hits += 1
				var w: int = await _solo_resolve_saves(bu, tgt, n, [], hits,
					_solo_shielded_defense(tgt), profile, not _solo_is_ai_unit(tgt), false, true, false, range_in)
				await _solo_land_wounds(tgt, w, 0)
				if _solo_combined_alive(tgt) <= 0:
					targets_in_reach.erase(tgt)
					if targets_in_reach.is_empty():
						break
