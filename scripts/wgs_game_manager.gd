extends Node
class_name WGSGameManager
## Manages WGS (Wargaming Simulator) game synchronization with OpenTTS
## Handles importing WGS game states and spawning units on the table

signal game_imported(game: WGSClient.WGSGame)
signal units_spawned(models: Array[Node3D])
signal sync_started()
signal sync_completed()
signal sync_error(error: String)

## Reference to the object manager for spawning
var object_manager: Node3D

## WGS Client for parsing/exporting
var wgs_client: WGSClient

## Current loaded WGS game
var current_game: WGSClient.WGSGame

## Mapping from WGS unit to spawned models
var unit_to_models: Dictionary = {}  # WGSUnit -> Array[Node3D]

## Mapping from spawned model to WGS unit
var model_to_unit: Dictionary = {}  # Node3D -> WGSUnit


func _ready() -> void:
	wgs_client = WGSClient.new()
	add_child(wgs_client)
	wgs_client.game_loaded.connect(_on_game_loaded)
	wgs_client.import_failed.connect(_on_import_failed)


## Import game from WGS text file
func import_from_file(file_path: String) -> void:
	var game = wgs_client.import_from_file(file_path)
	if game:
		current_game = game
		game_imported.emit(game)


## Import game from text content (e.g., from HTTP response)
func import_from_text(content: String, game_id: String = "") -> void:
	var game = wgs_client.import_from_text(content, game_id)
	if game:
		current_game = game
		game_imported.emit(game)


## Spawn all units from the current game on the table
func spawn_game(offset: Vector3 = Vector3.ZERO) -> Array[Node3D]:
	if not current_game:
		push_error("WGSGameManager: No game loaded")
		return []

	if not object_manager:
		push_error("WGSGameManager: No object_manager set")
		return []

	var all_models: Array[Node3D] = []

	for unit in current_game.units:
		var models = _spawn_unit(unit, offset)
		all_models.append_array(models)

		# Store mappings
		unit_to_models[unit] = models
		for model in models:
			model_to_unit[model] = unit

	print("WGSGameManager: Spawned %d models for game '%s'" % [
		all_models.size(), current_game.game_id
	])

	units_spawned.emit(all_models)
	return all_models


## Spawn a single WGS unit with all its models
func _spawn_unit(unit: WGSClient.WGSUnit, offset: Vector3) -> Array[Node3D]:
	var models: Array[Node3D] = []
	var base_pos = unit.get_position_3d() + offset

	if unit.is_multibase:
		# Spawn multiple models in formation
		var spacing_x = (unit.base_width / float(unit.columns)) * WGSClient.INCH_TO_METER
		var spacing_z = (unit.base_depth / float(unit.rows)) * WGSClient.INCH_TO_METER
		var model_idx = 0

		for row in range(unit.rows):
			for col in range(unit.columns):
				if model_idx >= unit.model_count:
					break

				var model_offset = Vector3(
					col * spacing_x - (unit.base_width / 2.0 - spacing_x / 2.0) * WGSClient.INCH_TO_METER,
					0,
					row * spacing_z - (unit.base_depth / 2.0 - spacing_z / 2.0) * WGSClient.INCH_TO_METER
				)

				# Rotate offset by unit angle
				model_offset = model_offset.rotated(Vector3.UP, -unit.angle)

				var model = _create_model(unit, base_pos + model_offset)
				if model:
					model.rotation.y = -unit.angle
					models.append(model)
					model_idx += 1
	else:
		# Single model
		var model = _create_model(unit, base_pos)
		if model:
			model.rotation.y = -unit.angle
			models.append(model)

	return models


## Create a visual model for a WGS unit
func _create_model(unit: WGSClient.WGSUnit, position: Vector3) -> StaticBody3D:
	var wrapper = StaticBody3D.new()
	wrapper.name = "WGS_%s_%d" % [unit.name.replace(" ", "_").substr(0, 20), unit.index]
	wrapper.global_position = position

	var base_radius = unit.get_base_radius_meters()
	var base_height = 0.003

	# Create base
	var base_mesh = CylinderMesh.new()
	base_mesh.top_radius = base_radius
	base_mesh.bottom_radius = base_radius
	base_mesh.height = base_height

	var base_instance = MeshInstance3D.new()
	base_instance.mesh = base_mesh
	base_instance.position.y = base_height / 2.0

	var base_material = StandardMaterial3D.new()
	base_material.albedo_color = unit.color
	base_material.roughness = 0.7
	base_instance.material_override = base_material
	base_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	wrapper.add_child(base_instance)

	# Create body (cylinder placeholder) - scale gently with base size
	var scale_factor = sqrt(base_radius / 0.016)  # Gentle scaling relative to 32mm
	var body_height = (0.025 + randf() * 0.005) * scale_factor
	var body_mesh = CylinderMesh.new()
	# Narrower body relative to base for larger units
	var body_ratio = lerp(0.5, 0.35, clampf((base_radius - 0.016) / 0.03, 0.0, 1.0))
	body_mesh.top_radius = base_radius * body_ratio
	body_mesh.bottom_radius = base_radius * (body_ratio + 0.1)
	body_mesh.height = body_height

	var body_instance = MeshInstance3D.new()
	body_instance.mesh = body_mesh
	body_instance.position.y = base_height + body_height / 2.0

	var body_material = StandardMaterial3D.new()
	body_material.albedo_color = unit.color.lightened(0.3)
	body_material.roughness = 0.8
	body_instance.material_override = body_material
	body_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	wrapper.add_child(body_instance)

	# Create head (sphere) - scaled to body
	var head_radius = base_radius * 0.35 * body_ratio / 0.5  # Scale with body
	var head_mesh = SphereMesh.new()
	head_mesh.radius = head_radius
	head_mesh.height = head_radius * 2

	var head_instance = MeshInstance3D.new()
	head_instance.mesh = head_mesh
	head_instance.position.y = base_height + body_height + head_radius

	var head_material = StandardMaterial3D.new()
	head_material.albedo_color = Color(0.9, 0.75, 0.6)  # Skin tone
	head_material.roughness = 0.9
	head_instance.material_override = head_material
	head_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	wrapper.add_child(head_instance)

	# Add collision shape
	var total_height = base_height + body_height + head_radius * 2
	var collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = base_radius
	shape.height = total_height
	collision.shape = shape
	collision.position.y = total_height / 2.0
	wrapper.add_child(collision)

	# Add to object manager
	object_manager.add_child(wrapper)

	# Add to groups
	wrapper.add_to_group("selectable")
	wrapper.add_to_group("wgs_unit")
	wrapper.add_to_group("miniature")

	# Store WGS metadata
	wrapper.set_meta("wgs_unit", unit)
	wrapper.set_meta("wgs_game_id", current_game.game_id if current_game else "")
	wrapper.set_meta("original_color", unit.color)

	# Add selectable script if available
	var script_path = "res://scripts/selectable_object.gd"
	if ResourceLoader.exists(script_path):
		wrapper.set_script(load(script_path))

	return wrapper


## Get current game state as WGS text (for export)
func export_current_state() -> String:
	if not current_game:
		return ""

	# Update unit positions from current model positions
	_update_units_from_models()

	return wgs_client.export_to_text(current_game)


## Update WGS unit data from current model positions
func _update_units_from_models() -> void:
	for unit in unit_to_models:
		var models = unit_to_models[unit]
		if models.is_empty():
			continue

		# Use first model as unit position reference
		var first_model: Node3D = models[0]
		if is_instance_valid(first_model):
			var wgs_pos = wgs_client.position_to_wgs(first_model.global_position)
			unit.position_x = wgs_pos.x
			unit.position_y = wgs_pos.y
			unit.angle = wgs_client.rotation_to_wgs_angle(first_model.rotation.y)


## Generate move action string for current state changes
func generate_move_action() -> String:
	if not current_game:
		return ""

	var moves: Array = []

	for unit in unit_to_models:
		var models = unit_to_models[unit]
		if models.is_empty():
			continue

		var first_model: Node3D = models[0]
		if is_instance_valid(first_model):
			var wgs_pos = wgs_client.position_to_wgs(first_model.global_position)
			moves.append({
				"index": unit.index,
				"x": wgs_pos.x,
				"y": wgs_pos.y,
				"angle": -first_model.rotation.y
			})

	return wgs_client.create_move_action(current_game.game_id, moves)


## Get unit data for a model
func get_unit_for_model(model: Node3D) -> WGSClient.WGSUnit:
	return model_to_unit.get(model, null)


## Get all models for a unit
func get_models_for_unit(unit: WGSClient.WGSUnit) -> Array:
	return unit_to_models.get(unit, [])


## Clear all spawned WGS units
func clear_all() -> void:
	for unit in unit_to_models:
		var models = unit_to_models[unit]
		for model in models:
			if is_instance_valid(model):
				model.queue_free()

	unit_to_models.clear()
	model_to_unit.clear()
	current_game = null


## Get stats text for hover tooltip
func get_unit_stats_text(model: Node3D) -> String:
	var unit = get_unit_for_model(model)
	if unit:
		return unit.get_stats_text()
	return ""


func _on_game_loaded(game: WGSClient.WGSGame) -> void:
	print("WGSGameManager: Game loaded: %s" % game.game_id)


func _on_import_failed(error: String) -> void:
	push_error("WGS Import failed: %s" % error)
	sync_error.emit(error)


## HTTP-based sync with WGS server (for future async play support)
## This would fetch the current game state from the WGS server

var http_request: HTTPRequest

func fetch_game_from_server(game_id: String, base_url: String = "https://udos3dworld.com/WargamingSimulator/") -> void:
	sync_started.emit()

	if not http_request:
		http_request = HTTPRequest.new()
		add_child(http_request)
		http_request.request_completed.connect(_on_fetch_completed)

	var url = "%sGetGameState.php?gameID=%s" % [base_url, game_id]
	var error = http_request.request(url)

	if error != OK:
		sync_error.emit("HTTP request failed: %d" % error)


func _on_fetch_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		sync_error.emit("HTTP request failed with result: %d" % result)
		return

	if response_code != 200:
		sync_error.emit("Server returned error: %d" % response_code)
		return

	var content = body.get_string_from_utf8()
	import_from_text(content)
	sync_completed.emit()
