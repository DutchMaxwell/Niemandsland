extends Node
class_name OPRArmyManager
## Manages OPR armies, players, and spawned unit models
## Handles the relationship between game units and their visual representations

signal army_spawned(army: OPRApiClient.OPRArmy, models: Array[Node3D])
## Per-unit spawn progress so a loading bar can advance during the (synchronous) spawn.
signal spawn_progress(done: int, total: int)
## A loose model was parked (dead=true) or un-parked (dead=false). The single choke point for parked-
## model token cleanup/re-derivation — fired on EVERY path (local, MP receive, save/late-join restore)
## so listeners never have to hook each call site (J9).
signal loose_model_dead_changed(node: Node3D, dead: bool)
## Fired when the round counter advances (single seam for the Battle Log — both the local Next-Round path
## via advance_round() and the remote round-advance apply via set_current_round() go through here).
signal round_advanced(round_number: int)
## Pooled regiment wounds changed (single Battle-Log seam — local radial/card edits AND the remote apply
## both run through apply_regiment_wounds). delta is negative when wounds were healed.
signal regiment_wounds_applied(unit_name: String, delta: int, remaining: int, pool: int)

## Player colors for army identification. Values mirror PlayerPalette (the single source shared with
## presence) so a player's army matches their avatar/cursor; use army_color() below to also WRAP past
## slot 4 like presence does — the bare dict falls back to neutral for unknown/0 (bus 036).
const PLAYER_COLORS = {
	1: Color(0.20, 0.40, 0.90),  # Blue
	2: Color(0.90, 0.20, 0.20),  # Red
	3: Color(0.20, 0.80, 0.30),  # Green
	4: Color(0.90, 0.70, 0.10),  # Yellow
}


## The army-base colour for a player slot: the shared wrapping palette for a real slot (>= 1), else the
## caller's neutral (unowned / player 0). This makes army bases agree with presence at slot >= 5, where
## the old bare dict returned grey while avatars/cursors wrapped (bus 036).
static func army_color(player_id: int, neutral: Color = Color.GRAY) -> Color:
	if player_id < 1:
		return neutral
	return PlayerPalette.color_for_slot(player_id)

## Tray positions relative to table (player_id -> side)
## Player 1: left, Player 2: right, Player 3: front, Player 4: back
const TRAY_SIDES = {
	1: "left",
	2: "right",
	3: "front",
	4: "back",
}

const FEET_TO_METERS: float = 0.3048
const INCHES_TO_METERS: float = 0.0254
## Model fit relative to the base (against scale-creep):
## the largest horizontal extent may be at most 125% of the base's long side.
const FOOTPRINT_MAX_RATIO: float = 1.25
## Oval/rectangular bases: fit the model EXACTLY within both base axes (length AND width), no
## overhang — so a wide/square hull (vehicle) sits cleanly on its base instead of scaling to
## base_long x 1.25 and sticking far over the narrow width. Round bases keep FOOTPRINT_MAX_RATIO
## (organic minis may overhang their round base a little).
const OVAL_FOOTPRINT_RATIO: float = 1.0
## Hover height for Flying units, relative to the base long side (40mm base -> ~14mm).
const FLYING_HOVER_RATIO: float = 0.35
## Aircraft (the OPR "Aircraft" rule — NOT the same as Flying) hover much higher, on a tall flight
## stand: a fixed ~20cm above the base for ALL aircraft (1 unit = 1 m, so 0.2).
const AIRCRAFT_HOVER_M: float = 0.2
const TRAY_SIZE_INCHES: float = 32.0  # 32x32 inch tray
const TRAY_MARGIN: float = 0.05  # 5cm gap from table edge
const TRAY_DROP_HEIGHT: float = 0.5  # Start 50cm above table
const TRAY_DROP_DURATION: float = 1.5  # Animation duration in seconds

## Ambush/Scout deployment band on the army tray (representation only — no rules enforcement).
## A staging strip across the tray's near (-Z) third, split Ambush-LEFT / Scout-RIGHT by a thin
## divider, with two flat bird's-eye labels. Units carrying the Scout/Ambush rule auto-place into
## their half on import (see _add_ambush_scout_band / _unit_has_rule).
const BAND_DEPTH_FRACTION: float = 1.0 / 3.0  # near third of the tray reserved for the band
const BAND_TINT_Y: float = 0.004  # local y of the translucent tint quads (above the ~0.01 plate)
const BAND_DIVIDER_Y: float = 0.005  # local y of the centre divider (just above the tints)
const BAND_LABEL_Y: float = 0.006  # local y of the flat labels (clears the divider, no z-fight)
## Above the tray plate + border so the tints never z-flip on orbit (mirrors issue #71 precedent
## in terrain_overlay.gd's DEPLOYMENT_ZONE_RENDER_PRIORITY).
const BAND_RENDER_PRIORITY: int = 2
const BAND_DIVIDER_WIDTH: float = 0.01  # 1cm thick divider, matching the tray border width
const BAND_DIVIDER_HEIGHT: float = 0.02  # matches the tray border height
## Translucent tints — amber for Ambush, cyan for Scout (alpha kept low so models stay readable).
const BAND_AMBUSH_TINT: Color = Color(0.85, 0.55, 0.1, 0.28)  # amber
const BAND_SCOUT_TINT: Color = Color(0.1, 0.6, 0.8, 0.28)  # cyan
## Flat labels sized for bird's-eye readability (each half is ~0.4 m wide).
const BAND_LABEL_FONT_SIZE: int = 48
const BAND_LABEL_PIXEL_SIZE: float = 0.0006  # 50% size — small fixed tag, not a big centred plate
const BAND_LABEL_OUTLINE_SIZE: int = 5
const BAND_LABEL_OUTLINE_COLOR: Color = Color(0.03, 0.03, 0.03, 0.95)

## Physics layers (kept in sync with ObjectManager): miniatures sit on layer 2 so the
## placement raycast (which masks ground-only) rests them on terrain, not on each other.
const GROUND_COLLISION_LAYER: int = 1
const MINIATURE_COLLISION_LAYER: int = 2

## OPR-owned objects (army models + regiment trays) namespace their network_id by owner
## SLOT (player_id) so two players' armies never share the 1..N range and a move/delete by
## id can't hit the wrong army — regardless of import order. _object_counter stays a PURE
## low monotonic counter (the slot prefix is applied only at stamp time), so the
## +10000..+50000 non-OPR id offset bands and the receiver's bare-counter reconciliation
## stay collision-free. STRIDE caps the per-slot counter at <1e6 objects/slot (ample).
const OPR_NET_ID_SLOT_STRIDE: int = 1_000_000

## Reference to the object manager for spawning
var object_manager: Node3D

## Reference to the table for positioning
var table: Node3D

## NetworkManager reference (injected by main.gd) — used for regiment frontage sync.
var network_manager: Node = null

## UndoManager reference (injected by main.gd) — used for frontage-cycle undo.
var undo_manager: Node = null

## RadialMenuController reference (injected by main.gd) — used to drive the shared
## unit-boundary wound token for regiments (same visual language as Fatigued/Shaken).
var radial_menu_controller: Node = null

## Loaded armies by player
var armies: Dictionary = {}  # player_id -> OPRArmy
## Session-wide special-rule name -> description, populated from save/load and from
## the multiplayer state sync. Lets loaded saves and remote-only armies (which carry no
## OPRArmy) still resolve rule descriptions, not just freshly imported armies.
var rule_descriptions: Dictionary = {}
## Faction spell lists by player_id (for guest/loaded units whose OPRArmy carries no spells —
## the host syncs these alongside rule_descriptions). Each value: Array of spell dicts.
var _session_spells: Dictionary = {}

## Mapping from spawned model to unit data
var model_to_unit: Dictionary = {}  # Node3D -> OPRUnit

## Mapping from unit to spawned models
var unit_to_models: Dictionary = {}  # OPRUnit -> Array[Node3D]

## Mapping from OPRUnit to GameUnit wrapper
var unit_to_game_unit: Dictionary = {}  # OPRUnit -> GameUnit

## All GameUnits by unit_id
var game_units: Dictionary = {}  # unit_id (String) -> GameUnit
var regiments: Dictionary = {}  # unit_id (String) -> Regiment (AoF:R movement-tray blocks)

## Whether the regiment front-arc wedges are currently shown (toggled with KEY_F). The
## facing arrows are always visible; only the wedges toggle. Display only.
var _regiment_arcs_visible: bool = false

## Current game round (OPR rounds start at 1). Bookkeeping only - the players
## decide when a round ends; advance_round() does the standard transition.
var current_round: int = 1

## Army trays by player
var army_trays: Dictionary = {}  # player_id -> Node3D

## OPR API Client
var api_client: OPRApiClient

## On-demand model delivery (manifest + CDN cache); see docs/ASSET_DELIVERY.md
var model_library: ModelLibrary

# E6: per-import ctex-vs-legacy delivery tally (reset each spawn_army, logged at its end).
var _ctex_used_count: int = 0
var _legacy_used_reasons: Dictionary = {}
var _variant_used_count: int = 0   # I2: models resolved to a pre-baked loadout variant (`<unit>#<slug>`)
var _variant_missing_count: int = 0   # I2: a slug was derived but no `<unit>#<slug>` key exists → base

## Parsed-model cache: model path -> PackedScene. Runtime glTF models (user://) are
## otherwise re-parsed on every spawn, so a unit of N identical models paid N full
## glTF parses; cached, each distinct model is parsed once and instanced cheaply.
var _scene_cache: Dictionary = {}

func _ready() -> void:
	api_client = OPRApiClient.new()
	add_child(api_client)
	api_client.army_loaded.connect(_on_army_loaded)
	api_client.import_failed.connect(_on_import_failed)

	model_library = ModelLibrary.new()
	model_library.name = "ModelLibrary"
	add_child(model_library)


## Import army from file for a specific player
func import_army_for_player(file_path: String, player_id: int) -> void:
	var army = await api_client.import_from_file(file_path)
	if army:
		army.player_id = player_id
		armies[player_id] = army


## Spawn all units of an army on an army tray beside the table.
## Awaitable: any on-demand models the army needs are downloaded up front.
func spawn_army(army: OPRApiClient.OPRArmy, _start_position: Vector3 = Vector3.ZERO) -> Array[Node3D]:
	if not object_manager:
		push_error("OPRArmyManager: No object_manager set")
		return []

	# Reset the E6 per-import ctex/legacy delivery tally.
	_ctex_used_count = 0
	_legacy_used_reasons = {}
	_variant_used_count = 0
	_variant_missing_count = 0

	# Fetch on-demand models this army needs (no-op when the manifest is empty or
	# everything is cached); the spawn loop below then resolves them locally.
	await _ensure_army_models_cached(army)

	var all_models: Array[Node3D] = []
	var player_color = OPRArmyManager.army_color(army.player_id, Color.GRAY)

	# Create army tray and get spawn position (starts elevated). The tray + its models stay
	# HIDDEN through the build loop so the player never sees the army assemble stepwise — it
	# is revealed all at once for the drop animation once every unit is built (issue #56).
	var tray = _create_army_tray(army.player_id, army.name, player_color)
	tray.visible = false
	var tray_info = _get_tray_position_and_bounds(army.player_id)
	var tray_pos = tray_info.position
	var tray_bounds = tray_info.bounds  # Vector2 (width, depth)
	# The Ambush/Scout band is now built inside _create_army_tray (issue #76).

	# Default spacing values - will be adjusted per unit based on base size
	var unit_gap = 0.08  # 8cm gap between different units
	var row_height = 0.10  # 10cm between rows for clear separation
	var edge_padding = 0.06  # Padding from tray edge

	# Start position on tray (at elevated height)
	var spawn_height = TRAY_DROP_HEIGHT
	var current_pos = Vector3(
		tray_pos.x - tray_bounds.x / 2 + edge_padding,
		spawn_height,
		tray_pos.z - tray_bounds.y / 2 + edge_padding
	)
	var row_max_x = tray_pos.x + tray_bounds.x / 2 - edge_padding

	# Ambush/Scout band lanes (world space): the near (-Z) third of the tray, split at the tray
	# centre into a LEFT (Ambush) and RIGHT (Scout) half-rect. Each is an independent row-packer
	# scoped to its half, reusing the same gap/row_height/wrap math as the main loop. Units carrying
	# the matching rule are relocated here (representation only — Ambush wins if a unit has both).
	# Band sits at the near (+Z) edge — the "bottom" of the tray — so the main packer (which fills from
	# the -Z edge) keeps the top 2/3 and the two areas don't overlap.
	var band_z_max: float = tray_pos.z + tray_bounds.y / 2
	var band_z_min: float = band_z_max - tray_bounds.y * BAND_DEPTH_FRACTION
	var band_left_x_min: float = tray_pos.x - tray_bounds.x / 2 + edge_padding
	var band_left_x_max: float = tray_pos.x - edge_padding  # stop short of the centre divider
	var band_right_x_min: float = tray_pos.x + edge_padding  # start past the centre divider
	var band_right_x_max: float = tray_pos.x + tray_bounds.x / 2 - edge_padding
	var ambush_cursor := Vector3(band_left_x_min, spawn_height, band_z_min + edge_padding)
	var scout_cursor := Vector3(band_right_x_min, spawn_height, band_z_min + edge_padding)

	# Track unit counts for naming duplicates
	var unit_name_counts: Dictionary = {}
	var unit_name_indices: Dictionary = {}

	# First pass: count units by name
	for unit in army.units:
		var base_name = unit.name
		unit_name_counts[base_name] = unit_name_counts.get(base_name, 0) + 1

	# Order units so each joined Hero spawns right after its host unit (adjacent
	# on the tray), instead of as a separate group elsewhere.
	var ordered_units := _order_units_heroes_after_host(army.units)

	# Second pass: spawn with indices
	var total_units := ordered_units.size()
	var spawned_units := 0
	for unit in ordered_units:
		var base_name = unit.name
		var unit_index = unit_name_indices.get(base_name, 0) + 1
		unit_name_indices[base_name] = unit_index

		# Only add index suffix if there are multiple units with same name
		var display_suffix = ""
		if unit_name_counts[base_name] > 1:
			display_suffix = " (%d)" % unit_index

		# Use unit's actual base size for spacing calculations
		var unit_base_diameter = unit.get_base_diameter_meters()
		var edge_gap = BASE_EDGE_GAP_M
		var model_spacing = unit_base_diameter + edge_gap  # diameter + constant edge gap

		# Calculate unit width before spawning to check if we need a new row
		var unit_width = unit_base_diameter + (unit.size - 1) * model_spacing

		# Lane selection: a unit carrying the Ambush/Scout rule is relocated into its band half
		# (Ambush wins if both). Otherwise it stays in the main top-2/3 packer (unchanged).
		var is_ambush := _unit_has_rule(unit, "Ambush") or _unit_rule_describes(unit, "Ambush", army.rule_descriptions)
		var is_scout := _unit_has_rule(unit, "Scout") or _unit_rule_describes(unit, "Scout", army.rule_descriptions)
		var spawn_pos: Vector3
		if is_ambush:
			# LEFT band half — row-packer scoped to the Ambush half-rect.
			if ambush_cursor.x + unit_width > band_left_x_max and ambush_cursor.x > band_left_x_min + 0.01:
				ambush_cursor.x = band_left_x_min
				ambush_cursor.z += row_height
			spawn_pos = ambush_cursor
			ambush_cursor.x += unit_width + unit_gap
		elif is_scout:
			# RIGHT band half — row-packer scoped to the Scout half-rect.
			if scout_cursor.x + unit_width > band_right_x_max and scout_cursor.x > band_right_x_min + 0.01:
				scout_cursor.x = band_right_x_min
				scout_cursor.z += row_height
			spawn_pos = scout_cursor
			scout_cursor.x += unit_width + unit_gap
		else:
			# Main top-2/3 packer (unchanged): wrap to a new row when this unit overflows.
			if current_pos.x + unit_width > row_max_x and current_pos.x > tray_pos.x - tray_bounds.x / 2 + edge_padding + 0.01:
				current_pos.x = tray_pos.x - tray_bounds.x / 2 + edge_padding
				current_pos.z += row_height
			spawn_pos = current_pos

		var unit_models = _spawn_unit(unit, spawn_pos, player_color, display_suffix, army.player_id, army)
		# Keep each model hidden until the whole army is built (revealed for the drop below).
		for model in unit_models:
			model.visible = false
		all_models.append_array(unit_models)

		# Store mappings
		unit_to_models[unit] = unit_models
		for model in unit_models:
			model_to_unit[model] = unit
			model.set_meta("unit_suffix", display_suffix)

		# Move to next position with gap between units. Only the main lane advances current_pos —
		# band units advanced their own (ambush_/scout_) cursor above.
		if not is_ambush and not is_scout:
			current_pos.x += unit_width + unit_gap

		# Report progress and yield so the loading bar animates instead of the whole
		# spawn blocking the main thread in one frozen frame.
		spawned_units += 1
		spawn_progress.emit(spawned_units, total_units)
		await get_tree().process_frame

	# Every unit is built: reveal the whole army at once, then drop it in as one clean
	# deployment (no piecemeal pop-in during the build).
	tray.visible = true
	for model in all_models:
		model.visible = true
	_animate_tray_drop(tray, all_models, spawn_height)

	# Wire up joined Heroes (OPR: a Hero "joined to" a unit belongs to it).
	_attach_joined_heroes(army)

	print("OPRArmyManager: Spawned %d models for army '%s' on tray" % [all_models.size(), army.name])
	army_spawned.emit(army, all_models)

	# Age of Fantasy: Regiments — form each unit into a movement-tray block once the
	# drop animation has settled (deferred so it does not fight the drop tween).
	if army.game_system_abbrev == "aofr":
		_form_regiments_after_drop(army)

	# E6: log which delivery path each model resolved to (Output + session log; QA observability).
	var legacy_total: int = 0
	for r in _legacy_used_reasons:
		legacy_total += int(_legacy_used_reasons[r])
	# I2: variant hits + slug-derived-but-unknown-key fallbacks to base.
	var variant_note: String = ""
	if _variant_used_count > 0 or _variant_missing_count > 0:
		variant_note = "  (%d via loadout variant" % _variant_used_count
		if _variant_missing_count > 0:
			variant_note += ", %d slug→base fallback(s)" % _variant_missing_count
		variant_note += ")"
	print("[Ctex] army '%s': %d model(s) via ctex, %d via legacy fallback%s%s" % [
		army.name, _ctex_used_count, legacy_total,
		("  (reasons: %s)" % str(_legacy_used_reasons)) if legacy_total > 0 else "",
		variant_note])

	return all_models


## Allocate a globally-unique, slot-namespaced network_id for an OPR-owned object.
## Advances the shared low counter (kept pure) and applies slot*STRIDE only here.
func _next_owned_net_id(slot: int) -> int:
	object_manager._object_counter += 1
	return maxi(slot, 1) * OPR_NET_ID_SLOT_STRIDE + object_manager._object_counter


## Form a single Age of Fantasy: Regiments unit into a movement-tray block. Collects
## the unit's live model nodes, creates a RegimentTray under ObjectManager and ranks
## them. Returns the Regiment, or null if the unit is not a regiment / has no models.
## Representation only — no rules are enforced.
func form_regiment(game_unit) -> Regiment:
	if game_unit == null:
		return null
	var props: Dictionary = game_unit.unit_properties
	if not props.get("regiment_mode", false):
		return null
	var members := RegimentTray.collect_members(game_unit)
	var nodes: Array = members.nodes
	var footprints: Array = members.footprints
	if nodes.is_empty():
		return null

	var tray := RegimentTray.new()
	tray.name = "Regiment_%s" % game_unit.unit_id
	tray.set_meta("network_id", _next_owned_net_id(int(game_unit.unit_properties.get("player_id", 1))))
	object_manager.add_child(tray)

	var frontage: int = RegimentFormation.default_frontage(nodes.size())
	tray.form(nodes, footprints, frontage)

	var regiment := Regiment.new(game_unit, tray, frontage)
	tray.set_meta("regiment", regiment)
	game_unit.unit_properties["frontage"] = frontage
	regiments[game_unit.unit_id] = regiment
	# Initialise the pooled-wound counter at full strength (0 wounds taken). The
	# boundary wound token is hidden at full strength; a loaded save restores via
	# restore_regiment -> apply_regiment_wounds.
	regiment.wounds_taken = 0
	game_unit.unit_properties["regiment_wounds_taken"] = 0
	if radial_menu_controller != null and radial_menu_controller.has_method("update_regiment_wound_token"):
		radial_menu_controller.update_regiment_wound_token(game_unit, 0)
	return regiment


## Rebuild a regiment movement-tray block on load: create the tray at the saved
## transform and adopt the unit's already-restored model nodes (no re-layout — the
## exact saved arrangement, including casualty gaps, is preserved).
func restore_regiment(game_unit, frontage: int, pos: Vector3, rot_y: float, wounds_taken: int = 0, saved_net_id: int = -1) -> Regiment:
	if game_unit == null:
		return null
	var tray := RegimentTray.new()
	tray.name = "Regiment_%s" % game_unit.unit_id
	# Keep the tray's serialized MP identity so it survives save/load; only mint a fresh id for older
	# saves that never stored one (bus 036 — trays previously lost identity across load in MP).
	if saved_net_id >= 0:
		tray.set_meta("network_id", saved_net_id)
	else:
		tray.set_meta("network_id", _next_owned_net_id(int(game_unit.unit_properties.get("player_id", 1))))
	object_manager.add_child(tray)
	tray.frontage = maxi(frontage, 1)
	tray.global_position = pos
	tray.rotation.y = rot_y

	var nodes: Array = []
	for m in game_unit.models:
		if m.node and is_instance_valid(m.node):
			nodes.append(m.node)
	tray.adopt_existing(nodes)

	var regiment := Regiment.new(game_unit, tray, tray.frontage)
	tray.set_meta("regiment", regiment)
	game_unit.unit_properties["frontage"] = tray.frontage
	regiments[game_unit.unit_id] = regiment
	# The pooled-wound counter is the source of truth for regiment casualties: apply
	# the saved value to sync model states + re-rank + show the counter label.
	apply_regiment_wounds(regiment, wounds_taken)
	return regiment


## Toggle the 45° arc quadrants on the SELECTED regiment tray(s) only (display only).
## AoF:R v3.5.1 p.5 — the arcs are a per-unit facing aid, so showing them on every
## regiment at once clutters the table; F now toggles only the selection. Returns
## the new visibility state, or -1 if no regiment is selected.
func toggle_selected_regiment_arcs(selected: Array) -> int:
	var any_tray := false
	var visible := false
	for obj in selected:
		if obj is RegimentTray and is_instance_valid(obj):
			any_tray = true
			visible = (obj as RegimentTray).is_arc_visible()
			break
	if not any_tray:
		return -1
	# Toggle: invert the current state and apply to all selected trays.
	var new_state := not visible
	for obj in selected:
		if obj is RegimentTray and is_instance_valid(obj):
			(obj as RegimentTray).set_arc_visible(new_state)
	return 1 if new_state else 0


## Toggle the front-arc wedges on every regiment block (display only). Returns the new
## visibility state; the facing arrows stay visible regardless. Retained for the
## "show all" path (e.g. a future menu action); the F key uses toggle_selected.
func toggle_all_regiment_arcs() -> bool:
	_regiment_arcs_visible = not _regiment_arcs_visible
	set_all_regiment_arcs_visible(_regiment_arcs_visible)
	return _regiment_arcs_visible


## Show or hide the front-arc wedge on every regiment block.
func set_all_regiment_arcs_visible(p_visible: bool) -> void:
	_regiment_arcs_visible = p_visible
	for unit_id in regiments:
		var regiment = regiments[unit_id]
		if regiment and is_instance_valid(regiment.tray):
			regiment.tray.set_arc_visible(p_visible)


## Form every regiment-mode unit of an army into a movement-tray block.
func form_all_regiments(army) -> void:
	for unit in army.units:
		var gu = unit_to_game_unit.get(unit, null)
		if gu:
			form_regiment(gu)


## Cycle the frontage (models per rank) of every selected regiment tray to the next
## value in RegimentFormation.next_frontage's cycle (5 -> 4 -> 3 -> 2 -> 1 -> 5).
## AoF:R v3.5.1 p.6 "Unit Formations" allows a player to reform to any width 1..N.
## Re-ranks the block in place (tray transform is preserved), pushes one undoable
## action per regiment, and broadcasts the new frontage to multiplayer peers.
## `selected` is the ObjectManager's current selection (Array[Node3D]); non-regiment
## entries are ignored. Returns the number of regiments cycled.
func cycle_selected_regiment_frontage(selected: Array) -> int:
	var cycled: int = 0
	var move_peer: int = network_manager.get_my_peer_id() if network_manager else 0
	for obj in selected:
		if not (obj is RegimentTray) or not is_instance_valid(obj):
			continue
		var tray := obj as RegimentTray
		var regiment: Regiment = tray.get_meta("regiment") if tray.has_meta("regiment") else null
		if regiment == null or regiment.game_unit == null:
			continue
		var gu := regiment.game_unit as GameUnit
		var live_count := gu.get_alive_count()
		var from_frontage: int = tray.frontage
		var to_frontage: int = RegimentFormation.next_frontage(from_frontage, live_count)
		if to_frontage == from_frontage:
			continue
		# Capture from-state for undo before mutating.
		var members := RegimentTray.collect_members(gu)
		tray.reform(members.nodes, members.footprints, to_frontage)
		regiment.frontage = to_frontage
		gu.unit_properties["frontage"] = to_frontage
		cycled += 1
		# Undo (one action per regiment — mirrors how rotate captures per-object).
		if undo_manager != null:
			undo_manager.push(UndoManager.FrontageAction.new(tray, gu, from_frontage, to_frontage, network_manager, move_peer))
		# MP broadcast so peers re-rank to the same frontage.
		if network_manager != null and network_manager.is_multiplayer_active():
			network_manager.broadcast_regiment_frontage(gu.unit_id, to_frontage)
	return cycled


## The per-model Tough values (wounds_max) of a regiment's models, in front-to-back
## order (index 0 = front rank). Used by the pooled-wound counter.
func _regiment_toughs(gu: GameUnit) -> Array[int]:
	var toughs: Array[int] = []
	for m in gu.models:
		toughs.append(maxi(m.wounds_max, 1))
	return toughs


## Apply `wounds_taken` to a regiment: recompute each model's alive/wounds state from
## Show/hide a model node on death/revival AND toggle its collision, so a hidden (dead) model is
## no longer hit by measuring, selection, or any other raycast-based action — a dead base left at
## its spot (e.g. under an oil stain) must not be detected. Mirrors the visible + "deleted" meta
## the per-model/regiment/restore paths already set, plus the collision layer. Static so every
## hide site can share it.
static func set_model_alive_state(node: Node3D, alive: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.visible = alive
	node.set_meta("deleted", not alive)
	if node is CollisionObject3D:
		node.collision_layer = MINIATURE_COLLISION_LAYER if alive else 0


# === Loose-unit casualty → army tray (desaturated, revive-only) =============================
# A dead LOOSE model is not hidden: it is desaturated and parked on its owner's army tray, still
# raycastable so it can be right-clicked to revive (the "deleted" meta blocks every other action).
# Regiment models never use this — they keep AoF:R rank-removal in the block.

## Constant gap between adjacent model base edges — the same value the army-spawn layout uses so a
## parked casualty sits at the standard tight spacing, not spread out (J7). Shared by both paths.
const BASE_EDGE_GAP_M := 0.008
## Parked-model grid spacing = a ~1" base + the standard edge gap (matches a spawned unit's spacing).
const DEAD_SLOT_STEP := INCHES_TO_METERS + BASE_EDGE_GAP_M
const DEAD_SLOT_EDGE := 0.06          # padding from the tray edge (m)
## Rest exactly on the tray surface like a spawned model (_animate_tray_drop settles models at y=0.0),
## not floating above it (J7).
const DEAD_SLOT_Y := 0.0

static var _dead_shader: Shader = null   # shared greyscale shader for dead models

## Desaturate every surface of a model (dead look), keeping texture detail via a greyscale shader.
## The pre-death surface overrides are stashed under a meta so revive can restore them exactly.
func _desaturate_model(node: Node3D) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null or mi.has_meta("dead_orig_override"):
			continue
		var origs: Array = []
		for s in range(mi.mesh.get_surface_count()):
			origs.append(mi.get_surface_override_material(s))
			var base := mi.get_active_material(s)
			var sm := ShaderMaterial.new()
			sm.shader = _get_dead_shader()
			if base is BaseMaterial3D and (base as BaseMaterial3D).albedo_texture != null:
				sm.set_shader_parameter("albedo_tex", (base as BaseMaterial3D).albedo_texture)
			mi.set_surface_override_material(s, sm)
		mi.set_meta("dead_orig_override", origs)


## Restore a revived model's original per-surface materials.
func _restore_model_material(node: Node3D) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if not mi.has_meta("dead_orig_override"):
			continue
		var origs: Array = mi.get_meta("dead_orig_override")
		for s in range(mi.mesh.get_surface_count()):
			mi.set_surface_override_material(s, origs[s] if s < origs.size() else null)
		mi.remove_meta("dead_orig_override")


static func _get_dead_shader() -> Shader:
	if _dead_shader == null:
		_dead_shader = Shader.new()
		_dead_shader.code = "shader_type spatial;\n" \
			+ "uniform sampler2D albedo_tex : source_color, hint_default_white;\n" \
			+ "uniform float strength = 0.85;\n" \
			+ "void fragment() {\n" \
			+ "  vec3 c = texture(albedo_tex, UV).rgb;\n" \
			+ "  float g = dot(c, vec3(0.299, 0.587, 0.114));\n" \
			+ "  ALBEDO = mix(c, vec3(g), strength) * 0.65;\n" \
			+ "  ROUGHNESS = 0.95; METALLIC = 0.0;\n" \
			+ "}\n"
	return _dead_shader


## Park a dead loose model on its owner's tray (dead=true) or return it to its stored table spot
## (dead=false). Keeps the node visible + raycastable; the "deleted" meta gates it to revive-only.
## `unit_id` groups a unit's dead models into one contiguous block on the tray (G2); "" falls back to
## the node's own identity (each model its own block). `forced_slot` >= 0 pins the parking slot (remote
## peers replaying the host's choice in MP); -1 picks the slot locally from the unit's block.
func set_loose_model_dead(node: Node3D, player_id: int, dead: bool, unit_id: String = "", forced_slot: int = -1) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.set_meta("deleted", dead)
	node.visible = true
	if node is CollisionObject3D:
		node.collision_layer = MINIATURE_COLLISION_LAYER  # stays clickable for revive
	if dead:
		if not node.has_meta("revive_transform"):
			node.set_meta("revive_transform", node.global_transform)
		_desaturate_model(node)
		var slot := _claim_dead_slot(player_id, node, unit_id, forced_slot)
		if slot != Vector3.ZERO:
			node.global_position = slot
	else:
		_restore_model_material(node)
		_release_dead_slot(player_id, node)
		if node.has_meta("revive_transform"):
			node.global_transform = node.get_meta("revive_transform")
			node.remove_meta("revive_transform")
	# Choke point (J9): every path that parks/un-parks a loose model runs through here, so token
	# cleanup/re-derivation is driven once from this signal instead of at each call site.
	loose_model_dead_changed.emit(node, dead)


## The slot a parked model occupies (set by the last set_loose_model_dead call), or -1. Lets the MP
## sender tell peers which slot to reuse so both sides park identically.
func dead_slot_of(node: Node3D) -> int:
	return int(node.get_meta("dead_slot", -1)) if node != null and is_instance_valid(node) else -1


## Claim a parking slot on the player's tray for `node` and return its world position (ZERO if the
## tray is gone). Reveals the tray. `forced_index` >= 0 pins the slot; else the lowest free one. The
## slot is recorded on the node ("dead_slot") and marked occupied on the tray so revive can free it.
func _claim_dead_slot(player_id: int, node: Node3D, unit_id: String, forced_index: int = -1) -> Vector3:
	if not army_trays.has(player_id) or not is_instance_valid(army_trays[player_id]):
		push_warning("[DeadTray] no army tray for player %d — dead model stays in place" % player_id)
		return Vector3.ZERO
	var tray: Node3D = army_trays[player_id]
	tray.visible = true
	var info := _get_tray_position_and_bounds(player_id)
	var bounds: Vector2 = info.bounds
	var cols: int = maxi(1, int((bounds.x - 2.0 * DEAD_SLOT_EDGE) / DEAD_SLOT_STEP))
	var rows: int = maxi(1, int((bounds.y - 2.0 * DEAD_SLOT_EDGE) / DEAD_SLOT_STEP))
	var key: String = _dead_group_key(unit_id, node)
	var occupied: Dictionary = tray.get_meta("dead_slots", {})
	var anchors: Dictionary = tray.get_meta("dead_unit_anchors", {})
	var idx := _alloc_unit_slot(occupied, anchors, key, cols, cols * rows, forced_index)
	tray.set_meta("dead_slots", occupied)
	tray.set_meta("dead_unit_anchors", anchors)
	node.set_meta("dead_slot", idx)
	node.set_meta("dead_unit_key", key)
	var col: int = idx % cols
	var row: int = idx / cols
	# G1: fill from the FAR (−Z) edge toward the near-third Ambush/Scout band. Rows 0..(safe) sit
	# behind the band; only a nearly full grid (rows past ~2/3 of the depth) overflows into it — the
	# lesser evil vs. parking off the tray. See _first_free_row_start / DEAD_SLOT_* constants.
	return Vector3(
		info.position.x - bounds.x / 2.0 + DEAD_SLOT_EDGE + float(col) * DEAD_SLOT_STEP,
		DEAD_SLOT_Y,
		info.position.z - bounds.y / 2.0 + DEAD_SLOT_EDGE + float(row) * DEAD_SLOT_STEP)


## Free the slot a revived model held so it can be reused (fixes the kill→revive→kill creep). When the
## model's unit has no dead models left, releases the unit's anchor so the block can be re-packed.
func _release_dead_slot(player_id: int, node: Node3D) -> void:
	if node == null or not node.has_meta("dead_slot"):
		return
	var idx: int = int(node.get_meta("dead_slot"))
	var key: String = str(node.get_meta("dead_unit_key", ""))
	node.remove_meta("dead_slot")
	if node.has_meta("dead_unit_key"):
		node.remove_meta("dead_unit_key")
	if army_trays.has(player_id) and is_instance_valid(army_trays[player_id]):
		var tray: Node3D = army_trays[player_id]
		var occupied: Dictionary = tray.get_meta("dead_slots", {})
		_free_slot_index(occupied, idx)
		tray.set_meta("dead_slots", occupied)
		var anchors: Dictionary = tray.get_meta("dead_unit_anchors", {})
		_release_unit_anchor(occupied, anchors, key)   # unit fully revived → free its block
		tray.set_meta("dead_unit_anchors", anchors)


## Allocate a slot for `unit_key`, grouping a unit's dead models into a contiguous block (G2). A new
## unit anchors at the first fully-free row; further deaths take the lowest free index at/after the
## anchor (row-major), so two units never interleave. `forced` >= 0 pins the slot (MP replay). Wraps to
## the lowest free index when the unit's rows are exhausted. `occupied` maps index → owning unit_key.
## Pure/static → unit-testable.
static func _alloc_unit_slot(occupied: Dictionary, anchors: Dictionary, unit_key: String, cols: int, capacity: int, forced: int = -1) -> int:
	var cap: int = maxi(capacity, 1)
	var idx: int
	if forced >= 0:
		idx = forced % cap
		if not anchors.has(unit_key):
			anchors[unit_key] = idx   # first pinned slot anchors the block (MP replay / save restore)
	else:
		var anchor: int
		if anchors.has(unit_key):
			anchor = int(anchors[unit_key])
		else:
			anchor = _first_free_row_start(occupied, cols, cap)
			anchors[unit_key] = anchor
		idx = anchor
		while idx < cap and occupied.has(idx):
			idx += 1
		if idx >= cap:   # unit's rows exhausted → lowest free anywhere (overflow)
			idx = 0
			while idx < cap and occupied.has(idx):
				idx += 1
			idx = idx % cap
	occupied[idx] = unit_key
	return idx


## First col-0 index of a fully-free row (so a new unit's block never overlaps another's), or the
## lowest free index when no whole row is free (overflow toward the band). Pure/static.
static func _first_free_row_start(occupied: Dictionary, cols: int, capacity: int) -> int:
	var c: int = maxi(cols, 1)
	var cap: int = maxi(capacity, 1)
	var row: int = 0
	while row * c < cap:
		var start: int = row * c
		var free: bool = true
		for k in range(start, mini(start + c, cap)):
			if occupied.has(k):
				free = false
				break
		if free:
			return start
		row += 1
	var i: int = 0
	while i < cap and occupied.has(i):
		i += 1
	return i % cap


## Release a slot index (mirror of _alloc_unit_slot). Pure/static → unit-testable.
static func _free_slot_index(occupied: Dictionary, idx: int) -> void:
	occupied.erase(idx)


## The block key a dead model groups under: the caller's unit_id when given, else the model's OWN unit
## (from its game_unit meta) so a whole unit always parks as one contiguous block regardless of the
## call site (J2), else the node's instance id (a lone block). Pure/static → unit-testable.
static func _dead_group_key(unit_id: String, node: Node3D) -> String:
	if not unit_id.is_empty():
		return unit_id
	var gu := UnitUtils.get_game_unit(node)
	if gu != null and not gu.unit_id.is_empty():
		return gu.unit_id
	return str(node.get_instance_id())


## Drop a unit's block anchor once none of its slots remain occupied (called on revive, so the block
## can be re-packed from scratch next time). Pure/static → unit-testable.
static func _release_unit_anchor(occupied: Dictionary, anchors: Dictionary, unit_key: String) -> void:
	if not unit_key.is_empty() and anchors.has(unit_key) and not occupied.values().has(unit_key):
		anchors.erase(unit_key)


## Apply `wounds_taken` to a Tough(1) pooled regiment: mark casualties dead/alive, drive
## the pooled counter (back rank dies first, AoF:R v3.5.1 p.9), re-rank the block,
## refresh the counter label, and broadcast to peers. `regiment.wounds_taken` and
## `unit_properties["regiment_wounds_taken"]` are set to `wounds_taken`. No undo
## (callers wrap this in a RegimentWoundAction); no clamp (caller must clamp).
func apply_regiment_wounds(regiment: Regiment, wounds_taken: int) -> void:
	if regiment == null or regiment.game_unit == null or not is_instance_valid(regiment.tray):
		return
	var gu := regiment.game_unit as GameUnit
	var toughs := _regiment_toughs(gu)
	var pool := Regiment.pool_max(toughs)
	var taken := clampi(wounds_taken, 0, pool)
	var taken_before := regiment.wounds_taken
	regiment.wounds_taken = taken
	gu.unit_properties["regiment_wounds_taken"] = taken
	var mask := Regiment.alive_mask_for_wounds(toughs, taken)
	for i in range(gu.models.size()):
		var m := gu.models[i]
		var alive: bool = mask[i] if i < mask.size() else false
		var on_model: int = Regiment.wounds_on_model(toughs, taken, i)
		m.is_alive = alive
		# wounds_current = tough - wounds_taken_on_this (0 when dead).
		m.wounds_current = maxi(maxi(int(toughs[i]), 1) - on_model, 0) if alive else 0
		set_model_alive_state(m.node, alive)  # visible + "deleted" meta + collision off when dead
	# Re-rank the surviving models (ranks close from the back).
	var members := RegimentTray.collect_members(gu)
	if not members.nodes.is_empty():
		regiment.tray.reform(members.nodes, members.footprints)
	# Drive the wound token via the shared unit-boundary system (same visual language
	# as Fatigued/Shaken): the token sits on the Einheitenrand and shows the
	# wounds_taken count (counting UP). Hidden when taken == 0.
	if radial_menu_controller != null and radial_menu_controller.has_method("update_regiment_wound_token"):
		radial_menu_controller.update_regiment_wound_token(gu, taken)
	if network_manager != null and network_manager.is_multiplayer_active():
		network_manager.broadcast_regiment_wounds(gu.unit_id, taken)
	if taken != taken_before:
		regiment_wounds_applied.emit(gu.get_name(), taken - taken_before, pool - taken, pool)


## Take one casualty on the selected regiment (wounds_taken += 1). Clamped to the
## pool; no-op at full casualties. Pushes an undoable RegimentWoundAction. Called from
## the regiment radial menu's "Casualty -" item. Returns the new wounds_taken.
func regiment_take_casualty(tray: RegimentTray) -> int:
	var regiment: Regiment = tray.get_meta("regiment") if tray.has_meta("regiment") else null
	if regiment == null or regiment.game_unit == null:
		return 0
	var gu := regiment.game_unit as GameUnit
	var pool := Regiment.pool_max(_regiment_toughs(gu))
	var from_taken: int = regiment.wounds_taken
	var to_taken: int = mini(from_taken + 1, pool)
	if to_taken == from_taken:
		return from_taken
	apply_regiment_wounds(regiment, to_taken)
	if undo_manager != null:
		var move_peer: int = network_manager.get_my_peer_id() if network_manager else 0
		undo_manager.push(UndoManager.RegimentWoundAction.new(regiment, from_taken, to_taken, self, network_manager, move_peer))
	return to_taken


## Revive one model on the selected regiment (wounds_taken -= 1). Clamped to 0;
## no-op at full strength. Pushes an undoable RegimentWoundAction. Called from the
## regiment radial menu's "Casualty +" item. Returns the new wounds_taken.
func regiment_revive_casualty(tray: RegimentTray) -> int:
	var regiment: Regiment = tray.get_meta("regiment") if tray.has_meta("regiment") else null
	if regiment == null or regiment.game_unit == null:
		return 0
	var from_taken: int = regiment.wounds_taken
	var to_taken: int = maxi(from_taken - 1, 0)
	if to_taken == from_taken:
		return from_taken
	apply_regiment_wounds(regiment, to_taken)
	if undo_manager != null:
		var move_peer: int = network_manager.get_my_peer_id() if network_manager else 0
		undo_manager.push(UndoManager.RegimentWoundAction.new(regiment, from_taken, to_taken, self, network_manager, move_peer))
	return to_taken


## The wound-pool readout for a regiment tray (remaining, pool_max), for menu labels.
func regiment_wound_readout(tray: RegimentTray) -> Dictionary:
	var regiment: Regiment = tray.get_meta("regiment") if tray.has_meta("regiment") else null
	if regiment == null or regiment.game_unit == null:
		return {"remaining": 0, "pool_max": 0}
	var gu := regiment.game_unit as GameUnit
	var pool := Regiment.pool_max(_regiment_toughs(gu))
	return {"remaining": pool - regiment.wounds_taken, "pool_max": pool}


## Defer regiment forming until the spawn drop animation has settled.
func _form_regiments_after_drop(army) -> void:
	await get_tree().create_timer(TRAY_DROP_DURATION + 0.1).timeout
	form_all_regiments(army)


## Animate tray and models dropping from above - smooth deceleration
func _animate_tray_drop(tray: Node3D, models: Array[Node3D], start_height: float) -> void:
	# Position tray at elevated height
	tray.position.y = start_height

	# Create tween for smooth drop animation (fast start, gradual slowdown)
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)  # Smooth deceleration, no bounce

	# Animate tray dropping
	tween.tween_property(tray, "position:y", 0.0, TRAY_DROP_DURATION)

	# Animate all models dropping together
	for model in models:
		var model_tween = create_tween()
		model_tween.set_ease(Tween.EASE_OUT)
		model_tween.set_trans(Tween.TRANS_CUBIC)  # Smooth deceleration, no bounce
		var target_y = 0.0
		model_tween.tween_property(model, "global_position:y", target_y, TRAY_DROP_DURATION)
		# Ensure final position is exactly at table surface
		model_tween.tween_callback(func(): model.global_position.y = 0.0)


## Create an army tray beside the table for a player
func _create_army_tray(player_id: int, army_name: String, player_color: Color) -> Node3D:
	# Remove existing tray for this player
	if army_trays.has(player_id) and is_instance_valid(army_trays[player_id]):
		army_trays[player_id].queue_free()

	var tray_info = _get_tray_position_and_bounds(player_id)
	var tray_pos = tray_info.position
	var tray_size = tray_info.bounds

	# Create tray container
	var tray = StaticBody3D.new()
	tray.name = "ArmyTray_Player%d" % player_id

	# Tray surface (slightly raised platform)
	var tray_mesh = BoxMesh.new()
	tray_mesh.size = Vector3(tray_size.x, 0.01, tray_size.y)

	var tray_instance = MeshInstance3D.new()
	tray_instance.mesh = tray_mesh
	tray_instance.position.y = -0.005

	var tray_material = StandardMaterial3D.new()
	tray_material.albedo_color = player_color.darkened(0.6)
	tray_material.roughness = 0.8
	tray_instance.material_override = tray_material

	tray.add_child(tray_instance)

	# Tray border
	var border_color = player_color.darkened(0.3)
	_add_tray_border(tray, tray_size, border_color)

	# Ambush/Scout staging band (representation only). Built here — intrinsic to every tray —
	# so it survives ALL reconstruction paths (live MP receive, late-joiner state-sync, .nml
	# load), not just the importer's spawn_army (issue #76). Parented under the tray, so it
	# inherits the build-time hide and rides the _animate_tray_drop tween.
	_add_ambush_scout_band(tray, tray_size, border_color)

	# Army name label (as 3D text or just metadata for now)
	tray.set_meta("army_name", army_name)
	tray.set_meta("player_id", player_id)
	# Right-clickable (a dedicated group, NOT "selectable" so it isn't drag-selected) so the tray
	# menu can offer "Return destroyed units" — a fully-wiped unit has no clickable model of its own.
	tray.add_to_group("army_tray")

	# Collision for tray surface
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(tray_size.x, 0.02, tray_size.y)
	collision.shape = shape
	collision.position.y = -0.01
	tray.add_child(collision)

	# Add to scene tree BEFORE setting global_position
	object_manager.get_parent().add_child(tray)
	tray.global_position = tray_pos

	army_trays[player_id] = tray
	return tray


## Add border around tray
func _add_tray_border(tray: Node3D, tray_size: Vector2, border_color: Color) -> void:
	var border_height = 0.02
	var border_width = 0.01

	var border_material = StandardMaterial3D.new()
	border_material.albedo_color = border_color
	border_material.roughness = 0.7

	# Four sides
	var positions = [
		Vector3(0, border_height / 2, -tray_size.y / 2),  # Front
		Vector3(0, border_height / 2, tray_size.y / 2),   # Back
		Vector3(-tray_size.x / 2, border_height / 2, 0),  # Left
		Vector3(tray_size.x / 2, border_height / 2, 0),   # Right
	]

	var sizes = [
		Vector3(tray_size.x, border_height, border_width),
		Vector3(tray_size.x, border_height, border_width),
		Vector3(border_width, border_height, tray_size.y),
		Vector3(border_width, border_height, tray_size.y),
	]

	for i in range(4):
		var border_mesh = BoxMesh.new()
		border_mesh.size = sizes[i]

		var border_instance = MeshInstance3D.new()
		border_instance.mesh = border_mesh
		border_instance.material_override = border_material
		border_instance.position = positions[i]
		tray.add_child(border_instance)


## Add the Ambush/Scout deployment band to a tray. Reserves the tray's near (-Z) third, split at
## the centre into Ambush-LEFT / Scout-RIGHT by a thin divider, with two translucent tint quads
## and two flat, bird's-eye-readable labels. All nodes are parented UNDER `tray` so they inherit
## its build-time hide and ride the _animate_tray_drop tween. Representation only — no rules.
## `bounds` is the tray's (width, depth) in metres; the tray is an axis-aligned square at origin.
func _add_ambush_scout_band(tray: Node3D, bounds: Vector2, divider_color: Color) -> void:
	if tray == null or not is_instance_valid(tray):
		return

	# Tray-local band geometry. Band sits at the NEAR (+Z) edge — the "bottom" of the tray — so it
	# doesn't overlap the main packer, which fills from the -Z edge.
	var band_depth: float = bounds.y * BAND_DEPTH_FRACTION
	var band_z_min: float = bounds.y / 2.0 - band_depth
	var band_z_mid: float = band_z_min + band_depth / 2.0
	var half_w: float = bounds.x / 2.0
	var ambush_center_x: float = -bounds.x / 4.0  # LEFT half centre
	var scout_center_x: float = bounds.x / 4.0  # RIGHT half centre

	# (a) Two translucent half-quads (PlaneMesh + unshaded alpha), one tint per half.
	_add_band_tint_quad(tray, Vector2(half_w, band_depth),
		Vector3(ambush_center_x, BAND_TINT_Y, band_z_mid), BAND_AMBUSH_TINT)
	_add_band_tint_quad(tray, Vector2(half_w, band_depth),
		Vector3(scout_center_x, BAND_TINT_Y, band_z_mid), BAND_SCOUT_TINT)

	# (b) Thin centre divider spanning the band depth (matches the tray-border box style).
	var divider_mesh := BoxMesh.new()
	divider_mesh.size = Vector3(BAND_DIVIDER_WIDTH, BAND_DIVIDER_HEIGHT, band_depth)
	var divider_material := StandardMaterial3D.new()
	divider_material.albedo_color = divider_color
	divider_material.roughness = 0.7
	var divider_instance := MeshInstance3D.new()
	divider_instance.name = "AmbushScoutDivider"
	divider_instance.mesh = divider_mesh
	divider_instance.material_override = divider_material
	divider_instance.position = Vector3(0.0, BAND_DIVIDER_Y, band_z_mid)
	tray.add_child(divider_instance)

	# (c) Two small flat labels anchored BOTTOM-LEFT in each half (fixed orientation, no camera-follow).
	# Bottom (the near +Z edge) so they clear the minis, which fill the band from the inner (-Z) edge.
	# "Left" = each half's -X edge (Scout's left edge is the centre divider).
	var label_pad: float = 0.012
	var band_z_max: float = bounds.y / 2.0
	var label_z: float = band_z_max - label_pad
	_add_band_label(tray, "Ambush", Vector3(-bounds.x / 2.0 + label_pad, BAND_LABEL_Y, label_z))
	_add_band_label(tray, "Scout", Vector3(label_pad, BAND_LABEL_Y, label_z))


## One translucent, unshaded, double-sided band tint quad parented under `tray` (tray-local pos).
## render_priority keeps it above the tray plate/border so it never z-flips on orbit (issue #71).
func _add_band_tint_quad(tray: Node3D, size: Vector2, local_pos: Vector3, color: Color) -> void:
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = size

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = BAND_RENDER_PRIORITY

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "AmbushScoutTint"
	mesh_instance.mesh = plane_mesh
	mesh_instance.material_override = material
	mesh_instance.position = local_pos
	tray.add_child(mesh_instance)


## One small flat band label parented under `tray` (tray-local pos). Lies flat (billboard off, -90°
## about X) with a FIXED orientation (no camera-follow), anchored at its bottom-left, with a dark outline.
func _add_band_label(tray: Node3D, text: String, local_pos: Vector3) -> void:
	var label := Label3D.new()
	label.name = "AmbushScoutLabel_%s" % text
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED  # lie flat on the tray
	label.font_size = BAND_LABEL_FONT_SIZE
	label.outline_size = BAND_LABEL_OUTLINE_SIZE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.modulate = Color.WHITE
	label.outline_modulate = BAND_LABEL_OUTLINE_COLOR
	label.pixel_size = BAND_LABEL_PIXEL_SIZE
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)  # flat, fixed orientation (no camera-follow)
	label.position = local_pos
	tray.add_child(label)


## True if `unit` carries the literal special rule `rule` (e.g. "Scout"/"Ambush"). These rules are
## unrated, but may import with a trailing "(...)", so compare the base name only — mirroring the
## buff_tokens_from_rules normalization. Static so callers can probe without an instance.
static func _unit_has_rule(unit, rule: String) -> bool:
	if unit == null:
		return false
	for raw in unit.special_rules:
		if str(raw).split("(")[0].strip_edges() == rule:
			return true
	return false


## Path-4 heuristic: catches `rule` (Scout/Ambush) GRANTED only in the free-text DESCRIPTION of
## another rule the unit carries — ArmyForge exposes no structured "grants" field for that case, so we
## whole-word-scan the descriptions of the unit's rules. Maintainer-chosen (over missing a free-text
## grant); it can RARELY over-include a unit whose rule merely MENTIONS the word — accepted, benign for
## a staging aid. Direct hits are already handled by _unit_has_rule. Non-static (uses _word_in).
func _unit_rule_describes(unit, rule: String, rule_descriptions: Dictionary) -> bool:
	if unit == null or rule_descriptions.is_empty():
		return false
	for raw in unit.special_rules:
		var base: String = str(raw).split("(")[0].strip_edges()
		if base == rule:
			continue
		var desc: String = str(rule_descriptions.get(base, ""))
		if not desc.is_empty() and _word_in(desc, rule):
			return true
	return false


## Get tray position and bounds based on player ID and table size
func _get_tray_position_and_bounds(player_id: int) -> Dictionary:
	# Get table size (default 4x4 feet)
	var table_size_feet = Vector2(4, 4)
	if table and table.get("table_size"):
		table_size_feet = table.table_size

	var table_size_m = table_size_feet * FEET_TO_METERS

	# Fixed tray size: 32x32 inches
	var tray_size_m = TRAY_SIZE_INCHES * INCHES_TO_METERS  # ~0.81m

	var pos = Vector3.ZERO
	var bounds = Vector2(tray_size_m, tray_size_m)  # Square tray

	var side = TRAY_SIDES.get(player_id, "left")

	match side:
		"left":
			pos.x = -table_size_m.x / 2 - TRAY_MARGIN - tray_size_m / 2
			pos.z = 0
		"right":
			pos.x = table_size_m.x / 2 + TRAY_MARGIN + tray_size_m / 2
			pos.z = 0
		"front":
			pos.x = 0
			pos.z = -table_size_m.y / 2 - TRAY_MARGIN - tray_size_m / 2
		"back":
			pos.x = 0
			pos.z = table_size_m.y / 2 + TRAY_MARGIN + tray_size_m / 2

	return {"position": pos, "bounds": bounds}


## Spawn a single unit with all its models
func _spawn_unit(unit: OPRApiClient.OPRUnit, spawn_pos: Vector3, player_color: Color, name_suffix: String = "", player_id: int = 1, army: OPRApiClient.OPRArmy = null) -> Array[Node3D]:
	var models: Array[Node3D] = []
	# Use unit's base diameter + constant edge gap for spacing (prevents overlap)
	var edge_gap = BASE_EDGE_GAP_M
	var spacing = unit.get_base_diameter_meters() + edge_gap

	# Get faction folder for GLB model lookup
	var faction_folder = army.faction_folder if army else ""

	# Per-model base sizing: a weapon-team / upgrade that raises a model's Tough above the squad
	# baseline gets a bigger base (derived from the SAME distribution distribute() applies, so the
	# bigger base lands on the exact carrier model). Plain models keep the unit base unchanged.
	var loadout := EquipmentDistributor.build_loadout(unit)
	var toughs := EquipmentDistributor.per_model_toughs(unit.size, loadout, unit.special_rules)
	# Per-model loadout labels → pre-baked variant model resolution (I2).
	var labels_per_model := EquipmentDistributor.per_model_labels(unit.size, loadout)
	var unit_base_long := int(max(unit.base_width_mm, unit.base_depth_mm)) if (unit.base_is_oval or unit.base_is_square) else unit.base_size_round
	var model_longs: Array = []
	var any_enlarged := false
	for i in range(unit.size):
		var ml := model_base_long_mm(unit_base_long, int(toughs[i]))
		model_longs.append(ml)
		if ml > unit_base_long:
			any_enlarged = true

	# Mount/vehicle upgrade (Combat Bike, ...): fuzzy-pick a faction mount GLB once for the leader
	# model (model 0). "" when the unit has no mount or no matching faction GLB (keeps the foot model).
	var mount_glb: String = _find_mount_glb_name(unit.mount_name, faction_folder)
	var cursor_x := spawn_pos.x
	for i in range(unit.size):
		var model_pos: Vector3
		if any_enlarged:
			# Edge-to-edge spacing so a bigger model sits clear — only when sizes actually differ.
			if i > 0:
				cursor_x += (int(model_longs[i - 1]) * 0.5 + int(model_longs[i]) * 0.5) * 0.001 + edge_gap
			model_pos = Vector3(cursor_x, spawn_pos.y, spawn_pos.z)
		else:
			# Plain units unchanged byte-for-byte: original fixed diameter spacing.
			model_pos = Vector3(spawn_pos.x + i * spacing, spawn_pos.y, spawn_pos.z)

		var override_mm: int = int(model_longs[i]) if any_enlarged else 0
		# Mount/vehicle GLB applies to the leader model (model 0); its base is already on the unit.
		# Otherwise resolve a pre-baked loadout variant (`<unit>#<slug>`), falling back to the base (I2).
		var mglb: String = mount_glb if i == 0 else ""
		if mglb.is_empty():
			mglb = _resolve_model_variant_name(unit.name, labels_per_model[i], faction_folder)
			# A slug was derived but no `<unit>#<slug>` key exists → base fallback (rare; logged in E6).
			if mglb.is_empty() and model_library != null and not model_library.variant_slug(labels_per_model[i]).is_empty():
				_variant_missing_count += 1
		var model = _create_unit_model(unit, player_color, name_suffix, faction_folder, override_mm, mglb)
		if model:
			# Assign a slot-namespaced network_id for multiplayer position sync (no
			# cross-army collision regardless of import order).
			model.set_meta("network_id", _next_owned_net_id(player_id))

			object_manager.add_child(model)
			model.global_position = model_pos

			# Add to groups
			model.add_to_group("selectable")
			model.add_to_group("miniature")  # Required for measurement
			model.add_to_group("opr_unit")
			model.add_to_group("unit")

			# Store the OPRUnit on the model — still read by save_manager.gd for .nml restore
			model.set_meta("opr_unit", unit)
			model.set_meta("opr_player_id", player_id)

			models.append(model)

	# NEW: Create GameUnit wrapper with ModelInstances
	if not models.is_empty():
		var typed_models: Array[Node3D] = []
		typed_models.assign(models)
		var rule_descriptions: Dictionary = army.rule_descriptions if army else {}
		var game_unit = EquipmentDistributor.create_from_opr_unit(unit, typed_models, player_id, rule_descriptions)

		# Store mappings
		unit_to_game_unit[unit] = game_unit
		game_units[game_unit.unit_id] = game_unit

		# Store name suffix and faction folder on GameUnit (needed for save/load)
		game_unit.unit_properties["display_suffix"] = name_suffix
		game_unit.unit_properties["faction_folder"] = faction_folder

		# Store import positions on ModelInstances (for Sort Table reset).
		# Capture the resting height (table surface, y=0), NOT the elevated
		# TRAY_DROP_HEIGHT the models currently sit at before _animate_tray_drop
		# lowers them - otherwise Sort Table would restore them in mid-air.
		for i in range(game_unit.models.size()):
			var model_instance = game_unit.models[i]
			if model_instance and model_instance.node and is_instance_valid(model_instance.node):
				var resting_pos: Vector3 = model_instance.node.global_position
				resting_pos.y = 0.0
				model_instance.import_position = resting_pos
				model_instance.import_rotation = model_instance.node.rotation

	return models


## Create a visual model for a unit (GLB model if available, otherwise placeholder)
## Per-model base long-axis (mm): enlarge to the model's Tough-derived size, never shrink. A
## weapon-team / upgrade that raises a model's Tough above the squad baseline gets a bigger base.
## Plain models (Tough 1 -> OPRApiClient._base_size_from_tough == 0) keep the unit base unchanged.
static func model_base_long_mm(unit_base_long_mm: int, model_tough: int) -> int:
	return maxi(unit_base_long_mm, OPRApiClient._base_size_from_tough(model_tough))


## Returns a copy of `props` with the base dimensions scaled up to the per-model Tough-enlarged
## base (never shrinks). Tokens / measuring / range rings call this so they anchor to a model's
## ACTUAL (enlarged) base, not the unit-suggested one — while the model MESH stays natural-sized.
## Returns the same dict unchanged when no enlargement applies.
static func effective_base_props(props: Dictionary, model_tough: int) -> Dictionary:
	if model_tough <= 0 or props.is_empty():
		return props
	var is_oval: bool = props.get("base_is_oval", false) or props.get("base_is_square", false)
	var natural_long: int = int(maxi(int(props.get("base_width_mm", 0)), int(props.get("base_depth_mm", 0)))) if is_oval else int(props.get("base_size_round", 0))
	if natural_long <= 0:
		return props
	var effective: int = model_base_long_mm(natural_long, model_tough)
	if effective <= natural_long:
		return props
	var copy: Dictionary = props.duplicate()
	if is_oval:
		var ratio := float(effective) / float(natural_long)
		copy["base_width_mm"] = int(round(int(props.get("base_width_mm", 0)) * ratio))
		copy["base_depth_mm"] = int(round(int(props.get("base_depth_mm", 0)) * ratio))
	else:
		copy["base_size_round"] = effective
	return copy


func _create_unit_model(unit: OPRApiClient.OPRUnit, player_color: Color, name_suffix: String = "", faction_folder: String = "", base_long_override_mm: int = 0, model_name_override: String = "") -> StaticBody3D:
	var wrapper = StaticBody3D.new()
	wrapper.collision_layer = MINIATURE_COLLISION_LAYER
	wrapper.collision_mask = GROUND_COLLISION_LAYER
	var display_name = unit.name + name_suffix
	wrapper.name = "OPR_%s" % display_name.replace(" ", "_")

	# Get base dimensions from Army Forge
	var base_is_oval = unit.base_is_oval
	var base_width = unit.base_width_mm * 0.001  # mm to meters (perpendicular to facing)
	var base_depth = unit.base_depth_mm * 0.001  # mm to meters (in facing direction / "north")
	var base_radius = unit.get_base_radius_meters()  # For body scaling

	# Per-model base: a weapon-team / Tough upgrade enlarges THIS model's base (never shrinks).
	# Computed before the mesh so mesh/GLB-fit/collision all read the corrected dims.
	# Natural base = the unit's OPR-suggested size. The model mesh is fitted to THIS, never to the
	# Tough-enlarged base — otherwise enlarging the base scale-creeps the character (the base grows,
	# the model should not). The enlarged base only drives the ring/collision (and tokens/measuring,
	# which re-derive it from Tough).
	var natural_base_long_mm: int = int(max(unit.base_width_mm, unit.base_depth_mm)) if (base_is_oval or unit.base_is_square) else unit.base_size_round
	var natural_base_short_mm: int = int(min(unit.base_width_mm, unit.base_depth_mm)) if (base_is_oval or unit.base_is_square) else unit.base_size_round
	var fit_to_base: bool = unit.base_from_tough
	var base_long_mm: int = natural_base_long_mm
	if base_long_override_mm > base_long_mm:
		var ratio := float(base_long_override_mm) / float(maxi(1, base_long_mm))
		base_long_mm = base_long_override_mm
		if base_is_oval or unit.base_is_square:
			base_width = clampf(unit.base_width_mm * ratio, 20.0, 150.0) * 0.001
			base_depth = clampf(unit.base_depth_mm * ratio, 20.0, 150.0) * 0.001
		else:
			base_radius = (base_long_override_mm / 2.0) * 0.001
			base_width = base_long_override_mm * 0.001
			base_depth = base_long_override_mm * 0.001

	# Create base mesh
	var base_instance = MeshInstance3D.new()

	if unit.base_is_square:
		# Square/rectangular base (Age of Fantasy: Regiments): flat box.
		# Long side (depth) faces north (+Z direction), matching the oval convention.
		var base_mesh = BoxMesh.new()
		base_mesh.size = Vector3(base_width, 0.003, base_depth)
		base_instance.mesh = base_mesh
		base_instance.position.y = 0.0015
	elif base_is_oval:
		# Oval base: use cylinder with non-uniform scale
		# Long side (depth) faces north (+Z direction)
		var base_mesh = CylinderMesh.new()
		base_mesh.top_radius = 0.5  # Unit radius, will be scaled
		base_mesh.bottom_radius = 0.5
		base_mesh.height = 0.003
		base_instance.mesh = base_mesh
		# Scale: X = width, Y = height (unchanged), Z = depth
		base_instance.scale = Vector3(base_width, 1.0, base_depth)
		base_instance.position.y = 0.0015
	else:
		# Round base: normal cylinder
		var base_mesh = CylinderMesh.new()
		base_mesh.top_radius = base_radius
		base_mesh.bottom_radius = base_radius
		base_mesh.height = 0.003
		base_instance.mesh = base_mesh
		base_instance.position.y = 0.0015

	var base_material = StandardMaterial3D.new()
	base_material.albedo_color = player_color
	base_material.roughness = 0.7
	base_instance.material_override = base_material
	base_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	wrapper.add_child(base_instance)

	# Visual hover: Flying units, drones and hover vehicles float above the base.
	# Hover height: Aircraft on a tall stand (~20cm), Flying/drones a small base-relative float.
	var hover_lift: float = _hover_lift_m(unit.special_rules, unit.name, natural_base_long_mm)

	# Try to load GLB model for this unit (mount upgrades pick a faction mount/bike GLB instead).
	var glb_name: String = model_name_override if not model_name_override.is_empty() else unit.name
	# Prefer the ctex path (decimated mesh + BC7 material) when its blobs are cached (the army prefetch
	# fetches them for a compatible engine); otherwise fall back to the legacy raw-GLB path.
	var ctex_paths: Dictionary = model_library.ctex_cached_paths(faction_folder, glb_name) if model_library != null else {}
	var use_ctex: bool = not ctex_paths.is_empty()
	var model_path: String = str(ctex_paths.get("mesh", "")) if use_ctex else _find_model_for_unit(glb_name, faction_folder)
	if glb_name.contains("#"):
		_variant_used_count += 1   # I2: a pre-baked loadout variant was resolved for this model
	# E6: tally the delivery path (ctex vs legacy fallback + reason) — summarised at spawn_army end.
	if use_ctex:
		_ctex_used_count += 1
	else:
		var reason: String = "not-cached" if (model_library != null and not model_library.get_ctex_entry(faction_folder, glb_name).is_empty()) else "no-compatible-ctex"
		_legacy_used_reasons[reason] = int(_legacy_used_reasons.get(reason, 0)) + 1
	var model_height: float = 0.032  # Default 32mm height for collision calculation
	var use_glb_model = false

	if not model_path.is_empty():
		# Bundled res:// GLBs load via ResourceLoader; downloaded user:// GLBs via glTF.
		var glb_instance = _instantiate_model(model_path)
		if glb_instance:
			# Fit the model to its base (footprint cap against scale-creep; Flying hovers)
			var aabb = _get_model_aabb(glb_instance)
			var tough = _get_tough_value(unit)
			var fit = _compute_model_fit(aabb, natural_base_long_mm, tough, hover_lift, natural_base_short_mm, fit_to_base, _get_body_aabb(glb_instance))
			var final_scale = fit.scale

			glb_instance.scale = Vector3(final_scale, final_scale, final_scale)
			glb_instance.position.y = fit.y_offset
			# Orient on an oval base: walkers crosswise (quer), other vehicles along the long axis.
			_align_to_oval_long_axis(glb_instance, aabb, base_is_oval, base_width, base_depth, _is_walker(unit.name))

			if use_ctex:
				# Apply the offline-baked BC7 albedo onto the (texture-stripped) ctex mesh, then match
				# the legacy display treatment so ctex and legacy render identically (see
				# _brighten_ctex_materials): flat non-metallic diffuse + anisotropic filtering. The
				# multi-material form (I1) assigns per-surface albedo by index; both share the brighten.
				if ctex_paths.has("materials"):
					CtexLoader.apply_materials_to_mesh(glb_instance, ctex_paths["materials"])
				else:
					CtexLoader.apply_to_mesh(glb_instance, str(ctex_paths.get("albedo", "")),
						str(ctex_paths.get("normal", "")), str(ctex_paths.get("orm", "")), false)
				_brighten_ctex_materials(glb_instance)
			else:
				_brighten_trellis_materials(glb_instance)
			wrapper.add_child(glb_instance)
			use_glb_model = true
			model_height = fit.height

	# Fallback: Create placeholder body if no GLB model found
	if not use_glb_model:
		# Create placeholder body (cylinder) - moderately scaled to base size
		# Use sqrt for gentler scaling: 60mm base gets ~1.37x height, not 1.875x
		var scale_factor = sqrt(base_radius / 0.016)  # Gentler scaling
		var body_height = (0.025 + randf() * 0.005) * scale_factor
		var body_mesh = CylinderMesh.new()
		# Body width relative to base - slightly narrower for larger bases
		var body_width_ratio = lerp(0.5, 0.35, clampf((base_radius - 0.016) / 0.03, 0.0, 1.0))
		body_mesh.top_radius = base_radius * body_width_ratio
		body_mesh.bottom_radius = base_radius * (body_width_ratio + 0.1)
		body_mesh.height = body_height

		var body_instance = MeshInstance3D.new()
		body_instance.mesh = body_mesh
		body_instance.position.y = 0.003 + body_height / 2 + hover_lift

		var body_material = StandardMaterial3D.new()
		body_material.albedo_color = player_color.lightened(0.3)
		body_material.roughness = 0.8
		body_instance.material_override = body_material
		body_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		wrapper.add_child(body_instance)

		# Create head (sphere) - scaled to base size
		var head_radius = base_radius * 0.375
		var head_mesh = SphereMesh.new()
		head_mesh.radius = head_radius
		head_mesh.height = head_radius * 2

		var head_instance = MeshInstance3D.new()
		head_instance.mesh = head_mesh
		head_instance.position.y = 0.003 + body_height + head_radius + hover_lift

		var head_material = StandardMaterial3D.new()
		head_material.albedo_color = Color(0.9, 0.75, 0.6)  # Skin tone
		head_material.roughness = 0.9
		head_instance.material_override = head_material
		head_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		wrapper.add_child(head_instance)

		model_height = body_height + head_radius * 2 + hover_lift

	# Add collision shape - scaled to base size (box for square/rectangular regiment
	# bases so they sit edge-to-edge without overlap-reject; cylinder otherwise).
	var total_height = 0.003 + model_height
	var collision = CollisionShape3D.new()
	if unit.base_is_square:
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(base_width, total_height, base_depth)
		collision.shape = box_shape
	else:
		var collision_radius = max(base_width, base_depth) / 2.0 if base_is_oval else base_radius
		var shape = CylinderShape3D.new()
		shape.radius = collision_radius
		shape.height = total_height
		collision.shape = shape
	collision.position.y = total_height / 2
	wrapper.add_child(collision)

	# Add script for selection
	wrapper.set_script(load("res://scripts/selectable_object.gd"))

	return wrapper


## Create a visual model from saved unit_properties dictionary (for save/load)
## Uses the same visual logic as _create_unit_model() but reads from Dictionary instead of OPRUnit
func create_model_from_properties(props: Dictionary, model_tough: int = 0) -> StaticBody3D:
	var wrapper = StaticBody3D.new()
	wrapper.collision_layer = MINIATURE_COLLISION_LAYER
	wrapper.collision_mask = GROUND_COLLISION_LAYER
	var unit_name = props.get("name", "Unknown")
	var display_suffix = props.get("display_suffix", "")
	var display_name = unit_name + display_suffix
	wrapper.name = "OPR_%s" % display_name.replace(" ", "_")

	# Get base dimensions from saved properties
	var base_is_oval: bool = props.get("base_is_oval", false)
	var base_width: float = props.get("base_width_mm", 32) * 0.001
	var base_depth: float = props.get("base_depth_mm", 32) * 0.001
	var base_size_round: int = props.get("base_size_round", 32)
	var base_radius: float = (base_size_round / 2.0) * 0.001

	# Per-model base: re-derive the carrier model's bigger base from its synced per-model Tough
	# (never shrink). model_tough travels via model.properties["tough"] over save/load + MP sync.
	# Natural base = the saved OPR-suggested size; the model mesh is fitted to THIS, not to the
	# Tough-enlarged base (no scale creep). The enlarged base drives only ring/collision (+ tokens
	# and measuring, which re-derive it from Tough).
	var natural_base_long_mm: int = max(int(props.get("base_width_mm", 32)), int(props.get("base_depth_mm", 32))) if base_is_oval else base_size_round
	var natural_base_short_mm: int = min(int(props.get("base_width_mm", 32)), int(props.get("base_depth_mm", 32))) if base_is_oval else base_size_round
	var fit_to_base: bool = bool(props.get("base_from_tough", false))
	var base_long_mm: int = natural_base_long_mm
	var per_model_override_mm: int = model_base_long_mm(base_long_mm, model_tough)
	if per_model_override_mm > base_long_mm:
		var ratio := float(per_model_override_mm) / float(maxi(1, base_long_mm))
		base_long_mm = per_model_override_mm
		if base_is_oval:
			base_width = clampf(int(props.get("base_width_mm", 32)) * ratio, 20.0, 150.0) * 0.001
			base_depth = clampf(int(props.get("base_depth_mm", 32)) * ratio, 20.0, 150.0) * 0.001
		else:
			base_radius = (per_model_override_mm / 2.0) * 0.001
			base_width = per_model_override_mm * 0.001
			base_depth = per_model_override_mm * 0.001

	# Get player color
	var player_id: int = props.get("player_id", 1)
	var player_color: Color = OPRArmyManager.army_color(player_id, Color.GRAY)

	# Create base mesh
	var base_instance = MeshInstance3D.new()

	if base_is_oval:
		var base_mesh = CylinderMesh.new()
		base_mesh.top_radius = 0.5
		base_mesh.bottom_radius = 0.5
		base_mesh.height = 0.003
		base_instance.mesh = base_mesh
		base_instance.scale = Vector3(base_width, 1.0, base_depth)
		base_instance.position.y = 0.0015
	else:
		var base_mesh = CylinderMesh.new()
		base_mesh.top_radius = base_radius
		base_mesh.bottom_radius = base_radius
		base_mesh.height = 0.003
		base_instance.mesh = base_mesh
		base_instance.position.y = 0.0015

	var base_material = StandardMaterial3D.new()
	base_material.albedo_color = player_color
	base_material.roughness = 0.7
	base_instance.material_override = base_material
	base_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	wrapper.add_child(base_instance)

	# Visual hover: Flying units, drones and hover vehicles float above the base.
	# Hover height: Aircraft on a tall stand (~20cm), Flying/drones a small float (matches import).
	var hover_lift: float = _hover_lift_m(props.get("special_rules", []), unit_name, natural_base_long_mm)

	# Try to load GLB model for this unit (a mounted unit re-resolves its faction mount GLB so a
	# saved/synced Combat Bike hero keeps the bike model, matching the import path).
	var faction_folder: String = props.get("faction_folder", "")
	var glb_name: String = unit_name
	var saved_mount: String = str(props.get("mount_name", ""))
	if not saved_mount.is_empty():
		var mount_glb: String = _find_mount_glb_name(saved_mount, faction_folder)
		if not mount_glb.is_empty():
			glb_name = mount_glb
	var model_path = _find_model_for_unit(glb_name, faction_folder)
	var model_height: float = 0.032

	var use_glb_model = false
	if not model_path.is_empty():
		# Bundled res:// GLBs load via ResourceLoader; downloaded user:// GLBs via glTF.
		var glb_instance = _instantiate_model(model_path)
		if glb_instance:
			var aabb = _get_model_aabb(glb_instance)
			var tough = _get_tough_value_from_rules(props.get("special_rules", []))
			var fit = _compute_model_fit(aabb, natural_base_long_mm, tough, hover_lift, natural_base_short_mm, fit_to_base, _get_body_aabb(glb_instance))
			var final_scale = fit.scale

			glb_instance.scale = Vector3(final_scale, final_scale, final_scale)
			glb_instance.position.y = fit.y_offset
			# Orient on an oval base: walkers crosswise (quer), other vehicles along the long axis.
			_align_to_oval_long_axis(glb_instance, aabb, base_is_oval, base_width, base_depth, _is_walker(unit_name))

			_brighten_trellis_materials(glb_instance)
			wrapper.add_child(glb_instance)
			use_glb_model = true
			model_height = fit.height

	# Fallback: Create placeholder body if no GLB model found
	if not use_glb_model:
		var scale_factor = sqrt(base_radius / 0.016)
		var body_height = (0.025 + randf() * 0.005) * scale_factor
		var body_mesh = CylinderMesh.new()
		var body_width_ratio = lerp(0.5, 0.35, clampf((base_radius - 0.016) / 0.03, 0.0, 1.0))
		body_mesh.top_radius = base_radius * body_width_ratio
		body_mesh.bottom_radius = base_radius * (body_width_ratio + 0.1)
		body_mesh.height = body_height

		var body_instance = MeshInstance3D.new()
		body_instance.mesh = body_mesh
		body_instance.position.y = 0.003 + body_height / 2 + hover_lift

		var body_material = StandardMaterial3D.new()
		body_material.albedo_color = player_color.lightened(0.3)
		body_material.roughness = 0.8
		body_instance.material_override = body_material
		body_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		wrapper.add_child(body_instance)

		var head_radius = base_radius * 0.375
		var head_mesh = SphereMesh.new()
		head_mesh.radius = head_radius
		head_mesh.height = head_radius * 2

		var head_instance = MeshInstance3D.new()
		head_instance.mesh = head_mesh
		head_instance.position.y = 0.003 + body_height + head_radius + hover_lift

		var head_material = StandardMaterial3D.new()
		head_material.albedo_color = Color(0.9, 0.75, 0.6)
		head_material.roughness = 0.9
		head_instance.material_override = head_material
		head_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		wrapper.add_child(head_instance)

		model_height = body_height + head_radius * 2 + hover_lift

	# Add collision shape
	var collision_radius = max(base_width, base_depth) / 2.0 if base_is_oval else base_radius
	var total_height = 0.003 + model_height
	var collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = collision_radius
	shape.height = total_height
	collision.shape = shape
	collision.position.y = total_height / 2
	wrapper.add_child(collision)

	# Add script for selection and groups
	wrapper.set_script(load("res://scripts/selectable_object.gd"))
	wrapper.add_to_group("selectable")
	wrapper.add_to_group("miniature")
	wrapper.add_to_group("opr_unit")
	wrapper.add_to_group("unit")

	# Stamp the owner slot so the movement gate's fast key (opr_player_id meta) and slow
	# key (game_unit.player_id) agree for restored/remote-synced models too. ONLY when the
	# source actually specifies player_id: defaulting a missing key to the host (1) would
	# fail CLOSED — silently making a synced model host-owned and unselectable for its real
	# owner. Absent -> leave unstamped (gate falls back to the slow key / fails open).
	if props.has("player_id"):
		wrapper.set_meta("opr_player_id", player_id)

	return wrapper


## Extract Tough value from a special_rules array (for save/load)
func _get_tough_value_from_rules(rules: Array) -> int:
	for rule in rules:
		var rule_str = ""
		if rule is String:
			rule_str = rule
		elif rule is Dictionary:
			rule_str = rule.get("name", "")
		if rule_str.begins_with("Tough("):
			var value_str = rule_str.trim_prefix("Tough(").trim_suffix(")")
			if value_str.is_valid_int():
				return value_str.to_int()
	return 0


## Get unit data for a model
func get_unit_for_model(model: Node3D) -> OPRApiClient.OPRUnit:
	return model_to_unit.get(model, null)


## Get all models for a unit
func get_models_for_unit(unit: OPRApiClient.OPRUnit) -> Array:
	return unit_to_models.get(unit, [])


## Get army for a player
func get_army(player_id: int) -> OPRApiClient.OPRArmy:
	return armies.get(player_id, null)


## Look up an OPR special-rule description. Checks the session cache first (populated
## from save/load + multiplayer sync), then the in-memory imported armies. Handles
## parameterised rules ("Tough(3)" -> "Tough"). Returns "" if unknown.
func get_rule_description(rule_name: String) -> String:
	if rule_descriptions.has(rule_name):
		return rule_descriptions[rule_name]
	var paren := rule_name.find("(")
	if paren > 0:
		var base := rule_name.substr(0, paren).strip_edges()
		if rule_descriptions.has(base):
			return rule_descriptions[base]
	for army in armies.values():
		if army == null:
			continue
		var desc := OPRApiClient.get_rule_description(rule_name, army)
		if not desc.is_empty():
			return desc
	return ""


## All known rule descriptions (imported armies + session cache), for serialization
## into a save / the multiplayer state sync.
func get_all_rule_descriptions() -> Dictionary:
	var out: Dictionary = rule_descriptions.duplicate()
	for army in armies.values():
		if army and army.rule_descriptions is Dictionary:
			for k in army.rule_descriptions:
				out[k] = army.rule_descriptions[k]
	return out


## The faction's spell list for a caster unit (from its army), or [] if none. Falls back to the
## synced session cache keyed by player_id (guest/loaded units whose OPRArmy carries no spells).
func get_spells_for_unit(game_unit) -> Array:
	if game_unit == null or not (game_unit.unit_properties is Dictionary):
		return []
	var pid: int = int(game_unit.unit_properties.get("player_id", 0))
	var army = armies.get(pid, null)
	if army and "spells" in army and army.spells is Array and not army.spells.is_empty():
		return army.spells
	return _session_spells.get(pid, [])


## Special-rule names known this session that appear as a whole word in `text` — e.g. a spell
## whose effect grants "Shred". Lets a spell tooltip append the granted rule's full description
## after the spell text. Case-sensitive (rule names are capitalised); names < 4 chars are skipped
## to avoid noise (AP, etc.).
func rules_referenced_in(text: String) -> Array:
	var out: Array = []
	for name in get_all_rule_descriptions():
		var n: String = str(name)
		if n.length() < 4 or out.has(n):
			continue
		if _word_in(text, n):
			out.append(n)
	return out


func _word_in(haystack: String, needle: String) -> bool:
	var idx: int = haystack.find(needle)
	while idx >= 0:
		var before_ok: bool = idx == 0 or not _is_word_char(haystack[idx - 1])
		var after: int = idx + needle.length()
		var after_ok: bool = after >= haystack.length() or not _is_word_char(haystack[after])
		if before_ok and after_ok:
			return true
		idx = haystack.find(needle, idx + 1)
	return false


func _is_word_char(c: String) -> bool:
	return c.to_upper() != c.to_lower() or (c >= "0" and c <= "9")


## All players' spell lists, for the host's full-state sync to peers.
func get_all_player_spells() -> Dictionary:
	var out: Dictionary = _session_spells.duplicate(true)
	for pid in armies:
		var army = armies[pid]
		if army and "spells" in army and army.spells is Array and not army.spells.is_empty():
			out[pid] = army.spells
	return out


## Merge incoming per-player spell lists (from a save or a peer's state sync).
func merge_player_spells(incoming: Dictionary) -> void:
	for pid in incoming:
		if incoming[pid] is Array and not incoming[pid].is_empty():
			_session_spells[int(pid)] = incoming[pid]


## Merge incoming rule descriptions (from a loaded save or a peer's state sync) into
## the session cache, so loaded/remote units can resolve descriptions too.
func merge_rule_descriptions(incoming: Dictionary) -> void:
	for k in incoming:
		rule_descriptions[k] = incoming[k]


# ===== Auto buff-tokens from special rules =====

## Curated OPR special-rule -> buff-token map. Only rules a player wants to TRACK on the table
## (auras / situational / re-rolls). hex = token colour; counter = tracked number vs on/off.
## The effect falls back to this text when the synced rule_description is missing.
const BUFF_TOKEN_RULES := {
	"Furious":    {"hex": "e81828", "counter": false, "effect": "Extra hits on charge"},
	"Relentless": {"hex": "d4af37", "counter": false, "effect": "Keep shooting after activating"},
	"Stealth":    {"hex": "1a7d4d", "counter": false, "effect": "-1 to be hit from over 12\""},
	"Poison":     {"hex": "7030a0", "counter": false, "effect": "Re-roll wound rolls"},
	"Resilient":  {"hex": "70ad47", "counter": false, "effect": "Re-roll failed defense"},
	"Bloodborn":  {"hex": "8b0000", "counter": false, "effect": "Heals after kills"},
	"Fear":       {"hex": "5b2c8a", "counter": true,  "effect": "Counts as extra models for morale"},
}

## Passive / always-on rules that should NOT spawn a token (avoid palette spam). Caster has its
## own dedicated marker, so it is excluded here too.
const PASSIVE_BUFF_RULES := ["Tough", "Fearless", "Fast", "Slow", "Strider", "Hero", "Flying",
	"Hover", "Impact", "Parry", "Regeneration", "Caster", "Scout", "Ambush", "Mobile Artillery",
	"Hold the Line"]

## Pure: derive the buff tokens to auto-create from a unit/army's special_rules. A rule qualifies
## when it is in the curated map, OR its name reads like an aura/buff, OR its description grants a
## +1/-1/re-roll — and it is not passive. Numbered rules ("Fear(2)") collapse to their base name.
## rule_desc supplies effect text (the synced OPR rule descriptions). Deduped by base name.
static func buff_tokens_from_rules(special_rules: Array, rule_desc: Dictionary = {}) -> Array:
	var out: Array = []
	var seen := {}
	for raw in special_rules:
		var name := str(raw)
		var base := name
		var paren := base.find("(")
		if paren > 0:
			base = base.substr(0, paren)
		base = base.strip_edges()
		if base.is_empty() or seen.has(base) or base in PASSIVE_BUFF_RULES:
			continue
		var desc := str(rule_desc.get(base, rule_desc.get(name, "")))
		var dlow := desc.to_lower()
		var blow := base.to_lower()
		var mapped: Dictionary = BUFF_TOKEN_RULES.get(base, {})
		var qualifies := not mapped.is_empty() \
			or "aura" in blow or "buff" in blow \
			or "+1" in desc or "-1" in desc or "re-roll" in dlow or "reroll" in dlow
		if not qualifies:
			continue
		seen[base] = true
		var hex := str(mapped.get("hex", "c8a02a" if "aura" in blow else "8aa0b8"))
		var effect := desc if not desc.is_empty() else str(mapped.get("effect", ""))
		out.append({
			"name": base,
			"color": Color.html(hex),
			"is_counter": bool(mapped.get("counter", false)),
			"effect": effect,
		})
	return out


# ===== NEW: GameUnit Access Methods =====

## Get GameUnit for an OPRUnit
func get_game_unit(opr_unit: OPRApiClient.OPRUnit) -> GameUnit:
	return unit_to_game_unit.get(opr_unit, null)


## Get GameUnit by unit_id
func get_game_unit_by_id(unit_id: String) -> GameUnit:
	return game_units.get(unit_id, null)


## Get all GameUnits for a player
func get_game_units_for_player(player_id: int) -> Array[GameUnit]:
	var result: Array[GameUnit] = []
	for game_unit in game_units.values():
		if game_unit.unit_properties.get("player_id", 0) == player_id:
			result.append(game_unit)
	return result


## Get all GameUnits
func get_all_game_units() -> Array[GameUnit]:
	var result: Array[GameUnit] = []
	for game_unit in game_units.values():
		result.append(game_unit)
	return result


## Check if a node is a unit model
func is_unit_model(node: Node3D) -> bool:
	return node.is_in_group("unit") or node.is_in_group("opr_unit")


# ===== Hero Attachment =====

## Returns the units ordered so each joined Hero comes right after its host unit
## (matched by selectionId). Heroes whose host is missing keep their place.
func _order_units_heroes_after_host(units: Array) -> Array:
	var heroes_by_host: Dictionary = {}
	for unit in units:
		if not unit.join_to_unit.is_empty():
			if not heroes_by_host.has(unit.join_to_unit):
				heroes_by_host[unit.join_to_unit] = []
			heroes_by_host[unit.join_to_unit].append(unit)

	var ordered: Array = []
	for unit in units:
		if not unit.join_to_unit.is_empty():
			continue  # placed right after its host below
		ordered.append(unit)
		if heroes_by_host.has(unit.selection_id):
			for hero in heroes_by_host[unit.selection_id]:
				ordered.append(hero)

	# Heroes whose host was not found must not be dropped - append them.
	for unit in units:
		if not unit.join_to_unit.is_empty() and unit not in ordered:
			ordered.append(unit)

	return ordered


## Attaches joined Heroes to their host units after spawning.
## OPR: a Hero unit can be "joined to" another unit (Army Forge sets the Hero's
## joinToUnit to the host's selectionId). Combined-unit halves were already merged
## away during parsing, so the remaining units carrying join_to_unit are Heroes.
func _attach_joined_heroes(army: OPRApiClient.OPRArmy) -> void:
	# Index every unit's GameUnit by its selectionId.
	var by_selection: Dictionary = {}
	for unit in army.units:
		var game_unit: GameUnit = unit_to_game_unit.get(unit)
		if game_unit and not unit.selection_id.is_empty():
			by_selection[unit.selection_id] = game_unit

	for unit in army.units:
		if unit.join_to_unit.is_empty():
			continue
		var hero_unit: GameUnit = unit_to_game_unit.get(unit)
		var host_unit: GameUnit = by_selection.get(unit.join_to_unit)
		if hero_unit and host_unit and hero_unit != host_unit:
			EquipmentDistributor.attach_hero_to_unit(hero_unit, host_unit)


# ===== Round Management =====

## Advances to the next game round (OPR round transition - pure bookkeeping):
## every unit may activate again and casters gain their per-round points (capped).
## The players, not the app, decide when to call this.
func advance_round() -> void:
	current_round += 1
	for game_unit in game_units.values():
		if game_unit:
			game_unit.reset_activation()
			game_unit.add_round_caster_points()
	round_advanced.emit(current_round)


## Sets the current round (used by save/load restore).
func set_current_round(value: int) -> void:
	current_round = maxi(1, value)


## Clear all armies and spawned models
func clear_all() -> void:
	# Remove all spawned models. Guard against double-free: ObjectManager.
	# clear_all_objects() may have already queued these (the models are its
	# children) before delegating here.
	for unit in unit_to_models:
		var models = unit_to_models[unit]
		for model in models:
			if is_instance_valid(model) and not model.is_queued_for_deletion():
				model.queue_free()

	# Remove all army trays
	for player_id in army_trays:
		if is_instance_valid(army_trays[player_id]) and not army_trays[player_id].is_queued_for_deletion():
			army_trays[player_id].queue_free()

	armies.clear()
	model_to_unit.clear()
	unit_to_models.clear()
	unit_to_game_unit.clear()
	game_units.clear()
	army_trays.clear()
	_scene_cache.clear()  # release parsed PackedScenes; rebuilt lazily on next spawn
	current_round = 1


## Clear army for a specific player
func clear_army(player_id: int) -> void:
	var army = armies.get(player_id)
	if not army:
		return

	for unit in army.units:
		# Clear GameUnit mappings
		if unit in unit_to_game_unit:
			var game_unit = unit_to_game_unit[unit]
			game_units.erase(game_unit.unit_id)
			unit_to_game_unit.erase(unit)

		if unit in unit_to_models:
			var models = unit_to_models[unit]
			for model in models:
				if is_instance_valid(model):
					model.queue_free()
				model_to_unit.erase(model)
			unit_to_models.erase(unit)

	# Remove the army tray for this player (its band tints/divider/labels are children → freed with it).
	if army_trays.has(player_id) and is_instance_valid(army_trays[player_id]):
		army_trays[player_id].queue_free()
		army_trays.erase(player_id)

	armies.erase(player_id)


# ===== GLB Model Loading Functions =====

## Downloads any on-demand models the army needs (manifest + CDN) so the spawn
## loop can resolve them from the local cache. No-op without a populated manifest.
func _ensure_army_models_cached(army: OPRApiClient.OPRArmy) -> void:
	if model_library == null or army == null:
		return
	var faction_folder: String = army.faction_folder
	if faction_folder.is_empty():
		return
	var specs: Array = []
	var seen: Dictionary = {}   # unit_name -> true; dedup across units (3 identical squads share keys)
	for unit: OPRApiClient.OPRUnit in army.units:
		# Base + each model's loadout variant (009: variants MUST be prefetched, else they are derived
		# at spawn but never downloaded → "No model found" pegs) + the mount GLB.
		var mount_glb: String = _find_mount_glb_name(unit.mount_name, faction_folder) if not unit.mount_name.is_empty() else ""
		for n in _collect_prefetch_names(unit.name, _unit_model_variant_names(unit, faction_folder), mount_glb):
			if not seen.has(n):
				seen[n] = true
				specs.append({"faction": faction_folder, "unit_name": n})
	await model_library.ensure_models(specs)


## Instantiates a model from a local path, reusing a per-path PackedScene so each
## distinct model is parsed once. Bundled res:// GLBs load via ResourceLoader;
## downloaded user:// GLBs are parsed once via runtime glTF (GLTFDocument) and packed.
func _instantiate_model(path: String) -> Node3D:
	var packed: PackedScene = _scene_cache.get(path, null)
	if packed == null:
		packed = _load_model_scene(path)
		if packed == null:
			return null
		_scene_cache[path] = packed
	return packed.instantiate() as Node3D


## Loads a model path into a reusable PackedScene (no caching/instancing here).
func _load_model_scene(path: String) -> PackedScene:
	if path.begins_with("res://"):
		return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene

	# Runtime glTF for downloaded user:// GLBs: parse once, then pack so subsequent
	# spawns instance instead of re-parsing.
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	var scene_root := doc.generate_scene(state)
	if scene_root == null:
		return null
	# pack() only stores descendants whose owner is the packed root.
	_set_owner_recursive(scene_root, scene_root)
	var packed := PackedScene.new()
	var ok := packed.pack(scene_root)
	scene_root.free()
	return packed if ok == OK else null


func _set_owner_recursive(node: Node, scene_owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = scene_owner
		_set_owner_recursive(child, scene_owner)


## Resolve a model's pre-baked loadout variant name `<base>#<slug>` from its distributed loadout
## labels (I2), or "" to use the base model. Returns the variant ONLY when the manifest actually has
## that key — otherwise "" so the caller falls back to the base unit model (never a missing lookup).
func _resolve_model_variant_name(base_name: String, labels: Array, faction_folder: String) -> String:
	if model_library == null:
		return ""
	var slug: String = model_library.variant_slug(labels)
	if slug.is_empty():
		return ""
	var variant: String = "%s#%s" % [base_name, slug]
	return variant if model_library.has_model(faction_folder, variant) else ""


## Per-model resolved variant model name ("" = base) for a unit — the SINGLE derivation shared by the
## prefetch spec builder AND the spawn loop, so every variant a unit needs is DOWNLOADED, not just
## derived at spawn (009). Length == unit.size.
func _unit_model_variant_names(unit, faction_folder: String) -> Array:
	var loadout := EquipmentDistributor.build_loadout(unit)
	var labels := EquipmentDistributor.per_model_labels(unit.size, loadout)
	var out: Array = []
	for i in range(unit.size):
		out.append(_resolve_model_variant_name(unit.name, labels[i], faction_folder))
	return out


## Deduplicated prefetch names for a unit: the base model + each distinct NON-EMPTY variant + the
## mount. Pure/static → unit-testable (009: variants MUST be prefetched, deduped so N identical variant
## models don't queue the same key N×). Empty entries (base-fallback models) are dropped.
static func _collect_prefetch_names(base_name: String, variant_names: Array, mount_name: String) -> Array:
	var candidates: Array = [base_name]
	candidates.append_array(variant_names)
	if not mount_name.is_empty():
		candidates.append(mount_name)
	var out: Array = []
	var seen: Dictionary = {}
	for n in candidates:
		var s: String = str(n)
		if not s.is_empty() and not seen.has(s):
			seen[s] = true
			out.append(s)
	return out


## Find the GLB model for a unit. Prefers an on-demand model already cached locally
## (manifest + CDN), then falls back to a bundled GLB probed by name. OPR unit data
## (incl. names) comes exclusively from the API at runtime.
func _find_model_for_unit(unit_name: String, faction_folder: String) -> String:
	if faction_folder.is_empty():
		return ""

	# On-demand model already downloaded? (manifest-driven, content-addressed cache)
	if model_library != null:
		var cached: String = model_library.get_cached_path(faction_folder, unit_name)
		if not cached.is_empty():
			return cached

	# Probe bundled GLBs by name with ResourceLoader.exists() (works in exports).
	var glb_base_path = "res://assets/miniatures/%s/glb/" % faction_folder

	# Try numbered prefixes 01-99
	for i in range(1, 100):
		var prefix = "%02d" % i
		var glb_filename = "%s_%s.glb" % [prefix, unit_name]
		var full_path = glb_base_path + glb_filename

		if ResourceLoader.exists(full_path):
			print("OPRArmyManager: Found model for '%s' -> %s (fallback)" % [unit_name, full_path])
			return full_path

	# Also try without prefix (in case naming convention changes)
	var direct_path = glb_base_path + unit_name + ".glb"
	if ResourceLoader.exists(direct_path):
		print("OPRArmyManager: Found model for '%s' -> %s (direct)" % [unit_name, direct_path])
		return direct_path

	print("OPRArmyManager: No model found for '%s' in %s" % [unit_name, faction_folder])
	return ""


## OPR mount/vehicle upgrades whose name carries one of these words map to a faction GLB containing
## that word (fuzzy). Dedicated per-mount models are a Model Forge follow-up.
const MOUNT_KEYWORDS: Array[String] = ["bike", "jetbike", "mount", "steed", "horse", "chariot",
	"cavalry", "disc", "drake", "wyvern", "hover", "speeder", "beast", "sled", "raptor", "carnosaur",
	"dino", "dinosaur", "lizard", "saurus", "serpent", "dragon", "monster"]


## The faction GLB name for a unit's mount/vehicle upgrade, fuzzy-matched from the mount name's
## recognizable words (e.g. "Combat Bike" -> a faction "*bike*" model). "" -> keep the foot model.
func _find_mount_glb_name(mount_name: String, faction_folder: String) -> String:
	if model_library == null or mount_name.is_empty() or faction_folder.is_empty():
		return ""
	var kws: Array = []
	for w in mount_name.to_lower().split(" ", false):
		if w in MOUNT_KEYWORDS:
			kws.append(w)
	if kws.is_empty():
		return ""
	return model_library.find_faction_model_matching(faction_folder, kws)


## Extract Tough value from unit's special rules
## Returns 0 if no Tough rule found
func _get_tough_value(unit: OPRApiClient.OPRUnit) -> int:
	return _get_tough_value_from_rules(unit.special_rules)


## Calculate model scale based on Tough value
## Formula: scale = 1.05^(tough/3)
## Tough(0)=1.0, Tough(3)=1.05, Tough(6)=1.10, Tough(12)=1.22
func _calculate_model_scale(tough: int) -> float:
	return pow(1.05, tough / 3.0)


## True if the rules contain "Flying" (or Flying(x)).
func _is_flying_from_rules(rules: Array) -> bool:
	for r in rules:
		if String(r).strip_edges().to_lower().begins_with("flying"):
			return true
	return false


## True if a unit has the OPR "Aircraft" rule. NOT the same as Flying (aircraft must move every turn,
## can't be charged, etc.) — it drives the tall flight-stand hover, not the small Flying float.
func _is_aircraft_from_rules(rules: Array) -> bool:
	for r in rules:
		if String(r).strip_edges().to_lower().begins_with("aircraft"):
			return true
	return false


## Visual hover height (m): a fixed tall stand for Aircraft, a small base-relative float for Flying /
## drones / hover vehicles, else 0 (on the table). Single source of truth for the GLB fit, the
## procedural fallback and the save/load rebuild.
func _hover_lift_m(rules: Array, unit_name: String, base_long_mm: int) -> float:
	if _is_aircraft_from_rules(rules):
		return AIRCRAFT_HOVER_M
	if _should_hover(unit_name, rules):
		return base_long_mm * FLYING_HOVER_RATIO * 0.001
	return 0.0


## True if a unit should visually hover above its base: it has the Flying rule,
## or its name marks it as a drone / hover vehicle (e.g. "Gun Drones", "Hover
## Tank"). Hover is cosmetic only - in this sim Flying has no other effect since
## coherency reads the model wrapper at table level, not the rule.
func _should_hover(unit_name: String, rules: Array) -> bool:
	if _is_flying_from_rules(rules):
		return true
	var lowered := unit_name.to_lower()
	return "drone" in lowered or "hover" in lowered


## Orients a GLB on an OVAL base relative to the base's long axis (depth/Z when base_depth >=
## base_width). Y-only rotation, so it leaves the (rotation-invariant) uniform scale and y-offset
## intact. No-op for round/square bases.
##
## Vehicles (cross_align=false): align the model's LONGER horizontal axis ALONG the base's long
## axis (a tank runs front-to-back down its oval). This uses the AABB, which is reliable for a
## tank-shaped hull.
##
## Walkers (cross_align=true): sit CROSSWISE ("quer") — DETERMINISTICALLY, ignoring the AABB. A
## biped's footprint is near-square (e.g. 0.672 x 0.642), so the AABB "long axis" is just noise
## that rotated identical walkers inconsistently. Instead we orient the model's default forward
## (+Z) ACROSS the base's long axis purely from the base geometry, so every walker is consistent.
## (Near-square means the exact facing barely shows; if it ever reads 90° off, flip the rotate.)
func _align_to_oval_long_axis(glb: Node3D, _aabb: AABB, base_is_oval: bool,
		base_width: float, base_depth: float, cross_align: bool = false) -> void:
	if not base_is_oval or glb == null:
		return
	# Deterministic from the base geometry (model forward = +Z): a WALKER faces ACROSS the base's
	# long axis (its +Z onto the SHORT side), a VEHICLE runs ALONG it (its +Z onto the LONG side) —
	# exact opposites. The AABB is ignored on purpose: a near-square hull has no reliable long axis,
	# and AABB-based turns rotated identical models inconsistently (same reason walkers are
	# deterministic).
	var base_long_is_z: bool = base_depth >= base_width
	var turn: bool = base_long_is_z if cross_align else not base_long_is_z
	if turn:
		glb.rotate_y(PI / 2.0)


## A walker unit (named "… Walker") sits crosswise ("quer") on its oval base instead of aligned
## to the long axis, so a biped faces forward rather than lying down the length of the base.
func _is_walker(unit_name: String) -> bool:
	return "walker" in unit_name.to_lower()


## Computes scale + vertical offset so a GLB fits its base nicely.
##
## Rule against scale-creep:
##   - height target ~ base size (Tough makes it slightly taller) -> slim bipeds.
##   - footprint cap: largest horizontal extent <= 125% of the base long side
##     (oval: the long axis) -> wide vehicles/drones don't spill over.
##   - the SMALLER of the two factors wins (min), so both constraints hold.
## Flying units hover slightly above the base.
## base_long_mm = base long side in mm (round: diameter; oval: longer axis).
## Returns { "scale": float, "y_offset": float, "height": float }.
func _compute_model_fit(aabb: AABB, base_long_mm: int, tough: int, hover_lift_m: float, base_short_mm: int = -1, fit_to_base: bool = false, body_aabb: AABB = AABB()) -> Dictionary:
	# Contract v1.2: when the GLB carries a named `body` node, HEIGHT and GROUNDING measure that node's
	# box (body_aabb) so composed parts (a banner pole, a downward-held bow) can't shrink the body or lift
	# it off the base; the COMBINED aabb still drives the horizontal footprint/base-fit cap. Empty
	# body_aabb (legacy single-mesh models) → measure everything from the combined aabb, unchanged.
	var fit_aabb: AABB = body_aabb if body_aabb.size.y > 0.0 else aabb
	var raw_height: float = fit_aabb.size.y
	var raw_footprint: float = max(aabb.size.x, aabb.size.z)
	if raw_height <= 0.0 or raw_footprint <= 0.0:
		return {"scale": 0.001, "y_offset": 0.003, "height": 0.03}

	# Height target: 25mm bases get +3mm, otherwise = base; Tough scales it mildly.
	var height_target_mm: float = float(base_long_mm + 3 if base_long_mm <= 25 else base_long_mm)
	var target_height_m: float = height_target_mm * 0.001 * _calculate_model_scale(tough)
	var height_scale: float = target_height_m / raw_height

	# Footprint cap. Round base: cap to base_long x FOOTPRINT_MAX_RATIO (organic overhang ok).
	# Oval/rectangular base (base_short < base_long): fit WITHIN BOTH axes at OVAL_FOOTPRINT_RATIO, so
	# a wide/square hull can't overhang the narrow side (the vehicle scale-creep). Uniform scale, so
	# the tighter axis wins; raw_footprint = the model's longer horizontal side, raw_short the shorter.
	var short_mm: int = base_short_mm if base_short_mm > 0 else base_long_mm
	var footprint_scale: float
	if short_mm < base_long_mm:
		var raw_short: float = max(0.001, min(aabb.size.x, aabb.size.z))
		footprint_scale = min(
			base_long_mm * OVAL_FOOTPRINT_RATIO * 0.001 / raw_footprint,
			short_mm * OVAL_FOOTPRINT_RATIO * 0.001 / raw_short)
	else:
		# Round base: organic infantry may overhang (FOOTPRINT_MAX_RATIO). A Tough-derived
		# vehicle/monster base (fit_to_base, no Army Forge recommendation) IS the intended footprint,
		# so fill it exactly — no overhang.
		var round_ratio: float = 1.0 if fit_to_base else FOOTPRINT_MAX_RATIO
		footprint_scale = base_long_mm * round_ratio * 0.001 / raw_footprint

	var final_scale: float = min(height_scale, footprint_scale)

	# Feet on the base top (the base is 3mm tall); Flying/Aircraft additionally hover (caller-supplied).
	# Ground on the BODY's minimum-y (fit_aabb) so a below-feet part can't float the model.
	var lift: float = hover_lift_m
	var y_offset: float = -fit_aabb.position.y * final_scale + 0.003 + lift

	return {
		"scale": final_scale,
		"y_offset": y_offset,
		"height": raw_height * final_scale + lift,
	}


## Calculate the combined AABB (bounding box) of a 3D model and all its children
func _get_model_aabb(node: Node3D) -> AABB:
	var combined_aabb = AABB()
	var first = true

	# Recursively collect AABBs from all MeshInstance3D children
	var nodes_to_check: Array[Node] = [node]
	while not nodes_to_check.is_empty():
		var current = nodes_to_check.pop_back()
		nodes_to_check.append_array(current.get_children())

		if current is MeshInstance3D:
			var mesh_instance = current as MeshInstance3D
			if mesh_instance.mesh:
				var mesh_aabb = mesh_instance.mesh.get_aabb()
				# Transform AABB to node's local space
				var transformed_aabb = mesh_instance.transform * mesh_aabb
				if first:
					combined_aabb = transformed_aabb
					first = false
				else:
					combined_aabb = combined_aabb.merge(transformed_aabb)

	return combined_aabb


## The AABB of the named `body` node (contract v1.2), in `node`'s local space, or an EMPTY AABB when the
## GLB has no body node (the 1014 legacy single-mesh models — caller then measures the combined aabb).
## Model Forge re-bakes composed units with a `body` node so height + grounding ignore attached parts.
func _get_body_aabb(node: Node3D) -> AABB:
	var body := _find_body_node(node)
	if body == null:
		return AABB()
	var combined := AABB()
	var first := true
	var stack: Array[Node] = [body]
	while not stack.is_empty():
		var current = stack.pop_back()
		stack.append_array(current.get_children())
		if current is MeshInstance3D and (current as MeshInstance3D).mesh:
			var mi := current as MeshInstance3D
			var box: AABB = _relative_transform(mi, node) * mi.mesh.get_aabb()
			if first:
				combined = box
				first = false
			else:
				combined = combined.merge(box)
	return combined


## First descendant Node3D named "body" (case-insensitive), or null.
func _find_body_node(node: Node) -> Node3D:
	if node is Node3D and node.name.to_lower() == "body":
		return node
	for child in node.get_children():
		var found := _find_body_node(child)
		if found != null:
			return found
	return null


## Transform composing local transforms from `from_node` up to (excluding) `ancestor`, so a mesh nested
## under the body node is expressed in the model root's space without needing valid global transforms.
func _relative_transform(from_node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = from_node
	while n != null and n != ancestor:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Adjust Trellis-generated GLB materials for better visibility
## Trellis bakes very dark textures — subtle emission + roughness fix compensates
func _brighten_trellis_materials(node: Node) -> void:
	var nodes_to_check: Array[Node] = [node]
	while not nodes_to_check.is_empty():
		var current = nodes_to_check.pop_back()
		nodes_to_check.append_array(current.get_children())

		if current is MeshInstance3D:
			var mesh_instance = current as MeshInstance3D
			if not mesh_instance.mesh:
				continue
			for surface_idx in range(mesh_instance.mesh.get_surface_count()):
				var mat = mesh_instance.mesh.surface_get_material(surface_idx)
				if mat is StandardMaterial3D:
					var adjusted_mat = mat.duplicate() as StandardMaterial3D
					# Force non-metallic so ambient/fill light works as diffuse
					adjusted_mat.metallic = 0.0
					adjusted_mat.roughness = 0.7
					# Crisp models up close: anisotropic mipmap filtering, and
					# regenerate mipmaps for runtime GLTF textures, which Godot loads
					# without a mip chain (godotengine/godot#100481) so they shimmer
					# and alias on small minis.
					adjusted_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
					adjusted_mat.albedo_texture = _ensure_texture_mipmaps(adjusted_mat.albedo_texture)
					adjusted_mat.normal_texture = _ensure_texture_mipmaps(adjusted_mat.normal_texture)
					adjusted_mat.roughness_texture = _ensure_texture_mipmaps(adjusted_mat.roughness_texture)
					adjusted_mat.emission_texture = _ensure_texture_mipmaps(adjusted_mat.emission_texture)
					adjusted_mat.ao_texture = _ensure_texture_mipmaps(adjusted_mat.ao_texture)
					mesh_instance.mesh.surface_set_material(surface_idx, adjusted_mat)


## Match the legacy _brighten_trellis_materials look on a ctex model (E1/E2). The game renders the
## TRELLIS-baked albedo as FLAT DIFFUSE (metallic 0, roughness 0.7) — there are no reflection probes,
## so an ORM-driven metallic surface renders dark, and this batch's ORM metal channel additionally
## produced black hull blotches on vehicles. So we force the same non-metallic diffuse the legacy path
## uses and drop the ORM metallic/roughness textures, plus anisotropic filtering for crisp small minis.
## Operates only on the surface OVERRIDE materials CtexLoader.apply_to_mesh set — never the .ctex data.
func _brighten_ctex_materials(node: Node) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for surface_idx in range(mi.mesh.get_surface_count()):
			var mat := mi.get_surface_override_material(surface_idx) as StandardMaterial3D
			if mat == null:
				continue
			mat.metallic = 0.0
			mat.metallic_texture = null
			mat.roughness = 0.7
			mat.roughness_texture = null
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


## Returns a copy of [param tex] with a generated mipmap chain, for runtime GLTF
## textures that Godot loads without mipmaps (godotengine/godot#100481). Returns the
## texture unchanged when it already has mipmaps, is empty, or is GPU-compressed
## (mipmaps cannot be generated on compressed data).
func _ensure_texture_mipmaps(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.has_mipmaps() or img.is_compressed():
		return tex
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _on_army_loaded(army: OPRApiClient.OPRArmy) -> void:
	print("Army loaded: %s (faction: %s)" % [army.name, army.faction_name])


func _on_import_failed(error: String) -> void:
	push_error("OPR Import failed: %s" % error)
