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


func _log_text(main) -> String:
	var lines: Array = []
	for e in main.battle_log.entries():
		lines.append(str(e["text"]))
	return "\n".join(lines)


## NEW leg — Purge adds its AP(+2) against a Shaken defender on the live save, and the log names it.
func test_purge_ap_reaches_the_live_spell_save_at_epoch_73() -> void:
	var main := await _cast(AiActRecorder.EPOCH_73_V36, ["Purge"], 3, [6, 6, 6], true)
	var text := _log_text(main)
	assert_str(text).override_failure_message(
		"Purge's AP(+2) must move the live spell save from 4+ to 6+ (log: %s)" % text.strip_edges()) \
		.contains("Target saves on 6+")
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


## FAB-C20: a probe that keeps the real `_solo_resolve_saves` and records the save batches instead of
## rolling them, so the on-6 label and the AP number it travels with can be asserted together.
class ProbeLabel extends "res://scripts/main.gd":
	var batches: Array = []

	func _solo_save_batch(_striker: GameUnit, _defender: GameUnit, weapon_name: String, count: int,
			_base_defense: int, ap: int, _profile: Dictionary, _human_defends: bool, _bane: bool,
			_apply_deadly: bool = true, _over9: bool = false, _solo: Dictionary = {},
			_dist_in: float = -1.0, _charge_from_in: float = 0.0, _bane_from: int = 6) -> int:
		batches.append({"name": weapon_name, "count": count, "ap": ap})
		return 0


## One real on-6 save resolution: a plain gun with 3 hits, two of them unmodified 6s.
func _on6_run(epoch: int, rules: Array, faction: String, rending: bool = false,
		destructive: bool = false) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	var main: ProbeLabel = auto_free(ProbeLabel.new())
	main.battle_log = auto_free(BattleLog.new())
	main.solo_ai_slots = {2: true}
	var striker := _unit(1, "Striker", 3)
	striker.unit_properties["faction_folder"] = faction
	var defender := _unit(2, "Guard", 3)
	var profile := {"name": "Gun", "attacks": 3, "ap": 0, "deadly": 0, "range": 12, "rules": rules}
	if rending:
		profile["rending"] = true
	if destructive:
		profile["destructive"] = true
	await main._solo_resolve_saves(striker, defender, "Gun", [6, 6, 1], 3, 4, profile, false, false)
	return {"log": _log_text(main), "batches": main.batches}


## FAB-C20/C-F20: a Fracture carrier's unmodified 6s are labelled Fracture, at the same AP(+2).
func test_fracture_names_itself_on_the_on6_batch() -> void:
	var run := await _on6_run(AiActRecorder.EPOCH_73_V36, ["Fracture"], "dwarf_guilds")
	assert_str(run["log"]).override_failure_message(
		"the on-6 line must name Fracture, not Crack (log: %s)" % run["log"]).contains(
			"Fracture: 2 hits on a 6 → AP(+2)")
	assert_int(run["batches"][0]["ap"]).is_equal(2)
	assert_int(run["batches"][0]["count"]).is_equal(2)


## FAB-C20/C-F20: a Shatter carrier's unmodified 6s are labelled Shatter, at the same AP(+3).
func test_shatter_names_itself_on_the_on6_batch() -> void:
	var run := await _on6_run(AiActRecorder.EPOCH_73_V36, ["Shatter"], "jackals")
	assert_str(run["log"]).override_failure_message(
		"the on-6 line must name Shatter, not Crack (log: %s)" % run["log"]).contains(
			"Shatter: 2 hits on a 6 → AP(+3)")
	assert_int(run["batches"][0]["ap"]).is_equal(3)
	assert_int(run["batches"][0]["count"]).is_equal(2)


## FAB-C20: the literal Crack entry keeps its name and its number.
func test_plain_crack_still_says_crack() -> void:
	var run := await _on6_run(AiActRecorder.EPOCH_73_V36, ["Crack"], "human_defense_force")
	assert_str(run["log"]).contains("Crack: 2 hits on a 6 → AP(+2)")
	assert_int(run["batches"][0]["ap"]).is_equal(2)


## FAB-C20: Rending and Destructive keep their fixed AP(+4) and their own labels.
func test_rending_and_destructive_labels_and_numbers_are_unchanged() -> void:
	var rending := await _on6_run(AiActRecorder.EPOCH_73_V36, [], "dwarf_guilds", true)
	assert_str(rending["log"]).contains("Rending: 2 hits on a 6 → AP(+4)")
	assert_int(rending["batches"][0]["ap"]).is_equal(4)
	var destructive := await _on6_run(AiActRecorder.EPOCH_73_V36, [], "dwarf_guilds", false, true)
	assert_str(destructive["log"]).contains("Destructive: 2 hits on a 6 → AP(+4)")
	assert_int(destructive["batches"][0]["ap"]).is_equal(4)
