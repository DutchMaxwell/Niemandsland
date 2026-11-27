extends GdUnitTestSuite
## AiLists: NACHTMAHR's lists come from the bundle, the rules-3.6 user cache and the ai_lists_v36/ CDN
## folder, in that order; a fetched file is cached; a 3.5 cache is never read. The CDN fetch is a
## recorder stub: no network. Probe files are removed again after each test.

const PROBE_FILE := "_ai_lists_probe.json"
const OLD_CACHE := "user://ai_lists_cache"
const NEW_CACHE := "user://ai_lists_cache_v36"


## AiLists with the CDN answered from `cdn` (rel_path -> text) and every request recorded.
class Probe extends "res://scripts/ai_lists.gd":
	var fetched: Array = []
	var cdn: Dictionary = {}

	func fetch_text(rel_path: String) -> String:
		fetched.append(rel_path)
		return str(cdn.get(rel_path, ""))


var _wrote_manifest := false


func after_test() -> void:
	var paths: Array = ["%s/%s" % [OLD_CACHE, PROBE_FILE], "%s/%s" % [NEW_CACHE, PROBE_FILE]]
	if _wrote_manifest:
		paths.append("%s/_manifest.json" % NEW_CACHE)
	for p: String in paths:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	_wrote_manifest = false


func _write(dir: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open("%s/%s" % [dir, PROBE_FILE], FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_the_v36_names_differ_from_the_0_3_14_names() -> void:
	assert_str(AiLists.CDN_PATH).is_equal("ai_lists_v36")
	assert_str(AiLists.CACHE_DIR).is_equal(NEW_CACHE)
	assert_str(AiLists.DIR).is_equal("res://assets/ai_lists")


func test_a_missing_list_is_fetched_from_the_v36_folder() -> void:
	var probe: Node = auto_free(Probe.new())
	assert_str(await probe.list_text(PROBE_FILE)).is_equal("")
	assert_array(probe.fetched).is_equal(["ai_lists_v36/" + PROBE_FILE])
	assert_bool(FileAccess.file_exists("%s/%s" % [NEW_CACHE, PROBE_FILE])).is_false()


func test_a_fetched_list_is_cached_and_read_locally_next_time() -> void:
	var probe: Node = auto_free(Probe.new())
	probe.cdn = {"ai_lists_v36/" + PROBE_FILE: "from cdn"}
	assert_str(await probe.list_text(PROBE_FILE)).is_equal("from cdn")
	assert_str(FileAccess.get_file_as_string("%s/%s" % [NEW_CACHE, PROBE_FILE])).is_equal("from cdn")
	probe.cdn = {}
	assert_str(await probe.list_text(PROBE_FILE)).is_equal("from cdn")
	assert_int(probe.fetched.size()).is_equal(1)


func test_a_cached_list_is_read_before_the_cdn() -> void:
	var probe: Node = auto_free(Probe.new())
	_write(NEW_CACHE, "cached")
	assert_str(await probe.list_text(PROBE_FILE)).is_equal("cached")
	assert_array(probe.fetched).is_empty()


func test_a_cached_3_5_list_is_never_read() -> void:
	var probe: Node = auto_free(Probe.new())
	_write(OLD_CACHE, "3.5 list")
	assert_str(probe.local_text(PROBE_FILE)).is_equal("")
	_write(NEW_CACHE, "3.6 list")
	assert_str(probe.local_text(PROBE_FILE)).is_equal("3.6 list")


func test_a_cache_write_lands_in_the_v36_dir_only() -> void:
	var probe: Node = auto_free(Probe.new())
	probe.cache_write(PROBE_FILE, "v36")
	assert_str(FileAccess.get_file_as_string("%s/%s" % [NEW_CACHE, PROBE_FILE])).is_equal("v36")
	assert_bool(FileAccess.file_exists("%s/%s" % [OLD_CACHE, PROBE_FILE])).is_false()


func test_the_manifest_is_fetched_from_the_v36_folder_and_cached() -> void:
	if FileAccess.file_exists("%s/_manifest.json" % AiLists.DIR):
		return   # a dev bundle answers first; the order is proven on machines without it (CI)
	var probe: Node = auto_free(Probe.new())
	probe.cdn = {"ai_lists_v36/_manifest.json": "{\"orc_tribes\": {\"name\": \"Orc Tribes\"}}"}
	_wrote_manifest = true
	var m: Dictionary = await probe.manifest()
	assert_array(probe.fetched).is_equal(["ai_lists_v36/_manifest.json"])
	assert_str(str(m.get("orc_tribes", {}).get("name", ""))).is_equal("Orc Tribes")
	assert_bool(FileAccess.file_exists("%s/_manifest.json" % NEW_CACHE)).is_true()


func test_without_any_source_the_manifest_is_empty() -> void:
	if FileAccess.file_exists("%s/_manifest.json" % AiLists.DIR) \
			or FileAccess.file_exists("%s/_manifest.json" % NEW_CACHE):
		return   # a dev bundle or a real cache answers; the empty case is proven on a clean profile (CI)
	var probe: Node = auto_free(Probe.new())
	assert_dict(await probe.manifest()).is_empty()
	assert_array(probe.fetched).is_equal(["ai_lists_v36/_manifest.json"])
