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


func test_conditional_ap_raises_ev_only_against_qualifying_targets() -> void:
	# Shatter (AP+2 vs Tough(3)+), stamped as cond_ap: it must raise the EV against a Tough(3) target
	# but do nothing against a Tough(1) target — the target-property gate, valued exactly the way the
	# dice resolution (main._solo_conditional_ap) applies it.
	var shatter := {"ap_bonus": 2, "condition": "vs_tough_ge", "threshold": 3}
	var plain := _rprof()
	var armed := _rprof({"cond_ap": [shatter]})
	var tough_def := {"defense": 3, "tough": 3, "models": 5}
	var soft_def := {"defense": 3, "tough": 1, "models": 5}
	assert_bool(AiEv.profile_ev(armed, ATT, tough_def, 12.0, false)
		> AiEv.profile_ev(plain, ATT, tough_def, 12.0, false)).is_true()
	assert_float(AiEv.profile_ev(armed, ATT, soft_def, 12.0, false)) \
		.is_equal_approx(AiEv.profile_ev(plain, ATT, soft_def, 12.0, false), 0.0001)


func test_stamp_conditional_ap_marks_profiles_from_the_book() -> void:
	# stamp_conditional_ap reads the striker's book (system+faction) and marks each profile whose weapon
	# carries a conditional-AP rule; others are left untouched.
	var u := GameUnit.new()
	u.unit_properties = {"player_id": 2, "name": "T", "game_system": "gf",
		"faction_folder": "blood_prime_brothers", "special_rules": []}
	var mi := ModelInstance.new(); mi.is_alive = true; u.models.append(mi)
	var profs := [_mprof({"rules": ["Shatter"]}), _mprof({"rules": []})]
	AiEv.stamp_conditional_ap(profs, u)
	assert_bool((profs[0] as Dictionary).has("cond_ap")).is_true()
	assert_int(int(((profs[0]["cond_ap"] as Array)[0] as Dictionary).get("ap_bonus", 0))).is_equal(2)
	assert_bool((profs[1] as Dictionary).has("cond_ap")).is_false()


func test_crack_on6_ap_raises_ev() -> void:
	# Crack (AP(+2) on unmodified 6s), stamped as on6_ap: the expected six-hits save at the worse AP, so
	# EV rises over a plain weapon. Rending's fixed +4 fallback is covered by the existing rending test.
	var plain := _rprof()
	var crack := _rprof({"on6_ap": 2})
	assert_bool(AiEv.profile_ev(crack, ATT, DEF_PLAIN, 12.0, false)
		> AiEv.profile_ev(plain, ATT, DEF_PLAIN, 12.0, false)).is_true()


func test_precise_raises_ev() -> void:
	# Precise: +1 to hit (any range) raises expected hits and thus EV over a plain weapon.
	var plain := _rprof()
	var precise := _rprof({"precise": true})
	assert_bool(AiEv.profile_ev(precise, ATT, DEF_PLAIN, 12.0, false)
		> AiEv.profile_ev(plain, ATT, DEF_PLAIN, 12.0, false)).is_true()


func test_aura_granted_rules_extracts_base_keeping_qualifier() -> void:
	# "X Aura" = "this model and its unit get X": the granted base keeps any qualifier and only drops the
	# " Aura" suffix; non-aura rules are ignored. (Import-time expander input.)
	var hero := GameUnit.new()
	hero.unit_properties = {"player_id": 1, "name": "H",
		"special_rules": ["Furious Aura", "Bane in Melee Aura", "Hero"]}
	var body := GameUnit.new()
	body.unit_properties = {"player_id": 1, "name": "U", "special_rules": ["Tough(3)"]}
	var granted := AiEv.aura_granted_rules([body, hero])
	assert_bool(granted.has("Furious")).is_true()
	assert_bool(granted.has("Bane in Melee")).is_true()
	assert_bool(granted.has("Hero")).is_false()   # not an aura
	assert_int(granted.size()).is_equal(2)


func test_fortified_defender_lowers_ev_against_ap() -> void:
	# Fortified: incoming AP counts as -1 (min 0), so a Fortified defender takes fewer unsaved wounds from
	# an AP weapon -> strictly lower EV than the same defender without it.
	var ap_weapon := _rprof({"ap": 2})
	var plain_def := {"defense": 4, "tough": 1, "models": 5}
	var fort_def := {"defense": 4, "tough": 1, "models": 5, "fortified": true}
	assert_bool(AiEv.profile_ev(ap_weapon, ATT, fort_def, 12.0, false)
		< AiEv.profile_ev(ap_weapon, ATT, plain_def, 12.0, false)).is_true()


func test_guarded_defender_lowers_shooting_ev_only_over_9() -> void:
	# Guarded: "+1 to defense rolls when shot ... from over 9\" away" — the EV drops at long range,
	# stays untouched inside 9", and the melee side is NOT valued here (melee EV runs at dist 0;
	# the dice resolution carries the charged-from-over-9 facet).
	var rifle := _rprof()
	var plain_def := {"defense": 4, "tough": 1, "models": 5}
	var guard_def := {"defense": 4, "tough": 1, "models": 5, "guarded": true}
	assert_bool(AiEv.profile_ev(rifle, ATT, guard_def, 12.0, false)
		< AiEv.profile_ev(rifle, ATT, plain_def, 12.0, false)).is_true()
	assert_float(AiEv.profile_ev(rifle, ATT, guard_def, 6.0, false)) \
		.is_equal_approx(AiEv.profile_ev(rifle, ATT, plain_def, 6.0, false), 0.0001)
	var sword := _mprof()
	assert_float(AiEv.profile_ev(sword, ATT, guard_def, 0.0, true)) \
		.is_equal_approx(AiEv.profile_ev(sword, ATT, plain_def, 0.0, true), 0.0001)


func test_ranged_shrouding_defender_gates_shoot_ev_range() -> void:
	# Ranged Shrouding on the DEFENDER: each profile's working range shrinks -6" (min 6") before the
	# in-range gate. A 24" rifle at 20": gated out vs a shrouded target (18" < 20"), counted at 16";
	# a 6" pistol at 5" still counts (at/below the floor = untouched).
	var rifle := _rprof()
	var plain_def := {"defense": 4, "tough": 1, "models": 5}
	var shroud_def := {"defense": 4, "tough": 1, "models": 5, "ranged_shrouding": true}
	assert_float(AiEv.shoot_ev([rifle], ATT, shroud_def, 20.0)).is_equal_approx(0.0, 0.0001)
	assert_bool(AiEv.shoot_ev([rifle], ATT, plain_def, 20.0) > 0.0).is_true()
	assert_bool(AiEv.shoot_ev([rifle], ATT, shroud_def, 16.0) > 0.0).is_true()
	var pistol := _rprof({"range": 6})
	assert_bool(AiEv.shoot_ev([pistol], ATT, shroud_def, 5.0) > 0.0).is_true()


func test_ravage_raises_melee_ev_and_regen_thins_it() -> void:
	# Ravage(2) on a 3-model unit = 6 dice x 1/6 = ~1 expected direct wound on every melee turn
	# (charging or not); the defender's Regeneration thins it (5+ ignores a third).
	var att_rv := {"quality": 4, "models": 3, "ravage": 2}
	var plain_def := {"defense": 4, "tough": 1, "models": 5}
	var sword := _mprof()
	var with_rv := AiEv.melee_ev([sword], att_rv, plain_def, false)
	var without := AiEv.melee_ev([sword], {"quality": 4, "models": 3}, plain_def, false)
	assert_float(with_rv - without).is_equal_approx(1.0, 0.01)
	var regen_def := {"defense": 4, "tough": 1, "models": 5, "regeneration": true, "regen_target": 5}
	var rv_vs_regen := AiEv.melee_ev([sword], att_rv, regen_def, false) - AiEv.melee_ev([sword], {"quality": 4, "models": 3}, regen_def, false)
	assert_bool(rv_vs_regen < 1.0 - 0.2).is_true()


func test_versatile_defense_projects_the_guarded_ev_flag() -> void:
	# Versatile Defense's consistently-played def-half rides the SAME "guarded" EV flag as Guarded —
	# ctx_for sets it for either rule (one flag, one dice-path arithmetic).
	var u := GameUnit.new()
	u.unit_properties = {"player_id": 2, "name": "U", "quality": 4, "defense": 4,
		"special_rules": ["Versatile Defense"]}
	var mi := ModelInstance.new(); mi.is_alive = true; u.models.append(mi)
	assert_bool(bool(AiEv.ctx_for(u).get("guarded", false))).is_true()
	var plain := GameUnit.new()
	plain.unit_properties = {"player_id": 2, "name": "P", "quality": 4, "defense": 4, "special_rules": []}
	var mp := ModelInstance.new(); mp.is_alive = true; plain.models.append(mp)
	assert_bool(bool(AiEv.ctx_for(plain).get("guarded", false))).is_false()


func test_heavy_impact_adds_an_ap1_pool_and_counter_strips_it_first() -> void:
	# Heavy Impact(1) on 2 models = 2 extra dice saving at AP(1): the charge EV rises above the plain
	# Impact-only attacker, and 2 Counter models strip exactly the heavy pool (defender-optimal).
	var plain_def := {"defense": 4, "tough": 1, "models": 5}
	var att_imp := {"quality": 4, "models": 2, "impact": 1}
	var att_both := {"quality": 4, "models": 2, "impact": 1, "heavy_impact": 1}
	assert_bool(AiEv.impact_ev(att_both, plain_def) > AiEv.impact_ev(att_imp, plain_def)).is_true()
	var counter_def := {"defense": 4, "tough": 1, "models": 5, "counter_models": 2}
	assert_float(AiEv.impact_ev(att_both, counter_def)) 		.is_equal_approx(AiEv.impact_ev(att_imp, plain_def), 0.0001)   # heavy pool fully stripped


func test_has_exact_rule_rejects_prefix_match() -> void:
	# has_special_rule matches by PREFIX — the exact reader must not: an "Unpredictable Fighter" unit
	# does NOT carry the generic "Unpredictable" (and ratings are stripped: "Impact(3)" carries Impact).
	var u := GameUnit.new()
	u.unit_properties = {"player_id": 2, "name": "U", "quality": 4,
		"special_rules": ["Unpredictable Fighter", "Impact(3)"]}
	assert_bool(AiEv.has_exact_rule(u, "Unpredictable Fighter")).is_true()
	assert_bool(AiEv.has_exact_rule(u, "Unpredictable")).is_false()
	assert_bool(AiEv.has_exact_rule(u, "Impact")).is_true()
	assert_bool(AiEv.has_exact_rule(null, "Impact")).is_false()


func test_ferocious_stamps_surge_onto_every_profile() -> void:
	# Ferocious (unit rule) = every weapon the unit uses gets Surge; stamp_sergeant sets the surge facet
	# on all profiles. Exact match: "Ferocious Boost" (a different rule) must NOT trigger it.
	var u := GameUnit.new()
	u.unit_properties = {"player_id": 2, "name": "U", "quality": 4, "special_rules": ["Ferocious", "Tough(3)"]}
	var mi := ModelInstance.new(); mi.is_alive = true; u.models.append(mi)
	var profs := [_rprof(), _mprof()]
	AiEv.stamp_sergeant(profs, u)
	assert_bool(bool((profs[0] as Dictionary).get("surge", false))).is_true()
	assert_bool(bool((profs[1] as Dictionary).get("surge", false))).is_true()
	var u2 := GameUnit.new()
	u2.unit_properties = {"player_id": 2, "name": "U2", "quality": 4, "special_rules": ["Ferocious Boost"]}
	var mi2 := ModelInstance.new(); mi2.is_alive = true; u2.models.append(mi2)
	var profs2 := [_rprof()]
	AiEv.stamp_sergeant(profs2, u2)
	assert_bool(bool((profs2[0] as Dictionary).get("surge", false))).is_false()
