extends GdUnitTestSuite
## Solo-AI M2: AiTargeting — the OPR Solo & Co-Op v3.5.0 (p.2) weapon target-selection overlays
## (AP → best Defense, Deadly → single-model Tough, Takedown → hero) over the base nearest/not-activated/
## in-the-open priority. Verified against GF - Solo & Co-Op Rules v3.5.0.


## A candidate descriptor with sensible defaults; override only the fields a case cares about.
func _cand(over: Dictionary = {}) -> Dictionary:
	var c := {
		"dist": 10.0, "activated": false, "in_cover": false, "defense": 4,
		"is_hero": false, "has_upgrade": false, "upgrade_cost": 0,
		"single_tough": false, "has_tough": false, "remaining_tough": 0,
	}
	for k in over:
		c[k] = over[k]
	return c


# === weapon_overlay ===

func test_weapon_overlay_detects_each_rule() -> void:
	assert_int(AiTargeting.weapon_overlay(["AP(1)"])).is_equal(AiTargeting.Overlay.AP)
	assert_int(AiTargeting.weapon_overlay(["Deadly(3)"])).is_equal(AiTargeting.Overlay.DEADLY)
	assert_int(AiTargeting.weapon_overlay(["Takedown"])).is_equal(AiTargeting.Overlay.TAKEDOWN)
	assert_int(AiTargeting.weapon_overlay([])).is_equal(AiTargeting.Overlay.NONE)
	assert_int(AiTargeting.weapon_overlay(["Blast(3)"])).is_equal(AiTargeting.Overlay.NONE)


func test_weapon_overlay_precedence_takedown_over_deadly_over_ap() -> void:
	# A weapon carrying several overlay rules picks the most specific one (documented tie-break).
	assert_int(AiTargeting.weapon_overlay(["AP(2)", "Deadly(3)", "Takedown"])).is_equal(AiTargeting.Overlay.TAKEDOWN)
	assert_int(AiTargeting.weapon_overlay(["AP(2)", "Deadly(3)"])).is_equal(AiTargeting.Overlay.DEADLY)


# === base priority (Overlay.NONE) ===

func test_base_prefers_not_activated_then_open_then_nearest() -> void:
	# A far, un-activated, open target beats a near, activated one (not-activated dominates).
	var far_fresh := _cand({"dist": 20.0, "activated": false})
	var near_done := _cand({"dist": 5.0, "activated": true})
	assert_int(AiTargeting.best_index([near_done, far_fresh], AiTargeting.Overlay.NONE)).is_equal(1)
	# Among two un-activated, the one in the open beats the one in cover.
	var open_far := _cand({"dist": 15.0, "in_cover": false})
	var cover_near := _cand({"dist": 6.0, "in_cover": true})
	assert_int(AiTargeting.best_index([cover_near, open_far], AiTargeting.Overlay.NONE)).is_equal(1)
	# All else equal → nearest.
	assert_int(AiTargeting.best_index([_cand({"dist": 9.0}), _cand({"dist": 4.0})], AiTargeting.Overlay.NONE)).is_equal(1)


func test_empty_candidates_returns_minus_one() -> void:
	assert_int(AiTargeting.best_index([], AiTargeting.Overlay.AP)).is_equal(-1)


# === AP overlay: highest Defense first ===

func test_ap_targets_highest_defense_over_nearest() -> void:
	var near_soft := _cand({"dist": 4.0, "defense": 3})
	var far_tanky := _cand({"dist": 18.0, "defense": 6})
	assert_int(AiTargeting.best_index([near_soft, far_tanky], AiTargeting.Overlay.AP)).is_equal(1)
	# Defense tie → falls back to the base tie-break (nearest here).
	var a := _cand({"dist": 12.0, "defense": 5})
	var b := _cand({"dist": 3.0, "defense": 5})
	assert_int(AiTargeting.best_index([a, b], AiTargeting.Overlay.AP)).is_equal(1)


# === Deadly overlay: single-model Tough, then Tough (lowest remaining), then the rest ===

func test_deadly_prioritises_single_model_tough_then_lowest_remaining_tough() -> void:
	var single_tough := _cand({"dist": 20.0, "single_tough": true, "has_tough": true, "remaining_tough": 6})
	var multi_tough := _cand({"dist": 5.0, "has_tough": true, "remaining_tough": 3})
	var no_tough := _cand({"dist": 2.0})
	# The single-model Tough unit wins even though it is farthest.
	assert_int(AiTargeting.best_index([no_tough, multi_tough, single_tough], AiTargeting.Overlay.DEADLY)).is_equal(2)
	# Without a single-model Tough present, a Tough unit beats a non-Tough one …
	assert_int(AiTargeting.best_index([no_tough, multi_tough], AiTargeting.Overlay.DEADLY)).is_equal(1)
	# … and among Tough units the lowest total remaining Tough is finished first.
	var tough_hi := _cand({"has_tough": true, "remaining_tough": 9, "dist": 3.0})
	var tough_lo := _cand({"has_tough": true, "remaining_tough": 2, "dist": 15.0})
	assert_int(AiTargeting.best_index([tough_hi, tough_lo], AiTargeting.Overlay.DEADLY)).is_equal(1)


# === Takedown overlay: heroes first ===

func test_takedown_targets_heroes_first() -> void:
	var grunt_near := _cand({"dist": 3.0})
	var hero_far := _cand({"dist": 22.0, "is_hero": true})
	assert_int(AiTargeting.best_index([grunt_near, hero_far], AiTargeting.Overlay.TAKEDOWN)).is_equal(1)
	# No hero present → base tie-break (nearest).
	assert_int(AiTargeting.best_index([_cand({"dist": 8.0}), _cand({"dist": 4.0})], AiTargeting.Overlay.TAKEDOWN)).is_equal(1)


func test_tied_with_best_returns_the_genuine_ties() -> void:
	# Two candidates share the full official key (a genuine tie the hybrid policy ranks by EV);
	# the third loses on distance and is not in the tied set.
	var a := _cand({"dist": 5.0})
	var b := _cand({"dist": 5.0})
	var c := _cand({"dist": 9.0})
	var best := AiTargeting.best_index([a, b, c], AiTargeting.Overlay.NONE)
	var tied := AiTargeting.tied_with_best([a, b, c], AiTargeting.Overlay.NONE, best)
	assert_int(tied.size()).is_equal(2)
	assert_bool(tied.has(0) and tied.has(1)).is_true()
	assert_int(AiTargeting.tied_with_best([], AiTargeting.Overlay.NONE, -1).size()).is_equal(0)
