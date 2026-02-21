extends Node
class_name SaveManager
## Manages saving and loading of game state
## Supports both local saves and multiplayer sync

signal save_completed(path: String)
signal load_completed(object_count: int)
signal load_failed(error: String)

const SAVE_VERSION = "1.2"  # Updated for map layout + marker restore
const SAVE_EXTENSION = "otts"  # OpenTTS Save

var object_manager: Node3D
var table: Node3D
var army_manager: OPRArmyManager  # Reference for GameUnit data
var map_layout_editor: Control  # Reference to map layout editor (terrain, zones, objectives)
var terrain_overlay: Node3D  # Reference to 3D terrain overlay
var radial_menu_controller: Node  # Reference for token/marker visualization after load


func _ready() -> void:
	# Will be set by main.gd
	pass


## Serialize current game state to dictionary
func serialize_game_state() -> Dictionary:
	var state = {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"table": _serialize_table(),
		"objects": _serialize_objects(),
		"game_units": _serialize_game_units(),
		"game_state": _serialize_game_state(),
		"object_counter": object_manager._object_counter if object_manager else 0
	}
	return state


## Serialize table state including map layout (terrain, deployment, objectives)
func _serialize_table() -> Dictionary:
	if not table:
		return {"size_feet": [6, 4]}

	var data = {
		"size_feet": [table.table_size.x, table.table_size.y]
	}

	# Serialize map layout data from map_layout_editor
	if map_layout_editor:
		data["grid_rotation"] = map_layout_editor.grid_rotation_degrees
		data["deployment_type"] = map_layout_editor.deployment_type

		# Grid cells - convert Vector2i keys to strings for JSON
		var cells = {}
		for cell_pos in map_layout_editor.grid_cells:
			var key = "%d,%d" % [cell_pos.x, cell_pos.y]
			cells[key] = map_layout_editor.grid_cells[cell_pos]
		data["grid_cells"] = cells

		# Custom deployment zones (1" coordinates)
		var custom_zones = {"player1": [], "player2": []}
		for v in map_layout_editor.custom_zone_vertices_p1:
			custom_zones["player1"].append({"x": v.x, "y": v.y})
		for v in map_layout_editor.custom_zone_vertices_p2:
			custom_zones["player2"].append({"x": v.x, "y": v.y})
		data["custom_zones"] = custom_zones

		# Mission objectives (1" coordinates)
		var objectives = []
		for obj in map_layout_editor.mission_objectives:
			objectives.append({"x": obj.x, "y": obj.y})
		data["mission_objectives"] = objectives

	return data


## Serialize all objects on the table
func _serialize_objects() -> Array:
	var objects: Array = []

	if not object_manager:
		return objects

	for child in object_manager.get_children():
		if not child is Node3D:
			continue
		if not child.is_in_group("selectable"):
			continue

		var obj_data = _serialize_object(child)
		if not obj_data.is_empty():
			objects.append(obj_data)

	return objects


## Serialize a single object
func _serialize_object(obj: Node3D) -> Dictionary:
	var data: Dictionary = {}

	# Determine object type
	if obj.is_in_group("opr_unit"):
		data["type"] = "opr_unit"
		# Store GameUnit reference info
		var game_unit = obj.get_meta("game_unit", null)
		if game_unit:
			data["game_unit_id"] = game_unit.unit_id
			data["model_index"] = obj.get_meta("model_index", 0)
	elif obj.is_in_group("tts_import"):
		data["type"] = "tts_import"
		data["tts_mesh_url"] = obj.get_meta("tts_mesh_url", "")
		data["tts_diffuse_url"] = obj.get_meta("tts_diffuse_url", "")
	elif obj.is_in_group("custom_model"):
		data["type"] = "custom_model"
		data["model_path"] = obj.get_meta("model_path", "")
	elif obj.is_in_group("miniature"):
		data["type"] = "miniature"
	elif obj.is_in_group("terrain"):
		data["type"] = "terrain"
	else:
		# Unknown type, skip
		return {}

	# Common properties
	data["name"] = obj.name
	data["network_id"] = obj.get_meta("network_id", 0)
	data["position"] = [obj.global_position.x, obj.global_position.y, obj.global_position.z]
	data["rotation"] = [obj.rotation_degrees.x, obj.rotation_degrees.y, obj.rotation_degrees.z]

	return data


## Serialize all GameUnits with model-level data
func _serialize_game_units() -> Array:
	var units: Array = []

	if not army_manager:
		return units

	for game_unit in army_manager.get_all_game_units():
		var unit_data = game_unit.to_dict()

		# Add node positions for each model
		var model_positions: Array = []
		for model in game_unit.models:
			if model.node and is_instance_valid(model.node):
				model_positions.append({
					"position": [model.node.global_position.x, model.node.global_position.y, model.node.global_position.z],
					"rotation": [model.node.rotation_degrees.x, model.node.rotation_degrees.y, model.node.rotation_degrees.z],
					"visible": model.node.visible
				})
			else:
				model_positions.append(null)

		unit_data["model_positions"] = model_positions
		units.append(unit_data)

	return units


## Serialize global game state (round, turn, etc.)
func _serialize_game_state() -> Dictionary:
	return {
		"current_round": 1,  # TODO: Get from game manager when implemented
		"current_player": 1
	}


## Save game state to file
func save_game(path: String) -> Error:
	var state = serialize_game_state()

	var json_string = JSON.stringify(state, "\t")  # Pretty print with tabs

	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		var error = FileAccess.get_open_error()
		push_error("Failed to open save file: %s (error %d)" % [path, error])
		return error

	file.store_string(json_string)
	file.close()

	print("Game saved to: %s (%d objects)" % [path, state.objects.size()])
	save_completed.emit(path)
	return OK


## Load game state from file
func load_game(path: String) -> Error:
	if not FileAccess.file_exists(path):
		load_failed.emit("File not found: %s" % path)
		return ERR_FILE_NOT_FOUND

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		var error = FileAccess.get_open_error()
		load_failed.emit("Failed to open file: %s" % path)
		return error

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_error = json.parse(json_string)
	if parse_error != OK:
		load_failed.emit("JSON parse error at line %d" % json.get_error_line())
		return parse_error

	var state = json.data
	if not state is Dictionary:
		load_failed.emit("Invalid save file format")
		return ERR_INVALID_DATA

	# Validate version
	var version = state.get("version", "")
	if version != SAVE_VERSION:
		push_warning("Save file version mismatch: %s (expected %s)" % [version, SAVE_VERSION])

	# Clear current state
	if object_manager:
		object_manager.clear_all_objects()

	# Load table
	_deserialize_table(state.get("table", {}))

	# Load GameUnits first (they contain model-level state)
	var game_units_loaded = _deserialize_game_units(state.get("game_units", []))

	# Load objects (async for TTS downloads)
	var loaded_count = await _deserialize_objects(state.get("objects", []))

	# Restore game state
	_deserialize_game_state(state.get("game_state", {}))

	# Restore token/marker visualizations for all loaded game units
	_restore_markers_after_load()

	print("Game loaded from: %s (%d objects, %d game units)" % [path, loaded_count, game_units_loaded])
	load_completed.emit(loaded_count)
	return OK


## Deserialize table state including map layout (terrain, deployment, objectives)
func _deserialize_table(table_data: Dictionary) -> void:
	if not table:
		return

	var size = table_data.get("size_feet", [6, 4])
	var table_size = Vector2(6, 4)
	if size is Array and size.size() >= 2:
		table_size = Vector2(size[0], size[1])
		table.setup_table(table_size)

	# Restore map layout data
	_deserialize_map_layout(table_data, table_size)


## Deserialize map layout data (terrain grid, deployment zones, objectives)
func _deserialize_map_layout(table_data: Dictionary, table_size: Vector2) -> void:
	var grid_rotation = float(table_data.get("grid_rotation", 0.0))
	var deployment_type = int(table_data.get("deployment_type", 0))

	# Parse grid cells (string keys -> Vector2i)
	var grid_cells = {}
	var cells_data = table_data.get("grid_cells", {})
	if cells_data is Dictionary:
		for key in cells_data:
			var coords = str(key).split(",")
			if coords.size() == 2:
				var cell_pos = Vector2i(int(coords[0]), int(coords[1]))
				grid_cells[cell_pos] = int(cells_data[key])

	# Parse custom deployment zones (1" coordinates)
	var custom_p1: Array[Vector2] = []
	var custom_p2: Array[Vector2] = []
	var custom_zones = table_data.get("custom_zones", {})
	if custom_zones is Dictionary:
		for v in custom_zones.get("player1", []):
			if v is Dictionary:
				custom_p1.append(Vector2(float(v.get("x", 0)), float(v.get("y", 0))))
		for v in custom_zones.get("player2", []):
			if v is Dictionary:
				custom_p2.append(Vector2(float(v.get("x", 0)), float(v.get("y", 0))))

	# Parse mission objectives (1" coordinates)
	var objectives: Array[Vector2] = []
	for obj in table_data.get("mission_objectives", []):
		if obj is Dictionary:
			objectives.append(Vector2(float(obj.get("x", 0)), float(obj.get("y", 0))))

	# Apply to map_layout_editor (stores raw data in 1" / cell coordinates)
	if map_layout_editor:
		map_layout_editor.table_size_feet = table_size
		map_layout_editor.grid_cells = grid_cells
		map_layout_editor.grid_rotation_degrees = grid_rotation
		map_layout_editor.deployment_type = deployment_type
		map_layout_editor.custom_zone_vertices_p1 = custom_p1
		map_layout_editor.custom_zone_vertices_p2 = custom_p2
		map_layout_editor.mission_objectives = objectives

	# Apply to 3D terrain overlay
	if terrain_overlay:
		# Update terrain cells
		if terrain_overlay.has_method("update_overlay"):
			terrain_overlay.update_overlay(grid_cells, table_size, grid_rotation)

		# Set deployment zones
		if terrain_overlay.has_method("set_deployment_zones"):
			# For custom zones, set zone vertices first
			if deployment_type == 2 and map_layout_editor:
				var zone_data = map_layout_editor.get_custom_zone_data()
				if terrain_overlay.has_method("set_custom_zones"):
					terrain_overlay.set_custom_zones(zone_data.player1_world, zone_data.player2_world)
			terrain_overlay.set_deployment_zones(deployment_type)

		# Show deployment zones if a type is set
		if deployment_type > 0 and terrain_overlay.has_method("set_deployment_zones_visible"):
			terrain_overlay.set_deployment_zones_visible(true)

		# Update mission objectives (convert 1" to world coords)
		if not objectives.is_empty() and map_layout_editor:
			if map_layout_editor.has_method("get_objectives_for_overlay"):
				var world_objectives = map_layout_editor.get_objectives_for_overlay()
				if terrain_overlay.has_method("update_objectives"):
					terrain_overlay.update_objectives(world_objectives)

	print("Map layout restored: %d cells, rotation=%.1f°, deployment=%d, zones=P1:%d/P2:%d, objectives=%d" % [
		grid_cells.size(), grid_rotation, deployment_type,
		custom_p1.size(), custom_p2.size(), objectives.size()
	])


## Deserialize all objects (async for TTS downloads)
func _deserialize_objects(objects_data: Array) -> int:
	if not object_manager:
		return 0

	var loaded_count = 0

	for obj_data in objects_data:
		if not obj_data is Dictionary:
			continue

		var success = await _deserialize_object(obj_data)
		if success:
			loaded_count += 1

	return loaded_count


## Deserialize and spawn a single object (async for TTS downloads)
func _deserialize_object(data: Dictionary) -> bool:
	var obj_type = data.get("type", "")
	var position = _array_to_vector3(data.get("position", [0, 0, 0]))
	var rotation = _array_to_vector3(data.get("rotation", [0, 0, 0]))

	var spawned_obj: Node3D = null

	# Preserve network_id from serialized data (broadcast=false to avoid re-broadcasting)
	var net_id = int(data.get("network_id", -1))

	match obj_type:
		"opr_unit":
			var game_unit_id = data.get("game_unit_id", "")
			var model_idx = data.get("model_index", 0)
			if army_manager and _loaded_game_units.has(game_unit_id):
				var loaded = _loaded_game_units[game_unit_id]
				var game_unit = loaded.game_unit as GameUnit
				var props = game_unit.unit_properties
				spawned_obj = army_manager.create_model_from_properties(props)
				if spawned_obj:
					object_manager.add_child(spawned_obj)
					spawned_obj.global_position = position
					spawned_obj.rotation_degrees = rotation
					if net_id >= 0:
						spawned_obj.set_meta("network_id", net_id)
					restore_game_unit_state(spawned_obj, game_unit_id, model_idx)
					return true
			else:
				push_warning("Could not restore OPR unit: game_unit_id=%s" % game_unit_id)
			return false
		"tts_import":
			spawned_obj = await _spawn_tts_object(data, position)
		"custom_model":
			var model_path = data.get("model_path", "")
			if not model_path.is_empty():
				spawned_obj = object_manager.spawn_custom_model(model_path, position)
		"miniature":
			spawned_obj = object_manager.spawn_miniature(position, false, net_id)
		"terrain":
			spawned_obj = object_manager.spawn_terrain(position, false, net_id)
		_:
			push_warning("Unknown object type: %s" % obj_type)
			return false

	if spawned_obj:
		spawned_obj.rotation_degrees = rotation
		# Preserve serialized network_id for all object types (TTS, custom models, etc.)
		if net_id >= 0:
			spawned_obj.set_meta("network_id", net_id)
		return true

	return false


## Spawn a TTS object from saved data
func _spawn_tts_object(data: Dictionary, position: Vector3) -> Node3D:
	var mesh_url = data.get("tts_mesh_url", "")
	var diffuse_url = data.get("tts_diffuse_url", "")

	if mesh_url.is_empty():
		return null

	# Check if we have this in cache already
	var dm = TTSDownloadManager.new()
	add_child(dm)

	var mesh_path = dm.find_cached_file(mesh_url, true)
	var texture_path = ""
	if not diffuse_url.is_empty():
		texture_path = dm.find_cached_file(diffuse_url, false)

	if mesh_path.is_empty():
		# Need to download - queue it
		print("  [DOWNLOAD] %s" % mesh_url.get_file())
		dm.queue_download(mesh_url, true)
		if not diffuse_url.is_empty():
			dm.queue_download(diffuse_url, false)

		# Wait for downloads
		await dm.all_downloads_completed

		mesh_path = dm.find_cached_file(mesh_url, true)
		if not diffuse_url.is_empty():
			texture_path = dm.find_cached_file(diffuse_url, false)

	dm.queue_free()

	if mesh_path.is_empty():
		push_warning("Failed to get mesh for TTS object")
		return null

	# Load the model
	var model = object_manager._load_obj_model(mesh_path, texture_path, true)
	if not model:
		return null

	# Scale it (TTS units to meters)
	var tts_scale = 0.0254
	model.scale = Vector3(tts_scale, tts_scale, tts_scale)

	# Create wrapper
	object_manager._object_counter += 1
	var wrapper = StaticBody3D.new()
	wrapper.name = "TTS_Loaded_%d" % object_manager._object_counter
	wrapper.set_meta("network_id", object_manager._object_counter + 30000)
	wrapper.set_meta("tts_mesh_url", mesh_url)
	wrapper.set_meta("tts_diffuse_url", diffuse_url)
	wrapper.add_to_group("selectable")
	wrapper.add_to_group("tts_import")

	# Position model on base
	model.position.y = 0.003
	wrapper.add_child(model)

	# Add base
	var base = object_manager._create_miniature_base()
	wrapper.add_child(base)

	# Add collision
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.032, 0.05, 0.032)
	collision.shape = shape
	collision.position = Vector3(0, 0.025, 0)
	wrapper.add_child(collision)

	# Add selection script
	wrapper.set_script(preload("res://scripts/selectable_object.gd"))

	object_manager.add_child(wrapper)
	wrapper.global_position = position

	return wrapper


## Helper: Convert array to Vector3
func _array_to_vector3(arr: Array) -> Vector3:
	if arr.size() >= 3:
		return Vector3(arr[0], arr[1], arr[2])
	return Vector3.ZERO


## Get save file path with dialog (called from main.gd)
static func get_default_save_dir() -> String:
	var dir = OS.get_user_data_dir().path_join("saves")
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return dir


# ===== GameUnit Deserialization =====

## Temporary storage for loaded game units (used during load)
var _loaded_game_units: Dictionary = {}  # unit_id -> GameUnit


## Deserialize GameUnits from saved data
func _deserialize_game_units(units_data: Array) -> int:
	_loaded_game_units.clear()

	if units_data.is_empty():
		return 0

	var count = 0
	for unit_data in units_data:
		if not unit_data is Dictionary:
			continue

		var game_unit = GameUnit.from_dict(unit_data)
		if game_unit:
			_loaded_game_units[game_unit.unit_id] = {
				"game_unit": game_unit,
				"model_positions": unit_data.get("model_positions", [])
			}
			count += 1

	return count


## Deserialize game state (round, turn, etc.)
func _deserialize_game_state(state_data: Dictionary) -> void:
	# TODO: Apply to game manager when implemented
	var _current_round = state_data.get("current_round", 1)
	var _current_player = state_data.get("current_player", 1)


## Restore GameUnit data to a spawned model node
## Called after OPR units are re-spawned
func restore_game_unit_state(node: Node3D, unit_id: String, model_index: int) -> bool:
	if not _loaded_game_units.has(unit_id):
		return false

	var loaded_data = _loaded_game_units[unit_id]
	var game_unit = loaded_data.game_unit as GameUnit
	var model_positions = loaded_data.model_positions as Array

	if model_index >= game_unit.models.size():
		return false

	# Restore model instance reference
	var model = game_unit.models[model_index]
	model.node = node

	# Set metadata on node
	node.set_meta("game_unit", game_unit)
	node.set_meta("model_instance", model)
	node.set_meta("model_index", model_index)

	# Restore position if available
	if model_index < model_positions.size() and model_positions[model_index] != null:
		var pos_data = model_positions[model_index]
		node.global_position = _array_to_vector3(pos_data.get("position", [0, 0, 0]))
		node.rotation_degrees = _array_to_vector3(pos_data.get("rotation", [0, 0, 0]))
		node.visible = pos_data.get("visible", true)

	# Register with army manager if available
	if army_manager:
		if not army_manager.game_units.has(game_unit.unit_id):
			army_manager.game_units[game_unit.unit_id] = game_unit

	return true


## Get a loaded GameUnit by ID (for use during load process)
func get_loaded_game_unit(unit_id: String) -> GameUnit:
	if _loaded_game_units.has(unit_id):
		return _loaded_game_units[unit_id].game_unit
	return null


## Restore token/marker visualizations after loading game units
func _restore_markers_after_load() -> void:
	if not radial_menu_controller or not army_manager:
		return

	for game_unit in army_manager.get_all_game_units():
		# Status markers (fatigued, shaken, activated)
		radial_menu_controller.initialize_status_markers_for_unit(game_unit)
		# Caster markers
		radial_menu_controller.initialize_caster_marker_for_unit(game_unit)
		# Wound markers for models with damage
		radial_menu_controller.initialize_wound_markers_for_unit(game_unit)


## Clear loaded game units cache after load is complete
func clear_loaded_cache() -> void:
	_loaded_game_units.clear()
