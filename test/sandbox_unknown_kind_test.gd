extends GdUnitTestSuite
## A free-terrain record of a kind this build does not know (a newer save or peer, a corrupt file) is
## skipped with a log line by ObjectManager.spawn_sandbox_terrain, the one choke point the shelf, the
## save loader and the MP spawn RPC share. Before, every unknown kind was built as a ruin and silently
## got a ruin's cover and area sight.


func _pieces() -> int:
	return ObjectManager.sandbox_pieces(get_tree()).size()


func test_unknown_sandbox_kind_is_skipped_not_built_as_a_ruin() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	var before := _pieces()
	var spawned := om.spawn_sandbox_terrain("future_piece_9x9", 99, Vector3.ZERO, false, 7001)
	assert_object(spawned).is_null()
	assert_int(_pieces()).is_equal(before)


func test_a_known_ruin_kind_still_spawns() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	var spawned := om.spawn_sandbox_terrain("ruin_small_1f", ObjectManager.SandboxPropKind.RUIN, Vector3.ZERO, false, 7002)
	assert_object(spawned).is_not_null()
	assert_int(int(spawned.get("prop_kind"))).is_equal(ObjectManager.SandboxPropKind.RUIN)
