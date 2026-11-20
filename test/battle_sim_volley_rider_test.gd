extends GdUnitTestSuite
## EPOCH_93_DANGER_RULES_RIDER, the GDScript fallback planner's half: `BattleSim.resolve` with the cast sub-phase OFF
## (the default) used to price, and pay for, the best affordable damage spell inside every shoot pick, a cast nobody
## makes (the table casts only what it planned, paid at plan time). From 93 the volley is the weapons only and spends
## no spell token, as the Rust core's `sim::resolve` does (its twin: `tests/sim/rider_off.rs`).
##
## Fixture: a one-model caster with a rifle and one spell token, a four-model squad 3" away, a HOLD that shoots it.
## The old arm (epoch 92) spends the token and adds the spell's expected wounds; the new arm keeps the token and the
## volley is the rifle alone.

const IN2M := 0.0254

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0


func _unit(pid: int, uid: String, positions: Array, rules: Array, faction: String, tokens: int, armed: bool) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": rules, "faction_folder": faction, "game_system": "gf"}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = 1
		m.wounds_max = 1
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	if armed:
		var opr := OPRApiClient.OPRUnit.new()
		var ow := OPRApiClient.OPRWeapon.new()
		ow.name = "Rifle"
		ow.range_value = 24
		ow.attacks = 2
		ow.count = 1
		opr.weapons.append(ow)
		u.source_type = "opr"
		u.source_data = opr
	u.casts_current = tokens
	u.casts_per_round = tokens
	return u


## Resolves one shooting HOLD of the caster at `epoch` and returns [tokens left, squad wounds taken].
func _volley(epoch: int) -> Array:
	AiActRecorder.rules_epoch = epoch
	var caster := _unit(1, "Wizard", [Vector3.ZERO], ["Caster(1)"], "robot_legions", 1, true)
	var foes: Array = []
	for i in range(4):
		foes.append(Vector3((3.0 + float(i)) * IN2M, 0, 0))
	var squad := _unit(2, "Squad", foes, [], "", 0, false)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Wizard": caster, "Squad": squad}
	var next := BattleSim.resolve(BattleSim.capture(army),
		{"unit": "Wizard", "kind": AiDecision.Action.HOLD, "shoot": "Squad"})
	var left := int((next["units"]["Wizard"] as Dictionary)["casts"])
	var sq: Dictionary = next["units"]["Squad"]
	var wounds := float(4 - int(sq["alive"])) + float(sq.get("wound_frac", 0.0))
	return [left, wounds]


func test_the_volley_rider_is_off_from_epoch_93() -> void:
	var new := _volley(AiActRecorder.EPOCH_93_DANGER_RULES_RIDER)
	assert_int(new[0]).is_equal(1)   # the token is kept: no cast was paid for


func test_the_volley_rider_still_spends_the_token_below_93() -> void:
	var old := _volley(AiActRecorder.EPOCH_93_DANGER_RULES_RIDER - 1)
	assert_int(old[0]).is_equal(0)   # the legacy rider paid for the spell inside the shoot pick


func test_the_rider_adds_its_spell_wounds_below_93_only() -> void:
	var old := _volley(AiActRecorder.EPOCH_93_DANGER_RULES_RIDER - 1)
	var new := _volley(AiActRecorder.EPOCH_93_DANGER_RULES_RIDER)
	assert_float(float(old[1])).is_greater(float(new[1]))   # below 93 the squad also carries the spell's expected wounds
	assert_float(float(new[1])).is_greater(0.0)             # the control: the rifle alone still hurts
