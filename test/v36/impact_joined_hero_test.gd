extends GdUnitTestSuite
## Impact(X) is a per-model rule: a living joined hero rolls its own X dice on a charge (rules 3.6
## wave, `EPOCH_73_V36`); the host's models keep theirs. Tray and save batch are the probe seams.

class Probe extends "res://scripts/main.gd":
	func _solo_tray_roll(count: int, _t: int, _o: String, _k: String = "attack", _p: String = "") -> Array:
		var f: Array = []
		f.resize(count)
		f.fill(1)
		return f


var _epoch_before := 0


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before


func _unit(name: String, models: int, rules: Array) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "imphero_%s" % name
	u.unit_properties = {"player_id": 1, "name": name, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": "blessed_sisters"}
	for i in models:
		var m := ModelInstance.new()
		m.is_alive = true
		u.models.append(m)
	return u


func _log_of(epoch: int, host_rules: Array, hero_rules: Array) -> String:
	AiActRecorder.rules_epoch = epoch
	var main: Probe = auto_free(Probe.new())
	main.battle_log = auto_free(BattleLog.new())
	var host := _unit("Host", 2, host_rules)
	EquipmentDistributor.attach_hero_to_unit(_unit("Hero", 1, hero_rules), host)
	await main._solo_charge_impact(host, _unit("Target", 1, []), false)
	var text := ""
	for e in main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func test_a_joined_hero_rolls_its_own_impact_at_epoch_73() -> void:
	var text := await _log_of(AiActRecorder.EPOCH_73_V36, [], ["Impact(2)"])
	assert_str(text).override_failure_message("hero Impact never rolled: " + text).contains("Impact(2) rolls 2 dice")


func test_host_impact_keeps_its_dice_and_a_plain_hero_adds_none() -> void:
	var text := await _log_of(AiActRecorder.EPOCH_73_V36, ["Impact(2)"], [])
	assert_str(text).contains("Impact(2) rolls 4 dice")


func test_host_and_hero_dice_add_up_and_the_old_epoch_stays_host_only() -> void:
	var text := await _log_of(AiActRecorder.EPOCH_73_V36, ["Impact(2)"], ["Impact(3)"])
	assert_str(text).contains("rolls 7 dice")
	text = await _log_of(AiActRecorder.EPOCH_73_V36 - 1, ["Impact(2)"], ["Impact(3)"])
	assert_str(text).contains("Impact(2) rolls 4 dice")
