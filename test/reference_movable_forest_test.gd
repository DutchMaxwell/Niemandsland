extends GdUnitTestSuite
## R5: grassland_reference._dress_movable_forests read `group.kind`, a field TerrainGroupBase does not have
## (it is `prop_kind`), so a grassland table with any movable forest group stopped the dressing with a script
## error. The menu diorama never had such a group; a player's table does.

const Reference := preload("res://scripts/visual/grassland_reference.gd")


func _group(kind: int, key: String) -> TerrainGroupBase:
	var group: TerrainGroupBase = auto_free(TerrainGroupBase.new())
	group.configure(key, kind, Vector2(12, 10))
	add_child(group)
	group.build(12345, null)
	group.position = Vector3(0.4, 0.0, -0.3)
	return group


func _presentation() -> Node3D:
	var presentation: Node3D = auto_free(Reference.new())
	add_child(presentation)
	presentation._ground = ShaderMaterial.new()
	return presentation


func test_movable_forest_group_becomes_a_forest_region() -> void:
	var group := _group(TerrainGroupBase.KIND_FOREST, "forest_large")
	var presentation := _presentation()
	presentation._dress_movable_forests()
	var regions: PackedVector4Array = presentation._regions
	assert_int(regions.size()).is_equal(1)
	if regions.size() != 1:
		return
	assert_float(regions[0].x).is_equal_approx(0.4, 0.001)
	assert_float(regions[0].y).is_equal_approx(-0.3, 0.001)
	assert_float(regions[0].z).is_equal_approx(12.0 * 0.0254 * 0.5, 0.0001)
	if is_instance_valid(group._floor_mesh):
		assert_object(group._floor_mesh.material_override).is_same(presentation._ground)


func test_hazard_cluster_is_not_a_forest_region() -> void:
	_group(TerrainGroupBase.KIND_HAZARD_CLUSTER, "hazard_cluster")
	var presentation := _presentation()
	presentation._dress_movable_forests()
	assert_int(presentation._regions.size()).is_equal(0)
