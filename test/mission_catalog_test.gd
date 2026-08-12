extends GdUnitTestSuite
## Missions wave M1 — the catalog data model. The duel entry must state
## TODAY'S implicit mission exactly (rounds 4, d3+2 markers placed
## alternately with the 9" gaps, front-line deployment, end scoring): any
## drift here would silently redefine the game every consumer builds on.
## Unknown ids and a broken catalog fall back to duel — data refines,
## never breaks.


func before_test() -> void:
	MissionCatalog.reset_cache()


func test_catalog_lists_the_v1_four() -> void:
	assert_that(MissionCatalog.mission_ids()).is_equal(
		["breakthrough", "duel", "king_of_the_hill", "seize_ground"])


func test_duel_matches_todays_live_constants() -> void:
	var m := MissionCatalog.get_mission("duel")
	assert_str(str(m["family"])).is_equal("face_off")
	assert_int(int(m["rounds"])).is_equal(4)
	assert_str(str(m["scoring"])).is_equal("end")
	assert_str(str(m["deployment"])).is_equal("front_line")
	var mk: Dictionary = m["markers"]
	assert_str(str(mk["count"])).is_equal("d3+2")
	assert_str(str(mk["placement"])).is_equal("alternate")
	assert_int(int(mk["min_gap_in"])).is_equal(9)
	assert_int(int(mk["outside_zones_in"])).is_equal(9)


func test_unknown_id_falls_back_to_duel() -> void:
	var m := MissionCatalog.get_mission("no_such_mission")
	assert_that(m).is_equal(MissionCatalog.get_mission("duel"))


func test_marker_count_is_deterministic_per_seed_and_in_range() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var duel := MissionCatalog.get_mission("duel")
	var a := MissionCatalog.marker_count(duel, rng)
	rng.seed = 7
	var b := MissionCatalog.marker_count(duel, rng)
	assert_int(a).is_equal(b)
	assert_bool(a >= 3 and a <= 5).is_true()
	assert_int(MissionCatalog.marker_count(
		MissionCatalog.get_mission("king_of_the_hill"), rng)).is_equal(1)
	assert_int(MissionCatalog.marker_count(
		MissionCatalog.get_mission("seize_ground"), rng)).is_equal(4)
