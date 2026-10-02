extends GdUnitTestSuite
## NML-1010 D6a — Attack & Defend deployment distance gates on the table: the pure referee
## (SoloController.gate_violation), the AI deployer honouring min_from_enemy_in and
## max_from_friend_in (the first unit is free of the friend gate, R12a).

const IN2M := 0.0254
const ZONE := Rect2(Vector2(-36.0 * IN2M, -24.0 * IN2M), Vector2(72.0 * IN2M, 12.0 * IN2M))


func _unit(pid: int, count: int, uid: String, at := Vector3.ZERO) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4, "special_rules": []}
	for _i in range(count):
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = at
		m.node = n
		u.models.append(m)
	return u


func _controller(units: Array) -> SoloController:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	army.current_round = 1
	var sc: SoloController = auto_free(SoloController.new())
	add_child(sc)
	sc.setup(army, null, null, 1, 2)
	return sc


func _base(x_in: float, z_in: float, r := 0.0) -> Dictionary:
	return {"pos": Vector2(x_in * IN2M, z_in * IN2M), "radius": r}


func test_the_pure_referee_names_the_broken_gate() -> void:
	var gates := {"min_from_enemy_in": 12, "min_from_marker_in": 6, "max_from_friend_in": 6}
	var me := [_base(0, 0)]
	assert_str(SoloController.gate_violation(gates, me, [_base(11, 0)], [], [])).contains("more than 12\" from enemy")
	assert_str(SoloController.gate_violation(gates, me, [_base(13, 0)], [], [])).is_equal("")
	assert_str(SoloController.gate_violation(gates, me, [], [], [Vector2(5.0 * IN2M, 0)])).contains("from the objective")
	assert_str(SoloController.gate_violation(gates, me, [], [_base(20, 0)], [])).contains("within 6\" of a friendly unit")
	assert_str(SoloController.gate_violation(gates, me, [], [_base(5, 0)], [])).is_equal("")
	assert_str(SoloController.gate_violation(gates, me, [], [], [])).is_equal("")   # first unit: free of the friend gate
	assert_str(SoloController.gate_violation({}, me, [_base(1, 0)], [], [])).is_equal("")


func _deploy_against_an_enemy_in_the_zone(gates: Dictionary, tag: String) -> float:
	var enemy := _unit(1, 1, "E_" + tag, Vector3(14.0 * IN2M, 0.0, -18.0 * IN2M))
	var mine: Array = []
	for i in range(6):   # enough units that one takes the centre section by the objective
		mine.append(_unit(2, 2, "U%d_%s" % [i, tag]))
	var sc := _controller(mine + [enemy])
	sc.deploy_army(ZONE, [Vector2(0.0, -18.0 * IN2M)], Callable(), Callable(), 11, Callable(), gates)
	var nearest := INF
	for u in mine:
		for m in (u as GameUnit).models:
			var p: Vector3 = (m as ModelInstance).node.global_position
			nearest = minf(nearest, Vector2(p.x, p.z).distance_to(Vector2(14.0 * IN2M, -18.0 * IN2M)))
	return nearest / IN2M


func test_the_ai_keeps_more_than_the_gate_from_enemy_models() -> void:
	assert_float(_deploy_against_an_enemy_in_the_zone({}, "free")).is_less(12.0)   # control: the ungated AI stands right beside it
	assert_float(_deploy_against_an_enemy_in_the_zone({"min_from_enemy_in": 12}, "gated")).is_greater(12.0)


func test_every_ai_unit_after_the_first_stays_within_reach_of_a_friend() -> void:
	var units: Array = []
	for i in range(4):
		units.append(_unit(2, 2, "F%d" % i))
	var sc := _controller(units)
	sc.deploy_army(ZONE, [Vector2(30.0 * IN2M, -18.0 * IN2M)], Callable(), Callable(), 11, Callable(), {"max_from_friend_in": 6})
	var bases := sc.bases_of_slot(2)
	var lonely := 0
	for u in units:
		var mine := sc.bases_of_slot(2, u as GameUnit)
		var mm := sc.bases_of_slot(2)
		var own: Array = []
		for m in (u as GameUnit).models:
			var p: Vector3 = (m as ModelInstance).node.global_position
			own.append({"pos": Vector2(p.x, p.z), "radius": 0.0})
		if not SoloController.gate_violation({"max_from_friend_in": 6}, own, [], mine, []).is_empty():
			lonely += 1
	assert_int(bases.size()).is_equal(8)
	assert_int(lonely).override_failure_message("%d units out of the 6\" reach" % lonely).is_equal(0)
