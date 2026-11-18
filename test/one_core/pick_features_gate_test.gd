extends GdUnitTestSuite
## P4.D-65 (gate G2): `_planner_pick_unit` computes the per-pick position features (AiMissionEval.features +
## BattleSim.reply_threat, stamped by `_with_reserves`) only when a consumer is attached: the harness capture
## (`decision_sink`). The shipped game has none. Everything the player sees is unchanged.
## Constructed: bare units, GDScript search (core off). `_with_reserves` reads `ambush_reserve` once per feature
## computation, so a spy unit in that list counts the computations.

const IN2M := 0.0254


## Counts how often `_with_reserves` looks at it = how often the features were computed.
class SpyUnit extends GameUnit:
	var looks := 0
	func is_destroyed() -> bool:
		looks += 1
		return false


func after_test() -> void:
	BattleSim._core_env = -1
	OS.unset_environment("NML_AIFIX")
	OS.unset_environment("NML_EVAL_VARIANT")
	AiPlanner.opener_by_finish = false
	AiPlanner.no_end_threat = false
	BattleSim.morale_by_probability = false
	BattleSim.reply_v2 = false
	BattleSim.reply_skip_activated = false
	BattleSim.reply_hold_gate = false


func _unit(pid: int, positions: Array, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4, "special_rules": []}
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
	var ow := OPRApiClient.OPRWeapon.new()
	ow.name = "CCW"
	ow.range_value = 0
	ow.attacks = 4
	ow.count = 1
	opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr
	return u


## The planner hook test's board (a marker-taker, an enemy 30" off, a far idler); `sink` = the harness capture, if any.
func _controller(sink: Callable = Callable()) -> SoloController:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Taker": _unit(2, [Vector3(6.0 * IN2M, 0, 0)], "Taker"),
		"Enemy": _unit(1, [Vector3(36.0 * IN2M, 0, 0)], "Enemy"),
		"Idler": _unit(2, [Vector3(60.0 * IN2M, 0, 60.0 * IN2M)], "Idler")}
	army.current_round = 1
	var sc: SoloController = auto_free(SoloController.new())
	add_child(sc)
	sc.setup(army, null, null, 1, 2)
	sc.game_rounds = 4
	sc.objectives_provider = func() -> Array: return [Vector3(0, 0, 12.0 * IN2M)]
	sc.objective_owner_of = func(_i: int) -> int: return 0
	sc.set_difficulty(2, SoloDifficulty.for_grade("planner_v0"))
	sc.decision_sink = sink
	BattleSim._core_env = 0
	return sc


func _pick(sc: SoloController) -> GameUnit:
	return sc._select_ai_unit([sc.army_manager.game_units["Idler"], sc.army_manager.game_units["Taker"]])


## Pick once with a spy in the reserve list; returns {unit, looks, records}.
func _run(sink: Callable = Callable()) -> Dictionary:
	var sc := _controller(sink)
	var spy := SpyUnit.new()
	sc.ambush_reserve = [spy]
	var chosen := _pick(sc)
	return {"unit": chosen, "looks": spy.looks, "records": sc.decision_log.duplicate(true)}


func _planner_records(records: Array) -> Array:
	return records.filter(func(r: Dictionary) -> bool: return str(r.get("kind", "")) == "planner")


func _unit_id(u: GameUnit) -> String:
	return u.unit_id if u != null else ""


func _why(records: Array) -> String:
	var planner := _planner_records(records)
	return str((planner[0] as Dictionary).get("why", "")) if not planner.is_empty() else ""


## The data of the i-th planner record ({} when there is none, so a red test fails an assert instead of a script error).
func _data(planner: Array, i: int) -> Dictionary:
	return (planner[i] as Dictionary).get("data", {}) if i < planner.size() else {}


func test_a_shipped_pick_computes_no_features_and_logs_no_vector_and_no_leaf_row() -> void:
	var got := _run()
	assert_int(got["looks"]).override_failure_message("the features were computed with no consumer attached").is_equal(0)
	var planner := _planner_records(got["records"])
	assert_int(planner.size()).override_failure_message("records: %s" % [planner]).is_equal(1)   # the unit pick, no leaf row
	assert_bool(_data(planner, 0).has("features")).is_false()
	assert_bool(_data(planner, 0).has("value")).is_true()   # the rest of the record stays
	assert_object(got["unit"]).is_not_null()


func test_a_harness_sink_gets_the_vector_and_the_leaf_row_as_before() -> void:
	var seen := []
	var got := _run(func(rec: Dictionary) -> void: seen.append(rec))
	assert_int(got["looks"]).override_failure_message("the features were not computed for the sink").is_greater(0)
	var planner := _planner_records(seen)
	assert_int(planner.size()).override_failure_message("records: %s" % [planner]).is_equal(2)   # unit pick + leaf row
	assert_array(_data(planner, 0).keys()).is_equal(["kept_back", "value", "features"])
	assert_bool((_data(planner, 0).get("features", {}) as Dictionary).is_empty()).is_false()
	assert_bool(bool(_data(planner, 1).get("leaf", false))).is_true()


func test_the_pick_and_every_line_the_player_can_see_are_the_same_with_and_without_the_features() -> void:
	var shipped := _run()
	var captured_records := []
	var captured := _run(func(rec: Dictionary) -> void: captured_records.append(rec))
	assert_str(_unit_id(shipped["unit"])).is_not_empty().is_equal(_unit_id(captured["unit"]))
	assert_array(SoloController.player_decision_lines(shipped["records"])) \
		.override_failure_message("the player's decision lines changed") \
		.is_equal(SoloController.player_decision_lines(captured_records))
	assert_str(_why(shipped["records"])).is_not_empty().is_equal(_why(captured_records))   # the unit-pick sentence, same either way
