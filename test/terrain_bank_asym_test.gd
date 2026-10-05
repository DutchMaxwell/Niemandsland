extends GdUnitTestSuite
## Stage-0 step 2: the bank dumper can write ASYMMETRIC boards from an explicit seed list.
## Default output stays byte-identical to the shipped bank; `symmetric=0` boards carry
## `"symmetric": 0` and break the point symmetry; `parse_seeds` is exact for 63-bit seeds.

const DUMP := "res://tools/terrain_bank_dump.gd"
# The v1 bank (terrain_bank/) predates the wall/blocker layers; v2 is the current dump format.
const BANK := "~/selfplay_out/terrain_bank_v2"


func _tmp_dir(tag: String) -> String:
	var d := OS.get_environment("HOME").path_join(".cache/nml-stage0-seal/tmp_" + tag)
	DirAccess.make_dir_recursive_absolute(d)
	return d


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _dump(out: String, seeds: String, symmetric: int, extra: Array = []) -> int:
	var seeds_file := out.path_join("seeds.txt")
	_write(seeds_file, seeds)
	var output := []
	return OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", DUMP, "--", "out=" + out, "seeds=" + seeds_file, "symmetric=%d" % symmetric] + extra, output)


func test_parse_seeds_reads_two_63_bit_seeds_exactly() -> void:
	var p := _tmp_dir("parse").path_join("s.txt")
	_write(p, "9223372036854775807\n146134785981946573\n\n")
	var s: Array = (load(DUMP) as GDScript).parse_seeds(p)
	assert_that(s).is_equal([9223372036854775807, 146134785981946573])


func test_generate_asymmetric_differs_and_breaks_point_symmetry() -> void:
	var sym := SchoolTerrain.generate(4242)
	var asym := SchoolTerrain.generate(4242, 6.0, 4.0, false)
	assert_bool(sym["cells"] == asym["cells"]).is_false()
	var cells: Dictionary = asym["cells"]
	var n: int = asym["n"]
	var broken := false
	for cell in cells:
		var m := Vector2i(n - 1 - (cell as Vector2i).x, n - 1 - (cell as Vector2i).y)
		if cells.get(m, -1) != cells[cell]:
			broken = true
	assert_bool(broken).is_true()


func test_default_dump_matches_shipped_bank_and_asym_dump_is_flagged() -> void:
	var bank := BANK.replace("~", OS.get_environment("HOME"))
	if not FileAccess.file_exists(bank.path_join("board_21.json")):
		return   # skipped: shipped bank absent on this machine
	var out := _tmp_dir("default")
	assert_int(_dump(out, "21\n22\n23\n", 1)).is_equal(0)
	for n in [21, 22, 23]:
		var fname := "board_%d.json" % n
		assert_that(FileAccess.get_file_as_string(out.path_join(fname))) \
			.is_equal(FileAccess.get_file_as_string(bank.path_join(fname)))
	var out_a := _tmp_dir("asym")
	assert_int(_dump(out_a, "21\n", 0)).is_equal(0)
	var board: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out_a.path_join("board_21.json")))
	assert_that(int(board["symmetric"])).is_equal(0)
	assert_bool(FileAccess.get_file_as_string(out_a.path_join("board_21.json")) \
		!= FileAccess.get_file_as_string(bank.path_join("board_21.json"))).is_true()


## Table-realism (04.10.): a school board's header line carried `walls: []` while the same layout raises
## the table's ruin walls (the board's own top-level `walls`), so a trainer reading the bank planned and
## moved on a wall-less table. `walls=1` puts the table's walls into the header line, one entry per wall
## segment; the default dump keeps `[]` (every bank and corpus written before replays as it was).
func test_walls_dump_carries_the_tables_walls_in_the_header_line() -> void:
	var out := _tmp_dir("walls_on")
	assert_int(_dump(out, "21\n", 1, ["walls=1"])).is_equal(0)
	var board: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out.path_join("board_21.json")))
	var table_walls := (board["walls"] as Array).size()
	assert_int(table_walls).is_greater(0)
	assert_int(((board["terrain"] as Dictionary)["walls"] as Array).size()) \
		.override_failure_message("the header line drops the table's walls").is_equal(table_walls)
	var off := _tmp_dir("walls_off")
	assert_int(_dump(off, "21\n", 1)).is_equal(0)
	var plain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(off.path_join("board_21.json")))
	assert_int(((plain["terrain"] as Dictionary)["walls"] as Array).size()).is_equal(0)
