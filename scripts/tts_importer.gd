extends Node
class_name TTSImporter
## Tabletop Simulator Save File Importer
## Parses TTS JSON saves and imports models with their textures

## Result of parsing a TTS save
class TTSParseResult:
	var objects: Array[TTSObject] = []
	var save_name: String = ""
	var error: String = ""

## Represents a single TTS custom mesh object
class TTSObject:
	var name: String = ""
	var mesh_url: String = ""
	var diffuse_url: String = ""
	var normal_url: String = ""
	var position: Vector3 = Vector3.ZERO
	var rotation: Vector3 = Vector3.ZERO
	var scale: Vector3 = Vector3.ONE
	var color: Color = Color.WHITE


## Parse a TTS save file and extract all CustomMesh objects
static func parse_tts_save(json_path: String) -> TTSParseResult:
	var result = TTSParseResult.new()

	var file = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		result.error = "Failed to open file: %s" % json_path
		return result

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_text)
	if parse_result != OK:
		result.error = "JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return result

	var data = json.data
	if not data is Dictionary:
		result.error = "Invalid TTS save format"
		return result

	result.save_name = data.get("SaveName", "Unknown")

	# Parse ObjectStates array
	var object_states = data.get("ObjectStates", [])
	_parse_objects_recursive(object_states, result.objects)

	print("TTS Import: Found %d custom mesh objects in '%s'" % [result.objects.size(), result.save_name])
	return result


## Recursively parse objects (TTS saves can have nested objects in bags/containers)
static func _parse_objects_recursive(objects: Array, output: Array[TTSObject]) -> void:
	for obj in objects:
		if not obj is Dictionary:
			continue

		# Check if this object has a CustomMesh
		var custom_mesh = obj.get("CustomMesh", null)
		if custom_mesh and custom_mesh is Dictionary:
			var tts_obj = TTSObject.new()
			tts_obj.name = obj.get("Nickname", obj.get("Name", "Unknown"))
			tts_obj.mesh_url = custom_mesh.get("MeshURL", "")
			tts_obj.diffuse_url = custom_mesh.get("DiffuseURL", "")
			tts_obj.normal_url = custom_mesh.get("NormalURL", "")

			# Parse transform
			var transform = obj.get("Transform", {})
			if transform is Dictionary:
				tts_obj.position = Vector3(
					transform.get("posX", 0.0),
					transform.get("posY", 0.0),
					transform.get("posZ", 0.0)
				)
				tts_obj.rotation = Vector3(
					transform.get("rotX", 0.0),
					transform.get("rotY", 0.0),
					transform.get("rotZ", 0.0)
				)
				tts_obj.scale = Vector3(
					transform.get("scaleX", 1.0),
					transform.get("scaleY", 1.0),
					transform.get("scaleZ", 1.0)
				)

			# Parse color
			var color_diffuse = obj.get("ColorDiffuse", {})
			if color_diffuse is Dictionary:
				tts_obj.color = Color(
					color_diffuse.get("r", 1.0),
					color_diffuse.get("g", 1.0),
					color_diffuse.get("b", 1.0)
				)

			if not tts_obj.mesh_url.is_empty():
				output.append(tts_obj)

		# Recursively check contained objects
		var contained = obj.get("ContainedObjects", [])
		if contained is Array and contained.size() > 0:
			_parse_objects_recursive(contained, output)

		# Also check States (for multi-state objects)
		var states = obj.get("States", {})
		if states is Dictionary:
			for state_key in states:
				var state = states[state_key]
				if state is Dictionary:
					_parse_objects_recursive([state], output)


## Convert a URL to TTS cache filename
## TTS uses URL-encoded filenames in its cache
static func url_to_cache_filename(url: String) -> String:
	if url.is_empty():
		return ""

	# URL encode the entire URL (TTS style)
	var encoded = url.uri_encode()
	return encoded


## Find the cache file for a URL in the given cache directory
## Returns empty string if not found
static func find_cache_file(url: String, cache_dir: String, extensions: Array[String]) -> String:
	if url.is_empty():
		return ""

	var encoded = url_to_cache_filename(url)

	# Try each extension
	for ext in extensions:
		var full_path = cache_dir.path_join(encoded + ext)
		if FileAccess.file_exists(full_path):
			return full_path

		# Also try without extension (TTS sometimes omits it)
		full_path = cache_dir.path_join(encoded)
		if FileAccess.file_exists(full_path):
			return full_path

	# Fallback: search directory for partial match
	var dir = DirAccess.open(cache_dir)
	if dir:
		dir.list_dir_begin()
		var filename = dir.get_next()
		while filename != "":
			# Check if filename contains the last part of the URL (hash)
			var url_parts = url.split("/")
			if url_parts.size() > 0:
				var hash_part = url_parts[-2] if url_parts[-1].is_empty() else url_parts[-1]
				if filename.contains(hash_part):
					dir.list_dir_end()
					return cache_dir.path_join(filename)
			filename = dir.get_next()
		dir.list_dir_end()

	return ""


## Get unique models from parse result (deduplicates by mesh URL)
static func get_unique_models(parse_result: TTSParseResult) -> Array[TTSObject]:
	var unique: Array[TTSObject] = []
	var seen_urls: Dictionary = {}

	for obj in parse_result.objects:
		if not seen_urls.has(obj.mesh_url):
			seen_urls[obj.mesh_url] = true
			unique.append(obj)

	return unique


## Generate a report of all models in the save
static func generate_report(parse_result: TTSParseResult) -> String:
	var report = "=== TTS Save Import Report ===\n"
	report += "Save Name: %s\n" % parse_result.save_name
	report += "Total Objects: %d\n\n" % parse_result.objects.size()

	var unique = get_unique_models(parse_result)
	report += "Unique Models: %d\n\n" % unique.size()

	var with_texture = 0
	var without_texture = 0

	for obj in unique:
		if obj.diffuse_url.is_empty():
			without_texture += 1
		else:
			with_texture += 1

	report += "Models with texture: %d\n" % with_texture
	report += "Models without texture: %d\n\n" % without_texture

	report += "--- Model List ---\n"
	for i in range(mini(unique.size(), 50)):  # Show first 50
		var obj = unique[i]
		var tex_status = "+" if not obj.diffuse_url.is_empty() else "-"
		report += "[%s] %s\n" % [tex_status, obj.name if not obj.name.is_empty() else "Unnamed"]

	if unique.size() > 50:
		report += "... and %d more\n" % (unique.size() - 50)

	return report
