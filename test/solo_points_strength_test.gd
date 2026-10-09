extends GdUnitTestSuite
## Hand-planner games (no brain) stamp strength_by_points into the header knobs the live core reads (A/B NOT_WORSE,
## 08.10.2026); a brain game gets it through the brain stamp; presets without the flag stamp nothing.


func after_test() -> void:
	OS.unset_environment("NML_POINTS")
	OS.unset_environment("NML_BRAIN_KNOBS")
	auto_free(SoloController.new())._apply_aifix(null)
	BattleSim._core_env = -1


func _brain_wired_solo() -> SoloController:
	var solo: SoloController = auto_free(SoloController.new())
	BattleSim._core_env = 1
	solo._core_node = auto_free(Node.new())
	solo.shipped_brain_sha = "test"
	assert_bool(solo.shipped_brain_ready()).is_true()
	return solo


func _armed(pid: int, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4, "special_rules": []}
	var m := ModelInstance.new()
	m.is_alive = true
	m.wounds_current = 1
	m.unit = u
	var n := Node3D.new()
	add_child(n)
	n.global_position = Vector3(float(pid), 0, 0)
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


func _knobs() -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"A": _armed(1, "A"), "B": _armed(2, "B")}
	var state := BattleSim.capture(army, func() -> Array: return [],
		func(_i: int) -> int: return 0, 1, 3)
	state["charge_illegal"] = func(_at: GameUnit, _vt: GameUnit, _gap: float,
		_ca: Vector3, _cb: Vector3) -> bool: return false
	return AiActRecorder._header_line(state, Callable()).get("knobs", {})


func test_hand_planner_v0_stamps_strength_by_points() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	var diff := SoloDifficulty.for_grade("planner_v0")
	assert_bool((diff.get("points_strength") == true)).is_true()
	solo._apply_aifix(diff)
	assert_bool(bool(_knobs().get("strength_by_points", false))).is_true()


func test_env_zero_removes_the_key() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	OS.set_environment("NML_POINTS", "0")
	solo._apply_aifix(SoloDifficulty.for_grade("planner_v0"))
	assert_bool(_knobs().has("strength_by_points")).is_false()


func test_env_one_forces_the_key_on_a_flagless_preset() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	OS.set_environment("NML_POINTS", "1")
	solo._apply_aifix(SoloDifficulty.for_grade("nachtmahr"))
	assert_bool(bool(_knobs().get("strength_by_points", false))).is_true()


func test_nachtmahr_stamps_nothing() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	var diff := SoloDifficulty.for_grade("nachtmahr")
	assert_bool((diff.get("points_strength") == true)).is_false()
	solo._apply_aifix(diff)
	assert_bool(_knobs().has("strength_by_points")).is_false()


func test_brain_wired_stamps_through_the_brain_path_not_the_hand_path() -> void:
	var solo := _brain_wired_solo()
	var diff := SoloDifficulty.for_grade("planner_v0")
	assert_bool(solo._points_strength_on(diff)).is_false()
	solo._apply_aifix(diff)
	assert_bool(AiPlanner.points_strength).is_false()
	assert_bool(bool(AiPlanner.brain_knob_stamp().get("strength_by_points", false))).is_true()
	assert_bool(bool(_knobs().get("strength_by_points", false))).is_true()
