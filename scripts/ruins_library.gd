class_name RuinsLibrary
extends Node
## Resolves the ruin shell-wall texture panels to image files delivered on demand from R2.
##
## A small bundled manifest (assets/ruins_manifest.json) maps each panel name ->
## { url, sha256, size }. The mossy masonry WebPs live on Cloudflare R2 and are
## downloaded + cached locally the first time a map with ruins is shown; until then the
## renderer keeps its bundled triplanar fallback (see terrain_overlay.gd). Textures are
## decoded from the WebP bytes at runtime, so the authored hard alpha edges survive
## without import-settings concerns (alpha scissor needs them). Mirrors BiomeLibrary; see docs/ASSET_DELIVERY.md.

# === Constants ===

const BUNDLED_MANIFEST_PATH: String = "res://assets/ruins_manifest.json"
const CACHE_DIR: String = "user://ruins_cache"
const FILE_EXTENSION: String = "webp"

## Panels the shell-wall renderer needs at runtime (masonry_source is art-source only).
const RUNTIME_PANELS: Array[String] = [
	"solid_a", "solid_b", "topdmg_a", "opening_a",
	"crumble_a", "crumble_b", "crumble_steep", "window", "normal",
]

## OPTIONAL biome-themed floor panels (cobbled base + flagstone upper platforms). Kept SEPARATE
## from RUNTIME_PANELS so they never gate the wall build: a biome whose manifest has no floor
## entry simply keeps the renderer's bundled fallback (`sandbox_floor_*.webp`). When the themed
## assets land on R2 + in the manifest, SandboxTerrainProp picks them up on its next rebuild.
const FLOOR_PANELS: Array[String] = ["floor_base", "floor_platform"]

# === Private variables ===

var _downloader: AssetDownloadManager = null
var _panels: Dictionary = {}    # panel name -> { url, sha256, size }
var _base_url: String = ""      # optional prefix for relative entry URLs
var _textures: Dictionary = {}  # panel name -> Texture2D (decoded once, then reused)

# === Lifecycle ===

func _ready() -> void:
	_downloader = AssetDownloadManager.new()
	_downloader.name = "RuinsDownloadManager"
	_downloader.cache_dir = CACHE_DIR
	_downloader.file_extension = FILE_EXTENSION
	add_child(_downloader)
	_load_bundled_manifest()

# === Public API ===

func has_panel(panel: String) -> bool:
	return _panels.has(panel)


## True when every runtime panel of the given biome theme (name prefix, e.g.
## "desert_") is already in the local cache (sync, no network).
func all_panels_cached(theme_prefix: String = "") -> bool:
	for panel in RUNTIME_PANELS:
		if get_cached_path(theme_prefix + panel).is_empty():
			return false
	return true


## True when nothing themed-floor remains to fetch for this biome: every FLOOR_PANEL the manifest
## actually declares is already cached. A panel ABSENT from the manifest counts as done (it has
## the bundled fallback, nothing to download), so a biome with no themed floors never triggers a
## fetch/rebuild. (sync, no network)
func floor_panels_cached(theme_prefix: String = "") -> bool:
	for panel in FLOOR_PANELS:
		var panel_name := theme_prefix + panel
		if has_panel(panel_name) and get_cached_path(panel_name).is_empty():
			return false
	return true


## Best-effort fetch of this biome's themed floor panels. Panels absent from the manifest are
## skipped (not an error — the bundled fallback covers them). Awaitable. Returns true when every
## DECLARED floor panel is available afterwards (false on a failed download, e.g. offline), but
## callers treat the floors as optional and never gate the wall build on this.
func ensure_floor_panels(theme_prefix: String = "") -> bool:
	var ok := true
	for panel in FLOOR_PANELS:
		var entry: Dictionary = _panels.get(theme_prefix + panel, {})
		if entry.is_empty():
			continue
		var path: String = await _downloader.ensure(_resolve_url(entry), entry.get("sha256", ""))
		if path.is_empty():
			ok = false
	return ok


## Returns the local path if the panel is already cached, else "" (sync).
func get_cached_path(panel: String) -> String:
	var entry: Dictionary = _panels.get(panel, {})
	if entry.is_empty():
		return ""
	var sha: String = entry.get("sha256", "")
	return _downloader.cache_path(sha) if _downloader.is_cached(sha) else ""


## Ensures every runtime panel of the given biome theme is cached (downloads the
## missing ones). Awaitable. Returns true when the full set is available afterwards,
## false otherwise (e.g. offline) so the caller can keep its fallback.
func ensure_all_panels(theme_prefix: String = "") -> bool:
	var ok := true
	for panel in RUNTIME_PANELS:
		var entry: Dictionary = _panels.get(theme_prefix + panel, {})
		if entry.is_empty():
			ok = false
			continue
		var path: String = await _downloader.ensure(_resolve_url(entry), entry.get("sha256", ""))
		if path.is_empty():
			ok = false
	return ok


## Decoded texture for a cached panel (mipmapped; decoded once, then reused).
## Returns null if the panel is not cached or fails to decode.
func get_texture(panel: String) -> Texture2D:
	if _textures.has(panel):
		return _textures[panel]
	var path := get_cached_path(panel)
	if path.is_empty():
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	if img.load_webp_from_buffer(bytes) != OK:
		push_warning("RuinsLibrary: failed to decode panel '%s' from %s" % [panel, path])
		return null
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[panel] = tex
	return tex

# === Private helpers ===

func _resolve_url(entry: Dictionary) -> String:
	var url: String = entry.get("url", "")
	if url.begins_with("http://") or url.begins_with("https://"):
		return url
	if not _base_url.is_empty():
		return _base_url.path_join(url)
	return url


func _load_bundled_manifest() -> void:
	if not FileAccess.file_exists(BUNDLED_MANIFEST_PATH):
		return
	apply_manifest_text(FileAccess.get_file_as_string(BUNDLED_MANIFEST_PATH))


## Parses a ruins manifest JSON string into the in-memory index (also used by tests).
func apply_manifest_text(text: String) -> void:
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	_base_url = AssetCDN.expand(data.get("base_url", ""))
	var panels: Variant = data.get("panels", {})
	if typeof(panels) == TYPE_DICTIONARY:
		_panels = panels
