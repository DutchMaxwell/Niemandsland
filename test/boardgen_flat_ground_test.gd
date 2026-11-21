extends GdUnitTestSuite
## A generated board owns its footprint: the game table's ground has mounds under trees and 7 mm ridges along its terrain walls (vertex relief in
## reference_ground_body.gdshaderinc), the board's skin is 1 mm thick, so every ridge poked through the garden plots of the ruin town as lime slabs (21.11.).
## A board tells both ground materials of the table (the mesh and the shared base top) to keep its rect flat, and clears that when it leaves.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"
const GROUND := preload("res://shaders/visual/reference_ground_table.gdshader")
const BODY := "res://shaders/visual/reference_ground_body.gdshaderinc"


class StubTable extends Node3D:   # what the board needs of table.gd: a TableMesh with a ground material and the shared base-top material
	var base := ShaderMaterial.new()

	func get_base_top_material() -> ShaderMaterial:
		return base


func _table() -> StubTable:
	var table := StubTable.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "TableMesh"
	mesh.material_override = _ground()
	table.add_child(mesh)
	table.base.shader = GROUND
	add_child(auto_free(table))
	return table


func _ground() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND
	return mat


func _flat(mat: Material) -> Vector4:
	var v: Variant = (mat as ShaderMaterial).get_shader_parameter("flat_rect")   # null until something sets it
	return v if v is Vector4 else Vector4.ZERO


func test_a_board_keeps_the_ground_flat_under_it_on_both_ground_materials_and_gives_the_relief_back_when_it_leaves() -> void:
	var table := _table()
	var layout: Dictionary = str_to_var(FileAccess.get_file_as_string(FIXTURE))
	var board := BoardgenGreybox.attach(table, layout)
	var half := 8.0 * float(layout["cell_in"]) * BoardgenGreybox.INCHES_TO_METERS + BoardgenGreybox.RELIEF_MARGIN_M   # 16 cells off the centre
	for mat: Material in [table.get_node("TableMesh").material_override, table.base]:
		var flat := _flat(mat)
		assert_float(flat.x).is_equal_approx(-half, 0.0005)
		assert_float(flat.y).is_equal_approx(-half, 0.0005)
		assert_float(flat.z).is_equal_approx(half, 0.0005)
		assert_float(flat.w).is_equal_approx(half, 0.0005)
	table.remove_child(board)
	board.free()
	for mat: Material in [table.get_node("TableMesh").material_override, table.base]:
		assert_object(_flat(mat)).is_equal(Vector4.ZERO)


func test_a_ground_material_built_after_the_board_is_told_the_rect_again() -> void:
	var table := _table()
	var layout: Dictionary = str_to_var(FileAccess.get_file_as_string(FIXTURE))
	var board := BoardgenGreybox.attach(table, layout)
	var fresh := _ground()   # the biome presenter builds a new ground material on every rebuild
	table.get_node("TableMesh").material_override = fresh
	assert_object(_flat(fresh)).is_equal(Vector4.ZERO)
	BoardgenGreybox.flatten_relief(table)
	assert_float(_flat(fresh).z).is_greater(0.6)
	table.remove_child(board)
	board.free()


func test_the_ground_shader_returns_no_relief_inside_the_flat_rect_and_the_presenter_asks_for_it() -> void:
	var body := FileAccess.get_file_as_string(BODY)
	assert_str(body).contains("uniform vec4 flat_rect")
	var start := body.find("float full_relief")
	var relief := body.substr(start, body.find("varying vec2 ground_xz") - start)
	assert_str(relief).contains("flat_rect.xy")   # the guard sits INSIDE full_relief, before its sum
	assert_str(relief).contains("return 0.0;")
	assert_str(FileAccess.get_file_as_string("res://scripts/visual/grassland_reference.gd")).contains("BoardgenGreybox.flatten_relief(table)")
