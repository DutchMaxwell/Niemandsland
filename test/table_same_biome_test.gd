extends GdUnitTestSuite
## table.set_biome with the biome already on the table rebuilds nothing (REPORT_mp_drops New A): every
## guest state sync pushed the biome again, and each push re-decoded the battlemap (~2 s on the main
## thread) and rebuilt the presentation. Only a battlemap that never arrived is fetched again (a flaky
## link must not leave the table on the fallback surface), still without the rebuild. Force re-applies.

const TableScript := preload("res://scripts/table.gd")
const MAP := "user://table_same_biome_test.png"


## Serves a battlemap file (or "" = the download failed) and counts the requests.
class FakeLibrary extends BiomeLibrary:
	var path := ""
	var requests := 0

	func ensure_biome(_biome_key: String) -> String:
		requests += 1
		return path


func after() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MAP))


func _map() -> String:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.4, 0.5, 0.3))
	img.save_png(MAP)
	return MAP


## The real set_biome/_apply_biome, outside the tree: a bare mesh and the fake library, no download.
func _table(library: FakeLibrary) -> Node:
	var table: Node = auto_free(TableScript.new())
	table.mesh_instance = auto_free(MeshInstance3D.new())
	table._biome_library = library
	return table


func test_same_biome_with_its_battlemap_in_place_is_a_no_op() -> void:
	var library: FakeLibrary = auto_free(FakeLibrary.new())
	library.path = _map()
	var table := _table(library)
	var changed: Array = []
	table.biome_changed.connect(func(b: String) -> void: changed.append(b))
	table.set_biome("arid_desert")   # a real change: fetched, decoded, applied
	table.set_biome("arid_desert")   # what each sync pushed: nothing to do
	assert_int(library.requests).is_equal(1)
	assert_array(changed).is_equal(["arid_desert"])


func test_same_biome_after_a_failed_battlemap_fetches_it_again_without_a_rebuild() -> void:
	var library: FakeLibrary = auto_free(FakeLibrary.new())   # path "" = the download failed
	var table := _table(library)
	var changed: Array = []
	table.biome_changed.connect(func(b: String) -> void: changed.append(b))
	table.set_biome("arid_desert")
	library.path = _map()            # the link is back
	table.set_biome("arid_desert")   # retried ...
	assert_int(library.requests).is_equal(2)
	assert_array(changed).is_equal(["arid_desert"])   # ... but not rebuilt
	table.set_biome("arid_desert")   # in place now: a no-op again
	assert_int(library.requests).is_equal(2)


func test_forced_same_biome_rebuilds() -> void:
	var library: FakeLibrary = auto_free(FakeLibrary.new())
	library.path = _map()
	var table := _table(library)
	table.set_biome("arid_desert")
	table.set_biome("arid_desert", true)
	assert_int(library.requests).is_equal(2)
