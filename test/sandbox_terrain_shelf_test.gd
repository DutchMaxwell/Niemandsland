extends GdUnitTestSuite
## Terrain shelf Place behaviour (F3 of the Map editor plan): a piece must land where the player
## was last aiming on the table, never at the table point BEHIND the shelf window (the cursor sits
## on the Place button when it is pressed).


class StubObjectManager extends Node:
	var cursor := Vector3.ZERO
	var spawned: Array = []

	func get_cursor_table_position() -> Vector3:
		return cursor

	func sandbox_catalog(_prefix: String) -> Array:
		return [{"prop_id": "stub_ruin", "label": "Stub ruin", "kind": 0}]

	func spawn_sandbox_terrain(prop_id: String, kind: int, pos: Vector3) -> void:
		spawned.append({"prop_id": prop_id, "kind": kind, "pos": pos})


func _shelf(om: Node) -> Control:
	var shelf := SandboxTerrainShelf.new()
	add_child(shelf)
	auto_free(shelf)
	shelf.setup(om)
	shelf._list.select(0)
	return shelf


func test_place_uses_last_table_point_not_the_point_behind_the_window() -> void:
	var om := StubObjectManager.new()
	auto_free(om)
	var shelf := _shelf(om)
	om.cursor = Vector3(1, 0, 2)
	if shelf.has_method("_track_cursor"):
		shelf.call("_track_cursor")
	shelf.mouse_entered.emit()
	om.cursor = Vector3(9, 0, 9)
	shelf._on_place_pressed()
	assert_int(om.spawned.size()).is_equal(1)
	assert_vector(om.spawned[0]["pos"]) \
		.override_failure_message("F3 — piece spawned at the table point behind the shelf window") \
		.is_equal(Vector3(1, 0, 2))


func test_place_without_any_aim_falls_back_to_table_centre() -> void:
	var om := StubObjectManager.new()
	auto_free(om)
	var shelf := _shelf(om)
	shelf.mouse_entered.emit()
	om.cursor = Vector3(9, 0, 9)
	shelf._on_place_pressed()
	assert_vector(om.spawned[0]["pos"]).is_equal(Vector3.ZERO)


func test_shelf_hint_tells_the_truth() -> void:
	var om := StubObjectManager.new()
	auto_free(om)
	var shelf := _shelf(om)
	var texts: Array = []
	for l in shelf.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	assert_str(" ".join(texts)).contains("Esc cancels")  # R12: click-to-place is real now
