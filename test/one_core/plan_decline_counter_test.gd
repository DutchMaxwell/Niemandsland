extends GdUnitTestSuite
## P4.D-61: the planner decline counter. `SoloController.note_plan` counts who still reaches the GDScript search into
## CoreActivation.legacy["plan_decline"]: "core:<reason>" when `_core_plan` declines, "rollout:used|unused" for the
## GDScript AiPlanner.plan_with_rollout answer that follows (the 1-ply "plan1" key went with its fallback, P4.D-93).
## Counting only: a declining core must decide exactly like no core. Constructed: bare units, a stub core node.

const IN2M := 0.0254


## What `_core_plan` asks of the node, answering a decline with `reason` (or refusing the game header).
class StubCore extends RefCounted:
	var reason := "PlantedReason"
	var header_ok := true
	func set_game_header(_head) -> bool:
		return header_ok
	func set_terrain(_line) -> bool:
		return true
	func statics_builds() -> int:
		return 0
	func last_error() -> String:
		return "header refused"
	func plan_with_rollout(_plain, _me, _statics, _sig) -> Dictionary:
		return {"used": false, "unsupported": reason}


func before_test() -> void:
	CoreActivation.legacy.clear()


func after_test() -> void:
	CoreActivation.legacy.clear()
	BattleSim._core_env = -1
	OS.unset_environment("NML_TABLE_CENSUS")
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


## The planner hook test's board: an AI marker-taker 6" from a neutral marker, an enemy 30" off, a far idler.
func _controller(core: StubCore) -> SoloController:
	var taker := _unit(2, [Vector3(6.0 * IN2M, 0, 0)], "Taker")
	var enemy := _unit(1, [Vector3(36.0 * IN2M, 0, 0)], "Enemy")
	var idler := _unit(2, [Vector3(60.0 * IN2M, 0, 60.0 * IN2M)], "Idler")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Taker": taker, "Enemy": enemy, "Idler": idler}
	army.current_round = 1
	var sc: SoloController = auto_free(SoloController.new())
	add_child(sc)
	sc.setup(army, null, null, 1, 2)
	sc.game_rounds = 4
	sc.objectives_provider = func() -> Array: return [Vector3(0, 0, 12.0 * IN2M)]
	sc.objective_owner_of = func(_i: int) -> int: return 0
	sc.set_difficulty(2, SoloDifficulty.for_grade("planner_v0"))
	BattleSim._core_env = 1 if core != null else 0
	sc._core_node = core
	return sc


func _pick(sc: SoloController) -> GameUnit:
	return sc._select_ai_unit([sc.army_manager.game_units["Idler"], sc.army_manager.game_units["Taker"]])


func _plan_decline() -> Dictionary:
	return CoreActivation.legacy.get("plan_decline", {})


func test_a_planted_decline_is_counted_once_by_its_reason_and_the_gdscript_answer_after_it() -> void:
	var sc := _controller(StubCore.new())
	var chosen := _pick(sc)
	var d := _plan_decline()
	assert_int(d.get("core:PlantedReason", 0)).override_failure_message("counts: %s" % [d]).is_equal(1)
	assert_int(d.get("rollout:used", 0) + d.get("rollout:unused", 0)).override_failure_message("counts: %s" % [d]).is_equal(1)
	assert_object(chosen).is_same(sc.army_manager.game_units["Taker"])


func test_a_refused_game_header_is_counted_as_a_decline() -> void:
	var core := StubCore.new()
	core.header_ok = false
	var sc := _controller(core)
	_pick(sc)
	var d := _plan_decline()
	assert_int(d.get("core:header_refused", 0)).override_failure_message("counts: %s" % [d]).is_equal(1)
	assert_int(d.get("core:PlantedReason", 0)).is_equal(0)


func test_a_declining_core_decides_exactly_like_no_core() -> void:
	var off := _controller(null)
	var chosen_off := _pick(off)
	var log_off := str(off.decision_log)
	assert_int(_plan_decline().get("rollout:used", 0) + _plan_decline().get("rollout:unused", 0)).is_equal(1)
	assert_bool(_plan_decline().keys().any(func(k: String) -> bool: return k.begins_with("core:"))).is_false()
	var declining := _controller(StubCore.new())
	var chosen_dec := _pick(declining)
	assert_str(chosen_dec.unit_id).is_equal(chosen_off.unit_id)
	assert_str(str(declining.decision_log)).override_failure_message("a decline changed the planner's decision record").is_equal(log_off)


func test_counting_draws_no_dice() -> void:
	seed(77)
	var next := randi()
	seed(77)
	SoloController.note_plan("core:anything")
	assert_int(randi()).override_failure_message("the counter drew from the global RNG").is_equal(next)


func test_the_census_dump_carries_the_plan_decline_counts() -> void:
	var path := "user://plan_decline_dump_test.json"
	DirAccess.remove_absolute(path)
	_pick(_controller(StubCore.new()))
	OS.set_environment("NML_TABLE_CENSUS", path)
	CoreActivation.dump_legacy()
	var text := FileAccess.get_file_as_string(path)
	DirAccess.remove_absolute(path)
	var got: Dictionary = JSON.parse_string(text) if text != "" else {}
	assert_int(int(got.get("legacy", {}).get("plan_decline", {}).get("core:PlantedReason", 0))).is_equal(1)
