extends GdUnitTestSuite
## PARITY: the clone scores in GDScript exactly what torch scored in training.
## The fixture carries RANDOM weights on purpose — this proves the maths, not
## the policy. A drifted implementation would steer real games with a
## different brain, so the loader refuses a net whose selftest disagrees.

const FIXTURE := "res://test/data/clone_parity.json"


func _fixture() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)) as Dictionary


func test_gdscript_scores_match_torch_to_1e_minus_4() -> void:
	var net := _fixture()
	var st: Dictionary = net["selftest"]
	var got := AiClone.scores(net, st["board"], int(st["side"]), st["menu"])
	assert_int(got.size()).is_equal((st["expected"] as Array).size())
	for i in range(got.size()):
		assert_float(float(got[i])).is_equal_approx(float((st["expected"] as Array)[i]), 1e-4)


func test_a_drifted_net_is_refused() -> void:
	var net := _fixture()
	assert_bool(AiClone.selftest_ok(net)).is_true()
	var bent := net.duplicate(true)
	var b: Array = bent["head_b1"]
	b[0] = float(b[0]) + 1.0        # one nudged bias = a different brain
	bent["head_b1"] = b
	assert_bool(AiClone.selftest_ok(bent)).is_false()


## NML-1010 night finding: a confident net exports scores around 41k, where
## float32 itself cannot hold the 3rd decimal — the wv00s duel lost all 120
## games to "selftest mismatch at 0: 41151.166128 vs 41151.167969". The
## tolerance must scale with the magnitude (float rounding is not drift)
## while genuine drift keeps failing.
func test_score_close_scales_with_magnitude() -> void:
	assert_bool(AiClone.score_close(41151.166128, 41151.167969)).is_true()
	assert_bool(AiClone.score_close(0.809998, 0.810000)).is_true()
	assert_bool(AiClone.score_close(41151.0, 41160.0)).is_false()
	assert_bool(AiClone.score_close(0.80, 0.82)).is_false()


func test_menu_tuples_speak_the_trainer_s_language() -> void:
	var st: Dictionary = _fixture()["selftest"]
	var a: Dictionary = (st["menu"] as Array)[0]
	# width follows the net: 18 pre-terrain, 19 with cover, 20 with cover+sight
	var v := AiClone.action_vec(a, st["board"] as Array, int(st["side"]), 0)
	assert_int(v.size()).is_equal(18)
	assert_int(AiClone.action_vec(a, st["board"] as Array, int(st["side"]), 1).size()).is_equal(19)
	assert_int(AiClone.action_vec(a, st["board"] as Array, int(st["side"]), 2).size()).is_equal(20)
	assert_float(float(v[int(a["kind"])])).is_equal(1.0)
	assert_float(float(v[5])).is_equal_approx(float(a["dest_x"]) / 36.0, 1e-6)
	assert_float(float(v[7])).is_equal(1.0 if int(a["victim_row"]) >= 0 else 0.0)
	# terrain wave: cover rides in slot 18, sight in slot 19
	var cv := int(a.get("cover", -1))
	var wide := AiClone.action_vec(a, st["board"] as Array, int(st["side"]), 2)
	assert_float(float(wide[18])).is_equal(0.5 if cv < 0 else float(cv))
	var sn := int(a.get("seen", -1))
	var of := int(a.get("seen_of", 0))
	assert_float(float(wide[19])).is_equal(
		0.5 if sn < 0 else (0.0 if of <= 0 else float(sn) / float(of)))


func test_the_vector_width_follows_the_net_not_the_build() -> void:
	# A net trained before the terrain wave must still be scored with the
	# vector IT learned — otherwise an old generation silently plays a
	# different brain than the one that was measured.
	assert_int(AiClone.extras_for(18)).is_equal(0)
	assert_int(AiClone.extras_for(19)).is_equal(1)
	assert_int(AiClone.extras_for(20)).is_equal(2)
	assert_int(AiClone.extras_for(99)).is_equal(2)      # never wider than we build
	assert_int(AiClone.extras_for(5)).is_equal(0)       # never negative


func test_the_loader_serves_every_width_the_vector_can_build() -> void:
	# The gate and the vector must agree BY CONSTRUCTION. On 16.08. they did
	# not: action_vec could build 20, the loader still admitted only 18 and 19,
	# and every terrain net was silently refused at load while these very
	# tests stayed green — because they tested the vector and nobody tested
	# the gate. A width the vector can build must be a width the loader takes.
	var base := 5 + 5 + AiClone.GEO_DIM
	for dim in [base, base + 1, base + 2]:
		assert_int(base + AiClone.extras_for(dim)).is_equal(dim)
	# and a width we genuinely cannot serve must still be refused
	for bad in [base - 1, base + 3]:
		assert_int(base + AiClone.extras_for(bad)).is_not_equal(bad)


func test_sight_is_a_share_not_a_count() -> void:
	# Two of four enemies holding a lane must read the same as one of two —
	# the number has to mean the same thing whatever the army size.
	var board: Array = _fixture()["selftest"]["board"]
	var half_of_4 := AiClone.action_vec({"kind": 1, "seen": 2, "seen_of": 4}, board, 1, 2)
	var half_of_2 := AiClone.action_vec({"kind": 1, "seen": 1, "seen_of": 2}, board, 1, 2)
	assert_float(float(half_of_4[19])).is_equal(0.5)
	assert_float(float(half_of_4[19])).is_equal(float(half_of_2[19]))
	# and the ends stay ends
	assert_float(float(AiClone.action_vec({"kind": 1, "seen": 0, "seen_of": 3},
		board, 1, 2)[19])).is_equal(0.0)
	assert_float(float(AiClone.action_vec({"kind": 1, "seen": 3, "seen_of": 3},
		board, 1, 2)[19])).is_equal(1.0)
