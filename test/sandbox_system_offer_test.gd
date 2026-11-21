extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 11: the terrain shelf offers what the table's game system offers. ObjectManager.sandbox_catalog
## takes the system (default: the table's) and returns nothing for a biome the system does not offer; the shelf's biome filter
## lists only those biomes. gf offers the 12 pieces of every biome it always did. Red proof: on main a fantasy shelf listed the
## Urban Ruins filter and its pieces.


class StubManager extends Node:
	var system := "gf"

	func table_system() -> String:
		return system

	func get_cursor_table_position() -> Vector3:
		return Vector3.ZERO

	func sandbox_catalog(_prefix: String) -> Array:
		return []


func _ids(entries: Array) -> Array:
	return entries.map(func(e: Dictionary) -> String: return str(e["prop_id"]))


func test_gf_keeps_the_twelve_pieces_of_every_biome() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	for prefix in ObjectManager.SANDBOX_BIOME_PREFIXES:
		assert_int(om.sandbox_catalog(prefix, "gf").size()).override_failure_message("gf lost pieces in biome '%s'" % prefix).is_equal(12)


func test_a_fantasy_table_gets_no_urban_and_no_jungle_pieces() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	for system in ["aof", "aofs", "aofr"]:
		assert_array(om.sandbox_catalog("urban_", system)).override_failure_message("%s lists urban pieces" % system).is_empty()
		assert_array(om.sandbox_catalog("jungle_", system)).override_failure_message("%s lists jungle pieces" % system).is_empty()
		for prefix in ["", "desert_", "tundra_", "volcanic_"]:
			assert_int(om.sandbox_catalog(prefix, system).size()).is_equal(12)
	assert_int(om.sandbox_catalog("urban_", "gff").size()).is_equal(12)   # a grimdark skirmish table keeps them


func test_the_default_system_is_the_tables_and_a_bare_manager_filters_nothing() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	assert_str(om.table_system()).is_equal("")   # outside the tree / without Main: no system, no filter
	assert_int(om.sandbox_catalog("urban_").size()).is_equal(12)


func _shelf(system: String) -> Array:
	var stub: StubManager = auto_free(StubManager.new())
	stub.system = system
	var shelf: SandboxTerrainShelf = auto_free(SandboxTerrainShelf.new())
	add_child(shelf)
	shelf.setup(stub)
	shelf.open()
	var option: OptionButton = shelf._biome_option
	var labels: Array = []
	for i in option.item_count:
		labels.append(option.get_item_text(i))
	return labels


func test_the_shelf_biome_filter_follows_the_system() -> void:
	assert_array(_shelf("gf")).is_equal(["Grassland", "Arid Desert", "Frozen Tundra", "Volcanic Ash", "Alien Jungle", "Urban Ruins"])
	assert_array(_shelf("aofs")).is_equal(["Grassland", "Arid Desert", "Frozen Tundra", "Volcanic Ash"])
	assert_array(_shelf("")).has_size(6)
