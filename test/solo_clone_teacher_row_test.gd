extends GdUnitTestSuite
## TR (NML-1009, wave C8): the IMITATION ROW must never teach a move the body
## refused. _solve_clone writes the row from its own argmax; only THEN does
## _act's adoption re-gate (NML-1026) turn an illegal charge into a Rush.

const IN2M := 0.0254


func _unit(pid: int, pos: Vector3, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	# 10 mm bases: the re-gate measures the BASE-EDGE gap (centre distance minus
	# 0.394"), the menu subtracts BattleSim.CONTACT_IN (1.0") — that IS the lever.
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": [], "base_size_round": 10}
	var m := ModelInstance.new()
	m.unit = u
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	m.node = n
	u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	var cc := OPRApiClient.OPRWeapon.new()
	cc.name = "CCW"
	cc.range_value = 0   # melee profile: without one the menu offers no charge
	cc.attacks = 4
	opr.weapons.append(cc)
	u.source_type = "opr"
	u.source_data = opr
	return u


## A policy scoring CHARGE 1.0 and all else 0.0: the clone's argmax IS the charge.
func before() -> void:
	var act_w1: Array = []
	for i in range(18):
		act_w1.append([1.0 if i == AiDecision.Action.CHARGE else 0.0])
	SoloController._teacher_rows_env = 1
	SoloController._menu_probe_env = 1
	AiClone._seat_nets = {}
	AiClone.set_net({"in_dim": 1, "act_dim": 18,
		"row_w1": [[0.0]], "row_b1": [0.0], "row_w2": [[0.0]], "row_b2": [0.0],
		"state_w1": [[0.0], [0.0], [0.0], [0.0]], "state_b1": [0.0],
		"act_w1": act_w1, "act_b1": [0.0], "head_w1": [[0.0], [1.0]],
		"head_b1": [0.0], "head_w2": [1.0], "head_b2": 0.0})


## PROCESS-wide statics: left set, the rest of the suite inherits a clone brain.
func after() -> void:
	SoloController._teacher_rows_env = -1
	SoloController._menu_probe_env = -1
	AiClone._net_cache = {}
	AiClone._tried = false
	AiClone._seat_nets = {}


func test_the_teacher_row_never_learns_a_charge_the_body_refused() -> void:
	var grunts := _unit(2, Vector3.ZERO, "Grunts")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Grunts": grunts, "Foe": _unit(1, Vector3(12.8 * IN2M, 0, 0), "Foe")}
	army.current_round = 1
	var sc: SoloController = auto_free(SoloController.new())
	add_child(sc)
	sc.setup(army, null, null, 1, 2)
	sc.game_rounds = 4
	sc.objectives_provider = func() -> Array: return [Vector3(0, 0, 20.0 * IN2M)]
	sc.objective_owner_of = func(_i: int) -> int: return 0
	assert_bool(sc._clone_active()).is_true()
	var report := sc._act(grunts)
	# A (no-idle guard): the re-gate FIRED, so B cannot pass on a charge-free turn.
	assert_int(int(report["action"])).is_equal(AiDecision.Action.RUSH)
	var rows := sc.decision_log.filter(func(r: Dictionary) -> bool:
		return str(r.get("kind", "")) == "teacher_row")
	assert_int(rows.size()).is_equal(1)
	var data: Dictionary = (rows[0] as Dictionary)["data"]
	var idx := int(data["teacher"])
	var learned := -1 if idx < 0 else int(((data["menu"] as Array)[idx] as Dictionary)["kind"])
	# B: what the corpus learns must not be the charge the body just refused.
	assert_int(learned).is_not_equal(AiDecision.Action.CHARGE)
