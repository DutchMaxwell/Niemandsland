extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-18c (lead ruling D-GATE6): the table's Shred-alias marker is a NAME, like
## the Surge alias, so the 3.6 distance gate reaches the table too. The bug: the profile build stamped
## `_shred_alias = true` while the reader only accepts a non-empty String; the bool never matched, the
## gate below it was skipped, and a Warbound-family carrier shredded at every distance. These cases run
## the real `_solo_attack_groups` profile build and the real `_solo_save_batch` save flow with a fixed
## tray, so the marker is never hand-built.

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


func _unit(unit_name: String, weapons: Array) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "sho18c_%s" % unit_name
	u.unit_properties = {"player_id": 2, "name": unit_name, "quality": 4, "defense": 4,
		"special_rules": ["Warbound"], "game_system": "gf", "faction_folder": "war_disciples"}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	var ws: Array[OPRApiClient.OPRWeapon] = []
	for wd in weapons:
		var d := wd as Dictionary
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(d.get("name", "Gun"))
		w.range_value = int(d.get("range", 0))
		w.attacks = int(d.get("attacks", 1))
		w.count = 1
		ws.append(w)
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = ws
	u.source_type = "opr"
	u.source_data = src
	return u


func _profile(main: Probe, striker: GameUnit, dist_in: float, melee: bool) -> Dictionary:
	var groups: Array = main._solo_attack_groups(striker, dist_in if not melee else 0.0, melee, null)
	assert_int(groups.size()).override_failure_message("the table built no attack group").is_equal(1)
	if groups.is_empty():
		return {}
	var profiles: Array = (groups[0] as Dictionary).get("profiles", [])
	assert_int(profiles.size()).override_failure_message("the table built no profile").is_equal(1)
	if profiles.is_empty():
		return {}
	var prof := profiles[0] as Dictionary
	assert_bool(bool(prof.get("shred", false))) \
		.override_failure_message("fixture broken: Warbound did not reach the profile").is_true()
	return prof


func _shoot_wounds(epoch: int, dist_in: float) -> int:
	AiActRecorder.rules_epoch = epoch
	var main: Probe = auto_free(Probe.new())
	main.battle_log = auto_free(BattleLog.new())
	main.faces = [1]
	var striker := _unit("Warbound Rifles", [{"name": "Rifle", "range": 24, "attacks": 2}])
	var target := _unit("Target", [])
	var profile := _profile(main, striker, dist_in, false)
	return await main._solo_save_batch(striker, target, "Rifle", 1, 4, 0, profile,
		false, false, true, false, {}, dist_in)


func _charge_wounds(epoch: int, charge_in: float) -> int:
	AiActRecorder.rules_epoch = epoch
	var main: Probe = auto_free(Probe.new())
	main.battle_log = auto_free(BattleLog.new())
	main.faces = [1]
	var striker := _unit("Warbound Blades", [{"name": "Blade", "range": 0, "attacks": 3}])
	var target := _unit("Target", [])
	var profile := _profile(main, striker, 0.0, true)
	return await main._solo_save_batch(striker, target, "Blade", 1, 4, 0, profile,
		false, false, true, false, {}, -1.0, charge_in)


## RED on main: the live build stamps a bool, so the 6" shot still shreds at epoch 73.
func test_a_six_inch_shot_pays_no_shred_alias_at_epoch_73() -> void:
	assert_int(await _shoot_wounds(AiActRecorder.EPOCH_73_V36, 6.0)) \
		.override_failure_message("the 6\" shot shreds — the gate never sees a marker name") \
		.is_equal(1)


## The working half: over 9" the table still pays the alias.
func test_a_shot_over_nine_inches_still_pays_the_alias_at_epoch_73() -> void:
	assert_int(await _shoot_wounds(AiActRecorder.EPOCH_73_V36, 10.0)) \
		.override_failure_message("the 10\" shot must still shred").is_equal(2)


## A charge over 6" pays the alias, and a charge inside 6" does not.
func test_a_charge_over_six_inches_still_pays_the_alias_at_epoch_73() -> void:
	assert_int(await _charge_wounds(AiActRecorder.EPOCH_73_V36, 7.0)) \
		.override_failure_message("the 7\" charge must still shred").is_equal(2)
	assert_int(await _charge_wounds(AiActRecorder.EPOCH_73_V36, 4.0)) \
		.override_failure_message("the 4\" charge must not shred").is_equal(1)


## Below 73 the old unconditional read stays.
func test_epoch_72_keeps_the_unconditional_shred() -> void:
	assert_int(await _shoot_wounds(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 6.0)) \
		.override_failure_message("below 73 the 6\" shot still shreds").is_equal(2)
