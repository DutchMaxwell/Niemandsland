extends GdUnitTestSuite
## SetupOpponent, the model of step 04 "Who is at the table?": the lists of exactly the picked game system (ported
## from the AI Opponent dialog's suite), the largest bracket by default, the three labels, the fall to two players
## while Solo is off, and the choice that travels to the table.

const MANIFEST := {
	"orc_tribes": {"name": "Orc Tribes", "system": "gf", "lists": [
		{"points": 1000, "file": "orc_tribes_1000.json"}, {"points": 2000, "file": "orc_tribes_2000.json"}]},
	"aof_orc_tribes": {"name": "Orc Tribes", "system": "aof", "lists": [{"points": 1000, "file": "aof_orc_tribes_1000.json"}]},
	"alien_hives": {"name": "Alien Hives", "lists": [
		{"points": 3000, "file": "alien_hives_3000.json"}, {"points": 750, "file": "alien_hives_750.json"}]},
}


func after_test() -> void:
	ProjectSettings.set_setting(PendingOpponent.KEY, null)


func _model(system: String = "gf", manifest: Dictionary = MANIFEST) -> SetupOpponent:
	var m := SetupOpponent.new()
	m.set_system(system)
	m.set_manifest(manifest)
	return m


func _names(m: SetupOpponent) -> Array:
	return m.factions().map(func(f: Array) -> String: return f[1])


func test_a_gf_table_is_offered_only_the_gf_lists() -> void:
	assert_array(_names(_model("gf"))).is_equal(["Alien Hives", "Orc Tribes"])


func test_an_aof_table_is_offered_only_the_aof_lists() -> void:
	assert_array(_names(_model("aof"))).is_equal(["Orc Tribes"])


func test_a_system_without_lists_falls_to_two_players() -> void:
	var m := _model("aof", {"alien_hives": MANIFEST["alien_hives"]})
	assert_bool(m.solo_available()).is_false()
	assert_str(m.who).is_equal("local")
	assert_str(m.off_line()).is_equal("No NACHTMAHR lists for %s yet." % GameSystem.label("aof"))


func test_the_largest_bracket_is_the_default() -> void:
	var m := _model()
	assert_str(m.faction).is_equal("alien_hives")
	assert_array(m.brackets()).is_equal([3000, 750])
	assert_int(m.bracket).is_equal(0)
	m.choose_faction("orc_tribes")
	assert_int(m.bracket).is_equal(1)


func test_a_system_change_keeps_the_faction_while_it_is_offered() -> void:
	var m := _model()
	m.choose_faction("orc_tribes")
	m.set_system("gf")
	assert_str(m.faction).is_equal("orc_tribes")
	m.set_system("aof")
	assert_str(m.faction).is_equal("aof_orc_tribes")
	m.set_system("gff")
	assert_str(m.who).is_equal("local")
	m.set_system("gf")
	assert_str(m.who).is_equal("solo")


func test_the_three_labels() -> void:
	var m := _model()
	assert_str(m.label()).is_equal("NACHTMAHR · Alien Hives · 3000")
	m.choose_who("local")
	assert_str(m.label()).is_equal("Two players, one screen")
	m.choose_who("online")
	assert_str(m.label()).is_equal("Online room")


func test_solo_is_off_while_loading_and_without_a_manifest() -> void:
	var m := SetupOpponent.new()
	m.loading = true
	m.set_system("gf")
	assert_str(m.off_line()).is_equal("Loading NACHTMAHR's lists ...")
	assert_str(m.who).is_equal("local")
	m.set_manifest({})
	assert_str(m.off_line()).is_equal("NACHTMAHR's lists need a connection the first time.")
	m.set_manifest(MANIFEST)
	assert_str(m.who).is_equal("solo")
	assert_str(m.off_line()).is_equal("")


func test_the_stored_choice() -> void:
	var m := _model()
	m.choose_bracket(1)
	m.choose_seat(1)
	m.commit()
	assert_dict(ProjectSettings.get_setting(PendingOpponent.KEY)).is_equal(
		{"who": "solo", "file": "alien_hives_750.json", "slot": 1, "label": "NACHTMAHR · Alien Hives · 750"})
	m.choose_who("local")
	m.commit()
	assert_dict(ProjectSettings.get_setting(PendingOpponent.KEY)).is_equal(
		{"who": "local", "label": "Two players, one screen"})
