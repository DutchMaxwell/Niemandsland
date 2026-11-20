class_name TiefwerkLibrary
extends Node
## Resolves the authored surfaces of a generated Tiefwerk board, delivered on demand from R2: four tiling PBR sets (GPU-compressed
## .ctex: BC7 albedo, BC5 normal, BC7 ORM) and one decal atlas (three lossless WebPs) with a rectangle per cell.
##
## assets/tiefwerk_manifest.json is the bundled index. Until a file is cached nothing here blocks and the board keeps its procedural
## look (set_texture / decal_textures answer null / {}). Mirrors HazardsLibrary; see docs/ASSET_DELIVERY.md.

# === Constants ===

const BUNDLED_MANIFEST_PATH: String = "res://assets/tiefwerk_manifest.json"
const CACHE_DIR: String = "user://tiefwerk_cache"
const MAPS: Array[String] = ["albedo", "normal", "orm"]

# === Private variables ===

var _ctex_downloader: AssetDownloadManager = null
var _webp_downloader: AssetDownloadManager = null
var _godot_version: String = ""
var _base_url: String = ""
var _sets: Dictionary = {}      # set name -> { tile_in, albedo/normal/orm: { url, sha256, size } }
var _decals: Dictionary = {}    # { atlas_px, texels_per_inch, albedo/normal/orm: {..}, cells: { name: { x, y, w, h } } }
var _set_textures: Dictionary = {}    # "set/map" -> Texture2D
var _atlas_images: Dictionary = {}    # map -> Image, decoded once
var _cell_textures: Dictionary = {}   # "cell/map" -> ImageTexture

# === Lifecycle ===

func _ready() -> void:
	_ctex_downloader = _make_downloader("TiefwerkCtexDownloads", "ctex")
	_webp_downloader = _make_downloader("TiefwerkWebpDownloads", "webp")
	if FileAccess.file_exists(BUNDLED_MANIFEST_PATH):
		apply_manifest_text(FileAccess.get_file_as_string(BUNDLED_MANIFEST_PATH))

# === Public API: tiling sets ===

func set_names() -> Array:
	return _sets.keys()


## True when the manifest has this set and its .ctex files were baked for this engine's major.minor (.ctex is engine-coupled).
func has_set(set_name: String) -> bool:
	return _sets.has(set_name) and CtexLoader.ctex_compatible(_godot_version)


## Inches of board one tile covers.
func tile_in(set_name: String) -> float:
	return float(_sets.get(set_name, {}).get("tile_in", 3.0))


## Downloads the missing files of every set. Awaitable; true when all are cached afterwards.
func ensure_sets() -> bool:
	var ok := true
	for set_name: String in _sets:
		for map in MAPS:
			var e: Dictionary = _sets[set_name].get(map, {})
			if e.is_empty() or (await _ctex_downloader.ensure(_resolve_url(e), e.get("sha256", ""))).is_empty():
				ok = false
	return ok


func sets_cached() -> bool:
	for set_name: String in _sets:
		for map in MAPS:
			if _cached_path(_ctex_downloader, _sets[set_name].get(map, {})).is_empty():
				return false
	return not _sets.is_empty()


## The GPU-compressed texture of one map of a set, or null while it is not cached.
func set_texture(set_name: String, map: String) -> Texture2D:
	var key := "%s/%s" % [set_name, map]
	if not _set_textures.has(key):
		var path := _cached_path(_ctex_downloader, _sets.get(set_name, {}).get(map, {}))
		_set_textures[key] = CtexLoader.load_ctex(path) if has_set(set_name) else null
	return _set_textures[key]

# === Public API: decal atlas ===

func decal_cell_names() -> Array:
	return _decals.get("cells", {}).keys()


## Size of a cell in inches at the atlas density (so a decal can be scaled to what the artwork shows).
func cell_size_in(cell: String) -> Vector2:
	var c: Dictionary = _decals.get("cells", {}).get(cell, {})
	return Vector2(float(c.get("w", 0)), float(c.get("h", 0))) / maxf(float(_decals.get("texels_per_inch", 256)), 1.0)


func ensure_decals() -> bool:
	var ok := true
	for map in MAPS:
		var e: Dictionary = _decals.get(map, {})
		if e.is_empty() or (await _webp_downloader.ensure(_resolve_url(e), e.get("sha256", ""))).is_empty():
			ok = false
	return ok


func decals_cached() -> bool:
	return not _decals.is_empty() and MAPS.all(func(map: String) -> bool: return not _cached_path(_webp_downloader, _decals.get(map, {})).is_empty())


## {albedo, normal, orm} textures of one atlas cell (sliced once from the decoded atlas; a Decal node takes a whole texture, not a
## rectangle of one), or {} while the atlas is not cached or the cell is unknown.
func decal_textures(cell: String) -> Dictionary:
	var c: Dictionary = _decals.get("cells", {}).get(cell, {})
	if c.is_empty() or not decals_cached():
		return {}
	var out := {}
	for map in MAPS:
		var key := "%s/%s" % [cell, map]
		if not _cell_textures.has(key):
			var atlas := _atlas_image(map)
			if atlas == null:
				return {}
			var img := atlas.get_region(Rect2i(int(c["x"]), int(c["y"]), int(c["w"]), int(c["h"])))
			img.generate_mipmaps()
			_cell_textures[key] = ImageTexture.create_from_image(img)
		out[map] = _cell_textures[key]
	return out

# === Private helpers ===

func _make_downloader(node_name: String, ext: String) -> AssetDownloadManager:
	var d := AssetDownloadManager.new()
	d.name = node_name
	d.cache_dir = CACHE_DIR
	d.file_extension = ext
	add_child(d)
	return d


func _cached_path(downloader: AssetDownloadManager, entry: Dictionary) -> String:
	var sha: String = entry.get("sha256", "")
	return downloader.cache_path(sha) if downloader != null and downloader.is_cached(sha) else ""


func _atlas_image(map: String) -> Image:
	if not _atlas_images.has(map):
		var img := Image.new()
		var path := _cached_path(_webp_downloader, _decals.get(map, {}))
		if path.is_empty() or img.load_webp_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
			push_warning("TiefwerkLibrary: could not decode the decal atlas map '%s'" % map)
			return null
		_atlas_images[map] = img
	return _atlas_images[map]


func _resolve_url(entry: Dictionary) -> String:
	var url: String = entry.get("url", "")
	if url.begins_with("http://") or url.begins_with("https://") or _base_url.is_empty():
		return url
	return _base_url.path_join(url)


## Parses a manifest JSON string into the index (also used by tests).
func apply_manifest_text(text: String) -> void:
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	_godot_version = str(data.get("godot_version", ""))
	_base_url = AssetCDN.expand(data.get("base_url", ""))
	_sets = data.get("sets", {}) if typeof(data.get("sets", {})) == TYPE_DICTIONARY else {}
	_decals = data.get("decals", {}) if typeof(data.get("decals", {})) == TYPE_DICTIONARY else {}
