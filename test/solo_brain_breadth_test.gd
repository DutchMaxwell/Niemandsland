extends GdUnitTestSuite
## The shipped brain searches 128 candidates at horizon 3 (A/B of record): the preset field brain_breadth stamps top_k / horizon
## into the header the live core reads. Hand games and env 0 keep the core default.



func after_test() -> void:
	OS.unset_environment("NML_BRAIN_BREADTH")
	auto_free(SoloController.new())._apply_aifix(null)   # resets the per-pick statics (brain_knobs off)
	BattleSim._core_env = -1


## A solo controller that reads as "core wanted + loaded + brain accepted" without a real GDExtension.
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


func _on(k: Dictionary) -> bool:
	return int(k.get("brain_breadth", 0)) == 128 and int(k.get("top_k", 0)) == 128 and int(k.get("horizon", 0)) == 3


func test_every_brain_preset_defaults_to_128() -> void:
	for preset in ["planner_v0", "planner_v0s", "planner_v0_herofold", "planner_v0_pool1", "planner_v0_both"]:
		var d := SoloDifficulty.for_grade(preset)
		assert_bool(d.brain_knobs).is_true()
		assert_bool(d.get("brain_breadth") == 128).is_true()


func test_presets_without_brain_knobs_default_to_zero() -> void:
	assert_bool(SoloDifficulty.for_grade("nachtmahr").get("brain_breadth") == 0).is_true()
	assert_bool(SoloDifficulty.for_grade("planner_v2").get("brain_breadth") == 0).is_true()


func test_brain_wired_header_carries_top_k_128_and_horizon_3() -> void:
	var solo := _brain_wired_solo()
	solo._apply_aifix(SoloDifficulty.for_grade("planner_v0"))
	assert_bool(_on(_knobs())).is_true()


func test_no_brain_keeps_the_core_default() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	solo._apply_aifix(SoloDifficulty.for_grade("planner_v0"))
	var k := _knobs()
	assert_bool(k.has("brain_breadth")).is_false()
	assert_int(int(k.get("top_k", 0))).is_not_equal(128)


func test_env_zero_turns_it_off_and_env_int_forces_it() -> void:
	var wired := _brain_wired_solo()
	OS.set_environment("NML_BRAIN_BREADTH", "0")
	wired._apply_aifix(SoloDifficulty.for_grade("planner_v0"))
	var k := _knobs()
	assert_bool(k.has("brain_breadth")).is_false()
	assert_int(int(k.get("top_k", 0))).is_not_equal(128)
	OS.set_environment("NML_BRAIN_BREADTH", "64")
	wired._apply_aifix(SoloDifficulty.for_grade("planner_v0"))
	k = _knobs()
	assert_int(int(k.get("top_k", 0))).is_equal(64)
	assert_int(int(k.get("horizon", 0))).is_equal(3)


func test_flagless_brain_preset_stamps_nothing() -> void:
	var solo := _brain_wired_solo()
	solo._apply_aifix(SoloDifficulty.for_grade("nachtmahr"))
	assert_bool(_knobs().has("brain_breadth")).is_false()
