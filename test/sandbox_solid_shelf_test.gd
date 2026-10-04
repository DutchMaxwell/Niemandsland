extends GdUnitTestSuite
## The terrain shelf offers the free solid once in every biome, with its confirmed label. Placing it goes through
## ObjectManager.spawn_sandbox_terrain (test/sandbox_solid_spawn_test.gd).

const SOLID_ID := "blocker_6x3"


func test_shelf_lists_the_solid_once_in_every_biome() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	for prefix in ObjectManager.SANDBOX_BIOME_PREFIXES:
		var hits := om.sandbox_catalog(prefix).filter(func(e: Dictionary) -> bool: return e["prop_id"] == SOLID_ID)
		assert_int(hits.size()).is_equal(1)
		if hits.size() == 1:
			assert_int(int(hits[0]["kind"])).is_equal(ObjectManager.SandboxPropKind.BLOCKER)
			assert_str(String(hits[0]["label"])).is_equal("Building (6×3)")
