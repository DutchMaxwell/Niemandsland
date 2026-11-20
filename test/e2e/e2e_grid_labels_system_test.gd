extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 12: the CONTAINER terrain type reads "Container" on a grimdark table and "Blocker" on a
## fantasy one - label only: same type, same button name, same rules text. Real scenes/main.tscn, the real map editor.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const MapLayoutScript := preload("res://scripts/map_layout.gd")

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


func _container_button() -> Button:
	return _main.map_layout_editor.find_child("TerrainContainerButton", true, false) as Button


func _open_editor() -> void:
	_main.map_layout_editor.visible = false
	_main.map_layout_editor.visible = true


func test_the_label_follows_the_table_system_and_nothing_else_changes() -> void:
	var button := _container_button()
	assert_object(button).override_failure_message("the type button must keep its name").is_not_null()
	assert_str(button.text).is_equal("Container")
	var tooltip := button.tooltip_text
	for system in ["aof", "aofs", "aofr"]:
		_main.opr_army_manager.table_system = system
		_open_editor()
		assert_str(_container_button().text).override_failure_message("%s: %s" % [system, _container_button().text]).is_equal("Blocker")
		assert_str(_container_button().tooltip_text).is_equal(tooltip)
	for system in ["gf", "gff"]:
		_main.opr_army_manager.table_system = system
		_open_editor()
		assert_str(_container_button().text).is_equal("Container")
	# the other types never change
	assert_str(_main.map_layout_editor.find_child("TerrainRuinsButton", true, false).text).is_equal("Ruins")


func test_terrain_label_is_a_label_of_the_same_type() -> void:
	var container: int = MapLayoutScript.TerrainType.CONTAINER
	assert_str(MapLayoutScript.terrain_label(container, "gf")).is_equal("Container")
	assert_str(MapLayoutScript.terrain_label(container, "")).is_equal("Container")
	assert_str(MapLayoutScript.terrain_label(container, "aofs")).is_equal("Blocker")
	for type in [MapLayoutScript.TerrainType.RUINS, MapLayoutScript.TerrainType.FOREST, MapLayoutScript.TerrainType.DANGEROUS]:
		assert_str(MapLayoutScript.terrain_label(type, "aof")).is_equal(MapLayoutScript.TERRAIN_NAMES[type])
