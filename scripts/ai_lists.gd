class_name AiLists
extends Node
## Where NACHTMAHR's opponent lists come from: the dev/arena bundle, the user cache of earlier
## downloads, and the CDN. One owner for the menu (the manifest of the setup's step 04) and the table
## (the list itself). Tests override `fetch_text` / `local_text`: no test ever reaches the CDN.

const DIR := "res://assets/ai_lists"          # dev/arena bundle — NEVER in the public repo
const CDN_PATH := "ai_lists_v36"               # <AssetCdn.HOST>/ai_lists_v36/… (rules 3.6; 0.3.14 keeps ai_lists/)
const CACHE_DIR := "user://ai_lists_cache_v36" # offline replay of fetched 3.6 lists (a 3.5 cache is never read)


## One-shot CDN text fetch (browser UA — the R2 host rejects bare clients). "" on any failure.
func fetch_text(rel_path: String) -> String:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	var err := http.request("%s/%s" % [AssetCDN.HOST, rel_path],
		["User-Agent: Mozilla/5.0 (X11; Linux x86_64) Niemandsland"])
	if err != OK:
		http.queue_free()
		return ""
	var res: Array = await http.request_completed
	http.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return ""
	return (res[3] as PackedByteArray).get_string_from_utf8()


## Local sources for a list file: the bundle first, then the user cache. "" when neither exists.
func local_text(file: String) -> String:
	var text := FileAccess.get_file_as_string("%s/%s" % [DIR, file])
	if not text.is_empty():
		return text
	return FileAccess.get_file_as_string("%s/%s" % [CACHE_DIR, file])


func cache_write(file: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var f := FileAccess.open("%s/%s" % [CACHE_DIR, file], FileAccess.WRITE)
	if f != null:
		f.store_string(text)


## The list index: bundle -> CDN (fresh, refreshes the cache) -> user cache (offline). {} when absent.
func manifest() -> Dictionary:
	var text := FileAccess.get_file_as_string("%s/_manifest.json" % DIR)
	if text.is_empty():
		text = await fetch_text("%s/_manifest.json" % CDN_PATH)
		if not text.is_empty():
			cache_write("_manifest.json", text)
		else:
			text = FileAccess.get_file_as_string("%s/_manifest.json" % CACHE_DIR)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## One list's text: bundle -> cache -> CDN (a fetched list is cached). "" when no source has it.
func list_text(file: String) -> String:
	var text := local_text(file)
	if text.is_empty():
		text = await fetch_text("%s/%s" % [CDN_PATH, file])
		if not text.is_empty():
			cache_write(file, text)
	return text
