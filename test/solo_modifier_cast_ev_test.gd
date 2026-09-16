extends GdUnitTestSuite
## D-MAGIC step 2b (parity with the core's #1012 `modifier_cast_ev_of`): a `def_mod` BUFF is priced
## in the bearer's DEFENSE ROLE — the nearest enemy's attack INTO the bearer — and SUMMED with the
## hit leg. On the pre-patch code the def_mod folded onto the NEAREST ENEMY's own defense, so a
## friendly +1 def buff priced NEGATIVE (-2/3) and the table AI never boosted it. Numbers (both
## units Q4, defense 4, one rifle 8x24" + one CCW, 9" gap, no long-range mod, no cover):
## baseline shooting EV 8 x 1/2 x 1/2 = 2.0; def leg: enemy into def 3: 4/3 - 2.0 = -2/3
## -> bearer gain +2/3; hit leg (+1 to hit): 8/3 - 2.0 = +2/3; both roles: +4/3.

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
		ow.attacks = int((w as Dictionary).get("attacks", 4))  # the hand numbers assume the 8-attack rifle; pass "attacks" explicitly
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


func test_def_mod_buff_prices_in_the_bearer_defense_role() -> void:
	# AI-side bearer 9" from the human-side enemy: +1 def is worth +2/3 (RED on main: -2/3).
	var bearer := _armed(2, [Vector3(9.0 * IN2M, 0, 0)], "Bearer",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0}])
	var enemy := _armed(1, [Vector3.ZERO], "Enemy",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0}])
	var sc := _controller([bearer, enemy])
	var entry := {"status": "modeled", "target": {"kind": "unit"},
		"effect": {"kind": "buff", "modifier": {"def_mod": 1}}}
	assert_float(sc._spell_ev_for(bearer, bearer, entry, bearer)) \
		.is_equal_approx(2.0 / 3.0, EPS)


func test_hit_buff_prices_on_the_bearer_own_attack() -> void:
	var bearer := _armed(2, [Vector3(9.0 * IN2M, 0, 0)], "Bearer",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0}])
	var enemy := _armed(1, [Vector3.ZERO], "Enemy",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0}])
	var sc := _controller([bearer, enemy])
	var entry := {"status": "modeled", "target": {"kind": "unit"},
		"effect": {"kind": "buff", "modifier": {"hit_mod": 1}}}
	assert_float(sc._spell_ev_for(bearer, bearer, entry, bearer)) \
		.is_equal_approx(2.0 / 3.0, EPS)


func test_hit_plus_def_buff_sums_both_roles() -> void:
	var bearer := _armed(2, [Vector3(9.0 * IN2M, 0, 0)], "Bearer",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0}])
	var enemy := _armed(1, [Vector3.ZERO], "Enemy",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0}])
	var sc := _controller([bearer, enemy])
	var entry := {"status": "modeled", "target": {"kind": "unit"},
		"effect": {"kind": "buff", "modifier": {"hit_mod": 1, "def_mod": 1}}}
	assert_float(sc._spell_ev_for(bearer, bearer, entry, bearer)) \
		.is_equal_approx(4.0 / 3.0, EPS)


func test_debuff_keeps_the_whole_modifier_fold() -> void:
	# -1 to hit debuff ON the human-side target: its best attack into OUR 9" unit drops
	# 2.0 -> 4/3, so the cast is worth +2/3 (unchanged by the patch — pin against drift).
	var target := _armed(1, [Vector3.ZERO], "Target", [{"name": "CCW", "range": 0}])
	var ours := _armed(2, [Vector3(9.0 * IN2M, 0, 0)], "Ours",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0}])
	var caster := _armed(2, [Vector3(18.0 * IN2M, 0, 0)], "Caster",
		[{"name": "Rifle", "range": 24, "attacks": 8}, {"name": "CCW", "range": 0}])
	var sc := _controller([target, ours, caster])
	var entry := {"status": "modeled", "target": {"kind": "unit"},
		"effect": {"kind": "debuff", "modifier": {"hit_mod": -1}}}
	assert_float(sc._spell_ev_for(caster, caster, entry, target)) \
		.is_equal_approx(2.0 / 3.0, EPS)
