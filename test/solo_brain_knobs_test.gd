extends GdUnitTestSuite
## The shipped brain's games stamp menu_open (menu_all_targets 3 + menu_advance_obj_shoot) into the header knobs the live core reads (T2b BETTER on Erlkoenig, 08.10.2026). Hand-planner
## games (no brain) write exactly the keys they wrote before.

const KEYS := ["menu_all_targets", "menu_advance_obj_shoot"]


func after_test() -> void:
	OS.unset_environment("NML_BRAIN_KNOBS")
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


func _assert_absent(k: Dictionary) -> void:
	for key in KEYS:
		assert_bool(k.has(key)).override_failure_message("key %s must be absent" % key).is_false()


func test_brain_wired_planner_v0_stamps_the_three_measured_knobs() -> void:
	var solo := _brain_wired_solo()
	var diff := SoloDifficulty.for_grade("planner_v0")
	assert_bool((diff.get("brain_knobs") == true)).is_true()
	solo._apply_aifix(diff)
	var k := _knobs()
	assert_int(int(k.get("menu_all_targets", 0))).is_equal(3)
	assert_bool(bool(k.get("menu_advance_obj_shoot", false))).is_true()
	assert_bool(bool(k.get("strength_by_points", false))).is_true()


func test_no_brain_writes_none_of_the_three_keys() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	solo._apply_aifix(SoloDifficulty.for_grade("planner_v0"))
	_assert_absent(_knobs())


func test_the_env_switch_forces_the_stamp_either_way() -> void:
	var wired := _brain_wired_solo()
	OS.set_environment("NML_BRAIN_KNOBS", "0")
	wired._apply_aifix(SoloDifficulty.for_grade("planner_v0"))
	_assert_absent(_knobs())
	BattleSim._core_env = -1
	var bare: SoloController = auto_free(SoloController.new())
	OS.set_environment("NML_BRAIN_KNOBS", "1")
	bare._apply_aifix(SoloDifficulty.for_grade("planner_v0"))
	assert_int(int(_knobs().get("menu_all_targets", 0))).is_equal(3)


func test_a_preset_without_the_flag_stamps_nothing_even_with_the_brain() -> void:
	var solo := _brain_wired_solo()
	var diff := SoloDifficulty.for_grade("nachtmahr")
	assert_bool((diff.get("brain_knobs") == true)).is_false()
	solo._apply_aifix(diff)
	_assert_absent(_knobs())
