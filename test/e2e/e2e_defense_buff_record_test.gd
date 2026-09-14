extends GdUnitTestSuite
## STANDALONE_SWEEP_E_2026-09-14, rows `Defense Buff` / `Defense Debuff` — the TABLE
## half of the defense axis, the shared seam.
##
## The registry spells the pair as two rows of ONE knob: the friendly Defense Buff
## carries `def_mod: 1` (aof human_empire), the enemy Defense Debuff carries
## `defense_mod: -1` (gf ratmen_clans). Core parses both spellings and folds them
## onto ONE axis (unit.rs param pair, sim.rs record_buff's widened guard, the
## ledger's `r.def_mod + r.defense_mod`). The table's utility-buff resolver
## (`_solo_apply_utility_buffs`) built its record WITHOUT either key, so the
## all-zero filter in `_solo_record_spell_mod` dropped the row: the player read
## "Defense Buff on X" and nothing changed — the save rung never saw a modifier.
##
## Drives the REAL `_solo_apply_utility_buffs` -> `_solo_record_spell_mod` ->
## `_solo_defense_vs` path over main.tscn; the registry map is synthetic
## (RulesRegistry._cache injection, the e2e_unstoppable_aura_scope_test.gd
## pattern), entries byte-identical to rules_mechanics_aof.json /
## rules_mechanics_gf.json. The debuff's record must land on the ENEMY unit's
## own store — the save rung reads the defender's records, so "record on the
## picked unit" is what puts the debuff on the enemy's Defense.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1


func after_test() -> void:
	RulesRegistry.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## The two entries exactly as the books field them (the sweep row's quote).
func _inject_registry() -> void:
	RulesRegistry.reset_cache()
	RulesRegistry._cache["aof"] = {"factions": {"human_empire": {
		"Defense Buff": {"primitive": "Utility Buff", "rated": false, "book_version": "3.5.3",
			"params": {"def_mod": 1, "target": "friendly", "max_targets": 1, "range_in": 12,
				"once": true}},
	}}, "common": {}}
	RulesRegistry._cache["gf"] = {"factions": {"ratmen_clans": {
		"Defense Debuff": {"primitive": "Utility Buff", "rated": false, "book_version": "3.5.3",
			"params": {"defense_mod": -1, "range_in": 18, "target": "enemy", "once": true,
				"needs_los": true}},
	}}, "common": {}}


func _reg(pid: int, unit_name: String, pos: Vector3, system: String, faction: String,
		rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	u.unit_properties["game_system"] = system
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _records_on(u: GameUnit) -> Array:
	return _main._solo_spell_mods.get(u.get_instance_id(), [])


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


# ===== (1) the RED pin: the buff's record survives the all-zero filter ===========

func test_the_defense_buffs_record_carries_def_mod() -> void:
	_inject_registry()
	var giver := _reg(1, "Marshal", Vector3.ZERO, "aof", "human_empire", ["Defense Buff"])
	var friend := _reg(1, "Line Infantry", Vector3(6.0 * INCH, 0, 0), "aof", "human_empire", [])

	_main._solo_apply_utility_buffs(giver)

	var recs := _records_on(friend)
	assert_int(recs.size()) \
		.override_failure_message("the buff record must survive _solo_record_spell_mod's all-zero " +
			"filter — the defect builds it without def_mod and the row is dropped (records: %s)" % str(recs)) \
		.is_equal(1)
	var rec: Dictionary = (recs[0] as Dictionary) if not recs.is_empty() else {}
	assert_int(int(rec.get("def_mod", 0))) \
		.override_failure_message("the record must carry the entry's def_mod=1 (record: %s)" % str(rec)) \
		.is_equal(1)
	assert_int(_main._solo_defense_vs(friend)) \
		.override_failure_message("the save rung folds the record it now carries: Defense 4+ saves on 3+") \
		.is_equal(3)


# ===== (2) the debuff lands on the ENEMY unit's Defense ==========================

func test_the_defense_debuffs_record_lands_on_the_enemy() -> void:
	_inject_registry()
	var giver := _reg(1, "Plague Priest", Vector3.ZERO, "gf", "ratmen_clans", ["Defense Debuff"])
	var foe := _reg(2, "Stormwind", Vector3(10.0 * INCH, 0, 0), "gf", "ratmen_clans", [])

	_main._solo_apply_utility_buffs(giver)

	var recs := _records_on(foe)
	assert_int(recs.size()) \
		.override_failure_message("the debuff's record must land on the ENEMY unit (the save rung " +
			"reads the defender's own records) and survive the filter (records: %s)" % str(recs)) \
		.is_equal(1)
	var rec: Dictionary = (recs[0] as Dictionary) if not recs.is_empty() else {}
	assert_int(int(rec.get("def_mod", 0))) \
		.override_failure_message("the registry spells the knob defense_mod=-1; core folds both " +
			"spellings onto the ONE defense axis the save rung reads (r.def_mod + r.defense_mod) " +
			"(record: %s)" % str(rec)) \
		.is_equal(-1)
	assert_int(_main._solo_defense_vs(foe)) \
		.override_failure_message("the save rung folds it on the debuffed unit: Defense 4+ saves on 5+") \
		.is_equal(5)


# ===== (3) rules-must-log: the announce line names the applied delta =============

func test_the_announce_line_names_the_delta() -> void:
	_inject_registry()
	var giver := _reg(1, "Marshal", Vector3.ZERO, "aof", "human_empire", ["Defense Buff"])
	_reg(1, "Line Infantry", Vector3(6.0 * INCH, 0, 0), "aof", "human_empire", [])

	_main._solo_apply_utility_buffs(giver)

	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log: the table's own announce line must name the " +
			"applied delta, not just the rule name (log: %s)" % text.strip_edges()) \
		.contains("+1 Defense")
