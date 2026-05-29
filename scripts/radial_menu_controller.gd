extends Node
class_name RadialMenuController
## Controller that manages the radial menu integration with the game.
## Handles context detection, menu opening, and action execution.

signal unit_activated(game_unit: GameUnit)
signal unit_deactivated(game_unit: GameUnit)
signal model_deleted(model_instance: ModelInstance)
signal unit_deleted(game_unit: GameUnit)
signal coherency_checked(game_unit: GameUnit, result: CoherencyChecker.CoherencyResult)

## Reference to the radial menu UI
var radial_menu: RadialMenu = null

## Reference to the object manager for selection info
var object_manager: Node = null

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
		boundary_visualizer = value
		if boundary_visualizer and boundary_visualizer.has_signal("boundary_updated"):
			boundary_visualizer.connect("boundary_updated", _on_boundary_updated)

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

## Current selection context
var _current_selection: Array = []

## Is the radial menu scene loaded
var _menu_scene: PackedScene = null

## Runtime token configs for dialog markers (node_name -> {color, label, letter,
## priority}). Lets arbitrary MarkerDialog markers reuse the same token engine as
## the built-in TOKEN_TYPES without hardcoding them.
var _dynamic_token_configs: Dictionary = {}

## Priority for dialog marker tokens - placed after the built-in status tokens.
const MARKER_TOKEN_PRIORITY := 100

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
	match action_id:
		"unit_stats":
			_show_unit_stats(context)
		"model_stats":
			_show_model_stats(context)
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
		"check_coherency":
			_check_coherency(context)
		"roll_attack":
			_roll_attack(context)
		"delete_model":
			_delete_model(context)
		"delete_unit":
			_delete_unit(context)
		"terrain_info":
			_show_terrain_info(context)
		"toggle_los":
			_toggle_los(context)
		"delete_terrain":
			_delete_terrain(context)
		"info":
			_show_generic_info(context)
		"delete":
			_delete_generic(context)


func _show_unit_stats(context: Dictionary) -> void:
	var game_unit = context.get("game_unit") as GameUnit
	if not game_unit:
		return

	# Check if we have a stats tooltip reference
	if not stats_tooltip:
		print("Stats tooltip not connected")
		return

	# Get the OPRUnit from source_data (only works for OPR units)
	if game_unit.source_type == "opr" and game_unit.source_data:
		var opr_unit = game_unit.source_data as OPRApiClient.OPRUnit
		if opr_unit:
			# Get first model node for reference
			var model_node: Node3D = null
			if game_unit.models.size() > 0 and game_unit.models[0].node:
				model_node = game_unit.models[0].node

			# Show the tooltip immediately (bypass delay for menu action)
			stats_tooltip.show_unit(opr_unit, model_node, true)
	else:
		# Fallback for non-OPR units - show basic info
		print("Unit stats for: %s (non-OPR unit)" % game_unit.get_name())


func _show_model_stats(context: Dictionary) -> void:
	var model = context.get("model_instance") as ModelInstance
	if not model:
		return

	if model_info_popup:
		model_info_popup.open(model)
	else:
		# Fallback to console output
		var lines: Array[String] = []
		lines.append("[b]%s[/b]" % model.get_display_name())
		lines.append("Wounds: %d/%d" % [model.wounds_current, model.wounds_max])
		print("\n".join(lines))


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
		print("Wounds dialog not available")


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
		print("Casts dialog not available")


func _open_marker_dialog(context: Dictionary) -> void:
	if not marker_dialog:
		print("Marker dialog not available")
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
	print("%s is now %s" % [game_unit.get_name(), "Fatigued" if game_unit.is_fatigued else "not Fatigued"])

	# Broadcast fatigued change to remote peers
	if network_manager:
		network_manager.broadcast_unit_marker(game_unit, "FatiguedMarker", game_unit.is_fatigued)


func _toggle_shaken(context: Dictionary) -> void:
	var game_unit = _get_game_unit_from_context(context)
	if not game_unit:
		return

	game_unit.is_shaken = not game_unit.is_shaken
	_update_shaken_markers(game_unit)
	print("%s is now %s" % [game_unit.get_name(), "Shaken" if game_unit.is_shaken else "not Shaken"])

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


func _check_coherency(context: Dictionary) -> void:
	var game_unit = context.get("game_unit") as GameUnit
	if not game_unit:
		return

	# Use visualizer if available
	if coherency_visualizer:
		var result = coherency_visualizer.show_coherency(game_unit)
		coherency_checked.emit(game_unit, result)
	else:
		# Fallback to just checking without visualization
		var result = CoherencyChecker.check_unit_coherency(game_unit)
		coherency_checked.emit(game_unit, result)
		if result.valid:
			print("✓ %s is in coherency" % game_unit.get_name())
		else:
			print("⚠ %s has coherency issues" % game_unit.get_name())


func _roll_attack(context: Dictionary) -> void:
	var game_unit = context.get("game_unit") as GameUnit
	if not game_unit:
		return

	# TODO: Implement attack roll dialog (integrate with dice_roller plugin)
	push_warning("Attack roll dialog not yet implemented")
	print("Roll attack for: %s" % game_unit.get_name())


func _delete_model(context: Dictionary) -> void:
	var model = context.get("model_instance") as ModelInstance
	if not model:
		return

	# Mark as dead
	model.is_alive = false
	model.wounds_current = 0

	# Hide the node
	if model.node and is_instance_valid(model.node):
		model.node.visible = false
		model.node.set_meta("deleted", true)

	model_deleted.emit(model)
	print("Deleted model %d" % (model.model_index + 1))

	# Broadcast model death to remote peers (wounds=0, alive=false)
	if network_manager:
		network_manager.broadcast_model_wounds(model)


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
	print("Deleted unit: %s" % game_unit.get_name())

	# Broadcast unit deletion to remote peers
	if network_manager:
		network_manager.broadcast_unit_delete(game_unit)


func _show_terrain_info(context: Dictionary) -> void:
	var terrain = context.get("terrain") as Node3D
	if terrain:
		print("Terrain: %s" % terrain.name)


func _toggle_los(context: Dictionary) -> void:
	var terrain = context.get("terrain") as Node3D
	if not terrain:
		return

	# Toggle blocks_los metadata
	var currently_blocking = terrain.get_meta("blocks_los", true)
	terrain.set_meta("blocks_los", not currently_blocking)

	var status = "blocking" if not currently_blocking else "not blocking"
	print("%s is now %s LOS" % [terrain.name, status])


func _delete_terrain(context: Dictionary) -> void:
	var terrain = context.get("terrain") as Node3D
	if terrain:
		terrain.queue_free()
		print("Deleted terrain: %s" % terrain.name)


func _show_generic_info(context: Dictionary) -> void:
	var obj = context.get("object") as Node3D
	if obj:
		print("Object: %s" % obj.name)


func _delete_generic(context: Dictionary) -> void:
	var obj = context.get("object") as Node3D
	if obj:
		obj.queue_free()
		print("Deleted: %s" % obj.name)


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

	# Broadcast wounds change to remote peers
	if network_manager:
		network_manager.broadcast_model_wounds(model)


## Updates or creates a wound marker (red disc with border) next to a model.
func _update_wound_marker(model: ModelInstance) -> void:
	if not model.node or not is_instance_valid(model.node):
		return

	var wounds_taken = model.wounds_max - model.wounds_current
	var is_active = wounds_taken > 0

	var unit = model.unit as GameUnit if model.unit else null
	_update_token(model.node, unit, "WoundMarker", is_active, wounds_taken)


## Called when casts are changed via the casts dialog.
func _on_casts_changed(unit: GameUnit, new_casts: int) -> void:
	# Update visual caster marker if needed
	_update_caster_marker(unit)
	print("Caster points changed for %s: %d/%d" % [unit.get_name(), new_casts, GameUnit.CASTER_POINTS_CAP])

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
## Returns boundary container for multi-model units, first model for single-model units.
func _get_unit_token_node(unit: GameUnit) -> Node3D:
	# For multi-model units with boundary, use the boundary token container
	if boundary_visualizer and unit.models.size() > 1:
		return boundary_visualizer.get_token_container(unit)

	# For single-model units, use the model itself
	if unit.models.is_empty():
		return null
	var model = unit.models[0]
	if not model.node or not is_instance_valid(model.node):
		return null
	return model.node


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
func _get_base_radius(unit: GameUnit) -> float:
	var base_radius = 0.016  # Default 32mm base
	if unit and unit.unit_properties:
		var oval_width = unit.unit_properties.get("base_size_oval_width", 0)
		var oval_length = unit.unit_properties.get("base_size_oval_length", 0)
		if oval_width > 0 and oval_length > 0:
			# Use average for oval bases
			base_radius = ((oval_width + oval_length) / 4.0) * 0.001
		else:
			var base_mm = unit.unit_properties.get("base_size_round", 32)
			base_radius = (base_mm / 2.0) * 0.001
	return base_radius


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
		var other_base_radius = _get_base_radius(unit)

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
	var base_radius = _get_base_radius(unit)

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
		char_label.no_depth_test = true
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
	number_label.no_depth_test = true
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
	letter_label.no_depth_test = true
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
	var config = _token_config(marker_name)
	if not config:
		return

	# Remove marker if inactive
	if not is_active:
		if existing_marker:
			# Remove from tree immediately so _get_active_tokens won't find it
			model_node.remove_child(existing_marker)
			existing_marker.queue_free()
			# Reposition remaining tokens with animation
			_reposition_all_tokens(model_node, unit)
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
	_store_marker_color(target, marker.name, marker.color)
	_apply_marker_token(target, marker.name, marker.color, true)

	if network_manager:
		if target is ModelInstance:
			network_manager.broadcast_model_marker(target, marker.name, true)
		elif target is GameUnit:
			network_manager.broadcast_unit_marker(target, marker.name, true)


## Called when a marker is removed via the marker dialog.
func _on_marker_dialog_marker_removed(target: Variant, marker_name: String) -> void:
	_apply_marker_token(target, marker_name, Color.WHITE, false)
	_clear_marker_color(target, marker_name)

	if network_manager:
		if target is ModelInstance:
			network_manager.broadcast_model_marker(target, marker_name, false)
		elif target is GameUnit:
			network_manager.broadcast_unit_marker(target, marker_name, false)


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
	if model and model.marker_colors.has(marker_name):
		return model.marker_colors[marker_name]
	return Color(0.6, 0.6, 0.6)


## Adds/removes a dialog marker token on every model the target covers.
func _apply_marker_token(target: Variant, marker_name: String, color: Color, is_active: bool) -> void:
	if target is ModelInstance:
		_render_marker_token(target, target.unit as GameUnit, marker_name, color, is_active)
	elif target is GameUnit:
		for model in target.models:
			_render_marker_token(model, target, marker_name, color, is_active)


## Renders or removes a single dialog marker token on one model.
func _render_marker_token(model: ModelInstance, unit: GameUnit, marker_name: String, color: Color, is_active: bool) -> void:
	if not model or not model.node or not is_instance_valid(model.node):
		return
	var node_name := _marker_token_name(marker_name)
	if is_active:
		_dynamic_token_configs[node_name] = {
			"color": color,
			"label": "",  # no curved label; custom text varies, just show the letter
			"letter": _marker_token_letter(marker_name),
			"priority": MARKER_TOKEN_PRIORITY,
		}
	_update_token(model.node, unit, node_name, is_active)
	# _update_token only colors NEW tokens; re-applying a marker with a changed
	# color must recolor the existing disc too.
	if is_active:
		_recolor_token(model.node.get_node_or_null(node_name), color)


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


## Re-creates all dialog marker tokens for a unit (used after load).
func initialize_marker_tokens_for_unit(game_unit: GameUnit) -> void:
	for model in game_unit.models:
		if not model.node or not is_instance_valid(model.node):
			continue
		for marker_name in model.markers:
			_render_marker_token(model, game_unit, marker_name, _resolve_marker_color(marker_name, model), true)


## Adds/removes a dialog marker token on all models of a unit (remote sync).
func set_unit_marker_token(game_unit: GameUnit, marker_name: String, add: bool) -> void:
	for model in game_unit.models:
		_render_marker_token(model, game_unit, marker_name, _resolve_marker_color(marker_name, model), add)


## Adds/removes a dialog marker token on a single model (remote sync).
func set_model_marker_token(model: ModelInstance, marker_name: String, add: bool) -> void:
	_render_marker_token(model, model.unit as GameUnit, marker_name, _resolve_marker_color(marker_name, model), add)
