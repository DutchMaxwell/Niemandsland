extends GdUnitTestSuite
## Decorative leaf reach must stay outside units, hazards, walls and the board edge.

const Jungle = preload("res://scripts/visual/reference_jungle.gd")


func test_full_leaf_footprint_respects_rule_object_clearings() -> void:
	var jungle: Node3D = auto_free(Jungle.new())
	jungle._board_size = Vector2(1.8,1.2)
	jungle._exclusions.append(Vector3(0,0,0.024))
	jungle._blockers.append(Vector3(0.3,0,0.035))
	jungle._walls = [[Vector2(-0.5,-0.3),Vector2(-0.5,0.3)]]
	assert_bool(jungle.clear_footprint(Vector2(0.038,0),0.016)).is_false()
	assert_bool(jungle.clear_footprint(Vector2(0.349,0),0.016)).is_false()
	assert_bool(jungle.clear_footprint(Vector2(-0.48,0),0.016)).is_false()
	assert_bool(jungle.clear_footprint(Vector2(0.88,0),0.016)).is_false()
	assert_bool(jungle.clear_footprint(Vector2(0.09,0.10),0.016)).is_true()
	# A tiny fragment fits a clearing which a full fern must avoid.
	assert_bool(jungle.clear_footprint(Vector2(0.038,0),0.003)).is_true()


func test_leaf_meshes_fit_the_declared_placement_envelopes() -> void:
	var jungle: Node3D = auto_free(Jungle.new())
	for record: Array in [[jungle._fern_mesh(),0.016],[jungle._broadleaf_mesh(),0.013]]:
		var mesh: ArrayMesh = record[0]
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		assert_int(vertices.size()).is_greater(100)
		for v in vertices:
			assert_float(Vector2(v.x,v.z).length()).is_less_equal(record[1])
			assert_float(v.y).is_greater_equal(-0.0001)
			assert_float(v.y).is_less_equal(0.020)
