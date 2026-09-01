extends GdUnitTestSuite
## AI ARENA — the difficulty POLICY KNOBS (SoloDifficulty). NML-211 (maintainer 2026-07-22): there
## is exactly ONE grade — NACHTMAHR, every knob at its ceiling; weaker personas return later as
## presets. The knob MACHINERY (seeded noise bands, mission-focus draws) stays fully covered here
## via manually-built knob instances, so the later rebuild lands on tested ground.


func _knobs(noise: float, focus: float, seed_v: int) -> SoloDifficulty:
	var d := SoloDifficulty.new()
	d.ev_noise = noise
	d.mission_focus = focus
	d.base_seed = seed_v
	return d


func test_the_one_grade_is_nachtmahr_with_every_knob_at_ceiling() -> void:
	assert_array(SoloDifficulty.grade_names()).contains_exactly(["nachtmahr"])
	var d := SoloDifficulty.for_grade("nachtmahr")
	assert_str(d.grade_name).is_equal("nachtmahr")
	assert_float(d.ev_noise).is_equal(0.0)
	assert_float(d.rule_exploitation).is_equal(1.0)
	assert_float(d.mission_focus).is_equal(1.0)
	assert_float(d.coordination).is_equal(1.0)
	assert_float(d.persistence).is_equal(1.0)
	assert_bool(d.lookahead).is_true()
	assert_bool(d.avoid_overkill).is_true()
	assert_bool(d.endgame_convergence).is_true()
	assert_bool(d.exploits_rules()).is_true()
	assert_bool(d.focus_fires()).is_true()
	assert_bool(d.spend_boosts()).is_true()
	assert_bool(d.converges_endgame()).is_true()
	for knob in ["grade", "ev_noise", "rule_exploitation", "mission_focus", "coordination", "lookahead"]:
		assert_bool(d.to_dict().has(knob)).override_failure_message("missing knob %s" % knob).is_true()


func test_every_legacy_and_unknown_name_resolves_to_nachtmahr() -> void:
	for name in SoloDifficulty.LEGACY_GRADE_ALIASES + ["nonsense", "ALBTRAUM", "  kriegsherr "]:
		var d := SoloDifficulty.for_grade(str(name))
		assert_str(d.grade_name).override_failure_message("'%s' did not resolve" % name).is_equal("nachtmahr")
		assert_float(d.ev_noise).is_equal(0.0)


func test_nachtmahr_never_deviates_regardless_of_seed() -> void:
	# ev_noise 0 + mission_focus 1 ⇒ noisy_pick == best and skips_objective == false for EVERY seed:
	# the "no dumb play at the ceiling" invariant.
	var d := SoloDifficulty.for_grade("nachtmahr", 7)
	for i in range(200):
		assert_int(d.noisy_pick(3, [1, i, 999])).is_equal(0)
		assert_bool(d.skips_objective([1, i, 999])).is_false()


func test_noise_machinery_is_reproducible_for_a_fixed_seed() -> void:
	# The knob machinery survives the grade collapse (weaker personas rebuild on it later).
	var a := _knobs(0.40, 0.35, 42)
	var b := _knobs(0.40, 0.35, 42)
	for i in range(100):
		var parts := [2, i, 314]
		assert_int(a.noisy_pick(3, parts)).is_equal(b.noisy_pick(3, parts))   # same seed ⇒ identical
	var c := _knobs(0.40, 0.35, 43)
	var diffs := 0
	for i in range(100):
		if a.noisy_pick(3, [2, i, 314]) != c.noisy_pick(3, [2, i, 314]):
			diffs += 1
	assert_int(diffs).is_greater(0)


func test_noise_machinery_deviation_rate_tracks_the_knob() -> void:
	var noisy := _knobs(0.40, 1.0, 1000)
	var deviations := 0
	var total := 2000
	for i in range(total):
		if noisy.noisy_pick(3, [1, i, 55]) > 0:
			deviations += 1
	assert_float(float(deviations) / float(total)).is_between(0.34, 0.46)   # ≈ 0.40
	assert_int(noisy.noisy_pick(1, [1, 1, 1])).is_equal(0)   # nothing to deviate to
	assert_int(noisy.noisy_pick(0, [1, 1, 1])).is_equal(0)


func test_mission_focus_machinery_skip_rate_tracks_the_knob() -> void:
	var loose := _knobs(0.0, 0.35, 2222)   # focus 0.35 → ~0.65 skip
	var skips := 0
	var total := 2000
	for i in range(total):
		if loose.skips_objective([1, i, 77]):
			skips += 1
	assert_float(float(skips) / float(total)).is_between(0.59, 0.71)


func test_base_seed_is_stamped_by_for_grade() -> void:
	assert_int(SoloDifficulty.for_grade("nachtmahr", 12345).base_seed).is_equal(12345)


# === NML-1140 step 8 — the placement ladder ====================================

## Set → resolve → unset BEFORE asserting, so a failing assert can never leak the
## env into a sibling test (the env is process-wide).
func _resolve_with_env(env_word: String, p1 := "nachtmahr", p2 := "nachtmahr",
		objectives := "rulebook") -> String:
	OS.set_environment("NML_OBJECTIVE_DOCTRINE", env_word)
	var r := SoloDifficulty.resolve_placement(p1, p2, objectives)
	OS.set_environment("NML_OBJECTIVE_DOCTRINE", "")
	return r


func test_placement_knob_round_trips_for_every_preset() -> void:
	for key in SoloDifficulty.PRESETS:
		var d := SoloDifficulty.for_grade(str(key), 7)
		assert_str(str(SoloDifficulty.PRESETS[key]["placement"])) \
			.override_failure_message("preset %s carries the search rung (the ladder decision)" % key) \
			.is_equal("search")
		var flat := d.to_dict()
		assert_str(str(flat.get("placement", "MISSING"))) \
			.override_failure_message("preset %s: placement missing from to_dict" % key) \
			.is_equal(str(d.placement))
		# the true round-trip: the flat view re-derives itself through for_grade
		assert_dict(SoloDifficulty.for_grade(str(flat["grade"])).to_dict()).is_equal(flat)


func test_resolver_env_beats_preset_and_preset_decides_when_unset() -> void:
	# Unset env: the preset decides — every preset is nachtmahr-grade, so "search";
	# gradeless harnesses (core/solo selfplay) land on the default preset the same way.
	OS.set_environment("NML_OBJECTIVE_DOCTRINE", "")
	assert_str(SoloDifficulty.resolve_placement("nachtmahr", "nachtmahr", "rulebook")).is_equal("search")
	assert_str(SoloDifficulty.resolve_placement("", "", "")).is_equal("search")
	assert_str(SoloDifficulty.resolve_placement("kriegsherr", "veteran", "rulebook")).is_equal("search")
	# The env beats the preset — including pinning the rulebook draw back over a
	# search preset (the A/B pairing's control arm).
	assert_str(_resolve_with_env("rulebook")).is_equal("rulebook")
	assert_str(_resolve_with_env("style")).is_equal("style")
	assert_str(_resolve_with_env("search")).is_equal("search")
	assert_str(_resolve_with_env("rulebook", "nachtmahr", "nachtmahr", "")).is_equal("rulebook")
	# A typo'd word and an armed rung without the rulebook layout: loud "?" (quit law).
	assert_str(_resolve_with_env("aggressive")).is_equal("?")
	assert_str(_resolve_with_env("style", "nachtmahr", "nachtmahr", "")).is_equal("?")
