extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-18: the offensive Surge/Shred alias families (Brutal, Violent,
## Warbound, Ferocious and their siblings) fire only from the right distance — a shot from over
## 9", a charge from over 6". Below EPOCH_73_V36 the old unconditional read stays. The Rust twin
## covers the dice; here the real _solo_hits and _solo_save_batch seams run with a fixed tray.

class Probe extends "res://scripts/main.gd":
	var faces: Array = []

	func _solo_tray_roll(_count: int, _target: int, _owner: String, _kind: String = "attack",
			_purpose: String = "") -> Array:
		return faces


var _epoch_before := 0


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before


func _unit(name: String, models: int, rules: Array, faction: String = "war_disciples") -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "sho18_%s" % name
	u.unit_properties = {"player_id": 2, "name": name, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": faction}
	for i in models:
		var m := ModelInstance.new()
		m.is_alive = true
		u.models.append(m)
	return u


func _surge_hits(epoch: int, dist_in: float) -> int:
	AiActRecorder.rules_epoch = epoch
	var main: Probe = auto_free(Probe.new())
	main.battle_log = auto_free(BattleLog.new())
	var profile := {"surge": true, "_surge_alias": "Ferocious", "bonus_hits_per_six": 1}
	return await main._solo_hits([6, 3, 2, 1], 4, profile, dist_in)


func _shred_wounds(epoch: int, charge_in: float) -> int:
	AiActRecorder.rules_epoch = epoch
	var main: Probe = auto_free(Probe.new())
	main.battle_log = auto_free(BattleLog.new())
	main.faces = [1]
	var striker := _unit("Warbound", 1, ["Warbound"])
	var target := _unit("Target", 1, [])
	var profile := {"shred": true, "_shred_alias": "Warbound", "range": 0, "rules": []}
	return await main._solo_save_batch(striker, target, "Warbound", 1, 4, 0, profile,
		false, false, true, false, {}, charge_in)


## The shared gate: a charge needs over 6", a shot over 9", and 72 keeps the old read.
func test_the_family_gate_is_six_inches_charging_and_nine_shooting_from_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var main: Node = auto_free(preload("res://scripts/main.gd").new())
	assert_bool(main._solo_alias_family_over(true, 0.0, 7.0)) \
		.override_failure_message("a 7\" charge clears the 6\" gate").is_true()
	assert_bool(main._solo_alias_family_over(true, 0.0, 3.0)) \
		.override_failure_message("a 3\" charge stays inside the 6\" gate").is_false()
	assert_bool(main._solo_alias_family_over(false, 10.0, 0.0)) \
		.override_failure_message("a 10\" shot clears the 9\" gate").is_true()
	assert_bool(main._solo_alias_family_over(false, 7.0, 0.0)) \
		.override_failure_message("a 7\" shot stays inside the 9\" gate").is_false()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_bool(main._solo_alias_family_over(false, 7.0, 0.0)) \
		.override_failure_message("below 73 the old unconditional read stays").is_true()


## RED on main: Ferocious' six bonus fires at 10" and stays silent at 7".
func test_ferocious_pays_its_sixes_over_nine_inches_and_not_inside_at_epoch_73() -> void:
	assert_int(await _surge_hits(AiActRecorder.EPOCH_73_V36, 10.0)) \
		.override_failure_message("10\" pays the unmodified 6").is_equal(2)
	assert_int(await _surge_hits(AiActRecorder.EPOCH_73_V36, 7.0)) \
		.override_failure_message("7\" keeps the bare hit").is_equal(1)
	assert_int(await _surge_hits(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 7.0)) \
		.override_failure_message("below 73 the 7\" shot still pays").is_equal(2)


## RED on main: Warbound's Shred fires on a 7" charge and not on a 3" charge.
func test_warbound_shreds_over_six_inches_charging_and_not_inside_at_epoch_73() -> void:
	assert_int(await _shred_wounds(AiActRecorder.EPOCH_73_V36, 7.0)) \
		.override_failure_message("the 7\" charge shreds the failed save 1").is_equal(2)
	assert_int(await _shred_wounds(AiActRecorder.EPOCH_73_V36, 3.0)) \
		.override_failure_message("the 3\" charge keeps the bare wound").is_equal(1)
	assert_int(await _shred_wounds(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 3.0)) \
		.override_failure_message("below 73 the 3\" charge still shreds").is_equal(2)


## Rules-must-log: the applied gate names the rule and its band.
func test_the_applied_gates_name_the_rule_and_the_band() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var main: Probe = auto_free(Probe.new())
	main.battle_log = auto_free(BattleLog.new())
	await main._solo_hits([6, 3, 2, 1], 4,
		{"surge": true, "_surge_alias": "Ferocious", "bonus_hits_per_six": 1}, 10.0)
	var text := ""
	for e in main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	assert_str(text) \
		.override_failure_message("the shot gate names Ferocious and the 9\" band — got: %s" % text.strip_edges()) \
		.contains("Ferocious") \
		.contains("over 9\"")
