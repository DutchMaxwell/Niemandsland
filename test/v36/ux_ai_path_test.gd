extends GdUnitTestSuite
## UX-AI-PATH (0.3.15): NACHTMAHR's opponent lists come from their own rules-3.6 CDN folder
## (ai_lists_v36/) and user cache (user://ai_lists_cache_v36) — 0.3.14 keeps ai_lists/ and
## user://ai_lists_cache, and a cached 3.5 list is never read by 3.6. The AI Opponent dialog offers only
## the lists of the system the human army plays (an entry without "system" counts as "gf"); with no
## human army it offers all, suffixed " (GF)" / " (AoF)" when the manifest mixes both.
## The CDN fetch is a recorder stub: no network. Probe files are removed again after each test.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const PROBE_FILE := "_ux_ai_path_probe.json"
const OLD_CACHE := "user://ai_lists_cache"
const NEW_CACHE := "user://ai_lists_cache_v36"
const MIXED := {
	"orc_tribes": {"name": "Orc Tribes", "system": "gf", "lists": [{"points": 1000, "file": "orc_tribes_1000.json"}]},
	"aof_orc_tribes": {"name": "Orc Tribes", "system": "aof", "lists": [{"points": 1000, "file": "aof_orc_tribes_1000.json"}]},
	"old_guard": {"name": "Old Guard", "lists": [{"points": 750, "file": "old_guard_750.json"}]},
}


## main.gd with the CDN fetch, the local read and the toast stubbed: records every requested CDN path.
class Probe extends "res://scripts/main.gd":
	var fetched: Array = []
	var toasts: Array = []
	var stub_local := true

	func _fetch_cdn_text(rel_path: String) -> String:
		fetched.append(rel_path)
		return ""

	func _ai_lists_local_text(file: String) -> String:
		return "" if stub_local else super(file)

	func _solo_show_toast(text: String, _auto_hide_s: float = 0.0, _explain: bool = false) -> void:
		toasts.append(text)


var _root_before: Array = []
var _booted := false


func after_test() -> void:
	if _booted:
		E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
		_booted = false
	for d: String in [OLD_CACHE, NEW_CACHE]:
		if FileAccess.file_exists("%s/%s" % [d, PROBE_FILE]):
			DirAccess.remove_absolute("%s/%s" % [d, PROBE_FILE])


func _write(dir: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open("%s/%s" % [dir, PROBE_FILE], FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_the_v36_names_differ_from_the_0_3_14_names() -> void:
	var probe: Node = auto_free(Probe.new())
	assert_str(probe.AI_LISTS_CDN_PATH).is_equal("ai_lists_v36")
	assert_str(probe.AI_LISTS_CACHE_DIR).is_equal(NEW_CACHE)
	assert_str(probe.AI_LISTS_CDN_PATH).is_not_equal("ai_lists")
	assert_str(probe.AI_LISTS_CACHE_DIR).is_not_equal(OLD_CACHE)


func test_a_list_is_fetched_from_the_v36_folder() -> void:
	var probe: Node = auto_free(Probe.new())
	await probe._load_ai_opponent_list("orc_tribes_1000.json", 2)
	assert_array(probe.fetched).is_equal(["ai_lists_v36/orc_tribes_1000.json"])
	assert_int(probe.toasts.size()).is_equal(1)


func test_the_manifest_is_fetched_from_the_v36_folder() -> void:
	var probe: Node = auto_free(Probe.new())
	await probe._load_ai_list_manifest()
	assert_array(probe.fetched).is_equal(["ai_lists_v36/_manifest.json"])


func test_a_cache_write_lands_in_the_v36_dir_only() -> void:
	var probe: Node = auto_free(Probe.new())
	probe._ai_lists_cache_write(PROBE_FILE, "v36")
	assert_str(FileAccess.get_file_as_string("%s/%s" % [NEW_CACHE, PROBE_FILE])).is_equal("v36")
	assert_bool(FileAccess.file_exists("%s/%s" % [OLD_CACHE, PROBE_FILE])).is_false()


func test_a_cached_3_5_list_is_never_read() -> void:
	var probe: Node = auto_free(Probe.new())
	probe.stub_local = false
	_write(OLD_CACHE, "3.5 list")
	assert_str(probe._ai_lists_local_text(PROBE_FILE)).is_equal("")
	_write(NEW_CACHE, "3.6 list")
	assert_str(probe._ai_lists_local_text(PROBE_FILE)).is_equal("3.6 list")


## The AI Opponent dialog over `manifest` with the human slot holding an army of `system` ("" = none):
## the offered faction names, or ["<no dialog>"] when the dialog did not open.
func _offered(manifest: Dictionary, system: String) -> Array:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_booted = true
	var runner := scene_runner(E2EBoot.MAIN_SCENE)
	var main: Node = runner.scene()
	await runner.simulate_frames(4)
	var slot: int = main.solo_controller.human_slot if main.solo_controller != null else 1
	main.opr_army_manager.armies.erase(slot)
	if not system.is_empty():
		var army := OPRApiClient.OPRArmy.new()
		army.game_system_abbrev = system
		army.points = 1000
		main.opr_army_manager.armies[slot] = army
	main._show_ai_opponent_dialog(manifest, func(_f: String, _s: int) -> void: pass)
	await runner.simulate_frames(2)
	var out: Array = ["<no dialog>"]
	for c in main.get_children():
		if c is CanvasLayer and c.name == "AiOpponentLayer" and not c.is_queued_for_deletion():
			var fac := c.find_children("*", "OptionButton", true, false)[0] as OptionButton
			out = []
			for i in fac.item_count:
				out.append(fac.get_item_text(i))
	return out


func test_a_gf_army_is_offered_only_the_gf_lists() -> void:
	assert_array(await _offered(MIXED, "gf")).is_equal(["Old Guard", "Orc Tribes"])


func test_an_aof_army_is_offered_only_the_aof_lists() -> void:
	assert_array(await _offered(MIXED, "aof")).is_equal(["Orc Tribes"])


func test_without_a_human_army_every_list_is_offered_with_its_system() -> void:
	assert_array(await _offered(MIXED, "")).is_equal(["Orc Tribes (AoF)", "Old Guard (GF)", "Orc Tribes (GF)"])


func test_an_army_without_lists_of_its_system_gets_no_dialog() -> void:
	var gf_only := {"old_guard": MIXED["old_guard"]}
	assert_array(await _offered(gf_only, "aof")).is_equal(["<no dialog>"])
