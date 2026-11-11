extends GdUnitTestSuite
## Bundled army lists ship no store links and no product picture paths: the game never reads them.

const DIRS := ["res://assets/arena_lists", "res://assets/tutorial"]


func _json_files() -> Array:
	var out: Array = []
	for d in DIRS:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".json"):
				out.append(d + "/" + f)
	return out


func test_the_scan_sees_the_bundled_lists() -> void:
	# The check must be able to fail: it has to find files at all.
	assert_int(_json_files().size()).is_greater(2)


func test_no_bundled_list_carries_a_store_link() -> void:
	var hits: Array = []
	for p in _json_files():
		var text := FileAccess.get_file_as_string(p)
		if text.contains("storeLinks") or text.contains("myminifactory") or text.contains("mageUrl"):
			hits.append(p)
	assert_array(hits).override_failure_message("store links or picture paths in bundled lists: %s" % str(hits)).is_empty()
