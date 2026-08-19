extends GdUnitTestSuite
## Missions wave M1 — the catalog data model. The duel entry must state
## TODAY'S implicit mission exactly (rounds 4, d3+2 markers placed
## alternately with the 9" gaps, front-line deployment, end scoring): any
## drift here would silently redefine the game every consumer builds on.
## Unknown ids and a broken catalog fall back to duel — data refines,
## never breaks.


func before_test() -> void:
	MissionCatalog.reset_cache()


func test_catalog_lists_the_v3_ten() -> void:
	# v1 four Face-Off + four carry-free Progressive (W2) + the two
	# destroy-marker missions (W3); the carry pair waits for its wave.
	assert_that(MissionCatalog.mission_ids()).is_equal(
		["breakthrough", "demolition", "domination", "duel", "headquarters",
		"king_of_the_hill", "mosh_pit", "pitched_battle", "sabotage",
		"seize_ground"])


## W3 — the destroy-marker pair carries owned/destructible flags and the
## demolition VP mode; sabotage scores by its own end verdict.
func test_destroy_missions_carry_book_flags() -> void:
	var sab := MissionCatalog.get_mission("sabotage")
	assert_str(str(sab["scoring"])).is_equal("sabotage")
	var smk: Dictionary = sab["markers"]
	assert_bool(bool(smk.get("owned", false))).is_true()
	assert_bool(bool(smk.get("destructible", false))).is_true()
	var dem := MissionCatalog.get_mission("demolition")
	assert_str(str(dem["scoring"])).is_equal("round_vp")
	assert_str(str((dem.get("vp", {}) as Dictionary).get("mode", ""))).is_equal("demolition")
	assert_bool(bool((dem["markers"] as Dictionary).get("owned", false))).is_true()


## W2 — the progressive entries carry the book's scoring flavours and reuse
## the proven placements (HQ shares breakthrough's 12" line by contract).
func test_progressive_missions_carry_book_flavours() -> void:
	var style := DeploymentCatalog.get_style("front_line")
	var pb := MissionCatalog.get_mission("pitched_battle")
	assert_str(str(pb["scoring"])).is_equal("round_vp")
	assert_str(str((pb.get("vp", {}) as Dictionary).get("majority", ""))).is_equal("end")
	assert_that(MissionCatalog.marker_positions(pb, style)).is_equal([])
	var dom := MissionCatalog.get_mission("domination")
	assert_str(str((dom.get("vp", {}) as Dictionary).get("majority", ""))).is_equal("round")
	assert_int(MissionCatalog.marker_positions(dom, style).size()).is_equal(4)
	var hq := MissionCatalog.get_mission("headquarters")
	assert_str(str((hq.get("vp", {}) as Dictionary).get("majority", ""))).is_equal("end")
	assert_that(MissionCatalog.marker_positions(hq, style)).is_equal(
		[Vector2(0.0, -12.0), Vector2(0.0, 12.0)])
	var mp := MissionCatalog.get_mission("mosh_pit")
	assert_str(str((mp.get("vp", {}) as Dictionary).get("majority", ""))).is_equal("none")
	assert_bool(bool((mp.get("vp", {}) as Dictionary).get("first_seize", false))).is_true()
	assert_that(MissionCatalog.marker_positions(mp, style)).is_equal([Vector2.ZERO])


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


## M3: automatic placement modes resolve to book positions; Duel's
## 'alternate' stays a hand-placement flow (empty list by contract).
func test_marker_positions_modes() -> void:
	var style := DeploymentCatalog.get_style("front_line")
	var sg := MissionCatalog.get_mission("seize_ground")
	var q := MissionCatalog.marker_positions(sg, style)
	assert_int(q.size()).is_equal(4)
	assert_that(q[0]).is_equal(Vector2(-18.0, -12.0))
	assert_that(q[3]).is_equal(Vector2(18.0, 12.0))
	var bt := MissionCatalog.get_mission("breakthrough")
	var z := MissionCatalog.marker_positions(bt, style)
	assert_int(z.size()).is_equal(2)
	# the book puts the marker 12" from the table edge (the zone FRONT on a
	# standard 12" zone), not on the zone centroid 6" deeper — the centroid
	# variant bred 87-90% structural draws in the corpus
	assert_that(z[0]).is_equal(Vector2(0.0, -12.0))
	assert_that(z[1]).is_equal(Vector2(0.0, 12.0))
	var koth := MissionCatalog.get_mission("king_of_the_hill")
	assert_that(MissionCatalog.marker_positions(koth, style)).is_equal([Vector2.ZERO])
	var duel := MissionCatalog.get_mission("duel")
	assert_that(MissionCatalog.marker_positions(duel, style)).is_equal([])
