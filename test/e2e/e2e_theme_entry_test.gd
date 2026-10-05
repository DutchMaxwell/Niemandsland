extends GdUnitTestSuite
## The map editor's "Ruined Borderland" entry (5.2b-2, maintainer d7b: right under "Auto-Generate Layout"): one click
## lays the theme out through main.apply_table_theme and closes the editor so the table shows; greyed out on a table
## of another size (lead D11). No model downloads in the test (empty model manifest).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.object_manager.solid_models_library().apply_manifest_text("{}")
	_main.table.setup_table(Vector2(6, 4))
	_main.terrain_overlay.grid_cells.clear()


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _entry() -> Button:
	return _main.map_layout_editor.find_child("ThemeBorderlandBtn", true, false) as Button


func test_the_entry_sits_under_auto_generate_and_lays_the_table_out() -> void:
	var editor: Control = _main.map_layout_editor
	editor.set_table_size(Vector2(6, 4))
	editor.show()
	var entry := _entry()
	assert_object(entry).is_not_null()
	if entry == null:
		return
	var autogen: Button = editor.autogen_button
	assert_object(entry.get_parent()).is_same(autogen.get_parent())
	assert_int(entry.get_index()).is_equal(autogen.get_index() + 1)
	assert_str(entry.text).is_equal("Ruined Borderland")
	assert_bool(entry.disabled).is_false()
	entry.pressed.emit()
	await _runner.simulate_frames(2)
	var live := ObjectManager.sandbox_pieces(_main.get_tree()).filter(func(n: Node) -> bool:
		return not bool(n.get_meta("deleted", false)))
	assert_int(live.size()).is_equal(14)
	assert_bool(editor.visible).is_false()   # closed, so the laid-out table shows


func test_the_entry_is_greyed_out_on_another_table_size() -> void:
	var editor: Control = _main.map_layout_editor
	editor.set_table_size(Vector2(4, 4))
	editor.show()
	var entry := _entry()
	assert_object(entry).is_not_null()
	if entry != null:
		assert_bool(entry.disabled).is_true()
