extends GdUnitTestSuite
## Rules 3.6 row SHO-15a, Scourge: every unmodified 1 the target rolls to block a Scourge SHOT counts as
## extra wounds (the map's phantom_wounds_per_save_one, 2) when the post-volley morale trigger is read, and
## nowhere else: nothing is removed. Gated on EPOCH_73_V36; at 72 the trigger reads the real wounds alone.
## The real save batch and the real trigger run; the tray faces and the morale roll are the two seams the
## probe replaces.


class Probe extends "res://scripts/main.gd":
	var faces: Array = []
	var morale_tests := 0

	func _solo_tray_roll(_count: int, _target: int, _owner: String, _kind: String = "attack",
			_purpose: String = "") -> Array:
		return faces

	func _solo_morale_test(_unit: GameUnit, _owner: String, _melee: bool = false, _cause: String = "") -> bool:
		morale_tests += 1
		return true


var _epoch_before := 0


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before


func _unit(models: int) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "sho15a_%d" % models
	u.unit_properties = {"player_id": 2, "name": "Squad", "quality": 4, "defense": 4, "special_rules": [],
		"game_system": "gf", "faction_folder": "dwarf_guilds"}
	for i in models:
		var m := ModelInstance.new()
		m.is_alive = true
		u.models.append(m)
	return u


## One volley at `epoch`: four hits at Defense 4+ against five Tough(1) models roll 1, 2, 5, 6 (two blocked,
## one unmodified 1), the two real wounds land, three of five stand (above half), then the trigger runs.
func _volley(epoch: int, rules: Array, range_in: int = 18) -> Probe:
	AiActRecorder.rules_epoch = epoch
	var main: Probe = auto_free(Probe.new())
	main.battle_log = auto_free(BattleLog.new())
	main.faces = [1, 2, 5, 6]
	var shooter := _unit(1)
	var target := _unit(5)
	var profile := {"name": "Heat Rifle", "range": range_in, "attacks": 4, "rules": rules}
	var wounds: int = await main._solo_save_batch(shooter, target, "Heat Rifle", 4, 4, 0, profile, false, false)
	assert_int(wounds).override_failure_message("fixture: the batch must leave 2 unsaved").is_equal(2)
	for i in 2:
		(target.models[i] as ModelInstance).is_alive = false
		(target.models[i] as ModelInstance).wounds_current = 0
	await main._solo_shooting_morale(target, 5, "AI", 5)
	return main


func _log_text(main: Probe) -> String:
	var lines: Array = []
	for e in main.battle_log.entries():
		lines.append(str(e["text"]))
	return "\n".join(lines)


## NEW leg: at 73 the one Scourge 1 counts 2 phantom wounds, 3 - 2 = 1 of 5 is half or less: the test is due,
## and the rule names itself in the log.
func test_scourge_ones_tip_the_shooting_morale_test_at_epoch_73() -> void:
	var main := await _volley(AiActRecorder.EPOCH_73_V36, ["Scourge"])
	assert_int(main.morale_tests).override_failure_message(
		"a Scourge 1 must count 2 phantom wounds toward the shooting morale trigger").is_equal(1)
	assert_str(_log_text(main)).contains("Scourge:")


## OLD leg: at 72 the same volley leaves 3 of 5 on real wounds, above half: no test.
func test_scourge_ones_do_not_count_at_epoch_72() -> void:
	var main := await _volley(AiActRecorder.EPOCH_72_PLAYTEST_RULES, ["Scourge"])
	assert_int(main.morale_tests).is_equal(0)


## Control: at 73 the same 1 against a weapon without Scourge counts nothing.
func test_plain_ones_do_not_count_at_epoch_73() -> void:
	var main := await _volley(AiActRecorder.EPOCH_73_V36, [])
	assert_int(main.morale_tests).is_equal(0)


## Control: Scourge on a melee strike (range 0) is the melee row's half; the shooting trigger ignores it.
func test_melee_scourge_ones_do_not_reach_the_shooting_trigger() -> void:
	var main := await _volley(AiActRecorder.EPOCH_73_V36, ["Scourge"], 0)
	assert_int(main.morale_tests).is_equal(0)
