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

## Reference to wounds dialog
var wounds_dialog: WoundsDialog = null

## Current selection context
var _current_selection: Array = []

## Is the radial menu scene loaded
var _menu_scene: PackedScene = null

## Activation markers on models
var _activation_markers: Dictionary = {}  # Node3D -> MeshInstance3D


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
	print("DEBUG: UI layer found: %s" % ui_layer)

	if not radial_menu:
		radial_menu = _menu_scene.instantiate() as RadialMenu
		ui_parent.add_child(radial_menu)
		radial_menu.action_selected.connect(_on_action_selected)

	# Create wounds dialog
	if not wounds_dialog:
		wounds_dialog = WoundsDialog.create_simple()
		ui_parent.add_child(wounds_dialog)
		wounds_dialog.wounds_changed.connect(_on_wounds_changed)


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

		if is_full_unit:
			items = RadialMenu.create_unit_menu(game_unit)
		else:
			# Single or partial model selection
			var model_instance = UnitUtils.get_model_instance(first_obj)
			print("DEBUG: model_instance from meta = %s" % model_instance)
			if model_instance:
				print("DEBUG: model_instance.wounds_max = %d" % model_instance.wounds_max)
				context["model_instance"] = model_instance
				items = RadialMenu.create_model_menu(model_instance)
			else:
				print("DEBUG: model_instance is NULL for %s" % first_obj.name)
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
		"add_marker":
			_open_marker_dialog(context)
		"toggle_activate":
			_toggle_activation(context)
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

	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % model.get_display_name())
	lines.append("Wounds: %d/%d" % [model.wounds_current, model.wounds_max])

	var weapons = model.get_weapons()
	if not weapons.is_empty():
		lines.append("")
		lines.append("[u]Weapons:[/u]")
		for weapon in weapons:
			if weapon is Dictionary:
				var w_name = weapon.get("name", "Unknown")
				var w_attacks = weapon.get("attacks", 1)
				var w_range = weapon.get("range", 0)
				var range_str = "Melee" if w_range == 0 else "%d\"" % w_range
				lines.append("• %s (%s, A%d)" % [w_name, range_str, w_attacks])

	var equipment = model.get_equipment()
	if not equipment.is_empty():
		lines.append("")
		lines.append("[u]Equipment:[/u]")
		lines.append(", ".join(equipment))

	if not model.markers.is_empty():
		lines.append("")
		lines.append("[u]Markers:[/u]")
		lines.append(", ".join(model.markers))

	print("\n".join(lines))  # TODO: Show in UI


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


func _open_marker_dialog(context: Dictionary) -> void:
	var game_unit = context.get("game_unit") as GameUnit
	var model = context.get("model_instance") as ModelInstance

	# TODO: Open marker selection dialog
	if model:
		print("Open marker dialog for model %d" % (model.model_index + 1))
	elif game_unit:
		print("Open marker dialog for unit %s" % game_unit.get_name())


func _toggle_activation(context: Dictionary) -> void:
	var game_unit = context.get("game_unit") as GameUnit
	if not game_unit:
		return

	if game_unit.is_activated:
		game_unit.is_activated = false
		_remove_activation_markers(game_unit)
		unit_deactivated.emit(game_unit)
	else:
		game_unit.activate(1)
		_add_activation_markers(game_unit)
		unit_activated.emit(game_unit)


## Adds visual activation markers to all models in a unit.
func _add_activation_markers(game_unit: GameUnit) -> void:
	# Get base size from unit properties (in mm, convert to meters)
	var base_size_mm = game_unit.unit_properties.get("base_size_round", 32)
	var base_radius_m = (base_size_mm / 2.0) * 0.001  # mm to meters

	for model in game_unit.models:
		if not model.node or not is_instance_valid(model.node):
			continue
		if model.node in _activation_markers:
			continue  # Already has marker

		# Create ring marker around the base
		var marker = MeshInstance3D.new()
		marker.name = "ActivationMarker"

		# Use a torus sized to wrap around the base
		var torus = TorusMesh.new()
		# Ring sits just outside the base
		torus.inner_radius = base_radius_m + 0.002  # 2mm outside base edge
		torus.outer_radius = base_radius_m + 0.006  # 4mm ring thickness
		marker.mesh = torus
		# TorusMesh defaults to flat (hole up), no rotation needed

		# Green glowing material
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.9, 0.3, 0.9)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.9, 0.3)
		mat.emission_energy_multiplier = 1.5
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		marker.material_override = mat

		# Position at base level (just above ground)
		marker.position = Vector3(0, 0.004, 0)

		model.node.add_child(marker)
		_activation_markers[model.node] = marker

		# Add pulsing animation with finite loops to avoid Godot 4.5 infinite loop error
		var tween = marker.create_tween()
		tween.set_loops(1000)  # Long enough for any practical use
		tween.tween_property(marker, "scale", Vector3(1.1, 1.1, 1.1), 0.5)
		tween.tween_property(marker, "scale", Vector3(1.0, 1.0, 1.0), 0.5)


## Removes activation markers from all models in a unit.
func _remove_activation_markers(game_unit: GameUnit) -> void:
	for model in game_unit.models:
		if not model.node:
			continue
		if model.node in _activation_markers:
			var marker = _activation_markers[model.node]
			if is_instance_valid(marker):
				marker.queue_free()
			_activation_markers.erase(model.node)


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

	# TODO: Open attack roll dialog
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


func _show_terrain_info(context: Dictionary) -> void:
	var terrain = context.get("terrain") as Node3D
	if terrain:
		print("Terrain: %s" % terrain.name)


func _toggle_los(context: Dictionary) -> void:
	var terrain = context.get("terrain") as Node3D
	if terrain:
		# TODO: Toggle line of sight blocking
		print("Toggle LoS for: %s" % terrain.name)


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


## Updates or creates a wound marker next to a model.
func _update_wound_marker(model: ModelInstance) -> void:
	if not model.node or not is_instance_valid(model.node):
		return

	var marker_name = "WoundMarker"
	var existing_marker = model.node.get_node_or_null(marker_name)

	# Remove marker if at full health
	if model.wounds_current >= model.wounds_max:
		if existing_marker:
			existing_marker.queue_free()
		return

	# Create marker if needed
	var marker: Label3D
	if existing_marker:
		marker = existing_marker as Label3D
	else:
		marker = Label3D.new()
		marker.name = marker_name
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.no_depth_test = true
		marker.font_size = 48
		marker.outline_size = 8
		marker.modulate = Color(1, 0.2, 0.2, 1)  # Red color
		marker.outline_modulate = Color(0, 0, 0, 1)
		model.node.add_child(marker)

		# Position marker offset from model center
		var base_radius = 0.02  # Default
		if model.unit:
			var game_unit = model.unit as GameUnit
			if game_unit and game_unit.unit_properties:
				var base_mm = game_unit.unit_properties.get("base_size_round", 32)
				base_radius = (base_mm / 2.0) * 0.001
		marker.position = Vector3(base_radius + 0.01, 0.03, 0)

	# Update text to show wounds taken (not remaining)
	var wounds_taken = model.wounds_max - model.wounds_current
	marker.text = "-%d" % wounds_taken
