class_name ObjectManager
extends Node3D
## Manages all game objects: miniatures, dice, terrain
## Handles spawning, selection, dragging, and rotation

signal selection_changed(selected_objects: Array[Node3D])
signal distance_changed(distance_inches: float, from_pos: Vector3, to_pos: Vector3)
signal measurement_finished(distance_inches: float)
signal drag_ended()
## A drag actually MOVED objects (> 0.1"): one entry per moved object with its exact table positions —
## {node: Node3D, from: Vector3, to: Vector3, inches: float}. Battle-Log seam today (main groups the
## entries per unit for the log line); deliberately REPLAY-GRADE (from→to coordinates) so a future event
## journal can record and play back full games (see ROADMAP: Game replay).
signal selection_dropped(moves: Array)
## Emitted (throttled) while dragging, so listeners can refresh live feedback
## such as unit coherency without waiting for the drag to finish.
signal drag_updated()
signal context_menu_requested(screen_pos: Vector2, selected_objects: Array)

@export var drag_height: float = 0.5  # Drag height in meters
@export var min_drag_height: float = 0.01  # Minimum height above table when dragging
@export var drag_lift_height: float = 0.05  # Lift height when dragging (5cm)

# Multi-selection support
var _selected_objects: Array[Node3D] = []
var _is_dragging: bool = false
var _drag_plane: Plane
var _object_counter: int = 0

# Selection mode control (can be disabled for map layout mode)
var selection_enabled: bool = true

# Undo/redo history (injected by main.gd); move and rotate gestures recorded here.
var undo_manager: UndoManager = null

# Hover highlight: glows the selectable currently under the cursor so it is
# unambiguous which object a click will select.
var _hover_glow: HoverGlow = HoverGlow.new()

# Persistent green glow for selected objects (replaces the old base ring).
var _selection_glow_material: StandardMaterial3D = null

# Clipboard for copy/paste
var _clipboard: Array[Node3D] = []  # Stores references to copied objects for duplication

# Rotation tracking
var _is_rotating: bool = false
var _rotation_broadcast_timer: float = 0.0
var _move_broadcast_timer: float = 0.0
const ROTATION_BROADCAST_INTERVAL: float = 0.066  # ~15 Hz
const MOVE_BROADCAST_INTERVAL: float = 0.05  # ~20 Hz

# Undo capture: rotation.y per object snapshotted at the start of a rotate
# gesture; committed as one RotateAction when the gesture ends.
var _rotation_capture: Dictionary = {}
# Minimum change before a gesture is recorded as undoable (avoids no-op entries).
const MOVE_UNDO_EPSILON_M: float = 0.001  # 1 mm
const ROTATION_UNDO_EPSILON_RAD: float = 0.0001  # ~0.006 degrees

# Throttle for live coherency feedback while dragging (~15 Hz).
const COHERENCY_UPDATE_INTERVAL: float = 0.066
var _coherency_update_timer: float = 0.0

# Sort Table animation: all models start moving at once but with slightly
# randomized durations so the swarm looks busy ("wuselig") rather than robotic.
const SORT_ANIM_DURATION: float = 1.2  # Base travel time in seconds
const SORT_ANIM_DURATION_JITTER: float = 0.35  # +/- random variation per model
const SORT_ANIM_RESTING_Y: float = 0.0  # Table surface height for all models

# Drag distance tracking
var _drag_start_positions: Dictionary = {}  # Object -> start position mapping
var _drag_anchor_position: Vector3 = Vector3.ZERO  # Primary drag anchor point
var _drag_grab_world: Vector3 = Vector3.ZERO  # Cursor table position at grab (preserves grab offset)
var _drag_line: MeshInstance3D = null  # Visual line during drag
var _drag_label: Label3D = null  # Distance label during drag

# Rotation gesture: a floating label showing the cumulative degrees rotated, anchored
# above the first selected object. Reused across both plain-R and Shift+R gestures.
var _rotation_label: Label3D = null
var _rotation_accumulated_deg: float = 0.0
const ROTATION_LABEL_Y: float = 0.08  # label height above the pivot object (metres)
## 20% of the original 22pt = ~4pt; the label is a billboard so it stays legible.
const ROTATION_LABEL_FONT_SIZE: int = 4

# Box selection (drag rectangle to select multiple objects)
var _is_box_selecting: bool = false
var _box_select_start: Vector2 = Vector2.ZERO
var _box_select_end: Vector2 = Vector2.ZERO
var _box_select_rect: ColorRect = null

# Measurement mode (Shift+Left-click to measure)
var _is_measuring: bool = false
var _measure_start_position: Vector3 = Vector3.ZERO
var _measure_start_snapped: bool = false  # True if start point snapped to object
var _measure_end_snapped: bool = false    # True if end point snapped to object
var _measure_start_object: Node3D = null  # Reference to start object for edge calculation
var _measure_end_object: Node3D = null    # Reference to end object for edge calculation
var _measure_line: MeshInstance3D = null
var _measure_label: Label3D = null
var _measure_los_warning: Label3D = null  # Warning icon for LOS blocking (🚫)
var _measure_front_label: Label3D = null  # Regiment facing aid (front vs flank/rear)

# Base-anchored range rings ("auras"): G cycles the ring range on selected models,
# Shift+G clears all. The RangeRingController (injected by main.gd) owns the per-model
# rings; local-only display aid. See scripts/range_ring_controller.gd.
var range_ring_controller: Node = null

# Movement reach indicator: M toggles the Advance + Rush/Charge bands on selected models,
# Shift+M clears all. The MovementRangeController (injected by main.gd) owns the per-model
# rings; local-only display aid. See scripts/movement_range_controller.gd.
var movement_range_controller: Node = null

# Movement cap: an opt-in limit so a dragged model/unit can't move further than its Advance or
# Rush/Charge allowance. OFF = free drag (sandbox default). Set from the HUD "Movement" area.
enum MovementCap { OFF, ADVANCE, RUSH }
var _movement_cap: int = MovementCap.OFF
var _movement_cap_meters: float = 0.0  # the active cap distance for the current drag (0 = no cap)

# Persistent shared rulers: a live measurement can be PINNED (key P) so it stays on the
# table and replicates to all players in the owner's colour. `pinned_rulers` (the
# PinnedRulers manager) is injected by main.gd. Right-click on a ruler removes it, K
# clears mine, Shift+K (host) clears all. Session-only — see scripts/pinned_rulers.gd.
var pinned_rulers: Node = null
var _ruler_id_counter: int = 0
## Snapshot of the live measurement so P can freeze exactly what is on screen.
var _measure_last_from: Vector3 = Vector3.ZERO
var _measure_last_to: Vector3 = Vector3.ZERO
var _measure_last_distance: float = 0.0
var _measure_last_blocked: bool = false
var _measure_has_value: bool = false
## Pick tolerance (metres) when right-clicking a ruler to remove it.
const RULER_REMOVE_RADIUS_M: float = 0.02
## Owner id used for pinned rulers in solo play (no multiplayer peer).
const SOLO_OWNER_PEER: int = 1

const METERS_TO_INCHES: float = 39.3701

## Max edge gap (meters) used when auto-arranging, so the smallest base stays
## within OPR 1" coherency of its neighbour (kept just under 1" = 0.0254 m).
const ARRANGE_COHERENCY_GAP: float = 0.022

# Network manager reference
var _network_manager: Node = null

## Lazily-created ruin GLB/manifest resolver for free-placed sandbox terrain (the GLB scene
## cache is static, so this instance shares parsed scenes with the terrain overlay's library).
var _ruins_library: RuinsLibrary = null
## Lazily-created tree GLB resolver for sandbox forest clusters (shared static scene cache).
var _trees_library: TreesLibrary = null
var _biome_library: BiomeLibrary = null  # battlemaps cropped for non-grassland forest floors
var _hazards_library: HazardsLibrary = null  # GLB hazard props (lava crater, carnivore plant) per biome

## Casual terrain edit mode. OFF by default: all sandbox terrain is LOCKED so players can't
## drag or delete it by accident during play. Turning it on (via the terrain shelf) unlocks
## the pieces for arranging; turning it off re-locks them.
var _terrain_edit_mode: bool = false

# Terrain overlay reference (for terrain hints)
var terrain_overlay: Node3D = null

# Preload resources (will be scenes in full version)
# Standard wargaming miniature sizes
const MINIATURE_HEIGHT: float = 0.032  # 32mm height
const MINIATURE_RADIUS: float = 0.016  # 32mm diameter base (16mm radius)

## Physics layers: ground (table + terrain props) on layer 1, miniatures on layer 2.
## The placement raycast masks ground-only so models rest on terrain, not on each other.
## Selection/measure/hover raycasts use all layers (0xFFFFFFFF), so they are unaffected.
## NOTE: kept in sync with the same constants in opr_army_manager.gd (model wrappers).
const GROUND_COLLISION_LAYER: int = 1
const MINIATURE_COLLISION_LAYER: int = 2
## Player-movable sandbox terrain (free-placed ruins/forests/hazard clusters). Props also
## carry the ground bit so minis settle on their floors; this extra bit marks them as
## movable terrain for selection/layouter tooling. Kept in sync with SandboxTerrainProp.
const MOVABLE_TERRAIN_COLLISION_LAYER: int = 4

## Casual-sandbox terrain categories (see SandboxTerrainProp / TerrainGroupBase).
enum SandboxPropKind { RUIN, FOREST, HAZARD_CLUSTER }

## Surface raycast probe: cast straight down from this height to this depth (metres) at a
## model's base centre to find the highest ground surface beneath it (table top = 0).
const SURFACE_PROBE_TOP_Y: float = 5.0
const SURFACE_PROBE_BOTTOM_Y: float = -1.0

## Regiment facing aid (measure tool): target in the front arc vs flank/rear.
const MEASURE_FRONT_COLOR: Color = Color(0.20, 0.85, 0.95)  # cyan, matches the arrow
const MEASURE_FLANK_COLOR: Color = Color(0.95, 0.70, 0.20)  # amber, matches the flank wedges
const MEASURE_REAR_COLOR: Color = Color(0.90, 0.25, 0.25)   # red, matches the rear wedge
## Smaller font for the arc-quadrant label (20% of the original 18pt = ~4pt; the
## label is a billboard so it stays legible up close without crowding the table).
const MEASURE_AID_FONT_SIZE: int = 4
const MEASURE_AID_Y: float = 0.06  # label height above the table

## Table-UI overlays (measure line/label, drag line/label, LOS warning) must draw ABOVE the ground
## decals — blood/oil stains (transparent, render_priority 1), deployment zones (2), seize rings (3)
## — so a stain never hides them (issue #82). The LINES must also join the transparent queue, since
## an opaque material is always painted over by transparent stains regardless of no_depth_test.
const OVERLAY_UI_RENDER_PRIORITY: int = 8
const OVERLAY_UI_LABEL_PRIORITY: int = 9


func _ready() -> void:
	_drag_plane = Plane(Vector3.UP, 0)

	# Get network manager reference (deferred to ensure scene is ready)
	call_deferred("_get_network_manager")

	# Rebuild selection spill lights when the graphics preset changes (a drop to a
	# tier without the lights removes them; a raise adds/recaps them).
	GraphicsSettings.settings_applied.connect(_on_graphics_settings_applied)


func _get_network_manager() -> void:
	_network_manager = get_node_or_null("/root/Main/NetworkManager")


func _process(delta: float) -> void:
	# Rotation while R is held: every selected piece turns to FACE THE MOUSE CURSOR (aim, don't
	# guess — community feedback). Regiment trays pivot the whole block around the tray centre; loose
	# models each pivot in place around their OWN base, so a multi-model selection all "looks" the
	# same way at once. The cumulative degrees from the gesture's start facing show next to the piece.
	if _is_rotating and _selected_objects.size() > 0:
		if _selection_is_regiment_only():
			_rotate_regiments_to_cursor(delta)
		else:
			_rotate_loose_to_cursor(delta)
	else:
		_rotation_broadcast_timer = 0.0


## Checks if a GUI element is blocking input (e.g., modal dialog or a focused text
## field like the chat input — object shortcuts must not fire while typing). Also true
## while a REMOTE peer is loading: object move/edit must be blocked until they finish (the
## non-loading player is held back). Camera/pan/zoom/chat are NOT routed through this gate.
func _is_gui_blocking_input() -> bool:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return true
	# A remote peer is mid-load (importing an army / syncing state): freeze object edits.
	if _network_manager != null and _network_manager.is_any_remote_peer_busy():
		return true
	# Check if any modal Control is visible and covering the viewport
	var ui_layer = get_tree().root.find_child("UI", true, false)
	if ui_layer:
		# Check for WoundsDialog or other modal dialogs
		var wounds_dialog = ui_layer.find_child("WoundsDialog", false, false)
		if wounds_dialog and wounds_dialog is Control and wounds_dialog.visible:
			return true
	return false


## D6 UI-occlusion decision (pure, unit-tested): a hovered control blocks the 3D-world click when it is a
## genuine HUD WIDGET — a STOP-filter control that does NOT span the whole viewport. The transparent
## full-rect HUD root (a STOP Control that merely holds the overlay) must NOT block, or every world click
## is occluded and nothing in the 3D scene is selectable (URGENT-024). IGNORE/PASS controls and empty
## space (null) never block, so field-clicks over the open scene still select/deselect.
func _control_blocks_world_click(hovered: Control) -> bool:
	if hovered == null or hovered.mouse_filter != Control.MOUSE_FILTER_STOP:
		return false
	var vp: Vector2 = hovered.get_viewport_rect().size
	var r: Vector2 = hovered.get_global_rect().size
	if r.x >= vp.x - 1.0 and r.y >= vp.y - 1.0:
		return false   # full-viewport container (HUD root) — not a click target
	return true


func _input(event: InputEvent) -> void:
	# Skip if GUI is handling input (dialog open, etc.)
	if _is_gui_blocking_input():
		return

	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton

		# A click over ANY interactive HUD control (dice tray, unit-dock card/strip/tab, panels) must
		# NOT reach the 3D world: _input fires before the control's _gui_input, so the control can't
		# consume it first. Without this, a click over the dock falls through, the selection raycast
		# finds nothing behind the UI, deselects the unit, hides the dock card, and nulls the action
		# target (the D6 dead-button + vanishing-card bug). Generalises the former dice-tray-only guard.
		# Motion still passes so camera drag over UI keeps working.
		if _control_blocks_world_click(get_viewport().gui_get_hovered_control()):
			return

		# Also reject by the ACTUAL click position over the unit dock: the cached hover above goes stale the
		# instant a card click collapses the strip, which otherwise let the click fall through to the table
		# and open a box-select rubber-band (maintainer bug).
		var main_node := get_node_or_null("/root/Main")
		var dock_node = main_node.get("unit_dock") if main_node != null else null
		if dock_node != null and dock_node.has_method("occludes_point") and dock_node.occludes_point(mouse_event.position):
			return

		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# Check if we're in custom zone editing mode
				if terrain_overlay and terrain_overlay.is_editing_custom_zones():
					# Add vertex at click position (snapped to 1" grid)
					var table_pos = _get_table_position_at_screen(mouse_event.position)
					if table_pos != Vector3.INF:
						terrain_overlay.add_custom_zone_vertex(table_pos)
					return  # Don't process normal click handling

				if mouse_event.shift_pressed:
					# Shift + Left-click starts measurement
					_start_measuring(mouse_event.position)
				elif mouse_event.double_click and not mouse_event.alt_pressed:
					# Double-click a unit model → select the WHOLE unit (issue #81)
					_try_select_unit_at_mouse(mouse_event.position)
				else:
					# Left-click for selection
					_try_select_at_mouse(mouse_event.position, mouse_event.alt_pressed)
			else:
				# Mouse released
				if _is_measuring:
					_stop_measuring(mouse_event.position)
				elif _is_box_selecting:
					_finish_box_selection(mouse_event.alt_pressed)
				else:
					_stop_dragging()

		# Right-click for context menu (radial menu)
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			if mouse_event.pressed:
				# Right-clicking an army tray (empty area) opens the tray menu (e.g. return a wiped
				# unit), without selecting/dragging it. A model on the tray is hit first → its menu.
				var army_tray := _army_tray_at_position(mouse_event.position)
				if army_tray != null:
					context_menu_requested.emit(mouse_event.position, [army_tray])
					get_viewport().set_input_as_handled()
				else:
					var clicked_object = _get_object_at_position(mouse_event.position)
					if clicked_object:
						# A DEAD model (parked on the tray) allows only one action: revive. Don't
						# select/drag it — hand it straight to the context menu, which shows a
						# revive-only menu for a "deleted" object.
						# Gate on dead_slot (J3): only a tray-parked model has it, so a blood stain
						# (collider-less — the ray falls through to a hidden delete wrapper underneath)
						# never opens the revive menu.
						if bool(clicked_object.get_meta("deleted", false)) and clicked_object.has_meta("dead_slot"):
							context_menu_requested.emit(mouse_event.position, [clicked_object])
							get_viewport().set_input_as_handled()
						else:
							# Select object if not already selected
							if clicked_object not in _selected_objects:
								_deselect_all()
								_add_to_selection(clicked_object)
							# Open context menu
							context_menu_requested.emit(mouse_event.position, _selected_objects.duplicate())
							get_viewport().set_input_as_handled()
					else:
						# No object under the cursor: if a pinned ruler is there, remove it
						# (else fall through so a right-drag still rotates the camera).
						_try_remove_ruler_at(mouse_event.position)

	elif event is InputEventMouseMotion:
		if _is_dragging:
			_update_drag(event.position)
		elif _is_box_selecting:
			_update_box_selection(event.position)
		elif _is_measuring:
			_update_measurement(event.position)
		else:
			_update_hover(event.position)

	# Rotation: hold R key for continuous rotation - requires selection
	# Only activate if Shift is NOT pressed (Shift+R is for group rotation in main.gd)
	elif event.is_action_pressed("rotate_object") and _selected_objects.size() > 0:
		if not Input.is_key_pressed(KEY_SHIFT):
			if not _is_rotating:
				begin_rotation_capture()
			_is_rotating = true
	elif event.is_action_released("rotate_object"):
		if _is_rotating:
			commit_rotation_capture()
		_is_rotating = false

	# ESC cancels current drag and restores original positions
	elif event.is_action_pressed("ui_cancel"):
		if _is_dragging:
			_cancel_drag()

	# Range-ring + movement + ruler hotkeys (gated above by _is_gui_blocking_input, so safe
	# while chatting): G cycles the range ring (off → 3 → … → 24 → off), Shift+G clears all;
	# M toggles the Advance/Rush move bands, Shift+M clears all; P pins the live measurement;
	# K clears my rulers, Shift+K (host) clears all.
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_G and range_ring_controller != null:
			if event.shift_pressed:
				range_ring_controller.clear_all()
			else:
				range_ring_controller.cycle(_selected_model_nodes())
		elif event.keycode == KEY_M and movement_range_controller != null:
			if event.shift_pressed:
				movement_range_controller.clear_all()
			else:
				movement_range_controller.toggle(_selected_model_nodes())
		elif event.keycode == KEY_P and _is_measuring:
			_pin_current_measurement()
		elif event.keycode == KEY_K:
			if event.shift_pressed:
				_clear_all_rulers()
			else:
				_clear_my_rulers()


## Double-click handling: select the WHOLE unit under the cursor in one click (issue #81) — no box
## drag or radial "select all" needed. A regiment is selected as its movement tray (it moves as one
## block); a loose unit selects all its model nodes; a non-unit object falls back to a normal click.
func _try_select_unit_at_mouse(screen_pos: Vector2) -> void:
	if not selection_enabled:
		return
	var obj := _get_object_at_position(screen_pos)
	if obj == null:
		_deselect_all()
		return
	var tray := _regiment_tray_of(obj)
	if tray != null:
		_deselect_all()
		_add_to_selection(tray)
		return
	var models := UnitUtils.get_combined_unit_models(obj)  # unit + attached heroes (#81)
	# J6: a select action yields ONLY the type (alive/dead) of the model it started on — double-clicking
	# an alive model grabs the unit's ALIVE models; a parked casualty grabs that unit's DEAD models. So
	# a battlefield double-click never drags parked casualties in, and tray revive-select stays clean.
	var want_dead := bool(obj.get_meta("deleted", false))
	var typed: Array[Node3D] = []
	for m in models:
		if is_instance_valid(m) and bool(m.get_meta("deleted", false)) == want_dead:
			typed.append(m)
	if typed.size() <= 1:
		_try_select_at_mouse(screen_pos, false)  # single model of this type — normal select
		return
	_deselect_all()
	for m in typed:
		_add_to_selection(m)


func _try_select_at_mouse(screen_pos: Vector2, alt_pressed: bool = false) -> void:
	# Skip selection if disabled (e.g., map layout mode)
	if not selection_enabled:
		return

	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 100

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = true

	var result = space_state.intersect_ray(query)

	if result and result.collider:
		var collider = result.collider

		# Check if it's a selectable object (not the table)
		if collider.is_in_group("selectable"):
			# Skip locked objects
			if is_object_locked(collider):
				return

			# Objectives are fixed by the map: right-click captures them (radial
			# menu), but left-click must not select or drag them.
			if collider.is_in_group("objective"):
				return

			# Regiments (AoF:R): clicking a model selects its movement-tray block, so
			# drag/rotate act on the whole regiment. Loose models resolve to themselves.
			var target := _regiment_root(collider)

			# NOTE: another player's models CAN be selected (to inspect their stats and
			# show range/movement rings on them) — they just can't be MOVED. The own-only
			# gate lives in the drag path (_start_dragging / _update_drag), not here.

			var already_selected = target in _selected_objects

			if alt_pressed:
				# Alt+click: toggle selection (add/remove from selection)
				_toggle_object_selection(target)
				# Only start dragging if object is now selected
				if target in _selected_objects:
					_start_dragging(screen_pos)
			elif already_selected:
				# Clicking on already-selected object: just start dragging (keep multi-selection)
				_start_dragging(screen_pos)
			else:
				# Normal click on unselected object: replace selection
				_deselect_all()
				_add_to_selection(target)
				_start_dragging(screen_pos)
			return

	# Anything else starts a box selection: the table, a terrain prop (walls,
	# containers, trees...) or empty space past the table edge. Requiring a TABLE hit
	# here made the rubber band feel view-angle dependent — at shallow camera angles
	# (or with the cursor over terrain) the ray missed the table collider and no box
	# ever appeared.
	_start_box_selection(screen_pos, alt_pressed)


## Free-move (community feedback): the ownership lock is lifted for EVERYONE at the table — anyone may
## move any model (fully solo / self-refereed games). SESSION state: only the HOST's toggle sets it, the
## value syncs to every peer through the table-settings broadcast, so guests may move the host's army
## too — they just cannot operate the toggle.
var host_free_move: bool = false


## In multiplayer you may only select/move your OWN models. Returns the foreign
## owner's player slot if `obj` is an OPR model owned by a DIFFERENT player, else 0.
## Fail-open by design: outside multiplayer, and for terrain / unowned props / any
## object whose owner can't be read, this returns 0 so nobody is ever locked out
## of their own pieces. Owner identity uses the stable player slot, not peer_id.
func _foreign_owner_slot(obj: Node) -> int:
	if obj == null or not _network_manager or not _network_manager.is_multiplayer_active():
		return 0
	if host_free_move:
		return 0
	var owner := 0
	if obj.has_meta("opr_player_id"):
		owner = int(obj.get_meta("opr_player_id"))
	elif obj.has_meta("game_unit"):
		var gu = obj.get_meta("game_unit")
		if gu != null and "unit_properties" in gu:
			owner = int(gu.unit_properties.get("player_id", 0))
	if owner <= 0:
		return 0
	var my_slot: int = _network_manager.get_my_player_slot()
	# Fail open while our own slot is still pending (0, the sub-second window right after
	# (re)connect): NEVER lock a player out of their own army because the slot hasn't landed.
	if my_slot <= 0:
		return 0
	return owner if owner != my_slot else 0


## Add an object to the current selection. Another player's models may be selected (to
## inspect / ring them); the own-only restriction is on MOVEMENT (the drag path), not here.
func _add_to_selection(obj: Node3D) -> void:
	if obj in _selected_objects:
		return

	_selected_objects.append(obj)
	# Clear any gold hover overlay on this object first, then apply the green glow,
	# so the two material overlays never fight over the same mesh.
	_hover_glow.set_target(null)
	_highlight_object(obj)
	AudioManager.play_sfx(AudioManager.SFXType.MODEL_SELECT)
	selection_changed.emit(_selected_objects)


## Remove an object from the current selection
func _remove_from_selection(obj: Node3D) -> void:
	if obj not in _selected_objects:
		return

	_selected_objects.erase(obj)
	_unhighlight_object(obj)

	selection_changed.emit(_selected_objects)


## Toggle an object's selection state (Ctrl+click behavior)
func _toggle_object_selection(obj: Node3D) -> void:
	if obj in _selected_objects:
		_remove_from_selection(obj)
	else:
		_add_to_selection(obj)


## Deselect all objects
func _deselect_all() -> void:
	for obj in _selected_objects:
		if is_instance_valid(obj):
			_unhighlight_object(obj)
	_selected_objects.clear()
	selection_changed.emit(_selected_objects)


## Public: Get currently selected objects
func get_selected_objects() -> Array[Node3D]:
	return _selected_objects.duplicate()


## Selected miniature nodes (for the range-ring hotkey). Skips objectives/terrain/trays.
func _selected_model_nodes() -> Array:
	var out: Array = []
	for obj in _selected_objects:
		if obj is Node3D and is_instance_valid(obj) and obj.is_in_group("miniature"):
			out.append(obj)
	return out


## Set the drag movement cap (OFF / ADVANCE / RUSH). Applies to the NEXT drag.
func set_movement_cap(mode: int) -> void:
	_movement_cap = mode


## The active cap distance in metres for the current selection (0 = no cap). Reads the selected
## model's Advance/Rush allowance from the movement-range controller (Fast/Slow/Swift/aura-aware).
func _compute_movement_cap_meters() -> float:
	if _movement_cap == MovementCap.OFF or movement_range_controller == null:
		return 0.0
	var models := _selected_model_nodes()
	if models.is_empty() or not movement_range_controller.has_method("bands_for_model"):
		return 0.0
	var bands: Dictionary = movement_range_controller.bands_for_model(models[0])
	var inches: int = int(bands.get("rush", 12)) if _movement_cap == MovementCap.RUSH else int(bands.get("advance", 6))
	return float(inches) / METERS_TO_INCHES


## Public: Select specific objects (replaces current selection)
func select_objects(objects: Array) -> void:
	_deselect_all()
	for obj in objects:
		if obj is Node3D and is_instance_valid(obj):
			_add_to_selection(obj)


## Get the selectable object at screen position (for right-click context menu)
## The army tray under the cursor (group "army_tray"), or null. Only when the tray is the FIRST
## hit — a live model on the tray blocks it (so a model's own menu wins).
func _army_tray_at_position(screen_pos: Vector2) -> Node3D:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return null
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 100
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = true
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	if result and result.collider and result.collider.is_in_group("army_tray"):
		return result.collider
	return null


func _get_object_at_position(screen_pos: Vector2) -> Node3D:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return null

	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 100

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = true

	var result = space_state.intersect_ray(query)

	if result and result.collider:
		if result.collider.is_in_group("selectable"):
			if not is_object_locked(result.collider):
				# Right-click keeps the actual model (the radial menu acts per model:
				# wounds, markers...). Left-click selection resolves to the tray block.
				return result.collider

	return null


## Resolve a clicked node to its selection target: a regiment model resolves to its
## movement-tray block (so the whole regiment is selected/dragged/rotated); any other
## node resolves to itself. Keyed off the "regiment_tray" meta set by RegimentTray.
func _regiment_root(node: Node) -> Node3D:
	if node and node.has_meta(RegimentTray.MEMBER_META):
		var tray = node.get_meta(RegimentTray.MEMBER_META)
		if is_instance_valid(tray):
			return tray
	# A click on a terrain-cluster member (tree/mine) resolves to its shared movable base.
	if node and node.has_meta(TerrainGroupBase.MEMBER_META):
		var base = node.get_meta(TerrainGroupBase.MEMBER_META)
		if is_instance_valid(base):
			return base
	return node as Node3D


## Resolve a measured object (a regiment member model) to its RegimentTray, or null if
## it is not part of a regiment block.
func _regiment_tray_of(obj: Node3D) -> RegimentTray:
	if obj and obj.has_meta(RegimentTray.MEMBER_META):
		var tray = obj.get_meta(RegimentTray.MEMBER_META)
		if tray is RegimentTray and is_instance_valid(tray):
			return tray
	return null


## Regiment facing aid for the measure line: when exactly one endpoint is a regiment
## block, label which arc the OTHER endpoint lies in (Front / Left Flank / Rear /
## Right Flank), anchored at the regiment endpoint. AoF:R v3.5.1 p.5 — four 90°
## quadrants. Display only — no rule enforced; hidden when neither or both endpoints
## are regiments.
func _update_front_arc_aid(start_pos: Vector3, end_pos: Vector3) -> void:
	var start_tray := _regiment_tray_of(_measure_start_object)
	var end_tray := _regiment_tray_of(_measure_end_object)

	var tray: RegimentTray = null
	var target := Vector3.ZERO  # the non-regiment endpoint we classify
	var anchor := Vector3.ZERO  # where the label sits (the regiment endpoint)
	if start_tray and not end_tray:
		tray = start_tray
		target = end_pos
		anchor = start_pos
	elif end_tray and not start_tray:
		tray = end_tray
		target = start_pos
		anchor = end_pos

	if tray == null:
		if _measure_front_label:
			_measure_front_label.visible = false
		return

	var quadrant := tray.classify_arc(target)
	if not _measure_front_label:
		_measure_front_label = Label3D.new()
		_measure_front_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_measure_front_label.no_depth_test = true
		_measure_front_label.render_priority = OVERLAY_UI_LABEL_PRIORITY  # above ground stains (issue #82)
		_measure_front_label.font_size = MEASURE_AID_FONT_SIZE
		add_child(_measure_front_label)
	_measure_front_label.visible = true
	_measure_front_label.text = RegimentFacingVisualizer.quadrant_label(quadrant)
	_measure_front_label.modulate = _arc_label_color(quadrant)
	_measure_front_label.global_position = Vector3(anchor.x, MEASURE_AID_Y, anchor.z)


## Colour for the measure-tool arc label by quadrant (matches the wedge colours).
static func _arc_label_color(quadrant: RegimentFacingVisualizer.ArcQuadrant) -> Color:
	match quadrant:
		RegimentFacingVisualizer.ArcQuadrant.FRONT:
			return MEASURE_FRONT_COLOR
		RegimentFacingVisualizer.ArcQuadrant.REAR:
			return MEASURE_REAR_COLOR
		_:
			return MEASURE_FLANK_COLOR


## Public wrapper so external UI (the unit-card dock) can drive the hover glow from a card hover.
func set_hover_target(node: Node3D) -> void:
	_hover_glow.set_target(node)


## Updates the hover glow to the selectable currently under the cursor (or none).
func _update_hover(screen_pos: Vector2) -> void:
	if not selection_enabled:
		_hover_glow.set_target(null)
		return
	var obj: Node3D = _get_object_at_position(screen_pos)
	if obj != null and obj in _selected_objects:
		obj = null  # selected objects keep their green glow; no gold hover on top
	_hover_glow.set_target(obj)


## Highlight a selected object with a green model glow (material_overlay), saving
## any previous overlay per mesh so it can be restored on deselect, and cast a real
## green spill light from it onto the surrounding ground / minis / mist.
func _highlight_object(obj: Node3D) -> void:
	var mat := _get_selection_glow_material()
	for mesh: MeshInstance3D in _collect_glow_meshes(obj):
		if not mesh.has_meta("_sel_prev_overlay"):
			mesh.set_meta("_sel_prev_overlay", mesh.material_overlay)
		mesh.material_overlay = mat
	_add_spill_light(obj)


## Remove the green selection glow, restoring the previous overlay per mesh, and
## remove the spill light.
func _unhighlight_object(obj: Node3D) -> void:
	for mesh: MeshInstance3D in _collect_glow_meshes(obj):
		if mesh.has_meta("_sel_prev_overlay"):
			mesh.material_overlay = mesh.get_meta("_sel_prev_overlay")
			mesh.remove_meta("_sel_prev_overlay")
	_remove_spill_light(obj)


func _collect_glow_meshes(obj: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node: MeshInstance3D in obj.find_children("*", "MeshInstance3D", true, false):
		result.append(node)
	return result


## Spawn the green spill light under a selected object. No-op if already present, if
## spill lights are disabled for the current preset, or if the per-preset cap is hit.
func _add_spill_light(obj: Node3D) -> void:
	if not _spill_lights_enabled():
		return
	if obj.get_node_or_null(NodePath(String(SelectionSpillLight.NODE_NAME))) != null:
		return
	# Live count from the tree (not a manual counter) so freeing a selected object
	# without going through deselect can't desync the cap. The green overlay still
	# marks any mini left unlit past the cap.
	if get_tree().get_node_count_in_group(SelectionSpillLight.GROUP) >= _spill_light_cap():
		return
	var light := SelectionSpillLight.new()
	obj.add_child(light)
	light.setup(_object_ground_radius(obj))


## Free the spill light under an object, if any. Detaches immediately (not just
## queue_free, which defers) so a same-frame rebuild — e.g. _on_graphics_settings_applied
## removing then re-adding — sees a clean tree/group state instead of the stale light.
func _remove_spill_light(obj: Node3D) -> void:
	var light := obj.get_node_or_null(NodePath(String(SelectionSpillLight.NODE_NAME)))
	if is_instance_valid(light):
		obj.remove_child(light)
		light.queue_free()


## Spill lights are the premium layer: on from MEDIUM up (where glow + volumetric fog
## are also enabled), off on PERFORMANCE/LOW/CUSTOM where FPS is the priority.
func _spill_lights_enabled() -> bool:
	var tier: int = GraphicsSettings.current_preset
	return tier == GraphicsSettings.QualityPreset.MEDIUM \
		or tier == GraphicsSettings.QualityPreset.HIGH \
		or tier == GraphicsSettings.QualityPreset.ULTRA


## Hard cap on concurrent spill lights, scaling with tier (conservative starts).
func _spill_light_cap() -> int:
	match GraphicsSettings.current_preset:
		GraphicsSettings.QualityPreset.ULTRA:
			return 48
		GraphicsSettings.QualityPreset.HIGH:
			return 24
		_:
			return 12


## Rebuild spill lights on the current selection after a preset change.
func _on_graphics_settings_applied(_preset_name: String) -> void:
	for obj: Node3D in _selected_objects:
		if is_instance_valid(obj):
			_remove_spill_light(obj)
	for obj: Node3D in _selected_objects:
		if is_instance_valid(obj):
			_add_spill_light(obj)


## Horizontal footprint radius (metres) from the object's mesh AABBs, in obj-local space.
func _object_ground_radius(obj: Node3D) -> float:
	var merged := AABB()
	var have := false
	var inv := obj.global_transform.affine_inverse()
	for node: MeshInstance3D in obj.find_children("*", "MeshInstance3D", true, false):
		var local_aabb := (inv * node.global_transform) * node.get_aabb()
		if have:
			merged = merged.merge(local_aabb)
		else:
			merged = local_aabb
			have = true
	if not have:
		return 0.02
	return maxf(merged.size.x, merged.size.z) * 0.5


func _get_selection_glow_material() -> StandardMaterial3D:
	if _selection_glow_material == null:
		var green := SelectionSpillLight.GREEN_SELECTION
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(green.r, green.g, green.b, 0.4)
		mat.emission_enabled = true
		mat.emission = green
		mat.emission_energy_multiplier = 2.0
		mat.grow = true
		mat.grow_amount = 0.003
		_selection_glow_material = mat
	return _selection_glow_material


## Start box selection (drag rectangle to select multiple objects)
func _start_box_selection(screen_pos: Vector2, alt_pressed: bool) -> void:
	# Skip box selection if disabled (e.g., map layout mode)
	if not selection_enabled:
		return
	_hover_glow.set_target(null)

	# If not holding Alt, clear current selection
	if not alt_pressed:
		_deselect_all()

	_is_box_selecting = true
	_box_select_start = screen_pos
	_box_select_end = screen_pos

	# Create selection rectangle UI
	_create_box_select_rect()


## Update box selection rectangle while dragging
func _update_box_selection(screen_pos: Vector2) -> void:
	if not _is_box_selecting:
		return

	_box_select_end = screen_pos
	_update_box_select_rect()


## Finish box selection and select all objects within the rectangle
func _finish_box_selection(alt_pressed: bool) -> void:
	if not _is_box_selecting:
		return

	# Find all selectable objects within the rectangle
	var rect = _get_box_select_rect()
	var camera = get_viewport().get_camera_3d()

	if camera:
		# Gather the band's hits first (objects behind the camera unproject MIRRORED — skip them, else
		# a shallow-angle box would grab minis behind you).
		var hits: Array[Node3D] = []
		for child in get_children():
			if child.is_in_group("selectable"):
				if camera.is_position_behind(child.global_position):
					continue
				if rect.has_point(camera.unproject_position(child.global_position)):
					hits.append(child)
		# J6: keep only ONE type. If the band holds ANY alive model, select alive only — a battlefield
		# band never grabs parked casualties. A band of exclusively dead models (on the tray) selects
		# those, so tray band-multi-revive keeps working.
		var has_alive := false
		for h in hits:
			if not bool(h.get_meta("deleted", false)):
				has_alive = true
				break
		for child in hits:
			if has_alive and bool(child.get_meta("deleted", false)):
				continue
			if alt_pressed and child in _selected_objects:
				# Alt + box select: toggle off if already selected
				_remove_from_selection(child)
			elif child not in _selected_objects:
				_add_to_selection(child)

	# Clean up
	_is_box_selecting = false
	_destroy_box_select_rect()


## Create the visual selection rectangle
func _create_box_select_rect() -> void:
	if _box_select_rect:
		_box_select_rect.queue_free()

	_box_select_rect = ColorRect.new()
	_box_select_rect.color = Color(0.3, 0.5, 1.0, 0.2)  # Semi-transparent blue

	# Add border using a StyleBoxFlat
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.3, 0.5, 1.0, 0.2)
	style.border_color = Color(0.3, 0.5, 1.0, 0.8)
	style.set_border_width_all(2)
	_box_select_rect.add_theme_stylebox_override("panel", style)

	# Add to UI layer
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "BoxSelectLayer"
	canvas_layer.layer = 100  # Above other UI
	add_child(canvas_layer)
	canvas_layer.add_child(_box_select_rect)

	_update_box_select_rect()


## Update the visual selection rectangle position and size
func _update_box_select_rect() -> void:
	if not _box_select_rect:
		return

	var rect = _get_box_select_rect()
	_box_select_rect.position = rect.position
	_box_select_rect.size = rect.size


## Get the normalized selection rectangle (handles negative sizes)
func _get_box_select_rect() -> Rect2:
	var min_pos = Vector2(
		min(_box_select_start.x, _box_select_end.x),
		min(_box_select_start.y, _box_select_end.y)
	)
	var max_pos = Vector2(
		max(_box_select_start.x, _box_select_end.x),
		max(_box_select_start.y, _box_select_end.y)
	)
	return Rect2(min_pos, max_pos - min_pos)


## Destroy the visual selection rectangle
func _destroy_box_select_rect() -> void:
	if _box_select_rect:
		var parent = _box_select_rect.get_parent()
		if parent:
			parent.queue_free()  # Also removes the CanvasLayer
		_box_select_rect = null


## The currently-selected objects this player may MOVE: own (or unowned) live objects.
## In multiplayer another player's models can be selected (to inspect / ring) but not dragged.
func _movable_selection() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for obj in _selected_objects:
		if is_instance_valid(obj) and _foreign_owner_slot(obj) <= 0:
			out.append(obj)
	return out


func _start_dragging(screen_pos: Vector2) -> void:
	if _selected_objects.is_empty():
		return

	# Only OWN (or unowned) objects are draggable; another player's models stay selected
	# (for inspection / rings) but never move.
	var movable := _movable_selection()
	if movable.is_empty():
		return

	_is_dragging = true
	_hover_glow.set_target(null)
	_drag_start_positions.clear()

	# Store start positions for the movable objects and lift them
	for obj in movable:
		if is_instance_valid(obj):
			_drag_start_positions[obj] = obj.global_position
			# For rigid bodies, make them kinematic while dragging
			if obj is RigidBody3D:
				obj.freeze = true
			# Lift object above the table surface
			obj.global_position.y += drag_lift_height

	# Anchor = first movable object (original position)
	_drag_anchor_position = _drag_start_positions[movable[0]]

	# Resolve the movement cap (Advance/Rush inches → metres) once for this drag.
	_movement_cap_meters = _compute_movement_cap_meters()

	# Remember where on the table the cursor grabbed, so the unit keeps that grab offset
	# while dragging instead of snapping its first model onto the cursor.
	_drag_grab_world = _drag_anchor_position
	var grab_camera = get_viewport().get_camera_3d()
	if grab_camera:
		var grab_from = grab_camera.project_ray_origin(screen_pos)
		var grab_dir = grab_camera.project_ray_normal(screen_pos)
		var grab_hit = Plane(Vector3.UP, 0).intersects_ray(grab_from, grab_dir)
		if grab_hit:
			_drag_grab_world = grab_hit

	# Create drag visualization line
	_create_drag_line()


func _stop_dragging() -> void:
	if _is_dragging and not _selected_objects.is_empty():
		# Anti-stacking + charge-snap: nudge dropped bases out of any overlap with other
		# units and snap a near-miss to enemy contact. Done BEFORE the batch / undo below
		# so the resolved position flows the normal move path (undo + MP broadcast).
		_resolve_drop_separation()

		# Build batch of final positions for network broadcast
		var drop_batch: Array = []

		# Smoothly lower objects back down and re-enable physics for rigid bodies
		for obj in _selected_objects:
			if is_instance_valid(obj):
				# For static bodies, snap to table surface (y=0)
				# For rigid bodies, lower by lift height and let physics handle it
				var target_y: float
				if obj is RigidBody3D:
					target_y = obj.global_position.y - drag_lift_height
				else:
					# Static bodies settle onto the ground surface beneath the base
					# (table top = 0, or a terrain prop like a container). Exclude the
					# dragged bodies so a terrain prop doesn't settle on its own floors.
					target_y = _surface_y_under(obj.global_position, _dragged_body_rids())

				# Collect final ground-level positions for batched broadcast
				if obj.has_meta("network_id"):
					drop_batch.append(obj.get_meta("network_id"))
					drop_batch.append(obj.global_position.x)
					drop_batch.append(target_y)
					drop_batch.append(obj.global_position.z)

				var tween = create_tween()
				tween.set_ease(Tween.EASE_OUT)
				tween.set_trans(Tween.TRANS_QUAD)
				tween.tween_property(obj, "global_position:y", target_y, 0.2)
				# Re-enable physics after animation completes
				if obj is RigidBody3D:
					tween.tween_callback(func(): obj.freeze = false)

		# Broadcast all final positions in a single RPC
		if drop_batch.size() > 0 and _network_manager and _network_manager.is_multiplayer_active():
			_network_manager.broadcast_move_batch(drop_batch)

		# Turn each moved model to face its own movement direction (playtest feedback, per-model).
		_auto_face_moved_models()

		# Record the whole drag as one undoable move (reads _drag_start_positions,
		# which is cleared further below).
		_record_move_for_undo()

		# Emit final distance for anchor object
		if _selected_objects.size() > 0:
			var anchor = _selected_objects[0]
			if is_instance_valid(anchor):
				var final_pos = anchor.global_position
				# Use table surface level for distance calculation
				final_pos.y = 0.0
				var distance_m = _drag_anchor_position.distance_to(final_pos)
				var distance_inches = distance_m * METERS_TO_INCHES
				if distance_inches > 0.1:  # Only emit if actually moved
					distance_changed.emit(distance_inches, _drag_anchor_position, final_pos)

		# Battle-Log / replay seam: every object that actually moved, with exact from→to table positions
		# (y flattened to the table plane). Read from _drag_start_positions BEFORE it is cleared below.
		var moves: Array = []
		for obj in _selected_objects:
			if not is_instance_valid(obj) or not _drag_start_positions.has(obj):
				continue
			var start: Vector3 = _drag_start_positions[obj]
			var end: Vector3 = obj.global_position
			start.y = 0.0
			end.y = 0.0
			var inches: float = start.distance_to(end) * METERS_TO_INCHES
			if inches > 0.1:
				moves.append({"node": obj, "from": start, "to": end, "inches": inches})
		if not moves.is_empty():
			selection_dropped.emit(moves)

		drag_ended.emit()
		AudioManager.play_sfx(AudioManager.SFXType.MODEL_PLACE)

	_is_dragging = false
	_move_broadcast_timer = 0.0
	_coherency_update_timer = 0.0
	_drag_start_positions.clear()
	_drag_anchor_position = Vector3.ZERO
	_destroy_drag_line()


## Drop-time separation resolution (SeparationResolver). Runs BEFORE the drop batch / undo
## record in _stop_dragging so the resolved x/z flows the normal move path. Two phases:
##  1. Unit-scoped: snap a near-miss to ENEMY base contact (charge) and push a dropped item
##     out of overlap with OTHER units to clean contact.
##  2. Absolute anti-stacking: guarantee NO dropped base overlaps ANY other base — same
##     unit, own other unit, enemy, or a sibling dragged item. Overlap is a hard physical
##     impossibility, distinct from the 1" spacing rule (which binds only between units and
##     exempts a charge); Phase 1 alone leaves same-unit / mutually-dragged stacks, which
##     this closes.
## Local-only geometry; no RPC of its own (the standard move broadcast carries it).
func _resolve_drop_separation() -> void:
	var army := get_node_or_null("/root/Main/OPRArmyManager")
	if army == null or not army.has_method("get_all_game_units"):
		return
	var movable := _movable_selection()
	if movable.is_empty():
		return

	# Node ids being dragged (loose models + tray members) — excluded as obstacles so a
	# multi-select group doesn't push against itself.
	var dragged_ids: Dictionary = {}
	for obj in movable:
		if not is_instance_valid(obj):
			continue
		dragged_ids[obj.get_instance_id()] = true
		if obj is RegimentTray or obj.is_in_group(RegimentTray.GROUP):
			for child in obj.get_children():
				if child is Node3D and child.has_meta("model_instance"):
					dragged_ids[child.get_instance_id()] = true

	# Phase 1 — unit-scoped enemy snap + other-unit contact push (charge semantics). Skipped
	# when nothing else is on the field, but Phase 2 (absolute anti-stacking) still runs.
	var candidates := _separation_candidates(army, dragged_ids)
	if not candidates.is_empty():
		var min_move: float = SeparationResolver.RESOLVE_EPSILON_INCHES * SeparationResolver.INCHES_TO_METERS
		for obj in movable:
			if not is_instance_valid(obj):
				continue
			var item := _drag_item_shapes(obj)
			var item_shapes: Array = item["shapes"]
			if item_shapes.is_empty():
				continue
			var item_unit_id: int = item["unit_id"]
			# Only OTHER units obstruct HERE (the 1" rule binds between units; same-unit
			# spacing is coherency / formation). Overlap between any pair is handled below.
			var item_cands: Array = []
			for c in candidates:
				if int(c["unit_id"]) != item_unit_id:
					item_cands.append(c)
			if item_cands.is_empty():
				continue
			var delta := SeparationResolver.resolve_translation(item_shapes, item_cands, int(item["player"]))
			if delta.length() > min_move:
				obj.global_position.x += delta.x
				obj.global_position.z += delta.y

	# Phase 2 — absolute anti-stacking (runs AFTER the unit-scoped snap/push above): guarantee no
	# dropped base overlaps ANY other base — same unit, own other unit, enemy, OR a sibling
	# dragged item. Overlap is a hard physical impossibility, distinct from the 1" spacing
	# rule (which binds only between units and exempts a charge). The snap/push above only
	# considers OTHER units, so same-unit siblings and mutually-dragged models can still be
	# stacked; this pass closes that.
	_resolve_drop_stacking(army, movable, dragged_ids)


## Absolute anti-stacking pass for the drop: no two model bases may overlap, for ANY pair.
## Each dragged item (a loose model = 1 base; a regiment tray = its whole member block) is
## pushed out of overlap with every other alive base — the stationary bases of ALL units
## (same unit included) AND the other dragged items' live bases. Iterated to convergence so
## items also clear each other; moves the item NODES so undo + MP sync carry the result
## (this runs before the drop batch / undo record in _stop_dragging). Best-effort escape
## for a fully-surrounded drop (SeparationResolver.resolve_overlaps settles at the
## shallowest opening rather than leaving a deep stack).
func _resolve_drop_stacking(army: Node, movable: Array, dragged_ids: Dictionary) -> void:
	# Movable items with live shapes (rebuilt at their post-snap/push positions).
	var items: Array = []
	for obj in movable:
		if not is_instance_valid(obj):
			continue
		var d := _drag_item_shapes(obj)
		var shapes: Array = d["shapes"]
		if shapes.is_empty():
			continue
		items.append({"node": obj, "shapes": shapes})
	if items.is_empty():
		return

	# Fixed obstacles: every alive base NOT part of the drag (all units, both armies).
	var fixed: Array = []
	for game_unit in army.get_all_game_units():
		if game_unit == null:
			continue
		for model in game_unit.get_alive_models():
			if model == null or model.node == null or not is_instance_valid(model.node):
				continue
			if dragged_ids.has(model.node.get_instance_id()):
				continue
			var shape := SeparationChecker.shape_for_model(model)
			if shape != null:
				fixed.append(shape)

	var min_move: float = SeparationResolver.RESOLVE_EPSILON_INCHES * SeparationResolver.INCHES_TO_METERS
	# Outer relaxation: moving one item can nudge it into another dragged item, so re-pass
	# until nothing moves (or the hard cap). Each item clears `fixed` PLUS the other items'
	# live bases (their centres were updated in place when they last moved).
	for _pass in range(SeparationResolver.MAX_OVERLAP_ITERATIONS):
		var moved_any := false
		for i in range(items.size()):
			var it: Dictionary = items[i]
			var obstacles: Array = fixed.duplicate()
			for j in range(items.size()):
				if j != i:
					obstacles.append_array(items[j]["shapes"])
			var delta := SeparationResolver.resolve_overlaps(it["shapes"], obstacles)
			if delta.length() > min_move:
				var node: Node3D = it["node"]
				node.global_position.x += delta.x
				node.global_position.z += delta.y
				moved_any = true
		if not moved_any:
			break


## Base shapes of a dragged node for separation resolution: a loose model yields one
## shape, a regiment tray yields all its member shapes (the whole block translates as
## one). Returns {shapes: Array[BaseShape], unit_id: int, player: int}.
func _drag_item_shapes(node: Node3D) -> Dictionary:
	var member_nodes: Array = []
	if node is RegimentTray or node.is_in_group(RegimentTray.GROUP):
		for child in node.get_children():
			if child is Node3D and child.has_meta("model_instance"):
				member_nodes.append(child)
	elif node.has_meta("model_instance"):
		member_nodes.append(node)

	var shapes: Array = []
	var unit_id: int = 0
	var player: int = 0
	for mn in member_nodes:
		if mn.get_meta("deleted", false):
			continue
		var model := mn.get_meta("model_instance") as ModelInstance
		if model == null or not model.is_alive:
			continue
		var shape := SeparationChecker.shape_for_model(model)
		if shape == null:
			continue
		shapes.append(shape)
		if unit_id == 0:
			var eff := SeparationChecker.effective_unit(model.unit as GameUnit)
			if eff != null and eff.unit_properties != null:
				unit_id = eff.get_instance_id()
				player = int(eff.unit_properties.get("player_id", 0))
	return {"shapes": shapes, "unit_id": unit_id, "player": player}


## Every alive OPR base NOT part of the current drag, as {shape, unit_id, player_id}
## for the resolver. A joined Hero folds into its host unit.
func _separation_candidates(army: Node, dragged_ids: Dictionary) -> Array:
	var out: Array = []
	for game_unit in army.get_all_game_units():
		if game_unit == null:
			continue
		var eff := SeparationChecker.effective_unit(game_unit)
		if eff == null or eff.unit_properties == null:
			continue
		var unit_id: int = eff.get_instance_id()
		var player: int = int(eff.unit_properties.get("player_id", 0))
		for model in game_unit.get_alive_models():
			if model == null or model.node == null or not is_instance_valid(model.node):
				continue
			if dragged_ids.has(model.node.get_instance_id()):
				continue
			var shape := SeparationChecker.shape_for_model(model)
			if shape == null:
				continue
			out.append({"shape": shape, "unit_id": unit_id, "player_id": player})
	return out


## After a drag, snap each moved model to face its own movement direction (playtest feedback, per-model).
## Snap-on-drop (not live) keeps it calm and costs one rotation broadcast. Skipped for tiny nudges,
## physics-driven RigidBodies, and Regiment movement-tray blocks (whose facing is set only via an
## explicit pivot — see _should_auto_face). NOTE: the facing axis sign may need a one-line eyeball tweak.
const AUTO_FACE_DEADZONE_M: float = 0.02  # min horizontal drag (m) before a drop implies a new facing
func _auto_face_moved_models() -> void:
	var rotation_batch: Array = []
	for obj in _selected_objects:
		# is_instance_valid must guard before the typed _should_auto_face() call —
		# a freed object cannot be passed as a Node3D arg (GDScript rejects it at the
		# call site, before the function body runs).
		if not is_instance_valid(obj) or not _drag_start_positions.has(obj):
			continue
		if not _should_auto_face(obj):
			continue
		var moved: Vector3 = obj.global_position - _drag_start_positions[obj]
		if Vector2(moved.x, moved.z).length() < AUTO_FACE_DEADZONE_M:
			continue
		obj.rotation.y = atan2(moved.x, moved.z)
		if obj.has_meta("network_id"):
			rotation_batch.append(obj.get_meta("network_id"))
			rotation_batch.append(obj.rotation.y)
	if rotation_batch.size() > 0 and _network_manager and _network_manager.is_multiplayer_active():
		_network_manager.broadcast_rotation_batch(rotation_batch)


## Whether a moved object should be auto-faced to its drag direction after a drop.
## Regiment movement-tray blocks keep their facing (Age of Fantasy: Regiments
## v3.5.1, p.8 "Pivoting": a unit's facing only changes via an explicit pivot during
## a move action — never implicitly from the drag direction). Rigid bodies are
## physics-driven and ignore scripted rotation.
##
## Precondition: callers must is_instance_valid-check freed objects BEFORE calling
## (a freed object is rejected by the typed Node3D param at the call site). The
## null/is_instance_valid guard here covers the null case for direct callers.
static func _should_auto_face(obj: Node3D) -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	if obj is RigidBody3D:
		return false
	if obj is RegimentTray:
		return false
	return true


## Cancel drag and restore all objects to their original positions
func _cancel_drag() -> void:
	if not _is_dragging:
		return

	# Restore all objects to their original positions
	for obj in _selected_objects:
		if is_instance_valid(obj) and _drag_start_positions.has(obj):
			obj.global_position = _drag_start_positions[obj]
			# Re-enable physics for rigid bodies
			if obj is RigidBody3D:
				obj.freeze = false

	_is_dragging = false
	_move_broadcast_timer = 0.0
	_coherency_update_timer = 0.0
	_drag_start_positions.clear()
	_drag_anchor_position = Vector3.ZERO
	_destroy_drag_line()


## Records the just-finished drag as one undoable MoveAction. No-op if nothing
## moved or no undo manager is wired. Call before _drag_start_positions is cleared.
func _record_move_for_undo() -> void:
	if undo_manager == null:
		return
	var objects: Array[Node3D] = []
	var from_positions: Array[Vector3] = []
	var to_positions: Array[Vector3] = []
	var moved: bool = false
	for obj in _selected_objects:
		if not is_instance_valid(obj) or not _drag_start_positions.has(obj):
			continue
		var start_pos: Vector3 = _drag_start_positions[obj]
		# Final resting height: static bodies settle on the ground surface beneath the
		# base (table or terrain prop), rigid bodies drop back by the lift height.
		var end_y: float = obj.global_position.y - drag_lift_height if obj is RigidBody3D else _surface_y_under(obj.global_position)
		var end_pos: Vector3 = Vector3(obj.global_position.x, end_y, obj.global_position.z)
		objects.append(obj)
		from_positions.append(start_pos)
		to_positions.append(end_pos)
		if start_pos.distance_to(end_pos) > MOVE_UNDO_EPSILON_M:
			moved = true
	if moved and not objects.is_empty():
		var move_peer: int = _network_manager.get_my_peer_id() if _network_manager else 0
		undo_manager.push(UndoManager.MoveAction.new(objects, from_positions, to_positions, _network_manager, move_peer))


## Whether the current selection is exclusively RegimentTray blocks (so R-hold uses
## mouse-follow rotation instead of the continuous spin).
func _selection_is_regiment_only() -> bool:
	if _selected_objects.is_empty():
		return false
	for obj in _selected_objects:
		if not (obj is RegimentTray):
			return false
	return true


## Whether the current selection is exclusively RegimentTray blocks (so R-hold uses
## mouse-follow rotation instead of the continuous spin). Public wrapper for main.gd.
func is_selection_regiment_only() -> bool:
	return _selection_is_regiment_only()


## One frame of mouse-follow rotation for the selected regiment tray(s). Public
## wrapper for main.gd's Shift+R group-rotation path.
func step_regiment_cursor_rotation(delta: float) -> void:
	_rotate_regiments_to_cursor(delta)


## Rotate the selected regiment tray(s) to face the cursor (mouse-driven rotation).
## The tray's facing (+Z) turns toward the cursor's table position; the cumulative
## degrees rotated (vs the gesture's start) is shown in the rotation label. AoF:R
## v3.5.1 p.8 "Pivoting" — the player decides if the resulting pivot is legal.
func _rotate_regiments_to_cursor(delta: float) -> void:
	var cursor := get_cursor_table_position()
	if cursor == Vector3.ZERO:
		return
	var any_rotated := false
	var first_delta_deg := 0.0
	var found_first := false
	for obj in _selected_objects:
		if not (obj is RegimentTray) or not is_instance_valid(obj):
			continue
		var tray := obj as RegimentTray
		var to_cursor := Vector2(cursor.x - tray.global_position.x, cursor.z - tray.global_position.z)
		if to_cursor.length_squared() < 0.0000001:
			continue
		var target_rot: float = facing_rotation_to(tray.global_position.x, tray.global_position.z, cursor.x, cursor.z)
		tray.rotation.y = target_rot
		if _rotation_capture.has(tray):
			var start_rot: float = _rotation_capture[tray]
			var deg := rad_to_deg(target_rot - start_rot)
			if not found_first:
				first_delta_deg = deg
				found_first = true
			any_rotated = true
	# Show the cumulative degrees on the first rotated tray (mirrors the spin label).
	if any_rotated:
		set_rotation_label(first_delta_deg)
	# Throttled broadcast (same cadence as the spin path).
	_rotation_broadcast_timer += delta
	if _rotation_broadcast_timer >= ROTATION_BROADCAST_INTERVAL and _network_manager:
		_rotation_broadcast_timer = 0.0
		var batch: Array = []
		for obj in _selected_objects:
			if is_instance_valid(obj) and obj.has_meta("network_id"):
				batch.append(obj.get_meta("network_id"))
				batch.append(obj.rotation.y)
		if batch.size() > 0 and _network_manager.is_multiplayer_active():
			_network_manager.broadcast_rotation_batch(batch)


## Pure facing math shared by both cursor-follow rotation paths: the rotation.y (radians) that aims a
## piece's +Z forward from (from_x, from_z) at (target_x, target_z). World facing = (sin(rot), cos(rot)),
## so aiming +Z at the target is atan2(dx, dz).
static func facing_rotation_to(from_x: float, from_z: float, target_x: float, target_z: float) -> float:
	return atan2(target_x - from_x, target_z - from_z)


## Loose (non-regiment) rotation: each selected model turns in place around ITS OWN base to face the
## cursor (community feedback — aim instead of guess-and-release). A multi-model selection all faces the
## same cursor direction independently (NOT a rigid group spin). Mirrors the regiment-tray path; a mixed
## selection rotates the loose models and leaves any trays for the regiment-only path.
func _rotate_loose_to_cursor(delta: float) -> void:
	var cursor := get_cursor_table_position()
	if cursor == Vector3.ZERO:
		return
	var any_rotated := false
	var first_delta_deg := 0.0
	var found_first := false
	for obj in _selected_objects:
		if obj is RegimentTray or not is_instance_valid(obj):
			continue
		var to_cursor := Vector2(cursor.x - obj.global_position.x, cursor.z - obj.global_position.z)
		if to_cursor.length_squared() < 0.0000001:
			continue
		var target_rot: float = facing_rotation_to(obj.global_position.x, obj.global_position.z, cursor.x, cursor.z)
		obj.rotation.y = target_rot
		if _rotation_capture.has(obj):
			var start_rot: float = _rotation_capture[obj]
			if not found_first:
				first_delta_deg = rad_to_deg(target_rot - start_rot)
				found_first = true
		any_rotated = true
	# Cumulative degrees on the first rotated model (mirrors the tray label).
	if any_rotated:
		set_rotation_label(first_delta_deg)
	# Throttled broadcast (same cadence as the tray + former spin path).
	_rotation_broadcast_timer += delta
	if _rotation_broadcast_timer >= ROTATION_BROADCAST_INTERVAL and _network_manager:
		_rotation_broadcast_timer = 0.0
		var batch: Array = []
		for obj in _selected_objects:
			if obj is RegimentTray or not is_instance_valid(obj) or not obj.has_meta("network_id"):
				continue
			batch.append(obj.get_meta("network_id"))
			batch.append(obj.rotation.y)
		if batch.size() > 0 and _network_manager.is_multiplayer_active():
			_network_manager.broadcast_rotation_batch(batch)


## Snapshots rotation.y of the current selection at the start of a rotate gesture.
func begin_rotation_capture() -> void:
	_rotation_capture.clear()
	for obj in _selected_objects:
		if is_instance_valid(obj):
			_rotation_capture[obj] = obj.rotation.y
	# Reset the cumulative-rotation counter; the label itself is shown only while a
	# continuous rotate is in progress (update_rotation_label), not for one-shot snaps.
	_rotation_accumulated_deg = 0.0


## Accumulate `delta_deg` into the rotation label and reposition it above the pivot
## (first selected object). Called each frame during a continuous rotate gesture
## (plain R in _process, Shift+R group rotation from main.gd).
func update_rotation_label(delta_deg: float) -> void:
	_rotation_accumulated_deg += delta_deg
	_show_rotation_label(_rotation_accumulated_deg)


## Set the rotation label directly to `degrees` (no accumulation). Used by the
## mouse-follow rotation path for regiment trays, where the degrees shown is the
## angle between the current cursor direction and the gesture's start facing — not
## a per-frame delta to accumulate.
func set_rotation_label(degrees: float) -> void:
	_show_rotation_label(degrees)


## Commits a rotate gesture as one undoable RotateAction. No-op if nothing rotated.
func commit_rotation_capture() -> void:
	_hide_rotation_label()
	if undo_manager == null or _rotation_capture.is_empty():
		_rotation_capture.clear()
		return
	var objects: Array[Node3D] = []
	var from_rot: Array[float] = []
	var to_rot: Array[float] = []
	var rotated: bool = false
	for obj in _rotation_capture:
		if not is_instance_valid(obj):
			continue
		var start_y: float = _rotation_capture[obj]
		objects.append(obj)
		from_rot.append(start_y)
		to_rot.append(obj.rotation.y)
		if absf(obj.rotation.y - start_y) > ROTATION_UNDO_EPSILON_RAD:
			rotated = true
	_rotation_capture.clear()
	if rotated and not objects.is_empty():
		var rot_peer: int = _network_manager.get_my_peer_id() if _network_manager else 0
		undo_manager.push(UndoManager.RotateAction.new(objects, from_rot, to_rot, _network_manager, rot_peer))


## Create (if needed) and show the rotation label with `degrees` (cumulative this
## gesture), anchored above the first selected object. No-op if nothing is selected.
func _show_rotation_label(degrees: float) -> void:
	if _selected_objects.is_empty():
		return
	var anchor: Node3D = _selected_objects[0]
	if not is_instance_valid(anchor):
		return
	if _rotation_label == null:
		_rotation_label = Label3D.new()
		_rotation_label.name = "RotationLabel"
		_rotation_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_rotation_label.no_depth_test = true
		_rotation_label.render_priority = OVERLAY_UI_LABEL_PRIORITY  # above ground stains (issue #82)
		_rotation_label.font_size = ROTATION_LABEL_FONT_SIZE
		_rotation_label.outline_size = 8
		_rotation_label.outline_modulate = Color.BLACK
		_rotation_label.modulate = Color.WHITE
		add_child(_rotation_label)
	# Normalise to (-180, 180] for a readable readout (a 270° CW turn reads as -90°).
	var deg := fmod(degrees, 360.0)
	if deg > 180.0:
		deg -= 360.0
	elif deg <= -180.0:
		deg += 360.0
	_rotation_label.text = "%+.0f°" % deg
	_rotation_label.global_position = Vector3(anchor.global_position.x, ROTATION_LABEL_Y, anchor.global_position.z)
	_rotation_label.visible = true


## Hide the rotation label (called when the gesture ends). The node is reused on the
## next gesture to avoid per-frame allocation churn.
func _hide_rotation_label() -> void:
	if _rotation_label:
		_rotation_label.visible = false


## Public wrapper to clear the current selection (e.g., after deleting it).
func deselect_all() -> void:
	_deselect_all()


## Create drag visualization line and label
func _create_drag_line() -> void:
	if _drag_line:
		_drag_line.queue_free()
	if _drag_label:
		_drag_label.queue_free()

	# Create line mesh
	_drag_line = MeshInstance3D.new()
	_drag_line.name = "DragLine"
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.ORANGE
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # draw over ground stains (issue #82)
	material.render_priority = OVERLAY_UI_RENDER_PRIORITY
	_drag_line.material_override = material
	_drag_line.visible = false
	add_child(_drag_line)

	# Create 3D label
	_drag_label = Label3D.new()
	_drag_label.name = "DragLabel"
	_drag_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_drag_label.no_depth_test = true
	_drag_label.render_priority = OVERLAY_UI_LABEL_PRIORITY  # above ground stains (issue #82)
	_drag_label.pixel_size = 0.001
	_drag_label.font_size = 24
	_drag_label.outline_size = 8
	_drag_label.modulate = Color.WHITE
	_drag_label.outline_modulate = Color.BLACK
	_drag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drag_label.visible = false
	add_child(_drag_label)


## Update drag line visualization
func _update_drag_line(from_pos: Vector3, to_pos: Vector3, distance_inches: float) -> void:
	if not _drag_line or not _drag_label:
		return

	# Calculate horizontal direction
	var direction = Vector3(to_pos.x - from_pos.x, 0, to_pos.z - from_pos.z)
	var length = direction.length()

	if length < 0.001:
		_drag_line.visible = false
		_drag_label.visible = false
		return

	_drag_line.visible = true
	_drag_label.visible = true

	# Create line mesh
	var line_mesh = BoxMesh.new()
	line_mesh.size = Vector3(length, 0.001, 0.002)
	_drag_line.mesh = line_mesh

	# Position at midpoint, slightly above table
	var midpoint = Vector3((from_pos.x + to_pos.x) / 2, 0.005, (from_pos.z + to_pos.z) / 2)
	_drag_line.global_position = midpoint

	# Rotate to align with direction
	var angle = atan2(direction.x, direction.z)
	_drag_line.rotation = Vector3(0, angle + PI/2, 0)

	# Update label
	_drag_label.global_position = Vector3(midpoint.x, 0.02, midpoint.z)
	_drag_label.text = "%.1f\"" % distance_inches
	_drag_label.rotation = Vector3(-PI/2, angle, 0)

	# Tint the drag line by the terrain it crosses (OPR Difficult/Dangerous Terrain,
	# Asgard rulebook). The detection RULE stays; only the large on-table skull/
	# exclamation symbols were removed (intentionally no Label3D indicator here).
	var line_color = Color.CYAN  # Default drag line color

	if terrain_overlay and terrain_overlay.has_method("get_terrain_at_world_position"):
		# Sample terrain at multiple points along the line
		var num_samples = int(max(3, length * 20))  # At least 3 samples, more for longer lines
		var has_difficult = false
		var has_dangerous = false

		for i in range(num_samples):
			var t = float(i) / float(num_samples - 1)
			var sample_pos = from_pos.lerp(to_pos, t)
			var terrain_type = terrain_overlay.get_terrain_at_world_position(sample_pos)

			# TerrainType enum: NONE=0, RUINS=1, FOREST=2, CONTAINER=3, DANGEROUS=4
			if terrain_type == 2:  # FOREST (Difficult Terrain)
				has_difficult = true
			elif terrain_type == 4:  # DANGEROUS
				has_dangerous = true

		# Tint the line by terrain (Dangerous overrides Difficult).
		if has_dangerous:
			line_color = Color.RED
		elif has_difficult:
			line_color = Color.ORANGE

	# Update line material color
	var mat = _drag_line.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = line_color


## Destroy drag visualization
func _destroy_drag_line() -> void:
	if _drag_line:
		_drag_line.queue_free()
		_drag_line = null
	if _drag_label:
		_drag_label.queue_free()
		_drag_label = null


## Highest ground surface (table top or a terrain prop like a container) directly beneath
## `xz`, found by a downward physics ray on the ground layer only. Miniatures live on
## layer 2, so the ray ignores them — models rest on terrain, never on each other.
## Returns the table top (0.0) when nothing is hit. Placement aid; enforces no rule.
## `exclude` holds body RIDs to ignore — used while dragging so a movable terrain prop
## (whose own walkable floors are on the ground layer) rests on the table or a lower prop
## instead of climbing onto itself.
func _surface_y_under(xz: Vector3, exclude: Array = []) -> float:
	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return 0.0
	var from := Vector3(xz.x, SURFACE_PROBE_TOP_Y, xz.z)
	var to := Vector3(xz.x, SURFACE_PROBE_BOTTOM_Y, xz.z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = GROUND_COLLISION_LAYER
	query.collide_with_bodies = true
	query.exclude = exclude
	var hit := space_state.intersect_ray(query)
	return _pick_surface_y(hit, 0.0)


## Physics RIDs of the currently-selected bodies, so a drag's surface probe ignores the
## objects being dragged (they must not rest on themselves).
func _dragged_body_rids() -> Array:
	var rids: Array = []
	for obj in _selected_objects:
		if is_instance_valid(obj) and obj is CollisionObject3D:
			rids.append((obj as CollisionObject3D).get_rid())
	return rids


## Pure decision behind _surface_y_under: given a downward-ray hit (empty = miss), return
## the resting surface Y, or `fallback` on a miss. Extracted so it is unit-testable
## without a physics scene.
static func _pick_surface_y(hit: Dictionary, fallback: float) -> float:
	if hit.is_empty():
		return fallback
	var pos = hit.get("position", null)
	if pos == null:
		return fallback
	return (pos as Vector3).y


func _update_drag(screen_pos: Vector2) -> void:
	if _selected_objects.is_empty() or not _is_dragging:
		return

	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	var from = camera.project_ray_origin(screen_pos)
	var dir = camera.project_ray_normal(screen_pos)

	# Use first selected object as reference for drag plane
	var anchor = _selected_objects[0]
	if not is_instance_valid(anchor):
		return

	# Intersect with drag plane at table level (y=0) for XZ movement
	var drag_plane_at_table = Plane(Vector3.UP, 0)
	var intersection = drag_plane_at_table.intersects_ray(from, dir)

	if intersection:
		# Movement delta = how far the cursor moved since the grab, so the grabbed point
		# stays under the cursor (the unit no longer snaps its first model to the cursor).
		var delta_xz = Vector3(intersection.x - _drag_grab_world.x, 0, intersection.z - _drag_grab_world.z)

		# AoF:R v3.5.1 p.8 — Rush/Charge are forward-only. Hold Shift while dragging a
		# regiment tray to lock movement to its facing axis (forward/backward only, no
		# sideways drift). The player decides whether the move is a legal Rush/Charge;
		# this is a sandbox movement aid, not a rule enforcement.
		if Input.is_key_pressed(KEY_SHIFT) and anchor is RegimentTray:
			delta_xz = RegimentTray.project_drag_onto_facing(delta_xz, (anchor as RegimentTray).facing_dir())

		# Movement cap (opt-in): don't let the drag exceed the unit's Advance/Rush allowance. Clamp
		# the shared delta length, so the whole group is capped by the anchor's travel. Composes
		# after the axis-lock (direction) — cap then limits the magnitude.
		if _movement_cap_meters > 0.0 and delta_xz.length() > _movement_cap_meters:
			delta_xz = delta_xz.normalized() * _movement_cap_meters

		# Move all selected objects by the same XZ delta (formation kept). Each model's
		# Y rests on the ground surface beneath its own base (table or a terrain prop),
		# lifted by drag_lift_height while dragging — so a unit climbs onto a container
		# per model and settles to the surface on drop. The dragged bodies are excluded
		# from the probe so a movable terrain prop never climbs onto its own floors.
		# Move only the registered movable objects (own/unowned) — _drag_start_positions was
		# populated own-only in _start_dragging, so another player's selected models stay put.
		var exclude_rids := _dragged_body_rids()
		for obj in _drag_start_positions:
			if is_instance_valid(obj):
				var obj_start = _drag_start_positions.get(obj, obj.global_position)
				var new_x: float = obj_start.x + delta_xz.x
				var new_z: float = obj_start.z + delta_xz.z
				var surface_y: float = _surface_y_under(Vector3(new_x, 0.0, new_z), exclude_rids)
				obj.global_position = Vector3(new_x, surface_y + drag_lift_height, new_z)

		# Broadcast positions throttled to ~20 Hz to avoid relay rate limit
		_move_broadcast_timer += get_process_delta_time()
		if _move_broadcast_timer >= MOVE_BROADCAST_INTERVAL and _network_manager and _network_manager.is_multiplayer_active():
			_move_broadcast_timer = 0.0
			if _drag_start_positions.size() <= 1:
				# Single object: use regular move broadcast
				for obj in _drag_start_positions:
					if is_instance_valid(obj) and obj.has_meta("network_id"):
						_network_manager.broadcast_move(obj.get_meta("network_id"), obj.global_position)
			else:
				# Multiple objects: batch into a single RPC to avoid relay rate limit
				var batch: Array = []
				for obj in _drag_start_positions:
					if is_instance_valid(obj) and obj.has_meta("network_id"):
						batch.append(int(obj.get_meta("network_id")))
						batch.append(obj.global_position.x)
						batch.append(obj.global_position.y)
						batch.append(obj.global_position.z)
				if not batch.is_empty():
					_network_manager.broadcast_move_batch(batch)

		# Calculate horizontal distance for display
		var current_anchor_pos = anchor.global_position
		var horizontal_distance = _horizontal_distance(_drag_anchor_position, current_anchor_pos)
		var distance_inches = horizontal_distance * METERS_TO_INCHES

		# Update drag line visualization
		_update_drag_line(_drag_anchor_position, current_anchor_pos, distance_inches)

		# Emit distance
		distance_changed.emit(distance_inches, _drag_anchor_position, current_anchor_pos)

		# Throttled live update for coherency feedback while dragging
		_coherency_update_timer += get_process_delta_time()
		if _coherency_update_timer >= COHERENCY_UPDATE_INTERVAL:
			_coherency_update_timer = 0.0
			drag_updated.emit()


## Start measuring distance from a point on the table
func _start_measuring(screen_pos: Vector2) -> void:
	_hover_glow.set_target(null)
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 100

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = true

	var result = space_state.intersect_ray(query)

	if result:
		_is_measuring = true
		# If hit an object, store reference and mark as snapped
		if result.collider.is_in_group("selectable"):
			_measure_start_object = result.collider
			_measure_start_position = result.collider.global_position
			_measure_start_position.y = 0.02  # Slightly above table for visibility
			_measure_start_snapped = true
		else:
			_measure_start_object = null
			_measure_start_position = result.position
			_measure_start_position.y = 0.02
			_measure_start_snapped = false

		# Create measurement line and label
		_create_measure_line()
		_measure_has_value = false  # nothing to pin until the first update draws a line


## Update measurement line while dragging
func _update_measurement(screen_pos: Vector2) -> void:
	if not _is_measuring:
		return

	var end_data = _get_measure_end_position(screen_pos)
	if end_data:
		var end_center: Vector3 = end_data["position"]
		_measure_end_snapped = end_data["snapped"]
		_measure_end_object = end_data["object"]

		# Calculate edge positions for snapped objects
		var start_pos = _measure_start_position
		var end_pos = end_center

		# If start snapped to object, calculate edge closest to end
		if _measure_start_snapped and _measure_start_object:
			start_pos = _get_edge_position(_measure_start_object, _measure_start_position, end_center)

		# If end snapped to object, calculate edge closest to start
		if _measure_end_snapped and _measure_end_object:
			end_pos = _get_edge_position(_measure_end_object, end_center, _measure_start_position)

		# Calculate HORIZONTAL distance only (XZ plane) - edge to edge
		var distance_m = _horizontal_distance(start_pos, end_pos)
		var distance_inches = distance_m * METERS_TO_INCHES

		# Update line and label
		var both_snapped = _measure_start_snapped and _measure_end_snapped
		_update_measure_line(start_pos, end_pos, distance_inches, both_snapped)

		distance_changed.emit(distance_inches, start_pos, end_pos)

		_update_front_arc_aid(start_pos, end_pos)


## Stop measuring and emit final result
func _stop_measuring(screen_pos: Vector2) -> void:
	if _is_measuring:
		var end_data = _get_measure_end_position(screen_pos)
		if end_data:
			var end_center: Vector3 = end_data["position"]
			var end_obj = end_data["object"]

			# Calculate edge positions
			var start_pos = _measure_start_position
			var end_pos = end_center

			if _measure_start_snapped and _measure_start_object:
				start_pos = _get_edge_position(_measure_start_object, _measure_start_position, end_center)

			if end_data["snapped"] and end_obj:
				end_pos = _get_edge_position(end_obj, end_center, _measure_start_position)

			# Calculate HORIZONTAL distance only - edge to edge
			var distance_m = _horizontal_distance(start_pos, end_pos)
			var distance_inches = distance_m * METERS_TO_INCHES
			measurement_finished.emit(distance_inches)

		# Clean up line and label
		if _measure_line:
			_measure_line.queue_free()
			_measure_line = null
		if _measure_label:
			_measure_label.queue_free()
			_measure_label = null
		if _measure_los_warning:
			_measure_los_warning.queue_free()
			_measure_los_warning = null
		if _measure_front_label:
			_measure_front_label.queue_free()
			_measure_front_label = null

	_is_measuring = false
	_measure_start_position = Vector3.ZERO
	_measure_start_snapped = false
	_measure_end_snapped = false
	_measure_start_object = null
	_measure_end_object = null


## Get measurement end position - snaps to objects if hit
## Returns Dictionary with "position", "snapped", and "object" keys, or null
func _get_measure_end_position(screen_pos: Vector2) -> Variant:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return null

	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 100

	# First check if we hit an object
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = true

	var result = space_state.intersect_ray(query)

	if result:
		# If hit a selectable object, snap to its base position
		if result.collider.is_in_group("selectable"):
			var obj_pos = result.collider.global_position
			return {
				"position": Vector3(obj_pos.x, 0.02, obj_pos.z),
				"snapped": true,
				"object": result.collider
			}
		else:
			# Hit table or other surface - use that point
			return {
				"position": Vector3(result.position.x, 0.02, result.position.z),
				"snapped": false,
				"object": null
			}

	# Fallback: intersect with table plane
	var dir = camera.project_ray_normal(screen_pos)
	var table_plane = Plane(Vector3.UP, 0)
	var intersection = table_plane.intersects_ray(from, dir)
	if intersection:
		return {
			"position": Vector3(intersection.x, 0.02, intersection.z),
			"snapped": false,
			"object": null
		}

	return null


## Get edge distance from center in a specific direction for an object.
## For oval bases, calculates actual ellipse edge distance.
## dir_x, dir_z should be normalized direction components.
func _get_edge_distance_in_direction(obj: Node3D, dir_x: float, dir_z: float) -> float:
	if not obj.is_in_group("miniature"):
		if obj.is_in_group("dice"):
			return 0.008
		elif obj.is_in_group("terrain"):
			return 0.015
		return 0.016

	var game_unit = obj.get_meta("game_unit", null) as GameUnit
	if not game_unit or not game_unit.unit_properties:
		return MINIATURE_RADIUS

	# Use the model's ACTUAL base: a per-model Tough upgrade enlarges it (the mesh stays
	# natural-sized), so the ruler edge anchors to the base you see, not the suggested one.
	var edge_tough := 0
	var edge_mi = UnitUtils.get_model_instance(obj)
	if edge_mi and edge_mi.properties:
		edge_tough = int(edge_mi.properties.get("tough", 0))
	var props = OPRArmyManager.effective_base_props(game_unit.unit_properties, edge_tough)

	if props.get("base_is_oval", false):
		# Oval base - calculate actual ellipse edge distance
		var width_mm = props.get("base_width_mm", 32)
		var depth_mm = props.get("base_depth_mm", 32)
		var a = (width_mm / 2.0) * 0.001  # Semi-axis X (width/2) in meters
		var b = (depth_mm / 2.0) * 0.001  # Semi-axis Z (depth/2) in meters

		# Distance to ellipse edge in direction (dir_x, dir_z):
		# r = (a * b) / sqrt(b² * dir_x² + a² * dir_z²)
		var denominator = sqrt(b * b * dir_x * dir_x + a * a * dir_z * dir_z)
		if denominator < 0.0001:
			return (a + b) / 2.0  # Fallback to average
		return (a * b) / denominator
	else:
		# Round base - simple radius
		var base_mm = props.get("base_size_round", 32)
		return (base_mm / 2.0) * 0.001


## Calculate edge position on object closest to target point
func _get_edge_position(obj: Node3D, obj_center: Vector3, target_pos: Vector3) -> Vector3:
	# Direction from object center to target (horizontal only)
	var dir = Vector3(target_pos.x - obj_center.x, 0, target_pos.z - obj_center.z)
	var dist = dir.length()

	if dist < 0.001:
		# Target is at center, pick arbitrary direction
		dir = Vector3(1, 0, 0)
	else:
		dir = dir.normalized()

	# Get edge distance in this direction (handles oval bases)
	var edge_dist = _get_edge_distance_in_direction(obj, dir.x, dir.z)

	# Edge point is center + direction * edge_distance
	var edge_pos = Vector3(obj_center.x + dir.x * edge_dist, 0.02, obj_center.z + dir.z * edge_dist)
	return edge_pos


## Calculate horizontal distance (XZ plane only, ignoring Y)
func _horizontal_distance(from_pos: Vector3, to_pos: Vector3) -> float:
	var dx = to_pos.x - from_pos.x
	var dz = to_pos.z - from_pos.z
	return sqrt(dx * dx + dz * dz)


## Create a visual line and label for measurement
func _create_measure_line() -> void:
	if _measure_line:
		_measure_line.queue_free()
	if _measure_label:
		_measure_label.queue_free()

	# Create line mesh (render first, lower priority)
	_measure_line = MeshInstance3D.new()
	_measure_line.name = "MeasureLine"
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.YELLOW
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true  # Always visible
	# Join the transparent queue with a high priority so the line draws OVER ground decals (blood/oil
	# stains): an opaque line is painted over by transparent stains regardless of no_depth_test, since
	# transparent always renders after opaque (issue #82).
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = OVERLAY_UI_RENDER_PRIORITY
	_measure_line.material_override = material
	add_child(_measure_line)

	# Create 3D label for distance display (~2cm text height)
	# Render after line to appear on top
	_measure_label = Label3D.new()
	_measure_label.name = "MeasureLabel"
	_measure_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED  # Align with line direction
	_measure_label.no_depth_test = true
	_measure_label.render_priority = OVERLAY_UI_LABEL_PRIORITY  # above the line + ground stains (issue #82)
	_measure_label.pixel_size = 0.001  # 1mm per pixel
	_measure_label.font_size = 24      # ~2.4cm text height
	_measure_label.outline_size = 8  # Thicker outline for better contrast
	_measure_label.modulate = Color.WHITE
	_measure_label.outline_modulate = Color.BLACK
	_measure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_measure_label)


## Update the measurement line mesh and label
func _update_measure_line(from_pos: Vector3, to_pos: Vector3, distance_inches: float, both_snapped: bool) -> void:
	if not _measure_line or not _measure_label:
		return

	# Calculate horizontal direction (XZ plane only)
	var direction = Vector3(to_pos.x - from_pos.x, 0, to_pos.z - from_pos.z)
	var length = direction.length()

	if length < 0.001:
		_measure_line.visible = false
		_measure_label.visible = false
		_measure_has_value = false
		return

	_measure_line.visible = true
	_measure_label.visible = true

	# Create a thin flat box as line (horizontal on XZ plane)
	var line_mesh = BoxMesh.new()
	line_mesh.size = Vector3(length, 0.001, 0.002)  # Length along X, 1mm height, 2mm depth

	_measure_line.mesh = line_mesh

	# Position at midpoint, just above table surface
	var midpoint = (from_pos + to_pos) / 2
	midpoint.y = 0.005  # 0.5cm above table
	_measure_line.global_position = midpoint

	# Rotate to align with direction (rotation around Y axis)
	var angle = atan2(direction.x, direction.z)
	_measure_line.rotation = Vector3(0, angle + PI/2, 0)

	# Update label position (at midpoint, above line)
	_measure_label.global_position = Vector3(midpoint.x, 0.02, midpoint.z)  # 2cm above table
	_measure_label.text = "%.1f\"" % distance_inches

	# Rotate label to align with measurement line direction
	# Face along the line, tilted to be readable from above
	var label_angle = atan2(direction.x, direction.z)
	_measure_label.rotation = Vector3(-PI/2, label_angle, 0)  # Flat, facing up, aligned with line

	# Update line material color (green if both ends snapped, yellow otherwise)
	var line_color = Color.GREEN if both_snapped else Color.YELLOW

	# Check LOS along the path, height-aware per the Asgard standard: a terrain zone
	# between the two points blocks only if its Height >= BOTH endpoints' Height and
	# neither endpoint stands inside that zone (you see in/out of your own zone).
	var los_blocked = false
	if terrain_overlay and terrain_overlay.has_method("has_line_of_sight"):
		var from_height := _object_height_category(_measure_start_object)
		var to_height := _object_height_category(_measure_end_object)
		if not terrain_overlay.has_line_of_sight(from_pos, to_pos, from_height, to_height):
			los_blocked = true
			line_color = Color.RED  # Change line to red if LOS is blocked
		# Units block sight lines too (Asgard: formation Height, <1" gaps closed).
		elif _units_block_measure_line(from_pos, to_pos, from_height, to_height):
			los_blocked = true
			line_color = Color.RED

	var mat = _measure_line.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = line_color

	# Show LOS blocking warning if blocked
	if los_blocked:
		if not _measure_los_warning:
			_measure_los_warning = Label3D.new()
			_measure_los_warning.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_measure_los_warning.no_depth_test = true
			_measure_los_warning.render_priority = OVERLAY_UI_LABEL_PRIORITY  # above ground stains (issue #82)
			_measure_los_warning.font_size = 32
			add_child(_measure_los_warning)

		_measure_los_warning.visible = true
		_measure_los_warning.text = "🚫"  # Blocked symbol
		_measure_los_warning.modulate = Color.RED
		# Position slightly higher than other labels
		_measure_los_warning.global_position = Vector3(midpoint.x, 0.08, midpoint.z)
	else:
		if _measure_los_warning:
			_measure_los_warning.visible = false

	# Label stays white with black outline for best readability
	_measure_label.modulate = Color.WHITE

	# Snapshot the live measurement so P (pin) can freeze exactly what is shown.
	_measure_last_from = from_pos
	_measure_last_to = to_pos
	_measure_last_distance = distance_inches
	_measure_last_blocked = los_blocked
	_measure_has_value = true


## Asgard Height category (1-6) of a measured endpoint's object, read from its
## ModelInstance meta. Table points / non-model objects default to infantry (2).
func _object_height_category(obj: Node3D) -> int:
	var model := _object_model_instance(obj)
	return LosRules.model_height_category(model) if model else LosRules.HEIGHT_INFANTRY


## The ModelInstance attached to a measured object (meta on the node or its
## parent), or null for table points / non-OPR objects.
func _object_model_instance(obj: Node3D) -> ModelInstance:
	if obj == null:
		return null
	for node in [obj, obj.get_parent()]:
		if node and node.has_meta("model_instance"):
			var model = node.get_meta("model_instance")
			if model is ModelInstance:
				return model
	return null


## Unit-as-LOS-blocker check for the measure line (Asgard, display-only): every
## OPR model on the table blocks at its Height; <1" gaps inside a unit count as
## closed. The units at the measure line's endpoints never block their own line.
func _units_block_measure_line(from_pos: Vector3, to_pos: Vector3,
		from_height: int, to_height: int) -> bool:
	var exclude_units: Array[int] = []
	for endpoint: Node3D in [_measure_start_object, _measure_end_object]:
		var endpoint_model := _object_model_instance(endpoint)
		if endpoint_model and endpoint_model.unit:
			exclude_units.append(endpoint_model.unit.get_instance_id())

	var blockers: Array[LosRules.Blocker] = []
	for node: Node in get_tree().get_nodes_in_group("miniature"):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var model := _object_model_instance(node as Node3D)
		if model == null:
			continue  # custom minis without an OPR profile carry no Height
		if not model.is_alive:
			continue  # dead models are only hidden, not freed — they must not block line of sight
		# Models without a unit block alone, keyed by their own node id (no
		# gap-closure partner, never excludable via a unit).
		var unit_key: int = model.unit.get_instance_id() if model.unit else node.get_instance_id()
		var pos_3d := (node as Node3D).global_position
		blockers.append(LosRules.Blocker.new(
			Vector2(pos_3d.x, pos_3d.z),
			LosRules.model_base_radius_m(model),
			LosRules.model_height_category(model),
			unit_key))

	return LosRules.units_block_line(
		Vector2(from_pos.x, from_pos.z), Vector2(to_pos.x, to_pos.z),
		from_height, to_height, blockers, exclude_units)


# ==============================================================================
# PERSISTENT SHARED RULERS (pinned measurements)
# ==============================================================================

## Pin the live measurement: drop a persistent ruler in the local player's colour and
## replicate it to all peers. Display-only — it shows distance/LoS, decides nothing.
func _pin_current_measurement() -> void:
	if not _measure_has_value or pinned_rulers == null:
		return
	var owner_peer := _local_owner_peer()
	var ruler_id := _next_ruler_id(owner_peer)
	pinned_rulers.add_ruler(ruler_id, owner_peer, _measure_last_from, _measure_last_to,
			_measure_last_distance, _measure_last_blocked)
	if _network_manager and _network_manager.has_method("broadcast_ruler_pin"):
		_network_manager.broadcast_ruler_pin(ruler_id, owner_peer, _measure_last_from,
				_measure_last_to, _measure_last_distance, _measure_last_blocked)


## Right-click on a pinned ruler removes it. Each player removes only their own; the host
## may remove anyone's. No ruler under the cursor → no-op (right-drag still moves the camera).
func _try_remove_ruler_at(screen_pos: Vector2) -> void:
	if pinned_rulers == null:
		return
	var table_pos := _get_table_position_at_screen(screen_pos)
	if table_pos == Vector3.INF:
		return
	var ruler_id: int = pinned_rulers.nearest_ruler_at(
			table_pos, RULER_REMOVE_RADIUS_M, _ruler_owner_filter())
	if ruler_id < 0:
		return
	pinned_rulers.remove_ruler(ruler_id)
	if _network_manager and _network_manager.has_method("broadcast_ruler_clear"):
		_network_manager.broadcast_ruler_clear(ruler_id)
	get_viewport().set_input_as_handled()


## Clear all of the local player's rulers (key K).
func _clear_my_rulers() -> void:
	if pinned_rulers == null:
		return
	var owner_peer := _local_owner_peer()
	pinned_rulers.clear_owner(owner_peer)
	if _network_manager and _network_manager.has_method("broadcast_ruler_clear_owner"):
		_network_manager.broadcast_ruler_clear_owner(owner_peer)


## Host clears EVERYONE's rulers (Shift+K). A non-host Shift+K just clears their own.
func _clear_all_rulers() -> void:
	if pinned_rulers == null:
		return
	if _is_networked() and not multiplayer.is_server():
		_clear_my_rulers()
		return
	pinned_rulers.clear_all()
	if _network_manager and _network_manager.has_method("broadcast_ruler_clear_all"):
		_network_manager.broadcast_ruler_clear_all()


## Local player's peer id (1 in solo play, where rulers use a neutral colour).
func _local_owner_peer() -> int:
	return multiplayer.get_unique_id() if _is_networked() else SOLO_OWNER_PEER


## In MP a non-host may only remove their own rulers; the host (and solo play) any.
func _ruler_owner_filter() -> int:
	if _is_networked() and not multiplayer.is_server():
		return _local_owner_peer()
	return -1


## Collision-free, owner-scoped ruler id so pins from different players never clash.
func _next_ruler_id(owner_peer: int) -> int:
	_ruler_id_counter += 1
	return owner_peer * 1000000 + _ruler_id_counter


func _is_networked() -> bool:
	return _network_manager != null and _network_manager.has_method("is_multiplayer_active") \
			and _network_manager.is_multiplayer_active()


## Find a spawned object by its network_id (unique: OPR uses slot*STRIDE + counter). Used by the
## restore path to make a doubly-delivered model idempotent — spawn exactly once. Linear scan;
## fine at army sizes (tens of models). Returns null if none matches.
func find_by_network_id(net_id: int) -> Node3D:
	if net_id < 0:
		return null
	for child in get_children():
		if child is Node3D and child.has_meta("network_id") and int(child.get_meta("network_id")) == net_id:
			return child
	return null


## Spawn a miniature at the given position
## If broadcast is true and multiplayer is active, syncs to other clients
func spawn_miniature(pos: Vector3, broadcast: bool = true, network_id: int = -1) -> Node3D:
	_object_counter += 1

	# Generate network ID if not provided
	var obj_network_id = network_id if network_id >= 0 else _object_counter

	var miniature = StaticBody3D.new()
	miniature.name = "Miniature_%d" % _object_counter
	miniature.set_meta("network_id", obj_network_id)
	miniature.add_to_group("selectable")
	miniature.add_to_group("miniature")

	var base_height = 0.003  # 3mm base thickness

	# Create base (circular)
	var base_mesh = CylinderMesh.new()
	base_mesh.top_radius = MINIATURE_RADIUS
	base_mesh.bottom_radius = MINIATURE_RADIUS
	base_mesh.height = base_height

	var base_instance = MeshInstance3D.new()
	base_instance.mesh = base_mesh
	base_instance.position.y = base_height / 2

	var base_material = StandardMaterial3D.new()
	base_material.albedo_color = Color(0.1, 0.1, 0.1)
	base_instance.material_override = base_material

	# Enable shadow casting for base
	base_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	miniature.add_child(base_instance)

	# Create simple model (cylinder as placeholder)
	var model_mesh = CylinderMesh.new()
	model_mesh.top_radius = MINIATURE_RADIUS * 0.4
	model_mesh.bottom_radius = MINIATURE_RADIUS * 0.6
	model_mesh.height = MINIATURE_HEIGHT

	var model_instance = MeshInstance3D.new()
	model_instance.mesh = model_mesh
	model_instance.position.y = MINIATURE_HEIGHT / 2 + base_height  # Above base

	var model_material = StandardMaterial3D.new()
	model_material.albedo_color = Color(randf(), randf(), randf())  # Random color
	model_instance.material_override = model_material
	miniature.add_child(model_instance)

	# Store material reference for selection highlight
	miniature.set_meta("model_material", model_material)
	miniature.set_meta("original_color", model_material.albedo_color)

	# Add collision
	var collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = MINIATURE_RADIUS
	shape.height = MINIATURE_HEIGHT + base_height
	collision.shape = shape
	collision.position.y = (MINIATURE_HEIGHT + base_height) / 2
	miniature.add_child(collision)

	# Set collision layers: miniatures on layer 2 so the placement raycast (ground-only)
	# rests them on terrain, never on each other.
	miniature.collision_layer = MINIATURE_COLLISION_LAYER
	miniature.collision_mask = GROUND_COLLISION_LAYER

	# Add selection methods
	miniature.set_script(preload("res://scripts/selectable_object.gd"))

	# IMPORTANT: Add to tree BEFORE setting global_position
	add_child(miniature)
	miniature.global_position = pos

	# Broadcast to other clients if in multiplayer
	if broadcast and _network_manager and _network_manager.is_multiplayer_active():
		_network_manager.broadcast_spawn("miniature", pos, obj_network_id)

	return miniature


## Spawn terrain piece at the given position
## If broadcast is true and multiplayer is active, syncs to other clients
func spawn_terrain(pos: Vector3, broadcast: bool = true, network_id: int = -1) -> StaticBody3D:
	_object_counter += 1

	# Generate network ID if not provided
	var obj_network_id = network_id if network_id >= 0 else _object_counter + 10000  # Offset to avoid conflicts

	var terrain = StaticBody3D.new()
	terrain.name = "Terrain_%d" % _object_counter
	terrain.set_meta("network_id", obj_network_id)
	terrain.add_to_group("selectable")
	terrain.add_to_group("terrain")

	# Random terrain type
	var terrain_types = ["rock", "building", "tree"]
	var terrain_type = terrain_types[randi() % terrain_types.size()]

	var mesh: Mesh
	var height: float

	match terrain_type:
		"rock":
			mesh = _create_rock_mesh()
			height = 0.25  # 25cm
		"building":
			mesh = _create_building_mesh()
			height = 0.6  # 60cm
		"tree":
			mesh = _create_tree_mesh()
			height = 0.6  # 60cm
		_:
			mesh = BoxMesh.new()
			height = 0.3  # 30cm

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.position.y = height / 2

	var material = StandardMaterial3D.new()
	match terrain_type:
		"rock":
			material.albedo_color = Color(0.4, 0.4, 0.4)
		"building":
			material.albedo_color = Color(0.6, 0.5, 0.4)
		"tree":
			material.albedo_color = Color(0.2, 0.5, 0.2)

	mesh_instance.material_override = material
	terrain.add_child(mesh_instance)

	terrain.set_meta("model_material", material)
	terrain.set_meta("original_color", material.albedo_color)

	# Add collision based on terrain type
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	match terrain_type:
		"rock":
			shape.size = Vector3(0.4, height, 0.35)
		"building":
			shape.size = Vector3(0.5, height, 0.5)
		"tree":
			shape.size = Vector3(0.3, height, 0.3)
		_:
			shape.size = Vector3(0.3, height, 0.3)
	collision.shape = shape
	collision.position.y = height / 2
	terrain.add_child(collision)

	terrain.set_script(preload("res://scripts/selectable_object.gd"))

	# IMPORTANT: Add to tree BEFORE setting global_position
	add_child(terrain)
	terrain.global_position = pos

	# Broadcast to other clients if in multiplayer
	if broadcast and _network_manager and _network_manager.is_multiplayer_active():
		_network_manager.broadcast_spawn("terrain", pos, obj_network_id)

	return terrain


## Network-ID offset for free-placed sandbox terrain (keeps ranges from colliding with the
## miniature/terrain/custom-model offsets above).
const SANDBOX_TERRAIN_NETWORK_OFFSET: int = 40000
## Footprint (inches) for a sandbox piece whose catalogue entry omits one.
const SANDBOX_DEFAULT_FOOTPRINT_INCHES: float = 3.0

## Grassland ruin catalogue. Ruins are built procedurally from the SAME mossy masonry wall
## panels as the competitive grid ruins (RuinsLibrary, already on R2) — no new GLB assets and
## no model-forge dependency. Keyed by prop_id -> {footprint, floors (storey heights, inches),
## label}.
const SANDBOX_RUINS: Dictionary = {
	"ruin_small_1f": {"footprint": Vector2(3, 3), "floors": [0.0], "label": "Ruin (small, 1 floor)"},
	"ruin_corner_wall": {"footprint": Vector2(2, 2), "floors": [0.0], "label": "Ruin corner wall"},
	"ruin_medium_1f": {"footprint": Vector2(6, 4), "floors": [0.0], "label": "Ruin (medium, 1 floor)"},
	"ruin_medium_2f": {"footprint": Vector2(6, 4), "floors": [0.0, 3.0], "label": "Ruin (medium, 2 floors)"},
	"ruin_large_2f": {"footprint": Vector2(9, 6), "floors": [0.0, 3.0], "label": "Ruin (large, 2 floors)"},
	"ruin_large_3f": {"footprint": Vector2(9, 6), "floors": [0.0, 3.0, 6.0], "label": "Ruin (large, 3 floors)"},
}

## Tree-group / hazard-cluster catalogue (the non-ruin sandbox pieces, which reuse existing
## tree/hazard art). Keyed by prop_id -> {kind, footprint, label}.
## Forests are OVAL pads (footprint = bounding box: long axis × widest point).
const SANDBOX_GROUPS: Dictionary = {
	"forest_small": {"kind": SandboxPropKind.FOREST, "footprint": Vector2(6, 4), "label": "Forest (small)"},
	"forest_large": {"kind": SandboxPropKind.FOREST, "footprint": Vector2(9, 6), "label": "Forest (large)"},
	# "minefield" is the internal key (kept for save compatibility); the label + actual props read as
	# generic dangerous terrain (per-biome props are chosen at build time). Oval footprint like the
	# small forest (6×4), not a 6×6 circle.
	"minefield": {"kind": SandboxPropKind.HAZARD_CLUSTER, "footprint": Vector2(6, 4), "label": "Dangerous Terrain"},
}

## Biome prefixes a sandbox FOREST or HAZARD field can carry, encoded INTO its prop_id (e.g.
## "desert_forest_small", "desert_minefield") so save + broadcast preserve the biome through the
## existing prop_id field — no new wire/save fields. Kept in sync with SandboxTerrainShelf.BIOMES.
## The mine props themselves stay procedural; only the oval pad floor crops the biome battlemap.
const SANDBOX_BIOME_PREFIXES: Array[String] = ["", "desert_", "tundra_", "volcanic_", "jungle_", "urban_"]


## Shared ruin library for sandbox terrain, created on first use.
func _get_ruins_library() -> RuinsLibrary:
	if _ruins_library == null or not is_instance_valid(_ruins_library):
		_ruins_library = RuinsLibrary.new()
		_ruins_library.name = "SandboxRuinsLibrary"
		add_child(_ruins_library)
	return _ruins_library


## Shared tree library for sandbox forest clusters, created on first use.
func _get_trees_library() -> TreesLibrary:
	if _trees_library == null or not is_instance_valid(_trees_library):
		_trees_library = TreesLibrary.new()
		_trees_library.name = "SandboxTreesLibrary"
		add_child(_trees_library)
	return _trees_library


## Shared biome-battlemap library for sandbox forest floors, created on first use. A non-grassland
## forest crops a tile of its biome battlemap as the pad texture (shares the user:// cache the table
## already fills, so a battlemap fetched for the table is reused on disk).
func _get_biome_library() -> BiomeLibrary:
	if _biome_library == null or not is_instance_valid(_biome_library):
		_biome_library = BiomeLibrary.new()
		_biome_library.name = "SandboxBiomeLibrary"
		add_child(_biome_library)
	return _biome_library


## Shared hazard-model (GLB) resolver for sandbox dangerous-terrain clusters, created on first use.
## Resolves the per-biome hazard props (volcanic lava crater, jungle/alien carnivore plant) from R2,
## like the trees library does for forests; grassland/desert/tundra/urban keep procedural mines.
func _get_hazards_library() -> HazardsLibrary:
	if _hazards_library == null or not is_instance_valid(_hazards_library):
		_hazards_library = HazardsLibrary.new()
		_hazards_library.name = "SandboxHazardsLibrary"
		add_child(_hazards_library)
	return _hazards_library


## Spawn a free-placed casual-sandbox terrain piece at `pos`. RUIN kinds become a walkable
## multi-storey SandboxTerrainProp; FOREST/HAZARD_CLUSTER kinds become a TerrainGroupBase
## (several tree/mine visuals on one draggable base). Either way it is a first-class
## selectable object, so the existing drag/rotate/undo/multiplayer paths move it. Syncs to
## peers when `broadcast` and multiplayer is active.
func spawn_sandbox_terrain(prop_id: String, kind: int, pos: Vector3, broadcast: bool = true, network_id: int = -1) -> Node3D:
	_object_counter += 1
	var obj_network_id: int = network_id if network_id >= 0 else _object_counter + SANDBOX_TERRAIN_NETWORK_OFFSET

	var spawned: Node3D
	if kind == SandboxPropKind.FOREST or kind == SandboxPropKind.HAZARD_CLUSTER:
		spawned = _build_terrain_group(prop_id, kind, obj_network_id)
	else:
		spawned = _build_sandbox_ruin(prop_id, kind, obj_network_id)

	# Add to tree BEFORE positioning (matches the other spawners).
	add_child(spawned)
	spawned.global_position = Vector3(pos.x, 0.0, pos.z)
	# Members/visuals are built after positioning so cached GLBs fit correctly.
	if spawned is SandboxTerrainProp:
		(spawned as SandboxTerrainProp).build_visual(_get_ruins_library())
	elif spawned is TerrainGroupBase:
		# Seed from the (synced) network id so every client builds an identical cluster.
		(spawned as TerrainGroupBase).build(obj_network_id, _get_trees_library(), _get_biome_library(), _get_hazards_library())

	# Freshly placed terrain stays UNLOCKED so the player can drag it into position right away; it
	# only locks when the player manually locks it (select + L). No auto-lock tied to the shelf.

	if broadcast and _network_manager and _network_manager.is_multiplayer_active():
		_network_manager.broadcast_sandbox_terrain_spawn(prop_id, kind, spawned.global_position, obj_network_id)

	return spawned


## Enable/disable casual terrain editing. This now ONLY tracks the shelf state — locking is manual
## and per-piece (select + L): a freshly placed piece stays draggable until the player locks it, and
## a locked piece stays locked regardless of the shelf. (Was: ON unlocked every terrain piece, OFF
## locked them all — that auto-lock made a just-placed piece immovable the moment the shelf closed.)
func set_terrain_edit_mode(enabled: bool) -> void:
	_terrain_edit_mode = enabled


func is_terrain_edit_mode() -> bool:
	return _terrain_edit_mode


func _build_sandbox_ruin(prop_id: String, kind: int, obj_network_id: int) -> SandboxTerrainProp:
	var split := _split_sandbox_biome_prefix(prop_id)
	var biome_prefix: String = split[0]
	var base_id: String = split[1]
	var spec: Dictionary = SANDBOX_RUINS.get(base_id, {})
	var footprint: Vector2 = spec.get("footprint", Vector2(SANDBOX_DEFAULT_FOOTPRINT_INCHES, SANDBOX_DEFAULT_FOOTPRINT_INCHES))
	var floors: Array = spec.get("floors", [0.0])
	var prop := SandboxTerrainProp.new()
	prop.name = "SandboxTerrain_%d" % _object_counter
	# Keep the FULL (biome-prefixed) prop_id so save/meta round-trips the biome; the prefix selects
	# the themed RuinsLibrary wall panels (e.g. "desert_solid_a"), like a forest carries its biome.
	prop.configure(prop_id, kind, footprint, floors, biome_prefix)
	prop.set_meta("network_id", obj_network_id)
	return prop


## Catalogue of placeable sandbox pieces for the shelf browser. EVERY biome lists the ruins +
## forest/hazard groups; a ruin's wall panels and a forest's trees/floor are themed from the biome
## prefix carried in each entry's prop_id. Each entry is {prop_id, kind, label}.
func sandbox_catalog(biome_prefix: String = "") -> Array:
	var entries: Array = []
	for id in SANDBOX_RUINS.keys():
		var ruin: Dictionary = SANDBOX_RUINS[id]
		# A ruin carries its biome in the prop_id (e.g. "desert_ruin_small_1f"), like a forest, so
		# save/broadcast round-trip it via the existing prop_id field; the prefix themes its panels.
		entries.append({"prop_id": biome_prefix + id, "kind": SandboxPropKind.RUIN, "label": ruin.get("label", id)})
	for id in SANDBOX_GROUPS.keys():
		var spec: Dictionary = SANDBOX_GROUPS[id]
		var kind: int = spec.get("kind", SandboxPropKind.FOREST)
		# Forests AND hazard fields carry their biome in the prop_id (e.g. "desert_forest_small",
		# "desert_minefield"), so their oval pad crops the biome battlemap like the table does, and
		# save/broadcast round-trip the biome via the existing prop_id field.
		var entry_id: String = (biome_prefix + id) if (kind == SandboxPropKind.FOREST or kind == SandboxPropKind.HAZARD_CLUSTER) else id
		entries.append({"prop_id": entry_id, "kind": kind, "label": spec.get("label", id)})
	return entries


## Split a sandbox forest prop_id into [biome_prefix, base_id] — e.g. "desert_forest_small" ->
## ["desert_", "forest_small"]; an unprefixed id ("forest_small" / "minefield") -> ["", id].
func _split_sandbox_biome_prefix(prop_id: String) -> Array:
	for prefix in SANDBOX_BIOME_PREFIXES:
		if prefix != "" and prop_id.begins_with(prefix):
			return [prefix, prop_id.substr(prefix.length())]
	return ["", prop_id]


func _build_terrain_group(prop_id: String, kind: int, obj_network_id: int) -> TerrainGroupBase:
	var split := _split_sandbox_biome_prefix(prop_id)
	var biome_prefix: String = split[0]
	var base_id: String = split[1]
	var spec: Dictionary = SANDBOX_GROUPS.get(base_id, {})
	var footprint: Vector2 = spec.get("footprint", Vector2(SANDBOX_DEFAULT_FOOTPRINT_INCHES, SANDBOX_DEFAULT_FOOTPRINT_INCHES))
	var base := TerrainGroupBase.new()
	base.name = "SandboxTerrainGroup_%d" % _object_counter
	# Keep the FULL (biome-prefixed) prop_id on the base so save/meta round-trips the biome.
	base.configure(prop_id, kind, footprint, biome_prefix)
	base.set_meta("network_id", obj_network_id)
	return base


## Load and spawn a custom 3D model from GLB/GLTF/STL file
func spawn_custom_model(file_path: String, pos: Vector3, _broadcast: bool = true) -> Node3D:
	_object_counter += 1
	var obj_network_id = _object_counter + 20000  # Offset for custom models

	var model_scene: Node3D = null
	var extension = file_path.get_extension().to_lower()

	# Load based on file type (no base - we add our own below)
	match extension:
		"glb", "gltf":
			model_scene = _load_gltf_model(file_path, false)
		"stl":
			model_scene = _load_stl_model(file_path)
		"obj":
			model_scene = _load_obj_model(file_path, "", false)
		"fbx":
			# FBX cannot be loaded at runtime - Godot converts it during import
			push_warning("FBX files must be converted to GLB first. Use Blender or import into Godot project.")
			return null
		_:
			push_error("Unsupported model format: %s" % extension)
			return null

	if not model_scene:
		return null

	# Wrap in StaticBody3D for selection/collision
	var wrapper = StaticBody3D.new()
	wrapper.name = "CustomModel_%d" % _object_counter
	wrapper.set_meta("network_id", obj_network_id)
	wrapper.set_meta("model_path", file_path)
	wrapper.add_to_group("selectable")
	wrapper.add_to_group("custom_model")

	# Add the loaded model as child
	wrapper.add_child(model_scene)

	# Calculate bounding box for collision BEFORE adding base
	var aabb = _calculate_aabb(model_scene)
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = aabb.size
	collision.shape = shape
	collision.position = aabb.position + aabb.size / 2
	wrapper.add_child(collision)

	# Scale to reasonable size (target ~5cm height for miniatures)
	var max_dim = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
	var scale_factor = 1.0
	if max_dim > 0.001:
		var target_size = 0.05  # 5cm default target size
		scale_factor = target_size / max_dim
		model_scene.scale = Vector3(scale_factor, scale_factor, scale_factor)

	# Add 32mm base for custom models
	var base = _create_miniature_base()
	wrapper.add_child(base)

	# Position model so its bottom sits on top of base
	# The scaled AABB's lowest point (position.y) must be at base_height
	var base_height = 0.003  # 3mm base height
	var scaled_aabb_min_y = aabb.position.y * scale_factor
	model_scene.position.y = base_height - scaled_aabb_min_y

	# Update collision to include base + model
	var base_radius = 0.016  # 32mm diameter (16mm radius)
	var scaled_model_height = aabb.size.y * scale_factor
	var total_height = scaled_model_height + base_height
	shape.size = Vector3(base_radius * 2, total_height, base_radius * 2)
	collision.position = Vector3(0, total_height / 2, 0)

	# Enable shadows for model
	_enable_shadows_recursive(wrapper)

	wrapper.set_script(preload("res://scripts/selectable_object.gd"))

	# Add to scene
	add_child(wrapper)
	wrapper.global_position = pos

	return wrapper


## Load a GLB/GLTF model with optional 32mm base
func _load_gltf_model(file_path: String, add_base: bool = true) -> Node3D:
	var gltf_doc = GLTFDocument.new()
	var gltf_state = GLTFState.new()

	var error = gltf_doc.append_from_file(file_path, gltf_state)
	if error != OK:
		push_error("Failed to load GLTF: %s (error %d)" % [file_path, error])
		return null

	var model_scene = gltf_doc.generate_scene(gltf_state)
	if not model_scene:
		push_error("Failed to generate scene from GLTF: %s" % file_path)
		return null

	# If base not needed, return model as-is
	if not add_base:
		return model_scene

	# Wrap in Node3D with base
	var root = Node3D.new()
	root.name = "GLTF_Model"

	# Add wargaming base
	var base = _create_miniature_base()
	root.add_child(base)

	# Calculate model bounds to position it on top of base
	var aabb = _calculate_aabb(model_scene)
	var base_top = 0.003  # 3mm base height

	# Position model so its bottom sits on top of base
	model_scene.position.y = base_top - aabb.position.y

	root.add_child(model_scene)

	# Enable shadow casting for all meshes
	_enable_shadows_recursive(root)

	return root


## Load an STL model (binary or ASCII) with automatic base
func _load_stl_model(file_path: String) -> Node3D:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open STL file: %s" % file_path)
		return null

	var mesh: ArrayMesh = null

	# Check if binary or ASCII STL
	var header = file.get_buffer(80)
	var header_str = header.get_string_from_ascii()

	# Reset to start
	file.seek(0)

	if header_str.begins_with("solid") and not _is_binary_stl(file):
		mesh = _parse_ascii_stl(file)
	else:
		mesh = _parse_binary_stl(file)

	file.close()

	if not mesh:
		push_error("Failed to parse STL: %s" % file_path)
		return null

	# Create mesh instance with default material
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh

	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.7, 0.7)  # Default gray
	material.roughness = 0.5
	material.metallic = 0.0
	mesh_instance.material_override = material

	# Return mesh instance directly (base will be added by spawn_custom_model)
	# Enable shadow casting
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	return mesh_instance


## Create a standard wargaming base (32mm diameter)
func _create_miniature_base() -> MeshInstance3D:
	var base_radius = 0.016  # 16mm radius = 32mm diameter base
	var base_height = 0.003  # 3mm height

	var base_mesh = CylinderMesh.new()
	base_mesh.top_radius = base_radius
	base_mesh.bottom_radius = base_radius
	base_mesh.height = base_height

	var base_instance = MeshInstance3D.new()
	base_instance.mesh = base_mesh
	base_instance.name = "Base"

	# Position base so top is at y=0 (model sits on top)
	base_instance.position.y = base_height / 2

	# Black material for base
	var base_material = StandardMaterial3D.new()
	base_material.albedo_color = Color(0.1, 0.1, 0.1)  # Dark black
	base_material.roughness = 0.8
	base_instance.material_override = base_material

	# IMPORTANT: Enable shadow casting for the base!
	base_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	return base_instance


## Check if STL is binary (some ASCII files start with "solid" but are binary)
func _is_binary_stl(file: FileAccess) -> bool:
	# Binary STL: 80 byte header + 4 byte triangle count
	# Check if file size matches expected binary size
	var file_size = file.get_length()
	file.seek(80)
	var tri_count = file.get_32()
	file.seek(0)

	# Binary: 80 + 4 + (50 * tri_count)
	var expected_size = 84 + (50 * tri_count)
	return abs(file_size - expected_size) < 10  # Allow small tolerance


## Parse binary STL file
func _parse_binary_stl(file: FileAccess) -> ArrayMesh:
	# Skip 80 byte header
	file.seek(80)

	var tri_count = file.get_32()
	if tri_count == 0 or tri_count > 10000000:  # Sanity check
		push_error("Invalid triangle count in STL: %d" % tri_count)
		return null

	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()

	vertices.resize(tri_count * 3)
	normals.resize(tri_count * 3)

	for i in range(tri_count):
		# Read normal (3 floats)
		var nx = file.get_float()
		var ny = file.get_float()
		var nz = file.get_float()
		var normal = Vector3(nx, ny, nz)

		# Read 3 vertices
		for v in range(3):
			var x = file.get_float()
			var y = file.get_float()
			var z = file.get_float()
			vertices[i * 3 + v] = Vector3(x, y, z)
			normals[i * 3 + v] = normal

		# Skip attribute byte count (2 bytes)
		file.get_16()

	# Create mesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return mesh


## Parse ASCII STL file
func _parse_ascii_stl(file: FileAccess) -> ArrayMesh:
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var current_normal = Vector3.UP

	var content = file.get_as_text()
	var lines = content.split("\n")

	for line in lines:
		line = line.strip_edges().to_lower()

		if line.begins_with("facet normal"):
			var parts = line.split(" ")
			if parts.size() >= 5:
				current_normal = Vector3(
					float(parts[2]),
					float(parts[3]),
					float(parts[4])
				)

		elif line.begins_with("vertex"):
			var parts = line.split(" ")
			if parts.size() >= 4:
				var vertex = Vector3(
					float(parts[1]),
					float(parts[2]),
					float(parts[3])
				)
				vertices.append(vertex)
				normals.append(current_normal)

	if vertices.size() == 0:
		return null

	# Create mesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return mesh


## Load an OBJ model (Wavefront format) with optional texture support
## texture_path: Optional path to a texture file (PNG, JPG, etc.)
## add_base: If true, adds a 32mm wargaming base under the model
func _load_obj_model(file_path: String, texture_path: String = "", add_base: bool = true) -> Node3D:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open OBJ file: %s" % file_path)
		return null

	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var uvs: Array[Vector2] = []  # Texture coordinates
	var mesh_vertices = PackedVector3Array()
	var mesh_normals = PackedVector3Array()
	var mesh_uvs = PackedVector2Array()  # UV array for mesh

	var content = file.get_as_text()
	file.close()

	var lines = content.split("\n")

	for line in lines:
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue

		var parts = line.split(" ", false)  # Split by space, skip empty
		if parts.size() < 2:
			continue

		match parts[0]:
			"v":  # Vertex position
				if parts.size() >= 4:
					vertices.append(Vector3(
						float(parts[1]),
						float(parts[2]),
						float(parts[3])
					))
			"vt":  # Texture coordinate (UV)
				if parts.size() >= 3:
					uvs.append(Vector2(
						float(parts[1]),
						1.0 - float(parts[2])  # Flip V coordinate (OBJ uses bottom-left origin)
					))
			"vn":  # Vertex normal
				if parts.size() >= 4:
					normals.append(Vector3(
						float(parts[1]),
						float(parts[2]),
						float(parts[3])
					))
			"f":  # Face
				var face_verts: Array[int] = []
				var face_uvs: Array[int] = []
				var face_normals: Array[int] = []

				for i in range(1, parts.size()):
					var indices = parts[i].split("/")
					# OBJ indices are 1-based
					var v_idx = int(indices[0]) - 1
					face_verts.append(v_idx)

					# UV index (v/vt/vn format)
					if indices.size() >= 2 and not indices[1].is_empty():
						var uv_idx = int(indices[1]) - 1
						face_uvs.append(uv_idx)
					else:
						face_uvs.append(-1)

					# Normal index (v/vt/vn format)
					if indices.size() >= 3 and not indices[2].is_empty():
						var n_idx = int(indices[2]) - 1
						face_normals.append(n_idx)
					else:
						face_normals.append(-1)

				# Triangulate face (fan triangulation)
				for i in range(1, face_verts.size() - 1):
					var tri_indices = [0, i, i + 1]
					for ti in tri_indices:
						var v_idx = face_verts[ti]
						if v_idx >= 0 and v_idx < vertices.size():
							mesh_vertices.append(vertices[v_idx])

							# Use UV if available
							var uv_idx = face_uvs[ti] if ti < face_uvs.size() else -1
							if uv_idx >= 0 and uv_idx < uvs.size():
								mesh_uvs.append(uvs[uv_idx])
							else:
								mesh_uvs.append(Vector2.ZERO)

							# Use normal if available
							var n_idx = face_normals[ti] if ti < face_normals.size() else -1
							if n_idx >= 0 and n_idx < normals.size():
								mesh_normals.append(normals[n_idx])
							else:
								mesh_normals.append(Vector3.UP)

	if mesh_vertices.size() == 0:
		push_error("No geometry found in OBJ: %s" % file_path)
		return null

	# Check if we have valid normals from the OBJ file
	# The shader handles backface lighting, so we just need normals to exist
	var has_valid_normals = false
	for i in range(mesh_normals.size()):
		if mesh_normals[i].length_squared() > 0.0001:
			has_valid_normals = true
			break

	if not has_valid_normals:
		# No valid normals in file, calculate from geometry
		mesh_normals = _calculate_smooth_normals(mesh_vertices)

	# Create mesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh_vertices
	arrays[Mesh.ARRAY_NORMAL] = mesh_normals
	if mesh_uvs.size() == mesh_vertices.size():
		arrays[Mesh.ARRAY_TEX_UV] = mesh_uvs

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Create mesh instance
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh

	# Create shader material with two-sided lighting
	# This flips normals for backfaces so both sides are lit correctly
	# (TTS/Unity does this automatically, Godot requires a shader)
	var shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool use_texture = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;

void fragment() {
	// Ensure normal always faces the camera for proper lighting
	// VIEW points FROM camera TO fragment in Godot
	// So if dot(NORMAL, VIEW) > 0, they point same direction = normal faces away
	// In that case, flip the normal to face the camera
	if (dot(NORMAL, VIEW) > 0.0) {
		NORMAL = -NORMAL;
	}

	if (use_texture) {
		ALBEDO = texture(albedo_texture, UV).rgb * albedo_color.rgb;
	} else {
		ALBEDO = albedo_color.rgb;
	}
	ROUGHNESS = roughness;
}
"""

	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("albedo_color", Color(0.7, 0.7, 0.7))
	material.set_shader_parameter("roughness", 0.9)
	material.set_shader_parameter("use_texture", false)

	# Load texture if provided
	if not texture_path.is_empty():
		var texture = _load_texture(texture_path)
		if texture:
			material.set_shader_parameter("albedo_texture", texture)
			material.set_shader_parameter("albedo_color", Color.WHITE)
			material.set_shader_parameter("use_texture", true)

	mesh_instance.material_override = material

	# Wrap in Node3D
	var root = Node3D.new()
	root.name = "OBJ_Model"

	if add_base:
		# Add wargaming base
		var base = _create_miniature_base()
		root.add_child(base)

		# Position mesh on top of base
		var mesh_aabb = mesh.get_aabb()
		var base_top = 0.003
		mesh_instance.position.y = base_top - mesh_aabb.position.y
	else:
		# No base - just use mesh as-is
		mesh_instance.position.y = 0

	root.add_child(mesh_instance)

	# Enable shadow casting for all meshes
	_enable_shadows_recursive(root)

	return root


## Load a texture from file path (supports PNG, JPG, WEBP)
## Detects format from file content (magic bytes), not extension
func _load_texture(texture_path: String) -> ImageTexture:
	if not FileAccess.file_exists(texture_path):
		push_warning("Texture file not found: %s" % texture_path)
		return null

	# Read file content
	var file = FileAccess.open(texture_path, FileAccess.READ)
	if not file:
		push_warning("Failed to open texture file: %s" % texture_path)
		return null

	var buffer = file.get_buffer(file.get_length())
	file.close()

	if buffer.size() < 12:
		push_warning("Texture file too small: %s" % texture_path)
		return null

	# Detect format from magic bytes (file signature)
	var image = Image.new()
	var error: Error = ERR_FILE_UNRECOGNIZED

	# PNG: 89 50 4E 47 0D 0A 1A 0A (first 8 bytes)
	if buffer[0] == 0x89 and buffer[1] == 0x50 and buffer[2] == 0x4E and buffer[3] == 0x47:
		error = image.load_png_from_buffer(buffer)
	# JPEG: FF D8 FF (first 3 bytes)
	elif buffer[0] == 0xFF and buffer[1] == 0xD8 and buffer[2] == 0xFF:
		error = image.load_jpg_from_buffer(buffer)
	# WebP: RIFF....WEBP (bytes 0-3 = RIFF, bytes 8-11 = WEBP)
	elif buffer[0] == 0x52 and buffer[1] == 0x49 and buffer[2] == 0x46 and buffer[3] == 0x46:
		if buffer.size() >= 12 and buffer[8] == 0x57 and buffer[9] == 0x45 and buffer[10] == 0x42 and buffer[11] == 0x50:
			error = image.load_webp_from_buffer(buffer)
	# BMP: 42 4D (BM)
	elif buffer[0] == 0x42 and buffer[1] == 0x4D:
		error = image.load_bmp_from_buffer(buffer)
	# TGA: Try as fallback (no reliable magic bytes)
	else:
		# Try TGA as last resort
		error = image.load_tga_from_buffer(buffer)

	if error != OK:
		# Log the magic bytes for debugging
		var magic = "%02X %02X %02X %02X" % [buffer[0], buffer[1], buffer[2], buffer[3]]
		push_warning("Failed to load texture: %s (error %d, magic: %s)" % [texture_path, error, magic])
		return null

	# Generate mipmaps for better rendering at distance
	image.generate_mipmaps()

	var texture = ImageTexture.create_from_image(image)
	return texture


## Enable shadow casting for all MeshInstance3D nodes recursively
func _enable_shadows_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	for child in node.get_children():
		_enable_shadows_recursive(child)


## Calculate smooth normals for a mesh (vertex normals averaged from face normals)
## Uses centroid-based detection to ensure normals point outward
func _calculate_smooth_normals(vertices: PackedVector3Array) -> PackedVector3Array:
	var normals = PackedVector3Array()
	normals.resize(vertices.size())

	# Initialize all normals to zero
	for i in range(normals.size()):
		normals[i] = Vector3.ZERO

	@warning_ignore("integer_division")
	var tri_count = vertices.size() / 3

	if tri_count == 0:
		return normals

	# Calculate mesh centroid (average of all vertices)
	var centroid = Vector3.ZERO
	for i in range(vertices.size()):
		centroid += vertices[i]
	centroid /= vertices.size()

	# Calculate face normals, ensuring they point outward from centroid
	var flipped_count = 0

	for i in range(tri_count):
		var idx0 = i * 3
		var idx1 = i * 3 + 1
		var idx2 = i * 3 + 2

		var v0 = vertices[idx0]
		var v1 = vertices[idx1]
		var v2 = vertices[idx2]

		# Calculate face center
		var face_center = (v0 + v1 + v2) / 3.0

		# Calculate face normal using cross product
		var edge1 = v1 - v0
		var edge2 = v2 - v0
		var face_normal = edge1.cross(edge2).normalized()

		# Check if normal points outward (away from centroid)
		# The vector from centroid to face center should align with normal
		var outward_dir = (face_center - centroid).normalized()
		if face_normal.dot(outward_dir) < 0:
			# Normal is pointing inward, flip it
			face_normal = -face_normal
			flipped_count += 1

		# Add face normal to all three vertices of this triangle
		normals[idx0] += face_normal
		normals[idx1] += face_normal
		normals[idx2] += face_normal

	# Normalize all vertex normals
	for i in range(normals.size()):
		if normals[i].length_squared() > 0.0001:
			normals[i] = normals[i].normalized()
		else:
			normals[i] = Vector3.UP  # Fallback for degenerate cases

	return normals


## Calculate AABB for a node and all its children
func _calculate_aabb(node: Node3D) -> AABB:
	var aabb = AABB()
	var found_mesh = false

	for child in node.get_children():
		if child is MeshInstance3D:
			# Get local AABB and transform by child's position/scale
			var mesh_aabb = child.get_aabb()
			# Apply child's transform to the AABB
			var transformed_aabb = AABB(
				mesh_aabb.position * child.scale + child.position,
				mesh_aabb.size * child.scale
			)
			if not found_mesh:
				aabb = transformed_aabb
				found_mesh = true
			else:
				aabb = aabb.merge(transformed_aabb)

		if child is Node3D:
			var child_aabb = _calculate_aabb(child)
			if child_aabb.size.length() > 0:
				# Transform child AABB by child's position/scale
				var transformed_aabb = AABB(
					child_aabb.position * child.scale + child.position,
					child_aabb.size * child.scale
				)
				if not found_mesh:
					aabb = transformed_aabb
					found_mesh = true
				else:
					aabb = aabb.merge(transformed_aabb)

	# Default if nothing found
	if not found_mesh:
		aabb = AABB(Vector3(-0.025, 0, -0.025), Vector3(0.05, 0.05, 0.05))

	return aabb


func _create_rock_mesh() -> Mesh:
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.4, 0.25, 0.35)  # Rock dimensions
	return mesh


func _create_building_mesh() -> Mesh:
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.5, 0.6, 0.5)  # Building dimensions
	return mesh


func _create_tree_mesh() -> Mesh:
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.2  # Tree crown radius
	mesh.bottom_radius = 0.08  # Tree trunk radius
	mesh.height = 0.6  # Tree height
	return mesh


## Clear all objects from the table
## If broadcast is true and multiplayer is active, syncs to other clients
func clear_all_objects(broadcast: bool = true) -> void:
	# Broadcast to other clients if in multiplayer (before clearing locally)
	if broadcast and _network_manager and _network_manager.is_multiplayer_active():
		_network_manager.broadcast_clear()

	for child in get_children():
		child.queue_free()

	_selected_objects.clear()
	_object_counter = 0

	# Clear OPR army state and unit boundary outlines too. The boundary
	# visualizer renders from OPRArmyManager.game_units, which is otherwise never
	# cleared - without this, a cleared (or reloaded) table keeps stale unit
	# outlines lingering on the surface.
	var army_manager = get_node_or_null("/root/Main/OPRArmyManager")
	if army_manager and army_manager.has_method("clear_all"):
		army_manager.clear_all()
	var boundary_visualizer = get_node_or_null("/root/Main/UnitBoundaryVisualizer")
	if boundary_visualizer and boundary_visualizer.has_method("clear_all"):
		boundary_visualizer.clear_all()


## Resets all units to their import positions and clears all markers/status
## Unlike clear_all_objects(), this preserves the models
func sort_table(broadcast: bool = true) -> void:
	# Get reference to OPR army manager via Main. Use the absolute path (matches
	# how this manager resolves its other siblings) instead of a recursive
	# find_child() string search.
	var main = get_node_or_null("/root/Main")
	if not main:
		push_error("Sort Table: Could not find Main node")
		return

	var army_manager = main.get("opr_army_manager")
	if not army_manager:
		push_error("Sort Table: No OPR Army Manager found")
		return

	# Get all game units
	var all_units: Array = []
	if army_manager.has_method("get_all_game_units"):
		all_units = army_manager.get_all_game_units()
	elif "game_units" in army_manager:
		all_units = army_manager.game_units.values()

	if all_units.is_empty():
		push_warning("Sort Table: No units to reset")
		return

	# Reset status/wounds/markers/visibility, then animate models back to their
	# import positions so the movement can be followed on the table.
	for game_unit in all_units:
		if game_unit and game_unit.has_method("reset_to_import_state"):
			game_unit.reset_to_import_state()
			_animate_unit_to_import(game_unit)

	# Clear selection
	_deselect_all()

	# Update visual markers via radial menu controller
	var radial_controller = main.get("radial_menu_controller")
	if radial_controller:
		for game_unit in all_units:
			if radial_controller.has_method("initialize_status_markers_for_unit"):
				radial_controller.initialize_status_markers_for_unit(game_unit)
			if radial_controller.has_method("initialize_caster_marker_for_unit"):
				radial_controller.initialize_caster_marker_for_unit(game_unit)

	print("Sort Table: Reset %d units to import positions" % all_units.size())

	# Mirror the reset to remote peers (skipped when WE are applying a remote sort, to avoid an
	# echo loop). Each peer re-runs the same reset to its synced import_positions.
	if broadcast and _network_manager and _network_manager.is_multiplayer_active():
		_network_manager.broadcast_sort_table()


## Animates every model of a unit from its current spot back to its import
## position. Tweens are created in the same frame so all models start moving
## simultaneously; per-model duration jitter gives the swarm a busy look.
func _animate_unit_to_import(game_unit) -> void:
	for model in game_unit.models:
		var node: Node3D = model.node
		if not node or not is_instance_valid(node):
			continue

		var target: Vector3 = model.import_position
		target.y = SORT_ANIM_RESTING_Y

		var duration: float = SORT_ANIM_DURATION + randf_range(
			-SORT_ANIM_DURATION_JITTER, SORT_ANIM_DURATION_JITTER
		)

		var move_tween: Tween = create_tween()
		move_tween.set_ease(Tween.EASE_IN_OUT)
		move_tween.set_trans(Tween.TRANS_CUBIC)
		move_tween.tween_property(node, "global_position", target, duration)
		# Snap to the exact target to avoid floating-point drift.
		move_tween.tween_callback(func() -> void: node.global_position = target)

		if model.import_rotation != Vector3.ZERO:
			var rot_tween: Tween = create_tween()
			rot_tween.set_ease(Tween.EASE_IN_OUT)
			rot_tween.set_trans(Tween.TRANS_CUBIC)
			rot_tween.tween_property(node, "rotation", model.import_rotation, duration)


## ============================================================================
## TTS Download Manager (shared by terrain spawn)
## ============================================================================

## Lazily-created download manager for TTS asset URLs (mesh/texture), shared by
## spawn_tts_terrain. The full TTS save-file import path that also used it was
## removed (cleanup wave 13).
var _download_manager: TTSDownloadManager = null


## Get or create the download manager.
func _get_download_manager() -> TTSDownloadManager:
	if _download_manager == null:
		_download_manager = TTSDownloadManager.new()
		add_child(_download_manager)
	return _download_manager


## ============================================================================
## Arrangement Functions (TTS-style formations)
## ============================================================================

## Get table position from screen position (for input handling)
## @param screen_pos: Screen coordinates to project
## @return: World position on table, or Vector3.INF if not intersecting
func _get_table_position_at_screen(screen_pos: Vector2) -> Vector3:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return Vector3.INF

	var from = camera.project_ray_origin(screen_pos)
	var dir = camera.project_ray_normal(screen_pos)

	# Intersect with table plane (y=0)
	var table_plane = Plane(Vector3.UP, 0)
	var intersection = table_plane.intersects_ray(from, dir)

	if intersection:
		return Vector3(intersection.x, 0, intersection.z)

	return Vector3.INF


## Get cursor position on the table from current mouse position
func get_cursor_table_position() -> Vector3:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return Vector3.ZERO

	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)

	# Intersect with table plane (y=0)
	var table_plane = Plane(Vector3.UP, 0)
	var intersection = table_plane.intersects_ray(from, dir)

	if intersection:
		return Vector3(intersection.x, 0, intersection.z)

	return Vector3.ZERO


## Base footprint of an object as Vector2(x_extent, z_extent) in meters. Oval
## bases use their real width (X) and depth (Z); round bases use the diameter on
## both axes. (The keys base_width_mm/base_depth_mm/base_is_oval are the ones the
## OPR importer actually sets - see EquipmentDistributor.create_from_opr_unit.)
func _base_footprint(obj: Node3D) -> Vector2:
	var game_unit = UnitUtils.get_game_unit(obj)
	if game_unit and game_unit.unit_properties:
		# Use the model's ACTUAL base: a per-model Tough upgrade enlarges it (the mesh stays
		# natural-sized). The per-model Tough lives on the model_instance.
		var model_tough := 0
		var mi = UnitUtils.get_model_instance(obj)
		if mi and mi.properties:
			model_tough = int(mi.properties.get("tough", 0))
		var props: Dictionary = OPRArmyManager.effective_base_props(game_unit.unit_properties, model_tough)
		if props.get("base_is_oval", false):
			return Vector2(float(props.get("base_width_mm", 32)), float(props.get("base_depth_mm", 32))) * 0.001
		var diameter := float(props.get("base_size_round", 32)) * 0.001
		return Vector2(diameter, diameter)
	return Vector2(0.032, 0.032)


## Per-axis arrangement spacing (center-to-center) as Vector2(x, z). Each axis is
## the largest base extent on that axis + a small gap (no overlap), capped so even
## the smallest base stays within ~1" of its neighbour on that axis (OPR coherency)
## - so a big joined-Hero base can't push the troops out of coherency, and oval
## bases get tight spacing on their short axis instead of their long one.
func _arrange_spacing(objects: Array) -> Vector2:
	var max_x := 0.0
	var min_x := INF
	var max_z := 0.0
	var min_z := INF
	for obj in objects:
		if not is_instance_valid(obj):
			continue
		var footprint := _base_footprint(obj)
		max_x = maxf(max_x, footprint.x)
		min_x = minf(min_x, footprint.x)
		# footprint.y holds the Z-axis (depth) extent.
		max_z = maxf(max_z, footprint.y)
		min_z = minf(min_z, footprint.y)

	if min_x == INF:
		return Vector2(0.04, 0.04)

	var edge_gap := 0.008  # 8mm constant gap between base edges
	return Vector2(
		minf(max_x + edge_gap, min_x + ARRANGE_COHERENCY_GAP),
		minf(max_z + edge_gap, min_z + ARRANGE_COHERENCY_GAP)
	)


## Returns the selected objects that are still live (not deleted/hidden), so
## arranging a unit after casualties leaves no gaps.
func _live_objects(objs: Array) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for obj in objs:
		if is_instance_valid(obj) and not obj.get_meta("deleted", false):
			result.append(obj)
	return result


## Arrange selected objects in N rows, centred on the unit's current centre (keys 1-9)
func arrange_selected_in_rows(num_rows: int) -> void:
	var objects: Array[Node3D] = _movable_selection()  # own-only in MP; all live in single-player
	if objects.size() < 2:
		return

	var count = objects.size()
	var cols = ceili(float(count) / num_rows)

	# Per-axis spacing, capped so neighbours stay within ~1" coherency on each
	# axis (handles oval bases and a big joined-Hero base correctly).
	var spacing := _arrange_spacing(objects)

	# Anchor on the unit's CURRENT centre (not the cursor) and centre the whole block on it, so
	# re-forming tidies the unit in place instead of dropping it off to one side (playtest feedback).
	var centre := _selection_centroid(objects)
	var start_x = centre.x - (cols - 1) * spacing.x * 0.5
	var start_z = centre.z - (num_rows - 1) * spacing.y * 0.5

	var idx = 0
	for row in range(num_rows):
		for col in range(cols):
			if idx >= count:
				break
			var obj = objects[idx]
			if is_instance_valid(obj):
				obj.global_position = Vector3(
					start_x + col * spacing.x,
					obj.global_position.y,
					start_z + row * spacing.y
				)
			idx += 1

	_broadcast_arrange_positions(objects)



## Arrange selected objects in an arrow/wedge, centred on the unit's current centre (Shift+A)
func arrange_selected_arrow() -> void:
	var objects: Array[Node3D] = _movable_selection()  # own-only in MP; all live in single-player
	if objects.size() < 2:
		return

	var count = objects.size()

	# Within-row spacing on X, capped for coherency (see arrange_selected_in_rows).
	var col_spacing := _arrange_spacing(objects).x
	# Triangular lattice: rows are offset by col_spacing/2, so a row height of
	# col_spacing*sqrt(3)/2 puts EVERY nearest neighbour (incl. the diagonal
	# apex->row links) at exactly col_spacing apart - the whole wedge stays coherent.
	var row_spacing := col_spacing * sqrt(3.0) / 2.0

	# Centre the wedge on the unit's CURRENT centre (not the cursor): count the rows the triangular
	# layout needs, then offset Z so the wedge is centred on the unit instead of growing away from it.
	var centre := _selection_centroid(objects)
	var total_rows := 0
	var capacity := 0
	while capacity < count:
		total_rows += 1
		capacity += total_rows
	var z_offset := (total_rows - 1) * row_spacing * 0.5

	# Arrow formation: 1 in front, then 2, then 3, etc.
	var row = 0
	var idx = 0
	var row_count = 1

	while idx < count:
		# Position objects in this row, centred on the unit centre X
		var row_start_x = centre.x - (row_count - 1) * col_spacing / 2

		for col in range(row_count):
			if idx >= count:
				break
			var obj = objects[idx]
			if is_instance_valid(obj):
				obj.global_position = Vector3(
					row_start_x + col * col_spacing,
					obj.global_position.y,
					centre.z - z_offset + row * row_spacing
				)
			idx += 1

		row += 1
		row_count += 1

	_broadcast_arrange_positions(objects)


## Average (X,Z) of the selection's current positions — the anchor the arrange formations centre on.
func _selection_centroid(objects: Array[Node3D]) -> Vector3:
	var sum := Vector3.ZERO
	for obj in objects:
		sum += obj.global_position
	return sum / float(objects.size())


## Broadcast the post-arrange positions of every networked object in one batch,
## so a formation snap (rows / arrow) mirrors to remote peers like a drag does.
func _broadcast_arrange_positions(objects: Array[Node3D]) -> void:
	if not _network_manager or not _network_manager.is_multiplayer_active():
		return
	var batch: Array = []
	for obj in objects:
		if is_instance_valid(obj) and obj.has_meta("network_id"):
			var p: Vector3 = obj.global_position
			batch.append_array([obj.get_meta("network_id"), p.x, p.y, p.z])
	if batch.size() > 0:
		_network_manager.broadcast_move_batch(batch)


## Copy selected objects to clipboard (Ctrl+C)
func copy_to_clipboard() -> void:
	if _selected_objects.is_empty():
		return

	_clipboard.clear()
	for obj in _selected_objects:
		if is_instance_valid(obj):
			_clipboard.append(obj)


## Paste objects from clipboard at cursor position (Ctrl+V)
func paste_from_clipboard(cursor_pos: Vector3) -> void:
	if _clipboard.is_empty():
		push_warning("Clipboard is empty")
		return

	# Calculate center of clipboard objects
	var clipboard_center = Vector3.ZERO
	var valid_count = 0
	for obj in _clipboard:
		if is_instance_valid(obj):
			clipboard_center += obj.global_position
			valid_count += 1

	if valid_count == 0:
		_clipboard.clear()
		return

	clipboard_center /= valid_count

	# Paste at cursor position, maintaining relative positions
	var pasted_count = 0
	_deselect_all()  # Deselect current selection

	for obj in _clipboard:
		if not is_instance_valid(obj):
			continue

		var copy: Node3D = null

		# Check if it's a TTS import (has mesh URL meta)
		if obj.has_meta("tts_mesh_url"):
			copy = _duplicate_tts_object(obj)
		else:
			# Generic duplication for other objects. Assign a FRESH unique
			# network_id (duplicate() inherits the source's, which would collide
			# in multiplayer); +50000 keeps pasted copies clear of the per-type
			# id offsets (miniature 0, terrain 10000, custom 20000, tts 30000,
			# generated terrain 40000).
			copy = obj.duplicate()
			_object_counter += 1
			copy.name = obj.name.split("_")[0] + "_%d" % _object_counter
			copy.set_meta("network_id", _object_counter + 50000)

		if copy:
			add_child(copy)
			# Position relative to cursor (maintaining formation)
			var offset = obj.global_position - clipboard_center
			copy.global_position = cursor_pos + offset
			copy.global_position.y = obj.global_position.y  # Keep original height
			# Select the pasted object
			_add_to_selection(copy)
			_broadcast_pasted_copy(copy)
			pasted_count += 1


## Mirror a pasted/duplicated object to remote peers by serializing it and
## letting SaveManager._deserialize_object reconstruct it with the same
## network_id. OPR army models are skipped (they are re-imported, not pasted,
## and depend on per-load game-unit state that peers do not have live).
func _broadcast_pasted_copy(copy: Node3D) -> void:
	if not _network_manager or not _network_manager.is_multiplayer_active():
		return
	if copy.is_in_group("opr_unit"):
		return
	var main = get_node_or_null("/root/Main")
	if main == null or main.save_manager == null:
		return
	var obj_data: Dictionary = main.save_manager._serialize_object(copy)
	if obj_data.is_empty():
		return
	_network_manager.broadcast_object_data_spawn(obj_data)


## Duplicate a TTS-imported object
func _duplicate_tts_object(original: Node3D) -> Node3D:
	# Deep duplicate the object
	var copy = original.duplicate()

	# Assign new unique ID
	_object_counter += 1
	copy.name = original.name.split("_")[0] + "_%d" % _object_counter
	copy.set_meta("network_id", _object_counter + 30000)

	# Make sure it's in the right groups
	if not copy.is_in_group("selectable"):
		copy.add_to_group("selectable")
	if not copy.is_in_group("tts_import"):
		copy.add_to_group("tts_import")

	return copy


## ============================================================================
## Terrain System
## ============================================================================

## Spawn terrain from TTS URLs at given spawn position
## Returns the spawned terrain object
func spawn_tts_terrain(mesh_url: String, diffuse_url: String, tts_scale: Vector3, spawn_pos: Vector3, terrain_name: String = "Terrain") -> Node3D:
	if mesh_url.is_empty():
		push_error("spawn_tts_terrain: No mesh URL provided")
		return null

	# Get or create download manager
	var dm = _get_download_manager()

	# Check if already cached
	var mesh_path = dm.find_cached_file(mesh_url, true)
	var texture_path = ""

	if mesh_path.is_empty():
		# Need to download
		dm.queue_download(mesh_url, true)
		if not diffuse_url.is_empty():
			dm.queue_download(diffuse_url, false)

		# Wait for downloads
		dm.start_downloads()
		await dm.all_downloads_completed

		mesh_path = dm.find_cached_file(mesh_url, true)

	if not diffuse_url.is_empty():
		texture_path = dm.find_cached_file(diffuse_url, false)

	if mesh_path.is_empty():
		push_error("spawn_tts_terrain: Failed to download mesh")
		return null

	# Load the model (no base for terrain)
	var model_scene = _load_obj_model(mesh_path, texture_path, false)
	if not model_scene:
		push_error("spawn_tts_terrain: Failed to load mesh")
		return null

	# Apply TTS scale (inches to meters, plus terrain's own scale)
	var scale_factor = 0.0254  # TTS units to meters
	var final_scale = tts_scale * scale_factor
	model_scene.scale = final_scale

	# Calculate bounds for collision BEFORE scaling was applied (raw mesh bounds)
	# Then apply scale to the AABB
	var raw_aabb = _calculate_aabb(model_scene)
	# The AABB from _calculate_aabb doesn't include parent scale, so we need to apply it
	var mesh_aabb = AABB(
		raw_aabb.position * final_scale,
		raw_aabb.size * final_scale
	)

	# Ensure minimum collision size for clickability
	var min_size = 0.05  # 5cm minimum
	mesh_aabb.size.x = max(mesh_aabb.size.x, min_size)
	mesh_aabb.size.y = max(mesh_aabb.size.y, min_size)
	mesh_aabb.size.z = max(mesh_aabb.size.z, min_size)

	# Create wrapper
	_object_counter += 1
	var wrapper = StaticBody3D.new()
	wrapper.name = "Terrain_%s_%d" % [terrain_name.replace(" ", "_"), _object_counter]
	wrapper.set_meta("network_id", _object_counter + 40000)  # Terrain IDs start at 40000
	wrapper.set_meta("tts_mesh_url", mesh_url)
	wrapper.set_meta("tts_diffuse_url", diffuse_url)
	wrapper.set_meta("terrain_name", terrain_name)
	wrapper.add_to_group("selectable")
	wrapper.add_to_group("tts_import")
	wrapper.add_to_group("terrain_piece")

	# Add model
	wrapper.add_child(model_scene)

	# Add collision
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = mesh_aabb.size
	collision.shape = shape
	collision.position = mesh_aabb.position + mesh_aabb.size / 2
	wrapper.add_child(collision)

	# Enable shadow casting for terrain
	_enable_shadows_recursive(wrapper)

	# Add script for selection
	wrapper.set_script(preload("res://scripts/selectable_object.gd"))

	# Add to scene
	add_child(wrapper)
	wrapper.global_position = spawn_pos

	return wrapper


## ============================================================================
## Lock/Unlock System
## ============================================================================

## Toggle lock state of selected objects
func toggle_lock_selected() -> void:
	if _selected_objects.is_empty():
		return

	# Check if any are unlocked - if so, lock all. Otherwise unlock all.
	var any_unlocked = false
	for obj in _selected_objects:
		if is_instance_valid(obj) and not obj.get_meta("locked", false):
			any_unlocked = true
			break

	var new_state = any_unlocked  # Lock if any unlocked, unlock if all locked

	for obj in _selected_objects:
		if is_instance_valid(obj):
			_set_object_locked(obj, new_state)

	# Deselect if locking
	if new_state:
		_deselect_all()


## Set lock state of a single object
func _set_object_locked(obj: Node3D, locked: bool) -> void:
	obj.set_meta("locked", locked)

	# Visual feedback - change material or add indicator
	if locked:
		obj.add_to_group("locked")
		# Dim the object slightly to indicate locked state
		_set_object_dimmed(obj, true)
	else:
		obj.remove_from_group("locked")
		_set_object_dimmed(obj, false)


## Check if object is locked
func is_object_locked(obj: Node3D) -> bool:
	return obj.get_meta("locked", false)


## Apply dimming effect to show locked state
func _set_object_dimmed(obj: Node3D, dimmed: bool) -> void:
	# Find all MeshInstance3D children and adjust their material
	for child in obj.get_children():
		if child is MeshInstance3D:
			var mesh_inst = child as MeshInstance3D
			if mesh_inst.material_override:
				var mat = mesh_inst.material_override as StandardMaterial3D
				if mat:
					if dimmed:
						mat.albedo_color = mat.albedo_color.darkened(0.3)
					else:
						mat.albedo_color = mat.albedo_color.lightened(0.3)
		# Recurse into children
		if child.get_child_count() > 0:
			_set_object_dimmed(child, dimmed)


## ============================================================================
## Group Rotation System (Shift+R)
## ============================================================================

## Rotate selected objects as a group around the first object (Shift+R)
## Called continuously while Shift+R is held, so no print statements
func rotate_selected_group(angle_degrees: float) -> void:
	# Only OWN (or unowned) objects rotate; another player's selected models stay put.
	var movable := _movable_selection()
	if movable.size() < 2:
		# Single object or no movable selection - just rotate the object itself
		if movable.size() == 1:
			var obj = movable[0]
			if is_instance_valid(obj):
				obj.rotate_y(deg_to_rad(angle_degrees))
		return

	# First movable object is the pivot (_movable_selection only returns valid nodes).
	var pivot_obj: Node3D = movable[0]
	var pivot_pos = pivot_obj.global_position
	var angle_rad = deg_to_rad(angle_degrees)

	# Rotate the movable objects around the pivot
	for obj in movable:
		if not is_instance_valid(obj):
			continue

		if obj == pivot_obj:
			# Pivot object just rotates in place
			obj.rotate_y(angle_rad)
		else:
			# Calculate offset from pivot
			var offset = obj.global_position - pivot_pos

			# Rotate offset around Y axis
			var new_offset = Vector3(
				offset.x * cos(angle_rad) - offset.z * sin(angle_rad),
				offset.y,
				offset.x * sin(angle_rad) + offset.z * cos(angle_rad)
			)

			# Apply new position (keep individual model rotation unchanged)
			obj.global_position = pivot_pos + new_offset
