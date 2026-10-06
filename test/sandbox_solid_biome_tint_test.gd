extends GdUnitTestSuite
## S8.2 (maintainer 06.10.: the terrain should match the biome): a shelf solid takes the table's biome. Its stone parts
## and an uploaded model are tinted (desert: warm sandstone), the green foot parts take the biome's ground colour
## (desert: sand); grassland keeps today's look, and a biome change follows. The rule box never changes.

const DESERT_TINT := Color(1.0, 0.86, 0.66)
const DESERT_GROUND := Color(0.55, 0.45, 0.30)


class StubTable extends Node3D:
	signal biome_changed(biome_name: String)
	var biome := "arid_desert"


var _table: StubTable


func before_test() -> void:
	_table = auto_free(StubTable.new())
	_table.add_to_group("table")
	add_child(_table)


func _colours(solid: Node3D) -> Array:
	var out := []
	for child in solid.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			out.append((child.mesh.material as StandardMaterial3D).albedo_color)
	return out


func _has(colours: Array, c: Color) -> bool:
	return colours.any(func(x: Color) -> bool: return x.is_equal_approx(c))


func test_a_solid_on_a_desert_table_turns_sandstone_and_follows_a_biome_change() -> void:
	var solid: SandboxSolidProp = auto_free(SandboxSolidProp.new())
	solid.configure("longhouse_6x3", 3, Vector2(6, 3), "house_b")
	add_child(solid)
	var box: Vector3 = (solid.get_child(0) as CollisionShape3D).shape.size
	var model := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var white := StandardMaterial3D.new()
	mi.mesh.surface_set_material(0, white)
	model.add_child(mi)
	solid.use_model(model)
	var ashlar: Color = SandboxSolidProp.COLOURS["ashlar"]
	assert_bool(_has(_colours(solid), ashlar * DESERT_TINT)).override_failure_message("stone not sandstone: %s" % [
		_colours(solid)]).is_true()
	assert_bool(_has(_colours(solid), DESERT_GROUND)).override_failure_message("no sand at the foot").is_true()
	assert_object(mi.get_active_material(0)).is_not_null()
	assert_bool((mi.get_active_material(0) as StandardMaterial3D).albedo_color.is_equal_approx(DESERT_TINT)) \
		.override_failure_message("the model is not tinted").is_true()
	_table.biome_changed.emit("temperate_grassland")
	assert_bool(_has(_colours(solid), ashlar)).override_failure_message("grassland look not back").is_true()
	assert_bool((mi.get_active_material(0) as StandardMaterial3D).albedo_color.is_equal_approx(Color.WHITE)).is_true()
	assert_vector((solid.get_child(0) as CollisionShape3D).shape.size).is_equal(box)   # the rule box never changes
