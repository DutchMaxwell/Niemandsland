extends GdUnitTestSuite
## D-MAGIC step 2c: the table's DEBUFF branch prices a penalty by the target's BEST BASELINE
## attack into our nearest unit (max over USABLE modes of baseline minus same-mode malus), and a
## `def_mod` debuff is priced from OUR side (our nearest unit's attack INTO the target with the
## target's defense worsened), sign = caster gain. Fixture copied from the measurement suite
## (branch measure/table-debuff-ev, draft PR #1018), which copied #1014's. On main the
## whole-modifier fold read (measured, CI):
##   rifle 8-attack target @9": +1/3   (maxf over the deltas picked the CCW leg that loses least)
##   CCW-only target @1":      -0.0   (empty ranged mode's hard-coded 0.0 masked the melee leg)
##   CCW-only target @9":      -0.0
##   `def_mod` -1 @9":         -2/3   (malus folded onto OUR unit's defense; NEGATIVE = "don't cast")
## Hand numbers (both units Q4, defense 4, no cover, no long-range mod):
##   rifle8 @9": baseline shoot 8 x 1/2 x 1/2 = 2.0; with -1 hit 8 x 1/3 x 1/2 = 4/3 -> +2/3
##   (the CCW melee leg is NOT usable at 9" — "Who Can Strike"; empty ranged mode is not a mode)
##   CCW-only @1": melee 4 x 1/2 x 1/2 = 1.0; with -1 hit 4 x 1/3 x 1/2 = 2/3 -> +1/3
##   CCW-only @9": shooting unusable (range 0) AND melee unusable (no strike reach) — both modes
##   unusable is legitimately 0.0: a target that cannot attack us cannot be made worse
##   def_mod -1 @9" (AiSpell.spell_modifier_delta, ai_spell.gd:272-277): def2["defense"] =
##   clamp(4 - (-1)) = 5, so the target's save goes 4+ (1/2) -> 5+ (1/3); our rifle 8:
##   baseline 8 x 1/2 x 1/2 = 2.0, with the worsened defense 8 x 1/2 x 1/3 = 4/3 -> delta +2/3.

const IN2M := 0.0254
const EPS := 0.0001


func _armed(pid: int, positions: Array, uid: String, weapons: Array,
		rules: Array = [], wounds_now := 1, quality := 4, defense := 4) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": quality,
		"defense": defense, "special_rules": rules}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = wounds_now
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	for w in weapons:
		var ow := OPRApiClient.OPRWeapon.new()
		ow.name = str((w as Dictionary).get("name", "W"))
		ow.range_value = int((w as Dictionary).get("range", 0))
		ow.attacks = int((w as Dictionary).get("attacks", 4))
		ow.count = 1
		opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr
	return u


func _controller(units: Array) -> SoloController:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	var sc := SoloController.new()
	sc.army_manager = army
	auto_free(sc)
	return sc


func _debuff_entry(modifier: Dictionary) -> Dictionary:
	return {"status": "modeled", "target": {"kind": "unit"},
		"effect": {"kind": "debuff", "modifier": modifier}}


func test_hit_debuff_rifle8_target_at_9in_prices_the_best_baseline_mode() -> void:
	# RED on main (+1/3: maxf over the deltas picked the CCW leg that loses least).
	var target := _armed(1, [Vector3.ZERO], "TargetA",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0, "attacks": 4}])
	var our := _armed(2, [Vector3(9.0 * IN2M, 0, 0)], "OurA",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0, "attacks": 4}])
	var caster := _armed(2, [Vector3(18.0 * IN2M, 0, 0)], "CasterA",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0, "attacks": 4}])
	var sc := _controller([target, our, caster])
	assert_float(sc._spell_ev_for(caster, caster, _debuff_entry({"hit_mod": -1}), target)) \
		.is_equal_approx(2.0 / 3.0, EPS)


func test_hit_debuff_ccw_only_target_in_melee_range_prices_the_melee_leg() -> void:
	# RED on main (-0.0: the empty ranged mode's 0.0 masked the melee leg).
	var target := _armed(1, [Vector3.ZERO], "TargetB", [{"name": "CCW", "range": 0, "attacks": 4}])
	var our := _armed(2, [Vector3(1.0 * IN2M, 0, 0)], "OurB",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0, "attacks": 4}])
	var caster := _armed(2, [Vector3(18.0 * IN2M, 0, 0)], "CasterB",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0, "attacks": 4}])
	var sc := _controller([target, our, caster])
	assert_float(sc._spell_ev_for(caster, caster, _debuff_entry({"hit_mod": -1}), target)) \
		.is_equal_approx(1.0 / 3.0, EPS)


func test_hit_debuff_ccw_only_target_out_of_reach_is_legitimately_zero() -> void:
	# 0 on main too — the regression guard: both modes unusable must stay 0.0 (not negative).
	var target := _armed(1, [Vector3.ZERO], "TargetC", [{"name": "CCW", "range": 0, "attacks": 4}])
	var our := _armed(2, [Vector3(9.0 * IN2M, 0, 0)], "OurC",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0, "attacks": 4}])
	var caster := _armed(2, [Vector3(18.0 * IN2M, 0, 0)], "CasterC",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0, "attacks": 4}])
	var sc := _controller([target, our, caster])
	assert_float(sc._spell_ev_for(caster, caster, _debuff_entry({"hit_mod": -1}), target)) \
		.is_equal_approx(0.0, EPS)


func test_def_mod_debuff_prices_our_attack_into_the_target() -> void:
	# RED on main (-2/3: the malus folded onto OUR unit's defense and priced the cast negative).
	# Hand derivation in the file header comment (AiSpell.spell_modifier_delta, ai_spell.gd:272-277).
	var target := _armed(1, [Vector3.ZERO], "TargetD",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0, "attacks": 4}])
	var our := _armed(2, [Vector3(9.0 * IN2M, 0, 0)], "OurD",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0, "attacks": 4}])
	var caster := _armed(2, [Vector3(18.0 * IN2M, 0, 0)], "CasterD",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0, "attacks": 4}])
	var sc := _controller([target, our, caster])
	assert_float(sc._spell_ev_for(caster, caster, _debuff_entry({"def_mod": -1}), target)) \
		.is_equal_approx(2.0 / 3.0, EPS)
