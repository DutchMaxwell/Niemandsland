extends GdUnitTestSuite
## Rules 3.6 row FAB-A1: the table's damage-spell resolution applies the same spell tokens the core's
## spell.rs prices. Purge's AP vs a shaken/fatigued defender reaches the live save, Reap's widened
## Bane window reaches the live re-roll, and Scourge's phantom wounds feed the SHOOTING tally. The
## probe drives the real `_solo_resolve_spell_damage` / `_solo_save_batch`; only the dice tray and
## the presentation seams are replaced. Below EPOCH_73_V36 the table stays on the old facets.


class Probe extends "res://scripts/main.gd":
	var faces: Array = []
	var rerolls: Array = []
	var morale_calls := 0
	var last_phantom := 0

	func _solo_tray_roll(_count: int, _target: int, _owner: String, _kind: String = "attack",
			_purpose: String = "") -> Array:
		return faces

	func _owner_roll(_unit: GameUnit, _count: int, _target: int, _kind: String, _purpose: String,
			_ask: Dictionary = {}) -> Array:
		return rerolls

	func _solo_show_outcome(_text: String) -> void:
		pass

	func _solo_shooting_morale(_unit: GameUnit, _alive_before: int, _owner: String,
			_wounds_before: int = -1, _cause: String = "", _over_in: float = -1.0,
			_charge_from_in: float = -1.0) -> void:
		morale_calls += 1
		last_phantom = _solo_scourge_wounds
		_solo_scourge_wounds = 0


var _epoch_before := 0


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RulesRegistry.reset_cache()


func _unit(pid: int, unit_name: String, models: int) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "faba1_%d_%s" % [pid, unit_name]
	u.unit_properties = {"player_id": pid, "name": unit_name, "quality": 4, "defense": 4,
		"special_rules": [], "game_system": "gf", "faction_folder": "dwarf_guilds"}
	for i in models:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = 1
		m.wounds_max = 1
		u.models.append(m)
	return u


func _spell(rules: Array, hits: int) -> Dictionary:
	return {"effect": {"kind": "damage", "hits": hits, "weapon_rules": rules},
		"target": {"kind": "unit", "side": "enemy"}}


## One real cast at `epoch`: the caster and the target are plain Defense 4+ units; the target is
## AI-owned so the save tray is the probe's seam.
func _cast(epoch: int, rules: Array, hits: int, faces: Array, shaken: bool) -> Probe:
	AiActRecorder.rules_epoch = epoch
	var main: Probe = auto_free(Probe.new())
	main.battle_log = auto_free(BattleLog.new())
	main.solo_ai_slots = {2: true}
	main.faces = faces
	main.rerolls = faces
	var caster := _unit(1, "Caster", 1)
	var target := _unit(2, "Target", 3)
	target.is_shaken = shaken
	await main._solo_resolve_spell_damage(caster, caster, "Hex", _spell(rules, hits), target)
	main.set_meta("target", target)
	return main


func _log_text(main: Probe) -> String:
	var lines: Array = []
	for e in main.battle_log.entries():
		lines.append(str(e["text"]))
	return "\n".join(lines)


## NEW leg — Purge adds its AP(+2) against a Shaken defender on the live save, and the log names it.
func test_purge_ap_reaches_the_live_spell_save_at_epoch_73() -> void:
	var main := await _cast(AiActRecorder.EPOCH_73_V36, ["Purge"], 3, [6, 6, 6], true)
	var text := _log_text(main)
	assert_str(text).override_failure_message(
		"Purge's AP(+2) must move the live spell save from Defense 4+ to 2+ (log: %s)" % text.strip_edges()) \
		.contains("Target saves on 2+")
	assert_str(text).override_failure_message("rules-must-log: Purge must be named (log: %s)" % text.strip_edges()) \
		.contains("Purge +2 AP vs Shaken")


## OLD leg — below 73 Purge is not a facet, so the same cast saves at the unbonused Defense 4+.
func test_purge_stays_off_below_epoch_73() -> void:
	var main := await _cast(AiActRecorder.EPOCH_72_PLAYTEST_RULES, ["Purge"], 3, [6, 6, 6], true)
	var text := _log_text(main)
	assert_str(text).contains("Target saves on 4+")
	assert_str(text).not_contains("Purge")


## NEW leg — Reap opens the 5+ Bane window against a Shaken defender on the live save.
func test_reap_widens_the_live_spell_window_at_epoch_73() -> void:
	var main := await _cast(AiActRecorder.EPOCH_73_V36, ["Reap"], 3, [5, 5, 5], true)
	var text := _log_text(main)
	assert_str(text).override_failure_message(
		"Reap must re-roll the successful 5s, not only the sixes (log: %s)" % text.strip_edges()) \
		.contains("of 5+")
	assert_str(text).override_failure_message("rules-must-log: Reap must be named (log: %s)" % text.strip_edges()) \
		.contains("Reap — save window 5+ vs Shaken")


## OLD leg — below 73 Reap is a no-op: no widened window, no line.
func test_reap_stays_off_below_epoch_73() -> void:
	var main := await _cast(AiActRecorder.EPOCH_72_PLAYTEST_RULES, ["Reap"], 3, [5, 5, 5], true)
	var text := _log_text(main)
	assert_str(text).not_contains("of 5+")
	assert_str(text).not_contains("Reap")


## NEW leg — Scourge's phantom wounds from the spell's save batch feed the SHOOTING tally, never melee.
func test_scourge_phantom_wounds_feed_the_shooting_tally_at_epoch_73() -> void:
	var main := await _cast(AiActRecorder.EPOCH_73_V36, ["Scourge"], 4, [1, 2, 5, 6], false)
	assert_int(main.last_phantom).override_failure_message(
		"the spell's Scourge 1 must count toward the shooting morale trigger").is_equal(2)
	assert_int(main._solo_melee_scourge.size()).override_failure_message(
		"a spell's phantom wounds must not enter the melee tally").is_equal(0)


## OLD leg — below 73 Scourge is not read at all: no phantom wound reaches either tally.
func test_scourge_stays_off_below_epoch_73() -> void:
	var main := await _cast(AiActRecorder.EPOCH_72_PLAYTEST_RULES, ["Scourge"], 4, [1, 2, 5, 6], false)
	assert_int(main.last_phantom).is_equal(0)
	assert_int(main._solo_melee_scourge.size()).is_equal(0)
