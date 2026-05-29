extends Node
class_name TerrainLibrary
## Thin terrain spawn helper. Terrain is placed as procedural prefabs from the map
## editor (terrain_prefabs.gd + terrain_overlay.gd); this only retains the ad-hoc TTS
## terrain import/spawn path used by the (now hidden) terrain browser and save restore.

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

const INCHES_TO_METERS := 0.0254
const GRID_CELL_INCHES := 3.0


func _ready() -> void:
	# Load library on start
	call_deferred("load_library")


## Library load entry point. The legacy TTS JSON library and the generated terrain
## themes have been removed — terrain is now placed as procedural prefabs from the map
## editor. Kept so the hidden terrain browser and the ad-hoc TTS spawn path initialize
## cleanly with an empty library.
func load_library() -> void:
	categories.clear()
	all_pieces.clear()
	library_loaded.emit(categories.keys())

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
