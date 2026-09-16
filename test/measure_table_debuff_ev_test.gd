extends GdUnitTestSuite
## Measurement-only suite (do not merge): prints the table's `_spell_ev_for` for a `-1 hit` and a
## `-1 def` DEBUFF on an enemy target, over four board shapes, plus the two legs
## (`_modifier_delta` on the caster's own attack, and the negated `_modifier_value_on_attack` on
## the target's own attack) so the log shows which branch produced each number. Fixture copied
## from test/solo_modifier_cast_ev_test.gd (#1014). Shapes:
##   (a) target rifle 8 att at 9" from our unit, caster 18" away
##   (b) target CCW-only at 9"
##   (c) target CCW-only at 1" (melee range)
##   (d) target rifle 4 att at 9"
## Hand number if the debuff degraded the target's attack into us:
##   8 x 1/2 x 1/2 = 2.0 -> 8 x 1/3 x 1/2 = 4/3 -> value +2/3.

const IN2M := 0.0254


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


## Prints, for both {"hit_mod": -1} and {"def_mod": -1}: the table's spell EV, the
## beneficiary-"attackers" leg (caster's own attack into the target), and the negated
## value-on-attack leg (the target's own degraded attack into our nearest unit).
func _measure(shape: String, target: GameUnit, caster: GameUnit, sc: SoloController) -> void:
	for eff_key in ["hit_mod", "def_mod"]:
		var effect := {"kind": "debuff", "modifier": {eff_key: -1}}
		var entry := {"status": "modeled", "target": {"kind": "unit"}, "effect": effect}
		var ev := sc._spell_ev_for(caster, caster, entry, target)
		var delta := sc._modifier_delta(caster, target, effect)
		var value := -sc._modifier_value_on_attack(target, effect, true)
		print("[EVDEBUFF] shape=%s effect=%s=-1 | _spell_ev_for=%.4f | _modifier_delta(caster,target)=%.4f | -_modifier_value_on_attack(target,flip)=%.4f"
			% [shape, eff_key, ev, delta, value])


func test_shape_a_rifle8_target_at_9in_caster_18in() -> void:
	var target := _armed(1, [Vector3.ZERO], "TargetA",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0}])
	var our := _armed(2, [Vector3(9.0 * IN2M, 0, 0)], "OurA",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0}])
	var caster := _armed(2, [Vector3(18.0 * IN2M, 0, 0)], "CasterA",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0}])
	var sc := _controller([target, our, caster])
	_measure("a_rifle8@9in_caster18in", target, caster, sc)
	assert_bool(true).is_true()


func test_shape_b_ccw_only_target_at_9in() -> void:
	var target := _armed(1, [Vector3.ZERO], "TargetB", [{"name": "CCW", "range": 0}])
	var our := _armed(2, [Vector3(9.0 * IN2M, 0, 0)], "OurB",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0}])
	var caster := _armed(2, [Vector3(18.0 * IN2M, 0, 0)], "CasterB",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0}])
	var sc := _controller([target, our, caster])
	_measure("b_ccw_only@9in", target, caster, sc)
	assert_bool(true).is_true()


func test_shape_c_ccw_only_target_at_1in() -> void:
	var target := _armed(1, [Vector3.ZERO], "TargetC", [{"name": "CCW", "range": 0}])
	var our := _armed(2, [Vector3(1.0 * IN2M, 0, 0)], "OurC",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0}])
	var caster := _armed(2, [Vector3(18.0 * IN2M, 0, 0)], "CasterC",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0}])
	var sc := _controller([target, our, caster])
	_measure("c_ccw_only@1in", target, caster, sc)
	assert_bool(true).is_true()


func test_shape_d_rifle4_target_at_9in() -> void:
	var target := _armed(1, [Vector3.ZERO], "TargetD",
		[{"name": "Rifle", "range": 24, "attacks": 4}, {"name": "CCW", "range": 0}])
	var our := _armed(2, [Vector3(9.0 * IN2M, 0, 0)], "OurD",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0}])
	var caster := _armed(2, [Vector3(18.0 * IN2M, 0, 0)], "CasterD",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0}])
	var sc := _controller([target, our, caster])
	_measure("d_rifle4@9in", target, caster, sc)
	assert_bool(true).is_true()
