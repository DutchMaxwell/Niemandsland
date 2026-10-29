extends GdUnitTestSuite
## The 29.10.2026 play-test fixes in the GDScript sim twins, gated on AiActRecorder.EPOCH_72_PLAYTEST_RULES
## exactly like the core (acts.rs EPOCH_72_PLAYTEST_RULES): A1 a unit-level Lacerate re-rolls the Defense 6s
## but keeps the defender's Regeneration roll, A2 wounds that leave a unit at half strength or less test
## morale without a lost model, A4 Deadly(X) against Regeneration is priced roll-then-cap. Below the gate
## every recorded game replays the old reading. The table's own dice (#1911/#1912/#1914) are not gated.

const ATT := {"quality": 4, "models": 5}
const REGEN1 := {"defense": 4, "tough": 1, "models": 5, "regeneration": true, "regen_target": 5}


func _sim_unit(id: String, rules: Array) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = id
	u.unit_properties = {"player_id": 1, "name": id, "quality": 4, "defense": 4, "special_rules": rules}
	var od := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Blade"
	w.range_value = 0
	w.attacks = 2
	od.weapons = [w] as Array[OPRApiClient.OPRWeapon]
	u.source_type = "opr"
	u.source_data = od
	var m: ModelInstance = ModelInstance.new()
	m.unit = u
	m.is_alive = true
	m.node = auto_free(Node3D.new())
	add_child(m.node)
	u.models.append(m)
	return u


func _melee_profile_at(epoch: int, rules: Array) -> Dictionary:
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = epoch
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Laced": _sim_unit("Laced", rules)}
	var state := BattleSim.capture(army)
	var q: Dictionary = BattleSim._profiles_of(state["units"]["Laced"], true)[0]
	AiActRecorder.rules_epoch = epoch0   # statics leak across gdUnit tests — restore
	return q


## A1: a unit-level Lacerate keeps the re-roll at both epochs and loses the Regeneration bypass from the gate;
## its expected wounds against a Regeneration (5+) target drop by the kept third. Bane keeps its bypass.
func test_a_unit_level_lacerate_keeps_regeneration_from_the_gate() -> void:
	var gate := AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var old := _melee_profile_at(gate - 1, ["Lacerate"])
	var new := _melee_profile_at(gate, ["Lacerate"])
	assert_bool(bool(old["bane"]) and bool(new["bane"])).is_true()
	assert_bool(bool(old.get("bypass_regen", true))).is_true()
	assert_bool(bool(new.get("bypass_regen", true))).override_failure_message("A1: Lacerate keeps Regeneration").is_false()
	var ev_old := AiEv.profile_ev(old, ATT, REGEN1, 0.0, false)
	assert_float(AiEv.profile_ev(new, ATT, REGEN1, 0.0, false)).is_equal_approx(ev_old * 2.0 / 3.0, 0.0001)
	assert_bool(bool(_melee_profile_at(gate, ["Bane"]).get("bypass_regen", true))).is_true()


func _squad() -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "Squad"
	u.unit_properties = {"player_id": 2, "name": "Squad", "quality": 5, "defense": 4, "special_rules": ["Tough(3)"]}
	for i in range(4):
		var m: ModelInstance = ModelInstance.new()
		m.unit = u
		m.is_alive = i < 2
		m.wounds_current = 3 if i < 2 else 0
		u.models.append(m)
	return u


## Two of four Tough(3) models left before and after the volley (no loss), 6 wounds before, `after` now.
## Quality 5+ fails the expected test, so a due test leaves the unit Shaken.
func _shaken_at(epoch: int, alive: int, after: Array) -> bool:
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = epoch
	var tu := {"unit": _squad(), "alive": alive, "wounds": after, "shaken": false}
	BattleSim._expected_shooting_morale(tu, alive, 3 * alive)
	AiActRecorder.rules_epoch = epoch0   # statics leak across gdUnit tests — restore
	return bool(tu["shaken"])


## A2: below the gate wounds without a lost model never test; from it they test at half strength.
func test_wounds_at_half_strength_test_morale_from_the_gate() -> void:
	var gate := AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_bool(_shaken_at(gate - 1, 2, [3, 1])).override_failure_message("below the gate: casualty-only").is_false()
	assert_bool(_shaken_at(gate, 2, [3, 1])).override_failure_message("A2: 2 of 4 and wounded").is_true()
	assert_bool(_shaken_at(gate, 2, [3, 3])).override_failure_message("no wound, no test").is_false()
	assert_bool(_shaken_at(gate, 3, [3, 3, 1])).override_failure_message("3 of 4 is above half").is_false()


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
	var lacerate_s := AiSpell.spell_facets(["Lacerate"])
	var d3 := AiSpell.spell_facets(["Deadly(3)"])
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
