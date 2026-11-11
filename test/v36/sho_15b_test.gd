extends GdUnitTestSuite
## Rules 3.6 row SHO-15b, Scourge: every unmodified 1 the defender rolls to block a Scourge MELEE strike
## counts as phantom wounds (the map's phantom_wounds_per_save_one, 2) in the melee-winner tally, against
## the side that rolled it, and nowhere else: nothing is removed. Gated on EPOCH_73_V36; at 72 the tally is
## the real wounds alone, and a plain blade changes nothing at 73. The shooting accumulator of SHO-15a stays
## untouched by a melee batch.


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


func _unit(unit_name: String) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "sho15b_%s" % unit_name
	u.unit_properties = {"player_id": 2, "name": unit_name, "quality": 4, "defense": 4, "special_rules": [],
		"game_system": "gf", "faction_folder": "dwarf_guilds"}
	var m := ModelInstance.new()
	m.is_alive = true
	m.wounds_current = 5
	u.models.append(m)
	return u


## One melee save batch at Defense 4+ with four hits rolls 1, 2, 5, 6 (two blocked, one unmodified 1):
## two real wounds land, and the 1 is worth two phantom wounds at 73.
func _strike(epoch: int, rules: Array) -> Probe:
	AiActRecorder.rules_epoch = epoch
	var main: Probe = auto_free(Probe.new())
	main.battle_log = auto_free(BattleLog.new())
	main.faces = [1, 2, 5, 6]
	var striker := _unit("Striker")
	var defender := _unit("Defender")
	var profile := {"name": "Scourge blade", "range": 0, "attacks": 4, "rules": rules}
	var wounds: int = await main._solo_save_batch(striker, defender, "Scourge blade", 4, 4, 0, profile, false, false)
	assert_int(wounds).override_failure_message("fixture: the batch must leave 2 unsaved").is_equal(2)
	main.set_meta("striker", striker)
	main.set_meta("defender", defender)
	return main


func _log_text(main: Probe) -> String:
	var lines: Array = []
	for e in main.battle_log.entries():
		lines.append(str(e["text"]))
	return "\n".join(lines)


## NEW leg: at 73 the defender's Scourge 1 is two wounds it TOOK, so the tied 1-vs-1 comparison turns
## into a defender loss, the rule names the count, and the shooting accumulator stays empty.
func test_scourge_melee_ones_decide_the_melee_at_epoch_73() -> void:
	var main := await _strike(AiActRecorder.EPOCH_73_V36, ["Scourge"])
	var striker: GameUnit = main.get_meta("striker") as GameUnit
	var defender: GameUnit = main.get_meta("defender") as GameUnit
	var scores: Array = main._solo_melee_scores(striker, 1, defender, 1)
	assert_int(scores[0]).override_failure_message(
		"the defender's phantom wounds must lift the striker's melee tally").is_equal(3)
	assert_int(scores[1]).is_equal(1)
	var loser: GameUnit = main._solo_melee_loser(striker, scores[0], defender, scores[1])
	assert_bool(loser == defender).override_failure_message("the defender took more: it loses").is_true()
	assert_int(main._solo_scourge_wounds).override_failure_message(
		"a melee batch must not feed the shooting morale trigger").is_equal(0)
	main._solo_log_melee_result(striker, 1, scores[0], defender, 1, scores[1])
	assert_str(_log_text(main)).contains("Scourge: 2 phantom wounds count for Defender in the melee result")
	assert_str(_log_text(main)).contains("they decide it")


## OLD leg: at 72 the same 1 counts nothing, the comparison stays a 1-vs-1 draw and the log stays silent.
func test_scourge_melee_ones_do_not_count_at_epoch_72() -> void:
	var main := await _strike(AiActRecorder.EPOCH_72_PLAYTEST_RULES, ["Scourge"])
	var striker: GameUnit = main.get_meta("striker") as GameUnit
	var defender: GameUnit = main.get_meta("defender") as GameUnit
	var scores: Array = main._solo_melee_scores(striker, 1, defender, 1)
	assert_int(scores[0]).is_equal(1)
	assert_int(scores[1]).is_equal(1)
	var loser: GameUnit = main._solo_melee_loser(striker, scores[0], defender, scores[1])
	assert_bool(loser == null).is_true()
	main._solo_log_melee_result(striker, 1, scores[0], defender, 1, scores[1])
	assert_str(_log_text(main)).not_contains("Scourge:")


## Control: at 73 the same 1 against a plain melee blade counts nothing either.
func test_plain_melee_ones_do_not_count_at_epoch_73() -> void:
	var main := await _strike(AiActRecorder.EPOCH_73_V36, [])
	var striker: GameUnit = main.get_meta("striker") as GameUnit
	var defender: GameUnit = main.get_meta("defender") as GameUnit
	var scores: Array = main._solo_melee_scores(striker, 1, defender, 1)
	assert_int(scores[0]).is_equal(1)
	assert_int(scores[1]).is_equal(1)
	main._solo_log_melee_result(striker, 1, scores[0], defender, 1, scores[1])
	assert_str(_log_text(main)).not_contains("Scourge:")
