extends GdUnitTestSuite
## Rules 3.6 row AI-06 (shooting half): the AI's expected shooting-morale read counts the phantom
## wounds a Scourge volley's unmodified block 1s earn, exactly as the resolver does (SHO-15a).
## Two expected phantom wounds per expected save-6 (P = 1/6) count toward the post-volley trigger,
## from EPOCH_73_V36. Below 73 and for a non-Scourge volley the number stays put.

const IN2M := 0.0254

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore


func _shot_unit(pid: int, uid: String, xs: Array, wounds_max: int, weapons: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	for x in xs:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_max = wounds_max
		m.wounds_current = wounds_max
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = Vector3(float(x) * IN2M, 0, 0)
		m.node = n
		u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	for w in weapons:
		var ow := OPRApiClient.OPRWeapon.new()
		ow.name = str((w as Dictionary).get("name", "W"))
		ow.range_value = int((w as Dictionary).get("range", 0))
		ow.attacks = int((w as Dictionary).get("attacks", 1))
		ow.count = 1
		for r in (w as Dictionary).get("rules", []):
			ow.special_rules.append(str(r))
		opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr
	return u


func _shot_capture(units: Array) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	return BattleSim.capture(army)


# --- shooting: 36 attacks at Q4+ leave a 20-Tough target at 11 (above half); 18 expected hits add
# --- 6 phantom wounds, which put it at 5 and force the morale read.
func _shot(scourge: bool, epoch: int) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	var rules: Array = ["Scourge"] if scourge else []
	var shooter := _shot_unit(2, "Shooter", [0.0], 1,
		[{"name": "Heat Rifle", "range": 24, "attacks": 36, "rules": rules}])
	var target := _shot_unit(1, "Squad", [12.0], 20, [])
	var next := BattleSim.resolve(_shot_capture([shooter, target]),
		{"unit": "Shooter", "kind": AiDecision.Action.HOLD, "shoot": "Squad"})
	return next["units"]["Squad"]


func test_scourge_phantom_wounds_force_the_shooting_morale_test_at_epoch_73() -> void:
	assert_bool(bool(_shot(true, AiActRecorder.EPOCH_73_V36)["shaken"])).is_true()


func test_the_same_scourge_volley_leaves_no_test_at_epoch_72() -> void:
	assert_bool(bool(_shot(true, AiActRecorder.EPOCH_72_PLAYTEST_RULES)["shaken"])).is_false()


func test_a_plain_volley_leaves_no_test_at_epoch_73() -> void:
	assert_bool(bool(_shot(false, AiActRecorder.EPOCH_73_V36)["shaken"])).is_false()
