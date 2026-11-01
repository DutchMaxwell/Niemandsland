extends GdUnitTestSuite
## Rules 3.6 row AI-06 (melee half): the AI's expected melee-morale number counts the phantom
## wounds a Scourge striker's unmodified block 1s earn, exactly as the resolver does (SHO-15b).
## Two expected phantom wounds per expected save-6 (P = 1/6) go into the defender's TAKEN tally,
## from EPOCH_73_V36. Below 73 and for a non-Scourge striker the number stays put.

const IN2M := 0.0254

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore


func _unit(pid: int, uid: String, xs: Array, wounds_max: int, weapons: Array) -> GameUnit:
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


func _capture(units: Array) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	return BattleSim.capture(army)


# --- melee: the charger deals 7 and takes 8, so it loses on real wounds; 30 attack dice add 5
# --- expected phantom wounds to the defender's taken tally, which flips the loser.
func _charge(scourge: bool, epoch: int) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	var rules: Array = ["Scourge"] if scourge else []
	var charger := _unit(2, "Charger", [0.0], 100,
		[{"name": "Blade", "range": 0, "attacks": 30, "rules": rules}])
	var target := _unit(1, "Target", [1.3], 100,
		[{"name": "Claw", "range": 0, "attacks": 33}])
	var next := BattleSim.resolve(_capture([charger, target]),
		{"unit": "Charger", "kind": AiDecision.Action.CHARGE, "charge": "Target"})
	return next["units"]


func test_scourge_phantom_wounds_flip_the_melee_loser_at_epoch_73() -> void:
	var u := _charge(true, AiActRecorder.EPOCH_73_V36)
	assert_bool(bool((u["Target"] as Dictionary)["shaken"])).is_true()
	assert_bool(bool((u["Charger"] as Dictionary)["shaken"])).is_false()


func test_the_same_scourge_charge_keeps_the_old_loser_at_epoch_72() -> void:
	var u := _charge(true, AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	assert_bool(bool((u["Charger"] as Dictionary)["shaken"])).is_true()
	assert_bool(bool((u["Target"] as Dictionary)["shaken"])).is_false()


func test_a_plain_charger_keeps_the_old_loser_at_epoch_73() -> void:
	var u := _charge(false, AiActRecorder.EPOCH_73_V36)
	assert_bool(bool((u["Charger"] as Dictionary)["shaken"])).is_true()
