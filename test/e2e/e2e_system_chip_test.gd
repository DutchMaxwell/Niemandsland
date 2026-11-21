extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 21 over the real scenes/main.tscn: a read-only "SYSTEM: ..." chip sits beside the rules chip and
## follows the table's game system; the map editor carries the change control (free while no list is on the table, locked with
## the reason afterwards; a refused change puts the row back on the real system). Glyphs: plain ASCII, nothing outside Inter.

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


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


func _option() -> OptionButton:
	return _main.map_layout_editor.find_child("SystemOption", true, false) as OptionButton


func _open_editor() -> void:
	_main._on_map_layout_pressed()
	await _runner.simulate_frames(2)


func test_the_chip_follows_the_table_system() -> void:
	_main._update_rules_chip()
	assert_str(_main._system_chip.text).is_equal("SYSTEM: GF")
	assert_bool(_main.set_table_system("aofs", "P1")).is_true()
	assert_str(_main._system_chip.text).is_equal("SYSTEM: AoFS")
	assert_str(_main._system_chip.tooltip_text).contains("Age of Fantasy: Skirmish")
	for c in _main._system_chip.text:
		assert_bool(c.unicode_at(0) < 128).override_failure_message("a glyph outside ASCII in the chip: %s" % c).is_true()


func test_the_editor_row_changes_the_system_while_the_table_is_empty_and_locks_after_a_list() -> void:
	await _open_editor()
	var option := _option()
	assert_object(option).is_not_null()
	assert_int(option.item_count).is_equal(5)
	assert_bool(option.disabled).is_false()
	option.select(1)
	option.item_selected.emit(1)   # Grimdark Future: Firefight
	assert_str(_main.opr_army_manager.table_system).is_equal("gff")
	assert_str(_main._system_chip.text).is_equal("SYSTEM: GFF")
	# a list arrives: the row locks, with the reason
	var army := OPRApiClient.OPRArmy.new()
	army.name = "Firefight List"
	army.game_system_abbrev = "gff"
	await _main._on_opr_army_imported(army, 1, false)
	await _runner.simulate_frames(2)
	await _open_editor()
	assert_bool(_option().disabled).is_true()
	assert_str(_option().tooltip_text).is_equal("Locked while a list is on the table")
	# even a forced change is refused and the row goes back on the real system
	_option().select(2)
	_option().item_selected.emit(2)
	assert_str(_main.opr_army_manager.table_system).is_equal("gff")
	assert_int(_option().selected).is_equal(1)


func test_the_system_row_heads_the_terrain_tab_and_the_type_box_holds_only_type_buttons() -> void:
	var editor: Node = _main.map_layout_editor
	for child in editor.terrain_buttons.get_children():
		assert_bool(child is Button).override_failure_message("a non-button in the type box: %s" % child.name).is_true()
	var tab: Node = editor.find_child("TabTerrain", true, false)
	assert_object(tab).is_not_null()
	assert_object(tab.find_child("SystemOption", true, false)).override_failure_message("the row is not in the terrain tab").is_not_null()
	assert_str(str(tab.get_child(0).name)).is_equal("SystemRow")
