extends Node
class_name OPRArmyManager
## Manages OPR armies, players, and spawned unit models
## Handles the relationship between game units and their visual representations

signal army_spawned(army: OPRApiClient.OPRArmy, models: Array[Node3D])
signal unit_hovered(unit: OPRApiClient.OPRUnit)
signal unit_unhovered()

## Player colors for army identification
const PLAYER_COLORS = {
	1: Color(0.2, 0.4, 0.8),   # Blue
	2: Color(0.8, 0.2, 0.2),   # Red
	3: Color(0.2, 0.7, 0.2),   # Green
	4: Color(0.7, 0.5, 0.1),   # Orange/Gold
}

## Reference to the object manager for spawning
var object_manager: Node3D

## Loaded armies by player
var armies: Dictionary = {}  # player_id -> OPRArmy

## Mapping from spawned model to unit data
var model_to_unit: Dictionary = {}  # Node3D -> OPRUnit

## Mapping from unit to spawned models
var unit_to_models: Dictionary = {}  # OPRUnit -> Array[Node3D]

## OPR API Client
var api_client: OPRApiClient


func _ready() -> void:
	api_client = OPRApiClient.new()
	add_child(api_client)
	api_client.army_loaded.connect(_on_army_loaded)
	api_client.import_failed.connect(_on_import_failed)


## Import army from file for a specific player
func import_army_for_player(file_path: String, player_id: int) -> void:
	var army = await api_client.import_from_file(file_path)
	if army:
		army.player_id = player_id
		armies[player_id] = army


## Spawn all units of an army on the table
func spawn_army(army: OPRApiClient.OPRArmy, start_position: Vector3 = Vector3.ZERO) -> Array[Node3D]:
	if not object_manager:
		push_error("OPRArmyManager: No object_manager set")
		return []

	var all_models: Array[Node3D] = []
	var current_pos = start_position
	var row_start_x = start_position.x
	var max_row_depth = 0.0
	var unit_spacing = 0.15  # Space between units
	var model_spacing = 0.04  # Space between models in a unit

	var player_color = PLAYER_COLORS.get(army.player_id, Color.GRAY)

	for unit in army.units:
		var unit_models = _spawn_unit(unit, current_pos, player_color)
		all_models.append_array(unit_models)

		# Store mappings
		unit_to_models[unit] = unit_models
		for model in unit_models:
			model_to_unit[model] = unit

		# Calculate next position
		var unit_width = unit.size * model_spacing
		current_pos.x += unit_width + unit_spacing

		# Track row depth for next row
		max_row_depth = max(max_row_depth, model_spacing)

		# Start new row if too wide (more than 1 meter)
		if current_pos.x - row_start_x > 1.0:
			current_pos.x = row_start_x
			current_pos.z += max_row_depth + unit_spacing
			max_row_depth = 0.0

	print("OPRArmyManager: Spawned %d models for army '%s'" % [all_models.size(), army.name])
	army_spawned.emit(army, all_models)
	return all_models


## Spawn a single unit with all its models
func _spawn_unit(unit: OPRApiClient.OPRUnit, position: Vector3, player_color: Color) -> Array[Node3D]:
	var models: Array[Node3D] = []
	var spacing = 0.04  # 40mm spacing

	for i in range(unit.size):
		var model_pos = Vector3(
			position.x + i * spacing,
			0,
			position.z
		)

		var model = _create_unit_model(unit, player_color)
		if model:
			object_manager.add_child(model)
			model.global_position = model_pos

			# Add to selectable group
			model.add_to_group("selectable")
			model.add_to_group("opr_unit")

			# Store unit reference in model metadata
			model.set_meta("opr_unit", unit)
			model.set_meta("opr_player_id", unit.get_meta("player_id", 1))

			models.append(model)

	return models


## Create a visual model for a unit (placeholder miniature with base)
func _create_unit_model(unit: OPRApiClient.OPRUnit, player_color: Color) -> StaticBody3D:
	var wrapper = StaticBody3D.new()
	wrapper.name = "OPR_%s" % unit.name.replace(" ", "_")

	# Create 32mm base
	var base_mesh = CylinderMesh.new()
	base_mesh.top_radius = 0.016  # 32mm diameter
	base_mesh.bottom_radius = 0.016
	base_mesh.height = 0.003

	var base_instance = MeshInstance3D.new()
	base_instance.mesh = base_mesh
	base_instance.position.y = 0.0015

	var base_material = StandardMaterial3D.new()
	base_material.albedo_color = player_color
	base_material.roughness = 0.7
	base_instance.material_override = base_material
	base_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	wrapper.add_child(base_instance)

	# Create placeholder body (cylinder)
	var body_height = 0.025 + randf() * 0.01  # Slight variation
	var body_mesh = CylinderMesh.new()
	body_mesh.top_radius = 0.008
	body_mesh.bottom_radius = 0.01
	body_mesh.height = body_height

	var body_instance = MeshInstance3D.new()
	body_instance.mesh = body_mesh
	body_instance.position.y = 0.003 + body_height / 2

	var body_material = StandardMaterial3D.new()
	body_material.albedo_color = player_color.lightened(0.3)
	body_material.roughness = 0.8
	body_instance.material_override = body_material
	body_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	wrapper.add_child(body_instance)

	# Create head (sphere)
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.006
	head_mesh.height = 0.012

	var head_instance = MeshInstance3D.new()
	head_instance.mesh = head_mesh
	head_instance.position.y = 0.003 + body_height + 0.006

	var head_material = StandardMaterial3D.new()
	head_material.albedo_color = Color(0.9, 0.75, 0.6)  # Skin tone
	head_material.roughness = 0.9
	head_instance.material_override = head_material
	head_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	wrapper.add_child(head_instance)

	# Add collision shape
	var collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = 0.016
	shape.height = 0.04
	collision.shape = shape
	collision.position.y = 0.02
	wrapper.add_child(collision)

	# Add script for selection
	wrapper.set_script(load("res://scripts/selectable_object.gd"))

	return wrapper


## Get unit data for a model
func get_unit_for_model(model: Node3D) -> OPRApiClient.OPRUnit:
	return model_to_unit.get(model, null)


## Get all models for a unit
func get_models_for_unit(unit: OPRApiClient.OPRUnit) -> Array:
	return unit_to_models.get(unit, [])


## Get army for a player
func get_army(player_id: int) -> OPRApiClient.OPRArmy:
	return armies.get(player_id, null)


## Clear all armies and spawned models
func clear_all() -> void:
	# Remove all spawned models
	for unit in unit_to_models:
		var models = unit_to_models[unit]
		for model in models:
			if is_instance_valid(model):
				model.queue_free()

	armies.clear()
	model_to_unit.clear()
	unit_to_models.clear()


## Clear army for a specific player
func clear_army(player_id: int) -> void:
	var army = armies.get(player_id)
	if not army:
		return

	for unit in army.units:
		if unit in unit_to_models:
			var models = unit_to_models[unit]
			for model in models:
				if is_instance_valid(model):
					model.queue_free()
				model_to_unit.erase(model)
			unit_to_models.erase(unit)

	armies.erase(player_id)


func _on_army_loaded(army: OPRApiClient.OPRArmy) -> void:
	print("Army loaded: %s" % army.name)


func _on_import_failed(error: String) -> void:
	push_error("OPR Import failed: %s" % error)
