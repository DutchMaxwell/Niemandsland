extends Node
class_name RadialMenuController
## Controller that manages the radial menu integration with the game.
## Handles context detection, menu opening, and action execution.

signal unit_activated(game_unit: GameUnit)
signal unit_deactivated(game_unit: GameUnit)
signal model_deleted(model_instance: ModelInstance)
signal unit_deleted(game_unit: GameUnit)

## Reference to the radial menu UI
var radial_menu: RadialMenu = null

## Reference to the object manager for selection info
var object_manager: Node = null

## Reference to the undo/redo history (injected by main.gd)
var undo_manager: UndoManager = null

## Reference to the OPR army manager
var army_manager: OPRArmyManager = null

## Reference to OPR stats tooltip
var stats_tooltip: Node = null

## Reference to coherency visualizer
var coherency_visualizer: CoherencyVisualizer = null

## Reference to unit boundary visualizer (for unit-wide tokens)
var boundary_visualizer: Node3D = null:  # UnitBoundaryVisualizer
	set(value):
		if boundary_visualizer and boundary_visualizer.has_signal("boundary_updated"):
			if boundary_visualizer.is_connected("boundary_updated", _on_boundary_updated):
				boundary_visualizer.disconnect("boundary_updated", _on_boundary_updated)
		if boundary_visualizer and boundary_visualizer.has_signal("boundary_lost"):
			if boundary_visualizer.is_connected("boundary_lost", _on_boundary_lost):
				boundary_visualizer.disconnect("boundary_lost", _on_boundary_lost)
		if boundary_visualizer and boundary_visualizer.has_signal("boundary_gained"):
			if boundary_visualizer.is_connected("boundary_gained", _on_boundary_gained):
				boundary_visualizer.disconnect("boundary_gained", _on_boundary_gained)
		boundary_visualizer = value
		if boundary_visualizer and boundary_visualizer.has_signal("boundary_updated"):
			boundary_visualizer.connect("boundary_updated", _on_boundary_updated)
		if boundary_visualizer and boundary_visualizer.has_signal("boundary_lost"):
			boundary_visualizer.connect("boundary_lost", _on_boundary_lost)
		if boundary_visualizer and boundary_visualizer.has_signal("boundary_gained"):
			boundary_visualizer.connect("boundary_gained", _on_boundary_gained)

## Reference to wounds dialog
var wounds_dialog: WoundsDialog = null

## Reference to casts dialog
var casts_dialog: CastsDialog = null

## Reference to model info popup
var model_info_popup: ModelInfoPopup = null

## Reference to marker dialog
var marker_dialog: MarkerDialog = null

## Reference to network manager for broadcasting state changes
var network_manager: Node = null

## Reference to the terrain overlay (for objective capture / recolor)
var terrain_overlay: Node = null

## Reusable library of user-defined custom tokens (color/effect/is_counter,
## keyed by name). Source of truth for custom-token color + effect.
var token_library := TokenLibrary.new()

## Display names for the player-owner choices in the objective capture menu,
## matching OPRArmyManager.PLAYER_COLORS.
const PLAYER_COLOR_NAMES := {1: "Blue", 2: "Red", 3: "Green", 4: "Gold"}

## Current selection context
var _current_selection: Array = []

## Is the radial menu scene loaded
var _menu_scene: PackedScene = null

## Lazily-loaded font shared by the curved arc labels (see ARC_FONT_PATH).
var _arc_font: Font = null

## Runtime token configs for dialog markers (node_name -> {color, label, letter,
## priority}). Lets arbitrary MarkerDialog markers reuse the same token engine as
## the built-in TOKEN_TYPES without hardcoding them.
var _dynamic_token_configs: Dictionary = {}

## Priority for dialog marker tokens - placed after the built-in status tokens.
const MARKER_TOKEN_PRIORITY := 100

## Special-weapon ring: an automatic per-model flat base ring + curved label
## naming the weapons that deviate from the unit's standard loadout (e.g.
## "Shredding Gun + Gauntlets"). Derived from loadout data, so no flag/save/MP.
## The ring uses the base/player colour (see _unit_base_color).
const SPECIAL_WEAPON_RING_NODE := "SpecialWeaponRing"

## Token layout constants
const TOKEN_RADIUS = 0.010  # 10mm radius = 20mm diameter disc
const TOKEN_HEIGHT = 0.003  # 3mm thick
const TOKEN_GAP = 0.001  # 1mm gap between tokens

## Token type definitions with colors and labels
const TOKEN_TYPES = {
	"WoundMarker": {"color": Color(0.9, 0.15, 0.15), "label": "WOUNDS", "letter": "W", "priority": 1},
	"CasterMarker": {"color": Color(0.6, 0.3, 0.9), "label": "CASTS", "letter": "C", "priority": 2},
	"ShakenMarker": {"color": Color(0.3, 0.5, 0.9), "label": "SHAKEN", "letter": "S", "priority": 3},
	"FatiguedMarker": {"color": Color(0.85, 0.45, 0.1), "label": "FATIGUED", "letter": "F", "priority": 4},
	"ActivatedMarker": {"color": Color(0.1, 0.5, 0.2), "label": "ACTIVATED", "letter": "A", "priority": 5},
}

## Curved token/weapon labels are measured AND rendered with this font so the
## per-glyph spacing matches; the spacing factor adds air for the arc rotation.
const ARC_FONT_PATH := "res://assets/ui_glassmorphism/fonts/Inter.ttf"
const ARC_LETTER_SPACING := 1.15


func _ready() -> void:
	# Preload the menu scene
	_menu_scene = load("res://scenes/radial_menu.tscn")


## Initializes the controller with required references.
func initialize(p_object_manager: Node, p_army_manager: OPRArmyManager) -> void:
	object_manager = p_object_manager
	army_manager = p_army_manager

	# Create radial menu instance if not exists
	# Get UI CanvasLayer (node is named "UI")
	var ui_layer = get_tree().root.find_child("UI", true, false)
	var ui_parent = ui_layer if ui_layer else get_tree().root

	if not radial_menu:
		radial_menu = _menu_scene.instantiate() as RadialMenu
		ui_parent.add_child(radial_menu)
		radial_menu.action_selected.connect(_on_action_selected)

	# Create wounds dialog
	if not wounds_dialog:
		wounds_dialog = WoundsDialog.create_simple()
		ui_parent.add_child(wounds_dialog)
		wounds_dialog.wounds_changed.connect(_on_wounds_changed)

	# Create casts dialog
	if not casts_dialog:
		casts_dialog = CastsDialog.create_simple()
		ui_parent.add_child(casts_dialog)
		casts_dialog.casts_changed.connect(_on_casts_changed)

	# Create model info popup
	if not model_info_popup:
		model_info_popup = ModelInfoPopup.create_simple()
		ui_parent.add_child(model_info_popup)

	# Create marker dialog
	if not marker_dialog:
		marker_dialog = MarkerDialog.create_simple()
		ui_parent.add_child(marker_dialog)
		marker_dialog.marker_added.connect(_on_marker_dialog_marker_added)
		marker_dialog.marker_removed.connect(_on_marker_dialog_marker_removed)
		marker_dialog.marker_value_changed.connect(_on_marker_dialog_value_changed)
		marker_dialog.marker_edited.connect(_on_marker_dialog_marker_edited)
		marker_dialog.token_library = token_library


## Opens the radial menu for the current selection at the given position.
func open_menu(screen_position: Vector2, selected_objects: Array) -> void:
	if not radial_menu:
		return

	_current_selection = selected_objects

	if selected_objects.is_empty():
		return

	# Determine context and create appropriate menu
	var items: Array[RadialMenu.RadialMenuItem] = []
	var context: Dictionary = {}

	# Check if all selected are from the same unit
	var first_obj = selected_objects[0] as Node3D
	if not first_obj:
		return

	# Mission objectives are pickable bodies carrying an objective_index meta;
	# they have no GameUnit, so detect them first.
	if first_obj.has_meta("objective_index"):
		context["objective_index"] = int(first_obj.get_meta("objective_index"))
		radial_menu.open(screen_position, _create_objective_menu(), context)
		return

	var game_unit = UnitUtils.get_game_unit(first_obj)

	if game_unit:
		context["game_unit"] = game_unit
		context["selection"] = selected_objects

		# Check if entire unit is selected
		var all_models = UnitUtils.get_all_unit_models(first_obj)
		var is_full_unit = all_models.size() == selected_objects.size()

		for model in all_models:
			if model not in selected_objects:
				is_full_unit = false
				break

		context["is_full_unit"] = is_full_unit

		# For single-model units, use model menu to show wounds option
		# For multi-model units with full selection, use unit menu
		var model_instance = UnitUtils.get_model_instance(first_obj)
		var is_single_model_unit = all_models.size() == 1

		if is_full_unit and not is_single_model_unit:
			# Multi-model unit fully selected - show unit menu
			items = RadialMenu.create_unit_menu(game_unit)
		elif model_instance:
			# Single model or partial selection - show model menu (includes wounds)
			context["model_instance"] = model_instance
			items = RadialMenu.create_model_menu(model_instance)
	elif UnitUtils.is_terrain(first_obj):
		context["terrain"] = first_obj
		items = RadialMenu.create_terrain_menu()
	else:
		# Generic object - minimal menu
		items.append(RadialMenu.RadialMenuItem.new("info", "Info", "ℹ️"))
		items.append(RadialMenu.RadialMenuItem.new("delete", "Delete", "🗑️"))
		context["object"] = first_obj

	if not items.is_empty():
		radial_menu.open(screen_position, items, context)


## Closes the radial menu.
func close_menu() -> void:
	if radial_menu and radial_menu.is_open():
		radial_menu.close()


## Checks if the menu is currently open.
func is_menu_open() -> bool:
	return radial_menu and radial_menu.is_open()


# ===== Action Handlers =====

func _on_action_selected(action_id: String, context: Dictionary) -> void:
	# Objective owner actions are dynamic ("set_owner_<player_id>").
	if action_id.begins_with("set_owner_"):
		_set_objective_owner(context, action_id)
		return

	match action_id:
		"select_unit":
			_select_entire_unit(context)
		"wounds":
			_open_wounds_dialog(context)
		"casts":
			_open_casts_dialog(context)
		"add_marker":
			_open_marker_dialog(context)
		"toggle_activate":
			_toggle_activation(context)
		"toggle_fatigued":
			_toggle_fatigued(context)
		"toggle_shaken":
			_toggle_shaken(context)
		"delete_model":
			_delete_model(context)
		"delete_unit":
			_delete_unit(context)
		"delete_terrain":
			_delete_terrain(context)
		"info":
			_show_generic_info(context)
		"delete":
			_delete_generic(context)


## Builds the flat objective-capture ring: Neutral plus one item per active
## player (army slot). Player count caps cleanly at the defined PLAYER_COLORS.
func _create_objective_menu() -> Array[RadialMenu.RadialMenuItem]:
	var items: Array[RadialMenu.RadialMenuItem] = []
	items.append(RadialMenu.RadialMenuItem.new("set_owner_0", "Neutral", "N", true, "Set objective to neutral (gold)"))

	for pid in _active_player_ids():
		var pname: String = PLAYER_COLOR_NAMES.get(pid, "Player %d" % pid)
		items.append(RadialMenu.RadialMenuItem.new(
			"set_owner_%d" % pid, pname, str(pid), true, "Captured by %s" % pname))

	return items


## Distinct, sorted player ids (> 0) that currently have units on the table. Unions the
## imported-armies dict with the live game_units, because `armies` is only populated on the
## LOCAL import path — on a joined or RECONNECTED peer it is empty, which used to leave the
## objective-capture menu with no players to seize for (issue #70). game_units is restored on
## every load / state-sync / reconnect, so it is the reliable source of player ownership.
func _active_player_ids() -> Array[int]:
	var ids := {}
	if army_manager:
		for pid in army_manager.armies.keys():
			if int(pid) > 0:
				ids[int(pid)] = true
		for gu in army_manager.game_units.values():
			var unit := gu as GameUnit
			if unit == null:
				continue
			var pid := int(unit.unit_properties.get("player_id", 0))
			if pid > 0:
				ids[pid] = true
	var sorted_ids: Array[int] = []
	for k in ids.keys():
		sorted_ids.append(int(k))
	sorted_ids.sort()
	return sorted_ids


## Sets the owner of the objective in the context, recolors it, and syncs it.
func _set_objective_owner(context: Dictionary, action_id: String) -> void:
	var index: int = context.get("objective_index", -1)
	if index < 0:
		return

	var owner_id := int(action_id.substr("set_owner_".length()))

	if terrain_overlay and terrain_overlay.has_method("set_objective_owner"):
		terrain_overlay.set_objective_owner(index, owner_id)

	if network_manager:
		network_manager.broadcast_objective_owner(index, owner_id)


func _select_entire_unit(context: Dictionary) -> void:
	var game_unit = context.get("game_unit") as GameUnit
	if not game_unit:
		return

	if object_manager and object_manager.has_method("select_objects"):
		var all_models = []
		for model in game_unit.models:
			if model.node and is_instance_valid(model.node):
				all_models.append(model.node)
		object_manager.select_objects(all_models)


func _open_wounds_dialog(context: Dictionary) -> void:
	var model = context.get("model_instance") as ModelInstance
	if not model:
		return

	if wounds_dialog:
		wounds_dialog.open(model)
	else:
		push_warning("Wounds dialog not available")


func _open_casts_dialog(context: Dictionary) -> void:
	var game_unit = context.get("game_unit") as GameUnit
	if not game_unit:
		# Try to get unit from model
		var model = context.get("model_instance") as ModelInstance
		if model and model.unit and model.unit is GameUnit:
			game_unit = model.unit as GameUnit

	if not game_unit:
		return

	if casts_dialog:
		casts_dialog.open(game_unit)
	else:
		push_warning("Casts dialog not available")


func _open_marker_dialog(context: Dictionary) -> void:
	if not marker_dialog:
		push_warning("Marker dialog not available")
		return

	var game_unit = context.get("game_unit") as GameUnit
	var model = context.get("model_instance") as ModelInstance

	if model:
		marker_dialog.open_for_model(model)
	elif game_unit:
		marker_dialog.open_for_unit(game_unit)


func _toggle_activation(context: Dictionary) -> void:
	var game_unit = context.get("game_unit") as GameUnit
	if not game_unit:
		return

	if game_unit.is_activated:
		game_unit.is_activated = false
		_update_activated_markers(game_unit)
		unit_deactivated.emit(game_unit)
	else:
		game_unit.activate(1)
		_update_activated_markers(game_unit)
		unit_activated.emit(game_unit)

	# Broadcast activation change to remote peers
	if network_manager:
		network_manager.broadcast_unit_activation(game_unit)


func _toggle_fatigued(context: Dictionary) -> void:
	var game_unit = _get_game_unit_from_context(context)
	if not game_unit:
		return

	game_unit.is_fatigued = not game_unit.is_fatigued
	_update_fatigued_markers(game_unit)

	# Broadcast fatigued change to remote peers
	if network_manager:
		network_manager.broadcast_unit_marker(game_unit, "FatiguedMarker", game_unit.is_fatigued)


func _toggle_shaken(context: Dictionary) -> void:
	var game_unit = _get_game_unit_from_context(context)
	if not game_unit:
		return

	game_unit.is_shaken = not game_unit.is_shaken
	_update_shaken_markers(game_unit)

	# Broadcast shaken change to remote peers
	if network_manager:
		network_manager.broadcast_unit_marker(game_unit, "ShakenMarker", game_unit.is_shaken)


## Helper to get GameUnit from context (supports both unit and model selection)
func _get_game_unit_from_context(context: Dictionary) -> GameUnit:
	var game_unit = context.get("game_unit") as GameUnit
	if game_unit:
		return game_unit

	# Try to get from model
	var model = context.get("model_instance") as ModelInstance
	if model and model.unit and model.unit is GameUnit:
		return model.unit as GameUnit

	return null


## Deletes (hides) a set of selected objects as one undoable action.
##
## Unit models use casualty semantics (is_alive=false, wounds=0, hidden) and sync
## to peers via NetworkManager.broadcast_model_wounds(). Plain nodes (custom minis
## / terrain) are hidden locally only — matching the existing, non-networked
## generic/terrain delete. Nothing is freed, so the whole batch stays undoable.
func delete_objects(objects: Array) -> void:
	if objects.is_empty():
		return

	var models: Array[ModelInstance] = []
	var prev_wounds: Array[int] = []
	var prev_alive: Array[bool] = []
	var nodes: Array[Node3D] = []

	for obj in objects:
		if not (obj is Node3D) or not is_instance_valid(obj):
			continue
		var model: ModelInstance = UnitUtils.get_model_instance(obj)
		if model:
			models.append(model)
			prev_wounds.append(model.wounds_current)
			prev_alive.append(model.is_alive)
		else:
			nodes.append(obj)

	if models.is_empty() and nodes.is_empty():
		return

	# DeleteAction.redo() performs the initial deletion (hide + broadcast), so the
	# deletion logic lives in exactly one place.
	var del_peer: int = network_manager.get_my_peer_id() if network_manager else 0
	var action := UndoManager.DeleteAction.new(models, prev_wounds, prev_alive, nodes, network_manager, del_peer)
	action.redo()

	for model in models:
		model_deleted.emit(model)

	if undo_manager:
		undo_manager.push(action)


func _delete_model(context: Dictionary) -> void:
	var model = context.get("model_instance") as ModelInstance
	if not model or not model.node:
		return
	# Delete the whole current selection (not just the clicked model) so deleting a
	# multi-selection removes all of them; falls back to the single clicked model.
	var targets: Array = _current_selection.duplicate() if not _current_selection.is_empty() else [model.node]
	delete_objects(targets)
	if object_manager and object_manager.has_method("deselect_all"):
		object_manager.deselect_all()


func _delete_unit(context: Dictionary) -> void:
	var game_unit = context.get("game_unit") as GameUnit
	if not game_unit:
		return

	# Delete all models
	for model in game_unit.models:
		model.is_alive = false
		model.wounds_current = 0
		if model.node and is_instance_valid(model.node):
			model.node.queue_free()

	unit_deleted.emit(game_unit)

	# Broadcast unit deletion to remote peers
	if network_manager:
		network_manager.broadcast_unit_delete(game_unit)


func _delete_terrain(context: Dictionary) -> void:
	var terrain = context.get("terrain") as Node3D
	if terrain:
		terrain.queue_free()


## Show a minimal info popup (name + node type) for a generic table object — one
## that is not an OPR unit/model or terrain (e.g. a directly loaded custom model).
func _show_generic_info(context: Dictionary) -> void:
	var obj = context.get("object") as Node3D
	if not obj or not model_info_popup:
		return
	model_info_popup.open_with_content(obj.name, "Type: %s" % obj.get_class())


func _delete_generic(context: Dictionary) -> void:
	var obj = context.get("object") as Node3D
	if obj:
		obj.queue_free()


## Called when wounds are changed via the wounds dialog.
func _on_wounds_changed(model: ModelInstance, new_wounds: int) -> void:
	# Update visual wound marker
	_update_wound_marker(model)

	# Hide model if dead
	if new_wounds <= 0 and not model.is_alive:
		if model.node and is_instance_valid(model.node):
			model.node.visible = false
			model.node.set_meta("deleted", true)
		model_deleted.emit(model)
	# Show model if revived
	elif new_wounds > 0 and model.node and is_instance_valid(model.node):
		model.node.visible = true
		model.node.set_meta("deleted", false)

	# Regiments (AoF:R): close ranks on a casualty, re-open on revive.
	_reform_regiment_for_model(model)

	# Broadcast wounds change to remote peers
	if network_manager:
		network_manager.broadcast_model_wounds(model)


## If the model belongs to a regiment movement-tray block, re-rank the block so the
## ranks close on a casualty (or re-open on revive). No-op for loose skirmish models.
func _reform_regiment_for_model(model: ModelInstance) -> void:
	if model == null or model.node == null or not is_instance_valid(model.node):
		return
	if not model.node.has_meta(RegimentTray.MEMBER_META):
		return
	var tray = model.node.get_meta(RegimentTray.MEMBER_META)
	if is_instance_valid(tray) and tray.has_method("reform_from_unit"):
		tray.reform_from_unit(model.unit)


## Updates or creates a wound marker (red disc with border) next to a model.
func _update_wound_marker(model: ModelInstance) -> void:
	if not model.node or not is_instance_valid(model.node):
		return

	var wounds_taken = model.wounds_max - model.wounds_current
	var is_active = wounds_taken > 0

	var unit = model.unit as GameUnit if model.unit else null
	_update_token(model.node, unit, "WoundMarker", is_active, wounds_taken)


## Called when casts are changed via the casts dialog.
func _on_casts_changed(unit: GameUnit, _new_casts: int) -> void:
	# Update visual caster marker if needed
	_update_caster_marker(unit)

	# Broadcast casts change to remote peers
	if network_manager:
		network_manager.broadcast_unit_casts(unit)


## Updates or creates a caster point marker (purple disc) next to a unit's first model.
func _update_caster_marker(unit: GameUnit) -> void:
	if unit.models.is_empty():
		return

	var model = unit.models[0]
	if not model.node or not is_instance_valid(model.node):
		return

	var is_active = unit.is_caster()
	_update_token(model.node, unit, "CasterMarker", is_active, unit.casts_current)


## Public method to initialize caster marker for a unit after import.
## Call this for each caster unit after spawning to show the initial caster token.
func initialize_caster_marker_for_unit(game_unit: GameUnit) -> void:
	if game_unit and game_unit.is_caster():
		_update_caster_marker(game_unit)


# ===== Status Token Markers (Fatigue, Shaken, Activated) =====
# These are unit-wide markers - placed on boundary for multi-model units

## Gets the node to attach unit-wide tokens to.
## Routes by the visualizer's authoritative has_boundary() (which tracks the ALIVE
## model count), NOT the total model count — so a unit reduced to its last model
## (boundary gone) hands its tokens to that lone survivor instead of an orphaned
## boundary container. Falls back to the first alive model (then any model).
func _get_unit_token_node(unit: GameUnit) -> Node3D:
	# Multi-model unit that currently HAS a boundary -> use the boundary container.
	if boundary_visualizer and boundary_visualizer.has_boundary(unit):
		return boundary_visualizer.get_token_container(unit)

	# Single-model unit (incl. one reduced to its last model): use that model.
	var model: ModelInstance = _lone_token_model(unit)
	if not model or not model.node or not is_instance_valid(model.node):
		return null
	return model.node


## The model a single-model unit's tokens belong to: the first ALIVE model, or the
## first model as a fallback when none are alive (e.g. a fully wiped unit mid-cleanup).
func _lone_token_model(unit: GameUnit) -> ModelInstance:
	if unit.models.is_empty():
		return null
	for model in unit.models:
		if model.is_alive and model.node and is_instance_valid(model.node):
			return model
	return unit.models[0]


## Updates fatigued markers for a unit.
func _update_fatigued_markers(unit: GameUnit) -> void:
	var token_node = _get_unit_token_node(unit)
	if not token_node:
		return
	_update_token(token_node, unit, "FatiguedMarker", unit.is_fatigued)


## Updates shaken markers for a unit.
func _update_shaken_markers(unit: GameUnit) -> void:
	var token_node = _get_unit_token_node(unit)
	if not token_node:
		return
	_update_token(token_node, unit, "ShakenMarker", unit.is_shaken)


## Updates activated markers for a unit.
func _update_activated_markers(unit: GameUnit) -> void:
	var token_node = _get_unit_token_node(unit)
	if not token_node:
		return
	_update_token(token_node, unit, "ActivatedMarker", unit.is_activated)


## Public method to initialize status markers for a unit after import.
func initialize_status_markers_for_unit(game_unit: GameUnit) -> void:
	if game_unit.is_fatigued:
		_update_fatigued_markers(game_unit)
	if game_unit.is_shaken:
		_update_shaken_markers(game_unit)
	if game_unit.is_activated:
		_update_activated_markers(game_unit)


## Public method to initialize wound markers for all models in a unit after load.
func initialize_wound_markers_for_unit(game_unit: GameUnit) -> void:
	for model in game_unit.models:
		if model.wounds_current < model.wounds_max:
			_update_wound_marker(model)


## Called when a unit's boundary is updated (models moved/rearranged).
## Repositions tokens along the new boundary shape.
func _on_boundary_updated(game_unit: GameUnit) -> void:
	if not boundary_visualizer:
		return

	# Get the token container for this unit
	var container = boundary_visualizer.get_token_container(game_unit)
	if not container or not is_instance_valid(container):
		return

	# Get active tokens on the container
	var tokens = _get_active_tokens(container)
	if tokens.is_empty():
		return

	# Reposition tokens along the updated boundary
	_reposition_tokens_boundary(container, game_unit, tokens)


## Called when a unit drops to its last alive model: the boundary (and its token
## rail) is gone, so migrate the unit-wide status/marker tokens from the orphaned
## boundary container onto the lone survivor. We clear the container's tokens and
## re-drive them from unit state — _get_unit_token_node now routes to the model
## (has_boundary() is false), so they land in circular mode on the survivor and
## follow it from then on. Idempotent and cheap (a handful of tokens).
func _on_boundary_lost(game_unit: GameUnit) -> void:
	if not boundary_visualizer or game_unit == null:
		return
	var container = boundary_visualizer.get_token_container(game_unit)
	if container and is_instance_valid(container):
		_clear_unit_status_tokens(container, game_unit)
	_redraw_unit_tokens(game_unit)


## Symmetric to _on_boundary_lost: a unit regained a boundary (e.g. a revive), so
## pull the unit-wide tokens off the lone model back onto the container. We clear
## them from every model node, then re-drive — _get_unit_token_node now routes to
## the container (has_boundary() is true), and boundary_updated lays them out.
func _on_boundary_gained(game_unit: GameUnit) -> void:
	if not boundary_visualizer or game_unit == null:
		return
	for model in game_unit.models:
		if model.node and is_instance_valid(model.node):
			_clear_unit_status_tokens(model.node, game_unit)
	_redraw_unit_tokens(game_unit)


## Removes every active unit-wide token from a node (boundary container OR a model
## node). Snapshots the names first: removing a token re-lays out the rest, which
## mutates the live child list mid-iteration.
func _clear_unit_status_tokens(node: Node3D, game_unit: GameUnit) -> void:
	for token_name in _get_active_tokens(node):
		_update_token(node, game_unit, token_name, false)


## Re-draws the unit-wide tokens (built-in status + dialog/custom markers) from
## unit state. They land on whatever node _get_unit_token_node currently resolves
## to (boundary container or lone model), so this drives both migration directions.
func _redraw_unit_tokens(game_unit: GameUnit) -> void:
	# Built-in status tokens (no-ops when the flag is inactive).
	_update_activated_markers(game_unit)
	_update_shaken_markers(game_unit)
	_update_fatigued_markers(game_unit)

	# Dialog/custom markers the unit carries, each at its correct scope.
	var seen: Dictionary = {}
	for model in game_unit.models:
		for marker_name in model.markers:
			if seen.has(marker_name):
				continue
			seen[marker_name] = true
			_render_token_for_unit_scoped(game_unit, marker_name)


# ===== Unified Token Layout System =====

## Returns the layout/style config for a token node name, looking at the built-in
## TOKEN_TYPES first and then the runtime dialog-marker configs. Null if unknown.
func _token_config(token_name: String) -> Variant:
	if TOKEN_TYPES.has(token_name):
		return TOKEN_TYPES[token_name]
	return _dynamic_token_configs.get(token_name, null)


## Gets all active token markers on a model node.
func _get_active_tokens(model_node: Node3D) -> Array[String]:
	var tokens: Array[String] = []
	for token_name in TOKEN_TYPES.keys() + _dynamic_token_configs.keys():
		if model_node.get_node_or_null(token_name):
			tokens.append(token_name)
	# Sort by priority
	tokens.sort_custom(func(a, b): return _token_config(a)["priority"] < _token_config(b)["priority"])
	return tokens


## Gets the base radius for a unit (in meters).
func _get_base_radius(unit: GameUnit, model_node: Node3D = null) -> float:
	var base_radius = 0.016  # Default 32mm base
	if unit and unit.unit_properties:
		# Use the model's ACTUAL base when a model is given: a per-model Tough upgrade enlarges it
		# (the mesh stays natural-sized), so tokens / equipment rings sit on the base you see.
		var model_tough := _model_tough_of(model_node) if model_node else 0
		var props = OPRArmyManager.effective_base_props(unit.unit_properties, model_tough)
		if props.get("base_is_oval", false) or props.get("base_is_square", false):
			var w := float(props.get("base_width_mm", 0))
			var d := float(props.get("base_depth_mm", 0))
			if w > 0.0 and d > 0.0:
				# Average of width + depth for oval/square bases
				base_radius = ((w + d) / 4.0) * 0.001
			else:
				base_radius = (float(props.get("base_size_round", 32)) / 2.0) * 0.001
		else:
			var base_mm = props.get("base_size_round", 32)
			base_radius = (base_mm / 2.0) * 0.001
	return base_radius


## The per-model Tough value (drives the enlarged base), 0 if none.
func _model_tough_of(model_node: Node3D) -> int:
	if model_node and model_node.has_meta("model_instance"):
		var m = model_node.get_meta("model_instance")
		if m is ModelInstance and m.properties != null:
			return int(m.properties.get("tough", 0))
	return 0


## Calculates positions for tokens around the base edge, centered at 9 o'clock.
## Returns array of angles (in radians) for each token position.
func _calculate_token_angles(token_count: int, base_radius: float) -> Array[float]:
	var angles: Array[float] = []
	if token_count == 0:
		return angles

	# Tokens are placed at this distance from base center
	var token_orbit_radius = base_radius + TOKEN_RADIUS + 0.001

	# Arc length between token centers = diameter + gap
	# arc_length = angle * radius, so angle = arc_length / radius
	var token_angular_width = (2.0 * TOKEN_RADIUS + TOKEN_GAP) / token_orbit_radius

	# Total angular span for all tokens (n tokens, n-1 gaps already included in width)
	var total_span = token_count * token_angular_width - TOKEN_GAP / token_orbit_radius

	# Center position is PI (9 o'clock = left side)
	var center_angle = PI

	# Starting angle: center minus half of total span, offset by half token width
	var start_angle = center_angle - total_span / 2.0 + token_angular_width / 2.0

	for i in range(token_count):
		angles.append(start_angle + i * token_angular_width)

	return angles


## Calculates 3D position for a token at a given angle around the base.
func _angle_to_position(angle: float, base_radius: float) -> Vector3:
	var distance = base_radius + TOKEN_RADIUS + 0.001  # Slight gap from base edge
	return Vector3(cos(angle) * distance, 0, sin(angle) * distance)


## Determines the best side (angle) for tokens to avoid overlapping with other models.
## Returns PI (9 o'clock/left) or 0 (3 o'clock/right).
func _get_best_token_side(model_node: Node3D, unit: GameUnit, base_radius: float, token_count: int) -> float:
	var default_angle = PI  # 9 o'clock (left side)
	var opposite_angle = 0.0  # 3 o'clock (right side)

	if not unit or token_count == 0:
		return default_angle

	var model_pos = model_node.global_position

	# Calculate the farthest token position on the left side
	var angles = _calculate_token_angles(token_count, base_radius)
	if angles.is_empty():
		return default_angle

	# Check if any token would overlap with another model or its tokens
	for other_model in unit.models:
		if not is_instance_valid(other_model) or not is_instance_valid(other_model.node):
			continue
		if other_model.node == model_node:
			continue

		var other_pos = other_model.node.global_position
		var other_base_radius = _get_base_radius(unit, other_model.node)

		# Check each token position on the left side
		for angle in angles:
			var token_local_pos = _angle_to_position(angle, base_radius)
			var token_world_pos = model_pos + token_local_pos

			# Distance from this token to the other model's center
			var dist_to_other = Vector2(token_world_pos.x - other_pos.x, token_world_pos.z - other_pos.z).length()

			# Check if token overlaps with other model's base or its token zone
			# Token zone extends: other_base_radius + TOKEN_RADIUS + small buffer
			var overlap_threshold = other_base_radius + TOKEN_RADIUS + 0.005

			if dist_to_other < overlap_threshold:
				# Left side overlaps, try right side
				# First check if right side is clear
				var right_clear = true
				var right_angles = _calculate_token_angles_at_center(token_count, base_radius, opposite_angle)

				for right_angle in right_angles:
					var right_token_pos = model_pos + _angle_to_position(right_angle, base_radius)
					var right_dist = Vector2(right_token_pos.x - other_pos.x, right_token_pos.z - other_pos.z).length()
					if right_dist < overlap_threshold:
						right_clear = false
						break

				if right_clear:
					return opposite_angle

	return default_angle


## Calculates token angles centered at a specific angle (for overlap avoidance).
func _calculate_token_angles_at_center(token_count: int, base_radius: float, center_angle: float) -> Array[float]:
	var angles: Array[float] = []
	if token_count == 0:
		return angles

	var token_orbit_radius = base_radius + TOKEN_RADIUS + 0.001
	var token_angular_width = (2.0 * TOKEN_RADIUS + TOKEN_GAP) / token_orbit_radius
	var total_span = token_count * token_angular_width - TOKEN_GAP / token_orbit_radius
	var start_angle = center_angle - total_span / 2.0 + token_angular_width / 2.0

	for i in range(token_count):
		angles.append(start_angle + i * token_angular_width)

	return angles


## Repositions all tokens on a model with optional animation.
func _reposition_all_tokens(model_node: Node3D, unit: GameUnit, new_token_name: String = "") -> void:
	var tokens = _get_active_tokens(model_node)
	if tokens.is_empty():
		return

	# Check if this is a boundary token container (unit-wide tokens)
	var is_boundary_container = model_node.name == "UnitTokenContainer"

	if is_boundary_container:
		# Arrange tokens along boundary edge
		_reposition_tokens_boundary(model_node, unit, tokens, new_token_name)
	else:
		# Circular arrangement around base for model-specific tokens
		_reposition_tokens_circular(model_node, unit, tokens, new_token_name)


## Repositions tokens along boundary edge.
## Tokens follow the boundary contour starting from -45° of first model.
func _reposition_tokens_boundary(container: Node3D, unit: GameUnit, tokens: Array[String], new_token_name: String = "") -> void:
	if not boundary_visualizer:
		return

	# Get positions along boundary for all tokens
	var boundary_positions = boundary_visualizer.get_token_positions_on_boundary(unit, tokens.size())

	if boundary_positions.is_empty():
		return

	# Container is at anchor point, calculate relative positions
	var container_pos = container.global_position

	for i in range(tokens.size()):
		var token_name = tokens[i]
		var marker = container.get_node_or_null(token_name)
		if not marker:
			continue

		if i >= boundary_positions.size():
			continue

		# Calculate local position relative to container
		var world_pos = boundary_positions[i]
		var local_pos = world_pos - container_pos

		if token_name == new_token_name:
			# New token: animate in from above
			marker.position = local_pos + Vector3(0, 0.03, 0)
			marker.scale = Vector3(0.01, 0.01, 0.01)

			var tween = marker.create_tween()
			tween.set_parallel(true)
			tween.tween_property(marker, "scale", Vector3(1, 1, 1), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tween.tween_property(marker, "position", local_pos, 0.3).set_ease(Tween.EASE_OUT)
		else:
			# Existing token: animate to new position if changed
			if marker.position.distance_to(local_pos) > 0.001:
				var tween = marker.create_tween()
				tween.set_ease(Tween.EASE_OUT)
				tween.set_trans(Tween.TRANS_CUBIC)
				tween.tween_property(marker, "position", local_pos, 0.4)
			else:
				marker.position = local_pos


## Repositions tokens in a circle around base (for model tokens).
func _reposition_tokens_circular(model_node: Node3D, unit: GameUnit, tokens: Array[String], new_token_name: String = "") -> void:
	var base_radius = _get_base_radius(unit, model_node)

	# Determine the best side to place tokens (avoids overlapping with other models)
	var best_side = _get_best_token_side(model_node, unit, base_radius, tokens.size())
	var angles = _calculate_token_angles_at_center(tokens.size(), base_radius, best_side)

	# North angle (12 o'clock) for spawn position
	var north_angle = -PI / 2.0

	for i in range(tokens.size()):
		var token_name = tokens[i]
		var marker = model_node.get_node_or_null(token_name)
		if not marker:
			continue

		var target_pos = _angle_to_position(angles[i], base_radius)

		if token_name == new_token_name:
			# New token: spawn at north and animate to position
			var spawn_pos = _angle_to_position(north_angle, base_radius)
			marker.position = spawn_pos
			marker.scale = Vector3(0.01, 0.01, 0.01)  # Start tiny

			# Animate along arc to final position
			_animate_token_to_position(marker, spawn_pos, target_pos, base_radius, north_angle, angles[i])
		else:
			# Existing token: animate to new position
			if marker.position.distance_to(target_pos) > 0.001:
				var tween = marker.create_tween()
				tween.set_ease(Tween.EASE_OUT)
				tween.set_trans(Tween.TRANS_CUBIC)
				tween.tween_property(marker, "position", target_pos, 0.4)


## Animates a token from north along the base edge to its target position.
func _animate_token_to_position(marker: Node3D, _start_pos: Vector3, _end_pos: Vector3, base_radius: float, start_angle: float, end_angle: float) -> void:
	var tween = marker.create_tween()

	# Scale up (pop in effect)
	tween.set_parallel(true)
	tween.tween_property(marker, "scale", Vector3(1, 1, 1), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Arc movement
	var distance = base_radius + TOKEN_RADIUS + 0.001
	var duration = 0.6

	tween.set_parallel(false)

	# Create smooth arc animation using multiple keyframes
	var steps = 20
	var angle_diff = end_angle - start_angle
	# Ensure we go the shorter way around (left side, so go clockwise from north)
	if angle_diff > PI:
		angle_diff -= 2 * PI
	elif angle_diff < -PI:
		angle_diff += 2 * PI

	var step_duration = duration / steps
	for step in range(1, steps + 1):
		var t = float(step) / steps
		# Ease out cubic
		var eased_t = 1.0 - pow(1.0 - t, 3)
		var current_angle = start_angle + angle_diff * eased_t
		var pos = Vector3(cos(current_angle) * distance, 0, sin(current_angle) * distance)
		tween.tween_property(marker, "position", pos, step_duration)


## Creates a token disc with the unified style.
func _create_token_disc(marker_name: String) -> Node3D:
	var config = _token_config(marker_name)
	if not config:
		return null

	var marker = Node3D.new()
	marker.name = marker_name

	var color = config["color"]
	var label_text = config["label"]

	# Create black base disc (border)
	var border_mesh = MeshInstance3D.new()
	border_mesh.name = "Border"
	var border_cyl = CylinderMesh.new()
	border_cyl.top_radius = TOKEN_RADIUS + 0.001
	border_cyl.bottom_radius = TOKEN_RADIUS + 0.001
	border_cyl.height = TOKEN_HEIGHT
	border_mesh.mesh = border_cyl
	var border_mat = StandardMaterial3D.new()
	border_mat.albedo_color = Color(0.02, 0.02, 0.02)
	border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	border_mesh.material_override = border_mat
	border_mesh.position = Vector3(0, TOKEN_HEIGHT / 2, 0)
	marker.add_child(border_mesh)

	# Create colored disc (main body)
	var disc_mesh = MeshInstance3D.new()
	disc_mesh.name = "Disc"
	var disc_cyl = CylinderMesh.new()
	disc_cyl.top_radius = TOKEN_RADIUS
	disc_cyl.bottom_radius = TOKEN_RADIUS
	disc_cyl.height = TOKEN_HEIGHT + 0.0002
	disc_mesh.mesh = disc_cyl
	var disc_mat = StandardMaterial3D.new()
	disc_mat.albedo_color = color
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mesh.material_override = disc_mat
	disc_mesh.position = Vector3(0, TOKEN_HEIGHT / 2 + 0.0001, 0)
	marker.add_child(disc_mesh)

	# Create text arc
	_create_token_text_arc(marker, label_text, TOKEN_RADIUS * 0.75, TOKEN_HEIGHT + 0.001, color)

	return marker


## Lazily loads the shared font for the curved arc labels (see ARC_FONT_PATH).
func _get_arc_font() -> Font:
	if _arc_font == null:
		_arc_font = load(ARC_FONT_PATH)
	return _arc_font


## Creates text arc for a token.
func _create_token_text_arc(parent: Node3D, text: String, radius: float, height: float, color: Color) -> void:
	var angle_per_char = PI / 10
	var total_arc = (text.length() - 1) * angle_per_char
	var start_angle = PI / 2 + total_arc / 2

	for i in range(text.length()):
		var char_label = Label3D.new()
		char_label.name = "TokenChar%d" % i
		char_label.text = text[i]
		char_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		char_label.no_depth_test = false  # occlude when the token sits behind a model
		char_label.font_size = 24
		char_label.outline_size = 2
		char_label.modulate = Color.WHITE
		char_label.outline_modulate = color.darkened(0.4)
		char_label.pixel_size = 0.0001
		char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		var angle = start_angle - i * angle_per_char
		var x = cos(angle) * radius
		var z = -sin(angle) * radius
		char_label.position = Vector3(x, height, z)
		char_label.rotation = Vector3(-PI / 2, angle - PI / 2, 0)

		parent.add_child(char_label)


## Adds a number label to a token.
func _add_token_number_label(marker: Node3D, color: Color) -> Label3D:
	var number_label = Label3D.new()
	number_label.name = "NumberLabel"
	number_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	number_label.no_depth_test = false  # occlude when the token sits behind a model
	number_label.font_size = 72
	number_label.outline_size = 8
	number_label.modulate = Color.WHITE
	number_label.outline_modulate = color.darkened(0.4)
	number_label.pixel_size = 0.00016
	number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number_label.position = Vector3(0, TOKEN_HEIGHT + 0.001, 0.002)
	number_label.rotation = Vector3(-PI / 2, 0, 0)
	marker.add_child(number_label)
	return number_label


## Adds a letter label to a token (for status markers like S, F).
func _add_token_letter_label(marker: Node3D, letter: String, color: Color) -> Label3D:
	var letter_label = Label3D.new()
	letter_label.name = "LetterLabel"
	letter_label.text = letter
	letter_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	letter_label.no_depth_test = false  # occlude when the token sits behind a model
	letter_label.font_size = 72
	letter_label.outline_size = 8
	letter_label.modulate = Color.WHITE
	letter_label.outline_modulate = color.darkened(0.4)
	letter_label.pixel_size = 0.00016
	letter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter_label.position = Vector3(0, TOKEN_HEIGHT + 0.001, 0.002)
	letter_label.rotation = Vector3(-PI / 2, 0, 0)
	marker.add_child(letter_label)
	return letter_label


## Updates a token marker (unified version with animation).
## For tokens with numbers (wounds, casts), pass the value.
## For tokens with letters (shaken, fatigued), pass -1.
func _update_token(model_node: Node3D, unit: GameUnit, marker_name: String, is_active: bool, value: int = -1) -> void:
	var existing_marker = model_node.get_node_or_null(marker_name)

	# Remove marker if inactive (no config needed for removal).
	if not is_active:
		if existing_marker:
			# Remove from tree immediately so _get_active_tokens won't find it
			model_node.remove_child(existing_marker)
			existing_marker.queue_free()
			# Reposition remaining tokens with animation
			_reposition_all_tokens(model_node, unit)
		return

	var config = _token_config(marker_name)
	if not config:
		return

	var is_new = existing_marker == null

	# Create marker if needed
	if not existing_marker:
		var marker = _create_token_disc(marker_name)
		model_node.add_child(marker)
		existing_marker = marker

		# Add appropriate label
		if value >= 0:
			var label = _add_token_number_label(marker, config["color"])
			label.text = str(value)
		else:
			_add_token_letter_label(marker, config["letter"], config["color"])
	else:
		# Update number if applicable
		if value >= 0:
			var label = existing_marker.get_node_or_null("NumberLabel") as Label3D
			if label:
				label.text = str(value)

	# Reposition all tokens (with animation for new tokens)
	if is_new:
		_reposition_all_tokens(model_node, unit, marker_name)
	else:
		_reposition_all_tokens(model_node, unit)


# ===== Marker Dialog Network Broadcasts =====

## Called when a marker is added via the marker dialog.
func _on_marker_dialog_marker_added(target: Variant, marker: UnitMarker) -> void:
	# Register/update custom tokens in the reusable library (standard markers stay
	# defined by UnitMarker, not user-editable).
	if not UnitMarker.STANDARD_MARKERS.has(marker.name):
		token_library.define(marker.name, marker.color, marker.is_counter, marker.effect)
		if network_manager:
			network_manager.broadcast_token_define(marker.name, marker.color, marker.is_counter, marker.effect)

	_store_marker_color(target, marker.name, marker.color)
	if marker.is_counter:
		_store_marker_value(target, marker.name, marker.counter_value)
	_apply_marker_token(target, marker.name)

	var value := marker.counter_value if marker.is_counter else -1
	if network_manager:
		if target is ModelInstance:
			network_manager.broadcast_model_marker(target, marker.name, true, marker.color, value)
		elif target is GameUnit:
			network_manager.broadcast_unit_marker(target, marker.name, true, marker.color, value)


## Called when a custom token's definition is edited via the dialog (rename,
## recolor, or effect change). Applies across every instance and syncs it.
func _on_marker_dialog_marker_edited(old_name: String, new_name: String, color: Color, effect: String) -> void:
	apply_token_edit(old_name, new_name, color, effect, true)


## Applies a library token edit everywhere: optional rename (migrates instances),
## then updates color/effect and re-renders every instance.
func apply_token_edit(old_name: String, new_name: String, color: Color, effect: String, do_broadcast: bool) -> void:
	if old_name.is_empty():
		return
	var is_counter := token_library.is_counter(old_name) if token_library.has(old_name) else false

	var final_name := old_name
	if not new_name.is_empty() and new_name != old_name:
		_rename_token_everywhere(old_name, new_name)
		token_library.rename(old_name, new_name)
		final_name = new_name

	token_library.define(final_name, color, is_counter, effect)
	_rerender_token_everywhere(final_name)

	if do_broadcast and network_manager:
		network_manager.broadcast_token_edit(old_name, final_name, color, effect)


## Migrates a custom token from old_name to new_name on every model that has it
## (markers, counter value, stored color, and the rendered token node).
func _rename_token_everywhere(old_name: String, new_name: String) -> void:
	if not army_manager:
		return
	for unit in army_manager.get_all_game_units():
		if not _any_model_has_marker(unit, old_name):
			continue
		# Clear the old token visuals (unit + model nodes) before migrating data.
		_remove_token_renders(unit, old_name)
		for model in unit.models:
			if not model.has_marker(old_name):
				continue
			var was_counter := model.is_counter_marker(old_name)
			var val := model.get_marker_value(old_name)
			model.remove_marker(old_name)  # also clears its counter value
			model.marker_colors.erase(old_name)
			model.add_marker(new_name)
			if was_counter:
				model.set_marker_value(new_name, val)
	# The new-name visuals are drawn by apply_token_edit -> _rerender_token_everywhere.


## Re-renders a custom token on every unit that has it (e.g. after a color edit).
func _rerender_token_everywhere(token_name: String) -> void:
	if not army_manager:
		return
	for unit in army_manager.get_all_game_units():
		if _any_model_has_marker(unit, token_name):
			_render_token_for_unit_scoped(unit, token_name)


## Remote: a peer defined/updated a custom token (color/effect/is_counter).
func receive_token_define(token_name: String, color: Color, is_counter: bool, effect: String) -> void:
	token_library.define(token_name, color, is_counter, effect)
	_rerender_token_everywhere(token_name)


## Called when a marker is removed via the marker dialog.
func _on_marker_dialog_marker_removed(target: Variant, marker_name: String) -> void:
	# The dialog already removed the marker data; re-render clears the visual.
	_apply_marker_token(target, marker_name)
	_clear_marker_color(target, marker_name)

	if network_manager:
		if target is ModelInstance:
			network_manager.broadcast_model_marker(target, marker_name, false)
		elif target is GameUnit:
			network_manager.broadcast_unit_marker(target, marker_name, false)


## Called when a counter marker's value is changed via the marker dialog (+/-).
func _on_marker_dialog_value_changed(target: Variant, marker_name: String, value: int) -> void:
	_store_marker_value(target, marker_name, value)
	_apply_marker_token(target, marker_name)

	if network_manager:
		if target is ModelInstance:
			network_manager.broadcast_model_marker_value(target, marker_name, value)
		elif target is GameUnit:
			network_manager.broadcast_unit_marker_value(target, marker_name, value)


## Stores a counter marker's value on the affected models.
func _store_marker_value(target: Variant, marker_name: String, value: int) -> void:
	if target is ModelInstance:
		target.set_marker_value(marker_name, value)
	elif target is GameUnit:
		target.set_marker_value_on_all(marker_name, value)


# ===== Dialog Marker Tokens =====
# Dialog markers reuse the unified token engine: each marker becomes a runtime
# token config (color + center letter) rendered per model via _update_token.

## Node name for a dialog marker's orbit token (kept distinct from TOKEN_TYPES).
## Hash the raw text: validate_node_name() collapses '. : / @ %' all to '_', so
## distinct marker texts (e.g. "Aura: Fear" vs "Aura/Fear") would otherwise share
## one node and corrupt each other's color/removal. The hash is injective enough.
func _marker_token_name(marker_name: String) -> String:
	return "DlgMarker_" + str(marker_name.hash())


## Center letter shown on a dialog marker token (first character, uppercased).
func _marker_token_letter(marker_name: String) -> String:
	if marker_name.is_empty():
		return "?"
	return marker_name.substr(0, 1).to_upper()


## Resolves a marker's display color: standard markers from the UnitMarker defs,
## custom markers from the model's stored color, else a neutral gray.
func _resolve_marker_color(marker_name: String, model: ModelInstance) -> Color:
	if UnitMarker.STANDARD_MARKERS.has(marker_name):
		return UnitMarker.STANDARD_MARKERS[marker_name].color
	# Library is authoritative for custom tokens, so editing a definition's color
	# updates every instance on the next render.
	if token_library.has(marker_name):
		return token_library.get_color(marker_name)
	if model and model.marker_colors.has(marker_name):
		return model.marker_colors[marker_name]
	return Color(0.6, 0.6, 0.6)


## Re-renders the dialog token for `marker_name` from the unit's current data, at
## the right SCOPE: one token on the unit's boundary node if EVERY model carries
## it (like the activation/shaken tokens), otherwise one per carrying model.
func _apply_marker_token(target: Variant, marker_name: String) -> void:
	var unit: GameUnit = null
	if target is ModelInstance:
		unit = target.unit as GameUnit
	elif target is GameUnit:
		unit = target
	if unit:
		_render_token_for_unit_scoped(unit, marker_name)


## Scope-aware (re)render: clears any stale renders, then draws the token once on
## the unit node if all models have it, else per carrying model.
func _render_token_for_unit_scoped(unit: GameUnit, marker_name: String) -> void:
	if not unit:
		return
	_remove_token_renders(unit, marker_name)
	if not _any_model_has_marker(unit, marker_name):
		return
	if _all_models_have_marker(unit, marker_name):
		var rep: ModelInstance = unit.models[0] if not unit.models.is_empty() else null
		_render_dialog_token_on_node(_get_unit_token_node(unit), unit, marker_name, rep, _resolve_marker_color(marker_name, rep))
	else:
		for model in unit.models:
			if model.has_marker(marker_name):
				_render_dialog_token_on_node(model.node, unit, marker_name, model, _resolve_marker_color(marker_name, model))


## Removes every rendered instance of a dialog token (unit node + all model nodes)
## so a scope change (unit-wide <-> per-model) never leaves a stale disc behind.
func _remove_token_renders(unit: GameUnit, marker_name: String) -> void:
	var node_name := _marker_token_name(marker_name)
	var unit_node := _get_unit_token_node(unit)
	if unit_node and is_instance_valid(unit_node):
		_update_token(unit_node, unit, node_name, false)
	for model in unit.models:
		if model.node and is_instance_valid(model.node):
			_update_token(model.node, unit, node_name, false)


func _any_model_has_marker(unit: GameUnit, marker_name: String) -> bool:
	for model in unit.models:
		if model.has_marker(marker_name):
			return true
	return false


func _all_models_have_marker(unit: GameUnit, marker_name: String) -> bool:
	if unit.models.is_empty():
		return false
	for model in unit.models:
		if not model.has_marker(marker_name):
			return false
	return true


## Renders one dialog token disc (counter number or status letter) on a node. The
## value/counter state is read from `value_model` (the representative model).
func _render_dialog_token_on_node(node: Node3D, unit: GameUnit, marker_name: String, value_model: ModelInstance, color: Color) -> void:
	if not node or not is_instance_valid(node):
		return
	var node_name := _marker_token_name(marker_name)
	var value := value_model.get_marker_value(marker_name) if (value_model and value_model.is_counter_marker(marker_name)) else -1
	_dynamic_token_configs[node_name] = {
		"color": color,
		# Full token name curved small around the rim (like "ACTIVATED" on the
		# activation token); the center still shows the letter/counter number.
		"label": marker_name,
		"letter": _marker_token_letter(marker_name),
		"priority": MARKER_TOKEN_PRIORITY,
	}
	_update_token(node, unit, node_name, true, value)
	# _update_token only colors NEW tokens; recolor on re-apply too.
	_recolor_token(node.get_node_or_null(node_name), color)


## Renders or removes a single dialog token on ONE model (low-level; the scope-
## aware path above is preferred). Kept for direct/per-model rendering.
func _render_marker_token(model: ModelInstance, unit: GameUnit, marker_name: String, color: Color, is_active: bool) -> void:
	if not model or not model.node or not is_instance_valid(model.node):
		return
	if is_active:
		_render_dialog_token_on_node(model.node, unit, marker_name, model, color)
	else:
		_update_token(model.node, unit, _marker_token_name(marker_name), false)


## Re-applies a token's color to its disc + letter outline (for color changes on
## an already-rendered token).
func _recolor_token(token: Node, color: Color) -> void:
	if not token:
		return
	var disc := token.get_node_or_null("Disc") as MeshInstance3D
	if disc and disc.material_override is StandardMaterial3D:
		(disc.material_override as StandardMaterial3D).albedo_color = color
	var letter := token.get_node_or_null("LetterLabel") as Label3D
	if letter:
		letter.outline_modulate = color.darkened(0.4)
	var number := token.get_node_or_null("NumberLabel") as Label3D
	if number:
		number.outline_modulate = color.darkened(0.4)


## Stores a custom marker's color on the affected models (standard colors are
## derivable from the marker name, so they are not stored).
func _store_marker_color(target: Variant, marker_name: String, color: Color) -> void:
	if UnitMarker.STANDARD_MARKERS.has(marker_name):
		return
	if target is ModelInstance:
		target.marker_colors[marker_name] = color
	elif target is GameUnit:
		for model in target.models:
			model.marker_colors[marker_name] = color


## Clears a stored custom marker color from the affected models.
func _clear_marker_color(target: Variant, marker_name: String) -> void:
	if target is ModelInstance:
		target.marker_colors.erase(marker_name)
	elif target is GameUnit:
		for model in target.models:
			model.marker_colors.erase(marker_name)


# ===== Special-Weapon Ring =====
# An automatic per-model flat base ring naming each piece of SPECIAL equipment a
# model carries. The ring is split into one segment per item, and the item's
# name is written (curved) from the centre of its segment. Purely derived from
# loadout data, so no per-model flag, save or network sync is needed.

## Renders (or clears) the special-equipment ring on a single model.
func _render_special_weapon_ring(model: ModelInstance) -> void:
	if not model or not model.node or not is_instance_valid(model.node):
		return
	var unit := model.unit as GameUnit
	if not unit:
		return

	# Always rebuild so loadout edits (Sort-Table, re-import) stay correct.
	var existing := model.node.get_node_or_null(SPECIAL_WEAPON_RING_NODE)
	if existing:
		existing.free()

	var items := unit.get_special_equipment_names(model)
	if items.is_empty():
		return

	var base_radius := _get_base_radius(unit, model.node)
	var ring_color := _unit_base_color(unit).lightened(0.25)
	var ring_root := Node3D.new()
	ring_root.name = SPECIAL_WEAPON_RING_NODE

	# FLAT ring lying on the base, same outer radius as the base, in the base/
	# player colour so it reads as a painted rim (not a 3D donut).
	var band := maxf(0.003, base_radius * 0.22)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = _make_flat_ring_mesh(base_radius - band, base_radius, 48)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = ring_color
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = ring_mat
	ring.position = Vector3(0, 0.005, 0)
	ring_root.add_child(ring)

	# One segment per special item; text is written from the segment centre and
	# auto-shrinks to fit the band + its arc, so it never overruns the ring.
	var text_radius := base_radius - band / 2.0
	var seg := TAU / items.size()
	var divider_color := ring_color.darkened(0.6)
	for i in range(items.size()):
		var center := PI / 2.0 - i * seg  # segment 0 faces the camera (front)
		var seg_node := Node3D.new()
		seg_node.name = "RingSegment%d" % i
		seg_node.set_meta("item", items[i])
		ring_root.add_child(seg_node)
		_create_ring_segment_text(seg_node, items[i], text_radius, center, band, seg * 0.82)
		if items.size() > 1:
			_create_ring_divider(ring_root, base_radius - band, base_radius, center - seg / 2.0, divider_color)

	model.node.add_child(ring_root)


## Builds a flat ring (annulus) mesh in the XZ plane between inner and outer radius.
func _make_flat_ring_mesh(inner: float, outer: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var ci0 := Vector3(cos(a0) * inner, 0, sin(a0) * inner)
		var co0 := Vector3(cos(a0) * outer, 0, sin(a0) * outer)
		var ci1 := Vector3(cos(a1) * inner, 0, sin(a1) * inner)
		var co1 := Vector3(cos(a1) * outer, 0, sin(a1) * outer)
		for v in [co0, ci0, ci1, co0, ci1, co1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()


## Colour of a unit's bases (player colour), used so the ring matches the base.
func _unit_base_color(unit: GameUnit) -> Color:
	var pid: int = unit.unit_properties.get("player_id", 1)
	return OPRArmyManager.PLAYER_COLORS.get(pid, Color(0.5, 0.5, 0.5))


## Writes one item's name as flat, curved text centered on its segment. Sizes the
## glyphs to ~0.78 of the band height and shrinks further if the word is wider
## than max_arc, so the text never overruns the ring (radially or tangentially).
func _create_ring_segment_text(parent: Node3D, text: String, radius: float, center_angle: float, band: float, max_arc: float) -> void:
	var n := text.length()
	if n == 0:
		return
	var font := _get_arc_font()
	var font_size := 48
	var pixel_size := (band * 0.78) / font_size  # glyph height ~ 0.78 * band

	# Real per-glyph advances (incl. kerning) via cumulative substring widths — NOT a
	# constant width — so wide letters (W, M) don't overlap and narrow ones don't gap.
	var total_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var arc_per_px := pixel_size * ARC_LETTER_SPACING / radius
	var total_arc := total_w * arc_per_px
	if total_arc > max_arc and total_arc > 0.0:
		var s := max_arc / total_arc  # shrink to fit the segment, keeping proportions
		pixel_size *= s
		arc_per_px *= s
		total_arc = max_arc

	for i in range(n):
		var left: float = font.get_string_size(text.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var right: float = font.get_string_size(text.substr(0, i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var offset_px: float = (left + right) / 2.0 - total_w / 2.0  # glyph centre from text centre
		var angle := center_angle - offset_px * arc_per_px

		var ch := Label3D.new()
		ch.name = "Char%d" % i
		ch.text = text[i]
		ch.font = font  # render with the font we measured -> correct spacing
		ch.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		ch.no_depth_test = false
		ch.font_size = font_size
		ch.outline_size = 8
		ch.modulate = Color.WHITE
		ch.outline_modulate = Color(0.05, 0.05, 0.05)
		ch.pixel_size = pixel_size
		ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ch.position = Vector3(cos(angle) * radius, 0.0065, -sin(angle) * radius)
		ch.rotation = Vector3(-PI / 2, angle - PI / 2, 0)
		parent.add_child(ch)


## Draws a small radial divider tick on the ring at the given boundary angle.
func _create_ring_divider(parent: Node3D, inner: float, outer: float, angle: float, color: Color) -> void:
	var box := MeshInstance3D.new()
	box.name = "Divider"
	var m := BoxMesh.new()
	m.size = Vector3(outer - inner, 0.0012, 0.0008)  # spans the band, thin tangentially
	box.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material_override = mat
	var mid := (inner + outer) / 2.0
	box.position = Vector3(cos(angle) * mid, 0.0055, -sin(angle) * mid)
	box.rotation = Vector3(0, angle, 0)  # align the box's length axis radially
	parent.add_child(box)


## Renders special-weapon rings for every model of a unit (spawn + after load).
func initialize_special_weapon_rings_for_unit(game_unit: GameUnit) -> void:
	for model in game_unit.models:
		_render_special_weapon_ring(model)


## Re-creates all dialog marker tokens for a unit (used after load), each at the
## correct scope (unit-wide vs per-model).
func initialize_marker_tokens_for_unit(game_unit: GameUnit) -> void:
	var seen: Dictionary = {}
	for model in game_unit.models:
		for marker_name in model.markers:
			if seen.has(marker_name):
				continue
			seen[marker_name] = true
			_render_token_for_unit_scoped(game_unit, marker_name)


## Adds/removes a dialog marker token on all models of a unit (remote sync). The
## marker data was already applied by the RPC; this stores color/value + renders.
## value >= 0 marks the marker as a counter and seeds its number on add.
func set_unit_marker_token(game_unit: GameUnit, marker_name: String, add: bool, color: Color = Color.WHITE, value: int = -1) -> void:
	for model in game_unit.models:
		_sync_marker_color_store(model, marker_name, color, add)
		if add and value >= 0:
			model.set_marker_value(marker_name, value)
	_render_token_for_unit_scoped(game_unit, marker_name)


## Adds/removes a dialog marker token on a single model (remote sync).
func set_model_marker_token(model: ModelInstance, marker_name: String, add: bool, color: Color = Color.WHITE, value: int = -1) -> void:
	_sync_marker_color_store(model, marker_name, color, add)
	if add and value >= 0:
		model.set_marker_value(marker_name, value)
	var unit := model.unit as GameUnit
	if unit:
		_render_token_for_unit_scoped(unit, marker_name)


## Updates a counter marker's value on all models of a unit (remote sync).
func set_unit_marker_value(game_unit: GameUnit, marker_name: String, value: int) -> void:
	game_unit.set_marker_value_on_all(marker_name, value)
	_render_token_for_unit_scoped(game_unit, marker_name)


## Updates a counter marker's value on a single model (remote sync).
func set_model_marker_value(model: ModelInstance, marker_name: String, value: int) -> void:
	model.set_marker_value(marker_name, value)
	var unit := model.unit as GameUnit
	if unit:
		_render_token_for_unit_scoped(unit, marker_name)


## Stores (add) or erases (remove) a remote custom-marker color on a model so
## _resolve_marker_color returns it; standard markers derive color from the name.
func _sync_marker_color_store(model: ModelInstance, marker_name: String, color: Color, add: bool) -> void:
	if not model:
		return
	if add and not UnitMarker.STANDARD_MARKERS.has(marker_name):
		model.marker_colors[marker_name] = color
	elif not add:
		model.marker_colors.erase(marker_name)
