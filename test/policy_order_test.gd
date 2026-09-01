extends GdUnitTestSuite
## NML-1158b step 6 — the GDScript ORDER seam (design §7 step 6): default
## (`AiPlanner.policy_mode == "off"`) leaves `plan_with_rollout` byte-identical
## to the hand order even with a net ARMED; "order" re-ranks WITHIN one
## unit's own menu by `PolicyOrder`'s net, exactly — never touching which
## unit owns which slot (design §1's cross-menu rule).

const IN2M := 0.0254


func _armed(pid: int, positions: Array, uid: String, weapons: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = 1
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


## A lone P2 "Striker" 20" from an unclaimed marker, nothing else to
## activate on either side: its menu is HOLD plus a RUSH toward the marker —
## two DISTINCT kinds, which is all the reorder needs to prove itself.
func _state() -> Dictionary:
	var gunner := _armed(1, [Vector3(60.0 * IN2M, 0, 0)], "Gunner", [{"name": "CCW", "range": 0}])
	var striker := _armed(2, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0)], "Striker",
		[{"name": "CCW", "range": 0}])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Gunner": gunner, "Striker": striker}
	return BattleSim.capture(army, func() -> Array: return [Vector3(20.0 * IN2M, 0, 0)],
		func(_i: int) -> int: return 0, 1, 4)


## `-kind`: HOLD(0) logit 100, RUSH(2) logit 98 — HOLD ranks ABOVE RUSH,
## opposite of the marker-proximity bonus the hand eval favours here, so
## ORDER mode has to move at least one of Striker's own two slots.
func _reverse_kind_net() -> Dictionary:
	var state_dim := 93
	var act_dim := 20
	var w1: Array = []
	for _i in range(state_dim + act_dim):
		w1.append([0.0])
	for k in range(4):
		(w1[state_dim + k] as Array)[0] = -float(k)
	return {"schema": "policy_net/1", "state_dim": state_dim, "act_dim": act_dim, "hidden": 1,
		"w1": w1, "b1": [100.0], "w2": [1.0], "b2": 0.0}


func before_test() -> void:
	AiPlanner.opener_seat = false
	AiPlanner.policy_mode = "off"
	AiPlanner.trace_enabled = true
	PolicyOrder.set_net({})


func after_test() -> void:
	AiPlanner.policy_mode = "off"
	AiPlanner.trace_enabled = false
	PolicyOrder.set_net({})


func test_default_off_ignores_an_armed_net() -> void:
	AiPlanner.plan_with_rollout(_state(), 2)
	var bare_scored: Array = (AiPlanner.trace["scored"] as Array).duplicate(true)

	PolicyOrder.set_net(_reverse_kind_net())   # armed, mode STILL off
	AiPlanner.plan_with_rollout(_state(), 2)
	assert_that(AiPlanner.trace["scored"]).is_equal(bare_scored)


func test_order_mode_sorts_one_units_menu_by_the_nets_logit() -> void:
	PolicyOrder.set_net(_reverse_kind_net())
	AiPlanner.policy_mode = "order"
	AiPlanner.plan_with_rollout(_state(), 2)
	var kinds: Array = []
	for row in (AiPlanner.trace["scored"] as Array):
		if str((row as Dictionary)["unit"]) == "Striker":
			kinds.append(int((row as Dictionary)["kind"]))
	assert_int(kinds.size()).is_greater_equal(2)
	var distinct := {}
	for k in kinds:
		distinct[k] = true
	assert_int(distinct.size()).is_greater(1)   # more than one KIND, or there is nothing to sort
	for i in range(kinds.size() - 1):
		# `-kind` DESCENDING logit == kind ASCENDING — exactly the net's order.
		assert_int(kinds[i]).is_less_equal(kinds[i + 1])
