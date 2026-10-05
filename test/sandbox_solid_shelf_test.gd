extends GdUnitTestSuite
## The terrain shelf offers each free solid once in every biome, with its confirmed label (maintainer picks 04.10.:
## plain block, slab-roof storehouse B, heather outcrop C). Placing it goes through
## ObjectManager.spawn_sandbox_terrain (test/sandbox_solid_spawn_test.gd).

const SOLIDS := {"blocker_6x3": "Building (6×3)", "longhouse_6x3": "Slab-roof storehouse (6×3)",
	"outcrop_6x3": "Heather outcrop (6×3)"}


func test_shelf_lists_each_solid_once_in_every_biome() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	for prefix in ObjectManager.SANDBOX_BIOME_PREFIXES:
		for id: String in SOLIDS:
			var hits := om.sandbox_catalog(prefix).filter(func(e: Dictionary) -> bool: return e["prop_id"] == id)
			assert_int(hits.size()).override_failure_message("%s in %s" % [id, prefix]).is_equal(1)
			if hits.size() == 1:
				assert_int(int(hits[0]["kind"])).is_equal(ObjectManager.SandboxPropKind.BLOCKER)
				assert_str(String(hits[0]["label"])).is_equal(SOLIDS[id])


func test_every_shelf_solid_has_a_bundled_look() -> void:
	for id: String in ObjectManager.SANDBOX_SOLIDS:
		var look: String = ObjectManager.SANDBOX_SOLIDS[id].get("look", "plain")
		assert_bool(SandboxSolidProp.LOOKS.has(look)).override_failure_message("%s -> %s" % [id, look]).is_true()
