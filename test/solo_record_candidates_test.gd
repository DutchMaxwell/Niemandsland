extends GdUnitTestSuite
## Stage 1 record honesty — the CANDIDATE LIST of a 'target' record. The cited rule ("nearest valid
## target, not-activated first") is a claim about a SET, but the record wrote down only the tie group:
## a pick out of four enemies claimed "considered 4" and named one unit, so the cited rule was neither
## provable nor refutable. Record-only — the pick is made above the write, so the chosen target is
## asserted in every case as well.

const IN2M := 0.0254


func _unit(pid: int, x_in: float, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 5, "defense": 4}
	var m := ModelInstance.new()
	m.is_alive = true
	m.unit = u
	var n := Node3D.new()
	add_child(n)
	n.global_position = Vector3(x_in * IN2M, 0, 0)
	m.node = n
	u.models.append(m)
	return u


## `n` fresh enemies on an ascending distance ramp, so each lands in its own tie band and the official
## key leaves exactly ONE winner — the shape that produced the bad records. Then: the record must list
## `expect` candidates and say so, and E0 must still be the pick.
func _assert_record_lists(n: int, expect: int) -> void:
	var actor := _unit(2, 0.0, "Actor")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {actor.unit_id: actor}
	army.current_round = 1
	for i in range(n):
		army.game_units["E%d" % i] = _unit(1, 6.0 + float(i) * 2.0, "E%d" % i)
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	var recs: Array = []
	solo.decision_sink = func(rec: Dictionary) -> void:
		if str(rec.get("kind", "")) == "target":
			recs.append(rec)

	var picked := solo.nearest_human_unit(actor)

	assert_str(str(picked.unit_id)).override_failure_message(
		"behaviour guard: the nearest fresh enemy is still the pick").is_equal("E0")
	assert_int(recs.size()).is_equal(1)
	var cands: Array = recs[0]["candidates"] as Array
	var data: Dictionary = recs[0]["data"] as Dictionary
	assert_int(int(data["considered"])).is_equal(n)
	# THE FIX: a rule claiming "nearest of N" must name what it ranked, and own up to what it left out.
	assert_int(cands.size()).override_failure_message(
		"record claims %d considered but lists %d" % [n, cands.size()]).is_equal(expect)
	assert_int(int(data.get("listed", -1))).override_failure_message(
		"the record must say how many candidates it wrote").is_equal(expect)
	var names: Array = []
	for c in cands:
		names.append(str((c as Dictionary)["name"]))
		assert_bool((c as Dictionary).has("key")).is_true()   # the official key it was ranked by
	assert_array(names).contains(["E0", "E1"])   # the winner AND a beaten also-ran, by name


func test_target_record_lists_every_candidate_it_claims_to_have_considered() -> void:
	_assert_record_lists(4, 4)   # the whole considered set fits under the cap, so all of it is written


func test_target_record_caps_the_list_and_says_how_many_it_wrote() -> void:
	# 8 is pinned as a literal on purpose: a test that read the constant it guards would still pass if
	# the cap silently became 500.
	_assert_record_lists(12, 8)
