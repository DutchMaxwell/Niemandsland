extends GdUnitTestSuite
## W-P1 cent fixes (parity coverage table 2026-08-20): three wired-but-unread
## or half-stamped rules reach the lab's dice math.
## 1. Unstoppable bypasses Regeneration in profile_ev (flag was parsed, never read).
## 2. UNIT-level Bane/Lacerate/Rending/Unstoppable fold into sim profiles.
## 3. Fatigue = unmodified natural 6 (no modifier pipeline), and the DEFENDER
##    is stamped fatigued after striking back in resolve().

const IN2M := 0.0254


func _profile(unstoppable := false, rending := false) -> Dictionary:
	return {"name": "Claw", "range": 0, "attacks": 6.0, "ap": 0,
		"unstoppable": unstoppable, "rending": rending, "bane": false}


func test_unstoppable_bypasses_regeneration_in_ev() -> void:
	var att := {"quality": 4, "models": 1, "tough": 1}
	var regen_def := {"quality": 4, "defense": 4, "tough": 1, "models": 5,
		"regeneration": true, "regen_target": 5}
	var plain: float = AiEv.profile_ev(_profile(false), att, regen_def, 0.0, true)
	var unstop: float = AiEv.profile_ev(_profile(true), att, regen_def, 0.0, true)
	# Regeneration ignores 1/3 of wounds (5+) — the Unstoppable volley must NOT
	# pay that tax: strictly more expected wounds, ratio ~1/(1-1/3).
	assert_bool(unstop > plain * 1.2).is_true()
	# Against a defender WITHOUT Regeneration both volleys are identical.
	var no_regen := {"quality": 4, "defense": 4, "tough": 1, "models": 5}
	assert_float(AiEv.profile_ev(_profile(true), att, no_regen, 0.0, true)) \
		.is_equal_approx(AiEv.profile_ev(_profile(false), att, no_regen, 0.0, true), 0.0001)


func test_fatigued_attacker_hits_only_on_unmodified_six() -> void:
	var fat := {"quality": 3, "models": 1, "tough": 1, "fatigued": true}
	var fresh := {"quality": 3, "models": 1, "tough": 1}
	var soft := {"quality": 4, "defense": 5, "tough": 1, "models": 5}
	var ev_fat: float = AiEv.profile_ev(_profile(), fat, soft, 0.0, true)
	var ev_fresh: float = AiEv.profile_ev(_profile(), fresh, soft, 0.0, true)
	# Quality 3+ hits 4/6; fatigued hits 1/6 — the ratio must collapse to ~1/4.
	assert_float(ev_fat / ev_fresh).is_equal_approx(0.25, 0.02)
	# And a to-hit BONUS (evasive=false, spell_mod would help) must not move the
	# fatigued target: natural 6 stays natural 6 even for quality 2 elites.
	var elite_fat := {"quality": 2, "models": 1, "tough": 1, "fatigued": true}
	assert_float(AiEv.profile_ev(_profile(), elite_fat, soft, 0.0, true)) \
		.is_equal_approx(ev_fat, 0.0001)


func _sim_unit(id: String, pid: int, n: int, rules: Array) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = id
	u.unit_properties = {"player_id": pid, "name": id, "quality": 4, "defense": 4,
		"special_rules": rules}
	var od := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Blade"
	w.range_value = 0
	w.attacks = 2
	od.weapons = [w] as Array[OPRApiClient.OPRWeapon]
	u.source_type = "opr"
	u.source_data = od
	for i in range(n):
		var m: ModelInstance = ModelInstance.new()
		m.unit = u
		m.is_alive = true
		m.node = auto_free(Node3D.new())
		add_child(m.node)
		m.node.global_position = Vector3(float(i) * IN2M, 0, 0)
		u.models.append(m)
	return u


func test_unit_level_lacerate_reaches_sim_profiles() -> void:
	var laced := _sim_unit("Laced", 1, 3, ["Lacerate"])
	var plain := _sim_unit("Plain", 1, 3, [])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Laced": laced, "Plain": plain}
	var state := BattleSim.capture(army)
	var p_laced: Array = BattleSim._profiles_of(state["units"]["Laced"], true)
	var p_plain: Array = BattleSim._profiles_of(state["units"]["Plain"], true)
	assert_bool(bool((p_laced[0] as Dictionary).get("bane", false))).is_true()
	assert_bool(bool((p_plain[0] as Dictionary).get("bane", false))).is_false()


func test_resolve_stamps_defender_fatigue_after_strike_back() -> void:
	var a := _sim_unit("A", 1, 3, [])
	var b := _sim_unit("B", 2, 3, [])
	for i in range(3):
		(b.models[i] as ModelInstance).node.global_position = Vector3(float(i) * IN2M, 0, 0.5 * IN2M)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"A": a, "B": b}
	var state := BattleSim.capture(army)
	var next := BattleSim.resolve(state, {"unit": "A", "kind": AiDecision.Action.CHARGE, "charge": "B"})
	assert_bool(bool((next["units"]["A"] as Dictionary)["fatigued"])).is_true()
	assert_bool(bool((next["units"]["B"] as Dictionary)["fatigued"])).is_true()
