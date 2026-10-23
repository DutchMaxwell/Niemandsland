extends GdUnitTestSuite
## table.set_biome with the biome already on the table is a no-op (REPORT_mp_drops New A): every guest
## state sync pushed the biome again, and each push re-decoded the battlemap (~2 s on the main thread)
## and rebuilt the presentation. A real change, and the forced path, still apply.


## Counts the battlemap applies instead of decoding one (not in the tree: no mesh, no download).
class CountingTable extends "res://scripts/table.gd":
	var applied := 0

	func _apply_biome(_biome_name: String) -> void:
		applied += 1


func test_same_biome_neither_reapplies_nor_rebuilds() -> void:
	var table: Node = auto_free(CountingTable.new())
	var changed: Array = []
	table.biome_changed.connect(func(b: String) -> void: changed.append(b))
	table.set_biome(table.biome)   # what each sync pushed: the biome already on the table
	assert_int(table.applied).is_equal(0)
	assert_array(changed).is_empty()
	table.set_biome("arid_desert")
	assert_int(table.applied).is_equal(1)
	assert_array(changed).is_equal(["arid_desert"])


func test_forced_same_biome_rebuilds() -> void:
	var table: Node = auto_free(CountingTable.new())
	table.set_biome(table.biome, true)
	assert_int(table.applied).is_equal(1)
