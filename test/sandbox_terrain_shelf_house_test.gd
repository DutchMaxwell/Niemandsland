extends GdUnitTestSuite
## A12 (Map editor plan): the Terrain Shelf is an in-viewport house panel docked at the left, not an OS-style
## Window. The public seam stays: setup(object_manager), open(), closed, piece_placed(prop_id), visible.


class StubObjectManager extends Node:
	var spawned: Array = []

	func get_cursor_table_position() -> Vector3:
		return Vector3(1, 0, 2)

	func sandbox_catalog(_prefix: String) -> Array:
		return [{"prop_id": "stub_ruin", "label": "Stub ruin", "kind": 0}]

	func spawn_sandbox_terrain(prop_id: String, kind: int, pos: Vector3) -> void:
		spawned.append([prop_id, kind, pos])


var _shelf: Node
var _om: StubObjectManager


func before_test() -> void:
	_om = auto_free(StubObjectManager.new())
	_shelf = auto_free(SandboxTerrainShelf.new())
	add_child(_shelf)
	_shelf.setup(_om)
	await get_tree().process_frame


func _btn(text: String) -> Button:
	for b: Node in _shelf.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b as Button
	return null


func test_a12_shelf_is_a_docked_house_panel_not_a_window() -> void:
	assert_bool(_shelf is Window).override_failure_message("A12 — the shelf is still an OS-style Window").is_false()
	assert_bool(_shelf is PanelContainer).is_true()
	if not (_shelf is PanelContainer):
		return
	assert_str(String((_shelf as PanelContainer).theme_type_variation)).is_equal(String(HouseStyle.PANEL_VARIANT))
	assert_bool((_shelf as Control).theme == HouseStyle.theme()).is_true()
	assert_float((_shelf as Control).position.x).is_less(200.0)   # left side, right of the rail


func test_a12_controls_use_house_rows_and_variants() -> void:
	var biome: OptionButton = _shelf._biome_option
	var row := biome.get_parent()
	assert_bool(row is HBoxContainer and row.get_child(0) is Label and row.get_child(1) == biome).is_true()
	assert_str(String(_btn("Place").theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
	assert_str(String(_btn("Close").theme_type_variation)).is_equal(String(HouseStyle.BUTTON))


func test_a12_public_seam_survives() -> void:
	assert_bool(_shelf.has_signal("closed") and _shelf.has_signal("piece_placed")).is_true()
	assert_bool(_shelf.visible).is_false()
	_shelf.open()
	assert_bool(_shelf.visible).is_true()
	assert_int(_shelf._list.item_count).is_greater(0)
	var placed: Array = []
	_shelf.piece_placed.connect(func(id): placed.append(id))
	_shelf._list.select(0)
	_btn("Place").pressed.emit()
	assert_array(placed).contains_exactly(["stub_ruin"])
	assert_int(_om.spawned.size()).is_equal(1)
	var closed := [false]
	_shelf.closed.connect(func(): closed[0] = true)
	_btn("Close").pressed.emit()
	assert_bool(closed[0]).is_true()
	assert_bool(_shelf.visible).is_false()
