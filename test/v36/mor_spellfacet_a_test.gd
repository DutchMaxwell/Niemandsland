extends GdUnitTestSuite
## Rules 3.6 row MOR-SPELLFACET-a: the spell facet reader follows the renamed and re-pointed
## weapon-rule tokens at EPOCH_73_V36. Below 73 all four keep the 3.5 readings. The core twin is
## core/nml-core/src/tests/unit/v36_morale.rs (mod mor_spellfacet_a).

const EPS := 0.0001

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore


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


func test_the_four_tokens_read_the_36_facets_at_epoch_73() -> void:
	var fracture := _facets("aof", "high_elves", "Magic Arrows", AiActRecorder.EPOCH_73_V36)
	assert_int(int(fracture["on6_ap"])).is_equal(2)   # Fracture = the old Crack
	assert_bool(bool(fracture["ignores_regen"])).is_false()

	var puncture := _facets("aof", "duchies_of_vinci", "Explosive Concoction", AiActRecorder.EPOCH_73_V36)
	assert_bool(bool(puncture["ignores_regen"])).is_true()   # Puncture = the old Disintegrate
	assert_int(int(puncture["ap_vs_def3"])).is_equal(2)
	assert_int(int(puncture["on6_ap"])).is_equal(0)

	var disintegrate := _facets("aof", "beastmen", "Ancestral Wrath", AiActRecorder.EPOCH_73_V36)
	assert_bool(bool(disintegrate["ignores_regen"])).is_true()
	assert_int(int(disintegrate["ap_vs_tough3"])).is_equal(2)
	assert_int(int(disintegrate["ap_vs_def3"])).is_equal(0)   # never the 3.5 ticket

	var shatter := _facets("aof", "kingdom_of_angels", "Lightning Bolt", AiActRecorder.EPOCH_73_V36)
	assert_int(int(shatter["on6_ap"])).is_equal(3)   # Shatter: sixes get AP(+3)
	assert_int(int(shatter["ap_vs_tough3"])).is_equal(0)   # never the 3.5 ticket


func test_the_four_tokens_keep_their_35_readings_at_epoch_72() -> void:
	var e := AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var fracture := _facets("aof", "high_elves", "Magic Arrows", e)
	assert_int(int(fracture["on6_ap"])).is_equal(0)   # Fracture was unknown
	assert_bool(bool(fracture["ignores_regen"])).is_false()

	var puncture := _facets("aof", "duchies_of_vinci", "Explosive Concoction", e)
	assert_int(int(puncture["on6_ap"])).is_equal(0)   # Puncture was unknown
	assert_bool(bool(puncture["ignores_regen"])).is_false()
	assert_int(int(puncture["ap_vs_def3"])).is_equal(0)

	var disintegrate := _facets("aof", "beastmen", "Ancestral Wrath", e)
	assert_bool(bool(disintegrate["ignores_regen"])).is_true()
	assert_int(int(disintegrate["ap_vs_def3"])).is_equal(2)   # the 3.5 ticket
	assert_int(int(disintegrate["ap_vs_tough3"])).is_equal(0)

	var shatter := _facets("aof", "kingdom_of_angels", "Lightning Bolt", e)
	assert_int(int(shatter["ap_vs_tough3"])).is_equal(2)   # the 3.5 ticket
	assert_int(int(shatter["on6_ap"])).is_equal(0)


func test_shatter_raises_the_six_hit_ev_at_epoch_73() -> void:
	var def_ctx := {"defense": 4, "tough": 1, "models": 1}
	var now := _ev("aof", "kingdom_of_angels", "Lightning Bolt", AiActRecorder.EPOCH_73_V36, def_ctx)
	var before := _ev("aof", "kingdom_of_angels", "Lightning Bolt", AiActRecorder.EPOCH_72_PLAYTEST_RULES, def_ctx)
	assert_bool(now > before + EPS).override_failure_message(
		"AP(+3) on the sixes must raise the EV: %f vs %f" % [now, before]).is_true()


func test_disintegrate_adds_ap_two_only_against_tough_three_at_epoch_73() -> void:
	var spell_name := "Ancestral Wrath"
	var tough3 := {"defense": 4, "tough": 3, "models": 1}
	var tough2 := {"defense": 4, "tough": 2, "models": 1}
	var now3 := _ev("aof", "beastmen", spell_name, AiActRecorder.EPOCH_73_V36, tough3)
	var old3 := _ev("aof", "beastmen", spell_name, AiActRecorder.EPOCH_72_PLAYTEST_RULES, tough3)
	assert_bool(now3 > old3 + EPS).override_failure_message(
		"Tough(3)+ pays the new AP(+2): %f vs %f" % [now3, old3]).is_true()

	var now2 := _ev("aof", "beastmen", spell_name, AiActRecorder.EPOCH_73_V36, tough2)
	var old2 := _ev("aof", "beastmen", spell_name, AiActRecorder.EPOCH_72_PLAYTEST_RULES, tough2)
	assert_float(now2).is_equal_approx(old2, EPS)   # Tough(2) pays nothing new

	var regen := {"defense": 4, "tough": 3, "models": 1,
		"regeneration": true, "regen_target": 5, "regen_target_spell": 5}
	assert_float(_ev("aof", "beastmen", spell_name, AiActRecorder.EPOCH_73_V36, regen)).is_equal_approx(now3, EPS)
