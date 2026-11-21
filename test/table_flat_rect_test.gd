extends GdUnitTestSuite
## Table.set_flat_rect / sync_flat_rect: the rect a footprint owner (a generated board) keeps flat reaches the `flat_rect` uniform of the table mesh's ground and of the shared
## base top, empty clears it, and a ground material built later is told again (the biome presenter replaces the material on every rebuild).

const TableScript := preload("res://scripts/table.gd")
const GROUND := preload("res://shaders/visual/reference_ground_table.gdshader")
const Menu := preload("res://scripts/menu_battlefield.gd")
const Reference := preload("res://scripts/visual/grassland_reference.gd")


func _table() -> TableScript:
	var table: TableScript = auto_free(TableScript.new())
	table.mesh_instance = auto_free(MeshInstance3D.new())
	table.mesh_instance.material_override = _ground()
	table.get_base_top_material().shader = GROUND   # (the presenter gives the base the reference ground's shader)
	return table


func _ground() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND
	return mat


func _flat(mat: Material) -> Vector4:
	var v: Variant = (mat as ShaderMaterial).get_shader_parameter("flat_rect")   # null until something sets it
	return v if v is Vector4 else Vector4.ZERO


func test_the_rect_reaches_both_ground_materials_and_an_empty_rect_clears_it() -> void:
	var table := _table()
	table.set_flat_rect(Rect2(-0.5, -0.4, 1.0, 0.8))
	for mat: Material in [table.mesh_instance.material_override, table.get_base_top_material()]:
		assert_object(_flat(mat)).is_equal(Vector4(-0.5, -0.4, 0.5, 0.4))
	table.set_flat_rect(Rect2())
	for mat: Material in [table.mesh_instance.material_override, table.get_base_top_material()]:
		assert_object(_flat(mat)).is_equal(Vector4.ZERO)


func test_a_ground_material_built_later_is_told_the_rect_when_the_table_syncs() -> void:
	var table := _table()
	table.set_flat_rect(Rect2(-0.5, -0.5, 1.0, 1.0))
	var fresh := _ground()
	table.mesh_instance.material_override = fresh
	assert_object(_flat(fresh)).is_equal(Vector4.ZERO)
	table.sync_flat_rect()
	assert_object(_flat(fresh)).is_equal(Vector4(-0.5, -0.5, 0.5, 0.5))


func test_the_presenter_syncs_the_rect_on_the_game_table_and_leaves_the_main_menus_surface_alone() -> void:
	var table := _table()
	table.set_flat_rect(Rect2(-0.5, -0.5, 1.0, 1.0))
	var fresh := _ground()
	table.mesh_instance.material_override = fresh
	Reference.sync_flat(table)   # the game's Table: the new ground is told
	assert_object(_flat(fresh)).is_equal(Vector4(-0.5, -0.5, 0.5, 0.5))
	var menu: Node3D = auto_free(Menu.MenuSurface.new())   # the menu's stand-in sits in the same slot and has no hook: an unguarded call is a SCRIPT ERROR
	Reference.sync_flat(menu)
	assert_bool(menu.has_method("sync_flat_rect")).is_false()
