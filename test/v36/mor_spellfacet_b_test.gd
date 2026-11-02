extends GdUnitTestSuite
## Rules 3.6 row MOR-SPELLFACET-b: the Destructive spell token prices AP(+1) against a
## defender still above half its starting size / Tough value at EPOCH_73_V36, and keeps the
## 3.5 AP(+4)-on-sixes ticket below it. The core twin is
## core/nml-core/src/tests/unit/v36_morale.rs (mod mor_spellfacet_b).

const EPS := 0.0001
const MODELS := 5

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore


func _defender(alive: int) -> Dictionary:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "mor_spellfacet_b_%d" % alive
	u.unit_properties = {"player_id": 2, "name": "Target", "quality": 4, "defense": 4,
		"special_rules": [], "game_system": "gf", "faction_folder": "elven_jesters"}
	for i in MODELS:
		var m := ModelInstance.new()
		m.is_alive = i < alive
		m.wounds_max = 1
		m.wounds_current = 1
		u.models.append(m)
	return BattleSim._ctx_of({"unit": u, "alive": alive, "in_cover": false, "wounds": []})


func _facets(system: String, faction: String, spell_name: String, epoch: int) -> Dictionary:
	var entry: Dictionary = SpellsRegistry.entry_for(system, faction, spell_name)
	assert_bool(entry.is_empty()).override_failure_message(
		"%s/%s carries no %s" % [system, faction, spell_name]).is_false()
	var effect: Dictionary = entry.get("effect", {})
	return AiSpell.spell_facets(effect.get("weapon_rules", []), epoch)


func _ev(system: String, faction: String, spell_name: String, epoch: int, def_ctx: Dictionary) -> float:
	var entry: Dictionary = SpellsRegistry.entry_for(system, faction, spell_name)
	assert_bool(entry.is_empty()).override_failure_message(
		"%s/%s carries no %s" % [system, faction, spell_name]).is_false()
	var effect: Dictionary = entry.get("effect", {})
	var hits := int(effect.get("hits", 0)) * maxi(int((entry.get("target", {}) as Dictionary).get("count", 1)), 1)
	return AiSpell.spell_damage_ev(hits, def_ctx, AiSpell.spell_facets(effect.get("weapon_rules", []), epoch))


func test_destructive_prices_ap_one_only_against_an_above_half_defender_at_epoch_73() -> void:
	var f := _facets("gf", "elven_jesters", "Light Fragments", AiActRecorder.EPOCH_73_V36)
	assert_int(int(f["on6_ap"])).override_failure_message(
		"the 3.5 AP(+4) on the sixes is gone from 73").is_equal(0)
	assert_int(int(f["ap_vs_above_half"])).override_failure_message(
		"the token prices AP(+1) against the defender state").is_equal(1)

	var above := _ev("gf", "elven_jesters", "Light Fragments", AiActRecorder.EPOCH_73_V36, _defender(MODELS))
	var below := _ev("gf", "elven_jesters", "Light Fragments", AiActRecorder.EPOCH_73_V36, _defender(2))
	assert_float(above).is_equal_approx(4.0, EPS)   # 6 hits at Defense 4: 6 × 2/3 = 4
	assert_float(below).is_equal_approx(3.0, EPS)   # no AP at or below half: 6 × 1/2 = 3


func test_a_plain_spell_is_unchanged_in_both_states() -> void:
	for alive: int in [MODELS, 2]:
		var now := _ev("gf", "elven_jesters", "Fatal Sorrow", AiActRecorder.EPOCH_73_V36, _defender(alive))
		var before := _ev("gf", "elven_jesters", "Fatal Sorrow", AiActRecorder.EPOCH_72_PLAYTEST_RULES, _defender(alive))
		assert_float(now).is_equal_approx(3.0, EPS)
		assert_float(now).is_equal_approx(before, EPS)


func test_destructive_keeps_the_35_on6_ap_at_epoch_72() -> void:
	var f := _facets("gf", "elven_jesters", "Light Fragments", AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	assert_int(int(f["on6_ap"])).is_equal(4)   # the 3.5 on-6 ticket
	assert_int(int(f["ap_vs_above_half"])).is_equal(0)

	var old := 5.0 * 0.5 + 1.0 * (5.0 / 6.0)
	for alive: int in [MODELS, 2]:
		var ev := _ev("gf", "elven_jesters", "Light Fragments", AiActRecorder.EPOCH_72_PLAYTEST_RULES, _defender(alive))
		assert_float(ev).is_equal_approx(old, EPS)
