extends GdUnitTestSuite
## A table load must not freeze the main loop while the biome battlemap is prepared. Delivered battlemaps
## are ~7.5k px WebPs; decoding one and scaling it to BATTLEMAP_MAX_WIDTH took ~2.3 s in ONE frame on the
## main thread (measured on the acceptance run: a 2.3-2.8 s gap after every table load, solo too). The
## image work now runs on the worker pool; only the texture upload stays on the main thread.

const MAP := "user://table_battlemap_decode_test.webp"
## The size the R2 battlemaps are delivered at (urban_ruins, temperate_grassland: 7584 x 5088).
const DELIVERED := Vector2i(7584, 5088)


## Serves the battlemap file and counts the requests (no download).
class FakeLibrary extends BiomeLibrary:
	var path := ""
	var requests := 0

	func ensure_biome(_biome_key: String) -> String:
		requests += 1
		return path


## The real table script inside the tree, without its _ready: no BiomeLibrary of its own, no R2 request.
class QuietTable extends "res://scripts/table.gd":
	func _ready() -> void:
		pass


func before() -> void:
	var img := Image.create(DELIVERED.x, DELIVERED.y, false, Image.FORMAT_RGB8)
	img.fill(Color(0.42, 0.38, 0.3))
	img.save_webp(MAP)


func after() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MAP))


func _table(library: FakeLibrary) -> Node:
	var table: Node = QuietTable.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "TableMesh"
	table.add_child(mesh)
	var collision := CollisionShape3D.new()
	collision.name = "TableCollision"
	table.add_child(collision)
	table._biome_library = library
	add_child(table)
	return auto_free(table)


func test_a_battlemap_never_stalls_the_main_loop_for_a_second() -> void:
	var library: FakeLibrary = auto_free(FakeLibrary.new())
	library.path = MAP
	var table := _table(library)
	var start := Time.get_ticks_msec()
	var last := start
	table.set_biome("arid_desert")
	var longest := Time.get_ticks_msec() - last
	last = Time.get_ticks_msec()
	while table._battlemap_biome != "arid_desert" and last - start < 60000:
		await get_tree().process_frame
		longest = maxi(longest, Time.get_ticks_msec() - last)
		last = Time.get_ticks_msec()
	assert_str(table._battlemap_biome).is_equal("arid_desert")   # it still arrives ...
	assert_int(library.requests).is_equal(1)
	var mat := table.mesh_instance.material_override as ShaderMaterial
	var tex := mat.get_shader_parameter("albedo_tex") as Texture2D
	assert_int(tex.get_width()).is_equal(table.BATTLEMAP_MAX_WIDTH)   # ... scaled as before
	assert_int(longest).override_failure_message(
		"the main loop stood still for %d ms while the battlemap was prepared" % longest).is_less(1000)
