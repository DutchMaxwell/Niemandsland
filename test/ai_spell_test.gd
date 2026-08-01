extends GdUnitTestSuite
## Solo-AI wave 6 — AiSpell: the three pure spellcasting primitives (P1 cast_success_chance, P2
## spell_damage_ev, P3 spell_modifier_delta), the facet parser, the official Solo v3.5.0 D3+X pick
## cycle and the deterministic boost/interference token economy. All headless, no dice, no state.

const EPS := 0.0001


# === P1 — cast probability (v3.5.1: 4+, +1 per friendly token, -1 per enemy token, [2,6] clamp) ===

func test_cast_success_chance_base_and_boost_and_interference() -> void:
	assert_float(AiSpell.cast_success_chance(0, 0)).is_equal_approx(0.5, EPS)          # 4+
	assert_float(AiSpell.cast_success_chance(1, 0)).is_equal_approx(4.0 / 6.0, EPS)    # 3+
	assert_float(AiSpell.cast_success_chance(2, 0)).is_equal_approx(5.0 / 6.0, EPS)    # 2+
	assert_float(AiSpell.cast_success_chance(0, 1)).is_equal_approx(2.0 / 6.0, EPS)    # 5+
	assert_float(AiSpell.cast_success_chance(0, 2)).is_equal_approx(1.0 / 6.0, EPS)    # 6+
	assert_float(AiSpell.cast_success_chance(1, 1)).is_equal_approx(0.5, EPS)          # cancel out


func test_cast_target_clamps_to_two_and_six() -> void:
	# A natural 1 always fails and a 6 always succeeds — no token pile changes that.
	assert_int(AiSpell.cast_target(5, 0)).is_equal(2)
	assert_int(AiSpell.cast_target(0, 9)).is_equal(6)
	assert_float(AiSpell.cast_success_chance(9, 0)).is_equal_approx(5.0 / 6.0, EPS)
	assert_float(AiSpell.cast_success_chance(0, 9)).is_equal_approx(1.0 / 6.0, EPS)


# === Facet parsing (the committed weapon-rule tokens) ===

func test_spell_facets_parse_rated_and_flag_rules() -> void:
	var f := AiSpell.spell_facets(["AP(2)", "Blast(3)", "Deadly(3)", "Bane", "Shred"])
	assert_int(int(f["ap"])).is_equal(2)
	assert_int(int(f["blast"])).is_equal(3)
	assert_int(int(f["deadly"])).is_equal(3)
	assert_bool(bool(f["bane"])).is_true()
	assert_bool(bool(f["shred"])).is_true()
	assert_bool(bool(f["ignores_regen"])).is_true()   # Bane bypasses Regeneration


func test_spell_facets_on_six_and_conditional_ap() -> void:
	var crack := AiSpell.spell_facets(["Crack"])
	assert_int(int(crack["on6_ap"])).is_equal(2)
	var destructive := AiSpell.spell_facets(["Destructive"])
	assert_int(int(destructive["on6_ap"])).is_equal(4)
	# Lacerate = the AoF Bane sibling (re-roll Defense 6s + Regeneration bypass).
	var lacerate := AiSpell.spell_facets(["Lacerate"])
	assert_bool(bool(lacerate["bane"])).is_true()
	assert_bool(bool(lacerate["ignores_regen"])).is_true()
	# Conditional AP resolves against the CONCRETE defender.
	var shatter := AiSpell.spell_facets(["Shatter"])
	assert_int(AiSpell.effective_ap(shatter, {"defense": 4, "tough": 3})).is_equal(2)
	assert_int(AiSpell.effective_ap(shatter, {"defense": 4, "tough": 1})).is_equal(0)
	var tear := AiSpell.spell_facets(["Tear"])
	assert_int(AiSpell.effective_ap(tear, {"defense": 4, "tough": 9})).is_equal(4)
	assert_int(AiSpell.effective_ap(tear, {"defense": 4, "tough": 3})).is_equal(0)
	var disintegrate := AiSpell.spell_facets(["Disintegrate"])
	assert_int(AiSpell.effective_ap(disintegrate, {"defense": 3, "tough": 1})).is_equal(2)
	assert_int(AiSpell.effective_ap(disintegrate, {"defense": 4, "tough": 1})).is_equal(0)
	assert_bool(bool(disintegrate["ignores_regen"])).is_true()
	# Unknown facets are a conservative no-op, never a crash.
	var unknown := AiSpell.spell_facets(["Totally Unknown Rule(7)"])
	assert_int(int(unknown["ap"])).is_equal(0)


# === P2 — damage-spell EV (fixed hits; NO to-hit; NO Shielded; NO Cover) ===

func test_spell_damage_ev_given_hits_no_to_hit_roll() -> void:
	# 4 hits vs Defense 4+ (blocks 1/2): expected 2 wounds — NO attacks × P(hit) step.
	assert_float(AiSpell.spell_damage_ev(4, {"defense": 4, "models": 5})).is_equal_approx(2.0, EPS)
	assert_float(AiSpell.spell_damage_ev(0, {"defense": 4})).is_equal(0.0)


func test_spell_damage_ev_ignores_shielded_and_cover() -> void:
	# THE wave-6 rule gate: Shielded reads "+1 to defense rolls against hits that are NOT from
	# spells" and Cover applies "against shooting" — a spell-hit context with shielded/in_cover set
	# must price EXACTLY like one without (both flags dead against spells).
	var plain := {"defense": 4, "models": 5}
	var protected := {"defense": 4, "models": 5, "shielded": true, "in_cover": true}
	assert_float(AiSpell.spell_damage_ev(4, protected)).is_equal_approx(
		AiSpell.spell_damage_ev(4, plain), EPS)
	# The same hits as SHOOTING would price the flags in (proof the exclusion is spell-specific):
	# one 4-attack Q2+... — profile_ev with shielded true lowers the EV below the plain case.
	var profile := {"attacks": 4, "range": 12, "ap": 0}
	var att := {"quality": 2}
	var shot_plain := AiEv.profile_ev(profile, att, plain, 5.0, false)
	var shot_protected := AiEv.profile_ev(profile, att, protected, 5.0, false)
	assert_bool(shot_protected < shot_plain).is_true()


func test_spell_damage_ev_blast_multiplies_capped_at_models() -> void:
	# 1 hit with Blast(3): ×3 vs 5 models, ×2 vs 2 models (min(X, models) — GF v3.5.1).
	var f := AiSpell.spell_facets(["Blast(3)"])
	assert_float(AiSpell.spell_damage_ev(1, {"defense": 4, "models": 5}, f)).is_equal_approx(1.5, EPS)
	assert_float(AiSpell.spell_damage_ev(1, {"defense": 4, "models": 2}, f)).is_equal_approx(1.0, EPS)


func test_spell_damage_ev_ap_deadly_and_regeneration() -> void:
	# AP(2): Defense 4+ saves on 6 only → 5/6 through.
	var ap2 := AiSpell.spell_facets(["AP(2)"])
	assert_float(AiSpell.spell_damage_ev(6, {"defense": 4, "models": 5}, ap2)).is_equal_approx(5.0, EPS)
	# Deadly(3) vs Tough(3): ×3; vs Tough 1: cap ×1.
	var d3 := AiSpell.spell_facets(["Deadly(3)"])
	assert_float(AiSpell.spell_damage_ev(2, {"defense": 4, "tough": 3}, d3)).is_equal_approx(3.0, EPS)
	assert_float(AiSpell.spell_damage_ev(2, {"defense": 4, "tough": 1}, d3)).is_equal_approx(1.0, EPS)
	# Regeneration 5+ ignores 1/3... a plain spell is reduced ×(1/3? no: 1 − P(5+) = 2/3)…
	var regen := {"defense": 4, "regeneration": true, "regen_target": 5}
	assert_float(AiSpell.spell_damage_ev(6, regen)).is_equal_approx(3.0 * (2.0 / 3.0), EPS)
	# …but Bane wounds bypass it entirely (and re-roll the Defense 6s).
	var bane := AiSpell.spell_facets(["Bane"])
	var p_block_bane := (2.0 / 6.0) + (1.0 / 6.0) * 0.5   # P(4,5) + P(6) × P(re-roll blocks)
	assert_float(AiSpell.spell_damage_ev(6, regen, bane)).is_equal_approx(6.0 * (1.0 - p_block_bane), EPS)


func test_spell_damage_ev_surge_and_on_six_ap() -> void:
	# Surge: +hits/6 expected extra hits. 6 hits vs Def 4+ → (6+1)×0.5.
	var surge := AiSpell.spell_facets(["Surge"])
	assert_float(AiSpell.spell_damage_ev(6, {"defense": 4}, surge)).is_equal_approx(3.5, EPS)
	# Crack: hits/6 of the volley saves at AP(+2). 6 hits vs Def 4+: 5 at 1/2 + 1 at 5/6.
	var crack := AiSpell.spell_facets(["Crack"])
	assert_float(AiSpell.spell_damage_ev(6, {"defense": 4}, crack)).is_equal_approx(5.0 * 0.5 + 1.0 * (5.0 / 6.0), EPS)
	# Shred: +1 wound per Defense 1 → +hits/6 on top.
	var shred := AiSpell.spell_facets(["Shred"])
	assert_float(AiSpell.spell_damage_ev(6, {"defense": 4}, shred)).is_equal_approx(3.0 + 1.0, EPS)


# === P3 — buff/debuff EV delta ===

func _profiles() -> Array:
	return [{"attacks": 6, "range": 0, "ap": 0}]


func test_spell_modifier_delta_hit_mod_sign_and_magnitude() -> void:
	# +1 to hit on a Q4+ melee swing vs Def 4+: P(hit) 0.5 → 2/3; EV 6×0.5×0.5 → 6×2/3×0.5.
	var att := {"quality": 4}
	var def_ctx := {"defense": 4}
	var delta := AiSpell.spell_modifier_delta(_profiles(), att, def_ctx,
		{"modifier": {"hit_mod": 1}}, false, 0.0, false)
	assert_float(delta).is_equal_approx(6.0 * (4.0 / 6.0) * 0.5 - 6.0 * 0.5 * 0.5, EPS)
	# -1 to hit (a debuff on the attacker) is the mirrored negative delta.
	var down := AiSpell.spell_modifier_delta(_profiles(), att, def_ctx,
		{"modifier": {"hit_mod": -1}}, false, 0.0, false)
	assert_float(down).is_equal_approx(6.0 * (2.0 / 6.0) * 0.5 - 6.0 * 0.5 * 0.5, EPS)


func test_spell_modifier_delta_def_mod_and_rule_grant() -> void:
	var att := {"quality": 4}
	var def_ctx := {"defense": 4}
	# +1 to defense rolls on the DEFENDER: saves on 3+ → the attacker's EV drops (negative delta).
	var def_up := AiSpell.spell_modifier_delta(_profiles(), att, def_ctx,
		{"modifier": {"def_mod": 1}}, false, 0.0, false)
	assert_float(def_up).is_equal_approx(6.0 * 0.5 * (1.0 - 4.0 / 6.0) - 6.0 * 0.5 * 0.5, EPS)
	# Granting Bane strips the guaranteed Defense-6 blocks → a positive delta.
	var bane_grant := AiSpell.spell_modifier_delta(_profiles(), att, def_ctx,
		{"grants_rule": "Bane"}, false, 0.0, false)
	assert_bool(bane_grant > 0.0).is_true()
	# An effect the EV chain cannot price (movement) is worth exactly 0 — the honest boundary.
	var move := AiSpell.spell_modifier_delta(_profiles(), att, def_ctx,
		{"modifier": {"advance_in": 2}}, false, 0.0, false)
	assert_float(move).is_equal(0.0)


func test_spell_modifier_delta_scope_gates_the_side() -> void:
	# A melee-scoped buff is worth 0 on a shooting evaluation (and vice versa).
	var att := {"quality": 4}
	var def_ctx := {"defense": 4}
	var ranged_profiles := [{"attacks": 4, "range": 18, "ap": 0}]
	assert_float(AiSpell.spell_modifier_delta(ranged_profiles, att, def_ctx,
		{"modifier": {"hit_mod": 1}, "scope": "melee"}, true, 10.0, false)).is_equal(0.0)
	assert_float(AiSpell.spell_modifier_delta(_profiles(), att, def_ctx,
		{"modifier": {"hit_mod": 1}, "scope": "shooting"}, false, 0.0, false)).is_equal(0.0)
	# The same modifier IS priced on its own side.
	assert_bool(AiSpell.spell_modifier_delta(ranged_profiles, att, def_ctx,
		{"modifier": {"hit_mod": 1}, "scope": "shooting"}, true, 10.0, false) > 0.0).is_true()


# === The official Solo v3.5.0 D3+X pick cycle ===

func test_official_pick_order_indexes_and_wraps() -> void:
	# Caster(2), D3=1 → index 3 (1-based) on a 6-spell list, cycling forward with wrap.
	assert_array(AiSpell.official_pick_order(6, 1, 2)).is_equal([2, 3, 4, 5, 0, 1])
	# Caster(3), D3=3 → index 6 → the LAST spell first, then wrap to the start.
	assert_array(AiSpell.official_pick_order(6, 3, 3)).is_equal([5, 0, 1, 2, 3, 4])
	# An index beyond the list wraps (a Caster(3) rolling high on a 4-spell list).
	assert_array(AiSpell.official_pick_order(4, 3, 3)).is_equal([1, 2, 3, 0])
	assert_array(AiSpell.official_pick_order(0, 2, 1)).is_equal([])


# === Token economy (deterministic boost/interference heuristics) ===

func test_plan_boost_spends_while_marginal_ev_exceeds_floor() -> void:
	# Each boost token is worth effect_value/6 until the [2,6] clamp: a 3-wound spell buys tokens
	# (0.5 > 0.05) up to the 2+ ceiling — exactly 2 of the 4 available.
	assert_int(AiSpell.plan_boost(3.0, 4)).is_equal(2)
	# A worthless effect never buys a token; an empty pool never spends.
	assert_int(AiSpell.plan_boost(0.0, 4)).is_equal(0)
	assert_int(AiSpell.plan_boost(3.0, 0)).is_equal(0)
	# A marginal effect below the floor (6 × 0.05 = 0.3 wounds) holds the tokens.
	assert_int(AiSpell.plan_boost(0.2, 4)).is_equal(0)


func test_plan_interference_mirrors_the_calculus() -> void:
	# A 3-wound enemy cast is worth interfering with: -1 per token until the 6+ clamp (2 tokens).
	assert_int(AiSpell.plan_interference(3.0, 4)).is_equal(2)
	# Against a boosted cast the clamp sits further away — more tokens pay off.
	assert_int(AiSpell.plan_interference(3.0, 9, 2)).is_equal(4)
	assert_int(AiSpell.plan_interference(0.0, 4)).is_equal(0)


# === F4: pure once-mod filtering (beneficiary + scope + role — the dice path's read contract) ===

func _mods() -> Array:
	return [
		{"spell": "Raiding Drugs", "hit_mod": 1, "def_mod": 0, "scope": "melee", "beneficiary": "attackers", "duration": "once"},
		{"spell": "Psy-Strength", "hit_mod": 1, "def_mod": 0, "scope": "melee", "beneficiary": "", "duration": "once"},
		{"spell": "Brain Infestation", "hit_mod": -1, "def_mod": 0, "scope": "attacking", "beneficiary": "", "duration": "once"},
		{"spell": "Banishing Sigil", "hit_mod": 0, "def_mod": -1, "scope": "", "beneficiary": "", "duration": "once"},
		{"spell": "Eagle-Eyed Focus", "hit_mod": 1, "def_mod": 0, "scope": "shooting", "beneficiary": "attackers", "duration": "once"},
	]


func test_mods_for_attacker_own_excludes_attackers_beneficiary() -> void:
	var own := AiSpell.mods_for(_mods(), "attacker_own", true)
	var names: Array = own.map(func(r): return r["spell"])
	# Eigene Melee-Rolle: Psy-Strength (+1 melee) und Brain Infestation (-1 attacking) — NIE Raiding Drugs.
	assert_bool(names.has("Psy-Strength")).is_true()
	assert_bool(names.has("Brain Infestation")).is_true()
	assert_bool(names.has("Raiding Drugs")).is_false()


func test_mods_for_vs_target_selects_attackers_beneficiary_scoped() -> void:
	# Gegen den Träger im MELEE: Raiding Drugs greift, Eagle-Eyed (shooting) nicht.
	var vs_m: Array = AiSpell.mods_for(_mods(), "vs_target", true).map(func(r): return r["spell"])
	assert_bool(vs_m.has("Raiding Drugs")).is_true()
	assert_bool(vs_m.has("Eagle-Eyed Focus")).is_false()
	# Beim BESCHUSS des Trägers: genau umgekehrt.
	var vs_s: Array = AiSpell.mods_for(_mods(), "vs_target", false).map(func(r): return r["spell"])
	assert_bool(vs_s.has("Eagle-Eyed Focus")).is_true()
	assert_bool(vs_s.has("Raiding Drugs")).is_false()


func test_mods_for_defense_reads_def_mod_only() -> void:
	var d := AiSpell.mods_for(_mods(), "defense", false)
	assert_int(d.size()).is_equal(1)
	assert_str(str((d[0] as Dictionary)["spell"])).is_equal("Banishing Sigil")


# === NML-104: the hit SOURCE filters the defense read (the wording of each token decides) ===

func _mods_scoped_defense() -> Array:
	return [
		{"spell": "Warding Chant", "def_mod": 1, "scope": "", "beneficiary": "", "duration": "round"},
		{"spell": "Shield Wall", "def_mod": 1, "scope": "melee", "beneficiary": "", "duration": "round"},
		{"spell": "Flak Field", "def_mod": 1, "scope": "shooting", "beneficiary": "", "duration": "round"},
	]


func test_mods_for_spell_source_keeps_only_the_unscoped_defense_mods() -> void:
	# A spell hit is neither a shot nor a melee attack, so a token whose own text scopes ITSELF to an
	# attack stays out — while the one without a clause applies, because the block step is neutral.
	var spell_read: Array = AiSpell.mods_for(_mods_scoped_defense(), "defense", false,
		AiCombatMath.HIT_SOURCE_SPELL).map(func(r): return r["spell"])
	assert_array(spell_read).contains(["Warding Chant"])
	assert_array(spell_read).not_contains(["Shield Wall"])
	assert_array(spell_read).not_contains(["Flak Field"])
	# The attack reads are untouched: shooting still keeps its shooting-scoped token.
	var shot: Array = AiSpell.mods_for(_mods_scoped_defense(), "defense", false).map(func(r): return r["spell"])
	assert_array(shot).contains(["Warding Chant"])
	assert_array(shot).contains(["Flak Field"])


# === NML-006: the remaining encoding kinds (casting/morale/range/speed/grant) as pure roles ===

func _mods_nml006() -> Array:
	return [
		{"spell": "Burn the Heretic", "casting_mod": -3, "scope": "", "beneficiary": "", "duration": "once"},
		{"spell": "Psy-Injected Courage", "morale_mod": 1, "scope": "", "beneficiary": "", "duration": "once"},
		{"spell": "Battle Rune", "range_in": 6, "scope": "shooting", "beneficiary": "", "duration": "once"},
		{"spell": "Time Freeze", "advance_in": -2, "rush_in": -4, "scope": "", "beneficiary": "", "duration": "once"},
		{"spell": "Battle Fury", "grants_rule": "Furious", "scope": "", "beneficiary": "", "duration": "once"},
	]


func test_mods_for_nml006_roles_are_disjoint() -> void:
	# Jede Rolle liest GENAU ihre Encoding-Art — kein Übersprechen zwischen den Arten.
	for pair in [["casting", "Burn the Heretic"], ["morale", "Psy-Injected Courage"],
			["speed", "Time Freeze"], ["grant", "Battle Fury"]]:
		var got := AiSpell.mods_for(_mods_nml006(), str(pair[0]), false)
		assert_int(got.size()).is_equal(1)
		assert_str(str((got[0] as Dictionary)["spell"])).is_equal(str(pair[1]))


func test_mods_for_range_is_shooting_only() -> void:
	# range_in ist im Datenbestand shooting-scoped: die Melee-Lesung liefert NICHTS (generischer
	# Scope-Filter), die Schuss-Lesung genau den Reichweiten-Spruch.
	var shoot := AiSpell.mods_for(_mods_nml006(), "range", false)
	assert_int(shoot.size()).is_equal(1)
	assert_str(str((shoot[0] as Dictionary)["spell"])).is_equal("Battle Rune")
	assert_int(AiSpell.mods_for(_mods_nml006(), "range", true).size()).is_equal(0)


func test_mods_for_legacy_roles_ignore_nml006_records() -> void:
	# Die F4-Rollen (hit/def) sehen die neuen Encoding-Arten nicht — Regressionsschutz.
	assert_int(AiSpell.mods_for(_mods_nml006(), "attacker_own", true).size()).is_equal(0)
	assert_int(AiSpell.mods_for(_mods_nml006(), "defense", false).size()).is_equal(0)


# === grant_facet — the facet a granted rule name maps to (GRANT_FACETS + its scope suffixes) ===

func test_grant_facet_maps_only_the_facets_the_ev_chain_reads() -> void:
	# Every GRANT_FACETS entry names a facet profile_ev already reads for a NATIVE weapon rule — a
	# granted rule is worth exactly what that facet is worth, no extra valuation invented here.
	assert_str(AiSpell.grant_facet("Furious")).is_equal("furious")
	assert_str(AiSpell.grant_facet("Relentless")).is_equal("relentless")
	assert_str(AiSpell.grant_facet("Rending")).is_equal("rending")
	assert_str(AiSpell.grant_facet("Surge")).is_equal("surge")
	assert_str(AiSpell.grant_facet("Indirect")).is_equal("indirect")
	assert_str(AiSpell.grant_facet("Shred")).is_equal("shred")
	assert_str(AiSpell.grant_facet("Bane")).is_equal("bane")
	# Scope suffixes ("Bane in Melee", "Indirect when Shooting" — the data's own encoding) resolve to
	# the SAME facet: it is still the same rule, just textually scoped.
	assert_str(AiSpell.grant_facet("Bane when Shooting")).is_equal("bane")
	assert_str(AiSpell.grant_facet("Bane in Melee")).is_equal("bane")
	assert_str(AiSpell.grant_facet("Indirect when Shooting")).is_equal("indirect")
	# Unpriced names return "" EXACTLY — the honest boundary: "<X> Boost" is an UPGRADE rule (only
	# fires when the bearer already has the base rule; its facets are dice-path-only), "<X> Aura"
	# grants to OTHER units (a different effect), and the rest simply have no term in profile_ev.
	for grant_name in ["Primal Boost", "Ferocious Boost", "Devout Boost", "Hit & Run Fighter Aura",
			"Unstoppable", "Quick Shot", "Evasive", "Melee Evasion", "Steadfast", "Regeneration", ""]:
		assert_str(AiSpell.grant_facet(grant_name)).is_equal("")


# === P3 grants — each priced via the SAME facet a native weapon rule with the same name reads ===

func test_spell_modifier_delta_furious_is_worth_a_sixth_of_the_attacks_on_a_charge() -> void:
	# Furious (GF/AoF v3.5.1 p.14): melee AND charging only, +1 hit per unmodified 6.
	# 6 attacks × P(hit 4+)=0.5 → 3 hits; Furious adds attacks/6 = 1 hit → 4; each unsaved at Def4+ =
	# 0.5 → 2.0 vs the un-granted baseline 1.5 → delta 0.5.
	var att := {"quality": 4}
	var def_ctx := {"defense": 4}
	var delta := AiSpell.spell_modifier_delta(_profiles(), att, def_ctx,
		{"grants_rule": "Furious"}, false, 0.0, true)
	assert_float(delta).is_equal_approx(0.5, EPS)
	# RED FLIP: Furious needs a CHARGE — the same grant on a non-charging melee swing buys nothing.
	var not_charging := AiSpell.spell_modifier_delta(_profiles(), att, def_ctx,
		{"grants_rule": "Furious"}, false, 0.0, false)
	assert_float(not_charging).is_equal(0.0)
	# RED FLIP: Furious needs MELEE — granting it on a shooting profile never reaches the facet read.
	var ranged_profiles := [{"attacks": 6, "range": 18, "ap": 0}]
	var shooting := AiSpell.spell_modifier_delta(ranged_profiles, att, def_ctx,
		{"grants_rule": "Furious"}, true, 12.0)
	assert_float(shooting).is_equal(0.0)


func test_spell_modifier_delta_relentless_only_over_nine_inches() -> void:
	# Relentless (v3.5.1 p.14): shooting only, +1 hit per unmodified 6, but ONLY over 9".
	# 4 attacks × 0.5 = 2 hits; +4/6 bonus hits, each unsaved at Def4+ = 0.5 → delta = (4/6) × 0.5.
	var ranged_profiles := [{"attacks": 4, "range": 18, "ap": 0}]
	var att := {"quality": 4}
	var def_ctx := {"defense": 4}
	var delta := AiSpell.spell_modifier_delta(ranged_profiles, att, def_ctx,
		{"grants_rule": "Relentless"}, true, 12.0)
	assert_float(delta).is_equal_approx(1.0 / 3.0, EPS)
	# RED FLIP: at 6" (not "over" 9") the bonus never triggers — the grant is worth exactly 0.
	var close := AiSpell.spell_modifier_delta(ranged_profiles, att, def_ctx,
		{"grants_rule": "Relentless"}, true, 6.0)
	assert_float(close).is_equal(0.0)
	# RED FLIP: Relentless is shooting-only — granting it on the melee side is worth exactly 0.
	var melee := AiSpell.spell_modifier_delta(_profiles(), att, def_ctx,
		{"grants_rule": "Relentless"}, false, 0.0, false)
	assert_float(melee).is_equal(0.0)


func test_spell_modifier_delta_surge_is_unconditional_and_rending_upgrades_the_sixes() -> void:
	var att := {"quality": 4}
	var def_ctx := {"defense": 4}
	# Surge (v3.5.1 p.14): +1 hit per unmodified 6, UNCONDITIONAL — unlike Furious, no charge needed.
	var surge := AiSpell.spell_modifier_delta(_profiles(), att, def_ctx,
		{"grants_rule": "Surge"}, false, 0.0, false)
	assert_float(surge).is_equal_approx(0.5, EPS)
	# Rending (v3.5.1 p.14): unmodified 6s to hit get AP(+4) — a positive delta even without a charge.
	var rending := AiSpell.spell_modifier_delta(_profiles(), att, def_ctx,
		{"grants_rule": "Rending"}, false, 0.0, false)
	assert_bool(rending > 0.0).is_true()


func test_spell_modifier_delta_indirect_is_worth_the_targets_cover() -> void:
	# Indirect (wave 5: the target's Cover does not apply to the volley) is worth exactly the save
	# swing Cover would have bought the defender (Def4+ → 3+): delta = 1/3 of the volley's hits.
	var ranged_profiles := [{"attacks": 4, "range": 18, "ap": 0}]
	var att := {"quality": 4}
	var covered := {"defense": 4, "in_cover": true}
	var delta := AiSpell.spell_modifier_delta(ranged_profiles, att, covered,
		{"grants_rule": "Indirect"}, true, 12.0)
	assert_float(delta).is_equal_approx(1.0 / 3.0, EPS)
	# RED FLIP: with no Cover to ignore in the first place, Indirect has nothing to buy — exactly 0.
	var uncovered := {"defense": 4, "in_cover": false}
	var no_cover := AiSpell.spell_modifier_delta(ranged_profiles, att, uncovered,
		{"grants_rule": "Indirect"}, true, 12.0)
	assert_float(no_cover).is_equal(0.0)


func test_spell_modifier_delta_upgrade_and_defensive_grants_stay_at_zero() -> void:
	# The honest boundary (grant_facet's documented refusals): each of these needs its OWN valuation
	# and is priced at exactly 0 here, never invented.
	var att := {"quality": 4}
	var def_ctx := {"defense": 4}
	# Primal Boost is an UPGRADE rule: its surge_attack_low facet is read only by the dice path in
	# scripts/main.gd, never by AiEv.profile_ev — so this chain cannot price it.
	# Unstoppable / Quick Shot / Evasive / Steadfast / Regeneration: defensive/movement grants with
	# no term in profile_ev at all — needs its own valuation, not a reused facet.
	for grant in ["Primal Boost", "Unstoppable", "Quick Shot", "Evasive", "Steadfast", "Regeneration"]:
		var delta := AiSpell.spell_modifier_delta(_profiles(), att, def_ctx,
			{"grants_rule": grant}, false, 0.0, true)
		assert_float(delta).is_equal(0.0)
