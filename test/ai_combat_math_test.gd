extends GdUnitTestSuite
## Solo-AI M2: AiCombatMath turns rolled dice FACES into hits / wounds / morale outcomes per OPR core.


func test_count_hits_at_or_above_quality() -> void:
	# Quality 3+ → faces 6 and 3 hit, 2 and 1 miss.
	assert_int(AiCombatMath.count_hits([6, 3, 2, 1], 3)).is_equal(2)


func test_save_target_adds_ap() -> void:
	assert_int(AiCombatMath.save_target(4, 1)).is_equal(5)
	assert_int(AiCombatMath.save_target(4, 0)).is_equal(4)


func test_count_blocks_uses_defense_plus_ap() -> void:
	# Defense 4, AP 1 → save target 5 → only 6 and 5 block.
	assert_int(AiCombatMath.count_blocks([6, 5, 3], 4, 1)).is_equal(2)


func test_wounds_are_hits_minus_blocks() -> void:
	# 3 hits, saves [6,2,1] vs Defense 4 (target 4, no AP) → one block (6) → 2 wounds.
	assert_int(AiCombatMath.wounds(3, [6, 2, 1], 4, 0)).is_equal(2)


func test_wounds_never_negative() -> void:
	assert_int(AiCombatMath.wounds(1, [6, 6, 6], 4, 0)).is_equal(0)


func test_at_or_below_half() -> void:
	assert_bool(AiCombatMath.at_or_below_half(5, 10)).is_true()
	assert_bool(AiCombatMath.at_or_below_half(6, 10)).is_false()
	assert_bool(AiCombatMath.at_or_below_half(0, 0)).is_true()


func test_morale_pass_shaken_rout() -> void:
	# Quality 3+: a 5 passes.
	assert_int(AiCombatMath.morale_result(5, 3, false)).is_equal(AiCombatMath.Morale.PASSED)
	# A 2 fails; above half → Shaken.
	assert_int(AiCombatMath.morale_result(2, 3, false)).is_equal(AiCombatMath.Morale.SHAKEN)
	# A 2 fails; at/below half → Rout.
	assert_int(AiCombatMath.morale_result(2, 3, true)).is_equal(AiCombatMath.Morale.ROUT)


func test_should_test_shooting_morale() -> void:
	# Took casualties (10 -> 4 of 10) and now at/below half → test.
	assert_bool(AiCombatMath.should_test_shooting_morale(10, 4, 10)).is_true()
	# Took casualties but still above half (10 -> 6 of 10) → no test.
	assert_bool(AiCombatMath.should_test_shooting_morale(10, 6, 10)).is_false()
	# No casualties this volley (unchanged) → no test, even at half.
	assert_bool(AiCombatMath.should_test_shooting_morale(5, 5, 10)).is_false()
	# Wiped out (alive_now 0) → gone, not routed via a morale test.
	assert_bool(AiCombatMath.should_test_shooting_morale(3, 0, 10)).is_false()
	# Exactly half after casualties (10 -> 5 of 10) → test.
	assert_bool(AiCombatMath.should_test_shooting_morale(10, 5, 10)).is_true()


func test_success_chance_bounds_and_values() -> void:
	# 2+ → 5/6, 4+ → 3/6, 6+ → 1/6 (a 6 always hits).
	assert_float(AiCombatMath.success_chance(2)).is_equal_approx(5.0 / 6.0, 0.0001)
	assert_float(AiCombatMath.success_chance(4)).is_equal_approx(3.0 / 6.0, 0.0001)
	assert_float(AiCombatMath.success_chance(6)).is_equal_approx(1.0 / 6.0, 0.0001)
	# Clamped: target <= 1 caps at 5/6 (a 1 always fails); target >= 7 floors at 1/6 (a 6 always saves).
	assert_float(AiCombatMath.success_chance(1)).is_equal_approx(5.0 / 6.0, 0.0001)
	assert_float(AiCombatMath.success_chance(9)).is_equal_approx(1.0 / 6.0, 0.0001)


func test_relentless_bonus_hits_only_beyond_9_inches() -> void:
	# Over 9": each unmodified 6 adds a hit.
	assert_int(AiCombatMath.relentless_bonus_hits([6, 6, 3, 1], 12.0)).is_equal(2)
	# At exactly 9" or closer: no bonus (the rule is "over 9").
	assert_int(AiCombatMath.relentless_bonus_hits([6, 6, 3, 1], 9.0)).is_equal(0)
	assert_int(AiCombatMath.relentless_bonus_hits([6, 6, 3, 1], 5.0)).is_equal(0)
	# No 6s → no bonus even at long range.
	assert_int(AiCombatMath.relentless_bonus_hits([5, 4, 3], 24.0)).is_equal(0)


func test_deadly_multiplier_is_tough_capped() -> void:
	# Deadly(3) vs a Tough(3) model → each unsaved wound counts triple.
	assert_int(AiCombatMath.deadly_multiplier(3, 3)).is_equal(3)
	# Deadly(6) vs Tough(3) → capped at the model's Tough (overkill lost).
	assert_int(AiCombatMath.deadly_multiplier(6, 3)).is_equal(3)
	# Deadly(2) vs Tough(3) → the full X (below the cap).
	assert_int(AiCombatMath.deadly_multiplier(2, 3)).is_equal(2)
	# Against a non-Tough unit (Tough 1) Deadly deals only 1 (per the p.10 clarification).
	assert_int(AiCombatMath.deadly_multiplier(3, 1)).is_equal(1)


func test_deadly_wounds_dealt_has_no_carry_over() -> void:
	# THE bug the pooled multiplier hid (GF v3.5.1 p.14 "no carry-over"): Deadly(2), 2 unsaved, on
	# Tough(3) models — each wound ×2 on its OWN model, both survive (2 < 3). The pool combined 4 and
	# spilled to kill one; per-model spread kills NONE.
	assert_int(AiCombatMath.deadly_wounds_dealt(2, 2, [3, 3, 3])).is_equal(4)   # 2+2, both alive
	var toughs := [3, 3, 3]
	AiCombatMath.deadly_wounds_dealt(2, 2, toughs)
	assert_array(toughs).contains_exactly([1, 1, 3])   # two models at 1 wound, none removed
	# Deadly(6), 1 unsaved, Tough(2): kills one model, 4 excess LOST (no carry-over).
	var t2 := [2, 2, 2]
	assert_int(AiCombatMath.deadly_wounds_dealt(1, 6, t2)).is_equal(2)
	assert_array(t2).contains_exactly([0, 2, 2])   # only ONE model removed
	# 4 unsaved of Deadly(2) on Tough(3)×3: spread fills each to 1 wound left, the 4th finishes one → 1 kill.
	var t3 := [3, 3, 3]
	AiCombatMath.deadly_wounds_dealt(4, 2, t3)
	assert_int(t3.count(0)).is_equal(1)   # exactly one model removed (defender-optimal spread)


func test_unmodified_sixes_counts_natural_sixes() -> void:
	assert_int(AiCombatMath.unmodified_sixes([6, 6, 5, 1, 6])).is_equal(3)
	assert_int(AiCombatMath.unmodified_sixes([5, 4, 3])).is_equal(0)


func test_surge_adds_a_hit_per_six_at_any_range() -> void:
	# Surge (GF/AoF v3.5.1 p.14): +1 hit per unmodified 6, with NO range condition (unlike Relentless).
	assert_int(AiCombatMath.surge_bonus_hits([6, 6, 3, 1])).is_equal(2)
	assert_int(AiCombatMath.surge_bonus_hits([5, 4, 2])).is_equal(0)


func test_furious_adds_a_hit_per_six_only_when_charging() -> void:
	# Furious (GF/AoF v3.5.1 p.14): melee, charging only.
	assert_int(AiCombatMath.furious_bonus_hits([6, 6, 2], true)).is_equal(2)
	assert_int(AiCombatMath.furious_bonus_hits([6, 6, 2], false)).is_equal(0)


func test_rending_ap_hits_is_capped_at_total_hits() -> void:
	# Rending (GF/AoF v3.5.1 p.14): one AP(+4) hit per unmodified 6.
	assert_int(AiCombatMath.rending_ap_hits([6, 6, 4, 1], 4)).is_equal(2)
	# Capped at the hits actually scored (a hit-reduction can't create phantom Rending hits).
	assert_int(AiCombatMath.rending_ap_hits([6, 6, 6], 1)).is_equal(1)
	assert_int(AiCombatMath.rending_ap_hits([5, 4, 3], 3)).is_equal(0)


func test_rending_ap_bonus_is_plus_four() -> void:
	assert_int(AiCombatMath.RENDING_AP_BONUS).is_equal(4)


func test_impact_hits_score_on_two_plus() -> void:
	# Impact (GF/AoF v3.5.1 p.13): each of the X charge dice is a hit on 2+.
	assert_int(AiCombatMath.impact_hits([2, 3, 6, 1, 1])).is_equal(3)
	assert_int(AiCombatMath.impact_hits([1, 1, 1])).is_equal(0)


func test_thrust_to_hit_improves_by_one_when_charging() -> void:
	# Thrust (GF/AoF v3.5.1 p.14): +1 to hit on a charge (a lower needed face); unchanged otherwise.
	assert_int(AiCombatMath.thrust_to_hit(4, true)).is_equal(3)
	assert_int(AiCombatMath.thrust_to_hit(4, false)).is_equal(4)
	# Clamped at the 2+ ceiling (a natural 1 always misses).
	assert_int(AiCombatMath.thrust_to_hit(2, true)).is_equal(2)


func test_fearless_recovers_on_four_plus() -> void:
	# Fearless (GF/AoF v3.5.1 p.13): a re-roll of 4+ turns a failed morale test into a pass.
	assert_bool(AiCombatMath.fearless_recovers(4)).is_true()
	assert_bool(AiCombatMath.fearless_recovers(6)).is_true()
	assert_bool(AiCombatMath.fearless_recovers(3)).is_false()
	assert_bool(AiCombatMath.fearless_recovers(1)).is_false()


func test_fear_adjusted_wounds_adds_x_for_the_winner_check() -> void:
	# Fear (GF/AoF v3.5.1 p.13): +X to the who-won-melee tally only.
	assert_int(AiCombatMath.fear_adjusted_wounds(2, 3)).is_equal(5)
	assert_int(AiCombatMath.fear_adjusted_wounds(0, 2)).is_equal(2)
	assert_int(AiCombatMath.fear_adjusted_wounds(4, 0)).is_equal(4)


func test_bane_reroll_count_is_the_defense_sixes() -> void:
	assert_int(AiCombatMath.bane_reroll_count([6, 6, 5, 6])).is_equal(3)
	assert_int(AiCombatMath.bane_reroll_count([5, 4, 3])).is_equal(0)


func test_blocks_with_bane_rerolls_defense_sixes_once() -> void:
	# Bane (GF/AoF v3.5.1 p.13): the defender re-rolls unmodified Defense 6s once. Def 4+, no AP.
	# Saves [6, 6, 3]: without Bane all three would-be blocks are [6,6](block) + 3(fail vs 4) = 2 blocks.
	assert_int(AiCombatMath.count_blocks([6, 6, 3], 4, 0)).is_equal(2)
	# Bane re-rolls the two 6s → [2, 5]: the 2 fails, the 5 blocks; plus the original 3 fails → 1 block.
	assert_int(AiCombatMath.blocks_with_bane([6, 6, 3], [2, 5], 4, 0)).is_equal(1)
	# A re-rolled 6 stays a block ("a die is only re-rolled once"): [6] → reroll [6] → still 1 block.
	assert_int(AiCombatMath.blocks_with_bane([6], [6], 4, 0)).is_equal(1)
	# No 6s → identical to a plain block count (Bane does nothing).
	assert_int(AiCombatMath.blocks_with_bane([5, 3, 2], [], 4, 0)).is_equal(1)


func test_blocks_with_bane_respects_ap_on_the_reroll() -> void:
	# Def 4+, AP 1 → save target 5. Original [6, 6] both block; Bane re-rolls to [4, 5]: 4 fails vs 5+, 5
	# blocks → 1 block. (A natural 6 in a re-roll would still block regardless of AP.)
	assert_int(AiCombatMath.blocks_with_bane([6, 6], [4, 5], 4, 1)).is_equal(1)


func test_expected_wounds() -> void:
	# 6 attacks, hit on 4+ (1/2), target Def 4+ save fails on 1/2 → 6 × 0.5 × 0.5 = 1.5.
	assert_float(AiCombatMath.expected_wounds(6, 4, 4, 0)).is_equal_approx(1.5, 0.0001)
	# AP2 pushes the save to 6+ (through-chance 5/6): 6 × 0.5 × 5/6 = 2.5.
	assert_float(AiCombatMath.expected_wounds(6, 4, 4, 2)).is_equal_approx(2.5, 0.0001)
	# No attacks → no damage.
	assert_float(AiCombatMath.expected_wounds(0, 3, 5, 0)).is_equal_approx(0.0, 0.0001)
	# Higher AP never lowers expected damage (more wounds get through).
	assert_bool(AiCombatMath.expected_wounds(4, 3, 4, 3) >= AiCombatMath.expected_wounds(4, 3, 4, 0)).is_true()


func test_modified_hit_target_applies_roll_modifiers_bounded() -> void:
	# A +1 to-hit roll bonus lowers the needed face; a −1 raises it.
	assert_int(AiCombatMath.modified_hit_target(4, 1)).is_equal(3)
	assert_int(AiCombatMath.modified_hit_target(4, -1)).is_equal(5)
	assert_int(AiCombatMath.modified_hit_target(4, 0)).is_equal(4)
	# Bounded to [2, 6]: a natural 1 always fails, a natural 6 always succeeds (core p.1 "Modifiers").
	assert_int(AiCombatMath.modified_hit_target(2, 3)).is_equal(2)
	assert_int(AiCombatMath.modified_hit_target(5, -2)).is_equal(6)


func test_shooting_hit_modifier_over_nine_inches_rules() -> void:
	# Stealth (p.14): −1 to hit only when shot from OVER 9" (exactly 9" is not over).
	assert_int(AiCombatMath.shooting_hit_modifier(12.0, false, true, false, false)).is_equal(-1)
	assert_int(AiCombatMath.shooting_hit_modifier(9.0, false, true, false, false)).is_equal(0)
	# Artillery target (p.13): −2 to hit from over 9".
	assert_int(AiCombatMath.shooting_hit_modifier(12.0, false, false, true, false)).is_equal(-2)
	assert_int(AiCombatMath.shooting_hit_modifier(6.0, false, false, true, false)).is_equal(0)
	# Artillery shooter (p.13): +1 to hit at over 9".
	assert_int(AiCombatMath.shooting_hit_modifier(12.0, true, false, false, false)).is_equal(1)
	assert_int(AiCombatMath.shooting_hit_modifier(8.0, true, false, false, false)).is_equal(0)


func test_shooting_hit_modifier_evasive_any_range_and_stacking() -> void:
	# Evasive (army-book rule): −1 to hit at ANY range.
	assert_int(AiCombatMath.shooting_hit_modifier(3.0, false, false, false, true)).is_equal(-1)
	assert_int(AiCombatMath.shooting_hit_modifier(20.0, false, false, false, true)).is_equal(-1)
	# Different rules stack (core "Rules Priority & Stacking"): Artillery +1, Stealth −1, Evasive −1 → −1.
	assert_int(AiCombatMath.shooting_hit_modifier(12.0, true, true, false, true)).is_equal(-1)
	# No rules → no modifier.
	assert_int(AiCombatMath.shooting_hit_modifier(12.0, false, false, false, false)).is_equal(0)


func test_melee_hit_modifier_only_evasive_applies() -> void:
	assert_int(AiCombatMath.melee_hit_modifier(true)).is_equal(-1)
	assert_int(AiCombatMath.melee_hit_modifier(false)).is_equal(0)


func test_shielded_defense_improves_the_save_by_one() -> void:
	# Shielded (army-book rule): +1 to Defense rolls = a save target one better.
	assert_int(AiCombatMath.shielded_defense(4, true)).is_equal(3)
	assert_int(AiCombatMath.shielded_defense(4, false)).is_equal(4)
	# Floored at 2+ (a natural 1 always fails).
	assert_int(AiCombatMath.shielded_defense(2, true)).is_equal(2)


func test_impact_total_dice_counter_reduction() -> void:
	# The rulebook example (p.13 Counter): Impact(3), one charging model, one Counter model → 2 rolls.
	assert_int(AiCombatMath.impact_total_dice(3, 1, 1)).is_equal(2)
	# No Counter → X per charging model.
	assert_int(AiCombatMath.impact_total_dice(3, 2, 0)).is_equal(6)
	# The reduction is "-1 TOTAL Impact rolls per model with Counter" and never goes negative.
	assert_int(AiCombatMath.impact_total_dice(1, 1, 5)).is_equal(0)


# === Wave-4 army-book rules (Robot Legions / Battle Brothers / Mummified Undead) ===

func test_battleborn_recovers_on_4plus() -> void:
	# Round-start Shaken recovery (army-book text): 4+ clears Shaken, 1-3 does not.
	assert_bool(AiCombatMath.battleborn_recovers(4)).is_true()
	assert_bool(AiCombatMath.battleborn_recovers(6)).is_true()
	assert_bool(AiCombatMath.battleborn_recovers(3)).is_false()
	assert_bool(AiCombatMath.battleborn_recovers(1)).is_false()
	# Steadfast shares the seam with a registry-tuned target — an explicit target is honoured.
	assert_bool(AiCombatMath.battleborn_recovers(3, 3)).is_true()
	assert_bool(AiCombatMath.battleborn_recovers(4, 5)).is_false()


func test_ravage_wounds_count_6_plus() -> void:
	# Ravage(X): each 6+ is one direct wound (no save); the target is registry-tunable.
	assert_int(AiCombatMath.ravage_wounds([6, 6, 5, 1])).is_equal(2)
	assert_int(AiCombatMath.ravage_wounds([1, 2, 3])).is_equal(0)
	assert_int(AiCombatMath.ravage_wounds([])).is_equal(0)
	assert_int(AiCombatMath.ravage_wounds([5, 6], 5)).is_equal(2)


func test_conditional_ap_range_gates() -> void:
	# Piercing Hunter: AP(+1) only when shooting from over 9" — melee and close shots stay flat;
	# dist -1 (unknown) is conservative.
	var ph := {"ap_bonus": 1, "condition": "ranged_over", "over_in": 9.0}
	assert_int(AiCombatMath.conditional_ap_bonus(ph, 1, 4, false, 12.0, false)).is_equal(1)
	assert_int(AiCombatMath.conditional_ap_bonus(ph, 1, 4, false, 8.0, false)).is_equal(0)
	assert_int(AiCombatMath.conditional_ap_bonus(ph, 1, 4, false, 12.0, true)).is_equal(0)
	assert_int(AiCombatMath.conditional_ap_bonus(ph, 1, 4, false)).is_equal(0)
	# Slayer: AP(+2) vs Tough>=3, but ONLY on an over-9" shot or a charge (the situational gate).
	var sl := {"ap_bonus": 2, "condition": "vs_tough_ge", "threshold": 3, "gate": "ranged_over_or_charge", "over_in": 9.0}
	assert_int(AiCombatMath.conditional_ap_bonus(sl, 3, 4, false, 12.0, false)).is_equal(2)
	assert_int(AiCombatMath.conditional_ap_bonus(sl, 3, 4, true, -1.0, true)).is_equal(2)
	assert_int(AiCombatMath.conditional_ap_bonus(sl, 3, 4, false, 8.0, false)).is_equal(0)
	assert_int(AiCombatMath.conditional_ap_bonus(sl, 1, 4, false, 12.0, false)).is_equal(0)


func test_shrouded_reach_penalty_and_floor() -> void:
	# Ranged Shrouding: -6" to a min of 6" — 24" -> 18", 9" -> 6" (floored), and a reach already at or
	# below the floor is untouched (the rule shortens, it never lengthens a 6"-or-less weapon).
	assert_float(AiCombatMath.shrouded_reach(24.0, 6.0, 6.0)).is_equal_approx(18.0, 0.001)
	assert_float(AiCombatMath.shrouded_reach(9.0, 6.0, 6.0)).is_equal_approx(6.0, 0.001)
	assert_float(AiCombatMath.shrouded_reach(6.0, 6.0, 6.0)).is_equal_approx(6.0, 0.001)
	assert_float(AiCombatMath.shrouded_reach(4.0, 6.0, 6.0)).is_equal_approx(4.0, 0.001)
	# Melee Shrouding: -3" to a min of 6" — 12" charge -> 9", 8" -> 6" (floored).
	assert_float(AiCombatMath.shrouded_reach(12.0, 3.0, 6.0)).is_equal_approx(9.0, 0.001)
	assert_float(AiCombatMath.shrouded_reach(8.0, 3.0, 6.0)).is_equal_approx(6.0, 0.001)


func test_guarded_defense_bonus_and_floor() -> void:
	# Guarded (+1 to defense rolls when shot/charged from over 9"): one better when the gate applies,
	# floored at 2+ like every defense modifier; passthrough when it does not.
	assert_int(AiCombatMath.guarded_defense(4, true)).is_equal(3)
	assert_int(AiCombatMath.guarded_defense(2, true)).is_equal(2)
	assert_int(AiCombatMath.guarded_defense(4, false)).is_equal(4)


func test_no_retreat_wounds_count_1_to_3() -> void:
	# No Retreat (official text): one self-wound per die at 1-3; 4+ is safe.
	assert_int(AiCombatMath.no_retreat_wounds([1, 2, 3, 4, 5, 6])).is_equal(3)
	assert_int(AiCombatMath.no_retreat_wounds([4, 5, 6])).is_equal(0)
	assert_int(AiCombatMath.no_retreat_wounds([])).is_equal(0)
	# The ceiling is registry-tunable (an errata that shifts the band stays a data change).
	assert_int(AiCombatMath.no_retreat_wounds([1, 2, 3, 4], 2)).is_equal(2)


func test_unpredictable_fighter_effect_split() -> void:
	# 1-3 → AP(+1); 4-6 → +1 to hit (exactly one facet each).
	for f in [1, 2, 3]:
		var lo := AiCombatMath.unpredictable_fighter_effect(f)
		assert_int(int(lo["ap"])).is_equal(1)
		assert_int(int(lo["hit"])).is_equal(0)
	for f in [4, 5, 6]:
		var hi := AiCombatMath.unpredictable_fighter_effect(f)
		assert_int(int(hi["ap"])).is_equal(0)
		assert_int(int(hi["hit"])).is_equal(1)


## Field-test finding 8: a unit that is ALREADY Shaken auto-fails any further morale test (GF/AoF v3.5.1
## p.10) — no roll. At half or less that fail is a Rout; above half it stays Shaken.
func test_morale_result_shaken_auto_fails() -> void:
	assert_int(AiCombatMath.morale_result_shaken(true)).is_equal(AiCombatMath.Morale.ROUT)
	assert_int(AiCombatMath.morale_result_shaken(false)).is_equal(AiCombatMath.Morale.SHAKEN)


## Field-test finding 9: Reliable (GF/AoF v3.5.1 p.14, "shoots at Quality 2+") must set the base Quality on
## the MELEE strike path exactly as it does when shooting — a Reliable strike hits on 2+, and the roll can
## still be modified on top (Thrust on a charge). Pins the composition the strike phase now uses.
func test_reliable_sets_melee_to_hit_to_two_plus() -> void:
	# A Quality-5 model with a Reliable melee weapon strikes at 2+ (not 5+).
	var q_reliable := AiCombatMath.reliable_quality(5, true)
	assert_int(AiCombatMath.modified_hit_target(AiCombatMath.thrust_to_hit(q_reliable, false), 0)).is_equal(2)
	# Without Reliable the same weapon still needs 5+.
	var q_plain := AiCombatMath.reliable_quality(5, false)
	assert_int(AiCombatMath.modified_hit_target(AiCombatMath.thrust_to_hit(q_plain, false), 0)).is_equal(5)


# === Wave-5 primitives (registry-derived params; semantics verified against the official rulebook PDFs) ===

func test_shred_counts_unmodified_save_ones() -> void:
	# Shred (army-book weapon rule, same text in all five systems): each unmodified Defense roll of 1
	# deals 1 extra wound.
	assert_int(AiCombatMath.shred_bonus_wounds([1, 3, 1, 6])).is_equal(2)
	assert_int(AiCombatMath.shred_bonus_wounds([2, 3, 4])).is_equal(0)
	assert_int(AiCombatMath.shred_bonus_wounds([])).is_equal(0)


func test_shred_reads_the_final_faces_after_bane_rerolls() -> void:
	# With Bane, a Defense 6 is re-rolled once: a re-roll of 1 shreds; a re-rolled 6 stays a block
	# (and is NOT a 1). Original 1s always count.
	assert_int(AiCombatMath.shred_bonus_wounds([6, 1], [1])).is_equal(2)   # 6→1 re-roll + original 1
	assert_int(AiCombatMath.shred_bonus_wounds([6], [6])).is_equal(0)      # re-rolled 6 blocks, no shred
	assert_int(AiCombatMath.shred_bonus_wounds([6, 6], [1, 4])).is_equal(1)


func test_sergeant_bonus_hits_capped_at_the_bearers_attacks() -> void:
	# Sergeant (core v3.5.1, MODEL-level): the bearer's unmodified 6s deal +1 hit — the pooled volley
	# caps the bonus at the bearer's own attack count (documented approximation).
	assert_int(AiCombatMath.sergeant_bonus_hits([6, 6, 6, 2], 1)).is_equal(1)
	assert_int(AiCombatMath.sergeant_bonus_hits([6, 6, 3], 2)).is_equal(2)
	assert_int(AiCombatMath.sergeant_bonus_hits([5, 4], 2)).is_equal(0)
	assert_int(AiCombatMath.sergeant_bonus_hits([6], 0)).is_equal(0)


func test_armored_defense_counts_as_best_of() -> void:
	# Armor(X) (army-book upgrade: "counts as having Defense X+") — best-of: it improves a worse
	# printed Defense and never degrades a better one; 0/invalid ratings change nothing.
	assert_int(AiCombatMath.armored_defense(5, 4)).is_equal(4)
	assert_int(AiCombatMath.armored_defense(3, 4)).is_equal(3)
	assert_int(AiCombatMath.armored_defense(5, 2)).is_equal(2)
	assert_int(AiCombatMath.armored_defense(5, 0)).is_equal(5)
	assert_int(AiCombatMath.armored_defense(5, 1)).is_equal(5)


func test_morale_target_applies_banner_bonus_clamped() -> void:
	# Banner: +1 to morale test rolls = the roll target drops by one, bounded to [2,6] (a natural 1
	# always fails — core p.1 "Modifiers"). NML-006: NEGATIVE mods count too ("-1 to morale test
	# rolls" raises the target) — the old floor-at-0 silently dropped spell debuffs.
	assert_int(AiCombatMath.morale_target(4, 1)).is_equal(3)
	assert_int(AiCombatMath.morale_target(2, 1)).is_equal(2)
	assert_int(AiCombatMath.morale_target(4, 0)).is_equal(4)
	assert_int(AiCombatMath.morale_target(4, -1)).is_equal(5)   # spell debuff (Mind Shaper)
	assert_int(AiCombatMath.morale_target(6, -3)).is_equal(6)   # clamp: a 6 still always passes


func test_indirect_hit_modifier_only_after_moving() -> void:
	# Indirect (core v3.5.1): "-1 to hit rolls when shooting after moving" — nothing on a Hold.
	assert_int(AiCombatMath.indirect_hit_modifier(true)).is_equal(-1)
	assert_int(AiCombatMath.indirect_hit_modifier(false)).is_equal(0)
	assert_int(AiCombatMath.indirect_hit_modifier(true, 2)).is_equal(-2)


func test_conditional_ap_bonus_target_property_rules() -> void:
	# The generic target-property AP rules, driven entirely by registry params (wave-5 "primitive
	# families first"): Shatter/Tear (vs Tough), Melee Slayer (vs Tough + charge only), Disintegrate
	# (vs good armour). tough / defense are the target's; is_charging the bearer's.
	var shatter := {"ap_bonus": 2, "condition": "vs_tough_ge", "threshold": 3}
	assert_int(AiCombatMath.conditional_ap_bonus(shatter, 3, 4, false)).is_equal(2)   # Tough(3) -> +2
	assert_int(AiCombatMath.conditional_ap_bonus(shatter, 2, 4, false)).is_equal(0)   # Tough(2) -> none
	var tear := {"ap_bonus": 4, "condition": "vs_tough_ge", "threshold": 9}
	assert_int(AiCombatMath.conditional_ap_bonus(tear, 9, 2, false)).is_equal(4)      # Tough(9) -> +4
	assert_int(AiCombatMath.conditional_ap_bonus(tear, 6, 2, false)).is_equal(0)      # Tough(6) -> none
	# Melee Slayer: same Tough(3) gate BUT only while charging.
	var slayer := {"ap_bonus": 2, "condition": "vs_tough_ge", "threshold": 3, "charge_only": true}
	assert_int(AiCombatMath.conditional_ap_bonus(slayer, 3, 4, true)).is_equal(2)     # charging -> +2
	assert_int(AiCombatMath.conditional_ap_bonus(slayer, 3, 4, false)).is_equal(0)    # not charging -> none
	# Disintegrate: vs well-armoured targets (save value <= 3 is better armour).
	var disint := {"ap_bonus": 2, "condition": "vs_armor", "threshold": 3}
	assert_int(AiCombatMath.conditional_ap_bonus(disint, 1, 3, false)).is_equal(2)    # Defense 3+ -> +2
	assert_int(AiCombatMath.conditional_ap_bonus(disint, 1, 4, false)).is_equal(0)    # Defense 4+ -> none
	# Piercing Assault: AP(+1) purely while charging, no target property.
	var pierce := {"ap_bonus": 1, "condition": "on_charge"}
	assert_int(AiCombatMath.conditional_ap_bonus(pierce, 1, 5, true)).is_equal(1)     # charging -> +1
	assert_int(AiCombatMath.conditional_ap_bonus(pierce, 9, 2, false)).is_equal(0)    # not charging -> none
	# No params / no bonus -> inert (the byte-identical fallback when the map is absent).
	assert_int(AiCombatMath.conditional_ap_bonus({}, 9, 2, true)).is_equal(0)


func test_melee_hit_modifier_evasive_or_melee_evasion() -> void:
	# Both Evasive (any range) and the melee-only Melee Evasion cost a melee attacker -1 to hit; they do
	# not stack with each other, and neither -> 0.
	assert_int(AiCombatMath.melee_hit_modifier(true, false)).is_equal(-1)   # Evasive
	assert_int(AiCombatMath.melee_hit_modifier(false, true)).is_equal(-1)   # Melee Evasion
	assert_int(AiCombatMath.melee_hit_modifier(true, true)).is_equal(-1)    # no stacking
	assert_int(AiCombatMath.melee_hit_modifier(false, false)).is_equal(0)   # neither


func test_fortified_ap_reduces_incoming_ap_min_zero() -> void:
	# Fortified: incoming hits count as AP(-1), floored at AP(0); no effect when the defender lacks it.
	assert_int(AiCombatMath.fortified_ap(2, true)).is_equal(1)
	assert_int(AiCombatMath.fortified_ap(1, true)).is_equal(0)
	assert_int(AiCombatMath.fortified_ap(0, true)).is_equal(0)   # min 0
	assert_int(AiCombatMath.fortified_ap(3, false)).is_equal(3)  # not fortified -> unchanged
