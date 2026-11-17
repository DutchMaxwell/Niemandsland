extends GdUnitTestSuite
## The 29.10.2026 play-test fixes in the table-side estimates, gated on AiActRecorder.EPOCH_72_PLAYTEST_RULES
## exactly like the core (acts.rs EPOCH_72_PLAYTEST_RULES): A4 Deadly(X) against Regeneration is priced
## roll-then-cap, and Lacerate keeps the defender's Regeneration roll in the weapon and spell estimates. (A1 and A2 of
## the sim twin are the core's: core/nml-core/src/tests/unit/playtest_rules.rs, tests/sim/playtest_morale.rs.) Below the gate
## every recorded game replays the old reading. The table's own dice (#1911/#1912/#1914) are not gated.

const ATT := {"quality": 4, "models": 5}
const REGEN1 := {"defense": 4, "tough": 1, "models": 5, "regeneration": true, "regen_target": 5}


## A4: Deadly(3) on a 1-wound Regeneration (5+) model is worth 26/27 per unsaved wound from the gate, 2/3 below.
func test_deadly_against_regeneration_is_priced_roll_then_cap_from_the_gate() -> void:
	var w := {"name": "Rifle", "attacks": 10, "ap": 0, "deadly": 3, "range": 24, "rules": []}
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES - 1
	var ev_old := AiEv.profile_ev(w, ATT, REGEN1, 12.0, false)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var ev_new := AiEv.profile_ev(w, ATT, REGEN1, 12.0, false)
	AiActRecorder.rules_epoch = epoch0   # statics leak across gdUnit tests — restore
	assert_float(ev_old).is_equal_approx(2.5 * 2.0 / 3.0, 0.0001)
	assert_float(ev_new).is_equal_approx(2.5 * 26.0 / 27.0, 0.0001)


## The estimates #1914, #1920 and #1921 changed (AiEv.profile_ev, AiSpell.spell_damage_ev) follow the same gate:
## below it they price exactly what the core prices at 71 (core tests/unit/playtest_rules.rs pins the same
## numbers): a Lacerate weapon and a Lacerate spell still bypass Regeneration, and a Deadly(3) spell on a
## 1-wound Regeneration model is the capped single roll. From the gate, the table's readings.
func test_below_the_gate_the_estimates_price_what_the_core_prices_at_71() -> void:
	var gate := AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var through_w := 5.0 * (1.0 - 5.0 / 12.0)   # 10 attacks at Q4+, Defense 4+ with the 6s re-rolled
	var through_s := 6.0 * (1.0 - 5.0 / 12.0)   # 6 spell hits, same save
	var lacerate_w := {"name": "Claw Gun", "attacks": 10, "ap": 0, "deadly": 0, "bane": true, "range": 24,
		"rules": ["Lacerate"]}
	var lacerate_s := AiSpell.spell_facets(["Lacerate"], AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var d3 := AiSpell.spell_facets(["Deadly(3)"], AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var epoch0: int = AiActRecorder.rules_epoch
	var got := {}
	for e in [gate - 1, gate]:
		AiActRecorder.rules_epoch = e
		got[e] = [AiEv.profile_ev(lacerate_w, ATT, REGEN1, 12.0, false),
			AiSpell.spell_damage_ev(6, REGEN1, lacerate_s), AiSpell.spell_damage_ev(6, REGEN1, d3)]
	AiActRecorder.rules_epoch = epoch0   # statics leak across gdUnit tests — restore
	var old: Array = got[gate - 1]
	var new: Array = got[gate]
	assert_float(float(old[0])).override_failure_message("below the gate: the weapon's Lacerate bypasses").is_equal_approx(through_w, 0.0001)
	assert_float(float(old[1])).override_failure_message("below the gate: the spell's Lacerate bypasses").is_equal_approx(through_s, 0.0001)
	assert_float(float(old[2])).override_failure_message("below the gate: the capped single roll").is_equal_approx(3.0 * 2.0 / 3.0, 0.0001)
	assert_float(float(new[0])).is_equal_approx(through_w * 2.0 / 3.0, 0.0001)
	assert_float(float(new[1])).is_equal_approx(through_s * 2.0 / 3.0, 0.0001)
	assert_float(float(new[2])).is_equal_approx(3.0 * 26.0 / 27.0, 0.0001)
