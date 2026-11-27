extends GdUnitTestSuite
## UX-AI-PATH (0.3.15): the table loads NACHTMAHR's lists through AiLists from the rules-3.6 CDN folder
## (ai_lists_v36/; the sources and caches themselves are test/ai_lists_test.gd; the system filter of the setup's
## step 04 is test/setup_opponent_test.gd).
## The CDN fetch is a recorder stub: no network. Probe files are removed again after each test.

const PROBE_FILE := "_ux_ai_path_probe.json"
const OLD_CACHE := "user://ai_lists_cache"
const NEW_CACHE := "user://ai_lists_cache_v36"


## main.gd with the toast stubbed; its AiLists is a recorder of every requested CDN path (no bundle, no cache).
class Probe extends "res://scripts/main.gd":
	var toasts: Array = []

	func _solo_show_toast(text: String, _auto_hide_s: float = 0.0, _explain: bool = false) -> void:
		toasts.append(text)


class Lists extends AiLists:
	var fetched: Array = []

	func fetch_text(rel_path: String) -> String:
		fetched.append(rel_path)
		return ""

	func local_text(_file: String) -> String:
		return ""


func after_test() -> void:
	for d: String in [OLD_CACHE, NEW_CACHE]:
		if FileAccess.file_exists("%s/%s" % [d, PROBE_FILE]):
			DirAccess.remove_absolute("%s/%s" % [d, PROBE_FILE])


func test_a_list_is_fetched_from_the_v36_folder() -> void:
	var probe: Node = auto_free(Probe.new())
	var lists: Lists = auto_free(Lists.new())
	probe._ai_lists = lists
	await probe._load_ai_opponent_list("orc_tribes_1000.json", 2)
	assert_array(lists.fetched).is_equal(["ai_lists_v36/orc_tribes_1000.json"])
	assert_int(probe.toasts.size()).is_equal(1)


## The delivery probe's default is the v36 manifest the maintainer uploads (no --path needed).
func test_the_cdn_probe_default_follows_the_v36_folder() -> void:
	var probe_tool: Variant = load("res://tools/cdn_lists_probe.gd")
	var has_default := false
	for m: Dictionary in probe_tool.get_script_method_list():
		if str(m["name"]) == "_default_path":
			has_default = true
	assert_bool(has_default).override_failure_message(
		"cdn_lists_probe has no v36 default path").is_true()
	if has_default:
		assert_str(str(probe_tool.call("_default_path"))).is_equal("ai_lists_v36/_manifest.json")
