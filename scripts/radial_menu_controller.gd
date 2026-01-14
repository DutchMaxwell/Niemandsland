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

## Reference to casts dialog
var casts_dialog: CastsDialog = null

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


func _toggle_fatigued(context: Dictionary) -> void:
	var game_unit = _get_game_unit_from_context(context)
	if not game_unit:
		return

	game_unit.is_fatigued = not game_unit.is_fatigued
	_update_fatigued_markers(game_unit)
	print("%s is now %s" % [game_unit.get_name(), "Fatigued" if game_unit.is_fatigued else "not Fatigued"])


func _toggle_shaken(context: Dictionary) -> void:
	var game_unit = _get_game_unit_from_context(context)
	if not game_unit:
		return

	game_unit.is_shaken = not game_unit.is_shaken
	_update_shaken_markers(game_unit)
	print("%s is now %s" % [game_unit.get_name(), "Shaken" if game_unit.is_shaken else "not Shaken"])


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


## Updates or creates a wound marker (red disc with border) next to a model.
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

	var wounds_taken = model.wounds_max - model.wounds_current

	# Create marker container if needed
	var marker: Node3D
	var number_label: Label3D

	# Marker dimensions: 20mm diameter disc
	var disc_radius = 0.010  # 10mm radius = 20mm diameter
	var disc_height = 0.003  # 3mm thick

	if existing_marker:
		marker = existing_marker
		number_label = marker.get_node_or_null("NumberLabel") as Label3D
	else:
		marker = Node3D.new()
		marker.name = marker_name
		model.node.add_child(marker)

		# Create black base disc (slightly larger for border effect)
		var border_mesh = MeshInstance3D.new()
		border_mesh.name = "Border"
		var border_cyl = CylinderMesh.new()
		border_cyl.top_radius = disc_radius + 0.001  # 1mm larger = thin border
		border_cyl.bottom_radius = disc_radius + 0.001
		border_cyl.height = disc_height
		border_mesh.mesh = border_cyl
		var border_mat = StandardMaterial3D.new()
		border_mat.albedo_color = Color(0.02, 0.02, 0.02)  # Black
		border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		border_mesh.material_override = border_mat
		border_mesh.position = Vector3(0, disc_height / 2, 0)
		marker.add_child(border_mesh)

		# Create red disc (main body) - sits on top of black border
		var disc_mesh = MeshInstance3D.new()
		disc_mesh.name = "Disc"
		var disc_cyl = CylinderMesh.new()
		disc_cyl.top_radius = disc_radius
		disc_cyl.bottom_radius = disc_radius
		disc_cyl.height = disc_height + 0.0002  # Slightly taller to sit on top
		disc_mesh.mesh = disc_cyl
		var disc_mat = StandardMaterial3D.new()
		disc_mat.albedo_color = Color(0.9, 0.15, 0.15)  # Bright red
		disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		disc_mesh.material_override = disc_mat
		disc_mesh.position = Vector3(0, disc_height / 2 + 0.0001, 0)
		marker.add_child(disc_mesh)

		# Create "WOUNDS" text along outer top edge
		_create_wound_text_arc(marker, disc_radius * 0.75, disc_height + 0.001)

		# Create number label in center (slightly lower to make room for WOUNDS text)
		number_label = Label3D.new()
		number_label.name = "NumberLabel"
		number_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		number_label.no_depth_test = true
		number_label.font_size = 72
		number_label.outline_size = 8
		number_label.modulate = Color.WHITE
		number_label.outline_modulate = Color(0.5, 0, 0)  # Dark red outline
		number_label.pixel_size = 0.00016  # Slightly smaller to fit
		number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		number_label.position = Vector3(0, disc_height + 0.001, 0.002)  # Offset toward bottom
		number_label.rotation = Vector3(-PI / 2, 0, 0)  # Face up
		marker.add_child(number_label)

		# Position marker touching the base
		var base_x_radius = 0.016  # Default 32mm base
		if model.unit:
			var game_unit = model.unit as GameUnit
			if game_unit and game_unit.unit_properties:
				# Check for oval base first
				var oval_width = game_unit.unit_properties.get("base_size_oval_width", 0)
				var oval_length = game_unit.unit_properties.get("base_size_oval_length", 0)
				if oval_width > 0 and oval_length > 0:
					# Oval base: use the narrow side (width) for X positioning
					base_x_radius = (oval_width / 2.0) * 0.001
				else:
					# Round base
					var base_mm = game_unit.unit_properties.get("base_size_round", 32)
					base_x_radius = (base_mm / 2.0) * 0.001
		# Direct contact: marker edge touches base edge
		marker.position = Vector3(base_x_radius + disc_radius, 0, 0)

	# Update number
	if number_label:
		number_label.text = str(wounds_taken)


## Creates "WOUNDS" text as an arc along the top outer edge of the disc.
func _create_wound_text_arc(parent: Node3D, radius: float, height: float) -> void:
	var text = "WOUNDS"
	var angle_per_char = PI / 10  # More spacing between letters
	var total_arc = (text.length() - 1) * angle_per_char
	var start_angle = PI / 2 + total_arc / 2  # Center at top

	for i in range(text.length()):
		var char_label = Label3D.new()
		char_label.name = "WoundChar%d" % i
		char_label.text = text[i]
		char_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		char_label.no_depth_test = true
		char_label.font_size = 24
		char_label.outline_size = 2
		char_label.modulate = Color.WHITE
		char_label.outline_modulate = Color(0.3, 0, 0)  # Dark red outline
		char_label.pixel_size = 0.0001  # Slightly larger for readability
		char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		# Position in arc at outer edge, at the TOP of the marker (negative Z)
		var angle = start_angle - i * angle_per_char
		var x = cos(angle) * radius
		var z = -sin(angle) * radius  # Negative to put at top
		char_label.position = Vector3(x, height, z)
		# Rotate to face up and follow the arc
		char_label.rotation = Vector3(-PI / 2, angle - PI / 2, 0)

		parent.add_child(char_label)


## Called when casts are changed via the casts dialog.
func _on_casts_changed(unit: GameUnit, new_casts: int) -> void:
	# Update visual caster marker if needed
	_update_caster_marker(unit)
	print("Caster points changed for %s: %d/%d" % [unit.get_name(), new_casts, GameUnit.CASTER_POINTS_CAP])


## Updates or creates a caster point marker (purple disc) next to a unit's first model.
func _update_caster_marker(unit: GameUnit) -> void:
	if unit.models.is_empty():
		return

	var model = unit.models[0]
	if not model.node or not is_instance_valid(model.node):
		return

	var marker_name = "CasterMarker"
	var existing_marker = model.node.get_node_or_null(marker_name)

	# Remove marker if unit is not a caster or has no points
	if not unit.is_caster():
		if existing_marker:
			existing_marker.queue_free()
		return

	# Marker dimensions: 20mm diameter disc
	var disc_radius = 0.010  # 10mm radius = 20mm diameter
	var disc_height = 0.003  # 3mm thick

	var marker: Node3D
	var number_label: Label3D

	if existing_marker:
		marker = existing_marker
		number_label = marker.get_node_or_null("NumberLabel") as Label3D
	else:
		marker = Node3D.new()
		marker.name = marker_name
		model.node.add_child(marker)

		# Create black base disc (border)
		var border_mesh = MeshInstance3D.new()
		border_mesh.name = "Border"
		var border_cyl = CylinderMesh.new()
		border_cyl.top_radius = disc_radius + 0.001
		border_cyl.bottom_radius = disc_radius + 0.001
		border_cyl.height = disc_height
		border_mesh.mesh = border_cyl
		var border_mat = StandardMaterial3D.new()
		border_mat.albedo_color = Color(0.02, 0.02, 0.02)
		border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		border_mesh.material_override = border_mat
		border_mesh.position = Vector3(0, disc_height / 2, 0)
		marker.add_child(border_mesh)

		# Create purple disc (main body)
		var disc_mesh = MeshInstance3D.new()
		disc_mesh.name = "Disc"
		var disc_cyl = CylinderMesh.new()
		disc_cyl.top_radius = disc_radius
		disc_cyl.bottom_radius = disc_radius
		disc_cyl.height = disc_height + 0.0002
		disc_mesh.mesh = disc_cyl
		var disc_mat = StandardMaterial3D.new()
		disc_mat.albedo_color = Color(0.6, 0.3, 0.9)  # Purple
		disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		disc_mesh.material_override = disc_mat
		disc_mesh.position = Vector3(0, disc_height / 2 + 0.0001, 0)
		marker.add_child(disc_mesh)

		# Create "CASTS" text arc
		_create_caster_text_arc(marker, disc_radius * 0.75, disc_height + 0.001)

		# Create number label in center
		number_label = Label3D.new()
		number_label.name = "NumberLabel"
		number_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		number_label.no_depth_test = true
		number_label.font_size = 72
		number_label.outline_size = 8
		number_label.modulate = Color.WHITE
		number_label.outline_modulate = Color(0.3, 0.1, 0.5)  # Dark purple outline
		number_label.pixel_size = 0.00016
		number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		number_label.position = Vector3(0, disc_height + 0.001, 0.002)
		number_label.rotation = Vector3(-PI / 2, 0, 0)
		marker.add_child(number_label)

		# Position marker on opposite side from wound marker
		var base_x_radius = 0.016
		if unit.unit_properties:
			var oval_width = unit.unit_properties.get("base_size_oval_width", 0)
			var oval_length = unit.unit_properties.get("base_size_oval_length", 0)
			if oval_width > 0 and oval_length > 0:
				base_x_radius = (oval_width / 2.0) * 0.001
			else:
				var base_mm = unit.unit_properties.get("base_size_round", 32)
				base_x_radius = (base_mm / 2.0) * 0.001
		# Position on opposite side (-X) from wound marker
		marker.position = Vector3(-(base_x_radius + disc_radius), 0, 0)

	# Update number
	if number_label:
		number_label.text = str(unit.casts_current)


## Public method to initialize caster marker for a unit after import.
## Call this for each caster unit after spawning to show the initial caster token.
func initialize_caster_marker_for_unit(game_unit: GameUnit) -> void:
	if game_unit and game_unit.is_caster():
		_update_caster_marker(game_unit)


## Creates "CASTS" text as an arc along the top outer edge of the caster disc.
func _create_caster_text_arc(parent: Node3D, radius: float, height: float) -> void:
	var text = "CASTS"
	var angle_per_char = PI / 10
	var total_arc = (text.length() - 1) * angle_per_char
	var start_angle = PI / 2 + total_arc / 2

	for i in range(text.length()):
		var char_label = Label3D.new()
		char_label.name = "CasterChar%d" % i
		char_label.text = text[i]
		char_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		char_label.no_depth_test = true
		char_label.font_size = 24
		char_label.outline_size = 2
		char_label.modulate = Color.WHITE
		char_label.outline_modulate = Color(0.3, 0.1, 0.5)  # Dark purple
		char_label.pixel_size = 0.0001
		char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		var angle = start_angle - i * angle_per_char
		var x = cos(angle) * radius
		var z = -sin(angle) * radius
		char_label.position = Vector3(x, height, z)
		char_label.rotation = Vector3(-PI / 2, angle - PI / 2, 0)

		parent.add_child(char_label)


# ===== Fatigue and Shaken Token Markers =====

## Updates fatigued markers for all models in a unit.
func _update_fatigued_markers(unit: GameUnit) -> void:
	if unit.models.is_empty():
		return
	# Only show marker on first model (like Caster marker)
	var model = unit.models[0]
	if not model.node or not is_instance_valid(model.node):
		return
	_update_status_marker(model, unit, "FatiguedMarker", unit.is_fatigued, Color(0.9, 0.6, 0.1), "FATIGUED")


## Updates shaken markers for all models in a unit.
func _update_shaken_markers(unit: GameUnit) -> void:
	if unit.models.is_empty():
		return
	# Only show marker on first model (like Caster marker)
	var model = unit.models[0]
	if not model.node or not is_instance_valid(model.node):
		return
	_update_status_marker(model, unit, "ShakenMarker", unit.is_shaken, Color(0.3, 0.5, 0.9), "SHAKEN")


## Creates or removes a status marker (disc token) next to a model.
## Style matches Wound/Caster markers: disc on ground with text arc and letter.
func _update_status_marker(model: ModelInstance, unit: GameUnit, marker_name: String, is_active: bool, color: Color, label_text: String) -> void:
	var model_node = model.node
	var existing_marker = model_node.get_node_or_null(marker_name)

	# Remove marker if status is inactive
	if not is_active:
		if existing_marker:
			existing_marker.queue_free()
		return

	# Marker dimensions: 20mm diameter disc (same as Wound/Caster)
	var disc_radius = 0.010  # 10mm radius = 20mm diameter
	var disc_height = 0.003  # 3mm thick

	# Create marker if it doesn't exist
	if not existing_marker:
		var marker = Node3D.new()
		marker.name = marker_name
		model_node.add_child(marker)

		# Create black base disc (border) - same style as Wound/Caster markers
		var border_mesh = MeshInstance3D.new()
		border_mesh.name = "Border"
		var border_cyl = CylinderMesh.new()
		border_cyl.top_radius = disc_radius + 0.001
		border_cyl.bottom_radius = disc_radius + 0.001
		border_cyl.height = disc_height
		border_mesh.mesh = border_cyl
		var border_mat = StandardMaterial3D.new()
		border_mat.albedo_color = Color(0.02, 0.02, 0.02)  # Black
		border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		border_mesh.material_override = border_mat
		border_mesh.position = Vector3(0, disc_height / 2, 0)
		marker.add_child(border_mesh)

		# Create colored disc (main body)
		var disc_mesh = MeshInstance3D.new()
		disc_mesh.name = "Disc"
		var disc_cyl = CylinderMesh.new()
		disc_cyl.top_radius = disc_radius
		disc_cyl.bottom_radius = disc_radius
		disc_cyl.height = disc_height
		disc_mesh.mesh = disc_cyl
		var disc_mat = StandardMaterial3D.new()
		disc_mat.albedo_color = color
		disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		disc_mesh.material_override = disc_mat
		disc_mesh.position = Vector3(0, disc_height / 2 + 0.0001, 0)
		marker.add_child(disc_mesh)

		# Create text arc along outer edge (like WOUNDS/CASTS)
		_create_status_text_arc(marker, label_text, disc_radius * 0.75, disc_height + 0.001, color)

		# Create letter in center (first letter of label_text)
		var letter_label = Label3D.new()
		letter_label.name = "LetterLabel"
		letter_label.text = label_text[0]  # First letter: "F" or "S"
		letter_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		letter_label.no_depth_test = true
		letter_label.font_size = 72
		letter_label.outline_size = 8
		letter_label.modulate = Color.WHITE
		letter_label.outline_modulate = color.darkened(0.4)
		letter_label.pixel_size = 0.00016
		letter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter_label.position = Vector3(0, disc_height + 0.001, 0.002)
		letter_label.rotation = Vector3(-PI / 2, 0, 0)  # Face up
		marker.add_child(letter_label)

		# Position marker next to base (on Z axis, behind/in front of model)
		var base_z_radius = 0.016  # Default 32mm base
		if unit.unit_properties:
			var oval_length = unit.unit_properties.get("base_size_oval_length", 0)
			if oval_length > 0:
				base_z_radius = (oval_length / 2.0) * 0.001
			else:
				var base_mm = unit.unit_properties.get("base_size_round", 32)
				base_z_radius = (base_mm / 2.0) * 0.001

		# Position: Fatigued in front (+Z), Shaken behind (-Z)
		var z_direction = 1.0 if marker_name == "FatiguedMarker" else -1.0
		marker.position = Vector3(0, 0, z_direction * (base_z_radius + disc_radius))


## Creates text as an arc along the outer edge of a status marker disc.
func _create_status_text_arc(parent: Node3D, text: String, radius: float, height: float, color: Color) -> void:
	var angle_per_char = PI / 10
	var total_arc = (text.length() - 1) * angle_per_char
	var start_angle = PI / 2 + total_arc / 2

	for i in range(text.length()):
		var char_label = Label3D.new()
		char_label.name = "StatusChar%d" % i
		char_label.text = text[i]
		char_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		char_label.no_depth_test = true
		char_label.font_size = 24
		char_label.outline_size = 2
		char_label.modulate = Color.WHITE
		char_label.outline_modulate = color.darkened(0.4)
		char_label.pixel_size = 0.0001
		char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		# Position in arc at outer edge
		var angle = start_angle - i * angle_per_char
		var x = cos(angle) * radius
		var z = -sin(angle) * radius
		char_label.position = Vector3(x, height, z)
		char_label.rotation = Vector3(-PI / 2, angle - PI / 2, 0)

		parent.add_child(char_label)


## Public method to initialize status markers for a unit after import.
func initialize_status_markers_for_unit(game_unit: GameUnit) -> void:
	if game_unit.is_fatigued:
		_update_fatigued_markers(game_unit)
	if game_unit.is_shaken:
		_update_shaken_markers(game_unit)
