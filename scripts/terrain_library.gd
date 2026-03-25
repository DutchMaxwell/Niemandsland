extends Node
class_name TerrainLibrary
## Manages terrain assets loaded from TTS JSON files and Model Forge terrain themes
## Provides data for the terrain browser UI

signal library_loaded(categories: Array)
signal terrain_spawned(terrain: Node3D)

## Structure for a single terrain piece
class TerrainPiece:
	var id: String  # Unique identifier (category_index or theme_key/piece_key)
	var name: String
	var description: String
	var category: String
	var mesh_url: String
	var diffuse_url: String
	var scale: Vector3 = Vector3.ONE
	## Model Forge generated terrain fields
	var is_generated: bool = false
	var glb_path: String = ""
	var terrain_type: String = ""   ## RUINS, FOREST, CONTAINER, DANGEROUS
	var grid_footprint: String = "" ## "3x3", "2x1", etc.
	var theme_key: String = ""

	func _to_string() -> String:
		return "%s (%s)" % [name, category]

	var footprint_width: int:
		get:
			var parts := grid_footprint.split("x")
			if parts.size() >= 2:
				return int(parts[0])
			return 1

	var footprint_depth: int:
		get:
			var parts := grid_footprint.split("x")
			if parts.size() >= 2:
				return int(parts[1])
			return 1

## All loaded terrain pieces, organized by category
var categories: Dictionary = {}  # category_name -> Array[TerrainPiece]

## Flat list of all pieces for search
var all_pieces: Array[TerrainPiece] = []

## Reference to object_manager for spawning
var object_manager: Node3D

## Generated terrain theme keys
var _generated_theme_keys: Array[String] = []

const TERRAIN_PATH = "res://assets/terrain/"
const INCHES_TO_METERS := 0.0254
const GRID_CELL_INCHES := 3.0


func _ready() -> void:
	# Load library on start
	call_deferred("load_library")


## Load all terrain JSON files from assets/terrain/
func load_library() -> void:
	categories.clear()
	all_pieces.clear()
	_generated_theme_keys.clear()

	var dir = DirAccess.open(TERRAIN_PATH)
	if not dir:
		# Not an error during first run when no terrain exists yet
		library_loaded.emit([])
		return

	dir.list_dir_begin()
	var entry_name = dir.get_next()

	while entry_name != "":
		if dir.current_is_dir() and not entry_name.begins_with("."):
			# Check for Model Forge generated terrain theme (subfolder with terrain.json)
			var json_path = TERRAIN_PATH + entry_name + "/terrain.json"
			if FileAccess.file_exists(json_path):
				_load_generated_theme(json_path, entry_name)
		elif entry_name.ends_with(".json") and entry_name != "library.json":
			# Legacy TTS JSON files in root terrain directory
			var category_name = entry_name.get_basename()
			_load_category(TERRAIN_PATH + entry_name, category_name)
		entry_name = dir.get_next()

	dir.list_dir_end()

	print("TerrainLibrary: Loaded %d pieces in %d categories (%d generated themes)" % [
		all_pieces.size(), categories.size(), _generated_theme_keys.size()])
	library_loaded.emit(categories.keys())


## Parsed terrain theme data from terrain.json (modulares Format)
class TerrainThemeData:
	var theme_name: String
	var theme_key: String
	var battle_map_path: String  ## Relative path to battle_map.png
	var base_plates: Dictionary = {}  ## terrain_type -> relative path to PNG
	var walls: Array[Dictionary] = []  ## [{key, name, length_inches, height_inches, glb|texture}]
	var trees: Array[Dictionary] = []  ## [{key, name, glb}]
	var containers: Array[Dictionary] = []  ## [{key, name, glb}]

## Loaded theme data (keyed by theme_key)
var _theme_data: Dictionary = {}  ## theme_key -> TerrainThemeData


## Load a Model Forge generated terrain theme from terrain.json
func _load_generated_theme(json_path: String, folder_name: String) -> void:
	var file = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		push_warning("TerrainLibrary: Cannot open generated theme: %s" % json_path)
		return

	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("TerrainLibrary: JSON parse error in %s: %s" % [json_path, json.get_error_message()])
		return

	var data: Dictionary = json.data
	var theme_name: String = data.get("theme", folder_name)
	var theme_key: String = data.get("theme_key", folder_name)
	var base_path: String = TERRAIN_PATH + folder_name + "/"

	# Parse neues modulares Format
	var theme := TerrainThemeData.new()
	theme.theme_name = theme_name
	theme.theme_key = theme_key
	theme.battle_map_path = base_path + data.get("battle_map", "")

	# Base plates
	var bp: Dictionary = data.get("base_plates", {})
	for terrain_type: String in bp:
		theme.base_plates[terrain_type] = base_path + bp[terrain_type]

	# Walls (support both GLB and texture-based walls)
	for wall_data: Dictionary in data.get("walls", []):
		var wall_entry: Dictionary = {
			"key": wall_data.get("key", ""),
			"name": wall_data.get("name", ""),
			"length_inches": wall_data.get("length_inches", 3.0),
			"height_inches": wall_data.get("height_inches", 3.0),
		}
		if wall_data.has("texture"):
			wall_entry["texture"] = base_path + wall_data["texture"]
			wall_entry["glb"] = ""
		else:
			wall_entry["glb"] = base_path + wall_data.get("glb", "")
			wall_entry["texture"] = ""
		theme.walls.append(wall_entry)

	# Trees
	for tree_data: Dictionary in data.get("trees", []):
		theme.trees.append({
			"key": tree_data.get("key", ""),
			"name": tree_data.get("name", ""),
			"glb": base_path + tree_data.get("glb", ""),
		})

	# Containers
	for container_data: Dictionary in data.get("containers", []):
		theme.containers.append({
			"key": container_data.get("key", ""),
			"name": container_data.get("name", ""),
			"glb": base_path + container_data.get("glb", ""),
		})

	_theme_data[theme_key] = theme
	_generated_theme_keys.append(theme_key)

	# Backwards-compat: Registriere GLB-Assets als TerrainPieces
	var pieces: Array[TerrainPiece] = []

	# Fallback: Legacy "pieces" dict in terrain.json
	var pieces_dict: Dictionary = data.get("pieces", {})
	if not pieces_dict.is_empty():
		var glb_base: String = TERRAIN_PATH + folder_name + "/glb/"
		for piece_key: String in pieces_dict:
			var piece_data: Dictionary = pieces_dict[piece_key]
			var piece = TerrainPiece.new()
			piece.id = "%s/%s" % [theme_key, piece_key]
			piece.name = piece_data.get("name", piece_key)
			piece.terrain_type = piece_data.get("terrain_type", "RUINS")
			piece.grid_footprint = piece_data.get("grid_footprint", "1x1")
			piece.glb_path = glb_base + piece_data.get("glb_file", "")
			piece.theme_key = theme_key
			piece.category = theme_name
			piece.description = "%s %s" % [piece.terrain_type, piece.grid_footprint]
			piece.is_generated = true
			pieces.append(piece)
			all_pieces.append(piece)

	# Register wall/tree/container GLBs as TerrainPieces too
	for wall in theme.walls:
		var piece = TerrainPiece.new()
		piece.id = "%s/wall_%s" % [theme_key, wall["key"]]
		piece.name = wall["name"]
		piece.terrain_type = "RUINS"
		piece.grid_footprint = "1x1"
		piece.glb_path = wall["glb"]
		piece.theme_key = theme_key
		piece.category = theme_name
		piece.is_generated = true
		pieces.append(piece)
		all_pieces.append(piece)

	for tree in theme.trees:
		var piece = TerrainPiece.new()
		piece.id = "%s/tree_%s" % [theme_key, tree["key"]]
		piece.name = tree["name"]
		piece.terrain_type = "FOREST"
		piece.grid_footprint = "1x1"
		piece.glb_path = tree["glb"]
		piece.theme_key = theme_key
		piece.category = theme_name
		piece.is_generated = true
		pieces.append(piece)
		all_pieces.append(piece)

	for container in theme.containers:
		var piece = TerrainPiece.new()
		piece.id = "%s/container_%s" % [theme_key, container["key"]]
		piece.name = container["name"]
		piece.terrain_type = "CONTAINER"
		piece.grid_footprint = "1x1"
		piece.glb_path = container["glb"]
		piece.theme_key = theme_key
		piece.category = theme_name
		piece.is_generated = true
		pieces.append(piece)
		all_pieces.append(piece)

	if not pieces.is_empty():
		categories[theme_name] = pieces
		print("  [Generated: %s] %d assets (%d walls, %d trees, %d containers)" % [
			theme_name, pieces.size(), theme.walls.size(), theme.trees.size(), theme.containers.size()])


## Load a single category from a TTS JSON file
func _load_category(path: String, category_name: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("TerrainLibrary: Cannot open file: %s" % path)
		return

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_text) != OK:
		push_warning("TerrainLibrary: JSON parse error in %s" % path)
		return

	var data = json.data
	if not data is Dictionary:
		return

	var object_states = data.get("ObjectStates", [])
	if object_states.is_empty():
		return

	var pieces: Array[TerrainPiece] = []
	var index = 0

	for obj in object_states:
		var piece = _parse_object(obj, category_name, index)
		if piece:
			pieces.append(piece)
			all_pieces.append(piece)
			index += 1

	if not pieces.is_empty():
		categories[category_name] = pieces
		print("  [%s] %d pieces" % [category_name, pieces.size()])


## Parse a single TTS object into a TerrainPiece
func _parse_object(obj: Dictionary, category: String, index: int) -> TerrainPiece:
	# Only handle Custom_Model (not Custom_Assetbundle which is Unity format)
	var obj_name = obj.get("Name", "")
	if obj_name != "Custom_Model":
		return null

	var custom_mesh = obj.get("CustomMesh", {})
	var mesh_url = custom_mesh.get("MeshURL", "")

	if mesh_url.is_empty():
		return null

	var piece = TerrainPiece.new()
	piece.id = "%s_%d" % [category, index]
	piece.category = category
	piece.mesh_url = mesh_url
	piece.diffuse_url = custom_mesh.get("DiffuseURL", "")

	# Get name from Nickname, or generate one
	var nickname = obj.get("Nickname", "")
	if nickname.is_empty():
		piece.name = "%s #%d" % [category, index + 1]
	else:
		piece.name = nickname

	piece.description = obj.get("Description", "")

	# Get scale
	var transform = obj.get("Transform", {})
	piece.scale = Vector3(
		transform.get("scaleX", 1.0),
		transform.get("scaleY", 1.0),
		transform.get("scaleZ", 1.0)
	)

	return piece


## Get all categories
func get_categories() -> Array:
	return categories.keys()


## Get pieces in a category
func get_pieces_in_category(category_name: String) -> Array:
	return categories.get(category_name, [])


## Get piece by ID
func get_piece_by_id(piece_id: String) -> TerrainPiece:
	for piece in all_pieces:
		if piece.id == piece_id:
			return piece
	return null


## Search pieces by name
func search_pieces(query: String) -> Array[TerrainPiece]:
	if query.is_empty():
		return all_pieces

	var results: Array[TerrainPiece] = []
	var query_lower = query.to_lower()

	for piece in all_pieces:
		if piece.name.to_lower().contains(query_lower) or piece.category.to_lower().contains(query_lower):
			results.append(piece)

	return results


## Spawn a terrain piece at the given position
func spawn_terrain_piece(piece: TerrainPiece, position: Vector3) -> void:
	if not object_manager:
		push_error("TerrainLibrary: No object_manager set")
		return

	if piece.is_generated:
		_spawn_generated_terrain(piece, position)
		return

	if piece.mesh_url.is_empty():
		push_error("TerrainLibrary: Piece has no mesh URL")
		return

	print("Spawning terrain: %s" % piece.name)

	# Use object_manager's TTS download and spawn system
	var terrain = await object_manager.spawn_tts_terrain(
		piece.mesh_url,
		piece.diffuse_url,
		piece.scale,
		position,
		piece.name
	)

	if terrain:
		terrain_spawned.emit(terrain)
		# Broadcast to other peers if in multiplayer
		if object_manager._network_manager and object_manager._network_manager.is_multiplayer_active():
			object_manager._network_manager.broadcast_tts_terrain_spawn(
				piece.mesh_url, piece.diffuse_url, piece.scale, position, piece.name)


## Spawn a Model Forge generated terrain piece (GLB)
func _spawn_generated_terrain(piece: TerrainPiece, spawn_pos: Vector3) -> void:
	if piece.glb_path.is_empty():
		push_error("TerrainLibrary: Generated piece has no GLB path: %s" % piece.id)
		return

	var model := _load_glb_model(piece.glb_path)
	if not model:
		push_error("TerrainLibrary: Failed to load GLB: %s" % piece.glb_path)
		return

	# Scale model to match grid footprint
	_scale_to_footprint(model, piece.footprint_width, piece.footprint_depth)

	# Create StaticBody3D wrapper
	var body := StaticBody3D.new()
	body.name = piece.name.replace(" ", "_")
	body.add_to_group("terrain")
	body.add_to_group("terrain_piece")
	body.add_to_group("generated_terrain")

	# Store metadata for save/load
	body.set_meta("terrain_piece_id", piece.id)
	body.set_meta("terrain_theme_key", piece.theme_key)
	body.set_meta("terrain_type", piece.terrain_type)
	body.set_meta("grid_footprint", piece.grid_footprint)
	body.set_meta("is_generated_terrain", true)

	body.add_child(model)

	# Add collision shape based on AABB
	var aabb := _calculate_aabb(model)
	if aabb.size.length() > 0.0:
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size
		collision.shape = box
		collision.position = aabb.get_center()
		body.add_child(collision)

	# Position on table
	body.global_position = Vector3(spawn_pos.x, 0.0, spawn_pos.z)
	object_manager.add_child(body)

	print("TerrainLibrary: Spawned generated '%s' at (%.3f, %.3f)" % [piece.name, spawn_pos.x, spawn_pos.z])
	terrain_spawned.emit(body)


## Get list of available generated theme keys
func get_generated_themes() -> Array[String]:
	return _generated_theme_keys


## Get parsed theme data for a specific theme
func get_theme_data(theme_key: String) -> TerrainThemeData:
	return _theme_data.get(theme_key, null)


## Get wall definitions for a theme
func get_wall_definitions(theme_key: String) -> Array[Dictionary]:
	var theme := get_theme_data(theme_key)
	if theme:
		return theme.walls
	return []


## Get tree definitions for a theme
func get_tree_definitions(theme_key: String) -> Array[Dictionary]:
	var theme := get_theme_data(theme_key)
	if theme:
		return theme.trees
	return []


## Get container definitions for a theme
func get_container_definitions(theme_key: String) -> Array[Dictionary]:
	var theme := get_theme_data(theme_key)
	if theme:
		return theme.containers
	return []


# ==============================================================================
# MODEL LOADING (for generated terrain)
# ==============================================================================

func _load_glb_model(file_path: String) -> Node3D:
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()

	var error := gltf_doc.append_from_file(file_path, gltf_state)
	if error != OK:
		push_error("TerrainLibrary: Failed to load GLTF: %s (error %d)" % [file_path, error])
		return null

	var model_scene := gltf_doc.generate_scene(gltf_state)
	if not model_scene:
		push_error("TerrainLibrary: Failed to generate scene: %s" % file_path)
		return null

	_enable_shadows_recursive(model_scene)
	return model_scene


func _scale_to_footprint(model: Node3D, width_cells: int, depth_cells: int) -> void:
	## Scale model so it fits the target grid footprint
	var aabb := _calculate_aabb(model)
	if aabb.size.length() < 0.001:
		return

	var target_width := float(width_cells) * GRID_CELL_INCHES * INCHES_TO_METERS
	var target_depth := float(depth_cells) * GRID_CELL_INCHES * INCHES_TO_METERS

	# Uniform scale based on the larger dimension ratio (90% to leave grid gaps)
	var scale_x := target_width / maxf(aabb.size.x, 0.001)
	var scale_z := target_depth / maxf(aabb.size.z, 0.001)
	var uniform_scale := minf(scale_x, scale_z) * 0.9

	model.scale = Vector3(uniform_scale, uniform_scale, uniform_scale)


func _calculate_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var found_mesh := false

	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_aabb: AABB = child.get_aabb()
			var transformed: AABB = child.transform * mesh_aabb
			if found_mesh:
				result = result.merge(transformed)
			else:
				result = transformed
				found_mesh = true

		if child is Node3D:
			var child_aabb := _calculate_aabb(child)
			if child_aabb.size.length() > 0.0:
				var transformed: AABB = child.transform * child_aabb
				if found_mesh:
					result = result.merge(transformed)
				else:
					result = transformed
					found_mesh = true

	return result


func _enable_shadows_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child in node.get_children():
		_enable_shadows_recursive(child)
