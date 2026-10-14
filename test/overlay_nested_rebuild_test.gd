extends GdUnitTestSuite
## update_placed_objects() requests the tree panels from inside its own object loop. When panels/models are
## already cached, TreesLibrary's awaits complete without suspending, so _fetch_tree_panels() re-enters
## update_placed_objects() synchronously. The nested call builds every object; the OUTER call then built them
## again without clearing -> every tree twice, both live (CI shard 5 on #1788: "6 oaks for 9 table trees").

const OverlayScript := preload("res://scripts/terrain_overlay.gd")
const IN2M := 0.0254


## A tree library whose awaits finish at once and whose "ready" checks are still false, so the overlay asks
## for the panels (the request path) and the request returns synchronously (the cached-on-disk case).
class SyncTrees extends TreesLibrary:
	func all_panels_cached(_theme_prefix: String = "") -> bool:
		return false

	func all_models_cached(_theme_prefix: String = "") -> bool:
		return false

	func ensure_all_panels(_theme_prefix: String = "") -> bool:
		return true

	func ensure_all_models(_theme_prefix: String = "") -> bool:
		return true


func _trees() -> Array:
	var objects: Array = []
	for x in range(18, 21):
		objects.append({"object_type": "tree", "cell": Vector2i(x, 17), "offset": Vector2(0.5, 0.5)})
	return objects


func test_a_synchronous_panel_request_does_not_build_every_tree_twice() -> void:
	var overlay: Node3D = auto_free(OverlayScript.new())
	add_child(overlay)
	overlay._trees_library.queue_free()
	overlay._trees_library = SyncTrees.new()
	overlay.add_child(overlay._trees_library)
	overlay.update_placed_objects(_trees(), Vector2(6, 4), 0.0)
	assert_int(overlay._object_instances.size()).override_failure_message(
		"%d tree instances for 3 trees (a nested rebuild was built over again)" % overlay._object_instances.size()).is_equal(3)
	var live := 0
	for child in overlay.get_children():
		if child.has_method("get_child_count") and child in overlay._object_instances:
			live += 1
	assert_int(live).is_equal(3)


func test_a_plain_rebuild_still_builds_each_object_once() -> void:
	var overlay: Node3D = auto_free(OverlayScript.new())
	add_child(overlay)
	overlay._tree_fetch_started = true   # no request at all: the ordinary path
	overlay.update_placed_objects(_trees(), Vector2(6, 4), 0.0)
	assert_int(overlay._object_instances.size()).is_equal(3)
