extends GdUnitTestSuite
## The table_fidelity preset flag stamps the seven rule-fidelity knobs into the header the live core reads, brain or hand.


func after_test() -> void:
	OS.unset_environment("NML_TABLE_FIDELITY")
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


const KEYS := ["range_by_base_edge", "fire_in_range_only", "casualties_bearers_last", "hero_counts_in_size",
	"reply_threat_by_speed", "charge_needs_path", "fearless_roll_when_shaken"]


func _all_seven(k: Dictionary) -> bool:
	for key in KEYS:
		if not bool(k.get(key, false)):
			return false
	return true


func _none_of_seven(k: Dictionary) -> bool:
	for key in KEYS:
		if k.has(key):
			return false
	return true


func test_flag_defaults_true_on_every_shipped_planner_preset() -> void:
	for name in ["planner_v0", "planner_v0s", "planner_v0_herofold", "planner_v0_pool1", "planner_v0_both"]:
		assert_bool(SoloDifficulty.for_grade(name).table_fidelity).is_true()


func test_hand_game_stamps_all_seven_keys_and_the_stamp() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	solo._apply_aifix(SoloDifficulty.for_grade("planner_v0"))
	var k := _knobs()
	assert_bool(_all_seven(k)).is_true()
	assert_bool(bool(k.get("table_fidelity", false))).is_true()


func test_brain_game_stamps_all_seven_keys() -> void:
	var solo := _brain_wired_solo()
	solo._apply_aifix(SoloDifficulty.for_grade("planner_v0"))
	assert_bool(_all_seven(_knobs())).is_true()


func test_env_zero_removes_the_stamp() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	OS.set_environment("NML_TABLE_FIDELITY", "0")
	solo._apply_aifix(SoloDifficulty.for_grade("planner_v0"))
	var k := _knobs()
	assert_bool(_none_of_seven(k)).is_true()
	assert_bool(k.has("table_fidelity")).is_false()


func test_env_one_forces_it_on_a_flagless_preset() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	OS.set_environment("NML_TABLE_FIDELITY", "1")
	solo._apply_aifix(SoloDifficulty.for_grade("nachtmahr"))
	assert_bool(_all_seven(_knobs())).is_true()


func test_flagless_preset_stamps_nothing() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	solo._apply_aifix(SoloDifficulty.for_grade("nachtmahr"))
	assert_bool(_none_of_seven(_knobs())).is_true()
