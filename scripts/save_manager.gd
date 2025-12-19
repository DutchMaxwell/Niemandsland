extends Node
class_name SaveManager
## Manages saving and loading of game state
## Supports both local saves and multiplayer sync

signal save_completed(path: String)
signal load_completed(object_count: int)
signal load_failed(error: String)

const SAVE_VERSION = "1.0"
const SAVE_EXTENSION = "otts"  # OpenTTS Save

var object_manager: Node3D
var table: Node3D


func _ready() -> void:
	# Will be set by main.gd
	pass


## Serialize current game state to dictionary
func serialize_game_state() -> Dictionary:
	var state = {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"table": _serialize_table(),
		"objects": _serialize_objects()
	}
	return state


## Serialize table state
func _serialize_table() -> Dictionary:
	if not table:
		return {"size_feet": [6, 4]}

	return {
		"size_feet": [table.table_size.x, table.table_size.y]
	}


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
	if obj.is_in_group("tts_import"):
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

	# Load objects
	var loaded_count = _deserialize_objects(state.get("objects", []))

	print("Game loaded from: %s (%d objects)" % [path, loaded_count])
	load_completed.emit(loaded_count)
	return OK


## Deserialize table state
func _deserialize_table(table_data: Dictionary) -> void:
	if not table:
		return

	var size = table_data.get("size_feet", [6, 4])
	if size is Array and size.size() >= 2:
		table.setup_table(Vector2(size[0], size[1]))


## Deserialize all objects
func _deserialize_objects(objects_data: Array) -> int:
	if not object_manager:
		return 0

	var loaded_count = 0

	for obj_data in objects_data:
		if not obj_data is Dictionary:
			continue

		var success = _deserialize_object(obj_data)
		if success:
			loaded_count += 1

	return loaded_count


## Deserialize and spawn a single object
func _deserialize_object(data: Dictionary) -> bool:
	var obj_type = data.get("type", "")
	var position = _array_to_vector3(data.get("position", [0, 0, 0]))
	var rotation = _array_to_vector3(data.get("rotation", [0, 0, 0]))

	var spawned_obj: Node3D = null

	match obj_type:
		"tts_import":
			spawned_obj = _spawn_tts_object(data, position)
		"custom_model":
			var model_path = data.get("model_path", "")
			if not model_path.is_empty():
				spawned_obj = object_manager.spawn_custom_model(model_path, position)
		"miniature":
			spawned_obj = object_manager.spawn_miniature(position)
		"terrain":
			spawned_obj = object_manager.spawn_terrain(position)
		_:
			push_warning("Unknown object type: %s" % obj_type)
			return false

	if spawned_obj:
		spawned_obj.rotation_degrees = rotation
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
