extends GdUnitTestSuite
## The low ground mist of a boardgen layout (BoardgenMist) and its graphics setting: thicker over the sumps and in wells, none over raised
## tiers, thin planes between ankle and knee height, one draw call, nothing physical, one layout always the same, and the setting adds and
## removes the node (off on Low and Performance and in calm mode). Synthetic 8 x 8 layouts, so the suite stands on its own.

const NX := 8
const NZ := 8


## An 8 x 8 board of open level-0 floor; `sump` cells are Hazard, `tier` cells are level 1.
func _layout(sump: Array, tier: Array = []) -> Dictionary:
	var cells: Array[Dictionary] = []
	for z in NZ:
		for x in NX:
			var c := Vector2i(x, z)
			cells.append({"x": x, "z": z, "level": 1 if tier.has(c) else 0, "lot_kind": "Hazard" if sump.has(c) else "Street", "street": false})
	return {"seed": 5, "nx": NX, "nz": NZ, "cell_in": 3.0, "board_in": [24, 24], "cells": cells, "level_in": [0, 3, 6, 9], "connectors": []}


func _thick(bytes: PackedByteArray, x: int, z: int) -> int:
	return bytes[(z * NX + x) * 2]


func _toxic(bytes: PackedByteArray, x: int, z: int) -> int:
	return bytes[(z * NX + x) * 2 + 1]


func after_test() -> void:
	GraphicsSettings.show_board_mist = true
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.MEDIUM
	GraphicsSettings.calm_mode = false


func test_the_density_is_zero_over_a_tier_thick_over_a_sump_and_thicker_in_a_well() -> void:
	var layout := _layout([Vector2i(1, 1)], [Vector2i(5, 4), Vector2i(5, 5), Vector2i(4, 5), Vector2i(6, 5), Vector2i(5, 6)])
	var d := BoardgenMist.density(layout)
	assert_int(d.size()).is_equal(NX * NZ * 2)
	assert_int(_thick(d, 5, 5)).is_equal(0)   # a raised tier carries no mist
	assert_int(_thick(d, 1, 1)).is_equal(255)
	assert_int(_toxic(d, 1, 1)).is_equal(255)
	assert_int(_toxic(d, 2, 1)).is_equal(128)   # beside a sump: toxic mist, thick
	assert_int(_thick(d, 2, 1)).is_greater_equal(int(0.75 * 255) - 1)
	assert_int(_toxic(d, 7, 0)).is_equal(0)
	assert_int(_thick(d, 4, 4)).is_greater(_thick(d, 7, 0))   # a cell the tiers wall in beats open floor
	assert_int(_thick(d, 7, 0)).is_greater(0)


func test_one_layout_gives_the_same_density_and_a_moved_sump_moves_it() -> void:
	randomize()   # the global generator must not matter
	assert_array(BoardgenMist.density(_layout([Vector2i(2, 2)]))).is_equal(BoardgenMist.density(_layout([Vector2i(2, 2)])))
	assert_bool(BoardgenMist.density(_layout([Vector2i(2, 2)])) == BoardgenMist.density(_layout([Vector2i(5, 5)]))).is_false()


func test_the_mist_is_three_thin_planes_below_the_knee_in_one_multimesh_with_nothing_physical() -> void:
	var mist: BoardgenMist = auto_free(BoardgenMist.new())
	add_child(mist)
	mist.build(_layout([]))
	assert_int(mist.multimesh.instance_count).is_equal(3)
	assert_int(BoardgenMist.LAYER_HEIGHTS_IN.size()).is_equal(3)   # (the instance transforms are not readable back on the headless renderer)
	for y_in in BoardgenMist.LAYER_HEIGHTS_IN:
		assert_float(y_in).is_between(0.05, 0.5)   # ankle to knee of a 28 mm miniature
	assert_int(mist.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_int(mist.find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)
	var mat := mist.material_override as ShaderMaterial
	assert_bool(mat.shader.code.contains("hint_depth_texture")).is_true()   # soft where it meets geometry
	assert_bool(mat.shader.code.contains("ALPHA = clamp(a, 0.0, 0.5);")).is_true()   # never a wall


func _board(layout: Dictionary) -> BoardgenGreybox:
	var node: BoardgenGreybox = auto_free(BoardgenGreybox.new())
	add_child(node)
	node.build(layout)
	return node


func test_the_board_has_a_mist_node_while_the_setting_is_on_and_loses_it_at_once_when_it_goes_off() -> void:
	var node := _board(_layout([Vector2i(2, 2)]))
	assert_object(node.get_node_or_null("Mist")).is_not_null()
	GraphicsSettings.show_board_mist = false   # the setter tells every board
	assert_object(node.get_node_or_null("Mist")).is_null()
	GraphicsSettings.show_board_mist = true
	assert_object(node.get_node_or_null("Mist")).is_not_null()
	assert_int((node.find_child("Colliders", false, false) as StaticBody3D).get_child_count()).is_equal(0)   # the mist never blocks standing room


func test_a_board_built_while_the_setting_is_off_has_no_mist_and_the_low_presets_and_calm_mode_turn_it_off() -> void:
	GraphicsSettings.show_board_mist = false
	assert_object(_board(_layout([])).get_node_or_null("Mist")).is_null()
	GraphicsSettings.show_board_mist = true
	assert_bool(GraphicsSettings.board_mist_enabled()).is_true()
	for preset in [GraphicsSettings.QualityPreset.PERFORMANCE, GraphicsSettings.QualityPreset.LOW]:
		GraphicsSettings.current_preset = preset
		assert_bool(GraphicsSettings.board_mist_enabled()).override_failure_message("mist on at preset %d" % preset).is_false()
	for preset in [GraphicsSettings.QualityPreset.MEDIUM, GraphicsSettings.QualityPreset.HIGH, GraphicsSettings.QualityPreset.ULTRA]:
		GraphicsSettings.current_preset = preset
		assert_bool(GraphicsSettings.board_mist_enabled()).is_true()
	GraphicsSettings.calm_mode = true
	assert_bool(GraphicsSettings.board_mist_enabled()).is_false()
