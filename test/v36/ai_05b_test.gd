extends GdUnitTestSuite
## Rules 3.6 row AI-05b: the nine spell tokens of the new weapon family read off the spell's own
## token list at EPOCH_73_V36. Five are priced by the spell damage EV (Purge, Decimate,
## Obliterate, Reap, Fragment); four stay explicit no-ops (Pierce, Smash, Demolish, Scourge)
## because the spell EV carries no cast distance or terrain context. The core twin is
## core/nml-core/src/tests/unit/v36_ai.rs (mod ai_05b).

const EPS := 0.000001

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0
	SpellsRegistry.reset_cache()


func _entry(system: String, faction: String, spell_name: String) -> Dictionary:
	var entry: Dictionary = SpellsRegistry.entry_for(system, faction, spell_name)
	assert_bool(entry.is_empty()).override_failure_message(
		"%s/%s carries no %s" % [system, faction, spell_name]).is_false()
	return entry


func _facets(system: String, faction: String, spell_name: String, epoch: int) -> Dictionary:
	var effect: Dictionary = _entry(system, faction, spell_name).get("effect", {})
	return AiSpell.spell_facets(effect.get("weapon_rules", []), epoch)


func _ev(system: String, faction: String, spell_name: String, epoch: int, def_ctx: Dictionary) -> float:
	AiActRecorder.rules_epoch = epoch
	var entry: Dictionary = _entry(system, faction, spell_name)
	var effect: Dictionary = entry.get("effect", {})
	var hits := int(effect.get("hits", 0)) * maxi(int((entry.get("target", {}) as Dictionary).get("count", 1)), 1)
	return AiSpell.spell_damage_ev(hits, def_ctx, AiSpell.spell_facets(effect.get("weapon_rules", []), epoch))


func _defender(defense: int, tough: int, above_half: bool, shaken: bool) -> Dictionary:
	return {"defense": defense, "tough": tough, "models": 1,
		"above_half_strength": above_half, "shaken_or_fatigued": shaken}


## Case 1 — every evaluable token moves the EV only while its condition holds, and the closed
## condition is exactly the epoch-72 plain spell.
func test_the_evaluable_tokens_price_their_conditions() -> void:
	var e73 := AiActRecorder.EPOCH_73_V36
	var e72 := AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var shaken := _defender(4, 1, false, true)
	var calm := _defender(4, 1, false, false)

	assert_float(_ev("gf", "blessed_sisters", "Eternal Flame", e73, shaken)).is_equal_approx(2.5, EPS)
	assert_float(_ev("gf", "blessed_sisters", "Eternal Flame", e73, calm)).is_equal_approx(1.5, EPS)
	assert_float(_ev("gf", "blessed_sisters", "Eternal Flame", e73, calm)).is_equal_approx(
		_ev("gf", "blessed_sisters", "Eternal Flame", e72, calm), EPS)

	var above := _defender(4, 1, true, false)
	assert_float(_ev("gf", "daemons_of_plague", "Rapid Putrefaction", e73, above)).is_equal_approx(14.0 / 9.0, EPS)
	assert_float(_ev("gf", "daemons_of_plague", "Rapid Putrefaction", e73, calm)).is_equal_approx(4.0 / 3.0, EPS)
	assert_float(_ev("gf", "daemons_of_plague", "Rapid Putrefaction", e73, calm)).is_equal_approx(
		_ev("gf", "daemons_of_plague", "Rapid Putrefaction", e72, calm), EPS)

	var tough3 := _defender(4, 3, false, false)
	assert_float(_ev("gf", "daemons_of_lust", "Beautiful Pain", e73, tough3)).is_equal_approx(8.0 / 3.0, EPS)
	assert_float(_ev("gf", "daemons_of_lust", "Beautiful Pain", e73, calm)).is_equal_approx(
		_ev("gf", "daemons_of_lust", "Beautiful Pain", e72, calm), EPS)

	assert_float(_ev("gf", "rebel_guerrillas", "Wave of Discord", e73, shaken)).is_equal_approx(8.0 / 3.0, EPS)
	assert_float(_ev("gf", "rebel_guerrillas", "Wave of Discord", e73, calm)).is_equal_approx(
		_ev("gf", "rebel_guerrillas", "Wave of Discord", e72, calm), EPS)

	var def5 := _defender(5, 1, false, false)
	assert_float(_ev("gf", "alien_hives", "Overwhelming Strike", e73, def5)).is_equal_approx(32.0 / 9.0, EPS)
	assert_float(_ev("gf", "alien_hives", "Overwhelming Strike", e73, calm)).is_equal_approx(
		_ev("gf", "alien_hives", "Overwhelming Strike", e72, calm), EPS)


## Case 2 — Obliterate / Reap / Fragment widen the save window: a successful save of 5 re-rolls
## too, so the EV beats the sixes-only leg.
func test_the_widened_window_re_rolls_a_successful_five() -> void:
	var e73 := AiActRecorder.EPOCH_73_V36
	var tough3 := _defender(4, 3, false, false)
	var ob := _ev("gf", "daemons_of_lust", "Beautiful Pain", e73, tough3)
	assert_float(ob).is_equal_approx(8.0 / 3.0, EPS)
	assert_bool(ob > 7.0 / 3.0 + EPS).override_failure_message("the sixes-only leg would stop at 7/3").is_true()

	var shaken := _defender(4, 1, false, true)
	var reap := _ev("gf", "rebel_guerrillas", "Wave of Discord", e73, shaken)
	assert_float(reap).is_equal_approx(8.0 / 3.0, EPS)
	assert_bool(reap > 7.0 / 3.0 + EPS).override_failure_message("the sixes-only leg would stop at 7/3").is_true()

	var def5 := _defender(5, 1, false, false)
	var frag := _ev("gf", "alien_hives", "Overwhelming Strike", e73, def5)
	assert_float(frag).is_equal_approx(32.0 / 9.0, EPS)
	assert_bool(frag > 28.0 / 9.0 + EPS).override_failure_message("the sixes-only leg would stop at 28/9").is_true()

	assert_float(AiEv.block_chance_from(4, 0, true, 6)).is_equal_approx(AiEv.block_chance(4, 0, true), EPS)
	assert_bool(AiEv.block_chance_from(4, 0, true, 5) < AiEv.block_chance(4, 0, true)).is_true()


## Case 3 — the four documented no-ops leave the EV on the plain spell even with every target
## state they name switched on.
func test_the_four_no_op_tokens_stay_at_the_plain_spell_ev() -> void:
	var e73 := AiActRecorder.EPOCH_73_V36
	var e72 := AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var loaded := _defender(4, 3, true, true)
	for c: Array in [
		["gf", "blood_prime_brothers", "Blood Wound", 4.0],
		["gf", "battle_brothers", "Cerebral Trauma", 4.0],
		["gf", "machine_cults", "Searing Shrapnel", 2.0],
		["gf", "dwarf_guilds", "Smiting Rune", 2.0],
	]:
		var now := _ev(str(c[0]), str(c[1]), str(c[2]), e73, loaded)
		assert_float(now).is_equal_approx(float(c[3]), EPS)
		assert_float(now).is_equal_approx(_ev(str(c[0]), str(c[1]), str(c[2]), e72, loaded), EPS)


## Case 4 — at epoch 72 every one of the nine is a no-op (no 3.5 spell spells these tokens).
func test_every_new_token_is_a_no_op_at_epoch_72() -> void:
	var e72 := AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var loaded := _defender(5, 3, true, true)
	for c: Array in [
		["gf", "blessed_sisters", "Eternal Flame", 2.0],
		["gf", "daemons_of_plague", "Rapid Putrefaction", 5.0 / 3.0],
		["gf", "daemons_of_lust", "Beautiful Pain", 8.0 / 3.0],
		["gf", "rebel_guerrillas", "Wave of Discord", 2.5],
		["gf", "alien_hives", "Overwhelming Strike", 8.0 / 3.0],
		["gf", "blood_prime_brothers", "Blood Wound", 5.0],
		["gf", "battle_brothers", "Cerebral Trauma", 5.0],
		["gf", "machine_cults", "Searing Shrapnel", 8.0 / 3.0],
		["gf", "dwarf_guilds", "Smiting Rune", 8.0 / 3.0],
	]:
		assert_float(_ev(str(c[0]), str(c[1]), str(c[2]), e72, loaded)).is_equal_approx(float(c[3]), EPS)


## The split is 5 priced / 4 no-ops at 73, pinned on both twins (core: the same five test).
func test_the_73_split_is_five_priced_and_four_no_ops() -> void:
	var e73 := AiActRecorder.EPOCH_73_V36
	var e72 := AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var loaded := _defender(5, 3, true, true)
	for c: Array in [
		["gf", "blessed_sisters", "Eternal Flame", true],
		["gf", "daemons_of_plague", "Rapid Putrefaction", true],
		["gf", "daemons_of_lust", "Beautiful Pain", true],
		["gf", "rebel_guerrillas", "Wave of Discord", true],
		["gf", "alien_hives", "Overwhelming Strike", true],
		["gf", "blood_prime_brothers", "Blood Wound", false],
		["gf", "battle_brothers", "Cerebral Trauma", false],
		["gf", "machine_cults", "Searing Shrapnel", false],
		["gf", "dwarf_guilds", "Smiting Rune", false],
	]:
		var now := _ev(str(c[0]), str(c[1]), str(c[2]), e73, loaded)
		var old := _ev(str(c[0]), str(c[1]), str(c[2]), e72, loaded)
		if bool(c[3]):
			assert_bool(now > old + EPS).override_failure_message("%s must be priced at 73" % str(c[2])).is_true()
		else:
			assert_float(now).is_equal_approx(old, EPS)

	# The visible knobs: same names and defaults on the Rust twin.
	var purge := _facets("gf", "blessed_sisters", "Eternal Flame", e73)
	assert_int(int(purge.get("ap_vs_shaken", 0))).is_equal(2)
	var decimate := _facets("gf", "daemons_of_plague", "Rapid Putrefaction", e73)
	assert_bool(bool(decimate.get("bane_above_half", false))).is_true()
	var obliterate := _facets("gf", "daemons_of_lust", "Beautiful Pain", e73)
	assert_int(int(obliterate.get("bane_tough3_low", 0))).is_equal(5)
	assert_bool(bool(obliterate.get("ignores_regen", false))).is_true()
	var reap := _facets("gf", "rebel_guerrillas", "Wave of Discord", e73)
	assert_int(int(reap.get("bane_shaken_low", 0))).is_equal(5)
	var fragment := _facets("gf", "alien_hives", "Overwhelming Strike", e73)
	assert_int(int(fragment.get("bane_def56_low", 0))).is_equal(5)
	for c: Array in [
		["gf", "blood_prime_brothers", "Blood Wound"],
		["gf", "battle_brothers", "Cerebral Trauma"],
		["gf", "machine_cults", "Searing Shrapnel"],
		["gf", "dwarf_guilds", "Smiting Rune"],
	]:
		var f := _facets(str(c[0]), str(c[1]), str(c[2]), e73)
		for key: String in ["ap_vs_shaken", "bane_tough3_low", "bane_shaken_low", "bane_def56_low"]:
			assert_int(int(f.get(key, 0))).override_failure_message("%s must stay a no-op: %s" % [str(c[2]), key]).is_equal(0)
		for key: String in ["bane_above_half"]:
			assert_bool(bool(f.get(key, false))).override_failure_message("%s must stay a no-op: %s" % [str(c[2]), key]).is_false()
