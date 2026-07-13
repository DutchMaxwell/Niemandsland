extends GdUnitTestSuite
## AI ARENA — the difficulty POLICY KNOBS (SoloDifficulty). Pure, deterministic, seeded: same seed + same
## preset ⇒ identical "mistakes". These tests pin the preset table shape, the reproducibility of every
## seeded draw, and the boundary invariant that the ceiling grades (Kriegsherr/Albtraum) never deviate.


func test_preset_table_has_all_four_named_grades_with_every_knob() -> void:
	var names := SoloDifficulty.grade_names()
	assert_array(names).contains_exactly(["rekrut", "veteran", "kriegsherr", "albtraum"])
	for key in names:
		var d := SoloDifficulty.for_grade(key)
		var dict := d.to_dict()
		for knob in ["grade", "ev_noise", "rule_exploitation", "mission_focus", "coordination", "lookahead"]:
			assert_bool(dict.has(knob)).override_failure_message("%s missing knob %s" % [key, knob]).is_true()


func test_grade_knob_values_follow_the_ladder() -> void:
	var rekrut := SoloDifficulty.for_grade("rekrut")
	var veteran := SoloDifficulty.for_grade("veteran")
	var kriegsherr := SoloDifficulty.for_grade("kriegsherr")
	var albtraum := SoloDifficulty.for_grade("albtraum")
	# Rekrut: high noise, NO exploitation, low focus, NO coordination.
	assert_float(rekrut.ev_noise).is_greater(0.3)
	assert_float(rekrut.rule_exploitation).is_equal(0.0)
	assert_float(rekrut.mission_focus).is_less(0.5)
	assert_float(rekrut.coordination).is_equal(0.0)
	# Noise is monotone down the ladder; Kriegsherr and Albtraum are the sharp, no-noise ceiling.
	assert_float(rekrut.ev_noise).is_greater(veteran.ev_noise)
	assert_float(veteran.ev_noise).is_greater(kriegsherr.ev_noise)
	assert_float(kriegsherr.ev_noise).is_equal(0.0)
	assert_float(albtraum.ev_noise).is_equal(0.0)
	# The ceiling grades: full exploitation, full focus, full coordination.
	for d in [kriegsherr, albtraum]:
		assert_bool(d.exploits_rules()).is_true()
		assert_float(d.mission_focus).is_equal(1.0)
		assert_bool(d.focus_fires()).is_true()
	# Albtraum is the ceiling flag; the others are not.
	assert_bool(albtraum.lookahead).is_true()
	assert_bool(kriegsherr.lookahead).is_false()
	assert_bool(rekrut.lookahead).is_false()


func test_unknown_grade_falls_back_to_kriegsherr() -> void:
	var d := SoloDifficulty.for_grade("nonsense")
	assert_str(d.grade_name).is_equal("kriegsherr")
	assert_float(d.ev_noise).is_equal(0.0)


func test_exploits_and_focus_fire_thresholds() -> void:
	assert_bool(SoloDifficulty.for_grade("rekrut").exploits_rules()).is_false()
	assert_bool(SoloDifficulty.for_grade("veteran").exploits_rules()).is_false()   # 0.5 < EXPLOIT_THRESHOLD
	assert_bool(SoloDifficulty.for_grade("kriegsherr").exploits_rules()).is_true()
	assert_bool(SoloDifficulty.for_grade("rekrut").focus_fires()).is_false()       # coordination 0 → spread
	assert_bool(SoloDifficulty.for_grade("veteran").focus_fires()).is_true()       # 0.6 ≥ COORD_THRESHOLD
	# spend_boosts mirrors the exploitation gate (future boost subsystem hook).
	assert_bool(SoloDifficulty.for_grade("kriegsherr").spend_boosts()).is_true()
	assert_bool(SoloDifficulty.for_grade("rekrut").spend_boosts()).is_false()


func test_ceiling_grades_never_deviate_regardless_of_seed() -> void:
	# Kriegsherr/Albtraum have ev_noise 0 and mission_focus 1 → noisy_pick == best, skips_objective == false,
	# for EVERY seed. This is the "no illegal, no dumb play at the ceiling" invariant.
	for grade in ["kriegsherr", "albtraum"]:
		var d := SoloDifficulty.for_grade(grade, 7)
		for i in range(200):
			assert_int(d.noisy_pick(3, [1, i, 999])).override_failure_message(
				"%s deviated at i=%d" % [grade, i]).is_equal(0)
			assert_bool(d.skips_objective([1, i, 999])).is_false()


func test_noisy_pick_is_reproducible_for_a_fixed_seed() -> void:
	var a := SoloDifficulty.for_grade("rekrut", 42)
	var b := SoloDifficulty.for_grade("rekrut", 42)
	for i in range(100):
		var parts := [2, i, 314]
		assert_int(a.noisy_pick(3, parts)).is_equal(b.noisy_pick(3, parts))   # same seed ⇒ identical
	# A different base seed produces an independent (generally different) mistake stream.
	var c := SoloDifficulty.for_grade("rekrut", 43)
	var diffs := 0
	for i in range(100):
		if a.noisy_pick(3, [2, i, 314]) != c.noisy_pick(3, [2, i, 314]):
			diffs += 1
	assert_int(diffs).is_greater(0)


func test_noisy_pick_deviation_rate_approximates_ev_noise() -> void:
	# Over many independent seeds, the fraction of deviations (index > 0) tracks ev_noise. Deterministic per
	# seed, but the ENSEMBLE rate is the knob's meaning: Rekrut (0.40) deviates ~40%, and never at ev_noise 0.
	var rekrut := SoloDifficulty.for_grade("rekrut", 1000)
	var deviations := 0
	var total := 2000
	for i in range(total):
		if rekrut.noisy_pick(3, [1, i, 55]) > 0:
			deviations += 1
	var rate := float(deviations) / float(total)
	assert_float(rate).is_between(0.34, 0.46)   # ≈ 0.40, loose bound for the finite sample
	# The 3rd-best is only ever taken on the deeper half of the deviation band (n ≥ 3).
	var got_third := false
	for i in range(total):
		if rekrut.noisy_pick(3, [1, i, 55]) == 2:
			got_third = true
			break
	assert_bool(got_third).is_true()


func test_noisy_pick_degenerate_inputs() -> void:
	var rekrut := SoloDifficulty.for_grade("rekrut", 5)
	assert_int(rekrut.noisy_pick(1, [1, 1, 1])).is_equal(0)   # nothing to deviate to
	assert_int(rekrut.noisy_pick(0, [1, 1, 1])).is_equal(0)
	# With only 2 candidates it can deviate to index 1 but never 2.
	var saw_two := false
	for i in range(500):
		if rekrut.noisy_pick(2, [1, i, 1]) == 2:
			saw_two = true
	assert_bool(saw_two).is_false()


func test_skips_objective_rate_tracks_mission_focus() -> void:
	# mission_focus == 1.0 (Kriegsherr) never skips; a lower focus skips with probability 1 − focus.
	assert_bool(SoloDifficulty.for_grade("kriegsherr", 9).skips_objective([1, 1, 1])).is_false()
	var rekrut := SoloDifficulty.for_grade("rekrut", 2222)   # mission_focus 0.35 → ~0.65 skip
	var skips := 0
	var total := 2000
	for i in range(total):
		if rekrut.skips_objective([1, i, 77]):
			skips += 1
	assert_float(float(skips) / float(total)).is_between(0.59, 0.71)   # ≈ 0.65


func test_base_seed_is_stamped_by_for_grade() -> void:
	assert_int(SoloDifficulty.for_grade("rekrut", 12345).base_seed).is_equal(12345)
