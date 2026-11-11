extends GdUnitTestSuite
## Rules 3.6 row SHO-14 (lane shoot): a Pierce weapon's saves ignore the target's POSITIVE Defense
## modifiers — Cover, Shielded (and its aliases), Guarded, the Defensive growth ladder and a Defense
## Buff — while Armor, Fortified and a NEGATIVE modifier (Defense Debuff) still apply. Below
## EPOCH_73_V36 nothing changes. The save target recorded here is the number the dice really rolled.

class Probe extends "res://scripts/main.gd":
	var targets: Array = []
	var faces: Array = [2, 2, 2, 2]

	func _solo_tray_roll(_count: int, target: int, _owner: String, _kind: String = "attack",
			_purpose: String = "") -> Array:
		targets.append(target)
		return faces


var _epoch_before := 0


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RulesRegistry.reset_cache()


func _unit(unit_name: String, rules: Array) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "sho14_%s" % unit_name
	u.unit_properties = {"player_id": 2, "name": unit_name, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": "robot_legions"}
	var m := ModelInstance.new()
	m.is_alive = true
	m.wounds_current = 5
	u.models.append(m)
	return u


func _probe() -> Probe:
	var main: Probe = auto_free(Probe.new())
	main.battle_log = auto_free(BattleLog.new())
	return main


## One Pierce shot's save batch at `base_defense` (the caller's already-covered/shielded value).
func _save(main: Probe, epoch: int, defender: GameUnit, weapon_rules: Array, base_defense: int) -> Probe:
	AiActRecorder.rules_epoch = epoch
	var striker := _unit("Striker", [])
	var profile := {"name": "Pierce rifle", "range": 24, "attacks": 4, "rules": weapon_rules}
	var _w: int = await main._solo_resolve_saves(striker, defender, "Pierce rifle", [], 4,
		base_defense, profile, false, false, true, false, 12.0)
	return main


func _log_text(main: Probe) -> String:
	var lines: Array = []
	for e in main.battle_log.entries():
		lines.append(str(e["text"]))
	return "\n".join(lines)


## RED/GREEN: Defense 4+ in cover saves on 3+ with a plain weapon; a Pierce weapon strips it to 4+.
func test_pierce_ignores_cover_at_epoch_73() -> void:
	var main := _probe()
	var defender := _unit("Target", [])
	await _save(main, AiActRecorder.EPOCH_73_V36, defender, ["Pierce"], 3)
	assert_int(int(main.targets[0])) \
		.override_failure_message("Pierce must drop the cover +1: the save rolls at the printed Defense") \
		.is_equal(4)


## Shielded is a positive Defense modifier too, and the line names what was ignored.
func test_pierce_ignores_shielded_at_epoch_73_and_names_it() -> void:
	var main := _probe()
	var defender := _unit("Shielded Target", ["Shielded"])
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var shielded_defense: int = main._solo_defense_vs(defender)
	assert_int(shielded_defense).override_failure_message("fixture: Shielded lowers 4+ to 3+").is_equal(3)
	await _save(main, AiActRecorder.EPOCH_73_V36, defender, ["Pierce"], shielded_defense)
	assert_int(int(main.targets[0])) \
		.override_failure_message("Shielded +1 is ignored by Pierce") \
		.is_equal(4)
	assert_str(_log_text(main)) \
		.override_failure_message("rules-must-log: the line names the ignored Shielded bonus") \
		.contains("Pierce") \
		.contains("Shielded")


## CONTROL: the same covered Defense with a non-Pierce weapon keeps the +1.
func test_a_plain_weapon_keeps_cover_at_epoch_73() -> void:
	var main := _probe()
	var defender := _unit("Target", [])
	await _save(main, AiActRecorder.EPOCH_73_V36, defender, [], 3)
	assert_int(int(main.targets[0])) \
		.override_failure_message("a non-Pierce weapon keeps the target's cover") \
		.is_equal(3)


## A NEGATIVE modifier (Defense Debuff: `def_mod` -1) still applies; a Defense Buff (+1) is dropped.
func test_pierce_keeps_a_negative_defense_modifier_at_epoch_73() -> void:
	var hexed := _unit("Hexed", [])
	var buffed := _unit("Buffed", [])
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var hexed_main := _probe()
	hexed_main._solo_spell_mods[hexed.get_instance_id()] = [{"spell": "Defense Debuff", "def_mod": -1}]
	var hexed_save: int = hexed_main._solo_defense_vs(hexed)
	await _save(hexed_main, AiActRecorder.EPOCH_73_V36, hexed, ["Pierce"], hexed_save)
	assert_int(hexed_save).override_failure_message("fixture: the debuff makes 4+ into 5+").is_equal(5)
	assert_int(int(hexed_main.targets[0])) \
		.override_failure_message("a negative defense modifier still applies against Pierce") \
		.is_equal(5)
	var buffed_main := _probe()
	buffed_main._solo_spell_mods[buffed.get_instance_id()] = [{"spell": "Defense Buff", "def_mod": 1}]
	var buffed_save: int = buffed_main._solo_defense_vs(buffed)
	await _save(buffed_main, AiActRecorder.EPOCH_73_V36, buffed, ["Pierce"], buffed_save)
	assert_int(buffed_save).override_failure_message("fixture: the buff makes 4+ into 3+").is_equal(3)
	assert_int(int(buffed_main.targets[0])) \
		.override_failure_message("a positive Defense Buff is ignored by Pierce") \
		.is_equal(4)


## OLD leg: at 72 the same Pierce weapon counts the cover like every other weapon.
func test_pierce_changes_nothing_at_epoch_72() -> void:
	var main := _probe()
	var defender := _unit("Target", [])
	await _save(main, AiActRecorder.EPOCH_72_PLAYTEST_RULES, defender, ["Pierce"], 3)
	assert_int(int(main.targets[0])) \
		.override_failure_message("below 73 the recorded cover fold stands") \
		.is_equal(3)
