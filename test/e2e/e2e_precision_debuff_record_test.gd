extends GdUnitTestSuite
## EPOCH 58 — the Precision Debuff row (precision text sweep 15.09.,
## gf Infected Colonies / Alien Hives, registry numeric in all five maps:
## `Utility Buff | hit_mod: -1, range_in: 18, target: "enemy", once,
## needs_los`). Once per activation, before attacking, the bearer picks ONE
## enemy unit within 18" in line of sight — it gets -1 to hit until the end
## of the round (the book: "gets -1 to hit rolls when attacking once (next
## time the effect would apply)").
##
## Drives the REAL `_solo_apply_utility_buffs` -> `_solo_record_spell_mod` ->
## `_solo_spell_hit_mod` path over main.tscn; the registry map is synthetic
## (RulesRegistry._cache injection, the e2e_defense_buff_record_test.gd
## pattern), the entry byte-identical to rules_mechanics_gf.json. The record
## must land on the ENEMY unit's own store with the registry's `hit_mod: -1`
## (the victim's own next to-hit reads it back), and the rules-must-log line
## must name the applied delta and the victim.

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


## The entry exactly as the book fields it (rules_mechanics_gf.json:1128).
func _inject_registry() -> void:
	RulesRegistry.reset_cache()
	RulesRegistry._cache["gf"] = {"factions": {"infected_colonies": {
		"Precision Debuff": {"primitive": "Utility Buff", "rated": false, "book_version": "3.5.3",
			"params": {"hit_mod": -1, "range_in": 18, "target": "enemy", "once": true,
				"needs_los": true}},
	}}, "common": {}}


func _reg(pid: int, unit_name: String, positions: Array, system: String, faction: String,
		rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
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


# ===== (1) the record lands on the ENEMY unit's own store, hit_mod -1 ==========

func test_the_precision_debuffs_record_lands_on_the_enemy() -> void:
	_inject_registry()
	var giver := _reg(1, "Plague Magus", [Vector3.ZERO], "gf", "infected_colonies",
		["Precision Debuff"])
	var foe := _reg(2, "Stormwind", [Vector3(12.0 * INCH, 0, 0)], "gf", "infected_colonies", [])

	_main._solo_apply_utility_buffs(giver)

	var recs := _records_on(foe)
	assert_int(recs.size()) \
		.override_failure_message("the debuff's record must land on the ENEMY unit — the -1 " +
			"rides the victim's own to-hit net (records: %s)" % str(recs)) \
		.is_equal(1)
	var rec: Dictionary = (recs[0] as Dictionary) if not recs.is_empty() else {}
	assert_int(int(rec.get("hit_mod", 0))) \
		.override_failure_message("the record must carry the registry's own hit_mod=-1 " +
			"(record: %s)" % str(rec)) \
		.is_equal(-1)
	assert_str(str(rec.get("duration", ""))) \
		.override_failure_message("once per activation: the record is spent by the exchange " +
			"that uses it (record: %s)" % str(rec)) \
		.is_equal("once")
	# The victim's OWN next to-hit reads the record back — one worse.
	var hit: Dictionary = _main._solo_spell_hit_mod(foe, false)
	assert_int(int(hit.get("mod", 0))) \
		.override_failure_message("the debuffed enemy's next to-hit target is one worse " +
			"(hit info: %s)" % str(hit)) \
		.is_equal(-1)


# ===== (2) rules-must-log: the line names the delta and the victim =============

func test_the_rules_must_log_line_names_the_delta_and_the_victim() -> void:
	_inject_registry()
	var giver := _reg(1, "Plague Magus", [Vector3.ZERO], "gf", "infected_colonies",
		["Precision Debuff"])
	_reg(2, "Stormwind", [Vector3(12.0 * INCH, 0, 0)], "gf", "infected_colonies", [])

	_main._solo_apply_utility_buffs(giver)

	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log: the debuff's own line must name the -1, " +
			"the victim and the lifetime the book prints (log: %s)" % text.strip_edges()) \
		.contains("Precision Debuff: -1 to hit on Stormwind until end of round")


# ===== (3) the pick refuses beyond the printed 18" =============================

func test_the_pick_refuses_beyond_the_printed_range() -> void:
	_inject_registry()
	var giver := _reg(1, "Plague Magus", [Vector3.ZERO], "gf", "infected_colonies",
		["Precision Debuff"])
	_reg(2, "Stormwind", [Vector3(30.0 * INCH, 0, 0)], "gf", "infected_colonies", [])

	_main._solo_apply_utility_buffs(giver)

	var landed := false
	for u in _main.opr_army_manager.game_units.values():
		if not (_records_on(u) as Array).is_empty():
			landed = true
			break
	assert_bool(landed) \
		.override_failure_message("beyond the printed 18\" no record may land anywhere") \
		.is_false()