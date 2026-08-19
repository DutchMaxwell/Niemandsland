extends GdUnitTestSuite
## #339 — the Blast overlay: a Blast(X) volley pointed at a single model wastes
## the rule (each hit multiplies by min(X, models in target)). The house overlay
## prefers the fullest reachable unit, CAPPED at X, and ranks BELOW the three
## book overlays (Takedown > Deadly > AP > Blast) so it never overrides them.


func _cand(dist: float, blast_pref: int, activated: bool = false) -> Dictionary:
	return {"dist": dist, "activated": activated, "in_cover": false, "defense": 4,
		"is_hero": false, "has_upgrade": false, "upgrade_cost": 0,
		"single_tough": false, "has_tough": false, "remaining_tough": 1,
		"blast_pref": blast_pref}


func test_weapon_overlay_detects_blast_below_the_book_set() -> void:
	assert_int(AiTargeting.weapon_overlay(["Blast(3)"])).is_equal(AiTargeting.Overlay.BLAST)
	# Any book overlay on the same weapon outranks the house extension.
	assert_int(AiTargeting.weapon_overlay(["Blast(3)", "Deadly(3)"])).is_equal(AiTargeting.Overlay.DEADLY)
	assert_int(AiTargeting.weapon_overlay(["Blast(6)", "AP(2)"])).is_equal(AiTargeting.Overlay.AP)
	assert_int(AiTargeting.weapon_overlay(["Rending"])).is_equal(AiTargeting.Overlay.NONE)


func test_blast_prefers_the_fuller_unit_across_distance() -> void:
	# The reported game: 1-model tank NEARER, 10-model squad farther — the squad
	# must win under the Blast overlay (blast_pref 1 vs 3 for a Blast(3) gun).
	var tank := _cand(8.0, 1)
	var squad := _cand(15.0, 3)
	assert_int(AiTargeting.best_index([tank, squad], AiTargeting.Overlay.BLAST)).is_equal(1)
	# Without the overlay the official nearest key keeps the tank — the base
	# behaviour is untouched.
	assert_int(AiTargeting.best_index([tank, squad], AiTargeting.Overlay.NONE)).is_equal(0)


func test_blast_cap_makes_full_units_tie_and_base_key_decides() -> void:
	# Blast(3): a 3-model and a 10-model unit both fill the cap (blast_pref 3) —
	# beyond-cap models must not pull, so the nearer one wins the base key.
	var three_near := _cand(8.0, 3)
	var ten_far := _cand(15.0, 3)
	assert_int(AiTargeting.best_index([ten_far, three_near], AiTargeting.Overlay.BLAST)).is_equal(1)
	var tied: Array = AiTargeting.tied_with_best([_cand(8.0, 3), _cand(8.0, 3)],
		AiTargeting.Overlay.BLAST, 0)
	assert_int(tied.size()).is_equal(2)


func test_not_activated_still_outranks_within_equal_blast_pref() -> void:
	# The base key survives under the overlay tier: equal blast_pref, the
	# not-yet-activated candidate wins even when farther.
	var acted_near := _cand(6.0, 3, true)
	var fresh_far := _cand(14.0, 3, false)
	assert_int(AiTargeting.best_index([acted_near, fresh_far], AiTargeting.Overlay.BLAST)).is_equal(1)
