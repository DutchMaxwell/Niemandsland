class_name AmbienceLibrary
extends Node
## Resolves the CC0 battlefield-ambience recordings (freesound.org, see
## tools/model_forge/fetch_ambience_audio.py for the exact sources) to OGG files
## delivered on demand from R2.
##
## A small bundled manifest (assets/ambience_manifest.json) maps each sound name ->
## { url, sha256, size, loop }. WarAmbience starts with the procedural AmbienceSynth
## sounds and hot-swaps to these recordings once cached. Mirrors HazardsLibrary;
## see docs/ASSET_DELIVERY.md.

# === Constants ===

const BUNDLED_MANIFEST_PATH: String = "res://assets/ambience_manifest.json"
const CACHE_DIR: String = "user://ambience_cache"
const FILE_EXTENSION: String = "ogg"

## Sounds the battlefield soundscape plays.
const RUNTIME_SOUNDS: Array[String] = [
	"war_artillery_a", "war_artillery_b", "war_mg_a", "war_mg_b",
	"thunder_a", "thunder_b", "rain_loop", "fire_crackle", "menu_drone",
]

# === Private variables ===

var _downloader: AssetDownloadManager = null
var _sounds: Dictionary = {}    # sound name -> { url, sha256, size, loop }
var _base_url: String = ""      # optional prefix for relative entry URLs
var _streams: Dictionary = {}   # sound name -> AudioStream (decoded once, then reused)

# === Lifecycle ===

func _ready() -> void:
	_downloader = AssetDownloadManager.new()
	_downloader.name = "AmbienceDownloadManager"
	_downloader.cache_dir = CACHE_DIR
	_downloader.file_extension = FILE_EXTENSION
	add_child(_downloader)
	_load_bundled_manifest()

# === Public API ===

func has_sound(sound: String) -> bool:
	return _sounds.has(sound)


## True when every runtime sound is already in the local cache (sync, no network).
func all_sounds_cached() -> bool:
	for sound in RUNTIME_SOUNDS:
		if get_cached_path(sound).is_empty():
			return false
	return true


## Returns the local path if the sound is already cached, else "" (sync).
func get_cached_path(sound: String) -> String:
	var entry: Dictionary = _sounds.get(sound, {})
	if entry.is_empty():
		return ""
	var sha: String = entry.get("sha256", "")
	return _downloader.cache_path(sha) if _downloader.is_cached(sha) else ""


## Ensures every runtime sound is cached (downloads the missing ones). Awaitable.
## Returns true when the full set is available afterwards, false otherwise.
func ensure_all_sounds() -> bool:
	var ok := true
	for sound in RUNTIME_SOUNDS:
		var entry: Dictionary = _sounds.get(sound, {})
		if entry.is_empty():
			ok = false
			continue
		var path: String = await _downloader.ensure(_resolve_url(entry), entry.get("sha256", ""))
		if path.is_empty():
			ok = false
	return ok


## Decoded stream for a cached sound (loop flag applied from the manifest; decoded
## once, then reused). Returns null if the sound is not cached or fails to decode.
func get_stream(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var path := get_cached_path(sound)
	if path.is_empty():
		return null
	var stream := AudioStreamOggVorbis.load_from_file(path)
	if stream == null:
		push_warning("AmbienceLibrary: failed to decode sound '%s' from %s" % [sound, path])
		return null
	stream.loop = bool(_sounds.get(sound, {}).get("loop", false))
	_streams[sound] = stream
	return stream

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


## Parses an ambience manifest JSON string into the in-memory index (used by tests).
func apply_manifest_text(text: String) -> void:
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	_base_url = AssetCDN.expand(data.get("base_url", ""))
	var sounds: Variant = data.get("sounds", {})
	if typeof(sounds) == TYPE_DICTIONARY:
		_sounds = sounds
