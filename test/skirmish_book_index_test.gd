extends GdUnitTestSuite
## Plan step 25: the two skirmish games resolve a list's faction key from the book index without the network. Their
## books share the armyIds of their GF/AoF twins but carry their own book names, so `army_books_index.json` has its own
## gff and aofs sections (tools/army_books_index.py --merge --known-only). The fixture is our own made-up unit; only the
## armyId points at a real book.

const FIXTURE := "res://test/fixtures/card_list_gff_own_stats_400.json"


func test_a_gff_list_gets_its_faction_key_offline() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var client := OPRApiClient.new()
	var army: OPRApiClient.OPRArmy = client.build_army_offline(data)
	client.free()
	assert_object(army).is_not_null()
	assert_str(army.game_system_abbrev).is_equal("gff")
	assert_str(army.faction_folder).is_equal("orc_marauders")


func test_both_skirmish_sections_resolve_and_a_missing_book_stays_empty() -> void:
	assert_str(str(OPRApiClient.book_index_entry("1wj1ysgxpuuz9bc7", "gff").get("faction_folder", ""))).is_equal("orc_marauders")
	assert_str(str(OPRApiClient.book_index_entry("0EXXlzFwAk3q1n5e", "aofs").get("faction_folder", ""))).is_equal("halflings")
	assert_dict(OPRApiClient.book_index_entry("no-such-book", "gff")).is_empty()


func test_the_snapshot_path_reads_a_gff_book() -> void:
	var dir := "user://skirmish_book_index_test"
	DirAccess.make_dir_recursive_absolute(dir.path_join("gff"))
	var f := FileAccess.open(dir.path_join("gff/1wj1ysgxpuuz9bc7.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": "Test Book"}))
	f.close()
	var before := OS.get_environment(OPRApiClient.SNAPSHOT_DIR_ENV)
	OS.set_environment(OPRApiClient.SNAPSHOT_DIR_ENV, ProjectSettings.globalize_path(dir))
	# the static read `_snapshot_book` makes, without its once-per-process pin (other suites share the process)
	var book: Dictionary = OPRApiClient._snapshot_json("gff/1wj1ysgxpuuz9bc7.json")
	OS.set_environment(OPRApiClient.SNAPSHOT_DIR_ENV, before)
	assert_str(str(book.get("name", ""))).is_equal("Test Book")
