extends GdUnitTestSuite
## Tree plan step 13 — the tree search knobs reach the Rust core through the game
## header (`AiActRecorder._header_line`'s `knobs`, read by plain.rs `knobs_of`) ONLY
## when their env var is set: an unset game writes the header it always did and
## the core answers with today's one-ply search.

const _ENV := ["NML_SEARCH_MODE", "NML_TREE_LEAF", "NML_TREE_DICE", "NML_TREE_BUDGET",
	"NML_TREE_SAMPLES", "NML_TREE_BATCH", "NML_TREE_WALL_MS", "NML_POOL_WALL_MS", "NML_TREE_WIDEN"]


func _reset() -> void:
	for k in _ENV:
		OS.set_environment(k, "")
	AiPlanner.tree_knob_stamp = {}
	AiPlanner._tk_env = false


func before_test() -> void:
	_reset()


func after_test() -> void:
	_reset()


func _header_knobs() -> Dictionary:
	return AiActRecorder._header_line({"units": {}}, Callable())["knobs"] as Dictionary


func test_env_unset_stamps_nothing_and_the_header_is_todays() -> void:
	assert_dict(AiPlanner.tree_knobs()).is_empty()
	for key in ["search_mode", "tree_leaf", "tree_dice", "tree_budget", "tree_samples", "tree_batch",
			"tree_wall_ms", "pool_wall_ms", "tree_widen"]:
		assert_bool(_header_knobs().has(key)).is_false()


func test_env_set_stamps_clamped_values_into_the_header() -> void:
	OS.set_environment("NML_SEARCH_MODE", "tree")
	OS.set_environment("NML_TREE_LEAF", "terminal")
	OS.set_environment("NML_TREE_DICE", "dice")   # not a setting: refused, never stamped
	OS.set_environment("NML_TREE_BUDGET", "99999")
	OS.set_environment("NML_TREE_BATCH", "0")
	OS.set_environment("NML_TREE_WALL_MS", "500")
	OS.set_environment("NML_TREE_WIDEN", "0.5")
	var want := {"search_mode": "tree", "tree_leaf": "terminal", "tree_budget": 4096, "tree_batch": 1,
		"tree_wall_ms": 500, "tree_widen": 0.5}
	assert_dict(AiPlanner.tree_knobs()).is_equal(want)
	var knobs := _header_knobs()
	for key in want:
		assert_bool(knobs.has(key)).is_true()
		assert_str(str(knobs.get(key))).is_equal(str(want[key]))
	assert_bool(knobs.has("tree_dice")).is_false()
	assert_bool(knobs.has("top_k")).is_true()   # the stamp is additive, never a replacement
