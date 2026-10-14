extends GdUnitTestSuite
## The battle-log intent for ADVANCE must follow the real direction: the retreat point says
## "fall back", every move toward the enemy (safe advance, second wave, advance+shoot) does not.

const IN2M := 0.0254


func _armed(pid: int, pos: Vector3, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4, "special_rules": []}
	var m := ModelInstance.new()
	m.is_alive = true
	m.wounds_current = 1
	m.unit = u
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	m.node = n
	u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	var ow := OPRApiClient.OPRWeapon.new()
	ow.name = "Rifle"
	ow.range_value = 24
	ow.attacks = 4
	ow.count = 1
	opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr
	return u


func test_advance_label_follows_direction() -> void:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var me := _armed(2, Vector3.ZERO, "Me")
	var foe := _armed(1, Vector3(30.0 * IN2M, 0, 0), "Foe")
	army.game_units = {"Me": me, "Foe": foe}
	var state := BattleSim.capture(army, func() -> Array: return [], func(_i: int) -> int: return 0)
	var toward := {"unit": "Me", "kind": AiDecision.Action.ADVANCE, "dest": Vector3(20.0 * IN2M, 0, 0)}
	var toward_shoot := {"unit": "Me", "kind": AiDecision.Action.ADVANCE, "dest": Vector3(30.0 * IN2M, 0, 0), "shoot": "Foe"}
	assert_str(AiPlanner._describe(state, toward)).is_equal("advance")
	assert_str(AiPlanner._describe(state, toward_shoot)).is_equal("advance and shoot Foe")
	var retreats := AiPlanner.candidates(state, "Me").filter(
		func(c: Dictionary) -> bool: return int(c["kind"]) == AiDecision.Action.ADVANCE and (c["dest"] as Vector3).x < 0.0)
	assert_int(retreats.size()).is_greater(0)
	for c in retreats:
		assert_str(AiPlanner._describe(state, c)).is_equal("fall back")
