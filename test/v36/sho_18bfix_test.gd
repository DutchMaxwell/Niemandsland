extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-18b-fix: the Surge/Shred alias families pay on a charge over 6"
## and on a shot over 9", never on a non-charging melee strike-back. Below EPOCH_73_V36
## the old unconditional read stays. The Rust twin covers the dice; here the real
## _solo_hits and _solo_save_batch seams run with a fixed tray.

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
	u.unit_id = "sho18bfix_%s" % name
	u.unit_properties = {"player_id": 2, "name": name, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": faction}
	for i in models:
		var m := ModelInstance.new()
		m.is_alive = true
		u.models.append(m)
	return u


func _surge_hits(epoch: int, charging: bool, charge_in: float) -> int:
	AiActRecorder.rules_epoch = epoch
	var main: Probe = auto_free(Probe.new())
	main.battle_log = auto_free(BattleLog.new())
	var profile := {"surge": true, "_surge_alias": "Ferocious", "bonus_hits_per_six": 1}
	return await main._solo_hits([6, 3, 2, 1], 4, profile, 0.0, null, charging, "", charge_in)


func _shred_wounds(epoch: int, charge_in: float) -> int:
	AiActRecorder.rules_epoch = epoch
	var main: Probe = auto_free(Probe.new())
	main.battle_log = auto_free(BattleLog.new())
	main.faces = [1]
	var striker := _unit("Warbound", 1, ["Warbound"])
	var target := _unit("Target", 1, [])
	var profile := {"shred": true, "_shred_alias": "Warbound", "range": 0, "rules": []}
	return await main._solo_save_batch(striker, target, "Warbound", 1, 4, 0, profile,
		false, false, true, false, {}, -1.0, charge_in)


## The shared gate: a strike-back pays nothing at 73; the shot and charge bands stay.
func test_the_family_gate_is_charge_or_shot_only_from_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var main: Node = auto_free(preload("res://scripts/main.gd").new())
	assert_bool(main._solo_alias_charge_over(true, 7.0)) \
		.override_failure_message("a 7\" charge clears the 6\" gate").is_true()
	assert_bool(main._solo_alias_charge_over(true, 3.0)) \
		.override_failure_message("a 3\" charge stays inside the 6\" gate").is_false()
	assert_bool(main._solo_alias_charge_over(false, 0.0)) \
		.override_failure_message("a strike-back pays no charge bonus").is_false()
	assert_bool(main._solo_alias_family_over(0.0)) \
		.override_failure_message("a melee strike-back pays no alias bonus").is_false()
	assert_bool(main._solo_alias_family_over(7.0)) \
		.override_failure_message("a 7\" shot stays inside the 9\" gate").is_false()
	assert_bool(main._solo_alias_family_over(10.0)) \
		.override_failure_message("a 10\" shot clears the 9\" gate").is_true()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_bool(main._solo_alias_charge_over(false, 0.0)) \
		.override_failure_message("below 73 the old unconditional read stays").is_true()
	assert_bool(main._solo_alias_family_over(0.0)) \
		.override_failure_message("below 73 melee keeps the old read").is_true()


## RED on main: a strike-back pays no Ferocious six; a 7" charge still does.
func test_ferocious_pays_no_sixes_on_a_strike_back_at_epoch_73() -> void:
	assert_int(await _surge_hits(AiActRecorder.EPOCH_73_V36, false, 0.0)) \
		.override_failure_message("the strike-back keeps the bare hit").is_equal(1)
	assert_int(await _surge_hits(AiActRecorder.EPOCH_73_V36, true, 7.0)) \
		.override_failure_message("the 7\" charge pays the unmodified 6").is_equal(2)
	assert_int(await _surge_hits(AiActRecorder.EPOCH_73_V36, true, 3.0)) \
		.override_failure_message("the 3\" charge keeps the bare hit").is_equal(1)
	assert_int(await _surge_hits(AiActRecorder.EPOCH_72_PLAYTEST_RULES, false, 0.0)) \
		.override_failure_message("below 73 the strike-back still pays").is_equal(2)


## RED on main: a strike-back shreds nothing; a 7" charge still shreds.
func test_warbound_shreds_nothing_on_a_strike_back_at_epoch_73() -> void:
	assert_int(await _shred_wounds(AiActRecorder.EPOCH_73_V36, 0.0)) \
		.override_failure_message("the strike-back keeps the bare wound").is_equal(1)
	assert_int(await _shred_wounds(AiActRecorder.EPOCH_73_V36, 7.0)) \
		.override_failure_message("the 7\" charge shreds the failed save 1").is_equal(2)
	assert_int(await _shred_wounds(AiActRecorder.EPOCH_73_V36, 3.0)) \
		.override_failure_message("the 3\" charge keeps the bare wound").is_equal(1)
	assert_int(await _shred_wounds(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 0.0)) \
		.override_failure_message("below 73 the strike-back still shreds").is_equal(2)
