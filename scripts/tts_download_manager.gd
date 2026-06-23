extends Node
class_name TTSDownloadManager
## Downloads and caches TTS models and textures from online URLs
## v1.0 - Initial implementation

signal download_completed(url: String, local_path: String, success: bool)
signal all_downloads_completed(results: Dictionary)
signal progress_updated(current: int, total: int, url: String)

## Cache directory for downloaded files
var cache_dir: String = "user://tts_cache"
var models_cache_dir: String
var images_cache_dir: String

## Active downloads tracking
var _pending_downloads: Array[Dictionary] = []
var _completed_downloads: Dictionary = {}  # url -> local_path
var _failed_downloads: Array[String] = []
var _current_download_idx: int = 0
var _total_downloads: int = 0
var _is_downloading: bool = false

## HTTP request node (reused)
var _http_request: HTTPRequest


func _ready() -> void:
	# Setup cache directories
	models_cache_dir = cache_dir.path_join("models")
	images_cache_dir = cache_dir.path_join("images")

	# Create directories if they don't exist
	DirAccess.make_dir_recursive_absolute(models_cache_dir)
	DirAccess.make_dir_recursive_absolute(images_cache_dir)

	# Create HTTP request node
	_http_request = HTTPRequest.new()
	_http_request.use_threads = true
	_http_request.download_chunk_size = 65536  # 64KB chunks
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)


## Get the local cache path for a URL
func get_cache_path(url: String, is_model: bool) -> String:
	if url.is_empty():
		return ""

	var base_dir = models_cache_dir if is_model else images_cache_dir
	var filename = _url_to_filename(url)
	return base_dir.path_join(filename)


## Check if a URL is already cached
func is_cached(url: String, is_model: bool) -> bool:
	var cache_path = get_cache_path(url, is_model)
	if cache_path.is_empty():
		return false

	# Check with common extensions
	var extensions = [".obj", ".OBJ", ""] if is_model else [".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG", ""]
	for ext in extensions:
		if FileAccess.file_exists(cache_path + ext):
			return true

	# Also check if file exists without extension
	return FileAccess.file_exists(cache_path)


## Find cached file path (returns empty string if not cached)
func find_cached_file(url: String, is_model: bool) -> String:
	var cache_path = get_cache_path(url, is_model)
	if cache_path.is_empty():
		return ""

	var extensions = [".obj", ".OBJ", ""] if is_model else [".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG", ""]
	for ext in extensions:
		var full_path = cache_path + ext
		if FileAccess.file_exists(full_path):
			return full_path

	if FileAccess.file_exists(cache_path):
		return cache_path

	return ""


## Queue a download (doesn't start immediately)
func queue_download(url: String, is_model: bool) -> void:
	if url.is_empty():
		return

	# Skip if already in queue or completed
	for pending in _pending_downloads:
		if pending.url == url:
			return

	if _completed_downloads.has(url):
		return

	# Check if already cached
	var cached = find_cached_file(url, is_model)
	if not cached.is_empty():
		_completed_downloads[url] = cached
		return

	_pending_downloads.append({
		"url": url,
		"is_model": is_model
	})


## Start downloading all queued files
func start_downloads() -> void:
	if _is_downloading:
		push_warning("Downloads already in progress")
		return

	if _pending_downloads.is_empty():
		print("TTS Download: No downloads needed (all cached)")
		all_downloads_completed.emit(_completed_downloads)
		return

	_is_downloading = true
	_current_download_idx = 0
	_total_downloads = _pending_downloads.size()
	_failed_downloads.clear()

	_process_next_download()


## Process the next download in queue
func _process_next_download() -> void:
	if _current_download_idx >= _pending_downloads.size():
		# All done
		_is_downloading = false
		print("TTS Download: Complete! Success: %d, Failed: %d" % [
			_completed_downloads.size(),
			_failed_downloads.size()
		])
		all_downloads_completed.emit(_completed_downloads)
		return

	var download_info = _pending_downloads[_current_download_idx]
	var url = download_info.url
	var is_model = download_info.is_model

	progress_updated.emit(_current_download_idx + 1, _total_downloads, url)

	# Determine file extension from URL or use default
	var extension = _get_extension_from_url(url, is_model)
	var cache_path = get_cache_path(url, is_model) + extension

	# Set download file
	_http_request.download_file = cache_path

	var error = _http_request.request(url)
	if error != OK:
		push_warning("TTS Download: Failed to start request for %s (error %d)" % [url, error])
		_failed_downloads.append(url)
		_current_download_idx += 1
		_process_next_download()


## Handle completed request
func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var download_info = _pending_downloads[_current_download_idx]
	var url = download_info.url
	var is_model = download_info.is_model

	var success = result == HTTPRequest.RESULT_SUCCESS and response_code == 200

	if success:
		var extension = _get_extension_from_url(url, is_model)
		var cache_path = get_cache_path(url, is_model) + extension
		_completed_downloads[url] = cache_path
		download_completed.emit(url, cache_path, true)
	else:
		_failed_downloads.append(url)
		download_completed.emit(url, "", false)
		push_warning("Download failed: result=%d, code=%d" % [result, response_code])

	_current_download_idx += 1

	# Small delay between downloads to be nice to servers
	await get_tree().create_timer(0.1).timeout
	_process_next_download()


## Convert URL to safe filename
func _url_to_filename(url: String) -> String:
	# Extract the unique hash/ID from Steam CDN URLs
	# Format: https://steamusercontent-a.akamaihd.net/ugc/XXXXX/HASH/
	var parts = url.trim_suffix("/").split("/")
	if parts.size() >= 2:
		# Use last two parts for uniqueness (often contains hash)
		var hash_part = parts[-1]
		if hash_part.is_empty() and parts.size() >= 2:
			hash_part = parts[-2]
		# Clean up and return
		return hash_part.uri_encode()

	# Fallback: encode entire URL
	return url.uri_encode().substr(0, 200)  # Limit length


## Try to determine file extension from URL
func _get_extension_from_url(url: String, is_model: bool) -> String:
	var lower_url = url.to_lower()

	# Check for explicit extension in URL
	if lower_url.ends_with(".obj"):
		return ".obj"
	elif lower_url.ends_with(".png"):
		return ".png"
	elif lower_url.ends_with(".jpg") or lower_url.ends_with(".jpeg"):
		return ".jpg"

	# Default based on type
	return ".obj" if is_model else ".png"
