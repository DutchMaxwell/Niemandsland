extends GdUnitTestSuite
## Missions wave M1 — the catalog data model. The duel entry must state
## TODAY'S implicit mission exactly (rounds 4, d3+2 markers placed
## alternately with the 9" gaps, front-line deployment, end scoring): any
## drift here would silently redefine the game every consumer builds on.
## Unknown ids and a broken catalog fall back to duel — data refines,
## never breaks.


func before_test() -> void:
	MissionCatalog.reset_cache()


func test_catalog_lists_the_shipped_missions() -> void:
	# The original ten, the two carried-marker missions, and the Attack & Defend ones that shipped.
	assert_that(MissionCatalog.mission_ids()).is_equal(
		["breakthrough", "capture_and_hold", "demolition", "domination", "duel",
		"headquarters", "king_of_the_hill", "last_stand", "mosh_pit", "pitched_battle",
		"relic_hunt", "sabotage", "seize_ground", "smash_and_grab"])


## D14.6 — Smash & Grab (GF/AoF Advanced Rules v3.5.1, p.27 / p.26): 6 rounds, roles with the
## attacker's +25 % points, d3+2 markers hiding a trap and a relic, decided by an edge extraction.
func test_smash_and_grab_is_the_attack_and_defend_extract_mission() -> void:
	var m := MissionCatalog.get_mission("smash_and_grab")
	assert_str(str(m["name"])).is_equal("Smash & Grab")
	assert_str(str(m["family"])).is_equal("attack_defend")
	assert_int(int(m["rounds"])).is_equal(6)
	assert_str(str(m["scoring"])).is_equal("extract")
	assert_bool(bool(m["roles"])).is_true()
	assert_float(float(m["attacker_points_factor"])).is_equal(1.25)
	assert_str(str(m["deployment"])).is_equal("front_line")
	var mk: Dictionary = m["markers"]
	assert_str(str(mk["count"])).is_equal("d3+2")
	assert_str(str(mk["placement"])).is_equal("alternate")
	assert_bool(bool(mk["secret"])).is_true()
	assert_bool(mk.has("carry")).is_false()   # only the relic carries, and it is chosen at the roll-off
	assert_that(MissionCatalog.marker_positions(m, DeploymentCatalog.get_style("front_line"))).is_equal([])


func test_carry_missions_have_three_alternate_relics() -> void:
	for id in ["relic_hunt", "capture_and_hold"]:
		var mission := MissionCatalog.get_mission(id)
		var mk: Dictionary = mission["markers"]
		assert_int(int(mk["count"])).is_equal(3)
		assert_str(str(mk["placement"])).is_equal("alternate")
		assert_bool(bool(mk.get("carry", false))).is_true()
		assert_that(MissionCatalog.marker_positions(mission,
			DeploymentCatalog.get_style("front_line"))).is_equal([])
	assert_str(str(MissionCatalog.get_mission("relic_hunt")["scoring"])).is_equal("end")
	assert_str(str(MissionCatalog.get_mission("capture_and_hold")["scoring"])).is_equal("round_vp")
	assert_str(str((MissionCatalog.get_mission("capture_and_hold").get("vp", {}) as Dictionary).get("majority", ""))) \
		.is_equal("end")


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
	# Book (GF Advanced Rules v3.5.1 p.25/26): quarter the NON-deployment zone
	# area (audit §2.11) — front_line's zones end at z = ±12, so the band is
	# z in [-12, 12] and the centres are (±18, ±6); the old ±12 sat on the
	# deployment line.
	assert_that(q[0]).is_equal(Vector2(-18.0, -6.0))
	assert_that(q[3]).is_equal(Vector2(18.0, 6.0))
	# Property, not just literals: every marker's z strictly inside the band.
	for c in q:
		assert_float(absf((c as Vector2).y)).is_less(12.0)
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


## D14.3 — Last Stand (GF/AoF Advanced Rules v3.5.1, p.27 / p.26): 6 rounds, roles, the defender's whole
## army in the 12" disc round the central marker, the attacker in the 12" edge frame; a destroyed
## attacker unit returns to reserve once on a 6; the marker's holder wins.
func test_last_stand_is_the_attack_and_defend_recycle_mission() -> void:
	var m := MissionCatalog.get_mission("last_stand")
	assert_str(str(m["name"])).is_equal("Last Stand")
	assert_str(str(m["family"])).is_equal("attack_defend")
	assert_int(int(m["rounds"])).is_equal(6)
	assert_str(str(m["scoring"])).is_equal("end")
	assert_bool(bool(m["roles"])).is_true()
	assert_bool(m.has("attacker_points_factor")).override_failure_message("the book grants no +25 % here").is_false()
	assert_that(m["deploy_phases"]).is_equal([["defender", "all", "centre_disc_12"], ["attacker", "all", "edge_band_12"]])
	var r: Dictionary = m["reserves"]
	assert_str(str(r["who"])).is_equal("attacker")
	assert_bool(bool(r["recycle"])).is_true()
	assert_int(int(r["arrive_on"])).is_equal(6)
	assert_str(str(r["zone"])).is_equal("edge_band_12")
	var style := DeploymentCatalog.get_style("front_line")
	assert_that(MissionCatalog.marker_positions(m, style)).is_equal([Vector2.ZERO])
	for id in ["centre_disc_12", "edge_band_12"]:
		assert_bool(DeploymentCatalog.style_ids().has(id)).is_true()
