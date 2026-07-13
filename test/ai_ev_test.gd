extends GdUnitTestSuite
## Solo-AI capstone: AiEv — the expected-value metric that fills the official rules' undefined "better
## than" and ranks genuine ties, built on the SAME AiCombatMath helpers as the dice resolution. These
## prove the rule sensitivity the maintainer asked for (Stealth devalues beyond 9", Deadly prefers
## Tough, Blast prefers big units, …), the charge-score hooks (Counter reduces, Fearless raises risk
## tolerance) and determinism.


## A ranged profile dict in the AiShooting shape; override what a case cares about.
func _rprof(over: Dictionary = {}) -> Dictionary:
	var p := {"name": "Rifle", "attacks": 10, "ap": 0, "deadly": 0, "relentless": false, "blast": 0,
		"reliable": false, "surge": false, "rending": false, "bane": false, "thrust": false,
		"counter": false, "range": 24, "rules": []}
	for k in over:
		p[k] = over[k]
	return p


func _mprof(over: Dictionary = {}) -> Dictionary:
	var p := _rprof({"name": "Blades", "range": 0})
	for k in over:
		p[k] = over[k]
	return p


const ATT := {"quality": 4, "models": 5}
const DEF_PLAIN := {"defense": 4, "tough": 1, "models": 5}


func test_profile_ev_baseline_matches_expected_wounds() -> void:
	# No special rules: 10 attacks, hit 4+ (1/2), save 4+ fails 1/2 → 2.5 — identical to the wave-0
	# AiCombatMath.expected_wounds metric (one math, no second truth).
	assert_float(AiEv.profile_ev(_rprof(), ATT, DEF_PLAIN, 12.0, false)).is_equal_approx(
		AiCombatMath.expected_wounds(10, 4, 4, 0), 0.0001)


func test_stealth_devalues_targets_beyond_nine_inches_only() -> void:
	var stealthy := {"defense": 4, "tough": 1, "models": 5, "stealth": true}
	# Beyond 9": Stealth −1 to hit → lower EV than the same target without Stealth.
	var far_stealth: float = AiEv.profile_ev(_rprof(), ATT, stealthy, 12.0, false)
	var far_plain: float = AiEv.profile_ev(_rprof(), ATT, DEF_PLAIN, 12.0, false)
	assert_bool(far_stealth < far_plain).is_true()
	# Within 9" Stealth does nothing (GF v3.5.1 p.14 — "over 9\" away").
	assert_float(AiEv.profile_ev(_rprof(), ATT, stealthy, 8.0, false)).is_equal_approx(
		AiEv.profile_ev(_rprof(), ATT, DEF_PLAIN, 8.0, false), 0.0001)


func test_deadly_prefers_tough_targets() -> void:
	# Deadly(3): vs Tough(3) each unsaved wound triples; vs Tough 1 it stays single (p.13 + p.10).
	var w := _rprof({"deadly": 3, "attacks": 3})
	var tough3 := {"defense": 4, "tough": 3, "models": 3}
	assert_bool(AiEv.profile_ev(w, ATT, tough3, 12.0, false) >
		AiEv.profile_ev(w, ATT, DEF_PLAIN, 12.0, false) * 2.0).is_true()


func test_blast_prefers_big_units() -> void:
	# Blast(3) multiplies each hit by min(X, models): 10-model target doubles+ the 2-model one.
	var w := _rprof({"blast": 3, "attacks": 2})
	var big := {"defense": 4, "tough": 1, "models": 10}
	var small := {"defense": 4, "tough": 1, "models": 2}
	assert_float(AiEv.profile_ev(w, ATT, big, 12.0, false)).is_equal_approx(
		AiEv.profile_ev(w, ATT, small, 12.0, false) * 1.5, 0.0001)   # ×3 vs ×2 multiplier


func test_shielded_and_cover_lower_ev_blast_ignores_cover_only() -> void:
	var shielded := {"defense": 4, "tough": 1, "models": 5, "shielded": true}
	assert_bool(AiEv.profile_ev(_rprof(), ATT, shielded, 12.0, false) <
		AiEv.profile_ev(_rprof(), ATT, DEF_PLAIN, 12.0, false)).is_true()
	var covered := {"defense": 4, "tough": 1, "models": 5, "in_cover": true}
	var plain_ev: float = AiEv.profile_ev(_rprof(), ATT, DEF_PLAIN, 12.0, false)
	assert_bool(AiEv.profile_ev(_rprof(), ATT, covered, 12.0, false) < plain_ev).is_true()
	# Blast ignores cover (GF v3.5.1): the covered target scores the same as the open one.
	var bw := _rprof({"blast": 2})
	assert_float(AiEv.profile_ev(bw, ATT, covered, 12.0, false)).is_equal_approx(
		AiEv.profile_ev(bw, ATT, DEF_PLAIN, 12.0, false), 0.0001)


func test_reliable_rending_bane_raise_ev() -> void:
	var base: float = AiEv.profile_ev(_rprof(), ATT, DEF_PLAIN, 12.0, false)
	assert_bool(AiEv.profile_ev(_rprof({"reliable": true}), ATT, DEF_PLAIN, 12.0, false) > base).is_true()
	assert_bool(AiEv.profile_ev(_rprof({"rending": true}), ATT, DEF_PLAIN, 12.0, false) > base).is_true()
	assert_bool(AiEv.profile_ev(_rprof({"bane": true}), ATT, DEF_PLAIN, 12.0, false) > base).is_true()


func test_regeneration_lowers_ev_but_bane_bypasses_it() -> void:
	var regen := {"defense": 4, "tough": 1, "models": 5, "regeneration": true}
	var base: float = AiEv.profile_ev(_rprof(), ATT, DEF_PLAIN, 12.0, false)
	# Regeneration ignores each wound on 5+ → ×2/3.
	assert_float(AiEv.profile_ev(_rprof(), ATT, regen, 12.0, false)).is_equal_approx(base * 2.0 / 3.0, 0.0001)
	# A Bane weapon bypasses Regeneration entirely (wave-1 _solo_ignores_regen rule).
	assert_bool(AiEv.profile_ev(_rprof({"bane": true}), ATT, regen, 12.0, false) >
		AiEv.profile_ev(_rprof(), ATT, regen, 12.0, false)).is_true()


func test_charge_score_counter_reduces_and_fearless_raises() -> void:
	var us := {"quality": 4, "defense": 4, "tough": 1, "models": 5}
	var them := {"quality": 4, "defense": 4, "tough": 1, "models": 5}
	var them_counter := {"quality": 4, "defense": 4, "tough": 1, "models": 5, "counter_models": 5}
	var our_melee: Array = [_mprof()]
	var their_plain: Array = [_mprof({"counter": false})]
	var their_counter: Array = [_mprof({"counter": true})]
	# A Counter defender lowers the charge score (strike-first attrition; same weapons otherwise).
	var vs_plain: float = AiEv.charge_score(our_melee, us, their_plain, them)
	var vs_counter: float = AiEv.charge_score(our_melee, us, their_counter, them_counter)
	assert_bool(vs_counter < vs_plain).is_true()
	# Our Fearless halves the taken-wounds weight (p.13 morale re-roll) → higher score, same matchup.
	var us_fearless := {"quality": 4, "defense": 4, "tough": 1, "models": 5, "fearless": true}
	assert_bool(AiEv.charge_score(our_melee, us_fearless, their_plain, them) > vs_plain).is_true()


func test_impact_ev_reduced_by_counter_models() -> void:
	var att := {"quality": 4, "impact": 3, "models": 2}
	var no_counter := {"defense": 4, "tough": 1, "models": 5}
	var with_counter := {"defense": 4, "tough": 1, "models": 5, "counter_models": 3}
	assert_bool(AiEv.impact_ev(att, with_counter) < AiEv.impact_ev(att, no_counter)).is_true()
	assert_float(AiEv.impact_ev({"impact": 0, "models": 5}, no_counter)).is_equal_approx(0.0, 0.0001)


func test_classify_fills_the_undefined_better_than() -> void:
	# No ranged weapon → MELEE (Solo v3.5.0 p.1).
	assert_int(AiEv.classify([{"name": "CCW", "range_value": 0, "attacks": 2, "count": 5, "special_rules": []}],
		{"quality": 4})).is_equal(AiArchetype.Type.MELEE)
	# A rifle squad with a token CCW: ranged EV wins → SHOOTING.
	var rifles: Array = [
		{"name": "Rifle", "range_value": 24, "attacks": 1, "count": 10, "special_rules": []},
		{"name": "Fists", "range_value": 0, "attacks": 1, "count": 2, "special_rules": []},
	]
	assert_int(AiEv.classify(rifles, {"quality": 4})).is_equal(AiArchetype.Type.SHOOTING)
	# A heavy melee unit with a token pistol: melee EV wins → HYBRID (Furious/charge bonuses count).
	var brutes: Array = [
		{"name": "Pistol", "range_value": 12, "attacks": 1, "count": 1, "special_rules": []},
		{"name": "Great Axes", "range_value": 0, "attacks": 4, "count": 5, "special_rules": ["AP(2)"]},
	]
	assert_int(AiEv.classify(brutes, {"quality": 4})).is_equal(AiArchetype.Type.HYBRID)


func test_ev_is_deterministic() -> void:
	var w := _rprof({"deadly": 3, "rending": true, "blast": 2})
	var d := {"defense": 5, "tough": 3, "models": 4, "stealth": true, "in_cover": true}
	assert_float(AiEv.profile_ev(w, ATT, d, 14.0, false)).is_equal_approx(
		AiEv.profile_ev(w, ATT, d, 14.0, false), 0.000001)


# === Wave-4: Destructive and Self-Repair flow through the EV ===

func test_destructive_raises_ev_like_rending_via_ap4_on_sixes() -> void:
	# Destructive upgrades the expected unmodified-6 hits to AP(+4) — more expected wounds than a plain
	# weapon, matching Rending's EV effect (same AP(+4)-on-6 math).
	var plain := AiEv.profile_ev(_rprof(), ATT, DEF_PLAIN, 12.0, false)
	var destructive := AiEv.profile_ev(_rprof({"destructive": true}), ATT, DEF_PLAIN, 12.0, false)
	var rending := AiEv.profile_ev(_rprof({"rending": true}), ATT, DEF_PLAIN, 12.0, false)
	assert_bool(destructive > plain).is_true()
	assert_float(destructive).is_equal_approx(rending, 0.0001)


func test_self_repair_regen_target_is_six_and_devalues_shooting() -> void:
	# Self-Repair (6+ ignore) is worth less than Regeneration (5+) to the shooter, and both devalue vs a
	# plain defender — the EV sees the wound-ignore rate, per unit rule.
	var self_repair := {"defense": 4, "tough": 1, "models": 5, "regeneration": true, "regen_target": 6}
	var regen5 := {"defense": 4, "tough": 1, "models": 5, "regeneration": true, "regen_target": 5}
	var plain_ev := AiEv.profile_ev(_rprof(), ATT, DEF_PLAIN, 12.0, false)
	var sr_ev := AiEv.profile_ev(_rprof(), ATT, self_repair, 12.0, false)
	var rg_ev := AiEv.profile_ev(_rprof(), ATT, regen5, 12.0, false)
	assert_bool(sr_ev < plain_ev).is_true()      # 6+ ignore reduces wounds
	assert_bool(sr_ev > rg_ev).is_true()          # but less reduction than a 5+ regen


# === Wave-5: the new primitives flow through the EV (the AI VALUES them) ===

func test_shred_raises_ev_by_hits_over_six() -> void:
	# Shred: every save die (one per hit) that rolls a natural 1 deals +1 wound → expected +hits/6,
	# not Deadly-multiplied (mirrors the dice path's save-step reading).
	var base: float = AiEv.profile_ev(_rprof(), ATT, DEF_PLAIN, 12.0, false)
	var shred: float = AiEv.profile_ev(_rprof({"shred": true}), ATT, DEF_PLAIN, 12.0, false)
	# 10 attacks at 4+ → 5 expected hits → +5/6 expected shred wounds.
	assert_float(shred).is_equal_approx(base + 5.0 / 6.0, 0.0001)


func test_indirect_ignores_cover_in_the_ev() -> void:
	# Indirect ignores cover from sight obstructions: a covered target scores like an open one.
	var covered := {"defense": 4, "tough": 1, "models": 5, "in_cover": true}
	var w := _rprof({"indirect": true})
	assert_float(AiEv.profile_ev(w, ATT, covered, 12.0, false)).is_equal_approx(
		AiEv.profile_ev(w, ATT, DEF_PLAIN, 12.0, false), 0.0001)
	# A non-Indirect weapon still pays the cover tax (control).
	assert_bool(AiEv.profile_ev(_rprof(), ATT, covered, 12.0, false) <
		AiEv.profile_ev(_rprof(), ATT, DEF_PLAIN, 12.0, false)).is_true()


func test_sergeant_attacks_add_expected_bonus_hits() -> void:
	# The stamped bearer share adds share/6 expected hits, which then save normally.
	var base: float = AiEv.profile_ev(_rprof(), ATT, DEF_PLAIN, 12.0, false)
	var with_sgt: float = AiEv.profile_ev(_rprof({"sergeant_attacks": 2}), ATT, DEF_PLAIN, 12.0, false)
	# +2/6 expected hits × 1/2 unsaved = +1/6 expected wounds.
	assert_float(with_sgt).is_equal_approx(base + 2.0 / 6.0 * 0.5, 0.0001)


func test_banner_morale_bonus_relaxes_charge_risk() -> void:
	# Banner's +1 morale shaves 1/6 off the wounds-taken risk weight (advisory, tie-breaks only) —
	# a Banner unit scores a contested charge higher than the same unit without it.
	var our_melee := [_mprof({"attacks": 6})]
	var their_melee := [_mprof({"attacks": 6})]
	var us := {"quality": 4, "models": 5, "defense": 4, "tough": 1}
	var us_banner := {"quality": 4, "models": 5, "defense": 4, "tough": 1, "morale_bonus": 1}
	var them := {"defense": 4, "tough": 1, "models": 5, "quality": 4}
	assert_bool(AiEv.charge_score(our_melee, us_banner, their_melee, them) >
		AiEv.charge_score(our_melee, us, their_melee, them)).is_true()


func test_stamp_sergeant_marks_one_profile_with_the_bearers_share() -> void:
	# A 5-model unit with Sergeant (core rule — active in the default system): the FIRST profile with
	# attacks carries the bearer's per-model share (10 attacks / 5 models = 2); the second stays clean.
	var u := GameUnit.new()
	u.unit_id = "sgt1"
	u.unit_properties = {"player_id": 2, "name": "S", "quality": 4, "defense": 4,
		"special_rules": ["Sergeant"]}
	for i in range(5):
		var m := ModelInstance.new()
		m.is_alive = true
		u.models.append(m)
	var profiles := [_rprof({"attacks": 10}), _rprof({"attacks": 4, "name": "Pistol"})]
	AiEv.stamp_sergeant(profiles, u)
	assert_int(int((profiles[0] as Dictionary).get("sergeant_attacks", 0))).is_equal(2)
	assert_int(int((profiles[1] as Dictionary).get("sergeant_attacks", 0))).is_equal(0)
	# No Sergeant rule → nothing stamped.
	var plain_unit := GameUnit.new()
	plain_unit.unit_id = "sgt2"
	plain_unit.unit_properties = {"player_id": 2, "name": "P", "quality": 4, "defense": 4, "special_rules": []}
	var clean := [_rprof({"attacks": 10})]
	AiEv.stamp_sergeant(clean, plain_unit)
	assert_int(int((clean[0] as Dictionary).get("sergeant_attacks", 0))).is_equal(0)


func test_ctx_for_applies_armor_counts_as_defense() -> void:
	# Armor(4) on a Defense-5 unit: the EV context sees Defense 4 (the same armored_defense the dice
	# path uses — one seam). Without Armor the printed value stays.
	var u := GameUnit.new()
	u.unit_id = "arm1"
	u.unit_properties = {"player_id": 2, "name": "A", "quality": 4, "defense": 5,
		"special_rules": ["Armor(4)", "Tough(3)"]}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	assert_int(int(AiEv.ctx_for(u)["defense"])).is_equal(4)
	var plain := GameUnit.new()
	plain.unit_id = "arm2"
	plain.unit_properties = {"player_id": 2, "name": "B", "quality": 4, "defense": 5, "special_rules": []}
	var m2 := ModelInstance.new()
	m2.is_alive = true
	plain.models.append(m2)
	assert_int(int(AiEv.ctx_for(plain)["defense"])).is_equal(5)
