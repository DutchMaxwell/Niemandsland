extends GdUnitTestSuite
## Rules 3.6 wave, row AI-09: the net's per-unit melee input ("mev") must price an Assault weapon's
## melee copy from the 3.6 epoch (73), exactly like the table's AiShooting.melee_profiles. This is the
## twin pin: BattleSim.board_rows (GDScript) and unit_sev_mev (Rust) must give the SAME number.

const MEV_COLUMN := 13

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests: restore


func _unit(pid: int, positions: Array, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


## The one-model unit armed ONLY with a ranged Assault weapon (12", A2, AP(1)) — no melee weapon.
func _assault_gunner() -> GameUnit:
	var gunner := _unit(1, [Vector3.ZERO], "Gunner")
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Assault Rifle"
	w.range_value = 12
	w.attacks = 2
	w.count = 1
	w.special_rules.append("Assault")
	w.special_rules.append("AP(1)")
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	var src := OPRApiClient.OPRUnit.new()
	src.quality = 4
	src.defense = 4
	src.weapons = ws
	gunner.source_type = "opr"
	gunner.source_data = src
	return gunner


func _board_mev_at(epoch: int) -> float:
	AiActRecorder.rules_epoch = epoch
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gunner := _assault_gunner()
	army.game_units = {gunner.unit_id: gunner}
	var state := BattleSim.capture(army, func() -> Array: return [],
		func(_i: int) -> int: return 0, 1, 4)
	return float((BattleSim.board_rows(state)[0] as Array)[MEV_COLUMN])


func test_an_assault_weapon_prices_as_bare_hands_in_the_net_at_epoch_72() -> void:
	assert_float(_board_mev_at(AiActRecorder.EPOCH_72_PLAYTEST_RULES)).is_equal_approx(0.0, 0.001)


func test_an_assault_weapon_prices_its_melee_copy_in_the_net_at_epoch_73() -> void:
	assert_float(_board_mev_at(73)).is_equal_approx(0.67, 0.001)
