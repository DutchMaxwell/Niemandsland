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
