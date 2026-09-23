extends RefCounted
## The tree pass of TableBiomePresenter: on a dressed game table, the tree models of the terrain overlay and
## of the movable forest groups show the biome's accepted reference trees, as the reference scene dresses
## them — grassland: the canopy-dressed oak (grassland_reference.gd); desert: acacia, tundra: pine, jungle:
## swaying jungle trees, volcanic: charred monoliths (reference_biome_forest.gd). Urban keeps the game's
## trees, as the accepted urban look does.
##
## DISPLAY ONLY: every original stays in place with its meshes hidden; the reference trees are extra visual
## children. No collider, footprint, LOS volume, rule or save data changes, and undress() puts every hidden
## mesh back and removes every added tree.
##
## Frame budget: the sources (TRELLIS GLB parse, oak canopy, mesh LODs: seconds of work) are prepared on a
## worker thread once per biome per session. Until they are ready the table keeps its old trees, never an
## empty spot. Only the swap runs on the main thread (tens of ms). The mesh LODs (reference_tree_lod.gd) hold
## the frame rate: the source GLBs carry ~100k triangles each (the acacia 273k) and ship without LODs.

const LodBuilder := preload("res://scripts/visual/reference_tree_lod.gd")
const Canopy := preload("res://scripts/visual/reference_canopy.gd")
const PropsScript := preload("res://scripts/visual/reference_props.gd")
const ForestScript := preload("res://scripts/visual/reference_biome_forest.gd")
const Materials := preload("res://scripts/visual/reference_materials.gd")

## Reference biome -> manifest of its reconstructed tree (url + sha256, loaded like reference_props.gd and
## reference_biome_forest.gd load them).
const HERO_MANIFESTS := {
	"grassland": "res://assets/terrain/reference/hero/oak.json",
	"arid_desert": "res://assets/terrain/reference/forest/dry-acacia.json",
	"frozen_tundra": "res://assets/terrain/reference/forest/open-pine.json",
}
## Reference biome -> TreesLibrary prefix of the native trees it re-shades (reference_biome_forest.gd).
const NATIVE_PREFIXES := {"arid_desert": "desert_", "frozen_tundra": "tundra_", "volcanic_ash": "volcanic_",
	"alien_jungle": "jungle_"}
## The oak canopy's leaf card texture (reference_canopy.gd).
const LEAF_TEXTURE := "res://assets/terrain/reference/hero/leaf.webp"

signal trees_dressed(reference_biome: String)

## Prepared sources per reference biome, reused by every later build of this session.
static var _sources := {}
## Source jobs on the worker pool, by reference biome.
static var _jobs := {}

var _host: Node = null
var _main: Node = null
var _presentation: Node3D = null
var _dressed := false
var _preparing := {}
var _visibility := {}
var _children_before := {}
var _added: Array[Node] = []
var _watched: Array[Node] = []
var _forest: Node3D = null


## `host` owns the temporary downloader (the presenter); `main` is the Main node.
func _init(host: Node, main: Node) -> void:
	_host = host
	_main = main


## Does the reference replace this biome's trees at all?
static func has_trees(reference_biome: String) -> bool:
	return HERO_MANIFESTS.has(reference_biome) or NATIVE_PREFIXES.has(reference_biome)


## Tests: prepared sources without a download ({"hero", "natives"} or {"oak_scenes", "oak_bounds"}).
static func inject_sources(reference_biome: String, sources: Dictionary) -> void:
	_sources[reference_biome] = sources


static func clear_sources() -> void:
	_sources.clear()


func is_dressed() -> bool:
	return _dressed


## Swap the trees of the freshly built `presentation` (now if its sources are ready, else once they are).
func dress(presentation: Node3D) -> void:
	undress()
	var biome := str(presentation.biome)
	if not has_trees(biome):
		return
	_presentation = presentation
	if _sources.has(biome):
		_swap()
	else:
		_prepare(biome)


## Put the old trees back. Call before the presentation goes away.
func undress() -> void:
	_restore()
	_presentation = null


## Once per frame from the presenter (never during a build).
func process() -> void:
	for biome in _jobs.keys():
		_collect(biome)
	if not is_instance_valid(_presentation):
		_presentation = null
		return
	if not _dressed:
		if _sources.has(str(_presentation.biome)):
			_swap()
	elif _stale():
		# The overlay rebuilt its objects (a tree download finished) or a forest group re-populated:
		# swap again from the cached sources.
		_restore()
		_swap()


static func _collect(biome: String) -> void:
	var job = _jobs[biome]
	if not WorkerThreadPool.is_task_completed(job.task_id):
		return
	WorkerThreadPool.wait_for_task_completion(job.task_id)
	_jobs.erase(biome)
	_sources[biome] = job.result
	print("TABLE_TREES sources ready %s (%s)" % [biome, ", ".join(job.result.keys())])


## Main-thread part: download the reconstructed tree, make sure the native GLBs are cached, then hand the
## heavy part to the worker pool. Headless runs never download (tests inject their sources).
func _prepare(biome: String) -> void:
	if _jobs.has(biome) or _preparing.has(biome) or DisplayServer.get_name() == "headless":
		return
	_preparing[biome] = true
	if biome == "grassland":
		# The canopy reads its leaf texture through the shared reference_materials cache: fill it here, so
		# the worker only ever reads that dictionary.
		Materials.texture(LEAF_TEXTURE)
	var job := SourceJob.new()
	job.biome = biome
	job.hero_path = await _download(str(HERO_MANIFESTS.get(biome, "")))
	var prefix: String = NATIVE_PREFIXES.get(biome, "")
	var library: TreesLibrary = _main.terrain_overlay._trees_library
	if not prefix.is_empty() and library != null and await library.ensure_all_models(prefix):
		for variant in TreesLibrary.TREE_VARIANTS:
			var path := library.get_cached_model_path(prefix + variant)
			if not path.is_empty():
				job.natives[prefix + variant] = [path, library._model_scene_cache.get(path)]
	_preparing.erase(biome)
	job.task_id = WorkerThreadPool.add_task(job.run, false, "table trees " + biome)
	_jobs[biome] = job


func _download(manifest: String) -> String:
	if manifest.is_empty() or not FileAccess.file_exists(manifest):
		return ""
	var entry: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
	if not entry is Dictionary or not entry.has("url") or not entry.has("sha256"):
		return ""
	var downloader := AssetDownloadManager.new()
	downloader.cache_dir = "user://reference_terrain_cache"
	_host.add_child(downloader)
	var path: String = await downloader.ensure(AssetCDN.expand(entry.url), entry.sha256)
	downloader.queue_free()
	if path.is_empty():
		push_warning("Reference tree source unavailable; the table keeps its trees.")
	return path


func _swap() -> void:
	var biome := str(_presentation.biome)
	var sources: Dictionary = _sources[biome]
	_dressed = true
	if sources.is_empty():
		return   # no source (offline): the old trees stay
	var t0 := Time.get_ticks_usec()
	_snapshot()
	if biome == "grassland":
		_dress_oaks(sources)
	else:
		_forest = ForestScript.new()
		_forest.name = "TableTreeForest"
		_presentation.add_child(_forest)
		_forest.use_sources(biome, sources.get("hero"), sources.get("natives", {}))
		_forest.apply(_main, _presentation)
		_presentation._biome_forest = _forest
		if _presentation._jungle_motion != null:
			_presentation._jungle_motion._materials.append_array(_forest._wind_materials)
	for node: Node in _children_before:
		for child in node.get_children():
			if not _children_before[node].has(child):
				_added.append(child)
	print("TABLE_TREES swapped %s: %d trees in %.1f ms" % [biome, _added.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	trees_dressed.emit(biome)


## Grassland: the reference's oak replacement of the overlay trees (grassland_reference.gd
## _dress_grid_forest), plus the same oak on grassland forest groups (placed as reference_biome_forest.gd
## _dress_groups places its trees; the reference scene never had a movable forest).
func _dress_oaks(sources: Dictionary) -> void:
	var props: Node3D = PropsScript.new()   # only its tree_instance(); freed below
	props._tree_variants = sources["oak_scenes"]
	props._tree_bounds = sources["oak_bounds"]
	var overlay: Node3D = _main.terrain_overlay
	var dims: Vector2i = overlay._calculate_grid_dims(overlay.table_size_feet)
	var cell_size: float = overlay.GRID_SIZE_INCHES * overlay.INCHES_TO_METERS
	var rotation_angle := deg_to_rad(float(overlay.grid_rotation_degrees))
	var index := 0
	for obj: Dictionary in overlay._last_objects:
		if obj.get("object_type", "") != "tree":
			continue
		var cell: Vector2i = obj.cell
		var offset: Vector2 = obj.offset
		var x := (cell.x - dims.x / 2.0 + offset.x) * cell_size
		var z := (cell.y - dims.y / 2.0 + offset.y) * cell_size
		var expected := Vector2(x * cos(rotation_angle) - z * sin(rotation_angle), x * sin(rotation_angle) + z * cos(rotation_angle))
		for original: Node3D in overlay._object_instances:
			if Vector2(original.position.x, original.position.z).distance_squared_to(expected) > 0.000001:
				continue
			var height := clampf(overlay._model_space_aabb(original).size.y, 0.08, 0.20)
			for child in original.get_children():
				if child is Node3D:
					child.visible = false
			var tree: Node3D = props.tree_instance(height, index, Materials.ground_height(expected))
			tree.name = "ReferenceCanopy"
			original.add_child(tree)
			index += 1
			break
	for group in _main.get_tree().get_nodes_in_group(TerrainGroupBase.GROUP):
		if group.prop_kind != TerrainGroupBase.KIND_FOREST or group.biome_prefix != "":
			continue
		for member in group.get_children():
			if not member is Node3D or not member.has_meta(TerrainGroupBase.MEMBER_META):
				continue
			var bounds: AABB = overlay._model_space_aabb(member)
			for mesh in member.find_children("*", "GeometryInstance3D", true, false):
				mesh.visible = false
			if member is GeometryInstance3D:
				member.visible = false
			var tree: Node3D = props.tree_instance(bounds.size.y, 200 + index, bounds.position.y)
			tree.name = "ReferenceCanopy"
			tree.position.x = member.position.x
			tree.position.z = member.position.z
			group.add_child(tree)
			index += 1
	props.free()


## Record what the swap may touch: the visibility under every overlay object and forest group, and their
## children (anything new afterwards is ours).
func _snapshot() -> void:
	var roots: Array[Node] = []
	for original in _main.terrain_overlay._object_instances:
		if is_instance_valid(original):
			roots.append(original)
	for group in _main.get_tree().get_nodes_in_group(TerrainGroupBase.GROUP):
		if group.prop_kind == TerrainGroupBase.KIND_FOREST:
			roots.append(group)
	for root in roots:
		_watched.append(root)
		var children := {}
		for child in root.get_children():
			children[child] = true
			_watched.append(child)
		_children_before[root] = children
		for node in root.find_children("*", "Node3D", true, false):
			_visibility[node] = node.visible


func _restore() -> void:
	for node in _added:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()
	for node in _visibility:
		if is_instance_valid(node):
			node.visible = _visibility[node]
	if is_instance_valid(_forest):
		if is_instance_valid(_presentation) and _presentation._biome_forest == _forest:
			_presentation._biome_forest = null
		if _forest.get_parent() != null:
			_forest.get_parent().remove_child(_forest)
		_forest.queue_free()
	_forest = null
	_added.clear()
	_visibility.clear()
	_children_before.clear()
	_watched.clear()
	_dressed = false


func _stale() -> bool:
	for node in _watched:
		if not is_instance_valid(node):
			return true
	return false


## The heavy, thread-safe part: parse the reconstructed tree, dress the oak canopy, build mesh LODs and pack
## the scenes. Touches no node inside the scene tree.
class SourceJob extends RefCounted:
	var biome := ""
	var hero_path := ""
	## TreesLibrary model name -> [cached GLB path, the library's parsed PackedScene or null].
	var natives := {}
	var task_id := -1
	var result := {}
	var _lod_meshes := {}
	var _images := {}
	var _mipmapped_textures := {}

	func run() -> void:
		var t0 := Time.get_ticks_msec()
		if biome == "grassland":
			result = _oak_sources()
		else:
			var hero: Node = _parse(hero_path)
			result = {"hero": _pack(_lod(hero)) if hero != null else null, "natives": _native_sources()}
		print("TABLE_TREES prepared %s in %d ms (worker thread)" % [biome, Time.get_ticks_msec() - t0])

	## The oak exactly as reference_props.gd builds it: one canopy per variant, packed with its bounds.
	func _oak_sources() -> Dictionary:
		var root: Node = _parse(hero_path)
		if root == null:
			return {}
		var props: Node3D = PropsScript.new()
		var scenes: Array[PackedScene] = []
		var bounds: Array[AABB] = []
		# The canopy classifies leaf vs wood from the albedo: hand it the CPU copy (no GPU read-back).
		for texture: Texture2D in _images:
			texture.set_meta(Canopy.CPU_IMAGE_META, _images[texture])
		for variant in Canopy.VARIANTS:
			var copy: Node = root.duplicate()
			Canopy.dress(copy, variant)
			bounds.append(props._mesh_bounds(copy, Transform3D.IDENTITY, AABB()))
			scenes.append(_pack(copy))
		for texture: Texture2D in _images:
			texture.remove_meta(Canopy.CPU_IMAGE_META)
		root.free()
		props.free()
		if bounds.is_empty() or bounds[0].size.y <= 0.0:
			return {}
		return {"oak_scenes": scenes, "oak_bounds": bounds}

	func _native_sources() -> Dictionary:
		var out := {}
		for native_name in natives:
			var entry: Array = natives[native_name]
			var root: Node = null
			if entry[1] != null:
				root = (entry[1] as PackedScene).instantiate()
			else:
				root = _parse(str(entry[0]))
				if root != null:
					_fix_materials(root)
			if root != null:
				out[native_name] = _pack(_lod(root))
		return out

	func _parse(path: String) -> Node:
		if path.is_empty():
			return null
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(path, state) != OK:
			return null
		_decode_images(state)
		return document.generate_scene(state)

	## CPU copies of the GLB's embedded images, by the texture the materials use: the worker never reads a
	## texture back from the GPU (Texture2D.get_image() stalls the main thread for ~100 ms on a 4k albedo).
	func _decode_images(state: GLTFState) -> void:
		var entries: Array = state.get_json().get("images", [])
		var textures: Array = state.get_images()
		var views: Array = state.get_buffer_views()
		for i in mini(entries.size(), textures.size()):
			var entry: Dictionary = entries[i]
			if textures[i] == null or not entry.has("bufferView"):
				continue
			var data: PackedByteArray = (views[int(entry["bufferView"])] as GLTFBufferView).load_buffer_view_data(state)
			var image := Image.new()
			var mime := str(entry.get("mimeType", ""))
			var err := image.load_webp_from_buffer(data) if mime == "image/webp" \
				else (image.load_png_from_buffer(data) if mime == "image/png" else image.load_jpg_from_buffer(data))
			if err == OK:
				_images[textures[i]] = image

	## TreesLibrary._fix_runtime_materials from the CPU copies (the library's version reads the textures back
	## from the GPU): non-metallic, rough, mipmapped and anisotropic, as the table's own trees are.
	func _fix_materials(node: Node) -> void:
		if node is MeshInstance3D and node.mesh != null:
			for surface in node.mesh.get_surface_count():
				var material := node.mesh.surface_get_material(surface) as StandardMaterial3D
				if material == null:
					continue
				var adjusted := material.duplicate() as StandardMaterial3D
				adjusted.metallic = 0.0
				adjusted.roughness = 0.9
				adjusted.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				adjusted.albedo_texture = _mipmapped(adjusted.albedo_texture)
				adjusted.normal_texture = _mipmapped(adjusted.normal_texture)
				node.mesh.surface_set_material(surface, adjusted)
		for child in node.get_children():
			_fix_materials(child)

	func _mipmapped(texture: Texture2D) -> Texture2D:
		if texture == null or not _images.has(texture):
			return texture
		if _mipmapped_textures.has(texture):
			return _mipmapped_textures[texture]
		var image: Image = _images[texture]
		if image.is_compressed():
			return texture
		if not image.has_mipmaps():
			image.generate_mipmaps()
		_mipmapped_textures[texture] = ImageTexture.create_from_image(image)
		return _mipmapped_textures[texture]

	func _lod(node: Node) -> Node:
		if node is MeshInstance3D and node.mesh is ArrayMesh:
			if not _lod_meshes.has(node.mesh):
				_lod_meshes[node.mesh] = LodBuilder.with_lods(node.mesh)
			node.mesh = _lod_meshes[node.mesh]
		for child in node.get_children():
			_lod(child)
		return node

	func _pack(root: Node) -> PackedScene:
		_own(root, root)
		var packed := PackedScene.new()
		packed.pack(root)
		root.free()
		return packed

	func _own(node: Node, owner_node: Node) -> void:
		for child in node.get_children():
			child.owner = owner_node
			_own(child, owner_node)
