extends Node
class_name TerrainLibrary
## Manages terrain assets loaded from TTS JSON files
## Provides data for the terrain browser UI

signal library_loaded(categories: Array)
signal terrain_spawned(terrain: Node3D)

## Structure for a single terrain piece
class TerrainPiece:
	var id: String  # Unique identifier (category_index)
	var name: String
	var description: String
	var category: String
	var mesh_url: String
	var diffuse_url: String
	var scale: Vector3 = Vector3.ONE

	func _to_string() -> String:
		return "%s (%s)" % [name, category]

## All loaded terrain pieces, organized by category
var categories: Dictionary = {}  # category_name -> Array[TerrainPiece]

## Flat list of all pieces for search
var all_pieces: Array[TerrainPiece] = []

## Reference to object_manager for spawning
var object_manager: Node3D

const TERRAIN_PATH = "res://assets/terrain/"


func _ready() -> void:
	# Load library on start
	call_deferred("load_library")


## Load all terrain JSON files from assets/terrain/
func load_library() -> void:
	categories.clear()
	all_pieces.clear()

	var dir = DirAccess.open(TERRAIN_PATH)
	if not dir:
		push_error("TerrainLibrary: Cannot open terrain directory: %s" % TERRAIN_PATH)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if file_name.ends_with(".json") and file_name != "library.json":
			var category_name = file_name.get_basename()
			_load_category(TERRAIN_PATH + file_name, category_name)
		file_name = dir.get_next()

	dir.list_dir_end()

	print("TerrainLibrary: Loaded %d pieces in %d categories" % [all_pieces.size(), categories.size()])
	library_loaded.emit(categories.keys())


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
