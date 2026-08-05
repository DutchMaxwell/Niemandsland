extends GdUnitTestSuite
## #321 — the futile-charge gate: a unit whose melee cannot plausibly hurt a target (expected wounds
## under SoloController.FUTILE_CHARGE_EV) must neither charge it nor, when it is a PURE melee unit
## with a hurtable alternative on the table, keep closing on it. Community evidence (playtest log
## 2026-08-05): Q6-melee Iron Veterans and Dwarf Warriors rushed a Tough(15) Def(2+) Heavy Battle
## Tank for three rounds — near-zero expected wounds a charge, activations wasted.

const IN2M := 0.0254


func _unit(pid: int, positions: Array, rules: Array = [], uid: String = "",
		quality: int = 4, defense: int = 4) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid if uid != "" else "p%d_%d" % [pid, positions.size()]
	u.unit_properties = {"player_id": pid, "name": (uid if uid != "" else "U%d" % pid),
		"quality": quality, "defense": defense, "special_rules": rules}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


func _army(units: Array) -> OPRArmyManager:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	army.current_round = 1
	return army


func _controller(units: Array) -> SoloController:
	var sc: SoloController = auto_free(SoloController.new())
	add_child(sc)
	sc.setup(_army(units), null, null, 1, 2)
	return sc


func _arm(u: GameUnit, weapons: Array) -> void:
	var opr := OPRApiClient.OPRUnit.new()
	for w in weapons:
		var ow := OPRApiClient.OPRWeapon.new()
		ow.name = str((w as Dictionary).get("name", "W"))
		ow.range_value = int((w as Dictionary).get("range", 0))
		ow.attacks = int((w as Dictionary).get("attacks", 2))
		ow.count = 1
		for r in (w as Dictionary).get("rules", []):
			ow.special_rules.append(str(r))
		opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr


## Q6 hands vs a Tough(15) Def(2+) tank ≈ 0.08 expected wounds — futile. The same fists against
## ordinary 4+/4+ infantry trade well above the floor — not futile.
func test_futility_floor_separates_tank_from_infantry() -> void:
	var grunts := _unit(2, [Vector3.ZERO], [], "Grunts", 6, 4)
	_arm(grunts, [{"name": "CCW", "range": 0, "attacks": 3, "rules": []}])
	var tank := _unit(1, [Vector3(10.0 * IN2M, 0, 0)], ["Tough(15)"], "Tank", 3, 2)
	var infantry := _unit(1, [Vector3(20.0 * IN2M, 0, 0)], [], "Infantry")
	var sc := _controller([grunts, tank, infantry])
	assert_bool(sc.melee_futile_against(grunts, tank)).is_true()
	assert_bool(sc.melee_futile_against(grunts, infantry)).is_false()


func test_unit_without_melee_profiles_is_trivially_futile() -> void:
	var arty := _unit(2, [Vector3.ZERO], [], "Battery")
	_arm(arty, [{"name": "Gun", "range": 30, "attacks": 2, "rules": []}])
	var infantry := _unit(1, [Vector3(10.0 * IN2M, 0, 0)], [], "Infantry")
	var sc := _controller([arty, infantry])
	assert_bool(sc.melee_futile_against(arty, infantry)).is_true()


## The retarget helper: with the tank NEAREST and hurtable infantry farther out, the pure melee
## unit's alternative is the infantry; with ONLY the tank on the table there is no alternative.
func test_nearest_hurtable_enemy_skips_the_tank() -> void:
	var grunts := _unit(2, [Vector3.ZERO], [], "Grunts", 6, 4)
	_arm(grunts, [{"name": "CCW", "range": 0, "attacks": 3, "rules": []}])
	var tank := _unit(1, [Vector3(10.0 * IN2M, 0, 0)], ["Tough(15)"], "Tank", 3, 2)
	var infantry := _unit(1, [Vector3(30.0 * IN2M, 0, 0)], [], "Infantry")
	var sc := _controller([grunts, tank, infantry])
	assert_object(sc.nearest_hurtable_enemy(grunts)).is_same(infantry)
	var sc2 := _controller([_dup_armed_grunts(), _unit(1, [Vector3(10.0 * IN2M, 0, 0)], ["Tough(15)"], "Tank", 3, 2)])
	assert_object(sc2.nearest_hurtable_enemy(sc2.army_manager.game_units.values()[0])).is_null()


func _dup_armed_grunts() -> GameUnit:
	var g := _unit(2, [Vector3.ZERO], [], "Grunts2", 6, 4)
	_arm(g, [{"name": "CCW", "range": 0, "attacks": 3, "rules": []}])
	return g


## End to end through _act: the pure melee unit next to the tank neither charges it (the tree never
## sees "enemy_in_charge") nor keeps it as its move target while hurtable infantry exists — and both
## decisions surface as rule notes (rules-must-log).
func test_act_refuses_futile_charge_and_retargets() -> void:
	var grunts := _unit(2, [Vector3.ZERO], [], "Grunts", 6, 4)
	_arm(grunts, [{"name": "CCW", "range": 0, "attacks": 3, "rules": []}])
	var tank := _unit(1, [Vector3(8.0 * IN2M, 0, 0)], ["Tough(15)"], "Tank", 3, 2)
	var infantry := _unit(1, [Vector3(30.0 * IN2M, 0, 0)], [], "Infantry")
	var sc := _controller([grunts, tank, infantry])
	var report := sc._act(grunts)
	assert_object(report.get("target")).is_same(infantry)
	var texts := PackedStringArray()
	for n in report.get("rule_notes", []):
		texts.append(str((n as Dictionary).get("text", "")))
	assert_str("\n".join(texts)).contains("retargets Infantry")


## A hybrid unit (guns + fists) KEEPS the futile target for shooting — the retarget is melee-only.
func test_hybrid_unit_keeps_target_but_never_charges_it() -> void:
	var vets := _unit(2, [Vector3.ZERO], [], "Vets", 4, 3)
	_arm(vets, [{"name": "Rifle", "range": 24, "attacks": 1, "rules": []},
		{"name": "CCW", "range": 0, "attacks": 1, "rules": []}])
	var tank := _unit(1, [Vector3(8.0 * IN2M, 0, 0)], ["Tough(15)"], "Tank", 3, 2)
	var sc := _controller([vets, tank])
	var report := sc._act(vets)
	assert_object(report.get("target")).is_same(tank)
	# The tree may advance/shoot, but a charge into the tank must never be the plan.
	assert_int(int(report.get("action", -1))).is_not_equal(AiDecision.Action.CHARGE)
