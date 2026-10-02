extends GdUnitTestSuite
## R12 (Map editor plan): terrain shelf click-to-place. Picking a piece arms a ghost that follows the
## cursor on the table; a click drops the piece at that table point, Esc cancels, Place stays as the fallback.


class StubObjectManager extends Node3D:
	var cursor := Vector3.ZERO
	var spawned: Array = []
	const SANDBOX_DEFAULT_FOOTPRINT_INCHES := 6.0

	func get_cursor_table_position() -> Vector3:
		return cursor

	func sandbox_catalog(_prefix: String) -> Array:
		return [{"prop_id": "stub_ruin", "label": "Stub ruin", "kind": 0}]

	func spawn_sandbox_terrain(prop_id: String, kind: int, pos: Vector3) -> void:
		spawned.append({"prop_id": prop_id, "kind": kind, "pos": pos})


var _om: StubObjectManager


func before_test() -> void:
	_om = auto_free(StubObjectManager.new())
	add_child(_om)


func _ghost() -> Node3D:
	var g := SandboxPlacementGhost.new()
	_om.add_child(g)
	g.setup(_om)
	return g


func test_r12_armed_ghost_follows_the_cursor_and_a_click_drops_the_piece_there() -> void:
	var g := _ghost()
	assert_bool(g.is_armed()).is_false()
	g.arm({"prop_id": "stub_ruin", "kind": 0})
	assert_bool(g.is_armed()).is_true()
	assert_bool(g.visible).is_true()
	_om.cursor = Vector3(0.2, 0, -0.1)
	g._follow_cursor()
	assert_vector(g.global_position).is_equal(Vector3(0.2, 0, -0.1))
	assert_bool(g.commit()).is_true()
	assert_int(_om.spawned.size()).override_failure_message("R12 — the click did not spawn the piece").is_equal(1)
	assert_vector(_om.spawned[0]["pos"]).is_equal(Vector3(0.2, 0, -0.1))
	assert_bool(g.is_armed()).override_failure_message("R12 — the ghost should stay armed for the next piece").is_true()


func test_r12_cancel_disarms_and_a_click_then_does_nothing() -> void:
	var g := _ghost()
	g.arm({"prop_id": "stub_ruin", "kind": 0})
	g.cancel()
	assert_bool(g.is_armed()).is_false()
	assert_bool(g.visible).is_false()
	assert_bool(g.commit()).is_false()
	assert_int(_om.spawned.size()).is_equal(0)


func test_r12_picking_a_shelf_entry_arms_the_ghost_and_closing_disarms_it() -> void:
	var shelf := SandboxTerrainShelf.new()
	add_child(shelf)
	auto_free(shelf)
	shelf.setup(_om)
	await get_tree().process_frame
	shelf._list.item_selected.emit(0)
	assert_bool(shelf.placement_ghost() != null and shelf.placement_ghost().is_armed()) \
		.override_failure_message("R12 — selecting a piece did not arm the ghost").is_true()
	var placed: Array = []
	shelf.piece_placed.connect(func(id): placed.append(id))
	_om.cursor = Vector3(1, 0, 1)
	shelf.placement_ghost().commit()
	assert_array(placed).contains_exactly(["stub_ruin"])
	shelf._emit_closed()
	assert_bool(shelf.placement_ghost().is_armed()).is_false()
