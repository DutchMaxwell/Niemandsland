extends GdUnitTestSuite
## Stones and grass at the foot of free ruins and solids (S6-2, maintainer 05.10.: the ruins must belong to the
## picture): one FootScatter child with a stone and a grass MultiMesh, every instance in a ring up to 2.5" outside the
## footprint (grass reaching a little under the walls), more on ruins than on solids; grassland only and following
## biome changes (lead D12); decoration only, no collision.


class StubTable extends Node3D:
	signal biome_changed(biome_name: String)
	var biome := "temperate_grassland"


var _table: StubTable


func before_test() -> void:
	_table = auto_free(StubTable.new())
	_table.add_to_group("table")
	add_child(_table)


func _scatter(n: Node) -> Node3D:
	var found := n.find_children("FootScatter", "Node3D", false, false)
	return found[0] as Node3D if found.size() == 1 else null


func test_ruins_and_solids_carry_stones_and_grass_at_their_foot() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	om.solid_models_library().apply_manifest_text("{}")   # no model downloads in tests
	var counts := []
	for spec: Array in [["blocker_6x3", ObjectManager.SandboxPropKind.BLOCKER, Vector2(6, 3)],
			["ruin_large_2f", ObjectManager.SandboxPropKind.RUIN, Vector2(9, 6)]]:
		var s := _scatter(om.spawn_sandbox_terrain(spec[0], spec[1], Vector3.ZERO, false))
		assert_object(s).override_failure_message("%s has no foot scatter" % spec[0]).is_not_null()
		if s == null:
			continue
		var layers := s.find_children("*", "MultiMeshInstance3D", false, false)
		assert_int(layers.size()).is_equal(2)   # stones + grass
		assert_int(s.find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)
		var fp: Vector2 = spec[2]
		var total := 0
		for mmi: MultiMeshInstance3D in layers:
			total += mmi.multimesh.instance_count
			for i in mmi.multimesh.instance_count:
				var o := mmi.multimesh.get_instance_transform(i).origin / 0.0254
				var out := Vector2(maxf(absf(o.x) - fp.x * 0.5, 0.0), maxf(absf(o.z) - fp.y * 0.5, 0.0)).length()
				assert_float(out).is_less_equal(2.5 + 0.01)
		counts.append(total)
	if counts.size() == 2:
		assert_int(counts[1]).is_greater(counts[0])   # a ruin gets more than a solid


func test_the_scatter_shows_on_grassland_only() -> void:
	var solid: SandboxSolidProp = auto_free(SandboxSolidProp.new())
	solid.configure("blocker_6x3", 3, Vector2(6, 3))
	add_child(solid)
	var s := _scatter(solid)
	assert_object(s).is_not_null()
	if s == null:
		return
	_table.biome_changed.emit("frozen_tundra")
	assert_bool(s.visible).is_false()
	_table.biome_changed.emit("temperate_grassland")
	assert_bool(s.visible).is_true()
